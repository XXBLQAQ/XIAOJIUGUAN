import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api_client.dart';
import '../../core/design_system.dart';
import '../../core/routes.dart';
import '../../services/auth_service.dart';

class CocktailRecipe {
  const CocktailRecipe({
    required this.id,
    required this.name,
    required this.keywords,
    required this.ingredients,
    required this.steps,
    required this.glass,
    required this.garnish,
    required this.taste,
    required this.abv,
    required this.category,
    required this.style,
  });

  final String id;
  final String name;
  final List<String> keywords, ingredients, steps;
  final String glass, garnish, taste, category, style;
  final int abv;

  factory CocktailRecipe.fromJson(Map<String, dynamic> json) => CocktailRecipe(
        id: json['id']?.toString() ??
            _stableId(json['name']?.toString() ?? '未命名配方'),
        name: json['name']?.toString() ?? '未命名配方',
        keywords: _stringList(json['keywords']),
        ingredients: _stringList(json['ingredients']),
        steps: _stringList(json['steps']),
        glass: json['glass']?.toString() ?? '未指定酒杯',
        garnish: json['garnish']?.toString() ?? '无',
        taste: json['taste']?.toString() ?? '未分类',
        abv: (json['abv'] as num?)?.round() ?? 0,
        category: json['category']?.toString() ?? '',
        style: json['style']?.toString() ?? '',
      );

  static String _stableId(String name) {
    final slug = name
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isNotEmpty
        ? slug
        : 'recipe-${name.runes.map((r) => r.toRadixString(16)).join()}';
  }

  static List<String> _stringList(Object? value) =>
      value is List ? value.whereType<String>().toList() : const [];
}

class CocktailRecipePage extends StatefulWidget {
  const CocktailRecipePage({super.key});
  @override
  State<CocktailRecipePage> createState() => _CocktailRecipePageState();
}

class _CocktailRecipePageState extends State<CocktailRecipePage> {
  static const _categories = <({String value, String label})>[
    (value: 'The Unforgettables', label: '不朽经典'),
    (value: 'The Contemporary Classics', label: '当代经典'),
    (value: 'The New Era', label: '新时代'),
  ];
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _searchDebounce;
  List<CocktailRecipe> _recipes = <CocktailRecipe>[];
  final Set<String> _favorites = {};
  final Map<String, int> _ratings = {};
  String _query = '', _taste = '全部', _category = '';
  final Set<String> _tastes = {'全部'};
  int _offset = 0;
  static const _limit = 20;
  bool _loading = false, _loadingMore = false, _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 240) _loadRecipes(loadMore: true);
    });
    _loadRecipes();
  }

  Future<void> _loadRecipes({bool loadMore = false}) async {
    if (_loading || _loadingMore || (loadMore && !_hasMore)) return;
    if (mounted) {
      setState(() {
        loadMore ? _loadingMore = true : _loading = true;
        _error = null;
      });
    }
    final nextOffset = loadMore ? _offset : 0;
    try {
      final params = <String, dynamic>{'limit': _limit, 'offset': nextOffset};
      if (_query.trim().isNotEmpty) {
        params['q'] = _query.trim();
        params['keyword'] = _query.trim();
      }
      if (_taste != '全部') {
        params['taste'] = _taste;
      }
      if (_category.isNotEmpty) {
        params['category'] = _category;
      }
      final response = await ApiClient()
          .get('/cocktail/recipes', authenticated: false, params: params);
      final raw = response.data is Map ? response.data['data'] : response.data;
      final list = raw is List
          ? raw
          : (raw is Map && raw['items'] is List
              ? raw['items'] as List
              : const []);
      final recipes = list
          .whereType<Map>()
          .map((e) => CocktailRecipe.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      if (!mounted) return;
      setState(() {
        if (loadMore) {
          _recipes.addAll(recipes);
        } else {
          _recipes = recipes;
          _tastes
            ..clear()
            ..add('全部')
            ..addAll(_recipes
                .map((recipe) => recipe.taste.trim())
                .where((taste) => taste.isNotEmpty)
                .toList()
              ..sort());
          if (!_tastes.contains(_taste)) _taste = '全部';
        }
        _offset = nextOffset + recipes.length;
        _hasMore = recipes.length >= _limit;
      });
      if (!loadMore) await _loadInteractions();
    } catch (e) {
      if (mounted) setState(() => _error = '配方加载失败，请检查网络后重试');
      debugPrint('[Cocktail] 配方请求失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _loadInteractions() async {
    if (!context.read<AuthService>().hasAccount) return;
    for (final recipe in _recipes) {
      try {
        final response =
            await ApiClient().get('/cocktail/recipes/${recipe.id}/interaction');
        final data = response.data is Map ? response.data['data'] : null;
        if (data is Map) {
          if (data['favorite'] == true) _favorites.add(recipe.id);
          if (data['rating'] is num) {
            _ratings[recipe.id] = (data['rating'] as num).round();
          }
        }
      } catch (e) {
        debugPrint('[Cocktail] 互动状态加载失败: $e');
      }
    }
    if (mounted) setState(() {});
  }

  void _resetAndLoad({String? query, String? taste, String? category}) {
    setState(() {
      if (query != null) _query = query;
      if (taste != null) _taste = taste;
      if (category != null) _category = category;
      _offset = 0;
      _hasMore = true;
    });
    if (query != null) {
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 350), _loadRecipes);
    } else {
      _loadRecipes();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('经典配方')),
        body: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(children: [
            AppSearchField(
                hint: '搜索酒名、食材或关键词',
                controller: _search,
                onChanged: (v) => _resetAndLoad(query: v)),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
                height: 42,
                child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _categories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final item = _categories[i];
                      return ChoiceChip(
                          label: Text(item.label),
                          selected: _category == item.value,
                          onSelected: (_) => _resetAndLoad(
                              category:
                                  _category == item.value ? '' : item.value));
                    })),
            const SizedBox(height: AppSpacing.sm),
            _filters(),
            const SizedBox(height: AppSpacing.md),
            Expanded(child: _body()),
          ]),
        ),
      );

  Widget _body() {
    if (_loading && _recipes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _recipes.isEmpty) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_error!),
        const SizedBox(height: 12),
        FilledButton(onPressed: _loadRecipes, child: const Text('重新加载'))
      ]));
    }
    if (_recipes.isEmpty) {
      return const Center(child: Text('没有匹配的配方'));
    }
    return ListView.separated(
        controller: _scroll,
        itemCount: _recipes.length + (_loadingMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => i == _recipes.length
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()))
            : _card(_recipes[i]));
  }

  Widget _filters() => Row(children: [
        Expanded(
            child: _filterDropdown('口味', _taste, _tastes.toList(),
                (v) => _resetAndLoad(taste: v!))),
      ]);

  Widget _filterDropdown(String label, String value, List<String> items,
          ValueChanged<String?> onChanged) =>
      Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .outline
                      .withValues(alpha: .3))),
          child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                  isExpanded: true,
                  value: value,
                  items: items
                      .map((i) =>
                          DropdownMenuItem(value: i, child: Text('$label：$i')))
                      .toList(),
                  onChanged: onChanged)));

  String _categoryLabel(String category) {
    final normalized = category.trim().toLowerCase();
    for (final item in _categories) {
      if (item.value.toLowerCase() == normalized) return item.label;
    }
    return category.isEmpty ? '未分类' : category;
  }

  String _abvText(CocktailRecipe r) => r.abv == 0 ? '未估算' : '${r.abv}% ABV';

  Widget _card(CocktailRecipe r) => AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: () => _details(r),
      child: Row(children: [
        Container(
            width: 54,
            height: 70,
            decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: .18),
                borderRadius: BorderRadius.circular(AppRadius.sm)),
            child: Icon(Icons.local_bar,
                color: Theme.of(context).colorScheme.primary, size: 30)),
        const SizedBox(width: 14),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r.name,
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          Text('${_categoryLabel(r.category)} · ${r.taste} · ${_abvText(r)}'),
          Text(r.ingredients.take(2).join('、'),
              maxLines: 1, overflow: TextOverflow.ellipsis)
        ])),
        IconButton(
            onPressed: () => _toggleFavorite(r),
            icon: Icon(_favorites.contains(r.id)
                ? Icons.favorite
                : Icons.favorite_border))
      ]));

  Future<bool> _requireLogin() async {
    if (context.read<AuthService>().hasAccount) return true;
    await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('登录后使用'),
                content: const Text('收藏和评分需要登录账号。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () {
                        Navigator.pop(c);
                        Navigator.pushNamed(context, AppRoutes.login);
                      },
                      child: const Text('去登录'))
                ]));
    return false;
  }

  Future<void> _toggleFavorite(CocktailRecipe r) async {
    if (!await _requireLogin()) return;
    final old = _favorites.contains(r.id), next = !old;
    setState(() => next ? _favorites.add(r.id) : _favorites.remove(r.id));
    try {
      await ApiClient()
          .put('/cocktail/recipes/${r.id}/favorite', data: {'favorite': next});
    } catch (e) {
      if (mounted) {
        setState(() => old ? _favorites.add(r.id) : _favorites.remove(r.id));
      }
      debugPrint('[Cocktail] 收藏失败: $e');
    }
  }

  void _details(CocktailRecipe r) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.name, style: Theme.of(context).textTheme.headlineSmall),
                Text(
                    '${_categoryLabel(r.category)} · ${r.taste} · ${_abvText(r)}'),
                if (r.style.trim().isNotEmpty) Text('风格：${r.style}'),
                const SizedBox(height: 16),
                Text('食材用量', style: Theme.of(context).textTheme.titleMedium),
                ...r.ingredients.map((e) => Text('• $e')),
                const SizedBox(height: 12),
                Text('调制步骤', style: Theme.of(context).textTheme.titleMedium),
                ...r.steps
                    .asMap()
                    .entries
                    .map((e) => Text('${e.key + 1}. ${e.value}')),
                const SizedBox(height: 12),
                Text('酒杯：${r.glass}'),
                Text('装饰：${r.garnish}'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('评分：'),
                    ...List.generate(
                        5,
                        (i) => IconButton(
                              onPressed: () async {
                                if (!await _requireLogin()) return;
                                final old = _ratings[r.id] ?? 0;
                                setState(() => _ratings[r.id] = i + 1);
                                setSheet(() {});
                                try {
                                  await ApiClient().put(
                                      '/cocktail/recipes/${r.id}/rating',
                                      data: {'rating': i + 1});
                                } catch (e) {
                                  if (mounted) {
                                    setState(() => _ratings[r.id] = old);
                                    setSheet(() {});
                                  }
                                  debugPrint('[Cocktail] 评分失败: $e');
                                }
                              },
                              icon: Icon(
                                  i < (_ratings[r.id] ?? 0)
                                      ? Icons.star
                                      : Icons.star_border,
                                  color: Colors.amber),
                            )),
                    IconButton(
                        onPressed: () => _share(r),
                        icon: const Icon(Icons.share)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _share(CocktailRecipe r) => Share.share(
      '${r.name}\n${r.ingredients.join('\n')}\n步骤：${r.steps.join('；')}',
      subject: r.name);

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchDebounce = null;
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }
}
