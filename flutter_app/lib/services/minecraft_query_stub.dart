import 'package:dio/dio.dart';
import 'minecraft_query.dart';

MinecraftQueryClient createPlatformMinecraftQueryClient(Dio dio) =>
    WebMinecraftQueryClient(dio);

class WebMinecraftQueryClient implements MinecraftQueryClient {
  final Dio dio;

  WebMinecraftQueryClient(this.dio);

  @override
  Future<MinecraftQueryResult> query({
    required String address,
    required int port,
    required MinecraftEdition edition,
    bool forceRefresh = false,
  }) async {
    final response = await dio.get<Map<String, dynamic>>(
      'https://api.mcsrvstat.us/3/${edition == MinecraftEdition.bedrock ? 'bedrock/' : ''}$address:$port',
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
      onlinePlayers: _number(players['online']),
      maxPlayers: _number(players['max']),
      version: _version(data['version']),
      motd: _description(motd),
      favicon: data['icon'] as String?,
    );
  }

  int _number(dynamic value) {
    final number = value is num ? value.toInt() : int.tryParse('$value');
    return number == null || number < 0 ? 0 : number;
  }

  String _version(dynamic value) {
    if (value is String && value.isNotEmpty) return value;
    if (value is Map && value['name'] is String) return value['name'] as String;
    return '未知版本';
  }

  String _description(dynamic value) {
    if (value is String) return value;
    if (value is List) return value.map(_description).join(' ').trim();
    if (value is Map) return _description(value['clean'] ?? value['text']);
    return '';
  }
}
