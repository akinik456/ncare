import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/identity_manager.dart';
import '../../core/notification_service.dart';
import '../../core/location_helper.dart';
import '../setup/setup_screen.dart';
import 'add_locator_screen.dart';
import 'pairing_options_screen.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class RequesterScreen extends StatefulWidget {
  const RequesterScreen({super.key});

  @override
  State<RequesterScreen> createState() => _RequesterScreenState();
}

class _RequesterScreenState extends State<RequesterScreen> with SingleTickerProviderStateMixin{
  String? _lastRequestId; // ekranda gösterilen son başarılı cevap
  String? _pendingRequestId; // şu an beklenen yeni request
  String? _lastAddress;
  String? _lastAddressKey;
  String? requesterId;
  String? _groupId;
  String? _selectedLocatorId;
  bool _timeout = false;
  String? _callRequestFrom;
  String? _lastAlertId;
  String? _activeCallAlertId;
  String? _callRequestLocatorId;
  bool requestAlertsEnabled=true;
  bool deviceWarningsEnabled=true;
  Timer? _presenceUiTimer;
  late AnimationController _pulseController;
  late Animation<double> _pulse;
  double? _myLat;
  double? _myLng;
  Timer? _reqLocationTimer;
  String? _requesterDeviceId;
  StreamSubscription? _callAlertSub;

  @override
  void initState() {
    super.initState();
	NotificationService.suppressForegroundAlerts = true;
    _initRequesterId();	
	_loadAlertSettings();
	_presenceUiTimer = Timer.periodic(
  const Duration(seconds: 15),
  (_) {
    if (mounted) setState(() {});
  },
);
  _reqLocationTimer = Timer.periodic(
  const Duration(seconds: 15),
  (_) => _getMyLocation(),
  );
	_pulseController = AnimationController(
  vsync: this,
  duration: const Duration(seconds: 1),
)..repeat(reverse: true);
_pulse = Tween<double>(begin: 0.8, end: 2).animate(_pulseController);

  //_getMyLocation();
  _initBatteryDefaults();
	
  }
  
Future<void> _getMyLocation() async {

  LocationPermission permission = await Geolocator.checkPermission();

  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }

  if (permission == LocationPermission.deniedForever) {
    return;
  }

  final pos = await LocationService.getCurrentLocationSafe(
  accuracy: LocationAccuracy.high,
  timeLimit: const Duration(seconds: 20),
);
		if(pos == null) return;
  
  setState(() {
    _myLat = pos.latitude;
    _myLng = pos.longitude;
  });
print('myLat $_myLat , myLng $_myLng');
}
  Future<void> _initRequesterId() async {
    final id = await IdentityManager.getOrCreateDeviceId();
	final deviceId=await
	IdentityManager.getOrCreateDeviceId();
	 
    await FirebaseMessaging.instance.subscribeToTopic(id);
    if (!mounted) return;

    setState(() {
      requesterId = id;
	  _requesterDeviceId=deviceId;
    });
    
	_loadGroupId();
  }
  Future<void> _loadGroupId() async {
  final prefs = await SharedPreferences.getInstance();
  final gid = prefs.getString('groupId');

  setState(() {
  _groupId=gid;  
  });
  _listenCallAlerts();
}

String shortCode(String id) {
  final clean = id.replaceAll('-', '').toUpperCase();
  return "${clean.substring(0,4)}-${clean.substring(4,8)}";
}
  


Future<void> _loadAlertSettings() async {
  final prefs = await SharedPreferences.getInstance();

  setState(() {
    requestAlertsEnabled =
        prefs.getBool('locator_request_alerts') ?? true;

    deviceWarningsEnabled =
        prefs.getBool('locator_device_warnings') ?? true;
  });
}

Future<void> _initBatteryDefaults() async {
  final prefs = await SharedPreferences.getInstance();

  if (!prefs.containsKey('batteryAlertThreshold')) {
    await prefs.setInt('batteryAlertThreshold', 20);
  }
}



Future<void> saveRequestAlerts(bool value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('locator_request_alerts', value);

  setState(() {
    requestAlertsEnabled = value;
  });
}

Future<void> saveDeviceWarnings(bool value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('locator_device_warnings', value);

  setState(() {
    deviceWarningsEnabled = value;
  });
}
  
String formatLastSeen(DateTime? lastSeen) {
  if (lastSeen == null) return "-";

  final diff = DateTime.now().difference(lastSeen);

  if (diff.inSeconds < 60) return "ONLINE";
  if (diff.inMinutes < 60) return "Last seen ${diff.inMinutes}m ago";
  if (diff.inHours < 24) return "Last seen ${diff.inHours}h ago";

  return "Last seen ${diff.inDays}d ago";
}

String formatDistance(double? distance, double acc) {
  if (distance == null) return "-";

  // NEARBY
  if (distance <= acc + 30) {
    return "NEARBY";
  }

  // KM
  if (distance >= 1000) {
    final km = distance / 1000;
    return "${km.toStringAsFixed(1)} km ±${(acc / 1000).toStringAsFixed(2)}";
  }

  // METERS
  return "${distance.round()} m ±${acc.round()}";
}

  
  @override
  void dispose(){
   NotificationService.suppressForegroundAlerts = 
  false;
  _presenceUiTimer?.cancel();
  _pulseController.dispose();
  _reqLocationTimer?.cancel();
   super.dispose();
   _callAlertSub?.cancel();
  }   

Future<void> _sendRequest() async {
  if (_groupId == null || _groupId!.isEmpty) return;
  if (_selectedLocatorId == null || _selectedLocatorId!.isEmpty) return;
  if (requesterId == null || requesterId!.isEmpty) return;
  
  final locatorDoc = await FirebaseFirestore.instance
    .collection('locators')
    .doc(_selectedLocatorId)
    .get();

final paired = locatorDoc.data()?['pairedRequesters']
    as Map<String, dynamic>?;

final entry = paired?[requesterId];

if (entry == null || entry['active'] != true) {
  print("REQ BLOCKED => not paired");
  return;
}

  final requestDeviceId = await IdentityManager.getOrCreateDeviceId();

  final doc = await FirebaseFirestore.instance
      .collection('groups')
      .doc(_groupId)
      .collection('locators')
      .doc(_selectedLocatorId)
      .collection('requests')
      .add({
    'type': 'rl',
    'requesterId': requesterId,
    'requestDeviceId': requestDeviceId,
    'locatorId': _selectedLocatorId,
    'ts': FieldValue.serverTimestamp(),
  });

  setState(() {
    _pendingRequestId = doc.id;
    _timeout = false;
  });

  Future.delayed(const Duration(seconds: 60), () {
    if (!mounted) return;

    if (_pendingRequestId == doc.id) {
      setState(() {
        _timeout = true;
      });
    }
  });
}


  
String lastSeenText(Timestamp ts) {
  final time = ts.toDate();
  final now = DateTime.now();
  final diff = now.difference(time);

  if (diff.inSeconds <= 60) {
    return "Online";
  }

  final y = time.year;
  final m = time.month.toString().padLeft(2, '0');
  final d = time.day.toString().padLeft(2, '0');
  final h = time.hour.toString().padLeft(2, '0');
  final min = time.minute.toString().padLeft(2, '0');

  return "Last seen $y-$m-$d $h:$min";
}    

void _listenCallAlerts() {
  if (_groupId == null || _groupId!.isEmpty) return;

  print("callme Listener Started");

  _callAlertSub?.cancel();

  _callAlertSub = FirebaseFirestore.instance
      .collectionGroup('alerts')
      .where('type', isEqualTo: 'call_me')
      .where('groupId', isEqualTo: _groupId)
      .orderBy('ts', descending: true)
      .snapshots()
      .listen((snapshot) async {
    if (snapshot.docs.isEmpty) return;

    final visibleDocs = snapshot.docs.where((doc) {
      final data = doc.data();

      final targetMode = (data['targetMode'] ?? 'all').toString();
      final targetRequesterDeviceId =
          (data['requesterDeviceId'] ?? '').toString().trim();

      if (targetMode == 'all') {
        return true;
      }

      if (targetMode == 'single') {
        return _requesterDeviceId != null &&
            targetRequesterDeviceId == _requesterDeviceId;
      }

      return false;
    }).toList();

    if (visibleDocs.isEmpty) return;

    final doc = visibleDocs.first;

    if (_lastAlertId == doc.id) return;

    final data = doc.data();
    final locatorId = (data['locatorId'] ?? '').toString();

    String displayName = 'Locator';

    if (locatorId.isNotEmpty) {
      final locatorDoc = await FirebaseFirestore.instance
          .collection('locators')
          .doc(locatorId)
          .get();

      displayName =
          (locatorDoc.data()?['name'] ?? 'Locator').toString().trim();
    }

    if (!mounted) return;

    setState(() {
      _lastAlertId = doc.id;
      _activeCallAlertId = doc.id;
      _callRequestFrom = displayName;
      _callRequestLocatorId = locatorId;
    });
  }, onError: (e) {
    print("CALL_ME LISTENER ERROR => $e");
  });
}




  Future<void> _openInMaps(double lat, double lng) async {
    final uri =
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      // sessiz geç
    }
  }

  Future<void> _resolveAddress(double lat, double lng) async {
    final key = '${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)}';
    if (_lastAddressKey == key && _lastAddress != null) return;

    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isEmpty) return;

      final p = placemarks.first;

      final parts = <String>[
        if ((p.street ?? '').trim().isNotEmpty) p.street!.trim(),
        if ((p.locality ?? '').trim().isNotEmpty) p.locality!.trim(),
        if ((p.administrativeArea ?? '').trim().isNotEmpty)
          p.administrativeArea!.trim(),
      ];

      final addr = parts.where((e) => e.isNotEmpty).join(', ');
      if (addr.isEmpty) return;

      if (!mounted) return;
      setState(() {
        _lastAddressKey = key;
        _lastAddress = addr;
      });
    } catch (_) {
      // sessiz geç
    }
  }
  String lastSeen(Timestamp ts) {
	  final time = ts.toDate();
	  final formatted = DateFormat('d MMM yyyy • HH:mm').format(time);
	  return 'Last seen $formatted';
	}

void _showQrDialog(String groupId) {
  showDialog(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.all(20),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "GROUP QR",
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 16),
            QrImageView(
              data: groupId,
              version: QrVersions.auto,
              size: 240,
            ),
            const SizedBox(height: 12),
            Text(
              shortCode(groupId),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}	

Future<void> _joinGroup() async {
  final result = await Navigator.push<String>(
    context,
    MaterialPageRoute(
      builder: (_) => const _GroupQrScanner(),
    ),
  );

  if (result == null || result.isEmpty) return;

  final requesterId = await IdentityManager.getOrCreateDeviceId();
  
  final requesterDoc = await FirebaseFirestore.instance
		.collection('requesters')
		.doc(requesterId)
		.get();

	final requesterName =
		(requesterDoc.data()?['name'] ?? '').toString();
		
  final now = FieldValue.serverTimestamp();

  await IdentityManager.setLocalGroupId(result);

  await FirebaseFirestore.instance
      .collection('groups')
      .doc(result)
      .collection('devices')
      .doc(requesterId)
      .set({
    'deviceId': requesterId,
    'groupId': result,
    'role': 'requester',
	'name': requesterName,
    'joinedAt': now,
    'active': true,
    'isMaster': false,
  });

  setState(() {
    _groupId = result;
  });
  _listenCallAlerts();
}


	
	
  @override
  Widget build(BuildContext context) {
  final displayId = _groupId ?? requesterId;
  
    if (requesterId == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final theme = Theme.of(context);
    final visibleRequestId = _lastRequestId;
    final pendingRequestId = _pendingRequestId;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFFF1F5F9),
        surfaceTintColor: Colors.transparent,
        titleSpacing: 20,
        title: const Text(
          'NCare',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.tonalIcon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddLocatorScreen()),
                );
              },
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Add locator'),
              style: FilledButton.styleFrom(
                foregroundColor: const Color(0xFF0F172A),
                backgroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
		padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          children: [
if (_groupId != null)
Container(
  margin: const EdgeInsets.only(bottom: 12),
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: const Color(0xFFE2E8F0)),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        "GROUP",
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: Color(0xFF0F172A),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        shortCode(_groupId!),
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
        ),
      ),
      const SizedBox(height: 12),

  GestureDetector(
  onTap: () => _showQrDialog(_groupId!),      
  child:Container(
        height: 120,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(16),
        ),
        

  child: Center(
    child: QrImageView(
      data: _groupId!,
      version: QrVersions.auto,
      size: 100,
    ),
  ),
),
),
      

      const SizedBox(height: 8),

      TextButton(
        onPressed: () {
          Clipboard.setData(ClipboardData(text: _groupId!));
        },
        child: const Text("COPY"),
      ),
    ],
  ),
),		  
  
		  
		  
		  if (_callRequestFrom != null)
  Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFEF2F2),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFDC2626)),
    ),
    child: Row(
      children: [
        const Icon(Icons.call, color: Color(0xFFDC2626)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '$_callRequestFrom wants you to call',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF7F1D1D),
            ),
          ),
        ),
        TextButton(
onPressed: () async {
  final alertId = _activeCallAlertId;
  final locatorId = _callRequestLocatorId;
  final groupId = _groupId;

  setState(() {
    _callRequestFrom = null;
    _callRequestLocatorId = null;
    _activeCallAlertId = null;
  });

   if (groupId == null || groupId.isEmpty) return;
  if (locatorId == null || locatorId.isEmpty) return;
  if (alertId == null || alertId.isEmpty) return;

  try {
  await FirebaseFirestore.instance
      .collection('groups')
      .doc(groupId)
      .collection('locators')
      .doc(locatorId)
      .collection('alerts')
      .doc(alertId)
      .delete();
} catch (e) {
  print('CALL_ME DISMISS DELETE ERROR => $e');
}
},

          child: const Text('DISMISS'),
        ),
      ],
    ),
  ),
if (_groupId == null || _groupId!.isEmpty) ...[
  const SizedBox(height: 8),
  SizedBox(
    width: double.infinity,
    child: OutlinedButton.icon(
      onPressed: _joinGroup,
      icon: const Icon(Icons.qr_code_scanner),
      label: const Text("Join group"),
    ),
  ),
],		  
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF1D4ED8),
                    Color(0xFF2563EB),
                    Color(0xFF3B82F6),
                  ],
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x221D4ED8),
                    blurRadius: 28,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.travel_explore_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Requester Device',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Request location from the selected locator device.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.92),
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed:
                          _selectedLocatorId == null ? null : _sendRequest,
                      icon: const Icon(Icons.my_location_rounded),
                      label: const Text('Request location'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF1D4ED8),
                        disabledBackgroundColor:
                            Colors.white.withValues(alpha: 0.65),
                        disabledForegroundColor: const Color(0xFF94A3B8),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
  stream: (_groupId == null || _groupId!.isEmpty)
      ? null
      : FirebaseFirestore.instance
          .collection('locators')
          .where('groupId', isEqualTo: _groupId)
          .where('role', isEqualTo: 'locator')
          .where('active', isEqualTo: true)
          .snapshots(),
  builder: (context, snapshot) {
    final allDocs = snapshot.data?.docs ?? [];

    final docs = allDocs.where((doc) {
      final data = doc.data();
      final pairedRequesters =
          data['pairedRequesters'] as Map<String, dynamic>?;

      if (pairedRequesters == null || requesterId == null) {
        return false;
      }

      final entry = pairedRequesters[requesterId];
	  if(entry == null ) return false;
	  
	  return entry['active'] == true ;
    }).toList();

    if (docs.isEmpty) {
	  WidgetsBinding.instance.addPostFrameCallback((_) {
		if (!mounted) return;
		if (_selectedLocatorId != null) {
		  setState(() {
			_selectedLocatorId = null;
		  });
		}
	  });

	  return Text(
		_groupId == null
			? 'Create or join a group first'
			: 'No paired locator',
		style: theme.textTheme.titleMedium?.copyWith(
		  color: Colors.white,
		  fontWeight: FontWeight.w700,
		),
	  );
	}

    final hasSelected =
        docs.any((doc) => doc.id == _selectedLocatorId);

    if (!hasSelected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _selectedLocatorId = docs.first.id;
        });
      });
    }


  return Wrap(
    spacing: 8,
    runSpacing: 8,
    children: docs.map((doc) {
      final deviceData = doc.data();
      final locatorId = doc.id;
      final name =
          (deviceData['name'] ?? deviceData['deviceId'] ?? locatorId)
              .toString();

      final selected = locatorId == _selectedLocatorId;

      return GestureDetector(
        onTap: () {
          setState(() {
            _selectedLocatorId = locatorId;
          });
        },
        onLongPress: () async {
          final changed = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PairingOptionsScreen(
                locatorId: locatorId,
                locatorName: name,
              ),
            ),
          );

          if (changed == true && mounted) {
            setState(() {});
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 7,
              ),
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: selected
                      ? const Color(0xFF1D4ED8)
                      : Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 6),
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('locators')
                  .doc(locatorId)
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const SizedBox();
                }

                final data = snap.data!.data() as Map<String, dynamic>?;
                final ts = data?['lastSeen'] as Timestamp?;
                final lastSeen = ts?.toDate();
                final battery = data?['battery'] ?? 0;
                final gpsOn = data?['gpsEnabled'] ?? true;

                final online = lastSeen != null &&
                    DateTime.now().difference(lastSeen).inSeconds < 120;

                final lat = (data?['lat'] as num?)?.toDouble();
                final lng = (data?['lng'] as num?)?.toDouble();
                final acc = (data?['acc'] as num?)?.toDouble() ?? 0;

                double? distance;

                if (_myLat != null &&
                    _myLng != null &&
                    lat != null &&
                    lng != null) {
                  distance = Geolocator.distanceBetween(
                    _myLat!,
                    _myLng!,
                    lat,
                    lng,
                  );
                }

                return Row(
                  children: [
                    online
                        ? AnimatedBuilder(
                            animation: _pulse,
                            builder: (context, child) {
                              return Transform.scale(
                                scale: _pulse.value,
                                child: child,
                              );
                            },
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                              ),
                            ),
                          )
                        : Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.white70,
                              shape: BoxShape.circle,
                            ),
                          ),
                    const SizedBox(width: 6),
                    Text(
                      online ? "ONLINE" : formatLastSeen(lastSeen),
                      style: TextStyle(
                        color: online ? Colors.green : Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      "🔋$battery%",
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      gpsOn ? "📍GPS" : "⚠️GPS",
                      style: TextStyle(
                        color: gpsOn ? Colors.white70 : Colors.orange,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (distance != null) ...[
                      const SizedBox(width: 12),
                      Text(
                        formatDistance(distance, acc),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      );
    }).toList(),
  );
}

					  
					  
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            if (visibleRequestId == null && pendingRequestId == null)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0E7FF),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(
                        Icons.location_searching_rounded,
                        color: Color(0xFF4338CA),
                        size: 26,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No active request yet',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _selectedLocatorId == null
                          ? 'Add and select a locator first.'
                          : 'Tap request location and wait for locator response.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF64748B),
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

            if (pendingRequestId != null) ...[
              _StatusCard(
                icon: _timeout
                    ? Icons.error_outline
                    : Icons.hourglass_top_rounded,
                iconBg: _timeout
                    ? const Color(0xFFFEF2F2)
                    : const Color(0xFFFFF7ED),
                iconColor: _timeout
                    ? const Color(0xFFDC2626)
                    : const Color(0xFFEA580C),
                title: _timeout
                    ? 'Locator did not respond'
                    : 'Waiting for response',
                subtitle: _timeout
                    ? 'Please try again'
                    : 'Request sent successfully. Waiting for locator device...',
              ),
              const SizedBox(height: 14),
            ],

            if (pendingRequestId != null || visibleRequestId != null)
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('locators')
                    .doc(_selectedLocatorId)
                    .snapshots(),
                builder: (context, locatorSnapshot) {
				  if (locatorSnapshot.connectionState == ConnectionState.waiting) {
					return const SizedBox();
				  }

				  if (locatorSnapshot.hasError) {
					return const SizedBox();
				  }

				  if (!locatorSnapshot.hasData || locatorSnapshot.data == null) {
					return const SizedBox();
				  }

				  final locatorDoc = locatorSnapshot.data!;
				  if (!locatorDoc.exists) {
					return const SizedBox();
				  }

				  final locatorData = locatorDoc.data();
				  if (locatorData == null) {
					return const SizedBox();
				  }

				  final pairedRequesters =
					locatorData['pairedRequesters'] as Map<String, dynamic>?;

				  final isStillPaired =
					pairedRequesters != null && pairedRequesters.containsKey(requesterId);

				  if (!isStillPaired) {
					WidgetsBinding.instance.addPostFrameCallback((_) {
					  if (!mounted) return;
					  setState(() {
						_pendingRequestId = null;
						_lastRequestId = null;
						_timeout = false;
						_lastAddress = null;
						_lastAddressKey = null;
					  });
					});
					return const SizedBox();
				  }
					return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
  stream: FirebaseFirestore.instance
      .collection('groups')
      .doc(_groupId)
      .collection('locators')
      .doc(_selectedLocatorId)
      .collection('responses')
      .doc(pendingRequestId ?? visibleRequestId)
      .snapshots(),
  builder: (context, snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const SizedBox();
    }

    if (snapshot.hasError) {
      return const SizedBox();
    }

    if (!snapshot.hasData || snapshot.data == null) {
      return const SizedBox();
    }

    final responseDoc = snapshot.data!;
    if (!responseDoc.exists) {
      return const SizedBox();
    }

    final data = responseDoc.data();
    if (data == null) {
      return const SizedBox();
    }

    final responseDeviceId =
        (data['requestDeviceId'] ?? '').toString().trim();

    if (_requesterDeviceId != null &&
        responseDeviceId.isNotEmpty &&
        responseDeviceId != _requesterDeviceId) {
      return const SizedBox();
    }

    final status = (data['status'] ?? '').toString();
    final lat = (data['lat'] as num?)?.toDouble();
    final lng = (data['lng'] as num?)?.toDouble();
    final hasFix = (status == 'ok' && lat != null && lng != null);

    if (hasFix && pendingRequestId != null) {
      final currentPending = pendingRequestId!;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;

        setState(() {
          _lastRequestId = currentPending;
          _pendingRequestId = null;
          _timeout = false;
          _lastAddress = null;
          _lastAddressKey = null;
        });
      });
    }

    if (visibleRequestId == null && pendingRequestId != null) {
      return const SizedBox();
    }

    if (visibleRequestId == null && pendingRequestId == null) {
      return const SizedBox();
    }

    final displayDocId = _lastRequestId ?? visibleRequestId;
    if (displayDocId == null) {
      return const SizedBox();
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('groups')
          .doc(_groupId)
          .collection('locators')
          .doc(_selectedLocatorId)
          .collection('responses')
          .doc(displayDocId)
          .snapshots(),
      builder: (context, visibleSnapshot) {
        final visibleData = visibleSnapshot.data?.data();

        if (visibleData == null) {
          return const SizedBox();
        }

        final visibleResponseDeviceId =
            (visibleData['requestDeviceId'] ?? '').toString().trim();

        if (_requesterDeviceId != null &&
            visibleResponseDeviceId.isNotEmpty &&
            visibleResponseDeviceId != _requesterDeviceId) {
          return const SizedBox();
        }

        final status = (visibleData['status'] ?? '').toString();
        final lat = (visibleData['lat'] as num?)?.toDouble();
        final lng = (visibleData['lng'] as num?)?.toDouble();
        final acc = (visibleData['acc'] as num?)?.toDouble();
        final ts = visibleData['ts'] as Timestamp?;
        final battery = (visibleData['battery'] as num?)?.toInt();

        final hasFix = (status == 'ok' && lat != null && lng != null);
        final online =
            ts != null &&
            DateTime.now().difference(ts.toDate()).inSeconds <= 60;

        if (!hasFix) {
          return _StatusCard(
            icon: Icons.sync_problem_rounded,
            iconBg: const Color(0xFFFEF2F2),
            iconColor: const Color(0xFFDC2626),
            title: 'Response received',
            subtitle: 'Status: $status\nWaiting for valid location...',
          );
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _resolveAddress(lat!, lng!);
        });

        return Container(
          padding: const EdgeInsets.all(16),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.location_on_rounded,
                      color: Color(0xFF16A34A),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Location result',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              if (_lastAddress != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.place_rounded,
                          color: Color(0xFF1D4ED8),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _lastAddress!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF0F172A),
                            height: 1.4,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  _MiniInfo(
                    icon: Icons.gps_fixed_rounded,
                    text: acc != null
                        ? 'Accuracy ${acc.toStringAsFixed(0)} m'
                        : 'Accuracy -',
                  ),
                  if (battery != null)
                    _MiniInfo(
                      icon: Icons.battery_full,
                      text: 'Battery $battery%',
                    ),
                  _MiniInfo(
                    icon: Icons.circle,
                    text: online ? 'Online' : lastSeenText(ts!),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _openInMaps(lat, lng),
                  icon: const Icon(Icons.map_rounded),
                  label: const Text('Open in Maps'),
                ),
              ),
            ],
          ),
        );
      },
    );
  },
);


				  
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _MiniInfo extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MiniInfo({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: const Color(0xFF475569)),
          const SizedBox(width: 6),
          Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF475569),
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;

  const _StatusCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: iconColor, size: 28),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0F172A),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF64748B),
              height: 1.45,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
class _GroupQrScanner extends StatefulWidget {
  const _GroupQrScanner();

  @override
  State<_GroupQrScanner> createState() => _GroupQrScannerState();
}

class _GroupQrScannerState extends State<_GroupQrScanner> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Scan group QR")),
      body: MobileScanner(
        onDetect: (capture) {
          if (_handled) return;

          final barcodes = capture.barcodes;
          if (barcodes.isEmpty) return;

          final code = barcodes.first.rawValue;
          if (code == null || code.isEmpty) return;

          _handled = true;
          Navigator.pop(context, code);
        },
      ),
    );
  }
}
