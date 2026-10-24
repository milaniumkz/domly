# UI text catalogue

From the repository root:

```sh
(cd tool/ui_texts && dart pub get)
dart --packages=tool/ui_texts/.dart_tool/package_config.json tool/ui_texts/generate.dart
```

The Dart AST extractor handles adjacent literals and interpolation without regex
fragments. It writes bundled offline sources, immutable source keys/locations,
and an additive PostgreSQL seed. Existing RU/KK administrator edits are retained.
Placeholders must be retained in both languages; the admin API validates them.

`inventory.dart` records source occurrences. `sinks.dart` lists display expressions
without explicit translation calls for review. Its output is not a defect count:
user names, addresses, chat messages, dates and numeric values are data, not UI
wording. Custom Domly widgets translate their label/title arguments internally.
Do not translate database keys, status identifiers, user input or URLs.

When adding a screen, translate app-owned display text with `.tr()` and pass
variable values with `.tr(params: ...)`. Subscribe its build/dialog via
`TranslationScope.watch(context)` (also called by `DomlyPalette.watch`). Never
change widget keys to refresh wording: forms and scroll state must survive.

Run localization tests and the complete Flutter suite after regeneration. The
backend integration suite executes the generated SQL twice and verifies that
administrator wording survives. Native system dialogs and text drawn inside
uploaded images are not application dictionary entries.
