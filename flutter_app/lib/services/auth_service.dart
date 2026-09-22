import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_client.dart';

/// 用户认证服务
/// 管理登录/注册/Token状态
class AuthService extends ChangeNotifier {
  static const _tokenKey = 'auth_token';
  final ApiClient _api = ApiClient();
  static const _secureStorage = FlutterSecureStorage();
  final FutureOr<void> Function()? onLogout;
  final Future<void> Function(String? userId)? onSessionChanged;

  bool _isGuest = false;

  String? _token;
  Map<String, dynamic>? _user;
  bool _loading = false;
  String? _lastError;

  bool get isLoggedIn => _token != null && _token!.isNotEmpty;
  bool get isGuest => _isGuest;
  bool get hasAccount => isLoggedIn && !_isGuest;
  String? get lastError => _lastError;
  Map<String, dynamic>? get user => _user;
  bool get loading => _loading;
  String? get token => _token;

  AuthService({this.onLogout, this.onSessionChanged});

  String? get userId => _user?['id']?.toString() ?? _user?['uid']?.toString();

  void enterGuest() {
    _isGuest = true;
    _token = null;
    _user = {'nickname': '游客'};
    _api.setToken(null);
    unawaited(onSessionChanged?.call(null));
    notifyListeners();
  }

  Future<void> restoreSession() async {
    _isGuest = false;
    var token = await _secureStorage.read(key: _tokenKey);
    if (token == null) {
      final preferences = await SharedPreferences.getInstance();
      token = preferences.getString(_tokenKey);
      if (token != null && token.isNotEmpty) {
        await _secureStorage.write(key: _tokenKey, value: token);
        await preferences.remove(_tokenKey);
      }
    }
    if (token == null || token.isEmpty) return;
    _token = token;
    _api.setToken(token);
    try {
      final res = await _api.get('/users/me');
      final data = res.data is Map ? res.data['data'] : null;
      if (data is Map) {
        _user = Map<String, dynamic>.from(data);
        await onSessionChanged?.call(userId);
      }
    } catch (e) {
      debugPrint('[Auth] 恢复登录失败: $e');
      await logout();
    }
    notifyListeners();
  }

  Future<void> _saveSession(String token, Map<String, dynamic>? user) async {
    _isGuest = false;
    _token = token;
    _user = user;
    _api.setToken(token);
    await _secureStorage.write(key: _tokenKey, value: token);
    await onSessionChanged?.call(userId);
  }

  Future<bool> changePassword(
      String currentPassword, String newPassword) async {
    _lastError = null;
    try {
      await _api.post('/auth/password/change', data: {
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      });
      return true;
    } catch (e) {
      _lastError = errorMessage(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateProfile({
    String? nickname,
    String? avatar,
    String? avatarId,
  }) async {
    _lastError = null;
    try {
      final payload = <String, dynamic>{};
      if (nickname != null) payload['nickname'] = nickname;
      if (avatarId != null) payload['avatar_id'] = avatarId;
      if (avatar != null) payload['avatar'] = avatar;
      final response = await _api.patch('/users/me', data: payload);
      final data = response.data is Map && response.data['data'] is Map
          ? response.data['data']
          : response.data;
      if (data is Map) _user = Map<String, dynamic>.from(data);
      notifyListeners();
      return true;
    } catch (e) {
      _lastError = errorMessage(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> login(String phone, String password) async {
    _lastError = null;
    _loading = true;
    notifyListeners();
    try {
      final res = await _api.post('/auth/login', data: {
        'phone': phone,
        'password': password,
      });
      final payload = res.data is Map && res.data['data'] is Map
          ? res.data['data'] as Map
          : res.data as Map;
      final token = payload['token']?.toString();
      if (token == null || token.isEmpty) {
        throw StateError('登录响应缺少 Token');
      }
      await _saveSession(
        token,
        payload['user'] is Map
            ? Map<String, dynamic>.from(payload['user'] as Map)
            : null,
      );
      _loading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _lastError = errorMessage(e);
      debugPrint('[Auth] 登录失败: $e');
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> sendRegisterCode(String phone) async {
    return _sendCode('/auth/sms/send', phone, '发送验证码');
  }

  Future<bool> sendResetCode(String phone) async {
    return _sendCode('/auth/sms/send-reset', phone, '发送重置验证码');
  }

  Future<bool> _sendCode(String path, String phone, String action) async {
    _lastError = null;
    try {
      await _api.post(path, authenticated: false, data: {'phone': phone});
      return true;
    } catch (e) {
      _lastError = errorMessage(e);
      debugPrint('[Auth] $action失败: $e');
      return false;
    }
  }

  Future<bool> resetPassword(
    String phone,
    String code,
    String password,
  ) async {
    _lastError = null;
    _loading = true;
    notifyListeners();
    try {
      await _api.post('/auth/password/reset',
          data: {
            'phone': phone,
            'code': code,
            'password': password,
          },
          authenticated: false);
      _loading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _lastError = errorMessage(e);
      debugPrint('[Auth] 重置密码失败: $e');
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> register(
    String phone,
    String password,
    String code,
    String nickname,
  ) async {
    _lastError = null;
    _loading = true;
    notifyListeners();
    try {
      final res =
          await _api.post('/auth/register', authenticated: false, data: {
        'phone': phone,
        'password': password,
        'code': code,
        'nickname': nickname,
      });
      final payload = res.data is Map && res.data['data'] is Map
          ? res.data['data'] as Map
          : res.data as Map;
      final token = payload['token']?.toString();
      if (token == null || token.isEmpty) {
        throw StateError('注册响应缺少 Token');
      }
      await _saveSession(
        token,
        payload['user'] is Map
            ? Map<String, dynamic>.from(payload['user'] as Map)
            : null,
      );
      _loading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _lastError = errorMessage(e);
      debugPrint('[Auth] 注册失败: $e');
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  String errorMessage(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['message'] is String) {
        return data['message'] as String;
      }
      if (data is Map && data['error'] is String) {
        return data['error'] as String;
      }
      return error.message ?? '网络请求失败，请稍后重试';
    }
    return '请求失败，请稍后重试';
  }

  Future<void> logout() async {
    final hadSession = isLoggedIn;
    _isGuest = false;
    try {
      if (hadSession) await _api.post('/auth/logout');
    } catch (e) {
      debugPrint('[Auth] 退出登录请求失败: $e');
    }
    await _secureStorage.delete(key: _tokenKey);
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_tokenKey);
    _token = null;
    _user = null;
    _api.setToken(null);
    await onSessionChanged?.call(null);
    try {
      await onLogout?.call();
    } catch (e) {
      debugPrint('[Auth] 退出登录清理失败: $e');
    }
    notifyListeners();
  }
}
