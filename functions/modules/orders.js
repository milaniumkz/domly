/**
 * Order-related Cloud Functions
 * Extracted from main index.js for better maintainability
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { notifyCleanerAssigned, notifyPaymentConfirmed, notifyOrderCompleted } = require('../utils/notifications');

const db = admin.firestore();

/**
 * Create order from request
 */
exports.createOrderFromRequest = functions.https.onCall(async (request) => {
  if (!request.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Login required');
  }

  const { packageId, area, addons, accessMethod } = request.data || {};

  if (!packageId || !area) {
    throw new functions.https.HttpsError('invalid-argument', 'Package and area required');
  }

  const orderId = db.collection('customer_orders').doc().id;

  await db.collection('customer_orders').doc(orderId).set({
    customerId: request.auth.uid,
    package: packageId,
    area: area,
    accessMethod: accessMethod || 'Я дома',
    addons: addons || [],
    status: 'created',
    orderStatus: 'pending_payment',
    paymentStatus: 'initiated',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return { ok: true, orderId };
});

/**
 * Advance order status with notification
 */
exports.advanceOrderStatus = functions.https.onCall(async (request) => {
  if (!request.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Login required');
  }

  const { orderId, newStatus } = request.data || {};

  if (!orderId || !newStatus) {
    throw new functions.https.HttpsError('invalid-argument', 'orderId and newStatus required');
  }

  const orderRef = db.collection('customer_orders').doc(orderId);
  const orderSnap = await orderRef.get();

  if (!orderSnap.exists) {
    throw new functions.https.HttpsError('not-found', 'Order not found');
  }

  await orderRef.update({
    orderStatus: newStatus,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  // Send notifications based on status
  if (newStatus === 'assigned') {
    await notifyCleanerAssigned(orderId);
  } else if (newStatus === 'completed') {
    await notifyOrderCompleted(orderId);
  }

  return { ok: true, status: newStatus };
});

/**
 * Assign cleaner to order
 */
exports.assignCleaner = functions.https.onCall(async (request) => {
  if (!request.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Login required');
  }

  const { orderId, cleanerId, cleanerName } = request.data || {};

  if (!orderId || !cleanerId) {
    throw new functions.https.HttpsError('invalid-argument', 'orderId and cleanerId required');
  }

  const orderRef = db.collection('customer_orders').doc(orderId);
  const orderSnap = await orderRef.get();

  if (!orderSnap.exists) {
    throw new functions.https.HttpsError('not-found', 'Order not found');
  }

  await orderRef.update({
    cleanerId: cleanerId,
    cleanerName: cleanerName || 'Уборщица',
    orderStatus: 'assigned',
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await notifyCleanerAssigned(orderId);

  return { ok: true, cleanerId, cleanerName };
});
