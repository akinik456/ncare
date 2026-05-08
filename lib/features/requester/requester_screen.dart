import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/identity_manager.dart';
import '../../core/location_helper.dart';
import '../../core/notification_service.dart';
import '../../services/rtdb.dart';
import 'add_locator_screen.dart';
import 'pairing_options_screen.dart';

class RequesterScreen extends StatefulWidget {
  const RequesterScreen({super.key});

  @override
  State<RequesterScreen> createState() => _RequesterScreenState();
}

class _RequesterScreenState extends State<RequesterScreen>
    with SingleTickerProviderStateMixin {
  String? requesterId;
  String? _groupId;
  String? _requesterDeviceId;

  String? requesterName;
  String? _currentRequesterName;
  String? _cachedMyName;

  bool isMaster = false;
  bool requestAlertsEnabled = true;
  bool deviceWarningsEnabled = true;

  double? _myLat;
  double? _myLng;

  Timer? _presenceUiTimer;
  Timer? _reqLocationTimer;

  late AnimationController _pulseController;
  late Animation<double> _pulse;

  StreamSubscription? _callMeRtdbSub;

  String? _callRequestFrom;
  String? _callRequestTs;
  String? _lastAlertId;
  String? _activeCallAlertId;
  String? _callRequestLocatorId;
  String? targetMode;
  String? targetReqId;

  final Set<String> _watchedLocatorIds = {};

  @override
  void initState() {
    super.initState();

    NotificationService.suppressForegroundAlerts = true;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    _pulse = Tween<double>(begin: 0.8, end: 2).animate(_pulseController);

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

    _initRequesterId();
    _loadMyName();
    _loadAlertSettings();
    _initBatteryDefaults();
    _getMyLocation();
  }

  @override
  void dispose() {
    NotificationService.suppressForegroundAlerts = false;

    _clearWatchingStatus();

    _presenceUiTimer?.cancel();
    _reqLocationTimer?.cancel();
    _callMeRtdbSub?.cancel();
    _pulseController.dispose();

    super.dispose();
  }

  Future<void> _initRequesterId() async {
    final id = await IdentityManager.getOrCreateDeviceId();
    final deviceId = await IdentityManager.getOrCreateDeviceId();

    if (!mounted) return;

    setState(() {
      requesterId = id;
      _requesterDeviceId = deviceId;
    });

    await _loadGroupId();
  }

  Future<void> _loadGroupId() async {
    final prefs = await SharedPreferences.getInstance();
    final gid = prefs.getString('groupId');
    final master = await IdentityManager.getIsMaster();

    if (!mounted) return;

    setState(() {
      _groupId = gid;
      isMaster = master;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initCallMeLiveSync();
    });
  }

  Future<void> _loadMyName() async {
    final name = await IdentityManager.getMyName();

    if (!mounted) return;

    setState(() {
      _cachedMyName = name;
      _currentRequesterName = name;
      requesterName = name;
    });
  }

  Future<void> _loadAlertSettings() async {
    final prefs = await SharedPreferences.getInstance();

    if (!mounted) return;

    setState(() {
      requestAlertsEnabled = prefs.getBool('locator_request_alerts') ?? true;
      deviceWarningsEnabled = prefs.getBool('locator_device_warnings') ?? true;
    });
  }

  Future<void> _initBatteryDefaults() async {
    final prefs = await SharedPreferences.getInstance();

    if (!prefs.containsKey('batteryAlertThreshold')) {
      await prefs.setInt('batteryAlertThreshold', 20);
    }
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

    if (pos == null) return;
    if (!mounted) return;

    setState(() {
      _myLat = pos.latitude;
      _myLng = pos.longitude;
    });
  }

  Future<void> saveRequestAlerts(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('locator_request_alerts', value);

    if (!mounted) return;

    setState(() {
      requestAlertsEnabled = value;
    });
  }

  Future<void> saveDeviceWarnings(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('locator_device_warnings', value);

    if (!mounted) return;

    setState(() {
      deviceWarningsEnabled = value;
    });
  }

  String shortCode(String id) {
    final clean = id.replaceAll('-', '').toUpperCase();
    if (clean.length < 8) return clean;
    return "${clean.substring(0, 4)}-${clean.substring(4, 8)}";
  }

  String formatLastSeen(DateTime? lastSeen) {
    if (lastSeen == null) return "Unknown";

    final diff = DateTime.now().difference(lastSeen);

    if (diff.inSeconds < 60) return "Just now";
    if (diff.inMinutes < 60) return "${diff.inMinutes} min ago";
    if (diff.inHours < 24) return "${diff.inHours} h ago";

    return "${diff.inDays} d ago";
  }

  String formatDistance(double? distance, double acc) {
    if (distance == null) return "--";

    if (distance <= acc + 30) {
      return "NEARBY";
    }

    if (distance >= 1000) {
      final km = distance / 1000;
      return "${km.toStringAsFixed(1)} km";
    }

    return "${distance.round()} m";
  }

  String formatCoordinate(double value) {
    return value.toStringAsFixed(6);
  }

  Future<void> _openInMaps(double lat, double lng) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _copyLocation(double lat, double lng) {
    Clipboard.setData(
      ClipboardData(text: '${formatCoordinate(lat)}, ${formatCoordinate(lng)}'),
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Location copied')),
    );
  }

  void _showQrDialog(String groupId) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
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
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: groupId));
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Copy group code'),
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

    final reqId = await IdentityManager.getOrCreateDeviceId();
    final reqName = _currentRequesterName;
    final now = FieldValue.serverTimestamp();

    await IdentityManager.setLocalGroupId(result);

    await FirebaseFirestore.instance
        .collection('groups')
        .doc(result)
        .collection('devices')
        .doc(reqId)
        .set({
      'deviceId': reqId,
      'groupId': result,
      'role': 'requester',
      'name': reqName,
      'joinedAt': now,
      'active': true,
      'isMaster': false,
    });

    if (!mounted) return;

    setState(() {
      _groupId = result;
    });

    _initCallMeLiveSync();
  }

  void _initCallMeLiveSync() {
    if (_groupId == null || _groupId!.isEmpty) return;

    _callMeRtdbSub?.cancel();

    _callMeRtdbSub =
        RTDBService().getGroupPresenceStream(_groupId!).listen((event) async {
      final data = event.snapshot.value as Map?;
      if (data == null) return;

      String? foundAlertId;
      String? foundLocatorId;
      String? foundDisplayName;
      String? foundTs;

      data.forEach((locId, locData) {
        if (locData is! Map) return;

        final commands = locData['commands'] as Map?;
        final callMe = commands?['call_me'] as Map?;
        final handledBy = callMe?['handledBy']?.toString();

        if (callMe != null && callMe['pending'] == true) {
          targetMode = (callMe['targetMode'] ?? 'all').toString();
          targetReqId = (callMe['requesterId'] ?? '').toString();

          final isTarget =
              (targetMode == 'all' && handledBy == null) ||
              (targetMode == 'single' && targetReqId == _requesterDeviceId);

          if (isTarget) {
            foundAlertId = "rtdb_${locId}_${callMe['ts']}";
            foundLocatorId = locId.toString();
            foundDisplayName = callMe['locatorName']?.toString();

            final tsRaw = callMe['ts'];
            final tsMs = tsRaw is int ? tsRaw : int.tryParse('$tsRaw');

            if (tsMs != null) {
              foundTs = _formatAlertTsFromDate(
                DateTime.fromMillisecondsSinceEpoch(tsMs),
              );
            }
          }
        }
      });

      if (!mounted) return;

      if (foundAlertId != null) {
        if (_lastAlertId == foundAlertId) return;

        setState(() {
          _lastAlertId = foundAlertId;
          _activeCallAlertId = foundAlertId;
          _callRequestFrom = foundDisplayName;
          _callRequestLocatorId = foundLocatorId;
          _callRequestTs = foundTs;
        });
      } else {
        if (_activeCallAlertId != null &&
            _activeCallAlertId!.startsWith("rtdb_")) {
          setState(() {
            _callRequestFrom = null;
            _activeCallAlertId = null;
            _callRequestTs = null;
          });
        }
      }
    }, onError: (e) {
      debugPrint("LynraCare RTDB CALL_ME ERROR => $e");
    });
  }

  String _formatAlertTsFromDate(DateTime date) {
    final now = DateTime.now();
    final sameDay =
        date.year == now.year && date.month == now.month && date.day == now.day;

    final hh = date.hour.toString().padLeft(2, '0');
    final mm = date.minute.toString().padLeft(2, '0');

    if (sameDay) return '$hh:$mm';

    final dd = date.day.toString().padLeft(2, '0');
    final mo = date.month.toString().padLeft(2, '0');

    return '$dd.$mo $hh:$mm';
  }

  Future<void> _dismissCallMe() async {
    final alertId = _activeCallAlertId;
    final locatorId = _callRequestLocatorId;
    final groupId = _groupId;
    final reqId = requesterId;

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
      debugPrint('CALL_ME DISMISS DELETE ERROR => $e');
    }

    if (reqId != null && reqId.isNotEmpty) {
      try {
        await FirebaseFirestore.instance.collection('requesters').doc(reqId).get();
      } catch (_) {}
    }

    await RTDBService().updateCallRequest(
      groupId: groupId,
      locatorId: locatorId,
      isPending: false,
      handlerName: _currentRequesterName,
      targetMode: targetMode,
    );

    if (!mounted) return;

    setState(() {
      _callRequestFrom = null;
      _callRequestLocatorId = null;
      _activeCallAlertId = null;
      _callRequestTs = null;
    });
  }

  void _syncWatchingStatus(List<String> locatorIds) {
    if (_groupId == null || _groupId!.isEmpty) return;
    if (requesterId == null || requesterId!.isEmpty) return;

    final next = locatorIds.toSet();

    final toStart = next.difference(_watchedLocatorIds);
    final toStop = _watchedLocatorIds.difference(next);

    for (final locatorId in toStart) {
      RTDBService().setWatchingStatus(
        groupId: _groupId!,
        locatorId: locatorId,
        requesterId: requesterId!,
        requesterName: _currentRequesterName ?? "Requester",
        isWatching: true,
      );
    }

    for (final locatorId in toStop) {
      RTDBService().setWatchingStatus(
        groupId: _groupId!,
        locatorId: locatorId,
        requesterId: requesterId!,
        requesterName: _currentRequesterName ?? "Requester",
        isWatching: false,
      );
    }

    _watchedLocatorIds
      ..clear()
      ..addAll(next);
  }

  void _clearWatchingStatus() {
    if (_groupId == null || _groupId!.isEmpty) return;
    if (requesterId == null || requesterId!.isEmpty) return;

    for (final locatorId in _watchedLocatorIds) {
      RTDBService().setWatchingStatus(
        groupId: _groupId!,
        locatorId: locatorId,
        requesterId: requesterId!,
        requesterName: _currentRequesterName ?? "Requester",
        isWatching: false,
      );
    }

    _watchedLocatorIds.clear();
  }

  @override
  Widget build(BuildContext context) {
    if (requesterId == null) {
      return const Scaffold(
        backgroundColor: Color(0xFFF1F5F9),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFFF1F5F9),
        surfaceTintColor: Colors.transparent,
        titleSpacing: 20,
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFFE0E7FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.shield_rounded,
                size: 21,
                color: Color(0xFF4F46E5),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'LynraCare',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                      fontSize: 20,
                      letterSpacing: -0.4,
                    ),
                  ),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          'Requester: ${_cachedMyName ?? "Requester"}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                      if (isMaster) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.verified_rounded,
                          size: 14,
                          color: Color(0xFF6366F1),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (_groupId != null && _groupId!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton.filledTonal(
                onPressed: () => _showQrDialog(_groupId!),
                icon: const Icon(Icons.qr_code_2_rounded),
                color: const Color(0xFF0F172A),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddLocatorScreen()),
                );
              },
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Add locator'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          children: [
            if (_groupId == null || _groupId!.isEmpty)
              _JoinGroupCard(onJoin: _joinGroup),

            if (_callRequestFrom != null)
              _CallMeCard(
                from: _callRequestFrom!,
                ts: _callRequestTs,
                onDismiss: _dismissCallMe,
              ),

            _SectionHeader(
              title: 'My Locators',
              subtitle: 'Live status from your paired locators',
              trailing: _groupId == null
                  ? null
                  : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('locators')
                          .where('groupId', isEqualTo: _groupId)
                          .where('role', isEqualTo: 'locator')
                          .where('active', isEqualTo: true)
                          .snapshots(),
                      builder: (context, snapshot) {
                        final docs = _filterPairedLocators(snapshot.data?.docs ?? []);
                        if (docs.isEmpty) return const SizedBox.shrink();

                        return StreamBuilder<DatabaseEvent>(
                          stream: RTDBService().getGroupPresenceStream(_groupId!),
                          builder: (context, snap) {
                            final presence =
                                _parsePresenceMap(snap.data?.snapshot.value);

                            int onlineCount = 0;

                            for (final doc in docs) {
                              final item = _presenceForLocator(
                                locatorId: doc.id,
                                presence: presence,
                              );

                              if (item.online) onlineCount++;
                            }

                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '$onlineCount online',
                                  style: const TextStyle(
                                    color: Color(0xFF16A34A),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Container(
                                  width: 9,
                                  height: 9,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF16A34A),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
            ),

            const SizedBox(height: 12),

            if (_groupId == null || _groupId!.isEmpty)
              const _EmptyLocatorCard(
                title: 'No group yet',
                subtitle: 'Join or create a group first to see paired locators.',
              )
            else
              _LocatorList(
                groupId: _groupId!,
                requesterId: requesterId!,
                myLat: _myLat,
                myLng: _myLng,
                pulse: _pulse,
                onOpenMaps: _openInMaps,
                onCopyLocation: _copyLocation,
                formatLastSeen: formatLastSeen,
                formatDistance: formatDistance,
                formatCoordinate: formatCoordinate,
                filterPairedLocators: _filterPairedLocators,
                parsePresenceMap: _parsePresenceMap,
                presenceForLocator: _presenceForLocator,
                onLocatorsVisible: (ids) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _syncWatchingStatus(ids);
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterPairedLocators(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs.where((doc) {
      final data = doc.data();
      final pairedRequesters = data['pairedRequesters'] as Map<String, dynamic>?;

      if (pairedRequesters == null || requesterId == null) {
        return false;
      }

      final entry = pairedRequesters[requesterId];
      if (entry == null) return false;

      return entry['active'] == true;
    }).toList();
  }

  Map<dynamic, dynamic> _parsePresenceMap(Object? value) {
    if (value is Map<dynamic, dynamic>) return value;
    if (value is Map) return value;
    return {};
  }

  _LocatorPresence _presenceForLocator({
    required String locatorId,
    required Map<dynamic, dynamic> presence,
  }) {
    final raw = presence[locatorId];

    if (raw is! Map) {
      return const _LocatorPresence();
    }

    final status = (raw['status'] ?? '').toString();
    final lat = (raw['lat'] as num?)?.toDouble();
    final lng = (raw['lng'] as num?)?.toDouble();
    final acc = (raw['acc'] as num?)?.toDouble();
    final battery = (raw['battery'] as num?)?.toInt();
    final gpsOn = raw['gpsEnabled'] ?? true;

    DateTime? lastSeen;
    final tsRaw = raw['lastSeen'];
    final tsMs = tsRaw is int ? tsRaw : int.tryParse('$tsRaw');

    if (tsMs != null) {
      lastSeen = DateTime.fromMillisecondsSinceEpoch(tsMs);
    }

    return _LocatorPresence(
      status: status,
      online: status == 'online',
      lat: lat,
      lng: lng,
      acc: acc,
      battery: battery,
      gpsOn: gpsOn == true,
      lastSeen: lastSeen,
    );
  }
}

class _LocatorList extends StatelessWidget {
  final String groupId;
  final String requesterId;
  final double? myLat;
  final double? myLng;
  final Animation<double> pulse;
  final Future<void> Function(double lat, double lng) onOpenMaps;
  final void Function(double lat, double lng) onCopyLocation;
  final String Function(DateTime? lastSeen) formatLastSeen;
  final String Function(double? distance, double acc) formatDistance;
  final String Function(double value) formatCoordinate;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> Function(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) filterPairedLocators;
  final Map<dynamic, dynamic> Function(Object? value) parsePresenceMap;
  final _LocatorPresence Function({
    required String locatorId,
    required Map<dynamic, dynamic> presence,
  }) presenceForLocator;
  final void Function(List<String> ids) onLocatorsVisible;

  const _LocatorList({
    required this.groupId,
    required this.requesterId,
    required this.myLat,
    required this.myLng,
    required this.pulse,
    required this.onOpenMaps,
    required this.onCopyLocation,
    required this.formatLastSeen,
    required this.formatDistance,
    required this.formatCoordinate,
    required this.filterPairedLocators,
    required this.parsePresenceMap,
    required this.presenceForLocator,
    required this.onLocatorsVisible,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('locators')
          .where('groupId', isEqualTo: groupId)
          .where('role', isEqualTo: 'locator')
          .where('active', isEqualTo: true)
          .snapshots(),
      builder: (context, locatorSnapshot) {
        final docs = filterPairedLocators(locatorSnapshot.data?.docs ?? []);

        onLocatorsVisible(docs.map((e) => e.id).toList());

        if (locatorSnapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingCard();
        }

        if (docs.isEmpty) {
          return const _EmptyLocatorCard(
            title: 'No paired locator',
            subtitle: 'Add a locator or wait until pairing is approved.',
          );
        }

        return StreamBuilder<DatabaseEvent>(
          stream: RTDBService().getGroupPresenceStream(groupId),
          builder: (context, presenceSnapshot) {
            final presence = parsePresenceMap(presenceSnapshot.data?.snapshot.value);

            return Column(
              children: docs.map((doc) {
                final data = doc.data();
                final locatorId = doc.id;
                final name =
                    (data['name'] ?? data['deviceId'] ?? locatorId).toString();

                final item = presenceForLocator(
                  locatorId: locatorId,
                  presence: presence,
                );

                double? distance;
                if (myLat != null &&
                    myLng != null &&
                    item.lat != null &&
                    item.lng != null) {
                  distance = Geolocator.distanceBetween(
                    myLat!,
                    myLng!,
                    item.lat!,
                    item.lng!,
                  );
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _LocatorCard(
                    locatorId: locatorId,
                    name: name,
                    presence: item,
                    distance: distance,
                    pulse: pulse,
                    onOpenMaps: onOpenMaps,
                    onCopyLocation: onCopyLocation,
                    formatLastSeen: formatLastSeen,
                    formatDistance: formatDistance,
                    formatCoordinate: formatCoordinate,
                  ),
                );
              }).toList(),
            );
          },
        );
      },
    );
  }
}

class _LocatorCard extends StatelessWidget {
  final String locatorId;
  final String name;
  final _LocatorPresence presence;
  final double? distance;
  final Animation<double> pulse;
  final Future<void> Function(double lat, double lng) onOpenMaps;
  final void Function(double lat, double lng) onCopyLocation;
  final String Function(DateTime? lastSeen) formatLastSeen;
  final String Function(double? distance, double acc) formatDistance;
  final String Function(double value) formatCoordinate;

  const _LocatorCard({
    required this.locatorId,
    required this.name,
    required this.presence,
    required this.distance,
    required this.pulse,
    required this.onOpenMaps,
    required this.onCopyLocation,
    required this.formatLastSeen,
    required this.formatDistance,
    required this.formatCoordinate,
  });

  @override
  Widget build(BuildContext context) {
    final hasLocation = presence.lat != null && presence.lng != null;
    final lastText = presence.online ? 'Just now' : formatLastSeen(presence.lastSeen);

    return InkWell(
      borderRadius: BorderRadius.circular(26),
      onLongPress: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PairingOptionsScreen(
              locatorId: locatorId,
              locatorName: name,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x120F172A),
              blurRadius: 22,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LocatorHeader(
              name: name,
              online: presence.online,
              lastText: lastText,
              pulse: pulse,
            ),
            const SizedBox(height: 14),
            GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.15,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _MetricTile(
                  icon: Icons.battery_full_rounded,
                  iconColor: _batteryColor(presence.battery),
                  label: 'Battery',
                  value: presence.battery == null ? '--' : '${presence.battery}%',
                ),
                _MetricTile(
                  icon: presence.gpsOn
                      ? Icons.gps_fixed_rounded
                      : Icons.gps_off_rounded,
                  iconColor: presence.gpsOn
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFEF4444),
                  label: 'GPS',
                  value: presence.gpsOn ? 'ON' : 'OFF',
                ),
                _MetricTile(
                  icon: Icons.my_location_rounded,
                  iconColor: const Color(0xFF2563EB),
                  label: 'Accuracy',
                  value: presence.acc == null
                      ? '--'
                      : '${presence.acc!.toStringAsFixed(0)} m',
                ),
                _MetricTile(
                  icon: Icons.route_rounded,
                  iconColor: const Color(0xFF8B5CF6),
                  label: 'Distance',
                  value: formatDistance(distance, presence.acc ?? 0),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _LocationBox(
              hasLocation: hasLocation,
              online: presence.online,
              lat: presence.lat,
              lng: presence.lng,
              formatCoordinate: formatCoordinate,
              onCopy: hasLocation
                  ? () => onCopyLocation(presence.lat!, presence.lng!)
                  : null,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: hasLocation
                    ? () => onOpenMaps(presence.lat!, presence.lng!)
                    : null,
                icon: const Icon(Icons.map_rounded),
                label: const Text('Open in Maps'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF4F46E5),
                  side: const BorderSide(color: Color(0xFF6366F1)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _batteryColor(int? battery) {
    if (battery == null) return const Color(0xFF64748B);
    if (battery <= 20) return const Color(0xFFEF4444);
    if (battery <= 40) return const Color(0xFFF59E0B);
    return const Color(0xFF16A34A);
  }
}

class _LocatorHeader extends StatelessWidget {
  final String name;
  final bool online;
  final String lastText;
  final Animation<double> pulse;

  const _LocatorHeader({
    required this.name,
    required this.online,
    required this.lastText,
    required this.pulse,
  });

  @override
  Widget build(BuildContext context) {
    final avatarBg = online ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2);
    final avatarColor =
        online ? const Color(0xFF16A34A) : const Color(0xFFEF4444);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: avatarBg,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.person_rounded,
            color: avatarColor,
            size: 31,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  online
                      ? AnimatedBuilder(
                          animation: pulse,
                          builder: (context, child) => Transform.scale(
                            scale: pulse.value,
                            child: child,
                          ),
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF16A34A),
                              shape: BoxShape.circle,
                            ),
                          ),
                        )
                      : Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFFCBD5E1),
                            shape: BoxShape.circle,
                          ),
                        ),
                  const SizedBox(width: 8),
                  Text(
                    online ? 'ONLINE' : 'OFFLINE',
                    style: TextStyle(
                      color: online
                          ? const Color(0xFF16A34A)
                          : const Color(0xFF64748B),
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 7),
                  const Text(
                    '•',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      lastText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF334155),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded),
          color: Colors.white,
          onSelected: (_) {},
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'manage',
              child: Text('Manage locator'),
            ),
          ],
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  const _MetricTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
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

class _LocationBox extends StatelessWidget {
  final bool hasLocation;
  final bool online;
  final double? lat;
  final double? lng;
  final String Function(double value) formatCoordinate;
  final VoidCallback? onCopy;

  const _LocationBox({
    required this.hasLocation,
    required this.online,
    required this.lat,
    required this.lng,
    required this.formatCoordinate,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final title = hasLocation
        ? (online ? 'Location (WGS84)' : 'Last known location')
        : 'Location';

    final value = hasLocation
        ? '${formatCoordinate(lat!)}, ${formatCoordinate(lng!)}'
        : 'Waiting for location update...';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(13, 12, 10, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(
            hasLocation ? Icons.location_on_rounded : Icons.location_searching_rounded,
            color: const Color(0xFF4F46E5),
            size: 25,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: TextStyle(
                    color: hasLocation
                        ? const Color(0xFF0F172A)
                        : const Color(0xFF64748B),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: hasLocation ? 0.2 : 0,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onCopy,
            icon: const Icon(Icons.copy_rounded),
            color: const Color(0xFF64748B),
            tooltip: 'Copy location',
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? trailing;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _JoinGroupCard extends StatelessWidget {
  final VoidCallback onJoin;

  const _JoinGroupCard({
    required this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.qr_code_scanner_rounded,
              color: Color(0xFF2563EB),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Join a group',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Scan group QR to connect with locators.',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onJoin,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
            ),
            child: const Text('Join'),
          ),
        ],
      ),
    );
  }
}

class _CallMeCard extends StatelessWidget {
  final String from;
  final String? ts;
  final VoidCallback onDismiss;

  const _CallMeCard({
    required this.from,
    required this.ts,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.call_rounded,
              color: Color(0xFFDC2626),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$from wants you to call',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF7F1D1D),
                  ),
                ),
                if (ts != null && ts!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      ts!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF991B1B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: onDismiss,
            child: const Text('DISMISS'),
          ),
        ],
      ),
    );
  }
}

class _EmptyLocatorCard extends StatelessWidget {
  final String title;
  final String subtitle;

  const _EmptyLocatorCard({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
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
              color: const Color(0xFFE0E7FF),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.group_add_rounded,
              color: Color(0xFF4F46E5),
              size: 28,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 150,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class _LocatorPresence {
  final String status;
  final bool online;
  final double? lat;
  final double? lng;
  final double? acc;
  final int? battery;
  final bool gpsOn;
  final DateTime? lastSeen;

  const _LocatorPresence({
    this.status = '',
    this.online = false,
    this.lat,
    this.lng,
    this.acc,
    this.battery,
    this.gpsOn = true,
    this.lastSeen,
  });
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
