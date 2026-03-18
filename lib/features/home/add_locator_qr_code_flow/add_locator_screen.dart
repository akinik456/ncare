import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/fcm_manager.dart';
import 'pairing_options_screen.dart';

class AddLocatorScreen extends StatefulWidget {
  const AddLocatorScreen({super.key});

  @override
  State<AddLocatorScreen> createState() => _AddLocatorScreenState();
}

enum _AddLocatorMode { chooser, scanner, manual }

class _AddLocatorScreenState extends State<AddLocatorScreen> {
  final MobileScannerController controller = MobileScannerController();
  final TextEditingController _codeController = TextEditingController();

  bool _handled = false;
  bool _resolvingCode = false;
  _AddLocatorMode _mode = _AddLocatorMode.chooser;

  @override
  void dispose() {
    controller.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _openScanner() async {
    setState(() {
      _handled = false;
      _mode = _AddLocatorMode.scanner;
    });

    await controller.start();
  }

  Future<void> _backToChooser() async {
    if (_mode == _AddLocatorMode.scanner) {
      await controller.stop();
    }

    if (!mounted) return;
    setState(() {
      _handled = false;
      _mode = _AddLocatorMode.chooser;
    });
  }

  Future<void> _openManual() async {
    if (_mode == _AddLocatorMode.scanner) {
      await controller.stop();
    }

    if (!mounted) return;
    setState(() {
      _handled = false;
      _mode = _AddLocatorMode.manual;
    });
  }

  Future<void> _continueWithLocator({
    required String locatorId,
    required String locatorName,
  }) async {
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
      return;
    }

    if (_mode == _AddLocatorMode.scanner) {
      _handled = false;
      await controller.start();
    }
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

      await _continueWithLocator(
        locatorId: locatorId,
        locatorName: locatorName,
      );
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

  Future<void> _submitManualCode() async {
    if (_resolvingCode) return;

    final rawCode = _codeController.text.trim().toUpperCase();
    if (rawCode.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter 6-character code'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() => _resolvingCode = true);

    try {
      final query = await FirebaseFirestore.instance
          .collection('locators')
          .where('pairCode', isEqualTo: rawCode)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Code not found'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }

      final doc = query.docs.first;
      final locatorId = doc.id;
      final locatorName = (doc.data()['name'] ?? 'Locator').toString();

      if (!mounted) return;

      await _continueWithLocator(
        locatorId: locatorId,
        locatorName: locatorName,
      );
    } finally {
      if (mounted) {
        setState(() => _resolvingCode = false);
      }
    }
  }

  PreferredSizeWidget _buildAppBar() {
    String title = 'Add locator';

    if (_mode == _AddLocatorMode.scanner) {
      title = 'Scan locator QR';
    } else if (_mode == _AddLocatorMode.manual) {
      title = 'Enter pairing code';
    }

    return AppBar(
      title: Text(title),
      leading: _mode == _AddLocatorMode.chooser
          ? null
          : IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: _backToChooser,
            ),
    );
  }

  Widget _buildChooser() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.person_add_alt_1_rounded,
              size: 56,
              color: Color(0xFF1D4ED8),
            ),
            const SizedBox(height: 20),
            const Text(
              'Add locator',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Choose how you want to pair with the locator.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF64748B),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _openScanner,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Scan QR'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _openManual,
              icon: const Icon(Icons.password_rounded),
              label: const Text('Enter code'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanner() {
    return Stack(
      children: [
        MobileScanner(
          controller: controller,
          onDetect: (capture) async {
            final raw = capture.barcodes.first.rawValue;
            if (raw == null) return;
            await _handleScan(raw);
          },
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 24,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Point the camera at the locator QR code.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildManualEntry() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          const Text(
            'Enter 6-character pairing code',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Use the code shown on the locator device screen.',
            style: TextStyle(
              color: Color(0xFF64748B),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _codeController,
            textCapitalization: TextCapitalization.characters,
            maxLength: 6,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Pairing code',
              hintText: 'ABC123',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) {
              final normalized = value.toUpperCase().replaceAll(' ', '');
              if (normalized != value) {
                _codeController.value = TextEditingValue(
                  text: normalized,
                  selection: TextSelection.collapsed(offset: normalized.length),
                );
              }
            },
            onSubmitted: (_) => _submitManualCode(),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _resolvingCode ? null : _submitManualCode,
            child: _resolvingCode
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Continue'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget body;

    switch (_mode) {
      case _AddLocatorMode.chooser:
        body = _buildChooser();
        break;
      case _AddLocatorMode.scanner:
        body = _buildScanner();
        break;
      case _AddLocatorMode.manual:
        body = _buildManualEntry();
        break;
    }

    return Scaffold(
      appBar: _buildAppBar(),
      body: body,
    );
  }
}
