import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../../core/identity_manager.dart';
import '../../core/role_manager.dart';
import '../../core/auth_service.dart';
import '../../core/fcm_manager.dart';
import '../../core/background_engine.dart';
import '../requester/requester_screen.dart';
import '../requester/requester_permission_screen.dart';
import '../locator/locator_permission_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:restart_app/restart_app.dart';

class NameScreen extends StatefulWidget {
  const NameScreen({super.key});

  @override
  State<NameScreen> createState() => _NameScreenState();
}

class _NameScreenState extends State<NameScreen> {
  final controller = TextEditingController();
  bool saving = false;
  String? role;
  bool _isCreatingGroup = false;
  final focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadRole();
    _loadCreateGroupFlag();
	// Sayfa render edildikten hemen sonra focus ister
  Future.delayed(Duration.zero, () {
    if (mounted) focusNode.requestFocus();
  });
  }

  Future<void> _loadCreateGroupFlag() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getBool('isCreatingGroup') ?? false;

    if (!mounted) return;
    setState(() {
      _isCreatingGroup = value;
    });
  }

  Future<void> _loadRole() async {
    final r = await RoleManager.getRole();
    if (!mounted) return;
    setState(() {
      role = r;
    });
  }

  Future<void> _save() async {
    final name = controller.text.trim();
	bool isMaster=false;
    if (name.isEmpty) return;

    setState(() => saving = true);

    final deviceId = await IdentityManager.getOrCreateDeviceId();
    
	await IdentityManager.saveMyName(name);
	
	final now = FieldValue.serverTimestamp();

    if (role == "requester" && _isCreatingGroup) {
      await FcmManager.prepareApp();

      final groupId = const Uuid().v4();
      final authId = AuthService.currentAuthId;
	  isMaster=true;
      
      await IdentityManager.setLocalGroupId(groupId);
      await FirebaseFirestore.instance.collection('groups').doc(groupId).set({
        'groupId': groupId,
        'createdAt': now,
        'isPaid': false,
        'trialExpiresAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 7)),
        ),
        'maxDevicesCount': 10,
        'groupMasterDeviceId': deviceId,
        'groupMasterAuthId': authId,
      });
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .collection('devices')
          .doc(deviceId)
          .set({
        'authId': authId,
        'deviceId': deviceId,
        'groupId': groupId,
        'role': 'requester',
        'name': name,
        'joinedAt': now,
        'active': true,
        'isMaster': true,
      });
      await FirebaseFirestore.instance.collection('requesters').doc(deviceId).set({
        'authId': authId,
        'deviceId': deviceId,
        'role': 'requester',
        'name': name,
        'joinedAt': now,
        'active': true,
        'isMaster': true,
      });
	  await IdentityManager.saveIsMaster(isMaster);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isCreatingGroup', false);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const RequesterPermissionScreen()),
      );
    } else if (role == "requester") {
	isMaster=false;
	await IdentityManager.saveIsMaster(isMaster);
      await FcmManager.prepareApp();
      await FirebaseFirestore.instance.collection('requesters').doc(deviceId).set({
        'authId': AuthService.currentAuthId,
        'deviceId': deviceId,
        'role': 'requester',
        'name': name,
        'joinedAt': now,
        'active': true,
        'isMaster': false,
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isCreatingGroup', false);
      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const RequesterPermissionScreen()),
      );
    } else {
	isMaster=false;
	await IdentityManager.saveIsMaster(isMaster);
      await FcmManager.prepareApp();
      await FirebaseFirestore.instance.collection('locators').doc(deviceId).set({
        'authId': AuthService.currentAuthId,
        'deviceId': deviceId,
        'role': 'locator',
        'name': name,
        'joinedAt': now,
        'active': true,
      });
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LocatorPermissionScreen()),
      );
    }
  }

@override
  Widget build(BuildContext context) {
    final isRequester = role == "requester";

    final heroTitle = isRequester ? 'Requester Setup' : 'Locator Setup';
    final inputTitle = isRequester
        ? 'Name shown on locator'
        : 'Name shown on requester';
    final helperText = isRequester
        ? 'Enter the name that paired locator devices will see for this phone.'
        : 'Enter the name that requester devices will see for this phone.';
    final hintText = isRequester ? 'Enter requester name' : 'Enter locator name';

    return Scaffold(
      backgroundColor: const Color(0xFF020617), // En alt katman rengi [cite: 2]
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0F172A), 
              Color(0xFF020617),
            ],
            stops: [0.0, 0.85],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header Section [cite: 2]
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF14B8A6).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              isRequester ? Icons.travel_explore_rounded : Icons.phone_android_rounded,
                              color: const Color(0xFF14B8A6),
                              size: 32,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            heroTitle,
                            style: const TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: -1),
                          ),
                          Text(
                            helperText,
                            style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF94A3B8),
                                fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),

                      // Input Section [cite: 2]
                      Text(
                        "IDENTIFICATION",
                        style: TextStyle(
                            color: const Color(0xFF5EEAD4),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B).withOpacity(0.4),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFF334155),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              inputTitle,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: controller,
							  focusNode: focusNode, // Node'u bağladık
							  autofocus: true,      // İlk açılışta otomatik focus atar
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => saving ? null : _save(),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                              decoration: InputDecoration(
                                hintText: hintText,
                                hintStyle: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontWeight: FontWeight.w500,
                                ),
                                filled: true,
                                fillColor: const Color(0xFF020617).withOpacity(0.5),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 16,
                                ),
                                prefixIcon: Icon(
                                  isRequester ? Icons.badge_rounded : Icons.person_pin_circle_rounded,
                                  color: const Color(0xFF14B8A6),
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF334155),
                                    width: 1,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF14B8A6),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              // Bottom Bar (Dış Işımalı Buton Bölümü) [cite: 2]
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.transparent, 
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 40,
                      offset: const Offset(0, -10),
                    )
                  ],
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF14B8A6).withOpacity(0.35),
                        blurRadius: 25,
                        spreadRadius: 1,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: FilledButton(
                    onPressed: saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF14B8A6),
                      disabledBackgroundColor: const Color(0xFF1E293B),
                      minimumSize: const Size(double.infinity, 64),
                      shadowColor: Colors.transparent,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    ),
                    child: saving
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                        : const Text(
                            'CONTINUE',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                              color: Colors.white,
                            ),
                          ),
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