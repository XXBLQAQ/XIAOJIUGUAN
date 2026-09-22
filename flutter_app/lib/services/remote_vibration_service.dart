import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

import '../core/api_client.dart';
import 'chat_socket_service.dart';
import 'remote_vibration_policy.dart';

class RemoteVibrationPermission {
  final bool localEnabled;
  final bool peerAuthorized;

  const RemoteVibrationPermission({
    required this.localEnabled,
    required this.peerAuthorized,
  });

  bool get canSend => peerAuthorized;

  factory RemoteVibrationPermission.fromJson(Map<String, dynamic> json) {
    return RemoteVibrationPermission(
      localEnabled: json['localEnabled'] == true ||
          json['enabled'] == true ||
          json['allowRemoteVibration'] == true,
      peerAuthorized: json['peerAuthorized'] == true ||
          json['canRemoteVibrate'] == true ||
          json['remoteVibrationAvailable'] == true,
    );
  }
}

/// 远程震动只响应服务端验证过的实时事件，且本机仍需保留接收授权。
class RemoteVibrationService extends ChangeNotifier {
  static const _duration = Duration(milliseconds: 500);
  static const _localEnabledKey = 'remote_vibration_enabled_chats';

  final ApiClient _api;
  final ChatSocketService _socket;
  final Map<String, RemoteVibrationPermission> _permissions = {};
  final Set<String> _loadingChats = {};
  final Set<String> _localEnabledChats = {};
  final List<DateTime> _sentTriggerTimestamps = [];
  final List<DateTime> _receivedTriggerTimestamps = [];
  String? _userId;
  int _sessionRevision = 0;

  RemoteVibrationService(this._socket, {ApiClient? api})
      : _api = api ?? ApiClient() {
    _socket.onRemoteVibration = _handleRemoteVibration;
  }

  String? get userId => _userId;

  Future<void> setUserId(String? userId) async {
    final nextUserId = userId?.trim().isEmpty == true ? null : userId?.trim();
    if (_userId == nextUserId) return;
    _userId = nextUserId;
    _sessionRevision++;
    _permissions.clear();
    _loadingChats.clear();
    _localEnabledChats.clear();
    _sentTriggerTimestamps.clear();
    _receivedTriggerTimestamps.clear();
    await _restoreLocalPermissions(_sessionRevision);
    notifyListeners();
  }

  bool isLoading(String chatId) => _loadingChats.contains(chatId);

  RemoteVibrationPermission? permissionFor(String chatId) =>
      _permissions[chatId];

  static String localPermissionKeyFor(String userId) =>
      '$_localEnabledKey.$userId';

  String get _localPermissionKey => localPermissionKeyFor(_userId!);

  Future<void> _restoreLocalPermissions(int revision) async {
    if (_userId == null) return;
    final preferences = await SharedPreferences.getInstance();
    final chats = preferences.getStringList(_localPermissionKey) ?? const [];
    if (revision != _sessionRevision || _userId == null) return;
    _localEnabledChats
      ..clear()
      ..addAll(chats);
  }

  Future<void> _persistLocalPermissions() async {
    if (_userId == null) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      _localPermissionKey,
      _localEnabledChats.toList(),
    );
  }

  Future<void> loadPermission(String chatId) async {
    if (_userId == null || chatId.isEmpty || _loadingChats.contains(chatId)) {
      return;
    }
    _loadingChats.add(chatId);
    notifyListeners();
    try {
      final response =
          await _api.get('/remote-controls/chats/$chatId/vibration');
      final payload = _payload(response.data);
      if (payload.isNotEmpty) {
        final remote = RemoteVibrationPermission.fromJson(payload);
        _permissions[chatId] = RemoteVibrationPermission(
          localEnabled:
              _localEnabledChats.contains(chatId) || remote.localEnabled,
          peerAuthorized: remote.peerAuthorized,
        );
      }
    } catch (error) {
      debugPrint('[RemoteVibration] 读取授权状态失败: $error');
      _permissions[chatId] = RemoteVibrationPermission(
        localEnabled: _localEnabledChats.contains(chatId),
        peerAuthorized: false,
      );
    } finally {
      _loadingChats.remove(chatId);
      notifyListeners();
    }
  }

  Future<String?> setLocalPermission(String chatId, bool enabled) async {
    if (_userId == null) return '请先登录后再设置远程震动授权';
    if (chatId.isEmpty) return '会话无效';
    if (enabled && !await _canVibrate()) {
      return '此设备不支持震动，无法开启远程震动接收';
    }
    try {
      final response = await _api.put(
        '/remote-controls/chats/$chatId/vibration',
        data: {'enabled': enabled},
      );
      final payload = _payload(response.data);
      if (enabled) {
        _localEnabledChats.add(chatId);
      } else {
        _localEnabledChats.remove(chatId);
      }
      await _persistLocalPermissions();
      final current = _permissions[chatId];
      _permissions[chatId] = RemoteVibrationPermission(
        localEnabled: enabled,
        peerAuthorized: payload['peerAuthorized'] == true ||
            payload['canRemoteVibrate'] == true ||
            current?.peerAuthorized == true,
      );
      notifyListeners();
      return null;
    } catch (error) {
      return _errorText(error, '保存远程震动授权失败');
    }
  }

  /// null 表示服务端已接收。客户端和服务端均执行每分钟最多三次的保护。
  Future<String?> trigger(String chatId, dynamic receiverId) async {
    if (_userId == null) return '请先登录后再触发远程震动';
    final permission = _permissions[chatId];
    if (permission?.canSend != true) return '对方未授权震动控制功能';

    final now = DateTime.now();
    RemoteVibrationPolicy.discardExpired(_sentTriggerTimestamps, now);
    if (!RemoteVibrationPolicy.isWithinLimit(_sentTriggerTimestamps, now)) {
      return '远程震动过于频繁，请稍后再试';
    }

    // 在发送前记录，避免网络失败后连续重试绕过客户端限流。
    _sentTriggerTimestamps.add(now);
    return _socket.triggerRemoteVibration(chatId, receiverId: receiverId);
  }

  Future<void> _handleRemoteVibration(Map<String, dynamic> command) async {
    final chatId = command['chatId']?.toString() ?? '';
    if (chatId.isEmpty || !_localEnabledChats.contains(chatId)) {
      debugPrint('[RemoteVibration] 拒绝未授权的震动指令');
      return;
    }

    final now = DateTime.now();
    RemoteVibrationPolicy.discardExpired(_receivedTriggerTimestamps, now);
    if (!RemoteVibrationPolicy.isWithinLimit(_receivedTriggerTimestamps, now)) {
      debugPrint('[RemoteVibration] 接收端限流：一分钟内最多震动三次');
      return;
    }

    if (!await _canVibrate()) {
      debugPrint('[RemoteVibration] 当前设备不支持震动');
      return;
    }
    try {
      _receivedTriggerTimestamps.add(now);
      await Vibration.vibrate(duration: _duration.inMilliseconds);
    } catch (error, stackTrace) {
      debugPrint('[RemoteVibration] 执行震动失败: $error\n$stackTrace');
    }
  }

  Future<bool> _canVibrate() async {
    try {
      return await Vibration.hasVibrator();
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic> _payload(dynamic data) {
    if (data is! Map) return const {};
    final root = Map<String, dynamic>.from(
        data.map((key, value) => MapEntry(key.toString(), value)));
    final nested = root['data'];
    return nested is Map
        ? Map<String, dynamic>.from(
            nested.map((key, value) => MapEntry(key.toString(), value)))
        : root;
  }

  String _errorText(Object error, String fallback) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['message']?.toString().isNotEmpty == true) {
        return data['message'].toString();
      }
    }
    return fallback;
  }
}
