import 'package:flutter/material.dart';
import '../../utils/backend_compat.dart';

import '../../localization/translation_controller.dart';
import '../../services/firestore_data_service.dart';
import '../../ui/domly_ui.dart';
import 'widgets/video_embed_player.dart';

class VideoDetailScreen extends StatefulWidget {
  const VideoDetailScreen({
    super.key,
    required this.videoId,
    required this.audienceType,
  });

  final String videoId;
  final String audienceType;

  @override
  State<VideoDetailScreen> createState() => _VideoDetailScreenState();
}

class _VideoDetailScreenState extends State<VideoDetailScreen> {
  bool _markedViewed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_markedViewed || !mounted) {
        return;
      }
      _markedViewed = true;
      await FirestoreDataService.instance.markVideoViewed(
        videoId: widget.videoId,
        audienceType: widget.audienceType,
        completed: true,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = FirestoreDataService.instance;

    return StreamBuilder<Map<String, dynamic>?>(
      stream: data.videoStream(widget.videoId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const DomlyShell(
            child: SafeArea(
              child: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    DomlyColors.buttonPrimary,
                  ),
                ),
              ),
            ),
          );
        }
        final video = snap.hasError
            ? data.fallbackVideoById(widget.videoId)
            : snap.data;
        if (video == null) {
          return const DomlyShell(
            child: SafeArea(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: DomlyEmptyStateCard(
                    title: 'Видео не найдено',
                    subtitle: 'Возможно, его удалили или скрыли.',
                    icon: Icons.play_circle_outline,
                  ),
                ),
              ),
            ),
          );
        }

        final title = video.trValue(const ['title'], fallback: 'Видео');
        final description = video.trValue(const ['description']);
        final thumbnailUrl = _resolvedThumbnailUrl(video);
        final videoUrl = (video['videoUrl'] ?? '').toString();
        final category = (video['category'] ?? 'Без категории').toString().tr();
        final isRequired =
            video['isRequired'] == true && widget.audienceType == 'cleaner';
        final publishedAt = _formatDate(video['publishedAt']);
        final details = _videoHighlights(description);

        return DomlyShell(
          child: SafeArea(
            child: SingleChildScrollView(
              child: SizedBox(
                width: MediaQuery.sizeOf(context).width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DomlyHeader(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
                      child: Row(
                        children: [
                          domlyTopIconButton(
                            icon: Icons.arrow_back,
                            onPressed: () => Navigator.pop(context),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Обучающее видео'.tr(),
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Смотрите прямо в приложении'.tr(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xCCFFFFFF),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: AspectRatio(
                              aspectRatio: 16 / 9,
                              child: videoUrl.isNotEmpty
                                  ? buildVideoEmbedPlayer(
                                      videoUrl: videoUrl,
                                      borderRadius: BorderRadius.circular(24),
                                    )
                                  : thumbnailUrl.isEmpty
                                  ? Container(
                                      color: DomlyColors.backgroundSoft,
                                      alignment: Alignment.center,
                                      child: const Icon(
                                        Icons.play_circle_outline,
                                        size: 72,
                                        color: DomlyColors.buttonPrimary,
                                      ),
                                    )
                                  : Image.network(
                                      thumbnailUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (
                                            context,
                                            error,
                                            stackTrace,
                                          ) => Container(
                                            color: DomlyColors.backgroundSoft,
                                            alignment: Alignment.center,
                                            child: const Icon(
                                              Icons.play_circle_outline,
                                              size: 72,
                                              color: DomlyColors.buttonPrimary,
                                            ),
                                          ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              DomlyStatusChip(label: category),
                              if (isRequired)
                                const DomlyStatusChip(
                                  label: 'Обязательно',
                                  color: DomlyColors.danger,
                                ),
                              if (publishedAt.isNotEmpty)
                                DomlyStatusChip(
                                  label: publishedAt,
                                  color: DomlyColors.accent,
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: DomlyColors.foreground,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            description,
                            style: const TextStyle(
                              fontSize: 14,
                              color: DomlyColors.muted,
                              height: 1.45,
                            ),
                          ),
                          if (details.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            DomlyCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Что внутри'.tr(),
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: DomlyColors.foreground,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Ключевые тезисы'.tr(),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: DomlyColors.muted,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  ...details.map(
                                    (item) => Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Text(
                                        '• $item',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: DomlyColors.foreground,
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatDate(dynamic value) {
    if (value == null) {
      return '';
    }
    final date = value is DateTime
        ? value
        : value is Timestamp
        ? value.toDate()
        : null;
    if (date == null) {
      return '';
    }
    return domlyDateText(date);
  }

  String _resolvedThumbnailUrl(Map<String, dynamic> video) {
    final explicit = (video['thumbnailUrl'] ?? '').toString().trim();
    if (explicit.isNotEmpty) {
      return explicit;
    }
    final videoUrl = (video['videoUrl'] ?? '').toString().trim();
    final uri = Uri.tryParse(videoUrl);
    if (uri == null) {
      return '';
    }
    final host = uri.host.toLowerCase();
    String? videoId;
    if (host.contains('youtube.com')) {
      videoId = uri.queryParameters['v'];
    } else if (host.contains('youtu.be')) {
      final segments = uri.pathSegments.where((segment) => segment.isNotEmpty);
      if (segments.isNotEmpty) {
        videoId = segments.first;
      }
    }
    if (videoId == null || videoId.isEmpty) {
      return '';
    }
    return 'https://img.youtube.com/vi/$videoId/hqdefault.jpg';
  }

  List<String> _videoHighlights(String description) {
    final normalized = description
        .split(RegExp(r'[\n\r]+|(?<=[.!?])\s+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    return normalized.take(3).toList();
  }
}
