import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:firebase_database/firebase_database.dart';
import 'package:permission_handler/permission_handler.dart';

import 'alert_engine.dart';
import 'identity_manager.dart';
import 'location_helper.dart';
import 'utils.dart';
import '../../services/rtdb.dart';


class DeviceStateManager {
  DeviceStateManager._();
  static final DeviceStateManager instance = DeviceStateManager._();
  static const int _placeTransitionCooldownSeconds = 120;
  // --- DINAMIK PERIYOT DEĞİŞKENLERİ ---
  int _currentIntervalSeconds = 30; // Başlangıç: 1 Saat
  bool _isWorkerMode = false; // Isolate kimliğini tutacak bayrak
  bool _isActiveRequest = false; 
  Timer? _presenceTimer;
  Timer? _autoSleepTimer;
  Timer? _ticker;
  Timer? _geoTicker;
  
  bool gpsEnabled = false;
  bool hasLocationPermission = false;
  bool hasBackgroundLocationPermission = false;
  bool hasActivityPermission = false; 
  bool isBatteryOptimized = false;     
  
  String? pairCode;
  bool? _gfInside;
  bool _isReady = false;
  final _readyController = StreamController<bool>.broadcast();
  final Battery _battery = Battery();
  StreamSubscription<geo.ServiceStatus>? _gpsSub;

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
  
  void _restartPresenceTimer() {
    _presenceTimer?.cancel();
    _presenceTimer = Timer.periodic(
      Duration(seconds: _currentIntervalSeconds),
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
  
  // --- DURUM KONTROLÜ (UI İÇİN) ---
  Future<void> _checkState() async {
    gpsEnabled = await geo.Geolocator.isLocationServiceEnabled();
    final permission = await geo.Geolocator.checkPermission();
    
    hasLocationPermission = permission != geo.LocationPermission.denied && 
                            permission != geo.LocationPermission.deniedForever;
    hasBackgroundLocationPermission = permission == geo.LocationPermission.always;
    hasActivityPermission = await Permission.activityRecognition.isGranted;

    final isBatteryIgnored = await Permission.ignoreBatteryOptimizations.isGranted;
    isBatteryOptimized = !isBatteryIgnored; 

    final ready = gpsEnabled && 
                  hasBackgroundLocationPermission && 
                  hasActivityPermission && 
                  !isBatteryOptimized;

    _updateReady(ready);
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
  
    // --- VİTES ARTIRMA (REQUESTER EKRANI AÇINCA ÇAĞRILIR) ---
  void boostTracking() {
    print("LynraCare Canlı takip isteği alındı. Periyot: 20sn.");
    _isActiveRequest = true;
    _currentIntervalSeconds = 20; 
    _restartPresenceTimer();

    // 5 dakika sonra otomatik olarak ekonomi moduna (1 saat) dön
    _autoSleepTimer?.cancel();
    _autoSleepTimer = Timer(const Duration(minutes: 5), () {
      print("LynraCareZaman aşımı. Ekonomi moduna dönülüyor (3600sn).");
      _isActiveRequest = false;
      _currentIntervalSeconds = 20; 
      _restartPresenceTimer();
    });
  }
}
