import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class IdentityManager {
  static Future<String> getRequesterId() async {
    final prefs = await SharedPreferences.getInstance();

    var id = prefs.getString('requesterId');
    if (id != null && id.isNotEmpty) return id;

    id = const Uuid().v4();
    await prefs.setString('requesterId', id);
    return id;
  }

	static Future<String> getLocatorId() async {
	  final prefs = await SharedPreferences.getInstance();

	  var id = prefs.getString('locatorId');
	  if (id != null && id.isNotEmpty) return id;

	  id = const Uuid().v4();
	  await prefs.setString('locatorId', id);
	  return id;
	}  
  
}