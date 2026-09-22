import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../services/chat_socket_service.dart';
import '../../services/message_notification_service.dart';

/// 启动页 — 自动判断登录状态跳转
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});
  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  Timer? _navigationTimer;

  @override
  void initState() {
    super.initState();
    _navigationTimer = Timer(const Duration(seconds: 2), _navigateAfterDelay);
  }

  Future<void> _navigateAfterDelay() async {
    if (!mounted) return;
    final auth = context.read<AuthService>();
    await auth.restoreSession();
    if (!mounted) return;
    if (auth.isLoggedIn) {
      context
          .read<ChatSocketService>()
          .connect(token: auth.token, userId: auth.user?['id']?.toString());
      unawaited(context
          .read<MessageNotificationService>()
          .requestNotificationPermission());
    }
    Navigator.pushReplacementNamed(
      context,
      auth.isLoggedIn ? '/home' : '/login',
    );
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: .28),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(Icons.forum_rounded, size: 38, color: scheme.onPrimary),
                  Positioned(
                    right: 14,
                    bottom: 14,
                    child: Icon(Icons.star_rounded,
                        size: 13, color: scheme.primary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text('小酒馆',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    )),
            const SizedBox(height: 8),
            Text('和朋友一起，聊点有趣的',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurface.withValues(alpha: .72),
                    )),
            const SizedBox(height: 28),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.primary.withValues(alpha: .8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
