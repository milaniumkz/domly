/// Uploaded media URLs carry the original filename in the signed `key` query.
bool isDirectVideoSource(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return false;
  final path = (uri.queryParameters['key'] ?? uri.path).toLowerCase();
  return ['.mp4', '.webm', '.ogg', '.mov', '.m3u8'].any(path.endsWith);
}
