import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../firebase_options.dart'; 
import 'identity_manager.dart';
import 'role_manager.dart';
import 'auth_service.dart'; 

class FcmManager {
  // EMNİYET KİLİDİ: Sistem bir kez kurulduysa true olur.
  static bool _isInitialized = false;

  /// Uygulamanın ağır toplarını (Firebase, Auth, Subs) uyandıran ana şalter.
  /// Main, HomeScreen veya RequesterScreen'den güvenle çağrılabilir.
  static Future<void> prepareApp() async {
    // Eğer zaten bir yerden çağrıldıysa, tekrar kuruluma girme, hemen dön.
    if (_isInitialized) {
      print("LynraCareSYSTEM: FCM Şalter zaten açık, tekrar kuruluma gerek yok.");
      return;
    }
    try {
      print("LynraCareSYSTEM: FCM Şalter kaldırılıyor... (Bakir cihaz resmileşiyor)");
      // 1. Firebase Temeli (Her şeyin başı)
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      // 2. Kimlik Servisi (Auth olmadan Firestore'a yazamazsın)
      await AuthService.initializeAuth();
      // 3. Bildirim Abonelikleri (Role göre topic'lere bağlanma)
      await FcmManager.ensureSubscriptions();
	  FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
		print("LynraCareFCM TOKEN REFRESH => $token");
		await FcmManager.ensureSubscriptions();
		});
      _isInitialized = true;
      print("LynraCareSYSTEM: FCM Şalter başarıyla kaldırıldı. Tüm servisler aktif.");
    } catch (e) {
      print("LynraCareSYSTEM ERROR: FCM Şalter kaldırılırken hata oluştu => $e");
      // Hata durumunda _isInitialized false kalır, bir sonraki çağrıda tekrar dener.
    }
  }

  /// Rol ve ID bazlı abonelik işlemlerini yöneten metot.
  static Future<void> ensureSubscriptions() async {
    final role = await RoleManager.getRole();
    final myId = await IdentityManager.getOrCreateDeviceId();
    
    // FirebaseMessaging instance'ı burada güvenle çağrılabilir
    // Çünkü prepareApp içinde Firebase.initializeApp çalıştı.
    final token = await FirebaseMessaging.instance.getToken();

    print("LynraCareFCM DEBUG => role=$role");
    print("LynraCareFCM DEBUG => myId=$myId");
    print("LynraCareFCM DEBUG => token=${token?.substring(0, 10)}..."); // Güvenlik için kısa log

    if (token == null || token.isEmpty) {
      print("LynraCareFCM SKIP => Token alınamadı, abonelik pas geçildi.");
      return;
    }

    if (role == 'locator') {
      print("LynraCareFCM => Locator subscribe: locator_$myId");
      await FirebaseMessaging.instance.subscribeToTopic('locator_$myId');
    } else if (role == 'requester') {
      print("LynraCareFCM => Requester subscribe: $myId");
      await FirebaseMessaging.instance.subscribeToTopic(myId);
    } else {
      print("LynraCareFCM SKIP => Rol henüz seçilmemiş ($role), abonelik yapılamaz.");
    }
  }
}