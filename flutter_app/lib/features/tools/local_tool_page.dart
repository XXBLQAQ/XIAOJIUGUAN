import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LocalTool { countdown, wheel, converter, password }

class LocalToolPage extends StatefulWidget {
  const LocalToolPage({super.key, required this.tool});

  final LocalTool tool;

  @override
  State<LocalToolPage> createState() => _LocalToolPageState();
}

class _LocalToolPageState extends State<LocalToolPage> {
  final _titleController = TextEditingController();
  final _wheelController = TextEditingController(text: '吃火锅\n看电影\n唱歌\n桌游');
  final _valueController = TextEditingController(text: '1');
  final _random = Random.secure();
  DateTime? _targetDate;
  String _wheelResult = '';
  String _password = '';
  String _unit = '千米 -> 英里';
  bool _includeSymbols = true;
  double _passwordLength = 16;

  @override
  void initState() {
    super.initState();
    if (widget.tool == LocalTool.countdown) _loadCountdown();
    if (widget.tool == LocalTool.password) _generatePassword();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _wheelController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  String get _pageTitle => switch (widget.tool) {
        LocalTool.countdown => '倒数日',
        LocalTool.wheel => '随机转盘',
        LocalTool.converter => '单位换算',
        LocalTool.password => '密码生成器',
      };

  Future<void> _loadCountdown() async {
    final prefs = await SharedPreferences.getInstance();
    final target =
        DateTime.tryParse(prefs.getString('tool_countdown_date') ?? '');
    if (!mounted) return;
    setState(() {
      _titleController.text = prefs.getString('tool_countdown_title') ?? '';
      _targetDate = target;
    });
  }

  Future<void> _saveCountdown() async {
    if (_targetDate == null || _titleController.text.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tool_countdown_title', _titleController.text.trim());
    await prefs.setString(
        'tool_countdown_date', _targetDate!.toIso8601String());
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _targetDate ?? now,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 30),
      helpText: '选择目标日期',
    );
    if (selected == null) return;
    setState(() => _targetDate = selected);
    await _saveCountdown();
  }

  void _spinWheel() {
    final entries = _wheelController.text
        .split(RegExp(r'\n|,'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (entries.length < 2) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请至少输入两个选项')));
      return;
    }
    setState(() => _wheelResult = entries[_random.nextInt(entries.length)]);
  }

  double get _convertedValue {
    final value = double.tryParse(_valueController.text.trim()) ?? 0;
    return switch (_unit) {
      '千米 -> 英里' => value * 0.621371,
      '英里 -> 千米' => value * 1.609344,
      '摄氏度 -> 华氏度' => value * 9 / 5 + 32,
      '华氏度 -> 摄氏度' => (value - 32) * 5 / 9,
      '千克 -> 磅' => value * 2.204623,
      _ => value / 2.204623,
    };
  }

  Future<void> _copyPassword() async {
    await Clipboard.setData(ClipboardData(text: _password));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('密码已复制')));
  }

  void _generatePassword() {
    const letters = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
    const numbers = '23456789';
    const symbols = '!@#%&*?';
    final characters = '$letters$numbers${_includeSymbols ? symbols : ''}';
    setState(() {
      _password = List.generate(
        _passwordLength.round(),
        (_) => characters[_random.nextInt(characters.length)],
      ).join();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(_pageTitle)),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _buildTool(),
            ],
          ),
        ),
      );

  Widget _buildTool() => switch (widget.tool) {
        LocalTool.countdown => _buildCountdown(),
        LocalTool.wheel => _buildWheel(),
        LocalTool.converter => _buildConverter(),
        LocalTool.password => _buildPassword(),
      };

  Widget _buildCountdown() {
    final date = _targetDate;
    final remaining = date == null
        ? null
        : DateUtils.dateOnly(date)
            .difference(DateUtils.dateOnly(DateTime.now()))
            .inDays;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _titleController,
        maxLength: 32,
        onChanged: (_) => _saveCountdown(),
        decoration:
            const InputDecoration(labelText: '事件名称', hintText: '例如：毕业、生日、旅行'),
      ),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: _pickDate,
        icon: const Icon(Icons.calendar_month_rounded),
        label: Text(date == null
            ? '选择目标日期'
            : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}'),
      ),
      const SizedBox(height: 28),
      if (remaining != null)
        _ResultPanel(
          title: _titleController.text.trim().isEmpty
              ? '倒数日'
              : _titleController.text.trim(),
          result: remaining >= 0 ? '还有 $remaining 天' : '已过去 ${-remaining} 天',
          icon: Icons.hourglass_bottom_rounded,
        ),
    ]);
  }

  Widget _buildWheel() =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _wheelController,
          minLines: 5,
          maxLines: 8,
          decoration: const InputDecoration(
              labelText: '转盘选项', hintText: '每行一个选项，也可用逗号分隔'),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _spinWheel,
          icon: const Icon(Icons.casino_rounded),
          label: const Text('开始随机'),
        ),
        const SizedBox(height: 28),
        if (_wheelResult.isNotEmpty)
          _ResultPanel(
              title: '这次就选',
              result: _wheelResult,
              icon: Icons.auto_awesome_rounded),
      ]);

  Widget _buildConverter() =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DropdownButtonFormField<String>(
          initialValue: _unit,
          decoration: const InputDecoration(labelText: '换算类型'),
          items: const [
            '千米 -> 英里',
            '英里 -> 千米',
            '摄氏度 -> 华氏度',
            '华氏度 -> 摄氏度',
            '千克 -> 磅',
            '磅 -> 千克'
          ]
              .map(
                  (value) => DropdownMenuItem(value: value, child: Text(value)))
              .toList(),
          onChanged: (value) => setState(() => _unit = value!),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _valueController,
          keyboardType: const TextInputType.numberWithOptions(
              decimal: true, signed: true),
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: '输入数值'),
        ),
        const SizedBox(height: 28),
        _ResultPanel(
            title: _unit,
            result: _convertedValue.toStringAsFixed(2),
            icon: Icons.swap_horiz_rounded),
      ]);

  Widget _buildPassword() =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _ResultPanel(
            title: '新密码', result: _password, icon: Icons.password_rounded),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _copyPassword,
          icon: const Icon(Icons.copy_rounded),
          label: const Text('复制密码'),
        ),
        const SizedBox(height: 20),
        Text('密码长度：${_passwordLength.round()}'),
        Slider(
          value: _passwordLength,
          min: 8,
          max: 32,
          divisions: 24,
          label: _passwordLength.round().toString(),
          onChanged: (value) {
            setState(() => _passwordLength = value);
            _generatePassword();
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('包含符号'),
          value: _includeSymbols,
          onChanged: (value) {
            setState(() => _includeSymbols = value);
            _generatePassword();
          },
        ),
        FilledButton.icon(
          onPressed: _generatePassword,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('生成新密码'),
        ),
      ]);
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel(
      {required this.title, required this.result, required this.icon});

  final String title;
  final String result;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        label: '$title，$result',
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(children: [
            Icon(icon, size: 36, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SelectableText(result,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall),
          ]),
        ),
      );
}
