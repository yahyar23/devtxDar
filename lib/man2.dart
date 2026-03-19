import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

// ملاحظة مهمة:
// 10.0.0.2 هو IP المحاكي (Android Emulator) للوصول لـ localhost الحاسوب
// إذا كنت تستخدم هاتف حقيقي، استبدله بـ IP حاسوبك (مثلاً 192.168.1.5)
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
      ),
      home: SplashScreen(),
    );
  }
}

// --- 0. شاشة الفحص (لحجز الجلسة) ---
class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  _checkLoginStatus() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('token');
    String? role = prefs.getString('role');

    // تأخير بسيط لإظهار شعار التطبيق
    await Future.delayed(Duration(seconds: 2));

    if (token != null && role != null) {
      if (role == 'driver') {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => CaptainDashboard(token: token)));
      } else {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => CustomerDashboard(token: token)));
      }
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => WelcomeScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.local_taxi, size: 100, color: Colors.amber),
            SizedBox(height: 20),
            CircularProgressIndicator(color: Colors.amber),
          ],
        ),
      ),
    );
  }
}

// --- 1. شاشة الترحيب واختيار النوع ---
class WelcomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.local_taxi, size: 120, color: Colors.amber),
            SizedBox(height: 20),
            Text("بغداد تاكسي", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
            Text("تطبيقك الموثوق للتنقل", style: TextStyle(fontSize: 16, color: Colors.grey)),
            SizedBox(height: 60),
            _buildBtn(context, "أنا زبون (طلب رحلة)", Icons.person, Colors.white, () => _goLogin(context, false)),
            SizedBox(height: 20),
            _buildBtn(context, "أنا كابتن (استقبال طلبات)", Icons.directions_car, Colors.amber, () => _goLogin(context, true)),
          ],
        ),
      ),
    );
  }

  void _goLogin(BuildContext context, bool isDriver) {
    Navigator.push(context, MaterialPageRoute(builder: (c) => LoginScreen(isDriver: isDriver)));
  }

  Widget _buildBtn(BuildContext context, String text, IconData icon, Color color, VoidCallback onTap) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.black,
        minimumSize: Size(300, 65),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 28),
      label: Text(text, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    );
  }
}

// --- 2. شاشة تسجيل الدخول المحسنة (تجنب خطأ Null) ---
class LoginScreen extends StatefulWidget {
  final bool isDriver;
  LoginScreen({required this.isDriver});
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _login() async {
    if (_phoneController.text.isEmpty || _passwordController.text.isEmpty) {
      _showMsg("يرجى إدخال كافة الحقول", isError: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse("$apiBaseUrl/login"),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'phone': _phoneController.text,
          'password': _passwordController.text
        },
      ).timeout(Duration(seconds: 10));

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        // حماية ضد الـ Null: التأكد من وجود المفاتيح قبل الاستخدام
        String? token = data['token']?.toString();
        var userData = data['user'];

        if (token != null && userData != null) {
          String role = userData['role']?.toString() ?? 'customer';
          int userId = userData['id'] ?? 0;

          SharedPreferences prefs = await SharedPreferences.getInstance();
          await prefs.setString('token', token);
          await prefs.setString('role', role);
          await prefs.setInt('userId', userId);

          _showMsg("تم تسجيل الدخول بنجاح ✅");

          if (role == 'driver') {
            Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (c) => CaptainDashboard(token: token)), (route) => false);
          } else {
            Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (c) => CustomerDashboard(token: token)), (route) => false);
          }
        } else {
          _showMsg("خطأ في بنية البيانات من السيرفر", isError: true);
        }
      } else {
        _showMsg(data['message'] ?? "بيانات الدخول غير صحيحة", isError: true);
      }
    } catch (e) {
      _showMsg("فشل الاتصال بالسيرفر. تأكد من تشغيل Laravel و Ngrok", isError: true);
      print("Login Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMsg(String m, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: isError ? Colors.red : Colors.green));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.isDriver ? "دخول الكابتن" : "دخول الزبون")),
      body: Padding(
        padding: EdgeInsets.all(25),
        child: SingleChildScrollView(
          child: Column(children: [
            TextField(controller: _phoneController, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: "رقم الهاتف", prefixIcon: Icon(Icons.phone, color: Colors.amber), border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)))),
            SizedBox(height: 15),
            TextField(controller: _passwordController, obscureText: true, decoration: InputDecoration(labelText: "كلمة السر", prefixIcon: Icon(Icons.lock, color: Colors.amber), border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)))),
            SizedBox(height: 30),
            _isLoading 
              ? CircularProgressIndicator() 
              : ElevatedButton(
                  onPressed: _login, 
                  child: Text("تسجيل الدخول", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)), 
                  style: ElevatedButton.styleFrom(minimumSize: Size(double.infinity, 60), backgroundColor: Colors.amber, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)))
                ),
          ]),
        ),
      ),
    );
  }
}

// --- 3. لوحة الكابتن الحقيقية (Dashboard) ---
class CaptainDashboard extends StatefulWidget {
  final String token;
  CaptainDashboard({required this.token});
  @override
  _CaptainDashboardState createState() => _CaptainDashboardState();
}

class _CaptainDashboardState extends State<CaptainDashboard> {
  bool isOnline = false;
  Map? currentTrip;
  Timer? _pollingTimer;

  Future<void> _fetchAvailableTrips() async {
    if (!isOnline || currentTrip != null) return;
    try {
      final response = await http.get(
        Uri.parse("$apiBaseUrl/trips/available"),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer ${widget.token}'
        },
      );
      if (response.statusCode == 200) {
        List trips = json.decode(response.body);
        if (trips.isNotEmpty) {
          setState(() => currentTrip = trips[0]);
        }
      }
    } catch (e) { print("Polling Error: $e"); }
  }

  Future<void> _acceptTrip(int tripId) async {
    try {
      final response = await http.post(
        Uri.parse("$apiBaseUrl/trips/$tripId/accept"),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer ${widget.token}'
        },
      );
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("تم قبول الرحلة بنجاح! ✅")));
        setState(() => currentTrip = null);
      }
    } catch (e) { print("Accept Error: $e"); }
  }

  _logout() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (c) => WelcomeScreen()), (route) => false);
  }

  @override
  void initState() {
    super.initState();
    _pollingTimer = Timer.periodic(Duration(seconds: 5), (t) => _fetchAvailableTrips());
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("لوحة الكابتن"),
        actions: [
          Switch(value: isOnline, onChanged: (v) => setState(() => isOnline = v), activeColor: Colors.green),
          IconButton(onPressed: _logout, icon: Icon(Icons.logout, color: Colors.red)),
        ],
      ),
      body: Stack(
        children: [
          Container(color: Colors.grey[900], child: Center(child: Icon(Icons.map_outlined, size: 100, color: Colors.white10))),
          if (!isOnline) Center(child: Text("أنت غير متصل الآن", style: TextStyle(color: Colors.grey))),
          if (isOnline && currentTrip == null) Center(child: CircularProgressIndicator(color: Colors.amber)),
          if (currentTrip != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: _buildTripCard(),
            ),
        ],
      ),
    );
  }

  Widget _buildTripCard() {
    return Container(
      margin: EdgeInsets.all(20),
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.amber)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("طلب جديد 🚕", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.amber)),
          SizedBox(height: 10),
          Text("من: ${currentTrip!['pickup_location']}"),
          Text("إلى: ${currentTrip!['dropoff_location']}"),
          SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => _acceptTrip(currentTrip!['id']),
            child: Text("قبول الآن"),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black, minimumSize: Size(double.infinity, 50)),
          ),
          TextButton(onPressed: () => setState(() => currentTrip = null), child: Text("تجاهل")),
        ],
      ),
    );
  }
}

// --- 4. واجهة الزبون (طلب رحلة) ---
class CustomerDashboard extends StatefulWidget {
  final String token;
  CustomerDashboard({required this.token});
  @override
  _CustomerDashboardState createState() => _CustomerDashboardState();
}

class _CustomerDashboardState extends State<CustomerDashboard> {
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();

  Future<void> _requestTrip() async {
    try {
      final response = await http.post(
        Uri.parse("$apiBaseUrl/trips/create"),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer ${widget.token}'
        },
        body: {
          'pickup_location': _fromCtrl.text,
          'dropoff_location': _toCtrl.text,
          'pickup_lat': '33.3128',
          'pickup_long': '44.3615',
          'dropoff_lat': '33.3025',
          'dropoff_long': '44.4211',
          'fare': '5000'
        },
      );
      if (response.statusCode == 201) {
        _showMsg("جاري البحث عن كابتن...");
      }
    } catch (e) { print("Request Error: $e"); }
  }

  void _showMsg(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("طلب تكسي")),
      body: Padding(
        padding: EdgeInsets.all(20),
        child: Column(children: [
          TextField(controller: _fromCtrl, decoration: InputDecoration(labelText: "نقطة الانطلاق")),
          SizedBox(height: 10),
          TextField(controller: _toCtrl, decoration: InputDecoration(labelText: "وجهة الوصول")),
          Spacer(),
          ElevatedButton(
            onPressed: _requestTrip,
            child: Text("اطلب الآن", style: TextStyle(color: Colors.black)),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, minimumSize: Size(double.infinity, 60)),
          )
        ]),
      ),
    );
  }
}