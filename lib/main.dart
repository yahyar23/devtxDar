import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // لإضافة تحسينات على شريط الحالة
import 'splash_screen.dart';

void main() {
  // لضمان استقرار واجهة المستخدم قبل تشغيل التطبيق
  WidgetsFlutterBinding.ensureInitialized();
  
  // ضبط اتجاه الشاشة وشفافية شريط الحالة (اختياري)
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  runApp(BaghdadDeliveryApp());
}

class BaghdadDeliveryApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'بغداد للتوصيل السريع', // الاسم الجديد للبراند
      
      // إعدادات الثيم (Theme) المحدثة لتلائم تطبيق التوصيل
      theme: ThemeData(
        brightness: Brightness.dark,
        // تم تغيير اللون الأساسي إلى BlueAccent ليعبر عن الثقة والسرعة في التوصيل
        colorSchemeSeed: Colors.blueAccent, 
        useMaterial3: true,
        
        // تحسين الخطوط للغة العربية (يفضل استخدام خط Tajawal إذا كان متوفراً في مشروعك)
        fontFamily: 'Arial', 
        
        // تخصيص شكل الأزرار بشكل عام في التطبيق
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),

      // نقطة الانطلاق لا تزال شاشة الـ Splash
      home: SplashScreen(),
      
      // تعريف اللغات لدعم اتجاه النصوص من اليمين لليسار (RTL) بشكل أفضل
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl, // لضمان ظهور التطبيق بالعربية بشكل صحيح
          child: child!,
        );
      },
    );
  }
}