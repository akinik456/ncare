import 'package:flutter/material.dart';
import '../../core/device_state_manager.dart';
import '../../core/setup_manager.dart';
import '../setup/setup_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('NCare')),
      body: Center(
        child: StreamBuilder<bool>(
          initialData: DeviceStateManager.instance.isReady,
          stream: DeviceStateManager.instance.readyStream,
          builder: (context, snapshot) {
            final ready = snapshot.data ?? false;
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  ready ? "READY ✅" : "NOT READY ❌",
                  style: const TextStyle(fontSize: 26),
                ),
                const SizedBox(height: 10),
                Text(
                  ready
                      ? "NCare running"
                      : "GPS kapalı veya izin eksik.\nSetup ekranına dön.",
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => SetupScreen()),
                    );
                  },
                  child: const Text("Setup"),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}