import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'constants.dart';
import 'active_trip_screen.dart';

class CustomerDashboard extends StatefulWidget {
  final String token;
  CustomerDashboard({required this.token});

  @override
  _CustomerDashboardState createState() => _CustomerDashboardState();
}

class _CustomerDashboardState extends State<CustomerDashboard> {
  int _currentIndex = 0;
  final _fromController = TextEditingController();
  final _toController = TextEditingController();
  
  LatLng? pickup;
  LatLng? dropoff;
  int fare = 0;
  final MapController _mapController = MapController();
  
  List _suggestions = []; 
  Timer? _debounce; 

  // --- 1. البحث التلقائي ---
  _searchLocation(String query) async {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      if (query.length < 3) return;
      
      final url = "https://nominatim.openstreetmap.org/search?q=$query, Baghdad, Iraq&format=json&addressdetails=1&limit=5";
      try {
        final res = await http.get(Uri.parse(url), headers: {'User-Agent': 'BaghdadTaxiApp'});
        if (res.statusCode == 200) {
          setState(() => _suggestions = json.decode(res.body));
        }
      } catch (e) { print("Search Error: $e"); }
    });
  }

  // --- 2. تحديد اسم المنطقة ---
  _getAddressFromLatLng(LatLng point, bool isPickup) async {
    final url = "https://nominatim.openstreetmap.org/reverse?lat=${point.latitude}&lon=${point.longitude}&format=json&addressdetails=1";
    try {
      final res = await http.get(Uri.parse(url), headers: {'User-Agent': 'BaghdadTaxiApp'});
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final addr = data['address'];
        
        String neighborhood = addr['neighbourhood'] ?? addr['suburb'] ?? addr['residential'] ?? "منطقة مجهولة";
        String road = addr['road'] ?? "شارع فرعي";
        String finalTitle = "$neighborhood - بالقرب من $road";

        setState(() {
          if (isPickup) {
            _fromController.text = finalTitle;
            pickup = point;
          } else {
            _toController.text = finalTitle;
            dropoff = point;
          }
        });
        _calculateFare();
      }
    } catch (e) { print("Geocoding Error: $e"); }
  }

  _setCurrentLocation() async {
    Position pos = await Geolocator.getCurrentPosition();
    LatLng myLoc = LatLng(pos.latitude, pos.longitude);
    _getAddressFromLatLng(myLoc, true);
    _mapController.move(myLoc, 15);
  }

  _calculateFare() {
    if (pickup != null && dropoff != null) {
      double dist = Geolocator.distanceBetween(
        pickup!.latitude, pickup!.longitude, 
        dropoff!.latitude, dropoff!.longitude
      ) / 1000;
      setState(() => fare = (2000 + (dist * 850)).round());
    }
  }

  _request() async {
    final res = await http.post(
      Uri.parse("$apiBaseUrl/trips/create"), 
      headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'}, 
      body: {
        'pickup_location': _fromController.text, 
        'dropoff_location': _toController.text, 
        'fare': fare.toString(),
        'pickup_lat': pickup!.latitude.toString(), 
        'pickup_long': pickup!.longitude.toString(),
        'dropoff_lat': dropoff!.latitude.toString(), 
        'dropoff_long': dropoff!.longitude.toString(),
      }
    );
    if (res.statusCode == 201) _wait(json.decode(res.body)['id']);
  }

  // --- وظيفة الانتظار مع مهلة دقيقة واحدة ---
  _wait(int id) {
    int secondsElapsed = 0; // عداد الثواني
    bool isDialogActive = true;

    showDialog(
      context: context, 
      barrierDismissible: false, 
      builder: (c) => AlertDialog(
        title: Text("جاري البحث عن كابتن...", textAlign: TextAlign.center), 
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(color: Colors.amber),
            SizedBox(height: 20),
            Text("يرجى الانتظار قليلاً"),
          ],
        )
      )
    );
    
    Timer.periodic(Duration(seconds: 4), (t) async {
      secondsElapsed += 4;

      // 1. تحقق من تخطي الوقت (60 ثانية)
      if (secondsElapsed >= 60) {
        t.cancel();
        if (isDialogActive) {
          Navigator.pop(context); // إغلاق نافذة البحث
          isDialogActive = false;
        }
        _showNoDriverAlert(); // إظهار رسالة الفشل
        return;
      }

      // 2. فحص حالة الطلب من السيرفر
      try {
        final res = await http.get(
          Uri.parse("$apiBaseUrl/trips/$id"), 
          headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'}
        );
        if (res.statusCode == 200) {
          final tripData = json.decode(res.body);
          if (tripData['status'] == 'accepted') {
            t.cancel(); 
            if (isDialogActive) Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (c) => ActiveTripScreen(
              tripId: id, 
              token: widget.token, 
              isDriver: false,
            )));
          }
        }
      } catch (e) { print("Polling Error: $e"); }
    });
  }

  // رسالة عدم العثور على سائق
  _showNoDriverAlert() {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text("عذراً", textAlign: TextAlign.center, style: TextStyle(color: Colors.red)),
        content: Text("لم يتم العثور على سائق متاح الآن. يرجى معاودة الطلب لاحقاً."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text("حسناً"))
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("بغداد تاكسي"), 
        actions: [IconButton(icon: Icon(Icons.logout), onPressed: () => logout(context))]
      ),
      body: Stack(children: [
        _buildMap(),
        _buildSearchOverlay(),
        _buildBottomCard(),
      ]),
    );
  }

  Widget _buildMap() => FlutterMap(
    mapController: _mapController, 
    options: MapOptions(
      initialCenter: LatLng(33.3128, 44.3615), 
      initialZoom: 13, 
      onTap: (p, l) => _getAddressFromLatLng(l, false), 
    ), 
    children: [
      TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
      MarkerLayer(markers: [
        if (pickup != null) Marker(point: pickup!, child: Icon(Icons.person_pin_circle, color: Colors.blue, size: 45)),
        if (dropoff != null) Marker(point: dropoff!, child: Icon(Icons.location_on, color: Colors.red, size: 45)),
      ])
    ]
  );

  Widget _buildSearchOverlay() => Positioned(
    top: 10, left: 15, right: 15,
    child: Column(children: [
      Container(
        decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(10)),
        child: TextField(
          controller: _toController,
          onChanged: _searchLocation,
          style: TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: "إلى أين تريد الذهاب؟",
            hintStyle: TextStyle(color: Colors.white60),
            prefixIcon: Icon(Icons.search, color: Colors.amber),
            border: InputBorder.none,
            contentPadding: EdgeInsets.all(15)
          ),
        ),
      ),
      if (_suggestions.isNotEmpty)
        Container(
          height: 200,
          color: Colors.black.withOpacity(0.9),
          child: ListView.builder(
            itemCount: _suggestions.length,
            itemBuilder: (c, i) {
              final s = _suggestions[i];
              return ListTile(
                title: Text(s['display_name'], style: TextStyle(fontSize: 13, color: Colors.white)),
                onTap: () {
                  setState(() {
                    dropoff = LatLng(double.parse(s['lat']), double.parse(s['lon']));
                    _toController.text = s['display_name'];
                    _suggestions = [];
                  });
                  _mapController.move(dropoff!, 15);
                  _calculateFare();
                },
              );
            },
          ),
        )
    ]),
  );

  Widget _buildBottomCard() => Align(
    alignment: Alignment.bottomCenter,
    child: Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Icon(Icons.my_location, color: Colors.blue),
          SizedBox(width: 10),
          Expanded(child: TextField(
            controller: _fromController, 
            style: TextStyle(color: Colors.white),
            decoration: InputDecoration(hintText: "موقع الانطلاق", hintStyle: TextStyle(color: Colors.white60)),
          )),
          IconButton(icon: Icon(Icons.gps_fixed, color: Colors.amber), onPressed: _setCurrentLocation)
        ]),
        if (fare > 0) Padding(
          padding: const EdgeInsets.symmetric(vertical: 15), 
          child: Text("السعر التقديري: $fare د.ع", style: TextStyle(fontSize: 22, color: Colors.amber, fontWeight: FontWeight.bold))
        ),
        ElevatedButton(
          onPressed: (pickup != null && dropoff != null) ? _request : null, 
          child: Text("اطلب الآن", style: TextStyle(fontSize: 18)), 
          style: ElevatedButton.styleFrom(
            minimumSize: Size(double.infinity, 55), 
            backgroundColor: Colors.amber, 
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
          )
        )
      ]),
    ),
  );
}