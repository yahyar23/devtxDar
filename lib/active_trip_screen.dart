import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart'; 
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'constants.dart';

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
    _timer = Timer.periodic(Duration(seconds: 5), (t) => _fetch());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  _fetch() async {
    if (!mounted) return;
    try {
      final res = await http.get(
        Uri.parse("$apiBaseUrl/trips/${widget.tripId}"), 
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json'
        }
      );
      if (res.statusCode == 200) {
        setState(() {
          trip = json.decode(res.body);
          status = trip!['status'] ?? "accepted";
        });
        if (status == 'completed' || status == 'cancelled') _timer?.cancel();
      }
    } catch (e) { print("Fetch Error: $e"); }
  }

  _makeCall(String phone) async {
    final Uri url = Uri.parse("tel:$phone");
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  _openInExternalMaps(double lat, double lng) async {
    final Uri url = Uri.parse("google.navigation:q=$lat,$lng&mode=d");
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      final String webUrl = "https://www.google.com/maps/search/?api=1&query=$lat,$lng";
      await launchUrl(Uri.parse(webUrl), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (trip == null) return Scaffold(body: Center(child: CircularProgressIndicator()));

    double pLat = double.tryParse(trip!['pickup_lat'].toString()) ?? 33.3128;
    double pLng = double.tryParse(trip!['pickup_long'].toString()) ?? 44.3615;
    double dLat = double.tryParse(trip!['dropoff_lat'].toString()) ?? 33.3128;
    double dLng = double.tryParse(trip!['dropoff_long'].toString()) ?? 44.3615;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isDriver ? "تنفيذ الرحلة" : "تتبع رحلتك"),
        backgroundColor: Colors.black,
        foregroundColor: Colors.amber,
      ),
      body: Stack(children: [
        FlutterMap(
          options: MapOptions(initialCenter: LatLng(pLat, pLng), initialZoom: 14),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
            MarkerLayer(markers: [
              Marker(point: LatLng(pLat, pLng), child: Icon(Icons.person_pin_circle, color: Colors.blue, size: 45)),
              Marker(point: LatLng(dLat, dLng), child: Icon(Icons.location_on, color: Colors.red, size: 45)),
            ])
          ]
        ),
        
        Align(alignment: Alignment.bottomCenter, child: Container(
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.grey[900]!.withOpacity(0.95),
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 10)]
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: 15, vertical: 5),
              decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(20)),
              child: Text(_getStatusArabic(status), style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
            ),
            
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(backgroundColor: Colors.amber, child: Icon(Icons.person, color: Colors.black)),
              title: Text(
                widget.isDriver ? "الزبون: ${trip!['customer']?['name'] ?? '...'}" : "الكابتن: ${trip!['driver']?['name'] ?? '...'}",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)
              ),
              subtitle: Text(
                widget.isDriver ? "الموقع: ${trip!['pickup_location']}" : "السيارة: ${trip!['driver']?['car_info'] ?? 'جاري التوجه'}",
                style: TextStyle(color: Colors.white70),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                icon: Icon(Icons.phone, color: Colors.green, size: 35),
                onPressed: () {
                  String phone = widget.isDriver 
                    ? trip!['customer']['phone'].toString() 
                    : trip!['driver']['phone'].toString();
                  _makeCall(phone);
                },
              ),
            ),

            Divider(color: Colors.white24),

            if (widget.isDriver && status != 'completed') ...[
              ElevatedButton.icon(
                onPressed: () => _openInExternalMaps(
                  (status == "accepted" || status == "arrived") ? pLat : dLat,
                  (status == "accepted" || status == "arrived") ? pLng : dLng,
                ),
                icon: Icon(Icons.navigation, color: Colors.black),
                label: Text(status == "ongoing" ? "فتح مسار الوجهة" : "فتح مسار الزبون"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue, 
                  foregroundColor: Colors.white, 
                  minimumSize: Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                ),
              ),
              SizedBox(height: 12),
              _buildDriverActions(),
            ] else if (status == "completed") ...[
               ElevatedButton(
                 onPressed: () => Navigator.pop(context),
                 child: Text("تمت الرحلة بنجاح - عودة"),
                 style: ElevatedButton.styleFrom(
                   backgroundColor: Colors.green, 
                   minimumSize: Size(double.infinity, 55),
                   shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                 )
               )
            ]
          ]),
        ))
      ]),
    );
  }

  String _getStatusArabic(String s) {
    switch (s) {
      case "accepted": return "الكابتن في الطريق إليك";
      case "arrived": return "الكابتن وصل لموقعك";
      case "ongoing": return "الرحلة مستمرة الآن";
      case "completed": return "تم الوصول بسلام";
      case "cancelled": return "تم إلغاء الرحلة";
      default: return "جاري التحديث...";
    }
  }

  Widget _buildDriverActions() {
    if (status == "accepted") return _actionBtn("أنا وصلت للمكان", "arrived");
    if (status == "arrived") return _actionBtn("بدء الرحلة (ركب الزبون)", "ongoing", color: Colors.green);
    if (status == "ongoing") return _actionBtn("إنهاء الرحلة (وصلنا)", "completed", color: Colors.redAccent);
    return Container();
  }

  Widget _actionBtn(String txt, String nextStatus, {Color color = Colors.amber}) {
    return ElevatedButton(
      onPressed: () async {
        // تحديث الرابط بناءً على الحالة المطلوبة
        // إذا كان الإنهاء، نتوجه لمسار finish
        String urlPath = nextStatus == "completed" ? "finish" : "status";
        
        try {
          // نجهز البيانات المرسلة
          Map<String, dynamic> bodyData = {'status': nextStatus};
          
          // إذا كان إنهاء، نرسل المبلغ المخزن في الرحلة كقيمة افتراضية
          if (nextStatus == "completed") {
            bodyData['amount'] = trip!['fare'];
          }

          final res = await http.post(
            Uri.parse("$apiBaseUrl/trips/${widget.tripId}/$urlPath"),
            headers: {
              'Authorization': 'Bearer ${widget.token}',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: json.encode(bodyData),
          );
          
          if (res.statusCode == 200) {
            _fetch();
            if (nextStatus == "completed") {
               ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("تم إنهاء الرحلة بنجاح"))
              );
            }
          } else {
            print("Error Response: ${res.body}");
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("خطأ: ${res.statusCode} - تحقق من الرصيد"))
            );
          }
        } catch (e) {
          print("Connection Error: $e");
        }
      },
      child: Text(txt, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color, 
        foregroundColor: Colors.white, 
        minimumSize: Size(double.infinity, 55),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
      )
    );
  }
}