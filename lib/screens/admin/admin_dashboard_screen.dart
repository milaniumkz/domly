import 'package:flutter/material.dart';

import '../../services/firestore_data_service.dart';
import '../../ui/domly_ui.dart';
import '../../localization/translation_controller.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = FirestoreDataService.instance;
    return DomlyShell(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.admin_panel_settings,
                    color: DomlyColors.buttonPrimary,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Админка DOMLY'.tr(),
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: DomlyColors.foreground,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              StreamBuilder<List<Map<String, dynamic>>>(
                stream: data.complaintsStream(),
                builder: (context, snapshot) {
                  final complaints =
                      snapshot.data ?? const <Map<String, dynamic>>[];
                  final inProgress = complaints.where((item) {
                    final status =
                        (item['status'] ?? 'open').toString().toLowerCase();
                    return status != 'resolved' &&
                        status != 'refund' &&
                        status != 'compensated';
                  }).length;
                  return _buildCard(
                    title: 'Жалобы в работе',
                    value: '$inProgress',
                    icon: Icons.report_problem_outlined,
                  );
                },
              ),
              const SizedBox(height: 16),
              StreamBuilder<List<Map<String, dynamic>>>(
                stream: data.adminOrdersStream(),
                builder: (context, snapshot) {
                  final orders =
                      snapshot.data ?? const <Map<String, dynamic>>[];
                  final activeOrders = orders.where((item) {
                    final status = (item['orderStatus'] ?? item['status'] ?? '')
                        .toString()
                        .toLowerCase();
                    return status != 'completed' &&
                        status != 'cancelled' &&
                        status != 'canceled';
                  }).length;
                  return _buildCard(
                    title: 'Активные заказы',
                    value: '$activeOrders',
                    icon: Icons.receipt_long_outlined,
                  );
                },
              ),
              const SizedBox(height: 16),
              StreamBuilder<List<Map<String, dynamic>>>(
                stream: data.cleanersDirectoryStream(),
                builder: (context, snapshot) {
                  final cleaners =
                      snapshot.data ?? const <Map<String, dynamic>>[];
                  final approved = cleaners.where((item) {
                    final status = (item['verificationStatus'] ?? '')
                        .toString()
                        .toLowerCase();
                    return status == 'approved';
                  }).length;
                  return _buildCard(
                    title: 'Одобренные уборщицы',
                    value: '$approved',
                    icon: Icons.cleaning_services_outlined,
                  );
                },
              ),
              const SizedBox(height: 24),
              Text(
                'Карточки используют service-layer и debug-aware потоки.'.tr(),
                style: TextStyle(color: DomlyColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard(
      {required String title, required String value, required IconData icon}) {
    return DomlyCard(
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: DomlyColors.accent.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: DomlyColors.buttonPrimary),
          ),
          const SizedBox(width: 16),
          Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600))),
          Text(value,
              style: const TextStyle(
                  color: DomlyColors.foreground,
                  fontSize: 24,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
