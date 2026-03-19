import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'constants.dart'; // للوصول إلى apiBaseUrl و logout
import 'active_trip_screen.dart'; // للانتقال لشاشة الرحلة عند قبولها

class CustomerDashboard extends StatefulWidget {
  final String token;
  CustomerDashboard({required this.token});

  @override
  _CustomerDashboardState createState() => _CustomerDashboardState();
}

class _CustomerDashboardState extends State<CustomerDashboard> {
  int _currentIndex = 0;
  final _from = TextEditingController();
  LatLng? pickup;
  LatLng? dropoff;
  int fare = 0;
  final MapController _mapController = MapController();

  // --- وظائف البيانات (Logic) ---

  _setCurrentLocation() async {
    Position pos = await Geolocator.getCurrentPosition();
    setState(() { 
      pickup = LatLng(pos.latitude, pos.longitude); 
      _from.text = "موقعي الحالي"; 
    });
    _mapController.move(pickup!, 15);
  }

  _calculateFare() {
    if (pickup != null && dropoff != null) {
      double dist = Geolocator.distanceBetween(
        pickup!.latitude, pickup!.longitude, 
        dropoff!.latitude, dropoff!.longitude
      ) / 1000;
      // معادلة السعر: 2000 فتح عداد + 750 لكل كيلومتر
      setState(() => fare = (2000 + (dist * 750)).round());
    }
  }

  _request() async {
    final res = await http.post(
      Uri.parse("$apiBaseUrl/trips/create"), 
      headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'}, 
      body: {
        'pickup_location': _from.text, 
        'dropoff_location': 'الوجهة المحددة على الخريطة', 
        'fare': fare.toString(),
        'pickup_lat': pickup!.latitude.toString(), 
        'pickup_long': pickup!.longitude.toString(),
        'dropoff_lat': dropoff!.latitude.toString(), 
        'dropoff_long': dropoff!.longitude.toString(),
      }
    );
    if (res.statusCode == 201) _wait(json.decode(res.body)['id']);
  }

  _wait(int id) {
    showDialog(
      context: context, 
      barrierDismissible: false, 
      builder: (c) => AlertDialog(
        title: Text("جاري البحث عن كابتن..."), 
        content: LinearProgressIndicator()
      )
    );
    
    // فحص حالة الطلب كل 4 ثوانٍ حتى يتم القبول
    Timer.periodic(Duration(seconds: 4), (t) async {
      final res = await http.get(
        Uri.parse("$apiBaseUrl/trips/$id"), 
        headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'}
      );
      if (res.statusCode == 200 && json.decode(res.body)['status'] == 'accepted') {
        t.cancel(); 
        Navigator.pop(context); // إغلاق نافذة الانتظار
        Navigator.push(context, MaterialPageRoute(builder: (c) => ActiveTripScreen(tripId: id, token: widget.token, isDriver: false)));
      }
    });
  }

  // --- واجهة المستخدم (UI) ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("بغداد تاكسي"), 
        actions: [IconButton(icon: Icon(Icons.logout), onPressed: () => logout(context))]
      ),
      body: _currentIndex == 0 ? _buildRequestPage() : Center(child: Text("سجل الرحلات قيد التطوير")),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: [
          NavigationDestination(icon: Icon(Icons.local_taxi), label: "طلب رحلة"),
          NavigationDestination(icon: Icon(Icons.history), label: "رحلاتي"),
        ],
      ),
    );
  }

  Widget _buildRequestPage() => Column(children: [
    Expanded(child: Stack(children: [
      FlutterMap(
        mapController: _mapController, 
        options: MapOptions(
          initialCenter: LatLng(33.3128, 44.3615), 
          initialZoom: 13, 
          onTap: (p, l) {
            setState(() => dropoff = l); 
            _calculateFare();
          }
        ), 
        children: [
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
          MarkerLayer(markers: [
            if (pickup != null) Marker(point: pickup!, child: Icon(Icons.person_pin_circle, color: Colors.blue, size: 40)),
            if (dropoff != null) Marker(point: dropoff!, child: Icon(Icons.location_on, color: Colors.red, size: 40)),
          ])
        ]
      ),
      Positioned(top: 10, right: 10, child: FloatingActionButton(onPressed: _setCurrentLocation, child: Icon(Icons.my_location), mini: true))
    ])),
    Container(
      padding: EdgeInsets.all(20), 
      decoration: BoxDecoration(color: Colors.grey[900]), 
      child: Column(children: [
        TextField(controller: _from, decoration: InputDecoration(hintText: "موقع الانطلاق")),
        TextField(
          decoration: InputDecoration(
            hintText: dropoff == null ? "اضغط الخريطة لتحديد الوجهة" : "تم تحديد الوجهة بنجاح", 
            enabled: false
          )
        ),
        if (fare > 0) Padding(
          padding: const EdgeInsets.symmetric(vertical: 10), 
          child: Text("السعر التقديري: $fare د.ع", style: TextStyle(fontSize: 20, color: Colors.amber, fontWeight: FontWeight.bold))
        ),
        ElevatedButton(
          onPressed: fare > 0 ? _request : null, 
          child: Text("تأكيد الطلب"), 
          style: ElevatedButton.styleFrom(minimumSize: Size(double.infinity, 50), backgroundColor: Colors.amber, foregroundColor: Colors.black)
        )
      ])
    )
  ]);
}