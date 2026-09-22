// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:chat_game_app/core/app.dart';
import 'package:chat_game_app/services/auth_service.dart';
import 'package:chat_game_app/services/chat_service.dart';

void main() {
  testWidgets('应用可以显示启动页', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthService()),
          ChangeNotifierProvider(create: (_) => ChatService()),
        ],
        child: const ChatGameApp(),
      ),
    );
    expect(find.text('小酒馆'), findsOneWidget);
    // 启动页会执行网络状态检查，测试只验证稳定可控的启动内容。
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('小酒馆'), findsOneWidget);
  });
}
