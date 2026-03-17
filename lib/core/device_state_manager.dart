import 'dart:async';

import 'package:geolocator/geolocator.dart' as geo;
import 'package:permission_handler/permission_handler.dart';
import 'identity_manager.dart';
import 'location_helper.dart';
import 'alert_engine.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../firebase_options.dart';

class DeviceStateManager {
  DeviceStateManager._();
  static final DeviceStateManager instance = DeviceStateManager._();

  final _readyController = StreamController<bool>.broadcast();

  bool _isReady = false;
  Timer? _ticker;
  Timer? _geoTicker;
  bool? _gfInside;
  
  StreamSubscription<geo.ServiceStatus>? _gpsSub;

  bool get isReady => _isReady;

  // Stream last value first, then updates
  Stream<bool> get readyStream async* {
    yield _isReady;
    yield* _readyController.stream;
  }

  void start() {
  _ticker?.cancel();
  _geoTicker?.cancel();

  _geoTicker = Timer.periodic(const Duration(seconds: 60), (_) async {
    try {
      final pos = await LocationService.getCurrentLocationSafe(
        accuracy: geo.LocationAccuracy.high,
        timeLimit: const Duration(seconds: 20),
      );
      if (pos == null) return;

      final locatorId = await IdentityManager.getRequesterId();
      final requesterId = await _getPairedRequesterId(locatorId);
      if (requesterId == null || requesterId.isEmpty) return;

      final gfDoc = await FirebaseFirestore.instance
          .collection('requesters')
          .doc(requesterId)
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
        await FirebaseFirestore.instance
            .collection('requesters')
            .doc(requesterId)
            .collection('alerts')
            .doc('geofence_exit_$locatorId')
            .set({
          'type': 'geofence_exit',
          'requesterId': requesterId,
          'locatorId': locatorId,
          'distance': dist,
          'ts': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        print("GF EXIT ALERT => $dist");
      }

      if (_gfInside == false && inside == true) {
        await FirebaseFirestore.instance
            .collection('requesters')
            .doc(requesterId)
            .collection('alerts')
            .doc('geofence_exit_$locatorId')
            .delete();

        print("GF RE-ENTER => alert cleared");
      }

      _gfInside = inside;
    } catch (e) {
      print("GF ERROR => $e");
    }
  });

	
	
    _gpsSub?.cancel();

    // Initial check
    _checkState();

    // GPS on/off changes
    _gpsSub = geo.Geolocator.getServiceStatusStream().listen((_) {
      _checkState();
    });

    // Safety polling (OEM devices etc.)
    _ticker = Timer.periodic(const Duration(seconds: 2), (_) => _checkState());
  }

  Future<void> recheckNow() async => _checkState();

  Future<void> requestPermissions() async {
    // While-in-use first
    await Permission.location.request();
    // Then always (may open settings flow depending on device)
    await Permission.locationWhenInUse.request();
  }

  Future<void> _checkState() async {
  final perm = await Permission.locationWhenInUse.status;
  final gpsEnabled = await geo.Geolocator.isLocationServiceEnabled();

  _updateReady(perm.isGranted && gpsEnabled);

  try {
    final prefs = await SharedPreferences.getInstance();
    final gpsSent = prefs.getBool('gpsOffAlertSent') ?? false;

    final locatorId = await IdentityManager.getRequesterId();

    final locatorDoc = await FirebaseFirestore.instance
        .collection('locators')
        .doc(locatorId)
        .get();
		
	final locatorName =
    (locatorDoc.data()?['name'] ?? 'Locator').toString();

    final requesterId =
        (locatorDoc.data()?['pairedRequesterId'] ?? '').toString().trim();

    if (requesterId.isEmpty) return;

    final settingsDoc = await FirebaseFirestore.instance
        .collection('requesters')
        .doc(requesterId)
        .collection('locators')
        .doc(locatorId)
        .get();

    final gpsOffAlarmEnabled =
        (settingsDoc.data()?['gpsOffAlarmEnabled'] ?? false) == true;

    if (!gpsEnabled && gpsOffAlarmEnabled && !gpsSent) {

	final allowed = await AlertEngine.shouldSend(
		requesterId: requesterId,
		locatorId: locatorId,
		alertType: 'gps_off',
	  );

	  if (!allowed) return;

	  await AlertEngine.send(
		requesterId: requesterId,
		locatorId: locatorId,
		locatorName: locatorName,
		alertType: 'gps_off',
	  );

	  await prefs.setBool('gpsOffAlertSent', true);
	}


    if (gpsEnabled && gpsSent) {

	  await AlertEngine.clear(
		requesterId: requesterId,
		locatorId: locatorId,
		alertType: 'gps_off',
	  );

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
}