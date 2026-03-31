import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class IdentityManager {
  static Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();

    var id = prefs.getString('DeviceId');
    if (id != null && id.isNotEmpty) return id;

    id =  const Uuid().v4(); 
	await prefs.setString('DeviceId', id);
    return id;
  }
  
static Future<String?> getLocalGroupId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('groupId');
  }

  static Future<void> setLocalGroupId(String groupId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('groupId', groupId);
  }

  static Future<void> clearLocalGroupId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('groupId');
  }


  }