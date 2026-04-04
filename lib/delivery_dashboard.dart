import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'constants.dart';
import 'active_trip_screen1.dart'; // تأكد من تحديث اسم الملف إذا تغير لـ active_delivery_screen

class MessengerDashboard extends StatefulWidget {
  final String token;
  MessengerDashboard({required this.token});

  @override
  _MessengerDashboardState createState() => _MessengerDashboardState();
}

class _MessengerDashboardState extends State<MessengerDashboard> {
  int _currentIndex = 0;
  bool isOnline = false;
  
  List<Map> availableOrders = []; // تم التغيير من Trips إلى Orders
  final PageController _orderPageController = PageController();

  double balance = 0.0;
  LatLng myPos = LatLng(33.3128, 44.3615); 
  final MapController _mapController = MapController();
  
  StreamSubscription<Position>? _positionStreamSubscription; 
  final TextEditingController _voucherController = TextEditingController();
  bool _isRecharging = false;
  Timer? _fetchTimer;
  Timer? _countdownTimer;
  double _currentHeading = 0.0; 

  @override
  void initState() {
    super.initState();
    _checkBalance();
    _initLocationTracking(); 
    
    _fetchTimer = Timer.periodic(Duration(seconds: 5), (t) {
      if (mounted && isOnline) {
        _fetchOrders(); // جلب طلبات التوصيل
      }
    });

    _countdownTimer = Timer.periodic(Duration(seconds: 1), (t) {
      _updateOrderTimers();
    });
  }

  @override
  void dispose() {
    _fetchTimer?.cancel();
    _countdownTimer?.cancel();
    _positionStreamSubscription?.cancel();
    _voucherController.dispose();
    _orderPageController.dispose();
    super.dispose();
  }

  // --- منطق المحفظة (مسارات المندوب) ---
  
  _checkBalance() async {
    try {
      final res = await http.get(
        Uri.parse("$apiBaseUrl/driver/balance"), // تم التعديل لمسار المندوب
        headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'},
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        setState(() {
          balance = double.tryParse(data['balance'].toString()) ?? 0.0;
        });
      }
    } catch (e) { print("Balance Check Error: $e"); }
  }

  _redeemVoucher(String code, StateSetter setDialogState) async {
    if (code.isEmpty) return;
    setDialogState(() => _isRecharging = true);
    try {
      final res = await http.post(
        Uri.parse("$apiBaseUrl/messenger/recharge"), // تم التعديل لمسار شحن المندوب
        headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json', 'Content-Type': 'application/json'},
        body: json.encode({'code': code}),
      );

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        _showSnackBar("تم الشحن بنجاح! الرصيد الجديد: ${data['new_balance']} د.ع", Colors.green);
        _checkBalance(); 
        Navigator.pop(context);
        _voucherController.clear();
      } else {
        _showSnackBar("الكود غير صحيح أو مستخدم مسبقاً", Colors.red);
      }
    } catch (e) {
      _showSnackBar("خطأ في الاتصال بالسيرفر", Colors.orange);
    } finally {
      setDialogState(() => _isRecharging = false);
    }
  }

  _showTopUpDialog() {
    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.grey[900],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.orangeAccent, width: 1)),
          title: Text("شحن محفظة المندوب", textAlign: TextAlign.center, style: TextStyle(color: Colors.orangeAccent)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(10)),
              child: Column(children: [
                Text("1. حول لزين كاش: 07713072470", style: TextStyle(color: Colors.white, fontSize: 13)),
                SizedBox(height: 5),
                Text("2. سيتم تزويدك بكود التعبئة فوراً", style: TextStyle(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold)),
              ]),
            ),
            SizedBox(height: 20),
            TextField(
              controller: _voucherController, 
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "أدخل كود الشحن",
                hintStyle: TextStyle(color: Colors.white38),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24), borderRadius: BorderRadius.circular(10)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.orangeAccent), borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: Text("إلغاء", style: TextStyle(color: Colors.white70))),
            _isRecharging 
              ? Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(color: Colors.orangeAccent))
              : ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent, foregroundColor: Colors.black),
                  onPressed: () => _redeemVoucher(_voucherController.text, setDialogState), 
                  child: Text("تأكيد الشحن", style: TextStyle(fontWeight: FontWeight.bold))
                )
          ],
        ),
      ),
    );
  }

  // --- تتبع الموقع والطلبات ---

  void _updateOrderTimers() {
    if (availableOrders.isEmpty) return;
    setState(() {
      availableOrders.removeWhere((order) {
        DateTime createdAt = DateTime.parse(order['received_at']);
        return DateTime.now().difference(createdAt).inSeconds >= 20;
      });
    });
  }

  Future<void> _initLocationTracking() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    const LocationSettings settings = LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5);
    _positionStreamSubscription = Geolocator.getPositionStream(locationSettings: settings).listen((pos) {
      if (mounted) {
        setState(() {
          myPos = LatLng(pos.latitude, pos.longitude);
          _currentHeading = pos.heading;
        });
        if (isOnline) _sendLocationToServer(pos);
      }
    });
  }

  void _moveToCurrentLocation() {
    _mapController.move(myPos, 16.0);
  }

  Future<void> _sendLocationToServer(Position pos) async {
    try {
      await http.post(Uri.parse("$apiBaseUrl/messenger/update-location"),
        headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'},
        body: {'lat': pos.latitude.toString(), 'lng': pos.longitude.toString(), 'heading': pos.heading.toString()},
      );
    } catch (e) { print(e); }
  }

  // أيقونة مندوب (دراجة توصيل)
  Widget _buildMessengerMarker() {
    return Transform.rotate(
      angle: _currentHeading * (3.14159 / 180),
      child: Icon(Icons.delivery_dining, color: Colors.orangeAccent, size: 40),
    );
  }

  _fetchOrders() async {
    if (balance <= -25000) {
      if (isOnline) setState(() => isOnline = false);
      return;
    }

    try {
      final res = await http.get(Uri.parse("$apiBaseUrl/trips/available"), // مسار الطلبات المتاحة
        headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'},
      );
      if (res.statusCode == 200) {
        List data = json.decode(res.body);
        setState(() {
          for (var newOrder in data) {
            if (!availableOrders.any((o) => o['id'] == newOrder['id'])) {
              newOrder['received_at'] = DateTime.now().toIso8601String();
              availableOrders.add(newOrder);
            }
          }
        });
      }
    } catch (e) { print("Fetch Error: $e"); }
  }

  _acceptOrder(Map order) async {
    if (balance <= -25000) {
      _showSnackBar("حسابك مقيد، يرجى تسديد مستحقات الشركة", Colors.red);
      return;
    }

    try {
      final res = await http.post(Uri.parse("$apiBaseUrl/trips/${order['id']}/accept"),
        headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'},
      );
      if (res.statusCode == 200) {
        setState(() => availableOrders.clear());
        Navigator.push(context, MaterialPageRoute(builder: (c) => ActiveTripScreen(tripId: order['id'], token: widget.token, isDriver: true)));
      } else {
        _showSnackBar("عذراً، الطلب لم يعد متاحاً", Colors.red);
        setState(() { availableOrders.removeWhere((o) => o['id'] == order['id']); });
      }
    } catch (e) { _showSnackBar("حدث خطأ في الاتصال", Colors.orange); }
  }

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg, textAlign: TextAlign.center), backgroundColor: color, behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(_currentIndex == 0 ? "رادار التوصيل" : "محفظة المندوب"),
        backgroundColor: Colors.black, foregroundColor: Colors.orangeAccent,
        actions: [ IconButton(icon: Icon(Icons.logout), onPressed: () => _logout()) ],
      ),
      body: IndexedStack(index: _currentIndex, children: [_buildHome(), _buildWallet()]),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.black,
        unselectedItemColor: Colors.white54,
        currentIndex: _currentIndex,
        onTap: (i) {
          setState(() => _currentIndex = i);
          if (i == 1) _checkBalance(); 
        },
        selectedItemColor: Colors.orangeAccent,
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.delivery_dining), label: "الطلبات"),
          BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet), label: "المحفظة"),
        ],
      ),
    );
  }

  Widget _buildHome() => Stack(children: [
    FlutterMap(
      mapController: _mapController,
      options: MapOptions(initialCenter: myPos, initialZoom: 16),
      children: [
        TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
        MarkerLayer(markers: [ Marker(point: myPos, width: 60, height: 60, child: _buildMessengerMarker()) ])
      ]
    ),
    Positioned(top: 10, right: 10, child: Column(children: [
      FloatingActionButton(
        heroTag: "loc_btn",
        onPressed: _moveToCurrentLocation, 
        mini: true, 
        backgroundColor: Colors.white, 
        child: Icon(Icons.my_location, color: Colors.black)
      ),
      SizedBox(height: 10),
      Container(
        padding: EdgeInsets.all(4),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
        child: Switch(
          value: isOnline, 
          activeColor: Colors.green, 
          onChanged: (v) {
            if (v && balance <= -25000) {
              _showSnackBar("يرجى شحن المحفظة لتتمكن من استقبال الطلبات", Colors.red);
            } else {
              setState(() => isOnline = v);
            }
          }
        ),
      ),
    ])),
    
    if (balance <= -20000)
      Positioned(
        top: 70, left: 20, right: 20,
        child: Container(
          padding: EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.red.withOpacity(0.9), borderRadius: BorderRadius.circular(10)),
          child: Text(
            balance <= -25000 ? "حسابك متوقف مؤقتاً، يرجى تسديد الديون" : "تنبيه: ديون الشركة مرتفعة، يرجى الشحن لتجنب التوقف",
            style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
        ),
      ),

    if (availableOrders.isNotEmpty) _buildOrdersSlider(),
  ]);

  Widget _buildWallet() {
    return Container(
      padding: EdgeInsets.all(20),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(30),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: balance < 0 ? [Colors.redAccent, Colors.red[900]!] : [Colors.orangeAccent, Colors.deepOrange]
              ),
              borderRadius: BorderRadius.circular(25),
              boxShadow: [BoxShadow(color: (balance < 0 ? Colors.red : Colors.orange).withOpacity(0.3), blurRadius: 15)]
            ),
            child: Column(children: [
              Text("الرصيد المتاح", style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold)),
              SizedBox(height: 10),
              Text("${balance.toStringAsFixed(0)} د.ع", style: TextStyle(color: Colors.white, fontSize: 35, fontWeight: FontWeight.bold)),
              if (balance < 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text("ديون مستحقة للشركة", style: TextStyle(color: Colors.white60, fontSize: 12)),
                ),
            ]),
          ),
          SizedBox(height: 20),
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            tileColor: Colors.grey[900],
            leading: Icon(Icons.add_card, color: Colors.orangeAccent),
            title: Text("تعبئة رصيد المندوب", style: TextStyle(color: Colors.white)),
            subtitle: Text("عبر زين كاش", style: TextStyle(color: Colors.white38)),
            trailing: Icon(Icons.arrow_forward_ios, color: Colors.orangeAccent, size: 16),
            onTap: _showTopUpDialog,
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersSlider() => Align(
    alignment: Alignment.bottomCenter,
    child: Container(
      height: 320, 
      child: PageView.builder(
        controller: _orderPageController,
        itemCount: availableOrders.length,
        itemBuilder: (context, index) => _buildOrderCard(availableOrders[index]),
      ),
    ),
  );

  Widget _buildOrderCard(Map order) {
    int timeLeft = 20 - DateTime.now().difference(DateTime.parse(order['received_at'])).inSeconds;
    if (timeLeft < 0) timeLeft = 0;

    return Container(
      margin: EdgeInsets.all(12),
      padding: EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.95),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.orangeAccent, width: 1.5),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text("📦 طلب توصيل جديد", style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 18)),
          CircleAvatar(radius: 16, backgroundColor: Colors.red, child: Text("$timeLeft", style: TextStyle(color: Colors.white, fontSize: 13))),
        ]),
        Divider(color: Colors.white24, height: 20),
        _orderRow(Icons.store, "من: ${order['pickup_location']}", Colors.green),
        SizedBox(height: 8),
        _orderRow(Icons.person_pin_circle, "إلى: ${order['dropoff_location']}", Colors.red),
        SizedBox(height: 12),
        Text("أجرة التوصيل: ${order['fare']} د.ع", style: TextStyle(color: Colors.greenAccent, fontSize: 20, fontWeight: FontWeight.bold)),
        Spacer(),
        Row(children: [
          Expanded(child: TextButton(onPressed: () => setState(() => availableOrders.remove(order)), child: Text("تجاهل", style: TextStyle(color: Colors.white70)))),
          SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onLongPress: () => _acceptOrder(order),
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(color: Colors.orangeAccent, borderRadius: BorderRadius.circular(12)),
                child: Center(child: Text("استلام الطلب (مطول)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black))),
              ),
            ),
          ),
        ])
      ]),
    );
  }

  Widget _orderRow(IconData icon, String text, Color color) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Icon(icon, color: color, size: 20),
    SizedBox(width: 10),
    Expanded(child: Text(text, style: TextStyle(color: Colors.white, fontSize: 14, height: 1.2), maxLines: 2, overflow: TextOverflow.ellipsis)),
  ]);

  _logout() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }
}