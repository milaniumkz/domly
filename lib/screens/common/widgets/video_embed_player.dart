import 'video_embed_player_io.dart'
    if (dart.library.html) 'video_embed_player_web.dart' as impl;

import 'package:flutter/widgets.dart';

Widget buildVideoEmbedPlayer({
  required String videoUrl,
  required BorderRadius borderRadius,
}) {
  return impl.buildVideoEmbedPlayer(
    videoUrl: videoUrl,
    borderRadius: borderRadius,
  );
}
