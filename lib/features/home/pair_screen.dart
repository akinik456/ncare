import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/identity_manager.dart';
import '../..core/fcm_manager.dart';

class PairScreen extends StatefulWidget {
  const PairScreen({super.key});

  @override
  State<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends State<PairScreen> {
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
      appBar: AppBar(
        title: const Text("Pair Locator"),
      ),
      body: MobileScanner(
        controller: controller,
        onDetect: (capture) async {
          if (_handled) return;

          final raw = capture.barcodes.first.rawValue;
          if (raw == null) return;

          final data = jsonDecode(raw);
          if (data['type'] != 'ncare_pair') return;

          final requesterId = data['requesterId']?.toString();
          if (requesterId == null || requesterId.isEmpty) return;

          _handled = true;

          await controller.stop();
          
		  final prefs = await SharedPreferences.getInstance();
 		  await prefs.setString('pairedRequesterId', requesterId);
		  try{
		  
		  print("SUBSCRIBED => $requesterId");
		  }catch(e){
		  print("SUBSCRIBED ERR => $e");
		  }
		  
		  final locatorId = await 		  
		  IdentityManager.getRequesterId();
		  		  
		  await FirebaseFirestore.instance
			.collection('requesters')
			.doc(requesterId)
			.collection('locators')
			.doc(locatorId)
			.set({
		 'active': true,
         'createdAt': FieldValue.serverTimestamp(),
		  });
          if (!mounted) return;
		  Navigator.pop(context, requesterId);
        },
      ),
    );
  }
}