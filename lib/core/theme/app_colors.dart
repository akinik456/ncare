import 'package:flutter/material.dart';

class AppColors {
  // 🌑 Background
  static const background = Color(0xFF020617);   // Midnight
  static const gradientTop = Color(0xFF0F172A);  // Dark Navy

  // 🧱 Surfaces
  static const card = Color(0xFF1E293B);         // Slate
  static const border = Color(0xFF334155);       // Slate Border

  // ✏️ Text
  static const textPrimary = Colors.white;
  static const textSecondary = Color(0xFF64748B); // Muted Slate

  // 🎯 Brand
  static const primary = Color(0xFF14B8A6);      // Teal

  // 🖤 Extras
  static const black = Colors.black;
}

/*
3. Kullanım (örnek)

Eskisi ❌

color: Color(0xFF14B8A6),

Yenisi ✅

color: AppColors.primary,

Gradient kullanım

decoration: const BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      AppColors.gradientTop,
      AppColors.background,
    ],
    stops: [0.0, 0.85],
  ),
),

*/

