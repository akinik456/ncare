import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:restart_app/restart_app.dart';

import '../../core/role_manager.dart';
import '../../core/setup_manager.dart';
import '../home/home_screen.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';


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
	await SetupManager.setSetupDone();
    Restart.restartApp();
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
        "3. LynraCare şalterini aktif edin.",
        style: TextStyle(color: Color(0xFF94A3B8)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("ANLADIM, AÇ", style: TextStyle(color: AppColors.primary)),
        ),
      ],
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
			  AppColors.background,
			  AppColors.gradientTop,
			],
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
        print("LynraCareKullanıcı Always seçmedi, sadece While In Use var.");
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
  // Bir kez basıldıysa artık sorgusuz sualsiz YEŞİL
  isGranted: _isBatteryOk || _manualBatteryConfirm, 
  onTap: () async {
    // Zaten yeşilse (işlem tamamlanmışsa) bir daha bir şey yapma
    if (_isBatteryOk || _manualBatteryConfirm) return;

    // 1. Standart Android diyaloğunu (iki ikonlu ekranı) aç
    await Permission.ignoreBatteryOptimizations.request();
    
    // 2. Kullanıcı o ekrandan hangi ikonla ne yaparsa yapsın, 
    // geri geldiğinde doğrudan YEŞİL yakıyoruz.
    setState(() => _manualBatteryConfirm = true);
  },
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
  subtitle: 'Enable LynraCare in Autostart list',
  icon: Icons.power_settings_new_rounded,
  isGranted: _isAutoStartOk,
  onTap: () async {
    // 1. Önce kullanıcıya ne yapacağını anlatan Dialog'u gösteriyoruz
    showDialog(
      context: context,
      barrierDismissible: false, // Kullanıcı dışarı basıp kapatamasın
      builder: (BuildContext context) {
        // 5 saniye sonra otomatik kapanması için bir Timer kuruyoruz
        Future.delayed(const Duration(seconds: 5), () {
          if (Navigator.canPop(context)) {
            Navigator.pop(context);
          }
        });

        return AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.info_outline, color: AppColors.primary),
              SizedBox(width: 10),
              Text("Action Required", style: TextStyle(color: Colors.white)),
            ],
          ),
          content: const Text(
            "In the opening screen, please find 'LynraCare' and turn the switch ON to ensure background reliability.\n\nThis window will close in 5 seconds...",
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 16),
          ),
        );
      },
    );

    // 2. 5 saniye bekle ve sonra ayar sayfasını aç
    await Future.delayed(const Duration(seconds: 5));
    
    // 3. Ayar sayfasını aç
    await _openManufacturerSetting('autostart');
    
    // 4. Geri döndüğünde yeşili yak
    setState(() => _isAutoStartOk = true);
  },
),
                      _buildPermissionItem(
  title: 'Memory Lock (Protected)',
  subtitle: 'Prevent system from killing LynraCare',
  icon: Icons.app_settings_alt_rounded,
  isGranted: _isProtectedAppOk,
  onTap: () async {
    showDialog(
      context: context,
      barrierDismissible: false, // Butona basmadan çıkamasın
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Row(
            children: [
              Icon(Icons.lock_clock_rounded, color: AppColors.primary),
              SizedBox(width: 12),
              Text("Memory Protection", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          content: const Text(
            "To keep LynraCare running in the background, please follow these steps:\n\n"
            "• Xiaomi: Security app > Boost Speed > Settings (top right) > App Lock > Enable LynraCare.\n"
            "• Others: Open 'Recent Apps' screen, long press LynraCare or swipe down, and tap the 'Lock' icon.\n\n"
            "This ensures the system won't close the app to save RAM.",
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 15, height: 1.5),
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                setState(() => _isProtectedAppOk = true);
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("I UNDERSTAND", style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ],
        );
      },
    );
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
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.shield_rounded, color: AppColors.primary, size: 32),
        ),
        const SizedBox(height: 12),
        const Text(
        'Permissions',
        style: AppTextStyles.pageTitle,
      ),
        const Text(
          'LynraCare requires these to function in background.',
          style: AppTextStyles.hint,
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        title.toUpperCase(),
        style: AppTextStyles.hint.copyWith(
  color: AppColors.primary,
  fontSize: 11,
  fontWeight: FontWeight.w800,
  letterSpacing: 1.2,
),
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
          color: isGranted ? AppColors.primary.withOpacity(0.05) : const Color(0xFF1E293B).withOpacity(0.4),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isGranted ? AppColors.primary.withOpacity(0.5) : const Color(0xFF334155),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: isGranted ? AppColors.primary : const Color(0xFF64748B), size: 26),
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
                color: isGranted ? AppColors.primary : const Color(0xFF475569),
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
          backgroundColor: AppColors.primary,
          disabledBackgroundColor: const Color(0xFF1E293B),
          minimumSize: const Size(double.infinity, 64),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        child: _busy
            ? const CircularProgressIndicator(color: Colors.white)
            : Text(
        _allPermissionsGranted ? 'CONTINUE' : 'GRANT REQUIRED PERMISSIONS',
        style: TextStyle(
          fontSize: 20, 
          fontWeight: FontWeight.w900, 
          letterSpacing: 1.5,
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