import 'dart:async';
import 'dart:ui';
import 'package:battery_plus/battery_plus.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../firebase_options.dart';
import 'device_state_manager.dart';
import 'role_manager.dart';
import 'identity_manager.dart';
import '../../services/rtdb.dart';

class BackgroundEngine {
  static Future<void> initialize() async {
  print("BackgroundEngine: Konfigüre ediliyor...");
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false, // BURAYI FALSE YAP: Kontrol bizde olsun
      isForegroundMode: true,
      notificationChannelId: 'ncare_alerts',
      initialNotificationTitle: 'NCare Servis',
      initialNotificationContent: 'Sistem hazırlanıyor...',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false, // iOS tarafında da manuel kontrol
      onForeground: onStart,
    ),
  );
  
  // Yapılandırma bitti, şimdi manuel olarak marşa bas
  await service.startService();
  print("BackgroundEngine: Marşa basıldı!");
}
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
print("onStart_called");

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  //final role = await RoleManager.getRole();
  //if (role != 'locator') return;
print("role locator BG");
  final String? groupId = await IdentityManager.getLocalGroupId();
  final String? deviceId = await IdentityManager.getOrCreateDeviceId();
  
  final Battery _battery = Battery();
  final int initialLevel = await _battery.batteryLevel;

  if (groupId != null && deviceId != null) {
    // Kalp atışını başlat
    RTDBService().startLocatorHeartbeat(
      groupId: groupId,
      deviceId: deviceId,
      initialBattery: initialLevel,
    );


    
    // Hareket algılama mantığını başlat
    _startMovementLogic(service, groupId, deviceId);
    
  }

  DeviceStateManager.instance.start();

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) => service.setAsForegroundService());
    service.on('setAsBackground').listen((event) => service.setAsBackgroundService());
  }

  service.on('stopService').listen((event) => service.stopSelf());
}

@pragma('vm:entry-point')
void _startMovementLogic(ServiceInstance service, String groupId, String deviceId) {
  int _startSteps = 0;
  bool _isMoving = false;
  bool _isTrackingActive = false;
  Timer? _stopTimer;
  print("Adım Sayar başladı");
  Pedometer.stepCountStream.listen((StepCount event) {
	print("ADIM GELDİ: ${event.steps}");
    if (!_isMoving) {
      _isMoving = true;
      _startSteps = event.steps;
      
      // UI'ı bilgilendir (Opsiyonel)
      service.invoke('onMovementDetected', {"status": "moving"});
    }

    int currentSessionSteps = event.steps - _startSteps;

    // 15 ADIM BARAJI - VİTES YÜKSELT
    if (currentSessionSteps >= 15 && !_isTrackingActive) {
      _isTrackingActive = true;
      
      DeviceStateManager.instance.updatePresence();
      
      service.invoke('onTrackingStatusChanged', {"active": true});
	  print("Steps >15 updatePresence_called");
    }
	if (!_isMoving) return;
    // Hareket devam ettiği sürece durma sayacını sıfırla
    _stopTimer?.cancel();
    _stopTimer = Timer(const Duration(minutes: 5), () {
      // HAREKET DURDU - VİTES DÜŞÜR
      _isMoving = false;
      _isTrackingActive = false;
      _startSteps = 0;
      service.invoke('onTrackingStatusChanged', {"active": false});
    });
  }, onError: (error) => print("Pedometer Hatası: $error"));
}