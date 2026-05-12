import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import 'core/device_state_manager.dart';
import 'core/setup_manager.dart';
import 'features/home/home_screen.dart';
import 'features/setup/name_screen.dart';
import 'features/locator/locator_permission_screen.dart';
import 'features/requester/requester_permission_screen.dart';
import 'features/auth/auth_storage.dart';
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
import 'l10n/app_localizations.dart';


import 'features/requester/requester_screen.dart';
import 'core/identity_manager.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

Future<void> main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  bool setupDone = await SetupManager.isSetupDone();
  final groupId = await IdentityManager.getLocalGroupId();
  final String? role = await RoleManager.getRole();
  final service = FlutterBackgroundService();
  bool isRunning = await service.isRunning();
	
  
    if (role != null) 
	{
	print('ROLE => $role');
	print('REQ ID => ${await IdentityManager.getOrCreateDeviceId()}');
	  
	  await FcmManager.prepareApp();
	  
	  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
		FlutterLocalNotificationsPlugin();

	  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
	  await NotificationService.init();
	  print("LynraCareAPP_START");
	  //if (!isRunning) {
      // Sadece servis çalışmıyorsa ana uygulama start versin
	     print("DeviceStateManager start called from main");

      DeviceStateManager.instance.start(); 
      //}
	  print("LynraCareSETUP CHECK DONE");
  
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'LynraCare_alerts',
  'LynraCare Alerts',
  description: 'Important alerts from LynraCare',
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

if (role == 'locator' && setupDone && groupId != null) {
  myLocatorId = await IdentityManager.getOrCreateDeviceId();
  final locatorTopic = 'locator_$myLocatorId';
  print("BackgroundEngine.initialize start called from main DeviceStateManager ");
  await BackgroundEngine.initialize();
} else {
  print("LynraCareLOCATOR FLOW SKIPPED => role=$role");
  final requesterId = await IdentityManager.getOrCreateDeviceId();
}  

FirebaseMessaging.onMessage.listen((message) async {
  await NotificationGateway.handle(message);
  if (role != 'locator') return;

  final data = message.data;
  if (data['type'] != 'rl') return;

  print("LynraCarerl received");

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
    print("LynraCareFG SKIP => target=$targetLocatorId mine=$myLocatorId");
    return;
  }

  if (groupId == null || groupId.isEmpty) {
    print("LynraCareFG RL BLOCKED => no groupId");
    return;
  }

  final stillPaired = await _isStillPaired(
    locatorId: myLocatorId!,
    requesterId: requesterId,
  );

  if (!stillPaired) {
    print("LynraCareFG RL BLOCKED => requester not paired");
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

  print("LynraCaremyLocatorId:$myLocatorId");

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
DeviceStateManager.updatePresence(source: "MAIN_UI");
      LocatorUiState.instance.onSentOk();
      print("LynraCareFG CACHED SENT => $requestId $cachedLat,$cachedLng age=$age");
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
DeviceStateManager.updatePresence(source: "MAIN_UI");
    LocatorUiState.instance.onSentOk();
    print("LynraCareFG LOC SENT => $requestId ${pos.latitude},${pos.longitude}");
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
	DeviceStateManager.updatePresence(source: "MAIN_UI");
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
runApp(LynraCareApp(setupDone: setupDone));
}   
  

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
print("LynraCareBG_HANDLER START => data=${message.data}");
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final role = await RoleManager.getRole();
  if (role != 'locator') {
    print("LynraCareBG LOCATOR FLOW SKIPPED => role=$role");
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
	print("LynraCarerequesterDeviceId:$requesterDeviceId");
  if (type != 'rl' ||
      requestId == null ||
      requestId.isEmpty ||
      requesterId == null ||
      requesterId.isEmpty) {
    return;
  }
print("LynraCareBG_HANDLER RL RECEIVED");
  if (targetLocatorId == null ||
      targetLocatorId.isEmpty ||
      targetLocatorId != myLocatorId) {
    print("LynraCareBG SKIP => target=$targetLocatorId mine=$myLocatorId");
    return;
  }
  
final stillPaired = await _isStillPaired(
  locatorId: myLocatorId,
  requesterId: requesterId,
);
print("LynraCareBG_HANDLER stillPaired => $stillPaired");
if (!stillPaired) {
  print("LynraCareBG RL BLOCKED => requester not paired");
  return;
}

final groupId = await IdentityManager.getLocalGroupId();
if (groupId == null || groupId.isEmpty) {
  print("LynraCareFG RL BLOCKED => no groupId");
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
DeviceStateManager.updatePresence(source: "MAIN_UI");
      //LocatorUiState.instance.onSentOk();
      print("LynraCareBG CACHED SENT => $requestId $cachedLat,$cachedLng age=$age");
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
  print("LynraCareBG FRESH POS NULL");
  return;
}
 print("LynraCareBG FRESH BEFORE WRITE");   
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
DeviceStateManager.updatePresence(source: "MAIN_UI");
    print("LynraCareBG LOC SENT => $requestId ${pos.latitude},${pos.longitude}");
  } catch (e) {
  print("LynraCareBG_HANDLER ERROR => $e");
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

class LynraCareApp extends StatefulWidget {
  final bool setupDone;

  const LynraCareApp({
    super.key,
    required this.setupDone,
  });

  @override
  State<LynraCareApp> createState() => _LynraCareAppState();
}


class _LynraCareAppState extends State<LynraCareApp> {
  Locale _locale = const Locale('tr');

  @override
  void initState() {
    super.initState();
    loadLocale();
  }

  Future<void> loadLocale() async {
    final code = await AuthStorage.safeRead("app_locale");
		print("LynraCare__code:$code");
    if (code != null) {
      setState(() {
        _locale = Locale(code);
      });
    }
  }

  /*Future<void> setLocale(Locale locale) async {
    await storage.write(
      key: "app_locale",
      value: locale.languageCode,
    );

    setState(() {
      _locale = locale;
			print("LynraCare__locale:$_locale");
    });
  }*/


  @override
Widget build(BuildContext context) {
  return MaterialApp(
    locale: _locale,
    debugShowCheckedModeBanner: false,
    title: 'LynraCare',

    builder: (context, child) {
      final lang = Localizations.localeOf(context).languageCode;
			print("LynraCare_lang:$lang");
      double textScale = 0.8;

      if (lang == 'hi' || lang == 'th') {
        textScale = 1.16;
      } else if (lang == 'ar') {
        textScale = 1.14;
      } else if (lang == 'ja' || lang == 'ko' || lang == 'zh') {
        textScale = 1.10;
      }

      return MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      );
    },

    localizationsDelegates:  [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],

    supportedLocales: const [
      Locale('en'),
      Locale('tr'),
      Locale('es'),
      Locale('de'),
      Locale('fr'),
      Locale('it'),
      Locale('hi'),
      Locale('ko'),
      Locale('ja'),
      Locale('zh'),
      Locale('ar'),
      Locale('ru'),
      Locale('id'),
      Locale('vi'),
      Locale('th'),
      Locale('nl'),
      Locale('pl'),
      Locale('sv'),
      Locale.fromSubtags(languageCode: 'pt', countryCode: 'BR'),
    ],

    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFF0F172A),
    ),

    home: FutureBuilder<String?>(
      future: RoleManager.getRole(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SplashScreen();
        }

        final role = snapshot.data;

        if (role == 'locator') {
          if (widget.setupDone) {
            return const HomeScreen();
          }
          return const NameScreen();
        }

        if (role == 'requester') {
          if (widget.setupDone) {
            return const RequesterScreen();
          }
          return const NameScreen();
        }

        return const RoleScreen();
      },
    ),
  );
}
}