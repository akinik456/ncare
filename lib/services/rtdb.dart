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
      print("LynraCare🚀 RTDB: Bağlantı kuruldu, online yapılıyor...");
      
      // onDisconnect mühürünü tekrar bas (Her bağlantıda yenilenmeli)
      locatorRef.onDisconnect().update({
        "status": "offline",
        "lastSeen": ServerValue.timestamp,
      });

				print("LynraCare_HeartBeat");
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
		print("LynraCare_setWatchingStatus");
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
	print("LynraCareRTDB Update Success");
  } catch (e) {
    print("LynraCareRTDB Update Error: $e");
  }
}  

/// 'Beni Ara' (Call Me) komutunu günceller/temizler
  Future<void> updateCallRequest({
    required String groupId,
    required String locatorId,
	String? locatorName,
    required bool isPending,
	String? handlerName,
    String? requesterId,
    String? requesterName,
	String? targetMode,
  }) async {
    final cmdRef = _dbRef.child("presence/groups/$groupId/locators/$locatorId/commands/call_me");

    if (!isPending) {
    if (targetMode == 'single') {
      // Bireysel ise kökten kapat (pending: false)
      await cmdRef.update({"pending": false});
    } else {
      // Genel (Everybody) ise kapatma, "Damga" bas!
      await cmdRef.update({
        "handledBy": handlerName ?? "Someone",
        "handledAt": ServerValue.timestamp,
        // pending: true olarak kalıyor, böylece diğerleri görüyor
      });
    }
  } else {
    // Yeni çağrı oluşturma (Senin mevcut kodun)
    await cmdRef.set({
      "pending": true,
      "targetMode": targetMode ,
	  "locatorName": locatorName,
      "requesterId": requesterId ?? "all",
      "requesterName": requesterName ?? "Everyone",
      "ts": ServerValue.timestamp,
      "handledBy": null, // Yeni çağrıda temizle
    });
  }
}

  /// Kritik Alert'lerin (Battery, GPS, Geofence) anlık durumunu yansıtır
  Future<void> updateAlertStatus({
    required String groupId,
    required String locatorId,
    required String alertType, // 'battery_low', 'gps_off', 'geofence'
    required bool active,
  }) async {
    final alertRef = _dbRef.child("presence/groups/$groupId/locators/$locatorId/alerts/$alertType");
    
    await alertRef.update({
      "active": active,
      "ts": ServerValue.timestamp,
    });
  }

  /// Belirli bir locator'ın komutlarını dinlemek için (Locator tarafı kullanır)
  Stream<DatabaseEvent> getCommandsStream(String groupId, String locatorId) {
    return _dbRef.child("presence/groups/$groupId/locators/$locatorId/commands").onValue;
  }
  
  Stream<DatabaseEvent> getWatchersStream(String groupId, String locatorId) {
  return _dbRef.child("presence/groups/$groupId/active_watchers/$locatorId").onValue;
}
Stream<DatabaseEvent> getGroupPresenceStream(String groupId) {
  return _dbRef.child("presence/groups/$groupId/locators").onValue;
}
}