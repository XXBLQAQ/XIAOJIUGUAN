import 'package:chat_game_app/services/chat_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatService 好友会话映射', () {
    final service = ChatService();

    test('支持显式好友字段', () {
      final chatId = service.conversationIdForUser(
        'user-2',
        chats: [
          {
            'id': 'chat-1',
            'friend_id': 'user-2',
          },
        ],
      );

      expect(chatId, 'chat-1');
    });

    test('支持不同成员字段和成员对象格式', () {
      expect(
        service.conversationIdForUser(
          'user-2',
          chats: [
            {
              'conversation_id': 'chat-1',
              'members': ['user-1', 'user-2'],
            },
          ],
        ),
        'chat-1',
      );

      expect(
        service.conversationIdForUser(
          'user-3',
          chats: [
            {
              'chatId': 'chat-2',
              'participants': [
                {'uid': 'user-1'},
                {'user_id': 'user-3'},
              ],
            },
          ],
        ),
        'chat-2',
      );
    });

    test('群聊不会被识别为好友私聊', () {
      final chatId = service.conversationIdForUser(
        'user-2',
        chats: [
          {
            'id': 'group-1',
            'groupId': 'group-1',
            'members': ['user-1', 'user-2'],
          },
          {
            'id': 'chat-1',
            'otherUserId': 'user-2',
          },
        ],
      );

      expect(chatId, 'chat-1');
    });

    test('空用户标识不返回会话', () {
      expect(
        service.conversationIdForUser('', chats: [
          {'id': 'chat-1', 'friendId': 'user-2'},
        ]),
        isNull,
      );
    });
  });
}
