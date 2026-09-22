import 'package:flutter/material.dart';

/// 统一间距资源。
abstract final class AppSpacing {
  static const double xs = 6;
  static const double sm = 10;
  static const double md = 16;
  static const double lg = 22;
  static const double xl = 28;
}

/// 统一圆角资源。
abstract final class AppRadius {
  static const double sm = 14;
  static const double input = 16;
  static const double md = 20;
  static const double lg = 28;
  static const double pill = 40;
}

/// 统一阴影资源。
abstract final class AppShadows {
  static List<BoxShadow> floating(BuildContext context) => [
        BoxShadow(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .12),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ];
}

/// 应用内统一的深色圆角卡片。
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.md);
    final card = Ink(
      padding: padding,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: radius,
      ),
      child: child,
    );
    if (onTap == null && onLongPress == null) {
      return card;
    }
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: radius,
        child: card,
      ),
    );
  }
}

/// 页面顶部统一标题。
class AppPageHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData actionIcon;
  final VoidCallback? onAction;

  const AppPageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.actionIcon,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                subtitle,
                style: TextStyle(
                  color: scheme.primary.withValues(alpha: .82),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onAction,
          icon: Icon(actionIcon, color: scheme.primary),
        ),
      ],
    );
  }
}

/// 统一搜索输入，复用应用输入框的颜色、圆角和焦点状态。
class AppSearchField extends StatefulWidget {
  final String hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;

  const AppSearchField({
    super.key,
    required this.hint,
    this.controller,
    this.onChanged,
  });

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  late final TextEditingController _controller =
      widget.controller ?? TextEditingController();
  final FocusNode _focusNode = FocusNode();

  bool get _hasQuery => _controller.text.trim().isNotEmpty;
  bool get _isFocused => _focusNode.hasFocus;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_refresh);
    _focusNode.addListener(_refresh);
  }

  @override
  void dispose() {
    _controller.removeListener(_refresh);
    _focusNode.removeListener(_refresh);
    _focusNode.dispose();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  void _clear() {
    _controller.clear();
    widget.onChanged?.call('');
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final inputTheme = theme.inputDecorationTheme;
    final active = _isFocused || _hasQuery;
    final radius = BorderRadius.circular(AppRadius.input);
    final borderColor = active ? scheme.primary : scheme.outline;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      height: 52,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: active
            ? [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: .14),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        onChanged: widget.onChanged,
        textInputAction: TextInputAction.search,
        textAlignVertical: TextAlignVertical.center,
        style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: inputTheme.hintStyle?.copyWith(
            color: scheme.onSurface.withValues(alpha: .52),
          ),
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _hasQuery
              ? IconButton(
                  tooltip: '清除搜索',
                  onPressed: _clear,
                  icon: const Icon(Icons.close_rounded),
                )
              : null,
          constraints: const BoxConstraints(minHeight: 52),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          border: OutlineInputBorder(
            borderRadius: radius,
            borderSide: BorderSide(color: borderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: radius,
            borderSide:
                BorderSide(color: scheme.outline.withValues(alpha: .72)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: radius,
            borderSide: BorderSide(color: scheme.primary, width: 2),
          ),
        ),
      ),
    );
  }
}

/// 统一的强调色胶囊按钮。
class AppAccentButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  const AppAccentButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final button = FilledButton.styleFrom(
      backgroundColor: Theme.of(context).colorScheme.primary,
      foregroundColor: Theme.of(context).colorScheme.onPrimary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
    );
    if (icon == null) {
      return FilledButton(
          onPressed: onPressed, style: button, child: Text(label));
    }
    return FilledButton.icon(
      onPressed: onPressed,
      style: button,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}
