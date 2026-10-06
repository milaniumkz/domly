/**
 * Send push notifications for order status changes
 * Call this from order-related Cloud Functions
 */

const admin = require('firebase-admin');

function getDb() {
  return admin.firestore();
}

function getMessaging() {
  return admin.messaging();
}

async function createNotification(userId, {type, title, body, payload = {}}) {
  if (!userId) return;
  await getDb().collection('notifications').add({
    userId,
    type,
    title,
    body,
    payload,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    read: false,
  });
}

/**
 * Send notification when cleaner is assigned
 */
async function notifyCleanerAssigned(orderId) {
  try {
    const db = getDb();
    const orderDoc = await db.collection('customer_orders').doc(orderId).get();
    if (!orderDoc.exists) return;

    const order = orderDoc.data();
    const customerId = order.customerId;
    const cleanerName = order.cleanerName || 'Уборщица';

    await createNotification(customerId, {
      type: 'cleaner_assigned',
      title: 'Уборщица назначена!',
      body: `${cleanerName} приедет к вам на уборку`,
      payload: {orderId, cleanerName},
    });

    // Get customer device tokens
    const tokensSnap = await db
      .collection('device_tokens')
      .where('userId', '==', customerId)
      .get();

    const tokens = [];
    tokensSnap.forEach(doc => tokens.push(doc.data().token));

    if (tokens.length === 0) return;

    const message = {
      notification: {
        title: 'Уборщица назначена!',
        body: `${cleanerName} приедет к вам на уборку`,
      },
      data: {
        type: 'cleaner_assigned',
        orderId: orderId,
        cleanerName: cleanerName,
      },
      tokens: tokens,
    };

    await getMessaging().sendEachForMulticast(message);
  } catch (e) {
    console.error('Error sending cleaner assigned notification:', e);
  }
}

/**
 * Send notification when order is completed
 */
async function notifyOrderCompleted(orderId) {
  try {
    const db = getDb();
    const orderDoc = await db.collection('customer_orders').doc(orderId).get();
    if (!orderDoc.exists) return;

    const order = orderDoc.data();
    const customerId = order.customerId;

    await createNotification(customerId, {
      type: 'order_completed',
      title: 'Уборка завершена! ✨',
      body: 'Оцените качество уборки',
      payload: {orderId},
    });

    const tokensSnap = await db
      .collection('device_tokens')
      .where('userId', '==', customerId)
      .get();

    const tokens = [];
    tokensSnap.forEach(doc => tokens.push(doc.data().token));

    if (tokens.length === 0) return;

    const message = {
      notification: {
        title: 'Уборка завершена! ✨',
        body: 'Оцените качество уборки',
      },
      data: {
        type: 'order_completed',
        orderId: orderId,
      },
      tokens: tokens,
    };

    await getMessaging().sendEachForMulticast(message);
  } catch (e) {
    console.error('Error sending order completed notification:', e);
  }
}

/**
 * Send notification when payment is confirmed
 */
async function notifyPaymentConfirmed(orderId) {
  try {
    const db = getDb();
    const orderDoc = await db.collection('customer_orders').doc(orderId).get();
    if (!orderDoc.exists) return;

    const order = orderDoc.data();
    const customerId = order.customerId;
    const packageName = order.package || order.frequencyLabel || 'Пакет';

    await createNotification(customerId, {
      type: 'payment_confirmed',
      title: 'Оплата подтверждена! ✅',
      body: `${packageName} активирован`,
      payload: {orderId, packageName},
    });

    const tokensSnap = await db
      .collection('device_tokens')
      .where('userId', '==', customerId)
      .get();

    const tokens = [];
    tokensSnap.forEach(doc => tokens.push(doc.data().token));

    if (tokens.length === 0) return;

    const message = {
      notification: {
        title: 'Оплата подтверждена! ✅',
        body: `${packageName} активирован`,
      },
      data: {
        type: 'payment_confirmed',
        orderId: orderId,
        packageName: packageName,
      },
      tokens: tokens,
    };

    await getMessaging().sendEachForMulticast(message);
  } catch (e) {
    console.error('Error sending payment confirmed notification:', e);
  }
}

/**
 * Send notification when payment is rejected
 */
async function notifyPaymentRejected(orderId, reason = null) {
  try {
    const db = getDb();
    const orderDoc = await db.collection('customer_orders').doc(orderId).get();
    if (!orderDoc.exists) return;

    const order = orderDoc.data();
    const customerId = order.customerId;
    const normalizedReason = reason ? String(reason).trim() : '';
    const body = normalizedReason
      ? `Причина: ${normalizedReason}`
      : 'Проверьте способ оплаты или свяжитесь с поддержкой';

    await createNotification(customerId, {
      type: 'payment_rejected',
      title: 'Оплата отклонена',
      body,
      payload: {orderId, reason: normalizedReason},
    });

    const tokensSnap = await db
      .collection('device_tokens')
      .where('userId', '==', customerId)
      .get();

    const tokens = [];
    tokensSnap.forEach(doc => tokens.push(doc.data().token));

    if (tokens.length === 0) return;

    const message = {
      notification: {
        title: 'Оплата отклонена',
        body,
      },
      data: {
        type: 'payment_rejected',
        orderId: orderId,
        reason: normalizedReason,
      },
      tokens: tokens,
    };

    await getMessaging().sendEachForMulticast(message);
  } catch (e) {
    console.error('Error sending payment rejected notification:', e);
  }
}

/**
 * Send reminder before scheduled cleaning
 */
async function sendCleaningReminder(orderId) {
  try {
    const db = getDb();
    const orderDoc = await db.collection('customer_orders').doc(orderId).get();
    if (!orderDoc.exists) return;

    const order = orderDoc.data();
    const customerId = order.customerId;

    await createNotification(customerId, {
      type: 'cleaning_reminder',
      title: 'Напоминание об уборке 🧹',
      body: 'Завтра к вам приедет уборщица',
      payload: {orderId},
    });

    const tokensSnap = await db
      .collection('device_tokens')
      .where('userId', '==', customerId)
      .get();

    const tokens = [];
    tokensSnap.forEach(doc => tokens.push(doc.data().token));

    if (tokens.length === 0) return;

    const message = {
      notification: {
        title: 'Напоминание об уборке 🧹',
        body: 'Завтра к вам приедет уборщица',
      },
      data: {
        type: 'cleaning_reminder',
        orderId: orderId,
      },
      tokens: tokens,
    };

    await getMessaging().sendEachForMulticast(message);
  } catch (e) {
    console.error('Error sending cleaning reminder:', e);
  }
}

/**
 * Send referral bonus notification
 */
async function notifyReferralBonus(customerId, bonusAmount) {
  try {
    const db = getDb();
    await createNotification(customerId, {
      type: 'referral_bonus',
      title: 'Бонус за реферала! 🎁',
      body: `Вам начислено ${bonusAmount} ₸ за приглашённого друга`,
      payload: {bonusAmount: String(bonusAmount)},
    });

    const tokensSnap = await db
      .collection('device_tokens')
      .where('userId', '==', customerId)
      .get();

    const tokens = [];
    tokensSnap.forEach(doc => tokens.push(doc.data().token));

    if (tokens.length === 0) return;

    const message = {
      notification: {
        title: 'Бонус за реферала! 🎁',
        body: `Вам начислено ${bonusAmount} ₸ за приглашённого друга`,
      },
      data: {
        type: 'referral_bonus',
        bonusAmount: String(bonusAmount),
      },
      tokens: tokens,
    };

    await getMessaging().sendEachForMulticast(message);
  } catch (e) {
    console.error('Error sending referral bonus notification:', e);
  }
}

module.exports = {
  notifyCleanerAssigned,
  notifyOrderCompleted,
  notifyPaymentConfirmed,
  notifyPaymentRejected,
  sendCleaningReminder,
  notifyReferralBonus,
};
