import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/identity_manager.dart';

class LocatorNameScreen extends StatefulWidget {
  final String locatorId;

  const LocatorNameScreen({super.key, required this.locatorId});

  @override
  State<LocatorNameScreen> createState() => _LocatorNameScreenState();
}

class _LocatorNameScreenState extends State<LocatorNameScreen> {
  final controller = TextEditingController();

Future<void> _save() async {

  try {
    final requesterId = await IdentityManager.getOrCreateDeviceId();
    final locatorId = widget.locatorId.toString();
    final groupId = await IdentityManager.getLocalGroupId();
	//if (groupId == null || groupId.isEmpty) return; 

    print("LynraCareREQUESTER ID => $requesterId");
    print("LynraCareLOCATOR ID => $locatorId");

    await FirebaseFirestore.instance
        .collection('groups')
        .doc(groupId)
        .collection('locators')
        .doc(locatorId)
        .set({
      'name': controller.text.trim(),
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
    });

    print("LynraCareREQUESTER SIDE LOCATOR SAVED");

    final requesterDoc = await FirebaseFirestore.instance
		.collection('groups')
		.doc(groupId)
		.get();

	final requesterName =
		(requesterDoc.data()?['name'] ?? '').toString();
		
	await FirebaseFirestore.instance
		.collection('locators')
		.doc(widget.locatorId)
		.set({
	  'pairedRequesterId': requesterId,
	  'requesterName': requesterName,
	}, SetOptions(merge: true));

    print("LynraCareTOP LEVEL PAIR SAVED");

    if (!mounted) return;
    Navigator.popUntil(context, (route) => route.isFirst);
  } catch (e) {
    print("LynraCareSAVE LOCATOR ERR => $e");
  }
}



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      appBar: AppBar(
        backgroundColor: const Color(0xFF020617),
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'LynraCare',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  color: const Color(0xFF020617),
                  border: Border.all(color: const Color(0xFF22C55E).withOpacity(.35)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF22C55E).withOpacity(.16),
                      blurRadius: 22,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Locator name',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.8,
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Choose the name that requester devices will see for this phone.',
                      style: TextStyle(
                        fontSize: 15,
                        color: Color(0xFF94A3B8),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: controller,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Locator name',
                  labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                  filled: true,
                  fillColor: Color(0xFF0F172A),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(18)),
                    borderSide: BorderSide(color: Color(0xFF334155)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(18)),
                    borderSide: BorderSide(color: Color(0xFF334155)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(18)),
                    borderSide: BorderSide(color: Color(0xFF22C55E)),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                child: const Text('Save locator'),
              )
            ],
          ),
        ),
      ),
    );
  }
}
