
import 'package:flutter/material.dart';
import '../../core/role_manager.dart';
import '../home/home_screen.dart';
import '../requester/requester_screen.dart';
import '../locator/locator_permission_screen.dart';

class RoleScreen extends StatelessWidget {
  const RoleScreen({super.key});

  Future<void> _select(BuildContext context, String role) async {
    await RoleManager.setRole(role);

    if (!context.mounted) return;

    if (role == "locator") {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LocatorPermissionScreen()),
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
    final theme = Theme.of(context);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFE8EEF7),
              Color(0xFFF1F5F9),
              Color(0xFFE2E8F0),
            ],
          ),
        ),
        child: SafeArea(
          top: true,
          bottom: true,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 4),

                    Center(
                      child: Container(
                        width: 92,
                        height: 92,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFFE0ECFF),
                              Color(0xFFEEF4FF),
                            ],
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFC7DBFF),
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x141F6FEB),
                              blurRadius: 20,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.place_rounded,
                          size: 44,
                          color: Color(0xFF1F6FEB),
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),

                    Text(
                      'NCare',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.0,
                        color: const Color(0xFF0F172A),
                        height: 1.0,
                      ),
                    ),

                    const SizedBox(height: 6),

                    Text(
                      'Choose how this device will be used',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF334155),
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      'You can continue as a locator device or as a requester device.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        height: 1.45,
                        color: const Color(0xFF64748B),
                      ),
                    ),

                    const SizedBox(height: 28),

                    _RoleCard(
                      icon: Icons.phone_android_rounded,
                      title: 'Locator',
                      subtitle:
                          'This phone sends its location automatically when a request arrives.',
                      accent: const Color(0xFF1F6FEB),
                      onTap: () => _select(context, "locator"),
                    ),

                    const SizedBox(height: 16),

                    _RoleCard(
                      icon: Icons.travel_explore_rounded,
                      title: 'Requester',
                      subtitle:
                          'This phone requests location from a paired locator device.',
                      accent: const Color(0xFF0F766E),
                      onTap: () => _select(context, "requester"),
                    ),

                    const SizedBox(height: 24),

                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.82),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(
                              Icons.info_outline_rounded,
                              size: 18,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'This screen is only for selecting the device role. Existing app logic remains unchanged.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                height: 1.45,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),
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

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x140F172A),
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    icon,
                    color: accent,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.4,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 18,
                  color: accent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
