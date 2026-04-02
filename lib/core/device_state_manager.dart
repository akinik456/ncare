import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:firebase_database/firebase_database.dart';
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
  int _currentIntervalSeconds = 3600; // Başlangıç: 1 Saat
  bool _isActiveRequest = false; 
  Timer? _presenceTimer;
  Timer? _autoSleepTimer;
  bool? _gfInside;
  bool gpsEnabled = false;
  bool hasLocationPermission = false;
  bool hasBackgroundLocationPermission = false;
  final _readyController = StreamController<bool>.broadcast();
  final Battery _battery = Battery();

  bool _isReady = false;
  Timer? _ticker;
  Timer? _geoTicker;
  String? pairCode;

  StreamSubscription<geo.ServiceStatus>? _gpsSub;

  bool get isReady => _isReady;

  Stream<bool> get readyStream async* {
    yield _isReady;
    yield* _readyController.stream;
  }

  // --- VİTES ARTIRMA (REQUESTER EKRANI AÇINCA ÇAĞRILIR) ---
  void boostTracking() {
    print(" Canlı takip isteği alındı. Periyot: 20sn.");
    _isActiveRequest = true;
    _currentIntervalSeconds = 30; 
    _restartPresenceTimer();

    // 5 dakika sonra otomatik olarak ekonomi moduna (1 saat) dön
    _autoSleepTimer?.cancel();
    _autoSleepTimer = Timer(const Duration(minutes: 5), () {
      print("Zaman aşımı. Ekonomi moduna dönülüyor (3600sn).");
      _isActiveRequest = false;
      _currentIntervalSeconds = 30; 
      _restartPresenceTimer();
    });
  }

  void _restartPresenceTimer() {
    _presenceTimer?.cancel();
    _presenceTimer = Timer.periodic(
      Duration(seconds: _currentIntervalSeconds),
      (_) => updatePresence(),
    );
  }

  void start() {
    print(" Sistem Başlatıldı. Mod: Standby (1 Saat)");
    _ticker?.cancel();
    _geoTicker?.cancel();
    
    _restartPresenceTimer();

    // Geofence kontrolü (60sn bir, sadece yerel kontrol)
    _geoTicker = Timer.periodic(const Duration(seconds: 60), (_) async {
      try {
        final pos = await LocationService.getCurrentLocationSafe(
          accuracy: geo.LocationAccuracy.high,
          timeLimit: const Duration(seconds: 15),
        );
        if (pos == null) return;

        final locatorId = await IdentityManager.getOrCreateDeviceId();
        await _handleSingleCenterGeofence(locatorId: locatorId, pos: pos);
        await _handleSavedPlacesGeofence(locatorId: locatorId, pos: pos);
      } catch (e) {
        print('GF Error: $e');
      }
    });

    _gpsSub?.cancel();
    _checkState();
    _gpsSub = geo.Geolocator.getServiceStatusStream().listen((_) => _checkState());
    _ticker = Timer.periodic(const Duration(seconds: 5), (_) => _checkState());
  }

Future<void> updatePresence() async {
  final locatorId = await IdentityManager.getOrCreateDeviceId();
  final groupId = await IdentityManager.getLocalGroupId(); // Grup ID'sini al
  final level = await _battery.batteryLevel;
  final gpsOn = await geo.Geolocator.isLocationServiceEnabled();

  Map<String, dynamic> rtdbData = {
    'battery': level,
    'gpsEnabled': gpsOn,
    'lastSeen': ServerValue.timestamp,
    'status': 'online', 
  };

  // Konum varsa ekle
  
    final pos = await LocationService.getCurrentLocationSafe(
      accuracy: geo.LocationAccuracy.high,
      timeLimit: const Duration(seconds: 1),
    );
    if (pos != null) {
	print("pos is not null");
      rtdbData.addAll({
        'lat': pos.latitude,
        'lng': pos.longitude,
        'acc': pos.accuracy,
      });
    }
  

  // FIRESTORE YERİNE RTDB'YE BASIYORUZ
  await RTDBService().updateStatus(
    groupId: groupId ?? "unknown_group",
    deviceId: locatorId,
    data: rtdbData,
  );
}

  Future<void> _checkState() async {
    final gpsEnabled = await geo.Geolocator.isLocationServiceEnabled();
    final permission = await geo.Geolocator.checkPermission();
    final hasPermission = permission == geo.LocationPermission.always || 
                         permission == geo.LocationPermission.whileInUse;
    _updateReady(gpsEnabled && hasPermission);
  }

  void _updateReady(bool value) {
    if (_isReady == value) return;
    _isReady = value;
    _readyController.add(_isReady);
  }

Future<void> _handleSingleCenterGeofence({
    required String locatorId,
    required geo.Position pos,
  }) async {
    final groupId = await IdentityManager.getLocalGroupId();
    if (groupId == null || groupId.isEmpty) return;
    final gfDoc = await FirebaseFirestore.instance
        .collection('groups')
        .doc(groupId)
        .collection('locators')
        .doc(locatorId)
        .get();

    final gf = gfDoc.data();

    final enabled = gf?['geofenceAlarmEnabled'] == true;
    final radius = (gf?['geofenceRadius'] as num?)?.toDouble();
    final cLat = (gf?['geofenceCenterLat'] as num?)?.toDouble();
    final cLng = (gf?['geofenceCenterLng'] as num?)?.toDouble();

    if (!enabled || radius == null || cLat == null || cLng == null) return;

    final dist = geo.Geolocator.distanceBetween(
      pos.latitude,
      pos.longitude,
      cLat,
      cLng,
    );

    final inside = dist <= radius;

    if (_gfInside == null) {
      _gfInside = inside;
      return;
    }

    if (_gfInside == true && inside == false) {
      final locatorDoc = await FirebaseFirestore.instance
          .collection('locators')
          .doc(locatorId)
          .get();
      final locatorName = (locatorDoc.data()?['name'] ?? 'Locator').toString();

      print('GF EXIT ALERT => $dist');
    }

    if (_gfInside == false && inside == true) {
      await AlertEngine.clear(
        groupId: groupId,
        locatorId: locatorId,
        alertType: 'geofence_exit',
      );

      print('GF RE-ENTER => alert cleared');
    }

    _gfInside = inside;
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
}