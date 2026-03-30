import 'dart:async';
import 'dart:ui';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import '../firebase_options.dart';
import 'device_state_manager.dart';
import 'role_manager.dart';

class BackgroundEngine {
  static Future<void> initialize() async {
    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true, // Telefon açıldığında otomatik başlasın
        isForegroundMode: true,
        notificationChannelId: 'ncare_alerts', // Senin NotificationService'deki kanal id'si
        initialNotificationTitle: 'NCare Aktif',
        initialNotificationContent: 'Takip sistemi arka planda çalışıyor...',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
      ),
    );
  }
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  
  // Arka plan izolesinde Firebase'i tekrar başlatmak zorunludur
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final role = await RoleManager.getRole();
  if (role != 'locator') return;

  // Senin asıl mantığını (Presence, Battery, Geofence) burada ateşliyoruz
  // Artık Timer'lar bu onStart bloğu içinde yaşadığı için uygulama kapansa da ölmez
  DeviceStateManager.instance.start();

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });
}