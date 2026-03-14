import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';

class NotificationService {
  NotificationService._();
  
  static bool suppressForegroundAlerts=false;

  static final FlutterLocalNotificationsPlugin _fln =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _alertsChannel =
      AndroidNotificationChannel(
    'ncare_alerts',
    'NCare Alerts',
    description: 'Important alerts from NCare',
    importance: Importance.high,
  );
  
static bool _initialized = false;

static Future<void> ensureInitialized() async {
  if (_initialized) return;

  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const settings = InitializationSettings(android: androidInit);

  await _fln.initialize(settings);

  await _fln
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_alertsChannel);

  _initialized = true;
}  

  static Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidInit);

    await _fln.initialize(settings);

    await _fln
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_alertsChannel);

    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.onMessage.listen((message) async {
      if(suppressForegroundAlerts)
	  {
	  return;
	  }
	  await showFromRemoteMessage(message);
    });
  }

static Future<void> show({
  required String title,
  required String body,
  required String type,
  required String locatorName,
}) async {

  await ensureInitialized();

  await _fln.show(
    _notificationId(type, locatorName),
    title,
    body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'ncare_alerts',
        'NCare Alerts',
        channelDescription: 'Important alerts from NCare',
        importance: Importance.high,
        priority: Priority.high,
        ticker: 'NCare alert',
      ),
    ),
  );
}
  
  

  static Future<void> showFromRemoteMessage(RemoteMessage message) async {
  
    await ensureInitialized();

    final data = message.data;

    final type = (data['type'] ?? '').toString();
    final locatorName = (data['locatorName'] ?? 'Locator').toString();



    String title =
        message.notification?.title?.trim().isNotEmpty == true
            ? message.notification!.title!
            : 'NCare Alert';

    String body =
        message.notification?.body?.trim().isNotEmpty == true
            ? message.notification!.body!
            : 'You have a new alert';
			
    if (type == 'rl') {
      final requesterName = (data['requesterName'] ?? 
	'Requester').toString();
      title = 'Location request';
     body = '$requesterName requested your location';
    }
	
	final prefs = await SharedPreferences.getInstance();
    if(type == 'rl'){
	final enabled = prefs.getBool('locator_request_alerts') ?? true;
	
       if (!enabled) return;
	}			
			

    if (type == 'call_me') {
      title = 'Call request';
      body = '$locatorName wants you to call';
    } else if (type == 'battery_low') {
      title = 'Battery alert';
      body = '$locatorName battery is low';
    } else if (type == 'geofence_exit') {
      title = 'Geofence alert';
      body = '$locatorName left the selected area';
    }

    await _fln.show(
      _notificationId(type, locatorName),
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'ncare_alerts',
          'NCare Alerts',
          channelDescription: 'Important alerts from NCare',
          importance: Importance.high,
          priority: Priority.high,
          ticker: 'NCare alert',
        ),
      ),
    );
  }

  static int _notificationId(String type, String locatorName) {
    return Object.hash(type, locatorName) & 0x7fffffff;
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await NotificationService.showFromRemoteMessage(message);
}