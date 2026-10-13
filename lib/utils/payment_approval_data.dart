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
  if (payment['invoiceIntegration'] == true)
    return 'Счёт через интеграцию MooonAI / Kaspi';
  return (payment['status'] ?? payment['paymentStatus']) == 'paid'
      ? 'Источник подтверждения не указан'
      : 'Ожидает подтверждения';
}
