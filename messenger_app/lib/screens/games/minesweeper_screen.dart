import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

enum _Difficulty { easy, medium, hard }

extension on _Difficulty {
  String get label => switch (this) {
        _Difficulty.easy => 'Лёгкий',
        _Difficulty.medium => 'Средний',
        _Difficulty.hard => 'Сложный',
      };

  int get rows => switch (this) {
        _Difficulty.easy => 10,
        _Difficulty.medium => 13,
        _Difficulty.hard => 17,
      };

  int get cols => 9;

  int get mines => switch (this) {
        _Difficulty.easy => 15,
        _Difficulty.medium => 24,
        _Difficulty.hard => 37,
      };
}

enum _GameStatus { waitingFirstTap, playing, won, lost }

class _Cell {
  bool isMine = false;
  bool revealed = false;
  bool flagged = false;
  int adjacentMines = 0;
}

/// Классический Сапёр. Полностью офлайн, никаких сетевых вызовов —
/// играть можно даже без подключения к интернету.
class MinesweeperScreen extends StatefulWidget {
  const MinesweeperScreen({super.key});

  @override
  State<MinesweeperScreen> createState() => _MinesweeperScreenState();
}

class _MinesweeperScreenState extends State<MinesweeperScreen> {
  _Difficulty _difficulty = _Difficulty.easy;
  late List<List<_Cell>> _board;
  _GameStatus _status = _GameStatus.waitingFirstTap;
  int _flagsPlaced = 0;
  int _revealedSafeCells = 0;
  int _elapsedSeconds = 0;
  Timer? _timer;

  int get _rows => _difficulty.rows;
  int get _cols => _difficulty.cols;
  int get _totalMines => _difficulty.mines;
  int get _totalSafeCells => _rows * _cols - _totalMines;

  @override
  void initState() {
    super.initState();
    _resetBoard();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _resetBoard() {
    _timer?.cancel();
    _board = List.generate(
      _rows,
      (_) => List.generate(_cols, (_) => _Cell()),
    );
    _status = _GameStatus.waitingFirstTap;
    _flagsPlaced = 0;
    _revealedSafeCells = 0;
    _elapsedSeconds = 0;
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsedSeconds++);
    });
  }

  // Мины расставляются только после первого тапа, чтобы игрок
  // никогда не проигрывал первым же ходом.
  void _placeMinesAvoiding(int safeRow, int safeCol) {
    final rand = Random();
    final safeZone = <Point<int>>{};
    for (var dr = -1; dr <= 1; dr++) {
      for (var dc = -1; dc <= 1; dc++) {
        safeZone.add(Point(safeRow + dr, safeCol + dc));
      }
    }

    var placed = 0;
    while (placed < _totalMines) {
      final r = rand.nextInt(_rows);
      final c = rand.nextInt(_cols);
      if (safeZone.contains(Point(r, c))) continue;
      if (_board[r][c].isMine) continue;
      _board[r][c].isMine = true;
      placed++;
    }

    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c < _cols; c++) {
        if (_board[r][c].isMine) continue;
        _board[r][c].adjacentMines = _countAdjacentMines(r, c);
      }
    }
  }

  int _countAdjacentMines(int row, int col) {
    var count = 0;
    for (var dr = -1; dr <= 1; dr++) {
      for (var dc = -1; dc <= 1; dc++) {
        if (dr == 0 && dc == 0) continue;
        final r = row + dr, c = col + dc;
        if (r < 0 || r >= _rows || c < 0 || c >= _cols) continue;
        if (_board[r][c].isMine) count++;
      }
    }
    return count;
  }

  void _onCellTap(int row, int col) {
    if (_status == _GameStatus.won || _status == _GameStatus.lost) return;
    final cell = _board[row][col];
    if (cell.revealed) return;
    // Клетка с флагом от случайного открытия защищена — сначала снимите флаг.
    if (cell.flagged) return;

    if (_status == _GameStatus.waitingFirstTap) {
      _placeMinesAvoiding(row, col);
      _status = _GameStatus.playing;
      _startTimer();
    }

    if (cell.isMine) {
      _revealAllMines();
      _timer?.cancel();
      setState(() => _status = _GameStatus.lost);
      return;
    }

    setState(() {
      _revealCell(row, col);
      _checkWinCondition();
    });
  }

  void _onCellLongPress(int row, int col) {
    if (_status == _GameStatus.won || _status == _GameStatus.lost) return;
    _toggleFlag(row, col);
    _checkWinCondition();
  }

  void _toggleFlag(int row, int col) {
    final cell = _board[row][col];
    if (cell.revealed) return;
    setState(() {
      cell.flagged = !cell.flagged;
      _flagsPlaced += cell.flagged ? 1 : -1;
    });
  }

  // Победа засчитывается, только когда открыты все безопасные клетки
  // И расставлены флаги на всех минах — просто дойти до последней
  // закрытой мины уже недостаточно.
  void _checkWinCondition() {
    if (_status != _GameStatus.playing) return;
    if (_revealedSafeCells < _totalSafeCells) return;

    final allMinesFlagged = _board.every(
      (row) => row.every((cell) => !cell.isMine || cell.flagged),
    );
    if (!allMinesFlagged) return;

    setState(() {
      _status = _GameStatus.won;
      _timer?.cancel();
    });
  }

  // Заливка пустых областей (flood fill) — стандартное поведение Сапёра.
  void _revealCell(int row, int col) {
    final cell = _board[row][col];
    if (cell.revealed || cell.flagged) return;
    cell.revealed = true;
    _revealedSafeCells++;

    if (cell.adjacentMines == 0) {
      for (var dr = -1; dr <= 1; dr++) {
        for (var dc = -1; dc <= 1; dc++) {
          if (dr == 0 && dc == 0) continue;
          final r = row + dr, c = col + dc;
          if (r < 0 || r >= _rows || c < 0 || c >= _cols) continue;
          if (!_board[r][c].revealed && !_board[r][c].isMine) {
            _revealCell(r, c);
          }
        }
      }
    }
  }

  void _revealAllMines() {
    for (final row in _board) {
      for (final cell in row) {
        if (cell.isMine) cell.revealed = true;
      }
    }
  }

  void _restart() {
    setState(_resetBoard);
  }

  Future<void> _pickDifficulty() async {
    final chosen = await showModalBottomSheet<_Difficulty>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Сложность',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            for (final d in _Difficulty.values)
              ListTile(
                title: Text(d.label),
                subtitle: Text('${d.rows}×${d.cols}, мин: ${d.mines}'),
                trailing: d == _difficulty ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, d),
              ),
          ],
        ),
      ),
    );
    if (chosen != null && chosen != _difficulty) {
      setState(() {
        _difficulty = chosen;
        _resetBoard();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final minesLeft = _totalMines - _flagsPlaced;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Сапёр'),
        actions: [
          IconButton(
            tooltip: 'Сложность',
            icon: const Icon(Icons.tune),
            onPressed: _pickDifficulty,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildStatusBar(minesLeft),
          if (_status == _GameStatus.won) _buildBanner('Вы выиграли! 🎉', Colors.green),
          if (_status == _GameStatus.lost) _buildBanner('Бум! Попробуйте ещё раз', Colors.red),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final cellSize = min(
                    constraints.maxWidth / _cols,
                    constraints.maxHeight / _rows,
                  );
                  return Center(
                    child: SizedBox(
                      width: cellSize * _cols,
                      height: cellSize * _rows,
                      child: GridView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: _cols,
                        ),
                        itemCount: _rows * _cols,
                        itemBuilder: (context, index) {
                          final row = index ~/ _cols;
                          final col = index % _cols;
                          return _buildCell(row, col);
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBanner(String text, Color color) {
    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildStatusBar(int minesLeft) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.flag, size: 18, color: Colors.redAccent),
              const SizedBox(width: 4),
              Text('$minesLeft', style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          Row(
            children: [
              const Icon(Icons.timer_outlined, size: 18),
              const SizedBox(width: 4),
              Text('$_elapsedSeconds с'),
            ],
          ),
          TextButton.icon(
            onPressed: _restart,
            icon: const Icon(Icons.refresh),
            label: const Text('Заново'),
          ),
        ],
      ),
    );
  }

  Widget _buildCell(int row, int col) {
    final cell = _board[row][col];
    final theme = Theme.of(context);

    Widget content;
    Color bg;

    if (cell.revealed) {
      bg = theme.colorScheme.surfaceContainerHighest;
      if (cell.isMine) {
        content = const Icon(Icons.brightness_1, size: 14, color: Colors.black87);
        bg = Colors.redAccent.withValues(alpha: 0.5);
      } else if (cell.adjacentMines > 0) {
        content = Text(
          '${cell.adjacentMines}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: _numberColor(cell.adjacentMines),
          ),
        );
      } else {
        content = const SizedBox.shrink();
      }
    } else {
      bg = theme.colorScheme.primaryContainer.withValues(alpha: 0.4);
      content = cell.flagged
          ? const Icon(Icons.flag, size: 14, color: Colors.redAccent)
          : const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: () => _onCellTap(row, col),
      onLongPress: () => _onCellLongPress(row, col),
      child: Container(
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.center,
        child: content,
      ),
    );
  }

  Color _numberColor(int n) => switch (n) {
        1 => Colors.blue,
        2 => Colors.green,
        3 => Colors.red,
        4 => Colors.indigo,
        5 => Colors.brown,
        6 => Colors.cyan,
        7 => Colors.black,
        _ => Colors.grey,
      };
}