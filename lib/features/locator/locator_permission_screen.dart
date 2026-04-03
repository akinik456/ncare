import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

import '../../core/role_manager.dart';
import '../home/home_screen.dart';

class LocatorPermissionScreen extends StatefulWidget {
  const LocatorPermissionScreen({super.key});

  @override
  State<LocatorPermissionScreen> createState() => _LocatorPermissionScreenState();
}

class _LocatorPermissionScreenState extends State<LocatorPermissionScreen> with WidgetsBindingObserver {
  // Otomatik kontrol edilen izinler
  bool _isLocationOk = false;
  bool _isActivityOk = false;
  bool _isBatteryOk = false;
  bool _isNotificationOk = false;
  
  // Manuel işaretlenen izinler (Android kısıtlamaları nedeniyle)
  bool _isAutoStartOk = false;
  bool _isProtectedAppOk = false;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions(); // İlk açılışta kontrol et
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Kullanıcı ayarlardan geri geldiğinde tetiklenir
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  /// Donanım ve sistem izinlerini check eder
  Future<void> _checkPermissions() async {
    final loc = await Permission.location.isGranted;
    final activity = await Permission.activityRecognition.isGranted;
    final battery = await Permission.ignoreBatteryOptimizations.isGranted;
    final notif = await Permission.notification.isGranted;

    if (mounted) {
      setState(() {
        _isLocationOk = loc;
        _isActivityOk = activity;
        _isBatteryOk = battery;
        _isNotificationOk = notif;
      });
    }
  }

  // Tüm izinler tamam mı?
  bool get _allPermissionsGranted =>
      _isLocationOk && 
      _isActivityOk && 
      _isBatteryOk && 
      _isNotificationOk && 
      _isAutoStartOk && 
      _isProtectedAppOk;

  Future<void> _continue() async {
    if (!_allPermissionsGranted || _busy) return;
    
    setState(() => _busy = true);
    try {
      await RoleManager.setRole('locator');
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF020617), Color(0xFF0F172A)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 32),
                      _buildSectionTitle("System Permissions"),
                      _buildPermissionItem(
                        title: 'Location Access',
                        subtitle: 'Always allow for real-time tracking',
                        icon: Icons.location_on_rounded,
                        isGranted: _isLocationOk,
                        onTap: () => Permission.location.request(),
                      ),
                      _buildPermissionItem(
                        title: 'Physical Activity',
                        subtitle: 'Required for motion detection',
                        icon: Icons.directions_run_rounded,
                        isGranted: _isActivityOk,
                        onTap: () => Permission.activityRecognition.request(),
                      ),
                      _buildPermissionItem(
                        title: 'Battery Optimization',
                        subtitle: 'Disable restrictions for background life',
                        icon: Icons.battery_charging_full_rounded,
                        isGranted: _isBatteryOk,
                        onTap: () => Permission.ignoreBatteryOptimizations.request(),
                      ),
                      _buildPermissionItem(
                        title: 'Notifications',
                        subtitle: 'Important for request visibility',
                        icon: Icons.notifications_active_rounded,
                        isGranted: _isNotificationOk,
                        onTap: () => Permission.notification.request(),
                      ),
                      const SizedBox(height: 24),
                      _buildSectionTitle("Manufacturer Settings"),
                      _buildPermissionItem(
                        title: 'Auto-Start',
                        subtitle: 'Allow app to start on device boot',
                        icon: Icons.power_settings_new_rounded,
                        isGranted: _isAutoStartOk,
                        isManual: true,
                        onTap: () => setState(() => _isAutoStartOk = !_isAutoStartOk),
                      ),
                      _buildPermissionItem(
                        title: 'Protected Apps',
                        subtitle: 'Keep NCare alive in background memory',
                        icon: Icons.app_settings_alt_rounded,
                        isGranted: _isProtectedAppOk,
                        isManual: true,
                        onTap: () => setState(() => _isProtectedAppOk = !_isProtectedAppOk),
                      ),
                    ],
                  ),
                ),
              ),
              _buildBottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF14B8A6).withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.shield_rounded, color: Color(0xFF14B8A6), size: 32),
        ),
        const SizedBox(height: 20),
        const Text(
          'Permissions',
          style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1),
        ),
        const Text(
          'NCare requires these to function in background.',
          style: TextStyle(fontSize: 16, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, left: 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(color: Color(0xFF5EEAD4), fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2),
      ),
    );
  }

  Widget _buildPermissionItem({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isGranted,
    required VoidCallback onTap,
    bool isManual = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isGranted ? const Color(0xFF14B8A6).withOpacity(0.05) : const Color(0xFF1E293B).withOpacity(0.4),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isGranted ? const Color(0xFF14B8A6).withOpacity(0.5) : const Color(0xFF334155),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: isGranted ? const Color(0xFF14B8A6) : const Color(0xFF64748B), size: 26),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  Text(subtitle, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            if (isManual && !isGranted)
              const Icon(Icons.touch_app_rounded, color: Colors.orangeAccent, size: 20)
            else
              Icon(
                isGranted ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                color: isGranted ? const Color(0xFF14B8A6) : const Color(0xFF475569),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF020617),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 40, offset: const Offset(0, -10))],
      ),
      child: FilledButton(
        onPressed: _allPermissionsGranted ? _continue : null,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF14B8A6),
          disabledBackgroundColor: const Color(0xFF1E293B),
          minimumSize: const Size(double.infinity, 64),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        child: _busy
            ? const CircularProgressIndicator(color: Colors.white)
            : Text(
                _allPermissionsGranted ? 'CONTINUE' : 'GRANT REQUIRED PERMISSIONS',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1),
              ),
      ),
    );
  }
}