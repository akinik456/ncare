import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/identity_manager.dart';
import 'locator_name_screen.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Locator')),
      body: MobileScanner(
        controller: controller,
        onDetect: (capture) async {
          if (_handled) return;

          final raw = capture.barcodes.first.rawValue;
          if (raw == null) return;

          final data = jsonDecode(raw);

          if (data['type'] != 'ncare_locator') return;

          final locatorId = data['locatorId']?.toString();
          if (locatorId == null || locatorId.isEmpty) return;

          print("SCANNED LOCATOR => $locatorId");

          _handled = true;
          await controller.stop();

          if (!mounted) return;

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => LocatorNameScreen(locatorId: locatorId),
            ),
          );
        },
      ),
    );
  }
}
