import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/identity_manager.dart';

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
  
  
  @override
  void initState() {
    super.initState();
    _loadBatteryThreshold();
  }

  Future<void> _loadBatteryThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    final t = prefs.getInt('batteryAlertThreshold') ?? 20;

    setState(() {
      _batteryThreshold = t;
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

    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Geofence center saved')),
    );
  } finally {
    if (mounted) {
      setState(() => _savingCenter = false);
    }
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

      await FirebaseFirestore.instance
          .collection('requesters')
          .doc(requesterId)
          .collection('locators')
          .doc(widget.locatorId)
          .set({
        'name': widget.locatorName,
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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${widget.locatorName} Setings updated'),
          duration: const Duration(seconds: 2),
        ),
      );

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
        onChanged: (v) => setState(() => _batteryAlarmEnabled = v),
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
              onSelected: (_) {
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
      ],
    ],
  ),
),
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
