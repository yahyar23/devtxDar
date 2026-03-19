import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

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
        fontFamily: 'Arial',
      ),
      home: SplashScreen(),
    );
  }
}

// --- نظام تسجيل الخروج الموحد ---
_logout(BuildContext context) async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (c) => WelcomeScreen()), (r) => false);
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
      final res = await http.post(
        Uri.parse("$apiBaseUrl/login"), 
        headers: {'Accept': 'application/json'},
        body: {'phone': _phone.text, 'password': _pass.text}
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['token']);
        await prefs.setString('role', data['user']['role']);
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (c) => 
          data['user']['role'] == 'driver' ? CaptainDashboard(token: data['token']) : CustomerDashboard(token: data['token'])), (r) => false);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("فشل الدخول: تأكد من البيانات")));
      }
    } catch (e) { print("Login Error: $e"); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text("تسجيل الدخول")), 
    body: Padding(padding: EdgeInsets.all(20), child: Column(children: [
      TextField(controller: _phone, decoration: InputDecoration(labelText: "رقم الهاتف"), keyboardType: TextInputType.phone),
      TextField(controller: _pass, obscureText: true, decoration: InputDecoration(labelText: "كلمة السر")),
      SizedBox(height: 20),
      ElevatedButton(onPressed: _login, child: Text("دخول"), style: ElevatedButton.styleFrom(minimumSize: Size(double.infinity, 50), backgroundColor: Colors.amber)),
      TextButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => RegisterScreen(isDriver: widget.isDriver))),
        child: Text("ليس لديك حساب؟ سجل الآن", style: TextStyle(color: Colors.amber))
      )
    ])));
}

// --- 2.1 شاشة إنشاء الحساب (الجديدة) ---
class RegisterScreen extends StatefulWidget {
  final bool isDriver;
  RegisterScreen({required this.isDriver});
  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _pass = TextEditingController();
  final _carInfo = TextEditingController(); // خاص بالسائق

  _register() async {
    try {
      Map<String, String> data = {
        'name': _name.text,
        'phone': _phone.text,
        'password': _pass.text,
        'role': widget.isDriver ? 'driver' : 'customer',
      };
      if (widget.isDriver) data['car_info'] = _carInfo.text;

      final res = await http.post(
        Uri.parse("$apiBaseUrl/register"), 
        headers: {'Accept': 'application/json'},
        body: data
      );

      if (res.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("تم إنشاء الحساب بنجاح! سجل دخولك الآن")));
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("فشل التسجيل: تأكد من المدخلات")));
      }
    } catch (e) { print("Register Error: $e"); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.isDriver ? "تسجيل كابتن جديد" : "تسجيل زبون جديد")),
    body: SingleChildScrollView(padding: EdgeInsets.all(20), child: Column(children: [
      TextField(controller: _name, decoration: InputDecoration(labelText: "الاسم الكامل")),
      TextField(controller: _phone, decoration: InputDecoration(labelText: "رقم الهاتف"), keyboardType: TextInputType.phone),
      TextField(controller: _pass, obscureText: true, decoration: InputDecoration(labelText: "كلمة السر")),
      if (widget.isDriver) TextField(controller: _carInfo, decoration: InputDecoration(labelText: "معلومات السيارة (النوع واللوحة)")),
      SizedBox(height: 30),
      ElevatedButton(onPressed: _register, child: Text("إنشاء الحساب"), style: ElevatedButton.styleFrom(minimumSize: Size(double.infinity, 55), backgroundColor: Colors.amber, foregroundColor: Colors.black))
    ])),
  );
}

// --- 3. لوحة الكابتن (مع Nav Bar و شحن الرصيد) ---
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
    Timer.periodic(Duration(seconds: 5), (t) { if (mounted) _fetchTrips(); });
  }

  _checkBalance() async {
    try {
      final res = await http.get(Uri.parse("$apiBaseUrl/driver/balance"), headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'});
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
      final res = await http.get(Uri.parse("$apiBaseUrl/trips/available"), headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'});
      if (res.statusCode == 200) {
        List trips = json.decode(res.body);
        if (trips.isNotEmpty) setState(() => currentTrip = trips[0]);
      }
    } catch (e) { print("Fetch Error: $e"); }
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> _pages = [
      _buildHome(),
      _buildWallet(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_currentIndex == 0 ? "لوحة الكابتن" : "المحفظة"),
        actions: [IconButton(icon: Icon(Icons.logout), onPressed: () => _logout(context))],
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

  Widget _buildHome() => Stack(children: [
    FlutterMap(mapController: _mapController, options: MapOptions(initialCenter: myPos, initialZoom: 15), children: [
      TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
      MarkerLayer(markers: [Marker(point: myPos, child: Icon(Icons.local_taxi, color: Colors.amber, size: 40))])
    ]),
    Positioned(top: 10, right: 10, child: Column(children: [
      FloatingActionButton(onPressed: _updateLocation, child: Icon(Icons.my_location), mini: true),
      SizedBox(height: 10),
      Switch(value: isOnline, onChanged: (v) => setState(() => isOnline = v), activeColor: Colors.green),
    ])),
    if (currentTrip != null) _buildTripRequest(),
  ]);

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
      ElevatedButton(onPressed: _recharge, child: Text("تفعيل الكود"), style: ElevatedButton.styleFrom(minimumSize: Size(double.infinity, 50), backgroundColor: Colors.amber, foregroundColor: Colors.black))
    ]),
  );

  Widget _buildTripRequest() => Align(alignment: Alignment.bottomCenter, child: Container(
    margin: EdgeInsets.all(15), padding: EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.amber)),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text("طلب رحلة جديد", style: TextStyle(color: Colors.amber, fontSize: 18)),
      Text("من: ${currentTrip!['pickup_location'] ?? 'غير محدد'}", style: TextStyle(color: Colors.white)),
      Text("السعر التقديري: ${currentTrip!['fare'] ?? '0'} د.ع", style: TextStyle(color: Colors.white70)),
      SizedBox(height: 10),
      ElevatedButton(onPressed: () async {
        final res = await http.post(Uri.parse("$apiBaseUrl/trips/${currentTrip!['id']}/accept"), headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'});
        if (res.statusCode == 200) {
          int tid = currentTrip!['id'];
          setState(() => currentTrip = null);
          Navigator.push(context, MaterialPageRoute(builder: (c) => ActiveTripScreen(tripId: tid, token: widget.token, isDriver: true)));
        }
      }, child: Text("قبول الرحلة"))
    ]),
  ));
}

// --- 4. لوحة الزبون (مع Nav Bar) ---
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

  _setCurrentLocation() async {
    Position pos = await Geolocator.getCurrentPosition();
    setState(() { pickup = LatLng(pos.latitude, pos.longitude); _from.text = "موقعي الحالي"; });
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
      appBar: AppBar(title: Text("بغداد تاكسي"), actions: [IconButton(icon: Icon(Icons.logout), onPressed: () => _logout(context))]),
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
      FlutterMap(mapController: _mapController, options: MapOptions(initialCenter: LatLng(33.3128, 44.3615), initialZoom: 13, onTap: (p, l) {
        setState(() => dropoff = l); _calculateFare();
      }), children: [
        TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
        MarkerLayer(markers: [
          if (pickup != null) Marker(point: pickup!, child: Icon(Icons.person_pin_circle, color: Colors.blue, size: 40)),
          if (dropoff != null) Marker(point: dropoff!, child: Icon(Icons.location_on, color: Colors.red, size: 40)),
        ])
      ]),
      Positioned(top: 10, right: 10, child: FloatingActionButton(onPressed: _setCurrentLocation, child: Icon(Icons.my_location), mini: true))
    ])),
    Container(padding: EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.grey[900]), child: Column(children: [
      TextField(controller: _from, decoration: InputDecoration(hintText: "موقع الانطلاق")),
      TextField(decoration: InputDecoration(hintText: dropoff == null ? "اضغط الخريطة لتحديد الوجهة" : "تم تحديد الوجهة بنجاح", enabled: false)),
      if (fare > 0) Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text("السعر التقديري: $fare د.ع", style: TextStyle(fontSize: 20, color: Colors.amber, fontWeight: FontWeight.bold))),
      ElevatedButton(onPressed: fare > 0 ? _request : null, child: Text("تأكيد الطلب"), style: ElevatedButton.styleFrom(minimumSize: Size(double.infinity, 50), backgroundColor: Colors.amber, foregroundColor: Colors.black))
    ]))
  ]);

  _request() async {
    final res = await http.post(
      Uri.parse("$apiBaseUrl/trips/create"), 
      headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'}, 
      body: {
        'pickup_location': _from.text, 'dropoff_location': 'الوجهة المحددة على الخريطة', 'fare': fare.toString(),
        'pickup_lat': pickup!.latitude.toString(), 'pickup_long': pickup!.longitude.toString(),
        'dropoff_lat': dropoff!.latitude.toString(), 'dropoff_long': dropoff!.longitude.toString(),
      }
    );
    if (res.statusCode == 201) _wait(json.decode(res.body)['id']);
  }

  _wait(int id) {
    showDialog(context: context, barrierDismissible: false, builder: (c) => AlertDialog(title: Text("جاري البحث عن كابتن..."), content: LinearProgressIndicator()));
    Timer.periodic(Duration(seconds: 4), (t) async {
      final res = await http.get(Uri.parse("$apiBaseUrl/trips/$id"), headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'});
      if (res.statusCode == 200 && json.decode(res.body)['status'] == 'accepted') {
        t.cancel(); Navigator.pop(context);
        Navigator.push(context, MaterialPageRoute(builder: (c) => ActiveTripScreen(tripId: id, token: widget.token, isDriver: false)));
      }
    });
  }
}

// --- 5. شاشة الرحلة النشطة ---
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
    if (!mounted) return;
    try {
      final res = await http.get(Uri.parse("$apiBaseUrl/trips/${widget.tripId}"), headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'});
      if (res.statusCode == 200) {
        setState(() { trip = json.decode(res.body); status = trip!['status'] ?? "accepted"; });
        if (status != 'completed' && status != 'cancelled') Future.delayed(Duration(seconds: 5), () => _fetch());
      }
    } catch (e) { print("Fetch Error: $e"); }
  }

  _update(String s) async {
    final res = await http.post(Uri.parse("$apiBaseUrl/trips/${widget.tripId}/status"), headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'}, body: {'status': s});
    if (res.statusCode == 200) _fetch();
  }

  @override
  Widget build(BuildContext context) {
    if (trip == null) return Scaffold(body: Center(child: CircularProgressIndicator()));
    double lat = double.tryParse(trip!['pickup_lat'].toString()) ?? 33.3128;
    double lng = double.tryParse(trip!['pickup_long'].toString()) ?? 44.3615;

    return Scaffold(
      appBar: AppBar(title: Text("تفاصيل الرحلة"), leading: Container()), 
      body: Stack(children: [
        FlutterMap(options: MapOptions(initialCenter: LatLng(lat, lng), initialZoom: 15), children: [
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
          MarkerLayer(markers: [Marker(point: LatLng(lat, lng), child: Icon(Icons.person_pin_circle, color: Colors.blue, size: 40))])
        ]),
        Align(alignment: Alignment.bottomCenter, child: Container(
          padding: EdgeInsets.all(25), decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(widget.isDriver ? "الزبون: ${trip!['customer']?['name'] ?? '...'}" : "الكابتن: ${trip!['driver']?['name'] ?? '...'}", style: TextStyle(fontSize: 20, color: Colors.amber, fontWeight: FontWeight.bold)),
            Text("المبلغ التقديري: ${trip!['fare'] ?? '0'} د.ع", style: TextStyle(color: Colors.white70)),
            SizedBox(height: 20),
            if (widget.isDriver) ...[
               if (status == "accepted") _btn("وصلت لنقطة الانطلاق", () => _update("arrived")),
               if (status == "arrived") _btn("ركب الزبون (بدء الرحلة)", () => _update("ongoing")), 
               if (status == "ongoing") _btn("إتمام الرحلة", () => _showFinishDialog(), color: Colors.green),
            ] else ...[
               Text(status == "arrived" ? "الكابتن وصل!" : status == "ongoing" ? "أنت في الرحلة الآن" : status == "completed" ? "وصلت!" : "الكابتن في الطريق...", style: TextStyle(fontSize: 18, color: Colors.amber)),
               if (status == "completed") ...[SizedBox(height: 10), _btn("العودة للرئيسية", () => Navigator.pop(context), color: Colors.green)]
            ]
          ]),
        ))
      ]),
    );
  }

  _showFinishDialog() {
    final c = TextEditingController(text: trip!['fare'].toString());
    showDialog(context: context, builder: (d) => AlertDialog(
      title: Text("إتمام الرحلة"),
      content: TextField(controller: c, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: "المبلغ الفعلي المستلم")),
      actions: [TextButton(onPressed: () async {
        final res = await http.post(Uri.parse("$apiBaseUrl/trips/${widget.tripId}/finish"), headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'}, body: {'amount': c.text});
        if (res.statusCode == 200) { Navigator.pop(d); Navigator.pop(context); }
      }, child: Text("تأكيد"))],
    ));
  }

  _btn(t, f, {Color color = Colors.amber}) => ElevatedButton(onPressed: f, child: Text(t), style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.black, minimumSize: Size(double.infinity, 55)));
}