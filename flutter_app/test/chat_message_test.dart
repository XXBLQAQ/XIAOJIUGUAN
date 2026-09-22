import 'package:chat_game_app/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatMessage', () {
    test('识别不同协议字段中的群聊消息', () {
      for (final payload in [
        {'group_id': 'group-1'},
        {'groupId': 'group-2'},
        {'is_group': true, 'chat_id': 'group-3'},
        {'isGroup': true, 'chatId': 'group-4'},
        {'chat_type': 'group', 'chat_id': 'group-5'},
      ]) {
        final message = ChatMessage.fromJson({
          ...payload,
          'content': '测试消息',
          'created_at': '2026-09-22T12:00:00.000Z',
        });

        expect(message.isGroup, isTrue);
      }
    });

    test('本地序列化后保留群聊和发送状态', () {
      final original = ChatMessage(
        groupId: 'group-1',
        isGroup: true,
        clientMessageId: 'client-1',
        createdAt: DateTime.utc(2026, 9, 22, 12),
        content: '待发送消息',
        status: ChatMessageStatus.pending,
      );

      final restored = ChatMessage.fromJson(original.toJson());

      expect(restored.groupId, 'group-1');
      expect(restored.isGroup, isTrue);
      expect(restored.clientMessageId, 'client-1');
      expect(restored.status, ChatMessageStatus.pending);
    });

    test('copyWith 保留或覆盖群聊属性', () {
      final original = ChatMessage(
        conversationId: 'chat-1',
        isGroup: true,
        createdAt: DateTime.utc(2026, 9, 22),
        content: '消息',
      );

      expect(original.copyWith().isGroup, isTrue);
      expect(original.copyWith(isGroup: false).isGroup, isFalse);
    });
  });
}
