import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'alert_engine.dart';
import 'identity_manager.dart';
import 'location_helper.dart';
import 'utils.dart';

class DeviceStateManager {
  DeviceStateManager._();
  static final DeviceStateManager instance = DeviceStateManager._();

  static const int _placeTransitionCooldownSeconds = 120;

  final _readyController = StreamController<bool>.broadcast();
  
  final Battery _battery = Battery();

  bool _isReady = false;
  Timer? _ticker;
  Timer? _geoTicker;
  Timer? _presenceTimer;
  bool? _gfInside;
  bool gpsEnabled = false;
  bool hasLocationPermission = false;
  bool hasBackgroundLocationPermission = false;
  String? pairCode;

  StreamSubscription<geo.ServiceStatus>? _gpsSub;

  bool get isReady => _isReady;

  Stream<bool> get readyStream async* {
    yield _isReady;
    yield* _readyController.stream;
  }
  
  void start() {
  print("DEVICE STATE MANAGER STARTED");
    _ticker?.cancel();
    _geoTicker?.cancel();
	_presenceTimer?.cancel();
    //_batteryTimer?.cancel();
	
    _updatePresence();

    _presenceTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _updatePresence(),
    );	
	
	
    _geoTicker = Timer.periodic(const Duration(seconds: 60), (_) async {
      try {
        final pos = await LocationService.getCurrentLocationSafe(
          accuracy: geo.LocationAccuracy.high,
          timeLimit: const Duration(seconds: 20),
        );
        if (pos == null) return;

        final locatorId = await IdentityManager.getOrCreateDeviceId();
		final generatedCode = AppUtils.generatePairCode(locatorId);
        final requesterId = await _getPairedRequesterId(locatorId);
        if (requesterId == null || requesterId.isEmpty) return;

        await _handleSingleCenterGeofence(
          requesterId: requesterId,
          locatorId: locatorId,
          pos: pos,
        );

        await _handleSavedPlacesGeofence(
          requesterId: requesterId,
          locatorId: locatorId,
          pos: pos,
        );
      } catch (e) {
        print('GF ERROR => $e');
      }
    });

    _gpsSub?.cancel();
    _checkState();

    _gpsSub = geo.Geolocator.getServiceStatusStream().listen((_) {
      _checkState();
    });

    _ticker = Timer.periodic(const Duration(seconds: 2), (_) => _checkState());
  }

  Future<void> recheckNow() async => _checkState();

  Future<void> requestPermissions() async {
    await Permission.location.request();
    await Permission.locationWhenInUse.request();
	await Permission.locationAlways.request();
    await recheckNow();
  }

Future<void> _checkState() async {
print("DEBUG: _checkState tetiklendi");

  final whenInUsePerm = await Permission.locationWhenInUse.status;
  final alwaysPerm = await Permission.locationAlways.status;
  final gpsEnabled = await geo.Geolocator.isLocationServiceEnabled();

  final hasLocationPermission =
      whenInUsePerm.isGranted || alwaysPerm.isGranted;
  final hasBackgroundLocationPermission = alwaysPerm.isGranted;

  _updateReady(
    hasLocationPermission &&
        hasBackgroundLocationPermission &&
        gpsEnabled,
  );

  try {
    final prefs = await SharedPreferences.getInstance();
    final gpsSent = prefs.getBool('gpsOffAlertSent') ?? false;

    final locatorId = await IdentityManager.getOrCreateDeviceId();
    final groupId = await IdentityManager.getLocalGroupId();
    if (groupId == null || groupId.isEmpty) return;

    final locatorDoc = await FirebaseFirestore.instance
        .collection('locators')
        .doc(locatorId)
        .get();

    final locatorName = (locatorDoc.data()?['name'] ?? 'Locator').toString();

    final requesterId =
        (locatorDoc.data()?['pairedRequesterId'] ?? '').toString().trim();

    if (requesterId.isEmpty) return;

    final settingsDoc = await FirebaseFirestore.instance
        .collection('groups')
        .doc(groupId)
        .collection('locators')
        .doc(locatorId)
        .get();

    final gpsOffAlarmEnabled =
        (settingsDoc.data()?['gpsOffAlarmEnabled'] ?? false) == true;

    if (!gpsEnabled && gpsOffAlarmEnabled && !gpsSent) {
      await AlertEngine.send(
        groupId: groupId,
        locatorId: locatorId,
        locatorName: locatorName,
        alertType: 'gps_off',
      );

      await prefs.setBool('gpsOffAlertSent', true);
    }

    if (gpsEnabled && gpsSent) {
      await prefs.setBool('gpsOffAlertSent', false);
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

  Future<String?> _getPairedRequesterId(String locatorId) async {
    final doc = await FirebaseFirestore.instance
        .collection('locators')
        .doc(locatorId)
        .get();

    final data = doc.data();
    if (data == null) return null;

    return data['pairedRequesterId']?.toString();
  }

  Future<void> _handleSingleCenterGeofence({
    required String requesterId,
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
    required String requesterId,
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
      final radiusMeters =
          (data['radiusMeters'] as num?)?.toDouble() ?? 180.0;
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
      final canTransition = lastTransitionAt == null ||
          now.difference(lastTransitionAt.toDate()).inSeconds >=
              _placeTransitionCooldownSeconds;

      if (!canTransition) continue;

      final transitionType =
    lastState == 'outside' && newState == 'inside' ? 'arrive' : 'left';
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
  
    Future<void> _updatePresence() async {
    final locatorId = await IdentityManager.getOrCreateDeviceId();
    final currentPairCode = AppUtils.generatePairCode(locatorId);

    if (pairCode != currentPairCode) {
    pairCode = currentPairCode;
    // Burada "notifyListeners()" veya benzeri bir tetikleyici 
    // kullanarak UI'a "Veri değişti, ekranı yenile" diyebiliriz.
	}

    final level = await _battery.batteryLevel;
    final gpsOn = await geo.Geolocator.isLocationServiceEnabled();
    final pos = await LocationService.getCurrentLocationSafe(
      accuracy: geo.LocationAccuracy.high,
      timeLimit: const Duration(seconds: 20),
    );
    if (pos == null) return;

    await FirebaseFirestore.instance.collection('locators').doc(locatorId).set({
      'lastSeen': FieldValue.serverTimestamp(),
      'battery': level,
      'gpsEnabled': gpsOn,
      'lat': pos.latitude,
      'lng': pos.longitude,
      'acc': pos.accuracy,
      'pairCode': currentPairCode,
    }, SetOptions(merge: true));

    print('PRESENCE => battery=$level gps=$gpsOn pairCode=$currentPairCode');
  }

}
