import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';

class NotificationGateway {

  static Future<void> handle(RemoteMessage message) async {

    final data = message.data;
    final type = (data['type'] ?? '').toString();
    final locatorName = (data['locatorName'] ?? 'Locator').toString();
    final requesterName = (data['requesterName'] ?? 'Requester').toString();
    final level = (data['level'] ?? '').toString();

    final prefs = await SharedPreferences.getInstance();

    String title = 'NCare Alert';
    String body = '';

    switch (type) {

      case 'rl':

        final enabled = prefs.getBool('locator_request_alerts') ?? true;
        if (!enabled) return;

        title = 'Location request';
        body = '$requesterName requested your location';
        break;

      case 'call_me':

        final enabled = prefs.getBool('requester_call_alerts') ?? true;
        if (!enabled) return;

        title = 'Call request';
        body = '$locatorName wants you to call';
        break;

      case 'battery_low':

        final enabled = prefs.getBool('requester_battery_alerts') ?? true;
        if (!enabled) return;

        title = 'Battery alert';
        body = '$locatorName battery is low ($level%)';
        break;

      case 'geofence_exit':

        final enabled = prefs.getBool('requester_geofence_alerts') ?? true;
        if (!enabled) return;

        title = 'Geofence alert';
        body = '$locatorName left the selected area';
        break;

      default:
        return;
    }

    await NotificationService.show(
      title: title,
      body: body,
      type: type,
      locatorName: locatorName,
    );
  }
}
