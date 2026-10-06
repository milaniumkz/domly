import '../../utils/backend_compat.dart';
import 'package:flutter/material.dart';

import '../../app/debug_session.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_data_service.dart';
import '../../services/photo_upload_service.dart';
import '../../ui/domly_ui.dart';
import '../../localization/translation_controller.dart';

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  static const List<String> _positiveTraits = [
    'Вежливая',
    'Опрятная',
    'Чистоплотная',
    'Пунктуальная',
    'Аккуратная',
  ];
  static const List<String> _negativeTraits = [
    'Грубая',
    'Непунктуальная',
    'Невнимательная',
    'Медлительная',
    'Неаккуратная',
  ];

  final _data = FirestoreDataService.instance;
  final _photoService = PhotoUploadService();
  final _textController = TextEditingController();
  final Set<String> _selectedTraits = <String>{};
  int _rating = 5;
  bool _loading = false;
  String? _photoUrl;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final isDebugCustomer = DebugSession.uid == 'customer_demo';
    final shouldAutofill =
        isDebugCustomer && DebugSession.value('debug_autofill') == 'review';
    if (!shouldAutofill) {
      return;
    }
    _selectedTraits
      ..clear()
      ..addAll(_positiveTraits.take(2));
    _textController.text = 'Все прошло хорошо, уборка была аккуратной.';
    final shouldAutoSubmit = DebugSession.value('debug_autosubmit') == 'review';
    if (shouldAutoSubmit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_loading) {
          _submit();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DomlyShell(
      child: SafeArea(
        child: Column(
          children: [
            DomlyHeader(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: _data.reviewsStream(),
                builder: (context, snapshot) {
                  final reviews =
                      snapshot.data ?? const <Map<String, dynamic>>[];
                  final hasExistingReview = reviews.any(
                    (item) =>
                        (item['orderId'] ?? item['id'] ?? '').toString() ==
                        widget.orderId,
                  );
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      domlyTopIconButton(
                        icon: Icons.arrow_back,
                        onPressed: _closeScreen,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Оценка уборки'.tr(),
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              hasExistingReview
                                  ? 'Ваш отзыв сохранен и уже учтен в системе.'
                                  : 'Оцените уборщицу и оставьте отзыв о визите',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xCCFFFFFF),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: _data.reviewsStream(),
                builder: (context, snapshot) {
                  final reviews =
                      snapshot.data ?? const <Map<String, dynamic>>[];
                  final existingReview = reviews
                      .where(
                        (item) =>
                            (item['orderId'] ?? item['id'] ?? '').toString() ==
                            widget.orderId,
                      )
                      .cast<Map<String, dynamic>?>()
                      .firstWhere((item) => item != null, orElse: () => null);
                  final hasExistingReview = existingReview != null;
                  final traitOptions = _rating < 3
                      ? _negativeTraits
                      : _positiveTraits;
                  final traitsTitle = _rating < 3
                      ? 'Что не понравилось'
                      : 'Что понравилось';
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (existingReview != null) ...[
                          _ExistingReviewCard(review: existingReview),
                          const SizedBox(height: 14),
                        ],
                        if (!hasExistingReview) ...[
                          DomlyCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Оцените качество уборки'.tr(),
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: DomlyColors.foreground,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: List.generate(5, (index) {
                                    final value = index + 1;
                                    return IconButton(
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () => setState(() {
                                        _rating = value;
                                        _selectedTraits.removeWhere(
                                          (item) => !_currentTraitOptions
                                              .contains(item),
                                        );
                                      }),
                                      icon: Icon(
                                        value <= _rating
                                            ? Icons.star
                                            : Icons.star_border,
                                        color: const Color(0xFFFFA500),
                                        size: 32,
                                      ),
                                    );
                                  }),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _rating < 3
                                      ? 'Если оценка ниже 3 звезд, отметьте причины.'
                                      : 'Отметьте сильные стороны уборщицы.',
                                  style: const TextStyle(
                                    color: DomlyColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          DomlyCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  traitsTitle,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: DomlyColors.foreground,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: traitOptions.map((trait) {
                                    final selected = _selectedTraits.contains(
                                      trait,
                                    );
                                    return FilterChip(
                                      label: Text(
                                        trait,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                      selected: selected,
                                      onSelected: (_) => setState(() {
                                        if (selected) {
                                          _selectedTraits.remove(trait);
                                        } else {
                                          _selectedTraits.add(trait);
                                        }
                                      }),
                                    );
                                  }).toList(),
                                ),
                                const SizedBox(height: 14),
                                TextField(
                                  controller: _textController,
                                  maxLines: 4,
                                  decoration: const InputDecoration(
                                    hintText:
                                        'Что понравилось, что нужно улучшить',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          DomlyCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Фото к отзыву'.tr(),
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: DomlyColors.foreground,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                if (_photoUrl != null)
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(18),
                                    decoration: BoxDecoration(
                                      color: DomlyColors.backgroundSoft,
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: DomlyColors.border,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.check_circle,
                                          color: DomlyColors.primary,
                                        ),
                                        SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Фото прикреплено'.tr(),
                                                style: TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w700,
                                                  color: DomlyColors.foreground,
                                                ),
                                              ),
                                              SizedBox(height: 2),
                                              Text(
                                                'Изображение будет отправлено вместе с отзывом.'
                                                    .tr(),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: DomlyColors.muted,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  const DomlyEmptyStateCard(
                                    title: 'Фото не добавлено',
                                    subtitle:
                                        'Фото к отзыву не обязательно, но поможет точнее описать впечатление.',
                                    icon: Icons.add_a_photo_outlined,
                                  ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: DomlySecondaryButton(
                                    label: _photoUrl == null
                                        ? 'Прикрепить фото'
                                        : 'Заменить фото',
                                    onPressed: _attachPhoto,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 96),
                      ],
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _data.reviewsStream(),
                  builder: (context, snapshot) {
                    final reviews =
                        snapshot.data ?? const <Map<String, dynamic>>[];
                    final hasExistingReview = reviews.any(
                      (item) =>
                          (item['orderId'] ?? item['id'] ?? '').toString() ==
                          widget.orderId,
                    );
                    return DomlyStickyActionBar(
                      child: DomlyPrimaryButton(
                        label: hasExistingReview
                            ? 'Вернуться к заказам'
                            : _loading
                            ? 'Отправляем...'
                            : 'Отправить отзыв',
                        onPressed: hasExistingReview
                            ? () => Navigator.pushNamedAndRemoveUntil(
                                context,
                                '/client/orders',
                                (route) => false,
                                arguments: {'initialTab': 'history'},
                              )
                            : _loading
                            ? null
                            : _submit,
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _attachPhoto() async {
    try {
      final url = AuthService.hasTemporarySession
          ? 'temp://reviews/${widget.orderId}/review_${DateTime.now().millisecondsSinceEpoch}.jpg'
          : await _photoService.pickAndUpload(
              folder: 'reviews/${widget.orderId}',
              filePrefix: 'review',
            );
      if (!mounted || url == null) {
        return;
      }
      setState(() => _photoUrl = url);
      showDomlySnackBar(
        context,
        title: 'Фото прикреплено',
        subtitle: 'Изображение добавлено к отзыву.',
        type: DomlySnackBarType.info,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      showDomlySnackBar(
        context,
        title: 'Не удалось загрузить фото',
        subtitle: error.toString(),
        type: DomlySnackBarType.error,
      );
    }
  }

  Future<void> _submit() async {
    if (_selectedTraits.isEmpty && _textController.text.trim().isEmpty) {
      showDomlySnackBar(
        context,
        title: 'Добавьте отзыв',
        subtitle: 'Отметьте качества или оставьте комментарий.',
        type: DomlySnackBarType.error,
      );
      return;
    }
    setState(() => _loading = true);
    try {
      await _data.submitReview(
        orderId: widget.orderId,
        rating: _rating,
        text: _textController.text.trim(),
        positiveTraits: _rating >= 3
            ? _selectedTraits.toList(growable: false)
            : const [],
        negativeTraits: _rating < 3
            ? _selectedTraits.toList(growable: false)
            : const [],
        photoUrl: _photoUrl,
      );
      if (!mounted) {
        return;
      }
      showDomlySnackBar(
        context,
        title: 'Отзыв отправлен',
        subtitle: 'Спасибо, ваша оценка сохранена.',
        type: DomlySnackBarType.success,
      );
      final shouldReturnToHistory =
          DebugSession.enabled &&
          DebugSession.value('debug_order_id') == widget.orderId;
      if (shouldReturnToHistory) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/client/orders',
          (route) => false,
          arguments: {'initialTab': 'history'},
        );
        return;
      }
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) {
        return;
      }
      showDomlySnackBar(
        context,
        title: 'Не удалось отправить отзыв',
        subtitle: error.toString(),
        type: DomlySnackBarType.error,
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _closeScreen() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    navigator.pushNamedAndRemoveUntil(
      '/client/orders',
      (route) => false,
      arguments: {'initialTab': 'history'},
    );
  }

  List<String> get _currentTraitOptions =>
      _rating < 3 ? _negativeTraits : _positiveTraits;
}

class _ExistingReviewCard extends StatelessWidget {
  const _ExistingReviewCard({required this.review});

  final Map<String, dynamic> review;

  @override
  Widget build(BuildContext context) {
    final rating = _readInt(review['rating']);
    final submittedAt = _formatSubmittedAt(review['createdAt']);
    final summary = _ratingSummary(rating);
    final positive = ((review['positiveTraits'] as List?) ?? const [])
        .whereType<String>()
        .toList();
    final negative = ((review['negativeTraits'] as List?) ?? const [])
        .whereType<String>()
        .toList();
    final traits = positive.isNotEmpty ? positive : negative;
    final photoUrl = (review['photoUrl'] ?? '').toString().trim();
    final text = (review['text'] ?? '').toString().trim();
    return DomlyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Ваш отзыв сохранен'.tr(),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: DomlyColors.foreground,
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                      5,
                      (index) => Icon(
                        index < rating ? Icons.star : Icons.star_border,
                        color: const Color(0xFFFFA500),
                        size: 18,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$rating из 5'.tr(),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: DomlyColors.muted,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (submittedAt != null) ...[
            const SizedBox(height: 6),
            Text(
              'Отправлено $submittedAt'.tr(),
              style: const TextStyle(fontSize: 12, color: DomlyColors.muted),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            summary,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: DomlyColors.foreground,
            ),
          ),
          if (traits.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: traits
                  .map(
                    (trait) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F6EF),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        trait,
                        style: const TextStyle(
                          fontSize: 12,
                          color: DomlyColors.foreground,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          if (text.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                color: DomlyColors.foreground,
              ),
            ),
          ],
          if (photoUrl.isNotEmpty) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                photoUrl,
                height: 140,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String? _formatSubmittedAt(dynamic value) {
    final date = _readDateTime(value);
    if (date == null) {
      return null;
    }
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day.$month.$year в $hour:$minute';
  }

  static DateTime? _readDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static String _ratingSummary(int rating) {
    if (rating <= 2) {
      return 'Оценка передана в контроль качества.';
    }
    if (rating == 3) {
      return 'Спасибо за отзыв. Мы учтем ваши замечания.';
    }
    return 'Спасибо, ваша высокая оценка сохранена.';
  }
}
