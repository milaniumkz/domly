import 'package:flutter/material.dart';

/// Keeps desktop rows and turns wide groups into a readable phone column.
/// Flexible children belong to the horizontal row only, never to the column.
class AdminAdaptiveRow extends StatelessWidget {
  const AdminAdaptiveRow({
    super.key,
    required this.children,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.mainAxisSize = MainAxisSize.max,
    this.breakpoint = 600,
    this.spacing = 12,
  });
  final List<Widget> children;
  final CrossAxisAlignment crossAxisAlignment;
  final MainAxisAlignment mainAxisAlignment;
  final MainAxisSize mainAxisSize;
  final double breakpoint;
  final double spacing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, size) {
          if (!size.hasBoundedWidth || size.maxWidth >= breakpoint) {
            return Row(
              mainAxisAlignment: mainAxisAlignment,
              mainAxisSize: mainAxisSize,
              crossAxisAlignment: crossAxisAlignment,
              children: children,
            );
          }
          final items = <Widget>[];
          for (var child in children) {
            if (child is Spacer) continue;
            if (child is Flexible) child = child.child;
            if (child is SizedBox &&
                child.child == null &&
                child.height == null) continue;
            if (items.isNotEmpty) items.add(SizedBox(height: spacing));
            items.add(child);
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: items,
          );
        },
      );
}

/// A toolbar remains reachable when filters expand or the keyboard is open.
class AdminSectionLayout extends StatelessWidget {
  const AdminSectionLayout({super.key, this.toolbar, required this.child});
  final Widget? toolbar;
  final Widget child;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, size) {
          final mobile =
              size.maxWidth < 600 || MediaQuery.sizeOf(context).height < 600;
          return Column(
            children: [
              if (toolbar != null)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: mobile ? size.maxHeight * .38 : double.infinity,
                  ),
                  child: SingleChildScrollView(
                    primary: false,
                    padding: EdgeInsets.fromLTRB(
                      mobile ? 12 : 20,
                      mobile ? 12 : 20,
                      mobile ? 12 : 20,
                      8,
                    ),
                    child:
                        Align(alignment: Alignment.centerLeft, child: toolbar),
                  ),
                ),
              Expanded(child: child),
            ],
          );
        },
      );
}

/// Phone forms use the available width and leave room for the software keyboard.
class AdminFormDialog extends StatelessWidget {
  const AdminFormDialog({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.shape,
    this.insetPadding,
    this.contentPadding,
    this.scrollable = true,
  });
  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;
  final ShapeBorder? shape;
  final EdgeInsets? insetPadding;
  final EdgeInsets? contentPadding;
  final bool scrollable;
  @override
  Widget build(BuildContext context) => AlertDialog(
        title: title,
        content: content,
        actions: actions,
        shape: shape,
        scrollable: scrollable,
        insetPadding: insetPadding ??
            EdgeInsets.symmetric(
              horizontal: MediaQuery.sizeOf(context).width < 600 ? 12 : 40,
              vertical: 20,
            ),
        contentPadding:
            contentPadding ?? const EdgeInsets.fromLTRB(20, 16, 20, 20),
      );
}
