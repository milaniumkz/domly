import '../../utils/backend_compat.dart';
import 'package:flutter/material.dart';

import '../../app/debug_session.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_data_service.dart';
import '../../services/photo_upload_service.dart';
import '../../ui/domly_ui.dart';
import '../../localization/translation_controller.dart';

class ComplaintScreen extends StatefulWidget {
  const ComplaintScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<ComplaintScreen> createState() => _ComplaintScreenState();
}

class _ComplaintScreenState extends State<ComplaintScreen> {
  final _controller = TextEditingController();
  final _data = FirestoreDataService.instance;
  final _photoService = PhotoUploadService();
  static const int _maxPhotos = 5;

  final List<String> _photoUrls = <String>[];
  bool _loading = false;
  bool _uploadingPhotos = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final isDebugCustomer = DebugSession.uid == 'customer_demo';
    final shouldAutofill =
        isDebugCustomer && DebugSession.value('debug_autofill') == 'complaint';
    if (!shouldAutofill) {
      return;
    }
    _controller.text = 'Нужно проверить качество уборки, остались замечания.';
    final shouldAutoSubmit =
        DebugSession.value('debug_autosubmit') == 'complaint';
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
        child: Stack(
          children: [
            Column(
              children: [
                DomlyHeader(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
                  child: StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _data.complaintsStream(),
                    builder: (context, snapshot) {
                      final complaints =
                          snapshot.data ?? const <Map<String, dynamic>>[];
                      final hasExistingComplaint = complaints.any(
                        (item) =>
                            (item['orderId'] ?? '').toString() ==
                                widget.orderId &&
                            (item['customerId'] ?? '').toString() ==
                                _data.currentUserId,
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
                                  'Жалоба по заказу'.tr(),
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  hasExistingComplaint
                                      ? 'Обращение сохранено. Здесь показан его текущий статус.'
                                      : 'Опишите проблему и приложите до 5 фото одним выбором',
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
                    stream: _data.complaintsStream(),
                    builder: (context, snapshot) {
                      final complaints =
                          snapshot.data ?? const <Map<String, dynamic>>[];
                      final currentComplaint = complaints
                          .where(
                            (item) =>
                                (item['orderId'] ?? '').toString() ==
                                widget.orderId,
                          )
                          .cast<Map<String, dynamic>?>()
                          .firstWhere(
                            (item) =>
                                item != null &&
                                (item['customerId'] ?? '').toString() ==
                                    _data.currentUserId,
                            orElse: () => null,
                          );
                      final hasExistingComplaint = currentComplaint != null;
                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                        child: Column(
                          children: [
                            if (currentComplaint != null) ...[
                              _ComplaintStatusCard(complaint: currentComplaint),
                              const SizedBox(height: 14),
                              _ExistingComplaintCard(
                                complaint: currentComplaint,
                              ),
                              const SizedBox(height: 14),
                            ],
                            if (!hasExistingComplaint) ...[
                              DomlyCard(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Опишите проблему'.tr(),
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: DomlyColors.foreground,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    TextField(
                                      controller: _controller,
                                      maxLines: 5,
                                      decoration: const InputDecoration(
                                        hintText:
                                            'Что произошло во время уборки',
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
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Фото'.tr(),
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              color: DomlyColors.foreground,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          '${_photoUrls.length}/$_maxPhotos',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: DomlyColors.muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    if (_photoUrls.isNotEmpty)
                                      Wrap(
                                        spacing: 10,
                                        runSpacing: 10,
                                        children: List.generate(_photoUrls.length, (
                                          index,
                                        ) {
                                          final url = _photoUrls[index];
                                          return Stack(
                                            children: [
                                              ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                                child: Image.network(
                                                  url,
                                                  height: 108,
                                                  width: 108,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, __, ___) =>
                                                      Container(
                                                        height: 108,
                                                        width: 108,
                                                        decoration: BoxDecoration(
                                                          color: DomlyColors
                                                              .backgroundSoft,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                16,
                                                              ),
                                                          border: Border.all(
                                                            color: DomlyColors
                                                                .border,
                                                          ),
                                                        ),
                                                        child: const Icon(
                                                          Icons.image_outlined,
                                                          color:
                                                              DomlyColors.muted,
                                                        ),
                                                      ),
                                                ),
                                              ),
                                              Positioned(
                                                top: 6,
                                                right: 6,
                                                child: GestureDetector(
                                                  onTap:
                                                      _loading ||
                                                          _uploadingPhotos
                                                      ? null
                                                      : () {
                                                          setState(
                                                            () => _photoUrls
                                                                .removeAt(
                                                                  index,
                                                                ),
                                                          );
                                                        },
                                                  child: Container(
                                                    width: 24,
                                                    height: 24,
                                                    decoration: BoxDecoration(
                                                      color: Colors.black
                                                          .withValues(
                                                            alpha: 0.65,
                                                          ),
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: const Icon(
                                                      Icons.close,
                                                      size: 14,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          );
                                        }),
                                      )
                                    else
                                      const DomlyEmptyStateCard(
                                        title: 'Фото не добавлены',
                                        subtitle:
                                            'Выберите до 5 фото сразу, чтобы показать проблему менеджеру.',
                                        icon: Icons.photo_library_outlined,
                                      ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: DomlySecondaryButton(
                                        label: _photoUrls.isEmpty
                                            ? 'Выбрать до 5 фото'
                                            : 'Добавить ещё фото',
                                        isLoading: _uploadingPhotos,
                                        onPressed:
                                            _photoUrls.length >= _maxPhotos ||
                                                _loading
                                            ? null
                                            : _pickPhotos,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _photoUrls.isEmpty
                                          ? 'После выбора фото сразу появятся здесь.'
                                          : 'Фото прикреплены к жалобе и будут отправлены вместе с текстом.',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: DomlyColors.muted,
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
                      stream: _data.complaintsStream(),
                      builder: (context, snapshot) {
                        final complaints =
                            snapshot.data ?? const <Map<String, dynamic>>[];
                        final hasExistingComplaint = complaints.any(
                          (item) =>
                              (item['orderId'] ?? '').toString() ==
                                  widget.orderId &&
                              (item['customerId'] ?? '').toString() ==
                                  _data.currentUserId,
                        );
                        return DomlyStickyActionBar(
                          child: DomlyPrimaryButton(
                            label: hasExistingComplaint
                                ? 'Вернуться к заказам'
                                : _loading
                                ? 'Отправляем жалобу...'
                                : 'Отправить жалобу',
                            isLoading: _loading,
                            onPressed: hasExistingComplaint
                                ? () => Navigator.pushNamedAndRemoveUntil(
                                    context,
                                    '/client/orders',
                                    (route) => false,
                                    arguments: {'initialTab': 'history'},
                                  )
                                : _loading || _uploadingPhotos
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
            if (_loading)
              Positioned.fill(
                child: AbsorbPointer(
                  absorbing: true,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.22),
                    ),
                    child: Center(
                      child: DomlyCard(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.6,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  DomlyColors.buttonPrimary,
                                ),
                              ),
                            ),
                            SizedBox(height: 12),
                            Text(
                              'Отправляем жалобу...'.tr(),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: DomlyColors.foreground,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Подождите, пожалуйста'.tr(),
                              style: TextStyle(
                                fontSize: 12,
                                color: DomlyColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickPhotos() async {
    if (_uploadingPhotos || _photoUrls.length >= _maxPhotos) {
      return;
    }
    setState(() => _uploadingPhotos = true);
    try {
      final remaining = _maxPhotos - _photoUrls.length;
      final urls = AuthService.hasTemporarySession
          ? List<String>.generate(
              remaining,
              (index) =>
                  'temp://complaints/${widget.orderId}/complaint_${DateTime.now().millisecondsSinceEpoch}_$index.jpg',
            )
          : await _photoService.pickMultipleAndUpload(
              folder: 'complaints/${widget.orderId}',
              filePrefix: 'complaint',
              limit: remaining,
            );
      if (!mounted) {
        return;
      }
      setState(() {
        for (final url in urls) {
          if (_photoUrls.length >= _maxPhotos) {
            break;
          }
          if (url.trim().isNotEmpty) {
            _photoUrls.add(url);
          }
        }
      });
      if (urls.isNotEmpty) {
        showDomlySnackBar(
          context,
          title: 'Фото прикреплены',
          subtitle: 'Добавлено ${urls.length} фото к жалобе.',
          type: DomlySnackBarType.info,
        );
      }
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
    } finally {
      if (mounted) {
        setState(() => _uploadingPhotos = false);
      }
    }
  }

  Future<void> _submit() async {
    if (_controller.text.trim().isEmpty) {
      showDomlySnackBar(
        context,
        title: 'Опишите проблему',
        subtitle: 'Без описания жалобу отправить нельзя.',
        type: DomlySnackBarType.error,
      );
      return;
    }
    setState(() => _loading = true);
    try {
      await _data.submitComplaint(
        orderId: widget.orderId,
        customerId: _data.currentUserId,
        text: _controller.text.trim(),
        photoUrl: _photoUrls.isNotEmpty ? _photoUrls.first : null,
        photoUrls: _photoUrls,
      );
      if (!mounted) {
        return;
      }
      showDomlySnackBar(
        context,
        title: 'Жалоба отправлена',
        subtitle: 'Мы передадим её менеджеру и проверим заказ.',
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
        title: 'Не удалось отправить жалобу',
        subtitle: '$error',
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
}

class _ComplaintStatusCard extends StatelessWidget {
  const _ComplaintStatusCard({required this.complaint});

  final Map<String, dynamic> complaint;

  @override
  Widget build(BuildContext context) {
    final status = (complaint['status'] ?? 'open').toString().toLowerCase();
    final resolution = (complaint['resolution'] ?? '').toString().trim();
    final compensationAmount = _readInt(complaint['compensationAmount']);
    final createdAt = _formatSubmittedAt(complaint['createdAt']);
    final resolvedAt = _formatSubmittedAt(complaint['resolvedAt']);
    final statusDescription = _statusDescription(status);
    return DomlyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Статус обращения'.tr(),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: DomlyColors.foreground,
                  ),
                ),
              ),
              _StatusChip(
                label: _statusLabel(status),
                color: _statusColor(status),
              ),
            ],
          ),
          if (statusDescription.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              statusDescription,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: DomlyColors.foreground,
              ),
            ),
          ],
          if (resolution.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              resolution,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: DomlyColors.foreground,
              ),
            ),
          ],
          if (createdAt != null && status == 'open') ...[
            const SizedBox(height: 6),
            Text(
              'На рассмотрении с $createdAt'.tr(),
              style: const TextStyle(fontSize: 12, color: DomlyColors.muted),
            ),
          ],
          if (resolvedAt != null && status != 'open') ...[
            const SizedBox(height: 6),
            Text(
              'Решение от $resolvedAt'.tr(),
              style: const TextStyle(fontSize: 12, color: DomlyColors.muted),
            ),
          ],
          if (compensationAmount > 0) ...[
            const SizedBox(height: 6),
            Text(
              'Компенсация: $compensationAmount ₸'.tr(),
              style: const TextStyle(fontSize: 13, color: DomlyColors.muted),
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

  static String _statusLabel(String status) {
    switch (status) {
      case 'resolved':
        return 'Закрыта';
      case 'compensated':
        return 'Компенсация';
      case 'refund':
        return 'Возврат';
      default:
        return 'Открыта';
    }
  }

  static String _statusDescription(String status) {
    switch (status) {
      case 'resolved':
        return 'Обращение проверено и закрыто.';
      case 'compensated':
        return 'По обращению назначена компенсация.';
      case 'refund':
        return 'По обращению оформлен возврат.';
      default:
        return 'Обращение передано менеджеру и находится в работе.';
    }
  }

  static Color _statusColor(String status) {
    switch (status) {
      case 'resolved':
        return const Color(0xFF4F46E5);
      case 'compensated':
        return const Color(0xFF0F9D58);
      case 'refund':
        return const Color(0xFFB45309);
      default:
        return const Color(0xFFD97706);
    }
  }
}

class _ExistingComplaintCard extends StatelessWidget {
  const _ExistingComplaintCard({required this.complaint});

  final Map<String, dynamic> complaint;

  @override
  Widget build(BuildContext context) {
    final text = (complaint['text'] ?? '').toString().trim();
    final submittedAt = _formatSubmittedAt(complaint['createdAt']);
    final photoUrls = ((complaint['photoUrls'] as List?) ?? const [])
        .whereType<String>()
        .where((item) => item.trim().isNotEmpty)
        .toList();
    final photoUrl = (complaint['photoUrl'] ?? '').toString().trim();
    if (photoUrls.isEmpty && photoUrl.isNotEmpty) {
      photoUrls.add(photoUrl);
    }
    return DomlyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ваше обращение'.tr(),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: DomlyColors.foreground,
            ),
          ),
          if (submittedAt != null) ...[
            const SizedBox(height: 6),
            Text(
              'Отправлено $submittedAt'.tr(),
              style: const TextStyle(fontSize: 12, color: DomlyColors.muted),
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
          if (photoUrls.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: photoUrls
                  .map(
                    (url) => ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.network(
                        url,
                        height: 108,
                        width: 108,
                        fit: BoxFit.cover,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Если потребуется уточнение, менеджер свяжется с вами отдельно.'
                .tr(),
            style: TextStyle(fontSize: 12, color: DomlyColors.muted),
          ),
        ],
      ),
    );
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
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
