import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:restart_app/restart_app.dart';

import '../../core/setup_manager.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_button.dart';

class RequesterPermissionScreen extends StatelessWidget {
  const RequesterPermissionScreen({super.key});

  Future<void> _handleContinue() async {
    await Permission.locationWhenInUse.request();
    await SetupManager.setSetupDone();
    Restart.restartApp();
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
            stops: [0.0, 0.85],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.location_on_rounded,
                          size: 96,
                          color: AppColors.primary,
                        ),
                        const SizedBox(height: 28),
                        Text(
                          'Location Access',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.pageTitle.copyWith(fontSize: 28),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'To accurately see your distance from the locator, we need your location permission while using the app.',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.hint.copyWith(
                            fontSize: 16,
                            height: 1.55,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                AppButton(
                  onPressed: _handleContinue,
                  loading: false,
                  text: 'OK, UNDERSTOOD',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}