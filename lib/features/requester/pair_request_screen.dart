import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/identity_manager.dart';

class PairRequestScreen extends StatefulWidget {
  final String locatorId;
  final String locatorName;

  const PairRequestScreen({
    super.key,
    required this.locatorId,
    required this.locatorName,
  });

  @override
  State<PairRequestScreen> createState() => _PairRequestScreenState();
}

class _PairRequestScreenState extends State<PairRequestScreen> {
  bool _sending = false;

  Future<void> _sendPairRequest() async {
    final groupId = await IdentityManager.getLocalGroupId();
	if(groupId == null || groupId!.isEmpty){
	return;
	}
    
    setState(() => _sending = true);

    try {
      final requesterId = await IdentityManager.getOrCreateDeviceId();

      final requesterDoc = await FirebaseFirestore.instance
          .collection('requesters')
          .doc(requesterId)
          .get();

      final requesterName =
          (requesterDoc.data()?['name'] ?? 'Requester').toString().trim();

      await FirebaseFirestore.instance
          .collection('locators')
          .doc(widget.locatorId)
          .set({
        'pendingPairRequesterId': requesterId,
        'pendingPairRequesterName': requesterName,
		'pendingPairGroupId': groupId,
        'pendingPairCreatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pair request sent')),
      );
      Navigator.pop(context, true);
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Widget _infoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF475569)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFF334155),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Pair request'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
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
                    const Text(
                      'Send pairing request',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Pairing will finish only after the locator approves this request.',
                      style: TextStyle(
                        fontSize: 15,
                        color: Color(0xFF64748B),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _infoRow(Icons.person_pin_circle_outlined, widget.locatorName),
                    const SizedBox(height: 10),
                    _infoRow(Icons.badge_outlined, widget.locatorId),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _sending ? null : _sendPairRequest,
                icon: _sending
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(_sending ? 'Sending...' : 'Send Pair Request'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
