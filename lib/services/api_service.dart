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
        final data = jsonDecode(response.body);
        final childrenList = data['children'] as List? ?? [];
        return {
          'success': true,
          'token': data['token'],
          'children': childrenList
              .map((childJson) => Child.fromJson(childJson))
              .toList(),
        };
      } else {
        final errorData = jsonDecode(response.body);
        return {
          'success': false,
          'error': errorData['error'] ?? 'Login failed',
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
