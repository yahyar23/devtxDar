import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'constants.dart';
import 'active_trip_screen1.dart';

class CaptainDashboard extends StatefulWidget {
  final String token;
  CaptainDashboard({required this.token});

  @override
  _CaptainDashboardState createState() => _CaptainDashboardState();
}

class _CaptainDashboardState extends State<CaptainDashboard> {
  int _currentIndex = 0;
  bool isOnline = false;
  
  List<Map> availableTrips = [];
  final PageController _tripPageController = PageController();

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
    _checkBalance(); // جلب الرصيد فور الدخول
    _initLocationTracking(); 
    
    _fetchTimer = Timer.periodic(Duration(seconds: 5), (t) {
      if (mounted && isOnline) {
        _fetchTrips();
      }
    });

    _countdownTimer = Timer.periodic(Duration(seconds: 1), (t) {
      _updateTripTimers();
    });
  }

  @override
  void dispose() {
    _fetchTimer?.cancel();
    _countdownTimer?.cancel();
    _positionStreamSubscription?.cancel();
    _voucherController.dispose();
    _tripPageController.dispose();
    super.dispose();
  }

  // --- منطق المحفظة والشحن (تم تحديث المسار والمنطق) ---
  
  _checkBalance() async {
    try {
      // تم تعديل المسار هنا إلى driver/balance كما طلبت
      final res = await http.get(
        Uri.parse("$apiBaseUrl/driver/balance"),
        headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'},
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        setState(() {
          // جلب الرصيد سواء كان موجباً أو سالباً
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
        Uri.parse("$apiBaseUrl/recharge"),
        headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json', 'Content-Type': 'application/json'},
        body: json.encode({'code': code}),
      );

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        _showSnackBar("تم الشحن بنجاح! رصيدك الجديد: ${data['new_balance']} د.ع", Colors.green);
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.amber, width: 1)),
          title: Text("شحن المحفظة", textAlign: TextAlign.center, style: TextStyle(color: Colors.amber)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(10)),
              child: Column(children: [
                Text("1. حول لزين كاش: 07713072470", style: TextStyle(color: Colors.white, fontSize: 13)),
                SizedBox(height: 5),
                Text("2. سيتم تزويدك بكود التعبئة فوراً", style: TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold)),
              ]),
            ),
            SizedBox(height: 20),
            TextField(
              controller: _voucherController, 
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "أدخل الكود هنا",
                hintStyle: TextStyle(color: Colors.white38),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24), borderRadius: BorderRadius.circular(10)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.amber), borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: Text("إلغاء", style: TextStyle(color: Colors.white70))),
            _isRecharging 
              ? Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(color: Colors.amber))
              : ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
                  onPressed: () => _redeemVoucher(_voucherController.text, setDialogState), 
                  child: Text("تأكيد الشحن", style: TextStyle(fontWeight: FontWeight.bold))
                )
          ],
        ),
      ),
    );
  }

  // --- تتبع الموقع والرحلات ---

  void _updateTripTimers() {
    if (availableTrips.isEmpty) return;
    setState(() {
      availableTrips.removeWhere((trip) {
        DateTime createdAt = DateTime.parse(trip['received_at']);
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
      await http.post(Uri.parse("$apiBaseUrl/driver/update-location"),
        headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'},
        body: {'lat': pos.latitude.toString(), 'lng': pos.longitude.toString(), 'heading': pos.heading.toString()},
      );
    } catch (e) { print(e); }
  }

  Widget _buildCarMarker() {
    return Transform.rotate(
      angle: _currentHeading * (3.14159 / 180),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(width: 42, height: 22, decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(4))),
          Container(
            width: 38, height: 18,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: Colors.grey[800]!, width: 1),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Container(width: 6, height: 12, color: Colors.blueGrey.withOpacity(0.5)),
                Container(width: 10, height: 12, color: Colors.black),
                Container(width: 4, height: 12, color: Colors.blueGrey.withOpacity(0.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  _fetchTrips() async {
    // إذا كان الرصيد سالباً وبقيمة 25 ألف أو أكثر، يمنع جلب الرحلات
    if (balance <= -25000) {
      if (isOnline) setState(() => isOnline = false);
      return;
    }

    try {
      final res = await http.get(Uri.parse("$apiBaseUrl/trips/available"),
        headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'},
      );
      if (res.statusCode == 200) {
        List data = json.decode(res.body);
        setState(() {
          for (var newTrip in data) {
            if (!availableTrips.any((t) => t['id'] == newTrip['id'])) {
              newTrip['received_at'] = DateTime.now().toIso8601String();
              availableTrips.add(newTrip);
            }
          }
        });
      }
    } catch (e) { print("Fetch Error: $e"); }
  }

  _acceptTrip(Map trip) async {
    // فحص إضافي قبل القبول
    if (balance <= -25000) {
      _showSnackBar("حسابك مقيد، يرجى شحن الرصيد لتجنب الحظر", Colors.red);
      return;
    }

    try {
      final res = await http.post(Uri.parse("$apiBaseUrl/trips/${trip['id']}/accept"),
        headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'},
      );
      if (res.statusCode == 200) {
        setState(() => availableTrips.clear());
        Navigator.push(context, MaterialPageRoute(builder: (c) => ActiveTripScreen(tripId: trip['id'], token: widget.token, isDriver: true)));
      } else {
        _showSnackBar("عذراً، لا يمكنك قبول هذه الرحلة", Colors.red);
        setState(() { availableTrips.removeWhere((t) => t['id'] == trip['id']); });
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
        title: Text(_currentIndex == 0 ? "لوحة الكابتن" : "المحفظة"),
        backgroundColor: Colors.black, foregroundColor: Colors.amber,
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
        selectedItemColor: Colors.amber,
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
      options: MapOptions(initialCenter: myPos, initialZoom: 16),
      children: [
        TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
        MarkerLayer(markers: [ Marker(point: myPos, width: 60, height: 60, child: _buildCarMarker()) ])
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
              _showSnackBar("لا يمكنك تفعيل الوضع المتصل، يرجى الشحن أولاً", Colors.red);
            } else {
              setState(() => isOnline = v);
            }
          }
        ),
      ),
    ])),
    
    // تنبيه الرصيد في الواجهة الرئيسية
    if (balance <= -20000)
      Positioned(
        top: 70, left: 20, right: 20,
        child: Container(
          padding: EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.red.withOpacity(0.9), borderRadius: BorderRadius.circular(10)),
          child: Text(
            balance <= -25000 ? "حسابك محظور مؤقتاً، يرجى شحن الرصيد" : "تنبيه: رصيدك قارب على الحد الأدنى، يرجى الشحن لتجنب الحظر",
            style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
        ),
      ),

    if (availableTrips.isNotEmpty) _buildTripsSlider(),
  ]);

  // --- واجهة المحفظة المحدثة ---
  Widget _buildWallet() {
    bool isWarning = balance <= -20000;
    return Container(
      padding: EdgeInsets.all(20),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(30),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: balance < 0 ? [Colors.redAccent, Colors.red[900]!] : [Colors.amber, Colors.orangeAccent]
              ),
              borderRadius: BorderRadius.circular(25),
              boxShadow: [BoxShadow(color: (balance < 0 ? Colors.red : Colors.amber).withOpacity(0.3), blurRadius: 15)]
            ),
            child: Column(children: [
              Text("رصيدك الحالي", style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold)),
              SizedBox(height: 10),
              Text("${balance.toStringAsFixed(0)} د.ع", style: TextStyle(color: Colors.white, fontSize: 35, fontWeight: FontWeight.bold)),
              if (balance < 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text("مستحقات الشركة (12%)", style: TextStyle(color: Colors.white60, fontSize: 12)),
                ),
            ]),
          ),
          if (isWarning)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 15),
              child: Text(
                "عليك الشحن لتجنب حظر حسابك (الحد الأقصى للدين: 25,000 د.ع)",
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          SizedBox(height: 20),
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            tileColor: Colors.grey[900],
            leading: Icon(Icons.add_card, color: Colors.amber),
            title: Text("تعبئة الرصيد كود", style: TextStyle(color: Colors.white)),
            subtitle: Text("عن طريق زين كاش", style: TextStyle(color: Colors.white38)),
            trailing: Icon(Icons.arrow_forward_ios, color: Colors.amber, size: 16),
            onTap: _showTopUpDialog,
          ),
        ],
      ),
    );
  }

  Widget _buildTripsSlider() => Align(
    alignment: Alignment.bottomCenter,
    child: Container(
      height: 320, 
      child: PageView.builder(
        controller: _tripPageController,
        itemCount: availableTrips.length,
        itemBuilder: (context, index) => _buildTripCard(availableTrips[index]),
      ),
    ),
  );

  Widget _buildTripCard(Map trip) {
    int timeLeft = 20 - DateTime.now().difference(DateTime.parse(trip['received_at'])).inSeconds;
    if (timeLeft < 0) timeLeft = 0;

    return Container(
      margin: EdgeInsets.all(12),
      padding: EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.95),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.amber, width: 1.5),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text("طلب رحلة جديد", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 18)),
          CircleAvatar(radius: 16, backgroundColor: Colors.red, child: Text("$timeLeft", style: TextStyle(color: Colors.white, fontSize: 13))),
        ]),
        Divider(color: Colors.white24, height: 20),
        _tripRow(Icons.radio_button_checked, "الانطلاق: ${trip['pickup_location']}", Colors.green),
        SizedBox(height: 8),
        _tripRow(Icons.location_on, "الوجهة: ${trip['dropoff_location']}", Colors.red),
        SizedBox(height: 12),
        Text("السعر التقديري: ${trip['fare']} د.ع", style: TextStyle(color: Colors.greenAccent, fontSize: 20, fontWeight: FontWeight.bold)),
        Spacer(),
        Row(children: [
          Expanded(child: TextButton(onPressed: () => setState(() => availableTrips.remove(trip)), child: Text("تجاهل", style: TextStyle(color: Colors.white70)))),
          SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onLongPress: () => _acceptTrip(trip),
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(12)),
                child: Center(child: Text("قبول (نقر مطول)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black))),
              ),
            ),
          ),
        ])
      ]),
    );
  }

  Widget _tripRow(IconData icon, String text, Color color) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
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