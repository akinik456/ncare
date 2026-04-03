import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'core/device_state_manager.dart';
import 'core/setup_manager.dart';
import 'features/home/home_screen.dart';
import 'core/role_manager.dart';
import 'features/role/role_screen.dart';
import 'core/locator_ui_state.dart';
import 'core/notification_service.dart';
import 'core/notification_gateway.dart';
import 'core/fcm_manager.dart';
import 'core/auth_service.dart';
import 'core/location_helper.dart';
import 'core/background_engine.dart';
import 'core/splash_screen.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pedometer/pedometer.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'features/requester/requester_screen.dart';
import 'core/identity_manager.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

Future<void> main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  bool setupDone = await SetupManager.isSetupDone();
  final String? role = await RoleManager.getRole();

    if (role != null) 
	{
	print('ROLE => $role');
	print('REQ ID => ${await IdentityManager.getOrCreateDeviceId()}');
	  if (role == 'locator') {
	  //await BackgroundEngine.initialize();
	  }
	  
	  await FcmManager.prepareApp();
	  
	  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
		FlutterLocalNotificationsPlugin();

	  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
	  await NotificationService.init();
	  print("APP_START");
	  DeviceStateManager.instance.start();
	  setupDone = await SetupManager.isSetupDone();
	  print("SETUP CHECK DONE");
  
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'ncare_alerts',
  'NCare Alerts',
  description: 'Important alerts from NCare',
  importance: Importance.high,
  
);

await flutterLocalNotificationsPlugin
    .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
    ?.createNotificationChannel(channel);

const AndroidInitializationSettings androidSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');

const InitializationSettings initSettings =
    InitializationSettings(android: androidSettings);

await flutterLocalNotificationsPlugin.initialize(initSettings);
	
    
String? myLocatorId;

if (role == 'locator') {
  myLocatorId = await IdentityManager.getOrCreateDeviceId();
  final locatorTopic = 'locator_$myLocatorId';
  await BackgroundEngine.initialize();
} else {
  print("LOCATOR FLOW SKIPPED => role=$role");
  final requesterId = await IdentityManager.getOrCreateDeviceId();
}  

FirebaseMessaging.onMessage.listen((message) async {
  await NotificationGateway.handle(message);
  if (role != 'locator') return;

  final data = message.data;
  if (data['type'] != 'rl') return;

  print("rl received");

  final requestId = data['requestId']?.toString();
  final requesterId = data['requesterId']?.toString();
  final targetLocatorId = data['locatorId']?.toString();
  final requesterDeviceId =
      (data['requesterDeviceId'] ?? '').toString().trim();

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

  final groupId = await IdentityManager.getLocalGroupId();
  if (groupId == null || groupId.isEmpty) {
    print("FG RL BLOCKED => no groupId");
    return;
  }

  final stillPaired = await _isStillPaired(
    locatorId: myLocatorId!,
    requesterId: requesterId,
  );

  if (!stillPaired) {
    print("FG RL BLOCKED => requester not paired");
    return;
  }

  final prefs = await SharedPreferences.getInstance();
  final enabled = prefs.getBool('locator_request_alerts') ?? true;

  if (enabled) {
    LocatorUiState.instance.onRequestReceived(requestId);
  }

  final locatorDoc = await FirebaseFirestore.instance
      .collection('locators')
      .doc(myLocatorId)
      .get();

  print("myLocatorId:$myLocatorId");

  final cachedLat = (locatorDoc.data()?['lat'] as num?)?.toDouble();
  final cachedLng = (locatorDoc.data()?['lng'] as num?)?.toDouble();
  final cachedAcc = (locatorDoc.data()?['acc'] as num?)?.toDouble();
  final lastSeen = locatorDoc.data()?['lastSeen'];

  final age = lastSeen != null
      ? DateTime.now().difference(lastSeen.toDate()).inSeconds
      : 9999;

  try {
    if (cachedLat != null &&
        cachedLng != null &&
        cachedAcc != null &&
        age < 30) {
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .collection('locators')
          .doc(myLocatorId)
          .collection('responses')
          .doc(requestId)
          .set({
        'locatorId': myLocatorId,
        'requesterDeviceId': requesterDeviceId,
        'status': 'ok',
        'lat': cachedLat,
        'lng': cachedLng,
        'acc': cachedAcc,
        'battery': level,
        'ts': FieldValue.serverTimestamp(),
        'via': 'cached',
      }, SetOptions(merge: true));

      LocatorUiState.instance.onSentOk();
      print("FG CACHED SENT => $requestId $cachedLat,$cachedLng age=$age");
      return;
    }

    final pos = await LocationService.getCurrentLocationSafe(
      accuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 20),
    );

    if (pos == null) return;

    await FirebaseFirestore.instance
        .collection('groups')
        .doc(groupId)
        .collection('locators')
        .doc(myLocatorId)
        .collection('responses')
        .doc(requestId)
        .set({
      'locatorId': myLocatorId,
      'requesterDeviceId': requesterDeviceId,
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
        .collection('groups')
        .doc(groupId)
        .collection('locators')
        .doc(myLocatorId)
        .collection('responses')
        .doc(requestId)
        .set({
      'locatorId': myLocatorId,
      'requesterDeviceId': requesterDeviceId,
      'status': 'error',
      'error': e.toString(),
      'ts': FieldValue.serverTimestamp(),
      'via': 'fg',
    }, SetOptions(merge: true));

    LocatorUiState.instance.reset();
  }
});
	
	} else {
    print('ROLE => NULL (Bakir cihaz, ağır yükler pas geçildi)');
  }
  FlutterNativeSplash.remove();
  await SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: SystemUiOverlay.values,
  );

runApp(NCareApp(setupDone: setupDone));
}   
  

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
print("BG_HANDLER START => data=${message.data}");
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
  final myLocatorId = await IdentityManager.getOrCreateDeviceId();
  final requesterDeviceId =
    (data['requesterDeviceId'] ?? '').toString().trim();
	print("requesterDeviceId:$requesterDeviceId");
  if (type != 'rl' ||
      requestId == null ||
      requestId.isEmpty ||
      requesterId == null ||
      requesterId.isEmpty) {
    return;
  }
print("BG_HANDLER RL RECEIVED");
  if (targetLocatorId == null ||
      targetLocatorId.isEmpty ||
      targetLocatorId != myLocatorId) {
    print("BG SKIP => target=$targetLocatorId mine=$myLocatorId");
    return;
  }
  
final stillPaired = await _isStillPaired(
  locatorId: myLocatorId,
  requesterId: requesterId,
);
print("BG_HANDLER stillPaired => $stillPaired");
if (!stillPaired) {
  print("BG RL BLOCKED => requester not paired");
  return;
}

final groupId = await IdentityManager.getLocalGroupId();
if (groupId == null || groupId.isEmpty) {
  print("FG RL BLOCKED => no groupId");
  return;
}
  await NotificationService.showFromRemoteMessage(message);

  final responseRef = FirebaseFirestore.instance
      .collection('groups')
.doc(groupId)
.collection('locators')
.doc(myLocatorId)
.collection('responses')
.doc(requestId);

  try {
    final locatorDoc = await FirebaseFirestore.instance
        .collection('locators')
        .doc(myLocatorId)
        .get();

    final cachedLat = (locatorDoc.data()?['lat'] as num?)?.toDouble();
    final cachedLng = (locatorDoc.data()?['lng'] as num?)?.toDouble();
    final cachedAcc = (locatorDoc.data()?['acc'] as num?)?.toDouble();
	
  final lastSeen = locatorDoc.data()?['lastSeen'];

  final age = lastSeen != null
      ? DateTime.now().difference(lastSeen.toDate()).inSeconds
      : 9999;
    final battery = Battery();
    final level = await battery.batteryLevel;
	
    if (cachedLat != null &&
        cachedLng != null &&
        cachedAcc != null &&
        age < 30) {
      await responseRef.set({
        'locatorId': myLocatorId,
		'requesterDeviceId': requesterDeviceId,
        'status': 'ok',
        'lat': cachedLat,
        'lng': cachedLng,
        'acc': cachedAcc,
        'battery': -1,//level,
        'ts': FieldValue.serverTimestamp(),
        'via': 'cached_bg',
      }, SetOptions(merge: true));
      //LocatorUiState.instance.onSentOk();
      print("BG CACHED SENT => $requestId $cachedLat,$cachedLng age=$age");
      return;
	  
    }


    final gpsOn = await Geolocator.isLocationServiceEnabled();
    if (!gpsOn) {
      await responseRef.set({
        'locatorId': myLocatorId,
		'requesterDeviceId': requesterDeviceId,
        'status': 'gps_off',
        'ts': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }
    final perm = await Permission.locationWhenInUse.status;
    if (!perm.isGranted) {
      await responseRef.set({
        'locatorId': myLocatorId,
		'requesterDeviceId': requesterDeviceId,
        'status': 'permission_missing',
        'ts': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }

  final pos = await LocationService.getCurrentLocationSafe(
  accuracy: LocationAccuracy.high,
  timeLimit: const Duration(seconds: 20),
);
		if (pos == null) {
  print("BG FRESH POS NULL");
  return;
}
 print("BG FRESH BEFORE WRITE");   
    await responseRef.set({
      'locatorId': myLocatorId,
	  'requesterDeviceId': requesterDeviceId,
      'status': 'ok',
      'lat': pos.latitude,
      'lng': pos.longitude,
      'acc': pos.accuracy,
      'battery': -1,//level,
      'ts': FieldValue.serverTimestamp(),
      'via': 'bg',
    }, SetOptions(merge: true));

    print("BG LOC SENT => $requestId ${pos.latitude},${pos.longitude}");
  } catch (e) {
  print("BG_HANDLER ERROR => $e");
    await responseRef.set({
      'locatorId': myLocatorId,
	  'requesterDeviceId': requesterDeviceId,
      'status': 'error',
      'error': e.toString(),
      'ts': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
Future<bool> _isStillPaired({
  required String locatorId,
  required String requesterId,
}) async {
  final locatorDoc = await FirebaseFirestore.instance
      .collection('locators')
      .doc(locatorId)
      .get();

  final paired =
      locatorDoc.data()?['pairedRequesters'] as Map<String, dynamic>?;

  final entry = paired?[requesterId];

  return entry != null && entry['active'] == true;
}

class NCareApp extends StatelessWidget {
  
 final bool setupDone; 
 const NCareApp({super.key, required this.setupDone});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NCare',
      theme: ThemeData(
        useMaterial3: true,
        // Splash ile uyumlu olması için arka planı buradan da sabitleyebilirsin
        scaffoldBackgroundColor: const Color(0xFF0F172A), 
      ),
      home: FutureBuilder<String?>(
        future: RoleManager.getRole(),
        builder: (context, snapshot) {
          // 1. VERİ BEKLENİRKEN: Beyaz ekran/Loading yerine Splash gösteriyoruz
          if (snapshot.connectionState != ConnectionState.done) {
            return const SplashScreen(); // Az önce oluşturduğumuz şık ekran
          }

          final role = snapshot.data;

          // 2. VERİ GELDİKTEN SONRA: Role göre yönlendir
          if (role == 'locator') {
            return const HomeScreen();
          }

          if (role == 'requester') {
            return const RequesterScreen();
          }

          // Role henüz yoksa (ilk kurulum)
          return const RoleScreen();
        },
      ),
    );
  }
}