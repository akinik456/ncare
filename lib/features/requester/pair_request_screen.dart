import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/identity_manager.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_input_field.dart';

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
	if(groupId == null || groupId.isEmpty){
	return;
	}
    
    setState(() => _sending = true);

    try {
      final requesterId = await IdentityManager.getOrCreateDeviceId();

      final requesterDoc = await FirebaseFirestore.instance
          .collection('groups')
		  .doc(groupId)
		  .collection('devices')
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
    backgroundColor: AppColors.background,
    appBar: AppBar(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      title: const Text(
        'Lynra Care',
        style: AppTextStyles.brand,
      ),
    ),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Send pairing request',
                    style: AppTextStyles.sectionTitle,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pairing will finish only after the locator approves this request.',
                    style: AppTextStyles.hint,
                  ),

                  const SizedBox(height: 16),

                  _infoRow(
                    Icons.person_pin_circle_outlined,
                    widget.locatorName,
                  ),

                  const SizedBox(height: 10),

                  Text(
                    widget.locatorId,
                    style: AppTextStyles.hint.copyWith(fontSize: 12),
                  ),

                  const SizedBox(height: 16),

                  AppButton(
                    onPressed: _sending ? null : _sendPairRequest,
                    loading: _sending,
                    text: 'SEND REQUEST',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
}
