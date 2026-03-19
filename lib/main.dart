import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

// ملاحظة: إذا كنت تستخدم المحاكي (Emulator) استخدم 10.0.2.2 بدلاً من localhost
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
    _btn(context, "أنا زبون", Colors.white, () => _go(context, 'customer')),
    SizedBox(height: 20),
    _btn(context, "أنا كابتن", Colors.amber, () => _go(context, 'driver')),
  ])));
  
  _go(context, role) => Navigator.push(context, MaterialPageRoute(builder: (c) => RegisterScreen(role: role)));
  
  _btn(context, txt, col, tap) => ElevatedButton(onPressed: tap, child: Text(txt), style: ElevatedButton.styleFrom(backgroundColor: col, foregroundColor: Colors.black, minimumSize: Size(250, 60)));
}

// --- 2. شاشة إنشاء حساب (مطابقة لجدول Users) ---
class RegisterScreen extends StatefulWidget {
  final String role; // 'driver' or 'customer'
  RegisterScreen({required this.role});
  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _pass = TextEditingController();
  final _email = TextEditingController(); // حقل اختياري موجود في جدولك

  _register() async {
    if (_name.text.isEmpty || _phone.text.isEmpty || _pass.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("يرجى ملء الحقول الأساسية")));
      return;
    }

    try {
      // بناء البيانات بناءً على الـ Migration الخاص بك
      Map<String, String> body = {
        'name': _name.text,
        'phone': _phone.text,
        'password': _pass.text,
        'role': widget.role, // driver, customer
        'status': 'active',  // نرسلها active ليتجاوز الـ pending الافتراضي في الجدول
        'balance': '0.00',
      };
      
      if (_email.text.isNotEmpty) body['email'] = _email.text;

      final res = await http.post(Uri.parse("$apiBaseUrl/register"), body: body);
      final data = json.decode(res.body);

      if (res.statusCode == 201 || res.statusCode == 200) {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['token']);
        await prefs.setString('role', data['user']['role']);
        
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (c) => 
          widget.role == 'driver' ? CaptainDashboard(token: data['token']) : CustomerDashboard(token: data['token'])), (r) => false);
      } else {
        String msg = data['message'] ?? "خطأ في التسجيل";
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("فشل الاتصال: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.role == 'driver' ? "تسجيل كابتن جديد" : "تسجيل زبون جديد")),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Column(children: [
          TextField(controller: _name, decoration: InputDecoration(labelText: "الاسم الكامل", prefixIcon: Icon(Icons.person))),
          TextField(controller: _phone, decoration: InputDecoration(labelText: "رقم الهاتف (Unique)", prefixIcon: Icon(Icons.phone)), keyboardType: TextInputType.phone),
          TextField(controller: _email, decoration: InputDecoration(labelText: "البريد الإلكتروني (اختياري)", prefixIcon: Icon(Icons.email))),
          TextField(controller: _pass, obscureText: true, decoration: InputDecoration(labelText: "كلمة السر", prefixIcon: Icon(Icons.lock))),
          
          SizedBox(height: 30),
          ElevatedButton(onPressed: _register, child: Text("إنشاء الحساب"), style: ElevatedButton.styleFrom(minimumSize: Size(double.infinity, 50), backgroundColor: Colors.amber, foregroundColor: Colors.black)),
          TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => LoginScreen())), child: Text("لديك حساب؟ سجل دخول"))
        ]),
      ),
    );
  }
}

// --- 3. شاشة تسجيل الدخول ---
class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController();
  final _pass = TextEditingController();

  _login() async {
    try {
      final res = await http.post(Uri.parse("$apiBaseUrl/login"), body: {
        'phone': _phone.text, 
        'password': _pass.text
      });
      
      final data = json.decode(res.body);
      if (res.statusCode == 200) {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['token']);
        await prefs.setString('role', data['user']['role']);
        
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (c) => 
          data['user']['role'] == 'driver' ? CaptainDashboard(token: data['token']) : CustomerDashboard(token: data['token'])), (r) => false);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("رقم الهاتف أو كلمة السر غير صحيحة")));
      }
    } catch (e) { 
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("تعذر الاتصال بالسيرفر")));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text("تسجيل الدخول")), body: Padding(padding: EdgeInsets.all(20), child: Column(children: [
    TextField(controller: _phone, decoration: InputDecoration(labelText: "رقم الهاتف"), keyboardType: TextInputType.phone),
    TextField(controller: _pass, obscureText: true, decoration: InputDecoration(labelText: "كلمة السر")),
    SizedBox(height: 30),
    ElevatedButton(onPressed: _login, child: Text("دخول"), style: ElevatedButton.styleFrom(minimumSize: Size(double.infinity, 50), backgroundColor: Colors.amber, foregroundColor: Colors.black))
  ])));
}

// --- 4. لوحة الكابتن (Captain Dashboard) ---
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
  void dispose() {
    _fetchTimer?.cancel();
    super.dispose();
  }

  _checkBalance() async {
    try {
      final res = await http.get(Uri.parse("$apiBaseUrl/profile"), headers: {'Authorization': 'Bearer ${widget.token}'});
      if (res.statusCode == 200) {
        setState(() => balance = double.tryParse(json.decode(res.body)['balance'].toString()) ?? 0.0);
      }
    } catch (e) { print("Balance Error: $e"); }
  }

  _updateLocation() async {
    try {
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() => myPos = LatLng(pos.latitude, pos.longitude));
      _mapController.move(myPos, 15);
    } catch (e) { print("Location Error: $e"); }
  }

  _fetchTrips() async {
    if (!isOnline || currentTrip != null) return;
    try {
      final res = await http.get(Uri.parse("$apiBaseUrl/trips/available"), headers: {'Authorization': 'Bearer ${widget.token}'});
      if (res.statusCode == 200) {
        List trips = json.decode(res.body);
        if (trips.isNotEmpty) setState(() => currentTrip = trips[0]);
      }
    } catch (e) { print("Fetch Trips Error: $e"); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("الرصيد: ${balance.toInt()} د.ع"), actions: [
        Switch(value: isOnline, activeColor: Colors.green, onChanged: (v) => setState(() => isOnline = v))
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
    margin: EdgeInsets.all(15), padding: EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.amber, width: 2)),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text("طلب رحلة جديد 🚕", style: TextStyle(color: Colors.amber, fontSize: 18, fontWeight: FontWeight.bold)),
      SizedBox(height: 10),
      Text("من: ${currentTrip!['pickup_location']}"),
      Text("السعر: ${currentTrip!['fare']} د.ع", style: TextStyle(fontSize: 16, color: Colors.greenAccent)),
      SizedBox(height: 15),
      ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black, minimumSize: Size(double.infinity, 50)),
        onPressed: () async {
          final res = await http.post(Uri.parse("$apiBaseUrl/trips/${currentTrip!['id']}/accept"), headers: {'Authorization': 'Bearer ${widget.token}'});
          if (res.statusCode == 200) {
            int tid = currentTrip!['id'];
            setState(() => currentTrip = null);
            if (!mounted) return;
            Navigator.push(context, MaterialPageRoute(builder: (c) => ActiveTripScreen(tripId: tid, token: widget.token, isDriver: true)));
          }
        }, child: Text("قبول الرحلة")
      )
    ]),
  ));
}

// --- 5. لوحة الزبون (Customer Dashboard) ---
class CustomerDashboard extends StatefulWidget {
  final String token;
  CustomerDashboard({required this.token});
  @override
  _CustomerDashboardState createState() => _CustomerDashboardState();
}

class _CustomerDashboardState extends State<CustomerDashboard> {
  final _from = TextEditingController();
  LatLng? pickup;
  LatLng? dropoff;
  int fare = 0;
  final MapController _mapController = MapController();

  _setCurrentLocation() async {
    try {
      Position pos = await Geolocator.getCurrentPosition();
      setState(() {
        pickup = LatLng(pos.latitude, pos.longitude);
        _from.text = "موقعي الحالي";
      });
      _mapController.move(pickup!, 15);
    } catch (e) { print(e); }
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
      appBar: AppBar(title: Text("اطلب تاكسي")),
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
          Positioned(top: 20, right: 20, child: FloatingActionButton(onPressed: _setCurrentLocation, child: Icon(Icons.my_location), mini: true))
        ])),
        Container(padding: EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.vertical(top: Radius.circular(20))), child: Column(children: [
          TextField(controller: _from, decoration: InputDecoration(hintText: "موقع الانطلاق", prefixIcon: Icon(Icons.circle, size: 12, color: Colors.blue))),
          if (fare > 0) Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text("التكلفة التقديرية: $fare د.ع", style: TextStyle(fontSize: 20, color: Colors.amber, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(onPressed: fare > 0 ? _request : null, child: Text("تأكيد الطلب الآن"), style: ElevatedButton.styleFrom(minimumSize: Size(double.infinity, 55), backgroundColor: Colors.amber, foregroundColor: Colors.black))
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
    if (res.statusCode == 201) _wait(json.decode(res.body)['id']);
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

// --- 6. شاشة الرحلة النشطة ---
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
  Timer? _refreshTimer;

  @override
  void initState() { 
    super.initState(); 
    _fetch(); 
    _refreshTimer = Timer.periodic(Duration(seconds: 5), (t) => _fetch());
  }

  @override
  void dispose() { _refreshTimer?.cancel(); super.dispose(); }

  _fetch() async {
    try {
      final res = await http.get(Uri.parse("$apiBaseUrl/trips/${widget.tripId}"), headers: {'Authorization': 'Bearer ${widget.token}'});
      if (res.statusCode == 200) {
        setState(() {
          trip = json.decode(res.body);
          status = trip!['status'] ?? "accepted";
        });
      }
    } catch (e) { print(e); }
  }

  _update(String s) async {
    await http.post(Uri.parse("$apiBaseUrl/trips/${widget.tripId}/status"), body: {'status': s}, headers: {'Authorization': 'Bearer ${widget.token}'});
    _fetch();
  }

  @override
  Widget build(BuildContext context) {
    if (trip == null) return Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: Text("الرحلة الحالية")),
      body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text("حالة الرحلة: $status", style: TextStyle(fontSize: 24, color: Colors.amber)),
        SizedBox(height: 20),
        if (widget.isDriver && status != 'completed') 
          ElevatedButton(onPressed: () => _update('completed'), child: Text("إنهاء الرحلة"))
        else if (status == 'completed')
          ElevatedButton(onPressed: () => Navigator.pop(context), child: Text("العودة"))
      ])),
    );
  }
}