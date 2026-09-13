import 'dart:io';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'storage_service.dart';
import 'auth_service.dart';


class UserService {
  static const String baseUrl = AuthService.baseUrl;

  // Простой кеш данных текущего пользователя в памяти приложения
  static Map<String, dynamic>? cachedMe;

  static Future<Map<String, String>> _authHeaders() async {
    final token = await StorageService.getToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, dynamic>> getMe() async {
    final headers = await _authHeaders();
    final url = Uri.parse('$baseUrl/me');

    final response = await http.get(url, headers: headers);
    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      cachedMe = data; // обновляем кеш
      return {'success': true, 'data': data};
    } else {
      return {'success': false, 'error': 'Не удалось загрузить профиль'};
    }
  }

  // Универсальное обновление профиля - можно передать любое подмножество полей
  static Future<Map<String, dynamic>> updateProfile({
    String? name,
    String? username,
    String? status,
  }) async {
    final headers = await _authHeaders();
    final url = Uri.parse('$baseUrl/me');

    final Map<String, dynamic> body = {};
    if (name != null) body['name'] = name;
    if (username != null) body['username'] = username;
    if (status != null) body['status'] = status;

    final response = await http.patch(
      url,
      headers: headers,
      body: jsonEncode(body),
    );
    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      cachedMe = data;
      return {'success': true, 'data': data};
    } else {
      return {'success': false, 'error': data['error'] ?? 'Не удалось обновить профиль'};
    }
  }

  // Загрузить аватар
  static Future<Map<String, dynamic>> uploadAvatar(File imageFile) async {
    final token = await StorageService.getToken();
    final url = Uri.parse('$baseUrl/me/avatar');

    final request = http.MultipartRequest('POST', url);
    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(
      await http.MultipartFile.fromPath('avatar', imageFile.path),
    );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      cachedMe = data;
      return {'success': true, 'data': data};
    } else {
      return {'success': false, 'error': data['error'] ?? 'Не удалось загрузить фото'};
    }
  }

  // Получить публичные данные другого пользователя
  static Future<Map<String, dynamic>> getUserById(String userId) async {
    final headers = await _authHeaders();
    final url = Uri.parse('$baseUrl/users/$userId');

    final response = await http.get(url, headers: headers);
    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      return {'success': true, 'data': data};
    } else {
      return {'success': false, 'error': 'Не удалось загрузить профиль'};
    }
  }
}