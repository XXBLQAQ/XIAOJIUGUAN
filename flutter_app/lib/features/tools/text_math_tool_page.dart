import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum TextMathTool { base64, randomNumber, dateCalculator, baseConverter }

class TextMathToolPage extends StatefulWidget {
  const TextMathToolPage({super.key, required this.tool});

  final TextMathTool tool;

  @override
  State<TextMathToolPage> createState() => _TextMathToolPageState();
}

class _TextMathToolPageState extends State<TextMathToolPage> {
  final _inputController = TextEditingController();
  final _minController = TextEditingController(text: '1');
  final _maxController = TextEditingController(text: '100');
  final _numberController = TextEditingController(text: '255');
  final _random = Random.secure();
  String _result = '';
  int _sourceRadix = 10;
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 7));

  @override
  void initState() {
    super.initState();
    if (widget.tool == TextMathTool.randomNumber) _generateRandom();
    if (widget.tool == TextMathTool.baseConverter) _convertBase();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _minController.dispose();
    _maxController.dispose();
    _numberController.dispose();
    super.dispose();
  }

  String get _title => switch (widget.tool) {
        TextMathTool.base64 => 'Base64 编解码',
        TextMathTool.randomNumber => '随机数生成器',
        TextMathTool.dateCalculator => '日期计算器',
        TextMathTool.baseConverter => '进制转换器',
      };

  void _encodeBase64() {
    setState(() => _result = base64Encode(utf8.encode(_inputController.text)));
  }

  void _decodeBase64() {
    try {
      setState(() =>
          _result = utf8.decode(base64Decode(_inputController.text.trim())));
    } on FormatException {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请输入有效的 Base64 内容')));
    }
  }

  void _generateRandom() {
    final min = int.tryParse(_minController.text.trim());
    final max = int.tryParse(_maxController.text.trim());
    if (min == null || max == null || min > max) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请输入有效范围，最小值不能大于最大值')));
      return;
    }
    setState(() => _result = (min + _random.nextInt(max - min + 1)).toString());
  }

  int get _dateDifference => DateUtils.dateOnly(_endDate)
      .difference(DateUtils.dateOnly(_startDate))
      .inDays;

  Future<void> _pickDate({required bool start}) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: start ? _startDate : _endDate,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
      helpText: start ? '选择开始日期' : '选择结束日期',
    );
    if (selected == null) return;
    setState(() {
      if (start) {
        _startDate = selected;
      } else {
        _endDate = selected;
      }
    });
  }

  void _convertBase() {
    final value =
        int.tryParse(_numberController.text.trim(), radix: _sourceRadix);
    if (value == null) {
      setState(() => _result = '输入内容不符合 $_sourceRadix 进制');
      return;
    }
    setState(() => _result = '二进制：${value.toRadixString(2).toUpperCase()}\n'
        '八进制：${value.toRadixString(8).toUpperCase()}\n'
        '十进制：$value\n'
        '十六进制：${value.toRadixString(16).toUpperCase()}');
  }

  Future<void> _copyResult() async {
    if (_result.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _result));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('结果已复制')));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(_title)),
        body: SafeArea(
          child: ListView(
              padding: const EdgeInsets.all(20), children: [_buildTool()]),
        ),
      );

  Widget _buildTool() => switch (widget.tool) {
        TextMathTool.base64 => _buildBase64(),
        TextMathTool.randomNumber => _buildRandomNumber(),
        TextMathTool.dateCalculator => _buildDateCalculator(),
        TextMathTool.baseConverter => _buildBaseConverter(),
      };

  Widget _buildBase64() =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _inputController,
          minLines: 6,
          maxLines: 10,
          decoration: const InputDecoration(labelText: '输入内容'),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
              child: FilledButton(
                  onPressed: _encodeBase64, child: const Text('编码'))),
          const SizedBox(width: 12),
          Expanded(
              child: OutlinedButton(
                  onPressed: _decodeBase64, child: const Text('解码'))),
        ]),
        const SizedBox(height: 24),
        _ResultPanel(title: '转换结果', result: _result, icon: Icons.code_rounded),
        const SizedBox(height: 12),
        OutlinedButton.icon(
            onPressed: _copyResult,
            icon: const Icon(Icons.copy_rounded),
            label: const Text('复制结果')),
      ]);

  Widget _buildRandomNumber() =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
            controller: _minController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '最小值')),
        const SizedBox(height: 16),
        TextField(
            controller: _maxController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '最大值')),
        const SizedBox(height: 16),
        FilledButton.icon(
            onPressed: _generateRandom,
            icon: const Icon(Icons.casino_rounded),
            label: const Text('生成随机数')),
        const SizedBox(height: 28),
        _ResultPanel(
            title: '随机结果', result: _result, icon: Icons.numbers_rounded),
      ]);

  Widget _buildDateCalculator() =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        OutlinedButton.icon(
          onPressed: () => _pickDate(start: true),
          icon: const Icon(Icons.calendar_today_rounded),
          label: Text('开始：${_formatDate(_startDate)}'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _pickDate(start: false),
          icon: const Icon(Icons.event_rounded),
          label: Text('结束：${_formatDate(_endDate)}'),
        ),
        const SizedBox(height: 28),
        _ResultPanel(
          title: '相差天数',
          result: _dateDifference >= 0
              ? '$_dateDifference 天'
              : '结束日期早了 ${-_dateDifference} 天',
          icon: Icons.date_range_rounded,
        ),
      ]);

  Widget _buildBaseConverter() =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DropdownButtonFormField<int>(
          initialValue: _sourceRadix,
          decoration: const InputDecoration(labelText: '输入进制'),
          items: const [2, 8, 10, 16]
              .map((radix) =>
                  DropdownMenuItem(value: radix, child: Text('$radix 进制')))
              .toList(),
          onChanged: (value) {
            setState(() => _sourceRadix = value!);
            _convertBase();
          },
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _numberController,
          textCapitalization: TextCapitalization.characters,
          onChanged: (_) => _convertBase(),
          decoration: const InputDecoration(labelText: '输入数值'),
        ),
        const SizedBox(height: 28),
        _ResultPanel(
            title: '转换结果', result: _result, icon: Icons.transform_rounded),
        const SizedBox(height: 12),
        OutlinedButton.icon(
            onPressed: _copyResult,
            icon: const Icon(Icons.copy_rounded),
            label: const Text('复制结果')),
      ]);

  String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
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
            SelectableText(result.isEmpty ? '等待输入' : result,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall),
          ]),
        ),
      );
}
