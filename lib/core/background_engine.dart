import 'dart:async';
import 'dart:ui';
import 'package:battery_plus/battery_plus.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../firebase_options.dart';
import 'device_state_manager.dart';
import 'role_manager.dart';
import 'identity_manager.dart';
import '../../services/rtdb.dart';

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
  	String? groupId;
  String? deviceId;

  
  groupId = await IdentityManager.getLocalGroupId(); 
    deviceId = await IdentityManager.getOrCreateDeviceId();
    final Battery _battery = Battery();
    final level = await _battery.batteryLevel;

// --- KRİTİK EKLEME BURASI ---
  // Servis başlar başlamaz RTDB vasiyetini (onDisconnect) kuruyoruz.
  final locatorId = await IdentityManager.getOrCreateDeviceId();
  RTDBService().startLocatorHeartbeat(
        groupId: groupId!,
        deviceId: deviceId!,
        initialBattery: level,
      );
  // ----------------------------

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