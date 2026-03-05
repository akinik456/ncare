import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AddLocatorScreen extends StatefulWidget {
  const AddLocatorScreen({super.key});

  @override
  State<AddLocatorScreen> createState() => _AddLocatorScreenState();
}

class _AddLocatorScreenState extends State<AddLocatorScreen> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();

    if (name.isEmpty || phone.isEmpty) return;

    await FirebaseFirestore.instance
        .collection('requesters')
        .doc('default')
        .collection('locators')
        .add({
      'name': name,
      'phone': phone,
      'createdAt': FieldValue.serverTimestamp(),
      'active': true,
    });

    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add locator')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phoneCtrl,
              decoration: const InputDecoration(
                labelText: 'Phone',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _save,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}