
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../../core/identity_manager.dart';
import '../../core/role_manager.dart';
import '../../core/auth_service.dart';
import '../../core/fcm_manager.dart';
import '../requester/requester_screen.dart';
import '../locator/locator_permission_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  @override
  void initState() {
    super.initState();
    _loadRole();
    _loadCreateGroupFlag();
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
    if (name.isEmpty) return;

    setState(() => saving = true);

    final deviceId = await IdentityManager.getOrCreateDeviceId();
    final now = FieldValue.serverTimestamp();

    if (role == "requester" && _isCreatingGroup) {
	  await FcmManager.prepareApp();

	  final groupId = const Uuid().v4();
	  final authId = AuthService.currentAuthId;
	  
	  print("SYSTEM: Grup kuruluyor. GroupID: $groupId, AuthID: $authId");

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

	  final prefs = await SharedPreferences.getInstance();
	  await prefs.setBool('isCreatingGroup', false);

	  if (!mounted) return;
	  Navigator.pushReplacement(
		context,
		MaterialPageRoute(builder: (_) => const RequesterScreen()),
	  );
	} else if (role == "requester") {
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
		MaterialPageRoute(builder: (_) => const RequesterScreen()),
	  );
	}else {
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
        ? 'Name shown on locator device'
        : 'Name shown on requester device';
    final helperText = isRequester
        ? 'Enter the name that paired locator devices will see for this phone.'
        : 'Enter the name that requester devices will see for this phone.';
    final hintText = isRequester ? 'Enter requester name' : 'Enter locator name';

    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF020617),
              Color(0xFF020617),
              Color(0xFF0F172A),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(32),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: isRequester
                              ? const [
                                  Color(0xFF1D4ED8),
                                  Color(0xFF2563EB),
                                  Color(0xFF3B82F6),
                                ]
                              : const [
                                  Color(0xFF0F766E),
                                  Color(0xFF0D9488),
                                  Color(0xFF14B8A6),
                                ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (isRequester
                                    ? const Color(0xFF2563EB)
                                    : const Color(0xFF0D9488))
                                .withOpacity(0.20),
                            blurRadius: 28,
                            offset: const Offset(0, 14),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(22),
                              color: Colors.white.withOpacity(0.16),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.16),
                              ),
                            ),
                            child: Icon(
                              isRequester
                                  ? Icons.travel_explore_rounded
                                  : Icons.phone_android_rounded,
                              color: Colors.white,
                              size: 34,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            heroTitle,
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: -0.8,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            helperText,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFE6F2FF),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        color: const Color(0xFF020617),
                        border: Border.all(
                          color: const Color(0xFF334155),
                          width: 1.1,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x100F172A),
                            blurRadius: 20,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            inputTitle,
                            style: const TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF64748B),
                              letterSpacing: -0.4,
                            ),
                          ),
                          const SizedBox(height: 18),
                          TextField(
                            controller: controller,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => saving ? null : _save(),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                            ),
                            decoration: InputDecoration(
                              hintText: hintText,
                              hintStyle: const TextStyle(
                                color: Color(0xFF94A3B8),
                                fontWeight: FontWeight.w600,
                              ),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 18,
                              ),
                              prefixIcon: Icon(
                                isRequester
                                    ? Icons.badge_rounded
                                    : Icons.person_pin_circle_rounded,
                                color: isRequester
                                    ? const Color(0xFF2563EB)
                                    : const Color(0xFF0D9488),
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: const BorderSide(
                                  color: Color(0xFFE2E8F0),
                                  width: 1.1,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: BorderSide(
                                  color: isRequester
                                      ? const Color(0xFF2563EB)
                                      : const Color(0xFF0D9488),
                                  width: 1.6,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: saving ? null : _save,
                              style: FilledButton.styleFrom(
                                backgroundColor: isRequester
                                    ? const Color(0xFF2563EB)
                                    : const Color(0xFF0D9488),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 18),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(22),
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              child: saving
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.4,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Continue'),
                            ),
                          ),
                        ],
                      ),
                    ),
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
