import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiConfig {
  static const String _kPrefBaseUrl = 'splitup_custom_api_base_url';

  /// Your development machine's local Wi-Fi IP address
  static const String defaultHost = '192.168.1.2';
  static const int defaultPort = 4000;

  static String get defaultBaseUrl {
    if (kIsWeb) {
      return 'http://localhost:$defaultPort';
    }
    return 'http://$defaultHost:$defaultPort';
  }

  static Future<String> getBaseUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final custom = prefs.getString(_kPrefBaseUrl);
      if (custom != null && custom.trim().isNotEmpty) {
        return custom.trim();
      }
    } catch (_) {}
    return defaultBaseUrl;
  }

  static Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefBaseUrl, url.trim());
  }
}
