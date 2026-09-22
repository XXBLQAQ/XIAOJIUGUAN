import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/design_system.dart';
import '../../services/local_image_store.dart';

class TravelPlannerPage extends StatefulWidget {
  const TravelPlannerPage({super.key});

  @override
  State<TravelPlannerPage> createState() => _TravelPlannerPageState();
}

class _TravelPlannerPageState extends State<TravelPlannerPage> {
  static const _storageKey = 'travel_planner_state';
  final _descriptionController = TextEditingController();
  final _scrollController = ScrollController();
  final _picker = ImagePicker();
  final List<_TravelNode> _nodes = [];
  DateTimeRange? _range;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _scrollController.dispose();
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_storageKey);
    if (raw != null) {
      final data = jsonDecode(raw);
      if (data is Map<String, dynamic>) {
        _descriptionController.text = data['description']?.toString() ?? '';
        final start = DateTime.tryParse(data['start']?.toString() ?? '');
        final end = DateTime.tryParse(data['end']?.toString() ?? '');
        if (start != null && end != null) {
          _range = DateTimeRange(start: start, end: end);
        }
        final items = data['nodes'];
        if (items is List) {
          _nodes.addAll(items.whereType<Map>().map(
              (item) => _TravelNode.fromJson(Map<String, dynamic>.from(item))));
        }
      }
    }
    await Future.wait(_nodes.map(_restoreImage));
    if (_nodes.isEmpty) {
      _nodes.add(_TravelNode(date: DateTime.now()));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
        _storageKey,
        jsonEncode({
          'description': _descriptionController.text,
          'start': _range?.start.toIso8601String(),
          'end': _range?.end.toIso8601String(),
          'nodes': _nodes.map((node) => node.toJson()).toList(),
        }));
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      initialDateRange: _range,
      helpText: '选择出行日期',
      saveText: '确定',
      cancelText: '取消',
    );
    if (picked == null) {
      return;
    }
    setState(() => _range = picked);
    await _save();
  }

  Future<void> _addNode() async {
    final date = _range?.start ?? DateTime.now();
    setState(() =>
        _nodes.add(_TravelNode(date: date.add(Duration(days: _nodes.length)))));
    await _save();
  }

  Future<void> _pickImage(_TravelNode node) async {
    final image =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 82);
    if (image == null) {
      return;
    }
    final imagePath = await saveLocalImage(image);
    if (imagePath == null || imagePath.isEmpty) return;
    final bytes = await image.readAsBytes();
    if (!mounted) return;
    setState(() {
      node.imagePath = imagePath;
      node.imageBytes = bytes;
    });
    await _save();
  }

  Future<void> _restoreImage(_TravelNode node) async {
    final path = node.imagePath;
    if (path == null || path.isEmpty) return;
    try {
      node.imageBytes = await XFile(path).readAsBytes();
    } catch (_) {
      node.imagePath = null;
    }
  }

  Future<void> _toggleNode(_TravelNode node) async {
    setState(() => node.completed = !node.completed);
    await _save();
    if (node.completed && mounted) {
      await _scrollController.animateTo(0,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic);
    }
  }

  // 节点名称和详情直接在卡片内编辑；日期通过节点日期按钮修改。
  Future<void> _editNode(_TravelNode node) async {
    final name = TextEditingController(text: node.title);
    final details = TextEditingController(text: node.details);
    final date = await showDialog<DateTime>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('编辑行程节点'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: name,
              decoration: const InputDecoration(labelText: '节点名称')),
          const SizedBox(height: 12),
          TextField(
              controller: details,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '节点详情')),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final picked = await showDatePicker(
                context: dialogContext,
                firstDate: DateTime(2020),
                lastDate: DateTime(2035),
                initialDate: node.date,
              );
              if (picked != null && dialogContext.mounted) {
                Navigator.pop(dialogContext, picked);
              }
            },
            icon: const Icon(Icons.calendar_month_rounded),
            label: Text(_dateText(node.date)),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, node.date),
              child: const Text('保存')),
        ],
      ),
    );
    if (date == null) {
      name.dispose();
      details.dispose();
      return;
    }
    setState(() {
      node.title = name.text.trim().isEmpty ? '行程节点' : name.text.trim();
      node.details = details.text.trim();
      node.date = date;
    });
    name.dispose();
    details.dispose();
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('出行规划')),
      body: LayoutBuilder(builder: (context, constraints) {
        final maxWidth = constraints.maxWidth > 900 ? 820.0 : double.infinity;
        return Center(
          child: SizedBox(
            width: maxWidth,
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                AppCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('出行规划',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _descriptionController,
                        maxLines: 2,
                        onChanged: (_) => _save(),
                        decoration: const InputDecoration(
                            labelText: '行程描述', hintText: '例如：周末去海边放松'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _pickRange,
                        icon: const Icon(Icons.date_range_rounded),
                        label: Text(_range == null
                            ? '选择起始日期与截止日期'
                            : '${_dateText(_range!.start)} - ${_dateText(_range!.end)}'),
                      ),
                    ])),
                const SizedBox(height: 20),
                ..._buildNodes(scheme),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                    onPressed: _addNode,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('添加行程节点')),
              ],
            ),
          ),
        );
      }),
    );
  }

  List<Widget> _buildNodes(ColorScheme scheme) {
    final pending = _nodes.where((node) => !node.completed).toList();
    final completed = _nodes.where((node) => node.completed).toList();
    final widgets = <Widget>[];
    for (var index = 0; index < pending.length; index++) {
      widgets.add(_nodeTile(
          pending[index], index, pending.length + completed.length, scheme));
    }
    if (completed.isNotEmpty) {
      widgets.add(ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 8),
        leading: const Icon(Icons.check_circle_outline_rounded),
        title: Text('已完成 ${completed.length} 个节点'),
        subtitle: const Text('点击展开查看'),
        children: [
          for (var i = 0; i < completed.length; i++)
            _nodeTile(completed[i], i, completed.length, scheme)
        ],
      ));
    }
    return widgets;
  }

  Widget _nodeTile(_TravelNode node, int index, int total, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 38,
          child: Column(children: [
            Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                    color: node.completed ? scheme.outline : scheme.primary,
                    shape: BoxShape.circle)),
            if (index < total - 1)
              Container(
                  width: 2,
                  height: 170,
                  color: scheme.primary.withValues(alpha: .35)),
          ]),
        ),
        Expanded(
          child: AppCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  InkWell(
                    onTap: () => _editNode(node),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: SizedBox(
                        width: 92,
                        child: Text(_dateText(node.date),
                            style: TextStyle(
                                color: scheme.primary,
                                fontWeight: FontWeight.w800))),
                  ),
                  Expanded(
                      child: TextField(
                          controller: node.titleController,
                          onChanged: (value) {
                            node.title = value;
                            _save();
                          },
                          decoration: InputDecoration(
                              hintText: '输入节点名称',
                              hintStyle: TextStyle(
                                  color:
                                      scheme.onSurface.withValues(alpha: .38)),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 10),
                              isDense: true))),
                  IconButton(
                      onPressed: () => _toggleNode(node),
                      icon: Icon(
                          node.completed
                              ? Icons.check_circle
                              : Icons.check_circle_outline,
                          color: node.completed
                              ? scheme.outline
                              : scheme.primary)),
                ]),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                    controller: node.detailsController,
                    maxLines: 3,
                    onChanged: (value) {
                      node.details = value;
                      _save();
                    },
                    decoration: InputDecoration(
                        hintText: '输入行程详情（可选）',
                        hintStyle: TextStyle(
                            color: scheme.onSurface.withValues(alpha: .38)),
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.all(14))),
                if (node.imageBytes != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Image.memory(node.imageBytes!,
                        height: 130, width: double.infinity, fit: BoxFit.cover),
                  ),
                Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                        onPressed: () => _pickImage(node),
                        icon: const Icon(Icons.image_outlined),
                        label: const Text('插入图片'))),
              ])),
        ),
      ]),
    );
  }

  String _dateText(DateTime date) => '${date.month}月${date.day}日';
}

class _TravelNode {
  DateTime date;
  String title;
  String details;
  String? imagePath;
  Uint8List? imageBytes;
  bool completed;
  late final TextEditingController titleController;
  late final TextEditingController detailsController;

  _TravelNode(
      {required this.date,
      this.title = '',
      this.details = '',
      this.imagePath,
      this.completed = false}) {
    titleController = TextEditingController(text: title);
    detailsController = TextEditingController(text: details);
  }

  factory _TravelNode.fromJson(Map item) => _TravelNode(
        date:
            DateTime.tryParse(item['date']?.toString() ?? '') ?? DateTime.now(),
        title: item['title']?.toString() ?? '',
        details: item['details']?.toString() ?? '',
        imagePath: item['imagePath']?.toString(),
        completed: item['completed'] == true ||
            item['completed']?.toString().toLowerCase() == 'true',
      );

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'title': title,
        'details': details,
        'imagePath': imagePath,
        'completed': completed
      };

  void dispose() {
    titleController.dispose();
    detailsController.dispose();
  }
}
