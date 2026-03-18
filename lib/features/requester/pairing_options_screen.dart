import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/identity_manager.dart';
import '../../core/location_helper.dart';
import 'add_place_screen.dart';
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
  final requesterId = await IdentityManager.getRequesterId();
  final doc = await FirebaseFirestore.instance
      .collection('requesters')
      .doc(requesterId)
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
  final requesterId = await IdentityManager.getRequesterId();

  final doc = await FirebaseFirestore.instance
      .collection('requesters')
      .doc(requesterId)
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
    final requesterId = await IdentityManager.getRequesterId();

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
	    .collection('requesters')
        .doc(requesterId)
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
  final requesterId = await IdentityManager.getRequesterId();
  final snap = await FirebaseFirestore.instance
      .collection('requesters')
      .doc(requesterId)
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
    final requesterId = await IdentityManager.getRequesterId();

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
        .collection('requesters')
        .doc(requesterId)
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
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: Color(0xFF0F172A),
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          color: Color(0xFF64748B),
          height: 1.35,
        ),
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
    final requesterId = await IdentityManager.getRequesterId();
    return FirebaseFirestore.instance
        .collection('requesters')
        .doc(requesterId)
        .collection('locators')
        .doc(widget.locatorId)
        .collection('places');
  }

  Widget _placeTile(Map<String, dynamic> data) {
    final name = (data['name'] ?? 'Place').toString().trim();
    final address = (data['address'] ?? '').toString().trim();
    final enabled = (data['enabled'] ?? true) == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFE0E7FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.place_rounded,
              color: Color(0xFF1D4ED8),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  address.isEmpty ? 'Address not available' : address,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: enabled ? const Color(0xFFDCFCE7) : const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              enabled ? 'Enabled' : 'Disabled',
              style: TextStyle(
                color: enabled ? const Color(0xFF166534) : const Color(0xFF475569),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
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

            return _sectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Saved places',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$placeCount / 3',
                          style: const TextStyle(
                            color: Color(0xFF334155),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Save up to 3 places from the locator current location.',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (docs.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: const Text(
                        'No places saved yet.',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  else
                    ...docs.map((doc) => _placeTile(doc.data())),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
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
                      icon: const Icon(Icons.add_location_alt_rounded),
                      label: Text(canAdd ? 'Add place' : 'Maximum 3 places reached'),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFFF1F5F9),
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Pair with locator',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          children: [
            const SizedBox(height: 14),
            _sectionCard(

  child: Column(
    children: [
      _toggleTile(
        title: 'Call request',
        subtitle: 'Allow this locator to ask requester to call.',
        value: _callEnabled,
        onChanged: (v) => setState(() => _callEnabled = v),
      ),

      const Divider(height: 20),

      _toggleTile(
  title: 'Battery alerts',
  subtitle: 'Notify when battery drops below selected level.',
  value: _batteryAlarmEnabled,
  onChanged: (v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('batteryAlarmEnabled', v);

    setState(() {
      _batteryAlarmEnabled = v;
    });
	print("prefs set");
  },
),
if (_batteryAlarmEnabled) ...[
  const SizedBox(height: 10),
  Align(
    alignment: Alignment.centerLeft,
    child: Text(
      'Battery alert level',
      style: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w800,
        color: const Color(0xFF0F172A),
      ),
    ),
  ),
  const SizedBox(height: 10),
  Wrap(
    spacing: 10,
    runSpacing: 10,
    children: [10, 15, 20, 25, 30].map((level) {
      return ChoiceChip(
        label: Text('$level%'),
        selected: _batteryThreshold == level,
        onSelected: (_) async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('batteryAlertThreshold', level);

          setState(() {
            _batteryThreshold = level;
          });
        },
      );
    }).toList(),
  ),
],

      const Divider(height: 20),

      _toggleTile(
        title: 'GPS off alarm',
        subtitle: 'Notify when locator location service is turned off.',
        value: _gpsOffAlarmEnabled,
        onChanged: (v) => setState(() => _gpsOffAlarmEnabled = v),
      ),

      const Divider(height: 20),

      _toggleTile(
        title: 'Geofence alarm',
        subtitle: 'Notify when locator leaves the selected area.',
        value: _geofenceAlarmEnabled,
        onChanged: (v) => setState(() => _geofenceAlarmEnabled = v),
      ),

      if (_geofenceAlarmEnabled) ...[
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Geofence radius',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0F172A),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _radiusChip(100),
            _radiusChip(250),
            _radiusChip(500),
            _radiusChip(1000),
          ],
        ),
		const SizedBox(height: 14),
SizedBox(
  width: double.infinity,
  child: OutlinedButton.icon(
    onPressed: _savingCenter ? null : _setCurrentLocationAsGeofenceCenter,
    icon: const Icon(Icons.my_location_rounded),
    label: Text(
      _savingCenter
          ? 'Saving center...'
          : 'Use my current location as center',
    ),
  ),
),
const SizedBox(height: 8),
Text(
  (_geofenceCenterLat != null && _geofenceCenterLng != null)
      ? 'Center saved'
      : 'Center not set',
  style: Theme.of(context).textTheme.bodySmall,
),

      ],
    ],
  ),
),
const SizedBox(height: 14),
_placesSection(),
const SizedBox(height: 14),
SizedBox(
  width: double.infinity,
  child: FilledButton(
    onPressed: _saving ? null : _confirmPairing,
    style: FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
    ),
    child: _saving
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Text(
            'Save settings',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
  ),
),

const SizedBox(height: 20),

OutlinedButton(
child: const Text('Remove locator'),
onPressed: _saving
    ? null
    : () async {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Remove locator'),
              content: const Text(
                'Are you sure you want to remove this locator? '
                'You can add it again later.',
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

        final requesterId = await IdentityManager.getRequesterId();

        await FirebaseFirestore.instance
            .collection('requesters')
            .doc(requesterId)
            .collection('locators')
            .doc(widget.locatorId)
            .set({
          'active': false,
          'removedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        if (!mounted) return;
        Navigator.pop(context, true);
      },

),



       
          ],
        ),
      ),
    );
  }
}
