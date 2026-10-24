import 'dart:convert';
import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

class Sinks extends RecursiveAstVisitor<void> {
  Sinks(this.path, this.src, this.rows);
  final String path, src;
  final List rows;
  @override
  void visitInstanceCreationExpression(InstanceCreationExpression n) {
    final type = n.constructorName.type.name.lexeme;
    scan(type, n.argumentList);
    super.visitInstanceCreationExpression(n);
  }

  @override
  void visitMethodInvocation(MethodInvocation n) {
    scan(n.methodName.name, n.argumentList);
    super.visitMethodInvocation(n);
  }

  void scan(String type, ArgumentList args) {
    for (final a in args.arguments) {
      final name = a is NamedExpression ? a.name.label.name : null;
      final v = a is NamedExpression ? a.expression : a;
      if ((['Text', 'SelectableText'].contains(type) &&
              a == args.arguments.first &&
              name == null) ||
          (type == 'TextSpan' && name == 'text') ||
          [
            'labelText',
            'hintText',
            'helperText',
            'errorText',
            'tooltip',
            'semanticsLabel',
            'semanticLabel',
          ].contains(name)) {
        if (!v.toSource().contains('.tr(') &&
            !v.toSource().contains('.trValue(') &&
            !v.toSource().contains('translate'))
          rows.add({
            'file': path,
            'line': '\n'.allMatches(src.substring(0, v.offset)).length + 1,
            'offset': v.offset,
            'length': v.length,
            'type': type,
            'field': name,
            'code': v.toSource(),
          });
      }
    }
  }
}

void main() {
  final rows = [];
  for (final f
      in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (f) =>
                f.path.endsWith('.dart') &&
                !f.path.startsWith('lib/screens/admin') &&
                !f.path.startsWith('lib/localization'),
          )) {
    final src = f.readAsStringSync();
    parseString(
      content: src,
      throwIfDiagnostics: false,
    ).unit.accept(Sinks(f.path, src, rows));
  }
  File(
    '/tmp/domly-unlocalized-sinks.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(rows));
  print(rows.length);
}
