import 'package:flutter/material.dart';

import '../../app/debug_session.dart';
import '../../localization/translation_controller.dart';
import '../../services/auth_service.dart';
import '../../services/backend_api_service.dart';
import '../../services/firestore_data_service.dart';
import '../../services/photo_upload_service.dart';
import '../../ui/domly_ui.dart';
import '../../utils/backend_compat.dart';

class PhotoReportScreen extends StatefulWidget {
  const PhotoReportScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<PhotoReportScreen> createState() => _PhotoReportScreenState();
}

class _PhotoReportScreenState extends State<PhotoReportScreen> {
  final _photoService = PhotoUploadService();
  final _data = FirestoreDataService.instance;
  final List<String> _urls = [];

  bool _loading = false;
  bool _uploadingPhotos = false;
  String? _resolvedOrderId;

  @override
  void initState() {
    super.initState();
    final isDebugCleaner = DebugSession.uid == 'cleaner_demo';
    final shouldAutofill =
        isDebugCleaner && DebugSession.value('debug_autofill') == 'photos';
    if (!shouldAutofill) {
      return;
    }
    final baseSeed = widget.orderId.hashCode.abs();
    _urls.addAll(
      List.generate(
        3,
        (index) => 'https://picsum.photos/seed/${baseSeed}_$index/1200/900',
      ),
    );
    final shouldAutoSubmit = DebugSession.value('debug_autosubmit') == 'report';
    if (isDebugCleaner && shouldAutoSubmit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_loading) {
          _submit();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final initialOrderId = widget.orderId.trim();
    if (initialOrderId.isEmpty && _resolvedOrderId == null) {
      return StreamBuilder<List<Map<String, dynamic>>>(
        stream: _data.cleanerScheduleSlotsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
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
          final active = (snapshot.data ?? const <Map<String, dynamic>>[])
              .where(
                (slot) =>
                    (slot['status'] ?? '').toString().toLowerCase() ==
                    'in_progress',
              )
              .toList();
          active.sort((a, b) => _dateValue(b).compareTo(_dateValue(a)));
          if (active.isNotEmpty) {
            final id = _reportTargetId(active.first);
            if (id.isNotEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() => _resolvedOrderId = id);
                }
              });
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
          }
          return DomlyShell(
            child: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const DomlyEmptyStateCard(
                        title: 'Нет активной уборки',
                        subtitle:
                            'Сначала нажмите "Начать" у нужного заказа, затем добавьте фотоотчет.',
                        icon: Icons.photo_camera_outlined,
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: DomlyPrimaryButton(
                          label: 'Открыть заказы',
                          onPressed: () => Navigator.pushNamedAndRemoveUntil(
                            context,
                            '/cleaner/orders',
                            (route) => false,
                          ),
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
    return DomlyShell(
      child: SafeArea(
        child: Column(
          children: [
            DomlyHeader(
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
                          'Фотоотчет до/после'.tr(),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Загрузите 3–5 фото после уборки'.tr(),
                          style: const TextStyle(
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
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DomlyCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Загружено: {count}/5'.tr(
                              params: {'count': _urls.length.toString()},
                            ),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: DomlyColors.muted,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_urls.isEmpty)
                            const DomlyEmptyStateCard(
                              title: 'Фото пока не добавлены',
                              subtitle:
                                  'Добавьте 3–5 фотографий результата уборки, чтобы отправить отчет.',
                              icon: Icons.photo_library_outlined,
                            )
                          else
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _urls.length,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                                childAspectRatio: 1,
                              ),
                              itemBuilder: (context, index) {
                                return Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: SizedBox.expand(
                                        child: Image.network(
                                          _urls[index],
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: InkWell(
                                        onTap: () {
                                          setState(() {
                                            _urls.removeAt(index);
                                          });
                                        },
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(
                                              alpha: 0.6,
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
                              },
                            ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: DomlySecondaryButton(
                              label: _uploadingPhotos
                                  ? 'Загружаем фото...'.tr()
                                  : 'Добавить до 5 фото'.tr(),
                              onPressed: (_urls.length >= 5 ||
                                      _uploadingPhotos ||
                                      _loading)
                                  ? null
                                  : _addPhotos,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 96),
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: DomlyStickyActionBar(
                  child: DomlyPrimaryButton(
                    label: _loading
                        ? 'Отправляем...'.tr()
                        : 'Отправить отчет'.tr(),
                    onPressed:
                        (_urls.length < 3 || _loading || _uploadingPhotos)
                            ? null
                            : _submit,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addPhotos() async {
    final orderId = _currentOrderId();
    if (orderId.isEmpty) {
      showDomlySnackBar(
        context,
        title: 'Не выбран заказ',
        subtitle: 'Откройте фотоотчет из активной уборки.',
        type: DomlySnackBarType.error,
      );
      return;
    }
    final remaining = 5 - _urls.length;
    if (remaining <= 0 || _uploadingPhotos) {
      return;
    }
    setState(() => _uploadingPhotos = true);
    try {
      final urls = AuthService.hasTemporarySession
          ? List<String>.generate(
              remaining,
              (index) =>
                  'temp://photo_reports/$orderId/report_${DateTime.now().millisecondsSinceEpoch}_$index.jpg',
            )
          : await _photoService.pickMultipleAndUpload(
              folder: 'photo_reports/$orderId',
              filePrefix: 'report',
              limit: remaining,
            );
      if (!mounted || urls.isEmpty) {
        return;
      }
      setState(() {
        _urls.addAll(urls.take(remaining));
      });
      showDomlySnackBar(
        context,
        title: urls.length == 1 ? 'Фото добавлено' : 'Фото добавлены',
        subtitle: 'Загружено ${_urls.length} из 5.',
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
    } finally {
      if (mounted) {
        setState(() => _uploadingPhotos = false);
      }
    }
  }

  Future<void> _submit() async {
    final orderId = _currentOrderId();
    if (orderId.isEmpty) {
      showDomlySnackBar(
        context,
        title: 'Не выбран заказ',
        subtitle: 'Откройте фотоотчет из активной уборки.',
        type: DomlySnackBarType.error,
      );
      return;
    }
    if (_urls.length < 3) {
      showDomlySnackBar(
        context,
        title: 'Недостаточно фото',
        subtitle: 'Добавьте минимум 3 фото для отчёта.',
        type: DomlySnackBarType.error,
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final startConfirmed = await _isCleaningStartConfirmed(orderId);
      if (!startConfirmed) {
        if (mounted) {
          showDomlySnackBar(
            context,
            title: 'Клиент ещё не подтвердил старт',
            subtitle: 'Фотоотчёт можно отправить после ответа клиента "Да".',
            type: DomlySnackBarType.error,
          );
        }
        return;
      }
      await _data.uploadPhotoReport(
        orderId: orderId,
        cleanerId: _data.currentUserId,
        photoUrls: _urls,
      );
      await _data.advanceOrderStatus(orderId: orderId, toStatus: 'completed');
      if (!mounted) {
        return;
      }
      await _showCustomerRatingDialog(orderId);
      if (!mounted) {
        return;
      }
      showDomlySnackBar(
        context,
        title: 'Фотоотчёт отправлен',
        subtitle: 'Заказ завершён, оценка клиента сохранена.',
        type: DomlySnackBarType.success,
      );
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/cleaner/orders',
        (route) => false,
        arguments: {'initialTab': 'completed'},
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      showDomlySnackBar(
        context,
        title: 'Не удалось отправить фотоотчёт',
        subtitle: error.toString(),
        type: DomlySnackBarType.error,
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _showCustomerRatingDialog(String orderId) async {
    var rating = 5;
    final noteController = TextEditingController();
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          var submitting = false;
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: Text('Оцените клиента'.tr()),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Эта оценка будет влиять на рейтинг клиента.'.tr()),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 1; i <= 5; i++)
                          IconButton(
                            onPressed: submitting
                                ? null
                                : () => setDialogState(() => rating = i),
                            icon: Icon(
                              i <= rating ? Icons.star : Icons.star_border,
                              color: const Color(0xFFD06D45),
                              size: 32,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: noteController,
                      enabled: !submitting,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Комментарий',
                        hintText: 'Например: всё было готово к уборке',
                      ),
                    ),
                  ],
                ),
                actions: [
                  FilledButton(
                    onPressed: submitting
                        ? null
                        : () async {
                            setDialogState(() => submitting = true);
                            try {
                              await _data.submitCustomerReview(
                                orderId: orderId,
                                rating: rating,
                                text: noteController.text,
                              );
                              if (dialogContext.mounted) {
                                Navigator.pop(dialogContext);
                              }
                            } catch (error) {
                              if (!context.mounted) {
                                return;
                              }
                              setDialogState(() => submitting = false);
                              showDomlySnackBar(
                                context,
                                title: 'Не удалось сохранить оценку',
                                subtitle: '$error',
                                type: DomlySnackBarType.error,
                              );
                            }
                          },
                    child: submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text('Сохранить'.tr()),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      noteController.dispose();
    }
  }

  String _currentOrderId() {
    final resolved = (_resolvedOrderId ?? '').trim();
    if (resolved.isNotEmpty) {
      return resolved;
    }
    return widget.orderId.trim();
  }

  Future<bool> _isCleaningStartConfirmed(String orderId) async {
    final data = await BackendApiService.instance.getMap(
      '/orders/$orderId/photo-report',
    );
    return data['canSubmit'] == true;
  }

  String _reportTargetId(Map<String, dynamic> slot) {
    for (final key in ['scheduleSlotId', 'slotId', 'id']) {
      final value = (slot[key] ?? '').toString().trim();
      if (value.isNotEmpty && value != 'null') {
        return value;
      }
    }
    for (final key in ['sourceOrderId', 'customerOrderId', 'orderId', 'id']) {
      final value = (slot[key] ?? '').toString().trim();
      if (value.isNotEmpty && value != 'null') {
        return value;
      }
    }
    return '';
  }

  DateTime _dateValue(Map<String, dynamic> item) {
    final value = item['startedAt'] ??
        item['updatedAt'] ??
        item['scheduledFor'] ??
        item['date'];
    if (value is DateTime) {
      return value;
    }
    if (value is Timestamp) {
      return value.toDate();
    }
    return DateTime.tryParse(value?.toString() ?? '') ?? DateTime(1970);
  }
}
