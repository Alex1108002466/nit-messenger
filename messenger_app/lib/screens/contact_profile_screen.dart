import 'package:flutter/material.dart';

import '../config.dart';
import '../services/user_service.dart';

import 'full_screen_image.dart';

class ContactProfileScreen extends StatefulWidget {
  final String userId;

  const ContactProfileScreen({super.key, required this.userId});

  @override
  State<ContactProfileScreen> createState() => _ContactProfileScreenState();
}

class _ContactProfileScreenState extends State<ContactProfileScreen> {
  Map<String, dynamic>? _userData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  void _loadUser() async {
    final result = await UserService.getUserById(widget.userId);

    if (!mounted) return;

    setState(() {
      _isLoading = false;
      if (result['success']) {
        _userData = result['data'];
      }
    });
  }

  void _openFullAvatar() {
    if (_userData!['avatarUrl'] == null) return;

    final fullUrl = '${Config.baseUrl}${_userData!['avatarUrl']}';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FullScreenImage(imageUrl: fullUrl),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _userData == null
              ? const Center(child: Text('Не удалось загрузить профиль'))
              : ListView(
                  padding: const EdgeInsets.all(24.0),
                  children: [
                    Center(
                      child: GestureDetector(
                        onTap: _openFullAvatar,
                        child: CircleAvatar(
                          radius: 60,
                          backgroundImage: _userData!['avatarUrl'] != null
                              ? NetworkImage(
                                  '${Config.baseUrl}${_userData!['avatarUrl']}',
                                )
                              : null,
                          child: _userData!['avatarUrl'] == null
                              ? Text(
                                  _userData!['name'][0].toUpperCase(),
                                  style: const TextStyle(fontSize: 40),
                                )
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: Text(
                        _userData!['name'],
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Center(
                      child: Text(
                        '@${_userData!['username']}',
                        style: const TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('О себе'),
                      subtitle: Text(_userData!['status']),
                    ),
                  ],
                ),
    );
  }
}