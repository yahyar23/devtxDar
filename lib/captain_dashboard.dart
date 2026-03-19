import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'constants.dart'; // للتواصل مع apiBaseUrl و logout
import 'active_trip_screen.dart'; // للانتقال لشاشة الرحلة عند القبول

class CaptainDashboard extends StatefulWidget {
  final String token;
  CaptainDashboard({required this.token});

  @override
  _CaptainDashboardState createState() => _CaptainDashboardState();
}

class _CaptainDashboardState extends State<CaptainDashboard> {
  int _currentIndex = 0;
  bool isOnline = false;
  Map? currentTrip;
  double balance = 0.0;
  LatLng myPos = LatLng(33.3128, 44.3615); 
  final MapController _mapController = MapController();
  final _codeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkBalance();
    _updateLocation();
    // فحص الرحلات المتاحة كل 5 ثوانٍ إذا كان السائق متصلاً
    Timer.periodic(Duration(seconds: 5), (t) { if (mounted) _fetchTrips(); });
  }

  // --- وظائف البيانات (Logic) ---

  _checkBalance() async {
    try {
      final res = await http.get(
        Uri.parse("$apiBaseUrl/driver/balance"), 
        headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'}
      );
      if (res.statusCode == 200) setState(() => balance = double.tryParse(json.decode(res.body)['balance'].toString()) ?? 0.0);
    } catch (e) { print("Balance Error: $e"); }
  }

  _recharge() async {
    if (_codeController.text.isEmpty) return;
    final res = await http.post(
      Uri.parse("$apiBaseUrl/driver/recharge"), 
      headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'},
      body: {'code': _codeController.text}
    );
    if (res.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("تم شحن الرصيد بنجاح")));
      _codeController.clear();
      _checkBalance();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("كود غير صالح")));
    }
  }

  _updateLocation() async {
    LocationPermission permission = await Geolocator.requestPermission();
    if (permission != LocationPermission.denied) {
      Position pos = await Geolocator.getCurrentPosition();
      setState(() => myPos = LatLng(pos.latitude, pos.longitude));
      _mapController.move(myPos, 15);
    }
  }

  _fetchTrips() async {
    if (!isOnline || currentTrip != null) return;
    try {
      final res = await http.get(
        Uri.parse("$apiBaseUrl/trips/available"), 
        headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'}
      );
      if (res.statusCode == 200) {
        List trips = json.decode(res.body);
        if (trips.isNotEmpty) setState(() => currentTrip = trips[0]);
      }
    } catch (e) { print("Fetch Error: $e"); }
  }

  // --- واجهة المستخدم (UI) ---

  @override
  Widget build(BuildContext context) {
    List<Widget> _pages = [
      _buildHome(),
      _buildWallet(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_currentIndex == 0 ? "لوحة الكابتن" : "المحفظة"),
        actions: [IconButton(icon: Icon(Icons.logout), onPressed: () => logout(context))],
      ),
      body: _pages[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: [
          NavigationDestination(icon: Icon(Icons.map), label: "الرئيسية"),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet), label: "رصيدي"),
        ],
      ),
    );
  }

  // شاشة الخريطة والطلبات
  Widget _buildHome() => Stack(children: [
    FlutterMap(
      mapController: _mapController, 
      options: MapOptions(initialCenter: myPos, initialZoom: 15), 
      children: [
        TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
        MarkerLayer(markers: [
          Marker(point: myPos, child: Icon(Icons.local_taxi, color: Colors.amber, size: 40))
        ])
      ]
    ),
    Positioned(top: 10, right: 10, child: Column(children: [
      FloatingActionButton(onPressed: _updateLocation, child: Icon(Icons.my_location), mini: true),
      SizedBox(height: 10),
      Switch(value: isOnline, onChanged: (v) => setState(() => isOnline = v), activeColor: Colors.green),
    ])),
    if (currentTrip != null) _buildTripRequest(),
  ]);

  // واجهة المحفظة
  Widget _buildWallet() => Padding(
    padding: EdgeInsets.all(20),
    child: Column(children: [
      Card(
        color: Colors.amber.withOpacity(0.1),
        child: ListTile(
          title: Text("رصيدك الحالي"),
          trailing: Text("${balance.toInt()} د.ع", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: balance < 0 ? Colors.red : Colors.green)),
          subtitle: Text("العمولة المقتطعة: 10% لكل رحلة"),
        ),
      ),
      SizedBox(height: 30),
      TextField(controller: _codeController, decoration: InputDecoration(labelText: "أدخل كود الشحن", border: OutlineInputBorder())),
      SizedBox(height: 15),
      ElevatedButton(
        onPressed: _recharge, 
        child: Text("تفعيل الكود"), 
        style: ElevatedButton.styleFrom(minimumSize: Size(double.infinity, 50), backgroundColor: Colors.amber, foregroundColor: Colors.black)
      )
    ]),
  );

  // نافذة طلب الرحلة المنبثقة
  Widget _buildTripRequest() => Align(alignment: Alignment.bottomCenter, child: Container(
    margin: EdgeInsets.all(15), 
    padding: EdgeInsets.all(20), 
    decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.amber)),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text("طلب رحلة جديد", style: TextStyle(color: Colors.amber, fontSize: 18)),
      Text("من: ${currentTrip!['pickup_location'] ?? 'غير محدد'}", style: TextStyle(color: Colors.white)),
      Text("السعر التقديري: ${currentTrip!['fare'] ?? '0'} د.ع", style: TextStyle(color: Colors.white70)),
      SizedBox(height: 10),
      ElevatedButton(
        onPressed: () async {
          final res = await http.post(
            Uri.parse("$apiBaseUrl/trips/${currentTrip!['id']}/accept"), 
            headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'}
          );
          if (res.statusCode == 200) {
            int tid = currentTrip!['id'];
            setState(() => currentTrip = null);
            Navigator.push(context, MaterialPageRoute(builder: (c) => ActiveTripScreen(tripId: tid, token: widget.token, isDriver: true)));
          }
        }, 
        child: Text("قبول الرحلة"),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white)
      )
    ]),
  ));
}