import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:sensors_plus/sensors_plus.dart';
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
  static   int currentIntervalSeconds = 30;//3600; // Başlangıç: 1 Saat
  bool _isWorkerMode = false; // Isolate kimliğini tutacak bayrak
  bool _isActiveRequest = false; 
static  Timer? _presenceTimer;
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
static  final Battery _battery = Battery();
  StreamSubscription<geo.ServiceStatus>? _gpsSub;
  static bool _gfEnabled = false;
// Places (Çoklu Mekanlar)
// Key: placeId, Value: Mekan Bilgileri
static Map<String, Map<String, dynamic>> _cachedPlaces = {};

  static bool _gpsOffAlarmEnabled = false; 
  static StreamSubscription? _settingsSub;
  
static StreamSubscription<QuerySnapshot>? _placesSub;  
  
  // Abonelik yönetimi
StreamSubscription<UserAccelerometerEvent>? _accelSub;

// Hareket durumu
static bool _isMovingByAccel = false;

// Hassasiyet eşiği: 
// 0.2-0.5 arası çok hassas (masa titremesi)
// 1.0-2.0 arası gerçek hareket (yürüme/araç sarsıntısı)
static const double _accelThreshold = 10;

static DateTime? _lastMovementTime;
static const Duration _movementExpiry = Duration(minutes: 5); // 3 dakika tolerans

  bool get isReady => _isReady;

  Stream<bool> get readyStream async* {
    yield _isReady;
    yield* _readyController.stream;
  }
  
  void start({bool isWorker = false}) {
  print("DeviceStateManager called");
    _isWorkerMode = isWorker;
    _ticker?.cancel();
	_ticker = null;
    _geoTicker?.cancel(); 
	_geoTicker = null; 
	_presenceTimer?.cancel();
	_presenceTimer = null;
	_accelSub?.cancel();
    _accelSub = null;
	
	print("LynraCare: Manager Mode => ${isWorker ? 'WORKER (BG)' : 'OBSERVER (UI)'}");
    
    _checkState();
	_gpsSub?.cancel();
    _gpsSub = geo.Geolocator.getServiceStatusStream().listen((_) => _checkState());
	initAccelerometer();
    _restartPresenceTimer();
	
	// UI tarafı 10 saniyede bir, BG tarafı 30 saniyede bir check etsin (Gereksiz yük olmasın)
    _ticker = Timer.periodic(Duration(seconds: isWorker ? 30 : 10), (_) => _checkState());
   // _startGeofenceTicker();
  }
  
static void initSettingsListener(String groupId, String locatorId) {
  // ZIRH: Eğer zaten dinliyorsak, ikinciye gerek yok!
  if (_settingsSub != null) return;
  _placesSub?.cancel(); // Places için yeni abonelik
  
  _settingsSub = FirebaseFirestore.instance
      .collection('groups').doc(groupId)
      .collection('locators').doc(locatorId)
      .snapshots() 
      .listen((doc) {
    if (doc.exists) {
	  final data = doc.data();
      _gpsOffAlarmEnabled = doc.data()?['gpsOffAlarmEnabled'] ?? false;

		// Geofence Ana Ayarlar
      _gfEnabled = data?['geofenceAlarmEnabled'] ?? false;
	  print("ZINK initSettingsListener _gfEnabled:$_gfEnabled");

    }
  });
  
  // 2. PLACES (Çoklu Mekanlar)
  _placesSub = FirebaseFirestore.instance
      .collection('groups').doc(groupId)
      .collection('locators').doc(locatorId)
      .collection('places')
      .where('enabled', isEqualTo: true)
      .snapshots()
      .listen((snap) {
    _cachedPlaces = {
      for (var doc in snap.docs) doc.id: {
        ...doc.data(),
        'id': doc.id, // ID'yi içinde tutalım ki lazım olursa kullanalım
      }
    };
  });
  
} 
  
static  void _restartPresenceTimer() {
  print("LynraCare updatePresence Timer started");
  updatePresence(source: "PRESENCE_TIMER");
    _presenceTimer?.cancel();
    _presenceTimer = Timer.periodic(
      Duration(seconds: currentIntervalSeconds),
      (_) => updatePresence(source: "MAIN_TICKER"),
    );
  }
  

  // --- RTDB GÜNCELLEME ---  
static  Future<void> updatePresence({String source = "UNKNOWN"}) async {
 print("DEBUG: updatePresence tetiklendi! Kaynak: $source, Süre: $currentIntervalSeconds");
 print("LynraCare: currentIntervalSeconds:$currentIntervalSeconds ,RTDB updateStatus [${DateTime.now()}]");
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
  }
  
Future<void> _checkState() async {
print("LynraCare _checkState");
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

// Bu kısım _checkState() fonksiyonunun içine eklenmeli:
if (_isMovingByAccel && _lastMovementTime != null) {
  final silenceDuration = DateTime.now().difference(_lastMovementTime!);

  // Eğer 3 dakikadır (veya belirlediğin süre) hareket yoksa
  if (silenceDuration > const Duration(minutes: 3)) {
    _isMovingByAccel = false;
    print("ZINK: Uzun süreli sessizlik. İvmeölçer tekrar nöbete geçiyor...");
    
    // İvmeölçeri tekrar uyandır
    initAccelerometer();
    
    // Hareket bittiği için Geofence Ticker'ı durdurabilirsin (Opsiyonel)
    _geoTicker?.cancel();
  }
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
  
void initAccelerometer() {
  _accelSub?.cancel();
  print("LynraCare: İvmeölçer bekçisi aktif (Threshold: 10)");

  _accelSub = userAccelerometerEvents.listen((UserAccelerometerEvent event) {
    // x^2 + y^2 + z^2 ile toplam ivmeyi hesapla
    final double power = (event.x * event.x) + (event.y * event.y) + (event.z * event.z);

    if (power > _accelThreshold) { // Threshold'u 10'a çektik
      _lastMovementTime = DateTime.now();
      print("LynraCare: Yüksek ivme tespit edildi ($power). İvmeölçer kapatılıyor...");
      
      // HAREKET ALGILANDI: Donanımsal dinlemeyi durdur (CPU'yu koru)
      _accelSub?.cancel();
      _accelSub = null;
      
      onMovementDetected();
    }
  });
}

  void _startGeofenceTicker() {
  _geoTicker?.cancel();
  _geoTicker = Timer.periodic(const Duration(seconds: 60), (_) async {
    // 1. ANA ŞALTER: Global Geofence kapalıysa zaten uyu.
    print("ZINK _startGeofenceTicker _gfEnabled:$_gfEnabled");
	if (!_gfEnabled) return; 

    // 2. İVME ZIRHI: Hareket yoksa (veya 3 dk'lık tolerans dolduysa) GPS'e dokunma!
    // Bu satır pil ömrünü 3-4 katına çıkaracak olan kritik vuruş.
    if (!_isMovingByAccel) {
      print("ZINK: Hareket yok (Pedometer & Accel sessiz). GPS uykuda.");
      return;
    }

    try {
      // 3. HAREKET VARSA: Artık High Accuracy GPS açmaya değer.
      final pos = await LocationService.getCurrentLocationSafe(
        accuracy: geo.LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      
      if (pos == null) return;

      // 4. MEKAN KONTROLÜ: Hafızadaki cachedPlaces üzerinden akıyoruz.
      final locatorId = await IdentityManager.getOrCreateDeviceId();
      await _handleSavedPlacesGeofence(locatorId: locatorId, pos: pos);
      
    } catch (e) {
      print('ZINK GF Error: $e');
    }
  });
}

// 1. ASIL İŞİ YAPAN MOTOR (FONKSİYON)
Future<void> _performGeofenceCheck() async {
print("ZINK _performGeofenceCheck _gfEnabled:$_gfEnabled");
  if (!_gfEnabled) return;
  
  try {
    final pos = await LocationService.getCurrentLocationSafe(
      accuracy: geo.LocationAccuracy.high,
      timeLimit: const Duration(seconds: 15),
    );
    if (pos == null) return;

    final locatorId = await IdentityManager.getOrCreateDeviceId();
    await _handleSavedPlacesGeofence(locatorId: locatorId, pos: pos);
	print(" ZINK _handleSavedPlacesGeofence call");
  } catch (e) {
    print('ZINK GF Error: $e');
  }
}

void onMovementDetected() {
  if (!_isMovingByAccel) {
    _isMovingByAccel = true;
    print("ZINK: Cihaz hareket moduna geçti!");

    // Anlık kontrolü yap ve rutin Ticker'ı başlat
    _performGeofenceCheck();
    _startGeofenceTicker();
  }
}

Future<void> _handleSavedPlacesGeofence({
  required String locatorId,
  required geo.Position pos,
}) async {
  // 1. Erken Çıkış & Temel Veriler
	print(" ZINK _handleSavedPlacesGeofence fonk");
  if (_cachedPlaces.isEmpty) return;
  
  final groupId = await IdentityManager.getLocalGroupId();
  if (groupId == null || groupId.isEmpty) return;

  // Locator ismini her mekan için tekrar sormayalım, bir kez çekelim
  final locatorDoc = await FirebaseFirestore.instance
      .collection('locators')
      .doc(locatorId)
      .get();
  final locatorName = (locatorDoc.data()?['name'] ?? 'Locator').toString();

  // 2. Hafızadaki (RAM) Mekanlar Üzerinde Döngü
  for (final place in _cachedPlaces.values) {
    final placeId = place['id'];
    final lat = (place['lat'] as num?)?.toDouble();
    final lng = (place['lng'] as num?)?.toDouble();
    final placeName = (place['name'] ?? 'Place').toString();
    final lastState = (place['lastState'] ?? 'unknown').toString();
    final lastTransitionAt = place['lastTransitionAt'] as Timestamp?;
    
    // Radius artık sabit 180m demiştik
    const double radiusMeters = 180.0;

    if (lat == null || lng == null) continue;

    // 3. Mesafe Hesaplama
    final dist = geo.Geolocator.distanceBetween(
      pos.latitude, pos.longitude, lat, lng,
    );

    final newState = dist <= radiusMeters ? 'inside' : 'outside';

    // 4. İlk Tanımlama (Unknown Durumu)
    if (lastState == 'unknown' || lastState.isEmpty) {
      await FirebaseFirestore.instance
          .collection('groups').doc(groupId)
          .collection('locators').doc(locatorId)
          .collection('places').doc(placeId)
          .set({
            'lastState': newState,
            'lastTransitionAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      continue;
    }

    // Durum değişmediyse diğer mekana geç
    if (lastState == newState) continue;

    // 5. Cooldown (Soğuma Süresi) Kontrolü
    final now = DateTime.now();
    final canTransition = lastTransitionAt == null ||
        now.difference(lastTransitionAt.toDate()).inSeconds >= _placeTransitionCooldownSeconds;

    if (!canTransition) continue;

    // 6. Transition (Geçiş) Operasyonu
    final transitionType = (lastState == 'outside' && newState == 'inside') ? 'arrive' : 'left';
    final currentAlertType = 'place_${transitionType}_$placeId';

    // Bildirimi Çak!
    await AlertEngine.send(
      groupId: groupId,
      locatorId: locatorId,
      locatorName: locatorName,
      alertType: currentAlertType,
      extra: {
        'subtype': transitionType,
        'placeId': placeId,
        'placeName': placeName,
        'distance': dist,
        'radiusMeters': radiusMeters,
      },
    );

    // 7. Firestore'u Güncelle (Hafıza zaten listener sayesinde güncellenecek)
    await FirebaseFirestore.instance
        .collection('groups').doc(groupId)
        .collection('locators').doc(locatorId)
        .collection('places').doc(placeId)
        .set({
          'lastState': newState,
          'lastTransitionAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

    print('ZINK: PLACE ${transitionType.toUpperCase()} => $placeName ($dist m)');
  }
}  
  
static void setTrackingState({bool? moving, bool? watched}) {
    // 1. Durumları güncelle
    if (moving != null) _isMoving = moving;
    if (watched != null) _isWatched = watched;

    // 2. Hedef vitesi belirle
    // İkisinden biri aktifse 10sn, ikisi de pasifse (soğuma sonrası) 30sn
    bool shouldBeFast = _isMoving || _isWatched;

    if (shouldBeFast) {
      // Hareket veya izleme geldiği an "Hızlı Mod"a geç
      _cooldownTimer?.cancel(); 
      
      // SADECE vites değişirse callback tetikle (CPU'yu gereksiz yorma)
      if (currentIntervalSeconds != 10) {
        currentIntervalSeconds = 10;
        print("Vites: 10s (Durum -> Hareket: $_isMoving, İzleyici: $_isWatched)");
        onIntervalChanged?.call(currentIntervalSeconds); 
		_restartPresenceTimer();
      }
    } else {
      // İkisi de false ise ve zaten geri sayım başlamadıysa başlat
      if (_cooldownTimer?.isActive ?? false) return;

      print("Aktiflik bitti, 2 dkk sonra 30s moduna geçilecek...");
      _cooldownTimer = Timer(const Duration(minutes: 2), () {
        if (currentIntervalSeconds != 30) {
          currentIntervalSeconds = 30;
          print("Vites: 30s (Sessizlik sağlandı, cooldown bitti)");
          onIntervalChanged?.call(currentIntervalSeconds);
		  _restartPresenceTimer();
        }
      });
    }
  }
}
