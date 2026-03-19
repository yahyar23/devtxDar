import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'constants.dart';
import 'captain_dashboard.dart';
import 'customer_dashboard.dart';

// --- 1. شاشة الترحيب (Welcome Screen) ---
class WelcomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center, 
        children: [
          Icon(Icons.local_taxi, size: 120, color: Colors.amber),
          Text("بغداد تاكسي", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
          SizedBox(height: 40),
          _btn(context, "أنا زبون (Customer)", Colors.white, () => _go(context, false)),
          SizedBox(height: 20),
          _btn(context, "أنا كابتن (Captain)", Colors.amber, () => _go(context, true)),
        ]
      )
    )
  );

  _go(context, isDriver) => Navigator.push(context, MaterialPageRoute(builder: (c) => LoginScreen(isDriver: isDriver)));
  
  _btn(context, txt, col, tap) => ElevatedButton(
    onPressed: tap, 
    child: Text(txt), 
    style: ElevatedButton.styleFrom(
      backgroundColor: col, 
      foregroundColor: Colors.black, 
      minimumSize: Size(250, 60),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
    )
  );
}

// --- 2. شاشة تسجيل الدخول (Login Screen) ---
class LoginScreen extends StatefulWidget {
  final bool isDriver;
  LoginScreen({required this.isDriver});
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController();
  final _pass = TextEditingController();
  bool isLoading = false;

  _login() async {
    setState(() => isLoading = true);
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
        
        // التوجيه للوحة التحكم المناسبة
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (c) => 
          data['user']['role'] == 'driver' 
            ? CaptainDashboard(token: data['token']) 
            : CustomerDashboard(token: data['token'])
        ), (r) => false);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("فشل الدخول: تأكد من البيانات")));
      }
    } catch (e) { 
      print("Login Error: $e"); 
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text("تسجيل الدخول")), 
    body: Padding(padding: EdgeInsets.all(20), child: Column(children: [
      TextField(controller: _phone, decoration: InputDecoration(labelText: "رقم الهاتف"), keyboardType: TextInputType.phone),
      TextField(controller: _pass, obscureText: true, decoration: InputDecoration(labelText: "كلمة السر")),
      SizedBox(height: 30),
      isLoading 
        ? CircularProgressIndicator() 
        : ElevatedButton(
            onPressed: _login, 
            child: Text("دخول"), 
            style: ElevatedButton.styleFrom(minimumSize: Size(double.infinity, 55), backgroundColor: Colors.amber, foregroundColor: Colors.black)
          ),
      TextButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => RegisterScreen(isDriver: widget.isDriver))),
        child: Text("ليس لديك حساب؟ سجل الآن", style: TextStyle(color: Colors.amber))
      )
    ]))
  );
}

// --- 3. شاشة إنشاء الحساب (Register Screen) ---
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
  final _carInfo = TextEditingController(); 
  bool isLoading = false;

  _register() async {
    setState(() => isLoading = true);
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
    } catch (e) { 
      print("Register Error: $e"); 
    } finally {
      setState(() => isLoading = false);
    }
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
      isLoading 
        ? CircularProgressIndicator() 
        : ElevatedButton(
            onPressed: _register, 
            child: Text("إنشاء الحساب"), 
            style: ElevatedButton.styleFrom(minimumSize: Size(double.infinity, 55), backgroundColor: Colors.amber, foregroundColor: Colors.black)
          )
    ])),
  );
}