import 'dart:convert';
import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

String? template(StringLiteral node) {
  var index = 0;
  String read(StringLiteral n) {
    if (n is SimpleStringLiteral) return n.value;
    if (n is AdjacentStrings) return n.strings.map(read).join();
    if (n is StringInterpolation)
      return n.elements
          .map((e) => e is InterpolationString ? e.value : '{p${index++}}')
          .join();
    return '';
  }

  return read(node);
}

class Inventory extends GeneralizingAstVisitor<void> {
  Inventory(this.file, this.source, this.rows);
  final String file, source;
  final List<Map<String, dynamic>> rows;
  @override
  void visitStringLiteral(StringLiteral n) {
    if (n.parent is AdjacentStrings) return;
    final value = template(n);
    if (value == null ||
        (!RegExp(r'[А-Яа-яЁёӘәҒғҚқҢңӨөҰұҮүҺһІі]').hasMatch(value) &&
            !(n.parent is MethodInvocation &&
                (n.parent as MethodInvocation).methodName.name == 'tr'))) {
      super.visitStringLiteral(n);
      return;
    }
    AstNode? p = n.parent;
    final parents = <String>[];
    bool translated = false;
    String? owner, field;
    while (p != null) {
      if (p is MethodInvocation &&
          [
            'tr',
            'trValue',
            'translate',
            'translateSource',
            'localizedValue',
          ].contains(p.methodName.name))
        translated = true;
      if (p is NamedExpression) field ??= p.name.label.name;
      if (p is MapLiteralEntry && p.value == n) field ??= p.key.toSource();
      if (p is MethodDeclaration || p is FunctionDeclaration) {
        owner = p is MethodDeclaration
            ? p.name.lexeme
            : (p as FunctionDeclaration).name.lexeme;
        break;
      }
      parents.add(p.runtimeType.toString().replaceAll('Impl', ''));
      p = p.parent;
    }
    rows.add({
      'file': file,
      'line': '\n'.allMatches(source.substring(0, n.offset)).length + 1,
      'offset': n.offset,
      'length': n.length,
      'text': value,
      'translated': translated,
      'field': field,
      'owner': owner,
      'parents': parents.take(6).toList(),
      'code': n.toSource(),
    });
    super.visitStringLiteral(n);
  }
}

void main(List<String> args) {
  final rows = <Map<String, dynamic>>[];
  for (final f
      in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (x) =>
                x.path.endsWith('.dart') &&
                !x.path.startsWith('lib/localization/'),
          )) {
    final s = f.readAsStringSync();
    final ast = parseString(
      content: s,
      path: f.path,
      throwIfDiagnostics: false,
    );
    ast.unit.accept(Inventory(f.path, s, rows));
  }
  File(
    args.isNotEmpty ? args.first : '/tmp/domly-text-inventory.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(rows));
  print(
    'Text literal occurrences: ${rows.length}; within translation calls: ${rows.where((r) => r['translated'] == true).length}',
  );
}
