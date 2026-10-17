import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:ir_blaster_ac/core/config/app_config.dart';
import 'package:ir_blaster_ac/core/services/auth_service.dart';

class AcConfigApiService {
  static Future<Map<String, String>> _headers() async {
    final token = await AuthService.getCookieHeader() ?? '';
    return {
      'Authorization': 'Bearer $token',
      'Cookie': 'auth_token=$token',
      'Content-Type': 'application/json',
    };
  }

  // ── Brands ─────────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> fetchBrands() async {
    try {
      final headers = await _headers();
      final url = '${AppConfig.provisionBaseUrl}/ac/brands';
      final response = await http.get(Uri.parse(url), headers: headers);
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('Error fetching brands: $e');
    }
    return [];
  }

  static Future<bool> createBrand(String brandName, String? description) async {
    try {
      final headers = await _headers();
      final url = '${AppConfig.provisionBaseUrl}/ac/brands';
      debugPrint('📡 [AcConfigApiService] POST $url with brand_name=$brandName');
      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode({
          'brand_name': brandName,
          'description': description,
        }),
      );
      debugPrint('📡 [AcConfigApiService] POST brand status: ${response.statusCode}, body: ${response.body}');
      return response.statusCode == 201 || response.statusCode == 200;
    } catch (e) {
      debugPrint('Error creating brand: $e');
      return false;
    }
  }

  static Future<bool> deleteBrand(int id) async {
    try {
      final headers = await _headers();
      final url = '${AppConfig.provisionBaseUrl}/ac/brands/$id';
      final response = await http.delete(Uri.parse(url), headers: headers);
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error deleting brand: $e');
      return false;
    }
  }

  // ── Models ─────────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> fetchModels() async {
    try {
      final headers = await _headers();
      final url = '${AppConfig.provisionBaseUrl}/ac/models';
      final response = await http.get(Uri.parse(url), headers: headers);
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('Error fetching models: $e');
    }
    return [];
  }

  static Future<Map<String, dynamic>?> createModel(String modelName, String? description, {int? brandId}) async {
    try {
      final headers = await _headers();
      final url = '${AppConfig.provisionBaseUrl}/ac/models';
      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode({
          'model_name': modelName,
          'brand_id': brandId,
          'description': description,
        }),
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        debugPrint('createModel failed status: ${response.statusCode}, body: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error creating model: $e');
    }
    return null;
  }

  static Future<bool> deleteModel(int id) async {
    try {
      final headers = await _headers();
      final url = '${AppConfig.provisionBaseUrl}/ac/models/$id';
      final response = await http.delete(Uri.parse(url), headers: headers);
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error deleting model: $e');
      return false;
    }
  }

  // ── Commands ────────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> fetchCommands({int? brandId, int? modelId}) async {
    try {
      final headers = await _headers();
      var url = '${AppConfig.provisionBaseUrl}/ac/commands';
      final queryParams = <String>[];
      if (brandId != null) queryParams.add('brand_id=$brandId');
      if (modelId != null) queryParams.add('model_id=$modelId');
      if (queryParams.isNotEmpty) {
        url += '?${queryParams.join('&')}';
      }
      final response = await http.get(Uri.parse(url), headers: headers);
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('Error fetching commands: $e');
    }
    return [];
  }

  static Future<bool> createCommand(
    String commandName,
    String? commandType,
    String? description, {
    int? brandId,
    int? modelId,
    String? addressCode,
    String? rawData,
    String? hexCode,
  }) async {
    try {
      final headers = await _headers();
      final url = '${AppConfig.provisionBaseUrl}/ac/commands';
      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode({
          'command_name': commandName,
          'command_type': commandType,
          'description': description,
          'brand_id': brandId,
          'model_id': modelId,
          'address_code': addressCode,
          'raw_data': rawData,
          'hex_code': hexCode,
        }),
      );
      return response.statusCode == 201 || response.statusCode == 200;
    } catch (e) {
      debugPrint('Error creating command: $e');
      return false;
    }
  }

  static Future<bool> updateCommand(
    int id,
    String commandName,
    String? commandType,
    String? description, {
    int? brandId,
    int? modelId,
    String? addressCode,
    String? rawData,
    String? hexCode,
  }) async {
    try {
      final headers = await _headers();
      final url = '${AppConfig.provisionBaseUrl}/ac/commands/$id';
      final response = await http.put(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode({
          'command_name': commandName,
          'command_type': commandType,
          'description': description,
          'brand_id': brandId,
          'model_id': modelId,
          'address_code': addressCode,
          'raw_data': rawData,
          'hex_code': hexCode,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error updating command: $e');
      return false;
    }
  }

  static Future<bool> deleteCommand(int id) async {
    try {
      final headers = await _headers();
      final url = '${AppConfig.provisionBaseUrl}/ac/commands/$id';
      final response = await http.delete(Uri.parse(url), headers: headers);
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error deleting command: $e');
      return false;
    }
  }

  // ── Command Addresses ───────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> fetchCommandAddresses({
    int? brandId,
    int? modelId,
  }) async {
    try {
      final headers = await _headers();
      final queryParams = <String>[];
      if (brandId != null && brandId > 0) queryParams.add('brand_id=$brandId');
      if (modelId != null && modelId > 0) queryParams.add('model_id=$modelId');

      final queryString = queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';
      final url = '${AppConfig.provisionBaseUrl}/ac/addresses$queryString';
      final response = await http.get(Uri.parse(url), headers: headers);
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('Error fetching addresses: $e');
    }
    return [];
  }

  static Future<bool> createCommandAddress({
    required String addressCode,
    String? rawData,
    String? hexCode,
    String? description,
    int? brandId,
    int? modelId,
  }) async {
    try {
      final headers = await _headers();
      final url = '${AppConfig.provisionBaseUrl}/ac/addresses';
      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode({
          'address_code': addressCode,
          'raw_data': rawData,
          'hex_code': hexCode,
          'description': description,
          'brand_id': brandId,
          'model_id': modelId,
        }),
      );
      return response.statusCode == 201 || response.statusCode == 200;
    } catch (e) {
      debugPrint('Error creating address: $e');
      return false;
    }
  }

  static Future<bool> deleteCommandAddress(int id) async {
    try {
      final headers = await _headers();
      final url = '${AppConfig.provisionBaseUrl}/ac/addresses/$id';
      final response = await http.delete(Uri.parse(url), headers: headers);
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error deleting address: $e');
      return false;
    }
  }
}
