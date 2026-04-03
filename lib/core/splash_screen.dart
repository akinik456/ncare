import 'package:flutter/material.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0F172A), // Ana tema rengin
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Uygulama Logon veya şık bir ikon
            Icon(Icons.track_changes_rounded, size: 100, color: Color(0xFF14B8A6)),
            SizedBox(height: 24),
            // Senin o meşhur Teal renginde ince bir yükleme çubuğu
            SizedBox(
              width: 140,
              child: LinearProgressIndicator(
                color: Color(0xFF14B8A6),
                backgroundColor: Color(0xFF1E293B),
                minHeight: 2,
              ),
            ),
            SizedBox(height: 16),
            Text(
              "Initializing System...",
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14, letterSpacing: 1.2),
            ),
          ],
        ),
      ),
    );
  }
}