import 'package:flutter/material.dart';

import 'app_avatar.dart';

/// 好友聊天卡片。
///
/// 长按卡片后显示操作胶囊，操作完成或点击其他区域后自动收起。
/// 所有操作按钮与卡片共用主题色、圆角和阴影风格。
class SwipeableChatTile extends StatefulWidget {
  final String name;
  final String text;
  final IconData icon;
  final String? avatar;
  final bool online;
  final String time;
  final bool isRead;
  final bool isUnread;
  final bool isPinned;
  final VoidCallback? onTap;
  final VoidCallback? onMarkUnread;
  final VoidCallback? onTogglePin;
  final VoidCallback? onSettings;

  static _SwipeableChatTileState? _activeState;

  static void closeActive() {
    _activeState?._hideActions();
  }

  const SwipeableChatTile({
    super.key,
    required this.name,
    required this.text,
    required this.icon,
    this.avatar,
    this.online = false,
    required this.time,
    this.isRead = true,
    this.isUnread = false,
    this.isPinned = false,
    this.onTap,
    this.onMarkUnread,
    this.onTogglePin,
    this.onSettings,
  });

  @override
  State<SwipeableChatTile> createState() => _SwipeableChatTileState();
}

class _SwipeableChatTileState extends State<SwipeableChatTile>
    with SingleTickerProviderStateMixin {
  static const double _buttonWidth = 68;
  static const double _capsuleWidth = _buttonWidth * 3 + 2;

  late final AnimationController _animationController;
  late final Animation<double> _bounce;
  bool _actionsVisible = false;
  bool _suppressNextCardTap = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
      reverseDuration: const Duration(milliseconds: 240),
    );
    _bounce = CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void dispose() {
    if (identical(SwipeableChatTile._activeState, this)) {
      SwipeableChatTile._activeState = null;
    }
    _animationController.dispose();
    super.dispose();
  }

  void _showActions() {
    if (_actionsVisible) return;
    SwipeableChatTile._activeState?._hideActions();
    SwipeableChatTile._activeState = this;
    setState(() {
      _actionsVisible = true;
      _suppressNextCardTap = true;
    });
    _animationController.forward(from: 0);
  }

  void _hideActions() {
    if (!_actionsVisible) return;
    setState(() => _actionsVisible = false);
    _animationController.reverse();
    if (identical(SwipeableChatTile._activeState, this)) {
      SwipeableChatTile._activeState = null;
    }
  }

  void _handleTap() {
    if (_suppressNextCardTap) {
      _suppressNextCardTap = false;
      if (_actionsVisible) _hideActions();
      return;
    }
    if (_actionsVisible) {
      _hideActions();
      return;
    }
    widget.onTap?.call();
  }

  void _handleAction(String label) {
    _suppressNextCardTap = false;
    _hideActions();
    if (label == '未读' || label == '已读') {
      widget.onMarkUnread?.call();
    } else if (label == '置顶' || label == '取消置顶') {
      widget.onTogglePin?.call();
    } else {
      widget.onSettings?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        height: 68,
        child: AnimatedBuilder(
          key: const ValueKey('swipeable_chat_tile_animation'),
          animation: _bounce,
          builder: (context, child) {
            final progress = _bounce.value.clamp(0.0, 1.0);
            return Stack(
              alignment: Alignment.center,
              children: [
                _buildCard(progress),
                _buildActions(progress),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildActions(double progress) {
    final scheme = Theme.of(context).colorScheme;

    return IgnorePointer(
      ignoring: !_actionsVisible,
      child: AbsorbPointer(
        absorbing: !_actionsVisible,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final capsuleWidth = constraints.maxWidth < _capsuleWidth
                ? constraints.maxWidth
                : _capsuleWidth;
            final itemWidth = (capsuleWidth - 2) / 3;

            return Align(
              alignment: Alignment.centerRight,
              child: ClipRect(
                child: Transform.translate(
                  offset: Offset((1 - progress) * 22, 0),
                  child: Transform.scale(
                    alignment: Alignment.centerRight,
                    scale: 0.78 + progress * 0.22,
                    child: Opacity(
                      opacity: progress,
                      child: Container(
                        width: capsuleWidth,
                        height: 68,
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest
                              .withValues(alpha: .96),
                          borderRadius: BorderRadius.circular(40),
                          border: Border.all(
                            color: scheme.primary.withValues(alpha: .2),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: scheme.primary.withValues(alpha: .12),
                              blurRadius: 18,
                              spreadRadius: 1,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            _actionItem(
                                widget.isUnread
                                    ? Icons.mark_email_read_rounded
                                    : Icons.markunread_rounded,
                                widget.isUnread ? '已读' : '未读',
                                scheme.primary,
                                itemWidth),
                            _divider(),
                            _actionItem(
                                widget.isPinned
                                    ? Icons.push_pin_outlined
                                    : Icons.push_pin,
                                widget.isPinned ? '取消置顶' : '置顶',
                                const Color(0xFFD97706),
                                itemWidth),
                            _divider(),
                            _actionItem(Icons.settings_rounded, '设置',
                                const Color(0xFF9CA3AF), itemWidth),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _actionItem(
      IconData icon, String label, Color color, double itemWidth) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _handleAction(label),
      child: SizedBox(
        width: itemWidth,
        height: 68,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 21),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .86),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider() {
    return Container(
      width: 1,
      height: 34,
      color: Colors.white.withValues(alpha: .1),
    );
  }

  Widget _buildCard(double progress) {
    final scheme = Theme.of(context).colorScheme;
    final activeScale = _actionsVisible ? 1 - progress * .025 : 1.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handleTap,
      onLongPress: _showActions,
      child: Transform.scale(
        alignment: Alignment.centerLeft,
        scale: activeScale,
        child: Container(
          height: 68,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: .42),
            borderRadius: BorderRadius.circular(40),
            border: Border.all(color: scheme.primary.withValues(alpha: .12)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .2),
                blurRadius: 12 + progress * 8,
                offset: Offset(0, 4 + progress * 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Stack(
                children: [
                  AppAvatar(
                    source: widget.avatar,
                    radius: 22,
                    icon: widget.icon,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: widget.online
                            ? Colors.green
                            : scheme.surfaceContainerHighest,
                        shape: BoxShape.circle,
                        border: Border.all(color: scheme.surface, width: 2),
                      ),
                      child: const SizedBox(width: 11, height: 11),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              color: scheme.onSurface,
                              fontWeight: widget.isUnread
                                  ? FontWeight.w900
                                  : FontWeight.w800,
                            ),
                          ),
                        ),
                        if (widget.isUnread)
                          const Padding(
                            padding: EdgeInsets.only(left: 5),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.redAccent,
                                shape: BoxShape.circle,
                              ),
                              child: SizedBox(width: 7, height: 7),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurface.withValues(alpha: .78),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                widget.time,
                style: TextStyle(color: scheme.primary, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
