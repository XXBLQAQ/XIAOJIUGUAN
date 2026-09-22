import 'dart:convert';
import 'package:flutter/material.dart';

Widget localOrNetworkImage(String source, {BoxFit fit = BoxFit.cover}) {
  if (source.startsWith('data:image/')) {
    final separator = source.indexOf('base64,');
    if (separator >= 0) {
      try {
        final encoded = source.substring(separator + 7);
        if (encoded.length > 3 * 1024 * 1024) {
          return const Icon(Icons.broken_image_outlined);
        }
        return Image.memory(
          base64Decode(encoded),
          fit: fit,
        );
      } on FormatException {
        return const SizedBox.shrink();
      }
    }
  }
  return Image.network(source, fit: fit);
}
