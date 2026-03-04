import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart';

import 'core/device_state_manager.dart';
import 'core/setup_manager.dart';
import 'features/setup/setup_screen.dart';
import 'features/home/home_screen.dart';

import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';




void main() async {
  // Start device state (permission + gps watcher)
  DeviceStateManager.instance.start();
  final setupDone = await SetupManager.isSetupDone();
  
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await FirebaseMessaging.instance.subscribeToTopic('test');
  print("SUBSCRIBED => test");  
  runApp(NCareApp(setupDone: setupDone));
}
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // 0) init
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final data = message.data;
  final type = data['type'];
  final requestId = data['requestId'];

  if (type != 'rl' || requestId == null) return;

  try {
    final gpsOn = await Geolocator.isLocationServiceEnabled();
    if (!gpsOn) {
      await FirebaseFirestore.instance.collection('responses').doc(requestId).set({
        'status': 'gps_off',
        'ts': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }

    final perm = await Permission.locationAlways.status;
    if (!perm.isGranted) {
      await FirebaseFirestore.instance.collection('responses').doc(requestId).set({
        'status': 'permission_missing',
        'ts': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }

    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 20),
    );

    await FirebaseFirestore.instance.collection('responses').doc(requestId).set({
      'status': 'ok',
      'lat': pos.latitude,
      'lng': pos.longitude,
      'acc': pos.accuracy,
      'ts': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    print("BG LOC SENT => $requestId ${pos.latitude},${pos.longitude}");
  } catch (e) {
    await FirebaseFirestore.instance.collection('responses').doc(requestId).set({
      'status': 'error',
      'error': e.toString(),
      'ts': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
  

class NCareApp extends StatelessWidget {
  final bool setupDone;
  const NCareApp({super.key, required this.setupDone});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NCare',
      theme: ThemeData(useMaterial3: true),
      home: setupDone ? const HomeScreen() : const SetupScreen(),
    );
  }
}



