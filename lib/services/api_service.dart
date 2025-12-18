import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/child.dart';

class ApiService {
  static const String baseUrl = 'https://seraphguardlabs.com';

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
}
