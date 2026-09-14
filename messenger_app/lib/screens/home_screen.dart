import 'package:flutter/material.dart';

import '../config.dart';
import '../services/storage_service.dart';
import '../services/chat_service.dart';
import '../services/socket_service.dart';
import '../widgets/app_drawer.dart';

import 'welcome_screen.dart';
import 'search_user_screen.dart';
import 'chat_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<dynamic> _chats = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    SocketService.connect();
    _loadChats();
    SocketService.onChatListUpdate(_loadChats);
    SocketService.onReconnected(_loadChats);
  }

  @override
  void dispose() {
    SocketService.offChatListUpdate(_loadChats);
    super.dispose();
  }

  void _loadChats() async {
    final result = await ChatService.getChats();

    if (!mounted) return;

    setState(() {
      _isLoading = false;
      if (result['success']) {
        _chats = result['data'];
      }
    });
  }

  void _handleLogout() async {
    SocketService.disconnect();
    await StorageService.deleteToken();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const WelcomeScreen()),
      (route) => false,
    );
  }

  void _openSearch() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SearchUserScreen()),
    );
    // Когда пользователь вернётся с экрана поиска - обновляем список чатов
    _loadChats();
  }

  void _openChat(Map<String, dynamic> chat) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          chatId: chat['id'],
          otherUserId: chat['otherUser']['id'],
          otherUserName: chat['otherUser']['name'],
          otherUserAvatarUrl: chat['otherUser']['avatarUrl'],
        ),
      ),
    );
    _loadChats();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Чаты'),
      ),
      drawer: const AppDrawer(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _chats.isEmpty
              ? const Center(
                  child: Text(
                    'У вас пока нет чатов.\nНажмите + чтобы найти собеседника',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  itemCount: _chats.length,
                  itemBuilder: (context, index) {
                    final chat = _chats[index];
                    final otherUser = chat['otherUser'];

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: otherUser['avatarUrl'] != null
                            ? NetworkImage('${Config.baseUrl}${otherUser['avatarUrl']}')
                            : null,
                        child: otherUser['avatarUrl'] == null
                            ? Text(otherUser['name'][0].toUpperCase())
                            : null,
                      ),
                      title: Text(otherUser['name']),
                      subtitle: Text(
                        chat['lastMessage'] != null
                            ? (chat['lastMessage']['type'] == 'text'
                                ? chat['lastMessage']['text']
                                : chat['lastMessage']['type'] == 'image'
                                    ? '📷 Фото'
                                    : '📎 Файл')
                            : '@${otherUser['username']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: chat['unreadCount'] > 0
                          ? CircleAvatar(
                              radius: 12,
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              child: Text(
                                '${chat['unreadCount']}',
                                style: const TextStyle(fontSize: 11, color: Colors.white),
                              ),
                            )
                          : null,
                      onTap: () => _openChat(chat),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openSearch,
        child: const Icon(Icons.add),
      ),
    );
  }
}