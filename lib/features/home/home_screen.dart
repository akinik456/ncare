import 'dart:async';
import 'dart:convert';

import 'package:battery_plus/battery_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../../core/alert_engine.dart';
import '../../core/device_state_manager.dart';
import '../../core/identity_manager.dart';
import '../../core/locator_settings_reader.dart';
import '../../core/utils.dart';
import '../setup/setup_screen.dart';

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

  @override
  void initState() {
    super.initState();

    _initLocatorId();
	_loadLocatorName();
    _startBatteryMonitor();
  }

  @override
  void dispose() {
    _batteryTimer?.cancel();
    super.dispose();
  }

  Future<void> _initLocatorId() async {
    final id = await IdentityManager.getOrCreateDeviceId();
	await FirebaseMessaging.instance.subscribeToTopic("locator_$id");
	print('_initLocatorId  FCM OK => $id');
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
    final locatorId = await IdentityManager.getOrCreateDeviceId();
    final doc = await FirebaseFirestore.instance
        .collection('locators')
        .doc(locatorId)
        .get();
    if (!mounted) return;
    setState(() {
      locatorName = doc.data()?['name'] ?? 'Locator';
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

Future<void> _sendCallMeAlert() async {
  print("callme called");

  final settings = await LocatorSettingsReader.load();
  if (settings == null) return;

  if (!settings.callEnabled) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Call request is disabled for this locator'),
        duration: Duration(seconds: 2),
      ),
    );
    return;
  }

  print("settings.callEnabled:${settings.callEnabled}");

  final locatorId = await IdentityManager.getOrCreateDeviceId();
  print("locatorId:$locatorId");

  final locatorDoc = await FirebaseFirestore.instance
      .collection('locators')
      .doc(locatorId)
      .get();

  final locatorName = (locatorDoc.data()?['name'] ?? 'Locator').toString();
  final groupId =
      (locatorDoc.data()?['groupId'] ?? '').toString().trim();

  if (groupId.isEmpty) return;

  print("groupId:$groupId");

  await FirebaseFirestore.instance
      .collection('groups')
      .doc(groupId)
      .collection('locators')
      .doc(locatorId)
      .collection('alerts')
      .add({
    'type': 'call_me',
    'groupId': groupId,
    'locatorId': locatorId,
    'locatorName': locatorName,
    'targetMode': 'all',
    'ts': FieldValue.serverTimestamp(),
  });

  if (!mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Call request sent'),
      duration: Duration(seconds: 2),
    ),
  );
}

Future<void> _sendCallMeSingle(
  String requesterId,
  String requesterName,
) async {
  final locatorId = await IdentityManager.getOrCreateDeviceId();

  final locatorDoc = await FirebaseFirestore.instance
      .collection('locators')
      .doc(locatorId)
      .get();
  final locatorName = (locatorDoc.data()?['name'] ?? 'Locator').toString();

  final groupId =
      (locatorDoc.data()?['groupId'] ?? '').toString().trim();
  if (groupId.isEmpty) return;

  await FirebaseFirestore.instance
      .collection('groups')
      .doc(groupId)
      .collection('locators')
      .doc(locatorId)
      .collection('alerts')
      .add({
    'type': 'call_me',
    'groupId': groupId,
    'locatorId': locatorId,
    'locatorName': locatorName,
    'targetMode': 'single',
    'requesterDeviceId': requesterId,
    'requesterName': requesterName,
    'ts': FieldValue.serverTimestamp(),
  });

  if (!mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Call request sent to $requesterName'),
      duration: const Duration(seconds: 2),
    ),
  );
}

Future<void> _sendCallMeAll() async {
  final locatorId = await IdentityManager.getOrCreateDeviceId();

  final locatorDoc = await FirebaseFirestore.instance
      .collection('locators')
      .doc(locatorId)
      .get();
  final locatorName = (locatorDoc.data()?['name'] ?? 'Locator').toString();

  final groupId =
      (locatorDoc.data()?['groupId'] ?? '').toString().trim();
  if (groupId.isEmpty) return;

  await FirebaseFirestore.instance
      .collection('groups')
      .doc(groupId)
      .collection('locators')
      .doc(locatorId)
      .collection('alerts')
      .add({
    'type': 'call_me',
    'groupId': groupId,
    'locatorId': locatorId,
    'locatorName': locatorName,
    'targetMode': 'all',
    'ts': FieldValue.serverTimestamp(),
  });

  if (!mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Call request sent to everybody'),
      duration: Duration(seconds: 2),
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


  } catch (e) {
    print('APPROVE PENDING PAIR ERROR => $e');
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
      'type': 'ncare_locator',
      'locatorId': locatorId,
      'locatorName': locatorName ?? 'Locator',
    });

return Scaffold(
  backgroundColor: const Color(0xFFF1F5F9),
  appBar: AppBar(
    backgroundColor: const Color(0xFFF1F5F9),
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    centerTitle: true,
    title: const Text(
      'LYNRA Care',
      style: TextStyle(
        fontWeight: FontWeight.w800,
        color: Color(0xFF0F172A),
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

        const SizedBox(height: 6),

        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
child: StreamBuilder<bool>(
  initialData: DeviceStateManager.instance.isReady,
  stream: DeviceStateManager.instance.readyStream,
  builder: (context, snapshot) {
    
    final ready = snapshot.data ?? false;
	
	final gpsEnabled = DeviceStateManager.instance.gpsEnabled;
final hasLocationPermission =
    DeviceStateManager.instance.hasLocationPermission;
final hasBackgroundLocationPermission =
    DeviceStateManager.instance.hasBackgroundLocationPermission;

    final statusTitle = ready
        ? 'Locator Device Ready'
        : !hasBackgroundLocationPermission
            ? 'Background Location Required'
            : !gpsEnabled
                ? 'Location Service Off'
                : 'Location Permission Required';

    final statusMessage = ready
        ? 'This device is ready to receive location requests.'
        : !hasBackgroundLocationPermission
            ? 'Set location access to "Allow all the time" in system settings.'
            : !gpsEnabled
                ? 'Turn on location services to keep this locator ready.'
                : 'Grant location permission to continue.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
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
                color: ready
                    ? const Color(0x220F766E)
                    : const Color(0x22B45309),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            ready
                                ? Icons.verified_rounded
                                : Icons.warning_amber_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            statusTitle,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      statusMessage,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.94),
                        height: 1.45,
                      ),
                    ),

                    const SizedBox(height: 8),

                    const Text(
                      'Remote Pairing Code',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SelectableText(
                      currentPairCode,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 8,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      locatorId!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Column(
                children: [
                  GestureDetector(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (_) => Dialog(
                          backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'Locator QR',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                QrImageView(
                                  data: qrData,
                                  version: QrVersions.auto,
                                  size: 260,
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Scan this code on requester device',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Color(0xFF475569),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: QrImageView(
                        data: qrData,
                        version: QrVersions.auto,
                        size: 120,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 120,
                    child: Text(
                      'Tap to enlarge',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.95),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
					  
                      const SizedBox(height: 14),
                      const SizedBox(height: 14),
                      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('locators')
                            .doc(locatorId)
                            .snapshots(),
                        builder: (context, snapshot) {
                          final data = snapshot.data?.data();
                          final requesterName =
                              (data?['pairedRequesterName'] ?? '').toString().trim();

                          final paired = requesterName.isNotEmpty;
						  
						  final pairedRequesters =
    data?['pairedRequesters'] as Map<String, dynamic>?;

final pairedNames = pairedRequesters == null
    ? <String>[]
    : pairedRequesters.values
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((e) => e['active'] == true)
        .map((e) => (e['name'] ?? 'Requester').toString())
        .toList();
						  
                          final hasPendingPair =
                              (data?['pendingPairRequesterId'] ?? '')
                                  .toString()
                                  .trim()
                                  .isNotEmpty;

                          return Column(
                            children: [
                              if (hasPendingPair) ...[
                                _buildPendingPairCard(theme, data),
                                const SizedBox(height: 12),
                              ],
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      paired
                                          ? Icons.check_circle_rounded
                                          : Icons.link_off_rounded,
                                      color: paired
                                          ? const Color(0xFF16A34A)
                                          : const Color(0xFFDC2626),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
  child: Text(
    pairedNames.isNotEmpty
        ? 'Paired with ${pairedNames.join(', ')}'
        : 'Not paired yet',
    style: Theme.of(context)
        .textTheme
        .bodyMedium
        ?.copyWith(
          fontWeight: FontWeight.w700,
          color: const Color(0xFF0F172A),
        ),
  ),
),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
  stream: FirebaseFirestore.instance
      .collection('locators')
      .doc(locatorId)
      .snapshots(),
  builder: (context, snapshot) {
    final data = snapshot.data?.data();
    final paired = data?['pairedRequesters']
        as Map<String, dynamic>?;

    if (paired == null) return const SizedBox();

    final activeRequesters = paired.entries
        .where((e) => e.value['active'] == true)
        .toList();

    if (activeRequesters.isEmpty) {
      return const SizedBox();
    }

    return Column(
      children: [
        ...activeRequesters.map((e) {
          final requesterId = e.key;
          final name =
              (e.value['name'] ?? 'Requester').toString();

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: FilledButton.icon(
              onPressed: () =>
                  _sendCallMeSingle(requesterId, name),
              icon: const Icon(Icons.call),
              label: Text('Ask $name to call me'),
            ),
          );
        }),

        if (activeRequesters.length > 1)
          FilledButton.icon(
            onPressed: _sendCallMeAll,
            icon: const Icon(Icons.campaign),
            label: const Text('Ask everyone to call me'),
          ),
      ],
    );
  },
),
							  
                            ],
                          );
                        },
                      ),
					  
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
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
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF0F172A),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
			  
            ),
          ),
        ),
      ),
	  ],
	  ),
	  ),
    );
  }
}
