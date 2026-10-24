# Delivery after order commit

`NotificationService.create` writes the notification and `notification_deliveries` row in the same PostgreSQL transaction. HTTP handlers do not wait for Redis, FCM or alarm scheduling. A rollback removes both records. Existing notification history is not enqueued again by the migration.

The worker claims at most32 rows with `FOR UPDATE SKIP LOCKED`, a five-minute lease and an ownership token. Four deliveries run concurrently; failed work remains durable with exponential backoff capped at300 seconds. Expired leases are recoverable after worker restart. Shutdown waits for the active batch. Cleaner offers are checked again before delivery/alarm, so cancelled or expired offers do not ring.

Delivery is **at least once**, not exactly once: a worker may stop after external delivery but before recording acknowledgement. The notification ID is stable; retries do not create additional history rows. Invalid FCM registration tokens are disabled. Transient provider failures remain queued. Real FCM delivery requires a provider/device test; isolated tests use stubs.

Monitor pending count, oldest pending age, attempts and `last_error` in `notification_deliveries`. Do not remove pending rows to clear alerts. A growing queue must be investigated; a successful HTTP reply does not itself prove push delivery. No production deployment accompanies this test branch.
