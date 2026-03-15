import 'dart:async';

import 'package:geolocator/geolocator.dart' as geo;
import 'package:permission_handler/permission_handler.dart';
import 'identity_manager.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../firebase_options.dart';

class DeviceStateManager {
  DeviceStateManager._();
  static final DeviceStateManager instance = DeviceStateManager._();

  final _readyController = StreamController<bool>.broadcast();

  bool _isReady = false;
  Timer? _ticker;
  Timer? _geoTicker;
  
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
    final pos = await geo.Geolocator.getCurrentPosition(
      desiredAccuracy: geo.LocationAccuracy.high,
    );

    print("GF TEST POS => ${pos.latitude}, ${pos.longitude}");
	final locatorId = await IdentityManager.getRequesterId();
final requesterId = await _getPairedRequesterId(locatorId);

print("GF TEST REQ => $requesterId");
  } catch (_) {}
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