import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/identity_manager.dart';
import '../../core/location_helper.dart';
import 'add_place_screen.dart';

import '../../core/identity_manager.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_input_field.dart';

class PairingOptionsScreen extends StatefulWidget {
  final String locatorId;
  final String locatorName;

  const PairingOptionsScreen({
    super.key,
    required this.locatorId,
    required this.locatorName,
  });

  @override
  State<PairingOptionsScreen> createState() => _PairingOptionsScreenState();
}

class _PairingOptionsScreenState extends State<PairingOptionsScreen> {
  bool _callEnabled = true;
  bool _batteryAlarmEnabled = true;
  bool _gpsOffAlarmEnabled = false;
  bool _geofenceAlarmEnabled = false;

  int _batteryThreshold = 20;
  int _geofenceRadius = 250;

  bool _saving = false;
  bool _savingCenter = false;
  
  double? _geofenceCenterLat;
  double? _geofenceCenterLng;
  
  @override
  void initState() {
    super.initState();
    _loadBatteryThreshold();
	_loadGeofenceCenter();
	_loadExistingSettings();
  }

  Future<void> _loadBatteryThreshold() async {
    final prefs = await 
	SharedPreferences.getInstance();
	
	_batteryAlarmEnabled = 
	  prefs.getBool('batteryAlarmEnabled') ?? true;
	  
    final t = prefs.getInt('batteryAlertThreshold') ?? 20;

    setState(() {
      _batteryThreshold = t;
    });
  }
Future<void> _loadGeofenceCenter() async {
final groupId = await IdentityManager.getLocalGroupId();
		if (groupId == null || groupId.isEmpty) return;
  final requesterId = await IdentityManager.getOrCreateDeviceId();
  final doc = await FirebaseFirestore.instance
      .collection('groups')
      .doc(groupId)
      .collection('locators')
      .doc(widget.locatorId)
      .get();

  final data = doc.data();
  if (!mounted) return;

  setState(() {
    _geofenceCenterLat = (data?['geofenceCenterLat'] as num?)?.toDouble();
    _geofenceCenterLng = (data?['geofenceCenterLng'] as num?)?.toDouble();
  });
}  

Future<void> _loadExistingSettings() async {
  final requesterId = await IdentityManager.getOrCreateDeviceId();
  final groupId = await IdentityManager.getLocalGroupId();
	if (groupId == null || groupId.isEmpty) return;
  final doc = await FirebaseFirestore.instance
      .collection('groups')
      .doc(groupId)
      .collection('locators')
      .doc(widget.locatorId)
      .get();

  final data = doc.data();
  if (data == null) return;

  setState(() {
    _callEnabled = (data['callEnabled'] ?? true) == true;
    _batteryAlarmEnabled = (data['batteryAlarmEnabled'] ?? true) == true;
    _gpsOffAlarmEnabled = (data['gpsOffAlarmEnabled'] ?? false) == true;
    _geofenceAlarmEnabled = (data['geofenceAlarmEnabled'] ?? false) == true;
    _geofenceRadius = (data['geofenceRadius'] ?? 250) as int;
    _batteryThreshold = (data['batteryAlertThreshold'] ?? 20) as int;
  });
}
  
Future<void> _setCurrentLocationAsGeofenceCenter() async {
  setState(() => _savingCenter = true);

  try {
    final requesterId = await IdentityManager.getOrCreateDeviceId();
final groupId = await IdentityManager.getLocalGroupId();
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location permission is required')),
      );
      return;
    }

    final pos = await LocationService.getCurrentLocationSafe(
  accuracy: LocationAccuracy.high,
  timeLimit: const Duration(seconds: 20),
);
		if(pos == null) return;
    
    await FirebaseFirestore.instance
	    .collection('groups')
        .doc(groupId)
        .collection('locators')
        .doc(widget.locatorId)
        .set({
      'geofenceCenterLat': pos.latitude,
      'geofenceCenterLng': pos.longitude,
    }, SetOptions(merge: true));
	
	

    
if (!mounted) return;
setState(() {
  _geofenceCenterLat = pos.latitude;
  _geofenceCenterLng = pos.longitude;
});
	
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Geofence center saved')),
    );
  } finally {
    if (mounted) {
      setState(() => _savingCenter = false);
    }
  }
}

Future<int> _getPlaceCount() async {
  final requesterId = await IdentityManager.getOrCreateDeviceId();
  final groupId = await IdentityManager.getLocalGroupId();
  final snap = await FirebaseFirestore.instance
      .collection('groups')
      .doc(groupId)
      .collection('locators')
      .doc(widget.locatorId)
      .collection('places')
      .get();
  return snap.docs.length;
}

Future<void> _openAddPlace() async {
  final placeCount = await _getPlaceCount();
  if (placeCount >= 3) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Maximum 3 places allowed')),
    );
    return;
  }

  if (!mounted) return;
  final added = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => AddPlaceScreen(
        locatorId: widget.locatorId,
        locatorName: widget.locatorName,
      ),
    ),
  );

  if (added == true && mounted) {
    setState(() {});
  }
}

Future<void> _confirmPairing() async {
  setState(() => _saving = true);

  try {
    final requesterId = await IdentityManager.getOrCreateDeviceId();
	final groupId = await IdentityManager.getLocalGroupId();
		if (groupId == null || groupId.isEmpty) return;
    final requesterDoc = await FirebaseFirestore.instance
        .collection('requesters')
        .doc(requesterId)
        .get();

    final requesterName =
        (requesterDoc.data()?['name'] ?? '').toString().trim();

    final locatorDoc = await FirebaseFirestore.instance
        .collection('locators')
        .doc(widget.locatorId)
        .get();

    final locatorName =
        (locatorDoc.data()?['name'] ?? 'Locator').toString().trim();

    await FirebaseFirestore.instance
        .collection('groups')
        .doc(groupId)
        .collection('locators')
        .doc(widget.locatorId)
        .set({
      'name': locatorName,
      'active': true,
      'callEnabled': _callEnabled,
      'batteryAlarmEnabled': _batteryAlarmEnabled,
      'batteryAlertThreshold': _batteryThreshold,
      'gpsOffAlarmEnabled': _gpsOffAlarmEnabled,
      'geofenceAlarmEnabled': _geofenceAlarmEnabled,
      'geofenceRadius': _geofenceRadius,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await FirebaseFirestore.instance
        .collection('locators')
        .doc(widget.locatorId)
        .set({
      'pairedRequesterId': requesterId,
      'pairedRequesterName': requesterName,
    }, SetOptions(merge: true));

    if (!mounted) return;
    Navigator.pop(context, true);
  } finally {
    if (mounted) {
      setState(() => _saving = false);
    }
  }
}
  Widget _sectionCard({required Widget child}) {
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
      child: child,
    );
  }

  Widget _toggleTile({
  required String title,
  required String subtitle,
  required bool value,
  required ValueChanged<bool> onChanged,
}) {
  return SwitchListTile.adaptive(
    contentPadding: EdgeInsets.zero,
    value: value,
    onChanged: onChanged,
    activeColor: AppColors.primary,
    title: Text(
      title,
      style: AppTextStyles.sectionTitle.copyWith(fontSize: 15),
    ),
    subtitle: Text(
      subtitle,
      style: AppTextStyles.hint.copyWith(height: 1.35),
    ),
  );
}

  Widget _radiusChip(int value) {
    final selected = _geofenceRadius == value;

    return GestureDetector(
      onTap: () {
        setState(() {
          _geofenceRadius = value;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1D4ED8) : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color:
                selected ? const Color(0xFF1D4ED8) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Text(
          '$value m',
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFF0F172A),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }



  Future<CollectionReference<Map<String, dynamic>>> _placesRef() async {
    final requesterId = await IdentityManager.getOrCreateDeviceId();
	final groupId = await IdentityManager.getLocalGroupId();
    return FirebaseFirestore.instance
        .collection('groups')
        .doc(groupId)
        .collection('locators')
        .doc(widget.locatorId)
        .collection('places');
  }


  Future<void> _setPlaceEnabled({
    required String placeId,
    required bool enabled,
  }) async {
    final ref = await _placesRef();
    await ref.doc(placeId).set({
      'enabled': enabled,
    }, SetOptions(merge: true));
  }

  Widget _placeTile(String placeId, Map<String, dynamic> data) {
  final name = (data['name'] ?? 'Place').toString().trim();
  final address = (data['address'] ?? '').toString().trim();
  final enabled = (data['enabled'] ?? true) == true;

  return Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: AppColors.background.withOpacity(0.45),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.place_rounded,
            color: AppColors.primary,
            size: 18,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: AppTextStyles.sectionTitle.copyWith(fontSize: 14),
              ),
              const SizedBox(height: 2),
              Text(
                address.isEmpty ? 'Address not available' : address,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.hint.copyWith(
                  fontSize: 12,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.scale(
              scale: 0.85,
              child: Switch.adaptive(
                value: enabled,
                activeColor: AppColors.primary,
                onChanged: (v) async {
                  await _setPlaceEnabled(
                    placeId: placeId,
                    enabled: v,
                  );
                },
              ),
            ),
            Text(
              enabled ? 'On' : 'Off',
              style: AppTextStyles.hint.copyWith(
                fontSize: 11,
                color: enabled ? AppColors.primary : AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

  Widget _placesSection() {
    return FutureBuilder<CollectionReference<Map<String, dynamic>>>(
      future: _placesRef(),
      builder: (context, refSnap) {
        if (!refSnap.hasData) {
          return _sectionCard(
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final ref = refSnap.data!;
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: ref.orderBy('createdAt', descending: false).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _sectionCard(
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }

            final docs = snapshot.data?.docs ?? const [];
            final placeCount = docs.length;
            final canAdd = placeCount < 3;

            return AppCard(
  padding: const EdgeInsets.all(14),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              'Saved places',
              style: AppTextStyles.sectionTitle.copyWith(fontSize: 15),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              '$placeCount / 3',
              style: AppTextStyles.hint.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      Text(
        'Save up to 3 places from the locator current location.',
        style: AppTextStyles.hint.copyWith(fontSize: 13, height: 1.25),
      ),
      const SizedBox(height: 8),
      if (docs.isEmpty)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.background.withOpacity(0.45),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            'No places saved yet.',
            style: AppTextStyles.hint.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        )
      else
        ...docs.map((doc) => _placeTile(doc.id, doc.data())),
      const SizedBox(height: 2),
      SizedBox(
  width: double.infinity,
  child: SizedBox(
    height: 48,
    child: AppButton(
      onPressed: canAdd
          ? () async {
              final saved = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => AddPlaceScreen(
                    locatorId: widget.locatorId,
                    locatorName: widget.locatorName,
                  ),
                ),
              );

              if (saved == true && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Place list updated')),
                );
              }
            }
          : null,
      loading: false,
      text: canAdd ? 'ADD PLACE' : 'MAXIMUM 3 PLACES',
    ),
  ),
),
    ],
  ),
);
          },
        );
      },
    );
  }



Future<void> _removeLocator() async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Remove locator'),
        content: const Text(
          'Are you sure you want to remove this locator? You can add it again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      );
    },
  );

  if (confirm != true) return;

  setState(() => _saving = true);

  try {
    final requesterId = await IdentityManager.getOrCreateDeviceId();
    final firestore = FirebaseFirestore.instance;
    final locatorRef = firestore.collection('locators').doc(widget.locatorId);

    final locatorSnap = await locatorRef.get();
    final locatorData = locatorSnap.data() ?? <String, dynamic>{};

    final pairedRequestersRaw =
        (locatorData['pairedRequesters'] as Map<String, dynamic>?) ?? {};
    final pairedRequesters =
        Map<String, dynamic>.from(pairedRequestersRaw);

    if (pairedRequesters.containsKey(requesterId)) {
    pairedRequesters.remove(requesterId);  
    }

    final activeCount = pairedRequesters.values.where((entry) {
      final map = Map<String, dynamic>.from(entry as Map);
      return map['active'] == true;
    }).length;

    final updates = <String, dynamic>{
      'pairedRequesters': pairedRequesters,
      'pairedRequestersCount': activeCount,
    };

    if ((locatorData['pairedRequesterId'] ?? '').toString() == requesterId) {
      updates['pairedRequesterId'] = FieldValue.delete();
      updates['pairedRequesterName'] = FieldValue.delete();
    }

    if ((locatorData['pendingPairRequesterId'] ?? '').toString() == requesterId) {
      updates['pendingPairRequesterId'] = FieldValue.delete();
      updates['pendingPairRequesterName'] = FieldValue.delete();
      updates['pendingPairCreatedAt'] = FieldValue.delete();
    }

    await locatorRef.set(updates, SetOptions(merge: true));
	
    if (!mounted) return;
    Navigator.pop(context, true);
  } finally {
    if (mounted) {
      setState(() => _saving = false);
    }
  }
}

@override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(
      elevation: 0,
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      title: const Text(
        'Lynra Care',
        style: AppTextStyles.brand,
      ),
    ),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  _toggleTile(
                    title: 'Call request',
                    subtitle: 'Allow this locator to ask requester to call.',
                    value: _callEnabled,
                    onChanged: (v) => setState(() => _callEnabled = v),
                  ),
                  const Divider(height: 14),

                  _toggleTile(
                    title: 'Battery alerts',
                    subtitle: 'Notify when battery drops below selected level.',
                    value: _batteryAlarmEnabled,
                    onChanged: (v) async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('batteryAlarmEnabled', v);
                      setState(() => _batteryAlarmEnabled = v);
                    },
                  ),

                  if (_batteryAlarmEnabled) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Battery alert level',
                        style: AppTextStyles.sectionTitle.copyWith(fontSize: 14),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [10,20,30].map((level) {
                        final selected = _batteryThreshold == level;
                        return ChoiceChip(
                          label: Text(
                            '$level%',
                            style: TextStyle(
                              color: selected
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          selected: selected,
                          selectedColor: AppColors.primary,
                          backgroundColor: AppColors.background,
                          side: const BorderSide(color: AppColors.border),
                          onSelected: (_) async {
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setInt('batteryAlertThreshold', level);
                            setState(() => _batteryThreshold = level);
                          },
                        );
                      }).toList(),
                    ),
                  ],

                  const Divider(height: 14),

                  _toggleTile(
                    title: 'GPS off alarm',
                    subtitle: 'Notify when locator location service is turned off.',
                    value: _gpsOffAlarmEnabled,
                    onChanged: (v) =>
                        setState(() => _gpsOffAlarmEnabled = v),
                  ),

                  const Divider(height: 14),

                  _toggleTile(
                    title: 'Geofence alarm',
                    subtitle: 'Notify when locator leaves the selected area.',
                    value: _geofenceAlarmEnabled,
                    onChanged: (v) =>
                        setState(() => _geofenceAlarmEnabled = v),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            _placesSection(),

            const SizedBox(height: 8),

            Padding(
  padding: const EdgeInsets.symmetric(horizontal: 14),
  child: SizedBox(
    height: 48,
    child: AppButton(
      onPressed: _saving ? null : _confirmPairing,
      loading: _saving,
      text: 'SAVE SETTINGS',
    ),
  ),
),

            const SizedBox(height: 6),

            Padding(
  padding: const EdgeInsets.symmetric(horizontal: 14),
  child: SizedBox(
    height: 48,
    child: OutlinedButton(
      onPressed: _saving ? null : _removeLocator,
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Colors.red),
        foregroundColor: Colors.red,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      child: const Text(
        'REMOVE LOCATOR',
        style: TextStyle(fontWeight: FontWeight.w700),
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

}
