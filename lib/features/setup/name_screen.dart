
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../../core/identity_manager.dart';
import '../../core/role_manager.dart';
import '../home/home_screen.dart';
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
      // CREATE GROUP
      final groupId = const Uuid().v4();
      await IdentityManager.setLocalGroupId(groupId);   
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .set({
        'groupId': groupId,
        'createdAt': now,
        'isPaid': false,
        'trialExpiresAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 7)),
        ),
        'maxDevicesCount': 2,
        'groupMasterDeviceId': deviceId,
      });
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .collection('devices')
          .doc(deviceId)
          .set({
        'deviceId': deviceId,
		'groupId': groupId,
        'role': 'requester',
        'name': name,
        'joinedAt': now,
        'active': true,
        'isMaster': true,
      });
      await FirebaseFirestore.instance
          .collection('requesters')
          .doc(deviceId)
          .set({
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
	}
	else if (role == "requester") {
      await FirebaseFirestore.instance
          .collection('requesters')
          .doc(deviceId)
          .set({
        'deviceId': deviceId,
        'role': 'requester',
        'name': name,
        'joinedAt': now,
        'active': true,
        'isMaster': false,
      });
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const RequesterScreen()),
      );
	final prefs = await SharedPreferences.getInstance();
	await prefs.setBool('isCreatingGroup', false);
    } else {
      await FirebaseFirestore.instance
          .collection('locators')
          .doc(deviceId)
          .set({
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
    final title = role == "requester"
        ? "Name shown on locator device"
        : "Name shown on requester device";

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: title,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: saving ? null : _save,
              child: const Text("Continue"),
            )
          ],
        ),
      ),
    );
  }
}
