import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../core/api_client.dart';
import '../models/chat_message.dart';
import 'chat_service.dart';
import 'message_notification_service.dart';

class ChatSocketService extends ChangeNotifier with WidgetsBindingObserver {
  static String get _url => ApiClient.socketBaseUrl;
  final ChatService chatService;
  final MessageNotificationService notificationService;
  io.Socket? _socket;
  String? _token;
  String? _conversationId;
  final Set<String> _joinedConversationIds = {};
  bool _connected = false;
  Timer? _typingTimer;
  void Function()? onReconnected;
  Future<void> Function(Map<String, dynamic> command)? onRemoteVibration;

  ChatSocketService(this.chatService, this.notificationService) {
    WidgetsBinding.instance.addObserver(this);
    chatService.addListener(refreshConversationSubscriptions);
  }

  bool get connected => _connected;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _token?.isEmpty != false) return;
    _resumeConnection();
  }

  void _resumeConnection() {
    if (_socket == null) {
      connect();
      return;
    }
    if (_socket!.connected) {
      unawaited(chatService.syncAll());
      return;
    }
    _socket!.connect();
  }

  void connect({String? token, String? userId}) {
    if (token != null && token.isNotEmpty) _token = token;
    if (_socket != null) return;
    _socket = io.io(_url, {
      'path': '/socket.io/',
      'transports': ['websocket', 'polling'],
      'autoConnect': false,
      'reconnection': true,
      'reconnectionAttempts': double.infinity,
      'reconnectionDelay': 1000,
      'reconnectionDelayMax': 10000,
      'timeout': 10000,
      'auth': {if (_token?.isNotEmpty == true) 'token': _token},
    });
    final socket = _socket!;
    socket.onConnect((_) {
      final wasConnected = _connected;
      socket.emitWithAck('auth', {'token': _token}, ack: (response) {
        if (response is Map && response['error'] != null) {
          disconnect();
          return;
        }
        _connected = true;
        _joinedConversationIds.clear();
        _joinKnownConversations();
        notifyListeners();
        unawaited(chatService.syncAll());
        if (wasConnected) onReconnected?.call();
      });
    });
    socket.onDisconnect((_) {
      _connected = false;
      notifyListeners();
    });
    socket.onConnectError((error) => debugPrint('[ChatSocket] 连接失败: $error'));
    socket.on('chat:message', _receive);
    socket.on('remote:vibration', _receiveRemoteVibration);
    socket.connect();
  }

  void _joinKnownConversations() {
    for (final chat in chatService.chatList) {
      _joinConversation(_chatId(chat));
    }
    _joinConversation(_conversationId);
  }

  void _joinConversation(String? id) {
    if (id == null || id.isEmpty || _socket?.connected != true) return;
    if (!_joinedConversationIds.add(id)) return;
    _socket!.emitWithAck('chat:join', id, ack: (response) {
      if (response is Map && response['error'] != null) {
        _joinedConversationIds.remove(id);
        debugPrint('[ChatSocket] 加入会话失败: ${response['error']}');
      }
    });
  }

  String _chatId(Map<String, dynamic> chat) =>
      (chat['id'] ?? chat['conversation_id'] ?? chat['chatId'] ?? '')
          .toString();

  void joinConversation(String id) {
    _conversationId = id;
    _joinConversation(id);
  }

  void refreshConversationSubscriptions() => _joinKnownConversations();

  Future<bool> sendMessage(String chatId, String content,
      {String type = 'text',
      dynamic receiverId,
      String? clientMessageId}) async {
    if (_socket?.connected != true ||
        content.trim().isEmpty ||
        content.length > 5000) {
      return false;
    }
    final completer = Completer<bool>();
    _socket!.emitWithAck('chat:send', {
      'chatId': chatId,
      'content': content,
      'type': type,
      if (receiverId != null) 'receiverId': receiverId,
      if (clientMessageId != null) 'clientMessageId': clientMessageId,
    }, ack: (response) {
      final failed = response is Map && response['error'] != null;
      if (!completer.isCompleted) completer.complete(!failed);
    });
    return completer.future
        .timeout(const Duration(seconds: 8), onTimeout: () => false);
  }

  Future<bool> sendReadReceipt(String chatId, {int? lastReadSeq}) async {
    if (_socket?.connected != true || chatId.isEmpty) return false;
    final completer = Completer<bool>();
    _socket!.emitWithAck('chat:read', {
      'chatId': chatId,
      if (lastReadSeq != null) 'lastReadSeq': lastReadSeq,
    }, ack: (response) {
      final failed = response is Map && response['error'] != null;
      if (!completer.isCompleted) completer.complete(!failed);
    });
    return completer.future
        .timeout(const Duration(seconds: 8), onTimeout: () => false);
  }

  Future<String?> triggerRemoteVibration(String chatId,
      {dynamic receiverId}) async {
    if (_socket?.connected != true) return '实时连接不可用，请稍后重试';
    final completer = Completer<String?>();
    _socket!.emitWithAck('remote:vibration:trigger', {
      'chatId': chatId,
      if (receiverId != null) 'receiverId': receiverId,
    }, ack: (response) {
      if (response is Map && response['error'] != null) {
        completer.complete(response['error'].toString());
      } else {
        completer.complete(null);
      }
    });
    return completer.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () => '远程操控响应超时，请稍后重试',
    );
  }

  void sendTyping(String conversationId, {dynamic receiverId}) {
    _typingTimer?.cancel();
    if (_socket?.connected != true) return;
    _socket!.emit('typing:start', {
      'chatId': conversationId,
      if (receiverId != null) 'receiverId': receiverId,
    });
    _typingTimer = Timer(const Duration(seconds: 1), () {
      stopTyping(conversationId, receiverId: receiverId);
    });
  }

  void stopTyping(String conversationId, {dynamic receiverId}) {
    _typingTimer?.cancel();
    if (_socket?.connected != true) return;
    _socket!.emit('typing:stop', {
      'chatId': conversationId,
      if (receiverId != null) 'receiverId': receiverId,
    });
  }

  void _receive(dynamic raw) {
    try {
      if (raw is! Map) return;
      final map = _map(raw);
      final message = ChatMessage.fromJson(map);
      if (message.content.length > 5000) return;
      final isMine = message.senderIdString.isNotEmpty &&
          message.senderIdString == chatService.currentUserId;
      final messageKey = chatService.conversationKeyForMessage(message);
      final isDuplicate =
          messageKey.isNotEmpty && chatService.hasMessage(messageKey, message);
      final conversationId = chatService.receiveMessage(message);
      if (!isMine && !isDuplicate && conversationId != null) {
        unawaited(notificationService.showMessage(
          message,
          chatIdOverride: conversationId,
        ));
      }
    } catch (error, stackTrace) {
      debugPrint('[ChatSocket] 忽略无效消息: $error\n$stackTrace');
    }
  }

  void _receiveRemoteVibration(dynamic raw) {
    final command = _map(raw);
    if (command.isEmpty) return;
    unawaited(onRemoteVibration?.call(command) ?? Future<void>.value());
  }

  Map<String, dynamic> _map(Map raw) => Map<String, dynamic>.from(
      raw.map((key, value) => MapEntry(key.toString(), value)));

  void disconnect() {
    _typingTimer?.cancel();
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _connected = false;
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    chatService.removeListener(refreshConversationSubscriptions);
    disconnect();
    super.dispose();
  }
}
