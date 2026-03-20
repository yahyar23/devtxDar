import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb; // للتحقق من المنصة
import 'constants.dart';
import 'captain_dashboard.dart';
import 'customer_dashboard.dart';

void main() => runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, colorSchemeSeed: Colors.amber),
      home: WelcomeScreen(),
    ));

// --- 1. شاشة الترحيب ---
class WelcomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Scaffold(
          body: Center(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.local_taxi, size: 120, color: Colors.amber),
        const Text("بغداد تاكسي", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
        const SizedBox(height: 40),
        _btn(context, "أنا زبون (Customer)", Colors.white, () => _go(context, false)),
        const SizedBox(height: 20),
        _btn(context, "أنا كابتن (Captain)", Colors.amber, () => _go(context, true)),
      ])));

  _go(context, isDriver) => Navigator.push(context, MaterialPageRoute(builder: (c) => LoginScreen(isDriver: isDriver)));

  _btn(context, txt, col, tap) => ElevatedButton(
      onPressed: tap,
      child: Text(txt),
      style: ElevatedButton.styleFrom(
          backgroundColor: col,
          foregroundColor: Colors.black,
          minimumSize: const Size(250, 60),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))));
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
  bool isLoading = false;

  _login() async {
    setState(() => isLoading = true);
    try {
      final res = await http.post(Uri.parse("$apiBaseUrl/login"),
          headers: {'Accept': 'application/json'},
          body: {'phone': _phone.text, 'password': _pass.text});

      final data = json.decode(res.body);

      if (res.statusCode == 200) {
        if (data['user']['role'] == 'driver' && data['user']['status'] != 'active') {
          _showStatusDialog("حسابك قيد المراجعة حالياً. سيتم إخطارك فور تفعيله من قبل الإدارة.");
          return;
        }

        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['token']);
        await prefs.setString('role', data['user']['role']);

        Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
                builder: (c) => data['user']['role'] == 'driver'
                    ? CaptainDashboard(token: data['token'])
                    : CustomerDashboard(token: data['token'])),
            (r) => false);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['message'] ?? "فشل الدخول")));
      }
    } catch (e) {
      print("Login Error: $e");
    } finally {
      setState(() => isLoading = false);
    }
  }

  _showStatusDialog(String msg) {
    showDialog(
        context: context,
        builder: (c) => AlertDialog(
              title: const Text("تنبيه"),
              content: Text(msg),
              actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text("حسناً"))],
            ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text("تسجيل الدخول")),
      body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            TextField(
                controller: _phone,
                decoration: const InputDecoration(labelText: "رقم الهاتف"),
                keyboardType: TextInputType.phone),
            TextField(controller: _pass, obscureText: true, decoration: const InputDecoration(labelText: "كلمة السر")),
            const SizedBox(height: 30),
            isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _login,
                    child: const Text("دخول"),
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 55),
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.black)),
            TextButton(
                onPressed: () =>
                    Navigator.push(context, MaterialPageRoute(builder: (c) => RegisterScreen(isDriver: widget.isDriver))),
                child: const Text("ليس لديك حساب؟ سجل الآن", style: TextStyle(color: Colors.amber)))
          ])));
}

// --- 3. شاشة إنشاء الحساب المطورة (المتوافقة مع الويب والموبايل) ---
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
  final _carColor = TextEditingController();
  final _carPlate = TextEditingController();

  // نستخدم XFile لأنه يعمل على جميع المنصات
  XFile? imgPersonal, imgIDFront, imgIDBack;
  bool isLoading = false;

  Future _pickImg(String type) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (picked != null) {
      setState(() {
        if (type == 'personal') imgPersonal = picked;
        if (type == 'front') imgIDFront = picked;
        if (type == 'back') imgIDBack = picked;
      });
    }
  }

  _register() async {
    if (widget.isDriver && (imgPersonal == null || imgIDFront == null || imgIDBack == null)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى إرفاق كافة الصور المطلوبة")));
      return;
    }

    setState(() => isLoading = true);
    try {
      var request = http.MultipartRequest('POST', Uri.parse("$apiBaseUrl/register"));

      request.fields['name'] = _name.text;
      request.fields['phone'] = _phone.text;
      request.fields['password'] = _pass.text;
      request.fields['role'] = widget.isDriver ? 'driver' : 'customer';

      if (widget.isDriver) {
        request.fields['car_color'] = _carColor.text;
        request.fields['car_plate'] = _carPlate.text;

        // إرفاق الصور عن طريق الـ Bytes لضمان عملها على الويب
        request.files.add(http.MultipartFile.fromBytes(
          'img_personal',
          await imgPersonal!.readAsBytes(),
          filename: 'personal.jpg',
        ));
        request.files.add(http.MultipartFile.fromBytes(
          'img_id_front',
          await imgIDFront!.readAsBytes(),
          filename: 'id_front.jpg',
        ));
        request.files.add(http.MultipartFile.fromBytes(
          'img_id_back',
          await imgIDBack!.readAsBytes(),
          filename: 'id_back.jpg',
        ));
      }

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 201) {
        _showSuccessAndPop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("فشل التسجيل: تأكد من البيانات")));
      }
    } catch (e) {
      print("Register Error: $e");
    } finally {
      setState(() => isLoading = false);
    }
  }

  _showSuccessAndPop() {
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) => AlertDialog(
              title: const Text("تم استلام طلبك"),
              content: const Text(
                  "شكراً لتسجيلك ككابتن. طلبك قيد المعالجة حالياً، سيتم التواصل معك وتفعيل الحساب بعد مراجعة المستندات."),
              actions: [
                TextButton(
                    onPressed: () {
                      Navigator.pop(c);
                      Navigator.pop(context);
                    },
                    child: const Text("فهمت"))
              ],
            ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.isDriver ? "تسجيل كابتن جديد" : "تسجيل زبون جديد")),
        body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              TextField(controller: _name, decoration: const InputDecoration(labelText: "الاسم الكامل")),
              TextField(
                  controller: _phone,
                  decoration: const InputDecoration(labelText: "رقم الهاتف"),
                  keyboardType: TextInputType.phone),
              TextField(controller: _pass, obscureText: true, decoration: const InputDecoration(labelText: "كلمة السر")),
              if (widget.isDriver) ...[
                const Divider(height: 40),
                TextField(controller: _carColor, decoration: const InputDecoration(labelText: "لون السيارة")),
                TextField(controller: _carPlate, decoration: const InputDecoration(labelText: "رقم اللوحة")),
                const SizedBox(height: 20),
                _imgTile("الصورة الشخصية", imgPersonal, () => _pickImg('personal')),
                _imgTile("الهوية (الوجه الأمامي)", imgIDFront, () => _pickImg('front')),
                _imgTile("الهوية (الوجه الخلفي)", imgIDBack, () => _pickImg('back')),
              ],
              const SizedBox(height: 30),
              isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: _register,
                      child: const Text("إرسال طلب التسجيل"),
                      style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 55),
                          backgroundColor: Colors.amber,
                          foregroundColor: Colors.black))
            ])),
      );

  Widget _imgTile(String title, XFile? file, VoidCallback tap) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: const TextStyle(fontSize: 14)),
      trailing: file == null
          ? ElevatedButton(onPressed: tap, child: const Text("إرفاق"))
          : const Icon(Icons.check_circle, color: Colors.green),
    );
  }
}