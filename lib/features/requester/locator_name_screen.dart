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
    final requesterId = await IdentityManager.getRequesterId();
    final locatorId = widget.locatorId.toString();

    print("REQUESTER ID => $requesterId");
    print("LOCATOR ID => $locatorId");

    await FirebaseFirestore.instance
        .collection('requesters')
        .doc(requesterId)
        .collection('locators')
        .doc(locatorId)
        .set({
      'name': controller.text.trim(),
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
    });

    print("REQUESTER SIDE LOCATOR SAVED");

    final requesterDoc = await FirebaseFirestore.instance
		.collection('requesters')
		.doc(requesterId)
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

    print("TOP LEVEL PAIR SAVED");

    if (!mounted) return;
    Navigator.popUntil(context, (route) => route.isFirst);
  } catch (e) {
    print("SAVE LOCATOR ERR => $e");
  }
}



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Locator name')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Locator name',
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _save,
              child: const Text('Save locator'),
            )
          ],
        ),
      ),
    );
  }
}
