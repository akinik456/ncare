import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../../core/identity_manager.dart';

class PairScreen extends StatefulWidget {
  const PairScreen({super.key});

  @override
  State<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends State<PairScreen> {
  bool _handled = false;

  Future<void> _handleQr(String raw) async {
    if (_handled) return;
    _handled = true;

    try {
      final data = jsonDecode(raw);

      if (data['type'] != 'ncare_pair') {
        _handled = false;
        return;
      }

      final requesterId = data['requesterId']?.toString();
      if (requesterId == null || requesterId.isEmpty) {
        _handled = false;
        return;
      }

      final locatorId = await IdentityManager.getRequesterId();

      await FirebaseFirestore.instance
          .collection('requesters')
          .doc(requesterId)
          .collection('locators')
          .doc(locatorId)
          .set({
        'createdAt': FieldValue.serverTimestamp(),
        'active': true,
      }, SetOptions(merge: true));

      await FirebaseMessaging.instance.subscribeToTopic(requesterId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pairing başarılı')),
      );

      Navigator.pop(context, true);
    } catch (_) {
      _handled = false;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Geçersiz QR')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pair Locator')),
      body: SafeArea(
        child: MobileScanner(
          onDetect: (capture) async {
            final raw = capture.barcodes.first.rawValue;
            if (raw == null) return;
            await _handleQr(raw);
          },
        ),
      ),
    );
  }
}