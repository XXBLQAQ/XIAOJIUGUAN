import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/routes.dart';
import '../core/api_client.dart';
import '../models/chat_message.dart';
import '../widgets/app_avatar.dart';

/// 统一处理前台横幅、后台系统通知和通知点击跳转。
class NotificationSettings {
  bool chat;
  bool game;
  bool friendRequest;
  bool system;

  NotificationSettings({
    this.chat = true,
    this.game = true,
    this.friendRequest = true,
    this.system = true,
  });

  NotificationSettings copy() => NotificationSettings(
        chat: chat,
        game: game,
        friendRequest: friendRequest,
        system: system,
      );

  Map<String, dynamic> toJson() => {
        'chat': chat,
        'game': game,
        'friend_request': friendRequest,
        'system': system,
      };
}

class MessageNotificationService extends ChangeNotifier
    with WidgetsBindingObserver {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final GlobalKey<NavigatorState> navigatorKey;
  Timer? _bannerTimer;
  OverlayEntry? _bannerEntry;
  String? _activeChatId;
  bool _ready = false;
  bool _notificationPermissionGranted = true;

  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  NotificationSettings _settings = NotificationSettings();

  NotificationSettings get settings => _settings;

  MessageNotificationService(this.navigatorKey) {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
  }

  Future<void> initialize() async {
    if (_ready || kIsWeb) return;
    try {
      final response = await ApiClient().get('/notification-settings');
      final data = response.data is Map ? response.data['data'] : null;
      if (data is Map) {
        _settings = NotificationSettings(
          chat: data['chat'] != false,
          game: data['game'] != false,
          friendRequest: data['friend_request'] != false,
          system: data['system'] != false,
        );
      }
    } catch (_) {
      // 未登录或后端暂不可用时使用默认设置。
    }
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _onNotificationTap,
    );
    const channel = AndroidNotificationChannel(
      'chat_messages',
      '好友消息',
      description: '好友新消息通知',
      importance: Importance.high,
      playSound: true,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final enabled = await androidPlugin?.areNotificationsEnabled();
    _notificationPermissionGranted = enabled ?? true;
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    _ready = true;
  }

  Future<bool> requestNotificationPermission() async {
    if (kIsWeb) return false;
    await initialize();
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return true;
    final enabled = await androidPlugin.areNotificationsEnabled();
    if (enabled == true) {
      _notificationPermissionGranted = true;
      return true;
    }
    _notificationPermissionGranted =
        await androidPlugin.requestNotificationsPermission() ?? false;
    return _notificationPermissionGranted;
  }

  void setActiveChat(String? chatId) {
    _activeChatId = chatId?.trim().isEmpty == true ? null : chatId?.trim();
  }

  void resetSession() {
    _activeChatId = null;
    _removeBanner();
    _settings = NotificationSettings();
    notifyListeners();
  }

  bool shouldSuppress(String chatId) => _activeChatId == chatId;

  Future<void> saveSettings(NotificationSettings settings) async {
    final previous = _settings;
    _settings = settings.copy();
    try {
      await ApiClient().put('/notification-settings', data: _settings.toJson());
    } catch (_) {
      _settings = previous;
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  Future<void> showCustomNotification(String title, String content,
      {String? iconPath}) async {
    if (kIsWeb) return;
    await initialize();
    if (!_ready) return;
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
      title.trim().isEmpty ? '通知自己' : title.trim(),
      content.trim(),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'self_notifications',
          '个人提醒',
          channelDescription: '发送给自己的提醒通知',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }

  Future<void> showMessage(ChatMessage message,
      {String? chatName, String? chatIdOverride}) async {
    final chatId = chatIdOverride ?? message.chatId;
    if (!_settings.chat || chatId.isEmpty || shouldSuppress(chatId)) return;
    final title = message.senderNickname.trim().isEmpty
        ? (chatName?.trim().isNotEmpty == true ? chatName! : '新消息')
        : message.senderNickname.trim();
    final content =
        message.content.trim().isEmpty ? '收到一条新消息' : message.content;
    final routeArgs = <String, dynamic>{
      'chatId': chatId,
      'chatName': title,
      'isGroup': message.isGroup,
    };
    final appInForeground = _lifecycle == AppLifecycleState.resumed;
    if (appInForeground) {
      _showForegroundBanner(title, content, routeArgs, message.senderAvatar);
      return;
    }
    await _showSystemNotification(title, content, routeArgs);
  }

  void _showForegroundBanner(
    String title,
    String content,
    Map<String, dynamic> routeArgs,
    String? avatar,
  ) {
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) return;
    _bannerTimer?.cancel();
    _bannerEntry?.remove();
    final entry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 8,
        left: 12,
        right: 12,
        child: Dismissible(
          key: ValueKey(DateTime.now().microsecondsSinceEpoch),
          direction: DismissDirection.horizontal,
          onDismissed: (_) => _removeBanner(),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(18),
            color: Theme.of(context).colorScheme.surface,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () {
                _removeBanner();
                navigatorKey.currentState?.pushNamed(
                  AppRoutes.chatDetail,
                  arguments: routeArgs,
                );
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Row(
                  children: [
                    AppAvatar(
                      source: avatar,
                      radius: 22,
                      icon: Icons.person_rounded,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 3),
                          Text(content,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    _bannerEntry = entry;
    _bannerTimer = Timer(const Duration(seconds: 3), _removeBanner);
  }

  Future<void> _showSystemNotification(
      String title, String content, Map<String, dynamic> routeArgs) async {
    if (!_ready || kIsWeb) return;
    final chatId = routeArgs['chatId']?.toString() ?? '';
    if (chatId.isEmpty) return;
    await _plugin.show(
      chatId.hashCode & 0x7fffffff,
      title,
      content,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'chat_messages',
          '好友消息',
          channelDescription: '好友新消息通知',
          importance: Importance.high,
          priority: Priority.high,
          ticker: '新消息',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: jsonEncode(routeArgs),
    );
  }

  void _onNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    try {
      final raw = jsonDecode(payload);
      if (raw is! Map) return;
      final args = Map<String, dynamic>.from(raw);
      if (args['chatId']?.toString().isEmpty != false) return;
      navigatorKey.currentState?.pushNamed(
        AppRoutes.chatDetail,
        arguments: args,
      );
    } catch (_) {
      navigatorKey.currentState?.pushNamed(
        AppRoutes.chatDetail,
        arguments: {'chatId': payload, 'chatName': '聊天'},
      );
    }
  }

  void _removeBanner() {
    _bannerTimer?.cancel();
    _bannerTimer = null;
    _bannerEntry?.remove();
    _bannerEntry = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _removeBanner();
    super.dispose();
  }
}
