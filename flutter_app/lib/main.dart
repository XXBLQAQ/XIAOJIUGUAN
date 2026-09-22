import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/app.dart';
import 'services/auth_service.dart';
import 'services/chat_service.dart';
import 'services/chat_socket_service.dart';
import 'services/minecraft_server_service.dart';
import 'services/message_notification_service.dart';
import 'services/remote_vibration_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final navigatorKey = GlobalKey<NavigatorState>();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ChatService()),
        ChangeNotifierProvider(
          create: (_) => MessageNotificationService(navigatorKey)..initialize(),
        ),
        ChangeNotifierProvider(
          create: (context) => ChatSocketService(
            context.read<ChatService>(),
            context.read<MessageNotificationService>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) =>
              RemoteVibrationService(context.read<ChatSocketService>()),
        ),
        ChangeNotifierProvider(create: (_) => MinecraftServerService()),
        ChangeNotifierProvider(
          create: (context) {
            final chatService = context.read<ChatService>();
            final chatSocketService = context.read<ChatSocketService>();
            final notificationService =
                context.read<MessageNotificationService>();
            final vibrationService = context.read<RemoteVibrationService>();
            return AuthService(
              onSessionChanged: (userId) async {
                await chatService.setUserId(userId);
                vibrationService.setUserId(userId);
              },
              onLogout: () async {
                await chatService.setUserId(null);
                chatSocketService.disconnect();
                notificationService.resetSession();
              },
            );
          },
        ),
      ],
      child: ChatGameApp(navigatorKey: navigatorKey),
    ),
  );
}
