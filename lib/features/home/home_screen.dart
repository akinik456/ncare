import 'dart:async';
import 'dart:convert';

import 'package:battery_plus/battery_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/alert_engine.dart';
import '../../core/device_state_manager.dart';
import '../../core/identity_manager.dart';
import '../../core/location_helper.dart';
import '../../core/locator_settings_reader.dart';
import '../setup/setup_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const String _pairCodeAlphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

  String? locatorId;
  String? locatorName;
  String? requesterName;
  String? displayname;
  String? pairCode;

  Timer? _presenceTimer;
  Timer? _batteryTimer;
  final Battery _battery = Battery();
  int? _lastBatteryLevel;

  @override
  void initState() {
    super.initState();

    _updatePresence();

    _presenceTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _updatePresence(),
    );
    _initLocatorId();
    _startBatteryMonitor();
  }

  @override
  void dispose() {
    _presenceTimer?.cancel();
    _batteryTimer?.cancel();
    super.dispose();
  }

  Future<void> _initLocatorId() async {
    final id = await IdentityManager.getRequesterId();
    final generatedCode = _generatePairCode(id);

    if (!mounted) return;

    setState(() {
      locatorId = id;
      pairCode = generatedCode;
    });

    await _syncPairCode(id, generatedCode);
    _checkPairing();
  }

  Future<void> _loadRequesterName() async {
    final locatorId = await IdentityManager.getRequesterId();

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
    final locatorId = await IdentityManager.getRequesterId();
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

    final locatorId = await IdentityManager.getRequesterId();

    final locatorDoc = await FirebaseFirestore.instance
        .collection('locators')
        .doc(locatorId)
        .get();

    final requesterId = settings.pairedRequesterId;
    locatorDoc.data()?['pairedRequesterId'];

    if (requesterId == null || requesterId.isEmpty) return;

    await FirebaseFirestore.instance
        .collection('requesters')
        .doc(requesterId)
        .collection('alerts')
        .add({
      'type': 'call_me',
      'locatorId': locatorId,
      'locatorName': locatorName,
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

  Future<void> _startBatteryMonitor() async {
    _batteryTimer?.cancel();

    _batteryTimer = Timer.periodic(const Duration(minutes: 1), (timer) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final batterysent = prefs.getBool('batteryAlertSent') ?? false;

        final level = await _battery.batteryLevel;
        _lastBatteryLevel = level;

        final locatorId = await IdentityManager.getRequesterId();

        final locatorDoc = await FirebaseFirestore.instance
            .collection('locators')
            .doc(locatorId)
            .get();

        final locatorName = (locatorDoc.data()?['name'] ?? 'Locator').toString();

        final requesterId =
            (locatorDoc.data()?['pairedRequesterId'] ?? '').toString().trim();

        if (requesterId.isEmpty) return;

        final settingsDoc = await FirebaseFirestore.instance
            .collection('requesters')
            .doc(requesterId)
            .collection('locators')
            .doc(locatorId)
            .get();

        final threshold =
            (settingsDoc.data()?['batteryAlertThreshold'] ?? 20) as int;

        final batteryAlarmEnabled =
            (settingsDoc.data()?['batteryAlarmEnabled'] ?? false) == true;

        if (level <= threshold && batteryAlarmEnabled && !batterysent) {
          final allowed = await AlertEngine.shouldSend(
            requesterId: requesterId,
            locatorId: locatorId,
            alertType: 'battery_low',
          );

          if (!allowed) return;

          await AlertEngine.send(
            requesterId: requesterId,
            locatorId: locatorId,
            locatorName: locatorName,
            alertType: 'battery_low',
			extra: {
				'battery': level,
			},
          );

          await prefs.setBool('batteryAlertSent', true);
        }

        if (level > threshold && batterysent) {
          await AlertEngine.clear(
            requesterId: requesterId,
            locatorId: locatorId,
            alertType: 'battery_low',
          );

          await prefs.setBool('batteryAlertSent', false);
        }
      } catch (e) {
        print('BATTERY MONITOR ERROR => $e');
      }
    });
  }

  Future<void> _updatePresence() async {
    final locatorId = await IdentityManager.getRequesterId();
    final currentPairCode = _generatePairCode(locatorId);

    if (pairCode != currentPairCode && mounted) {
      setState(() {
        pairCode = currentPairCode;
      });
    }

    final level = await _battery.batteryLevel;
    final gpsOn = await Geolocator.isLocationServiceEnabled();
    final pos = await LocationService.getCurrentLocationSafe(
      accuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 20),
    );
    if (pos == null) return;

    await FirebaseFirestore.instance.collection('locators').doc(locatorId).set({
      'lastSeen': FieldValue.serverTimestamp(),
      'battery': level,
      'gpsEnabled': gpsOn,
      'lat': pos.latitude,
      'lng': pos.longitude,
      'acc': pos.accuracy,
      'pairCode': currentPairCode,
    }, SetOptions(merge: true));

    print('PRESENCE => battery=$level gps=$gpsOn pairCode=$currentPairCode');
  }

  String _generatePairCode(String locatorId) {
    int hash = 17;
    for (final unit in locatorId.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }

    const base = _pairCodeAlphabet;
    final buffer = StringBuffer();
    int value = hash;

    for (int i = 0; i < 6; i++) {
      buffer.write(base[value % base.length]);
      value = value ~/ base.length;
    }

    return buffer.toString();
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
      final docRef = FirebaseFirestore.instance.collection('locators').doc(locatorId);
      final snap = await docRef.get();
      final data = snap.data();
      if (data == null) return;

      final pendingRequesterId =
          (data['pendingPairRequesterId'] ?? '').toString().trim();
      final pendingRequesterName =
          (data['pendingPairRequesterName'] ?? '').toString().trim();

      if (pendingRequesterId.isEmpty) return;

      await docRef.set({
        'pairedRequesterId': pendingRequesterId,
        'pairedRequesterName': pendingRequesterName,
        'pendingPairRequesterId': FieldValue.delete(),
        'pendingPairRequesterName': FieldValue.delete(),
        'pendingPairCreatedAt': FieldValue.delete(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pairing approved'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      print('APPROVE PENDING PAIR ERROR => $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to approve pairing'),
          duration: Duration(seconds: 2),
        ),
      );
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

  Widget _buildPairCodeCard(ThemeData theme, String code) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
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
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.password_rounded,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Remote Pairing Code',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Requester can pair with this 6-character code.',
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: SelectableText(
              code,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium?.copyWith(
                color: const Color(0xFF0F172A),
                fontWeight: FontWeight.w900,
                letterSpacing: 8,
              ),
            ),
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
    final currentPairCode = pairCode ?? _generatePairCode(locatorId!);

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
        title: const Text(
          'Locator',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
      ),
      body: SafeArea(
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
                                          ready
                                              ? 'Locator Device Ready'
                                              : 'Locator Needs Attention',
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
                                    ready
                                        ? 'This device is ready to receive location requests.'
                                        : 'GPS or permissions missing.',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: Colors.white.withValues(alpha: 0.94),
                                      height: 1.45,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  SelectableText(
                                    locatorId!,
                                    style: theme.textTheme.bodySmall?.copyWith(
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
                                                child: Column(
                                                  children: [
                                                    const Text(
                                                      'Remote Pairing Code',
                                                      style: TextStyle(
                                                        color: Color(0xFF475569),
                                                        fontWeight: FontWeight.w700,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    SelectableText(
                                                      currentPairCode,
                                                      style: const TextStyle(
                                                        color: Color(0xFF0F172A),
                                                        fontSize: 28,
                                                        fontWeight: FontWeight.w900,
                                                        letterSpacing: 8,
                                                      ),
                                                    ),
                                                  ],
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
                      _buildPairCodeCard(theme, currentPairCode),
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
                                        paired
                                            ? 'Paired with $requesterName'
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
                              FilledButton.icon(
                                onPressed: paired ? _sendCallMeAlert : null,
                                icon: const Icon(Icons.call),
                                label: Text(
                                  paired
                                      ? 'Ask $requesterName to call'
                                      : 'Ask requester to call',
                                ),
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
    );
  }
}
