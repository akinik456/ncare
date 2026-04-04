import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';

class NotificationGateway {
  static Future<void> handle(RemoteMessage message) async {
    final data = message.data;
    final type = (data['type'] ?? '').toString();
    final locatorName = (data['locatorName'] ?? 'Locator').toString();
    final requesterName = (data['requesterName'] ?? 'Requester').toString();
    final level = (data['level'] ?? data['battery'] ?? '').toString();
    final placeName = (data['placeName'] ?? 'Place').toString();

    final prefs = await SharedPreferences.getInstance();

    String title = 'LynraCare Alert';
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

        if (NotificationService.suppressForegroundAlerts) return;

        title = 'Call request';
        body = '$locatorName wants you to call';
        break;

      case 'battery_low':
        final enabled = prefs.getBool('requester_battery_alerts') ?? true;
        if (!enabled) return;

        title = 'Battery alert';
        body = '$locatorName battery is low ($level%)';
        break;

      case 'gps_off':
        final enabled = prefs.getBool('gpsOffAlarmEnabled') ?? true;
        if (!enabled) return;

        title = 'GPS disabled';
        body = '$locatorName turned GPS off';
        break;

      case 'geofence_exit':
        final enabled = prefs.getBool('requester_geofence_alerts') ?? true;
        if (!enabled) return;

        title = 'Geofence alert';
        body = '$locatorName left the selected area';
        break;

      default:
        if (type.startsWith('place_arrive')) {
          final enabled = prefs.getBool('requester_geofence_alerts') ?? true;
          if (!enabled) return;

          title = 'Arrived';
          body = '$locatorName arrived at $placeName';
          break;
        }

        if (type.startsWith('place_left')) {
          final enabled = prefs.getBool('requester_geofence_alerts') ?? true;
          if (!enabled) return;

          title = 'Left';
          body = '$locatorName left $placeName';
          break;
        }

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
