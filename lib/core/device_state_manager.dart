import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:firebase_database/firebase_database.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'alert_engine.dart';
import 'identity_manager.dart';
import 'location_helper.dart';
import 'utils.dart';
import '../../services/rtdb.dart';


class DeviceStateManager {
  DeviceStateManager._();
  static final DeviceStateManager instance = DeviceStateManager._();
  static const int _placeTransitionCooldownSeconds = 120;
  static   int currentIntervalSeconds = 3600; // Başlangıç: 1 Saat
  bool _isWorkerMode = false; // Isolate kimliğini tutacak bayrak
  bool _isActiveRequest = false; 
  Timer? _presenceTimer;
  Timer? _autoSleepTimer;
  Timer? _ticker;
  Timer? _geoTicker;
  
  static bool _isMoving = false;    // Hareket kilidi
  static bool _isWatched = false;   // İzleyici kilidi
  static Timer? _cooldownTimer;

  
  bool gpsEnabled = false;
  bool hasLocationPermission = false;
  bool hasBackgroundLocationPermission = false;
  bool hasActivityPermission = false; 
  bool isBatteryOptimized = false;     
static Function(int)? onIntervalChanged;  
  String? pairCode;
  bool? _gfInside;
  bool _isReady = false;
  final _readyController = StreamController<bool>.broadcast();
  final Battery _battery = Battery();
  StreamSubscription<geo.ServiceStatus>? _gpsSub;
  
  static bool _gpsOffAlarmEnabled = false; 
  static StreamSubscription? _settingsSub;

  bool get isReady => _isReady;

  Stream<bool> get readyStream async* {
    yield _isReady;
    yield* _readyController.stream;
  }
  
  void start({bool isWorker = false}) {
    _isWorkerMode = isWorker;
    _ticker?.cancel();
    _geoTicker?.cancel(); 
	_presenceTimer?.cancel();
	
	print("LynraCare: Manager Mode => ${isWorker ? 'WORKER (BG)' : 'OBSERVER (UI)'}");
    
	// 1. ORTAK GÖREV: Durum Kontrolleri (Her iki tarafta da çalışır)
    _checkState();
	 _gpsSub?.cancel();
    _gpsSub = geo.Geolocator.getServiceStatusStream().listen((_) => _checkState());
	
	// UI tarafı 10 saniyede bir, BG tarafı 30 saniyede bir check etsin (Gereksiz yük olmasın)
    _ticker = Timer.periodic(Duration(seconds: isWorker ? 30 : 10), (_) => _checkState());
	
	// 2. ÖZEL GÖREV: Sadece İşçi (BGEngine) ise Timer'ları kur
    if (_isWorkerMode) {
      _restartPresenceTimer();
      _startGeofenceTicker();
    }
  }
  
static void initSettingsListener(String groupId, String locatorId) {
  _settingsSub?.cancel(); // Eski varsa temizle
  
  _settingsSub = FirebaseFirestore.instance
      .collection('groups').doc(groupId)
      .collection('locators').doc(locatorId)
      .snapshots() 
      .listen((doc) {
    if (doc.exists) {
      _gpsOffAlarmEnabled = doc.data()?['gpsOffAlarmEnabled'] ?? false;
      print("ZINK: Firestore Ayarı Güncellendi -> $_gpsOffAlarmEnabled");
    }
  });
} 
  
  void _restartPresenceTimer() {
    _presenceTimer?.cancel();
    _presenceTimer = Timer.periodic(
      Duration(seconds: currentIntervalSeconds),
      (_) => updatePresence(),
    );
  }
  

  // --- RTDB GÜNCELLEME ---  
  Future<void> updatePresence() async {
  print("LynraCare updatePresence started");
  final locatorId = await IdentityManager.getOrCreateDeviceId();
  final groupId = await IdentityManager.getLocalGroupId(); // Grup ID'sini al
  
  if (groupId == null) return;
  
  int level = 0;
    try { level = await _battery.batteryLevel; } catch (_) {}
    final gpsOn = await geo.Geolocator.isLocationServiceEnabled();

    Map<String, dynamic> rtdbData = {
      'battery': level,
      'gpsEnabled': gpsOn,
      'lastSeen': ServerValue.timestamp,
      'status': 'online', 
    };
	
  // KONUM: 1 saniye yerine 10 saniye nefes payı verdik (Bina içi için kritik)
    final pos = await LocationService.getCurrentLocationSafe(
      accuracy: geo.LocationAccuracy.high,
      timeLimit: const Duration(seconds: 10), 
    );

    if (pos != null) {
      print("LynraCare: Konum yakalandı. Accuracy: ${pos.accuracy}");
      rtdbData.addAll({
        'lat': pos.latitude,
        'lng': pos.longitude,
        'acc': pos.accuracy,
      });
    } else {
      print("LynraCare: Konum alınamadı (10sn Timeout).");
    }	
	
	await RTDBService().updateStatus(
      groupId: groupId,
      deviceId: locatorId,
      data: rtdbData,
    );
    print("LynraCare: RTDB updateStatus [${DateTime.now()}]");
  }
  
Future<void> _checkState() async {
  // 1. Cihaz içi kontroller (Hızlı ve Bedava)
  gpsEnabled = await geo.Geolocator.isLocationServiceEnabled();
  final permission = await geo.Geolocator.checkPermission();
  
  hasLocationPermission = permission != geo.LocationPermission.denied && permission != geo.LocationPermission.deniedForever;
  hasBackgroundLocationPermission = permission == geo.LocationPermission.always;
  hasActivityPermission = await Permission.activityRecognition.isGranted;
  final isBatteryIgnored = await Permission.ignoreBatteryOptimizations.isGranted;
  isBatteryOptimized = !isBatteryIgnored; 

  final ready = gpsEnabled && hasBackgroundLocationPermission && hasActivityPermission && !isBatteryOptimized;
  _updateReady(ready);

  // 2. KRİTİK EŞİK: Eğer GPS zaten AÇIKSA, Firestore'a gidip alarm ayarı sormaya GEREK YOK!
  if (gpsEnabled) {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('gpsOffAlertSent') ?? false) {
      await prefs.setBool('gpsOffAlertSent', false);
    }
    return; // ZINK: Fonksiyon burada biter, Firestore okuması YAPILMAZ.
  }

  // 3. EĞER GPS KAPALIYSA: Zaten Stream ile aldığımız '_gpsOffAlarmEnabled' değişkenine bakıyoruz.
  // Yine Firestore'a gitmiyoruz!
  try {
    final prefs = await SharedPreferences.getInstance();
    final gpsSent = prefs.getBool('gpsOffAlertSent') ?? false;

    // Sadece alarm aktifse ve daha önce gönderilmediyse AlertEngine tetikle
    if (_gpsOffAlarmEnabled && !gpsSent) {
        final locatorId = await IdentityManager.getOrCreateDeviceId();
        final groupId = await IdentityManager.getLocalGroupId();
        final locatorName = await IdentityManager.getMyName();
        
        await AlertEngine.send(
          groupId: groupId!,
          locatorId: locatorId,
          locatorName: locatorName,
          alertType: 'gps_off',
        );
        await prefs.setBool('gpsOffAlertSent', true);
    }
  } catch (e) {
    print('GPS OFF ALERT ERROR => $e');
  }
}
  
  void _updateReady(bool value) {
    if (_isReady == value) return;
    _isReady = value;
    _readyController.add(_isReady);
  }

  void _startGeofenceTicker() {
    _geoTicker?.cancel();
    _geoTicker = Timer.periodic(const Duration(seconds: 60), (_) async {
      // Geofence logic (Arka planda sessizce çalışır)
    });
  }

  Future<void> _handleSavedPlacesGeofence({
    required String locatorId,
    required geo.Position pos,
  }) async {
    final groupId = await IdentityManager.getLocalGroupId();
    if (groupId == null || groupId.isEmpty) return;
    final locatorDoc = await FirebaseFirestore.instance
        .collection('locators')
        .doc(locatorId)
        .get();

    final locatorName = (locatorDoc.data()?['name'] ?? 'Locator').toString();

    final placesSnap = await FirebaseFirestore.instance
        .collection('groups')
        .doc(groupId)
        .collection('locators')
        .doc(locatorId)
        .collection('places')
        .where('enabled', isEqualTo: true)
        .get();

    for (final placeDoc in placesSnap.docs) {
      final data = placeDoc.data();

      final lat = (data['lat'] as num?)?.toDouble();
      final lng = (data['lng'] as num?)?.toDouble();
      final radiusMeters = (data['radiusMeters'] as num?)?.toDouble() ?? 180.0;
      final placeName = (data['name'] ?? 'Place').toString();
      final lastState = (data['lastState'] ?? 'unknown').toString();
      final lastTransitionAt = data['lastTransitionAt'] as Timestamp?;

      if (lat == null || lng == null) continue;

      final dist = geo.Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        lat,
        lng,
      );
      final groupId = await IdentityManager.getLocalGroupId();
      if (groupId == null || groupId.isEmpty) return;

      final newState = dist <= radiusMeters ? 'inside' : 'outside';

      if (lastState == 'unknown' || lastState.isEmpty) {
        await placeDoc.reference.set({
          'lastState': newState,
          'lastTransitionAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        continue;
      }

      if (lastState == newState) continue;

      final now = DateTime.now();
      final canTransition =
          lastTransitionAt == null ||
          now.difference(lastTransitionAt.toDate()).inSeconds >=
              _placeTransitionCooldownSeconds;

      if (!canTransition) continue;

      final transitionType = lastState == 'outside' && newState == 'inside'
          ? 'arrive'
          : 'left';
      final currentAlertType = 'place_${transitionType}_${placeDoc.id}';

      await AlertEngine.send(
        groupId: groupId,
        locatorId: locatorId,
        locatorName: locatorName,
        alertType: currentAlertType,
        extra: {
          'subtype': transitionType,
          'placeId': placeDoc.id,
          'placeName': placeName,
          'distance': dist,
          'radiusMeters': radiusMeters,
        },
      );

      await placeDoc.reference.set({
        'lastState': newState,
        'lastTransitionAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print('PLACE ${transitionType.toUpperCase()} => $placeName ($dist m)');
    }
  }
  
  static void setTrackingState({bool? moving, bool? watched}) {
    // Sadece gelen bilgiyi güncelle, gelmeyene dokunma
    if (moving != null) _isMoving = moving;
    if (watched != null) _isWatched = watched;

    // ANA MANTIK: İkisinden biri bile true ise vites 30sn olmalı
    bool shouldBeFast = _isMoving || _isWatched;

    if (shouldBeFast) {
      _cooldownTimer?.cancel(); // Uyku sayacını durdur
      currentIntervalSeconds = 30;
	  onIntervalChanged?.call(currentIntervalSeconds);
      print("Vites: 30s (Durum -> Hareket: $_isMoving, İzleyici: $_isWatched)");
    } else {
      // İkisi de false ise soğuma başlasın
      if (_cooldownTimer?.isActive ?? false) return;

      print("Aktiflik bitti, 5 dkk geri sayım...");
      _cooldownTimer = Timer(const Duration(minutes: 2), () {
        currentIntervalSeconds = 3600;
		onIntervalChanged?.call(currentIntervalSeconds);
        print("Vites: 3600s (Sessizlik sağlandı)");
      });
    }
  }
}
