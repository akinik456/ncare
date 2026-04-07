import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:battery_plus/battery_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:restart_app/restart_app.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../core/alert_engine.dart';
import '../../core/device_state_manager.dart';
import '../../core/identity_manager.dart';
import '../../core/utils.dart';
import '../../services/rtdb.dart';

import '../setup/setup_screen.dart';
import '../../core/background_engine.dart';


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {

  String? locatorId;
  String? locatorName;
  String? requesterName;
  String? displayname;
  String? pairCode;

  Timer? _batteryTimer;
  final Battery _battery = Battery();
  int? _lastBatteryLevel;
  
  String? groupId;
  String? deviceId;
  String _movementStatus = "Hareketsiz"; // Bunu ekle
  int _displaySteps = 0;
  String? _cachedMyName;
  
  DatabaseReference? _watchersRef;
  StreamSubscription<DatabaseEvent>? _watchersSubscription;
  bool _isBeingWatched = false;
  String _watcherName = "";
  int _displayInterval = 3600;
  
@override
void initState() {
  super.initState();
  _initEverything();
  
  DeviceStateManager.onIntervalChanged = (newVal) {
    if (mounted) {
      setState(() {
        _displayInterval = newVal;
      });
    }
	if (groupId != null && locatorId != null) {
	DeviceStateManager.initSettingsListener(groupId!, locatorId!);
	}
  };  

  FlutterBackgroundService().on('onTrackingStatusChanged').listen((event) {
    if (!mounted || event == null) return; 
	final bool isActive = event['active'] ?? false;
	final int steps = event['currentSteps'] ?? 0;
	DeviceStateManager.setTrackingState(moving: isActive);
    setState(() {
      _displaySteps = steps; 
      _movementStatus = isActive 
          ? "Takip Aktif ($_displaySteps Adım)" 
          : "Hareketsiz (Bekliyor: $_displaySteps/15)";
    });
  });
}

	Future<void> _initWatchersListener() async {
  _watchersRef = FirebaseDatabase.instance
    .ref("presence/groups/${groupId}/active_watchers/${locatorId}");

_watchersSubscription = _watchersRef?.onValue.listen((event) {
  // 1. Veriyi çek ve Map'e çevir
  final data = event.snapshot.value;
  
  if (data != null && data is Map) {
	setState(() {
		  _isBeingWatched = true;
		  
		  // Tüm isimleri bir listeye toplayalım
		  List<String> nameList = [];
		  data.values.forEach((v) {
			if (v is Map && v["name"] != null) {
			  nameList.add(v["name"].toString());
			}
		  });

		  // İsimleri virgülle birleştir (Örn: "r23, Ahmet, Ayşe")
		  if (nameList.length <= 2) {
			_watcherName = nameList.join(", ");
		  } else {
			// Eğer 2'den fazlaysa: "r23, Ahmet +1 kişi" gibi şık göster
			_watcherName = "${nameList[0]}, ${nameList[1]} +${nameList.length - 2} kişi";
		  }
		});
  DeviceStateManager.setTrackingState(watched: true);
  } else {
    // 3. Veri yoksa veya boşsa durumu sıfırla
    setState(() {
      _isBeingWatched = false;
      _watcherName = "";
    });
  // ZIRHLI GÜNCELLEME: İzleyici artık yok (false)
  // Bu, vitesi hemen 1 saate çekmez, sadece "izleyici bitti" der.
  // Eğer o sırada hareket (moving) varsa vites 30sn'de kalmaya devam eder.
  DeviceStateManager.setTrackingState(watched: false);
  }
});
}	
	Future<void> _initEverything() async {
    await _initLocatorId();
    await _loadLocatorName();
    
    groupId = await IdentityManager.getLocalGroupId(); 
    deviceId = await IdentityManager.getOrCreateDeviceId();
    
	
	if (groupId != null && deviceId != null) {
    setState(() {
      
    });
	_initWatchersListener();
}
    _startBatteryMonitor();
    // UI'ı güncellemek gerekirse
    if (mounted) setState(() {});
  }    
  
  @override
  void dispose() {
    _batteryTimer?.cancel();
	_watchersSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initLocatorId() async {
    final id = await IdentityManager.getOrCreateDeviceId();
	final generatedCode = AppUtils.generatePairCode(id);

    if (!mounted) return;

    setState(() {
      locatorId = id;
      pairCode = generatedCode;
    });

    await _syncPairCode(id, generatedCode);
    _checkPairing();
  }

  Future<void> _loadRequesterName() async {
    final locatorId = await IdentityManager.getOrCreateDeviceId();
    final doc = await FirebaseFirestore.instance
        .collection('locators')
        .doc(locatorId)
        .get();

    if (!mounted) return;

    setState(() {
      requesterName =
          (doc.data()?['pairedRequesterName'] ?? '').toString().trim();

      displayname = requesterName!.isNotEmpty ? requesterName : 'requester';
    });
  }

  Future<void> _loadLocatorName() async {
    final name = await IdentityManager.getMyName();
  setState(() {
	_cachedMyName = name;
	locatorName = name;
  });
  }

  Future<void> _checkPairing() async {
    if (locatorId == null || locatorId!.isEmpty) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('locators')
          .doc(locatorId)
          .get();

      final requesterId = doc.data()?['pairedRequesterId']?.toString();

      if (requesterId != null && requesterId.isNotEmpty) {
        final locatorTopic = 'locator_$locatorId';

        try {
          print('PAIRED WITH REQUESTER => $requesterId');
          print('SUBSCRIBED => $locatorTopic');
        } catch (e) {
          print('SUBSCRIBED ERR => $e');
        }
      } else {
        print('NO PAIR FOUND');
      }
    } catch (e) {
      print('PAIRING ERROR => $e');
    }
  }

Future<void> _sendCallMeRequest({
  String? requesterId,
  String? requesterName,
}) async {
  // 1. Ortak Verileri Hazırla
  final bool isAll = requesterId == null;
  final String locatorId = await IdentityManager.getOrCreateDeviceId();

  final locatorDoc = await FirebaseFirestore.instance
      .collection('locators')
      .doc(locatorId)
      .get();
      
  final String locatorName = _cachedMyName ?? 'Locator';// (locatorDoc.data()?['name'] ?? 'Locator').toString();
  final String groupId = (locatorDoc.data()?['groupId'] ?? '').toString().trim();
   print("LynraCare locatorName:$locatorName");
  
  
  if (groupId.isEmpty) return;

  // 2. Firestore'a Yaz (Mevcut Bildirim/FCM Yapısı İçin)
  final alertData = {
    'type': 'call_me',
    'groupId': groupId,
    'locatorId': locatorId,
    'locatorName': locatorName,
    'targetMode': isAll ? 'all' : 'single',
    'ts': FieldValue.serverTimestamp(),
  };

  if (!isAll) {
    alertData['requesterDeviceId'] = requesterId;
    alertData['requesterName'] = requesterName!;
  }

  await FirebaseFirestore.instance
      .collection('groups')
      .doc(groupId)
      .collection('locators')
      .doc(locatorId)
      .collection('alerts')
      .add(alertData);

  // --- RTDB KATMANI (GELECEK ADIMIN TEMELİ) ---
  // Buraya birazdan RTDB yazma kodunu da ekleyeceğiz ki "Noter" kaydı tutulsun.
  // --------------------------------------------
	try{
	await RTDBService().updateCallRequest(
	  groupId: groupId,
	  locatorId: locatorId,
	  locatorName: locatorName, 
	  isPending: true,
	  targetMode: isAll ? 'all' : 'single',
	  requesterId: requesterId,
	  requesterName: requesterName,
	);
	print("LynraCare: RTDB Call Request mühürlendi!");
    } catch (e) {
	print("LynraCare: RTDB Yazma Hatası: $e");
    }
	  
  if (!mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(isAll ? 'Call request sent to everybody' : 'Call request sent to $requesterName'),
      duration: const Duration(seconds: 2),
    ),
  );
}


  Future<void> _startBatteryMonitor() async {
    _batteryTimer?.cancel();

    _batteryTimer = Timer.periodic(const Duration(minutes: 1), (timer) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final batterysent = prefs.getBool('batteryAlertSent') ?? false;

        final level = await _battery.batteryLevel;
        _lastBatteryLevel = level;

        final locatorId = await IdentityManager.getOrCreateDeviceId();

        final locatorDoc = await FirebaseFirestore.instance
            .collection('locators')
            .doc(locatorId)
            .get();

        final groupId = await IdentityManager.getLocalGroupId();
		if (groupId == null || groupId.isEmpty) return;
		final locatorName = (locatorDoc.data()?['name'] ?? 'Locator').toString();

        final requesterId =
            (locatorDoc.data()?['pairedRequesterId'] ?? '').toString().trim();

        if (requesterId.isEmpty) return;

        final settingsDoc = await FirebaseFirestore.instance
            .collection('groups')
            .doc(groupId)
            .collection('locators')
            .doc(locatorId)
            .get();

        final threshold =
            (settingsDoc.data()?['batteryAlertThreshold'] ?? 20) as int;

        final batteryAlarmEnabled =
            (settingsDoc.data()?['batteryAlarmEnabled'] ?? false) == true;

        if (level <= threshold && batteryAlarmEnabled && !batterysent) {
          
          await AlertEngine.send(
             groupId: groupId,
			  locatorId: locatorId,
			  locatorName: locatorName,
			  alertType: 'battery_low',
			  extra: {
				'level': level,
			},
          );

          await prefs.setBool('batteryAlertSent', true);
        }

        if (level > threshold && batterysent) {
          
          await prefs.setBool('batteryAlertSent', false);
        }
      } catch (e) {
        print('BATTERY MONITOR ERROR => $e');
      }
    });
  }


  Future<void> _syncPairCode(String locatorId, String pairCode) async {
    try {
      await FirebaseFirestore.instance.collection('locators').doc(locatorId).set({
        'pairCode': pairCode,
      }, SetOptions(merge: true));
    } catch (e) {
      print('PAIR CODE SYNC ERROR => $e');
    }
  }


Future<void> _approvePendingPair() async {
  if (locatorId == null || locatorId!.isEmpty) return;

  try {
    final docRef =
        FirebaseFirestore.instance.collection('locators').doc(locatorId);

    final snap = await docRef.get();
    final data = snap.data();
    if (data == null) return;

    final pendingRequesterId =
        (data['pendingPairRequesterId'] ?? '').toString().trim();
    final pendingRequesterName =
        (data['pendingPairRequesterName'] ?? '').toString().trim();
    final groupId =
        (data['pendingPairGroupId'] ?? '').toString().trim();

    if (pendingRequesterId.isEmpty) return;
    if (groupId.isEmpty) return;

final pairedRequestersRaw =
    (data['pairedRequesters'] as Map<String, dynamic>?) ?? {};
final pairedRequesters =
    Map<String, dynamic>.from(pairedRequestersRaw);

final alreadyPaired = pairedRequesters.containsKey(pendingRequesterId);

const locatorRequesterLimit = 2; // şimdilik sabit

if (!alreadyPaired && pairedRequesters.length >= locatorRequesterLimit) {
  print('APPROVE BLOCKED => locator requester limit reached');
  return;
}

final groupSnap = await FirebaseFirestore.instance
    .collection('groups')
    .doc(groupId)
    .get();

final groupData = groupSnap.data() ?? {};
final maxDevicesCount =
    (groupData['maxDevicesCount'] as num?)?.toInt() ?? 10;

final devicesSnap = await FirebaseFirestore.instance
    .collection('groups')
    .doc(groupId)
    .collection('devices')
    .where('active', isEqualTo: true)
    .get();

final activeDevicesCount = devicesSnap.docs.length;

final locatorAlreadyInGroup = devicesSnap.docs.any((d) => d.id == locatorId);

if (!locatorAlreadyInGroup && activeDevicesCount >= maxDevicesCount) {
  print('APPROVE BLOCKED => group max device limit reached');
  return;
}

    if (!alreadyPaired) {
      pairedRequesters[pendingRequesterId] = {
        'requesterId': pendingRequesterId,
        'name': pendingRequesterName,
        'joinedAt': FieldValue.serverTimestamp(),
        'active': true,
      };
    }

    final pairedRequestersCount = pairedRequesters.length;

    await IdentityManager.setLocalGroupId(groupId);

    await docRef.set({
      'pairedRequesterId': pendingRequesterId, // eski alan şimdilik dursun
      'pairedRequesterName': pendingRequesterName, // eski alan şimdilik dursun
      'pairedRequesters': pairedRequesters,
      'pairedRequestersCount': pairedRequestersCount,
      'groupId': groupId,
      'pendingPairRequesterId': FieldValue.delete(),
      'pendingPairRequesterName': FieldValue.delete(),
      'pendingPairCreatedAt': FieldValue.delete(),
      'pendingPairGroupId': FieldValue.delete(),
	  'active': true,
    }, SetOptions(merge: true));

    await FirebaseFirestore.instance
        .collection('groups')
        .doc(groupId)
        .collection('devices')
        .doc(locatorId)
        .set({
      'deviceId': locatorId,
      'groupId': groupId,
      'role': 'locator',
      'name': (data['name'] ?? 'Locator').toString(),
      'joinedAt': FieldValue.serverTimestamp(),
      'active': true,
    }, SetOptions(merge: true));
    await FirebaseFirestore.instance
        .collection('groups')
        .doc(groupId)
        .collection('locators')
        .doc(locatorId)
        .set({
      'locatorId': locatorId,
      'name': (data['name'] ?? 'Locator').toString(),
      'joinedAt': FieldValue.serverTimestamp(),
      'active': true,
  // ---- DEFAULT SETTINGS ----
  'callEnabled': true,
  'gpsOffAlarmEnabled': true,
  'batteryAlarmEnabled': true,
  'batteryAlertThreshold': 20,
  'placeAlarmEnabled': false,
  'geofenceAlarmEnabled': false,
  'geofenceRadius': 250,
    }, SetOptions(merge: true));


	if(pairedRequestersCount==1)
	{
	Restart.restartApp();
	}

  } catch (e) {
    print('APPROVE PENDING PAIR ERROR => $e');
	return;
  }
}


  Future<void> _rejectPendingPair() async {
    if (locatorId == null || locatorId!.isEmpty) return;

    try {
      await FirebaseFirestore.instance.collection('locators').doc(locatorId).set({
        'pendingPairRequesterId': FieldValue.delete(),
        'pendingPairRequesterName': FieldValue.delete(),
        'pendingPairCreatedAt': FieldValue.delete(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pairing rejected'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      print('REJECT PENDING PAIR ERROR => $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to reject pairing'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildPendingPairCard(ThemeData theme, Map<String, dynamic>? data) {
    final pendingRequesterId =
        (data?['pendingPairRequesterId'] ?? '').toString().trim();
    final pendingRequesterName =
        (data?['pendingPairRequesterName'] ?? '').toString().trim();

    if (pendingRequesterId.isEmpty) {
      return const SizedBox.shrink();
    }

    final displayName = pendingRequesterName.isNotEmpty
        ? pendingRequesterName
        : 'Requester';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEDD5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.person_add_alt_1_rounded,
                  color: Color(0xFFEA580C),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pending Pair Request',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$displayName wants to pair with this locator.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF475569),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _rejectPendingPair,
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Reject'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFB91C1C),
                    side: const BorderSide(color: Color(0xFFFECACA)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _approvePendingPair,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Approve'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (locatorId == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
	


    final theme = Theme.of(context);
    final currentPairCode = pairCode ?? AppUtils.generatePairCode(locatorId!);

    final qrData = jsonEncode({
      'type': 'Lynracare_locator',
      'locatorId': locatorId,
      'locatorName': locatorName ?? 'Locator',
    });

return Scaffold(
  backgroundColor: const Color(0xFF020617),
  appBar: AppBar(
    backgroundColor: const Color(0xFF020617),
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    centerTitle: true,
    title: const Text(
      'LYNRA Care',
      style: TextStyle(
        fontWeight: FontWeight.w800,
        color: Color(0xFF334155),
      ),
    ),
  ),

  body: SafeArea(
    child: Column(
      children: [
        const SizedBox(height: 6),

        Center(
          child: Text(
            locatorName ?? 'Device',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Color(0xFF334155),
            ),
          ),
        ),
if (_isBeingWatched)
  Padding(
    padding: const EdgeInsets.only(top: 8.0),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.visibility, color: Colors.greenAccent, size: 18),
        const SizedBox(width: 6),
        Flexible( // <--- İsim çok uzunsa ekranın dışına taşmasın diye
          child: Text(
            _watcherName,
            style: const TextStyle(
              color: Colors.greenAccent, 
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
            overflow: TextOverflow.ellipsis, // Taşarsa "..." yapar
          ),
        ),
      ],
    ),
  ),
 
Container(
  padding: const EdgeInsets.all(4),
  decoration: BoxDecoration(
    color: Colors.black54,
    borderRadius: BorderRadius.circular(4),
  ),
  child: Text(
    "Vites: ${_displayInterval}s",
    style: const TextStyle(
      color: Colors.yellowAccent, 
      fontSize: 10, 
      fontWeight: FontWeight.bold
    ),
  ),
),
 
  
const SizedBox(height: 6),
// --- GÜNCELLENMİŞ TAKİP VE ADIM DURUMU ---
Container(
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  decoration: BoxDecoration(
    color: _movementStatus.contains("Aktif") 
        ? Colors.teal.shade50 
        : Colors.blueGrey.shade50,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(
      color: _movementStatus.contains("Aktif") 
          ? Colors.teal.withOpacity(0.2) 
          : Colors.blueGrey.withOpacity(0.2),
    ),
  ),
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        _movementStatus,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: _movementStatus.contains("Aktif") ? Colors.teal : Colors.blueGrey,
        ),
      ),
      const SizedBox(height: 2),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.directions_walk, 
            size: 16, 
            color: _movementStatus.contains("Aktif") ? Colors.teal : Colors.blueGrey
          ),
          const SizedBox(width: 4),
          Text(
            "$_displaySteps Adım",
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: _movementStatus.contains("Aktif") ? Colors.teal.shade700 : Colors.blueGrey.shade700,
            ),
          ),
        ],
      ),
    ],
  ),
),


Expanded(
  child: Column( // Ana taşıyıcıyı Column yaptık ki butonu alta itebilelim
    children: [
      // ÜST KISIM: Kaydırılabilir Kartlar Bölümü
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 80, 20, 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: StreamBuilder<bool>(
              stream: DeviceStateManager.instance.readyStream,
              initialData: DeviceStateManager.instance.isReady,
              builder: (context, snapshot) {
                final ready = snapshot.data ?? false;
                final gpsEn = DeviceStateManager.instance.gpsEnabled;
                
                String statusTitle = ready ? 'Locator Device Ready' : (!gpsEn ? 'Location Service Off' : 'Permissions Required');

                return Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // --- ANA DURUM KARTI (GLASSMORPHISM) ---
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF020617).withOpacity(0.8),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: (ready ? const Color(0xFF14B8A6) : const Color(0xFFB45309)).withOpacity(0.15),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (ready ? const Color(0xFF14B8A6) : const Color(0xFFD97706)).withOpacity(0.2),
                            blurRadius: 30,
                            spreadRadius: 1,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            ready ? Icons.verified_user_rounded : Icons.gpp_maybe_rounded,
                                            color: ready ? const Color(0xFF5EEAD4) : const Color(0xFFF59E0B),
                                            size: 20,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            statusTitle,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 18,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: -0.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      const Text(
                                        'PAIRING CODE',
                                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 2),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        currentPairCode,
                                        style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 6),
                                      ),
                                      const SizedBox(height: 12),
                                      const Text(
                                        'LOCATOR ID',
                                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5),
                                      ),
                                      SelectableText(
                                        locatorId ?? 'N/A',
                                        style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500, fontFamily: 'monospace'),
                                      ),
                                    ],
                                  ),
                                ),
                                // QR Bölümü
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    GestureDetector(
                                      onTap: () => _showLargeQr(context, qrData),
                                      child: Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.95),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: QrImageView(
                                          data: qrData,
                                          size: 90,
                                          version: QrVersions.auto,
                                          padding: const EdgeInsets.all(0),
                                          eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Tap to enlarge',
                                      style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // --- EŞLEŞME DURUM KARTI ---
                    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance.collection('locators').doc(locatorId).snapshots(),
                      builder: (context, snapshot) {
                        final data = snapshot.data?.data();
                        final pairedRequesters = data?['pairedRequesters'] as Map<String, dynamic>?;
                        final pairedNames = pairedRequesters?.values
                            .map((e) => Map<String, dynamic>.from(e as Map))
                            .where((e) => e['active'] == true)
                            .map((e) => (e['name'] ?? 'Requester').toString())
                            .toList() ?? [];

                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B).withOpacity(0.4),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                pairedNames.isNotEmpty ? Icons.verified_user_rounded : Icons.link_off_rounded,
                                color: pairedNames.isNotEmpty ? const Color(0xFF14B8A6) : const Color(0xFF64748B),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  pairedNames.isNotEmpty ? 'Paired with ${pairedNames.join(', ')}' : 'Not paired yet',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
      // ALT KISIM: EKRANIN EN ALTINA SABİTLENEN BUTON
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: const Color(0xFF14B8A6).withOpacity(0.3), blurRadius: 20, spreadRadius: 2),
            ],
          ),
          child: FilledButton.icon(
            onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SetupScreen())),
            icon: const Icon(Icons.settings_rounded),
            label: const Text(
  'OPEN SETUP', 
  style: TextStyle(
    fontSize: 20, // Buraya 16 ekleyebilirsin
    fontWeight: FontWeight.w900, 
    letterSpacing: 1.5
  )
  ),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF14B8A6),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 20),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
          ),
        ),
      ),
    ],
  ),
),

	  ],
	  ),
	  ),
    );
  }
void _showLargeQr(BuildContext context, String qrData) {
  showDialog(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: const Color(0xFF0F172A), // Koyu arka plan
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: const BorderSide(color: Color(0xFF334155), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Locator QR',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: QrImageView(
                data: qrData,
                version: QrVersions.auto,
                size: 260,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Scan this code on requester device',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'CLOSE',
                style: TextStyle(
                  color: Color(0xFF14B8A6),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}  
  
}
