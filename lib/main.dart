import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/device_state_manager.dart';
import 'core/setup_manager.dart';
import 'features/setup/setup_screen.dart';
import 'features/home/home_screen.dart';
import 'core/role_manager.dart';
import 'features/role/role_screen.dart';
import 'core/locator_ui_state.dart';

import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

import 'features/requester/requester_screen.dart';



Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
await SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: SystemUiOverlay.values,
  );
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  FirebaseMessaging.instance
      .subscribeToTopic('test')
      .timeout(const Duration(seconds: 5))
      .then((_) => print("SUBSCRIBED => test"))
      .catchError((e) => print("SUBSCRIBE ERR => $e"));

  print("APP_START");
  DeviceStateManager.instance.start();
  final setupDone = await SetupManager.isSetupDone();
  print("SETUP CHECK DONE");
  FirebaseMessaging.onMessage.listen((message) async {
  final data = message.data;

  if (data['type'] != 'rl') return;

  final requestId = data['requestId']?.toString();
  if (requestId == null || requestId.isEmpty) return;

  // UI: request geldi (app açıkken)
  LocatorUiState.instance.onRequestReceived(requestId);

  try {
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
      'via': 'fg',
    }, SetOptions(merge: true));

    // UI: gönderildi
    LocatorUiState.instance.onSentOk();

    print("FG LOC SENT => $requestId ${pos.latitude},${pos.longitude}");
  } catch (e) {
    await FirebaseFirestore.instance.collection('responses').doc(requestId).set({
      'status': 'error',
      'error': e.toString(),
      'ts': FieldValue.serverTimestamp(),
      'via': 'fg',
    }, SetOptions(merge: true));

    // UI: hata olursa tekrar READY'ye dön (şimdilik)
    LocatorUiState.instance.reset();
  }
});
  

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
      home: const RoleScreen(),
    );
  }
}


