import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/routes.dart';
import '../../services/auth_service.dart';
import '../../services/chat_socket_service.dart';
import '../../services/message_notification_service.dart';

/// 登录与注册页。
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _codeController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _nicknameController = TextEditingController();
  Timer? _codeTimer;
  int _countdown = 0;
  bool _isLogin = true;

  @override
  void dispose() {
    _codeTimer?.cancel();
    _phoneController.dispose();
    _passwordController.dispose();
    _codeController.dispose();
    _confirmPasswordController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _sendCode() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      _showMessage('请输入手机号');
      return;
    }
    final auth = context.read<AuthService>();
    final success = await auth.sendRegisterCode(phone);
    if (!mounted) return;
    if (!success) {
      _showMessage(auth.lastError ?? '验证码发送失败，请稍后重试');
      return;
    }
    setState(() => _countdown = 60);
    _codeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_countdown <= 1) {
        timer.cancel();
        setState(() => _countdown = 0);
      } else {
        setState(() => _countdown--);
      }
    });
    _showMessage('验证码已发送');
  }

  Future<void> _showForgotPassword() async {
    final phoneController = TextEditingController();
    final codeController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    Timer? timer;
    var countdown = 0;
    var submitting = false;
    var sendingCode = false;

    final reset = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> sendCode() async {
            final phone = phoneController.text.trim();
            if (!RegExp(r'^1[3-9]\d{9}$').hasMatch(phone)) {
              _showMessage('请输入正确的中国大陆11位手机号');
              return;
            }
            setDialogState(() => sendingCode = true);
            final auth = this.context.read<AuthService>();
            final success = await auth.sendResetCode(phone);
            if (!context.mounted) return;
            setDialogState(() => sendingCode = false);
            if (!success) {
              _showMessage(auth.lastError ?? '验证码发送失败，请稍后重试');
              return;
            }
            timer?.cancel();
            setDialogState(() => countdown = 60);
            timer = Timer.periodic(const Duration(seconds: 1), (timer) {
              if (!context.mounted) {
                timer.cancel();
                return;
              }
              if (countdown <= 1) {
                timer.cancel();
                setDialogState(() => countdown = 0);
              } else {
                setDialogState(() => countdown--);
              }
            });
            _showMessage('验证码已发送');
          }

          Future<void> submitReset() async {
            final phone = phoneController.text.trim();
            final code = codeController.text.trim();
            final password = passwordController.text;
            if (!RegExp(r'^1[3-9]\d{9}$').hasMatch(phone)) {
              _showMessage('请输入正确的中国大陆11位手机号');
              return;
            }
            if (!RegExp(r'^\d{6}$').hasMatch(code)) {
              _showMessage('请输入6位验证码');
              return;
            }
            if (password.length < 6 || password.length > 64) {
              _showMessage('密码长度需为6~64位');
              return;
            }
            if (password != confirmController.text) {
              _showMessage('两次输入的密码不一致');
              return;
            }
            setDialogState(() => submitting = true);
            final auth = this.context.read<AuthService>();
            final success = await auth.resetPassword(phone, code, password);
            if (!context.mounted) return;
            setDialogState(() => submitting = false);
            if (success) {
              Navigator.pop(dialogContext, true);
            } else {
              _showMessage(auth.lastError ?? '密码重置失败，请稍后重试');
            }
          }

          final scheme = Theme.of(context).colorScheme;
          final base = Theme.of(context).scaffoldBackgroundColor;
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            title: Row(
              children: [
                Icon(Icons.lock_reset_rounded, color: scheme.primary),
                const SizedBox(width: 10),
                const Text('重置密码'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  '验证手机号后设置新的登录密码',
                  style:
                      TextStyle(color: scheme.onSurface.withValues(alpha: .62)),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: '手机号',
                    prefixIcon: const Icon(Icons.phone_outlined),
                    fillColor: base,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: codeController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: '6位验证码',
                        prefixIcon: const Icon(Icons.verified_outlined),
                        fillColor: base,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: countdown == 0 && !sendingCode && !submitting
                        ? sendCode
                        : null,
                    child: Text(countdown == 0 ? '发送验证码' : '$countdown秒'),
                  ),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: '新密码（6~64位）',
                    prefixIcon: const Icon(Icons.lock_outline),
                    fillColor: base,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: '确认新密码',
                    prefixIcon: const Icon(Icons.lock_reset_outlined),
                    fillColor: base,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ]),
            ),
            actions: [
              TextButton(
                onPressed:
                    submitting ? null : () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: submitting ? null : submitReset,
                child: submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('重置密码'),
              ),
            ],
          );
        },
      ),
    );
    timer?.cancel();
    await WidgetsBinding.instance.endOfFrame;
    phoneController.dispose();
    codeController.dispose();
    passwordController.dispose();
    confirmController.dispose();
    if (reset == true && mounted) {
      _showMessage('密码已重置，请使用新密码登录');
    }
  }

  Future<void> _submit() async {
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;
    if (phone.isEmpty || password.isEmpty) {
      _showMessage('请输入手机号和密码');
      return;
    }
    if (!_isLogin && _nicknameController.text.trim().isEmpty) {
      _showMessage('请输入昵称');
      return;
    }
    if (!_isLogin && _codeController.text.trim().isEmpty) {
      _showMessage('请输入验证码');
      return;
    }
    if (!_isLogin &&
        _passwordController.text != _confirmPasswordController.text) {
      _showMessage('两次输入的密码不一致');
      return;
    }

    final auth = context.read<AuthService>();
    final success = _isLogin
        ? await auth.login(phone, password)
        : await auth.register(
            phone,
            password,
            _codeController.text.trim(),
            _nicknameController.text.trim(),
          );
    if (!mounted) return;
    if (success) {
      context
          .read<ChatSocketService>()
          .connect(token: auth.token, userId: auth.user?['id']?.toString());
      unawaited(context
          .read<MessageNotificationService>()
          .requestNotificationPermission());
      Navigator.pushReplacementNamed(context, AppRoutes.home);
    } else {
      _showMessage(auth.lastError ?? '${_isLogin ? '登录' : '注册'}失败，请稍后重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = Theme.of(context).scaffoldBackgroundColor;
    final loading = context.watch<AuthService>().loading;
    return Scaffold(
      backgroundColor: base,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 50, 28, 28),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(Icons.sports_esports_rounded,
                  color: scheme.onPrimary, size: 34),
            ),
            const SizedBox(height: 28),
            Text(_isLogin ? '欢迎回来' : '创建账号',
                style:
                    const TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(_isLogin ? '和好友一起，马上开玩。' : '加入好友，发现更多有趣游戏。',
                style: TextStyle(
                    fontSize: 15,
                    color: scheme.onSurface.withValues(alpha: .62))),
            const SizedBox(height: 38),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(28)),
              child: Column(children: [
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                      labelText: '手机号',
                      prefixIcon: const Icon(Icons.phone_outlined),
                      fillColor: base,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16))),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                      labelText: '密码',
                      prefixIcon: const Icon(Icons.lock_outline),
                      fillColor: base,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16))),
                ),
                if (_isLogin)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: loading ? null : _showForgotPassword,
                        child: const Text('忘记密码？'),
                      ),
                    ),
                  ),
                if (!_isLogin) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nicknameController,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                        labelText: '昵称',
                        prefixIcon: const Icon(Icons.badge_outlined),
                        fillColor: base,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16))),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirmPasswordController,
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: '确认密码',
                        prefixIcon: const Icon(Icons.lock_reset_outlined),
                        fillColor: base,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16))),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _codeController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                            labelText: '验证码',
                            prefixIcon: const Icon(Icons.verified_outlined),
                            fillColor: base,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16))),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _countdown == 0 && !loading ? _sendCode : null,
                      child: Text(_countdown == 0 ? '发送验证码' : '${_countdown}s'),
                    ),
                  ]),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton(
                    onPressed: loading ? null : _submit,
                    style: FilledButton.styleFrom(
                        backgroundColor: scheme.primary,
                        foregroundColor: scheme.onPrimary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(17))),
                    child: loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_isLogin ? '登录' : '注册',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: loading
                    ? null
                    : () {
                        context.read<AuthService>().enterGuest();
                        Navigator.pushReplacementNamed(context, AppRoutes.home);
                      },
                icon: const Icon(Icons.person_outline_rounded),
                label: const Text('游客进入'),
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: TextButton(
                onPressed: loading
                    ? null
                    : () => setState(() {
                          if (_isLogin) {
                            _confirmPasswordController.clear();
                          }
                          _isLogin = !_isLogin;
                          _codeTimer?.cancel();
                          _countdown = 0;
                        }),
                child: Text(_isLogin ? '还没有账号？立即注册' : '已有账号？返回登录',
                    style: TextStyle(
                        color: scheme.primary, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 28),
            Center(
                child: Text('登录即代表你同意用户协议与隐私政策',
                    style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurface.withValues(alpha: .45)))),
          ]),
        ),
      ),
    );
  }
}
