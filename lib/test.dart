import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart'; 
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'constants.dart';

class ActiveDeliveryScreen extends StatefulWidget {
  final int deliveryId; 
  final String token;
  final bool isDeliveryBoy; 

  ActiveDeliveryScreen({required this.deliveryId, required this.token, required this.isDeliveryBoy});

  @override
  _ActiveDeliveryScreenState createState() => _ActiveDeliveryScreenState();
}

class _ActiveDeliveryScreenState extends State<ActiveDeliveryScreen> {
  Map? order;
  String status = "accepted";
  Timer? _timer;
  LatLng? messengerPos; 
  double _currentHeading = 0.0; 
  
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchOrderDetails();
    });
    
    _timer = Timer.periodic(Duration(seconds: 4), (t) {
      if (mounted) _fetchOrderDetails();
    });

    if (widget.isDeliveryBoy) {
      _startLiveLocationTracking();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startLiveLocationTracking() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    Timer.periodic(Duration(seconds: 5), (t) async {
      if (status == 'completed' || status == 'cancelled' || !mounted) {
        t.cancel();
        return;
      }

      try {
        Position pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high
        );

        await http.post(
          Uri.parse("$apiBaseUrl/driver/update-location"),
          headers: {
            'Authorization': 'Bearer ${widget.token}',
            'Content-Type': 'application/json',
            'Accept': 'application/json'
          },
          body: json.encode({
            'lat': pos.latitude,
            'lng': pos.longitude,
            'heading': pos.heading,
          }),
        );
      } catch (e) {
        print("خطأ في تحديث موقع المندوب: $e");
      }
    });
  }

  _fetchOrderDetails() async {
    if (!mounted) return;
    try {
      final res = await http.get(
        Uri.parse("$apiBaseUrl/trips/${widget.deliveryId}"), 
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json'
        }
      );
      
      if (res.statusCode == 200 && mounted) {
        final data = json.decode(res.body);
        setState(() {
          order = data;
          status = order!['status'] ?? "accepted";
          
          if (order!['messenger'] != null) {
            var mData = order!['messenger'];
            double? lat = double.tryParse(mData['lat']?.toString() ?? "");
            double? lng = double.tryParse(mData['lng']?.toString() ?? "");
            _currentHeading = double.tryParse(mData['heading']?.toString() ?? "0.0") ?? 0.0;

            if (lat != null && lng != null) {
              messengerPos = LatLng(lat, lng);
              if (!widget.isDeliveryBoy && status == "accepted") {
                try {
                  _mapController.move(messengerPos!, 16.0);
                } catch (e) {}
              }
            }
          }
        });
        
        if (status == 'completed' || status == 'cancelled') _timer?.cancel();
      }
    } catch (e) {
      print("خطأ في جلب بيانات الطلب: $e");
    }
  }

  _makeCall(String phone) async {
    final Uri url = Uri.parse("tel:$phone");
    if (await canLaunchUrl(url)) await launchUrl(url);
  }

  _openInExternalMaps(double lat, double lng) async {
    final Uri url = Uri.parse("google.navigation:q=$lat,$lng&mode=d");
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (order == null) return Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator(color: Colors.orange)));

    double sLat = double.tryParse(order!['store_lat'].toString()) ?? 33.3128;
    double sLng = double.tryParse(order!['store_long'].toString()) ?? 44.3615;
    double cLat = double.tryParse(order!['customer_lat'].toString()) ?? 33.3128;
    double cLng = double.tryParse(order!['customer_long'].toString()) ?? 44.3615;

    // جلب سعر البضاعة الأصلي بدون خصومات أو حساب مسافات
    String itemPrice = order!['price']?.toString() ?? "0";

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isDeliveryBoy ? "تتبع مسار التوصيل" : "تتبع وصول طلبك"),
        backgroundColor: Colors.black, foregroundColor: Colors.orange,
        elevation: 0,
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: Text("المبلغ: $itemPrice د.ع", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          )
        ],
      ),
      body: Stack(children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: messengerPos ?? LatLng(sLat, sLng), 
            initialZoom: 15.0,
          ),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
            MarkerLayer(markers: [
              Marker(point: LatLng(sLat, sLng), child: Icon(Icons.store, color: Colors.blue, size: 40)), 
              Marker(point: LatLng(cLat, cLng), child: Icon(Icons.home, color: Colors.red, size: 40)), 
              if (messengerPos != null)
                Marker(
                  point: messengerPos!, 
                  width: 50, height: 50, 
                  child: _buildMessengerMarker()
                ),
            ])
          ]
        ),
        
        Align(alignment: Alignment.bottomCenter, child: Container(
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.95),
            borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
            border: Border.all(color: Colors.orange.withOpacity(0.4))
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(15)),
              child: Text(_getStatusArabic(status), style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
            ),
            
            if (status == "completed" || status == "cancelled") ...[
               const SizedBox(height: 15),
               _buildDeliverySummary() // هذا يظهر للجميع عند الانتهاء
            ] else ...[
               ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(radius: 25, backgroundColor: Colors.orange, child: Icon(widget.isDeliveryBoy ? Icons.person : Icons.delivery_dining, color: Colors.black)),
                title: Text(
                  widget.isDeliveryBoy ? "العميل: ${order!['customer']?['name'] ?? '...'}" : "المندوب: ${order!['messenger']?['name'] ?? '...'}",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)
                ),
                subtitle: Text(
                  "مبلغ البضاعة: $itemPrice د.ع",
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                trailing: IconButton(
                  icon: CircleAvatar(backgroundColor: Colors.green, child: Icon(Icons.phone, color: Colors.white, size: 20)),
                  onPressed: () {
                    var target = widget.isDeliveryBoy ? order!['customer'] : order!['messenger'];
                    if (target != null && target['phone'] != null) {
                      _makeCall(target['phone'].toString());
                    }
                  },
                ),
              ),

              Divider(color: Colors.white12),

              if (widget.isDeliveryBoy) ...[
                ElevatedButton.icon(
                  onPressed: () => _openInExternalMaps(
                    (status == "accepted" || status == "arrived") ? sLat : cLat,
                    (status == "accepted" || status == "arrived") ? sLng : cLng,
                  ),
                  icon: Icon(Icons.directions, color: Colors.white),
                  label: Text(status == "ongoing" ? "التوجه لمنزل العميل" : "التوجه للمتجر"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent, 
                    foregroundColor: Colors.white, 
                    minimumSize: Size(double.infinity, 48), 
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                  ),
                ),
                SizedBox(height: 10),
                _buildMessengerActions(),
              ]
            ]
          ]),
        ))
      ]),
    );
  }

  Widget _buildDeliverySummary() {
  return Container(
    width: double.infinity,
    padding: EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: Colors.white10, 
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: status == 'cancelled' ? Colors.red : Colors.green)
    ),
    child: Column(children: [
      Icon(
        status == 'cancelled' ? Icons.cancel_outlined : Icons.check_circle_outline, 
        color: status == 'cancelled' ? Colors.red : Colors.green, 
        size: 45
      ),
      SizedBox(height: 8),
      Text(
        status == 'cancelled' ? "تم إلغاء هذا الطلب" : "تم التوصيل بنجاح", 
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
      ),
      SizedBox(height: 20),
      
      ElevatedButton(
        onPressed: () {
          // العودة للوحة التحكم (الرئيسية)
          Navigator.pushNamedAndRemoveUntil(context, '/store_dashboard', (route) => false);
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orange,
          foregroundColor: Colors.black,
          minimumSize: Size(double.infinity, 45),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
        ),
        child: Text("العودة للقائمة الرئيسية", style: TextStyle(fontWeight: FontWeight.bold)),
      )
    ]),
  );
}

  String _getStatusArabic(String s) {
    switch (s) {
      case "accepted": return "المندوب يتوجه للمتجر";
      case "arrived": return "المندوب في المتجر لاستلام الطلب";
      case "ongoing": return "جاري توصيل الطلب إليك";
      case "completed": return "تم استلام الطلب";
      case "cancelled": return "تم إلغاء الطلب";
      default: return "جاري التحديث...";
    }
  }

  Widget _buildMessengerActions() {
    if (status == "accepted") return _actionBtn("وصلت للمتجر", "arrived");
    if (status == "arrived") return _actionBtn("استلمت الطلب وبدأت التوصيل", "ongoing", color: Colors.blue);
    if (status == "ongoing") return _actionBtn("تم تسليم الطلب للعميل", "completed", color: Colors.green);
    return Container();
  }

  Widget _actionBtn(String txt, String nextStatus, {Color color = Colors.orange}) {
    return ElevatedButton(
      onPressed: () async {
        try {
          final res = await http.post(
            Uri.parse("$apiBaseUrl/trips/${widget.deliveryId}/update-status"),
            headers: {
              'Authorization': 'Bearer ${widget.token}', 
              'Content-Type': 'application/json', 
              'Accept': 'application/json'
            },
            body: json.encode({'status': nextStatus}),
          );
          
          if (res.statusCode == 200) {
            _fetchOrderDetails();
          }
        } catch (e) { print("Error: $e"); }
      },
      child: Text(txt, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color, 
        foregroundColor: Colors.black, 
        minimumSize: Size(double.infinity, 50), 
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
      )
    );
  }

  Widget _buildMessengerMarker() {
    return Transform.rotate(
      angle: _currentHeading * (3.14159 / 180),
      child: Icon(Icons.delivery_dining, color: Colors.orange, size: 40),
    );
  }
}