import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/app_config_service.dart';
import '../../services/auth_service.dart';
import '../../services/backend_api_service.dart';
import '../../services/firestore_data_service.dart';
import '../../ui/domly_ui.dart';
import '../../localization/translation_controller.dart';

class AreaConfirmationScreen extends StatefulWidget {
  const AreaConfirmationScreen({super.key});

  @override
  State<AreaConfirmationScreen> createState() => _AreaConfirmationScreenState();
}

class _AreaConfirmationScreenState extends State<AreaConfirmationScreen> {
  final _data = FirestoreDataService.instance;
  final _config = AppConfigService.instance;
  final _areaController = TextEditingController();
  final _imagePicker = ImagePicker();

  XFile? _selectedImage;
  bool _isSubmitting = false;
  bool _areaSeeded = false;
  bool _routeArgsApplied = false;
  bool _forceTechPlanPrompt = false;
  int? _initialAreaFromRoute;
  String? _error;
  String? _uploadWarning;

  @override
  void initState() {
    super.initState();
    _areaController.addListener(_onAreaChanged);
  }

  void _onAreaChanged() {
    if (!mounted) {
      return;
    }
    setState(() {
      if (_error == 'Введите площадь квартиры' ||
          _error == 'Введите корректное числовое значение площади') {
        _error = null;
      }
    });
  }

  bool _canSubmit({
    required bool uploadEnabled,
    required bool techPlanRequired,
  }) {
    final area = _readAreaValue(_areaController.text);
    final hasRequiredImage =
        !uploadEnabled || !techPlanRequired || _selectedImage != null;
    return !_isSubmitting && area != null && hasRequiredImage;
  }

  int? _readAreaValue(Object? value) {
    if (value is num) {
      final area = value.ceil();
      return area > 0 ? area : null;
    }
    if (value is String) {
      final normalized = value.trim().replaceAll(',', '.');
      final area = double.tryParse(normalized)?.ceil();
      return area != null && area > 0 ? area : null;
    }
    return null;
  }

  @override
  void dispose() {
    _areaController.removeListener(_onAreaChanged);
    _areaController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeArgsApplied) {
      return;
    }
    _routeArgsApplied = true;
    final routeArgs = ModalRoute.of(context)?.settings.arguments;
    final args = routeArgs is Map ? routeArgs : const <String, dynamic>{};
    final initialArea = _readAreaValue(
      args['actualArea'] ??
          args['area'] ??
          args['apartmentArea'] ??
          args['initialArea'],
    );
    _forceTechPlanPrompt = args['forceTechPlanPrompt'] == true;
    if (initialArea != null && initialArea > 0) {
      _initialAreaFromRoute = initialArea;
      _areaController.text = initialArea.toString();
      _areaSeeded = true;
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final image = await _imagePicker.pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1800,
    );
    if (image != null && mounted) {
      setState(() {
        _selectedImage = image;
        if (_error == 'Прикрепите фото технического плана') {
          _error = null;
        }
      });
    }
  }

  void _showImageSourcePicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(
                'Выбрать из галереи'.tr(),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: Text(
                'Сделать снимок'.tr(),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit({
    required bool uploadEnabled,
    required bool techPlanRequired,
  }) async {
    final areaText = _areaController.text.trim();
    if (areaText.isEmpty) {
      setState(() => _error = 'Введите площадь квартиры');
      return;
    }

    final area = _readAreaValue(areaText);
    if (area == null || area <= 0) {
      setState(() => _error = 'Введите корректное числовое значение площади');
      return;
    }

    if (uploadEnabled && techPlanRequired && _selectedImage == null) {
      setState(() => _error = 'Прикрепите фото технического плана');
      return;
    }

    if (!mounted) return;

    setState(() {
      _isSubmitting = true;
      _error = null;
      _uploadWarning = null;
    });

    try {
      String? downloadUrl;
      String? fileId;
      if (uploadEnabled && _selectedImage != null) {
        final uid = _data.currentUserId;
        if (AuthService.hasTemporarySession) {
          downloadUrl =
              'temp://area_confirmations/$uid/technical_plan_${DateTime.now().millisecondsSinceEpoch}.jpg';
        } else {
          try {
            final bytes = await _selectedImage!.readAsBytes();
            final stamp = DateTime.now().millisecondsSinceEpoch;
            final upload = await BackendApiService.instance.uploadFile(
              path: '/files',
              bytes: bytes,
              filename: 'technical_plan_$stamp.jpg',
              contentType: 'image/jpeg',
              fields: {
                'folder': 'area_confirmations/$uid',
                'documentType': 'technical_plan',
                'platform': kIsWeb ? 'web' : 'native',
              },
            );
            fileId = upload['id']?.toString();
            downloadUrl = (upload['public_url'] ?? upload['publicUrl'] ?? '')
                .toString()
                .trim();
            if (downloadUrl.isEmpty) {
              throw StateError('Сервис не вернул ссылку на фото.');
            }
          } catch (error) {
            throw StateError('Не удалось загрузить фото. Попробуйте ещё раз.');
          }
        }
      }

      final result = await _data.verifyApartmentArea(
        actualArea: area,
        areaTechnicalPlanUrl: downloadUrl,
        documentFileId: fileId,
      );

      if (!mounted) return;

      final areaVerified = result['areaVerified'] == true;
      final pendingReview = result['pendingReview'] == true;
      final awardedBonus = (result['bonusAmount'] as num?)?.toInt() ?? 0;
      showDomlySnackBar(
        context,
        title: areaVerified
            ? 'Площадь подтверждена'
            : pendingReview
                ? 'Отправлено на проверку'
                : 'Площадь сохранена',
        subtitle: _uploadWarning ??
            (areaVerified
                ? awardedBonus > 0
                    ? 'Бонус $awardedBonus ₸ начислен.'
                    : 'Данные обновлены.'
                : pendingReview
                    ? 'Документ отправлен администратору. Бонус будет начислен только после проверки.'
                    : 'Администратор увидит расхождение и проверит его.'),
        type: areaVerified ? DomlySnackBarType.success : DomlySnackBarType.info,
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Ошибка при подтверждении: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isSubmitting,
      child: DomlyShell(
        showBackButton: _isSubmitting ? false : null,
        bottomNavigationBar:
            _isSubmitting ? null : const DomlyClientBottomNav(currentIndex: 2),
        child: SafeArea(
          bottom: false,
          child: StreamBuilder<Map<String, dynamic>?>(
            stream: _config.areaConfigStream(),
            builder: (context, configSnap) {
              final areaConfig = configSnap.data ?? const <String, dynamic>{};
              final uploadEnabled = _config.getBool(
                areaConfig,
                'uploadEnabled',
                true,
              );
              final techPlanRequired =
                  _config.getBool(areaConfig, 'techPlanRequired', false) ||
                      _forceTechPlanPrompt;

              return StreamBuilder<Map<String, dynamic>?>(
                stream: _data.customerProfileStream(),
                builder: (context, snapshot) {
                  final profile = snapshot.data ?? const <String, dynamic>{};
                  final areaVerified = profile['areaVerified'] == true;
                  final rawArea = _initialAreaFromRoute ??
                      _readAreaValue(profile['actualArea']) ??
                      _readAreaValue(profile['apartmentArea']) ??
                      _readAreaValue(profile['area']) ??
                      _readAreaValue(profile['initialArea']);
                  if (!_areaSeeded && _areaController.text.trim().isEmpty) {
                    if (rawArea != null) {
                      _areaController.text = rawArea.toString();
                    }
                    _areaSeeded = true;
                  }
                  final canSubmit = _canSubmit(
                    uploadEnabled: uploadEnabled,
                    techPlanRequired: techPlanRequired,
                  );

                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(15, 0, 15, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _AreaFigmaHeader(),
                        const SizedBox(height: 15),
                        _AreaStatusPill(
                          label: areaVerified ? 'Подтверждено' : 'На проверке',
                          verified: areaVerified,
                        ),
                        const SizedBox(height: 8),
                        _AreaValueCard(controller: _areaController),
                        const SizedBox(height: 30),
                        if (uploadEnabled) ...[
                          if (_forceTechPlanPrompt) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFDF3EE),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: const Color(
                                    0xFFCF7548,
                                  ).withValues(alpha: 0.3),
                                ),
                              ),
                              child: Text(
                                'Если вы подтвердите площадь документом, после проверки администратором будет начислен бонус. Эту площадь мы будем использовать при оформлении заказов.'
                                    .tr(),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF7B4B37),
                                  height: 1.35,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],
                          _TechPlanCard(
                            image: _selectedImage,
                            onPick: _showImageSourcePicker,
                            onRemove: () =>
                                setState(() => _selectedImage = null),
                          ),
                          const SizedBox(height: 28),
                        ],
                        if (_error != null) ...[
                          _AreaErrorBox(message: _error!),
                          const SizedBox(height: 14),
                        ],
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: SizedBox(
                            height: 40,
                            child: ElevatedButton(
                              onPressed: canSubmit
                                  ? () => _submit(
                                        uploadEnabled: uploadEnabled,
                                        techPlanRequired: techPlanRequired,
                                      )
                                  : null,
                              style: ElevatedButton.styleFrom(
                                padding: EdgeInsets.zero,
                                backgroundColor: const Color(0xFFC96A4A),
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: const Color(
                                  0xFFC96A4A,
                                ).withValues(alpha: 0.55),
                                elevation: 4,
                                shadowColor: Colors.black.withValues(
                                  alpha: 0.25,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  height: 18 / 14,
                                ),
                              ),
                              child: Text(
                                _isSubmitting
                                    ? 'Отправляем...'
                                    : 'Подтвердить площадь',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: SizedBox(
                            height: 40,
                            child: OutlinedButton(
                              onPressed: _isSubmitting
                                  ? null
                                  : () => Navigator.pop(context, false),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFC96A4A),
                                side: BorderSide(
                                  color: const Color(
                                    0xFFC96A4A,
                                  ).withValues(alpha: 0.35),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              child: Text('Позже'.tr()),
                            ),
                          ),
                        ),
                        const SizedBox(height: 112),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AreaFigmaHeader extends StatelessWidget {
  const _AreaFigmaHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 130,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF439F73), Color(0xFF80D4B0)],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -17,
            top: -22,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            left: -49,
            bottom: -75,
            child: Container(
              width: 138,
              height: 138,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            left: 8,
            top: 23,
            child: Material(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(12),
              elevation: 4,
              shadowColor: Colors.black.withValues(alpha: 0.25),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.maybePop(context),
                child: const SizedBox(
                  width: 36,
                  height: 36,
                  child: Icon(
                    Icons.arrow_back,
                    color: Color(0xFF2E7D5B),
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 52,
            top: 21,
            right: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Подтверждение площади'.tr(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 31 / 20,
                  ),
                ),
                Text(
                  'Выберите параметры'.tr(),
                  style: TextStyle(
                    color: Color(0xFFEDFAF2),
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
    );
  }
}

class _AreaStatusPill extends StatelessWidget {
  const _AreaStatusPill({required this.label, required this.verified});

  final String label;
  final bool verified;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 22),
        child: Container(
          width: 108,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: verified ? const Color(0xFFE6F6EC) : const Color(0xFFFEF3DE),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            label,
            style: TextStyle(
              color:
                  verified ? const Color(0xFF439F73) : const Color(0xFFF4B330),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 16 / 12,
            ),
          ),
        ),
      ),
    );
  }
}

class _AreaValueCard extends StatelessWidget {
  const _AreaValueCard({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 100,
      padding: const EdgeInsets.fromLTRB(25, 14, 45, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFDEECE3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Площадь квартиры'.tr(),
            style: TextStyle(
              color: Color(0xFF2B4338),
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 22 / 16,
            ),
          ),
          const SizedBox(height: 11),
          SizedBox(
            height: 42,
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: const TextStyle(
                color: Color(0xFF2B4338),
                fontSize: 16,
                fontWeight: FontWeight.w600,
                height: 22 / 16,
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.fromLTRB(18, 10, 16, 10),
                filled: true,
                fillColor: const Color(0xFFF0F7F2),
                suffixText: 'м²',
                suffixStyle: const TextStyle(
                  color: Color(0xFF2B4338),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  height: 22 / 16,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFF80D4B0)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TechPlanCard extends StatelessWidget {
  const _TechPlanCard({
    required this.image,
    required this.onPick,
    required this.onRemove,
  });

  final XFile? image;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 313,
      padding: const EdgeInsets.fromLTRB(25, 17, 30, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFDEECE3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Фото технического плана'.tr(),
            style: TextStyle(
              color: Color(0xFF2B4338),
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 22 / 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Прикрепите фото технического плана квартиры, чтобы подтвердить площадь и получить бонус'
                .tr(),
            style: TextStyle(
              color: Color(0xFF658170),
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 18 / 13,
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: onPick,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: double.infinity,
                height: 170,
                color: const Color(0xFFF0F7F2),
                child: image == null
                    ? const Icon(Icons.add, size: 64, color: Color(0xFF606060))
                    : FutureBuilder<Uint8List>(
                        future: image!.readAsBytes(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFFC96A4A),
                              ),
                            );
                          }
                          return Image.memory(
                            snapshot.data!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: 170,
                          );
                        },
                      ),
              ),
            ),
          ),
          const SizedBox(height: 7),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  'Если хотите заменить фото\nнажмите на него'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 15 / 12,
                  ),
                ),
              ),
              GestureDetector(
                onTap: image == null ? null : onRemove,
                child: Icon(
                  Icons.delete_outline,
                  color: image == null
                      ? const Color(0x668A8A8A)
                      : const Color(0xFFCF7548),
                  size: 22,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AreaErrorBox extends StatelessWidget {
  const _AreaErrorBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DomlyColors.danger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DomlyColors.danger.withValues(alpha: 0.25)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: DomlyColors.danger,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
