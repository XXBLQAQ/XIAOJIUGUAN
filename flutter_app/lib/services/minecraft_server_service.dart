import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'minecraft_query.dart';

class MinecraftServer {
  final String name;
  final String address;
  final int port;
  final MinecraftEdition edition;
  final String version;
  final int onlinePlayers;
  final int maxPlayers;
  final bool online;
  final String motd;
  final String? favicon;
  final String note;
  final String? customCoverUrl;
  final bool useAutomaticIcon;

  const MinecraftServer({
    required this.name,
    required this.address,
    required this.port,
    required this.edition,
    required this.version,
    required this.onlinePlayers,
    required this.maxPlayers,
    required this.online,
    required this.motd,
    required this.favicon,
    required this.note,
    required this.customCoverUrl,
    required this.useAutomaticIcon,
  });

  MinecraftServer copyWith(
          {String? name,
          String? address,
          int? port,
          MinecraftEdition? edition,
          String? version,
          int? onlinePlayers,
          int? maxPlayers,
          bool? online,
          String? motd,
          String? favicon,
          String? note,
          String? customCoverUrl,
          bool? useAutomaticIcon}) =>
      MinecraftServer(
        name: name ?? this.name,
        address: address ?? this.address,
        port: port ?? this.port,
        edition: edition ?? this.edition,
        version: version ?? this.version,
        onlinePlayers: onlinePlayers ?? this.onlinePlayers,
        maxPlayers: maxPlayers ?? this.maxPlayers,
        online: online ?? this.online,
        motd: motd ?? this.motd,
        favicon: favicon ?? this.favicon,
        note: note ?? this.note,
        customCoverUrl: customCoverUrl ?? this.customCoverUrl,
        useAutomaticIcon: useAutomaticIcon ?? this.useAutomaticIcon,
      );
}

class MinecraftServerService extends ChangeNotifier {
  static const _nameKey = 'minecraft_server_name';
  static const _addressKey = 'minecraft_server_address';
  static const _portKey = 'minecraft_server_port';
  static const _editionKey = 'minecraft_server_edition';
  static const _noteKey = 'minecraft_server_note';
  static const _coverKey = 'minecraft_server_cover';
  static const _autoIconKey = 'minecraft_server_auto_icon';

  final String? profileKey;
  final ResilientMinecraftQueryClient _queryClient =
      ResilientMinecraftQueryClient(Dio());

  String _key(String base) => profileKey == null ? base : '$base:$profileKey';

  MinecraftServer _server = const MinecraftServer(
      name: '未绑定服务器',
      address: '',
      port: 25565,
      edition: MinecraftEdition.java,
      version: '未知版本',
      onlinePlayers: 0,
      maxPlayers: 0,
      online: false,
      motd: '',
      favicon: null,
      note: '',
      customCoverUrl: null,
      useAutomaticIcon: true);
  bool _loading = false;
  String? _error;
  Timer? _refreshTimer;
  Future<void>? _restoreFuture;

  MinecraftServerService({this.profileKey}) {
    _restoreFuture = _restore();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => refreshStatus(forceRefresh: true),
    );
  }

  MinecraftServer get server => _server;
  bool get loading => _loading;
  String? get error => _error;
  MinecraftQueryMetrics get metrics => _queryClient.metrics;

  Future<void> _restore() async {
    final preferences = await SharedPreferences.getInstance();
    final address = preferences.getString(_key(_addressKey));
    _server = _server.copyWith(
        name: preferences.getString(_key(_nameKey)),
        address: address,
        port: preferences.getInt(_key(_portKey)),
        edition: preferences.getString(_key(_editionKey)) == 'bedrock'
            ? MinecraftEdition.bedrock
            : MinecraftEdition.java,
        note: preferences.getString(_key(_noteKey)),
        customCoverUrl: preferences.getString(_key(_coverKey)),
        useAutomaticIcon: preferences.getBool(_key(_autoIconKey)));
    notifyListeners();
    if (address?.isNotEmpty == true) {
      await _refreshStatus();
    }
  }

  Future<void> updateServer(
      {required String name,
      required String address,
      required int port,
      required MinecraftEdition edition,
      required String note,
      required String? customCoverUrl,
      required bool useAutomaticIcon}) async {
    _server = _server.copyWith(
        name: name,
        address: address,
        port: port,
        edition: edition,
        note: note,
        customCoverUrl: customCoverUrl,
        useAutomaticIcon: useAutomaticIcon,
        online: false,
        version: '查询中');
    _error = null;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key(_nameKey), name);
    await preferences.setString(_key(_addressKey), address);
    await preferences.setInt(_key(_portKey), port);
    await preferences.setString(_key(_editionKey), edition.name);
    await preferences.setString(_key(_noteKey), note);
    await preferences.setString(_key(_coverKey), customCoverUrl ?? '');
    await preferences.setBool(_key(_autoIconKey), useAutomaticIcon);
    await refreshStatus();
  }

  Future<void> refreshStatus({bool forceRefresh = true}) async {
    await _restoreFuture;
    await _refreshStatus(forceRefresh: forceRefresh);
  }

  Future<void> _refreshStatus({bool forceRefresh = false}) async {
    if (_server.address.isEmpty || _loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _queryClient.query(
          address: _server.address,
          port: _server.port,
          edition: _server.edition,
          forceRefresh: forceRefresh);
      _server = _server.copyWith(
          online: result.online,
          onlinePlayers: result.onlinePlayers,
          maxPlayers: result.maxPlayers,
          version: result.version,
          motd: result.motd,
          favicon: result.favicon);
    } catch (error) {
      _server = _server.copyWith(
          online: false,
          onlinePlayers: 0,
          maxPlayers: 0,
          version: '无法获取',
          motd: '无法获取服务器信息',
          favicon: null);
      _error = error is MinecraftQueryException
          ? '查询失败：${error.message}'
          : '查询失败：请确认服务器地址是公网域名/IP，并已开放游戏端口';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}
