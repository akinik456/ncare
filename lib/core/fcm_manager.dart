import 'package:firebase_messaging/firebase_messaging.dart';

import 'identity_manager.dart';
import 'role_manager.dart';

class FcmManager {
  static Future<void> ensureSubscriptions() async {
    final role = await RoleManager.getRole();
    final myId = await IdentityManager.getOrCreateDeviceId();

    if (role == 'locator') {
	  print("locator will try to Subscribe To Topic with $myId");
      final topic = 'locator_$myId';
      await FirebaseMessaging.instance.subscribeToTopic(topic);
      print('FCM OK => $topic');
    }

    if (role == 'requester') {
		 print("requester will try to Subscribe To Topic with $myId");
      await FirebaseMessaging.instance.subscribeToTopic(myId);
      print('FCM OK => $myId');
    }
  }
}
