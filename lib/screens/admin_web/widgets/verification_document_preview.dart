import 'package:flutter/material.dart';

import 'verification_document_preview_io.dart'
    if (dart.library.html) 'verification_document_preview_web.dart' as impl;

Widget buildVerificationDocumentPreview({
  required String url,
  required BorderRadius borderRadius,
  BoxFit fit = BoxFit.cover,
}) {
  return impl.buildVerificationDocumentPreview(
    url: url,
    borderRadius: borderRadius,
    fit: fit,
  );
}
