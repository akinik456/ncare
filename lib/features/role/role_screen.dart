import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/role_manager.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../setup/app_card.dart';
import '../setup/name_screen.dart';

class RoleScreen extends StatelessWidget {
  const RoleScreen({super.key});

  Future<void> _startNewGroup(BuildContext context) async {
    await RoleManager.setRole("requester");
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isCreatingGroup', true);

    if (!context.mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const NameScreen()),
    );
  }

  Future<void> _select(BuildContext context, String role) async {
    await RoleManager.setRole(role);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isCreatingGroup', false);

    if (!context.mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const NameScreen()),
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
              AppColors.gradientTop,
              AppColors.background,
            ],
            stops: [0.0, 0.9],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 24),

                    const Text(
                      'Lynra Care',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.brand,
                    ),

                    const SizedBox(height: 10),

                    Text(
                      'Choose device role',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.pageTitle.copyWith(fontSize: 32),
                    ),

                    const SizedBox(height: 10),

                    Text(
                      'Select how this device will be used',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.hint.copyWith(fontSize: 16),
                    ),

                    const SizedBox(height: 32),

                    _MainCard(
                      title: 'Create New Group',
                      subtitle: 'Start a fresh Lynra Care group on this device',
                      icon: Icons.group_add_rounded,
                      accentColor: const Color(0xFF8B5CF6),
                      onTap: () => _startNewGroup(context),
                    ),

                    const SizedBox(height: 18),

                    _MainCard(
                      title: 'Locator',
                      subtitle: 'Share location when a request arrives',
                      icon: Icons.phone_android_rounded,
                      accentColor: AppColors.primary,
                      onTap: () => _select(context, "locator"),
                    ),

                    const SizedBox(height: 18),

                    _MainCard(
                      title: 'Requester',
                      subtitle: 'Ask a paired locator for location',
                      icon: Icons.travel_explore_rounded,
                      accentColor: const Color(0xFF38BDF8),
                      onTap: () => _select(context, "requester"),
                    ),

                    const SizedBox(height: 12),
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

class _MainCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final VoidCallback onTap;

  const _MainCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: AppCard(
          padding: EdgeInsets.zero,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: AppColors.black.withOpacity(0.18),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Row(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      color: accentColor.withOpacity(0.12),
                    ),
                    child: Icon(
                      icon,
                      color: accentColor,
                      size: 34,
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: AppTextStyles.sectionTitle.copyWith(
                            fontSize: 20,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: AppTextStyles.hint.copyWith(
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 18,
                    color: accentColor,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}