import 'dart:convert';
import 'dart:io';

final RegExp _stringLiteralPattern = RegExp(
  r"""(?<!['"])(r?)(['"])((?:\\.|(?!\2).)*)\2""",
  multiLine: true,
);
final RegExp _hasCyrillic = RegExp(r'[А-Яа-яЁё]');

void main() {
  final root = Directory('lib');
  final values = <String>{};

  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) {
      continue;
    }
    if (entity.path.endsWith('default_translation_sources.dart')) {
      continue;
    }
    final content = entity.readAsStringSync();
    for (final match in _stringLiteralPattern.allMatches(content)) {
      final isRaw = match.group(1) == 'r';
      final body = match.group(3) ?? '';
      if (!_hasCyrillic.hasMatch(body)) {
        continue;
      }
      if (body.contains(r'${') || body.contains(r'$')) {
        continue;
      }
      final value = isRaw ? body : _decodeEscapes(body);
      final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (normalized.isEmpty) {
        continue;
      }
      values.add(normalized);
    }
  }

  final sorted = values.toList()..sort();
  final buffer = StringBuffer()
    ..writeln('const List<String> kDefaultTranslationSources = <String>[');
  for (final value in sorted) {
    buffer.writeln('  ${jsonEncode(value)},');
  }
  buffer
    ..writeln('];')
    ..writeln();

  final output = File('lib/localization/default_translation_sources.dart');
  output.writeAsStringSync(buffer.toString());
  stdout.writeln('Generated ${sorted.length} translation sources.');
}

String _decodeEscapes(String value) {
  final buffer = StringBuffer();
  for (var i = 0; i < value.length; i++) {
    final char = value[i];
    if (char != r'\') {
      buffer.write(char);
      continue;
    }
    if (i + 1 >= value.length) {
      buffer.write(char);
      continue;
    }
    final next = value[++i];
    switch (next) {
      case 'n':
        buffer.write('\n');
      case 'r':
        buffer.write('\r');
      case 't':
        buffer.write('\t');
      case '"':
        buffer.write('"');
      case '\'':
        buffer.write('\'');
      case '\\':
        buffer.write('\\');
      default:
        buffer.write(next);
    }
  }
  return buffer.toString();
}
