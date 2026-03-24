import 'package:cloud_firestore/cloud_firestore.dart';
import 'device_state_manager.dart';

class AlertEngine {
  static String _docId(String type, String locatorId) {
    return '${type}_$locatorId';
  }

  static Future<bool> shouldSend({
    required String requesterId,
    required String locatorId,
    required String alertType,
    int cooldownMinutes = 10,
  }) async {
    final docId = _docId(alertType, locatorId);

    final alertDoc = await FirebaseFirestore.instance
        .collection('requesters')
        .doc(requesterId)
        .collection('alerts')
        .doc(docId)
        .get();

    if (!alertDoc.exists) return true;

    final ts = alertDoc.data()?['ts'] as Timestamp?;
    if (ts == null) return true;

    final diff = DateTime.now().difference(ts.toDate());
    return diff.inMinutes >= cooldownMinutes;
  }

  static Future<void> send({
    required String requesterId,
    required String locatorId,
    required String locatorName,
    required String alertType,
    Map<String, dynamic>? extra,
  }) async {
    final data = {
      'type': alertType,
      'locatorId': locatorId,
      'locatorName': locatorName,
      'ts': FieldValue.serverTimestamp(),
      ...?extra,
    };

    final alertsRef = FirebaseFirestore.instance
        .collection('requesters')
        .doc(requesterId)
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
    required String requesterId,
    required String locatorId,
    required String alertType,
  }) async {
    await FirebaseFirestore.instance
        .collection('requesters')
        .doc(requesterId)
        .collection('alerts')
        .doc(_docId(alertType, locatorId))
        .delete();
  }
}