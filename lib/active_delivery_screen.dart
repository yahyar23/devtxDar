import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart'; 
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'constants.dart';
import 'customer_dashboard.dart'; 

class ActiveDeliveryScreen extends StatefulWidget {
  final int deliveryId; // تم تغيير المسمى من رحلة إلى توصيل
  final String token;
  final bool isDeliveryBoy; // هل المستخدم هو مندوب التوصيل؟

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

  // تتبع موقع المندوب وإرساله للسيرفر
  void _startLiveLocationTracking() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    Timer.periodic(Duration(seconds: 5), (t) async {
      if (status == 'delivered' || status == 'cancelled' || !mounted) {
        t.cancel();
        return;
      }

      try {
        Position pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high
        );

        await http.post(
          Uri.parse("$apiBaseUrl/messenger/update-location"),
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
                } catch (e) {
                  print("خريطة التتبع غير جاهزة بعد");
                }
              }
            }
          }
        });
        
        if (status == 'delivered' || status == 'cancelled') _timer?.cancel();
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
    } else {
      await launchUrl(Uri.parse("https://www.google.com/maps/search/?api=1&query=$lat,$lng"), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (order == null) return Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator(color: Colors.orange)));

    // إحداثيات المتجر (Pickup) وإحداثيات العميل (Dropoff)
    double sLat = double.tryParse(order!['store_lat'].toString()) ?? 33.3128;
    double sLng = double.tryParse(order!['store_long'].toString()) ?? 44.3615;
    double cLat = double.tryParse(order!['customer_lat'].toString()) ?? 33.3128;
    double cLng = double.tryParse(order!['customer_long'].toString()) ?? 44.3615;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isDeliveryBoy ? "تتبع مسار التوصيل" : "تتبع وصول طلبك"),
        backgroundColor: Colors.black, foregroundColor: Colors.orange,
        elevation: 0,
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
              Marker(point: LatLng(sLat, sLng), child: Icon(Icons.store, color: Colors.blue, size: 40)), // أيقونة المتجر
              Marker(point: LatLng(cLat, cLng), child: Icon(Icons.home, color: Colors.red, size: 40)), // أيقونة منزل العميل
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
            
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(radius: 25, backgroundColor: Colors.orange, child: Icon(widget.isDeliveryBoy ? Icons.person : Icons.delivery_dining, color: Colors.black)),
              title: Text(
                widget.isDeliveryBoy ? "العميل: ${order!['customer']?['name'] ?? '...'}" : "المندوب: ${order!['messenger']?['name'] ?? '...'}",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)
              ),
              subtitle: Text(
                widget.isDeliveryBoy ? "العنوان: ${order!['delivery_address']}" : "طلبك في الطريق إليك",
                style: TextStyle(color: Colors.white70, fontSize: 12),
                maxLines: 1, overflow: TextOverflow.ellipsis,
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

            if (widget.isDeliveryBoy && status != 'delivered') ...[
              ElevatedButton.icon(
                onPressed: () => _openInExternalMaps(
                  (status == "accepted" || status == "at_store") ? sLat : cLat,
                  (status == "accepted" || status == "at_store") ? sLng : cLng,
                ),
                icon: Icon(Icons.directions, color: Colors.white),
                label: Text(status == "shipping" ? "التوجه لمنزل العميل" : "التوجه للمتجر"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent, 
                  foregroundColor: Colors.white, 
                  minimumSize: Size(double.infinity, 48), 
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                ),
              ),
              SizedBox(height: 10),
              _buildMessengerActions(),
            ] else if (status == "delivered") ...[
               _buildDeliverySummary()
            ]
          ]),
        ))
      ]),
    );
  }

  Widget _buildDeliverySummary() {
    double deliveryFee = double.tryParse(order!['delivery_fee'].toString()) ?? 0.0;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(15)),
      child: Column(children: [
        Icon(Icons.check_circle_outline, color: Colors.green, size: 45),
        SizedBox(height: 8),
        Text("تم التوصيل بنجاح", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        if (widget.isDeliveryBoy) ...[
           Text("أجور التوصيل: ${deliveryFee.toStringAsFixed(0)} د.ع", style: TextStyle(color: Colors.orangeAccent)),
        ],
        SizedBox(height: 12),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text("إغلاق الواجهة", style: TextStyle(color: Colors.orange)),
        )
      ]),
    );
  }

  String _getStatusArabic(String s) {
    switch (s) {
      case "accepted": return "المندوب يتوجه للمتجر";
      case "at_store": return "المندوب في المتجر لاستلام الطلب";
      case "shipping": return "جاري توصيل الطلب إليك";
      case "delivered": return "تم استلام الطلب";
      case "cancelled": return "تم إلغاء الطلب";
      default: return "جاري التحديث...";
    }
  }

  Widget _buildMessengerActions() {
    if (status == "accepted") return _actionBtn("وصلت للمتجر", "at_store");
    if (status == "at_store") return _actionBtn("استلمت الطلب وبدأت التوصيل", "shipping", color: Colors.blue);
    if (status == "shipping") return _actionBtn("تم تسليم الطلب للعميل", "delivered", color: Colors.green);
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
      child: Container(
        child: Icon(Icons.delivery_dining, color: Colors.orange, size: 40),
      ),
    );
  }
}