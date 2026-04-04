import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'constants.dart';
import 'active_delivery_screen.dart'; 

class StoreDashboard extends StatefulWidget {
  final String token;
  StoreDashboard({required this.token});

  @override
  _StoreDashboardState createState() => _StoreDashboardState();
}

class _StoreDashboardState extends State<StoreDashboard> {
  final _customerNameController = TextEditingController();
  final _customerPhoneController = TextEditingController();
  final _itemsCountController = TextEditingController();
  final _storeLocationController = TextEditingController(); 
  final _customerAddressController = TextEditingController(); 
  final _itemTypeController = TextEditingController(); 
  final _itemPriceController = TextEditingController(); 
  
  LatLng? storeLatLng;
  LatLng? customerLatLng;
  int deliveryFare = 0;
  final MapController _mapController = MapController();
  
  List _suggestions = []; 
  Timer? _debounce; 

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setStoreCurrentLocation();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _storeLocationController.dispose();
    _customerAddressController.dispose();
    super.dispose();
  }

  _searchCustomerLocation(String query) async {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      if (query.length < 3) return;
      final url = "https://nominatim.openstreetmap.org/search?q=$query, Baghdad, Iraq&format=json&addressdetails=1&limit=5";
      try {
        final res = await http.get(Uri.parse(url), headers: {'User-Agent': 'BaghdadDeliveryApp'});
        if (res.statusCode == 200 && mounted) {
          setState(() => _suggestions = json.decode(res.body));
        }
      } catch (e) { print("Search Error: $e"); }
    });
  }

  _getAddressFromLatLng(LatLng point, bool isStore) async {
    final url = "https://nominatim.openstreetmap.org/reverse?lat=${point.latitude}&lon=${point.longitude}&format=json&addressdetails=1";
    try {
      final res = await http.get(Uri.parse(url), headers: {'User-Agent': 'BaghdadDeliveryApp'});
      if (res.statusCode == 200 && mounted) {
        final data = json.decode(res.body);
        final addr = data['address'];
        String neighborhood = addr['neighbourhood'] ?? addr['suburb'] ?? addr['residential'] ?? "منطقة مجهولة";
        String road = addr['road'] ?? "شارع فرعي";
        String finalTitle = "$neighborhood - $road";

        setState(() {
          if (isStore) {
            _storeLocationController.text = finalTitle;
            storeLatLng = point;
          } else {
            _customerAddressController.text = finalTitle;
            customerLatLng = point;
          }
        });
        _calculateDeliveryFare();
      }
    } catch (e) { print("Geocoding Error: $e"); }
  }

  _setStoreCurrentLocation() async {
    try {
      Position pos = await Geolocator.getCurrentPosition();
      LatLng myLoc = LatLng(pos.latitude, pos.longitude);
      _getAddressFromLatLng(myLoc, true);
      _mapController.move(myLoc, 15);
    } catch (e) { print("Location Error: $e"); }
  }

  _calculateDeliveryFare() {
    if (storeLatLng != null && customerLatLng != null) {
      double dist = Geolocator.distanceBetween(
        storeLatLng!.latitude, storeLatLng!.longitude, 
        customerLatLng!.latitude, customerLatLng!.longitude
      ) / 1000;
      setState(() => deliveryFare = (3000 + (dist * 500)).round());
    }
  }

  _sendDeliveryOrder() async {
    if (_customerNameController.text.isEmpty || _customerPhoneController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("يرجى إدخال بيانات الزبون")));
      return;
    }

    try {
      final res = await http.post(
        Uri.parse("$apiBaseUrl/trips/create"), 
        headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'}, 
        body: {
    // تم تغييرها لتطابق receiver_name في قاعدة البيانات
    'receiver_name': _customerNameController.text, 
    
    // تم تغييرها لتطابق receiver_phone في قاعدة البيانات
    'receiver_phone': _customerPhoneController.text, 
    
    // الحقول الجديدة التي أضفناها لنظام التوصيل
    'item_type': _itemTypeController.text,
    'item_price': _itemPriceController.text,
    'items_count': _itemsCountController.text, // جديد: عدد القطع
    // الحقول الأساسية للنظام (تبقى كما هي أو تعدل حسب قاعدة بياناتك)
    'pickup_location': _storeLocationController.text,
    'dropoff_location': _customerAddressController.text,
    'fare': deliveryFare.toString(), // أجور التوصيل
    
    'pickup_lat': storeLatLng!.latitude.toString(), 
    'pickup_long': storeLatLng!.longitude.toString(),
    'dropoff_lat': customerLatLng!.latitude.toString(), 
    'dropoff_long': customerLatLng!.longitude.toString(),
}
      );
      if (res.statusCode == 201 && mounted) {
        _waitMessenger(json.decode(res.body)['id']);
      }
    } catch (e) { print("Order Error: $e"); }
  }

  _waitMessenger(int id) {
    int secondsElapsed = 0; 
    bool isDialogActive = true;
    Timer? pollingTimer;

    showDialog(
      context: context, 
      barrierDismissible: false, 
      builder: (c) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text("جاري البحث عن مندوب...", textAlign: TextAlign.center, style: TextStyle(color: Colors.orangeAccent)), 
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(color: Colors.orangeAccent, backgroundColor: Colors.white24),
            SizedBox(height: 20),
            Text("يتم الآن عرض طلبك على المناديب القريبين", textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
          ],
        )
      )
    );
    
    pollingTimer = Timer.periodic(Duration(seconds: 4), (t) async {
      secondsElapsed += 4;

      if (!mounted) { t.cancel(); return; }

      if (secondsElapsed >= 60) {
        t.cancel();
        if (isDialogActive) {
          Navigator.of(context, rootNavigator: true).pop();
          isDialogActive = false;
        }
        _cancelOrderOnServer(id);
        return;
      }

      try {
        final res = await http.get(
          Uri.parse("$apiBaseUrl/trips/$id"), 
          headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'}
        );
        if (res.statusCode == 200 && mounted) {
          final orderData = json.decode(res.body);
          if (orderData['status'] == 'accepted') {
            t.cancel(); 
            if (isDialogActive) {
              Navigator.of(context, rootNavigator: true).pop();
              isDialogActive = false;
            }

            // التعديل هنا: استخدام البارامترات المطلوبة بدقة
            Future.delayed(Duration(milliseconds: 200), () {
              if (mounted) {
                Navigator.pushReplacement(
                  context, 
                  MaterialPageRoute(
                    builder: (c) => ActiveDeliveryScreen(
                      deliveryId: id,          // التعديل هنا
                      token: widget.token,
                      isDeliveryBoy: false,    // التعديل هنا
                    ),
                  ),
                );
              }
            });
          }
        }
      } catch (e) {}
    });
  }

  void _cancelOrderOnServer(int id) async {
    try {
      await http.delete(Uri.parse("$apiBaseUrl/trips/$id/timeout-cancel"),
        headers: {'Authorization': 'Bearer ${widget.token}', 'Accept': 'application/json'},
      );
      if (mounted) _showNoMessengerAlert(); 
    } catch (e) {}
  }

  _showNoMessengerAlert() {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text("نعتذر منك", textAlign: TextAlign.center, style: TextStyle(color: Colors.redAccent)),
        content: Text("لا يوجد مندوب متاح حالياً لتوصيل الطلب.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text("حسناً", style: TextStyle(color: Colors.orangeAccent)))]
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text("لوحة المتجر - طلب توصيل", style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)), 
        backgroundColor: Colors.black,
        elevation: 0,
      ),
      body: Stack(children: [
        _buildMap(),
        _buildCustomerInfoOverlay(),
        _buildBottomStoreCard(),
      ]),
    );
  }

  Widget _buildMap() => FlutterMap(
    mapController: _mapController, 
    options: MapOptions(
      initialCenter: LatLng(33.3128, 44.3615), 
      initialZoom: 13, 
      onTap: (p, l) => _getAddressFromLatLng(l, false),
    ), 
    children: [
      TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
      MarkerLayer(markers: [
        if (storeLatLng != null) Marker(point: storeLatLng!, child: Icon(Icons.store, color: Colors.blue, size: 40)),
        if (customerLatLng != null) Marker(point: customerLatLng!, child: Icon(Icons.location_on, color: Colors.red, size: 45)),
      ])
    ]
  );

 Widget _buildCustomerInfoOverlay() => Positioned(
    top: 10, left: 15, right: 15,
    child: Column(children: [
      Container(
        padding: EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.9), 
          borderRadius: BorderRadius.circular(15), 
          border: Border.all(color: Colors.orangeAccent.withOpacity(0.5))
        ),
        child: Column(children: [
          // حقل اسم الزبون
          TextField(
            controller: _customerNameController,
            style: TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: "اسم الزبون", 
              hintStyle: TextStyle(color: Colors.white30), 
              prefixIcon: Icon(Icons.person, color: Colors.orangeAccent), 
              border: InputBorder.none
            ),
          ),
          Divider(color: Colors.white10, height: 1),

          // حقل رقم هاتف الزبون
          TextField(
            controller: _customerPhoneController,
            keyboardType: TextInputType.phone,
            style: TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: "رقم هاتف الزبون", 
              hintStyle: TextStyle(color: Colors.white30), 
              prefixIcon: Icon(Icons.phone, color: Colors.orangeAccent), 
              border: InputBorder.none
            ),
          ),
          Divider(color: Colors.white10, height: 1),

          // حقل عنوان الزبون والبحث
          TextField(
            controller: _customerAddressController,
            onChanged: _searchCustomerLocation,
            style: TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: "عنوان الزبون (بحث أو تحديد من الخريطة)", 
              hintStyle: TextStyle(color: Colors.white30), 
              prefixIcon: Icon(Icons.location_on, color: Colors.orangeAccent), 
              border: InputBorder.none
            ),
          ),
          Divider(color: Colors.white10, height: 1),

          // حقل نوع البضاعة
          TextField(
            controller: _itemTypeController,
            style: TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: "نوع البضاعة (مثلاً: ملابس، عطور)", 
              hintStyle: TextStyle(color: Colors.white30), 
              prefixIcon: Icon(Icons.inventory_2, color: Colors.orangeAccent), 
              border: InputBorder.none
            ),
          ),
          Divider(color: Colors.white10, height: 1),

          // جديد: حقل عدد القطع
          TextField(
            controller: _itemsCountController, // تأكد من تعريف هذا الـ Controller في الكلاس
            keyboardType: TextInputType.number,
            style: TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: "عدد القطع", 
              hintStyle: TextStyle(color: Colors.white30), 
              prefixIcon: Icon(Icons.format_list_numbered, color: Colors.orangeAccent), 
              border: InputBorder.none
            ),
          ),
          Divider(color: Colors.white10, height: 1),

          // حقل سعر البضاعة
          TextField(
            controller: _itemPriceController,
            keyboardType: TextInputType.number,
            style: TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: "سعر البضاعة الكلي (لتحصيله من الزبون)", 
              hintStyle: TextStyle(color: Colors.white30), 
              prefixIcon: Icon(Icons.payments, color: Colors.orangeAccent), 
              border: InputBorder.none
            ),
          ),
        ]),
      ),
      
      if (_suggestions.isNotEmpty)
        Container(
          margin: EdgeInsets.only(top: 5),
          decoration: BoxDecoration(
            color: Colors.black, 
            borderRadius: BorderRadius.circular(10), 
            border: Border.all(color: Colors.white10)
          ),
          constraints: BoxConstraints(maxHeight: 180),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _suggestions.length,
            itemBuilder: (c, i) {
              final s = _suggestions[i];
              return ListTile(
                dense: true,
                title: Text(s['display_name'], style: TextStyle(fontSize: 12, color: Colors.white)),
                onTap: () {
                  setState(() {
                    customerLatLng = LatLng(double.parse(s['lat']), double.parse(s['lon']));
                    _customerAddressController.text = s['display_name'];
                    _suggestions = [];
                  });
                  _mapController.move(customerLatLng!, 15);
                  _calculateDeliveryFare();
                },
              );
            },
          ),
        )
    ]),
  );

  Widget _buildBottomStoreCard() => Align(
    alignment: Alignment.bottomCenter,
    child: Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Icon(Icons.storefront, color: Colors.blue),
          SizedBox(width: 10),
          Expanded(child: Text(_storeLocationController.text.isEmpty ? "جاري تحديد موقع المتجر..." : "موقعي: ${_storeLocationController.text}", 
            style: TextStyle(color: Colors.white70, fontSize: 13), overflow: TextOverflow.ellipsis)),
          IconButton(icon: Icon(Icons.my_location, color: Colors.orangeAccent), onPressed: _setStoreCurrentLocation)
        ]),
        if (deliveryFare > 0) Padding(
          padding: const EdgeInsets.symmetric(vertical: 10), 
          child: Text("أجرة التوصيل: $deliveryFare د.ع", style: TextStyle(fontSize: 18, color: Colors.greenAccent, fontWeight: FontWeight.bold))
        ),
        SizedBox(height: 5),
        ElevatedButton(
          onPressed: (customerLatLng != null) ? _sendDeliveryOrder : null, 
          child: Text("إرسال طلب التوصيل", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), 
          style: ElevatedButton.styleFrom(
            minimumSize: Size(double.infinity, 55), 
            backgroundColor: Colors.orangeAccent, 
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
          )
        )
      ]),
    ),
  );
}