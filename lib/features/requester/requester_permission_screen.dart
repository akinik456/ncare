import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:android_intent_plus/android_intent.dart';

import '../../core/role_manager.dart';
import 'package:restart_app/restart_app.dart';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class RequesterPermissionScreen extends StatelessWidget {
  const RequesterPermissionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Senin koyu lacivert/siyah tonun
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Üst Kısım: İkon ve Başlık
              const Icon(Icons.location_on_rounded, size: 80, color: Color(0xFF14B8A6)), // Teal
              const SizedBox(height: 32),
              const Text(
                "Location Access",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              
              // Açıklayıcı Metin (Senin istediğin o "Mesafe" vurgusu)
              const Text(
                "To accurately see your distance from the locator, we need your location permission while using the app.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF94A3B8), // Gri/Mavi tonu
                  fontSize: 16,
                  height: 1.5,
                ),
              ),
              const Spacer(),

              // "OK" Butonu - Senin tasarımdaki FilledButton stili
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: () async {
                    // 1. İzin iste (Sadece WhileInUse)
                    await Permission.locationWhenInUse.request();
                    
                    // 2. İzin versin ya da vermesin (kendi tercihi), Requester Home'a uçur
                    if (context.mounted) {
					Restart.restartApp();
                      Navigator.pushReplacementNamed(context, 'requester_screen');
                    }
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF14B8A6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text(
                    "OK, UNDERSTOOD",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}