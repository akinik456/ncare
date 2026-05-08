import 'dart:async';
import 'dart:convert';

import 'package:battery_plus/battery_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  int _displayInterval = 30;
  
 
@override
void initState() {
  super.initState();
  _initEverything().then((_) {
  print("ZINK home SUCCESS -> groupId:$groupId, locatorId:$locatorId");
  
  // 1. AYARLARI DİNLE (BAĞIMSIZ): 
  // Periyot değişiminden bağımsız, uygulama açılır açılmaz ayarları çekmeye başla.
  print("ZINK home groupId:$groupId,locatorId:$locatorId");
  if (groupId != null && locatorId != null) {
    DeviceStateManager.initSettingsListener(groupId!, locatorId!);
  }
  }).catchError((e) {
    print("ZINK ERROR: _initEverything patladı -> $e");
  });
  DeviceStateManager.onIntervalChanged = (newVal) {
    if (mounted) {
      setState(() {
        _displayInterval = newVal;
      });
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
    
	print("ZINK _initEverything groupId:$groupId,locatorId:$locatorId");
	
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

  void _showLocatorQrDialog(String qrData, String currentPairCode) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Pair this locator',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Scan this code on requester device',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: QrImageView(
                  data: qrData,
                  version: QrVersions.auto,
                  size: 250,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Remote Pairing Code',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      currentPairCode,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 6,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: locatorId ?? ''));
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Copy locator ID'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0F172A),
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _friendlyMovementText() {
    if (_movementStatus.contains('Aktif')) {
      return 'Moving';
    }
    return 'Stationary';
  }

  Color _movementColor() {
    if (_movementStatus.contains('Aktif')) {
      return const Color(0xFF0D9488);
    }
    return const Color(0xFF64748B);
  }

  @override
  Widget build(BuildContext context) {
    if (locatorId == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final currentPairCode = pairCode ?? AppUtils.generatePairCode(locatorId!);
    final qrData = jsonEncode({
      'type': 'Lynracare_locator',
      'locatorId': locatorId,
      'locatorName': locatorName ?? 'Locator',
    });

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF1F5F9),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 20,
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFE0F2FE),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.shield_rounded,
                color: Color(0xFF0369A1),
                size: 21,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'LynraCare',
                    style: TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.2,
                    ),
                  ),
                  Text(
                    locatorName ?? 'Locator device',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => _showLocatorQrDialog(qrData, currentPairCode),
            icon: const Icon(Icons.qr_code_2_rounded),
            color: const Color(0xFF0F172A),
            tooltip: 'Pairing QR',
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SetupScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.settings_rounded),
              color: const Color(0xFF0F172A),
              tooltip: 'Setup',
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<bool>(
          stream: DeviceStateManager.instance.readyStream,
          initialData: DeviceStateManager.instance.isReady,
          builder: (context, readySnapshot) {
            final ready = readySnapshot.data ?? false;
            final gpsEn = DeviceStateManager.instance.gpsEnabled;
            final hasBgLoc = DeviceStateManager.instance.hasBackgroundLocationPermission;
            final hasActivity = DeviceStateManager.instance.hasActivityPermission;
            final batteryOptimized = DeviceStateManager.instance.isBatteryOptimized;

            String statusTitle;
            String statusMessage;
            IconData statusIcon;
            Color statusColor;

            if (ready) {
              statusTitle = 'Protected device ready';
              statusMessage = 'This locator is active and ready to share live state with approved requesters.';
              statusIcon = Icons.verified_rounded;
              statusColor = const Color(0xFF0F766E);
            } else if (!gpsEn) {
              statusTitle = 'Location service off';
              statusMessage = 'Turn on GPS / Location services in system settings.';
              statusIcon = Icons.location_off_rounded;
              statusColor = const Color(0xFFD97706);
            } else if (!hasBgLoc) {
              statusTitle = 'Background location required';
              statusMessage = 'Set location access to “Allow all the time” to work in background.';
              statusIcon = Icons.lock_clock_rounded;
              statusColor = const Color(0xFFD97706);
            } else if (!hasActivity) {
              statusTitle = 'Activity access required';
              statusMessage = 'Physical activity permission is needed for smart tracking.';
              statusIcon = Icons.directions_walk_rounded;
              statusColor = const Color(0xFFD97706);
            } else if (batteryOptimized) {
              statusTitle = 'Battery optimization active';
              statusMessage = 'Set battery to “Unrestricted” to prevent tracking gaps.';
              statusIcon = Icons.battery_alert_rounded;
              statusColor = const Color(0xFFD97706);
            } else {
              statusTitle = 'Permissions required';
              statusMessage = 'Grant necessary permissions to continue tracking.';
              statusIcon = Icons.warning_amber_rounded;
              statusColor = const Color(0xFFD97706);
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                _LocatorHeroCard(
                  ready: ready,
                  statusTitle: statusTitle,
                  statusMessage: statusMessage,
                  statusIcon: statusIcon,
                  statusColor: statusColor,
                  batteryLevel: _lastBatteryLevel,
                  gpsEnabled: gpsEn,
                  backgroundLocationOk: hasBgLoc,
                  activityOk: hasActivity,
                  batteryOptimized: batteryOptimized,
                  interval: _displayInterval,
                  movementText: _friendlyMovementText(),
                  movementColor: _movementColor(),
                  steps: _displaySteps,
                ),
                const SizedBox(height: 14),
                _WatchersCard(
                  isBeingWatched: _isBeingWatched,
                  watcherName: _watcherName,
                ),
                const SizedBox(height: 14),
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('locators')
                      .doc(locatorId)
                      .snapshots(),
                  builder: (context, snapshot) {
                    final data = snapshot.data?.data();
                    final hasPendingPair =
                        (data?['pendingPairRequesterId'] ?? '')
                            .toString()
                            .trim()
                            .isNotEmpty;

                    final pairedRequesters =
                        data?['pairedRequesters'] as Map<String, dynamic>?;

                    final activeRequesters = pairedRequesters == null
                        ? <MapEntry<String, dynamic>>[]
                        : pairedRequesters.entries
                            .where((e) => e.value is Map && e.value['active'] == true)
                            .toList();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (hasPendingPair) ...[
                          _buildPendingPairCard(Theme.of(context), data),
                          const SizedBox(height: 14),
                        ],
                        _PairedRequestersCard(
                          activeRequesters: activeRequesters,
                          onCallOne: (requesterId, name) {
                            _sendCallMeRequest(
                              requesterId: requesterId,
                              requesterName: name,
                            );
                          },
                          onCallAll: activeRequesters.length > 1
                              ? () => _sendCallMeRequest()
                              : null,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),
                _PairingCompactCard(
                  pairCode: currentPairCode,
                  onShowQr: () => _showLocatorQrDialog(qrData, currentPairCode),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SetupScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.settings_rounded),
                    label: const Text('Open setup'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0F172A),
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LocatorHeroCard extends StatelessWidget {
  final bool ready;
  final String statusTitle;
  final String statusMessage;
  final IconData statusIcon;
  final Color statusColor;
  final int? batteryLevel;
  final bool gpsEnabled;
  final bool backgroundLocationOk;
  final bool hasActivityPermission;
  final bool batteryOptimized;
  final int interval;
  final String movementText;
  final Color movementColor;
  final int steps;

  const _LocatorHeroCard({
    required this.ready,
    required this.statusTitle,
    required this.statusMessage,
    required this.statusIcon,
    required this.statusColor,
    required this.batteryLevel,
    required this.gpsEnabled,
    required bool activityOk,
    required this.backgroundLocationOk,
    required this.batteryOptimized,
    required this.interval,
    required this.movementText,
    required this.movementColor,
    required this.steps,
  }) : hasActivityPermission = activityOk;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: ready
              ? const [
                  Color(0xFF0F766E),
                  Color(0xFF0D9488),
                  Color(0xFF14B8A6),
                ]
              : const [
                  Color(0xFFB45309),
                  Color(0xFFD97706),
                  Color(0xFFF59E0B),
                ],
        ),
        boxShadow: [
          BoxShadow(
            color: ready ? const Color(0x260F766E) : const Color(0x26B45309),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  statusIcon,
                  color: Colors.white,
                  size: 25,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          ready ? 'ONLINE • PROTECTED' : 'ACTION NEEDED',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.92),
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      statusTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            statusMessage,
            style: TextStyle(
              color: Colors.white.withOpacity(0.94),
              height: 1.38,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 2.45,
            children: [
              _HeroMetric(
                icon: Icons.battery_full_rounded,
                label: 'Battery',
                value: batteryLevel == null ? '--' : '$batteryLevel%',
              ),
              _HeroMetric(
                icon: gpsEnabled ? Icons.gps_fixed_rounded : Icons.gps_off_rounded,
                label: 'GPS',
                value: gpsEnabled ? 'On' : 'Off',
              ),
              _HeroMetric(
                icon: Icons.speed_rounded,
                label: 'Interval',
                value: '${interval}s',
              ),
              _HeroMetric(
                icon: Icons.directions_walk_rounded,
                label: movementText,
                value: '$steps steps',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusPill(
                text: backgroundLocationOk ? 'Background OK' : 'Background needed',
                good: backgroundLocationOk,
              ),
              _StatusPill(
                text: hasActivityPermission ? 'Activity OK' : 'Activity needed',
                good: hasActivityPermission,
              ),
              _StatusPill(
                text: batteryOptimized ? 'Battery restricted' : 'Battery unrestricted',
                good: !batteryOptimized,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _HeroMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.16),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.14)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 19),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.78),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String text;
  final bool good;

  const _StatusPill({
    required this.text,
    required this.good,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            good ? Icons.check_circle_rounded : Icons.error_rounded,
            color: Colors.white,
            size: 14,
          ),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _WatchersCard extends StatelessWidget {
  final bool isBeingWatched;
  final String watcherName;

  const _WatchersCard({
    required this.isBeingWatched,
    required this.watcherName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x100F172A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isBeingWatched
                  ? const Color(0xFFDCFCE7)
                  : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              isBeingWatched ? Icons.visibility_rounded : Icons.visibility_off_rounded,
              color: isBeingWatched
                  ? const Color(0xFF16A34A)
                  : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isBeingWatched ? 'Currently viewed by' : 'No active viewers',
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isBeingWatched
                      ? (watcherName.isEmpty ? 'Approved requester' : watcherName)
                      : 'Your location is not being actively viewed right now.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PairedRequestersCard extends StatelessWidget {
  final List<MapEntry<String, dynamic>> activeRequesters;
  final void Function(String requesterId, String name) onCallOne;
  final VoidCallback? onCallAll;

  const _PairedRequestersCard({
    required this.activeRequesters,
    required this.onCallOne,
    required this.onCallAll,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x100F172A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E7FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.people_alt_rounded,
                  color: Color(0xFF4338CA),
                  size: 21,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Approved requesters',
                      style: TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'People allowed to view this locator',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (activeRequesters.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Text(
                'Not paired yet',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else ...[
            ...activeRequesters.map((e) {
              final requesterId = e.key;
              final value = Map<String, dynamic>.from(e.value as Map);
              final name = (value['name'] ?? 'Requester').toString();

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _RequesterCallRow(
                  name: name,
                  onPressed: () => onCallOne(requesterId, name),
                ),
              );
            }),
            if (onCallAll != null) ...[
              const SizedBox(height: 2),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onCallAll,
                  icon: const Icon(Icons.campaign_rounded),
                  label: const Text('Ask everyone to call me'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _RequesterCallRow extends StatelessWidget {
  final String name;
  final VoidCallback onPressed;

  const _RequesterCallRow({
    required this.name,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: const Color(0xFFDBEAFE),
            child: Text(
              name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
              style: const TextStyle(
                color: Color(0xFF1D4ED8),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: onPressed,
            icon: const Icon(Icons.call_rounded, size: 17),
            label: const Text('Call me'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PairingCompactCard extends StatelessWidget {
  final String pairCode;
  final VoidCallback onShowQr;

  const _PairingCompactCard({
    required this.pairCode,
    required this.onShowQr,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(
              Icons.qr_code_2_rounded,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pairing code',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  pairCode,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: onShowQr,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF0F172A),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text('QR'),
          ),
        ],
      ),
    );
  }
}
