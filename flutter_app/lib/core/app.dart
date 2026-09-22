import 'package:flutter/material.dart';
import 'routes.dart';
import 'theme.dart';

/// 应用根Widget，监听双颜色主题变化。
class ChatGameApp extends StatelessWidget {
  final GlobalKey<NavigatorState> navigatorKey;

  const ChatGameApp(
      {super.key, this.navigatorKey = const GlobalObjectKey('app-navigator')});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: '小酒馆',
      theme: AppTheme.build(),
      initialRoute: AppRoutes.splash,
      onGenerateRoute: AppRoutes.generateRoute,
      debugShowCheckedModeBanner: false,
    );
  }
}
