import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/child.dart';
import '../models/websocket_data.dart';
import '../models/restrictions_data.dart';

class ApiService {
  static const String baseUrl = 'https://seraphguardlabs.com';
  static const String restrictionsBaseUrl = 'https://seraphguardlabs.com';

  Future<Map<String, dynamic>> login(String email, String password) async {
    final url = Uri.parse('$baseUrl/api/login/');
    
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        
        // Handle different response formats like PCA
        if (data['status'] == 'ok') {
          final childrenList = data['children'] as List? ?? [];
          return {
            'success': true,
            'token': '',
            'children': childrenList
                .map((childJson) => Child.fromJson(childJson as Map<String, dynamic>))
                .toList(),
          };
        }
        
        // Standard format with token
        final childrenList = data['children'] as List? ?? [];
        return {
          'success': true,
          'token': data['token'] ?? '',
          'children': childrenList
              .map((childJson) => Child.fromJson(childJson as Map<String, dynamic>))
              .toList(),
        };
      } else {
        final errorData = jsonDecode(response.body) as Map<String, dynamic>;
        return {
          'success': false,
          'error': errorData['error'] ?? errorData['message'] ?? errorData['detail'] ?? 'Login failed',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Network error: $e',
      };
    }
  }

  /// HTTP Fallback: Send data via POST when WebSocket is unavailable
  Future<Map<String, dynamic>> sendDataViaHttp({
    required String childHash,
    ScreenTimeData? screenTimeData,
    LocationData? locationData,
    SiteAccessData? siteAccessData,
  }) async {
    final url = Uri.parse('$baseUrl/api/ingest/');
    
    try {
      final payload = <String, dynamic>{};
      
      // Add screen time info
      if (screenTimeData != null) {
        payload['screen_time_info'] = {
          'child_hash': childHash,
          ...screenTimeData.toJson(),
        };
      }
      
      // Add location info
      if (locationData != null) {
        payload['location_info'] = {
          'child_hash': childHash,
          ...locationData.toJson(),
        };
      }
      
      // Add site access info
      if (siteAccessData != null) {
        payload['site_access_info'] = {
          'child_hash': childHash,
          ...siteAccessData.toJson(),
        };
      }
      
      debugPrint('📤 HTTP Fallback: Sending data to $url');
      debugPrint('📦 Payload: ${jsonEncode(payload)}');
      
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('✅ HTTP Fallback: Data sent successfully');
        final responseData = jsonDecode(response.body) as Map<String, dynamic>;
        return {
          'success': true,
          'data': responseData,
        };
      } else {
        debugPrint('❌ HTTP Fallback: Failed with status ${response.statusCode}');
        final errorData = jsonDecode(response.body) as Map<String, dynamic>;
        return {
          'success': false,
          'error': errorData['error'] ?? errorData['message'] ?? 'Failed to send data',
        };
      }
    } catch (e) {
      debugPrint('❌ HTTP Fallback: Network error: $e');
      return {
        'success': false,
        'error': 'Network error: $e',
      };
    }
  }

  /// Batch send multiple data types via HTTP
  Future<Map<String, dynamic>> batchSendData({
    required String childHash,
    required List<Map<String, dynamic>> batchData,
  }) async {
    final url = Uri.parse('$baseUrl/api/ingest/');
    
    try {
      debugPrint('📤 HTTP Batch: Sending ${batchData.length} items');
      
      final results = [];
      for (final data in batchData) {
        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(data),
        );
        
        results.add({
          'status': response.statusCode,
          'success': response.statusCode == 200 || response.statusCode == 201,
        });
        
        // Small delay between requests to avoid overwhelming the server
        await Future.delayed(const Duration(milliseconds: 100));
      }
      
      final successCount = results.where((r) => r['success'] == true).length;
      debugPrint('✅ HTTP Batch: $successCount/${batchData.length} sent successfully');
      
      return {
        'success': successCount == batchData.length,
        'total': batchData.length,
        'successful': successCount,
        'results': results,
      };
    } catch (e) {
      debugPrint('❌ HTTP Batch: Error: $e');
      return {
        'success': false,
        'error': 'Batch send error: $e',
      };
    }
  }
  
  /// Fetch app restrictions for a child
  Future<Map<String, dynamic>> fetchRestrictions(String childHash) async {
    final url = Uri.parse('$restrictionsBaseUrl/api/blocked-apps/$childHash/');
    
    try {
      debugPrint('📥 Fetching restrictions for: $childHash');
      
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        
        if (data['status'] == 'success') {
          final restrictedApps = data['restricted_apps'] as Map<String, dynamic>? ?? {};
          debugPrint('✅ Restrictions fetched: ${restrictedApps.length} apps');
          
          return {
            'success': true,
            'restrictions': RestrictionsData.fromJson(restrictedApps),
          };
        } else {
          debugPrint('⚠️ Restrictions API returned non-success status');
          return {
            'success': false,
            'error': 'API returned non-success status',
          };
        }
      } else {
        debugPrint('❌ Restrictions fetch failed: ${response.statusCode}');
        return {
          'success': false,
          'error': 'HTTP ${response.statusCode}',
        };
      }
    } catch (e) {
      debugPrint('❌ Restrictions fetch error: $e');
      return {
        'success': false,
        'error': 'Network error: $e',
      };
    }
  }
}
