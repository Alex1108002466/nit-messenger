import 'package:flutter/material.dart';

import 'minesweeper_screen.dart';

/// Хаб игр. Пока тут только Сапёр, но список сделан так,
/// чтобы дальше легко добавлять новые офлайн- и онлайн-игры
/// (шахматы с приглашением собеседника и т.д.)
class GamesScreen extends StatelessWidget {
  const GamesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final games = <_GameEntry>[
      _GameEntry(
        title: 'Сапёр',
        subtitle: 'Классика. Играется офлайн',
        icon: Icons.flag_outlined,
        color: Colors.deepOrange,
        enabled: true,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MinesweeperScreen()),
        ),
      ),
      _GameEntry(
        title: 'Крестики-нолики',
        subtitle: 'Скоро',
        icon: Icons.grid_3x3,
        color: Colors.teal,
        enabled: false,
      ),
      _GameEntry(
        title: 'Шахматы',
        subtitle: 'Скоро — с приглашением собеседника',
        icon: Icons.extension_outlined,
        color: Colors.indigo,
        enabled: false,
      ),
      _GameEntry(
        title: '2048',
        subtitle: 'Скоро',
        icon: Icons.apps,
        color: Colors.purple,
        enabled: false,
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Игры')),
      body: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: games.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final game = games[index];
          return Opacity(
            opacity: game.enabled ? 1.0 : 0.5,
            child: Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                leading: CircleAvatar(
                  backgroundColor: game.color.withValues(alpha: 0.15),
                  foregroundColor: game.color,
                  child: Icon(game.icon),
                ),
                title: Text(
                  game.title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(game.subtitle),
                trailing: game.enabled
                    ? const Icon(Icons.chevron_right)
                    : const Icon(Icons.lock_clock_outlined, size: 18),
                onTap: game.enabled ? game.onTap : null,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _GameEntry {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool enabled;
  final VoidCallback? onTap;

  _GameEntry({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.enabled,
    this.onTap,
  });
}