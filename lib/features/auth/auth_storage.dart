import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthStorage {
  static const _storage = FlutterSecureStorage();

  static Future<String?> safeRead(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      debugPrint('SECURE STORAGE READ FAILED: $key -> $e');
      await _storage.deleteAll();
      return null;
    }
  }

  static Future<void> safeWrite({
    required String key,
    required String value,
  }) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      debugPrint('SECURE STORAGE WRITE FAILED: $key -> $e');
      await _storage.deleteAll();
      rethrow;
    }
  }

  static Future<void> safeDelete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
      debugPrint('SECURE STORAGE DELETE FAILED: $key -> $e');
      await _storage.deleteAll();
    }
  }
}