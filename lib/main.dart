import 'package:flutter/material.dart';
import 'splash_screen.dart';

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