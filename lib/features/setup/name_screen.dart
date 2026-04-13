/*Typography scale (tüm app için kullan)
Brand (Lynra Care) → 22 / W700
Page Title (Locator Setup) → 30 / W900
Section Title (Name visible...) → 15-16 / W700
Input text → 16 / W600
Hint text → 14-15 / W500

primaryColor       = #14B8A6  // Teal
backgroundColor    = #020617  // Midnight
gradientTopColor   = #0F172A  // Dark Navy
cardColor          = #1E293B  // Slate
borderColor        = #334155  // Slate Border
secondaryTextColor = #64748B  // Muted Slate
*/

/*
onboard
	role_screen
	name_screen	
	locator_permission_screen
	requester_permission_screen
main
	requester_screen
	home_screen
settings
	add_locator_screen
	add_place_screen
	pairing_options_screen
	pair_screen
	setup_screen
	
Yeni ekran yaparken:

❌ TextField yazma
❌ FilledButton yazma
❌ Color hex yazma
❌ TextStyle yazma

👉 sadece:

AppInputField
AppButton
AppColors
AppTextStyles	
	
*/
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../../core/identity_manager.dart';
import '../../core/role_manager.dart';
import '../../core/auth_service.dart';
import '../../core/fcm_manager.dart';
import '../../core/background_engine.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_input_field.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
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
        ? 'Name visible to locators'
        : 'Name visible to requesters';
    final hintText = isRequester ? 'Enter requester name' : 'Enter locator name';

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
		  child: Column(
			children: [
			  // 🔼 CONTENT
			  Expanded(
				child: SingleChildScrollView(
				  padding: const EdgeInsets.all(24),
				  child: Column(
					crossAxisAlignment: CrossAxisAlignment.start,
					children: [
					  // 🟢 BRAND + TITLE
					  const Text(
						'Lynra Care',
						style: AppTextStyles.brand,
					  ),
					  const SizedBox(height: 8),
					  Text(
						heroTitle,
						style: AppTextStyles.pageTitle,
					  ),

					  const SizedBox(height: 16),

					  // 🧱 CARD
					  AppCard(
						child: Column(
						  crossAxisAlignment: CrossAxisAlignment.start,
						  children: [
							Text(
							  inputTitle,
							  style: AppTextStyles.sectionTitle,
							),
							const SizedBox(height: 14),

							AppInputField(
							  controller: controller,
							  focusNode: focusNode,
							  hintText: hintText,
							  onSubmitted: saving ? null : _save,
							),
						  ],
						),
					  ),
					],
				  ),
				),
			  ),

			  // 🔽 BOTTOM BUTTON
			  Container(
				padding: const EdgeInsets.all(24),
				decoration: BoxDecoration(
				  boxShadow: [
					BoxShadow(
					  color: AppColors.black.withOpacity(0.2),
					  blurRadius: 40,
					  offset: const Offset(0, -10),
					),
				  ],
				),
				child: AppButton(
				  onPressed: _save,
				  loading: saving,
				  text: 'CONTINUE',
				),
			  ),
			],
		  ),
		),
	  ),
	);
  }
}