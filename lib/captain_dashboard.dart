import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart'; 
import 'constants.dart';
import 'active_trip_screen.dart';

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
  
  Timer? _fetchTimer;
  Timer? _tripTimeoutTimer;
  int _secondsRemaining = 20;

  @override
  void initState() {
    super.initState();
    _checkBalance();
    _updateLocation();
    // فحص الرحلات كل 5 ثوانٍ بشرط أن يكون السائق متصل (Online) ولا توجد رحلة حالية
    _fetchTimer = Timer.periodic(Duration(seconds: 5), (t) {
      if (mounted && isOnline && currentTrip == null) _fetchTrips();
    });
  }

  @override
  void dispose() {
    _fetchTimer?.cancel();
    _tripTimeoutTimer?.cancel();
    super.dispose();
  }

  // --- وظائف المنطق (Logic) ---

  _fetchTrips() async {
    try {
      // تأكد أن المسار مطابق للباك اند (trips/available)
      final res = await http.get(
        Uri.parse("$apiBaseUrl/trips/available"),
        headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'}
      );
      if (res.statusCode == 200) {
        List trips = json.decode(res.body);
        if (trips.isNotEmpty && currentTrip == null) {
          setState(() {
            currentTrip = trips[0];
            _secondsRemaining = 20;
          });
          _startTripTimer();
        }
      }
    } catch (e) { print("Fetch Error: $e"); }
  }

  _startTripTimer() {
    _tripTimeoutTimer?.cancel();
    _tripTimeoutTimer = Timer.periodic(Duration(seconds: 1), (t) {
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
      } else {
        _ignoreTrip();
      }
    });
  }

  _ignoreTrip() {
    _tripTimeoutTimer?.cancel();
    setState(() => currentTrip = null);
  }

  _acceptTrip() async {
    try {
      final res = await http.post(
          Uri.parse("$apiBaseUrl/trips/${currentTrip!['id']}/accept"),
          headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'}
      );
      if (res.statusCode == 200) {
        int tid = currentTrip!['id'];
        _tripTimeoutTimer?.cancel();
        setState(() => currentTrip = null);
        Navigator.push(context, MaterialPageRoute(builder: (c) => ActiveTripScreen(tripId: tid, token: widget.token, isDriver: true)));
      }
    } catch (e) { print("Accept Error: $e"); }
  }

  _openMaps(double lat, double lng) async {
    final Uri url = Uri.parse("google.navigation:q=$lat,$lng&mode=d");
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("لا يمكن فتح خرائط جوجل")));
    }
  }

  _updateLocation() async {
    Position pos = await Geolocator.getCurrentPosition();
    setState(() => myPos = LatLng(pos.latitude, pos.longitude));
    _mapController.move(myPos, 15);
  }

  _checkBalance() async {
    try {
      final res = await http.get(Uri.parse("$apiBaseUrl/driver/balance"), headers: {'Authorization': 'Bearer ${widget.token}'});
      if (res.statusCode == 200) setState(() => balance = double.tryParse(json.decode(res.body)['balance'].toString()) ?? 0.0);
    } catch (e) {}
  }

  // --- الواجهات (UI) ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentIndex == 0 ? "لوحة الكابتن" : "المحفظة"),
        actions: [IconButton(icon: Icon(Icons.logout), onPressed: () => logout(context))],
      ),
      body: _currentIndex == 0 ? _buildHome() : Center(child: Text("الرصيد: $balance د.ع")),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: [
          NavigationDestination(icon: Icon(Icons.map), label: "الرئيسية"),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet), label: "المحفظة"),
        ],
      ),
    );
  }

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
    if (currentTrip != null) _buildTripRequestPopup(),
  ]);

  Widget _buildTripRequestPopup() => Align(
    alignment: Alignment.bottomCenter,
    child: Container(
      margin: EdgeInsets.all(15),
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.95),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.amber, width: 2)
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text("طلب رحلة جديد", style: TextStyle(color: Colors.amber, fontSize: 18, fontWeight: FontWeight.bold)),
          CircleAvatar(backgroundColor: Colors.red, child: Text("$_secondsRemaining", style: TextStyle(color: Colors.white))),
        ]),
        SizedBox(height: 15),
        _locationTile(Icons.circle, Colors.green, "من: ${currentTrip!['pickup_location']}", currentTrip!['pickup_lat'], currentTrip!['pickup_long']),
        _locationTile(Icons.location_on, Colors.red, "إلى: ${currentTrip!['dropoff_location']}", currentTrip!['dropoff_lat'], currentTrip!['dropoff_long']),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 15),
          child: Text("الأجرة: ${currentTrip!['fare']} د.ع", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
        ),
        Row(children: [
          Expanded(child: TextButton(onPressed: _ignoreTrip, child: Text("تجاهل", style: TextStyle(color: Colors.red)))),
          Expanded(
            flex: 2,
            child: GestureDetector(
              onLongPress: _acceptTrip,
              child: Container(
                height: 55,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(15)),
                child: Text("اضغط مطولاً للقبول", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
          ),
        ])
      ]),
    ),
  );

  Widget _locationTile(IconData icon, Color color, String text, dynamic lat, dynamic lng) => ListTile(
    leading: Icon(icon, color: color, size: 20),
    title: Text(text, style: TextStyle(color: Colors.white, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
    trailing: IconButton(
      icon: Icon(Icons.directions, color: Colors.blue),
      onPressed: () => _openMaps(double.parse(lat.toString()), double.parse(lng.toString())),
    ),
    contentPadding: EdgeInsets.zero,
  );
}