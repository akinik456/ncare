import 'dart:async';
import 'dart:ui';
import 'package:battery_plus/battery_plus.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../firebase_options.dart';
import 'device_state_manager.dart';
import 'role_manager.dart';
import 'identity_manager.dart';
import '../../services/rtdb.dart';
import 'auth_service.dart';
import 'fcm_manager.dart';
import 'setup_manager.dart';

class BackgroundEngine {
  static bool _bgInitialized = false;

  static Future<void> initialize() async {
    // 1. Yetki ve Kurulum Kontrolleri
    final String? role = await RoleManager.getRole();
    final bool setupDone = await SetupManager.isSetupDone();
    final String? groupId = await IdentityManager.getLocalGroupId();
    final String? deviceId = await IdentityManager.getOrCreateDeviceId();

    if (role != 'locator' || !setupDone || groupId == null || deviceId == null) {
      print("LynraCareBGEngine: Yetkisiz/Eksik kurulum. BGengine init iptal.");
      return;
    }

    print("LynraCareBackgroundEngine: Konfigüre ediliyor...");
    final service = FlutterBackgroundService();
    
    // Zaten çalışıyorsa tekrar konfigüre etme (Önemli!)
    if (await service.isRunning()) return;

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: 'LynraCare_alerts',
        initialNotificationTitle: 'LynraCare Servis',
        initialNotificationContent: 'Sistem hazırlanıyor...',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
      ),
    );
    
    await service.startService();
    print("LynraCareBackgroundEngine: Servis başlatma emri verildi.");
    
    // DİKKAT: Burada DeviceStateManager.start() ASLA çağrılmamalı!
    // Çünkü burası main isolate'i. Start emrini aşağıda onStart verecek.
  }

  static Future<void> prepareEngine() async {
    if (_bgInitialized) return;
    try {
      print("LynraCareBGEngine: İç şalter (Isolate Firebase) kaldırılıyor...");
      
      // Isolate içinde Firebase'i ayağa kaldır
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }

      await AuthService.initializeAuth();
      
      // Topic aboneliği sadece BURADA (Worker içinde) yapılmalı
      await FcmManager.ensureSubscriptions();

      FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
        print("LynraCareBGEngine: FCM TOKEN REFRESH => $token");
        await FcmManager.ensureSubscriptions();
      });

      _bgInitialized = true;
    } catch (e) {
      print("LynraCareBGEngine ERROR: Şalter hatası => $e");
      rethrow;
    }
  }
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  
  await Permission.location.status; 
  await Permission.locationAlways.status;
  await Permission.activityRecognition.status; 
  await Permission.ignoreBatteryOptimizations.status;
  
  
  // Isolate içinde kimlik bilgilerini tekrar al
  final String? groupId = await IdentityManager.getLocalGroupId();
  final String? deviceId = await IdentityManager.getOrCreateDeviceId();
  
  // ... (Yetki kontrolleri aynı kalıyor)

  try {
    // Firebase ve Auth'u worker isolate içinde başlat
    await BackgroundEngine.prepareEngine();
  } catch (e) {
    service.stopSelf();
    return;
  }

  // ... (Foreground/Background dinleyicileri aynı)

  print("LynraCareBGEngine: Tek gerçek motor çalışıyor. Takip başlatıldı.");

  // 1. Kalp atışı sadece worker'da başlar
  RTDBService().startLocatorHeartbeat(
    groupId: groupId!,
    deviceId: deviceId!,
    initialBattery: 0, // UpdatePresence zaten güncelleyecek
  );

  // 2. Hareket mantığı sadece worker'da başlar
  _startMovementLogic(service, groupId, deviceId);
  
  // 3. Ayarları dinle
  DeviceStateManager.initSettingsListener(groupId, deviceId);

  // 4. VE ASIL MARŞ: Kaptan burada DeviceStateManager'ı uyandırıyor.
  // isWorker: true olduğu için timer'lar sadece burada dönecek.
  print("DeviceStateManager start called from SINGLE source: BGEngine Worker");
  DeviceStateManager.instance.start(isWorker: true);
}

@pragma('vm:entry-point')
void _startMovementLogic(ServiceInstance service, String groupId, String deviceId) {
  int? _initialSteps;
  bool _isTrackingActive = false;
  Timer? _stopTimer;

  print("LynraCare: Pedometre dinleme başladı.");

  Pedometer.stepCountStream.listen((StepCount event) {
    if (_initialSteps == null) {
      _initialSteps = event.steps;
      print("LynraCare: Kalibrasyon Tamam. Başlangıç Adımı: $_initialSteps");
      return;
    }

    int currentSessionSteps = event.steps - _initialSteps!;
    
    // UI'a her adımda veriyi gönder (Rakamlar canlı artsın)
    service.invoke('onTrackingStatusChanged', {
      "active": _isTrackingActive,
      "currentSteps": currentSessionSteps,
	  "currentIntervalSeconds": DeviceStateManager.currentIntervalSeconds,
    });

    if (currentSessionSteps >= 15 && !_isTrackingActive) {
      _isTrackingActive = true;
      // DOĞRU ÇAĞRI: Parametre ismiyle (active:) çağırıyoruz
      DeviceStateManager.setTrackingState(moving: true);
      print("LynraCare: 15 Adım aşıldı! Sistem 'Takip' modunda.");
    }

    _stopTimer?.cancel();
    _stopTimer = Timer(const Duration(minutes: 5), () {
      print("LynraCare: 5 dakikadır hareket yok. Vites düşürülüyor.");
      _isTrackingActive = false;
      _initialSteps = null;
      
      DeviceStateManager.setTrackingState(moving: false);
      
      service.invoke('onTrackingStatusChanged', {
        "active": false,
        "currentSteps": 0,
		"currentIntervalSeconds": DeviceStateManager.currentIntervalSeconds,
      });
    });
  }, onError: (e) => print("LynraCare: Pedometer Error: $e"));
}