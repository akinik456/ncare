import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/device_state_manager.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../home/home_screen.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  bool requestAlertsEnabled = true;
  bool deviceWarningsEnabled = true;

  Future<void> saveRequestAlerts(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('locator_request_alerts', value);

    setState(() {
      requestAlertsEnabled = value;
    });
  }

  Future<void> saveDeviceWarnings(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('locator_device_warnings', value);

    setState(() {
      deviceWarningsEnabled = value;
    });
  }

  Future<void> loadAlertSettings() async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      requestAlertsEnabled = prefs.getBool('locator_request_alerts') ?? true;
      deviceWarningsEnabled = prefs.getBool('locator_device_warnings') ?? true;
    });
  }

  @override
  void initState() {
    super.initState();
    loadAlertSettings();
  }

  Future<void> _completeSetup(BuildContext context) async {
    if (!context.mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 20,
        title: const Text(
          'Lynra Care',
          style: AppTextStyles.brand,
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.gradientTop,
              AppColors.background,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: StreamBuilder<bool>(
                  initialData: DeviceStateManager.instance.isReady,
                  stream: DeviceStateManager.instance.readyStream,
                  builder: (context, snapshot) {
                    final ready = snapshot.data ?? false;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildStatusHero(ready),
                        const SizedBox(height: 16),
                        _buildDeviceCheckCard(context, ready),
                        const SizedBox(height: 16),
                        _buildToggleCard(
                          title: 'Request alerts',
                          subtitle:
                              'Notify when locator receives a location request',
                          value: requestAlertsEnabled,
                          onChanged: saveRequestAlerts,
                        ),
                        const SizedBox(height: 12),
                        _buildToggleCard(
                          title: 'Device warnings',
                          subtitle:
                              'Notify when GPS or permissions are off',
                          value: deviceWarningsEnabled,
                          onChanged: saveDeviceWarnings,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusHero(bool ready) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: ready
              ? const [
                  Color(0xFF0F766E),
                  Color(0xFF0D9488),
                  Color(0xFF14B8A6),
                ]
              : const [
                  Color(0xFFB45309),
                  Color(0xFFD97706),
                  Color(0xFFF59E0B),
                ],
        ),
        boxShadow: [
          BoxShadow(
            color: ready
                ? const Color(0x220F766E)
                : const Color(0x22B45309),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  ready
                      ? Icons.verified_rounded
                      : Icons.warning_amber_rounded,
                  color: AppColors.background,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  ready ? 'Device Ready' : 'Setup Required',
                  style: AppTextStyles.sectionTitle.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            ready
                ? 'This locator device is ready to receive location requests.'
                : 'Location permission and GPS access are required before this device can be used.',
            style: AppTextStyles.hint.copyWith(
              color: Colors.white.withValues(alpha: 0.94),
              height: 1.45,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceCheckCard(BuildContext context, bool ready) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Device check',
            style: AppTextStyles.sectionTitle,
          ),
          const SizedBox(height: 14),
          _SetupInfoRow(
            icon: ready
                ? Icons.check_circle_rounded
                : Icons.gps_off_rounded,
            iconColor: ready ? AppColors.primary : const Color(0xFFF59E0B),
            iconBg: ready
                ? AppColors.primary.withValues(alpha: 0.12)
                : const Color(0xFFF59E0B).withValues(alpha: 0.14),
            title: 'Location access',
            subtitle: ready
                ? 'Permissions and GPS look good.'
                : 'Check location permission and GPS status.',
          ),
          if (ready) ...[
            const SizedBox(height: 16),
            AppButton(
              onPressed: () => _completeSetup(context),
              loading: false,
              text: 'COMPLETE SETUP',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildToggleCard({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2, right: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.sectionTitle,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: AppTextStyles.hint.copyWith(height: 1.35),
                  ),
                ],
              ),
            ),
          ),
          Switch.adaptive(
            value: value,
            activeColor: AppColors.primary,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _SetupInfoRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;

  const _SetupInfoRow({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.sectionTitle.copyWith(
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: AppTextStyles.hint.copyWith(
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}