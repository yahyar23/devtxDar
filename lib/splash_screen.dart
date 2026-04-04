import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_screens.dart';
import 'delivery_dashboard.dart';
import 'customer_dashboard.dart';

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
        role == 'driver' ? MessengerDashboard(token: token) : StoreDashboard(token: token)));
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => WelcomeScreen()));
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: Icon(Icons.local_taxi, size: 100, color: Colors.amber)));
}