import 'package:firebase_auth/firebase_auth.dart';


class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static String? get currentAuthId => _auth.currentUser?.uid;

  static bool get isSignedIn => _auth.currentUser != null;
  
	static Future<void> initializeAuth() async {
	  try {
		final user = _auth.currentUser;
		if (user == null) {
		  await _auth.signInAnonymously();
		  print("Yeni anonim oturum açıldı. AuthId: ${currentAuthId}");
		} else {
		  print("Mevcut oturum devam ediyor. AuthId: ${currentAuthId}");
		}
	  } catch (e) {
		print("Auth başlatma hatası: $e");
	  }
	}  

  static Future<String?> signInAnonymously() async {
    try {
      final userCredential = await _auth.signInAnonymously();
      return userCredential.user?.uid;
    } catch (e) {
      return null;
    }
  }
}

