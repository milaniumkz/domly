import '../../utils/backend_compat.dart';
import 'package:flutter/material.dart';

import '../../services/firestore_data_service.dart';
import '../../ui/domly_ui.dart';
import '../../localization/translation_controller.dart';

class CleanerRatingScreen extends StatefulWidget {
  const CleanerRatingScreen({super.key});

  @override
  State<CleanerRatingScreen> createState() => _CleanerRatingScreenState();
}

class _CleanerRatingScreenState extends State<CleanerRatingScreen> {
  final _data = FirestoreDataService.instance;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: _data.cleanerProfileStream(),
      builder: (context, profileSnap) {
        if (profileSnap.hasError) {
          return const DomlyShell(
            bottomNavigationBar: DomlyCleanerBottomNav(currentIndex: 4),
            child: SafeArea(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: DomlyEmptyStateCard(
                    title: 'Не удалось загрузить рейтинг',
                    subtitle: 'Обновите экран и попробуйте снова.',
                    icon: Icons.error_outline,
                  ),
                ),
              ),
            ),
          );
        }
        if (profileSnap.connectionState == ConnectionState.waiting &&
            !profileSnap.hasData) {
          return const DomlyShell(
            bottomNavigationBar: DomlyCleanerBottomNav(currentIndex: 4),
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
        final profile = profileSnap.data ?? const <String, dynamic>{};
        return DomlyShell(
          bottomNavigationBar: const DomlyCleanerBottomNav(currentIndex: 4),
          child: SafeArea(
            child: Column(
              children: [
                _header(),
                Expanded(
                  child: StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _data.reviewsForCleanerStream(),
                    builder: (context, reviewsSnap) {
                      if (reviewsSnap.hasError) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: DomlyEmptyStateCard(
                              title: 'Не удалось загрузить отзывы',
                              subtitle: 'Обновите экран и попробуйте снова.',
                              icon: Icons.error_outline,
                            ),
                          ),
                        );
                      }
                      if (reviewsSnap.connectionState ==
                              ConnectionState.waiting &&
                          !reviewsSnap.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              DomlyColors.buttonPrimary,
                            ),
                          ),
                        );
                      }
                      final reviews = reviewsSnap.data ?? [];
                      final stats = _computeStats(reviews, profile);
                      return ListView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                        children: [
                          _averageCard(stats),
                          const SizedBox(height: 14),
                          _breakdownCard(stats),
                          const SizedBox(height: 14),
                          _summaryCard(stats),
                          if (reviews.isEmpty) ...[
                            const SizedBox(height: 14),
                            const DomlyEmptyStateCard(
                              title: 'Отзывов пока нет',
                              subtitle:
                                  'Первые оценки клиентов появятся здесь.',
                              icon: Icons.star_outline,
                            ),
                          ] else ...[
                            const SizedBox(height: 20),
                            Text(
                              'Последние отзывы'.tr(),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: DomlyColors.muted,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Что пишут клиенты'.tr(),
                              style: TextStyle(
                                fontSize: 12,
                                color: DomlyColors.muted,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ...reviews
                                .take(10)
                                .map(
                                  (r) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _reviewCard(r),
                                  ),
                                ),
                          ],
                          const SizedBox(height: 24),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _header() {
    return DomlyHeader(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
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
                  'Рейтинг'.tr(),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Отзывы и средняя оценка'.tr(),
                  style: TextStyle(fontSize: 12, color: Color(0xCCFFFFFF)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _computeStats(
    List<Map<String, dynamic>> reviews,
    Map<String, dynamic> profile,
  ) {
    if ((profile['totalRatings'] ?? 0) is num &&
        ((profile['totalRatings'] ?? 0) as num).toInt() > 0) {
      return {
        'average': ((profile['currentRating'] ?? profile['rating'] ?? 0) as num)
            .toDouble(),
        'total': ((profile['totalRatings'] ?? 0) as num).toInt(),
        'count5': ((profile['rating5Count'] ?? 0) as num).toInt(),
        'count4': ((profile['rating4Count'] ?? 0) as num).toInt(),
        'count3': ((profile['rating3Count'] ?? 0) as num).toInt(),
        'count2': ((profile['rating2Count'] ?? 0) as num).toInt(),
        'count1': ((profile['rating1Count'] ?? 0) as num).toInt(),
        'good': ((profile['goodRatingsCount'] ?? 0) as num).toInt(),
        'bad': ((profile['badRatingsCount'] ?? 0) as num).toInt(),
      };
    }
    int count5 = 0, count4 = 0, count3 = 0, count2 = 0, count1 = 0;
    double sum = 0;
    for (final r in reviews) {
      final rating = ((r['rating'] ?? 0) as num).toInt();
      sum += rating;
      switch (rating) {
        case 5:
          count5++;
          break;
        case 4:
          count4++;
          break;
        case 3:
          count3++;
          break;
        case 2:
          count2++;
          break;
        case 1:
          count1++;
          break;
      }
    }
    final total = count5 + count4 + count3 + count2 + count1;
    final avg = total > 0 ? (sum / total) : 0.0;
    return {
      'average': avg,
      'total': total,
      'count5': count5,
      'count4': count4,
      'count3': count3,
      'count2': count2,
      'count1': count1,
      'good': count5 + count4,
      'bad': count3 + count2 + count1,
    };
  }

  Widget _averageCard(Map<String, dynamic> stats) {
    return DomlyCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text(
            'Средняя оценка'.tr(),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: DomlyColors.foreground,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            stats['average'].toStringAsFixed(1),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: DomlyColors.foreground,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final filled = i < stats['average'].round();
              return Icon(
                Icons.star,
                color: filled ? const Color(0xFFFFA500) : DomlyColors.border,
                size: 12,
              );
            }),
          ),
          const SizedBox(height: 8),
          Text(
            'по ${stats['total']} отзывам',
            style: const TextStyle(fontSize: 12, color: DomlyColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _breakdownCard(Map<String, dynamic> stats) {
    return DomlyCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Разбивка по оценкам'.tr(),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: DomlyColors.muted,
            ),
          ),
          const SizedBox(height: 12),
          for (final entry in [
            {'star': 5, 'count': stats['count5'] as int},
            {'star': 4, 'count': stats['count4'] as int},
            {'star': 3, 'count': stats['count3'] as int},
            {'star': 2, 'count': stats['count2'] as int},
            {'star': 1, 'count': stats['count1'] as int},
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    child: Text(
                      '${entry['star']}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.star, size: 14, color: Color(0xFFFFA500)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        minHeight: 6,
                        value: stats['total'] > 0
                            ? (entry['count'] as int) / stats['total']
                            : 0,
                        backgroundColor: DomlyColors.border,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFFFFA500),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 24,
                    child: Text(
                      '${entry['count']}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _summaryCard(Map<String, dynamic> stats) {
    return DomlyCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: _summaryMetric(
              '${stats['good']}',
              'Хороших оценок',
              const Color(0xFF22C55E),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _summaryMetric(
              '${stats['bad']}',
              'Плохих оценок',
              DomlyColors.danger,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryMetric(String value, String label, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: DomlyColors.muted),
        ),
      ],
    );
  }

  Widget _reviewCard(Map<String, dynamic> review) {
    final rating = ((review['rating'] ?? 0) as num).toInt();
    final text = (review['text'] ?? '').toString();
    final date = review['createdAt'];
    String dateStr = '';
    if (date is Timestamp) {
      final d = date.toDate();
      dateStr = '${d.day}.${d.month}.${d.year}';
    }
    final positiveTraits = ((review['positiveTraits'] ?? []) as List)
        .cast<String>();
    final negativeTraits = ((review['negativeTraits'] ?? []) as List)
        .cast<String>();
    final traits = positiveTraits.isNotEmpty ? positiveTraits : negativeTraits;

    return DomlyCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (i) {
                  return Icon(
                    Icons.star,
                    size: 16,
                    color: i < rating
                        ? const Color(0xFFFFA500)
                        : DomlyColors.border,
                  );
                }),
              ),
              if (dateStr.isNotEmpty) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    dateStr,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 12,
                      color: DomlyColors.muted,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (traits.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: traits
                  .map(
                    (t) => Chip(
                      label: Text(t, style: const TextStyle(fontSize: 11)),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      backgroundColor: positiveTraits.isNotEmpty
                          ? DomlyColors.backgroundSoft
                          : DomlyColors.danger.withValues(alpha: 0.1),
                    ),
                  )
                  .toList(),
            ),
          ],
          if (text.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(text, style: const TextStyle(fontSize: 15)),
          ],
        ],
      ),
    );
  }
}
