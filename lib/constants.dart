import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_screens.dart';

const String apiBaseUrl = "http://localhost/my-taxi-project/public/api";

// نظام تسجيل الخروج الموحد
Future<void> logout(BuildContext context) async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (c) => WelcomeScreen()), (r) => false);
}