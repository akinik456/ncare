import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/device_state_manager.dart';
import 'core/setup_manager.dart';
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
import 'core/identity_manager.dart';
import 'package:battery_plus/battery_plus.dart';


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

  print("APP_START");
  DeviceStateManager.instance.start();
  final setupDone = await SetupManager.isSetupDone();
  print("SETUP CHECK DONE");

  final role = await RoleManager.getRole();
  print("ROLE => $role");

  if (role == 'locator') {
    final myLocatorId = await IdentityManager.getRequesterId();
    final locatorTopic = 'locator_$myLocatorId';

    FirebaseMessaging.instance
        .subscribeToTopic(locatorTopic)
        .timeout(const Duration(seconds: 5))
        .then((_) => print("SUBSCRIBED => $locatorTopic"))
        .catchError((e) => print("SUBSCRIBE ERR => $e"));

    FirebaseMessaging.onMessage.listen((message) async {
      final data = message.data;

      if (data['type'] != 'rl') return;

      final requestId = data['requestId']?.toString();
      final requesterId = data['requesterId']?.toString();
      final targetLocatorId = data['locatorId']?.toString();
      final battery = Battery();
      final level = await battery.batteryLevel;
	  
      if (requestId == null ||
          requestId.isEmpty ||
          requesterId == null ||
          requesterId.isEmpty) {
        return;
      }

      if (targetLocatorId == null ||
          targetLocatorId.isEmpty ||
          targetLocatorId != myLocatorId) {
        print("FG SKIP => target=$targetLocatorId mine=$myLocatorId");
        return;
      }

      LocatorUiState.instance.onRequestReceived(requestId);

      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 20),
        );

        await FirebaseFirestore.instance
            .collection('requesters')
            .doc(requesterId)
            .collection('responses')
            .doc(requestId)
            .set({
          'locatorId': myLocatorId,
          'status': 'ok',
          'lat': pos.latitude,
          'lng': pos.longitude,
          'acc': pos.accuracy,
		  'battery': level,
          'ts': FieldValue.serverTimestamp(),
          'via': 'fg',
        }, SetOptions(merge: true));

        LocatorUiState.instance.onSentOk();

        print("FG LOC SENT => $requestId ${pos.latitude},${pos.longitude}");
      } catch (e) {
        await FirebaseFirestore.instance
            .collection('requesters')
            .doc(requesterId)
            .collection('responses')
            .doc(requestId)
            .set({
          'locatorId': myLocatorId,
          'status': 'error',
          'error': e.toString(),
          'ts': FieldValue.serverTimestamp(),
          'via': 'fg',
        }, SetOptions(merge: true));

        LocatorUiState.instance.reset();
      }
    });
  } else {
    print("LOCATOR FLOW SKIPPED => role=$role");
  }

  runApp(NCareApp(setupDone: setupDone));
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final role = await RoleManager.getRole();
  if (role != 'locator') {
    print("BG LOCATOR FLOW SKIPPED => role=$role");
    return;
  }

  final data = message.data;
  final type = data['type'];
  final requestId = data['requestId']?.toString();
  final requesterId = data['requesterId']?.toString();
  final targetLocatorId = data['locatorId']?.toString();
  final myLocatorId = await IdentityManager.getRequesterId();

  if (type != 'rl' ||
      requestId == null ||
      requestId.isEmpty ||
      requesterId == null ||
      requesterId.isEmpty) {
    return;
  }

  if (targetLocatorId == null ||
      targetLocatorId.isEmpty ||
      targetLocatorId != myLocatorId) {
    print("BG SKIP => target=$targetLocatorId mine=$myLocatorId");
    return;
  }

  final responseRef = FirebaseFirestore.instance
      .collection('requesters')
      .doc(requesterId)
      .collection('responses')
      .doc(requestId);

  try {
    final gpsOn = await Geolocator.isLocationServiceEnabled();
    if (!gpsOn) {
      await responseRef.set({
        'locatorId': myLocatorId,
        'status': 'gps_off',
        'ts': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }

    final perm = await Permission.locationWhenInUse.status;
    if (!perm.isGranted) {
      await responseRef.set({
        'locatorId': myLocatorId,
        'status': 'permission_missing',
        'ts': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }

    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 20),
    );
final battery = Battery();
      final level = await battery.batteryLevel;
    await responseRef.set({
      'locatorId': myLocatorId,
      'status': 'ok',
      'lat': pos.latitude,
      'lng': pos.longitude,
      'acc': pos.accuracy,
	  'battery': level,
      'ts': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    print("BG LOC SENT => $requestId ${pos.latitude},${pos.longitude}");
  } catch (e) {
    await responseRef.set({
      'locatorId': myLocatorId,
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
      home: FutureBuilder<String?>(
        future: RoleManager.getRole(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          final role = snapshot.data;

          if (role == 'locator') {
            return const HomeScreen();
          }

          if (role == 'requester') {
            return const RequesterScreen();
          }

          return const RoleScreen();
        },
      ),
    );
  }
}
