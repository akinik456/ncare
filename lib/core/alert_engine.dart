import 'package:cloud_firestore/cloud_firestore.dart';

class AlertEngine {
  static String _docId(String type, String locatorId) {
    return '${type}_$locatorId';
  }

  static Future<void> send({
    required String groupId,
    required String locatorId,
    required String locatorName,
    required String alertType,
    Map<String, dynamic>? extra,
  }) async {
    final data = {
      'type': alertType,
      'groupId': groupId,
      'locatorId': locatorId,
      'locatorName': locatorName,
      'ts': FieldValue.serverTimestamp(),
      ...?extra,
    };

    final alertsRef = FirebaseFirestore.instance
        .collection('groups')
        .doc(groupId)
        .collection('locators')
        .doc(locatorId)
        .collection('alerts');

    if (alertType == 'battery_low') {
      final eventDocId =
          '${alertType}_${locatorId}_${DateTime.now().millisecondsSinceEpoch}';
      await alertsRef.doc(eventDocId).set(data);
      return;
    }

    if (alertType == 'gps_off') {
      final eventDocId =
          '${alertType}_${locatorId}_${DateTime.now().millisecondsSinceEpoch}';
      await alertsRef.doc(eventDocId).set(data);
      return;
    }

    if (alertType.startsWith('place_arrive_')) {
      final eventDocId =
          '${alertType}_${locatorId}_${DateTime.now().millisecondsSinceEpoch}';
      await alertsRef.doc(eventDocId).set(data);
      return;
    }

    if (alertType.startsWith('place_left_')) {
      final eventDocId =
          '${alertType}_${locatorId}_${DateTime.now().millisecondsSinceEpoch}';
      await alertsRef.doc(eventDocId).set(data);
      return;
    }

    await alertsRef.doc(_docId(alertType, locatorId)).set(data);
  }

  static Future<void> clear({
    required String groupId,
    required String locatorId,
    required String alertType,
  }) async {
    await FirebaseFirestore.instance
        .collection('groups')
        .doc(groupId)
        .collection('locators')
        .doc(locatorId)
        .collection('alerts')
        .doc(_docId(alertType, locatorId))
        .delete();
  }
}
