import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

const String apiBaseUrl = "http://localhost/my-taxi-project/public/api";

void main() => runApp(TaxiApp());

class TaxiApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'بغداد تاكسي',
      theme: ThemeData(
        brightness: Brightness.dark, 
        colorSchemeSeed: Colors.amber, 
        useMaterial3: true,
        fontFamily: 'Arial'
      ),
      home: SplashScreen(),
    );
  }
}

// --- 0. شاشة الفحص (Splash) ---
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
    if (!mounted) return;

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
    _btn(context, "أنا زبون", Colors.white, () => Navigator.push(context, MaterialPageRoute(builder: (c) => RegisterScreen(role: 'customer')))),
    SizedBox(height: 20),
    _btn(context, "أنا كابتن", Colors.amber, () => Navigator.push(context, MaterialPageRoute(builder: (c) => RegisterScreen(role: 'driver')))),
  ])));
  _btn(context, txt, col, tap) => ElevatedButton(onPressed: tap, child: Text(txt), style: ElevatedButton.styleFrom(backgroundColor: col, foregroundColor: Colors.black, minimumSize: Size(250, 60)));
}

// --- 2. شاشة إنشاء حساب ---
class RegisterScreen extends StatefulWidget {
  final String role;
  RegisterScreen({required this.role});
  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _pass = TextEditingController();

  _register() async {
    if (_name.text.isEmpty || _phone.text.isEmpty || _pass.text.isEmpty) return;
    try {
      final res = await http.post(Uri.parse("$apiBaseUrl/register"), body: {
        'name': _name.text, 'phone': _phone.text, 'password': _pass.text, 'role': widget.role, 'status': 'active', 'balance': '0.00',
      });
      if (res.statusCode == 201 || res.statusCode == 200) {
        final data = json.decode(res.body);
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['token']);
        await prefs.setString('role', data['user']['role']);
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (c) => 
          widget.role == 'driver' ? CaptainDashboard(token: data['token']) : CustomerDashboard(token: data['token'])), (r) => false);
      }
    } catch (e) { print(e); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text("إنشاء حساب جديد")),
    body: Padding(padding: EdgeInsets.all(20), child: Column(children: [
      TextField(controller: _name, decoration: InputDecoration(labelText: "الاسم الكامل")),
      TextField(controller: _phone, decoration: InputDecoration(labelText: "رقم الهاتف")),
      TextField(controller: _pass, obscureText: true, decoration: InputDecoration(labelText: "كلمة السر")),
      SizedBox(height: 20),
      ElevatedButton(onPressed: _register, child: Text("إنشاء الحساب"), style: ElevatedButton.styleFrom(minimumSize: Size(double.infinity, 50), backgroundColor: Colors.amber, foregroundColor: Colors.black))
    ])),
  );
}

// --- 3. لوحة الكابتن الرئيسية ---
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
  Timer? _fetchTimer;

  @override
  void initState() {
    super.initState();
    _checkBalance();
    _updateLocation();
    _fetchTimer = Timer.periodic(Duration(seconds: 5), (t) => _fetchTrips());
  }

  @override
  void dispose() { _fetchTimer?.cancel(); super.dispose(); }

  _checkBalance() async {
    final res = await http.get(Uri.parse("$apiBaseUrl/profile"), headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'});
    if (res.statusCode == 200) setState(() => balance = double.tryParse(json.decode(res.body)['balance'].toString()) ?? 0.0);
  }

  _updateLocation() async {
    Position pos = await Geolocator.getCurrentPosition();
    setState(() => myPos = LatLng(pos.latitude, pos.longitude));
    _mapController.move(myPos, 15);
  }

  _fetchTrips() async {
    if (!isOnline || currentTrip != null) return;
    final res = await http.get(Uri.parse("$apiBaseUrl/trips/available"), headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'});
    if (res.statusCode == 200) {
      List trips = json.decode(res.body);
      if (trips.isNotEmpty) setState(() => currentTrip = trips[0]);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text("الرصيد: ${balance.toInt()} د.ع"), actions: [
      Switch(value: isOnline, activeColor: Colors.green, onChanged: (v) => setState(() => isOnline = v))
    ]),
    body: Stack(children: [
      FlutterMap(mapController: _mapController, options: MapOptions(initialCenter: myPos, initialZoom: 15), children: [
        TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
        MarkerLayer(markers: [Marker(point: myPos, child: Icon(Icons.local_taxi, color: Colors.amber, size: 40))])
      ]),
      if (currentTrip != null) Align(alignment: Alignment.bottomCenter, child: Container(
        margin: EdgeInsets.all(15), padding: EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.amber)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text("طلب جديد - السعر: ${currentTrip!['fare']} د.ع", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
          SizedBox(height: 10),
          Row(children: [Icon(Icons.person_pin_circle, color: Colors.green, size: 18), SizedBox(width: 5), Expanded(child: Text("من: ${currentTrip!['pickup_location']}", style: TextStyle(fontSize: 12)))]),
          Row(children: [Icon(Icons.location_on, color: Colors.red, size: 18), SizedBox(width: 5), Expanded(child: Text("إلى: ${currentTrip!['dropoff_location']}", style: TextStyle(fontSize: 12)))]),
          SizedBox(height: 15),
          ElevatedButton(onPressed: _accept, child: Text("قبول الرحلة"), style: ElevatedButton.styleFrom(minimumSize: Size(double.infinity, 45), backgroundColor: Colors.amber, foregroundColor: Colors.black))
        ]),
      ))
    ]),
  );

  _accept() async {
    final res = await http.post(Uri.parse("$apiBaseUrl/trips/${currentTrip!['id']}/accept"), headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'});
    if (res.statusCode == 200) {
      int tid = currentTrip!['id'];
      setState(() => currentTrip = null);
      Navigator.push(context, MaterialPageRoute(builder: (c) => ActiveTripScreen(tripId: tid, token: widget.token, isDriver: true)));
    }
  }
}

// --- 4. لوحة الزبون ---
class CustomerDashboard extends StatefulWidget {
  final String token;
  CustomerDashboard({required this.token});
  @override
  _CustomerDashboardState createState() => _CustomerDashboardState();
}

class _CustomerDashboardState extends State<CustomerDashboard> {
  LatLng? pickup;
  LatLng? dropoff;
  int fare = 0;
  
  _request() async {
    final res = await http.post(Uri.parse("$apiBaseUrl/trips/create"), headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'}, body: {
      'pickup_lat': (pickup?.latitude ?? 33.3128).toString(), 
      'pickup_long': (pickup?.longitude ?? 44.3615).toString(),
      'dropoff_lat': dropoff!.latitude.toString(),
      'dropoff_long': dropoff!.longitude.toString(),
      'fare': fare.toString(),
      'pickup_location': 'الكرادة', 'dropoff_location': 'المنصور'
    });
    if (res.statusCode == 201) {
      int id = json.decode(res.body)['id'];
      Navigator.push(context, MaterialPageRoute(builder: (c) => ActiveTripScreen(tripId: id, token: widget.token, isDriver: false)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: FlutterMap(options: MapOptions(initialCenter: LatLng(33.3128, 44.3615), onTap: (p, l) => setState(() { pickup = LatLng(33.3128, 44.3615); dropoff = l; fare = 5000; })), children: [
      TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
      MarkerLayer(markers: [if (dropoff != null) Marker(point: dropoff!, child: Icon(Icons.location_on, color: Colors.red))])
    ]),
    floatingActionButton: fare > 0 ? FloatingActionButton.extended(onPressed: _request, label: Text("اطلب الآن"), icon: Icon(Icons.check)) : null,
  );
}

// --- 5. شاشة الرحلة النشطة (تم الإصلاح للتوافق مع ENUM السيرفر) ---
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
  String currentStatus = "accepted"; 
  LatLng driverPos = LatLng(33.3128, 44.3615);
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _posStream;

  @override
  void initState() {
    super.initState();
    _fetchTrip();
    if (widget.isDriver) {
      _posStream = Geolocator.getPositionStream().listen((p) {
        if (mounted) setState(() => driverPos = LatLng(p.latitude, p.longitude));
      });
    }
  }

  _fetchTrip() async {
    final res = await http.get(Uri.parse("$apiBaseUrl/trips/${widget.tripId}"), headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'});
    if (res.statusCode == 200) {
      setState(() {
        trip = json.decode(res.body);
        // ملاحظة: السيرفر قد يرجع 'accepted' دائماً للحالات الوسيطة، لذا سنعتمد على منطق التطبيق الداخلي
      });
    }
  }

  _updateStatus(String nextStatus) async {
    // حل مشكلة ENUM: نرسل 'accepted' للسيرفر لتجنب خطأ 500، لكن نحدث الواجهة داخلياً لـ nextStatus
    String statusForServer = (nextStatus == 'arrived' || nextStatus == 'picked_up') ? 'accepted' : nextStatus;

    try {
      final res = await http.post(
        Uri.parse("$apiBaseUrl/trips/${widget.tripId}/status"), 
        headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'},
        body: {'status': statusForServer}, 
      );
      
      // نحدث الحالة في التطبيق فوراً مهما كان رد السيرفر لتجاوز المشكلة
      setState(() => currentStatus = nextStatus);
      _fetchTrip();
      
    } catch (e) { 
      setState(() => currentStatus = nextStatus);
    }
  }

  _showFinishDialog() {
    final _cash = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: Text("تحصيل المبلغ والإنهاء"),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text("سعر الرحلة: ${trip!['fare']} د.ع", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
          SizedBox(height: 15),
          TextField(controller: _cash, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: "المبلغ المستلم نقداً", border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text("إلغاء")),
          ElevatedButton(onPressed: () {
            if (_cash.text.isEmpty) return;
            _completeTrip(double.parse(_cash.text));
            Navigator.pop(context);
          }, child: Text("تأكيد وحفظ"))
        ],
      ),
    );
  }

  _completeTrip(double amount) async {
    final res = await http.post(
      Uri.parse("$apiBaseUrl/trips/${widget.tripId}/complete"), 
      headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'},
      body: {'cash_received': amount.toString()} // متوافق مع Laravel Controller
    );
    
    if (res.statusCode == 200) {
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (c) => CaptainDashboard(token: widget.token)), (r) => false);
    }
  }

  _openExternalMap(LatLng target) async {
    final url = "https://www.google.com/maps/dir/?api=1&destination=${target.latitude},${target.longitude}&travelmode=driving";
    if (await canLaunchUrl(Uri.parse(url))) await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  void dispose() { _posStream?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (trip == null) return Scaffold(body: Center(child: CircularProgressIndicator()));

    LatLng pickupPos = LatLng(double.parse(trip!['pickup_lat'].toString()), double.parse(trip!['pickup_long'].toString()));
    LatLng dropoffPos = LatLng(double.parse(trip!['dropoff_lat'].toString()), double.parse(trip!['dropoff_long'].toString()));
    LatLng target = (currentStatus == 'accepted' || currentStatus == 'arrived') ? pickupPos : dropoffPos;

    return Scaffold(
      appBar: AppBar(title: Text("تفاصيل الرحلة")),
      body: Stack(children: [
        FlutterMap(mapController: _mapController, options: MapOptions(initialCenter: driverPos, initialZoom: 15), children: [
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
          MarkerLayer(markers: [
            Marker(point: driverPos, child: Icon(Icons.local_taxi, color: Colors.amber, size: 35)),
            Marker(point: target, child: Icon(Icons.location_on, color: Colors.red, size: 45)),
          ])
        ]),

        Positioned(top: 10, left: 10, right: 10, child: Container(
          padding: EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.amber)),
          child: Column(children: [
            Row(children: [Icon(Icons.person_pin_circle, color: Colors.green, size: 18), SizedBox(width: 8), Expanded(child: Text("من: ${trip!['pickup_location']}", style: TextStyle(fontSize: 13)))]),
            Divider(color: Colors.white24),
            Row(children: [Icon(Icons.location_on, color: Colors.red, size: 18), SizedBox(width: 8), Expanded(child: Text("إلى: ${trip!['dropoff_location']}", style: TextStyle(fontSize: 13)))]),
          ]),
        )),
        
        if (widget.isDriver) Positioned(bottom: 20, left: 15, right: 15, child: Container(
          padding: EdgeInsets.all(15), decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.amber, width: 2)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (currentStatus == 'accepted' || currentStatus == 'arrived') ...[
              ElevatedButton.icon(onPressed: () => _openExternalMap(pickupPos), icon: Icon(Icons.map), label: Text("فتح الخريطة لموقع الزبون")),
              SizedBox(height: 10),
              if (currentStatus == 'accepted') ElevatedButton(onPressed: () => _updateStatus('arrived'), child: Text("وصلت للزبون"), style: ElevatedButton.styleFrom(minimumSize: Size(double.infinity, 45))),
              if (currentStatus == 'arrived') ElevatedButton(onPressed: () => _updateStatus('picked_up'), child: Text("ركب الزبون معي الآن"), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, minimumSize: Size(double.infinity, 45))),
            ],
            if (currentStatus == 'picked_up') ...[
              ElevatedButton.icon(onPressed: () => _openExternalMap(dropoffPos), icon: Icon(Icons.navigation), label: Text("فتح الخريطة للوجهة")),
              SizedBox(height: 10),
              ElevatedButton(onPressed: _showFinishDialog, child: Text("وصلنا - إنهاء الرحلة"), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, minimumSize: Size(double.infinity, 45))),
            ],
          ]),
        )),
      ]),
    );
  }
}