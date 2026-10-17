import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:ir_blaster_ac/core/services/local_cache_service.dart';
import 'package:ir_blaster_ac/core/config/app_config.dart';
import 'package:ir_blaster_ac/screens/ac_app/sigin.dart';

/// Handles authentication and session management using ProvisionService API.
class AuthService {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  static bool _isRedirectingToLogin = false;

  static Future<void> logoutAndRedirect() async {
    if (_isRedirectingToLogin) return;
    _isRedirectingToLogin = true;
    try {
      debugPrint('🔐 [AuthService] Logging out and redirecting to SignInPage...');
      await logout();
      final navState = navigatorKey.currentState;
      if (navState != null) {
        await navState.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const SignInPage()),
          (route) => false,
        );
      }
    } finally {
      _isRedirectingToLogin = false;
    }
  }
  // ── Storage keys ────────────────────────────────────────────────────
  static const String _cookieKey = 'session_cookie';
  static const String _emailKey = 'user_email';
  static const String _userDataKey = 'user_data';
  static const String _companyIdKey = 'company_id';
  static const String _bucketKey = 'bucket';
  static const String _siteIdKey = 'site_id';
  static const String _zoneIdKey = 'zone_id';

  static final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(),
  );

  static Future<void> _persistUserData(Map<String, dynamic>? userData) async {
    if (userData == null) return;

    await _storage.write(key: _userDataKey, value: jsonEncode(userData));
    await _storage.write(
      key: _companyIdKey,
      value: extractCompanyId(userData) ?? '',
    );
    await _storage.write(key: _bucketKey, value: extractBucket(userData) ?? '');
    await _storage.write(
      key: _siteIdKey,
      value:
          userData['site']?.toString() ?? userData['siteId']?.toString() ?? '',
    );
    await _storage.write(
      key: _zoneIdKey,
      value:
          userData['zone']?.toString() ?? userData['zoneId']?.toString() ?? '',
    );
  }

  static bool isValidEmail(String email) {
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.trim());
  }

  static String _loginErrorMessage(http.Response response) {
    final serverMessage = _extractResponseMessage(response.body);

    switch (response.statusCode) {
      case 400:
        return serverMessage ?? 'Please check your email and password.';
      case 401:
      case 403:
        return 'Email or password is incorrect.';
      case 404:
        return 'No account found with this email address.';
      case 408:
        return 'The login request timed out. Please try again.';
      case 429:
        return 'Too many login attempts. Please wait and try again.';
      case >= 500:
        return 'Login service is temporarily unavailable. Please try again later.';
      default:
        return serverMessage ?? 'Unable to sign in. Please try again.';
    }
  }

  static String? _extractResponseMessage(String responseBody) {
    if (responseBody.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map) {
        final message =
            decoded['message'] ?? decoded['Message'] ?? decoded['title'];
        if (message != null && message.toString().trim().isNotEmpty) {
          final text = message.toString().trim();
          if (_isTechnicalLoginMessage(text)) return null;
          return text;
        }
      }
    } catch (_) {
      final text = responseBody.trim();
      if (text.isNotEmpty && !_isTechnicalLoginMessage(text)) {
        return text;
      }
    }

    return null;
  }

  static bool _isTechnicalLoginMessage(String message) {
    final lower = message.toLowerCase();
    return lower == 'unauthorized' ||
        lower.contains('status code') ||
        lower.contains('server error') ||
        lower.contains('http');
  }

  /// Performs a real login by hitting the auth service.
  static Future<String?> login(String email, String password) async {
    try {
      final url = AppConfig.loginEndpoint;
      debugPrint('🔐 [AuthService] Attempting login for: $email');
      debugPrint('🔐 [AuthService] Login URL: $url');

      final client = http.Client();
      try {
        // Build the request manually so we can follow redirects for POST
        final request = http.Request('POST', Uri.parse(url));
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode({
          'email': email,
          'password': password,
        });
        request.followRedirects = true;
        request.maxRedirects = 5;

        final streamedResponse =
            await client.send(request).timeout(const Duration(seconds: 10));
        final response = await http.Response.fromStream(streamedResponse);

        debugPrint('🔐 [AuthService] Login Status: ${response.statusCode}');
        debugPrint('🔐 [AuthService] Response URL: ${response.request?.url}');

        if (response.statusCode == 200) {
          final Map<String, dynamic> body = jsonDecode(response.body);

          if (body['status'] == 1) {
            final userData = body['data'];

            // Extract token from set-cookie header or response body
            String token = '';
            if (body['token'] != null) {
              token = body['token'].toString();
            } else if (userData != null &&
                userData is Map &&
                userData['token'] != null) {
              token = userData['token'].toString();
            }

            if (token.isEmpty) {
              String? rawCookie;
              response.headers.forEach((k, v) {
                if (k.toLowerCase() == 'set-cookie') {
                  rawCookie = v;
                }
              });

              if (rawCookie != null) {
                // Support multiple cookies joined by comma or semicolon
                final cookieParts = rawCookie!.split(RegExp(r'[;,]'));
                for (var part in cookieParts) {
                  part = part.trim();
                  if (part.startsWith('auth_token=')) {
                    token = part.substring('auth_token='.length);
                    break;
                  }
                }
              }
            }
            if (token.isEmpty) {
              debugPrint(
                  '⚠️ [AuthService] auth_token not found in cookies or response body. Using fallback "valid_session".');
              token = 'valid_session';
            }

            // Persist session and user details from the REAL response
            await _storage.write(key: _cookieKey, value: token);
            await _storage.write(key: _emailKey, value: email);
            if (userData is Map) {
              await _persistUserData(Map<String, dynamic>.from(userData));
            }

            debugPrint(
                '✅ [AuthService] Login successful. Data persisted for bucket: ${userData['bucket']}');
            return null; // Success
          } else {
            final message = body['message'] ?? body['Message'] ?? body['title'];
            if (message != null && message.toString().trim().isNotEmpty) {
              final text = message.toString().trim();
              if (!_isTechnicalLoginMessage(text)) return text;
            }
            return 'Email or password is incorrect.';
          }
        } else {
          return _loginErrorMessage(response);
        }
      } finally {
        client.close();
      }
    } on TimeoutException {
      debugPrint('❌ [AuthService] Login timeout');
      return 'The login request timed out. Please try again.';
    } catch (e) {
      debugPrint('❌ [AuthService] Login Exception: $e');
      return 'Unable to connect. Please check your internet connection and try again.';
    }
  }

  static bool _isPerformingSilentLogin = false;

  /// Ensures that we have a valid session and user details.
  /// If not, or if the current session is invalid/expired, log out and redirect to sign in.
  static Future<void> ensureAuthenticated() async {
    if (_isPerformingSilentLogin) return;
    _isPerformingSilentLogin = true;
    try {
      final token = await _storage.read(key: _cookieKey);

      if (token == null || token.isEmpty) {
        debugPrint('🔐 [AuthService] No active token.');
        return;
      }

      bool needLogout = false;

      // Double check session validity with the backend verify endpoint.
      final response = await http.get(
        Uri.parse(AppConfig.verifyEndpoint),
        headers: {
          'Cookie': 'auth_token=$token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['status'] != 1) {
          needLogout = true;
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        needLogout = true;
      }

      if (needLogout) {
        debugPrint('🔐 [AuthService] Session invalid or expired. Logging out...');
        await logoutAndRedirect();
      }
    } catch (e) {
      debugPrint('❌ [AuthService] Session verify error: $e');
    } finally {
      _isPerformingSilentLogin = false;
    }
  }

  /// Verifies current session by hitting the verify endpoint.
  static Future<Map<String, dynamic>?> verify() async {
    try {
      final token = await _storage.read(key: _cookieKey);
      if (token == null || token.isEmpty) return null;

      final response = await http.get(
        Uri.parse(AppConfig.verifyEndpoint),
        headers: {
          'Cookie': 'auth_token=$token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['status'] == 1) {
          final data = body['data'];
          if (data is Map) {
            final userData = Map<String, dynamic>.from(data);
            await _persistUserData(userData);
            return userData;
          }
        } else {
          debugPrint('🔐 [AuthService] verify returned status != 1. Logging out...');
          await logoutAndRedirect();
          return null;
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        debugPrint('🔐 [AuthService] verify returned ${response.statusCode}. Logging out...');
        await logoutAndRedirect();
        return null;
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ Verify error: $e');
      return null;
    }
  }

  static Future<String?> getCookieHeader() async {
    await ensureAuthenticated();
    return _storage.read(key: _cookieKey);
  }

  static Future<Map<String, dynamic>?> getUserData() async {
    final raw = await _storage.read(key: _userDataKey);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  static Future<String?> getEmail() async {
    return _storage.read(key: _emailKey);
  }

  static Future<String?> getCompanyId() async {
    return _storage.read(key: _companyIdKey);
  }

  static Future<String?> getBucket() async {
    return _storage.read(key: _bucketKey);
  }

  static Future<String?> getSiteId() async {
    return _storage.read(key: _siteIdKey);
  }

  static Future<String?> getZoneId() async {
    return _storage.read(key: _zoneIdKey);
  }

  static Future<bool> hasStoredSession() async {
    final c = await _storage.read(key: _cookieKey);
    return c != null && c.isNotEmpty;
  }

  /// Extract the active company ID from saved user data.
  static String? extractCompanyId(Map<String, dynamic>? userData) {
    if (userData == null) return null;
    final companyField = userData['company'] ??
        userData['Company'] ??
        userData['companyId'] ??
        userData['company_id'];
    if (companyField == null) return null;

    if (companyField is List && companyField.isNotEmpty) {
      return companyField.first?.toString();
    }

    if (companyField is String) {
      if (companyField.trim().startsWith('[')) {
        try {
          final parsed = jsonDecode(companyField) as List?;
          if (parsed != null && parsed.isNotEmpty) {
            return parsed.first?.toString();
          }
        } catch (_) {
          return companyField;
        }
      }
      return companyField;
    }

    return companyField.toString();
  }

  /// Extracts the bucket value from saved user data.
  static String? extractBucket(Map<String, dynamic>? userData) {
    if (userData == null) return null;
    return userData['Bucket']?.toString() ?? userData['bucket']?.toString();
  }

  /// Extracts the company display name from saved user data.
  static String? extractCompanyName(Map<String, dynamic>? userData) {
    if (userData == null) return null;
    return userData['companyName']?.toString() ??
        userData['CompanyName']?.toString() ??
        userData['company_name']?.toString();
  }

  static Future<void> logout() async {
    await _storage.delete(key: _cookieKey);
    await _storage.delete(key: _emailKey);
    await _storage.delete(key: _userDataKey);
    await _storage.delete(key: _companyIdKey);
    await _storage.delete(key: _bucketKey);
    await _storage.delete(key: _siteIdKey);
    await _storage.delete(key: _zoneIdKey);

    // Also clear the general cache (SharedPreferences)
    await LocalCacheService.clearAll();
  }

  /// Temporarily override the active company/bucket context
  /// (used by Platform Admin when drilling into a specific company).
  static Future<void> setTemporaryContext({
    required String companyId,
    required String bucket,
  }) async {
    await _storage.write(key: _companyIdKey, value: companyId);
    await _storage.write(key: _bucketKey, value: bucket);
  }

  /// Extract the role string from user data JSON.
  static String roleFromUserData(Map<String, dynamic>? userData) {
    if (userData == null) return '';
    return (userData['role'] ?? userData['userRole'] ?? '').toString().trim();
  }

  /// Check if the given role is a platform-level admin.
  static bool isPlatformAdminRole(String role) {
    final r = role.toLowerCase().trim();
    return r == 'platformadmin' ||
        r == 'platform_admin' ||
        r == 'superadmin' ||
        r == 'super_admin' ||
        r == 'platform admin';
  }

  /// Check if the given role is a company-level admin (includes site `admin` role).
  static bool isCompanyAdminRole(String role) {
    final r = role.toLowerCase().trim();
    return r == 'companyadmin' ||
        r == 'company_admin' ||
        r == 'company admin' ||
        r == 'admin';
  }

  /// Check if the given role is a site-level admin ("admin" role with a site assigned).
  static bool isAdminRole(String role) {
    final r = role.toLowerCase().trim();
    return r == 'admin';
  }

  /// Check if the given role is a site-level admin (explicit siteadmin variants only).
  static bool isSiteAdminRole(String role) {
    final r = role.toLowerCase().trim();
    return r == 'siteadmin' || r == 'site_admin' || r == 'site admin';
  }

  /// Persist the active site/company context before opening the employee dashboard.
  static Future<void> setSelectedSiteAndCompany(
    String siteId,
    String companyId, {
    String? zoneId,
    String? bucket,
  }) async {
    await _storage.write(key: _siteIdKey, value: siteId);
    await _storage.write(key: _companyIdKey, value: companyId);
    if (zoneId != null && zoneId.isNotEmpty) {
      await _storage.write(key: _zoneIdKey, value: zoneId);
    }
    if (bucket != null && bucket.isNotEmpty) {
      await _storage.write(key: _bucketKey, value: bucket);
    }
    debugPrint(
        '✅ [AuthService] Selected site=$siteId company=$companyId zone=$zoneId');
  }

  /// Check if the company has access to an AC Monitoring System.
  static Future<bool> checkAcSystemAccess(String companyId) async {
    try {
      debugPrint(
          '🔎 [AuthService] checkAcSystemAccess started. companyId=$companyId');
      final token = await _storage.read(key: _cookieKey);
      if (token == null || token.isEmpty) {
        debugPrint('⚠️ [AuthService] check-ac-access skipped: token missing');
        return false;
      }

      final url =
          '${AppConfig.provisionBaseUrl}/systems/check-ac-access?companyId=${Uri.encodeComponent(companyId)}';
      debugPrint('📡 [AuthService] GET $url');

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Cookie': 'auth_token=$token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      debugPrint(
          '📡 [AuthService] check-ac-access status=${response.statusCode}');
      debugPrint('📡 [AuthService] check-ac-access body=${response.body}');

      if (response.statusCode == 200) {
        try {
          final body = jsonDecode(response.body);
          if (body is Map &&
              (body['hasAcSystem'] == true ||
                  body['hasAccess'] == true ||
                  body['data'] == true)) {
            debugPrint('✅ [AuthService] AC access allowed');
            return true;
          }
        } catch (_) {
          // Response is not JSON (likely HTML from frontend), fall through
        }
      }

      // If the endpoint doesn't exist (404, HTML response, or route collision),
      // fall back to checking the /systems list
      if (response.statusCode == 404 ||
          response.body.trimLeft().startsWith('<!') ||
          _isCheckAcAccessRouteCollision(response)) {
        debugPrint(
            '⚠️ [AuthService] check-ac-access endpoint not available (status=${response.statusCode}). Falling back to /systems list.');
        return _checkAcSystemAccessFromSystems(companyId, token);
      }

      debugPrint('🚫 [AuthService] AC access denied');
      return false;
    } catch (e) {
      debugPrint('❌ [AuthService] checkAcSystemAccess error: $e');
      // On network/parse errors, allow access since login succeeded
      return true;
    }
  }

  static bool _isCheckAcAccessRouteCollision(http.Response response) {
    if (response.statusCode != 400) return false;

    try {
      final body = jsonDecode(response.body);
      return body is Map &&
          body['errors'] is Map &&
          (body['errors'] as Map).containsKey('systemId') &&
          response.body.contains('check-ac-access');
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _checkAcSystemAccessFromSystems(
    String companyId,
    String token,
  ) async {
    try {
      final url =
          '${AppConfig.provisionBaseUrl}/systems?companyId=${Uri.encodeComponent(companyId)}';
      debugPrint('📡 [AuthService] Fallback GET $url');

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Cookie': 'auth_token=$token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      debugPrint(
          '📡 [AuthService] fallback systems status=${response.statusCode}');
      debugPrint('📡 [AuthService] fallback systems body=${response.body}');

      if (response.statusCode != 200 ||
          response.body.trimLeft().startsWith('<!')) {
        debugPrint(
            '⚠️ [AuthService] fallback /systems endpoint unavailable. Allowing access by default.');
        return true;
      }

      final decoded = jsonDecode(response.body);
      final systems = decoded is Map ? decoded['data'] : decoded;
      if (systems is! List) return false;

      final hasAcSystem = systems.any((item) {
        if (item is! Map) return false;
        return _isAcMonitoringSystem(Map<String, dynamic>.from(item));
      });

      debugPrint('🔎 [AuthService] fallback AC system found=$hasAcSystem');
      return hasAcSystem;
    } catch (e) {
      debugPrint('❌ [AuthService] fallback AC access check error: $e');
      return false;
    }
  }

  static bool _isAcMonitoringSystem(Map<String, dynamic> system) {
    final systemType = system['systemType'] ?? system['SystemType'];
    final typeName = systemType is Map
        ? (systemType['name'] ?? systemType['Name'] ?? '').toString()
        : systemType?.toString() ?? '';
    final name =
        (system['name'] ?? system['Name'] ?? system['systemName'] ?? '')
            .toString();

    final searchable = '$typeName $name'.toLowerCase();
    return searchable.contains('ac monitoring') ||
        searchable.contains('ac_monitoring') ||
        searchable.contains('acmonitoring');
  }
}
