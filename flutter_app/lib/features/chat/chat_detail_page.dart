import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design_system.dart';
import '../../models/chat_message.dart';
import '../../services/chat_service.dart';
import '../../services/chat_socket_service.dart';
import '../../services/message_notification_service.dart';
import '../../services/remote_vibration_service.dart';

class ChatDetailPage extends StatefulWidget {
  final String chatId;
  final String chatName;
  final bool isGroup;
  final dynamic receiverId;

  const ChatDetailPage({
    super.key,
    required this.chatId,
    required this.chatName,
    this.isGroup = false,
    this.receiverId,
  });

  @override
  State<ChatDetailPage> createState() => _ChatDetailPageState();
}

class _ChatDetailPageState extends State<ChatDetailPage>
    with WidgetsBindingObserver {
  final _inputController = TextEditingController();
  final _inputFocusNode = FocusNode();
  final _scrollController = ScrollController();
  Timer? _typingTimer;
  bool _triggeringVibration = false;
  bool _initialLoadComplete = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final chat = context.read<ChatService>();
    context.read<MessageNotificationService>().setActiveChat(widget.chatId);
    context.read<ChatSocketService>().joinConversation(widget.chatId);
    if (!widget.isGroup && widget.receiverId != null) {
      unawaited(
        context.read<RemoteVibrationService>().loadPermission(widget.chatId),
      );
    }
    unawaited(_loadConversation(chat));
  }

  Future<void> _loadConversation(ChatService chat) async {
    try {
      await chat.markConversationRead(widget.chatId);
      await chat.restoreLocal(widget.chatId);
      if (widget.isGroup) {
        await chat.loadGroupMessages(widget.chatId);
      } else {
        await chat.loadMessages(widget.chatId);
      }
    } finally {
      if (mounted) {
        setState(() => _initialLoadComplete = true);
        _scrollToLatest(animated: false);
      }
    }
  }

  void _scrollToLatest({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position.maxScrollExtent;
      if (animated) {
        _scrollController.animateTo(
          position,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(position);
      }
    });
  }

  String _formatMessageTime(DateTime time) {
    final local = time.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  String _statusLabel(ChatMessage message) => switch (message.status) {
        ChatMessageStatus.sending => '发送中',
        ChatMessageStatus.pending => '待发送',
        ChatMessageStatus.failed => '发送失败，点击重试',
        ChatMessageStatus.sent => message.isRead ? '已读' : '已发送',
      };

  void _onChanged(String value) {
    _typingTimer?.cancel();
    final socket = context.read<ChatSocketService>();
    if (value.trim().isNotEmpty) {
      socket.sendTyping(widget.chatId, receiverId: widget.receiverId);
    }
    _typingTimer = Timer(const Duration(seconds: 1), () {
      socket.stopTyping(widget.chatId, receiverId: widget.receiverId);
    });
  }

  Future<void> _send({ChatMessage? retryMessage}) async {
    final text = retryMessage?.content ?? _inputController.text.trim();
    if (text.isEmpty) return;
    if (text.length > 5000) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('消息不能超过5000个字符')));
      return;
    }
    if (retryMessage == null) _inputController.clear();
    final result = await context.read<ChatService>().sendMessage(
          widget.chatId,
          text,
          group: widget.isGroup,
          receiverId: widget.receiverId,
          clientMessageId: retryMessage?.clientMessageId,
        );
    if (!mounted) return;
    _scrollToLatest();
    if (result?.status == ChatMessageStatus.failed) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('网络不可用，消息会在恢复连接后重试')));
    }
  }

  Future<void> _triggerRemoteVibration() async {
    if (_triggeringVibration) return;
    setState(() => _triggeringVibration = true);
    final error = await context
        .read<RemoteVibrationService>()
        .trigger(widget.chatId, widget.receiverId);
    if (!mounted) return;
    setState(() => _triggeringVibration = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(error ?? '远程震动指令已发送')));
  }

  Future<void> _showRemoteVibrationSettings() async {
    final service = context.read<RemoteVibrationService>();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final permission = context
              .watch<RemoteVibrationService>()
              .permissionFor(widget.chatId);
          final enabled = permission?.localEnabled ?? false;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ListTile(
                    leading: Icon(Icons.vibration_rounded),
                    title: Text('远程震动'),
                    subtitle: Text('仅允许当前好友在获得你的授权后触发'),
                  ),
                  SwitchListTile(
                    title: const Text('允许好友远程触发手机震动'),
                    value: enabled,
                    onChanged: (value) async {
                      final error = await service.setLocalPermission(
                        widget.chatId,
                        value,
                      );
                      if (!sheetContext.mounted) return;
                      if (error != null) {
                        ScaffoldMessenger.of(sheetContext)
                            .showSnackBar(SnackBar(content: Text(error)));
                        return;
                      }
                      setSheetState(() {});
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      context.read<ChatSocketService>().stopTyping(widget.chatId);
    }
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    context.read<ChatSocketService>().stopTyping(widget.chatId);
    context.read<ChatService>().clearActiveConversation(widget.chatId);
    context.read<MessageNotificationService>().setActiveChat(null);
    WidgetsBinding.instance.removeObserver(this);
    _inputController.dispose();
    _inputFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chat = context.watch<ChatService>();
    final messages = chat.messagesFor(widget.chatId);
    final vibration = context.watch<RemoteVibrationService>();
    final canRemoteVibrate = !widget.isGroup &&
        widget.receiverId != null &&
        vibration.permissionFor(widget.chatId)?.canSend == true;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: AppSpacing.sm,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.chatName,
                style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(
              widget.isGroup ? '群聊' : '私聊',
              style: TextStyle(
                color: scheme.onSurface.withValues(alpha: .58),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          if (!widget.isGroup && widget.receiverId != null)
            IconButton(
              tooltip: '远程震动设置',
              onPressed: _showRemoteVibrationSettings,
              icon: const Icon(Icons.tune_rounded),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessageList(messages, chat.currentUserId)),
          _buildComposer(canRemoteVibrate),
        ],
      ),
    );
  }

  Widget _buildMessageList(List<ChatMessage> messages, String? userId) {
    if (!_initialLoadComplete && messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Text(
            '发送第一条消息，开始聊天吧',
            style: TextStyle(
              color:
                  Theme.of(context).colorScheme.onSurface.withValues(alpha: .6),
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      itemCount: messages.length,
      itemBuilder: (_, index) {
        final message = messages[index];
        final mine = message.senderIdString.isNotEmpty &&
            message.senderIdString == userId;
        return _MessageBubble(
          message: message,
          mine: mine,
          time: _formatMessageTime(message.createdAt),
          status: mine ? _statusLabel(message) : null,
          onRetry: mine && message.status == ChatMessageStatus.failed
              ? () => _send(retryMessage: message)
              : null,
        );
      },
    );
  }

  Widget _buildComposer(bool canRemoteVibrate) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.md,
          AppSpacing.sm,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.input),
            border: Border.all(color: scheme.outline.withValues(alpha: .55)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (canRemoteVibrate)
                IconButton(
                  tooltip: '远程震动',
                  onPressed:
                      _triggeringVibration ? null : _triggerRemoteVibration,
                  icon: _triggeringVibration
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.vibration_rounded),
                ),
              Expanded(
                child: TextField(
                  controller: _inputController,
                  focusNode: _inputFocusNode,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: 5000,
                  textInputAction: TextInputAction.newline,
                  onChanged: _onChanged,
                  decoration: const InputDecoration(
                    hintText: '输入消息',
                    counterText: '',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              IconButton.filled(
                tooltip: '发送',
                onPressed: _send,
                icon: const Icon(Icons.send_rounded),
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool mine;
  final String time;
  final String? status;
  final VoidCallback? onRetry;

  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.time,
    this.status,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = mine ? scheme.onPrimary : scheme.onSurface;
    final metaColor = foreground.withValues(alpha: .66);
    return Semantics(
      button: onRetry != null,
      label: onRetry != null ? '发送失败，点击重试' : null,
      child: GestureDetector(
        onTap: onRetry,
        child: Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 300),
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            decoration: BoxDecoration(
              color: mine ? scheme.primary : scheme.surface,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(AppRadius.input),
                topRight: const Radius.circular(AppRadius.input),
                bottomLeft: Radius.circular(mine ? AppRadius.input : 4),
                bottomRight: Radius.circular(mine ? 4 : AppRadius.input),
              ),
              border: mine
                  ? null
                  : Border.all(color: scheme.outline.withValues(alpha: .42)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SelectableText(
                  message.content,
                  style: TextStyle(color: foreground, height: 1.42),
                ),
                const SizedBox(height: 4),
                Text(
                  status == null ? time : '$time  $status',
                  style: TextStyle(color: metaColor, fontSize: 10),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
