import 'package:flutter/material.dart';

import '../config.dart';
import '../services/storage_service.dart';
import '../services/socket_service.dart';
import '../services/user_service.dart';
import '../screens/welcome_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/games/games_screen.dart';

class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  Map<String, dynamic>? _userData;

  @override
  void initState() {
    super.initState();
    // Если в кеше уже есть данные - показываем их сразу, без ожидания
    if (UserService.cachedMe != null) {
      _userData = UserService.cachedMe;
    }
    _loadUser();
  }

  void _loadUser() async {
    final result = await UserService.getMe();
    if (!mounted) return;
    if (result['success']) {
      setState(() {
        _userData = result['data'];
      });
    }
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Выход из аккаунта'),
          content: const Text('Вы уверены, что хотите выйти?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await _performLogout(context);
              },
              child: const Text(
                'Выйти',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _performLogout(BuildContext context) async {
    SocketService.disconnect();
    await StorageService.deleteToken();
    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const WelcomeScreen()),
      (route) => false,
    );
  }

  Future<void> _openProfile(BuildContext context) async {
    Navigator.pop(context);
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ProfileScreen()),
    );
    // После возврата с экрана профиля - обновляем данные (вдруг что-то поменялось)
    _loadUser();
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundImage: _userData != null && _userData!['avatarUrl'] != null
                        ? NetworkImage('${Config.baseUrl}${_userData!['avatarUrl']}')
                        : null,
                    child: _userData == null || _userData!['avatarUrl'] == null
                        ? Text(
                            _userData != null ? _userData!['name'][0].toUpperCase() : '?',
                            style: const TextStyle(fontSize: 24),
                          )
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _userData != null ? _userData!['name'] : 'Загрузка...',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_userData != null)
                          Text(
                            _userData!['status'],
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.grey,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Профиль'),
            onTap: () => _openProfile(context),
          ),
          ListTile(
            leading: const Icon(Icons.sports_esports_outlined),
            title: const Text('Игры'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const GamesScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Настройки'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
          const Spacer(),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Выйти', style: TextStyle(color: Colors.red)),
            onTap: () => _confirmLogout(context),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}