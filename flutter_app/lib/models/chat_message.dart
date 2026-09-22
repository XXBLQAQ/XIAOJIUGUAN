enum ChatMessageStatus { sending, pending, sent, failed }

/// 兼容私聊、群聊及本地待发送消息的数据模型。
class ChatMessage {
  final dynamic id;
  final String? conversationId;
  final String? groupId;
  final bool isGroup;
  final dynamic senderId;
  final dynamic receiverId;
  final String? clientMessageId;
  final int? messageSeq;
  final bool isRead;
  final DateTime? readAt;
  final DateTime createdAt;
  final String senderNickname;
  final String? senderAvatar;
  final String content;
  final String type;
  final String localId;
  final ChatMessageStatus status;

  ChatMessage({
    this.id,
    this.conversationId,
    this.groupId,
    this.isGroup = false,
    this.senderId,
    this.receiverId,
    this.clientMessageId,
    this.messageSeq,
    this.isRead = false,
    this.readAt,
    required this.createdAt,
    this.senderNickname = '',
    this.senderAvatar,
    required this.content,
    this.type = 'text',
    String? localId,
    this.status = ChatMessageStatus.sent,
  }) : localId = localId ?? clientMessageId ?? id?.toString() ?? '';

  String get chatId => conversationId ?? groupId ?? '';
  String get senderName => senderNickname;
  String get senderIdString => senderId?.toString() ?? '';
  String get identity => clientMessageId?.isNotEmpty == true
      ? 'client:$clientMessageId'
      : id?.toString().isNotEmpty == true
          ? 'id:$id'
          : 'local:$localId';

  ChatMessage copyWith({
    dynamic id,
    String? conversationId,
    String? groupId,
    bool? isGroup,
    dynamic senderId,
    dynamic receiverId,
    String? clientMessageId,
    int? messageSeq,
    bool? isRead,
    DateTime? readAt,
    DateTime? createdAt,
    String? senderNickname,
    String? senderAvatar,
    String? content,
    String? type,
    String? localId,
    ChatMessageStatus? status,
  }) =>
      ChatMessage(
        id: id ?? this.id,
        conversationId: conversationId ?? this.conversationId,
        groupId: groupId ?? this.groupId,
        isGroup: isGroup ?? this.isGroup,
        senderId: senderId ?? this.senderId,
        receiverId: receiverId ?? this.receiverId,
        clientMessageId: clientMessageId ?? this.clientMessageId,
        messageSeq: messageSeq ?? this.messageSeq,
        isRead: isRead ?? this.isRead,
        readAt: readAt ?? this.readAt,
        createdAt: createdAt ?? this.createdAt,
        senderNickname: senderNickname ?? this.senderNickname,
        senderAvatar: senderAvatar ?? this.senderAvatar,
        content: content ?? this.content,
        type: type ?? this.type,
        localId: localId ?? this.localId,
        status: status ?? this.status,
      );

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawStatus = json['status']?.toString();
    return ChatMessage(
      id: json['id'],
      conversationId: _string(json['conversation_id'] ??
          json['conversationId'] ??
          json['chat_id'] ??
          json['chatId']),
      groupId: _string(json['group_id'] ?? json['groupId']),
      isGroup: json['group_id'] != null ||
          json['groupId'] != null ||
          json['is_group'] == true ||
          json['isGroup'] == true ||
          json['chat_type'] == 'group' ||
          json['conversation_type'] == 'group',
      senderId: json['sender_id']?.toString().isNotEmpty == true
          ? json['sender_id']
          : json['senderId'],
      receiverId: json['receiver_id'] ?? json['receiverId'],
      clientMessageId:
          _string(json['client_message_id'] ?? json['clientMessageId']),
      messageSeq:
          _int(json['seq'] ?? json['message_seq'] ?? json['messageSeq']),
      isRead: json['is_read'] == true ||
          json['isRead'] == true ||
          json['is_read'] == 1,
      readAt: _date(json['read_at'] ?? json['readAt']),
      createdAt:
          _date(json['created_at'] ?? json['createdAt']) ?? DateTime.now(),
      senderNickname: (json['sender_nickname'] ??
              json['senderNickname'] ??
              json['senderName'] ??
              '')
          .toString(),
      senderAvatar: _string(json['sender_avatar'] ?? json['senderAvatar']),
      content: (json['content'] ?? '').toString(),
      type: (json['message_type'] ?? json['type'] ?? 'text').toString(),
      localId: _string(json['localId'] ?? json['local_id']),
      status: ChatMessageStatus.values.firstWhere(
        (value) => value.name == rawStatus,
        orElse: () => ChatMessageStatus.sent,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'conversation_id': conversationId,
        'group_id': groupId,
        'is_group': isGroup,
        'sender_id': senderId,
        'receiver_id': receiverId,
        'client_message_id': clientMessageId,
        'message_seq': messageSeq,
        'is_read': isRead,
        'read_at': readAt?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
        'sender_nickname': senderNickname,
        'sender_avatar': senderAvatar,
        'content': content,
        'type': type,
        'localId': localId,
        'status': status.name,
      };

  static String? _string(dynamic value) => value?.toString();
  static int? _int(dynamic value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
  static DateTime? _date(dynamic value) =>
      value is DateTime ? value : DateTime.tryParse(value?.toString() ?? '');
}
