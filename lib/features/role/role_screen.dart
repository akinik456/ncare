import 'package:flutter/material.dart';
import '../../core/role_manager.dart';
import '../setup/name_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    final theme = Theme.of(context);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1E293B),
  Color(0xFF1E293B),
  Color(0xFF334155),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [

                    const SizedBox(height: 10),

                    Text(
                      "NCare",
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontSize: 38,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -1,
                      ),
                    ),

                    const SizedBox(height: 10),

                    Text(
                      "Choose device role",
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF94A3B8),
                      ),
                    ),

                    const SizedBox(height: 32),

                    /// CREATE GROUP (TOP)
                    _MainCard(
                      title: "Create New Group",
                      subtitle: "Start a fresh NCare group on this device",
                      icon: Icons.group_add_rounded,
                      color: const Color(0xFF6366F1),
                      onTap: () => _startNewGroup(context),
                    ),

                    const SizedBox(height: 18),

                    _MainCard(
                      title: "Locator",
                      subtitle: "Share location when request arrives",
                      icon: Icons.phone_android_rounded,
                      color: const Color(0xFF22C55E),
                      onTap: () => _select(context, "locator"),
                    ),

                    const SizedBox(height: 18),

                    _MainCard(
                      title: "Requester",
                      subtitle: "Ask paired locator for location",
                      icon: Icons.travel_explore_rounded,
                      color: const Color(0xFF38BDF8),
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
  final Color color;
  final VoidCallback onTap;

  const _MainCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            color: const Color(0xFF334155),
            border: Border.all(color: color.withOpacity(.35)),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(.25),
                blurRadius: 25,
                offset: const Offset(0, 10),
              )
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: color.withOpacity(.15),
                  ),
                  child: Icon(icon, color: color, size: 30),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 15,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded,
                    size: 18, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
