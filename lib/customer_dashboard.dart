import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'constants.dart';
import 'active_trip_screen1.dart';

class CustomerDashboard extends StatefulWidget {
  final String token;
  CustomerDashboard({required this.token});

  @override
  _CustomerDashboardState createState() => _CustomerDashboardState();
}

class _CustomerDashboardState extends State<CustomerDashboard> {
  final _fromController = TextEditingController();
  final _toController = TextEditingController();
  
  LatLng? pickup;
  LatLng? dropoff;
  int fare = 0;
  final MapController _mapController = MapController();
  
  List _suggestions = []; 
  Timer? _debounce; 

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setCurrentLocation();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _fromController.dispose();
    _toController.dispose();
    super.dispose();
  }

  _searchLocation(String query) async {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      if (query.length < 3) return;
      final url = "https://nominatim.openstreetmap.org/search?q=$query, Baghdad, Iraq&format=json&addressdetails=1&limit=5";
      try {
        final res = await http.get(Uri.parse(url), headers: {'User-Agent': 'BaghdadTaxiApp'});
        if (res.statusCode == 200 && mounted) {
          setState(() => _suggestions = json.decode(res.body));
        }
      } catch (e) { print("Search Error: $e"); }
    });
  }

  _getAddressFromLatLng(LatLng point, bool isPickup) async {
    final url = "https://nominatim.openstreetmap.org/reverse?lat=${point.latitude}&lon=${point.longitude}&format=json&addressdetails=1";
    try {
      final res = await http.get(Uri.parse(url), headers: {'User-Agent': 'BaghdadTaxiApp'});
      if (res.statusCode == 200 && mounted) {
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
    try {
      Position pos = await Geolocator.getCurrentPosition();
      LatLng myLoc = LatLng(pos.latitude, pos.longitude);
      _getAddressFromLatLng(myLoc, true);
      if (mounted) {
        try { _mapController.move(myLoc, 15); } catch (e) {}
      }
    } catch (e) { print("Location Error: $e"); }
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
    try {
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
      if (res.statusCode == 201) {
        _wait(json.decode(res.body)['id']);
      }
    } catch (e) {
      print("Request Error: $e");
    }
  }

  // --- دالة الانتظار المحدثة مع طلب الحذف التلقائي ---
  _wait(int id) {
    int secondsElapsed = 0; 
    bool isDialogActive = true;
    Timer? pollingTimer;

    showDialog(
      context: context, 
      barrierDismissible: false, 
      builder: (c) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text("جاري البحث عن كابتن...", textAlign: TextAlign.center, style: TextStyle(color: Colors.amber)), 
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(color: Colors.amber, backgroundColor: Colors.white24),
            SizedBox(height: 20),
            Text("يرجى الانتظار، السائقون القريبون يتلقون طلبك", textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
          ],
        )
      )
    );
    
    pollingTimer = Timer.periodic(Duration(seconds: 4), (t) async {
      secondsElapsed += 4;

      if (!mounted) { t.cancel(); return; }

      // 1. في حال تخطي الدقيقة: نطلب من السيرفر حذف الرحلة فوراً
      if (secondsElapsed >= 60) {
        t.cancel();
        if (isDialogActive) {
          Navigator.of(context, rootNavigator: true).pop(); // إغلاق الديالوج
          isDialogActive = false;
        }
        _cancelTripOnServer(id); // استدعاء API الحذف
        return;
      }

      // 2. فحص حالة الطلب من السيرفر
      try {
        final res = await http.get(
          Uri.parse("$apiBaseUrl/trips/$id"), 
          headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'}
        );
        if (res.statusCode == 200 && mounted) {
          final tripData = json.decode(res.body);
          if (tripData['status'] == 'accepted') {
            t.cancel(); 
            if (isDialogActive) {
              Navigator.of(context, rootNavigator: true).pop();
              isDialogActive = false;
            }

            Future.delayed(Duration(milliseconds: 200), () {
              if (mounted) {
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => ActiveTripScreen(
                  tripId: id, 
                  token: widget.token, 
                  isDriver: false,
                )));
              }
            });
          }
        }
      } catch (e) { print("Polling Error: $e"); }
    });
  }

  // دالة إبلاغ السيرفر بإلغاء الرحلة بسبب انتهاء وقت الانتظار
  void _cancelTripOnServer(int id) async {
    try {
      await http.delete(
        Uri.parse("$apiBaseUrl/trips/$id/timeout-cancel"),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json'
        },
      );
      _showNoDriverAlert(); 
    } catch (e) {
      print("Delete Trip Error: $e");
    }
  }

  _showNoDriverAlert() {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text("نعتذر منك", textAlign: TextAlign.center, style: TextStyle(color: Colors.redAccent)),
        content: Text("لم يتم العثور على سائق متاح حالياً. تم إلغاء الطلب تلقائياً، يمكنك المحاولة مرة أخرى.", 
          textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text("حسناً", style: TextStyle(color: Colors.amber)))
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text("بغداد تاكسي", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)), 
        backgroundColor: Colors.black,
        elevation: 0,
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
        decoration: BoxDecoration(color: Colors.black.withOpacity(0.8), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.amber.withOpacity(0.5))),
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
          margin: EdgeInsets.only(top: 5),
          decoration: BoxDecoration(color: Colors.black.withOpacity(0.9), borderRadius: BorderRadius.circular(10)),
          constraints: BoxConstraints(maxHeight: 200),
          child: ListView.builder(
            shrinkWrap: true,
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 10)]
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Icon(Icons.my_location, color: Colors.blue),
          SizedBox(width: 10),
          Expanded(child: TextField(
            controller: _fromController, 
            style: TextStyle(color: Colors.white),
            decoration: InputDecoration(hintText: "موقع الانطلاق", hintStyle: TextStyle(color: Colors.white60), border: InputBorder.none),
          )),
          IconButton(icon: Icon(Icons.gps_fixed, color: Colors.amber), onPressed: _setCurrentLocation)
        ]),
        Divider(color: Colors.white10),
        if (fare > 0) Padding(
          padding: const EdgeInsets.symmetric(vertical: 10), 
          child: Text("السعر التقديري: $fare د.ع", style: TextStyle(fontSize: 22, color: Colors.amber, fontWeight: FontWeight.bold))
        ),
        SizedBox(height: 10),
        ElevatedButton(
          onPressed: (pickup != null && dropoff != null) ? _request : null, 
          child: Text("اطلب الآن", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), 
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