import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pusher_channels_flutter/pusher_channels_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const InstantSOSApp());
}

class InstantSOSApp extends StatelessWidget {
  const InstantSOSApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Instant SOS',
      theme: ThemeData(primarySwatch: Colors.red, useMaterial3: true),
      home: const SOSHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class SOSHomePage extends StatefulWidget {
  const SOSHomePage({super.key});
  @override
  State<SOSHomePage> createState() => _SOSHomePageState();
}

class _SOSHomePageState extends State<SOSHomePage> {
  final String pusherAppId = "2176890";
  final String pusherKey = "163dad2d478fe38aa1cf";
  final String pusherSecret = "81ae586cffe7bf12c117";
  final String pusherCluster = "eu";

  String username = "";
  final TextEditingController _nameController = TextEditingController();
  bool isAlarmActive = false;
  String incomingMessage = "";

  @override
  void initState() {
    super.initState();
    _initUser();
    _initPusher();
    Geolocator.requestPermission();
  }

  Future<void> _initUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      username = prefs.getString('username') ?? "";
      _nameController.text = username;
    });
  }

  Future<void> _saveUsername(String name) async {
    if (name.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', name.trim());
    setState(() => username = name.trim());
  }

  Future<void> _sendSOS() async {
    if (username.isEmpty) return;

    try {
      int batteryLevel = await Battery().batteryLevel;
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      String mapsLink = "https://maps.google.com/?q=${position.latitude},${position.longitude}";

      String messageDetails = "المستخدم: $username بخطر!\nالبطارية: $batteryLevel%\nالموقع: $mapsLink";

      String eventData = jsonEncode({"message": messageDetails, "sender": username});
      String body = jsonEncode({"name": "sos-alert", "channels": ["sos-channel"], "data": eventData});

      String bodyMd5 = md5.convert(utf8.encode(body)).toString();
      String timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
      String queryParams = "auth_key=$pusherKey&auth_timestamp=$timestamp&auth_version=1.0&body_md5=$bodyMd5";
      String path = "/apps/$pusherAppId/events";
      String stringToSign = "POST\n$path\n$queryParams";
      String signature = Hmac(sha256, utf8.encode(pusherSecret)).convert(utf8.encode(stringToSign)).toString();

      String url = "https://api-$pusherCluster.pusher.com$path?$queryParams&auth_signature=$signature";

      await http.post(Uri.parse(url), headers: {"Content-Type": "application/json"}, body: body);
      
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال الاستغاثة!')));
    } catch (e) {
      print("خطأ: $e");
    }
  }

  Future<void> _initPusher() async {
    final pusher = PusherChannelsFlutter.getInstance();
    try {
      await pusher.init(apiKey: pusherKey, cluster: pusherCluster, onEvent: _onPusherEvent);
      await pusher.subscribe(channelName: "sos-channel");
      await pusher.connect();
    } catch (e) {}
  }

  void _onPusherEvent(PusherEvent event) {
    if (event.eventName == "sos-alert") {
      final data = jsonDecode(event.data.toString());
      if (data['sender'] != username) {
        setState(() {
          isAlarmActive = true;
          incomingMessage = data['message'];
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isAlarmActive) {
      return Scaffold(
        backgroundColor: Colors.red,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.warning, size: 100, color: Colors.white),
              const SizedBox(height: 20),
              Text("🚨 حالة طوارئ 🚨\n\n$incomingMessage", textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: () => setState(() => isAlarmActive = false),
                child: const Text("إخفاء الإنذار", style: TextStyle(fontSize: 18, color: Colors.red)),
              )
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Instant SOS'), backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'اسم المستخدم الخاص بك',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(icon: const Icon(Icons.save), onPressed: () => _saveUsername(_nameController.text)),
              ),
            ),
            const SizedBox(height: 50),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 40)),
              onPressed: _sendSOS,
              child: const Text('إرسال نداء استغاثة الآن', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
