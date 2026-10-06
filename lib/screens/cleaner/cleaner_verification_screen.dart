import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/firestore_data_service.dart';
import '../../services/verification_upload_service.dart';
import '../../ui/domly_ui.dart';
import '../../localization/translation_controller.dart';

class CleanerVerificationScreen extends StatefulWidget {
  const CleanerVerificationScreen({super.key});

  @override
  State<CleanerVerificationScreen> createState() =>
      _CleanerVerificationScreenState();
}

class _CleanerVerificationScreenState extends State<CleanerVerificationScreen> {
  final _data = FirestoreDataService.instance;
  final _uploads = VerificationUploadService();
  final _expiresController = TextEditingController();

  final Map<String, String?> _files = {
    'selfieUrl': null,
    'selfieWithIdUrl': null,
    'idDocumentUrl': null,
    'policeClearanceUrl': null,
    'psychDispenserUrl': null,
    'phthisiatricianUrl': null,
    'residenceProofUrl': null,
  };

  bool _submitting = false;

  @override
  void dispose() {
    _expiresController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: _data.cleanerVerificationStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const DomlyShell(
            bottomNavigationBar: DomlyCleanerBottomNav(currentIndex: 4),
            child: SafeArea(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: DomlyEmptyStateCard(
                    title: 'Не удалось загрузить верификацию',
                    subtitle: 'Обновите экран и попробуйте снова.',
                    icon: Icons.error_outline,
                  ),
                ),
              ),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const DomlyShell(
            bottomNavigationBar: DomlyCleanerBottomNav(currentIndex: 4),
            child: SafeArea(
              child: Center(
                child: CircularProgressIndicator(
                  valueColor:
                      AlwaysStoppedAnimation<Color>(DomlyColors.buttonPrimary),
                ),
              ),
            ),
          );
        }
        final verification = snapshot.data ?? <String, dynamic>{};
        for (final key in _files.keys) {
          _files[key] ??= verification[key]?.toString();
        }

        final status =
            (verification['status'] ?? 'pending').toString().toLowerCase();
        final isApproved = status == 'approved';
        final isRejected = status == 'rejected';

        return DomlyShell(
          bottomNavigationBar: const DomlyCleanerBottomNav(currentIndex: 4),
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DomlyHeader(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
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
                                    'Верификация исполнителя'.tr(),
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Загрузите все обязательные документы для допуска к заказам'
                                        .tr(),
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
                        padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DomlyStatusChip(
                              label: _statusText(status),
                              color: isApproved
                                  ? DomlyColors.primary
                                  : isRejected
                                      ? DomlyColors.danger
                                      : const Color(0xFFFF9800),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Без подтвержденной верификации заказы не назначаются.'
                                  .tr(),
                              style: TextStyle(color: DomlyColors.muted),
                            ),
                            if ((verification['rejectionReason'] ?? '')
                                .toString()
                                .isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Причина отказа: ${verification['rejectionReason']}',
                                  style: const TextStyle(
                                    color: DomlyColors.danger,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 2),
                            _stepTile('Шаг 1: Селфи', 'selfieUrl', 'selfie'),
                            _stepTile(
                              'Шаг 2: Фото с удостоверением',
                              'selfieWithIdUrl',
                              'selfie-with-id',
                            ),
                            _stepTile(
                              'Шаг 3: Удостоверение / ID',
                              'idDocumentUrl',
                              'id-document',
                            ),
                            _stepTile(
                              'Шаг 4: Справка о несудимости',
                              'policeClearanceUrl',
                              'police-clearance',
                            ),
                            _stepTile(
                              'Шаг 5: Справка с психдиспансера',
                              'psychDispenserUrl',
                              'psych-dispenser',
                            ),
                            _stepTile(
                              'Шаг 6: Справка фтизиатрия',
                              'phthisiatricianUrl',
                              'phthisiatrician',
                            ),
                            _stepTile(
                              'Шаг 7: Прописка с eGov',
                              'residenceProofUrl',
                              'residence-proof',
                            ),
                            const SizedBox(height: 2),
                            TextField(
                              controller: _expiresController,
                              decoration: const InputDecoration(
                                labelText:
                                    'Срок действия документов (YYYY-MM-DD)',
                              ),
                            ),
                            const SizedBox(height: 2),
                            DomlyPrimaryButton(
                              label: isApproved
                                  ? 'Верификация подтверждена'
                                  : isRejected
                                      ? 'Отправить повторно'
                                      : 'Отправить на проверку',
                              onPressed:
                                  _submitting || isApproved ? null : _submit,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _stepTile(String title, String key, String type) {
    final uploaded = (_files[key] ?? '').isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: DomlyCard(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(uploaded ? 'Файл загружен' : 'Файл не загружен'),
                ],
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 80,
              child: DomlySecondaryButton(
                label: uploaded ? 'Заменить' : 'Загрузить',
                onPressed: () => _pickFile(key, type),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFile(String key, String type) async {
    try {
      final cleanerId = _data.currentUserId;
      final url = AuthService.hasTemporarySession
          ? 'temp://cleaner_verification/$cleanerId/${type}_${DateTime.now().millisecondsSinceEpoch}.jpg'
          : await _uploads.pickAndUpload(cleanerId: cleanerId, type: type);
      if (url == null) {
        return;
      }
      setState(() {
        _files[key] = url;
      });
    } catch (e) {
      if (!mounted) return;
      showDomlySnackBar(
        context,
        title: 'Не удалось загрузить файл',
        subtitle: '$e',
        type: DomlySnackBarType.error,
      );
    }
  }

  Future<void> _submit() async {
    final missing = _files.entries
        .where((entry) => (entry.value ?? '').isEmpty)
        .map((entry) => entry.key)
        .toList();
    if (missing.isNotEmpty) {
      showDomlySnackBar(
        context,
        title: 'Не хватает файлов',
        subtitle: 'Загрузите все обязательные документы.',
        type: DomlySnackBarType.error,
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await _data.submitCleanerVerification({
        ..._files,
        'expiresAt': _expiresController.text.trim().isEmpty
            ? null
            : _expiresController.text.trim(),
      });
      if (!mounted) return;
      showDomlySnackBar(
        context,
        title: 'Документы отправлены',
        subtitle: 'Заявка передана на проверку.',
        type: DomlySnackBarType.success,
      );
    } catch (e) {
      if (!mounted) return;
      showDomlySnackBar(
        context,
        title: 'Не удалось отправить документы',
        subtitle: '$e',
        type: DomlySnackBarType.error,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _statusText(String status) {
    switch (status) {
      case 'approved':
        return 'Подтверждена';
      case 'rejected':
        return 'Отклонена';
      default:
        return 'На проверке';
    }
  }
}
