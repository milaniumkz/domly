import 'package:flutter/material.dart';

import '../../services/firestore_data_service.dart';
import '../../ui/domly_ui.dart';
import '../../localization/translation_controller.dart';

class VideoHubScreen extends StatefulWidget {
  const VideoHubScreen({
    super.key,
    required this.audienceType,
    required this.title,
    required this.subtitle,
  });

  final String audienceType;
  final String title;
  final String subtitle;

  @override
  State<VideoHubScreen> createState() => _VideoHubScreenState();
}

class _VideoHubScreenState extends State<VideoHubScreen> {
  static const _background = Color(0xFFF2FAF7);
  static const _foreground = Color(0xFF20382F);
  static const _muted = Color(0xFF6C8A7B);
  static const _border = Color(0xFFDDEAE3);
  static const _orange = Color(0xFFCF7548);
  static const _green = Color(0xFF4EA16C);
  static const _chipSoft = Color(0xFFEEF7F2);
  static const _thumb = Color(0xFFDDEEE6);

  final _data = FirestoreDataService.instance;
  String _selectedCategory = 'Все';

  @override
  Widget build(BuildContext context) {
    final isCleaner = widget.audienceType == 'cleaner';
    final videoStream =
        isCleaner ? _data.cleanerVideosStream() : _data.clientVideosStream();

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: videoStream,
      builder: (context, videosSnap) {
        if (videosSnap.connectionState == ConnectionState.waiting &&
            !videosSnap.hasData) {
          return DomlyShell(
            bottomNavigationBar:
                isCleaner ? null : const DomlyClientBottomNav(currentIndex: 0),
            child: const SafeArea(
              child: Center(
                child: CircularProgressIndicator(color: _green),
              ),
            ),
          );
        }
        final videos = videosSnap.hasError
            ? _data.fallbackVideosForAudience(widget.audienceType)
            : videosSnap.data ?? const <Map<String, dynamic>>[];
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _data.userVideoViewsStream(),
          builder: (context, viewsSnap) {
            if (viewsSnap.connectionState == ConnectionState.waiting &&
                !viewsSnap.hasData) {
              return DomlyShell(
                bottomNavigationBar: isCleaner
                    ? null
                    : const DomlyClientBottomNav(currentIndex: 0),
                child: const SafeArea(
                  child: Center(
                    child: CircularProgressIndicator(color: _green),
                  ),
                ),
              );
            }
            final views = viewsSnap.hasError
                ? const <Map<String, dynamic>>[]
                : viewsSnap.data ?? const <Map<String, dynamic>>[];
            final viewedIds = views
                .where((view) => (view['completed'] ?? false) == true)
                .map((view) => (view['videoId'] ?? '').toString())
                .toSet();
            final categories = <String>{
              'Все',
              ...videos
                  .map(
                    (video) =>
                        (video['category'] ?? 'Без категории').toString(),
                  )
                  .where((category) => category.isNotEmpty),
            }.toList();
            final filteredVideos = videos.where((video) {
              if (_selectedCategory == 'Все') {
                return true;
              }
              return (video['category'] ?? '').toString() == _selectedCategory;
            }).toList();

            return DomlyShell(
              bottomNavigationBar: isCleaner
                  ? null
                  : const DomlyClientBottomNav(currentIndex: 0),
              child: ColoredBox(
                color: _background,
                child: SafeArea(
                  bottom: false,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 390),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(15, 16, 15, 120),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Material(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  elevation: 4,
                                  shadowColor:
                                      Colors.black.withValues(alpha: 0.12),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () => Navigator.maybePop(context),
                                    child: const SizedBox(
                                      width: 36,
                                      height: 36,
                                      child: Icon(
                                        Icons.arrow_back,
                                        color: _orange,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: _foreground,
                                          fontSize: 20,
                                          fontWeight: FontWeight.w700,
                                          height: 27 / 20,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        widget.subtitle,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: _muted,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          height: 16 / 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                Expanded(
                                  child: _VideoMetricCard(
                                    label: 'Видео',
                                    value: '${videos.length}',
                                  ),
                                ),
                                const SizedBox(width: 29),
                                Expanded(
                                  child: _VideoMetricCard(
                                    label: 'Категории',
                                    value: '${categories.length - 1}',
                                  ),
                                ),
                                const SizedBox(width: 29),
                                Expanded(
                                  child: _VideoMetricCard(
                                    label: 'Просмотрено',
                                    value: '${viewedIds.length}',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 19),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: categories.map((category) {
                                  final selected =
                                      category == _selectedCategory;
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 33),
                                    child: _VideoFilterChip(
                                      label: category,
                                      selected: selected,
                                      onTap: () => setState(
                                        () => _selectedCategory = category,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                            const SizedBox(height: 24),
                            if (filteredVideos.isEmpty)
                              const _VideoEmptyCard()
                            else
                              ...filteredVideos.map((video) {
                                final isViewed =
                                    viewedIds.contains(video['id']);
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 22),
                                  child: _VideoTrainingCard(
                                    video: video,
                                    viewed: isViewed,
                                    audienceType: widget.audienceType,
                                  ),
                                );
                              }),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _VideoMetricCard extends StatelessWidget {
  const _VideoMetricCard({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _VideoHubScreenState._orange),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _VideoHubScreenState._muted,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 18 / 13,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: _VideoHubScreenState._foreground,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 22 / 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoFilterChip extends StatelessWidget {
  const _VideoFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? _VideoHubScreenState._green
          : _VideoHubScreenState._chipSoft,
      borderRadius: BorderRadius.circular(999),
      elevation: selected ? 4 : 0,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: selected
                ? null
                : Border.all(color: Colors.black.withValues(alpha: 0.13)),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : _VideoHubScreenState._green,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoTrainingCard extends StatelessWidget {
  const _VideoTrainingCard({
    required this.video,
    required this.viewed,
    required this.audienceType,
  });

  final Map<String, dynamic> video;
  final bool viewed;
  final String audienceType;

  @override
  Widget build(BuildContext context) {
    final duration = (video['duration'] ?? video['durationText'] ?? '5 мин')
        .toString()
        .trim();
    final popularity = viewed ? 'Просмотрено' : 'Популярно';
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => Navigator.pushNamed(
          context,
          '/video/detail',
          arguments: {
            'videoId': video['id'],
            'audienceType': audienceType,
          },
        ),
        child: Container(
          height: 116,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _VideoHubScreenState._border),
          ),
          child: Row(
            children: [
              Container(
                width: 112,
                height: 80,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _VideoHubScreenState._thumb,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Text(
                  '▶',
                  style: TextStyle(
                    color: _VideoHubScreenState._foreground,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 19),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (video['title'] ?? 'Видео').toString(),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _VideoHubScreenState._foreground,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 18 / 16,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${duration.isEmpty ? '5 мин' : duration} · $popularity',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _VideoHubScreenState._muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoEmptyCard extends StatelessWidget {
  const _VideoEmptyCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 116,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _VideoHubScreenState._border),
      ),
      child: Text(
        'Видео пока нет'.tr(),
        style: TextStyle(
          color: _VideoHubScreenState._foreground,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
