import 'package:geocoding/geocoding.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'add_locator_screen.dart';

class RequesterScreen extends StatefulWidget {
  const RequesterScreen({super.key});

  @override
  State<RequesterScreen> createState() => _RequesterScreenState();
}

class _RequesterScreenState extends State<RequesterScreen> {
  String? _lastRequestId;
  String? _lastAddress;
  String? _lastAddressKey;
  String _locatorName ='Locator';

  Future<void> _sendRequest() async {
    final doc = await FirebaseFirestore.instance.collection('requests').add({
      'type': 'rl',
      'ts': FieldValue.serverTimestamp(),
    });

    setState(() => _lastRequestId = doc.id);
  }
	
	Future<void> _openInMaps(double lat, double lng) async {
	  final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
	  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
		// fallback: do nothing (or show snackbar later)
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
		  if ((p.administrativeArea ?? '').trim().isNotEmpty) p.administrativeArea!.trim(),
		  if ((p.postalCode ?? '').trim().isNotEmpty) p.postalCode!.trim(),
		  if ((p.country ?? '').trim().isNotEmpty) p.country!.trim(),
		];

		final addr = parts.where((e) => e.isNotEmpty).join(', ');
		if (addr.isEmpty) return;

		setState(() {
		  _lastAddressKey = key;
		  _lastAddress = addr;
		});
	  } catch (_) {
		// sessiz geç (v1)
	  }
	}

	String timeAgo(Timestamp ts) {
	  final now = DateTime.now();
	  final time = ts.toDate();
	  final diff = now.difference(time);

	  if (diff.inSeconds < 5) return "Just now";
	  if (diff.inSeconds < 60) return "${diff.inSeconds} sec ago";
	  if (diff.inMinutes < 60) return "${diff.inMinutes} min ago";
	  return "${diff.inHours} h ago";
	}

  @override
  Widget build(BuildContext context) {
    final requestId = _lastRequestId;

    return Scaffold(
      appBar: AppBar(title: const Text('NCare Requester')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
		    
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
			  ElevatedButton(
				  onPressed: () {
					Navigator.push(
					  context,
					  MaterialPageRoute(builder: (_) => const AddLocatorScreen()),
					);
				  },
				  child: const Text('Add locator'),
				),
			
              ElevatedButton(
                onPressed: _sendRequest,
                child: const Text('Request Location'),
              ),
              const SizedBox(height: 16),
              Text('requestId: ${requestId ?? "-"}'),

              const SizedBox(height: 24),

              if (requestId != null)
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('responses')
                      .doc(requestId)
                      .snapshots(),
					builder: (context, snapshot) {
					  if (!snapshot.hasData) return const Text('Waiting response...');

					  final data = snapshot.data!.data();
					  if (data == null) return const Text('Waiting response...');

					  final status = (data['status'] ?? '').toString();
					  final lat = (data['lat'] as num?)?.toDouble();
					  final lng = (data['lng'] as num?)?.toDouble();
					  final acc = (data['acc'] as num?)?.toDouble();
					  final ts = data['ts'] as Timestamp?;

					  final hasFix = (status == 'ok' && lat != null && lng != null);

					  if (!hasFix) {
						return Text(
						  'status: $status\nwaiting for location...',
						  textAlign: TextAlign.center,
						);
					  }
					  WidgetsBinding.instance.addPostFrameCallback((_) {
						  _resolveAddress(lat!, lng!);
						});
					  return Column(
					  
						children: [
						  
							if (_lastAddress != null) ...[
							StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
  stream: FirebaseFirestore.instance
      .collection('requesters')
      .doc('default')
      .collection('locators')
      .where('active', isEqualTo: true)
      .orderBy('createdAt', descending: true)
      .limit(1)
      .snapshots(),
  builder: (context, snap) {
    if (snap.hasData && snap.data!.docs.isNotEmpty) {
      final newName =
          (snap.data!.docs.first.data()['name'] ?? 'Locator').toString();

      if (newName.isNotEmpty && newName != _locatorName) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _locatorName = newName;
            });
          }
        });
      }
    }

    return Text(
      _locatorName,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      textAlign: TextAlign.center,
    );
  },
),
const SizedBox(height: 8),
							
							  Text(
								'📍 $_lastAddress',
								textAlign: TextAlign.center,
								style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
							  ),
							  const SizedBox(height: 10),
							],
						  const SizedBox(height: 12),
						  if(acc!=null)
						  Text('Accuracy: ${acc ?? '-'} m'),
						  if (ts != null)
						  Text(timeAgo(ts)),
						  const SizedBox(height: 12),
						  Row(
							mainAxisAlignment: MainAxisAlignment.center,
							children: [
							  const SizedBox(width: 12),
							  OutlinedButton(
								onPressed: () => _openInMaps(lat, lng),
								child: const Text('Open in Maps'),
							  ),
							],
						  ),
						],
					  );
					},
				  
                ),
            ],
          ),
        ),
      ),
    );
  }
}