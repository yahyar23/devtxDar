import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

// ملاحظة: تأكد من تغيير localhost إلى IP جهازك إذا كنت تفحص من موبايل حقيقي
const String apiBaseUrl = "http://localhost/my-taxi-project/public/api";

void main() => runApp(TaxiApp());

class TaxiApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'بغداد تاكسي',
      theme: ThemeData(brightness: Brightness.dark, colorSchemeSeed: Colors.amber, useMaterial3: true),
      home: SplashScreen(),
    );
  }
}

// --- 0. شاشة الفحص ---
class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() { super.initState(); _checkStatus(); }
  _checkStatus() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('token');
    String? role = prefs.getString('role');
    await Future.delayed(Duration(seconds: 2));
    if (token != null && role != null) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => 
        role == 'driver' ? CaptainDashboard(token: token) : CustomerDashboard(token: token)));
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => WelcomeScreen()));
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: Icon(Icons.local_taxi, size: 100, color: Colors.amber)));
}

// --- 1. شاشة الترحيب ---
class WelcomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(Icons.local_taxi, size: 120, color: Colors.amber),
    Text("بغداد تاكسي", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
    SizedBox(height: 40),
    _btn(context, "أنا زبون", Colors.white, () => _go(context, false)),
    SizedBox(height: 20),
    _btn(context, "أنا كابتن", Colors.amber, () => _go(context, true)),
  ])));
  _go(context, isDriver) => Navigator.push(context, MaterialPageRoute(builder: (c) => LoginScreen(isDriver: isDriver)));
  _btn(context, txt, col, tap) => ElevatedButton(onPressed: tap, child: Text(txt), style: ElevatedButton.styleFrom(backgroundColor: col, foregroundColor: Colors.black, minimumSize: Size(250, 60)));
}

// --- 2. شاشة تسجيل الدخول ---
class LoginScreen extends StatefulWidget {
  final bool isDriver;
  LoginScreen({required this.isDriver});
  @override
  _LoginScreenState createState() => _LoginScreenState();
}
class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController();
  final _pass = TextEditingController();
  _login() async {
    try {
      final res = await http.post(Uri.parse("$apiBaseUrl/login"), body: {'phone': _phone.text, 'password': _pass.text});
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['token']);
        await prefs.setString('role', data['user']['role']);
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (c) => 
          data['user']['role'] == 'driver' ? CaptainDashboard(token: data['token']) : CustomerDashboard(token: data['token'])), (r) => false);
      }
    } catch (e) { print("Login Error: $e"); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(), body: Padding(padding: EdgeInsets.all(20), child: Column(children: [
    TextField(controller: _phone, decoration: InputDecoration(labelText: "رقم الهاتف"), keyboardType: TextInputType.phone),
    TextField(controller: _pass, obscureText: true, decoration: InputDecoration(labelText: "كلمة السر")),
    SizedBox(height: 20),
    ElevatedButton(onPressed: _login, child: Text("دخول"), style: ElevatedButton.styleFrom(minimumSize: Size(double.infinity, 50), backgroundColor: Colors.amber))
  ])));
}

// --- 3. لوحة الكابتن ---
class CaptainDashboard extends StatefulWidget {
  final String token;
  CaptainDashboard({required this.token});
  @override
  _CaptainDashboardState createState() => _CaptainDashboardState();
}

class _CaptainDashboardState extends State<CaptainDashboard> {
  bool isOnline = false;
  Map? currentTrip;
  double balance = 0.0;
  LatLng myPos = LatLng(33.3128, 44.3615); 
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _checkBalance();
    _updateLocation();
    Timer.periodic(Duration(seconds: 5), (t) => _fetchTrips());
  }

  _checkBalance() async {
    try {
      // تصحيح الرابط من balnce إلى balance
      final res = await http.get(Uri.parse("$apiBaseUrl/driver/balance"), headers: {'Authorization': 'Bearer ${widget.token}'});
      if (res.statusCode == 200) {
        setState(() => balance = double.tryParse(json.decode(res.body)['balance'].toString()) ?? 0.0);
      }
    } catch (e) { print("Balance Error: $e"); }
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
    final res = await http.get(Uri.parse("$apiBaseUrl/trips/available"), headers: {'Authorization': 'Bearer ${widget.token}'});
    if (res.statusCode == 200) {
      List trips = json.decode(res.body);
      if (trips.isNotEmpty) setState(() => currentTrip = trips[0]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("الرصيد: ${balance.toInt()} د.ع"), actions: [
        Switch(value: isOnline, onChanged: (v) => setState(() => isOnline = v))
      ]),
      body: Stack(children: [
        FlutterMap(mapController: _mapController, options: MapOptions(initialCenter: myPos, initialZoom: 15), children: [
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
          MarkerLayer(markers: [Marker(point: myPos, child: Icon(Icons.local_taxi, color: Colors.amber, size: 40))])
        ]),
        Positioned(bottom: 120, right: 20, child: FloatingActionButton(onPressed: _updateLocation, child: Icon(Icons.my_location), mini: true)),
        if (currentTrip != null) _buildTripRequest(),
      ]),
    );
  }

  Widget _buildTripRequest() => Align(alignment: Alignment.bottomCenter, child: Container(
    margin: EdgeInsets.all(15), padding: EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.amber)),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text("طلب رحلة جديد", style: TextStyle(color: Colors.amber, fontSize: 18)),
      Text("من: ${currentTrip!['pickup_location'] ?? 'غير محدد'}"),
      Text("السعر: ${currentTrip!['fare'] ?? '0'} د.ع"),
      SizedBox(height: 10),
      ElevatedButton(onPressed: () async {
        final res = await http.post(Uri.parse("$apiBaseUrl/trips/${currentTrip!['id']}/accept"), headers: {'Authorization': 'Bearer ${widget.token}'});
        if (res.statusCode == 200) {
          int tid = currentTrip!['id'];
          setState(() => currentTrip = null);
          Navigator.push(context, MaterialPageRoute(builder: (c) => ActiveTripScreen(tripId: tid, token: widget.token, isDriver: true)));
        }
      }, child: Text("قبول الرحلة"))
    ]),
  ));
}

// --- 4. لوحة الزبون ---
class CustomerDashboard extends StatefulWidget {
  final String token;
  CustomerDashboard({required this.token});
  @override
  _CustomerDashboardState createState() => _CustomerDashboardState();
}

class _CustomerDashboardState extends State<CustomerDashboard> {
  final _from = TextEditingController();
  final _to = TextEditingController();
  LatLng? pickup;
  LatLng? dropoff;
  int fare = 0;
  final MapController _mapController = MapController();

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
      double dist = Geolocator.distanceBetween(pickup!.latitude, pickup!.longitude, dropoff!.latitude, dropoff!.longitude) / 1000;
      setState(() => fare = (2000 + (dist * 750)).round());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(children: [
        Expanded(child: Stack(children: [
          FlutterMap(mapController: _mapController, options: MapOptions(initialCenter: LatLng(33.3128, 44.3615), initialZoom: 13, onTap: (p, l) {
            setState(() => dropoff = l);
            _calculateFare();
          }), children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
            MarkerLayer(markers: [
              if (pickup != null) Marker(point: pickup!, child: Icon(Icons.person_pin_circle, color: Colors.blue, size: 40)),
              if (dropoff != null) Marker(point: dropoff!, child: Icon(Icons.location_on, color: Colors.red, size: 40)),
            ])
          ]),
          Positioned(top: 50, right: 20, child: FloatingActionButton(onPressed: _setCurrentLocation, child: Icon(Icons.my_location), mini: true))
        ])),
        Container(padding: EdgeInsets.all(20), child: Column(children: [
          TextField(controller: _from, decoration: InputDecoration(hintText: "موقع الانطلاق")),
          TextField(controller: _to, decoration: InputDecoration(hintText: "اضغط الخريطة لتحديد الوجهة")),
          if (fare > 0) Text("السعر: $fare د.ع", style: TextStyle(fontSize: 20, color: Colors.amber)),
          ElevatedButton(onPressed: fare > 0 ? _request : null, child: Text("تأكيد الطلب"), style: ElevatedButton.styleFrom(minimumSize: Size(double.infinity, 50), backgroundColor: Colors.amber, foregroundColor: Colors.black))
        ]))
      ]),
    );
  }

  _request() async {
    final res = await http.post(Uri.parse("$apiBaseUrl/trips/create"), headers: {'Authorization': 'Bearer ${widget.token}'}, body: {
      'pickup_location': _from.text, 'dropoff_location': 'وجهة محددة', 'fare': fare.toString(),
      'pickup_lat': pickup!.latitude.toString(), 'pickup_long': pickup!.longitude.toString(),
      'dropoff_lat': dropoff!.latitude.toString(), 'dropoff_long': dropoff!.longitude.toString(),
    });
    if (res.statusCode == 201) {
       _wait(json.decode(res.body)['id']);
    }
  }

  _wait(int id) {
    showDialog(context: context, barrierDismissible: false, builder: (c) => AlertDialog(title: Text("جاري البحث..."), content: LinearProgressIndicator()));
    Timer.periodic(Duration(seconds: 4), (t) async {
      final res = await http.get(Uri.parse("$apiBaseUrl/trips/$id"), headers: {'Authorization': 'Bearer ${widget.token}'});
      if (json.decode(res.body)['status'] == 'accepted') {
        t.cancel(); Navigator.pop(context);
        Navigator.push(context, MaterialPageRoute(builder: (c) => ActiveTripScreen(tripId: id, token: widget.token, isDriver: false)));
      }
    });
  }
}

// --- 5. شاشة الرحلة النشطة (المصححة) ---
class ActiveTripScreen extends StatefulWidget {
  final int tripId;
  final String token;
  final bool isDriver;
  ActiveTripScreen({required this.tripId, required this.token, required this.isDriver});
  @override
  _ActiveTripScreenState createState() => _ActiveTripScreenState();
}

class _ActiveTripScreenState extends State<ActiveTripScreen> {
  Map? trip;
  String status = "accepted";

  @override
  void initState() { super.initState(); _fetch(); }

  _fetch() async {
    try {
      final res = await http.get(Uri.parse("$apiBaseUrl/trips/${widget.tripId}"), headers: {'Authorization': 'Bearer ${widget.token}'});
      if (res.statusCode == 200) {
        setState(() {
          trip = json.decode(res.body);
          status = trip!['status'] ?? "accepted";
        });
        if (!widget.isDriver && status != 'completed') Future.delayed(Duration(seconds: 5), () => _fetch());
      }
    } catch (e) { print("Fetch Trip Error: $e"); }
  }

  _update(String s) async {
    await http.post(Uri.parse("$apiBaseUrl/trips/${widget.tripId}/status"), body: {'status': s}, headers: {'Authorization': 'Bearer ${widget.token}'});
    _fetch();
  }

  @override
  Widget build(BuildContext context) {
    // حل مشكلة Null value: نضع واجهة انتظار حتى تكتمل البيانات
    if (trip == null) return Scaffold(body: Center(child: CircularProgressIndicator()));

    // استخدام tryParse لتجنب الخطأ في حال كانت الإحداثيات فارغة
    double lat = double.tryParse(trip!['pickup_lat'].toString()) ?? 33.3128;
    double lng = double.tryParse(trip!['pickup_long'].toString()) ?? 44.3615;

    return Scaffold(
      body: Stack(children: [
        FlutterMap(options: MapOptions(initialCenter: LatLng(lat, lng), initialZoom: 15), children: [
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
          MarkerLayer(markers: [Marker(point: LatLng(lat, lng), child: Icon(Icons.person_pin_circle, color: Colors.blue, size: 40))])
        ]),
        Align(alignment: Alignment.bottomCenter, child: Container(
          padding: EdgeInsets.all(25), decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // حماية الأسماء من الـ Null
            Text(widget.isDriver ? "الزبون: ${trip!['customer']?['name'] ?? 'جارِ التحميل...'}" : "الكابتن: ${trip!['driver']?['name'] ?? 'جارِ التحميل...'}", style: TextStyle(fontSize: 20, color: Colors.amber)),
            Text("المبلغ: ${trip!['fare'] ?? '0'} د.ع"),
            SizedBox(height: 20),
            if (widget.isDriver) ...[
               if (status == "accepted") _btn("وصلت لنقطة الانطلاق", () => _update("arrived")),
               if (status == "arrived") _btn("ركب الزبون", () => _update("picked_up")),
               if (status == "picked_up") _btn("إتمام الرحلة", () {
                  // نافذة إدخال المبلغ النهائي
                  _showFinishDialog();
               }, color: Colors.green),
            ] else ...[
               Text(status == "arrived" ? "الكابتن وصل!" : status == "picked_up" ? "أنت في الرحلة الآن" : "الكابتن في الطريق"),
               if (status == "completed") _btn("شكراً لك", () => Navigator.pop(context))
            ]
          ]),
        ))
      ]),
    );
  }

  _showFinishDialog() {
    final c = TextEditingController();
    showDialog(context: context, builder: (d) => AlertDialog(
      title: Text("إتمام الرحلة"),
      content: TextField(controller: c, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: "المبلغ المستلم")),
      actions: [TextButton(onPressed: () async {
        await http.post(Uri.parse("$apiBaseUrl/trips/${widget.tripId}/finish"), body: {'amount': c.text}, headers: {'Authorization': 'Bearer ${widget.token}'});
        Navigator.pop(d); Navigator.pop(context);
      }, child: Text("تأكيد"))],
    ));
  }

  _btn(t, f, {Color color = Colors.amber}) => ElevatedButton(onPressed: f, child: Text(t), style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.black, minimumSize: Size(double.infinity, 55)));
}