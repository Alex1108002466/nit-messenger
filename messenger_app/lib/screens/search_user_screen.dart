import 'package:flutter/material.dart';

import '../services/chat_service.dart';

import 'chat_screen.dart';

class SearchUserScreen extends StatefulWidget {
  const SearchUserScreen({super.key});

  @override
  State<SearchUserScreen> createState() => _SearchUserScreenState();
}

class _SearchUserScreenState extends State<SearchUserScreen> {
  final _usernameController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  void _handleSearch() async {
    final username = _usernameController.text.trim();

    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите никнейм')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final searchResult = await ChatService.searchUser(username);

    if (!mounted) return;

    if (!searchResult['success']) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(searchResult['error'])),
      );
      return;
    }

    final foundUser = searchResult['data'];

    // Пользователь найден - создаём (или открываем существующий) чат с ним
    final chatResult = await ChatService.createChat(foundUser['id']);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (chatResult['success']) {
      final chat = chatResult['data'];
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ChatScreen(
            chatId: chat['id'],
            otherUserId: foundUser['id'],
            otherUserName: foundUser['name'],
            otherUserAvatarUrl: foundUser['avatarUrl'],
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(chatResult['error'])),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Новый чат'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Никнейм пользователя',
                prefixText: '@',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _handleSearch(),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _handleSearch,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Найти', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}