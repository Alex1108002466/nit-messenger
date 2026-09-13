import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/theme_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeService = context.watch<ThemeService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
      ),
      body: ListView(
        children: [
          _buildSectionHeader('Уведомления'),
          const ListTile(
            leading: Icon(Icons.notifications_outlined),
            title: Text('Push-уведомления'),
            subtitle: Text('Скоро будет доступно'),
            enabled: false,
          ),
          const Divider(),

          _buildSectionHeader('Оформление'),
          SwitchListTile(
            secondary: const Icon(Icons.dark_mode_outlined),
            title: const Text('Тёмная тема'),
            value: themeService.themeMode == ThemeMode.dark,
            onChanged: (_) => themeService.toggleTheme(),
          ),
          const Divider(),

          _buildSectionHeader('Конфиденциальность'),
          const ListTile(
            leading: Icon(Icons.visibility_outlined),
            title: Text('Кто видит статус "в сети"'),
            subtitle: Text('Скоро будет доступно'),
            enabled: false,
          ),
          const Divider(),

          _buildSectionHeader('О приложении'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Версия'),
            subtitle: Text('1.0.0'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
        ),
      ),
    );
  }
}