import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_client.dart';
import '../../core/design_system.dart';
import '../../services/auth_service.dart';

class CocktailNote {
  const CocktailNote(
      {required this.id,
      required this.title,
      required this.body,
      required this.category,
      required this.tags});
  final String id;
  final String title;
  final String body;
  final String category;
  final List<String> tags;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'category': category,
        'tags': tags
      };
  factory CocktailNote.fromJson(Map<String, dynamic> json) => CocktailNote(
        id: json['id'] as String? ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        title: json['title'] as String? ?? '未命名笔记',
        body: json['body'] as String? ?? '',
        category: json['category'] as String? ?? '灵感',
        tags: (json['tags'] as List? ?? const []).cast<String>(),
      );
}

class CocktailNotesPage extends StatefulWidget {
  const CocktailNotesPage({super.key});
  @override
  State<CocktailNotesPage> createState() => _CocktailNotesPageState();
}

class _CocktailNotesPageState extends State<CocktailNotesPage> {
  static const _storageKey = 'cocktail_notes';
  final _search = TextEditingController();
  List<CocktailNote> _notes = [];
  String _query = '';
  String _category = '全部';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    if (!mounted) return;
    if (auth.hasAccount) {
      try {
        final response = await ApiClient().get('/cocktail/notes');
        final data = response.data is Map ? response.data['data'] : null;
        if (data is List && mounted) {
          setState(() => _notes = data
              .whereType<Map>()
              .map((item) =>
                  CocktailNote.fromJson(Map<String, dynamic>.from(item)))
              .toList());
          return;
        }
      } catch (e) {
        debugPrint('[Cocktail] 远程笔记失败，使用本地数据: $e');
      }
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_storageKey) ?? [];
    if (!mounted) return;
    final notes = <CocktailNote>[];
    for (final item in raw) {
      try {
        final decoded = jsonDecode(item);
        if (decoded is Map<String, dynamic>) {
          notes.add(CocktailNote.fromJson(decoded));
        }
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      }
    }
    setState(() => _notes = notes);
  }

  Future<CocktailNote?> _saveNote(CocktailNote note,
      {bool create = false}) async {
    final auth = context.read<AuthService>();
    if (auth.hasAccount) {
      try {
        final path = '/cocktail/notes/${note.id}';
        final response = await (create
            ? ApiClient().post('/cocktail/notes', data: note.toJson())
            : ApiClient().put(path, data: note.toJson()));
        if (create && response.data is Map && response.data['data'] is Map) {
          final saved = CocktailNote.fromJson(
              Map<String, dynamic>.from(response.data['data']));
          final index = _notes.indexWhere((item) => item.id == note.id);
          if (index >= 0) setState(() => _notes[index] = saved);
          return saved;
        }
        return note;
      } catch (e) {
        debugPrint('[Cocktail] 笔记同步失败，保留本地数据: $e');
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _storageKey, _notes.map((item) => jsonEncode(item.toJson())).toList());
    return note;
  }

  List<CocktailNote> get _filtered => _notes.where((note) {
        final text =
            '${note.title} ${note.body} ${note.category} ${note.tags.join(' ')}'
                .toLowerCase();
        return (_category == '全部' || note.category == _category) &&
            text.contains(_query.toLowerCase());
      }).toList();

  Future<void> _edit([CocktailNote? note]) async {
    final result = await showDialog<CocktailNote>(
        context: context, builder: (_) => _NoteEditor(note: note));
    if (result == null) return;
    final isNew = !_notes.any((item) => item.id == result.id);
    setState(() {
      final index = _notes.indexWhere((item) => item.id == result.id);
      if (index < 0) {
        _notes.insert(0, result);
      } else {
        _notes[index] = result;
      }
    });
    await _saveNote(result, create: isNew);
  }

  Future<void> _confirmDelete(CocktailNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除笔记？'),
        content: Text('确定删除“${note.title}”吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final auth = context.read<AuthService>();
    setState(() => _notes.removeWhere((item) => item.id == note.id));
    if (auth.hasAccount) {
      try {
        await ApiClient().delete('/cocktail/notes/${note.id}');
        return;
      } catch (e) {
        debugPrint('[Cocktail] 删除笔记同步失败，保留本地数据: $e');
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _storageKey, _notes.map((item) => jsonEncode(item.toJson())).toList());
  }

  @override
  Widget build(BuildContext context) {
    final categories = [
      '全部',
      ...{..._notes.map((note) => note.category)}
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('调酒笔记'), actions: [
        IconButton(onPressed: () => _edit(), icon: const Icon(Icons.add))
      ]),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
        child: Column(children: [
          AppSearchField(
              hint: '搜索笔记、标签或灵感',
              controller: _search,
              onChanged: (value) => setState(() => _query = value)),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
              height: 38,
              child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: categories.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, index) {
                    final item = categories[index];
                    return ChoiceChip(
                        label: Text(item),
                        selected: item == _category,
                        onSelected: (_) => setState(() => _category = item));
                  })),
          const SizedBox(height: AppSpacing.md),
          Expanded(
              child: _filtered.isEmpty
                  ? const Center(child: Text('还没有笔记，记录一杯新灵感吧'))
                  : ListView.separated(
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (_, index) {
                        final note = _filtered[index];
                        return AppCard(
                            onTap: () => _showDetail(note),
                            onLongPress: () => _confirmDelete(note),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Expanded(
                                        child: Text(note.title,
                                            style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold))),
                                    IconButton(
                                        onPressed: () => _edit(note),
                                        icon: const Icon(Icons.edit_outlined))
                                  ]),
                                  Text(note.body,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 8),
                                  Wrap(spacing: 6, children: [
                                    Chip(label: Text(note.category)),
                                    ...note.tags.map(
                                        (tag) => Chip(label: Text('#$tag')))
                                  ]),
                                ]));
                      })),
        ]),
      ),
      floatingActionButton: FloatingActionButton(
          onPressed: () => _edit(), child: const Icon(Icons.add)),
    );
  }

  void _showDetail(CocktailNote note) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CocktailNoteDetailPage(
          note: note,
          onEdit: () {
            Navigator.pop(context);
            _edit(note);
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }
}

class CocktailNoteDetailPage extends StatelessWidget {
  const CocktailNoteDetailPage(
      {super.key, required this.note, required this.onEdit});

  final CocktailNote note;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('笔记详情'),
        actions: [
          IconButton(onPressed: onEdit, icon: const Icon(Icons.edit_outlined)),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(note.title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.sm),
            Text('${note.category} · ${note.tags.map((e) => '#$e').join(' ')}'),
            const Divider(height: AppSpacing.xl),
            Text(note.body, style: const TextStyle(fontSize: 16, height: 1.6)),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: note.body));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('笔记内容已复制')),
                );
              },
              icon: const Icon(Icons.copy_outlined),
              label: const Text('复制内容'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteEditor extends StatefulWidget {
  const _NoteEditor({this.note});
  final CocktailNote? note;
  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  late final _title = TextEditingController(text: widget.note?.title ?? '');
  late final _body = TextEditingController(text: widget.note?.body ?? '');
  late final _category =
      TextEditingController(text: widget.note?.category ?? '灵感');
  late final _tags =
      TextEditingController(text: widget.note?.tags.join(', ') ?? '');
  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(widget.note == null ? '新建笔记' : '编辑笔记'),
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: _title,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: '标题')),
            const SizedBox(height: AppSpacing.sm),
            TextField(
                controller: _body,
                maxLines: 5,
                decoration: const InputDecoration(labelText: '内容')),
            const SizedBox(height: AppSpacing.sm),
            TextField(
                controller: _category,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: '分类')),
            const SizedBox(height: AppSpacing.sm),
            TextField(
                controller: _tags,
                decoration: const InputDecoration(labelText: '标签（逗号分隔）'))
          ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消')),
            FilledButton(
                onPressed: () {
                  if (_title.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('请输入笔记标题')),
                    );
                    return;
                  }
                  Navigator.pop(
                      context,
                      CocktailNote(
                          id: widget.note?.id ??
                              DateTime.now().microsecondsSinceEpoch.toString(),
                          title: _title.text.trim(),
                          body: _body.text.trim(),
                          category: _category.text.trim().isEmpty
                              ? '灵感'
                              : _category.text.trim(),
                          tags: _tags.text
                              .split(',')
                              .map((tag) => tag.trim())
                              .where((tag) => tag.isNotEmpty)
                              .toList()));
                },
                child: const Text('保存'))
          ]);
  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _category.dispose();
    _tags.dispose();
    super.dispose();
  }
}
