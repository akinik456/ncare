import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/identity_manager.dart';
import '../../core/role_manager.dart';
import '../home/home_screen.dart';
import '../requester/requester_screen.dart';
import '../locator/locator_permission_screen.dart';

class NameScreen extends StatefulWidget {
  const NameScreen({super.key});

  @override
  State<NameScreen> createState() => _NameScreenState();
}

class _NameScreenState extends State<NameScreen> {
  final controller = TextEditingController();
  bool saving = false;

  Future<void> _save() async {
    final name = controller.text.trim();
    if (name.isEmpty) return;

    setState(() => saving = true);

    final role = await RoleManager.getRole();

    if (role == "requester") {
      final id = await IdentityManager.getRequesterId();

      await FirebaseFirestore.instance
          .collection('requesters')
          .doc(id)
          .set({
        'name': name,
      }, SetOptions(merge: true));

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const RequesterScreen()),
      );
    } else {
      final id = await IdentityManager.getRequesterId();

      await FirebaseFirestore.instance
          .collection('locators')
          .doc(id)
          .set({
        'name': name,
      }, SetOptions(merge: true));

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LocatorPermissionScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your name')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Enter your name',
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: saving ? null : _save,
              child: const Text("Continue"),
            )
          ],
        ),
      ),
    );
  }
}