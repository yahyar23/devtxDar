import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
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
  List transactions = [];
  LatLng myPos = LatLng(33.3128, 44.3615);
  final MapController _mapController = MapController();

  final TextEditingController _voucherController = TextEditingController();
  bool _isRecharging = false;

  Timer? _fetchTimer;
  Timer? _tripTimeoutTimer;
  int _secondsRemaining = 20;

  @override
  void initState() {
    super.initState();
    _checkBalance();
    _updateLocation();
    _fetchTimer = Timer.periodic(Duration(seconds: 5), (t) {
      if (mounted && isOnline && currentTrip == null) _fetchTrips();
    });
  }

  @override
  void dispose() {
    _fetchTimer?.cancel();
    _tripTimeoutTimer?.cancel();
    _voucherController.dispose();
    super.dispose();
  }

  // --- وظائف المنطق (Logic) ---

  Future<void> _redeemVoucher(String code, StateSetter setDialogState) async {
    if (code.isEmpty) return;

    setDialogState(() => _isRecharging = true);

    try {
      // ملاحظة: تأكد أن apiBaseUrl في constants.dart هو http://10.0.2.2/my-taxi-project/public/api
      final res = await http.post(
        Uri.parse("$apiBaseUrl/recharge"),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode({'code': code}),
      );

      print("Response Status: ${res.statusCode}");
      print("Response Body: ${res.body}");

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        Navigator.pop(context);
        _voucherController.clear();
        setState(() {
          balance = double.parse(data['new_balance'].toString());
        });
        _showSnackBar("تم الشحن بنجاح! الرصيد الجديد: ${data['new_balance']}", Colors.green);
      } else {
        final data = json.decode(res.body);
        _showSnackBar(data['message'] ?? "كود غير صحيح", Colors.red);
      }
    } catch (e) {
      _showSnackBar("خطأ: تأكد من اتصال السيرفر بـ IP الصحيح", Colors.orange);
    } finally {
      if (mounted) setDialogState(() => _isRecharging = false);
    }
  }

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating)
    );
  }

  // (بقية الدوال المساعدة: _fetchTrips, _updateLocation, إلخ تبق كما هي)
  _fetchTrips() async { /* ... نفس الكود السابق ... */ }
  _startTripTimer() { /* ... نفس الكود السابق ... */ }
  _ignoreTrip() { /* ... نفس الكود السابق ... */ }
  _acceptTrip() async { /* ... نفس الكود السابق ... */ }
  _updateLocation() async { /* ... نفس الكود السابق ... */ }
  _checkBalance() async {
    try {
      final res = await http.get(
          Uri.parse("$apiBaseUrl/driver/balance"),
          headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'}
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (mounted) setState(() {
          balance = double.tryParse(data['balance'].toString()) ?? 0.0;
          transactions = data['recent_trips'] ?? [];
        });
      }
    } catch (e) { print("Balance Error: $e"); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentIndex == 0 ? "لوحة الكابتن" : "المحفظة"),
        backgroundColor: Colors.black,
        foregroundColor: Colors.amber,
      ),
      body: IndexedStack(index: _currentIndex, children: [_buildHome(), _buildWallet()]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) { if (i == 1) _checkBalance(); setState(() => _currentIndex = i); },
        selectedItemColor: Colors.amber[800],
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.map), label: "الرئيسية"),
          BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet), label: "المحفظة"),
        ],
      ),
    );
  }

  Widget _buildHome() => Stack(children: [
    FlutterMap(
        mapController: _mapController,
        options: MapOptions(initialCenter: myPos, initialZoom: 15),
        children: [
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
          MarkerLayer(markers: [Marker(point: myPos, child: Icon(Icons.local_taxi, color: Colors.amber, size: 40))])
        ]
    ),
    Positioned(top: 10, right: 10, child: Column(children: [
      FloatingActionButton(onPressed: _updateLocation, child: Icon(Icons.my_location), mini: true, backgroundColor: Colors.white),
      SizedBox(height: 10),
      Switch(value: isOnline, onChanged: (v) => setState(() => isOnline = v), activeColor: Colors.green),
    ])),
    if (currentTrip != null) _buildTripRequestPopup(),
  ]);

  Widget _buildWallet() {
    return Column(children: [
      Container(
        width: double.infinity, padding: EdgeInsets.all(40),
        color: Colors.black,
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
  }

  // --- النافذة المطلوبة مع التعليمات وحقل الكود ---
  _showTopUpDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text("شحن المحفظة", textAlign: TextAlign.center),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // تعليمات زين كاش
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color.fromARGB(255, 1, 9, 15), borderRadius: BorderRadius.circular(12)),
                child: Column(
                  children: [
                    Text("1. حول المبلغ لزين كاش: 07713072470", style: TextStyle(fontSize: 12)),
                    Text("2. أرسل صورة الحوالة للدعم الفني", style: TextStyle(fontSize: 12)),
                    Text("3. سيتم تزويدك بكود التعبئة فوراً", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              SizedBox(height: 20),
              // حقل إدخال الكود
              TextField(
                controller: _voucherController,
                decoration: InputDecoration(
                  hintText: "أدخل كود الشحن هنا",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: Icon(Icons.vignette_rounded),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: Text("إلغاء")),
            _isRecharging 
              ? CircularProgressIndicator()
              : ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.amber),
                  onPressed: () => _redeemVoucher(_voucherController.text, setDialogState), 
                  child: Text("تأكيد وشحن")
                ),
          ],
        ),
      )
    );
  }

  Widget _walletAction(IconData icon, String label, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Column(children: [
      CircleAvatar(radius: 25, backgroundColor: Colors.amber, child: Icon(icon, color: Colors.black)),
      SizedBox(height: 5),
      Text(label, style: TextStyle(fontSize: 12)),
    ]),
  );

  // (دوال الـ UI الأخرى تبق كما هي)
  _showLogoutDialog() { /* ... */ }
  _buildTripRequestPopup() { /* ... */ }
  _locationTile(IconData icon, Color color, String text) { /* ... */ }
}