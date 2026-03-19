import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'constants.dart'; // للوصول لـ apiBaseUrl

class ActiveTripScreen extends StatefulWidget {
  final int tripId;
  final String token;
  final bool isDriver;

  ActiveTripScreen({required this.tripId, required this.token, required this.isDriver});

  @override
  _ActiveTripScreenState createState() => _ActiveTripScreenState();
}

class _ActiveTripScreenState extends State<ActiveTripScreen> {
  Map? trip;
  String status = "accepted";
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _fetch();
    // تحديث تلقائي لبيانات الرحلة كل 5 ثوانٍ
    _timer = Timer.periodic(Duration(seconds: 5), (t) => _fetch());
  }

  @override
  void dispose() {
    _timer?.cancel(); // إيقاف التحديث عند إغلاق الشاشة
    super.dispose();
  }

  // جلب بيانات الرحلة الحالية
  _fetch() async {
    if (!mounted) return;
    try {
      final res = await http.get(
        Uri.parse("$apiBaseUrl/trips/${widget.tripId}"), 
        headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'}
      );
      if (res.statusCode == 200) {
        setState(() {
          trip = json.decode(res.body);
          status = trip!['status'] ?? "accepted";
        });
        // إذا انتهت الرحلة أو ألغيت، نتوقف عن التحديث
        if (status == 'completed' || status == 'cancelled') {
          _timer?.cancel();
        }
      }
    } catch (e) {
      print("Fetch Trip Error: $e");
    }
  }

  // تحديث حالة الرحلة (خاص بالسائق)
  _updateStatus(String newStatus) async {
    final res = await http.post(
      Uri.parse("$apiBaseUrl/trips/${widget.tripId}/status"), 
      headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'}, 
      body: {'status': newStatus}
    );
    if (res.statusCode == 200) _fetch();
  }

  @override
  Widget build(BuildContext context) {
    if (trip == null) return Scaffold(body: Center(child: CircularProgressIndicator()));

    // تحديد الإحداثيات (موقع الانطلاق كمثال)
    double lat = double.tryParse(trip!['pickup_lat'].toString()) ?? 33.3128;
    double lng = double.tryParse(trip!['pickup_long'].toString()) ?? 44.3615;

    return Scaffold(
      appBar: AppBar(title: Text("تفاصيل الرحلة الحالية"), leading: Container()), 
      body: Stack(children: [
        // عرض الخريطة
        FlutterMap(
          options: MapOptions(initialCenter: LatLng(lat, lng), initialZoom: 15), 
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
            MarkerLayer(markers: [
              Marker(point: LatLng(lat, lng), child: Icon(Icons.person_pin_circle, color: Colors.blue, size: 40))
            ])
          ]
        ),
        
        // لوحة التحكم السفلية
        Align(alignment: Alignment.bottomCenter, child: Container(
          padding: EdgeInsets.all(25), 
          decoration: BoxDecoration(
            color: Colors.black, 
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            boxShadow: [BoxShadow(color: Colors.amber.withOpacity(0.2), blurRadius: 10)]
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              widget.isDriver ? "الزبون: ${trip!['customer']?['name'] ?? '...'}" : "الكابتن: ${trip!['driver']?['name'] ?? '...'}", 
              style: TextStyle(fontSize: 20, color: Colors.amber, fontWeight: FontWeight.bold)
            ),
            Text("المبلغ التقديري: ${trip!['fare'] ?? '0'} د.ع", style: TextStyle(color: Colors.white70)),
            SizedBox(height: 20),
            
            // أزرار التحكم للسائق
            if (widget.isDriver) ...[
               if (status == "accepted") _btn("وصلت لنقطة الانطلاق", () => _updateStatus("arrived")),
               if (status == "arrived") _btn("ركب الزبون (بدء الرحلة)", () => _updateStatus("ongoing")), 
               if (status == "ongoing") _btn("إتمام الرحلة", () => _showFinishDialog(), color: Colors.green),
            ] 
            // رسائل الحالة للزبون
            else ...[
               Text(
                 status == "arrived" ? "الكابتن وصل لموقعك!" : 
                 status == "ongoing" ? "أنت في الرحلة الآن..." : 
                 status == "completed" ? "وصلت بسلام!" : "الكابتن في الطريق إليك...", 
                 style: TextStyle(fontSize: 18, color: Colors.amber, fontWeight: FontWeight.w500)
               ),
               if (status == "completed") ...[
                 SizedBox(height: 10), 
                 _btn("العودة للرئيسية", () => Navigator.pop(context), color: Colors.green)
               ]
            ]
          ]),
        ))
      ]),
    );
  }

  // نافذة إنهاء الرحلة وإدخال المبلغ المستلم
  _showFinishDialog() {
    final c = TextEditingController(text: trip!['fare'].toString());
    showDialog(context: context, builder: (d) => AlertDialog(
      title: Text("إتمام الرحلة"),
      content: TextField(
        controller: c, 
        keyboardType: TextInputType.number, 
        decoration: InputDecoration(labelText: "المبلغ الفعلي المستلم (د.ع)")
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text("إلغاء")),
        ElevatedButton(
          onPressed: () async {
            final res = await http.post(
              Uri.parse("$apiBaseUrl/trips/${widget.tripId}/finish"), 
              headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'}, 
              body: {'amount': c.text}
            );
            if (res.statusCode == 200) { 
              Navigator.pop(d); 
              Navigator.pop(context); 
            }
          }, 
          child: Text("تأكيد وإنهاء")
        )
      ],
    ));
  }

  Widget _btn(String t, VoidCallback f, {Color color = Colors.amber}) => ElevatedButton(
    onPressed: f, 
    child: Text(t), 
    style: ElevatedButton.styleFrom(
      backgroundColor: color, 
      foregroundColor: Colors.black, 
      minimumSize: Size(double.infinity, 55),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
    )
  );
}