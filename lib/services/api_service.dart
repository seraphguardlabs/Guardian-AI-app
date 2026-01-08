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
  
  /// Fetch children list for parent dashboard
  Future<Map<String, dynamic>> fetchChildren(String email, String password) async {
    final url = Uri.parse('$baseUrl/api/mobile/children/');
    
    try {
      debugPrint('📥 Fetching children list');
      
      final response = await http.get(
        url,
        headers: {
          'X-Email': email,
          'X-Password': password,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        
        if (data['status'] == 'ok') {
          final childrenList = data['children'] as List? ?? [];
          debugPrint('✅ Children fetched: ${childrenList.length} children');
          
          return {
            'success': true,
            'children': childrenList
                .map((childJson) => Child.fromJson(childJson as Map<String, dynamic>))
                .toList(),
          };
        } else {
          debugPrint('⚠️ Children API returned non-success status');
          return {
            'success': false,
            'error': 'API returned non-success status',
          };
        }
      } else {
        debugPrint('❌ Children fetch failed: ${response.statusCode}');
        return {
          'success': false,
          'error': 'HTTP ${response.statusCode}',
        };
      }
    } catch (e) {
      debugPrint('❌ Children fetch error: $e');
      return {
        'success': false,
        'error': 'Network error: $e',
      };
    }
  }
  
  /// Fetch child metrics (aggregated overview)
  Future<Map<String, dynamic>> fetchChildMetrics(String email, String password, String childHash) async {
    final url = Uri.parse('$baseUrl/api/mobile/child/$childHash/metrics/');
    
    try {
      final response = await http.get(
        url,
        headers: {
          'X-Email': email,
          'X-Password': password,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return {'success': true, 'data': data};
      } else {
        return {'success': false, 'error': 'HTTP ${response.statusCode}'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  /// Fetch screen time trend data
  Future<Map<String, dynamic>> fetchScreenTime(
    String email, 
    String password, 
    String childHash, 
    {String? startDate, String? endDate}
  ) async {
    var url = Uri.parse('$baseUrl/api/mobile/child/$childHash/screen-time/');
    
    // Add date parameters if provided
    if (startDate != null || endDate != null) {
      final queryParams = <String, String>{};
      if (startDate != null) queryParams['start_date'] = startDate;
      if (endDate != null) queryParams['end_date'] = endDate;
      url = url.replace(queryParameters: queryParams);
    }
    
    try {
      final response = await http.get(
        url,
        headers: {
          'X-Email': email,
          'X-Password': password,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return {'success': true, 'data': data};
      } else {
        return {'success': false, 'error': 'HTTP ${response.statusCode}'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  /// Fetch app usage data
  Future<Map<String, dynamic>> fetchAppUsage(String email, String password, String childHash) async {
    final url = Uri.parse('$baseUrl/api/mobile/child/$childHash/app-usage/');
    
    try {
      final response = await http.get(
        url,
        headers: {
          'X-Email': email,
          'X-Password': password,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return {'success': true, 'data': data};
      } else {
        return {'success': false, 'error': 'HTTP ${response.statusCode}'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  /// Fetch location history
  Future<Map<String, dynamic>> fetchLocations(String email, String password, String childHash, {int limit = 100}) async {
    final url = Uri.parse('$baseUrl/api/mobile/child/$childHash/locations/?limit=$limit');
    
    try {
      final response = await http.get(
        url,
        headers: {
          'X-Email': email,
          'X-Password': password,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return {'success': true, 'data': data};
      } else {
        return {'success': false, 'error': 'HTTP ${response.statusCode}'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  /// Fetch site access logs
  Future<Map<String, dynamic>> fetchSiteAccess(String email, String password, String childHash, {String filter = 'all', int limit = 100}) async {
    final url = Uri.parse('$baseUrl/api/mobile/child/$childHash/site-access/?filter=$filter&limit=$limit');
    
    try {
      final response = await http.get(
        url,
        headers: {
          'X-Email': email,
          'X-Password': password,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return {'success': true, 'data': data};
      } else {
        return {'success': false, 'error': 'HTTP ${response.statusCode}'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
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

  /// Update app restrictions for a child
  /// Supports multiple operations: add, update, remove, or full replacement
  Future<Map<String, dynamic>> updateRestrictions({
    required String email,
    required String password,
    required String childHash,
    String? action,  // 'add', 'update', 'remove', or null for full replacement
    String? package,
    double? hours,
    Map<String, double>? restrictedApps,  // For full replacement
  }) async {
    final url = Uri.parse('$baseUrl/api/mobile/child/$childHash/restricted-apps/');
    
    try {
      Map<String, dynamic> requestBody;
      
      if (action != null) {
        // Action-based update (add, update, remove)
        requestBody = {'action': action};
        
        if (action == 'add' || action == 'update') {
          if (package == null || hours == null) {
            return {
              'success': false,
              'error': 'Package and hours are required for $action action'
            };
          }
          requestBody['package'] = package;
          requestBody['hours'] = hours;
        } else if (action == 'remove') {
          if (package == null) {
            return {
              'success': false,
              'error': 'Package is required for remove action'
            };
          }
          requestBody['package'] = package;
        }
      } else {
        // Full replacement
        if (restrictedApps == null) {
          return {
            'success': false,
            'error': 'restrictedApps map is required for full replacement'
          };
        }
        requestBody = {'restricted_apps': restrictedApps};
      }
      
      debugPrint('📤 Updating restrictions for: $childHash');
      debugPrint('   Action: ${action ?? "full_replacement"}');
      
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'X-Email': email,
          'X-Password': password,
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        
        if (data['status'] == 'ok') {
          debugPrint('✅ Restrictions updated successfully');
          return {
            'success': true,
            'message': data['message'],
            'restricted_apps': data['restricted_apps'],
            'total_restricted': data['total_restricted'],
          };
        } else {
          debugPrint('⚠️ Update returned non-success status');
          return {
            'success': false,
            'error': data['message'] ?? 'Update failed',
          };
        }
      } else if (response.statusCode == 401) {
        return {
          'success': false,
          'error': 'Authentication failed. Check email and password.',
        };
      } else if (response.statusCode == 404) {
        return {
          'success': false,
          'error': 'Child not found or restriction not found.',
        };
      } else {
        debugPrint('❌ Restrictions update failed: ${response.statusCode}');
        final errorData = jsonDecode(response.body) as Map<String, dynamic>;
        return {
          'success': false,
          'error': errorData['message'] ?? 'HTTP ${response.statusCode}',
        };
      }
    } catch (e) {
      debugPrint('❌ Restrictions update error: $e');
      return {
        'success': false,
        'error': 'Network error: $e',
      };
    }
  }

  /// Get app restrictions for a child (using mobile API endpoint)
  Future<Map<String, dynamic>> getAppRestrictions({
    required String email,
    required String password,
    required String childHash,
  }) async {
    final url = Uri.parse('$baseUrl/api/mobile/child/$childHash/restricted-apps/');
    
    try {
      debugPrint('📥 Fetching app restrictions for: $childHash');
      
      final response = await http.get(
        url,
        headers: {
          'X-Email': email,
          'X-Password': password,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        
        if (data['status'] == 'ok') {
          debugPrint('✅ App restrictions fetched: ${data['total_restricted']} apps');
          return {
            'success': true,
            'data': data,
          };
        } else {
          return {
            'success': false,
            'error': data['message'] ?? 'Failed to fetch restrictions',
          };
        }
      } else if (response.statusCode == 401) {
        return {
          'success': false,
          'error': 'Authentication failed',
        };
      } else {
        return {
          'success': false,
          'error': 'HTTP ${response.statusCode}',
        };
      }
    } catch (e) {
      debugPrint('❌ Get restrictions error: $e');
      return {
        'success': false,
        'error': 'Network error: $e',
      };
    }
  }

  /// Get exam mode settings for a child
  Future<Map<String, dynamic>> getExamMode({
    required String email,
    required String password,
    required String childHash,
  }) async {
    final url = Uri.parse('$baseUrl/api/mobile/child/$childHash/exam-mode/');
    
    debugPrint('\n🎓 ===== API SERVICE: GET EXAM MODE =====');
    debugPrint('🎓 URL: $url');
    debugPrint('🎓 Child Hash: $childHash');
    debugPrint('🎓 Email provided: ${email.isNotEmpty}');
    debugPrint('🎓 Password provided: ${password.isNotEmpty}');
    
    try {
      // Build headers - only add auth if provided (child devices don't need auth for their own data)
      final headers = <String, String>{};
      if (email.isNotEmpty && password.isNotEmpty) {
        headers['X-Email'] = email;
        headers['X-Password'] = password;
        debugPrint('🎓 Using authenticated request');
      } else {
        debugPrint('🎓 Using unauthenticated request (child device)');
      }
      
      debugPrint('🎓 Sending GET request...');
      final response = await http.get(
        url,
        headers: headers,
      );

      debugPrint('🎓 Response status code: ${response.statusCode}');
      debugPrint('🎓 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        debugPrint('✅ Exam mode retrieved successfully:');
        debugPrint('   - exam_mode: ${data['exam_mode']}');
        debugPrint('   - exam_mode_apps: ${data['exam_mode_apps']}');
        debugPrint('🎓 ===== API CALL COMPLETE =====\n');
        return {
          'success': true,
          'data': data,
        };
      } else {
        debugPrint('❌ HTTP Error: ${response.statusCode}');
        debugPrint('   Response body: ${response.body}');
        debugPrint('🎓 ===== API CALL FAILED =====\n');
        return {
          'success': false,
          'error': 'HTTP ${response.statusCode}: ${response.body}',
        };
      }
    } catch (e) {
      debugPrint('❌ Get exam mode error: $e');
      debugPrint('🎓 ===== API CALL EXCEPTION =====\n');
      return {
        'success': false,
        'error': 'Network error: $e',
      };
    }
  }

  /// Update exam mode settings for a child
  /// Can toggle exam mode on/off and/or update the list of apps to block
  Future<Map<String, dynamic>> updateExamMode({
    required String email,
    required String password,
    required String childHash,
    bool? examMode,
    List<String>? examModeApps,
    String? action,  // 'add_app', 'remove_app'
    String? package,
  }) async {
    final url = Uri.parse('$baseUrl/api/mobile/child/$childHash/exam-mode/');
    
    try {
      Map<String, dynamic> requestBody = {};
      
      if (action != null) {
        requestBody['action'] = action;
        if (package != null) {
          requestBody['package'] = package;
        }
      } else {
        if (examMode != null) {
          requestBody['exam_mode'] = examMode;
        }
        if (examModeApps != null) {
          requestBody['exam_mode_apps'] = examModeApps;
        }
      }
      
      debugPrint('📤 Updating exam mode for: $childHash');
      debugPrint('   Request body: $requestBody');
      
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'X-Email': email,
          'X-Password': password,
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        debugPrint('✅ Exam mode updated successfully');
        return {
          'success': true,
          'data': data,
        };
      } else {
        final errorData = jsonDecode(response.body) as Map<String, dynamic>;
        return {
          'success': false,
          'error': errorData['message'] ?? 'Update failed',
        };
      }
    } catch (e) {
      debugPrint('❌ Update exam mode error: $e');
      return {
        'success': false,
        'error': 'Network error: $e',
      };
    }
  }
}
