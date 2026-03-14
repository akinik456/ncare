import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:battery_plus/battery_plus.dart';

import '../../core/device_state_manager.dart';
import '../../core/identity_manager.dart';
import '../setup/setup_screen.dart';
import '../../core/locator_settings_reader.dart';
import '../../core/fcm_manager.dart';

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
  Timer?  _presenceTimer;
  Timer?  _batteryTimer;
  final Battery _battery=Battery();
  
  @override
void initState() {
  super.initState();

  _updatePresence(); // ilk anda yaz

  _presenceTimer = Timer.periodic(
    const Duration(seconds: 30),
    (_) => _updatePresence(),
  );
  _initLocatorId();
  _startBatteryMonitor();
}

Future<void> _createBatteryAlert(int level) async {
  try {
    final requesterId = await IdentityManager.getRequesterId();
    final locatorId = await IdentityManager.getRequesterId();

    if (requesterId == null || locatorId == null) return;

    await FirebaseFirestore.instance
        .collection('requesters')
        .doc(requesterId)
        .collection('alerts')
        .add({
      'type': 'battery_low',
      'locatorId': locatorId,
      'locatorName': displayname ?? 'Locator',
      'battery': level,
      'ts': FieldValue.serverTimestamp(),
    });

    print("BATTERY ALERT CREATED => $level%");
  } catch (e) {
    print("BATTERY ALERT ERROR => $e");
  }
}

@override
void dispose() {
  _presenceTimer?.cancel();
  super.dispose();
}

  Future<void> _initLocatorId() async {
    final id = await IdentityManager.getRequesterId();
    if (!mounted) return;

    setState(() {
      locatorId = id;
    });

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

  displayname = requesterName!.isNotEmpty
      ? requesterName
      : "requester";
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
  locatorName = doc.data()?['name'] ??
  "Locator";
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

        try{
		
        print("PAIRED WITH REQUESTER => $requesterId");
        print("SUBSCRIBED => $locatorTopic");
        }catch(e){
		print("SUBSCRIBED ERR => $e");
		}	  
	  } else {
        print("NO PAIR FOUND");
      }
    } catch (e) {
      print("PAIRING ERROR => $e");
    }
  }
  Future<void> _sendCallMeAlert() async {
  final settings = await 
  LocatorSettingsReader.load();
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
      content: Text("Call request sent"),
      duration: Duration(seconds: 2),
    ),
  );
}

Future<void> _startBatteryMonitor() async {
  _batteryTimer?.cancel();

  _batteryTimer = Timer.periodic(const Duration(minutes: 15), (timer) async {
    final prefs = await SharedPreferences.getInstance();

    final enabled = prefs.getBool('batteryAlarmEnabled') ?? false;
    if (!enabled) return;

    final threshold = prefs.getInt('batteryAlertThreshold') ?? 20;

    final level = await _battery.batteryLevel;

    bool sent = prefs.getBool('batteryAlertSent') ?? false;

    if (level <= threshold && !sent) {
      print("BATTERY ALERT TRIGGER $level");

      await _createBatteryAlert(level);

      await prefs.setBool('batteryAlertSent', true);
    }

    if (level > threshold) {
      await prefs.setBool('batteryAlertSent', false);
    }
  });
}


Future<void> _updatePresence() async {
  final locatorId = await IdentityManager.getRequesterId();

  await FirebaseFirestore.instance
      .collection('locators')
      .doc(locatorId)
      .set({
    'lastSeen': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}



  @override
  Widget build(BuildContext context) {
    if (locatorId == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final theme = Theme.of(context);
	
    final qrData = jsonEncode({
      'type': 'ncare_locator',
      'locatorId': locatorId,
	  'locatorName':locatorName ?? "Locator",
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
                                          color: Colors.white.withValues(
                                            alpha: 0.16,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(14),
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
                                      color: Colors.white.withValues(
                                        alpha: 0.94,
                                      ),
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
                                          borderRadius:
                                              BorderRadius.circular(28),
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
                                    style:
                                        theme.textTheme.bodySmall?.copyWith(
                                      color: Colors.white.withValues(
                                        alpha: 0.95,
                                      ),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
					  
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

    return Column(
      children: [

        /// PAIR STATUS
						Container(
						  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
									  ? "Paired with $requesterName"
									  : "Not paired yet",
								  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
										fontWeight: FontWeight.w700,
										color: const Color(0xFF0F172A),
									  ),
								),
							  ),
							],
						  ),
						),
				const SizedBox(height: 12),

						/// CALL BUTTON
						FilledButton.icon(
						  onPressed: paired ? _sendCallMeAlert : null,
						  icon: const Icon(Icons.call),
						  label: Text(
							paired
								? "Ask $requesterName to call"
								: "Ask requester to call",
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
                              padding: const EdgeInsets.symmetric(
                                vertical: 15,
                              ),
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
