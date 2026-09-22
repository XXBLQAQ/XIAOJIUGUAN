import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/url_validation.dart';
import '../services/avatar_cache_service.dart';
import '../services/avatar_catalog_service.dart';

class AppAvatar extends StatefulWidget {
  const AppAvatar({super.key, this.source, this.radius = 34, this.icon});

  final String? source;
  final double radius;
  final IconData? icon;

  @override
  State<AppAvatar> createState() => _AppAvatarState();
}

class _AppAvatarState extends State<AppAvatar> {
  String? _catalogUrl;
  Uint8List? _cachedBytes;
  String? _cachedSource;

  @override
  void initState() {
    super.initState();
    _resolveCatalogAvatar();
  }

  @override
  void didUpdateWidget(covariant AppAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _catalogUrl = null;
      _cachedBytes = null;
      _cachedSource = null;
      _resolveCatalogAvatar();
    }
  }

  Future<void> _resolveCatalogAvatar() async {
    final value = widget.source?.trim() ?? '';
    if (parseSafeHttpsUrl(value) != null) {
      final cached = await loadCachedAvatar(value);
      if (mounted && cached != null) {
        setState(() {
          _cachedBytes = cached;
          _cachedSource = value;
        });
      }
      final downloaded = await cacheAvatar(value);
      if (mounted && downloaded != null && _cachedSource != value) {
        setState(() {
          _cachedBytes = downloaded;
          _cachedSource = value;
        });
      }
      return;
    }
    if (value.startsWith('/uploads/')) {
      final url = '${ApiClient.baseUrl.replaceFirst('/api', '')}$value';
      final cached = await loadCachedAvatar(url);
      if (mounted && cached != null) {
        setState(() {
          _cachedBytes = cached;
          _cachedSource = url;
        });
      }
      final downloaded = await cacheAvatar(url);
      if (mounted && downloaded != null && _cachedSource != url) {
        setState(() {
          _cachedBytes = downloaded;
          _cachedSource = url;
        });
      }
      return;
    }
    if (value.isEmpty || value.contains('/') || value.startsWith('http')) {
      return;
    }
    try {
      await AvatarCatalogService().load();
      final url = AvatarCatalogService().urlFor(value);
      if (mounted) setState(() => _catalogUrl = url);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final value = _catalogUrl ?? widget.source?.trim() ?? '';
    ImageProvider<Object>? image;
    if (_cachedBytes != null && _cachedSource == value) {
      image = MemoryImage(_cachedBytes!);
    } else if (value.startsWith('assets/')) {
      image = AssetImage(value);
    } else if (parseSafeHttpsUrl(value) != null) {
      image = NetworkImage(value);
    } else if (value.startsWith('/uploads/')) {
      final uploadUrl = '${ApiClient.baseUrl.replaceFirst('/api', '')}$value';
      if (parseSafeHttpsUrl(uploadUrl) != null) {
        image = NetworkImage(uploadUrl);
      }
    }
    final fallback = Icon(
      widget.icon ?? Icons.person_rounded,
      size: widget.radius * .72,
      color: scheme.primary,
    );
    if (image == null) {
      return CircleAvatar(
        radius: widget.radius,
        backgroundColor: scheme.primary.withValues(alpha: .18),
        child: fallback,
      );
    }
    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: scheme.primary.withValues(alpha: .18),
      child: ClipOval(
        child: Image(
          image: image,
          width: widget.radius * 2,
          height: widget.radius * 2,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback,
        ),
      ),
    );
  }
}
