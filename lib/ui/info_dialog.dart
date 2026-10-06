import 'package:flutter/material.dart';
import '../localization/translation_controller.dart';
import '../ui/domly_ui.dart';

/// Reusable dialog for displaying admin-driven info content
class InfoDialog extends StatelessWidget {
  final String title;
  final String description;
  final String? fullInfo;
  final int? price;
  final int? bonusAmount;
  final String? imageUrl;
  final List<String>? features;
  final List<String>? exclusions;

  const InfoDialog({
    super.key,
    required this.title,
    required this.description,
    this.fullInfo,
    this.price,
    this.bonusAmount,
    this.imageUrl,
    this.features,
    this.exclusions,
  });

  /// Show info dialog from Firestore config document
  static Future<void> showFromConfig(
    BuildContext context, {
    required Map<String, dynamic> config,
  }) {
    return showDialog(
      context: context,
      builder: (context) => InfoDialog(
        title: config.trValue(
          const ['title', 'name'],
          fallback: 'Информация',
        ),
        description: config.trValue(
          const ['shortInfo', 'description'],
        ),
        fullInfo: config.trValue(
          const ['fullInfo', 'longDescription'],
        ),
        price: (config['price'] as num?)?.toInt(),
        bonusAmount: (config['bonusAmount'] as num?)?.toInt(),
        imageUrl: _imageUrlFrom(config),
        features: config['features'] is List
            ? (config['features'] as List)
                .map((e) => e.toString().tr())
                .toList()
            : null,
        exclusions: config['exclusions'] is List
            ? (config['exclusions'] as List)
                .map((e) => e.toString().tr())
                .toList()
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasExtraContent = fullInfo != null && fullInfo!.isNotEmpty;
    final hasFeatures = features != null && features!.isNotEmpty;
    final hasExclusions = exclusions != null && exclusions!.isNotEmpty;
    final resolvedImageUrl = (imageUrl ?? '').trim();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: IntrinsicHeight(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [DomlyColors.primary, DomlyColors.accent],
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.info_outline,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title.tr(),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),

              // Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Price/Bonus badges
                      if (price != null || bonusAmount != null)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (price != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: DomlyColors.buttonPrimary
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '$price ₸',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: DomlyColors.foreground,
                                  ),
                                ),
                              ),
                            if (bonusAmount != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      DomlyColors.accent.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '{amount} ₸ бонус'.tr(
                                    params: {'amount': '$bonusAmount'},
                                  ),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: DomlyColors.accent,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      if (price != null || bonusAmount != null)
                        const SizedBox(height: 16),

                      if (resolvedImageUrl.isNotEmpty) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.network(
                            resolvedImageUrl,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Description
                      Text(
                        description.tr(),
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: DomlyColors.foreground,
                        ),
                      ),

                      // Full info
                      if (hasExtraContent) ...[
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 12),
                        Text(
                          fullInfo!.tr(),
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: DomlyColors.muted,
                          ),
                        ),
                      ],

                      // Features list
                      if (hasFeatures) ...[
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 12),
                        Text(
                          'Что входит:'.tr(),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: DomlyColors.foreground,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...features!.map(
                          (feature) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '• ',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: DomlyColors.foreground,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    feature.tr(),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: DomlyColors.foreground,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],

                      if (hasExclusions) ...[
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 12),
                        Text(
                          'Что не входит:'.tr(),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: DomlyColors.foreground,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...exclusions!.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '• ',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: DomlyColors.muted,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    item.tr(),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: DomlyColors.foreground,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Close button
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: SizedBox(
                  width: double.infinity,
                  child: DomlyPrimaryButton(
                    label: 'Закрыть',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _imageUrlFrom(Map<String, dynamic> source) {
    for (final key in const [
      'imageUrl',
      'imageURL',
      'photoUrl',
      'photoURL',
      'bannerImageUrl',
      'bannerImageURL',
      'homeBannerImageUrl',
      'homeBannerImageURL',
      'coverUrl',
      'coverImageUrl',
      'mediaUrl',
      'downloadUrl',
      'url',
    ]) {
      final value = (source[key] ?? '').toString().trim();
      if (value.startsWith('https://') || value.startsWith('http://')) {
        return value;
      }
    }
    return '';
  }
}

/// Bottom sheet variant for quick info display
class InfoBottomSheet extends StatelessWidget {
  final String title;
  final String description;
  final String? fullInfo;

  const InfoBottomSheet({
    super.key,
    required this.title,
    required this.description,
    this.fullInfo,
  });

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String description,
    String? fullInfo,
  }) {
    return showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => InfoBottomSheet(
        title: title,
        description: description,
        fullInfo: fullInfo,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Title
          Text(
            title.tr(),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: DomlyColors.foreground,
            ),
          ),
          const SizedBox(height: 12),

          // Description
          Text(
            description.tr(),
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              color: DomlyColors.foreground,
            ),
          ),

          // Full info
          if (fullInfo != null && fullInfo!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              fullInfo!.tr(),
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: DomlyColors.muted,
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Close button
          SizedBox(
            width: double.infinity,
            child: DomlyPrimaryButton(
              label: 'Закрыть',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}
