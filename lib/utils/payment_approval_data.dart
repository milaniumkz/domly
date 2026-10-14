String paymentApprovalLabel(Map<String, dynamic> payment) {
  final source = (payment['approvalSource'] ?? payment['approval_source'] ?? '')
      .toString();
  switch (source) {
    case 'manual':
      return 'Платёж одобрен вручную';
    case 'moon_ai':
      return 'Платёж проведён через интеграцию MooonAI / Kaspi';
    case 'kaspi':
      return 'Платёж проведён через интеграцию Kaspi';
    case 'bcc':
      return 'Платёж проведён через интеграцию BCC';
    case 'bonus':
      return 'Платёж проведён бонусами';
  }
  if (payment['bccTestMode'] == true) {
    return payment['bccBankStatus'] == 'paid'
        ? 'Тест BCC успешен; настоящая оплата не подтверждена'
        : 'Тестовый платёж BCC — реальные деньги не списываются';
  }
  if (payment['integrationReview'] != null) {
    return 'Интеграция: нужна ручная проверка';
  }
  if (payment['integrationStatus'] == 'invoice_sent') {
    return 'Счёт выставлен через интеграцию MooonAI / Kaspi';
  }
  if (payment['integrationStatus'] == 'rejected') {
    return 'Интеграция: отказ или ошибка';
  }
  if (payment['integrationStatus'] == 'cancelled') {
    return 'Интеграция: счёт отменён или истёк';
  }
  if (payment['invoiceIntegration'] == true) {
    return 'Счёт через интеграцию MooonAI / Kaspi';
  }
  return (payment['status'] ?? payment['paymentStatus']) == 'paid'
      ? 'Источник подтверждения не указан'
      : 'Ожидает подтверждения';
}

bool paymentNeedsManualReview(Map<String, dynamic> payment) {
  final status = (payment['status'] ?? payment['paymentStatus'] ?? '')
      .toString()
      .trim()
      .toLowerCase();
  return const {
    'pending',
    'invoice_requested',
    'pending_invoice',
    'initiated',
    'rejected',
    'failed'
  }.contains(status);
}
