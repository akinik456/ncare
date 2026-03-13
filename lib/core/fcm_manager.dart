import 'package:firebase_messaging/firebase_messaging.dart';

import 'identity_manager.dart';
import 'role_manager.dart';

class FcmManager {
  static Future<void> ensureSubscriptions() async {
    final role = await RoleManager.getRole();
    final myId = await IdentityManager.getRequesterId();

    if (role == 'locator') {
      final topic = 'locator_$myId';
      await FirebaseMessaging.instance.subscribeToTopic(topic);
      print('FCM OK => $topic');
    }

    if (role == 'requester') {
      await FirebaseMessaging.instance.subscribeToTopic(myId);
      print('FCM OK => $myId');
    }
  }
}
