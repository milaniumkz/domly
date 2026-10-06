export function normalizeMigrationPaymentStatus(value: unknown) {
  const raw = String(value ?? '').toLowerCase();
  if (['paid', 'success', 'completed', 'approved', 'confirmed'].includes(raw)) return 'paid';
  if (['refunded', 'refund'].includes(raw)) return 'refunded';
  if (['rejected', 'failed', 'declined'].includes(raw)) return 'rejected';
  if (['cancelled', 'canceled', 'expired'].includes(raw)) return 'cancelled';
  if (['invoice_requested', 'invoice'].includes(raw)) return 'invoice_requested';
  return raw || 'pending';
}

export function normalizeMigrationOrderStatus(value: unknown) {
  const raw = String(value ?? 'pending_assignment').toLowerCase();
  if (['draft'].includes(raw)) return 'draft';
  if (['pending', 'pending_assignment', 'waiting_cleaner', 'new', 'created'].includes(raw)) return 'pending_assignment';
  if (['pending_payment', 'awaiting_payment', 'payment_required'].includes(raw)) return 'pending_payment';
  if (['assigned', 'confirmed', 'accepted'].includes(raw)) return 'assigned';
  if (['in_progress', 'started', 'working'].includes(raw)) return 'in_progress';
  if (['completed', 'done', 'finished'].includes(raw)) return 'completed';
  if (['cancelled', 'canceled', 'declined', 'rejected'].includes(raw)) return 'cancelled';
  return 'pending_assignment';
}
