import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'minecraft_query.dart';

MinecraftQueryClient createPlatformMinecraftQueryClient(Dio dio) =>
    IoMinecraftQueryClient(dio);

class IoMinecraftQueryClient implements MinecraftQueryClient {
  final Dio dio;

  IoMinecraftQueryClient(this.dio);

  @override
  Future<MinecraftQueryResult> query({
    required String address,
    required int port,
    required MinecraftEdition edition,
    bool forceRefresh = false,
  }) {
    if (edition == MinecraftEdition.java) {
      return _queryJava(address, port);
    }
    return _queryBedrock(address, port);
  }

  Future<MinecraftQueryResult> _queryJava(String address, int port) async {
    try {
      return await _queryJavaDirect(address, port);
    } on SocketException {
      return _queryWebFallback(address, port);
    } on TimeoutException {
      return _queryWebFallback(address, port);
    } catch (_) {
      // Java 状态协议异常时也尝试公网查询，避免本地协议差异直接显示离线。
      return _queryWebFallback(address, port);
    }
  }

  Future<MinecraftQueryResult> _queryJavaDirect(
      String address, int port) async {
    final socket = await Socket.connect(address, port,
        timeout: const Duration(seconds: 5));
    try {
      final handshake = <int>[
        ..._varInt(0),
        ..._varInt(760),
        ..._string(address),
        (port >> 8) & 0xff,
        port & 0xff,
        ..._varInt(1)
      ];
      socket
          .add([..._varInt(handshake.length + 1), ..._varInt(0), ...handshake]);
      socket.add([0x01, 0x00]);
      await socket.flush();

      final buffer = <int>[];
      await for (final chunk in socket.timeout(const Duration(seconds: 5))) {
        buffer.addAll(chunk);
        final json = _readStatusJson(buffer);
        if (json != null) {
          final players = json['players'] as Map<String, dynamic>?;
          final version = json['version'] as Map<String, dynamic>?;
          return MinecraftQueryResult(
            online: true,
            onlinePlayers: (players?['online'] as num?)?.toInt() ?? 0,
            maxPlayers: (players?['max'] as num?)?.toInt() ?? 0,
            version: version?['name'] as String? ?? '未知版本',
            motd: _description(json['description']),
            favicon: json['favicon'] as String?,
          );
        }
      }
      throw const FormatException('Invalid Java status response');
    } catch (_) {
      rethrow;
    } finally {
      await socket.close();
    }
  }

  Future<MinecraftQueryResult> _queryBedrock(String address, int port) =>
      _queryWebFallback(address, port, path: 'bedrock');

  Future<MinecraftQueryResult> _queryWebFallback(String address, int port,
      {String? path}) async {
    final endpoint = path == null
        ? 'https://api.mcsrvstat.us/3/$address:$port'
        : 'https://api.mcsrvstat.us/3/$path/$address:$port';
    final response = await dio.get<Map<String, dynamic>>(
      endpoint,
      options: Options(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
        responseType: ResponseType.json,
      ),
    );
    final data = response.data ?? const <String, dynamic>{};
    final players = data['players'] is Map
        ? Map<String, dynamic>.from(data['players'] as Map)
        : const <String, dynamic>{};
    final motd = data['motd'];
    return MinecraftQueryResult(
      online: data['online'] == true,
      onlinePlayers: _nonNegativeInt(players['online']),
      maxPlayers: _nonNegativeInt(players['max']),
      version: _versionText(data['version']),
      motd: _description(motd),
      favicon: data['icon'] as String?,
    );
  }

  Map<String, dynamic>? _readStatusJson(List<int> bytes) {
    final length = _readVarInt(bytes, 0);
    if (length == null || bytes.length < length.value + length.size) {
      return null;
    }
    final packetStart = length.size;
    final packetId = _readVarInt(bytes, packetStart);
    if (packetId == null || packetId.value != 0) return null;
    final jsonLength = _readVarInt(bytes, packetStart + packetId.size);
    if (jsonLength == null) return null;
    final jsonStart = packetStart + packetId.size + jsonLength.size;
    final jsonEnd = jsonStart + jsonLength.value;
    if (bytes.length < jsonEnd) return null;
    return jsonDecode(String.fromCharCodes(bytes.sublist(jsonStart, jsonEnd)))
        as Map<String, dynamic>;
  }

  List<int> _string(String value) =>
      [..._varInt(value.length), ...utf8.encode(value)];

  List<int> _varInt(int value) {
    final result = <int>[];
    do {
      var current = value & 0x7f;
      value >>= 7;
      if (value != 0) current |= 0x80;
      result.add(current);
    } while (value != 0);
    return result;
  }

  _VarInt? _readVarInt(List<int> bytes, int offset) {
    var value = 0;
    var shift = 0;
    for (var index = offset;
        index < bytes.length && index < offset + 5;
        index++) {
      final current = bytes[index];
      value |= (current & 0x7f) << shift;
      if ((current & 0x80) == 0) return _VarInt(value, index - offset + 1);
      shift += 7;
    }
    return null;
  }

  String _description(dynamic value) {
    if (value is String) return value;
    if (value is List) return value.map(_description).join(' ').trim();
    if (value is Map) {
      final clean = value['clean'];
      if (clean is List && clean.isNotEmpty) return _description(clean);
      if (clean is String && clean.isNotEmpty) return clean;
      return _description(value['text']);
    }
    return '';
  }

  String _versionText(dynamic value) {
    if (value is String && value.isNotEmpty) return value;
    if (value is Map) {
      final name = value['name'] ?? value['name_raw'];
      if (name is String && name.isNotEmpty) return name;
    }
    return '未知版本';
  }

  int _nonNegativeInt(dynamic value) {
    final result = value is num ? value.toInt() : int.tryParse('$value');
    return result == null || result < 0 ? 0 : result;
  }
}

class _VarInt {
  final int value;
  final int size;
  const _VarInt(this.value, this.size);
}
