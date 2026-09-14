import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:photo_view/photo_view.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../config.dart';
import '../services/chat_service.dart';
import '../services/storage_service.dart';
import '../services/socket_service.dart';
import '../services/user_service.dart';
import '../services/download_service.dart';

import 'contact_profile_screen.dart';
import 'attachment_preview_screen.dart';
import 'full_screen_image.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String otherUserId;
  final String otherUserName;
  final String? otherUserAvatarUrl;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserAvatarUrl,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final Set<String> _deliveredMessageIds = {};
  final GlobalKey _unreadDividerKey = GlobalKey();

  List<dynamic> _messages = [];
  String? _myUserId;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _firstUnreadMessageId;
  bool _isOtherUserTyping = false;
  Timer? _typingTimer;
  Timer? _stopTypingIndicatorTimer;
  bool? _otherUserOnline;
  String? _otherUserLastSeen;

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    return _scrollController.position.pixels <= 100;
  }

  @override
  void initState() {
    super.initState();
    _init();
    _scrollController.addListener(_onScroll);
    _messageController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    SocketService.leaveChat(widget.chatId);
    SocketService.offNewMessage(_handleIncomingMessage);
    SocketService.offUserStatusChanged(_handleStatusChanged);
    SocketService.offMessagesRead(_handleMessagesRead);
    SocketService.offMessageDelivered(_handleMessageDelivered);
    SocketService.offUserTyping(_handleUserTyping);
    _scrollController.removeListener(_onScroll);
    _messageController.removeListener(_onTextChanged);
    _typingTimer?.cancel();
    _stopTypingIndicatorTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _init() async {
    _myUserId = await StorageService.getUserId();
    await _loadInitialMessages();
    await _loadOtherUserStatus();
    await ChatService.markAsRead(widget.chatId);

    SocketService.joinChat(widget.chatId);
    SocketService.onNewMessage(_handleIncomingMessage);
    SocketService.onReconnected(_handleReconnected);
    SocketService.onUserStatusChanged(_handleStatusChanged);
    SocketService.onMessagesRead(_handleMessagesRead);
    SocketService.onMessageDelivered(_handleMessageDelivered);
    SocketService.onUserTyping(_handleUserTyping);
  }

  Future<void> _loadOtherUserStatus() async {
    final result = await UserService.getUserById(widget.otherUserId);
    if (!mounted) return;
    if (result['success']) {
      setState(() {
        _otherUserOnline = result['data']['isOnline'];
        _otherUserLastSeen = result['data']['lastSeen'];
      });
    }
  }

  void _handleStatusChanged(dynamic data) {
    if (!mounted) return;
    if (data['userId'] != widget.otherUserId) return;
    setState(() {
      _otherUserOnline = data['isOnline'];
      if (data['lastSeen'] != null) {
        _otherUserLastSeen = data['lastSeen'];
      }
    });
  }

  void _handleUserTyping(dynamic data) {
    if (!mounted) return;
    if (data['userId'] != widget.otherUserId) return;

    setState(() {
      _isOtherUserTyping = true;
    });

    _stopTypingIndicatorTimer?.cancel();
    _stopTypingIndicatorTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() {
        _isOtherUserTyping = false;
      });
    });
  }

  void _handleMessagesRead(dynamic data) {
    if (!mounted) return;
    if (data['chatId'] != widget.chatId) return;
    if (data['readByUserId'] == _myUserId) return;

    setState(() {
      for (var i = 0; i < _messages.length; i++) {
        if (_messages[i]['senderId'] == _myUserId) {
          _messages[i] = Map<String, dynamic>.from(_messages[i]);
          _messages[i]['status'] = 'read';
        }
      }
    });
  }

  void _handleMessageDelivered(dynamic data) {
    if (!mounted) return;
    if (data['chatId'] != widget.chatId) return;

    final messageId = data['messageId'];
    _deliveredMessageIds.add(messageId);

    setState(() {
      final index = _messages.indexWhere((m) => m['id'] == messageId);
      if (index != -1 && _messages[index]['status'] != 'read') {
        _messages[index] = Map<String, dynamic>.from(_messages[index]);
        _messages[index]['status'] = 'delivered';
      }
    });
  }

  void _scrollToInitialPosition() {
    if (_firstUnreadMessageId == null) {
      // Нет непрочитанных - сразу в самый низ
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });
      return;
    }

    // Есть непрочитанные - точно прокручиваем к разделителю через его реальное положение
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToUnreadDivider();
    });
  }

  void _scrollToUnreadDivider() {
    final context = _unreadDividerKey.currentContext;
    if (context == null) {
      // Разделитель ещё не отрисован - попробуем ещё раз чуть позже
      Future.delayed(const Duration(milliseconds: 50), _scrollToUnreadDivider);
      return;
    }

    Scrollable.ensureVisible(
      context,
      alignment: 0.5, // разделитель окажется примерно по центру видимой области
      duration: Duration.zero,
    );
  }

  void _onScroll() {
    // При reverse:true "долистал до старых сообщений" означает pixels
    // приближается к maxScrollExtent
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMoreMessages();
    }
  }

  void _handleReconnected() {
    if (!mounted) return;
    print('Переподключение обнаружено - обновляем историю сообщений');
    _refreshMessages();
  }

  void _handleIncomingMessage(dynamic data) {
    if (!mounted) return;
    if (data['senderId'] == _myUserId) return;

    final wasNearBottom = _isNearBottom();

    setState(() {
      _messages.insert(0, data);
      _firstUnreadMessageId = null;
    });

    if (wasNearBottom) {
      _scrollToBottom();
    }

    ChatService.markAsRead(widget.chatId);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  void _handleSend() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();

    // Временный id для отслеживания сообщения до получения ответа от сервера
    final tempId = DateTime.now().millisecondsSinceEpoch.toString();
    final tempMessage = {
      'id': tempId,
      'text': text,
      'type': 'text',
      'senderId': _myUserId,
      'createdAt': DateTime.now().toIso8601String(),
      'status': 'sending',
    };

    setState(() {
      _messages.insert(0, tempMessage);
    });
    _scrollToBottom();

    final result = await ChatService.sendMessage(widget.chatId, text);

    if (!mounted) return;

    if (result['success']) {
      setState(() {
        final index = _messages.indexWhere((m) => m['id'] == tempId);
        if (index != -1) {
          final realMessage = Map<String, dynamic>.from(result['data']);
          realMessage['status'] =
              _deliveredMessageIds.contains(realMessage['id']) ? 'delivered' : 'sent';
          _messages[index] = realMessage;
        }
      });
    } else {
      setState(() {
        _messages.removeWhere((m) => m['id'] == tempId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['error'])),
      );
    }
  }

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_outlined),
                title: const Text('Фото из галереи'),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndSendImage();
                },
              ),
              ListTile(
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: const Text('Файл'),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndSendFile();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _pickAndSendImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (pickedFile == null) return;

    final file = File(pickedFile.path);
    if (!mounted) return;

    final caption = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => AttachmentPreviewScreen(file: file, type: 'image'),
      ),
    );

    if (caption == null) return; // пользователь отменил (нажал "назад")

    await _uploadAndSend(file, 'image', caption: caption);
  }

  void _pickAndSendFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.single.path == null) return;

    final file = File(result.files.single.path!);
    if (!mounted) return;

    final caption = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => AttachmentPreviewScreen(file: file, type: 'file'),
      ),
    );

    if (caption == null) return;

    await _uploadAndSend(file, 'file', caption: caption);
  }

  void _applyStatusToOwnMessages(List<dynamic> messages, String? otherUserLastReadAt) {
    for (final msg in messages) {
      if (msg['senderId'] == _myUserId) {
        if (otherUserLastReadAt != null &&
            DateTime.parse(msg['createdAt'])
                .isBefore(DateTime.parse(otherUserLastReadAt))) {
          msg['status'] = 'read';
        } else {
          msg['status'] = msg['status'] ?? 'sent';
        }
      }
    }
  }

  void _onTextChanged() {
    if (_messageController.text.isEmpty) return;

    if (_typingTimer == null || !_typingTimer!.isActive) {
      SocketService.sendTyping(widget.chatId, _myUserId ?? '');
      _typingTimer = Timer(const Duration(seconds: 2), () {});
    }
  }

  Future<void> _loadInitialMessages() async {
    final result = await ChatService.getMessages(widget.chatId);

    if (!mounted) return;

    if (result['success']) {
      final data = result['data'];
      final List<dynamic> loadedMessages = data['messages'];
      final String? lastReadAt = data['lastReadAt'];
      final String? otherUserLastReadAt = data['otherUserLastReadAt'];

      String? firstUnreadId;
      if (lastReadAt != null) {
        final lastReadDate = DateTime.parse(lastReadAt);
        for (final msg in loadedMessages) {
          final msgDate = DateTime.parse(msg['createdAt']);
          if (msg['senderId'] != _myUserId && msgDate.isAfter(lastReadDate)) {
            firstUnreadId = msg['id'];
            break;
          }
        }
      } else {
        for (final msg in loadedMessages) {
          if (msg['senderId'] != _myUserId) {
            firstUnreadId = msg['id'];
            break;
          }
        }
      }

      _applyStatusToOwnMessages(loadedMessages, otherUserLastReadAt);

      final reversedMessages = loadedMessages.reversed.toList();

      setState(() {
        _isLoading = false;
        _messages = reversedMessages;
        _hasMore = data['hasMore'] ?? false;
        _firstUnreadMessageId = firstUnreadId;
      });

      _scrollToInitialPosition();
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMoreMessages() async {
    if (_messages.isEmpty) return;

    setState(() => _isLoadingMore = true);

    final oldestMessageId = _messages.last['id'];
    final result = await ChatService.getMessages(widget.chatId, before: oldestMessageId);

    if (!mounted) return;

    if (result['success']) {
      final data = result['data'];
      final List<dynamic> olderMessages = data['messages'];
      final String? otherUserLastReadAt = data['otherUserLastReadAt'];

      _applyStatusToOwnMessages(olderMessages, otherUserLastReadAt);

      final reversedOlder = olderMessages.reversed.toList();

      setState(() {
        _messages = [..._messages, ...reversedOlder];
        _hasMore = data['hasMore'] ?? false;
        _isLoadingMore = false;
      });
    } else {
      setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _refreshMessages() async {
    final result = await ChatService.getMessages(widget.chatId);
    if (!mounted) return;
    if (result['success']) {
      final data = result['data'];
      final List<dynamic> loadedMessages = data['messages'];
      final String? otherUserLastReadAt = data['otherUserLastReadAt'];

      _applyStatusToOwnMessages(loadedMessages, otherUserLastReadAt);

      setState(() {
        _messages = loadedMessages.reversed.toList();
        _hasMore = data['hasMore'] ?? false;
        // _firstUnreadMessageId НЕ трогаем - переподключение не должно возвращать разделитель
      });
    }
  }

  Future<void> _uploadAndSend(File file, String type, {String? caption}) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Загрузка...')),
    );

    final uploadResult = await ChatService.uploadChatFile(file);

    if (!mounted) return;

    if (!uploadResult['success']) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(uploadResult['error'])),
      );
      return;
    }

    final fileData = uploadResult['data'];

    final sendResult = await ChatService.sendAttachmentMessage(
      chatId: widget.chatId,
      type: fileData['type'],
      fileUrl: fileData['fileUrl'],
      fileName: fileData['fileName'],
      text: caption,
    );

    if (!mounted) return;

    if (sendResult['success']) {
      setState(() {
        final realMessage = Map<String, dynamic>.from(sendResult['data']);
        realMessage['status'] =
            _deliveredMessageIds.contains(realMessage['id']) ? 'delivered' : 'sent';
        _messages.insert(0, realMessage);
      });
      _scrollToBottom();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sendResult['error'])),
      );
    }
  }

  String _formatLastSeen(String? lastSeen) {
    if (lastSeen == null) return '';
    final dateTime = DateTime.parse(lastSeen).toLocal();
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'был(а) в сети только что';
    } else if (difference.inMinutes < 60) {
      return 'был(а) в сети ${difference.inMinutes} мин назад';
    } else if (difference.inHours < 24) {
      return 'был(а) в сети ${difference.inHours} ч назад';
    } else {
      return 'был(а) в сети ${dateTime.day}.${dateTime.month}.${dateTime.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ContactProfileScreen(userId: widget.otherUserId),
              ),
            );
          },
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundImage: widget.otherUserAvatarUrl != null
                    ? NetworkImage('${Config.baseUrl}${widget.otherUserAvatarUrl}')
                    : null,
                child: widget.otherUserAvatarUrl == null
                    ? Text(widget.otherUserName[0].toUpperCase(), style: const TextStyle(fontSize: 14))
                    : null,
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(widget.otherUserName),
                  if (_isOtherUserTyping)
                    Text(
                      'печатает...',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.primary,
                        fontStyle: FontStyle.italic,
                      ),
                    )
                  else if (_otherUserOnline != null)
                    Text(
                      _otherUserOnline! ? 'в сети' : _formatLastSeen(_otherUserLastSeen),
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? const Center(
                        child: Text(
                          'Сообщений пока нет.\nНапишите первым!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        padding: const EdgeInsets.all(12),
                        itemCount: _messages.length + (_isLoadingMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          // При reverse:true последний элемент списка отрисовывается наверху экрана
                          if (_isLoadingMore && index == _messages.length) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }

                          final message = _messages[index];
                          final isMe = message['senderId'] == _myUserId;
                          final showUnreadDivider =
                              message['id'] == _firstUnreadMessageId;

                          // В reverse-списке "разделитель перед сообщением" визуально
                          // означает "разделитель ПОСЛЕ него" в порядке отрисовки
                          return Column(
                            children: [
                              if (showUnreadDivider) _buildUnreadDivider(),
                              _MessageBubble(message: message, isMe: isMe),
                            ],
                          );
                        },
                      ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildUnreadDivider() {
    return Container(
      key: _unreadDividerKey,
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Text(
        'Непрочитанные сообщения',
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: 'Сообщение...',
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(24)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.attach_file),
                    onPressed: _showAttachmentOptions,
                  ),
                ),
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => _handleSend(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _handleSend,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool isMe;

  const _MessageBubble({required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final type = message['type'] ?? 'text';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: type == 'image'
            ? const EdgeInsets.all(4)
            : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isMe
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildContent(context, type),
            const SizedBox(height: 2),
            _buildTimeAndStatus(context),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeAndStatus(BuildContext context) {
    final textColor = isMe
        ? Theme.of(context).colorScheme.onPrimary
        : Theme.of(context).colorScheme.onSurface;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _formatTime(message['createdAt']),
          style: TextStyle(fontSize: 11, color: textColor.withOpacity(0.7)),
        ),
        if (isMe) ...[
          const SizedBox(width: 4),
          _buildStatusIcon(context, textColor),
        ],
      ],
    );
  }

  Widget _buildStatusIcon(BuildContext context, Color textColor) {
    final status = message['status'] ?? 'sent';

    if (status == 'sending') {
      return Icon(Icons.access_time, size: 14, color: textColor.withOpacity(0.7));
    } else if (status == 'read') {
      return const Icon(Icons.done_all, size: 16, color: Colors.lightBlueAccent);
    } else if (status == 'delivered') {
      return Icon(Icons.done_all, size: 16, color: textColor.withOpacity(0.7));
    } else {
      return Icon(Icons.done, size: 16, color: textColor.withOpacity(0.7));
    }
  }

  Widget _buildContent(BuildContext context, String type) {
    final textColor = isMe
        ? Theme.of(context).colorScheme.onPrimary
        : Theme.of(context).colorScheme.onSurface;

    if (type == 'image') {
      final fileUrl = message['fileUrl'];
      final fullUrl = '${Config.baseUrl}$fileUrl';
      final caption = message['text'];

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => FullScreenImage(imageUrl: fullUrl),
                ),
              );
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 1,
                child: CachedNetworkImage(
                  imageUrl: fullUrl,
                  width: 200,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: const Center(child: Icon(Icons.broken_image)),
                  ),
                ),
              ),
            ),
          ),
          if (caption != null && caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4, right: 4),
              child: Text(caption, style: TextStyle(color: textColor)),
            ),
        ],
      );
    }

    if (type == 'file') {
      final fileName = message['fileName'] ?? 'Файл';
      final fileUrl = message['fileUrl'];
      final fullUrl = '${Config.baseUrl}$fileUrl';
      final caption = message['text'];

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => _openOrDownloadFile(context, fullUrl, fileName),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.insert_drive_file, color: textColor),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    fileName,
                    style: TextStyle(color: textColor),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.download, size: 18, color: textColor),
              ],
            ),
          ),
          if (caption != null && caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(caption, style: TextStyle(color: textColor)),
            ),
        ],
      );
    }

    return Text(
      message['text'] ?? '',
      style: TextStyle(color: textColor),
    );
  }

  void _openOrDownloadFile(BuildContext context, String url, String fileName) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Скачивание...')),
    );

    final result = await DownloadService.downloadFile(url, fileName);

    if (result['success']) {
      OpenFilex.open(result['path']);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['error'])),
      );
    }
  }

  String _formatTime(String createdAt) {
    final dateTime = DateTime.parse(createdAt).toLocal();
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
