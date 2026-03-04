import 'package:flutter/material.dart';
import 'core/device_state_manager.dart';
import 'core/setup_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Start device state (permission + gps watcher)
  DeviceStateManager.instance.start();

  final setupDone = await SetupManager.isSetupDone();

  runApp(NCareApp(setupDone: setupDone));
}

class NCareApp extends StatelessWidget {
  final bool setupDone;
  const NCareApp({super.key, required this.setupDone});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NCare',
      theme: ThemeData(useMaterial3: true),
      home: setupDone ? const HomeScreen() : const SetupScreen(),
    );
  }
}

class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('NCare Setup')),
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
                  ready ? "DEVICE READY ✅" : "DEVICE NOT READY ❌",
                  style: const TextStyle(fontSize: 22),
                ),
                const SizedBox(height: 14),

                if (!ready) const Text("Konum izni ve GPS gerekli."),

                const SizedBox(height: 18),

                ElevatedButton(
                  onPressed: () async {
                    await DeviceStateManager.instance.requestPermissions();
                    // state zaten auto refresh, ama hızlı update için:
                    await DeviceStateManager.instance.recheckNow();
                  },
                  child: const Text("İzinleri kontrol et"),
                ),

                const SizedBox(height: 14),

                if (ready)
                  ElevatedButton(
                    onPressed: () async {
                      await SetupManager.setSetupDone();
                      if (!context.mounted) return;
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const HomeScreen()),
                      );
                    },
                    child: const Text("Kurulumu tamamla"),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

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
                      MaterialPageRoute(builder: (_) => const SetupScreen()),
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