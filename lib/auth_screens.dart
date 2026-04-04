import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb; 
import 'constants.dart';
import 'delivery_dashboard.dart'; // يفضل لاحقاً تغيير الاسم لـ delivery_dashboard
import 'customer_dashboard.dart';

void main() => runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark, 
        colorSchemeSeed: Colors.blueAccent, // تغيير اللون للأزرق ليعطي طابع احترافي للتوصيل
      ),
      home: WelcomeScreen(),
    ));

// --- 1. شاشة الترحيب (Welcome Screen) ---
class WelcomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          // تم تغيير الأيقونة لأيقونة صندوق/توصيل
          Icon(Icons.local_shipping_rounded, size: 120, color: Colors.blueAccent),
          const SizedBox(height: 10),
          const Text("بغداد للتوصيل السريع", 
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          const Text("خدمة نقل الطرود والبضائع", 
              style: TextStyle(fontSize: 16, color: Colors.grey)),
          const SizedBox(height: 50),
          _btn(context, "أنا مرسل طلبات (Customer)", Colors.white, () => _go(context, false)),
          const SizedBox(height: 20),
          _btn(context, "أنا مندوب توصيل (Delivery)", Colors.blueAccent, () => _go(context, true)),
        ])));

  _go(context, isDriver) => Navigator.push(context, MaterialPageRoute(builder: (c) => LoginScreen(isDriver: isDriver)));

  _btn(context, txt, col, tap) => ElevatedButton(
      onPressed: tap,
      child: Text(txt),
      style: ElevatedButton.styleFrom(
          backgroundColor: col,
          foregroundColor: Colors.black,
          minimumSize: const Size(280, 60),
          elevation: 5,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))));
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

  bool _validatePhone(String phone) {
    final regex = RegExp(r'^(077|77|078|78|079|79|075|75)\d+$');
    if (!regex.hasMatch(phone)) return false;
    if (phone.length < 10 || phone.length > 11) return false;
    return true;
  }

  _login() async {
    if (!_validatePhone(_phone.text)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("الرقم الذي ادخلته غير صحيح")));
      return;
    }

    setState(() => isLoading = true);
    try {
      final res = await http.post(Uri.parse("$apiBaseUrl/login"),
          headers: {'Accept': 'application/json'},
          body: {'phone': _phone.text, 'password': _pass.text});

      final data = json.decode(res.body);

      if (res.statusCode == 200) {
        if (data['user']['role'] == 'driver' && data['user']['status'] != 'active') {
          _showStatusDialog("حسابك قيد المراجعة. سيتم تفعيل حساب المندوب بعد التأكد من الوثائق.");
          return;
        }

        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['token']);
        await prefs.setString('role', data['user']['role']);

        Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
                builder: (c) => data['user']['role'] == 'driver'
                    ? MessengerDashboard(token: data['token'])
                    : StoreDashboard(token: data['token'])),
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
      appBar: AppBar(title: Text(widget.isDriver ? "دخول المندوبين" : "دخول المستخدمين")),
      body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            const SizedBox(height: 20),
            Icon(widget.isDriver ? Icons.delivery_dining : Icons.person_pin, size: 80, color: Colors.blueAccent),
            const SizedBox(height: 20),
            TextField(
                controller: _phone,
                decoration: const InputDecoration(
                  labelText: "رقم الهاتف",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                ),
                keyboardType: TextInputType.phone),
            const SizedBox(height: 15),
            TextField(
                controller: _pass, 
                obscureText: true, 
                decoration: const InputDecoration(
                  labelText: "كلمة السر",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                )),
            const SizedBox(height: 30),
            isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _login,
                    child: const Text("تسجيل الدخول", style: TextStyle(fontSize: 18)),
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 55),
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white)),
            TextButton(
                onPressed: () =>
                    Navigator.push(context, MaterialPageRoute(builder: (c) => RegisterScreen(isDriver: widget.isDriver))),
                child: const Text("ليس لديك حساب؟ سجل الآن", style: TextStyle(color: Colors.blueAccent)))
          ])));
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
  final _carColor = TextEditingController();
  final _carPlate = TextEditingController();

  String? selectedBrand;
  String? selectedModel;
  String? selectedYear;

  // تم تعديل البيانات لتشمل مركبات التوصيل الشائعة أيضاً
  final Map<String, List<String>> carData = {
    'تويوتا': ['كورولا', 'هايلوكس', 'برادوا', 'تويوتا بيك آب'],
    'هيونداي': ['إلنترا', 'ستاريكس (باص)', 'H100'],
    'كيا': ['سيراتو', 'بونغو (حمل)', 'ريو'],
    'دراجات نارية': ['باجاج', 'تكتك', 'دراجة شحن'],
    'شيري': ['تيكو', 'أريزو'],
  };

  XFile? imgPersonal, imgIDFront, imgIDBack, imgCarFront, imgCarBack;
  bool isLoading = false;

  bool _validatePhone(String phone) {
    final regex = RegExp(r'^(077|77|078|78|079|79|075|75)\d+$');
    if (!regex.hasMatch(phone)) return false;
    if (phone.length < 10 || phone.length > 11) return false;
    return true;
  }

  Future _pickImg(String type) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (picked != null) {
      setState(() {
        if (type == 'personal') imgPersonal = picked;
        if (type == 'front') imgIDFront = picked;
        if (type == 'back') imgIDBack = picked;
        if (type == 'car_front') imgCarFront = picked;
        if (type == 'car_back') imgCarBack = picked;
      });
    }
  }

  _register() async {
    if (!_validatePhone(_phone.text)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("الرقم الذي ادخلته غير صحيح")));
      return;
    }

    if (_pass.text.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("كلمة السر يجب ألا تقل عن 8 أحرف")));
      return;
    }

    if (widget.isDriver) {
      if (imgPersonal == null || imgIDFront == null || imgIDBack == null || imgCarFront == null || imgCarBack == null || selectedBrand == null || selectedModel == null || selectedYear == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى إكمال كافة البيانات وصور المركبة")));
        return;
      }
    }

    setState(() => isLoading = true);
    try {
      var request = http.MultipartRequest('POST', Uri.parse("$apiBaseUrl/register"));

      request.fields['name'] = _name.text;
      request.fields['phone'] = _phone.text;
      request.fields['password'] = _pass.text;
      request.fields['role'] = widget.isDriver ? 'driver' : 'customer';

      if (widget.isDriver) {
        request.fields['car_brand'] = selectedBrand!;
        request.fields['car_model'] = selectedModel!;
        request.fields['car_year'] = selectedYear!;
        request.fields['car_color'] = _carColor.text;
        request.fields['car_plate'] = _carPlate.text;

        request.files.add(http.MultipartFile.fromBytes('img_personal', await imgPersonal!.readAsBytes(), filename: 'personal.jpg'));
        request.files.add(http.MultipartFile.fromBytes('img_id_front', await imgIDFront!.readAsBytes(), filename: 'id_front.jpg'));
        request.files.add(http.MultipartFile.fromBytes('img_id_back', await imgIDBack!.readAsBytes(), filename: 'id_back.jpg'));
        request.files.add(http.MultipartFile.fromBytes('img_car_front', await imgCarFront!.readAsBytes(), filename: 'car_front.jpg'));
        request.files.add(http.MultipartFile.fromBytes('img_car_back', await imgCarBack!.readAsBytes(), filename: 'car_back.jpg'));
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
              content: Text(widget.isDriver 
                ? "شكراً لتسجيلك كمندوب. طلبك قيد المراجعة حالياً." 
                : "تم إنشاء حسابك بنجاح، يمكنك الآن تسجيل الدخول."),
              actions: [
                TextButton(onPressed: () { Navigator.pop(c); Navigator.pop(context); }, child: const Text("فهمت"))
              ],
            ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.isDriver ? "تسجيل مندوب جديد" : "تسجيل مستخدم جديد")),
        body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              TextField(controller: _name, decoration: const InputDecoration(labelText: "الاسم الكامل", prefixIcon: Icon(Icons.person))),
              TextField(
                  controller: _phone,
                  decoration: const InputDecoration(labelText: "رقم الهاتف", prefixIcon: Icon(Icons.phone)),
                  keyboardType: TextInputType.phone),
              TextField(controller: _pass, obscureText: true, decoration: const InputDecoration(labelText: "كلمة السر (8 محارف على الأقل)", prefixIcon: Icon(Icons.lock))),
              
              if (widget.isDriver) ...[
                const Divider(height: 40, thickness: 1),
                const Text("معلومات مركبة التوصيل", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                const SizedBox(height: 15),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: "نوع المركبة / الشركة"),
                  value: selectedBrand,
                  items: carData.keys.map((brand) => DropdownMenuItem(value: brand, child: Text(brand))).toList(),
                  onChanged: (val) => setState(() { selectedBrand = val; selectedModel = null; }),
                ),
                if (selectedBrand != null)
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: "الموديل"),
                    value: selectedModel,
                    items: carData[selectedBrand]!.map((model) => DropdownMenuItem(value: model, child: Text(model))).toList(),
                    onChanged: (val) => setState(() => selectedModel = val),
                  ),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: "سنة الصنع"),
                  value: selectedYear,
                  items: List.generate(22, (index) => (2005 + index).toString())
                      .map((year) => DropdownMenuItem(value: year, child: Text(year))).toList(),
                  onChanged: (val) => setState(() => selectedYear = val),
                ),
                TextField(controller: _carColor, decoration: const InputDecoration(labelText: "لون المركبة")),
                TextField(controller: _carPlate, decoration: const InputDecoration(labelText: "رقم اللوحة")),
                const SizedBox(height: 20),
                const Text("الوثائق المطلوبة", style: TextStyle(fontWeight: FontWeight.bold)),
                _imgTile("الصورة الشخصية", imgPersonal, () => _pickImg('personal')),
                _imgTile("الهوية (الوجه الأمامي)", imgIDFront, () => _pickImg('front')),
                _imgTile("الهوية (الوجه الخلفي)", imgIDBack, () => _pickImg('back')),
                _imgTile("صورة المركبة من الأمام", imgCarFront, () => _pickImg('car_front')),
                _imgTile("صورة المركبة من الخلف", imgCarBack, () => _pickImg('car_back')),
              ],
              
              const SizedBox(height: 30),
              isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: _register,
                      child: const Text("إرسال طلب التسجيل"),
                      style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 55),
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white))
            ])),
      );

  Widget _imgTile(String title, XFile? file, VoidCallback tap) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: const TextStyle(fontSize: 14)),
      trailing: file == null
          ? TextButton.icon(onPressed: tap, icon: const Icon(Icons.upload_file), label: const Text("إرفاق"))
          : const Icon(Icons.check_circle, color: Colors.green),
    );
  }
}