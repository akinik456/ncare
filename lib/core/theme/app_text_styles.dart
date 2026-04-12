import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTextStyles {
  // Brand
  static const brand = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.5,
    color: AppColors.primary,
  );

  // Page titles
  static const pageTitle = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w900,
    letterSpacing: -1,
    color: AppColors.textPrimary,
  );

  // Section / field titles
  static const sectionTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  // Input text
  static const inputText = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  // Hint / secondary
  static const hint = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
  );

  // Button text
  static const button = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w900,
    letterSpacing: 1.5,
    color: AppColors.textPrimary,
  );
}

/*
Kullanım örneği

Eski:
style: const TextStyle(
  fontSize: 30,
  fontWeight: FontWeight.w900,
  color: Colors.white,
  letterSpacing: -1,
),

Yeni:
style: AppTextStyles.pageTitle,

Brand için:
const Text(
  'Lynra Care',
  style: AppTextStyles.brand,
),

Input title:

style: AppTextStyles.sectionTitle,

Hint:

hintStyle: AppTextStyles.hint,

Input text:

style: AppTextStyles.inputText,

Button:

style: AppTextStyles.button,



*/