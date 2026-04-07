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
  final String? role = await RoleManager.getRole();
  final bool setupDone = await SetupManager.isSetupDone();
  final String? groupId = await IdentityManager.getLocalGroupId();
  final String? deviceId = await IdentityManager.getOrCreateDeviceId();
  if (role != 'locator' || !setupDone|| groupId == null || deviceId == null) {
    print("LynraCareBGEngine: Yetkisiz veya eksik kurulum tespiti! BGengine init yapılmadı");
    print("LynraCareBGEngine: role:$role,setupDone:$setupDone,groupId:$groupId,deviceId:$deviceId");
    return;
  }  
  print("LynraCareBGEngine: role:$role,setupDone:$setupDone,groupId:$groupId,deviceId:$deviceId");
  print("LynraCareBackgroundEngine: Konfigüre ediliyor...");
  final service = FlutterBackgroundService();
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
      autoStart: false, // iOS tarafında da manuel kontrol
      onForeground: onStart,
    ),
  );  
  await service.startService();
  print("LynraCareBackgroundEngine: Marşa basıldı!");
 }

  static Future<void> prepareEngine() async {
    // Eğer bu isolate içinde şalter zaten kaldırılmışsa tekrar uğraşma
    if (_bgInitialized) return;

    try {
      print("LynraCareBGEngine: İç şalter kaldırılıyor...");

      // 1. Firebase Temeli (Isolate bağımsız kurulum)
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }

      // 2. Kimlik Servisi (RTDB/Firestore yazımı için Auth şart)
      await AuthService.initializeAuth(); 

      // 3. Bildirim Abonelikleri (Topic'lere bağlanma)
      // Bu işlem cihaz bazlıdır, ama isolate her uyandığında 
      // kontrol etmek abonelik güvenliğini artırır.
      await FcmManager.ensureSubscriptions();

      // 4. Token Yenilenme Dinleyicisi
      // Arka planda uzun süre çalışan bir serviste token değişirse 
      // abonelikleri otomatik tazeler.
      FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
        print("LynraCareBGEngine: FCM TOKEN REFRESH => $token");
        await FcmManager.ensureSubscriptions();
      });

      _bgInitialized = true;
      print("LynraCareBGEngine: İç şalter başarıyla kaldırıldı. Tüm servisler hazır.");
    } catch (e) {
      print("LynraCareBGEngine ERROR: Şalter kaldırılırken hata oluştu => $e");
      // Hata durumunda rethrow yaparak onStart'ın durmasını sağlıyoruz
      rethrow; 
    }
  }
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  
  final String? role = await RoleManager.getRole();
  final bool setupDone = await SetupManager.isSetupDone();
  final String? groupId = await IdentityManager.getLocalGroupId();
  final String? deviceId = await IdentityManager.getOrCreateDeviceId();
  if (role != 'locator' || !setupDone|| groupId == null || deviceId == null) {
    print("LynraCareBGEngine: Yetkisiz veya eksik kurulum tespiti! Servis durduruluyor...");
    print("LynraCareBGEngine: role:$role,setupDone:$setupDone,groupId:$groupId,deviceId:$deviceId");
	service.stopSelf();
    return;
  }
  print("LynraCareBGEngine: role:$role,setupDone:$setupDone,groupId:$groupId,deviceId:$deviceId");
  try {
    await BackgroundEngine.prepareEngine();
  } catch (e) {
    print("LynraCareBGEngine: Şalter kaldırılamadı, durduruluyor: $e");
    service.stopSelf();
    return;
  }
  
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) => service.setAsForegroundService());
    service.on('setAsBackground').listen((event) => service.setAsBackgroundService());
  }
  service.on('stopService').listen((event) => service.stopSelf());
    
  print("LynraCareBGEngine: Motor sorunsuz çalışıyor. Takip başlatıldı.");  
  
  final Battery _battery = Battery();
  int initialLevel = 0;  
    try {
      initialLevel = await Battery().batteryLevel;
    } catch (_) { print("LynraCare battery okuma hatası");}

    // Kalp atışını başlat
    RTDBService().startLocatorHeartbeat(
      groupId: groupId,
      deviceId: deviceId,
      initialBattery: initialLevel,
    );
    // Hareket algılama mantığını başlat
   _startMovementLogic(service, groupId, deviceId);
   DeviceStateManager.initSettingsListener(groupId, deviceId);
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