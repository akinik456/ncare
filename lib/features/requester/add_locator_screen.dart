import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/identity_manager.dart';

class AddLocatorScreen extends StatefulWidget {
  const AddLocatorScreen({super.key});

  @override
  State<AddLocatorScreen> createState() => _AddLocatorScreenState();
}

class _AddLocatorScreenState extends State<AddLocatorScreen> {
  final MobileScannerController controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _handleScan(String raw) async {
    if (_handled) return;

    try {
      final data = jsonDecode(raw);

      if (data['type'] != 'ncare_locator') return;

      final locatorId = data['locatorId']?.toString();
      final locatorName = (data['locatorName'] ?? 'Locator').toString();

      if (locatorId == null || locatorId.isEmpty) return;

      _handled = true;
      await controller.stop();

      final requesterId = await IdentityManager.getRequesterId();

      final requesterDoc = await FirebaseFirestore.instance
          .collection('requesters')
          .doc(requesterId)
          .get();

      final requesterName =
          (requesterDoc.data()?['name'] ?? '').toString().trim();

      // Requester altında locator listesi
      await FirebaseFirestore.instance
          .collection('requesters')
          .doc(requesterId)
          .collection('locators')
          .doc(locatorId)
          .set({
        'name': locatorName,
        'active': true,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Locator ana doc: pairing bilgisi
      await FirebaseFirestore.instance
          .collection('locators')
          .doc(locatorId)
          .set({
        'pairedRequesterId': requesterId,
        'pairedRequesterName': requesterName,
      }, SetOptions(merge: true));

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$locatorName paired successfully'),
          duration: const Duration(seconds: 2),
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid locator QR'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add locator'),
      ),
      body: MobileScanner(
        controller: controller,
        onDetect: (capture) async {
          final raw = capture.barcodes.first.rawValue;
          if (raw == null) return;
          await _handleScan(raw);
        },
      ),
    );
  }
}
