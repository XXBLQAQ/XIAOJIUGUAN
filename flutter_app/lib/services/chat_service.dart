import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../models/chat_message.dart';
import 'local_chat_database.dart';

class ChatService extends ChangeNotifier {
  final ApiClient _api = ApiClient();
  final Map<String, List<ChatMessage>> _messages = {};
  final Map<String, int> _lastSeq = {};
  final Set<String> _groupKeys = {};
  List<Map<String, dynamic>> _chatList = [];
  bool _loading = false;
  String? _userId;
  String? _activeConversationId;
  final LocalChatDatabase _localDatabase = LocalChatDatabase();
  Future<void>? _storageReady;
  Future<void> _persistQueue = Future<void>.value();
  bool _syncing = false;

  List<Map<String, dynamic>> get chatList => List.unmodifiable(_chatList);
  List<String> get groupIds => _groupKeys.toList();
  bool get loading => _loading;
  String? get currentUserId => _userId;
  List<ChatMessage> messagesFor(String key) =>
      List.unmodifiable(_messages[key] ?? []);

  String? conversationIdForUser(dynamic userId) {
    final target = userId?.toString();
    if (target == null || target.isEmpty) return null;
    for (final chat in _chatList) {
      final id = _chatId(chat);
      final members = chat['members'];
      if (id.isEmpty || members is! List) continue;
      if (members.map((item) => item.toString()).contains(target)) return id;
    }
    return null;
  }

  Future<String?> getOrCreatePrivateChat(dynamic userId) async {
    final existing = conversationIdForUser(userId);
    if (existing != null) return existing;
    final target = userId?.toString();
    if (target == null || target.isEmpty) return null;
    try {
      final response =
          await _api.post('/chats', data: {'targetUserId': target});
      final payload = _payload(response.data);
      if (payload is! Map) return null;
      final chat = Map<String, dynamic>.from(payload);
      final id = _chatId(chat);
      if (id.isEmpty) return null;
      _upsertChat(chat);
      notifyListeners();
      return id;
    } catch (error) {
      debugPrint('[Chat] 创建私聊会话失败: $error');
      return null;
    }
  }

  Future<void> updateChatSetting(
      String chatId, String field, bool value) async {
    if (chatId.isEmpty || (field != 'unread' && field != 'pinned')) return;
    final response =
        await _api.put('/chat-settings/$chatId', data: {field: value});
    final payload = _payload(response.data);
    final index = _chatList.indexWhere((chat) => _chatId(chat) == chatId);
    if (index >= 0) {
      _chatList[index][field] = payload is Map && payload[field] is bool
          ? payload[field] == true
          : value;
      if (field == 'unread' && value == false) {
        _chatList[index]['unread_count'] = 0;
      }
    }
    _sortChats();
    notifyListeners();
  }

  Future<void> markConversationRead(String chatId) async {
    if (chatId.isEmpty) return;
    _activeConversationId = chatId;
    await updateChatSetting(chatId, 'unread', false);
  }

  void clearActiveConversation(String chatId) {
    if (_activeConversationId == chatId) _activeConversationId = null;
  }

  int lastMessageSeq(String key) => _lastSeq[key] ?? 0;

  static bool isGroupChat(Map<dynamic, dynamic> chat) =>
      chat['group_id'] != null ||
      chat['groupId'] != null ||
      chat['is_group'] == true ||
      chat['isGroup'] == true ||
      chat['type'] == 'group';

  Future<void> setUserId(dynamic id) async {
    final nextUserId = id?.toString();
    if (_userId == nextUserId) return;
    await _persistQueue;
    _userId = nextUserId;
    _messages.clear();
    _lastSeq.clear();
    _groupKeys.clear();
    _chatList = [];
    _activeConversationId = null;
    _storageReady = null;
    await _localDatabase.setUserId(nextUserId);
    _storageReady = Future<void>.value();
    notifyListeners();
  }

  Future<void> _initStorage() {
    return _storageReady ??= Future<void>(() async {
      try {
        await _localDatabase.setUserId(_userId);
        await _localDatabase.messagesFor('__init__');
      } catch (e) {
        debugPrint('[Chat] 初始化本地数据库失败: $e');
      }
    });
  }

  Future<void> loadGroups() async {
    _groupKeys.clear();
    notifyListeners();
  }

  String _chatId(Map<String, dynamic> chat) =>
      (chat['id'] ?? chat['conversation_id'] ?? chat['chatId'] ?? '')
          .toString();

  void _upsertChat(Map<String, dynamic> chat) {
    final id = _chatId(chat);
    final index = _chatList.indexWhere((item) => _chatId(item) == id);
    if (index < 0) {
      _chatList.add(chat);
    } else {
      _chatList[index] = {..._chatList[index], ...chat};
    }
    _sortChats();
  }

  void _updateChatSummary(String key, ChatMessage message) {
    final index = _chatList.indexWhere((chat) => _chatId(chat) == key);
    if (index < 0) {
      _chatList.add({
        'id': key,
        'members': [message.senderId, message.receiverId],
        'name': message.senderNickname,
      });
    }

    final chat = index >= 0 ? _chatList[index] : _chatList.last;
    chat['last_message'] = message.content;
    chat['last_message_at'] = message.createdAt.toIso8601String();
    chat['updated_at'] = message.createdAt.toIso8601String();

    final isMine =
        message.senderIdString.isNotEmpty && message.senderIdString == _userId;
    if (!isMine && _activeConversationId != key) {
      final count = chat['unread_count'];
      chat['unread_count'] = count is num ? count.toInt() + 1 : 1;
      chat['unread'] = true;
    }
    _sortChats();
  }

  void _sortChats() {
    _chatList.sort((a, b) {
      final pinned =
          (b['pinned'] == true ? 1 : 0) - (a['pinned'] == true ? 1 : 0);
      if (pinned != 0) return pinned;
      final bTime = DateTime.tryParse(
          (b['updated_at'] ?? b['last_message_at'] ?? b['created_at'] ?? '')
              .toString());
      final aTime = DateTime.tryParse(
          (a['updated_at'] ?? a['last_message_at'] ?? a['created_at'] ?? '')
              .toString());
      return (bTime ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(aTime ?? DateTime.fromMillisecondsSinceEpoch(0));
    });
  }

  Future<void> loadChatList() async {
    _loading = true;
    notifyListeners();
    try {
      final previousById = <String, Map<String, dynamic>>{
        for (final chat in _chatList) _chatId(chat): chat,
      };
      final data = _payload(await _api.get('/chats'));
      _chatList = _list(data).map((item) {
        final chat = Map<String, dynamic>.from(item);
        final previous = previousById[_chatId(chat)];
        return previous == null ? chat : {...previous, ...chat};
      }).toList();
      _sortChats();
      for (final chat in _chatList) {
        final id =
            (chat['id'] ?? chat['conversation_id'] ?? chat['chatId'] ?? '')
                .toString();
        if (id.isNotEmpty) {
          if (isGroupChat(chat)) _groupKeys.add(id);
        }
      }
    } catch (e) {
      debugPrint('[Chat] 加载会话列表失败: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<List<ChatMessage>> loadMessages(String conversationId,
          {int page = 1, int limit = 50}) =>
      _load(conversationId, false, page: page, limit: limit);

  Future<List<ChatMessage>> loadGroupMessages(String groupId,
          {int page = 1, int limit = 50}) =>
      _load(groupId, true, page: page, limit: limit);

  Future<List<ChatMessage>> _load(String key, bool group,
      {required int page, required int limit}) async {
    await _initStorage();
    try {
      final path = group ? '/groups/$key/messages' : '/chats/$key/messages';
      final data = _payload(await _api.get(path, params: {
        'page': page,
        'page_size': limit,
        'limit': limit,
      }));
      final messages =
          _list(data).map((item) => ChatMessage.fromJson(item)).toList();
      mergeMessages(key, messages);
    } catch (e) {
      debugPrint('[Chat] 加载消息失败: $e');
    }
    return messagesFor(key);
  }

  Future<ChatMessage?> sendMessage(String key, String content,
      {String type = 'text',
      bool group = false,
      dynamic receiverId,
      String? clientMessageId}) async {
    final text = content.trim();
    if (text.isEmpty || text.length > 5000) {
      throw ArgumentError('消息长度必须为1至5000个字符');
    }
    await _initStorage();
    final clientId = clientMessageId ?? _newClientMessageId();
    final local = ChatMessage(
      conversationId: group ? null : key,
      groupId: group ? key : null,
      isGroup: group,
      senderId: _userId,
      receiverId: receiverId,
      clientMessageId: clientId,
      createdAt: DateTime.now(),
      content: text,
      type: type,
      localId: clientId,
      status: ChatMessageStatus.sending,
    );
    mergeMessage(key, local);
    await _localDatabase.saveOutbox(local, key);
    await _persist(key);
    final path = group ? '/groups/$key/messages' : '/chats/$key/messages';
    DioException? lastNetworkError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await _api.post(path, data: {
          'content': text,
          'type': type,
          'clientMessageId': clientId,
          if (!group && receiverId != null) 'receiverId': receiverId,
        });
        final sent = _messageFromPayload(response.data, local)
            .copyWith(status: ChatMessageStatus.sent);
        mergeMessage(key, sent);
        _updateChatSummary(key, sent);
        if (clientId.isNotEmpty) {
          await _localDatabase.removeOutbox(clientId);
        }
        await _persist(key);
        return sent;
      } on DioException catch (e) {
        final code = e.response?.statusCode ?? 0;
        if (code >= 400 && code < 500) {
          mergeMessage(key, local.copyWith(status: ChatMessageStatus.failed));
          await _localDatabase.saveOutbox(local, key,
              status: 'failed', retryCount: 2);
          await _persist(key);
          debugPrint('[Chat] 发送消息被拒绝($code): $e');
          return local.copyWith(status: ChatMessageStatus.failed);
        }
        lastNetworkError = e;
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
      } catch (e) {
        final failed = local.copyWith(status: ChatMessageStatus.failed);
        mergeMessage(key, failed);
        await _localDatabase.saveOutbox(local, key, status: 'pending');
        await _persist(key);
        debugPrint('[Chat] 发送消息失败: $e');
        return failed;
      }
    }
    final failed = local.copyWith(status: ChatMessageStatus.failed);
    mergeMessage(key, failed);
    await _localDatabase.saveOutbox(local, key,
        status: 'pending', retryCount: 2);
    await _persist(key);
    debugPrint('[Chat] 网络重试后仍发送失败: $lastNetworkError');
    return failed;
  }

  Future<void> syncConversation(String id) => _sync(id, false);

  Future<void> syncGroup(String id) {
    _groupKeys.add(id);
    return _sync(id, true);
  }

  Future<void> _sync(String key, bool group) async {
    try {
      final path =
          group ? '/groups/$key/messages/sync' : '/chats/$key/messages/sync';
      final response = await _api.get(path, params: {
        'afterSeq': lastMessageSeq(key),
        'after_seq': lastMessageSeq(key),
        'limit': 100,
      });
      final data = _payload(response.data);
      final items =
          _list(data).map((item) => ChatMessage.fromJson(item)).toList();
      mergeMessages(key, items);
      final next = _maxSeq(items);
      if (next > lastMessageSeq(key)) _lastSeq[key] = next;
      await _persist(key);
    } catch (e) {
      debugPrint('[Chat] 同步消息失败: $e');
    }
  }

  Future<void> syncAll() async {
    if (_syncing) return;
    _syncing = true;
    try {
      await _initStorage();
      if (_chatList.isEmpty) await loadChatList();
      final keys = {
        ..._messages.keys,
        ..._chatList.map(_chatId).where((id) => id.isNotEmpty),
      };
      for (final key in keys) {
        if (_groupKeys.contains(key)) {
          await syncGroup(key);
        } else {
          await syncConversation(key);
        }
      }
      await retryPendingMessages();
    } finally {
      _syncing = false;
    }
  }

  Future<void> retryPendingMessages() async {
    await _initStorage();
    final pending = await _localDatabase.pendingOutbox();
    for (final message in pending) {
      final key = message.chatId;
      if (key.isEmpty || message.content.trim().isEmpty) continue;
      await sendMessage(
        key,
        message.content,
        type: message.type,
        group: message.isGroup,
        receiverId: message.receiverId,
        clientMessageId: message.clientMessageId,
      );
    }
  }

  void mergeMessages(String key, Iterable<ChatMessage> incoming) {
    for (final message in incoming) {
      mergeMessage(key, message, persist: false, notify: false);
    }
    final list = _messages[key] ?? [];
    list.sort((a, b) {
      if (a.messageSeq != null && b.messageSeq != null) {
        return a.messageSeq!.compareTo(b.messageSeq!);
      }
      return a.createdAt.compareTo(b.createdAt);
    });
    if (list.length > 500) {
      list.removeRange(0, list.length - 500);
    }
    final seq = _maxSeq(list);
    if (seq > lastMessageSeq(key)) _lastSeq[key] = seq;
    notifyListeners();
    unawaited(_persist(key));
  }

  String conversationKeyForMessage(ChatMessage message) {
    final directKey = message.chatId;
    if (directKey.isNotEmpty) return directKey;

    final otherUserId = message.senderIdString == _userId
        ? message.receiverId
        : message.senderId;
    return conversationIdForUser(otherUserId) ?? '';
  }

  String? receiveMessage(ChatMessage message) {
    final key = conversationKeyForMessage(message);
    if (key.isEmpty) {
      debugPrint('[Chat] 收到消息但无法识别会话: ${message.identity}');
      return null;
    }
    final isNew = !hasMessage(key, message);
    final sequence = message.messageSeq;
    if (sequence != null && sequence > lastMessageSeq(key)) {
      _lastSeq[key] = sequence;
    }
    mergeMessage(key, message, notify: false);
    if (isNew) _updateChatSummary(key, message);
    notifyListeners();
    return key;
  }

  bool hasMessage(String key, ChatMessage message) =>
      (_messages[key] ?? []).any((item) =>
          (item.id != null &&
              message.id != null &&
              item.id.toString() == message.id.toString()) ||
          (item.clientMessageId != null &&
              message.clientMessageId != null &&
              item.clientMessageId == message.clientMessageId) ||
          item.identity == message.identity);

  void mergeMessage(String key, ChatMessage message,
      {bool persist = true, bool notify = true}) {
    if (message.isGroup) _groupKeys.add(key);
    final list = _messages.putIfAbsent(key, () => []);
    final index = list.indexWhere((item) =>
        (item.id != null &&
            message.id != null &&
            item.id.toString() == message.id.toString()) ||
        (item.clientMessageId != null &&
            message.clientMessageId != null &&
            item.clientMessageId == message.clientMessageId) ||
        item.identity == message.identity);
    if (index < 0) {
      list.add(message);
    } else {
      list[index] = message.status == ChatMessageStatus.sent
          ? message
          : _prefer(list[index], message);
    }
    if (notify) notifyListeners();
    if (persist) unawaited(_persist(key));
  }

  void addMessage(String key, ChatMessage message) =>
      mergeMessage(key, message);

  Future<void> _persist(String key) {
    _persistQueue = _persistQueue.then((_) async {
      try {
        await _localDatabase.upsertMessages(key, _messages[key] ?? [],
            group: _groupKeys.contains(key));
        await _localDatabase.saveSyncSequence(key, lastMessageSeq(key));
      } catch (e) {
        debugPrint('[Chat] 保存本地消息失败: $e');
      }
    });
    return _persistQueue;
  }

  Future<void> restoreLocal(String key) async {
    await _initStorage();
    try {
      final stored = await _localDatabase.messagesFor(key);
      _lastSeq[key] = await _localDatabase.syncSequence(key);
      if (stored.isNotEmpty) {
        mergeMessages(key, stored);
      }
    } catch (e) {
      debugPrint('[Chat] 恢复本地消息失败: $e');
    }
  }

  ChatMessage _messageFromPayload(dynamic raw, ChatMessage fallback) {
    final map = raw is Map ? _payload(raw) : null;
    return map is Map && (map['content'] != null || map['id'] != null)
        ? ChatMessage.fromJson(Map<String, dynamic>.from(map))
        : fallback;
  }

  dynamic _payload(dynamic raw) {
    if (raw is Map && raw['data'] != null) return raw['data'];
    return raw;
  }

  List<Map<String, dynamic>> _list(dynamic value) {
    dynamic list;
    if (value is List) {
      list = value;
    } else if (value is Map) {
      list =
          value['messages'] ?? value['items'] ?? value['records'] ?? const [];
    } else {
      return const [];
    }
    return (list as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  int _maxSeq(Iterable<ChatMessage> items) =>
      items.map((e) => e.messageSeq ?? 0).fold(0, max);
  ChatMessage _prefer(ChatMessage old, ChatMessage next) =>
      old.status == ChatMessageStatus.sending ? next : old;

  @override
  void dispose() {
    unawaited(_localDatabase.close());
    super.dispose();
  }

  String _newClientMessageId() =>
      '${_userId ?? 'anonymous'}_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 32)}';
}
