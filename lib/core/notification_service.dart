import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';

class NotificationService {
  NotificationService._();
  
  static bool suppressForegroundAlerts=false;
  static final FlutterLocalNotificationsPlugin _fln =FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  
  static const AndroidNotificationChannel _alertsChannel =AndroidNotificationChannel(
    'LynraCare_alerts',
    'LynraCare Alerts',
    description: 'Important alerts from LynraCare',
    importance: Importance.high,
  );  

  static Future<void> init() async {
    if (_initialized) return;

    // 1. Android Başlangıç Ayarları (İkon vb.)
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidInit);
    await _fln.initialize(settings);

    // 2. Android Bildirim Kanalını Oluştur (Main'den buraya taşındı)
    await _fln
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_alertsChannel);

    // 3. Firebase Ön Plan (Foreground) Ayarları
    try {
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (e) {
      print("FCM Foreground options skip (background mode)");
    }

    // 4. ON_MESSAGE LISTEN: Uygulama açıkken gelenleri yakalar.
    // Sadece bir kez (init anında) kurulur.
    FirebaseMessaging.onMessage.listen((message) async {
      print("FCM FOREGROUND => Message received: ${message.messageId}");
      if (suppressForegroundAlerts) return;
      await showFromRemoteMessage(message);
    });

    _initialized = true;
    print("NOTIFICATION_SERVICE: Başarıyla kuruldu.");
  }
/// Emniyet Kemeri: Her gösterimden önce init kontrolü yapar.
  static Future<void> _ensureReady() async => await init();

  static Future<void> show({
    required String title,
    required String body,
    required String type,
    required String locatorName,
  }) async {
    await _ensureReady();
    await _fln.show(
      _notificationId(type, locatorName),
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'LynraCare_alerts',
          'LynraCare Alerts',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }
  
  /// Uzaktan gelen mesajı (FCM) işleyip gösteren ana metod
  static Future<void> showFromRemoteMessage(RemoteMessage message) async {
    await _ensureReady();

    final data = message.data;
    final tsStr = data['ts'];
    DateTime? dt;

    if (tsStr != null && tsStr.isNotEmpty) {
      dt = DateTime.fromMillisecondsSinceEpoch(int.parse(tsStr));
    }

    // Tarih formatlama fonksiyonu
    String formatAlertTsFromDate(DateTime date) {
      final now = DateTime.now();
      final sameDay = date.year == now.year && date.month == now.month && date.day == now.day;
      final hh = date.hour.toString().padLeft(2, '0');
      final mm = date.minute.toString().padLeft(2, '0');

      if (sameDay) return '$hh:$mm';

      final dd = date.day.toString().padLeft(2, '0');
      final mo = date.month.toString().padLeft(2, '0');
      return '$dd.$mo $hh:$mm';
    }

    final formattedTs = dt != null ? formatAlertTsFromDate(dt) : '';
    final type = (data['type'] ?? '').toString();
    final locatorName = (data['locatorName'] ?? 'Locator').toString();
    final placeName = (data['placeName'] ?? 'Place').toString();

    String title = message.notification?.title?.trim().isNotEmpty == true
        ? message.notification!.title!
        : 'LynraCare Alert';

    String body = message.notification?.body?.trim().isNotEmpty == true
        ? message.notification!.body!
        : 'You have a new alert';

    // Tip bazlı başlık ve içerik belirleme
    if (type == 'rl') {
      final requesterName = (data['requesterName'] ?? 'Requester').toString();
      title = 'Location request';
      body = '$requesterName requested your location';
    }

    final prefs = await SharedPreferences.getInstance();

    if (type == 'rl') {
      final enabled = prefs.getBool('locator_request_alerts') ?? true;
      if (!enabled) return;
    }

    if (type == 'call_me') {
      title = 'Call request';
      body = '$locatorName wants you to call';
    } else if (type == 'battery_low') {
      title = 'Battery alert';
      body = '$locatorName battery is low';
    } else if (type == 'gps_off') {
      title = 'GPS alert';
      body = '$locatorName GPS is OFF';
    } else if (type.startsWith('place_arrive')) {
      title = 'Arrived';
      body = '$locatorName arrived at $placeName';
    } else if (type.startsWith('place_left')) {
      title = 'Left';
      body = '$locatorName left $placeName';
    }

    if (formattedTs.isNotEmpty) {
      body = '$body • $formattedTs';
    }

    await _fln.show(
      _notificationId(type, locatorName),
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'LynraCare_alerts',
          'LynraCare Alerts',
          channelDescription: 'Important alerts from LynraCare',
          importance: Importance.high,
          priority: Priority.high,
          ticker: 'LynraCare alert',
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
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.showFromRemoteMessage(message);
}