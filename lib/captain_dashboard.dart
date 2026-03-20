import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart'; // مكتبة التخزين
import 'constants.dart';
import 'active_trip_screen.dart';

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
  LatLng myPos = LatLng(33.3128, 44.3615); // موقع افتراضي (بغداد)
  final MapController _mapController = MapController();

  final TextEditingController _voucherController = TextEditingController();
  bool _isRecharging = false;
  Timer? _fetchTimer;

  @override
  void initState() {
    super.initState();
    _checkBalance();
    _updateLocation(); // جلب الموقع فور الدخول
    
    // فحص الرحلات كل 5 ثوانٍ إذا كان السائق متاحاً
    _fetchTimer = Timer.periodic(Duration(seconds: 5), (t) {
      if (mounted && isOnline && currentTrip == null) {
        _fetchTrips();
      }
    });
  }

  @override
  void dispose() {
    _fetchTimer?.cancel();
    _voucherController.dispose();
    super.dispose();
  }

  // --- وظيفة تسجيل الخروج ---
  Future<void> _logout() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.clear(); // مسح كل البيانات المخزنة (التوكن والاسم وغيرها)
    
    if (mounted) {
      // العودة لشاشة الترحيب وحذف كل الصفحات السابقة من الذاكرة
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    }
  }

  // --- 1. وظيفة شحن الرصيد (Logic) ---
  Future<void> _redeemVoucher(String code, StateSetter setDialogState) async {
    if (code.isEmpty) return;
    setDialogState(() => _isRecharging = true);

    try {
      final res = await http.post(
        Uri.parse("$apiBaseUrl/recharge"),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode({'code': code}),
      );

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        Navigator.pop(context);
        _voucherController.clear();
        setState(() => balance = double.parse(data['new_balance'].toString()));
        _showSnackBar("تم الشحن بنجاح! الرصيد الجديد: ${data['new_balance']}", Colors.green);
      } else {
        final data = json.decode(res.body);
        _showSnackBar(data['message'] ?? "كود غير صحيح", Colors.red);
      }
    } catch (e) {
      _showSnackBar("خطأ في الاتصال بالسيرفر", Colors.orange);
    } finally {
      if (mounted) setDialogState(() => _isRecharging = false);
    }
  }

  // --- 2. وظائف الموقع والرحلات (Map & Trips) ---
  Future<void> _updateLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    try {
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() => myPos = LatLng(pos.latitude, pos.longitude));
      _mapController.move(myPos, 15.0); // تحريك الخريطة لموقع السائق

      if (isOnline) {
        await http.post(
          Uri.parse("$apiBaseUrl/driver/update-location"),
          headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'},
          body: {'lat': pos.latitude.toString(), 'lng': pos.longitude.toString()},
        );
      }
    } catch (e) { print("Location Error: $e"); }
  }

  _fetchTrips() async {
    try {
      final res = await http.get(
        Uri.parse("$apiBaseUrl/trips/available"),
        headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'},
      );
      if (res.statusCode == 200) {
        List data = json.decode(res.body);
        if (data.isNotEmpty) setState(() => currentTrip = data[0]);
      }
    } catch (e) { print("Fetch Error: $e"); }
  }

  _acceptTrip() async {
    final res = await http.post(
      Uri.parse("$apiBaseUrl/trips/${currentTrip!['id']}/accept"),
      headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'},
    );
    if (res.statusCode == 200) {
      int id = currentTrip!['id'];
      setState(() => currentTrip = null);
      Navigator.push(context, MaterialPageRoute(builder: (c) => ActiveTripScreen(
        tripId: id, token: widget.token, isDriver: true,
      )));
    }
  }

  _checkBalance() async {
    try {
      final res = await http.get(
        Uri.parse("$apiBaseUrl/driver/balance"),
        headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'},
      );
      if (res.statusCode == 200) {
        setState(() => balance = double.tryParse(json.decode(res.body)['balance'].toString()) ?? 0.0);
      }
    } catch (e) { print("Balance Error: $e"); }
  }

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentIndex == 0 ? "لوحة الكابتن" : "المحفظة"),
        backgroundColor: Colors.black, foregroundColor: Colors.amber,
        actions: [
          // إضافة زر تسجيل الخروج هنا
          IconButton(
            icon: Icon(Icons.logout, color: Colors.redAccent),
            onPressed: () {
              showDialog(
                context: context,
                builder: (c) => AlertDialog(
                  title: Text("تسجيل الخروج"),
                  content: Text("هل أنت متأكد من رغبتك في تسجيل الخروج؟"),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c), child: Text("إلغاء")),
                    TextButton(onPressed: _logout, child: Text("خروج", style: TextStyle(color: Colors.red))),
                  ],
                )
              );
            },
          ),
        ],
      ),
      body: IndexedStack(index: _currentIndex, children: [_buildHome(), _buildWallet()]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) { if (i == 1) _checkBalance(); setState(() => _currentIndex = i); },
        selectedItemColor: Colors.amber,
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.map), label: "الرئيسية"),
          BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet), label: "المحفظة"),
        ],
      ),
    );
  }

  // --- واجهة الخريطة ---
  Widget _buildHome() => Stack(children: [
    FlutterMap(
      mapController: _mapController,
      options: MapOptions(initialCenter: myPos, initialZoom: 15),
      children: [
        TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
        MarkerLayer(markers: [Marker(point: myPos, child: Icon(Icons.local_taxi, color: Colors.amber, size: 45))])
      ]
    ),
    Positioned(top: 10, right: 10, child: Column(children: [
      FloatingActionButton(onPressed: _updateLocation, mini: true, backgroundColor: Colors.white, child: Icon(Icons.my_location, color: Colors.black)),
      SizedBox(height: 10),
      Switch(value: isOnline, activeColor: Colors.green, onChanged: (v) => setState(() => isOnline = v)),
    ])),
    if (currentTrip != null) _buildTripPopup(),
  ]);

  // --- واجهة المحفظة ---
  Widget _buildWallet() => Column(children: [
    Container(
      width: double.infinity, padding: EdgeInsets.all(40), color: Colors.black,
      child: Column(children: [
        Text("رصيدك الحالي", style: TextStyle(color: Colors.white70)),
        Text("${balance.toStringAsFixed(0)} د.ع", style: TextStyle(color: Colors.greenAccent, fontSize: 35, fontWeight: FontWeight.bold)),
      ]),
    ),
    Padding(
      padding: const EdgeInsets.all(20.0),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _walletAction(Icons.history, "السجل", () {}),
        _walletAction(Icons.add_card, "تعبئة رصيد", () => _showTopUpDialog()),
        _walletAction(Icons.help_outline, "الدعم", () {}),
      ]),
    ),
  ]);

  Widget _walletAction(IconData icon, String label, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Column(children: [
      CircleAvatar(radius: 25, backgroundColor: Colors.amber, child: Icon(icon, color: Colors.black)),
      SizedBox(height: 8), 
      Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
    ]),
  );

  // --- نافذة الشحن الاحترافية ---
  _showTopUpDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Column(children: [
            Icon(Icons.account_balance_wallet_outlined, size: 50, color: Colors.amber),
            SizedBox(height: 10),
            Text("شحن المحفظة", style: TextStyle(fontWeight: FontWeight.bold)),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.blueGrey[900], borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                Text("1. حول لزين كاش: 07713072470", style: TextStyle(color: Colors.white, fontSize: 12)),
                Text("2. سيتم تزويدك بكود التعبئة فوراً", style: TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold)),
              ]),
            ),
            SizedBox(height: 20),
            TextField(
              controller: _voucherController, 
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2),
              decoration: InputDecoration(
                hintText: "أدخل الكود هنا", 
                prefixIcon: Icon(Icons.vpn_key, color: Colors.amber),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: Text("إلغاء")),
            _isRecharging 
              ? CircularProgressIndicator() 
              : ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.amber),
                  onPressed: () => _redeemVoucher(_voucherController.text, setDialogState), 
                  child: Text("تأكيد الشحن")
                )
          ],
        ),
      ),
    );
  }

  // --- نافذة الرحلة المنبثقة ---
  Widget _buildTripPopup() => Align(
    alignment: Alignment.bottomCenter,
    child: Container(
      margin: EdgeInsets.all(15), padding: EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.amber)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text("طلب رحلة جديد! 🚖", style: TextStyle(color: Colors.amber, fontSize: 18, fontWeight: FontWeight.bold)),
        Text("من: ${currentTrip!['pickup_location']}", style: TextStyle(color: Colors.white)),
        Text("السعر: ${currentTrip!['fare']} د.ع", style: TextStyle(color: Colors.greenAccent, fontSize: 20)),
        SizedBox(height: 15),
        Row(children: [
          Expanded(child: ElevatedButton(onPressed: () => setState(() => currentTrip = null), child: Text("تجاهل"))),
          SizedBox(width: 10),
          Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black), onPressed: _acceptTrip, child: Text("قبول")))
        ])
      ]),
    ),
  );
}