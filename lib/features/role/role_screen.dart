import 'package:flutter/material.dart';
import '../../core/role_manager.dart';
import '../home/home_screen.dart';
import '../requester/requester_screen.dart';

class RoleScreen extends StatelessWidget {
  const RoleScreen({super.key});

  void _select(BuildContext context, String role) async {
    await RoleManager.setRole(role);

    if (!context.mounted) return;

    if (role == "locator") {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const RequesterScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose device role')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 40),

            ElevatedButton(
              onPressed: () => _select(context, "locator"),
              child: const Text("Locator\n(Sends location when requested)"),
            ),

            const SizedBox(height: 30),

            ElevatedButton(
              onPressed: () => _select(context, "requester"),
              child: const Text("Requester\n(Requests location from locator)"),
            ),
          ],
        ),
      ),
    );
  }
}