import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/user_service.dart';

import 'full_screen_image.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _userData;
  bool _isLoading = true;

  bool _isEditingName = false;
  bool _isEditingUsername = false;
  bool _isEditingStatus = false;

  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _statusController = TextEditingController();

  @override
  void initState() {
    super.initState();

    // Если есть кеш - показываем сразу, без ожидания
    if (UserService.cachedMe != null) {
      _userData = UserService.cachedMe;
      _isLoading = false;
      _nameController.text = _userData!['name'];
      _usernameController.text = _userData!['username'];
      _statusController.text = _userData!['status'];
    }

    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _statusController.dispose();
    super.dispose();
  }

  void _loadProfile() async {
    final result = await UserService.getMe();

    if (!mounted) return;

    setState(() {
      _isLoading = false;
      if (result['success']) {
        _userData = result['data'];
        if (!_isEditingName) _nameController.text = _userData!['name'];
        if (!_isEditingUsername) _usernameController.text = _userData!['username'];
        if (!_isEditingStatus) _statusController.text = _userData!['status'];
      }
    });
  }

  void _saveField({String? name, String? username, String? status}) async {
    final result = await UserService.updateProfile(
      name: name,
      username: username,
      status: status,
    );

    if (!mounted) return;

    if (result['success']) {
      setState(() {
        _userData = result['data'];
        _isEditingName = false;
        _isEditingUsername = false;
        _isEditingStatus = false;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['error'])),
      );
    }
  }

  void _pickAndUploadAvatar() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );

    if (pickedFile == null) return;

    final imageFile = File(pickedFile.path);

    if (!mounted) return;

    // Показываем индикатор загрузки
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Загружаем фото...')),
    );

    final result = await UserService.uploadAvatar(imageFile);

    if (!mounted) return;

    if (result['success']) {
      setState(() {
        _userData = result['data'];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Аватар обновлён')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['error'])),
      );
    }
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
                      child: Stack(
                        children: [
                          GestureDetector(
                            onTap: () {
                              if (_userData!['avatarUrl'] == null) return;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => FullScreenImage(
                                    imageUrl:
                                        'https://nit-messenger.duckdns.org${_userData!['avatarUrl']}',
                                  ),
                                ),
                              );
                            },
                            child: CircleAvatar(
                              radius: 50,
                              backgroundImage: _userData!['avatarUrl'] != null
                                  ? NetworkImage(
                                      'https://nit-messenger.duckdns.org${_userData!['avatarUrl']}',
                                    )
                                  : null,
                              child: _userData!['avatarUrl'] == null
                                  ? Text(
                                      _userData!['name'][0].toUpperCase(),
                                      style: const TextStyle(fontSize: 36),
                                    )
                                  : null,
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: _pickAndUploadAvatar,
                              child: CircleAvatar(
                                radius: 18,
                                backgroundColor: Theme.of(context).colorScheme.primary,
                                child: const Icon(
                                  Icons.camera_alt,
                                  size: 18,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    _buildEditableField(
                      label: 'Имя',
                      value: _userData!['name'],
                      controller: _nameController,
                      isEditing: _isEditingName,
                      onEditToggle: () => setState(() => _isEditingName = true),
                      onCancel: () {
                        setState(() {
                          _isEditingName = false;
                          _nameController.text = _userData!['name'];
                        });
                      },
                      onSave: () => _saveField(name: _nameController.text.trim()),
                    ),
                    const SizedBox(height: 16),

                    _buildEditableField(
                      label: 'Никнейм',
                      value: '@${_userData!['username']}',
                      controller: _usernameController,
                      isEditing: _isEditingUsername,
                      prefixText: '@',
                      onEditToggle: () => setState(() => _isEditingUsername = true),
                      onCancel: () {
                        setState(() {
                          _isEditingUsername = false;
                          _usernameController.text = _userData!['username'];
                        });
                      },
                      onSave: () => _saveField(username: _usernameController.text.trim()),
                    ),
                    const SizedBox(height: 16),

                    _buildEditableField(
                      label: 'Статус',
                      value: _userData!['status'],
                      controller: _statusController,
                      isEditing: _isEditingStatus,
                      onEditToggle: () => setState(() => _isEditingStatus = true),
                      onCancel: () {
                        setState(() {
                          _isEditingStatus = false;
                          _statusController.text = _userData!['status'];
                        });
                      },
                      onSave: () => _saveField(status: _statusController.text.trim()),
                    ),

                    const SizedBox(height: 24),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.email_outlined),
                      title: const Text('Email'),
                      subtitle: Text(_userData!['email']),
                    ),
                  ],
                ),
    );
  }

  Widget _buildEditableField({
    required String label,
    required String value,
    required TextEditingController controller,
    required bool isEditing,
    required VoidCallback onEditToggle,
    required VoidCallback onCancel,
    required VoidCallback onSave,
    String? prefixText,
  }) {
    if (isEditing) {
      return Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: label,
                prefixText: prefixText,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.check, color: Colors.green),
            onPressed: onSave,
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.red),
            onPressed: onCancel,
          ),
        ],
      );
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        label,
        style: const TextStyle(fontSize: 13, color: Colors.grey),
      ),
      subtitle: Text(
        value,
        style: const TextStyle(fontSize: 16),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.edit, size: 20),
        onPressed: onEditToggle,
      ),
    );
  }
}