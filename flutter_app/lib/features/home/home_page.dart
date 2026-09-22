import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/routes.dart';
import '../../core/api_client.dart';
import '../../core/url_validation.dart';
import '../../core/design_system.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../services/chat_service.dart';
import '../../services/minecraft_server_service.dart';
import '../minecraft/minecraft_server_page.dart';
import '../../services/app_update_service.dart';
import '../../services/message_notification_service.dart';
import '../../widgets/widgets.dart';
import 'website_page.dart';

/// 小酒馆主框架：好友、小酒馆、我的
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

const _avatarAssets = <String>[
  'assets/avatars/微信图片_20260801014537_310_19.jpg',
  'assets/avatars/微信图片_20260801014538_311_19.jpg',
  'assets/avatars/微信图片_20260801014538_312_19.jpg',
  'assets/avatars/微信图片_20260801014539_313_19.jpg',
  'assets/avatars/微信图片_20260801014540_314_19.jpg',
  'assets/avatars/微信图片_20260801014541_315_19.jpg',
  'assets/avatars/微信图片_20260801014542_316_19.jpg',
  'assets/avatars/微信图片_20260801014543_317_19.jpg',
  'assets/avatars/微信图片_20260801014544_318_19.jpg',
  'assets/avatars/微信图片_20260801014545_319_19.jpg',
  'assets/avatars/微信图片_20260801014546_320_19.jpg',
  'assets/avatars/微信图片_20260801014546_321_19.jpg',
  'assets/avatars/微信图片_20260801014547_322_19.jpg',
  'assets/avatars/微信图片_20260801014548_323_19.jpg',
  'assets/avatars/微信图片_20260801014549_324_19.jpg',
  'assets/avatars/微信图片_20260801014550_325_19.jpg',
  'assets/avatars/微信图片_20260801014551_326_19.jpg',
  'assets/avatars/微信图片_20260801014552_327_19.jpg',
  'assets/avatars/微信图片_20260801014553_328_19.jpg',
  'assets/avatars/微信图片_20260801014553_329_19.jpg',
  'assets/avatars/微信图片_20260801014554_330_19.jpg',
];

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 1;
  final TextEditingController _searchController = TextEditingController();
  final PageController _bannerController = PageController(
    initialPage: 1000,
    viewportFraction: .9,
  );
  final PageController _pageController = PageController(initialPage: 1);
  Timer? _bannerTimer;
  Timer? _bannerRefreshTimer;
  List<Map<String, dynamic>> _remoteBanners = const [];
  List<Map<String, dynamic>> _friends = [];
  final Map<String, String> _friendChatIds = {};
  bool _friendsLoading = false;
  bool _friendsRefreshing = false;
  String? _friendsError;
  bool _updateCheckStarted = false;
  bool _updateDialogVisible = false;
  static const _lastUpdatePromptDateKey = 'last_update_prompt_date';
  static const _lastUpdatePromptVersionKey = 'last_update_prompt_version';
  Color get _themeAccent => AppTheme.primary;

  late final List<_ExploreFeature> _features = [
    _ExploreFeature(
        '网站', '绑定网站后在 App 内访问', Icons.language_rounded, _themeAccent, true,
        type: _FeatureType.website),
    _ExploreFeature(
        '我的世界服务器', '查看服务器在线状态', Icons.public_rounded, _themeAccent, true,
        type: _FeatureType.minecraftServer),
    _ExploreFeature(
        '好友动态', '看看朋友最近在做什么', Icons.dynamic_feed_rounded, _themeAccent, true,
        type: _FeatureType.moments),
    _ExploreFeature(
        '出行规划', '安排日期、节点与旅行详情', Icons.map_rounded, _themeAccent, true,
        type: _FeatureType.travelPlanner),
    _ExploreFeature('通知自己', '定时提醒重要事项', Icons.notifications_active_rounded,
        _themeAccent, true,
        type: _FeatureType.selfNotification),
    _ExploreFeature(
        '时空穿梭', '输入时间开启穿梭倒计时', Icons.travel_explore_rounded, _themeAccent, true,
        type: _FeatureType.timeTravel),
    _ExploreFeature(
        '我的调酒台', '管理原料，发现现在能调的酒', Icons.local_bar_rounded, _themeAccent, true,
        type: _FeatureType.cocktailBar),
    _ExploreFeature(
        '调酒笔记', '记录你的配方与灵感', Icons.edit_note_rounded, _themeAccent, true,
        type: _FeatureType.cocktailNotes),
    _ExploreFeature(
        '调酒配方', '浏览经典调酒配方', Icons.local_bar_rounded, _themeAccent, true,
        type: _FeatureType.cocktailRecipes),
  ];

  @override
  void initState() {
    super.initState();
    _loadRemoteBanners();
    _bannerRefreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _loadRemoteBanners();
    });
    _loadFriends();
    _loadFriendChats();
    _loadFeatureSettings();
    _loadPersistedFeatures();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdate(promptOnlyIfUpdate: true);
    });
    _bannerTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_bannerController.hasClients) return;
      _bannerController.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _loadPersistedFeatures() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString('home_features');
    List<_ExploreFeature> decode(String? value) {
      if (value == null) return [];
      dynamic decoded;
      try {
        decoded = jsonDecode(value);
      } on FormatException {
        return [];
      }
      if (decoded is! List) return [];
      return decoded.whereType<Map>().map((item) {
        final savedType = item['type']?.toString();
        final type = savedType == _FeatureType.website.name
            ? _FeatureType.website
            : savedType == _FeatureType.selfNotification.name
                ? _FeatureType.selfNotification
                : savedType == _FeatureType.timeTravel.name
                    ? _FeatureType.timeTravel
                    : savedType == _FeatureType.postalCode.name
                        ? _FeatureType.postalCode
                        : savedType == _FeatureType.moments.name ||
                                item['title'] == '好友动态'
                            ? _FeatureType.moments
                            : savedType == _FeatureType.travelPlanner.name ||
                                    item['title'] == '出行规划'
                                ? _FeatureType.travelPlanner
                                : savedType ==
                                            _FeatureType.minecraftServer.name ||
                                        item['title']
                                                ?.toString()
                                                .startsWith('我的世界服务器') ==
                                            true
                                    ? _FeatureType.minecraftServer
                                    : savedType == _FeatureType.cocktailBar.name
                                        ? _FeatureType.cocktailBar
                                        : savedType ==
                                                _FeatureType.cocktailNotes.name
                                            ? _FeatureType.cocktailNotes
                                            : savedType ==
                                                    _FeatureType
                                                        .cocktailRecipes.name
                                                ? _FeatureType.cocktailRecipes
                                                : _FeatureType.standard;
        return _ExploreFeature(
          item['title']?.toString() ?? '功能',
          item['subtitle']?.toString() ?? '',
          Icons.extension_rounded,
          _themeAccent,
          item['visible'] != false,
          id: item['id']?.toString(),
          type: type,
          websiteUrl: item['websiteUrl']?.toString(),
          notificationName: item['notificationName']?.toString(),
          notificationContent: item['notificationContent']?.toString(),
          notificationIconPath: item['notificationIconPath']?.toString(),
          notificationIconBase64: item['notificationIconBase64']?.toString(),
        );
      }).toList();
    }

    final restored = decode(raw);
    if (!mounted || restored.isEmpty) return;
    final missing = _availableFeatureTemplates.where(
        (template) => !restored.any((item) => item.type == template.type));
    setState(() {
      _features
        ..clear()
        ..addAll(restored)
        ..addAll(missing.map((item) => _ExploreFeature(
              item.title,
              item.subtitle,
              item.icon,
              _themeAccent,
              true,
              type: item.type,
            )));
    });
    await _persistFeatures();
  }

  Future<void> _loadFeatureSettings() async {
    final preferences = await SharedPreferences.getInstance();
    final website =
        _features.firstWhere((item) => item.type == _FeatureType.website);
    const prefix = 'website_card_';
    final url = preferences.getString('$prefix${website.id}_url') ??
        preferences.getString('website_card_url') ??
        '';
    final name = preferences.getString('$prefix${website.id}_name') ??
        preferences.getString('website_card_name') ??
        '';
    final subtitle = preferences.getString('$prefix${website.id}_subtitle') ??
        preferences.getString('website_card_subtitle') ??
        '';
    if (!mounted) return;
    setState(() {
      website.websiteUrl = url;
      if (name.isNotEmpty) website.title = name;
      if (subtitle.isNotEmpty) website.subtitle = subtitle;
    });
  }

  Future<void> _saveWebsiteCard(_ExploreFeature feature) async {
    final preferences = await SharedPreferences.getInstance();
    final prefix = 'website_card_${feature.id}_';
    await Future.wait([
      preferences.setString('${prefix}url', feature.websiteUrl ?? ''),
      preferences.setString('${prefix}name', feature.title),
      preferences.setString('${prefix}subtitle', feature.subtitle),
    ]);
  }

  Future<void> _loadFriendChats() async {
    try {
      final chatService = context.read<ChatService>();
      await chatService.loadChatList();
      if (!mounted) return;
      final currentUserId = chatService.currentUserId;
      for (final chat in chatService.chatList) {
        final members = chat['members'];
        if (members is! List) continue;
        final friendId = members.map((member) => member.toString()).firstWhere(
              (member) => member != currentUserId,
              orElse: () => '',
            );
        final chatId =
            (chat['id'] ?? chat['conversation_id'] ?? chat['chatId'] ?? '')
                .toString();
        if (friendId.isNotEmpty && chatId.isNotEmpty) {
          _friendChatIds[friendId] = chatId;
        }
      }
      setState(() {});
    } catch (error) {
      debugPrint('[Home] 加载好友会话映射失败: $error');
    }
  }

  Future<void> _loadFriends({bool refresh = false}) async {
    if (_friendsLoading || _friendsRefreshing) return;
    setState(() {
      if (refresh) {
        _friendsRefreshing = true;
      } else {
        _friendsLoading = true;
      }
      _friendsError = null;
    });
    try {
      final response = await ApiClient().get('/friends').timeout(
            const Duration(seconds: 12),
          );
      final raw = response.data is Map ? response.data['data'] : response.data;
      if (raw is! List) throw const FormatException('好友列表格式错误');
      if (!mounted) return;
      final unique = <String, Map<String, dynamic>>{};
      for (final item in raw.whereType<Map>()) {
        final friend = Map<String, dynamic>.from(item);
        final key = (friend['id'] ?? friend['uid'] ?? friend['nickname'])
            .toString()
            .trim();
        if (key.isNotEmpty) unique[key] = friend;
      }
      setState(() {
        _friends = unique.values.toList();
      });
    } on TimeoutException {
      if (mounted) setState(() => _friendsError = '网络响应较慢，请点击重试');
    } catch (error) {
      if (mounted) {
        setState(() =>
            _friendsError = context.read<AuthService>().errorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() {
          _friendsLoading = false;
          _friendsRefreshing = false;
        });
      }
    }
  }

  /* Future<void> _loadChatSettings() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _pinnedChats
        ..clear()
        ..addAll(preferences.getStringList(_chatPinnedKey) ?? const []);
      _unreadChats
        ..clear()
        ..addAll(preferences.getStringList(_chatUnreadKey) ?? const []);
      _chatSettingsLoaded = true;
    });
  }

  Future<void> _persistChatSettings() async {
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.setStringList(_chatPinnedKey, _pinnedChats.toList()),
      preferences.setStringList(_chatUnreadKey, _unreadChats.toList()),
    ]);
  }

  Future<void> _updateChatSettings(String chatId,
      {bool? pinned, bool? unread}) async {
    if (chatId.startsWith('demo-')) return;
    try {
      await ApiClient().put('/chat-settings/$chatId', data: {
        if (pinned != null) 'pinned': pinned,
        if (unread != null) 'unread': unread,
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('聊天设置同步失败，已保留本地状态')));
      }
    }
  }

  */

  Future<void> _loadRemoteBanners() async {
    try {
      final response =
          await ApiClient().get('/banners', authenticated: false, params: {
        'platform': 'android',
        'enabled': true,
      });
      final raw = response.data is Map && response.data['data'] is List
          ? response.data['data'] as List
          : response.data is List
              ? response.data as List
              : const [];
      if (!mounted) return;
      setState(() {
        _remoteBanners = raw
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      });
    } catch (_) {
      // 网络不可用时继续使用本地横幅。
    }
  }

  @override
  void dispose() {
    SwipeableChatTile.closeActive();
    _bannerTimer?.cancel();
    _bannerRefreshTimer?.cancel();
    _searchController.dispose();
    _bannerController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          onPageChanged: (index) {
            if (_selectedIndex != index) {
              setState(() => _selectedIndex = index);
            }
          },
          children: [_buildFriends(), _buildTavern(), _buildProfile()],
        ),
      ),
      bottomNavigationBar: _buildPillNavigationBar(),
    );
  }

  Widget _buildPillNavigationBar() {
    const items = [
      (Icons.people_outline, Icons.people, '好友'),
      (Icons.local_bar_outlined, Icons.local_bar, '小酒馆'),
      (Icons.person_outline, Icons.person, '我的'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          boxShadow: AppShadows.floating(context),
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: SizedBox(
            height: 54,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final itemWidth = constraints.maxWidth / items.length;
                return Stack(
                  children: [
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutCubic,
                      left: itemWidth * _selectedIndex,
                      top: 0,
                      width: itemWidth,
                      height: 54,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          boxShadow: AppShadows.floating(context),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (var index = 0; index < items.length; index++)
                          Expanded(
                            child: Semantics(
                              button: true,
                              selected: _selectedIndex == index,
                              label: '${items[index].$3}页面',
                              child: InkWell(
                                borderRadius:
                                    BorderRadius.circular(AppRadius.pill),
                                onTap: () {
                                  if (_selectedIndex == index) return;
                                  _pageController.animateToPage(
                                    index,
                                    duration: const Duration(milliseconds: 360),
                                    curve: Curves.easeOutCubic,
                                  );
                                },
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      _selectedIndex == index
                                          ? items[index].$2
                                          : items[index].$1,
                                      color: _selectedIndex == index
                                          ? Colors.white
                                          : Colors.white60,
                                      size: 21,
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      items[index].$3,
                                      style: TextStyle(
                                        color: _selectedIndex == index
                                            ? Colors.white
                                            : Colors.white60,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFriends() {
    final auth = context.watch<AuthService>();
    if (auth.isGuest) return _buildGuestFriendsPrompt();
    final keyword = _searchController.text.trim().toLowerCase();
    final visibleFriends = _friends.where((friend) {
      final name = friend['nickname']?.toString().toLowerCase() ?? '';
      final uid = friend['uid']?.toString().toLowerCase() ?? '';
      return keyword.isEmpty || name.contains(keyword) || uid.contains(keyword);
    }).toList();
    return RefreshIndicator(
      onRefresh: () => _loadFriends(refresh: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 26, 20, 18),
        children: [
          _sectionIntro(
            '嗨，${auth.user?['nickname'] ?? 'Komang'}',
            '今天也和朋友玩点开心的吧',
            Icons.person_add_alt_1_rounded,
            _showAddFriendDialog,
          ),
          const SizedBox(height: 24),
          _buildSearchField(),
          const SizedBox(height: 26),
          Row(
            children: [
              Expanded(child: _sectionLabel('好友', '${_friends.length} 位好友')),
              if (_friendsRefreshing)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_friendsLoading)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_friendsError != null && _friends.isEmpty)
            _buildFriendsError()
          else if (visibleFriends.isEmpty)
            _buildEmptyFriends(keyword.isEmpty ? '还没有好友，先添加一位吧' : '没有匹配的好友')
          else
            ...visibleFriends.map(_buildFriendCard),
        ],
      ),
    );
  }

  Widget _buildFriendsError() {
    return AppCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 42),
          const SizedBox(height: 10),
          Text(_friendsError!, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () => _loadFriends(),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重新加载'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyFriends(String message) {
    return AppCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(Icons.people_outline_rounded,
              size: 48, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildFriendCard(Map<String, dynamic> friend) {
    final friendId =
        (friend['id'] ?? friend['user_id'] ?? friend['uid'] ?? '').toString();
    final id = (friend['chat_id'] ??
            friend['chatId'] ??
            _friendChatIds[friendId] ??
            '')
        .toString();
    final chat = context.read<ChatService>().chatList.firstWhere(
          (item) =>
              (item['id'] ?? item['conversation_id'] ?? item['chatId'] ?? '')
                  .toString() ==
              id,
          orElse: () => const <String, dynamic>{},
        );
    final unread = chat['unread'] == true || friend['unread'] == true;
    final pinned = chat['pinned'] == true || friend['pinned'] == true;
    final name = friend['nickname']?.toString().trim();
    final nickname = name?.isNotEmpty == true ? name! : '未命名好友';
    final avatar =
        friend['avatar_url']?.toString() ?? friend['avatar']?.toString();
    final online = friend['online'] == true;
    final preview = chat['last_message'] is Map
        ? chat['last_message']['content']?.toString()
        : chat['last_message']?.toString();
    final lastMessage = preview?.isNotEmpty == true
        ? preview!
        : (friend['last_message']?.toString() ?? '点击开始聊天');
    final lastTime = chat['last_message_at']?.toString() ??
        chat['updated_at']?.toString() ??
        friend['last_message_at']?.toString() ??
        '';
    return SwipeableChatTile(
      key: ValueKey('friend-$id'),
      name: nickname,
      text: lastMessage,
      icon: Icons.person_rounded,
      avatar: avatar,
      online: online,
      time: lastTime,
      isRead: !unread,
      isUnread: unread,
      isPinned: pinned,
      onTap: () => _openFriendChat(friend, friendId, nickname, id),
      onMarkUnread: () =>
          _handleFriendFlag(friend, friendId, id, 'unread', !unread),
      onTogglePin: () =>
          _handleFriendFlag(friend, friendId, id, 'pinned', !pinned),
      onSettings: () => _showFriendSettings(friend),
    );
  }

  Future<void> _openFriendChat(
    Map<String, dynamic> friend,
    String friendId,
    String nickname,
    String chatId,
  ) async {
    final service = context.read<ChatService>();
    final resolvedId = chatId.isNotEmpty
        ? chatId
        : await service.getOrCreatePrivateChat(friendId);
    if (!mounted || resolvedId == null || resolvedId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('暂时无法创建聊天会话，请稍后重试')),
        );
      }
      return;
    }
    _friendChatIds[friendId] = resolvedId;
    Navigator.pushNamed(context, AppRoutes.chatDetail, arguments: {
      'chatId': resolvedId,
      'chatName': nickname,
      'receiverId': friendId,
    });
  }

  Future<void> _handleFriendFlag(Map<String, dynamic> friend, String friendId,
      String chatId, String field, bool value) async {
    final resolvedId = chatId.isNotEmpty
        ? chatId
        : await context.read<ChatService>().getOrCreatePrivateChat(friendId);
    if (!mounted || resolvedId == null || resolvedId.isEmpty) return;
    _friendChatIds[friendId] = resolvedId;
    await _setFriendFlag(friendId, resolvedId, field, value);
  }

  Future<void> _setFriendFlag(
      String friendId, String chatId, String field, bool value) async {
    final chatService = context.read<ChatService>();
    final index = _friends.indexWhere((friend) =>
        (friend['id'] ?? friend['user_id'] ?? friend['uid'] ?? '').toString() ==
        friendId);
    if (index < 0 || chatId.isEmpty) return;
    final previous = _friends[index][field] == true;
    setState(() => _friends[index][field] = value);
    try {
      await chatService.updateChatSetting(chatId, field, value);
    } catch (_) {
      if (mounted) setState(() => _friends[index][field] = previous);
    }
  }

  Future<void> _deleteFriend(String friendId, String nickname) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除好友？'),
        content: Text('删除“$nickname”后，对方将不再出现在好友列表中，但历史聊天记录不会删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    try {
      await ApiClient().delete('/friends/$friendId');
      if (!mounted) return;
      setState(() {
        _friends.removeWhere((item) =>
            (item['id'] ?? item['user_id'] ?? item['uid'] ?? '').toString() ==
            friendId);
        _friendChatIds.remove(friendId);
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已删除好友“$nickname”')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('删除好友失败：$error')));
    }
  }

  Future<void> _showFriendSettings(Map<String, dynamic> friend) async {
    final friendId =
        (friend['id'] ?? friend['user_id'] ?? friend['uid'] ?? '').toString();
    final chatService = context.read<ChatService>();
    final chatId = (friend['chat_id'] ??
            friend['chatId'] ??
            _friendChatIds[friendId] ??
            '')
        .toString();
    final chat = chatService.chatList.firstWhere(
      (item) =>
          (item['id'] ?? item['conversation_id'] ?? item['chatId'] ?? '')
              .toString() ==
          chatId,
      orElse: () => <String, dynamic>{},
    );
    var unread = chat['unread'] == true || friend['unread'] == true;
    var pinned = chat['pinned'] == true || friend['pinned'] == true;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: Text('UID：${friend['uid'] ?? friend['id'] ?? ''}'),
                subtitle: Text(friend['online'] == true ? '当前在线' : '当前离线'),
              ),
              SwitchListTile(
                title: const Text('未读提醒'),
                value: unread,
                onChanged: (value) {
                  setSheetState(() => unread = value);
                  unawaited(_handleFriendFlag(
                      friend, friendId, chatId, 'unread', value));
                },
              ),
              SwitchListTile(
                title: const Text('置顶会话'),
                value: pinned,
                onChanged: (value) {
                  setSheetState(() => pinned = value);
                  unawaited(_handleFriendFlag(
                      friend, friendId, chatId, 'pinned', value));
                },
              ),
              const Divider(),
              ListTile(
                leading: Icon(Icons.person_remove_outlined,
                    color: Theme.of(sheetContext).colorScheme.error),
                title: Text('删除好友',
                    style: TextStyle(
                        color: Theme.of(sheetContext).colorScheme.error)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  unawaited(_deleteFriend(
                      friendId, friend['nickname']?.toString() ?? '该好友'));
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGuestFriendsPrompt() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: AppCard(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people_alt_outlined, size: 58, color: scheme.primary),
              const SizedBox(height: 18),
              const Text('登录后使用好友功能',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text('游客可以浏览小酒馆内容，登录后即可聊天、添加好友和查看动态。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: scheme.onSurface.withValues(alpha: .68))),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: () =>
                    Navigator.pushReplacementNamed(context, AppRoutes.login),
                icon: const Icon(Icons.login_rounded),
                label: const Text('立即登录'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField() => AppSearchField(
        hint: '搜索好友或群聊',
        controller: _searchController,
        onChanged: (_) => setState(() {}),
      );

  Widget _buildTavern() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
      children: [
        _sectionIntro(
            '小酒馆', '挑一个喜欢的功能，现在就开始', Icons.tune_rounded, _showFeatureSettings),
        const SizedBox(height: 22),
        _buildTeamBanner(),
        const SizedBox(height: 28),
        _sectionLabel('探索功能', '探索', _showExploreFeatures),
        const SizedBox(height: 16),
        _buildFeatureGrid(),
      ],
    );
  }

  Widget _sectionIntro(
      String title, String subtitle, IconData icon, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 28,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(subtitle,
                style: TextStyle(
                    color: scheme.primary.withValues(alpha: .78),
                    fontSize: 13)),
          ]),
        ),
        Material(
          color: scheme.surface,
          shape: const CircleBorder(),
          child: IconButton(
              onPressed: onTap, icon: Icon(icon, color: scheme.primary)),
        ),
      ],
    );
  }

  Widget _sectionLabel(String title, String action, [VoidCallback? onTap]) {
    final label = Text(action,
        style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontSize: 12,
            fontWeight: FontWeight.w700));
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w800)),
        onTap == null
            ? label
            : InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    child: label),
              ),
      ],
    );
  }

  Widget _buildTeamBanner() {
    final scheme = Theme.of(context).colorScheme;
    const fallbackBanners = [
      ('好友互动', '聊聊天，\n保持联系', '和朋友分享每一个日常瞬间', Icons.groups_rounded),
      ('轻松社交', '聊聊天，\n发现乐趣', '在小酒馆发现更多精彩内容', Icons.forum_rounded),
      ('今日推荐', '调一杯酒，\n放松一下', '浏览经典调酒配方', Icons.local_bar_rounded),
    ];
    final useRemote = _remoteBanners.isNotEmpty;
    final bannerCount =
        useRemote ? _remoteBanners.length : fallbackBanners.length;

    return SizedBox(
      height: 168,
      child: PageView.builder(
        controller: _bannerController,
        itemCount: 3000,
        itemBuilder: (context, index) {
          final raw = useRemote ? _remoteBanners[index % bannerCount] : null;
          final label = useRemote
              ? _remoteText(raw, 'label')
              : fallbackBanners[index % bannerCount].$1;
          final title = useRemote
              ? _remoteText(raw, 'title')
              : fallbackBanners[index % bannerCount].$2;
          final description = useRemote
              ? _remoteText(raw, 'description')
              : fallbackBanners[index % bannerCount].$3;
          final icon = useRemote
              ? _iconFromName(_remoteText(raw, 'icon'),
                  fallbackBanners[index % fallbackBanners.length].$4)
              : fallbackBanners[index % bannerCount].$4;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      scheme.primary,
                      Color.alphaBlend(
                        Colors.white.withValues(alpha: .10),
                        scheme.primary,
                      ),
                    ],
                    begin: Alignment.bottomLeft,
                    end: Alignment.topRight,
                  ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned(
                      right: -34,
                      bottom: -46,
                      child: Icon(
                        icon,
                        size: 190,
                        color: Colors.white.withValues(alpha: .10),
                      ),
                    ),
                    Positioned(
                      right: 24,
                      top: 22,
                      child: Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .18),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          icon,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 22,
                      top: 20,
                      right: 92,
                      bottom: 18,
                      child: Stack(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                label,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 7),
                              SizedBox(
                                height: 82,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.topLeft,
                                  child: SizedBox(
                                    width: 230,
                                    child: Text(
                                      title,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 27,
                                        height: 1.08,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Text(
                              description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProfile() {
    final scheme = Theme.of(context).colorScheme;
    final auth = context.watch<AuthService>();
    final nickname =
        auth.user?['nickname']?.toString() ?? (auth.isGuest ? '游客' : 'Komang');
    final uid = auth.user?['uid']?.toString() ??
        auth.user?['id']?.toString() ??
        '未分配UID';
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 18),
      children: [
        _sectionIntro(
            '我的', '管理个人资料与应用设置', Icons.settings_outlined, _showMySettings),
        const SizedBox(height: 22),
        InkWell(
          onTap: _showProfileSettings,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Row(children: [
              AppAvatar(
                source: auth.user?['avatar_url']?.toString() ??
                    auth.user?['avatar']?.toString(),
                radius: 34,
                icon: Icons.face_rounded,
              ),
              const SizedBox(width: 15),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(nickname,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 5),
                    Text(auth.isGuest ? '游客模式 · 登录后解锁全部功能' : 'UID：$uid',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13)),
                  ])),
              const Icon(Icons.chevron_right_rounded, color: Colors.white70),
            ]),
          ),
        ),
        const SizedBox(height: 24),
        _sectionLabel('设置', '个人偏好'),
        const SizedBox(height: 12),
        _profileItem(
            Icons.favorite_border, '我的收藏', '保存喜欢的内容', _showLoginRequired),
        _profileItem(
            Icons.shield_outlined, '账号与安全', '保护你的账号', _showAccountSecurity),
        _profileItem(Icons.notifications_none, '消息通知', '设置提醒方式',
            _showNotificationSettings),
        _profileItem(
            Icons.palette_outlined, '外观设置', '默认主题', _showColorSettings),
        _profileItem(Icons.help_outline, '帮助与反馈', '遇到问题联系我们', _showHelp),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton.icon(
            onPressed: () => _showLogoutDialog(auth),
            icon:
                Icon(auth.isGuest ? Icons.login_rounded : Icons.logout_rounded),
            label: Text(auth.isGuest ? '登录账号' : '退出登录'),
          ),
        ),
      ],
    );
  }

  String _remoteText(Map<String, dynamic>? value, String key) =>
      value?[key]?.toString() ?? '';

  IconData _iconFromName(String? name, IconData fallback) {
    const icons = <String, IconData>{
      'groups_rounded': Icons.groups_rounded,
      'forum_rounded': Icons.forum_rounded,
      'auto_awesome_rounded': Icons.auto_awesome_rounded,
      'grid_3x3_rounded': Icons.grid_3x3_rounded,
    };
    return icons[name] ?? fallback;
  }

  Widget _buildFeatureGrid() {
    final visibleFeatures =
        _features.where((feature) => feature.visible).toList();
    if (visibleFeatures.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('暂无启用的功能')),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: visibleFeatures.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.08,
      ),
      itemBuilder: (context, index) => _featureCard(visibleFeatures[index]),
    );
  }

  Widget _featureCard(_ExploreFeature feature) {
    final scheme = Theme.of(context).colorScheme;
    if (feature.type == _FeatureType.website) {
      return _websiteFeatureCard(feature);
    }
    if (feature.type == _FeatureType.minecraftServer) {
      return ChangeNotifierProvider(
        create: (_) => MinecraftServerService(profileKey: feature.id),
        child: Consumer<MinecraftServerService>(
          builder: (context, service, _) =>
              _minecraftFeatureCard(context, service.server, feature),
        ),
      );
    }
    if (feature.type == _FeatureType.selfNotification) {
      return _selfNotificationCard(feature);
    }
    if (feature.type == _FeatureType.timeTravel) {
      return _timeTravelCard(feature);
    }
    if (feature.type == _FeatureType.postalCode) {
      return _postalCodeFeatureCard(feature);
    }
    if (feature.type == _FeatureType.cocktailBar ||
        feature.type == _FeatureType.cocktailNotes ||
        feature.type == _FeatureType.cocktailRecipes) {
      return _cocktailFeatureCard(feature);
    }
    return InkWell(
      onLongPress: () => _showFeatureActions(feature),
      onTap: () {
        if (feature.type == _FeatureType.selfNotification) {
          _showSelfNotification(feature);
        }
        if (feature.type == _FeatureType.postalCode) {
          Navigator.pushNamed(context, AppRoutes.postalCode);
        }
        if (feature.type == _FeatureType.timeTravel) {
          _showTimeTravel(feature);
        }
        if (feature.type == _FeatureType.cocktailBar) {
          Navigator.pushNamed(context, AppRoutes.cocktailBar);
        }
        if (feature.type == _FeatureType.cocktailNotes) {
          Navigator.pushNamed(context, AppRoutes.cocktailNotes);
        }
        if (feature.type == _FeatureType.cocktailRecipes) {
          Navigator.pushNamed(context, AppRoutes.cocktailRecipes);
        }
        if (feature.type == _FeatureType.moments) {
          Navigator.pushNamed(context, AppRoutes.moments);
        }
        if (feature.type == _FeatureType.minecraftServer) {
          Navigator.pushNamed(context, AppRoutes.minecraftServer);
        }
        if (feature.type == _FeatureType.travelPlanner) {
          Navigator.pushNamed(context, AppRoutes.travelPlanner);
        }
      },
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: feature.color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: feature.color.withValues(alpha: .16)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  foregroundColor: feature.color,
                  child: Icon(feature.icon)),
              Icon(Icons.arrow_forward_rounded, color: feature.color, size: 20),
            ]),
            const Spacer(),
            Text(feature.title,
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface)),
            const SizedBox(height: 4),
            Text(feature.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withValues(alpha: .72))),
          ],
        ),
      ),
    );
  }

  Widget _selfNotificationCard(_ExploreFeature feature) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _showSelfNotification(feature),
      onLongPress: () => _showFeatureActions(feature),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: feature.color.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              backgroundColor: scheme.surface,
              foregroundColor: feature.color,
              backgroundImage: feature.notificationIconBytes == null
                  ? null
                  : MemoryImage(feature.notificationIconBytes!),
              child: feature.notificationIconBytes == null
                  ? Icon(feature.icon)
                  : null,
            ),
            const Spacer(),
            Icon(Icons.send_rounded, color: feature.color, size: 20),
          ]),
          const Spacer(),
          Text(feature.title,
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface)),
          const SizedBox(height: 4),
          Text(
              feature.notificationName?.isNotEmpty == true
                  ? feature.notificationName!
                  : feature.subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurface.withValues(alpha: .72))),
        ]),
      ),
    );
  }

  Future<void> _showSelfNotification(_ExploreFeature feature) async {
    final name = TextEditingController(text: feature.notificationName ?? '');
    final content =
        TextEditingController(text: feature.notificationContent ?? '');
    String? iconPath = feature.notificationIconPath;
    final picker = ImagePicker();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('通知自己'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: name,
                  decoration: const InputDecoration(
                      labelText: '通知名称', hintText: '例如：记得带伞')),
              const SizedBox(height: 12),
              TextField(
                  controller: content,
                  maxLines: 4,
                  decoration: const InputDecoration(
                      labelText: '通知内容', hintText: '输入要提醒自己的内容')),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final image = await picker.pickImage(
                      source: ImageSource.gallery, imageQuality: 82);
                  if (image != null) {
                    final bytes = await image.readAsBytes();
                    if (!mounted) return;
                    if (bytes.length > 2 * 1024 * 1024) {
                      messenger.showSnackBar(
                        const SnackBar(content: Text('通知图标不能超过 2 MB')),
                      );
                      return;
                    }
                    setState(() {
                      iconPath = image.path;
                      feature.notificationIconBase64 = base64Encode(bytes);
                    });
                  }
                },
                icon: const Icon(Icons.image_outlined),
                label: Text(iconPath == null ? '添加通知图标' : '更换通知图标'),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                if (content.text.trim().isEmpty) return;
                feature.notificationName =
                    name.text.trim().isEmpty ? '通知自己' : name.text.trim();
                feature.notificationContent = content.text.trim();
                feature.notificationIconPath = iconPath;
                final notifications = Provider.of<MessageNotificationService>(
                    this.context,
                    listen: false);
                final navigator = Navigator.of(dialogContext);
                await _persistFeatures();
                if (!mounted) return;
                navigator.pop();
                await notifications.showCustomNotification(
                    feature.notificationName!, feature.notificationContent!,
                    iconPath: iconPath);
              },
              child: const Text('发送通知'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    content.dispose();
  }

  Widget _timeTravelCard(_ExploreFeature feature) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _showTimeTravel(feature),
      onLongPress: () => _showFeatureActions(feature),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: feature.color.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              backgroundColor: scheme.surface,
              foregroundColor: feature.color,
              child: Icon(feature.icon),
            ),
            const Spacer(),
            Icon(Icons.hourglass_bottom_rounded,
                color: feature.color, size: 20),
          ]),
          const Spacer(),
          Text(feature.title,
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface)),
          const SizedBox(height: 4),
          Text(feature.subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurface.withValues(alpha: .72))),
        ]),
      ),
    );
  }

  Future<void> _showTimeTravel(_ExploreFeature feature) async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('时空穿梭'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: '穿梭时间',
            hintText: '输入时间开始穿梭',
            suffixText: '秒',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final seconds = int.tryParse(controller.text.trim());
              if (seconds == null || seconds < 1 || seconds > 86400) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('请输入 1 至 86400 秒')),
                );
                return;
              }
              Navigator.pop(dialogContext);
              _startTimeTravelCountdown(seconds);
            },
            child: const Text('开始'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<void> _startTimeTravelCountdown(int seconds) async {
    var remaining = seconds;
    Timer? timer;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
            if (remaining <= 1) {
              timer?.cancel();
              if (Navigator.of(dialogContext).canPop()) {
                Navigator.pop(dialogContext);
              }
              if (mounted) {
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(content: Text('时空穿梭成功')),
                );
              }
              return;
            }
            setState(() => remaining--);
          });
          return AlertDialog(
            title: const Text('正在穿梭'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.travel_explore_rounded, size: 64, color: _themeAccent),
              const SizedBox(height: 16),
              Text(_formatTravelDuration(remaining),
                  style: const TextStyle(
                      fontSize: 32, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text('请等待时空通道稳定...'),
            ]),
            actions: [
              TextButton(
                onPressed: () {
                  timer?.cancel();
                  timer = null;
                  Navigator.pop(dialogContext);
                },
                child: const Text('取消穿梭'),
              ),
            ],
          );
        },
      ),
    );
    timer?.cancel();
  }

  String _formatTravelDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final rest = seconds % 60;
    if (hours > 0) return '$hours时 $minutes分 $rest秒';
    if (minutes > 0) return '$minutes分 $rest秒';
    return '$rest秒';
  }

  Widget _cocktailFeatureCard(_ExploreFeature feature) {
    final scheme = Theme.of(context).colorScheme;
    final route = feature.type == _FeatureType.cocktailBar
        ? AppRoutes.cocktailBar
        : feature.type == _FeatureType.cocktailNotes
            ? AppRoutes.cocktailNotes
            : AppRoutes.cocktailRecipes;
    return InkWell(
      onTap: () => Navigator.pushNamed(context, route),
      onLongPress: () => _showFeatureActions(feature),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: feature.color.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              backgroundColor: scheme.surface,
              foregroundColor: feature.color,
              child: Icon(feature.icon),
            ),
            const Spacer(),
            Icon(feature.icon, color: feature.color, size: 20),
          ]),
          const Spacer(),
          Text(feature.title,
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface)),
          const SizedBox(height: 4),
          Text(feature.subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurface.withValues(alpha: .72))),
        ]),
      ),
    );
  }

  Widget _postalCodeFeatureCard(_ExploreFeature feature) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => Navigator.pushNamed(context, AppRoutes.postalCode),
      onLongPress: () => _showFeatureActions(feature),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: feature.color.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              backgroundColor: scheme.surface,
              foregroundColor: feature.color,
              child: Icon(feature.icon),
            ),
            const Spacer(),
            Icon(Icons.search_rounded, color: feature.color, size: 20),
          ]),
          const Spacer(),
          Text(feature.title,
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface)),
          const SizedBox(height: 4),
          Text(feature.subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurface.withValues(alpha: .72))),
        ]),
      ),
    );
  }

  Widget _websiteFeatureCard(_ExploreFeature feature) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => _openWebsite(feature),
      onLongPress: () => _showFeatureActions(feature),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: scheme.surface,
                  foregroundColor: feature.color,
                  child: Icon(feature.icon),
                ),
                const Spacer(),
                Icon(Icons.open_in_new_rounded, color: feature.color, size: 20),
              ],
            ),
            const Spacer(),
            Text(feature.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 17,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
                feature.websiteUrl?.isNotEmpty == true
                    ? feature.websiteUrl!
                    : feature.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    TextStyle(color: scheme.onSurface.withValues(alpha: .72))),
          ],
        ),
      ),
    );
  }

  Future<void> _openWebsite(_ExploreFeature feature) async {
    if (feature.websiteUrl?.isEmpty != false) {
      await _showWebsiteBinding(feature);
      return;
    }
    if (kIsWeb) {
      await launchUrl(Uri.parse(feature.websiteUrl!),
          mode: LaunchMode.externalApplication);
      return;
    }
    if (!mounted) return;
    Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              WebsitePage(title: feature.title, url: feature.websiteUrl!),
        ));
  }

  Future<void> _showWebsiteBinding(_ExploreFeature feature) async {
    final urlController = TextEditingController(text: feature.websiteUrl ?? '');
    final nameController =
        TextEditingController(text: feature.title == '网站' ? '' : feature.title);
    final subtitleController = TextEditingController(
        text: feature.subtitle == '绑定网站后在 App 内访问' ? '' : feature.subtitle);
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('绑定网站'),
        content: StatefulBuilder(
          builder: (context, setDialogState) => SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _siteInput(
                context,
                controller: nameController,
                label: '网站名称',
                icon: Icons.title_rounded,
                onChanged: (_) => setDialogState(() => error = null),
              ),
              const SizedBox(height: 16),
              _siteInput(
                context,
                controller: urlController,
                label: '网站地址',
                hint: 'https://example.com',
                icon: Icons.link_rounded,
                keyboardType: TextInputType.url,
                onChanged: (_) => setDialogState(() => error = null),
              ),
              const SizedBox(height: 16),
              _siteInput(
                context,
                controller: subtitleController,
                label: '卡片描述',
                icon: Icons.notes_rounded,
                onChanged: (_) => setDialogState(() => error = null),
              ),
              if (error != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12)),
                ),
              ],
            ]),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              FocusScope.of(dialogContext).unfocus(
                disposition: UnfocusDisposition.scope,
              );
              await WidgetsBinding.instance.endOfFrame;
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext);
              }
            },
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              var url = urlController.text.trim();
              if (url.isEmpty) {
                setState(() => error = '请输入网站地址');
                return;
              }
              if (!url.startsWith('http://') && !url.startsWith('https://')) {
                url = 'https://$url';
              }
              final uri = Uri.tryParse(url);
              if (uri == null ||
                  uri.scheme != 'https' ||
                  uri.host.isEmpty ||
                  uri.userInfo.isNotEmpty ||
                  (uri.port != 0 && uri.port != 443)) {
                setState(() => error = '请输入 HTTPS 网站地址（默认端口 443）');
                return;
              }
              feature.websiteUrl = uri.toString();
              feature.title = nameController.text.trim().isEmpty
                  ? '网站'
                  : nameController.text.trim();
              feature.subtitle = subtitleController.text.trim().isEmpty
                  ? '在 App 内访问网站'
                  : subtitleController.text.trim();
              _saveWebsiteCard(feature);
              setState(() {});
              Navigator.pop(dialogContext);
            },
            child: const Text('绑定并打开'),
          ),
        ],
      ),
    );
    urlController.dispose();
    nameController.dispose();
    subtitleController.dispose();
  }

  Widget _siteInput(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required ValueChanged<String> onChanged,
    VoidCallback? onTap,
    String? hint,
    TextInputType? keyboardType,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      onTap: onTap,
      onTapOutside: (_) {
        if (!context.mounted) return;
        FocusScope.of(context).unfocus(
          disposition: UnfocusDisposition.scope,
        );
      },
      onChanged: onChanged,
      style: TextStyle(color: scheme.onSurface),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: .45),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
              color: scheme.outline.withValues(alpha: .42), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
    );
  }

  Future<void> _saveFeatureState() async {
    await _persistFeatures();
  }

  Future<void> _showAddFriendDialog() async {
    final redeemController = TextEditingController();
    var expiry = '1d';
    var loading = true;
    String? error;
    List<_FriendCode> codes = [];
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> loadCodes() async {
              setDialogState(() {
                loading = true;
                error = null;
              });
              try {
                final response = await ApiClient().get('/friends/codes');
                final raw = response.data is Map &&
                        response.data['data'] is List
                    ? response.data['data'] as List
                    : response.data is List
                        ? response.data as List
                        : response.data is Map && response.data['id'] != null
                            ? [response.data]
                            : const [];
                codes = raw
                    .whereType<Map>()
                    .map((item) =>
                        _FriendCode.fromJson(Map<String, dynamic>.from(item)))
                    .toList();
              } catch (e) {
                error = '加载好友数据失败：$e';
              }
              if (dialogContext.mounted) setDialogState(() => loading = false);
            }

            if (loading && codes.isEmpty && error == null) {
              Future.microtask(loadCodes);
            }
            Future<void> createCode() async {
              setDialogState(() {
                loading = true;
                error = null;
              });
              try {
                await ApiClient().post('/friends/codes', data: {
                  'expiry': expiry,
                });
                await loadCodes();
              } catch (e) {
                setDialogState(() {
                  loading = false;
                  error = '生成失败：$e';
                });
              }
            }

            Future<void> updateCode(_FriendCode item) async {
              var selectedExpiry = expiry;
              final nextExpiry = await showDialog<String>(
                context: dialogContext,
                builder: (editContext) => StatefulBuilder(
                  builder: (context, setEditState) => AlertDialog(
                    title: const Text('修改好友代码有效期'),
                    content: DropdownButtonFormField<String>(
                      initialValue: selectedExpiry,
                      isExpanded: true,
                      menuMaxHeight: 280,
                      borderRadius: BorderRadius.circular(14),
                      dropdownColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      decoration: const InputDecoration(
                        labelText: '有效期',
                        prefixIcon: Icon(Icons.schedule_rounded),
                      ),
                      items: const {
                        '1d': '1天',
                        '3d': '3天',
                        '7d': '7天',
                        '30d': '30天',
                        'permanent': '永久有效',
                      }.entries.map((entry) {
                        return DropdownMenuItem<String>(
                          value: entry.key,
                          child: Text(entry.value),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setEditState(() => selectedExpiry = value);
                        }
                      },
                    ),
                    actions: [
                      TextButton(
                        onPressed: () async {
                          FocusScope.of(editContext).unfocus(
                            disposition: UnfocusDisposition.scope,
                          );
                          await WidgetsBinding.instance.endOfFrame;
                          if (editContext.mounted) {
                            Navigator.pop(editContext);
                          }
                        },
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () {
                          Navigator.pop(editContext, selectedExpiry);
                        },
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                ),
              );
              if (nextExpiry == null || !dialogContext.mounted) return;
              setDialogState(() {
                loading = true;
                error = null;
                expiry = nextExpiry;
              });
              try {
                await ApiClient().patch('/friends/codes/${item.id}',
                    data: {'expiry': nextExpiry});
                await loadCodes();
              } catch (e) {
                if (dialogContext.mounted) {
                  setDialogState(() {
                    loading = false;
                    error = '修改失败：$e';
                  });
                }
              }
            }

            Future<void> disableCode(_FriendCode item) async {
              try {
                await ApiClient().delete('/friends/codes/${item.id}');
                await loadCodes();
              } catch (e) {
                setDialogState(() => error = '禁用失败：$e');
              }
            }

            Future<void> permanentlyDeleteCode(_FriendCode item) async {
              try {
                await ApiClient().delete('/friends/codes/${item.id}/permanent');
                await loadCodes();
              } catch (e) {
                setDialogState(() => error = '删除失败：$e');
              }
            }

            Future<void> redeemCode() async {
              final value = redeemController.text.trim().toUpperCase();
              if (value.isEmpty) {
                setDialogState(() => error = '请输入好友代码');
                return;
              }
              if (!RegExp(r'^[A-Z0-9]{10}$').hasMatch(value)) {
                setDialogState(() => error = '好友代码应为10位字母或数字');
                return;
              }
              setDialogState(() {
                loading = true;
                error = null;
              });
              try {
                final response = await ApiClient()
                    .post('/friends/codes/redeem', data: {'code': value});
                await loadCodes();
                await _loadFriends(refresh: true);
                if (dialogContext.mounted) {
                  final responseData = response.data is Map
                      ? Map<String, dynamic>.from(response.data as Map)
                      : <String, dynamic>{};
                  final friend = responseData['user'] is Map
                      ? Map<String, dynamic>.from(responseData['user'] as Map)
                      : <String, dynamic>{};
                  final nickname = friend['nickname']?.toString().trim();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        nickname == null || nickname.isEmpty
                            ? '好友添加成功'
                            : '已添加好友：$nickname',
                      ),
                    ),
                  );
                  redeemController.clear();
                }
              } catch (e) {
                var message = '添加好友失败，请稍后重试';
                if (e is DioException) {
                  final data = e.response?.data;
                  if (data is Map) {
                    final code = data['code']?.toString();
                    message = switch (code) {
                      'FRIEND_CODE_NOT_FOUND' => '好友代码不存在',
                      'FRIEND_CODE_DISABLED' => '好友代码已禁用',
                      'FRIEND_CODE_EXPIRED' => '好友代码已过期',
                      'SELF_CODE_NOT_ALLOWED' => '不能添加自己为好友',
                      'ALREADY_FRIENDS' => '你们已经是好友',
                      'FRIEND_CODE_INVALID_FORMAT' => '好友代码格式不正确',
                      _ => data['message']?.toString() ??
                          data['error']?.toString() ??
                          message,
                    };
                  }
                }
                if (dialogContext.mounted) {
                  setDialogState(() => error = message);
                }
              }
              if (dialogContext.mounted) setDialogState(() => loading = false);
            }

            return AlertDialog(
              title: const Text('好友代码管理'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      const Text('生成代码分享给对方，或输入好友代码添加朋友。'),
                      const SizedBox(height: AppSpacing.md),
                      Row(children: [
                        Expanded(
                            child: DropdownButtonFormField<String>(
                                initialValue: expiry,
                                decoration: InputDecoration(
                                  labelText: '有效期',
                                  prefixIcon:
                                      const Icon(Icons.schedule_rounded),
                                  filled: true,
                                  fillColor: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest
                                      .withValues(alpha: .45),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                icon: const Icon(Icons.expand_more_rounded),
                                dropdownColor: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(14),
                                items: const {
                                  '1d': '1天',
                                  '3d': '3天',
                                  '7d': '7天',
                                  '30d': '30天',
                                  'permanent': '永久有效'
                                }
                                    .entries
                                    .map((item) => DropdownMenuItem(
                                        value: item.key,
                                        child: Text(item.value,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600))))
                                    .toList(),
                                onChanged: (value) => setDialogState(
                                    () => expiry = value ?? expiry))),
                        const SizedBox(width: 8),
                        FilledButton(
                            onPressed: loading ? null : createCode,
                            child: const Text('生成')),
                      ]),
                      const SizedBox(height: AppSpacing.md),
                      TextField(
                          controller: redeemController,
                          textCapitalization: TextCapitalization.characters,
                          decoration: InputDecoration(
                              labelText: '使用好友代码',
                              suffixIcon: IconButton(
                                  onPressed: loading ? null : redeemCode,
                                  icon: const Icon(Icons.check_rounded)))),
                      if (error != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(error!,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error))),
                      const SizedBox(height: 10),
                      if (loading)
                        const Center(
                            child: Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator()))
                      else if (codes.isEmpty)
                        const Text('暂无好友代码')
                      else
                        ...codes.map((item) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: SelectableText(item.code,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.2)),
                            subtitle: Text(
                                '有效期：${item.expiryText} · ${item.statusText}'),
                            trailing: item.isInactive
                                ? IconButton(
                                    tooltip: '永久删除',
                                    icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        color: Colors.grey),
                                    onPressed: () =>
                                        permanentlyDeleteCode(item),
                                  )
                                : PopupMenuButton<String>(
                                    tooltip: '更多操作',
                                    offset: const Offset(0, 8),
                                    elevation: 10,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest,
                                    onSelected: (value) {
                                      if (value == 'edit' && !item.isInactive) {
                                        unawaited(updateCode(item));
                                      } else if (value == 'disable') {
                                        unawaited(disableCode(item));
                                      }
                                    },
                                    itemBuilder: (_) => [
                                      PopupMenuItem(
                                        value: 'edit',
                                        enabled: !item.isInactive,
                                        child: const ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          leading: Icon(Icons.edit_outlined),
                                          title: Text('修改有效期'),
                                        ),
                                      ),
                                      const PopupMenuDivider(),
                                      PopupMenuItem(
                                        value: 'disable',
                                        child: ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          leading: Icon(
                                            Icons.block_outlined,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error,
                                          ),
                                          title: Text(
                                            '禁用',
                                            style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .error,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ))),
                    ])),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('关闭'))
              ],
            );
          },
        ),
      );
    } finally {
      redeemController.dispose();
    }
  }

  Widget _minecraftFeatureCard(
      BuildContext context, MinecraftServer server, _ExploreFeature feature) {
    final scheme = Theme.of(context).colorScheme;
    final cover = server.customCoverUrl?.isNotEmpty == true
        ? server.customCoverUrl
        : (server.useAutomaticIcon ? server.favicon : null);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider.value(
            value: context.read<MinecraftServerService>(),
            child: const MinecraftServerPage(),
          ),
        ),
      ),
      onLongPress: () => _showFeatureActions(feature),
      child: Stack(
        children: [
          Positioned(
            right: -8,
            bottom: -22,
            child: Text(
              'MC',
              style: TextStyle(
                color: scheme.primary.withValues(alpha: .10),
                fontSize: 78,
                height: .9,
                fontWeight: FontWeight.w900,
                letterSpacing: -8,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _serverCoverThumbnail(context, cover),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      server.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Divider(
                height: 1,
                color: scheme.primary.withValues(alpha: .18),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Icon(
                    server.online ? Icons.circle : Icons.circle_outlined,
                    color: server.online ? Colors.greenAccent : Colors.white54,
                    size: 11,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    server.online
                        ? '${server.onlinePlayers}/${server.maxPlayers} 人在线'
                        : '当前离线',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: .88),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '备注：${server.note.isEmpty ? '暂无备注' : server.note}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.25,
                  color: Colors.white.withValues(alpha: .58),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _serverCoverThumbnail(BuildContext context, String? source) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: SizedBox(
        width: 48,
        height: 48,
        child: source?.isNotEmpty == true
            ? localOrNetworkImage(source!, fit: BoxFit.cover)
            : _serverDefaultCover(context),
      ),
    );
  }

  Widget _serverDefaultCover(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(color: scheme.primary),
      child: const Center(
          child: Icon(Icons.public_rounded, color: Colors.white, size: 24)),
    );
  }

  Widget _profileItem(IconData icon, String title, String subtitle,
      [VoidCallback? onTap]) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(children: [
          Icon(icon, color: scheme.primary),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(subtitle,
                    style: TextStyle(
                        color: scheme.onSurface.withValues(alpha: .6),
                        fontSize: 12)),
              ])),
          Icon(Icons.chevron_right_rounded,
              color: scheme.onSurface.withValues(alpha: .45)),
        ]),
      ),
    );
  }

  /* void _showChatSettings(String chatName) {
    SwipeableChatTile.closeActive();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.notifications_off_outlined),
              title: const Text('消息免打扰'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('清除聊天记录'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: Text('关闭聊天：$chatName'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  */

  Future<void> _showAccountSecurity() async {
    final auth = context.read<AuthService>();
    if (auth.isGuest) {
      _showLoginRequired();
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              leading: Icon(Icons.verified_user_outlined),
              title: Text('账号与安全'),
              subtitle: Text('账号状态正常，建议定期修改密码'),
            ),
            ListTile(
              leading: const Icon(Icons.lock_reset_rounded),
              title: const Text('修改密码'),
              subtitle: const Text('使用当前密码验证后设置新密码'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showChangePassword();
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: const Text('退出登录'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await auth.logout();
                if (mounted) {
                  Navigator.pushReplacementNamed(context, AppRoutes.login);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showChangePassword() async {
    final auth = context.read<AuthService>();
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    var obscureCurrent = true;
    var obscureNext = true;
    var obscureConfirm = true;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('修改密码'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: current,
                obscureText: obscureCurrent,
                decoration: InputDecoration(
                  labelText: '当前密码',
                  suffixIcon: IconButton(
                    icon: Icon(obscureCurrent
                        ? Icons.visibility
                        : Icons.visibility_off),
                    onPressed: () =>
                        setState(() => obscureCurrent = !obscureCurrent),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: next,
                obscureText: obscureNext,
                decoration: InputDecoration(
                  labelText: '新密码（6~64位）',
                  suffixIcon: IconButton(
                    icon: Icon(
                        obscureNext ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => obscureNext = !obscureNext),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirm,
                obscureText: obscureConfirm,
                decoration: InputDecoration(
                  labelText: '确认新密码',
                  suffixIcon: IconButton(
                    icon: Icon(obscureConfirm
                        ? Icons.visibility
                        : Icons.visibility_off),
                    onPressed: () =>
                        setState(() => obscureConfirm = !obscureConfirm),
                  ),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                final navigator = Navigator.of(dialogContext);
                if (current.text.isEmpty ||
                    next.text.length < 6 ||
                    next.text.length > 64) {
                  ScaffoldMessenger.of(this.context).showSnackBar(
                      const SnackBar(content: Text('请输入正确的密码长度')));
                  return;
                }
                if (next.text != confirm.text) {
                  ScaffoldMessenger.of(this.context).showSnackBar(
                      const SnackBar(content: Text('两次输入的新密码不一致')));
                  return;
                }
                final success =
                    await auth.changePassword(current.text, next.text);
                if (!mounted) return;
                if (!success) {
                  ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(content: Text(auth.lastError ?? '密码修改失败')));
                  return;
                }
                navigator.pop();
                await auth.logout();
                if (!mounted) return;
                navigator.pushReplacementNamed(AppRoutes.login);
              },
              child: const Text('确认修改'),
            ),
          ],
        ),
      ),
    );
    current.dispose();
    next.dispose();
    confirm.dispose();
  }

  void _showLoginRequired() {
    final auth = context.read<AuthService>();
    if (auth.isGuest) {
      Navigator.pushReplacementNamed(context, AppRoutes.login);
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('该功能正在完善中')));
  }

  Future<void> _showProfileSettings() async {
    final auth = context.read<AuthService>();
    if (auth.isGuest) {
      _showLoginRequired();
      return;
    }
    final controller =
        TextEditingController(text: auth.user?['nickname']?.toString() ?? '');
    var selectedAvatar =
        auth.user?['avatar_id']?.toString() ?? auth.user?['avatar']?.toString();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: StatefulBuilder(
          builder: (context, setSheetState) => Padding(
            padding: EdgeInsets.fromLTRB(
                20, 8, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('个人信息',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 18),
                  TextField(
                    controller: controller,
                    maxLength: 20,
                    decoration: const InputDecoration(
                        labelText: '昵称',
                        prefixIcon: Icon(Icons.badge_outlined)),
                  ),
                  const SizedBox(height: 18),
                  Text('选择头像', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 78,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _avatarAssets.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (_, index) {
                        final asset = _avatarAssets[index];
                        final selected = selectedAvatar == asset;
                        return GestureDetector(
                          onTap: () =>
                              setSheetState(() => selectedAvatar = asset),
                          child: CircleAvatar(
                            radius: selected ? 36 : 32,
                            backgroundColor: selected
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent,
                            child: CircleAvatar(
                              radius: selected ? 32 : 30,
                              backgroundImage: AssetImage(asset),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () async {
                          FocusScope.of(sheetContext).unfocus(
                            disposition: UnfocusDisposition.scope,
                          );
                          await WidgetsBinding.instance.endOfFrame;
                          if (sheetContext.mounted) {
                            Navigator.pop(sheetContext);
                          }
                        },
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: () async {
                          final nickname = controller.text.trim();
                          if (nickname.isEmpty) return;
                          final success = await auth.updateProfile(
                              nickname: nickname, avatar: selectedAvatar);
                          if (!sheetContext.mounted) return;
                          if (success) {
                            Navigator.pop(sheetContext);
                          } else {
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                                SnackBar(
                                    content: Text(auth.lastError ?? '保存失败')));
                          }
                        },
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await WidgetsBinding.instance.endOfFrame;
    controller.dispose();
  }

  Future<void> _showNotificationSettings() async {
    final service = context.read<MessageNotificationService>();
    final current = service.settings.copy();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('消息通知',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                SwitchListTile(
                  title: const Text('好友消息'),
                  value: current.chat,
                  onChanged: (value) =>
                      setSheetState(() => current.chat = value),
                ),
                SwitchListTile(
                  title: const Text('对局提醒'),
                  value: current.game,
                  onChanged: (value) =>
                      setSheetState(() => current.game = value),
                ),
                SwitchListTile(
                  title: const Text('好友申请'),
                  value: current.friendRequest,
                  onChanged: (value) =>
                      setSheetState(() => current.friendRequest = value),
                ),
                SwitchListTile(
                  title: const Text('系统通知'),
                  value: current.system,
                  onChanged: (value) =>
                      setSheetState(() => current.system = value),
                ),
                FilledButton(
                  onPressed: () async {
                    await service.saveSettings(current);
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                  child: const Text('保存设置'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showMySettings() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title:
                  Text('小酒馆设置', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('应用版本、更新与偏好设置'),
            ),
            ListTile(
              leading: const Icon(Icons.system_update_alt_rounded),
              title: const Text('检查更新'),
              subtitle: const Text('检查最新 Android 版本'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _checkForUpdate();
              },
            ),
            ListTile(
              leading: const Icon(Icons.history_rounded),
              title: const Text('更新日志'),
              subtitle: const Text('查看每次版本更新的时间与内容'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showReleaseLogs();
              },
            ),
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('外观设置'),
              subtitle: const Text('自定义墨黑色与星紫色'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showColorSettings();
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _showReleaseLogs() async {
    final service = AppUpdateService();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => FutureBuilder<List<AppReleaseLog>>(
        future: service.getReleaseLogs(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AlertDialog(
              title: Text('更新日志'),
              content: SizedBox(
                  height: 80,
                  child: Center(child: CircularProgressIndicator())),
            );
          }
          if (snapshot.hasError) {
            return AlertDialog(
              title: const Text('更新日志'),
              content: const Text('更新日志加载失败，请稍后重试'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('关闭')),
              ],
            );
          }
          final logs = snapshot.data ?? const <AppReleaseLog>[];
          return AlertDialog(
            title: const Text('更新日志'),
            content: SizedBox(
              width: 420,
              child: logs.isEmpty
                  ? const Text('暂无更新日志')
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: logs.length,
                      separatorBuilder: (_, __) => const Divider(height: 24),
                      itemBuilder: (_, index) {
                        final log = logs[index];
                        final date = log.publishedAt.toLocal();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('v${log.version}  ·  编号 ${log.versionCode}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800)),
                            const SizedBox(height: 5),
                            Text(
                                '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
                                style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    fontSize: 12)),
                            const SizedBox(height: 8),
                            Text(log.content),
                          ],
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('关闭')),
            ],
          );
        },
      ),
    );
  }

  Future<void> _checkForUpdate({bool promptOnlyIfUpdate = false}) async {
    if (promptOnlyIfUpdate && (_updateCheckStarted || _updateDialogVisible)) {
      return;
    }
    if (promptOnlyIfUpdate) {
      _updateCheckStarted = true;
    }
    final messenger = ScaffoldMessenger.of(context);
    final service = AppUpdateService();
    try {
      final update = await service.check().timeout(const Duration(seconds: 8));
      if (!mounted) return;
      if (update == null) {
        if (!promptOnlyIfUpdate) {
          messenger.showSnackBar(const SnackBar(content: Text('当前已是最新版本')));
        }
        return;
      }
      if (!mounted) return;
      if (promptOnlyIfUpdate) {
        final preferences = await SharedPreferences.getInstance();
        final today = DateTime.now();
        final todayKey = '${today.year}-${today.month}-${today.day}';
        final versionKey = '${update.latestVersion}+${update.versionCode}';
        final sameVersionToday =
            preferences.getString(_lastUpdatePromptDateKey) == todayKey &&
                preferences.getString(_lastUpdatePromptVersionKey) ==
                    versionKey;
        if (sameVersionToday) return;
        await preferences.setString(_lastUpdatePromptDateKey, todayKey);
        await preferences.setString(_lastUpdatePromptVersionKey, versionKey);
        _updateDialogVisible = true;
      }
      if (!mounted) return;
      try {
        await showAppUpdateDialog(context, update, service);
      } finally {
        _updateDialogVisible = false;
      }
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(const SnackBar(content: Text('检查更新失败，请稍后重试')));
      }
    }
  }

  void _showHelp() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('帮助与反馈'),
        content: const Text('如果遇到问题，请通过应用反馈联系我们。感谢你的使用。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了')),
        ],
      ),
    );
  }

  Future<void> _showLogoutDialog(AuthService auth) async {
    if (auth.isGuest) {
      Navigator.pushReplacementNamed(context, AppRoutes.login);
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出当前账号吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('退出')),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await auth.logout();
      if (mounted) Navigator.pushReplacementNamed(context, AppRoutes.login);
    }
  }

  Future<void> _showColorSettings() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('外观设置'),
        content: const Text('当前使用默认主题，暂不支持切换或自定义主题。'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _showFeatureSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('小酒馆设置',
                            style: TextStyle(
                                fontSize: 23, fontWeight: FontWeight.w800)),
                        IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close)),
                      ],
                    ),
                    Text('复制已有卡片，独立编辑标题、描述和图标',
                        style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: .8),
                            fontSize: 13)),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () =>
                            _showNewFeatureCardDialog(setSheetState),
                        icon: const Icon(Icons.explore_rounded),
                        label: const Text('复制已有功能卡片'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    ReorderableListView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      onReorderItem: (oldIndex, newIndex) {
                        setSheetState(() {
                          final item = _features.removeAt(oldIndex);
                          _features.insert(newIndex, item);
                        });
                        setState(() {});
                      },
                      children: [
                        for (final feature in _features)
                          SwitchListTile(
                            key: ValueKey(feature.id),
                            title: Text(feature.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            subtitle: Text(feature.subtitle),
                            value: feature.visible,
                            activeThumbColor: feature.color,
                            onChanged: (value) {
                              setSheetState(() => feature.visible = value);
                              setState(() {});
                              _saveFeatureState();
                            },
                            secondary: GestureDetector(
                              onLongPress: () => _showEditFeatureDialog(
                                  feature, setSheetState),
                              child: CircleAvatar(
                                backgroundColor:
                                    feature.color.withValues(alpha: .15),
                                foregroundColor: feature.color,
                                child: Icon(feature.icon),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showFeatureActions(_ExploreFeature feature) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('编辑卡片'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showEditFeatureDialog(
                    feature, (callback) => setState(callback));
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('删除卡片'),
              onTap: () {
                Navigator.pop(sheetContext);
                _confirmDeleteFeature(feature);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteFeature(_ExploreFeature feature) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除功能卡片？'),
        content: Text('删除“${feature.title}”后，可在探索功能中重新添加。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _features.removeWhere((item) => item.id == feature.id);
    });
    await _persistFeatures();
    try {
      await ApiClient().delete('/features/${Uri.encodeComponent(feature.id)}');
    } catch (_) {
      // 本地删除仍然生效，后端接口未部署时兼容本地使用。
    }
  }

  Future<void> _persistFeatures() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = _features
        .map((feature) => {
              'id': feature.id,
              'title': feature.title,
              'subtitle': feature.subtitle,
              'visible': feature.visible,
              'type': feature.type.name,
              'websiteUrl': feature.websiteUrl,
              'notificationName': feature.notificationName,
              'notificationContent': feature.notificationContent,
              'notificationIconPath': feature.notificationIconPath,
              'notificationIconBase64': feature.notificationIconBase64,
            })
        .toList();
    await preferences.setString('home_features', jsonEncode(encoded));
  }

  Future<void> _showNewFeatureCardDialog(StateSetter setSheetState) async {
    if (_features.isEmpty) return;
    await _showExploreFeatureSheet(
      List<_ExploreFeature>.from(_features),
      title: '复制已有功能卡片',
      actionLabel: '复制',
      onAdd: (feature) {
        final copy = _ExploreFeature(
          '${feature.title}（副本）',
          feature.subtitle,
          feature.icon,
          feature.color,
          feature.visible,
          type: feature.type,
          websiteUrl: feature.websiteUrl,
          notificationName: feature.notificationName,
          notificationContent: feature.notificationContent,
          notificationIconPath: feature.notificationIconPath,
          notificationIconBase64: feature.notificationIconBase64,
        );
        setSheetState(() => _features.add(copy));
        setState(() {});
        _saveFeatureState();
        _showEditFeatureDialog(copy, setSheetState);
      },
    );
  }

  Future<void> _showEditFeatureDialog(
      _ExploreFeature feature, StateSetter setSheetState) async {
    final titleController = TextEditingController(text: feature.title);
    final subtitleController = TextEditingController(text: feature.subtitle);
    final urlController = TextEditingController(text: feature.websiteUrl ?? '');
    var titleFocused = false;
    var subtitleFocused = false;
    var urlFocused = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      useSafeArea: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('编辑功能卡片'),
        content: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _siteInput(
                dialogContext,
                controller: titleController,
                label: '标题',
                icon: Icons.title_rounded,
                onTap: () {
                  if (!titleFocused) {
                    titleFocused = true;
                    titleController.clear();
                  }
                },
                onChanged: (_) {},
              ),
              const SizedBox(height: 16),
              _siteInput(
                dialogContext,
                controller: subtitleController,
                label: '描述',
                icon: Icons.notes_rounded,
                onTap: () {
                  if (!subtitleFocused) {
                    subtitleFocused = true;
                    subtitleController.clear();
                  }
                },
                onChanged: (_) {},
              ),
              if (feature.type == _FeatureType.website) ...[
                const SizedBox(height: 16),
                _siteInput(
                  dialogContext,
                  controller: urlController,
                  label: '网站地址',
                  icon: Icons.link_rounded,
                  keyboardType: TextInputType.url,
                  onTap: () {
                    if (!urlFocused) {
                      urlFocused = true;
                      urlController.clear();
                    }
                  },
                  onChanged: (_) {},
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final title = titleController.text.trim();
              final subtitle = subtitleController.text.trim();
              if (title.isEmpty) return;
              if (feature.type == _FeatureType.website) {
                var url = urlController.text.trim();
                if (url.isNotEmpty && !url.contains('://')) {
                  url = 'https://$url';
                }
                if (url.isEmpty) {
                  feature.websiteUrl = null;
                } else if (parseSafeHttpsUrl(url) == null) {
                  return;
                } else {
                  feature.websiteUrl = parseSafeHttpsUrl(url)!.toString();
                }
                _saveWebsiteCard(feature);
              }
              feature.title = title;
              feature.subtitle = subtitle;
              _saveFeatureState();
              setSheetState(() {});
              setState(() {});
              Navigator.pop(dialogContext);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    await WidgetsBinding.instance.endOfFrame;
    titleController.dispose();
    subtitleController.dispose();
    urlController.dispose();
  }

  Future<void> _showExploreFeatures() async {
    final available = _availableFeatureTemplates
        .where((template) =>
            !_features.any((feature) => feature.type == template.type))
        .toList();
    await _showExploreFeatureSheet(
      available,
      onAdd: (feature) {
        setState(() {
          _features.add(_ExploreFeature(
            feature.title,
            feature.subtitle,
            feature.icon,
            _themeAccent,
            true,
            type: feature.type,
          ));
        });
        _saveFeatureState();
      },
    );
  }

  Future<void> _showExploreFeatureSheet(
    List<_ExploreFeature> available, {
    String title = '探索新的功能卡片',
    String actionLabel = '添加',
    required ValueChanged<_ExploreFeature> onAdd,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 23, fontWeight: FontWeight.w800)),
                  IconButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close)),
                ],
              ),
              Text(
                  title == '复制已有功能卡片'
                      ? '选择已有卡片后会生成独立副本，可单独修改标题和描述。'
                      : '选择功能卡片后，它会加入小酒馆设置，可继续排序或开关。',
                  style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: .8),
                      fontSize: 13)),
              const SizedBox(height: 16),
              if (available.isEmpty)
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('所有功能卡片都已添加')))
              else
                ...available.map((feature) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: feature.color.withValues(alpha: .15),
                        foregroundColor: feature.color,
                        child: Icon(feature.icon),
                      ),
                      title: Text(feature.title,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(feature.subtitle),
                      trailing: FilledButton.tonalIcon(
                        onPressed: () {
                          onAdd(feature);
                          Navigator.pop(sheetContext);
                        },
                        icon: const Icon(Icons.add_rounded),
                        label: Text(actionLabel),
                      ),
                    )),
            ],
          ),
        ),
      ),
    );
  }

  List<_ExploreFeature> get _availableFeatureTemplates => [
        _ExploreFeature(
            '我的世界服务器', '查看服务器在线状态', Icons.public_rounded, _themeAccent, true,
            type: _FeatureType.minecraftServer),
        _ExploreFeature('好友动态', '看看朋友最近在做什么', Icons.dynamic_feed_rounded,
            _themeAccent, true,
            type: _FeatureType.moments),
        _ExploreFeature(
            '出行规划', '安排日期、节点与旅行详情', Icons.map_rounded, _themeAccent, true,
            type: _FeatureType.travelPlanner),
        _ExploreFeature('通知自己', '定时提醒重要事项', Icons.notifications_active_rounded,
            _themeAccent, true,
            type: _FeatureType.selfNotification),
        _ExploreFeature('时空穿梭', '输入时间开启穿梭倒计时', Icons.travel_explore_rounded,
            _themeAccent, true,
            type: _FeatureType.timeTravel),
        _ExploreFeature('邮编查询', '查询地区邮政编码', Icons.markunread_mailbox_rounded,
            _themeAccent, true,
            type: _FeatureType.postalCode),
        _ExploreFeature('我的调酒台', '管理原料，发现现在能调的酒', Icons.local_bar_rounded,
            _themeAccent, true,
            type: _FeatureType.cocktailBar),
        _ExploreFeature(
            '调酒笔记', '记录你的配方与灵感', Icons.edit_note_rounded, _themeAccent, true,
            type: _FeatureType.cocktailNotes),
        _ExploreFeature(
            '调酒配方', '浏览经典调酒配方', Icons.local_bar_rounded, _themeAccent, true,
            type: _FeatureType.cocktailRecipes),
      ];
}

class _FriendCode {
  final String id;
  final String code;
  final DateTime? expiresAt;
  final bool disabled;
  final String status;

  const _FriendCode(
      {required this.id,
      required this.code,
      this.expiresAt,
      required this.disabled,
      this.status = 'active'});

  factory _FriendCode.fromJson(Map<String, dynamic> json) => _FriendCode(
        id: json['id']?.toString() ?? '',
        code: json['code']?.toString() ?? '',
        expiresAt: json['expiresAt'] == null
            ? null
            : DateTime.tryParse(json['expiresAt'].toString()),
        disabled: json['disabled'] == true,
        status: json['status']?.toString() ?? 'active',
      );

  bool get expired => expiresAt != null && !expiresAt!.isAfter(DateTime.now());
  bool get isInactive => disabled || expired || status != 'active';
  String get statusText => disabled
      ? '已禁用'
      : expired || status == 'expired'
          ? '失效'
          : '有效';

  String get expiryText => expiresAt == null
      ? '永久'
      : '${expiresAt!.year}-${expiresAt!.month.toString().padLeft(2, '0')}-${expiresAt!.day.toString().padLeft(2, '0')}';
}

enum _FeatureType {
  standard,
  website,
  minecraftServer,
  selfNotification,
  timeTravel,
  postalCode,
  moments,
  travelPlanner,
  cocktailBar,
  cocktailNotes,
  cocktailRecipes,
}

class _ExploreFeature {
  final String id;
  String title;
  String subtitle;
  final IconData icon;
  final Color color;
  bool visible;
  final _FeatureType type;
  String? websiteUrl;
  String? notificationName;
  String? notificationContent;
  String? notificationIconPath;
  String? notificationIconBase64;

  Uint8List? get notificationIconBytes => notificationIconBase64 == null
      ? null
      : base64Decode(notificationIconBase64!);

  _ExploreFeature(
    this.title,
    this.subtitle,
    this.icon,
    this.color,
    this.visible, {
    String? id,
    this.type = _FeatureType.standard,
    this.websiteUrl,
    this.notificationName,
    this.notificationContent,
    this.notificationIconPath,
    this.notificationIconBase64,
  }) : id = id ?? '${title}_${DateTime.now().microsecondsSinceEpoch}';
}
