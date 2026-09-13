import 'dart:io';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'storage_service.dart';
import 'auth_service.dart';


class ChatService {
  static const String baseUrl = AuthService.baseUrl;

  // Вспомогательный метод - собирает заголовки с токеном
  static Future<Map<String, String>> _authHeaders() async {
    final token = await StorageService.getToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // Поиск пользователя по username
  static Future<Map<String, dynamic>> searchUser(String username) async {
    final headers = await _authHeaders();
    final url = Uri.parse('$baseUrl/users/search/$username');

    final response = await http.get(url, headers: headers);
    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      return {'success': true, 'data': data};
    } else {
      return {'success': false, 'error': data['error'] ?? 'Пользователь не найден'};
    }
  }

  // Создать чат с пользователем (или получить существующий)
  static Future<Map<String, dynamic>> createChat(String otherUserId) async {
    final headers = await _authHeaders();
    final url = Uri.parse('$baseUrl/chats');

    final response = await http.post(
      url,
      headers: headers,
      body: jsonEncode({'userId': otherUserId}),
    );
    final data = jsonDecode(response.body);

    if (response.statusCode == 201) {
      return {'success': true, 'data': data};
    } else {
      return {'success': false, 'error': data['error'] ?? 'Не удалось создать чат'};
    }
  }

  // Получить список своих чатов
  static Future<Map<String, dynamic>> getChats() async {
    final headers = await _authHeaders();
    final url = Uri.parse('$baseUrl/chats');

    final response = await http.get(url, headers: headers);
    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      return {'success': true, 'data': data};
    } else {
      return {'success': false, 'error': 'Не удалось загрузить чаты'};
    }
  }

  // Получить сообщения чата (с пагинацией)
  static Future<Map<String, dynamic>> getMessages(String chatId, {String? before}) async {
    final headers = await _authHeaders();
    var url = '$baseUrl/chats/$chatId/messages?limit=30';
    if (before != null) {
      url += '&before=$before';
    }

    final response = await http.get(Uri.parse(url), headers: headers);
    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      return {'success': true, 'data': data};
    } else {
      return {'success': false, 'error': 'Не удалось загрузить сообщения'};
    }
  }

  // Отметить чат как прочитанный
  static Future<void> markAsRead(String chatId) async {
    final headers = await _authHeaders();
    final url = Uri.parse('$baseUrl/chats/$chatId/read');
    await http.post(url, headers: headers);
  }

  // Отправить сообщение
  static Future<Map<String, dynamic>> sendMessage(String chatId, String text) async {
    final headers = await _authHeaders();
    final url = Uri.parse('$baseUrl/chats/$chatId/messages');

    final response = await http.post(
      url,
      headers: headers,
      body: jsonEncode({'text': text}),
    );
    final data = jsonDecode(response.body);

    if (response.statusCode == 201) {
      return {'success': true, 'data': data};
    } else {
      return {'success': false, 'error': data['error'] ?? 'Не удалось отправить сообщение'};
    }
  }

  // Загрузить файл (изображение или документ) на сервер
  static Future<Map<String, dynamic>> uploadChatFile(File file) async {
    final token = await StorageService.getToken();
    final url = Uri.parse('$baseUrl/upload/chat-file');

    final request = http.MultipartRequest('POST', url);
    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(
      await http.MultipartFile.fromPath('file', file.path),
    );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      return {'success': true, 'data': data};
    } else {
      return {'success': false, 'error': data['error'] ?? 'Не удалось загрузить файл'};
    }
  }

  // Отправить сообщение с вложением (после того как файл уже загружен)
  static Future<Map<String, dynamic>> sendAttachmentMessage({
    required String chatId,
    required String type,
    required String fileUrl,
    required String fileName,
    String? text,
  }) async {
    final headers = await _authHeaders();
    final url = Uri.parse('$baseUrl/chats/$chatId/messages');

    final body = <String, dynamic>{
      'type': type,
      'fileUrl': fileUrl,
      'fileName': fileName,
    };
    if (text != null && text.trim().isNotEmpty) {
      body['text'] = text.trim();
    }

    final response = await http.post(
      url,
      headers: headers,
      body: jsonEncode(body),
    );
    final data = jsonDecode(response.body);

    if (response.statusCode == 201) {
      return {'success': true, 'data': data};
    } else {
      return {'success': false, 'error': data['error'] ?? 'Не удалось отправить файл'};
    }
  }
}