import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'identity_manager.dart';

class LocatorSettings {
  final bool callEnabled;
  final bool batteryAlarmEnabled;
  final bool geofenceAlarmEnabled;
  final int geofenceRadius;
  final String pairedRequesterId;

  const LocatorSettings({
    required this.callEnabled,
    required this.batteryAlarmEnabled,
    required this.geofenceAlarmEnabled,
    required this.geofenceRadius,
    required this.pairedRequesterId,
  });
}

class LocatorSettingsReader {
  static Future<LocatorSettings?> load() async {
  final locatorId = await IdentityManager.getRequesterId();

  final locatorDoc = await FirebaseFirestore.instance
      .collection('locators')
      .doc(locatorId)
      .get();

  final pairedRequesterId =
      (locatorDoc.data()?['pairedRequesterId'] ?? '').toString().trim();

  if (pairedRequesterId.isEmpty) {
    return null;
  }

  final doc = await FirebaseFirestore.instance
      .collection('requesters')
      .doc(pairedRequesterId)
      .collection('locators')
      .doc(locatorId)
      .get();

  final data = doc.data();
  if (data == null) return null;

  return LocatorSettings(
    callEnabled: (data['callEnabled'] ?? true) == true,
    batteryAlarmEnabled: (data['batteryAlarmEnabled'] ?? true) == true,
    geofenceAlarmEnabled: (data['geofenceAlarmEnabled'] ?? false) == true,
    geofenceRadius: (data['geofenceRadius'] as num?)?.toInt() ?? 250,
    pairedRequesterId: pairedRequesterId,
  );
}

}
