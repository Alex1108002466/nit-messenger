import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';

class AuthService {
  static const String baseUrl = '${Config.baseUrl}';

  static Future<Map<String, dynamic>> requestRegistration({
    required String name,
    required String username,
    required String email,
    required String password,
  }) async {
    final url = Uri.parse('$baseUrl/register/request');

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'username': username,
        'email': email,
        'password': password,
      }),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      return {'success': true, 'data': data};
    } else {
      return {'success': false, 'error': data['error'] ?? 'Ошибка регистрации'};
    }
  }

  static Future<Map<String, dynamic>> verifyRegistration({
    required String email,
    required String code,
  }) async {
    final url = Uri.parse('$baseUrl/register/verify');

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'code': code,
      }),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 201) {
      return {'success': true, 'data': data};
    } else {
      return {'success': false, 'error': data['error'] ?? 'Неверный код'};
    }
  }

    static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final url = Uri.parse('$baseUrl/login');

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
      }),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      return {'success': true, 'data': data};
    } else {
      return {'success': false, 'error': data['error'] ?? 'Ошибка входа'};
    }
  }
}