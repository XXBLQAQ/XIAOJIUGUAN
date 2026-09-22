import '../core/api_client.dart';

class AvatarCatalogService {
  static final AvatarCatalogService _instance = AvatarCatalogService._();
  factory AvatarCatalogService() => _instance;
  AvatarCatalogService._();

  final Map<String, String> _urls = {};
  Future<void>? _loading;

  String? urlFor(String id) => _urls[id];

  Future<void> load() {
    return _loading ??= _fetch().whenComplete(() => _loading = null);
  }

  Future<void> _fetch() async {
    final response = await ApiClient().get('/avatars', authenticated: false);
    final body = response.data is Map ? response.data['data'] : response.data;
    if (body is! List) return;
    for (final item in body.whereType<Map>()) {
      final data = Map<String, dynamic>.from(item);
      final id = data['id']?.toString();
      final url = data['url']?.toString();
      if (id != null && url != null && url.isNotEmpty) {
        _urls[id] = url;
      }
    }
  }
}
