import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design_system.dart';
import '../../core/routes.dart';
import '../../services/chat_service.dart';

class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _UnreadBadge extends StatelessWidget {
  final dynamic count;

  const _UnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final value = count is num ? count.toInt() : 0;
    final label = value > 99 ? '99+' : (value > 0 ? '$value' : '•');
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.error,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: scheme.onError,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ChatListPageState extends State<ChatListPage> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final chatService = context.read<ChatService>();
    Future.microtask(chatService.loadChatList);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chatService = context.watch<ChatService>();
    final chats = chatService.chatList;
    final keyword = _searchController.text.trim().toLowerCase();
    final visibleChats = chats.where((chat) {
      final name =
          (chat['name'] ?? chat['nickname'] ?? chat['group_name'] ?? '')
              .toString()
              .toLowerCase();
      return keyword.isEmpty || name.contains(keyword);
    }).toList();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('好友', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
              onPressed: () {},
              icon: Icon(Icons.edit_note_rounded, color: scheme.primary))
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          AppSearchField(
            hint: '搜索好友或群聊',
            controller: _searchController,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),
          if (chats.isEmpty)
            const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('暂无聊天会话')))
          else
            ...visibleChats.map((chat) {
              final id = (chat['id'] ??
                      chat['conversation_id'] ??
                      chat['group_id'] ??
                      '')
                  .toString();
              final name =
                  (chat['name'] ?? chat['nickname'] ?? chat['group_name'] ?? id)
                      .toString();
              final preview = (chat['last_message'] is Map
                      ? chat['last_message']['content']
                      : chat['last_message'] ?? '')
                  .toString();
              final time = (chat['updated_at'] ??
                      chat['last_message_at'] ??
                      chat['created_at'] ??
                      '')
                  .toString();
              final group = ChatService.isGroupChat(chat);
              return _chatTile(context, id, name, preview,
                  _formatConversationTime(time), group, chatService, chat);
            }),
        ],
      ),
    );
  }

  String _formatConversationTime(String raw) {
    final value = DateTime.tryParse(raw)?.toLocal();
    if (value == null) return '';
    final now = DateTime.now();
    final sameDay = now.year == value.year &&
        now.month == value.month &&
        now.day == value.day;
    if (sameDay) {
      return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (yesterday.year == value.year &&
        yesterday.month == value.month &&
        yesterday.day == value.day) {
      return '昨天';
    }
    if (now.year == value.year) {
      return '${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    }
    return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  }

  Widget _chatTile(
      BuildContext context,
      String id,
      String name,
      String text,
      String time,
      bool group,
      ChatService chatService,
      Map<String, dynamic> chat) {
    final scheme = Theme.of(context).colorScheme;
    final unread = chat['unread'] == true ||
        (chat['unread_count'] is num && chat['unread_count'] > 0);
    final pinned = chat['pinned'] == true;
    return InkWell(
      onTap: () => Navigator.pushNamed(context, AppRoutes.chatDetail,
          arguments: {'chatId': id, 'chatName': name, 'isGroup': group}),
      borderRadius: BorderRadius.circular(22),
      onLongPress: () => _showChatActions(context, id, unread, pinned),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Row(children: [
          CircleAvatar(
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
              child: Icon(group ? Icons.groups_rounded : Icons.person_rounded)),
          const SizedBox(width: 13),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 6),
                Text(text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: scheme.onSurface.withValues(alpha: .74),
                        fontSize: 13)),
              ])),
          SizedBox(
            width: 46,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(time,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: scheme.onSurface.withValues(alpha: .56),
                        fontSize: 11)),
                const SizedBox(height: 8),
                if (unread) _UnreadBadge(count: chat['unread_count']),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _showChatActions(
      BuildContext context, String chatId, bool unread, bool pinned) async {
    if (chatId.isEmpty) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(unread ? Icons.mark_email_read : Icons.markunread),
              title: Text(unread ? '标记为已读' : '标记为未读'),
              onTap: () => Navigator.pop(sheetContext, 'unread'),
            ),
            ListTile(
              leading: Icon(pinned ? Icons.push_pin_outlined : Icons.push_pin),
              title: Text(pinned ? '取消置顶' : '置顶'),
              onTap: () => Navigator.pop(sheetContext, 'pinned'),
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('聊天设置'),
              onTap: () => Navigator.pop(sheetContext, 'settings'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    final chatService = this.context.read<ChatService>();
    final messenger = ScaffoldMessenger.of(this.context);
    try {
      if (action == 'settings') {
        await _showChatSettings(chatId, unread, pinned);
        return;
      }
      final field = action == 'unread' ? 'unread' : 'pinned';
      final value = field == 'unread' ? !unread : !pinned;
      await chatService.updateChatSetting(chatId, field, value);
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('聊天设置失败：$error')),
        );
      }
    }
  }

  Future<void> _showChatSettings(
      String chatId, bool unread, bool pinned) async {
    var selectedUnread = unread;
    var selectedPinned = pinned;
    final changes = await showModalBottomSheet<Map<String, bool>>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  leading: Icon(Icons.settings_outlined),
                  title: Text('聊天设置'),
                ),
                SwitchListTile(
                  title: const Text('标记为未读'),
                  value: selectedUnread,
                  onChanged: (value) =>
                      setSheetState(() => selectedUnread = value),
                ),
                SwitchListTile(
                  title: const Text('置顶会话'),
                  value: selectedPinned,
                  onChanged: (value) =>
                      setSheetState(() => selectedPinned = value),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(sheetContext, {
                    'unread': selectedUnread,
                    'pinned': selectedPinned,
                  }),
                  child: const Text('保存'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted || changes == null) return;

    final chatService = context.read<ChatService>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (changes['unread'] != unread) {
        await chatService.updateChatSetting(
            chatId, 'unread', changes['unread']!);
      }
      if (changes['pinned'] != pinned) {
        await chatService.updateChatSetting(
            chatId, 'pinned', changes['pinned']!);
      }
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('聊天设置失败：$error')));
      }
    }
  }
}
