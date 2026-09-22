import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/design_system.dart';

class CocktailBarPage extends StatefulWidget {
  const CocktailBarPage({super.key});

  @override
  State<CocktailBarPage> createState() => _CocktailBarPageState();
}

class _CocktailBarPageState extends State<CocktailBarPage> {
  static const _inventoryKey = 'cocktail_bar_inventory_v1';

  final Set<String> _inventory = {};
  List<_BarRecipe> _recipes = const [];
  bool _loading = true;
  bool _onlyMakeable = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadBar();
  }

  Future<void> _loadBar() async {
    try {
      final results = await Future.wait([
        rootBundle.loadString('assets/data/cocktail_recipes.json'),
        SharedPreferences.getInstance(),
      ]);
      final rawRecipes = jsonDecode(results[0] as String) as List<dynamic>;
      final preferences = results[1] as SharedPreferences;
      final saved = preferences.getStringList(_inventoryKey) ?? const [];
      if (!mounted) return;
      setState(() {
        _recipes = rawRecipes
            .whereType<Map>()
            .map((item) => _BarRecipe.fromJson(Map<String, dynamic>.from(item)))
            .toList();
        _inventory
          ..clear()
          ..addAll(saved);
        _loading = false;
      });
    } catch (error) {
      debugPrint('[CocktailBar] 加载调酒台失败: $error');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleIngredient(String ingredient) async {
    setState(() {
      if (!_inventory.add(ingredient)) _inventory.remove(ingredient);
    });
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(_inventoryKey, _inventory.toList()..sort());
  }

  List<String> get _ingredients {
    final values = <String>{};
    for (final recipe in _recipes) {
      values.addAll(recipe.ingredients);
    }
    return values.toList()..sort();
  }

  List<_BarRecipe> get _visibleRecipes {
    final query = _query.trim().toLowerCase();
    final recipes = _recipes.where((recipe) {
      final matchesQuery = query.isEmpty ||
          recipe.name.toLowerCase().contains(query) ||
          recipe.ingredients.any((item) => item.toLowerCase().contains(query));
      return matchesQuery && (!_onlyMakeable || recipe.missing(_inventory).isEmpty);
    }).toList();
    recipes.sort((a, b) {
      final makeable = a.missing(_inventory).isEmpty ? 0 : 1;
      final otherMakeable = b.missing(_inventory).isEmpty ? 0 : 1;
      final status = makeable.compareTo(otherMakeable);
      if (status != 0) return status;
      return a.missing(_inventory).length.compareTo(b.missing(_inventory).length);
    });
    return recipes;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的调酒台'),
        actions: [
          IconButton(
            tooltip: '管理原料',
            onPressed: _loading ? null : _showInventorySheet,
            icon: const Icon(Icons.inventory_2_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadBar,
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  _summary(scheme),
                  const SizedBox(height: AppSpacing.lg),
                  AppSearchField(
                    hint: '搜索酒名或原料',
                    onChanged: (value) => setState(() => _query = value),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('只看可调配方'),
                    subtitle: const Text('原料齐全的配方会优先显示'),
                    value: _onlyMakeable,
                    onChanged: (value) => setState(() => _onlyMakeable = value),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ..._visibleRecipes.map(_recipeCard),
                  if (_visibleRecipes.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 64),
                      child: Center(child: Text('没有符合条件的配方')),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _summary(ColorScheme scheme) {
    final makeable =
        _recipes.where((recipe) => recipe.missing(_inventory).isEmpty).length;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.local_bar_rounded, color: scheme.primary),
              ),
              const SizedBox(width: AppSpacing.md),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('今晚喝什么？',
                        style: TextStyle(
                            fontSize: 19, fontWeight: FontWeight.w800)),
                    SizedBox(height: 2),
                    Text('勾选已有材料，查看现在可以调制的配方'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              _stat('已有原料', '${_inventory.length}', scheme.primary),
              const SizedBox(width: AppSpacing.sm),
              _stat('现在可调', '$makeable', Colors.teal),
              const SizedBox(width: AppSpacing.sm),
              _stat('配方总数', '${_recipes.length}', scheme.secondary),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: _showInventorySheet,
            icon: const Icon(Icons.tune_rounded),
            label: const Text('管理我的原料'),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Text(value,
                  style: TextStyle(
                      color: color, fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      );

  Widget _recipeCard(_BarRecipe recipe) {
    final scheme = Theme.of(context).colorScheme;
    final missing = recipe.missing(_inventory);
    final makeable = missing.isEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        onTap: () => _showRecipe(recipe),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(recipe.name,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w800)),
                ),
                _statusChip(makeable, missing.length, scheme),
              ],
            ),
            const SizedBox(height: 4),
            Text('${recipe.taste} · ${recipe.glass} · ${recipe.abv}% ABV'),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: recipe.ingredients.map((ingredient) {
                final owned = _inventory.contains(ingredient);
                return Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(owned ? Icons.check_circle : Icons.add_circle_outline,
                      size: 17, color: owned ? Colors.teal : scheme.outline),
                  label: Text(ingredient),
                );
              }).toList(),
            ),
            if (!makeable) ...[
              const SizedBox(height: AppSpacing.sm),
              Text('还缺：${missing.join('、')}',
                  style: TextStyle(color: scheme.error, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusChip(bool makeable, int missingCount, ColorScheme scheme) => Chip(
        visualDensity: VisualDensity.compact,
        backgroundColor: (makeable ? Colors.teal : scheme.error)
            .withValues(alpha: .12),
        label: Text(makeable ? '可调' : '缺 $missingCount 种',
            style: TextStyle(
                color: makeable ? Colors.teal.shade700 : scheme.error,
                fontWeight: FontWeight.w700)),
      );

  void _showInventorySheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .78,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('我的原料',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  const Text('选择你现在有的材料，推荐会立即更新。'),
                  const SizedBox(height: AppSpacing.md),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _ingredients.length,
                      itemBuilder: (_, index) {
                        final ingredient = _ingredients[index];
                        return CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(ingredient),
                          value: _inventory.contains(ingredient),
                          onChanged: (_) async {
                            await _toggleIngredient(ingredient);
                            if (mounted) setSheetState(() {});
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showRecipe(_BarRecipe recipe) {
    final missing = recipe.missing(_inventory);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(recipe.name,
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text('${recipe.taste} · ${recipe.glass} · ${recipe.abv}% ABV'),
              const SizedBox(height: AppSpacing.lg),
              const Text('所需原料',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: AppSpacing.sm),
              ...recipe.ingredients.map((item) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      _inventory.contains(item)
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: _inventory.contains(item)
                          ? Colors.teal
                          : Theme.of(context).colorScheme.outline,
                    ),
                    title: Text(item),
                  )),
              if (missing.isNotEmpty) ...[
                Text('缺少：${missing.join('、')}',
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: AppSpacing.lg),
              ],
              const Text('制作步骤',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: AppSpacing.sm),
              ...recipe.steps.asMap().entries.map((entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 12,
                          child: Text('${entry.key + 1}',
                              style: const TextStyle(fontSize: 12)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(entry.value)),
                      ],
                    ),
                  )),
              if (missing.isEmpty)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.local_bar_rounded),
                    label: const Text('开始调制'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarRecipe {
  const _BarRecipe({
    required this.name,
    required this.ingredients,
    required this.steps,
    required this.glass,
    required this.taste,
    required this.abv,
  });

  final String name;
  final List<String> ingredients;
  final List<String> steps;
  final String glass;
  final String taste;
  final int abv;

  factory _BarRecipe.fromJson(Map<String, dynamic> json) => _BarRecipe(
        name: json['name']?.toString() ?? '未命名配方',
        ingredients: (json['ingredients'] as List? ?? const [])
            .map((item) => item.toString())
            .toList(),
        steps: (json['steps'] as List? ?? const [])
            .map((item) => item.toString())
            .toList(),
        glass: json['glass']?.toString() ?? '未指定酒杯',
        taste: json['taste']?.toString() ?? '未分类',
        abv: (json['abv'] as num?)?.round() ?? 0,
      );

  List<String> missing(Set<String> inventory) =>
      ingredients.where((item) => !inventory.contains(item)).toList();
}
