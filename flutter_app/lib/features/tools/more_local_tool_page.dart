import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum MoreLocalTool { pomodoro, whatToEat, bmi, timestamp }

class MoreLocalToolPage extends StatefulWidget {
  const MoreLocalToolPage({super.key, required this.tool});

  final MoreLocalTool tool;

  @override
  State<MoreLocalToolPage> createState() => _MoreLocalToolPageState();
}

class _MoreLocalToolPageState extends State<MoreLocalToolPage> {
  static const _pomodoroSeconds = 25 * 60;
  final _foodController = TextEditingController(text: '火锅\n面条\n炒饭\n麻辣烫');
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();
  final _timestampController = TextEditingController();
  final _random = Random.secure();
  Timer? _timer;
  int _remainingSeconds = _pomodoroSeconds;
  bool _isRunning = false;
  String _foodResult = '';
  bool _secondsTimestamp = true;

  @override
  void initState() {
    super.initState();
    if (widget.tool == MoreLocalTool.whatToEat) _loadFoodOptions();
    if (widget.tool == MoreLocalTool.timestamp) {
      _timestampController.text =
          (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _foodController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _timestampController.dispose();
    super.dispose();
  }

  String get _title => switch (widget.tool) {
        MoreLocalTool.pomodoro => '番茄时钟',
        MoreLocalTool.whatToEat => '今天吃什么',
        MoreLocalTool.bmi => 'BMI 计算器',
        MoreLocalTool.timestamp => '时间戳转换',
      };

  Future<void> _loadFoodOptions() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _foodController.text =
        prefs.getString('tool_food_options') ?? _foodController.text);
  }

  Future<void> _saveFoodOptions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tool_food_options', _foodController.text);
  }

  void _togglePomodoro() {
    if (_isRunning) {
      _timer?.cancel();
      setState(() => _isRunning = false);
      return;
    }
    setState(() => _isRunning = true);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_remainingSeconds <= 1) {
        timer.cancel();
        setState(() {
          _remainingSeconds = 0;
          _isRunning = false;
        });
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('本轮专注已完成')));
        return;
      }
      setState(() => _remainingSeconds--);
    });
  }

  void _resetPomodoro() {
    _timer?.cancel();
    setState(() {
      _remainingSeconds = _pomodoroSeconds;
      _isRunning = false;
    });
  }

  void _chooseFood() {
    final options = _foodController.text
        .split(RegExp(r'\n|,'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (options.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先输入至少一个菜品')));
      return;
    }
    _saveFoodOptions();
    setState(() => _foodResult = options[_random.nextInt(options.length)]);
  }

  double? get _bmi {
    final height = double.tryParse(_heightController.text.trim());
    final weight = double.tryParse(_weightController.text.trim());
    if (height == null || weight == null || height <= 0 || weight <= 0) {
      return null;
    }
    return weight / pow(height / 100, 2);
  }

  String get _bmiAdvice {
    final bmi = _bmi;
    if (bmi == null) return '输入身高和体重后计算';
    if (bmi < 18.5) return '偏瘦';
    if (bmi < 24) return '正常';
    if (bmi < 28) return '超重';
    return '肥胖';
  }

  DateTime? get _timestampDate {
    final value = int.tryParse(_timestampController.text.trim());
    if (value == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(
        _secondsTimestamp ? value * 1000 : value);
  }

  String get _formattedTimestamp {
    final date = _timestampDate;
    if (date == null) return '请输入有效时间戳';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(_title)),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [_buildTool()],
          ),
        ),
      );

  Widget _buildTool() => switch (widget.tool) {
        MoreLocalTool.pomodoro => _buildPomodoro(),
        MoreLocalTool.whatToEat => _buildFoodPicker(),
        MoreLocalTool.bmi => _buildBmi(),
        MoreLocalTool.timestamp => _buildTimestamp(),
      };

  Widget _buildPomodoro() {
    final minutes = (_remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_remainingSeconds % 60).toString().padLeft(2, '0');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _ResultPanel(
        title: _remainingSeconds == 0 ? '完成一轮专注' : '专注中',
        result: '$minutes:$seconds',
        icon: Icons.timer_rounded,
      ),
      const SizedBox(height: 24),
      FilledButton.icon(
        onPressed: _remainingSeconds == 0 ? _resetPomodoro : _togglePomodoro,
        icon: Icon(_isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded),
        label: Text(_remainingSeconds == 0
            ? '开始下一轮'
            : _isRunning
                ? '暂停'
                : '开始专注'),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _resetPomodoro,
        icon: const Icon(Icons.restart_alt_rounded),
        label: const Text('重置为 25 分钟'),
      ),
    ]);
  }

  Widget _buildFoodPicker() =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _foodController,
          minLines: 5,
          maxLines: 8,
          onChanged: (_) => _saveFoodOptions(),
          decoration: const InputDecoration(
              labelText: '候选菜品', hintText: '每行一个菜品，也可用逗号分隔'),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _chooseFood,
          icon: const Icon(Icons.restaurant_rounded),
          label: const Text('帮我决定'),
        ),
        const SizedBox(height: 28),
        if (_foodResult.isNotEmpty)
          _ResultPanel(
              title: '今天就吃',
              result: _foodResult,
              icon: Icons.lunch_dining_rounded),
      ]);

  Widget _buildBmi() =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _heightController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration:
              const InputDecoration(labelText: '身高（厘米）', hintText: '例如：170'),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _weightController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration:
              const InputDecoration(labelText: '体重（千克）', hintText: '例如：60'),
        ),
        const SizedBox(height: 28),
        _ResultPanel(
          title: _bmi == null ? 'BMI 指数' : 'BMI ${_bmi!.toStringAsFixed(1)}',
          result: _bmiAdvice,
          icon: Icons.monitor_weight_outlined,
        ),
      ]);

  Widget _buildTimestamp() =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _timestampController,
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Unix 时间戳'),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('输入为秒级时间戳'),
          value: _secondsTimestamp,
          onChanged: (value) => setState(() => _secondsTimestamp = value),
        ),
        OutlinedButton.icon(
          onPressed: () => setState(() {
            _timestampController.text = (_secondsTimestamp
                    ? DateTime.now().millisecondsSinceEpoch ~/ 1000
                    : DateTime.now().millisecondsSinceEpoch)
                .toString();
          }),
          icon: const Icon(Icons.schedule_rounded),
          label: const Text('填入当前时间'),
        ),
        const SizedBox(height: 28),
        _ResultPanel(
            title: '转换结果',
            result: _formattedTimestamp,
            icon: Icons.calendar_today_rounded),
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
