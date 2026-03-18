import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'pair_request_screen.dart';

class AddLocatorScreen extends StatefulWidget {
  const AddLocatorScreen({super.key});

  @override
  State<AddLocatorScreen> createState() => _AddLocatorScreenState();
}

class _AddLocatorScreenState extends State<AddLocatorScreen> {
  final MobileScannerController controller = MobileScannerController();
  bool _handled = false;
  bool _scannerMode = false;
  bool _lookingUpCode = false;
  final TextEditingController _codeController = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _openPairRequestScreen({
    required String locatorId,
    required String locatorName,
  }) async {
    if (!mounted) return;

    final sent = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PairRequestScreen(
          locatorId: locatorId,
          locatorName: locatorName,
        ),
      ),
    );

    if (!mounted) return;

    if (sent == true) {
      Navigator.pop(context, true);
      return;
    }

    if (_scannerMode) {
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

      await _openPairRequestScreen(
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

  Future<void> _submitCode() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid 6-character code')),
      );
      return;
    }

    setState(() => _lookingUpCode = true);
    try {
      final query = await FirebaseFirestore.instance
          .collection('locators')
          .where('pairCode', isEqualTo: code)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Locator not found')),
        );
        return;
      }

      final doc = query.docs.first;
      final data = doc.data();
      await _openPairRequestScreen(
        locatorId: doc.id,
        locatorName: (data['name'] ?? 'Locator').toString(),
      );
    } finally {
      if (mounted) {
        setState(() => _lookingUpCode = false);
      }
    }
  }

  Widget _buildMethodPicker() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          const Text(
            'Add locator',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose how you want to start pairing.',
            style: TextStyle(
              fontSize: 15,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.tonalIcon(
            onPressed: () {
              setState(() {
                _scannerMode = true;
              });
            },
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: const Text('Scan QR'),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Enter 6-character code',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _codeController,
                  maxLength: 6,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    hintText: 'ABC123',
                    counterText: '',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    final upper = value.toUpperCase();
                    if (upper != value) {
                      _codeController.value = _codeController.value.copyWith(
                        text: upper,
                        selection: TextSelection.collapsed(offset: upper.length),
                      );
                    }
                  },
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _lookingUpCode ? null : _submitCode,
                  child: _lookingUpCode
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Continue'),
                ),
              ],
            ),
          ),
        ],
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
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.topLeft,
              child: FilledButton.tonalIcon(
                onPressed: () async {
                  await controller.stop();
                  if (!mounted) return;
                  setState(() {
                    _scannerMode = false;
                    _handled = false;
                  });
                },
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Back'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _scannerMode
          ? null
          : AppBar(
              title: const Text('Add locator'),
            ),
      body: _scannerMode ? _buildScanner() : _buildMethodPicker(),
    );
  }
}
