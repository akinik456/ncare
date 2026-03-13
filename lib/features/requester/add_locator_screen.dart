import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'pairing_options_screen.dart';
import '../../core/fcm_manager.dart';

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

      if (!mounted) return;

      final paired = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => PairingOptionsScreen(
            locatorId: locatorId,
            locatorName: locatorName,
          ),
        ),
      );

      if (!mounted) return;

      if (paired == true) {
	  await FcmManager.ensureSubscriptions();
        Navigator.pop(context, true);
      } else {
        _handled = false;
        await controller.start();
      }
    } catch (_) {
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
