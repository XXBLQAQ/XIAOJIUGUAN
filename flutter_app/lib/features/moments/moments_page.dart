import 'package:flutter/material.dart';

import '../../core/design_system.dart';

class MomentsPage extends StatelessWidget {
  const MomentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('动态')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: const [
          AppCard(
            child: _MomentEmptyState(),
          ),
        ],
      ),
    );
  }
}

class _MomentEmptyState extends StatelessWidget {
  const _MomentEmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        children: [
          Icon(Icons.forum_outlined, size: 48, color: scheme.primary),
          const SizedBox(height: AppSpacing.md),
          Text('动态功能正在准备中', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '这里将展示好友的新鲜事，敬请期待。',
            style: TextStyle(color: scheme.onSurface.withValues(alpha: .65)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
