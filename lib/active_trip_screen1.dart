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
  LatLng? driverPos; 
  double _currentHeading = 0.0; 
  
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetch();
    });
    
    _timer = Timer.periodic(Duration(seconds: 4), (t) {
      if (mounted) _fetch();
    });

    if (widget.isDriver) {
      _startLocationTracking();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startLocationTracking() async {
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
        print("Location update error: $e");
      }
    });
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
      
      if (res.statusCode == 200 && mounted) {
        final data = json.decode(res.body);
        setState(() {
          trip = data;
          status = trip!['status'] ?? "accepted";
          
          if (trip!['driver'] != null) {
            var dData = trip!['driver'];
            double? lat = double.tryParse(dData['lat']?.toString() ?? "");
            double? lng = double.tryParse(dData['lng']?.toString() ?? "");
            _currentHeading = double.tryParse(dData['heading']?.toString() ?? "0.0") ?? 0.0;

            if (lat != null && lng != null) {
              driverPos = LatLng(lat, lng);
              
              if (!widget.isDriver && status == "accepted") {
                try {
                  _mapController.move(driverPos!, 16.0);
                } catch (e) {
                  print("MapController not ready yet: $e");
                }
              }
            }
          }
        });
        
        if (status == 'completed' || status == 'cancelled') _timer?.cancel();
      }
    } catch (e) {
      print("Fetch Error: $e");
    }
  }

  // --- دوال الاتصال والملاحة الخارجية ---
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
    if (trip == null) return Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator(color: Colors.amber)));

    double pLat = double.tryParse(trip!['pickup_lat'].toString()) ?? 33.3128;
    double pLng = double.tryParse(trip!['pickup_long'].toString()) ?? 44.3615;
    double dLat = double.tryParse(trip!['dropoff_lat'].toString()) ?? 33.3128;
    double dLng = double.tryParse(trip!['dropoff_long'].toString()) ?? 44.3615;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isDriver ? "تتبع الزبون والملاحة" : "تتبع وصول الكابتن"),
        backgroundColor: Colors.black, foregroundColor: Colors.amber,
        elevation: 0,
      ),
      body: Stack(children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: driverPos ?? LatLng(pLat, pLng), 
            initialZoom: 15.5,
          ),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
            MarkerLayer(markers: [
              Marker(point: LatLng(pLat, pLng), child: Icon(Icons.person_pin_circle, color: Colors.blue, size: 45)),
              Marker(point: LatLng(dLat, dLng), child: Icon(Icons.location_on, color: Colors.red, size: 45)),
              if (driverPos != null)
                Marker(
                  point: driverPos!, 
                  width: 60, height: 60, 
                  child: _buildMovingCarMarker()
                ),
            ])
          ]
        ),
        
        Align(alignment: Alignment.bottomCenter, child: Container(
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.92),
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            border: Border.all(color: Colors.amber.withOpacity(0.3))
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(20)),
              child: Text(_getStatusArabic(status), style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
            ),
            
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(radius: 25, backgroundColor: Colors.amber, child: Icon(Icons.person, color: Colors.black)),
              title: Text(
                widget.isDriver ? "الزبون: ${trip!['customer']?['name'] ?? '...'}" : "الكابتن: ${trip!['driver']?['name'] ?? '...'}",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)
              ),
              subtitle: Text(
                widget.isDriver ? "الموقع: ${trip!['pickup_location']}" : "السيارة في طريقها إليك الآن",
                style: TextStyle(color: Colors.white70, fontSize: 13),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                icon: CircleAvatar(backgroundColor: Colors.green, child: Icon(Icons.phone, color: Colors.white)),
                onPressed: () {
                  var person = widget.isDriver ? trip!['customer'] : trip!['driver'];
                  if (person != null && person['phone'] != null) {
                    _makeCall(person['phone'].toString());
                  }
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
                label: Text(status == "ongoing" ? "الملاحة نحو الوجهة" : "الملاحة نحو الزبون"),
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
               _buildCompletionCard()
            ]
          ]),
        ))
      ]),
    );
  }

  // واجهة عرض تفاصيل إتمام الرحلة
  Widget _buildCompletionCard() {
    double fare = double.tryParse(trip!['fare'].toString()) ?? 0.0;
    double commission = fare * 0.12;
    
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(15)),
      child: Column(children: [
        Icon(Icons.check_circle, color: Colors.green, size: 50),
        SizedBox(height: 10),
        Text("تم إتمام الرحلة بنجاح", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        if (widget.isDriver) ...[
           SizedBox(height: 8),
           Text("المبلغ المحصل: ${fare.toStringAsFixed(0)} د.ع", style: TextStyle(color: Colors.greenAccent)),
           Text("العمولة المستقطسسعة (12%): ${commission.toStringAsFixed(0)} د.ع", style: TextStyle(color: Colors.redAccent, fontSize: 12)),
        ],
        SizedBox(height: 15),
        ElevatedButton(
          onPressed: () {
            if (!widget.isDriver) {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => StoreDashboard(token: widget.token)),
                (route) => false,
              );
            } else {
              Navigator.pop(context); // العودة للوحة الكابتن وتحديث الرصيد هناك
            }
          },
          child: Text("العودة للرئيسية"),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.amber, 
            foregroundColor: Colors.black, 
            minimumSize: Size(double.infinity, 50), 
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
          )
        )
      ]),
    );
  }

  String _getStatusArabic(String s) {
    switch (s) {
      case "accepted": return "الكابتن في طريقه إليك";
      case "arrived": return "الكابتن وصل للموقع";
      case "ongoing": return "الرحلة مستمرة الآن";
      case "completed": return "وصلت بالسلامة";
      case "cancelled": return "الرحلة ملغاة";
      default: return "جاري المزامنة...";
    }
  }

  Widget _buildDriverActions() {
    if (status == "accepted") return _actionBtn("لقد وصلت لمكان الزبون", "arrived");
    if (status == "arrived") return _actionBtn("بدء الرحلة", "ongoing", color: Colors.green);
    if (status == "ongoing") return _actionBtn("إنهاء الرحلة", "completed", color: Colors.redAccent);
    return Container();
  }

  Widget _actionBtn(String txt, String nextStatus, {Color color = Colors.amber}) {
    return ElevatedButton(
      onPressed: () async {
        // عند إنهاء الرحلة، نرسل الطلب لمسار الإغلاق مع المبلغ
        String urlPath = nextStatus == "completed" ? "finish" : "status";
        try {
          Map<String, dynamic> bodyData = {'status': nextStatus};
          
          // إذا كانت الحالة "إكمال"، نرسل الأجرة ليقوم السيرفر بحساب الـ 12%
          if (nextStatus == "completed") {
            bodyData['fare'] = trip!['fare']; 
          }

          final res = await http.post(
            Uri.parse("$apiBaseUrl/trips/${widget.tripId}/$urlPath"),
            headers: {
              'Authorization': 'Bearer ${widget.token}', 
              'Content-Type': 'application/json', 
              'Accept': 'application/json'
            },
            body: json.encode(bodyData),
          );
          
          if (res.statusCode == 200) {
            _fetch(); // تحديث الحالة في الواجهة
            if (nextStatus == "completed") {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("تم إنهاء الرحلة وخصم العمولة من رصيدك"))
              );
            }
          }
        } catch (e) { print("Error updating status: $e"); }
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

  // ويدجت السيارة المتحركة على الخريطة
  Widget _buildMovingCarMarker() {
    return Transform.rotate(
      angle: _currentHeading * (3.14159 / 180),
      child: Container(
        width: 40, height: 80,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(width: 22, height: 42, decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(6))),
            Container(
              width: 20, height: 40,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: Colors.grey[800]!, width: 0.5),
              ),
            ),
            // تفاصيل تصميم السيارة الصغيرة
            Positioned(top: 10, child: Container(width: 16, height: 8, decoration: BoxDecoration(color: Colors.blueGrey.withOpacity(0.6), borderRadius: BorderRadius.circular(2)))),
          ],
        ),
      ),
    );
  }
}