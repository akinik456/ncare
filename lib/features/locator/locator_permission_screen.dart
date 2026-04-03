import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:android_intent_plus/android_intent.dart';

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
  bool _manualBatteryConfirm = false;
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
    final loc = await Permission.locationAlways.isGranted;
    final activity = await Permission.activityRecognition.isGranted;
    final battery = await Permission.ignoreBatteryOptimizations.isGranted;
    final notif = await Permission.notification.isGranted;
	bool _isBatteryOk = false;
	bool _manualBatteryConfirm = false; // Kullanıcı "yaptım" derse diye

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
      (_isBatteryOk || _manualBatteryConfirm) && 
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
  
Future<void> _openManufacturerSetting(String type) async {
  if (!Platform.isAndroid) return;

  final deviceInfo = await DeviceInfoPlugin().androidInfo;
  final manufacturer = deviceInfo.manufacturer.toLowerCase();

  // XIAOMI / REDMI / POCO Grubu
  if (manufacturer.contains('xiaomi') || manufacturer.contains('redmi') || manufacturer.contains('poco')) {
    if (type == 'autostart') {
      try {
        await const AndroidIntent(
          action: 'miui.intent.action.OP_AUTO_START',
          package: 'com.miui.securitycenter',
        ).launch();
      } catch (e) {
        await openAppSettings(); // Fallback: Genel ayarlar
      }
    } else if (type == 'protected') {
  try {
    // Xiaomi Güvenlik (Security Center) - Hız Artırıcı ve Bellek Ayarları
    await const AndroidIntent(
      action: 'android.intent.action.MAIN',
      package: 'com.miui.securitycenter',
      componentName: 'com.miui.securitycenter.memorycleaner.MemorySettingsActivity', // Nokta atışı burası
    ).launch();
  } catch (e) {
    try {
      // Eğer yukarıdaki 'MemorySettings' hata verirse, Güvenlik ana sayfasını açalım
      // Kullanıcı oradan 'Hız Artır' (Speed Boost) butonuna kendisi basar.
      await const AndroidIntent(
        action: 'android.intent.action.MAIN',
        package: 'com.miui.securitycenter',
      ).launch();
    } catch (e) {
      // O da olmazsa genel ayarlara düşür (Fallback)
      await openAppSettings();
    }
  }
}
  } 
  // SAMSUNG Grubu
  else if (manufacturer.contains('samsung')) {
    // Samsung'da genelde "Battery and Device Care" sayfası açılır
    await openAppSettings(); 
  }
  // DİĞERLERİ
  else {
    await openAppSettings();
  }
}  

void _showXiaomiGuide() {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text("Xiaomi Memory Lock", style: TextStyle(color: Colors.white)),
      content: const Text(
        "Lütfen açılan ekranda şu yolu izleyin:\n\n"
        "1. Sağ üstteki 'Ayarlar' (Dişli) ikonuna basın.\n"
        "2. 'Uygulamaları Kilitle' (App Lock) seçeneğine girin.\n"
        "3. NCare şalterini aktif edin.",
        style: TextStyle(color: Color(0xFF94A3B8)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("ANLADIM, AÇ", style: TextStyle(color: Color(0xFF14B8A6))),
        ),
      ],
    ),
  );
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
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24), 
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 20),
                      _buildSectionTitle("System Permissions"),
                      _buildPermissionItem(
  title: 'Location Access',
  subtitle: 'Set to "Allow all the time" for tracking', // Alt yazıyı da netleştirdik
  icon: Icons.location_on_rounded,
  isGranted: _isLocationOk,
  onTap: () async {
    // 1. Önce standart izni iste (While in use)
    final status = await Permission.location.request();
    
    if (status.isGranted) {
      // 2. Eğer standart izin tamamsa, Arka Plan (Always) iznini iste
      // Bu çağrı Android 10+ cihazlarda direkt sistemin "İzin Ayarları" sayfasını açar
      final backgroundStatus = await Permission.locationAlways.request();
      
      if (backgroundStatus.isDenied) {
        // Eğer hala "Always" değilse, kullanıcıyı manuel olarak ikna etmemiz gerekebilir
        print("Kullanıcı Always seçmedi, sadece While In Use var.");
      }
    }
    
    _checkPermissions(); // Durumu güncelle (Tick yeşil yansın)
  },
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
  subtitle: 'Set to "No Restrictions" for background life',
  icon: Icons.battery_charging_full_rounded,
  // EĞER sistem onay veriyorsa VEYA kullanıcı manuel onayladıysa YEŞİL YANSIN
  isGranted: _isBatteryOk || _manualBatteryConfirm, 
  onTap: () async {
    // 1. Önce standart Android diyaloğunu dene
    final status = await Permission.ignoreBatteryOptimizations.request();
    
    if (status.isGranted) {
      _checkPermissions(); // Sistem onayladıysa otomatik yeşil yanar
    } else {
      // 2. Sistem hala kısıtlı diyorsa (Xiaomi vb. üretici engeli), ayarları aç
      await openAppSettings();
      
      // Kullanıcı ayardan dönünce (resumed) _checkPermissions zaten çalışacak.
      // Eğer hala yeşil değilse, kullanıcı bir kez daha bastığında 
      // veya ayardan döndüğünde manuel onayı biz veriyoruz.
      setState(() => _manualBatteryConfirm = true);
    }
  },
  // Sistem izni görmüyorsa ama manuel onay varsa "manuel" ikonunu gizle
  isManual: !_isBatteryOk && !_manualBatteryConfirm, 
),
                      _buildPermissionItem(
                        title: 'Notifications',
                        subtitle: 'Important for request visibility',
                        icon: Icons.notifications_active_rounded,
                        isGranted: _isNotificationOk,
                        onTap: () => Permission.notification.request(),
                      ),
                      const SizedBox(height: 16),
                      _buildSectionTitle("Manufacturer Settings"),
                      _buildPermissionItem(
  title: 'Auto-Start',
  subtitle: 'Allow app to start on device boot',
  icon: Icons.power_settings_new_rounded,
  isGranted: _isAutoStartOk,
  isManual: true,
  onTap: () async {
    await _openManufacturerSetting('autostart');
    setState(() => _isAutoStartOk = !_isAutoStartOk); // Kullanıcı geri gelince yeşil yansın
  },
),
                      _buildPermissionItem(
  title: 'Protected Apps',
  subtitle: 'Keep NCare alive in background memory',
  icon: Icons.app_settings_alt_rounded,
  isGranted: _isProtectedAppOk,
  isManual: true,
  onTap: () async {
  final deviceInfo = await DeviceInfoPlugin().androidInfo;
  if (deviceInfo.manufacturer.toLowerCase().contains('xiaomi')) {
    // Önce tarif et
    _showXiaomiGuide();
    
    // 2 saniye sonra ayarı aç (Kullanıcı diyaloğu okuyabilsin)
    await Future.delayed(const Duration(seconds: 10));
  }

  await _openManufacturerSetting('security');
  setState(() => _isProtectedAppOk = !_isProtectedAppOk);
},
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
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF14B8A6).withOpacity(0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.shield_rounded, color: Color(0xFF14B8A6), size: 32),
        ),
        const SizedBox(height: 12),
        const Text(
        'Permissions',
        style: TextStyle(
          fontSize: 30, // 34 -> 30 (Hala büyük ve heybetli ama yer kaplamıyor)
          fontWeight: FontWeight.w900, 
          color: Colors.white, 
          letterSpacing: -1
        ),
      ),
        const Text(
          'NCare requires these to function in background.',
          style: TextStyle(fontSize: 14, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(color: Color(0xFF5EEAD4), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2),
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
        style: TextStyle(
          fontSize: 16, 
          fontWeight: FontWeight.w900, 
          letterSpacing: 1,
          // İzinler eksikse yazıyı tamamen kaybetmek yerine 
          // beyazın %30-40 şeffaf haliyle gösteriyoruz ki okunsun
          color: _allPermissionsGranted 
              ? Colors.white 
              : Colors.white.withOpacity(0.4), 
        ),
      ),
      ),
    );
  }
}