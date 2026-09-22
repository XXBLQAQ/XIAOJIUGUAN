import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/design_system.dart';

class _PostalEntry {
  const _PostalEntry({
    required this.administrativeCode,
    required this.province,
    required this.city,
    required this.district,
    required this.postalCode,
  });

  final String administrativeCode;
  final String province;
  final String city;
  final String district;
  final String postalCode;

  String get areaKey => [province, city, district].join('|');

  String get displayArea => areaKey.replaceAll('|', ' · ');
}

class PostalCodePage extends StatefulWidget {
  const PostalCodePage({super.key});

  @override
  State<PostalCodePage> createState() => _PostalCodePageState();
}

class _PostalCodePageState extends State<PostalCodePage> {
  final _provinceController = TextEditingController();
  final _cityController = TextEditingController();
  final _districtController = TextEditingController();
  final _codeController = TextEditingController();
  String? _areaResult;
  String? _codeResult;
  String? _error;
  bool _searching = false;
  List<_PostalEntry> _postalEntries = _fallbackEntries;
  Map<String, List<_PostalEntry>> _areaIndex =
      _buildAreaIndex(_fallbackEntries);
  Map<String, List<_PostalEntry>> _codeIndex =
      _buildCodeIndex(_fallbackEntries);
  bool _dataReady = false;

  static const _fallbackEntries = <_PostalEntry>[
    _PostalEntry(
        administrativeCode: '110101',
        province: '北京市',
        city: '北京市',
        district: '东城区',
        postalCode: '100010'),
    _PostalEntry(
        administrativeCode: '110102',
        province: '北京市',
        city: '北京市',
        district: '西城区',
        postalCode: '100032'),
    _PostalEntry(
        administrativeCode: '110105',
        province: '北京市',
        city: '北京市',
        district: '朝阳区',
        postalCode: '100020'),
    _PostalEntry(
        administrativeCode: '310101',
        province: '上海市',
        city: '上海市',
        district: '黄浦区',
        postalCode: '200001'),
    _PostalEntry(
        administrativeCode: '120101',
        province: '天津市',
        city: '天津市',
        district: '和平区',
        postalCode: '300041'),
    _PostalEntry(
        administrativeCode: '500103',
        province: '重庆市',
        city: '重庆市',
        district: '渝中区',
        postalCode: '400010'),
    _PostalEntry(
        administrativeCode: '371728',
        province: '山东省',
        city: '菏泽市',
        district: '东明县',
        postalCode: '274500'),
  ];

  static Map<String, List<_PostalEntry>> _buildAreaIndex(
      List<_PostalEntry> entries) {
    final index = <String, List<_PostalEntry>>{};
    for (final entry in entries) {
      index.putIfAbsent(entry.areaKey, () => []).add(entry);
    }
    return index;
  }

  static Map<String, List<_PostalEntry>> _buildCodeIndex(
      List<_PostalEntry> entries) {
    final index = <String, List<_PostalEntry>>{};
    for (final entry in entries) {
      index.putIfAbsent(entry.postalCode, () => []).add(entry);
    }
    return index;
  }

  @override
  void initState() {
    super.initState();
    _loadCompletePostalData();
  }

  Future<void> _loadCompletePostalData() async {
    try {
      final json = await rootBundle.loadString('assets/data/postal_codes.json');
      final parsed = _parsePostalJson(json);
      if (parsed.isNotEmpty && mounted) {
        setState(() {
          _postalEntries = parsed;
          _areaIndex = _buildAreaIndex(parsed);
          _codeIndex = _buildCodeIndex(parsed);
          _dataReady = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _dataReady = true);
    }
  }

  List<_PostalEntry> _parsePostalJson(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! List) return [];

    final result = <_PostalEntry>[];
    final seen = <String>{};
    for (final item in decoded) {
      if (item is! Map) continue;
      final administrativeCode = item['code']?.toString().trim();
      final province = item['province']?.toString().trim();
      final city = item['city']?.toString().trim();
      final district = item['name']?.toString().trim();
      final postalCode = item['zipCode']?.toString().trim();
      if (administrativeCode == null ||
          province == null ||
          city == null ||
          district == null ||
          postalCode == null ||
          province.isEmpty ||
          city.isEmpty ||
          district.isEmpty ||
          !RegExp(r'^\d{6}$').hasMatch(postalCode) ||
          postalCode == administrativeCode) {
        continue;
      }
      final entry = _PostalEntry(
        administrativeCode: administrativeCode,
        province: province,
        city: city,
        district: district,
        postalCode: postalCode,
      );
      if (seen.add('${entry.areaKey}|$postalCode')) result.add(entry);
    }

    return result;
  }

  @override
  void dispose() {
    _provinceController.dispose();
    _cityController.dispose();
    _districtController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  String _normalizeAreaName(String value) {
    var normalized = value.trim().replaceAll(RegExp(r'\s+'), '');
    const aliases = {
      '北京': '北京市',
      '天津': '天津市',
      '上海': '上海市',
      '重庆': '重庆市',
      '内蒙古': '内蒙古自治区',
      '广西': '广西壮族自治区',
      '西藏': '西藏自治区',
      '宁夏': '宁夏回族自治区',
      '新疆': '新疆维吾尔自治区',
    };
    normalized = aliases[normalized] ?? normalized;
    return normalized;
  }

  Future<void> _queryByArea() async {
    FocusScope.of(context).unfocus();
    final province = _normalizeAreaName(_provinceController.text);
    final city = _normalizeAreaName(_cityController.text);
    final district = _normalizeAreaName(_districtController.text);
    if (province.isEmpty || city.isEmpty || district.isEmpty) {
      setState(() {
        _error = '请完整填写省或直辖市、城市和区/县';
        _areaResult = null;
      });
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
      _areaResult = null;
    });
    await Future<void>.delayed(const Duration(milliseconds: 260));
    final exact = _areaIndex['$province|$city|$district'] ?? const [];
    final matches = exact.isNotEmpty
        ? exact
        : _postalEntries
            .where((entry) =>
                entry.province == province &&
                entry.city == city &&
                entry.district == district)
            .toList();
    final codes = matches.map((entry) => entry.postalCode).toSet().toList();
    if (!mounted) return;
    setState(() {
      _searching = false;
      _areaResult = codes.isEmpty
          ? '暂未找到该地区的邮政编码'
          : '$province $city $district\n邮政编码：${codes.join('、')}';
      _error = codes.isEmpty ? '当前数据暂未收录该地区，请检查名称是否填写完整' : null;
    });
  }

  Future<void> _queryByCode() async {
    FocusScope.of(context).unfocus();
    final code = _codeController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() {
        _error = '请输入 6 位数字邮政编码';
        _codeResult = null;
      });
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
      _codeResult = null;
    });
    await Future<void>.delayed(const Duration(milliseconds: 260));
    final matches = _codeIndex[code] ?? const [];
    if (!mounted) return;
    setState(() {
      _searching = false;
      _codeResult = matches.isEmpty
          ? '暂未找到该邮编对应的区域'
          : '邮政编码：$code\n${matches.map((entry) => entry.displayArea).join('\n')}';
      _error = matches.isEmpty ? '当前内置数据暂未收录该邮编' : null;
    });
  }

  InputDecoration _input(String hint, IconData icon, String example) =>
      InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon),
        helperText: example,
        helperMaxLines: 2,
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!_dataReady) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('邮编查询')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth > 720 ? 680.0 : double.infinity;
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: width),
                child: Column(
                  children: [
                    _queryCard(
                      title: '查询地区邮政编码',
                      children: [
                        TextField(
                            controller: _provinceController,
                            decoration: _input(
                                '省或直辖市名',
                                Icons.location_on_outlined,
                                '例：江苏省（名称请写全，需带省字）')),
                        const SizedBox(height: AppSpacing.md),
                        TextField(
                            controller: _cityController,
                            decoration: _input(
                                '城市名',
                                Icons.location_city_outlined,
                                '例：南京市（名称请写全，需带市字）')),
                        const SizedBox(height: AppSpacing.md),
                        TextField(
                            controller: _districtController,
                            decoration: _input('区/县', Icons.map_outlined,
                                '例：秦淮区（名称请写全，需带区或县字）')),
                        const SizedBox(height: AppSpacing.lg),
                        _queryButton('查询', _queryByArea),
                        if (_areaResult != null) _result(_areaResult!, scheme),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _queryCard(
                      title: '查询邮编所属区域',
                      children: [
                        TextField(
                            controller: _codeController,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            decoration: _input(
                                    '邮政编码',
                                    Icons.markunread_mailbox_outlined,
                                    '邮政编码 例：100020')
                                .copyWith(counterText: '')),
                        const SizedBox(height: AppSpacing.lg),
                        _queryButton('查询', _queryByCode),
                        if (_codeResult != null) _result(_codeResult!, scheme),
                      ],
                    ),
                    if (_error != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: Text(_error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: scheme.error))),
                    if (_searching)
                      const Padding(
                          padding: EdgeInsets.only(top: 18),
                          child: CircularProgressIndicator()),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _queryCard({required String title, required List<Widget> children}) =>
      AppCard(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: AppSpacing.lg),
          ...children,
        ]),
      );

  Widget _queryButton(String label, VoidCallback onPressed) => SizedBox(
        width: double.infinity,
        child: FilledButton(
            onPressed: _searching ? null : onPressed, child: Text(label)),
      );

  Widget _result(String text, ColorScheme scheme) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Text(text,
            style:
                TextStyle(color: scheme.primary, fontWeight: FontWeight.w700)),
      );
}
