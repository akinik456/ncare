import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';

class RTDBService {
  // Singleton yapısı: Her yerden aynı instance'a erişmek için
  static final RTDBService _instance = RTDBService._internal();
  factory RTDBService() => _instance;
  RTDBService._internal();

  final DatabaseReference _dbRef = FirebaseDatabase.instanceFor(
  app: Firebase.app(),
  databaseURL: 'https://ncare-5ad1f-default-rtdb.firebaseio.com',
).ref();

 int _lastBatteryLevel = 0;
 
  /// Locator için 'Online' nabız atışını başlatır
  void startLocatorHeartbeat({
  required String groupId,
  required String deviceId,
  required int initialBattery,
}) {
  _lastBatteryLevel = initialBattery;
  final locatorRef = _dbRef.child("presence/groups/$groupId/locators/$deviceId");
  final connectedRef = FirebaseDatabase.instance.ref(".info/connected");

  // 1. Firebase'in kendi bağlantı durumunu dinliyoruz (MÜTHİŞ ÖZELLİK)
  connectedRef.onValue.listen((event) {
    final connected = event.snapshot.value as bool? ?? false;

    if (connected) {
      // İnternet geldiği an burası tetiklenir!
      print("🚀 RTDB: Bağlantı kuruldu, online yapılıyor...");
      
      // onDisconnect mühürünü tekrar bas (Her bağlantıda yenilenmeli)
      locatorRef.onDisconnect().update({
        "status": "offline",
        "lastSeen": ServerValue.timestamp,
      });

      // Status'u online yap
      locatorRef.update({
        "status": "online",
		"battery": _lastBatteryLevel,
        "lastSeen": ServerValue.timestamp,
      });
    }
  });
}

  /// Requester bir cihazı seçtiğinde (odaklandığında) çalışır
  void setWatchingStatus({
    required String groupId,
    required String locatorId,
    required String requesterId,
    required String requesterName,
    required bool isWatching,
  }) {
    final watcherRef = _dbRef.child("presence/groups/$groupId/active_watchers/$locatorId/$requesterId");

    if (isWatching) {
      // İzlemeye başlayınca: onDisconnect ile otomatik temizlik ekle
      watcherRef.onDisconnect().remove();
      
      watcherRef.set({
        "name": requesterName,
        "at": ServerValue.timestamp,
      });
    } else {
      // Odaktan çıkınca: Manuel temizle
      watcherRef.remove();
    }
  }
  
Future<void> updateStatus({
  required String groupId,
  required String deviceId,
  required Map<String, dynamic> data,
}) async {
  try {
    final locatorRef = _dbRef.child("presence/groups/$groupId/locators/$deviceId");
    
    // update() kullanarak sadece paketteki alanları günceller, 
    // mevcut diğer verileri (status gibi) bozmaz.
    await locatorRef.update(data);
	print("RTDB Update Success");
  } catch (e) {
    print("RTDB Update Error: $e");
  }
}  
  
  Stream<DatabaseEvent> getWatchersStream(String groupId, String locatorId) {
  return _dbRef.child("presence/groups/$groupId/active_watchers/$locatorId").onValue;
}
Stream<DatabaseEvent> getGroupPresenceStream(String groupId) {
  return _dbRef.child("presence/groups/$groupId/locators").onValue;
}
}