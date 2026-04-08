import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';

import '../../core/identity_manager.dart';

class AddPlaceScreen extends StatefulWidget {
  final String locatorId;
  final String locatorName;

  const AddPlaceScreen({
    super.key,
    required this.locatorId,
    required this.locatorName,
  });

  @override
  State<AddPlaceScreen> createState() => _AddPlaceScreenState();
}

class _AddPlaceScreenState extends State<AddPlaceScreen> {
  final TextEditingController _nameController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _address;
  double? _lat;
  double? _lng;
  double? _accuracy;
  DateTime? _locationAt;
  int _nextIndex = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
	final groupId = await IdentityManager.getLocalGroupId();
	final myDeviceId = await IdentityManager.getOrCreateDeviceId();
	if (groupId == null) {
      _error = "Group ID bulunamadı";
      return;
    }
	print("add_place_screen groupId:$groupId,myDeviceId:$myDeviceId");
      final placesSnap = await FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
		  .collection('locators')
          .doc(widget.locatorId)
          .collection('places')
          .get();

      _nextIndex = placesSnap.docs.length + 1;
      _nameController.text = 'Place $_nextIndex';
	 print("add_place_screen _nextIndex:$_nextIndex");

      // 2. Firestore yerine RTDB'den güncel konumu çekiyoruz
	  final rtdbRef = FirebaseDatabase.instance.ref("presence/groups/$groupId/locators/${widget.locatorId}");
	  final DataSnapshot snapshot = await rtdbRef.get();

	  if (!snapshot.exists) {
		_error = 'Locator not found in RTDB';
	print("add_place_screen locator not found");
		
		return;
	  }
	print("add_place_screen locator found");
	  // RTDB'de veri genellikle Map olarak döner
	  final data = Map<String, dynamic>.from(snapshot.value as Map);
setState(() {
      _lat = (data['lat'] as num?)?.toDouble();
      _lng = (data['lng'] as num?)?.toDouble();
      _accuracy = (data['acc'] as num?)?.toDouble();
	  print("add_place_screen lat:$_lat,lng:$_lng");
      final ts = data['lastSeen'];
		if (ts is int) {
  _locationAt = DateTime.fromMillisecondsSinceEpoch(ts);
		print("add_place_screen ts:$ts,_locationAt:$_locationAt");
  }
}); 

		if (_lat == null || _lng == null) {
		  _error = 'Locator location is not available yet';
		  return;
		}      

      try {
        final placemarks = await placemarkFromCoordinates(_lat!, _lng!)
		.timeout(const Duration(seconds: 5));
			if (placemarks.isNotEmpty) {
			final p = placemarks.first;
			_address = [p.street, p.subLocality, p.locality, p.administrativeArea]
				.where((e) => e != null && e.isNotEmpty)
				.join(', ');
		  }
		} catch (e) {
		  print("ZINK Adres alınamadı: $e");
		  _address = "Address not available";
		}
    } catch (e) {
    print("ZINK _load Error: $e");
    _error = 'An error occurred while loading data';
	} finally {
    if (mounted) setState(() => _loading = false);
	}
  }

  bool get _isFresh {
    if (_locationAt == null) return false;
    return DateTime.now().difference(_locationAt!).inSeconds <= 60;
  }

  String get _ageText {
    if (_locationAt == null) return 'Unknown';
    final secs = DateTime.now().difference(_locationAt!).inSeconds;
    if (secs < 0) return '0 sec';
    return '$secs sec ago';
  }

  bool get _canSave =>
      !_saving &&
      _lat != null &&
      _lng != null &&
      _isFresh;

  Future<int> _getPlaceCount(String requesterId) async {
  final groupId = await IdentityManager.getLocalGroupId();
		//if (groupId == null || groupId.isEmpty) return;
    final snap = await FirebaseFirestore.instance
        .collection('groups')
        .doc(groupId)
        .collection('locators')
        .doc(widget.locatorId)
        .collection('places')
        .get();
    return snap.docs.length;
  }

  Future<void> _save() async {
    if (!_canSave) return;

    setState(() => _saving = true);
    try {
      final requesterId = await IdentityManager.getOrCreateDeviceId();
	  final groupId = await IdentityManager.getLocalGroupId();
		if (groupId == null || groupId.isEmpty) return;
      final placeCount = await _getPlaceCount(requesterId);
      if (placeCount >= 3) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Maximum 3 places allowed')),
        );
        return;
      }

      final name = _nameController.text.trim().isEmpty
          ? 'Place $_nextIndex'
          : _nameController.text.trim();

      await FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .collection('locators')
          .doc(widget.locatorId)
          .collection('places')
          .add({
        'name': name,
        'lat': _lat,
        'lng': _lng,
        'address': (_address ?? '').trim(),
        'radiusMeters': 180,
        'enabled': true,
        'lastState': 'unknown',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Place saved')),
      );
      Navigator.pop(context, true);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF020617),
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'LynraCare',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF020617),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFF6366F1).withOpacity(.28)),
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
                        Text(
                          widget.locatorName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Save a place from the locator current location.',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Place name',
                            labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                            filled: true,
                            fillColor: Color(0xFF0F172A),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.all(Radius.circular(18)),
                              borderSide: BorderSide(color: Color(0xFF334155)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.all(Radius.circular(18)),
                              borderSide: BorderSide(color: Color(0xFF334155)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.all(Radius.circular(18)),
                              borderSide: BorderSide(color: Color(0xFF6366F1)),
                            ),
                          ),
                          style: TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: 18),
                        if (_error != null) ...[
                          Text(
                            _error!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ] else ...[
                          Text('Latitude: ${_lat!.toStringAsFixed(6)}', style: const TextStyle(color: Colors.white, fontSize: 14)),
                          Text('Longitude: ${_lng!.toStringAsFixed(6)}', style: const TextStyle(color: Colors.white, fontSize: 14)),
                          Text('Address: $_address', style: const TextStyle(color: Colors.white, fontSize: 14)),
                          Text('Accuracy: ${_accuracy!.toStringAsFixed(6)}', style: const TextStyle(color: Colors.white, fontSize: 14)),
                          Text('Location age: $_ageText', style: const TextStyle(color: Colors.white, fontSize: 14)),
                          const SizedBox(height: 8),
                          if (!_isFresh)
                            const Text(
                              'Location is too old. Wait for a fresh locator update.',
                              style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _canSave ? _save : null,
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
                              'Save place',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
