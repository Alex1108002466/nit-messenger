import 'package:socket_io_client/socket_io_client.dart' as IO;

import '../config.dart';

import 'storage_service.dart';

class SocketService {
  static IO.Socket? _socket;
  static String? _currentChatId;

  static final List<Function(dynamic)> _newMessageListeners = [];
  static final List<Function(dynamic)> _statusChangedListeners = [];
  static final List<Function()> _chatListUpdateListeners = [];
  static final List<Function(dynamic)> _messagesReadListeners = [];
  static final List<Function(dynamic)> _messageDeliveredListeners = [];
  static final List<Function(dynamic)> _typingListeners = [];
  
  static void connect() {
    if (_socket != null) return;

    _socket = IO.io(
      '${Config.baseUrl}',
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setReconnectionAttempts(9999)
          .setReconnectionDelay(2000)
          .setReconnectionDelayMax(5000)
          .build(),
    );

    _socket!.onConnect((_) async {
      print('Socket подключен: ${_socket!.id}');

      final userId = await StorageService.getUserId();
      if (userId != null) {
        _socket!.emit('identify', userId);
      }

      if (_currentChatId != null) {
        _socket!.emit('joinChat', _currentChatId);
      }
    });

    _socket!.onDisconnect((reason) {
      print('Socket отключен, причина: $reason');
    });

    _socket!.onConnectError((error) {
      print('Ошибка подключения сокета: $error');
    });

    // Единая точка входа для события newMessage - рассылаем ВСЕМ подписчикам
    _socket!.on('newMessage', (data) {
      for (final listener in List.of(_newMessageListeners)) {
        listener(data);
      }
    });

    // Обработка смены онлайн-статуса пользователя
    _socket!.on('userStatusChanged', (data) {
      for (final listener in List.of(_statusChangedListeners)) {
        listener(data);
      }
    });

    _socket!.on('userTyping', (data) {
      for (final listener in List.of(_typingListeners)) {
        listener(data);
      }
    });

    // Обработка обновления списка чатов
    _socket!.on('chatListUpdate', (_) {
      for (final listener in List.of(_chatListUpdateListeners)) {
        listener();
      }
    });

    _socket!.on('messagesRead', (data) {
      for (final listener in List.of(_messagesReadListeners)) {
        listener(data);
      }
    });

    _socket!.on('messageDelivered', (data) {
      for (final listener in List.of(_messageDeliveredListeners)) {
        listener(data);
      }
    });

    _socket!.connect();
  }

  static void onChatListUpdate(Function() callback) {
    _chatListUpdateListeners.add(callback);
  }

  static void offChatListUpdate(Function() callback) {
    _chatListUpdateListeners.remove(callback);
  }

  static void onMessagesRead(Function(dynamic) callback) {
    _messagesReadListeners.add(callback);
  }

  static void offMessagesRead(Function(dynamic) callback) {
    _messagesReadListeners.remove(callback);
  }

  static void onMessageDelivered(Function(dynamic) callback) {
    _messageDeliveredListeners.add(callback);
  }

  static void offMessageDelivered(Function(dynamic) callback) {
    _messageDeliveredListeners.remove(callback);
  }

  static void joinChat(String chatId) {
    _currentChatId = chatId;
    if (_socket == null) return;

    if (_socket!.connected) {
      _socket!.emit('joinChat', chatId);
    } else {
      _socket!.onConnect((_) {
        _socket!.emit('joinChat', chatId);
      });
    }
  }

  static void leaveChat(String chatId) {
    if (_currentChatId == chatId) {
      _currentChatId = null;
    }
    _socket?.emit('leaveChat', chatId);
  }

  static void onNewMessage(Function(dynamic) callback) {
    _newMessageListeners.add(callback);
  }

  static void offNewMessage(Function(dynamic) callback) {
    _newMessageListeners.remove(callback);
  }

  static void onUserStatusChanged(Function(dynamic) callback) {
    _statusChangedListeners.add(callback);
  }

  static void offUserStatusChanged(Function(dynamic) callback) {
    _statusChangedListeners.remove(callback);
  }

  static void sendTyping(String chatId, String userId) {
    _socket?.emit('typing', {'chatId': chatId, 'userId': userId});
  }

  static void onUserTyping(Function(dynamic) callback) {
    _typingListeners.add(callback);
  }

  static void offUserTyping(Function(dynamic) callback) {
    _typingListeners.remove(callback);
  }

  static void onReconnected(Function() callback) {
    _socket?.onConnect((_) {
      callback();
    });
  }

  static void disconnect() {
    _currentChatId = null;
    _newMessageListeners.clear();
    _statusChangedListeners.clear();
    _chatListUpdateListeners.clear();
    _messagesReadListeners.clear();
    _messageDeliveredListeners.clear();
    _typingListeners.clear();
    _socket?.disconnect();
    _socket = null;
  }
}