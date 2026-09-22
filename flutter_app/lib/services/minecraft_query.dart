import 'dart:async';
import 'package:dio/dio.dart';

class MinecraftQueryResult {
  final bool online;
  final int onlinePlayers;
  final int maxPlayers;
  final String version;
  final String motd;
  final String? favicon;

  const MinecraftQueryResult({
    required this.online,
    required this.onlinePlayers,
    required this.maxPlayers,
    required this.version,
    required this.motd,
    this.favicon,
  });
}

abstract interface class MinecraftQueryClient {
  Future<MinecraftQueryResult> query({
    required String address,
    required int port,
    required MinecraftEdition edition,
    bool forceRefresh = false,
  });
}

MinecraftQueryClient createMinecraftQueryClient(Dio dio) =>
    ResilientMinecraftQueryClient(dio);

enum MinecraftEdition { java, bedrock }

enum MinecraftQueryErrorType {
  timeout,
  dns,
  serverOffline,
  invalidResponse,
  tamperedResponse,
  rateLimited,
  nodeCircuitOpen,
  connection,
  http,
  unknown,
}

class MinecraftQueryException implements Exception {
  final MinecraftQueryErrorType type;
  final String message;

  const MinecraftQueryException(this.type, this.message);

  @override
  String toString() => message;
}

class MinecraftNodeMetric {
  final String node;
  int attempts = 0;
  int successes = 0;
  int failures = 0;
  int consecutiveFailures = 0;
  int totalLatencyMs = 0;
  DateTime? circuitOpenedAt;
  MinecraftQueryErrorType? lastError;

  MinecraftNodeMetric(this.node);

  double get successRate => attempts == 0 ? 0 : successes / attempts;
  double get averageLatencyMs =>
      successes == 0 ? 0 : totalLatencyMs / successes;
  bool get circuitOpen =>
      circuitOpenedAt != null &&
      DateTime.now().difference(circuitOpenedAt!) < const Duration(minutes: 10);
}

class MinecraftQueryMetrics {
  final Map<String, MinecraftNodeMetric> nodes = {};
  int totalRequests = 0;
  int cacheHits = 0;
  int retries = 0;
  int rateLimited = 0;

  Map<String, dynamic> toJson() => {
        'totalRequests': totalRequests,
        'cacheHits': cacheHits,
        'retries': retries,
        'rateLimited': rateLimited,
        'nodes': nodes.map((key, value) => MapEntry(key, {
              'attempts': value.attempts,
              'successes': value.successes,
              'failures': value.failures,
              'successRate': value.successRate,
              'averageLatencyMs': value.averageLatencyMs,
              'circuitOpen': value.circuitOpen,
              'lastError': value.lastError?.name,
            })),
      };
}

class ResilientMinecraftQueryClient implements MinecraftQueryClient {
  static const nodeUrls = <String>[
    'https://api.mcsrvstat.us/3',
    'https://api.mcstatus.io/v2/status',
  ];
  static const _timeouts = <Duration>[
    Duration(seconds: 5),
    Duration(seconds: 7),
  ];

  final Dio dio;
  final MinecraftQueryMetrics metrics = MinecraftQueryMetrics();
  final Map<String, _CachedQuery> _cache = {};
  final Map<String, DateTime> _lastRequests = {};
  final Map<String, Future<MinecraftQueryResult>> _inFlight = {};

  ResilientMinecraftQueryClient(this.dio);

  @override
  Future<MinecraftQueryResult> query({
    required String address,
    required int port,
    required MinecraftEdition edition,
    bool forceRefresh = false,
  }) async {
    final normalized = _normalizeAddress(address);
    if (normalized == null || port < 1 || port > 65535) {
      throw const MinecraftQueryException(
          MinecraftQueryErrorType.invalidResponse, '服务器地址或端口格式不正确');
    }
    final key = '$normalized:$port:${edition.name}';
    final cached = _cache[key];
    if (!forceRefresh &&
        cached != null &&
        DateTime.now().difference(cached.createdAt) <
            const Duration(minutes: 5)) {
      metrics.cacheHits++;
      return cached.result;
    }
    final existing = _inFlight[key];
    if (existing != null) return existing;
    final future = _queryWithNodes(normalized, port, edition, key);
    _inFlight[key] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<MinecraftQueryResult> _queryWithNodes(
      String address, int port, MinecraftEdition edition, String key) async {
    metrics.totalRequests++;
    final lastRequest = _lastRequests[key];
    if (lastRequest != null &&
        DateTime.now().difference(lastRequest) <
            const Duration(milliseconds: 300)) {
      metrics.rateLimited++;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    _lastRequests[key] = DateTime.now();
    MinecraftQueryException? lastError;
    final orderedNodes = [...nodeUrls];
    for (var index = 0; index < orderedNodes.length; index++) {
      final node = orderedNodes[index];
      final metric = metrics.nodes.putIfAbsent(
        node,
        () => MinecraftNodeMetric(node),
      );
      if (metric.circuitOpen) continue;
      if (index > 0) metrics.retries++;
      try {
        final started = DateTime.now();
        final result = await _requestNode(
          node,
          address,
          port,
          edition,
          _timeouts[index],
        );
        final elapsed = DateTime.now().difference(started).inMilliseconds;
        metric.attempts++;
        metric.successes++;
        metric.consecutiveFailures = 0;
        metric.totalLatencyMs += elapsed;
        metric.circuitOpenedAt = null;
        _cache[key] = _CachedQuery(result, DateTime.now());
        return result;
      } catch (error) {
        final failure = _classify(error);
        lastError = failure;
        metric.attempts++;
        metric.failures++;
        metric.consecutiveFailures++;
        metric.lastError = failure.type;
        if (metric.consecutiveFailures >= 5 ||
            (metric.attempts >= 5 && metric.failures / metric.attempts > .2)) {
          metric.circuitOpenedAt = DateTime.now();
        }
      }
    }
    throw lastError ??
        const MinecraftQueryException(
            MinecraftQueryErrorType.serverOffline, '所有查询节点均不可用');
  }

  Future<MinecraftQueryResult> _requestNode(
    String node,
    String address,
    int port,
    MinecraftEdition edition,
    Duration timeout,
  ) async {
    final path = node.contains('mcstatus.io')
        ? '$node/${edition == MinecraftEdition.bedrock ? 'bedrock' : 'java'}/$address:$port'
        : '$node/$address:$port';
    final response = await dio
        .get<Map<String, dynamic>>(
          path,
          options: Options(
            connectTimeout: timeout,
            receiveTimeout: timeout,
            sendTimeout: timeout,
            responseType: ResponseType.json,
          ),
        )
        .timeout(timeout);
    if (response.statusCode != 200 || response.data == null) {
      throw const MinecraftQueryException(
          MinecraftQueryErrorType.http, '查询节点返回异常');
    }
    return _parseResponse(response.data!);
  }

  MinecraftQueryResult _parseResponse(Map<String, dynamic> data) {
    final online = data['online'];
    if (online is! bool) {
      throw const MinecraftQueryException(
          MinecraftQueryErrorType.tamperedResponse, '查询响应缺少有效在线状态');
    }
    final players = (data['players'] is Map)
        ? Map<String, dynamic>.from(data['players'] as Map)
        : const <String, dynamic>{};
    final onlinePlayers = _nonNegativeInt(players['online']);
    final maxPlayers = _nonNegativeInt(players['max']);
    if (onlinePlayers > maxPlayers && maxPlayers > 0) {
      throw const MinecraftQueryException(
          MinecraftQueryErrorType.tamperedResponse, '查询响应人数数据异常');
    }
    final versionValue = data['version'];
    final version = _stringValue(versionValue) ??
        (versionValue is Map ? _stringValue(versionValue['name']) : null) ??
        (versionValue is Map ? _stringValue(versionValue['name_raw']) : null) ??
        '未知版本';
    final motdValue = data['motd'];
    final motd = _motdText(motdValue);
    final favicon = _stringValue(data['icon']) ?? _stringValue(data['favicon']);
    return MinecraftQueryResult(
      online: online,
      onlinePlayers: onlinePlayers,
      maxPlayers: maxPlayers,
      version: version,
      motd: motd,
      favicon: favicon,
    );
  }

  MinecraftQueryException _classify(Object error) {
    if (error is MinecraftQueryException) return error;
    if (error is TimeoutException ||
        error is DioException &&
            (error.type == DioExceptionType.connectionTimeout ||
                error.type == DioExceptionType.receiveTimeout)) {
      return const MinecraftQueryException(
          MinecraftQueryErrorType.timeout, '查询节点请求超时');
    }
    if (error is DioException &&
        error.type == DioExceptionType.connectionError) {
      return const MinecraftQueryException(
          MinecraftQueryErrorType.dns, '查询节点网络或DNS解析失败');
    }
    if (error is FormatException) {
      return const MinecraftQueryException(
          MinecraftQueryErrorType.invalidResponse, '查询响应格式无效');
    }
    return MinecraftQueryException(
        MinecraftQueryErrorType.unknown, error.toString());
  }

  String? _normalizeAddress(String value) {
    final address = value.trim().toLowerCase();
    if (address.isEmpty || address.contains('/') || address.contains(' ')) {
      return null;
    }
    return address;
  }

  int _nonNegativeInt(dynamic value) {
    final result = value is num ? value.toInt() : int.tryParse('$value');
    return result == null || result < 0 ? 0 : result;
  }

  String _motdText(dynamic value) {
    if (value is String) return value;
    if (value is List) return value.map(_motdText).join(' ').trim();
    if (value is Map) {
      final clean = value['clean'];
      if (clean is List && clean.isNotEmpty) return _motdText(clean);
      if (clean is String && clean.isNotEmpty) return clean;
      final text = value['text'];
      if (text != null) return _motdText(text);
      return '';
    }
    return '';
  }

  String? _stringValue(dynamic value) =>
      value is String && value.isNotEmpty ? value : null;
}

class _CachedQuery {
  final MinecraftQueryResult result;
  final DateTime createdAt;
  const _CachedQuery(this.result, this.createdAt);
}
