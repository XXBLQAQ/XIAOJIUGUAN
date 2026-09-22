Uri? parseSafeHttpsUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      uri.scheme.toLowerCase() != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      (uri.port != 0 && uri.port != 443)) {
    return null;
  }
  return uri;
}
