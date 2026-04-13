import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'pair_request_screen.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_input_field.dart';

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
  final FocusNode _codeFocusNode = FocusNode();

  @override
  void dispose() {
    controller.dispose();
    _codeController.dispose();
	_codeFocusNode.dispose();
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
      if (data['type'] != 'Lynracare_locator') return;

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
    return SingleChildScrollView(
  padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
          Container(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              color: const Color(0xFF020617),
              border: Border.all(color: const Color(0xFF38BDF8).withOpacity(.35)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF38BDF8).withOpacity(.18),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Add locator',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.8,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  'Choose how you want to start pairing.',
                  style: TextStyle(
                    fontSize: 15,
                    color: Color(0xFF94A3B8),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
		  AppButton(
			  onPressed: () {
              setState(() {
                _scannerMode = true;
              });
            },
			  loading: false,
			  text: 'SCAN QR',
			),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF020617),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFF38BDF8).withOpacity(.25)),
            ),
            child: SingleChildScrollView(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        'Enter 6-character code',
        style: AppTextStyles.sectionTitle,
      ),
      const SizedBox(height: 14),
      AppInputField(
        controller: _codeController,
        focusNode: _codeFocusNode,
        hintText: 'ABC123',
        onSubmitted: _lookingUpCode ? null : _submitCode,
      ),
      const SizedBox(height: 16),
      AppButton(
        onPressed: _lookingUpCode ? null : _submitCode,
        loading: _lookingUpCode,
        text: 'CONTINUE',
      ),
    ],
  ),
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
      backgroundColor: const Color(0xFF020617),
      appBar: _scannerMode
          ? null
          : AppBar(
			  backgroundColor: AppColors.background,
			  surfaceTintColor: Colors.transparent,
			  elevation: 0,
			  centerTitle: false,
			  title: const Text(
				'Lynra Care',
				style: AppTextStyles.brand,
			  ),
			),
      body: _scannerMode ? _buildScanner() : _buildMethodPicker(),
    );
  }
}
