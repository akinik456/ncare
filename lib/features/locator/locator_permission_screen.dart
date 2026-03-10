import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/role_manager.dart';
import '../home/home_screen.dart';

class LocatorPermissionScreen extends StatefulWidget {
  const LocatorPermissionScreen({super.key});

  @override
  State<LocatorPermissionScreen> createState() =>
      _LocatorPermissionScreenState();
}

class _LocatorPermissionScreenState extends State<LocatorPermissionScreen> {
  bool _busy = false;

  Future<void> _continue() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final locStatus = await Permission.locationWhenInUse.request();
      final notifStatus = await Permission.notification.request();

      final ok = locStatus.isGranted &&
          (notifStatus.isGranted || notifStatus.isLimited);

      if (ok) {
        await RoleManager.setRole('locator');
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (_) => false,
        );
        return;
      }

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Permissions required'),
          content: const Text(
            'Location and notification permissions are required for locator mode.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(context);
                await openAppSettings();
              },
              child: const Text('Open settings'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF1F5F9),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Locator setup',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x120F172A),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: const Color(0xFFDBEAFE),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: const Icon(
                        Icons.location_on_rounded,
                        size: 36,
                        color: Color(0xFF1D4ED8),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'This device will respond to location requests.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'To work properly NCare needs:\n\n• Location permission\n• Notification permission',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF475569),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _busy ? null : _continue,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Continue'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
