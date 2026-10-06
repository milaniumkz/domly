const admin = require('firebase-admin');
const crypto = require('crypto');
const {setGlobalOptions} = require('firebase-functions/v2');
const {onDocumentCreated, onDocumentWritten} = require('firebase-functions/v2/firestore');
const {onCall, onRequest, HttpsError} = require('firebase-functions/v2/https');
const {onSchedule} = require('firebase-functions/v2/scheduler');
const {
  notifyPaymentConfirmed,
  notifyPaymentRejected,
} = require('./utils/notifications');

setGlobalOptions({
  region: 'us-central1',
  cpu: 'gcf_gen1',
  memory: '256MiB'
});

admin.initializeApp();
const db = admin.firestore();
const WEB_CORS_ORIGINS = [
  /^https:\/\/domly-d0f91\.web\.app$/,
  /^https:\/\/domly-pro\.web\.app$/,
  /^https:\/\/domly-admin-web\.web\.app$/,
  /^http:\/\/localhost(:\d+)?$/,
  /^http:\/\/127\.0\.0\.1(:\d+)?$/
];
const callable = (handler) => onCall({cors: WEB_CORS_ORIGINS}, handler);
const AUTH_SESSION_TTL_DAYS = 180;
const assignmentOfferTriggerOptions = (document) => ({
  document,
  cpu: 'gcf_gen1',
  memory: '256MiB',
  timeoutSeconds: 120,
  concurrency: 1,
  maxInstances: 3,
});

const ORDER_TRANSITIONS = {
  pending_payment: ['pending_assignment', 'canceled'],
  pending_assignment: ['assigned', 'canceled'],
  assigned: ['start_pending', 'in_progress', 'canceled'],
  confirmed: ['start_pending', 'in_progress', 'canceled'],
  start_pending: ['in_progress', 'canceled'],
  in_progress: ['completed', 'disputed'],
  completed: [],
  disputed: ['completed', 'canceled'],
  canceled: []
};

const EPAY_TOKEN_URL = process.env.EPAY_TOKEN_URL || 'https://test-epay-oauth.epayment.kz/oauth2/token';
const EPAY_INVOICE_URL = process.env.EPAY_INVOICE_URL || 'https://test-epay-api.epayment.kz/invoice';
const EPAY_STATUS_URL = process.env.EPAY_STATUS_URL || 'https://test-epay-api.epayment.kz/invoice-links';
const EPAY_PAYOUT_URL = process.env.EPAY_PAYOUT_URL || 'https://test-epay-api.epayment.kz/payout';
const EPAY_INVOICE_CLIENT_ID = process.env.EPAY_INVOICE_CLIENT_ID || process.env.EPAY_CLIENT_ID || '';
const EPAY_INVOICE_CLIENT_SECRET = process.env.EPAY_INVOICE_CLIENT_SECRET || process.env.EPAY_CLIENT_SECRET || '';
const EPAY_PAYOUT_CLIENT_ID = process.env.EPAY_PAYOUT_CLIENT_ID || process.env.EPAY_CLIENT_ID || '';
const EPAY_PAYOUT_CLIENT_SECRET = process.env.EPAY_PAYOUT_CLIENT_SECRET || process.env.EPAY_CLIENT_SECRET || '';
const EPAY_WEBHOOK_TOKEN = process.env.EPAY_WEBHOOK_TOKEN || '';
const SEED_TOKEN = process.env.SEED_TOKEN || '';
const EPAY_SHOP_ID = process.env.EPAY_SHOP_ID || process.env.EPAY_INVOICE_SHOP_ID || '';
const EPAY_TERMINAL_ID = process.env.EPAY_TERMINAL_ID || process.env.EPAY_INVOICE_TERMINAL_ID || '';
const EPAY_PAYOUT_TERMINAL_ID = process.env.EPAY_PAYOUT_TERMINAL_ID || '';
const BCC_ECOMMERCE_URL =
  process.env.BCC_ECOMMERCE_URL || 'https://test3ds.bcc.kz:5445/cgi-bin/cgi_link';
const BCC_ECOMMERCE_MERCHANT = process.env.BCC_ECOMMERCE_MERCHANT || '00000001';
const BCC_ECOMMERCE_MERCH_NAME = process.env.BCC_ECOMMERCE_MERCH_NAME || 'TOO MERCHANT';
const BCC_ECOMMERCE_TERMINAL = process.env.BCC_ECOMMERCE_TERMINAL || '88888881';
const BCC_ECOMMERCE_MAC_KEY =
  process.env.BCC_ECOMMERCE_MAC_KEY || '6BB0AC02E47BDF73D98FEB777F3B5294';
const BCC_ECOMMERCE_BACKREF =
  process.env.BCC_ECOMMERCE_BACKREF || 'https://domly-d0f91.web.app/#/client/orders';
const BCC_ECOMMERCE_NOTIFY_URL =
  process.env.BCC_ECOMMERCE_NOTIFY_URL ||
  'https://us-central1-domly-d0f91.cloudfunctions.net/bccPaymentWebhook';
const SUBSCRIPTION_WINDOW_DAYS = Number(process.env.SUBSCRIPTION_WINDOW_DAYS || 35);
const SUBSCRIPTION_TERM_MONTHS = Number(process.env.SUBSCRIPTION_TERM_MONTHS || 1);
const FREE_CANCELLATION_HOURS = Number(process.env.FREE_CANCELLATION_HOURS || 12);
const SLOT_REMINDER_HOURS = [24, 3];
const MIN_BOOKING_HOURS = Number(process.env.MIN_BOOKING_HOURS || 0);
const BOOKING_START_DATE = startOfDay(new Date(
  process.env.BOOKING_START_DATE || '2026-09-02T00:00:00'
));
const APP_TIMEZONE_OFFSET_MINUTES = Number(
  process.env.APP_TIMEZONE_OFFSET_MINUTES || 300
);
const DEFAULT_TRAVEL_TIME_MINUTES = Number(process.env.DEFAULT_TRAVEL_TIME_MINUTES || 15);
const ADDON_BUFFER_MINUTES_PER_ITEM = Number(process.env.ADDON_BUFFER_MINUTES_PER_ITEM || 15);
const MAX_ONSITE_ADDONS = Number(process.env.MAX_ONSITE_ADDONS || 2);
const DAILY_SCHEDULE_LIMIT_MINUTES = Number(process.env.DAILY_SCHEDULE_LIMIT_MINUTES || 510);
const DAILY_AREA_LIMIT_SQM = Number(process.env.DAILY_AREA_LIMIT_SQM || 220);
const DAILY_AREA_OVERBOOK_TOLERANCE_SQM = Number(process.env.DAILY_AREA_OVERBOOK_TOLERANCE_SQM || 20);
const URGENT_ORDER_PREP_BUFFER_MINUTES = Number(process.env.URGENT_ORDER_PREP_BUFFER_MINUTES || 20);
const ORDER_OFFER_TTL_SECONDS = Number(process.env.ORDER_OFFER_TTL_SECONDS || 120);
const CLEANER_QUIET_HOURS_START = Number(process.env.CLEANER_QUIET_HOURS_START || 23);
const CLEANER_QUIET_HOURS_END = Number(process.env.CLEANER_QUIET_HOURS_END || 7);
const REVIEW_TEST_OTP_CODE = '123456';
const REVIEW_TEST_ACCOUNTS = {
  '77000000001': {flavor: 'customer', name: 'DOMLY Test Client'},
  '77000000002': {flavor: 'pro', name: 'DOMLY Test Cleaner'}
};
const TOMORROW_CONFIRMATION_DEADLINE_HOUR = Number(process.env.TOMORROW_CONFIRMATION_DEADLINE_HOUR || 21);
const ASSIGNMENT_WAVE_SIZE = Number(process.env.ASSIGNMENT_WAVE_SIZE || 8);
const HOUSE_STATUS = {
  INACTIVE: 'INACTIVE',
  IN_PROGRESS: 'IN_PROGRESS',
  ACTIVE: 'ACTIVE'
};
const USER_TIERS = {
  NEWBIE: 'NEWBIE',
  CLEANSTER: 'CLEANSTER',
  GURU: 'GURU',
  GOD: 'GOD'
};
const USER_TIER_RULES = [
  {tier: USER_TIERS.NEWBIE, minSpent: 0, maxSpent: 100000, discountPercent: 0},
  {tier: USER_TIERS.CLEANSTER, minSpent: 100000, maxSpent: 500000, discountPercent: 5},
  {tier: USER_TIERS.GURU, minSpent: 500000, maxSpent: 1500000, discountPercent: 10},
  {tier: USER_TIERS.GOD, minSpent: 1500000, maxSpent: null, discountPercent: 10}
];
const CLEANER_STATUSES = {
  NEWBIE: 'NEWBIE',
  RELIABLE: 'RELIABLE',
  EXPERT: 'EXPERT',
  LEGEND: 'LEGEND'
};
const CLEANER_STATUS_LABELS = {
  [CLEANER_STATUSES.NEWBIE]: 'Новичок',
  [CLEANER_STATUSES.RELIABLE]: 'Надежная',
  [CLEANER_STATUSES.EXPERT]: 'Эксперт',
  [CLEANER_STATUSES.LEGEND]: 'Легенда'
};
const CLEANER_STATUS_PRIORITY = {
  [CLEANER_STATUSES.NEWBIE]: 1,
  [CLEANER_STATUSES.RELIABLE]: 2,
  [CLEANER_STATUSES.EXPERT]: 3,
  [CLEANER_STATUSES.LEGEND]: 4
};
const CLEANER_STATUS_RULES = [
  {
    status: CLEANER_STATUSES.NEWBIE,
    label: CLEANER_STATUS_LABELS[CLEANER_STATUSES.NEWBIE],
    minArea: 0,
    careerBonus: 0
  },
  {
    status: CLEANER_STATUSES.RELIABLE,
    label: CLEANER_STATUS_LABELS[CLEANER_STATUSES.RELIABLE],
    minArea: 12000,
    careerBonus: 100000
  },
  {
    status: CLEANER_STATUSES.EXPERT,
    label: CLEANER_STATUS_LABELS[CLEANER_STATUSES.EXPERT],
    minArea: 30000,
    careerBonus: 200000
  },
  {
    status: CLEANER_STATUSES.LEGEND,
    label: CLEANER_STATUS_LABELS[CLEANER_STATUSES.LEGEND],
    minArea: 65000,
    careerBonus: 500000
  }
];
const FAIRNESS_WEIGHTS = {
  area: 0.30,
  hours: 0.30,
  income: 0.20,
  apartments: 0.10,
  district: 0.10,
  status: 0.15
};
const MANUAL_BOOKING_START_MINUTE = 8 * 60;
const MANUAL_BOOKING_END_MINUTE = 22 * 60;
const MANUAL_BOOKING_STEP_MINUTES = 30;
const HIGH_ADDON_THRESHOLD = Number(process.env.HIGH_ADDON_THRESHOLD || 10000);
const MEDIUM_ADDON_THRESHOLD = Number(process.env.MEDIUM_ADDON_THRESHOLD || 5000);
const DEFAULT_POLICY_CONFIG = {
  referralBonusAmount: 2000,
  defaultHouseThreshold: 20,
  areaVerificationTolerance: 0,
  cleanerReliableAreaThreshold: 12000,
  cleanerExpertAreaThreshold: 30000,
  cleanerLegendAreaThreshold: 65000,
  cleanerReliableBonusAmount: 100000,
  cleanerExpertBonusAmount: 200000,
  cleanerLegendBonusAmount: 500000,
  cleanerWeeklyAreaThreshold: 1300,
  cleanerWeeklyAreaBonusAmount: 5000,
  cleanerWeeklyAddonBonusThreshold1: 30000,
  cleanerWeeklyAddonBonusAmount1: 4000,
  cleanerWeeklyAddonBonusThreshold2: 50000,
  cleanerWeeklyAddonBonusAmount2: 6000,
  cleanerDailyIncome: 13500,
  cleanerSqmRate: 60,
  cleanerWeeklyCashoutPercent: 30,
  cleanerWeeklyCashoutCooldownDays: 7,
  cleanerFullCashoutCooldownDays: 30,
  packagePurchaseBonusEnabled: false,
  packagePurchaseBonusAmount: 10000,
  cleaningMinutesPerSqm: 1.6,
  cleaningBaseMinutes: 30,
  cleaningMinMinutes: 120,
  cleaningMaxMinutes: 480
};
const REFERRAL_DISCOUNT_TIERS = [
  {count: 20, percent: 10},
  {count: 10, percent: 7},
  {count: 5, percent: 3}
];
const CLEANER_AVAILABILITY_STATUSES = {
  OFFLINE: 'offline',
  ONLINE_READY: 'online_ready',
  AT_HOME_READY: 'at_home_ready',
  BUSY: 'busy',
  ON_WAY_TO_CLIENT: 'on_way_to_client',
  ARRIVED: 'arrived',
  CLEANING: 'cleaning',
  BREAK: 'break',
  FINISHED: 'finished'
};
const ORDER_ASSIGNMENT_STATUSES = {
  SEARCHING: 'searching',
  OFFER_PENDING: 'offer_pending',
  SCHEDULED_PENDING_CONFIRMATION: 'scheduled_pending_confirmation',
  SCHEDULED_CONFIRMED: 'scheduled_confirmed',
  REASSIGNMENT_NEEDED: 'reassignment_needed',
  ASSIGNED: 'assigned'
};

function isAdminAuth(auth) {
  return Boolean(auth && auth.token && (auth.token.admin === true || auth.token.superAdmin === true));
}

function isBackofficeAuth(auth) {
  return Boolean(auth && auth.token && (
    auth.token.admin === true ||
    auth.token.superAdmin === true ||
    auth.token.manager === true
  ));
}

function assertAdmin(auth) {
  if (!isAdminAuth(auth)) {
    throw new HttpsError('permission-denied', 'Admin privileges required');
  }
}

function assertBackoffice(auth) {
  if (!isBackofficeAuth(auth)) {
    throw new HttpsError('permission-denied', 'Backoffice privileges required');
  }
}

async function verifyBearerToken(req) {
  const raw = String(req.headers.authorization || '');
  if (!raw.startsWith('Bearer ')) {
    throw new HttpsError('unauthenticated', 'Bearer token required');
  }
  const token = raw.slice(7).trim();
  if (!token) {
    throw new HttpsError('unauthenticated', 'Bearer token required');
  }
  return admin.auth().verifyIdToken(token);
}

function normalizePhone(rawPhone) {
  const digits = String(rawPhone || '').replace(/\D/g, '');
  if (digits.length === 11 && digits.startsWith('8')) {
    return `7${digits.slice(1)}`;
  }
  if (digits.length === 11 && digits.startsWith('7')) {
    return digits;
  }
  if (digits.length === 10) {
    return `7${digits}`;
  }
  return null;
}

function timestampMillis(value) {
  if (value instanceof admin.firestore.Timestamp) {
    return value.toMillis();
  }
  if (value instanceof Date) {
    return value.getTime();
  }
  if (typeof value === 'string' || typeof value === 'number') {
    const parsed = new Date(value).getTime();
    return Number.isFinite(parsed) ? parsed : 0;
  }
  return 0;
}

function normalizeOrderNumber(value) {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return Math.trunc(value);
  }
  const digits = String(value || '').trim();
  if (!/^\d+$/.test(digits)) {
    return 0;
  }
  return Number.parseInt(digits, 10);
}

function orderDisplayIdFromNumber(value) {
  const normalized = normalizeOrderNumber(value);
  return normalized > 0 ? String(normalized) : null;
}

function stableAddonFingerprint(addonsDetailed = []) {
  return (Array.isArray(addonsDetailed) ? addonsDetailed : [])
    .map((item) => ({
      id: String(item?.id || item?.name || '').trim(),
      quantity: Math.max(1, Number(item?.quantity || 1)),
      separatePayment: Boolean(item?.separatePayment),
      price: Math.max(0, Number(item?.price || 0)),
    }))
    .sort((a, b) => `${a.id}:${a.quantity}:${a.price}`.localeCompare(`${b.id}:${b.quantity}:${b.price}`));
}

function buildPendingOrderFingerprint({
  customerId,
  normalizedPackageId,
  packageName,
  normalizedPricingMode,
  effectiveVisitsPerMonth,
  effectiveBillingPeriodMonths,
  finalAmount,
  area,
  customerAddress,
  normalizedDetailedAddons,
}) {
  return JSON.stringify({
    customerId: String(customerId || '').trim(),
    packageId: String(normalizedPackageId || '').trim(),
    packageName: String(packageName || '').trim(),
    pricingMode: String(normalizedPricingMode || '').trim(),
    visits: Math.max(0, Number(effectiveVisitsPerMonth || 0)),
    months: Math.max(0, Number(effectiveBillingPeriodMonths || 0)),
    amount: Math.max(0, Number(finalAmount || 0)),
    area: Math.max(0, Number(area || 0)),
    address: String(customerAddress || '').trim(),
    addons: stableAddonFingerprint(normalizedDetailedAddons),
  });
}

async function findReusablePendingOrder({
  customerId,
  fingerprint,
  freshnessWindowMs = 10 * 60 * 1000,
}) {
  const snap = await db
    .collection('customer_orders')
    .where('customerId', '==', customerId)
    .limit(20)
    .get();

  const candidates = snap.docs
    .map((doc) => ({id: doc.id, data: doc.data() || {}}))
    .filter(({data}) => {
      const orderStatus = String(data.orderStatus || '').trim().toLowerCase();
      const paymentStatus = String(data.paymentStatus || '').trim().toLowerCase();
      if (orderStatus !== 'pending_payment' || paymentStatus !== 'initiated') {
        return false;
      }
      const createdAtMs = timestampMillis(data.createdAt || data.date || data.updatedAt);
      if (!createdAtMs || (Date.now() - createdAtMs) > freshnessWindowMs) {
        return false;
      }
      return String(data.orderFingerprint || '') === String(fingerprint || '');
    })
    .sort((a, b) => timestampMillis(b.data.createdAt || b.data.date || b.data.updatedAt) - timestampMillis(a.data.createdAt || a.data.date || a.data.updatedAt));

  return candidates[0] || null;
}

async function allocateNextOrderNumber(tx) {
  const counterRef = db.collection('system_counters').doc('customer_orders');
  const counterSnap = await tx.get(counterRef);
  let lastOrderNumber = normalizeOrderNumber(
    counterSnap.exists ? counterSnap.data()?.lastOrderNumber : 0
  );

  if (lastOrderNumber <= 0) {
    const ordersSnap = await tx.get(db.collection('customer_orders'));
    for (const doc of ordersSnap.docs) {
      const data = doc.data() || {};
      lastOrderNumber = Math.max(
        lastOrderNumber,
        normalizeOrderNumber(data.orderNumber),
        normalizeOrderNumber(doc.id)
      );
    }
  }

  const nextOrderNumber = lastOrderNumber + 1;
  tx.set(counterRef, {
    lastOrderNumber: nextOrderNumber,
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, {merge: true});
  return nextOrderNumber;
}

function isCustomerAreaVerifiedForOrdering(customerProfile = {}, selectedAddress = null) {
  const profileStatus = String(customerProfile.areaStatus || '').trim().toUpperCase();
  const addressStatus = String(selectedAddress?.areaStatus || '').trim().toUpperCase();
  return customerProfile.areaVerified === true ||
    selectedAddress?.areaVerified === true ||
    profileStatus === 'VERIFIED' ||
    addressStatus === 'VERIFIED';
}

function assertCustomerAreaReadyForOrdering({
  customerProfile = {},
  selectedAddress = null,
  selectedArea = 0
}) {
  const area = Number(selectedArea || selectedAddress?.area || customerProfile.area || customerProfile.apartmentArea || 0);
  if (!Number.isFinite(area) || area <= 0) {
    throw new HttpsError(
      'failed-precondition',
      'Сначала заполните данные квартиры и укажите площадь.'
    );
  }
  return area;
}

async function resolveCanonicalPhoneProfile(collectionName, phone) {
  const indexId = `${collectionName}_${phone}`;
  const indexRef = db.collection('identity_phone_index').doc(indexId);
  const indexSnap = await indexRef.get();
  const indexedUid = String(indexSnap.data()?.uid || '').trim();
  if (indexedUid) {
    const indexedRef = db.collection(collectionName).doc(indexedUid);
    const indexedDoc = await indexedRef.get();
    if (indexedDoc.exists) {
      return indexedDoc;
    }
  }

  const matchesSnap = await db.collection(collectionName)
    .where('phone', '==', phone)
    .get();

  if (matchesSnap.empty) {
    return null;
  }

  const sortedDocs = matchesSnap.docs.slice().sort((left, right) => {
    const leftData = left.data() || {};
    const rightData = right.data() || {};
    const leftTemp = leftData.tempAuth === true || leftData.authMode === 'local_otp_fallback' ? 1 : 0;
    const rightTemp = rightData.tempAuth === true || rightData.authMode === 'local_otp_fallback' ? 1 : 0;
    if (leftTemp !== rightTemp) {
      return leftTemp - rightTemp;
    }
    const createdDelta = timestampMillis(leftData.createdAt) - timestampMillis(rightData.createdAt);
    if (createdDelta !== 0) {
      return createdDelta;
    }
    const updatedDelta = timestampMillis(rightData.updatedAt) - timestampMillis(leftData.updatedAt);
    if (updatedDelta !== 0) {
      return updatedDelta;
    }
    return left.id.localeCompare(right.id);
  });

  const canonicalDoc = sortedDocs[0];
  await indexRef.set({
    uid: canonicalDoc.id,
    phone,
    collectionName,
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, {merge: true});
  return canonicalDoc;
}

function generateOtpCode() {
  return String(100000 + Math.floor(Math.random() * 900000));
}

function getWappiConfig() {
  return {
    token: String(process.env.WAPPI_TOKEN || ''),
    profileId: String(process.env.WAPPI_PROFILE_ID || ''),
    baseUrl: String(process.env.WAPPI_BASE_URL || 'https://wappi.pro'),
    sendPath: String(process.env.WAPPI_SEND_PATH || '/api/sync/message/send')
  };
}

async function sendOtpViaWappi(phone, code) {
  const {token, profileId, baseUrl, sendPath} = getWappiConfig();
  if (!token || !profileId) {
    throw new Error('wappi-not-configured');
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 8000);
  let response;
  try {
    response = await fetch(`${baseUrl}${sendPath}?profile_id=${profileId}`, {
      method: 'POST',
      signal: controller.signal,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': token,
        'accept': 'application/json'
      },
      body: JSON.stringify({
        recipient: `+${phone}`,
        body: `DOMLY код подтверждения: ${code}`
      })
    });
  } catch (error) {
    if (error?.name === 'AbortError') {
      throw new Error('wappi-timeout');
    }
    throw error;
  } finally {
    clearTimeout(timeout);
  }

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`wappi-${response.status}:${text}`);
  }
}

function getEpayCredentials(mode) {
  if (mode === 'payout') {
    return {
      clientId: EPAY_PAYOUT_CLIENT_ID,
      clientSecret: EPAY_PAYOUT_CLIENT_SECRET
    };
  }
  return {
    clientId: EPAY_INVOICE_CLIENT_ID,
    clientSecret: EPAY_INVOICE_CLIENT_SECRET
  };
}

function startOfDay(date = new Date()) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

function toIsoDate(date) {
  const value = startOfDay(date);
  return `${value.getFullYear()}-${String(value.getMonth() + 1).padStart(2, '0')}-${String(value.getDate()).padStart(2, '0')}`;
}

function parseIsoDate(dateValue) {
  if (dateValue instanceof Date) {
    return startOfDay(dateValue);
  }
  const raw = String(dateValue || '').trim();
  const match = raw.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (match) {
    return new Date(
      Number(match[1]),
      Number(match[2]) - 1,
      Number(match[3])
    );
  }
  return startOfDay(new Date(raw || Date.now()));
}

function bookingFloor(date = new Date()) {
  const day = startOfDay(date);
  return day < BOOKING_START_DATE ? BOOKING_START_DATE : day;
}

function assertBookingDateOpen(date) {
  if (startOfDay(date) < BOOKING_START_DATE) {
    throw new HttpsError(
      'failed-precondition',
      'Booking is available from 2026-09-02'
    );
  }
}

function parseMonthKey(monthValue) {
  const raw = String(monthValue || '').trim();
  const match = raw.match(/^(\d{4})-(\d{2})$/);
  if (match) {
    return new Date(
      Number(match[1]),
      Number(match[2]) - 1,
      1
    );
  }
  return new Date(raw || Date.now());
}

function addDays(date, days) {
  const copy = new Date(date);
  copy.setDate(copy.getDate() + days);
  return copy;
}

async function getPolicyConfig() {
  const snap = await db.collection('meta').doc('policies').get();
  const data = snap.exists ? (snap.data() || {}) : {};
  return {
    referralBonusAmount: Number(
      data.referralBonusAmount || DEFAULT_POLICY_CONFIG.referralBonusAmount
    ),
    defaultHouseThreshold: Number(
      data.defaultHouseThreshold || DEFAULT_POLICY_CONFIG.defaultHouseThreshold
    ),
    areaVerificationTolerance: Number(
      data.areaVerificationTolerance || DEFAULT_POLICY_CONFIG.areaVerificationTolerance
    ),
    cleanerReliableAreaThreshold: Number(
      data.cleanerReliableAreaThreshold || DEFAULT_POLICY_CONFIG.cleanerReliableAreaThreshold
    ),
    cleanerExpertAreaThreshold: Number(
      data.cleanerExpertAreaThreshold || DEFAULT_POLICY_CONFIG.cleanerExpertAreaThreshold
    ),
    cleanerLegendAreaThreshold: Number(
      data.cleanerLegendAreaThreshold || DEFAULT_POLICY_CONFIG.cleanerLegendAreaThreshold
    ),
    cleanerReliableBonusAmount: Number(
      data.cleanerReliableBonusAmount || DEFAULT_POLICY_CONFIG.cleanerReliableBonusAmount
    ),
    cleanerExpertBonusAmount: Number(
      data.cleanerExpertBonusAmount || DEFAULT_POLICY_CONFIG.cleanerExpertBonusAmount
    ),
    cleanerLegendBonusAmount: Number(
      data.cleanerLegendBonusAmount || DEFAULT_POLICY_CONFIG.cleanerLegendBonusAmount
    ),
    cleanerWeeklyAreaThreshold: Number(
      data.cleanerWeeklyAreaThreshold || DEFAULT_POLICY_CONFIG.cleanerWeeklyAreaThreshold
    ),
    cleanerWeeklyAreaBonusAmount: Number(
      data.cleanerWeeklyAreaBonusAmount || DEFAULT_POLICY_CONFIG.cleanerWeeklyAreaBonusAmount
    ),
    cleanerWeeklyAddonBonusThreshold1: Number(
      data.cleanerWeeklyAddonBonusThreshold1 || DEFAULT_POLICY_CONFIG.cleanerWeeklyAddonBonusThreshold1
    ),
    cleanerWeeklyAddonBonusAmount1: Number(
      data.cleanerWeeklyAddonBonusAmount1 || DEFAULT_POLICY_CONFIG.cleanerWeeklyAddonBonusAmount1
    ),
    cleanerWeeklyAddonBonusThreshold2: Number(
      data.cleanerWeeklyAddonBonusThreshold2 || DEFAULT_POLICY_CONFIG.cleanerWeeklyAddonBonusThreshold2
    ),
    cleanerWeeklyAddonBonusAmount2: Number(
      data.cleanerWeeklyAddonBonusAmount2 || DEFAULT_POLICY_CONFIG.cleanerWeeklyAddonBonusAmount2
    ),
    cleanerDailyIncome: Number(
      data.cleanerDailyIncome || DEFAULT_POLICY_CONFIG.cleanerDailyIncome
    ),
    cleanerSqmRate: Number(
      data.cleanerSqmRate || DEFAULT_POLICY_CONFIG.cleanerSqmRate
    ),
    cleanerWeeklyCashoutPercent: Number(
      data.cleanerWeeklyCashoutPercent || DEFAULT_POLICY_CONFIG.cleanerWeeklyCashoutPercent
    ),
    cleanerWeeklyCashoutCooldownDays: Number(
      data.cleanerWeeklyCashoutCooldownDays || DEFAULT_POLICY_CONFIG.cleanerWeeklyCashoutCooldownDays
    ),
    cleanerFullCashoutCooldownDays: Number(
      data.cleanerFullCashoutCooldownDays || DEFAULT_POLICY_CONFIG.cleanerFullCashoutCooldownDays
    ),
    packagePurchaseBonusEnabled:
      data.packagePurchaseBonusEnabled === true,
    packagePurchaseBonusAmount: Number(
      data.packagePurchaseBonusAmount || DEFAULT_POLICY_CONFIG.packagePurchaseBonusAmount
    ),
    cleaningMinutesPerSqm: Number(
      data.cleaningMinutesPerSqm || DEFAULT_POLICY_CONFIG.cleaningMinutesPerSqm
    ),
    cleaningBaseMinutes: Number(
      data.cleaningBaseMinutes || DEFAULT_POLICY_CONFIG.cleaningBaseMinutes
    ),
    cleaningMinMinutes: Number(
      data.cleaningMinMinutes || DEFAULT_POLICY_CONFIG.cleaningMinMinutes
    ),
    cleaningMaxMinutes: Number(
      data.cleaningMaxMinutes || DEFAULT_POLICY_CONFIG.cleaningMaxMinutes
    )
  };
}

function addMonths(date, months) {
  const copy = new Date(date);
  copy.setMonth(copy.getMonth() + months);
  return copy;
}

function startOfMonth(date = new Date()) {
  return new Date(date.getFullYear(), date.getMonth(), 1);
}

function endOfMonth(date = new Date()) {
  return new Date(date.getFullYear(), date.getMonth() + 1, 0, 23, 59, 59, 999);
}

function startOfWeek(date = new Date()) {
  const start = startOfDay(date);
  start.setDate(start.getDate() - (start.getDay() === 0 ? 6 : start.getDay() - 1));
  return start;
}

function weekKey(date = new Date()) {
  const start = startOfWeek(date);
  return `${start.getFullYear()}-${String(start.getMonth() + 1).padStart(2, '0')}-${String(start.getDate()).padStart(2, '0')}`;
}

function monthKey(date = new Date()) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`;
}

function daysLeftInMonth(date = new Date()) {
  const end = endOfMonth(date);
  return Math.max(Math.ceil((end.getTime() - date.getTime()) / (24 * 60 * 60 * 1000)), 0);
}

function startOfHour(date = new Date()) {
  return new Date(
    date.getFullYear(),
    date.getMonth(),
    date.getDate(),
    date.getHours()
  );
}

function parseSlotStartTime(timeRange = '') {
  const source = String(timeRange || '').trim();
  const match = source.match(/(\d{1,2}):(\d{2})/);
  if (!match) {
    return {hour: 10, minute: 0};
  }
  return {
    hour: Number(match[1]),
    minute: Number(match[2])
  };
}

function slotScheduledAt(slot) {
  if (slot.scheduledDateKey) {
    return buildScheduledDateTime(slot.scheduledDateKey, slot.time || '10:00 - 13:00');
  }
  const raw = slot.scheduledFor;
  const baseDate =
    raw instanceof admin.firestore.Timestamp ? raw.toDate() :
    raw instanceof Date ? raw :
    parseIsoDate(slot.scheduledDateKey || Date.now());
  const time = parseSlotStartTime(slot.time);
  return new Date(
    baseDate.getFullYear(),
    baseDate.getMonth(),
    baseDate.getDate(),
    time.hour,
    time.minute
  );
}

function buildScheduledDateTime(dateValue, timeValue) {
  const baseDate = parseIsoDate(dateValue);
  if (Number.isNaN(baseDate.getTime())) {
    throw new HttpsError('invalid-argument', 'Invalid date');
  }
  const time = parseSlotStartTime(timeValue || '10:00 - 13:00');
  return new Date(
    Date.UTC(
      baseDate.getFullYear(),
      baseDate.getMonth(),
      baseDate.getDate(),
      time.hour,
      time.minute
    ) -
      APP_TIMEZONE_OFFSET_MINUTES * 60 * 1000
  );
}

function ensureMinBookingLeadTime(targetDateTime) {
  const hoursUntil = (targetDateTime.getTime() - Date.now()) / 3600000;
  if (hoursUntil < 0) {
    throw new HttpsError(
      'failed-precondition',
      'Cleaning cannot be booked in the past'
    );
  }
  if (MIN_BOOKING_HOURS > 0 && hoursUntil < MIN_BOOKING_HOURS) {
    throw new HttpsError(
      'failed-precondition',
      `Cleaning can only be booked at least ${MIN_BOOKING_HOURS} hours in advance`
    );
  }
}

function slotConsumesVisit(slot) {
  const status = String(slot.status || '');
  if (status === 'completed') {
    return true;
  }
  if (status === 'canceled' && slot.cancellationPenaltyApplied === true) {
    return true;
  }
  return false;
}

function activeSlotStatus(status) {
  return ['pending_assignment', 'assigned', 'confirmed', 'start_pending', 'in_progress'].includes(String(status || ''));
}

function selectedSlotStatus(status) {
  return activeSlotStatus(status) || String(status || '') === 'pending_payment';
}

function normalizeMaybeDate(value) {
  if (value instanceof admin.firestore.Timestamp) {
    return value.toDate();
  }
  if (value instanceof Date) {
    return value;
  }
  if (value && typeof value.toDate === 'function') {
    return value.toDate();
  }
  if (typeof value === 'string') {
    const parsed = new Date(value);
    if (!Number.isNaN(parsed.getTime())) {
      return parsed;
    }
  }
  return null;
}

function daysBetween(from, to = new Date()) {
  return Math.max(Math.floor((to.getTime() - from.getTime()) / (24 * 60 * 60 * 1000)), 0);
}

function safeRate(count, total) {
  if (!total) {
    return 0;
  }
  return Number(count || 0) / Number(total || 1);
}

function resolveCleanerJoinDate(cleaner = {}) {
  const explicit = normalizeMaybeDate(cleaner.workStartDate || cleaner.joinDate || cleaner.createdAt || null);
  if (explicit) {
    return explicit;
  }
  const months = Number(cleaner.experienceMonths || 0);
  if (months > 0) {
    return addMonths(new Date(), -months);
  }
  return new Date();
}

function getOrderAddonValue(order = {}) {
  if (Number.isFinite(Number(order.addonTotalPrice))) {
    return Number(order.addonTotalPrice || 0);
  }
  if (Number.isFinite(Number(order.addonsPrice))) {
    return Number(order.addonsPrice || 0);
  }
  const addons = Array.isArray(order.addons) ? order.addons : [];
  return addons.length * 3000;
}

function classifyAddonBucket(order = {}) {
  const addonValue = getOrderAddonValue(order);
  if (addonValue >= HIGH_ADDON_THRESHOLD) {
    return 'high';
  }
  if (addonValue >= MEDIUM_ADDON_THRESHOLD) {
    return 'medium';
  }
  return 'regular';
}

function buildCleanerStatusProgressSnapshot({
  nextRule,
  totalCleanedArea
}) {
  if (!nextRule) {
    return {
      nextStatus: null,
      progress: 1,
      message: 'Максимальный статус достигнут.',
      remainingArea: 0,
      nextCareerBonusAmount: 0,
      nextAreaTarget: totalCleanedArea
    };
  }
  const progress = Math.min(totalCleanedArea / Math.max(nextRule.minArea, 1), 1);
  const remainingArea = Math.max(nextRule.minArea - totalCleanedArea, 0);
  return {
    nextStatus: nextRule.status,
    progress: Number(progress.toFixed(4)),
    message: `До статуса ${nextRule.label} осталось убрать ${Math.round(remainingArea)} м².`,
    remainingArea: Math.round(remainingArea),
    nextCareerBonusAmount: Number(nextRule.careerBonus || 0),
    nextAreaTarget: Number(nextRule.minArea || 0)
  };
}

function cleanerStatusRulesFromPolicies(policies) {
  return [
    {
      status: CLEANER_STATUSES.NEWBIE,
      label: CLEANER_STATUS_LABELS[CLEANER_STATUSES.NEWBIE],
      minArea: 0,
      careerBonus: 0
    },
    {
      status: CLEANER_STATUSES.RELIABLE,
      label: CLEANER_STATUS_LABELS[CLEANER_STATUSES.RELIABLE],
      minArea: Number(policies.cleanerReliableAreaThreshold || 12000),
      careerBonus: Number(policies.cleanerReliableBonusAmount || 100000)
    },
    {
      status: CLEANER_STATUSES.EXPERT,
      label: CLEANER_STATUS_LABELS[CLEANER_STATUSES.EXPERT],
      minArea: Number(policies.cleanerExpertAreaThreshold || 30000),
      careerBonus: Number(policies.cleanerExpertBonusAmount || 200000)
    },
    {
      status: CLEANER_STATUSES.LEGEND,
      label: CLEANER_STATUS_LABELS[CLEANER_STATUSES.LEGEND],
      minArea: Number(policies.cleanerLegendAreaThreshold || 65000),
      careerBonus: Number(policies.cleanerLegendBonusAmount || 500000)
    }
  ];
}

function dailyIncomeForCleaner(cleaner = {}, policies = DEFAULT_POLICY_CONFIG) {
  const override = Number(cleaner.dailyIncomeOverride || 0);
  if (override > 0) {
    return override;
  }
  return Number(policies.cleanerDailyIncome || 13500);
}

function cleanerSqmRateFromPolicies(policies = DEFAULT_POLICY_CONFIG) {
  const rate = Number(policies.cleanerSqmRate || DEFAULT_POLICY_CONFIG.cleanerSqmRate);
  return rate > 0 ? rate : DEFAULT_POLICY_CONFIG.cleanerSqmRate;
}

function sourceAreaSqm(source = {}) {
  return Number(source.area || source.areaSqm || source.form?.area || 0);
}

function cleanerIncomeForArea(area, policies = DEFAULT_POLICY_CONFIG) {
  const normalizedArea = Math.max(0, Number(area || 0));
  if (normalizedArea <= 0) {
    return 0;
  }
  return Math.round(normalizedArea * cleanerSqmRateFromPolicies(policies));
}

function cleanerIncomeForSource(source = {}, policies = DEFAULT_POLICY_CONFIG) {
  const fixedIncome = Number(source.cleanerIncome || 0);
  if (fixedIncome > 0) {
    return fixedIncome;
  }
  return cleanerIncomeForArea(sourceAreaSqm(source), policies);
}

function cleanerEarningPayload(source = {}, policies = DEFAULT_POLICY_CONFIG) {
  const area = sourceAreaSqm(source);
  const cleanerSqmRate = cleanerSqmRateFromPolicies(policies);
  return {
    area,
    cleanerSqmRate,
    cleanerIncome: cleanerIncomeForArea(area, policies)
  };
}

function normalizeBonusLedger(cleaner = {}) {
  return Array.isArray(cleaner.bonusLedger)
    ? cleaner.bonusLedger
        .filter((item) => item && typeof item === 'object')
        .map((item) => ({
          id: String(item.id || ''),
          type: String(item.type || 'manual'),
          label: String(item.label || ''),
          amount: Number(item.amount || 0),
          awardedAtMs: Number(item.awardedAtMs || 0),
          unlockAtMs: Number(item.unlockAtMs || item.awardedAtMs || 0)
        }))
        .filter((item) => item.id && item.amount > 0)
    : [];
}

function buildBonusBalances({
  cleaner = {},
  bonusLedger = [],
  totalBonusWithdrawn = 0,
  now = new Date()
}) {
  const manualBonusTotal = Number(cleaner.manualBonusTotal || 0);
  const sources = [
    ...bonusLedger.map((item) => ({...item, source: 'ledger'})),
    {
      id: 'manual_bonus_pool',
      type: 'manual',
      label: 'Ручные бонусы',
      amount: manualBonusTotal,
      awardedAtMs: 0,
      unlockAtMs: 0,
      source: 'manual'
    }
  ].sort((a, b) => a.unlockAtMs - b.unlockAtMs || a.awardedAtMs - b.awardedAtMs);

  let remainingWithdrawn = Math.max(Number(totalBonusWithdrawn || 0), 0);
  let lockedBonusAmount = 0;
  let unlockedBonusAmount = 0;
  let manualBonusBalance = 0;

  for (const item of sources) {
    const consumed = Math.min(item.amount, remainingWithdrawn);
    const remaining = Math.max(item.amount - consumed, 0);
    remainingWithdrawn -= consumed;
    if (remaining <= 0) {
      continue;
    }
    if (item.source === 'manual') {
      manualBonusBalance += remaining;
      unlockedBonusAmount += remaining;
      continue;
    }
    if (item.unlockAtMs > now.getTime()) {
      lockedBonusAmount += remaining;
    } else {
      unlockedBonusAmount += remaining;
    }
  }

  return {
    lockedBonusAmount,
    unlockedBonusAmount,
    manualBonusBalance,
    totalBonusAwarded: bonusLedger.reduce((sum, item) => sum + Number(item.amount || 0), 0) + manualBonusTotal
  };
}

async function getCleanerPerformanceSnapshot(cleanerId, cleaner = null, now = new Date()) {
  const [ordersSnap, directReviewsSnap, directComplaintsSnap, payoutsSnap] = await Promise.all([
    db.collection('cleaner_orders').where('cleanerId', '==', cleanerId).get(),
    db.collection('order_reviews').where('cleanerId', '==', cleanerId).get(),
    db.collection('complaints').where('cleanerId', '==', cleanerId).get(),
    db.collection('payouts').where('cleanerId', '==', cleanerId).get()
  ]);

  const orders = ordersSnap.docs.map((doc) => ({id: doc.id, ...doc.data()}));
  const completedOrders = orders.filter((order) => String(order.orderStatus || order.status || '') === 'completed');
  const canceledOrders = orders.filter((order) => String(order.orderStatus || order.status || '') === 'canceled');
  const completedOrderIds = new Set(completedOrders.map((order) => String(order.customerOrderId || order.sourceOrderId || order.id)));
  const orderIds = new Set(orders.map((order) => String(order.customerOrderId || order.sourceOrderId || order.id)));
  const currentWeekKey = weekKey(now);
  const currentMonthKey = monthKey(now);
  const currentDayKey = toIsoDate(now);
  const completedDayKeys = new Set();
  const monthWorkedDayKeys = new Set();
  const weekWorkedDayKeys = new Set();
  let totalCleanedArea = 0;
  let currentWeekCleanedArea = 0;
  let currentWeekAddonSales = 0;
  let todayCompletedCount = 0;
  let monthCompletedCount = 0;

  for (const order of completedOrders) {
    const orderArea = Number(order.area || 0);
    totalCleanedArea += orderArea;
    const completedAt =
      normalizeMaybeDate(order.completedAt || order.updatedAt || order.date || order.createdAt) || now;
    const completedDayKey = toIsoDate(completedAt);
    completedDayKeys.add(completedDayKey);
    if (monthKey(completedAt) === currentMonthKey) {
      monthWorkedDayKeys.add(completedDayKey);
      monthCompletedCount += 1;
    }
    if (weekKey(completedAt) === currentWeekKey) {
      weekWorkedDayKeys.add(completedDayKey);
      currentWeekCleanedArea += orderArea;
      currentWeekAddonSales += getOrderAddonValue(order);
    }
    if (completedDayKey === currentDayKey) {
      todayCompletedCount += 1;
    }
  }

  let rating30Sum = 0;
  let rating30Count = 0;
  let rating90Sum = 0;
  let rating90Count = 0;
  let currentRating = Number(cleaner?.rating || 0);
  let rating5Count = 0;
  let rating4Count = 0;
  let rating3Count = 0;
  let rating2Count = 0;
  let rating1Count = 0;
  let totalRatings = 0;

  const directReviewOrderIds = new Set();
  const processedReviewIds = new Set();
  for (const doc of directReviewsSnap.docs) {
    const review = doc.data();
    const orderId = String(review.orderId || doc.id);
    directReviewOrderIds.add(orderId);
    if (!completedOrderIds.has(orderId)) {
      continue;
    }
    const createdAt = normalizeMaybeDate(review.createdAt || review.reviewedAt || review.updatedAt) || now;
    const ageDays = daysBetween(createdAt, now);
    const rating = Number(review.rating || 0);
    if (rating <= 0) {
      continue;
    }
    totalRatings += 1;
    if (rating >= 5) rating5Count += 1;
    else if (rating >= 4) rating4Count += 1;
    else if (rating >= 3) rating3Count += 1;
    else if (rating >= 2) rating2Count += 1;
    else if (rating >= 1) rating1Count += 1;
    if (ageDays <= 90) {
      rating90Sum += rating;
      rating90Count += 1;
    }
    if (ageDays <= 30) {
      rating30Sum += rating;
      rating30Count += 1;
    }
    processedReviewIds.add(doc.id);
  }
  const missingReviewOrderIds = [...completedOrderIds].filter((orderId) => !directReviewOrderIds.has(orderId));
  for (let i = 0; i < missingReviewOrderIds.length; i += 10) {
    const chunk = missingReviewOrderIds.slice(i, i + 10);
    if (chunk.length === 0) {
      continue;
    }
    const fallbackSnap = await db.collection('order_reviews')
      .where('orderId', 'in', chunk)
      .get();
    for (const doc of fallbackSnap.docs) {
      if (processedReviewIds.has(doc.id)) {
        continue;
      }
      const review = doc.data();
      if (String(review.cleanerId || '').trim() && String(review.cleanerId).trim() !== cleanerId) {
        continue;
      }
      const createdAt = normalizeMaybeDate(review.createdAt || review.reviewedAt || review.updatedAt) || now;
      const ageDays = daysBetween(createdAt, now);
      const rating = Number(review.rating || 0);
      if (rating <= 0) {
        continue;
      }
      totalRatings += 1;
      if (rating >= 5) rating5Count += 1;
      else if (rating >= 4) rating4Count += 1;
      else if (rating >= 3) rating3Count += 1;
      else if (rating >= 2) rating2Count += 1;
      else if (rating >= 1) rating1Count += 1;
      if (ageDays <= 90) {
        rating90Sum += rating;
        rating90Count += 1;
      }
      if (ageDays <= 30) {
        rating30Sum += rating;
        rating30Count += 1;
      }
      processedReviewIds.add(doc.id);
    }
  }

  if (rating30Count > 0) {
    currentRating = Number((rating30Sum / rating30Count).toFixed(2));
  } else if (rating90Count > 0) {
    currentRating = Number((rating90Sum / rating90Count).toFixed(2));
  }

  let complaintsCount = 0;
  const directComplaintOrderIds = new Set();
  const processedComplaintIds = new Set();
  for (const doc of directComplaintsSnap.docs) {
    const complaint = doc.data();
    directComplaintOrderIds.add(String(complaint.orderId || ''));
    if (orderIds.has(String(complaint.orderId || ''))) {
      complaintsCount += 1;
    }
    processedComplaintIds.add(doc.id);
  }
  const missingComplaintOrderIds = [...orderIds].filter((orderId) => !directComplaintOrderIds.has(orderId));
  for (let i = 0; i < missingComplaintOrderIds.length; i += 10) {
    const chunk = missingComplaintOrderIds.slice(i, i + 10);
    if (chunk.length === 0) {
      continue;
    }
    const fallbackSnap = await db.collection('complaints')
      .where('orderId', 'in', chunk)
      .get();
    for (const doc of fallbackSnap.docs) {
      if (processedComplaintIds.has(doc.id)) {
        continue;
      }
      const complaint = doc.data();
      if (String(complaint.cleanerId || '').trim() && String(complaint.cleanerId).trim() !== cleanerId) {
        continue;
      }
      complaintsCount += 1;
      processedComplaintIds.add(doc.id);
    }
  }

  const joinDate = resolveCleanerJoinDate(cleaner || {});
  const tenureDays = daysBetween(joinDate, now);
  const payouts = payoutsSnap.docs.map((doc) => ({id: doc.id, ...doc.data()}));
  const settledPayouts = payouts.filter((payout) => {
    const status = String(payout.status || '').trim().toLowerCase();
    return ['completed', 'paid', 'approved', 'settled', 'success', 'succeeded'].includes(status);
  });
  const totalWithdrawn = settledPayouts.reduce(
    (sum, payout) => sum + Number(payout.net || payout.amount || 0),
    0
  );
  const totalBonusWithdrawn = settledPayouts.reduce(
    (sum, payout) => sum + Number(payout.bonusPortion || 0),
    0
  );
  const pendingPayouts = payouts.filter((payout) => {
    const status = String(payout.status || '').trim().toLowerCase();
    return ['pending', 'requested', 'processing', 'in_review'].includes(status);
  });
  const pendingWithdrawalAmount = pendingPayouts.reduce(
    (sum, payout) => sum + Number(payout.net || payout.amount || 0),
    0
  );
  const pendingBonusWithdrawalAmount = pendingPayouts.reduce(
    (sum, payout) => sum + Number(payout.bonusPortion || 0),
    0
  );

  return {
    currentRating,
    averageRating30d: rating30Count > 0 ? Number((rating30Sum / rating30Count).toFixed(2)) : currentRating,
    averageRating90d: rating90Count > 0 ? Number((rating90Sum / rating90Count).toFixed(2)) : currentRating,
    totalRatings,
    rating5Count,
    rating4Count,
    rating3Count,
    rating2Count,
    rating1Count,
    goodRatingsCount: rating5Count + rating4Count,
    badRatingsCount: rating3Count + rating2Count + rating1Count,
    completedOrdersCount: completedOrders.length,
    complaintsCount,
    cancellationCount: canceledOrders.length,
    complaintsRate: safeRate(complaintsCount, completedOrders.length),
    cancellationRate: safeRate(canceledOrders.length, Math.max(orders.length, 1)),
    tenureDays,
    totalCleanedArea,
    currentWeekCleanedArea,
    currentWeekAddonSales,
    completedDayCount: completedDayKeys.size,
    monthWorkedDayCount: monthWorkedDayKeys.size,
    weekWorkedDayCount: weekWorkedDayKeys.size,
    todayCompletedCount,
    monthCompletedCount,
    payouts,
    totalWithdrawn,
    totalBonusWithdrawn,
    pendingWithdrawalAmount,
    pendingBonusWithdrawalAmount
  };
}

function evaluateCleanerStatusFromSnapshot(snapshot, cleaner = {}, policies = DEFAULT_POLICY_CONFIG) {
  const rules = cleanerStatusRulesFromPolicies(policies);
  let resolved = rules[0];
  for (const rule of rules) {
    if (snapshot.totalCleanedArea >= rule.minArea) {
      resolved = rule;
    }
  }
  const currentIndex = rules.findIndex((rule) => rule.status === resolved.status);
  const nextRule = currentIndex >= 0 && currentIndex < rules.length - 1
    ? rules[currentIndex + 1]
    : null;
  const progress = buildCleanerStatusProgressSnapshot({
    nextRule,
    totalCleanedArea: snapshot.totalCleanedArea
  });
  return {
    status: resolved.status,
    label: resolved.label,
    nextStatus: progress.nextStatus,
    progress: progress.progress,
    progressText: progress.message,
    careerBonus: Number(resolved.careerBonus || 0),
    remainingAreaToNextStatus: progress.remainingArea,
    nextCareerBonusAmount: progress.nextCareerBonusAmount,
    nextCleanerStatusAreaTarget: progress.nextAreaTarget
  };
}

async function appendCleanerStatusHistory(cleanerId, oldStatus, newStatus, reason) {
  if (oldStatus === newStatus) {
    return;
  }
  await db.collection('cleaner_status_history').add({
    cleanerId,
    oldStatus: oldStatus || null,
    newStatus,
    reason,
    createdAt: admin.firestore.FieldValue.serverTimestamp()
  });
}

async function recalculateCleanerStatusInternal(cleanerId, options = {}) {
  const cleanerRef = db.collection('cleaners').doc(cleanerId);
  const cleanerSnap = options.cleanerSnap || await cleanerRef.get();
  if (!cleanerSnap.exists) {
    throw new HttpsError('not-found', 'Cleaner not found');
  }
  const cleaner = cleanerSnap.data();
  if (cleaner.autoStatusLocked === true) {
    return {
      ok: true,
      cleanerId,
      locked: true,
      status: cleaner.cleanerStatus || CLEANER_STATUSES.NEWBIE
    };
  }
  const now = options.now || new Date();
  const policies = await getPolicyConfig();
  const snapshot = await getCleanerPerformanceSnapshot(cleanerId, cleaner, now);
  const evaluated = evaluateCleanerStatusFromSnapshot(snapshot, cleaner, policies);
  const oldStatus = cleaner.cleanerStatus || CLEANER_STATUSES.NEWBIE;
  const awardedStatuses = new Set(
    Array.isArray(cleaner.careerBonusAwardedStatuses)
      ? cleaner.careerBonusAwardedStatuses.map((item) => String(item))
      : []
  );
  const weeklyAreaAwardedWeeks = new Set(
    Array.isArray(cleaner.weeklyAreaBonusAwardedWeeks)
      ? cleaner.weeklyAreaBonusAwardedWeeks.map((item) => String(item))
      : []
  );
  const weeklyAddonBonusAwardedByWeek =
    cleaner.weeklyAddonBonusAwardedByWeek &&
    typeof cleaner.weeklyAddonBonusAwardedByWeek === 'object'
      ? {...cleaner.weeklyAddonBonusAwardedByWeek}
      : {};
  const bonusLedger = normalizeBonusLedger(cleaner);
  const statusRules = cleanerStatusRulesFromPolicies(policies);
  let lastBonusLabel = null;
  const dailyIncome = dailyIncomeForCleaner(cleaner, policies);

  for (const rule of statusRules) {
    if (
      Number(rule.careerBonus || 0) > 0 &&
      snapshot.totalCleanedArea >= Number(rule.minArea || 0) &&
      !awardedStatuses.has(rule.status)
    ) {
      awardedStatuses.add(rule.status);
      bonusLedger.push({
        id: `career_${rule.status}`,
        type: 'career',
        label: `Карьерный бонус: ${rule.label}`,
        amount: Number(rule.careerBonus || 0),
        awardedAtMs: now.getTime(),
        unlockAtMs: now.getTime()
      });
      lastBonusLabel = `career:${rule.status}`;
    }
  }

  const currentWeekKey = weekKey(now);
  if (
    snapshot.currentWeekCleanedArea >= Number(policies.cleanerWeeklyAreaThreshold || 1300) &&
    !weeklyAreaAwardedWeeks.has(currentWeekKey)
  ) {
    weeklyAreaAwardedWeeks.add(currentWeekKey);
    bonusLedger.push({
      id: `weekly_area_${currentWeekKey}`,
      type: 'weekly_area',
      label: 'Еженедельный бонус',
      amount: Number(policies.cleanerWeeklyAreaBonusAmount || 5000),
      awardedAtMs: now.getTime(),
      unlockAtMs: addDays(now, 7).getTime()
    });
    lastBonusLabel = `weekly_area:${currentWeekKey}`;
  }

  const targetAddonBonus =
    snapshot.currentWeekAddonSales >= Number(policies.cleanerWeeklyAddonBonusThreshold2 || 50000)
      ? Number(policies.cleanerWeeklyAddonBonusAmount2 || 6000)
      : snapshot.currentWeekAddonSales >= Number(policies.cleanerWeeklyAddonBonusThreshold1 || 30000)
        ? Number(policies.cleanerWeeklyAddonBonusAmount1 || 4000)
        : 0;
  const awardedAddonBonus = Number(weeklyAddonBonusAwardedByWeek[currentWeekKey] || 0);
  if (targetAddonBonus > awardedAddonBonus) {
    const delta = targetAddonBonus - awardedAddonBonus;
    weeklyAddonBonusAwardedByWeek[currentWeekKey] = targetAddonBonus;
    bonusLedger.push({
      id: `weekly_addons_${currentWeekKey}_${targetAddonBonus}`,
      type: 'weekly_addons',
      label: 'Бонус за доп. услуги',
      amount: delta,
      awardedAtMs: now.getTime(),
      unlockAtMs: addDays(now, 7).getTime()
    });
    lastBonusLabel = `weekly_addons:${currentWeekKey}`;
  }

  const todayEarnings = snapshot.todayCompletedCount > 0 ? dailyIncome : 0;
  const weeklyEarnings = snapshot.weekWorkedDayCount * dailyIncome;
  const monthlyEarnings = snapshot.monthWorkedDayCount * dailyIncome;
  const baseEarned = snapshot.completedDayCount * dailyIncome;
  const bonusBalances = buildBonusBalances({
    cleaner,
    bonusLedger,
    totalBonusWithdrawn: snapshot.totalBonusWithdrawn,
    now
  });
  const baseWithdrawn = Math.max(snapshot.totalWithdrawn - snapshot.totalBonusWithdrawn, 0);
  const baseBalance = Math.max(baseEarned - baseWithdrawn, 0);
  const totalEarned = baseEarned + bonusBalances.totalBonusAwarded;
  const currentWalletBalance = Math.max(baseBalance + bonusBalances.unlockedBonusAmount + bonusBalances.lockedBonusAmount, 0);
  const pendingWithdrawalAmount = Math.max(Number(snapshot.pendingWithdrawalAmount || 0), 0);
  const availableBaseAndUnlockedBonus = Math.max(
    baseBalance + bonusBalances.unlockedBonusAmount - pendingWithdrawalAmount,
    0
  );
  const isSettledPayout = (item) => ['completed', 'paid', 'approved', 'settled', 'success', 'succeeded']
    .includes(String(item.status || '').trim().toLowerCase());
  const lastPartialPayoutAt = snapshot.payouts
    .filter((item) => isSettledPayout(item) && String(item.payoutType || 'partial') === 'partial')
    .map((item) => normalizeMaybeDate(item.createdAt))
    .filter(Boolean)
    .sort((a, b) => b - a)[0] || null;
  const lastFullPayoutAt = snapshot.payouts
    .filter((item) => isSettledPayout(item) && String(item.payoutType || '') === 'full')
    .map((item) => normalizeMaybeDate(item.createdAt))
    .filter(Boolean)
    .sort((a, b) => b - a)[0] || resolveCleanerJoinDate(cleaner || {});
  const availableWeeklyCashoutAmount =
    !lastPartialPayoutAt ||
    daysBetween(lastPartialPayoutAt, now) >= Number(policies.cleanerWeeklyCashoutCooldownDays || 7)
      ? Math.round(availableBaseAndUnlockedBonus * (Number(policies.cleanerWeeklyCashoutPercent || 30) / 100))
      : 0;
  const availableFullCashoutAmount =
    daysBetween(lastFullPayoutAt, now) >= Number(policies.cleanerFullCashoutCooldownDays || 30)
      ? availableBaseAndUnlockedBonus
      : 0;
  const availableWithdrawalAmount =
    availableFullCashoutAmount > 0 ? availableFullCashoutAmount : availableWeeklyCashoutAmount;
  await cleanerRef.set({
    cleanerStatus: evaluated.status,
    cleanerStatusLabel: evaluated.label,
    nextCleanerStatus: evaluated.nextStatus,
    cleanerStatusProgress: evaluated.progress,
    cleanerStatusProgressText: evaluated.progressText,
    remainingAreaToNextStatus: evaluated.remainingAreaToNextStatus,
    nextCareerBonusAmount: evaluated.nextCareerBonusAmount,
    nextCleanerStatusAreaTarget: evaluated.nextCleanerStatusAreaTarget,
    currentRating: snapshot.currentRating,
    averageRating30d: snapshot.averageRating30d,
    averageRating90d: snapshot.averageRating90d,
    totalRatings: snapshot.totalRatings,
    rating5Count: snapshot.rating5Count,
    rating4Count: snapshot.rating4Count,
    rating3Count: snapshot.rating3Count,
    rating2Count: snapshot.rating2Count,
    rating1Count: snapshot.rating1Count,
    goodRatingsCount: snapshot.goodRatingsCount,
    badRatingsCount: snapshot.badRatingsCount,
    completedOrdersCount: snapshot.completedOrdersCount,
    complaintsCount: snapshot.complaintsCount,
    cancellationCount: snapshot.cancellationCount,
    totalCleanedArea: snapshot.totalCleanedArea,
    currentWeekCleanedArea: snapshot.currentWeekCleanedArea,
    currentWeekAddonSales: snapshot.currentWeekAddonSales,
    dailyIncome: dailyIncome,
    todayEarnings,
    weeklyEarnings,
    monthlyEarnings,
    baseEarned,
    totalEarned,
    totalWithdrawn: snapshot.totalWithdrawn,
    totalBonusWithdrawn: snapshot.totalBonusWithdrawn,
    pendingWithdrawalAmount,
    pendingBonusWithdrawalAmount: snapshot.pendingBonusWithdrawalAmount,
    currentWalletBalance,
    lockedBonusAmount: bonusBalances.lockedBonusAmount,
    unlockedBonusAmount: bonusBalances.unlockedBonusAmount,
    availableWeeklyCashoutAmount,
    availableFullCashoutAmount,
    availableWithdrawalAmount,
    manualBonusBalance: bonusBalances.manualBonusBalance,
    bonusLedger,
    careerBonusAwardedStatuses: [...awardedStatuses],
    weeklyAreaBonusAwardedWeeks: [...weeklyAreaAwardedWeeks],
    weeklyAddonBonusAwardedByWeek,
    lastBonusLabel,
    lastWalletEvaluatedAt: admin.firestore.FieldValue.serverTimestamp(),
    statusEvaluatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, {merge: true});
  await appendCleanerStatusHistory(
    cleanerId,
    oldStatus,
    evaluated.status,
    `area=${snapshot.totalCleanedArea};weekArea=${snapshot.currentWeekCleanedArea};weekAddons=${snapshot.currentWeekAddonSales};bonus=${lastBonusLabel || 'none'}`
  );
  return {
    ok: true,
    cleanerId,
    ...evaluated,
    totalCleanedArea: snapshot.totalCleanedArea,
    currentWalletBalance,
    availableWithdrawalAmount,
    availableWeeklyCashoutAmount,
    availableFullCashoutAmount
  };
}

function cleaningDurationPolicyFrom(policies = DEFAULT_POLICY_CONFIG) {
  const minutesPerSqm = Number(policies.cleaningMinutesPerSqm);
  const baseMinutes = Number(policies.cleaningBaseMinutes);
  const minMinutes = Number(policies.cleaningMinMinutes);
  const maxMinutes = Number(policies.cleaningMaxMinutes);
  return {
    minutesPerSqm: Number.isFinite(minutesPerSqm) && minutesPerSqm > 0
      ? minutesPerSqm
      : DEFAULT_POLICY_CONFIG.cleaningMinutesPerSqm,
    baseMinutes: Number.isFinite(baseMinutes) && baseMinutes >= 0
      ? baseMinutes
      : DEFAULT_POLICY_CONFIG.cleaningBaseMinutes,
    minMinutes: Number.isFinite(minMinutes) && minMinutes > 0
      ? minMinutes
      : DEFAULT_POLICY_CONFIG.cleaningMinMinutes,
    maxMinutes: Number.isFinite(maxMinutes) && maxMinutes > 0
      ? maxMinutes
      : DEFAULT_POLICY_CONFIG.cleaningMaxMinutes
  };
}

function estimateCleaningDuration(area = 0, policies = DEFAULT_POLICY_CONFIG) {
  const size = Number(area || 0);
  if (size <= 0) {
    return 2;
  }
  const minutes = estimateCleaningDurationMinutes(size, policies);
  return Math.round((minutes / 60) * 10) / 10;
}

function estimateCleaningDurationMinutes(area = 0, policies = DEFAULT_POLICY_CONFIG) {
  const size = Number(area || 0);
  const policy = cleaningDurationPolicyFrom(policies);
  if (size <= 0) {
    return Math.round(policy.minMinutes);
  }
  const calculated = Math.round(size * policy.minutesPerSqm + policy.baseMinutes);
  const maxMinutes = Math.max(policy.maxMinutes, policy.minMinutes);
  return Math.round(Math.min(Math.max(calculated, policy.minMinutes), maxMinutes));
}

function countOnsiteAddons(order = {}) {
  const detailed = normalizeDetailedAddons(order.addonsDetailed);
  if (detailed.length > 0) {
    return detailed.length;
  }
  const addons = Array.isArray(order.addons) ? order.addons : [];
  return addons.length;
}

function addonDurationMinutes(order = {}) {
  const detailed = normalizeDetailedAddons(order.addonsDetailed);
  if (detailed.length === 0) {
    return 0;
  }
  const catalog = buildAddonPricingCatalog(order.pricing || {});
  return detailed.reduce((sum, item) => {
    const explicit = Number(item.durationMinutes || 0);
    if (Number.isFinite(explicit) && explicit > 0) {
      return sum + explicit;
    }
    const pricingItem = catalog[item.key] || {};
    const configured = Number(pricingItem.durationMinutes || 0);
    if (Number.isFinite(configured) && configured > 0) {
      return sum + configured * Math.max(1, Number(item.quantity || 1));
    }
    const quantity = Math.max(1, Number(item.quantity || 1));
    return sum + (quantity * ADDON_BUFFER_MINUTES_PER_ITEM);
  }, 0);
}

function addAddonBuffer(durationMinutes = 0, addonCount = 0) {
  const normalizedCount = Math.max(0, Number(addonCount || 0));
  return Number(durationMinutes || 0) + (normalizedCount * ADDON_BUFFER_MINUTES_PER_ITEM);
}

function buildSchedulerMetrics(order = {}, policies = DEFAULT_POLICY_CONFIG) {
  const estimatedDurationMinutes = Number(
    order.estimatedDurationMinutes ||
    Math.round(Number(order.estimatedDurationHours || 0) * 60) ||
    estimateCleaningDurationMinutes(order.area || 0, policies)
  );
  const addonCount = countOnsiteAddons(order);
  const detailedAddonMinutes = addonDurationMinutes(order);
  const addonBufferMinutes = Math.max(
    Number(order.addonBufferMinutes || 0),
    detailedAddonMinutes > 0 ? detailedAddonMinutes : addAddonBuffer(0, addonCount)
  );
  const travelTimeMinutes = Math.max(
    Number(order.travelTimeMinutes || 0),
    DEFAULT_TRAVEL_TIME_MINUTES
  );
  const totalDurationMinutes = Math.max(
    Number(order.totalDurationMinutes || 0),
    estimatedDurationMinutes + addonBufferMinutes + travelTimeMinutes
  );
  return {
    estimatedDurationMinutes,
    estimatedDurationHours: Number((estimatedDurationMinutes / 60).toFixed(1)),
    addonCount,
    addonBufferMinutes,
    travelTimeMinutes,
    totalDurationMinutes,
    totalDurationHours: Number((totalDurationMinutes / 60).toFixed(1))
  };
}

function parseTimeRange(timeRange = '') {
  const source = String(timeRange || '').trim();
  const matches = [...source.matchAll(/(\d{1,2}):(\d{2})/g)];
  if (matches.length >= 2) {
    const start = Number(matches[0][1]) * 60 + Number(matches[0][2]);
    const end = Number(matches[1][1]) * 60 + Number(matches[1][2]);
    return {
      startMinutes: start,
      endMinutes: end > start ? end : start + 180
    };
  }
  const fallback = parseSlotStartTime(source);
  const start = fallback.hour * 60 + fallback.minute;
  return {
    startMinutes: start,
    endMinutes: start + 180
  };
}

function buildTimeRangeForDuration(timeRange = '', durationMinutes = 0) {
  const parsed = parseTimeRange(timeRange || '10:00 - 13:00');
  const normalizedDuration = Math.max(60, Math.round(Number(durationMinutes || 0)));
  return `${formatTimeMinutes(parsed.startMinutes)} - ${formatTimeMinutes(parsed.startMinutes + normalizedDuration)}`;
}

function timeRangesOverlap(left, right) {
  return left.startMinutes < right.endMinutes && right.startMinutes < left.endMinutes;
}

function normalizeCleanerAvailabilityStatus(value) {
  const normalized = String(value || '').trim().toLowerCase();
  switch (normalized) {
    case CLEANER_AVAILABILITY_STATUSES.OFFLINE:
    case CLEANER_AVAILABILITY_STATUSES.ONLINE_READY:
    case CLEANER_AVAILABILITY_STATUSES.AT_HOME_READY:
    case CLEANER_AVAILABILITY_STATUSES.BUSY:
    case CLEANER_AVAILABILITY_STATUSES.ON_WAY_TO_CLIENT:
    case CLEANER_AVAILABILITY_STATUSES.ARRIVED:
    case CLEANER_AVAILABILITY_STATUSES.CLEANING:
    case CLEANER_AVAILABILITY_STATUSES.BREAK:
    case CLEANER_AVAILABILITY_STATUSES.FINISHED:
      return normalized;
    case 'active':
    case 'available':
    case 'online':
      return CLEANER_AVAILABILITY_STATUSES.ONLINE_READY;
    default:
      return CLEANER_AVAILABILITY_STATUSES.ONLINE_READY;
  }
}

function cleanerDailyAreaLimit(cleaner = {}) {
  const value = Number(
    cleaner.dailyAreaLimit ||
    cleaner.daily_area_limit ||
    cleaner.dailyAreaLimitSqm ||
    DAILY_AREA_LIMIT_SQM
  );
  if (!Number.isFinite(value) || value <= 0) {
    return DAILY_AREA_LIMIT_SQM;
  }
  return Math.max(1, Math.round(value));
}

function cleanerDailyLimitMinutes(cleaner = {}) {
  const hours = Number(
    cleaner.dailyHourLimit ||
    cleaner.daily_hour_limit ||
    cleaner.dailyWorkLimitHours ||
    cleaner.daily_work_limit_hours ||
    (DAILY_SCHEDULE_LIMIT_MINUTES / 60)
  );
  if (!Number.isFinite(hours) || hours <= 0) {
    return DAILY_SCHEDULE_LIMIT_MINUTES;
  }
  return Math.round(hours * 60);
}

function extractLatLng(source = {}) {
  if (!source || typeof source !== 'object') {
    return null;
  }
  const directLat = Number(source.lat ?? source.latitude ?? source.addressLat);
  const directLng = Number(source.lng ?? source.longitude ?? source.addressLng);
  if (Number.isFinite(directLat) && Number.isFinite(directLng)) {
    return {lat: directLat, lng: directLng};
  }
  const current = source.currentLocation && typeof source.currentLocation === 'object'
    ? source.currentLocation
    : null;
  if (current) {
    const currentLat = Number(current.lat ?? current.latitude);
    const currentLng = Number(current.lng ?? current.longitude);
    if (Number.isFinite(currentLat) && Number.isFinite(currentLng)) {
      return {lat: currentLat, lng: currentLng};
    }
  }
  const home = source.homeLocation && typeof source.homeLocation === 'object'
    ? source.homeLocation
    : null;
  if (home) {
    const homeLat = Number(home.lat ?? home.latitude);
    const homeLng = Number(home.lng ?? home.longitude);
    if (Number.isFinite(homeLat) && Number.isFinite(homeLng)) {
      return {lat: homeLat, lng: homeLng};
    }
  }
  return null;
}

function haversineKm(left, right) {
  if (!left || !right) {
    return null;
  }
  const toRad = (value) => (value * Math.PI) / 180;
  const dLat = toRad(right.lat - left.lat);
  const dLng = toRad(right.lng - left.lng);
  const lat1 = toRad(left.lat);
  const lat2 = toRad(right.lat);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1) * Math.cos(lat2) *
      Math.sin(dLng / 2) * Math.sin(dLng / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return 6371 * c;
}

function estimateTravelMinutes({cleaner = {}, scope = {}, dayAssignments = []}) {
  const cleanerPoint = extractLatLng(cleaner);
  const scopePoint = extractLatLng(scope);
  const sameComplex =
    String(scope.residentialComplex || '').trim() !== '' &&
    String(scope.residentialComplex || '').trim().toLowerCase() ===
      String(cleaner.residentialComplex || '').trim().toLowerCase();
  const sameCluster =
    String(scope.clusterName || '').trim() !== '' &&
    String(scope.clusterName || '').trim().toLowerCase() ===
      String(cleaner.clusterName || '').trim().toLowerCase();
  if (cleanerPoint && scopePoint) {
    const km = haversineKm(cleanerPoint, scopePoint);
    if (km != null) {
      return Math.max(8, Math.round((km / 28) * 60) + 5);
    }
  }
  if (sameComplex) {
    return 10;
  }
  if (sameCluster) {
    return 18;
  }
  if (dayAssignments.length > 0) {
    return Math.max(DEFAULT_TRAVEL_TIME_MINUTES, 25);
  }
  return Math.max(DEFAULT_TRAVEL_TIME_MINUTES, 30);
}

function assignmentTypeForDate(dateValue) {
  const targetDate = startOfDay(
    dateValue instanceof Date ? dateValue : new Date(dateValue)
  );
  const today = startOfDay();
  const tomorrow = addDays(today, 1);
  if (toIsoDate(targetDate) === toIsoDate(today)) {
    return 'today';
  }
  if (toIsoDate(targetDate) === toIsoDate(tomorrow)) {
    return 'tomorrow';
  }
  return 'future';
}

function resolveScopeScheduledAt(scope = {}) {
  if (scope.scheduledDateKey) {
    return buildScheduledDateTime(scope.scheduledDateKey, scope.time || '10:00 - 13:00');
  }
  const rawDate =
    scope.scheduledFor instanceof admin.firestore.Timestamp
      ? scope.scheduledFor.toDate()
      : scope.date instanceof admin.firestore.Timestamp
        ? scope.date.toDate()
        : scope.scheduledFor || scope.date || scope.createdAt || new Date();
  return buildScheduledDateTime(rawDate, scope.time || '10:00 - 13:00');
}

function buildAssignmentRange(source = {}) {
  const parsed = parseTimeRange(source.time || '10:00 - 13:00');
  const totalDurationMinutes = Math.max(
    Number(source.totalDurationMinutes || 0),
    Number(source.estimatedDurationMinutes || 0),
    estimateCleaningDurationMinutes(source.area || source.form?.area || 0)
  );
  return {
    startMinutes: parsed.startMinutes,
    endMinutes: parsed.startMinutes + Math.max(totalDurationMinutes, 60)
  };
}

function confirmationDeadlineForDate(targetDate) {
  const base = startOfDay(targetDate);
  return new Date(
    base.getFullYear(),
    base.getMonth(),
    base.getDate(),
    TOMORROW_CONFIRMATION_DEADLINE_HOUR,
    0,
    0,
    0
  );
}

function cleanerStatusEligibleForAssignment(cleaner = {}, assignmentType = 'today') {
  const status = normalizeCleanerAvailabilityStatus(
    cleaner.availabilityStatus || cleaner.operationalStatus || cleaner.status
  );
  if (assignmentType === 'today') {
    return [
      CLEANER_AVAILABILITY_STATUSES.ONLINE_READY,
      CLEANER_AVAILABILITY_STATUSES.AT_HOME_READY
    ].includes(status);
  }
  return ![
    CLEANER_AVAILABILITY_STATUSES.BUSY,
    CLEANER_AVAILABILITY_STATUSES.ON_WAY_TO_CLIENT,
    CLEANER_AVAILABILITY_STATUSES.ARRIVED,
    CLEANER_AVAILABILITY_STATUSES.CLEANING
  ].includes(status);
}

function cleanerWorksOnDate(cleaner = {}, targetDate = new Date()) {
  const schedule = cleaner.workSchedule;
  if (!schedule || typeof schedule !== 'object') {
    return true;
  }
  const weekday = targetDate.getDay();
  const isoWeekday = weekday === 0 ? 7 : weekday;
  const candidates = [
    schedule[String(weekday)],
    schedule[String(isoWeekday)],
    schedule[['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'][weekday]],
    Array.isArray(schedule) ? schedule[weekday] : null
  ].filter(Boolean);
  if (candidates.length === 0) {
    return true;
  }
  const entry = candidates[0];
  if (typeof entry === 'boolean') {
    return entry;
  }
  if (typeof entry === 'object') {
    if (entry.enabled === false || entry.isWorking === false) {
      return false;
    }
    return true;
  }
  return true;
}

function normalizeServiceAreaMatchToken(value) {
  return String(value || '')
    .trim()
    .toLowerCase()
    .replace(/\s+/g, ' ');
}

function serviceAreaMatchTokens(value) {
  if (!Array.isArray(value)) {
    return [];
  }
  const tokens = [];
  for (const raw of value) {
    if (raw && typeof raw === 'object' && !Array.isArray(raw)) {
      tokens.push(
        raw.id,
        raw.zoneId,
        raw.serviceAreaId,
        raw.houseId,
        raw.title,
        raw.name,
        raw.label,
        raw.serviceArea,
        raw.clusterName,
        raw.residentialComplex
      );
    } else {
      tokens.push(raw);
    }
  }
  return tokens
    .map(normalizeServiceAreaMatchToken)
    .filter(Boolean);
}

function uniqueServiceAreaTokens(values = []) {
  return Array.from(new Set(
    values
      .map(normalizeServiceAreaMatchToken)
      .filter(Boolean)
  ));
}

function hasCityWideServiceAreaToken(tokens = [], scope = {}) {
  const scopeCity = resolveCityFromSource(scope);
  if (!scopeCity) {
    return false;
  }
  return tokens.some((token) => normalizeCityName(token) === scopeCity);
}

function serviceAreaMatches(cleaner = {}, scope = {}) {
  const areas = serviceAreaMatchTokens(cleaner.serviceAreas);
  const areaIds = serviceAreaMatchTokens(cleaner.serviceAreaIds);
  if (areas.length === 0 && areaIds.length === 0) {
    return false;
  }
  if (hasCityWideServiceAreaToken([...areas, ...areaIds], scope)) {
    return true;
  }

  const scopeIds = uniqueServiceAreaTokens([
    scope.serviceAreaId,
    scope.zoneId,
    scope.coverageZoneId,
    scope.coverageAreaId,
    scope.districtId,
    scope.clusterId,
    scope.houseId,
    scope.homeId,
    ...serviceAreaMatchTokens(scope.serviceAreaIds),
    ...serviceAreaMatchTokens(scope.zoneIds),
    ...serviceAreaMatchTokens(scope.coverageZoneIds),
    ...serviceAreaMatchTokens(scope.coverageAreaIds),
    ...serviceAreaMatchTokens(scope.districtIds),
    ...serviceAreaMatchTokens(scope.clusterIds),
    ...serviceAreaMatchTokens(scope.matchedServiceAreaIds),
    ...serviceAreaMatchTokens(scope.matchedZoneIds)
  ]);
  const scopeAreas = uniqueServiceAreaTokens([
    scope.serviceArea,
    scope.serviceAreaName,
    scope.serviceAreaId,
    scope.zoneName,
    scope.zoneId,
    scope.coverageZoneName,
    scope.coverageAreaName,
    scope.district,
    scope.districtName,
    scope.clusterName,
    scope.residentialComplex,
    scope.houseId,
    scope.homeId,
    ...serviceAreaMatchTokens(scope.serviceAreas),
    ...serviceAreaMatchTokens(scope.zoneNames),
    ...serviceAreaMatchTokens(scope.coverageZoneNames),
    ...serviceAreaMatchTokens(scope.coverageAreaNames),
    ...serviceAreaMatchTokens(scope.districtNames),
    ...serviceAreaMatchTokens(scope.clusterNames),
    ...serviceAreaMatchTokens(scope.matchedServiceAreas),
    ...serviceAreaMatchTokens(scope.matchedZoneNames)
  ]);
  if (scopeIds.length === 0 && scopeAreas.length === 0) {
    return false;
  }

  if (areaIds.some((areaId) => scopeIds.includes(areaId) || scopeAreas.includes(areaId))) {
    return true;
  }
  return areas.some((area) => scopeAreas.includes(area) || scopeIds.includes(area));
}

function filterCleanersByServiceArea(cleaners = [], scope = {}) {
  return cleaners.filter((cleaner) => serviceAreaMatches(cleaner, scope));
}

function scopeHasServiceAreaIdentity(scope = {}) {
  return uniqueServiceAreaTokens([
    scope.serviceAreaId,
    scope.zoneId,
    scope.coverageZoneId,
    scope.coverageAreaId,
    scope.districtId,
    scope.clusterId,
    scope.serviceArea,
    scope.serviceAreaName,
    scope.zoneName,
    scope.coverageZoneName,
    scope.coverageAreaName,
    scope.district,
    scope.districtName,
    scope.clusterName,
    scope.residentialComplex
  ]).length > 0;
}

function mergeServiceAreaIdentity(target = {}, source = {}) {
  const result = {...target};
  for (const key of [
    'serviceArea',
    'serviceAreaName',
    'serviceAreaId',
    'zoneId',
    'zoneName',
    'coverageZoneId',
    'coverageZoneName',
    'coverageAreaId',
    'coverageAreaName',
    'districtId',
    'district',
    'districtName',
    'clusterId',
    'clusterName',
    'residentialComplex'
  ]) {
    if (!result[key] && source[key]) {
      result[key] = source[key];
    }
  }
  return result;
}

function geoPolygonFrom(value) {
  if (!Array.isArray(value)) {
    return [];
  }
  return value
    .map((point) => ({
      lat: Number(point?.lat),
      lng: Number(point?.lng)
    }))
    .filter((point) => Number.isFinite(point.lat) && Number.isFinite(point.lng));
}

function geoPointInPolygon({lat, lng, polygon}) {
  if (!Array.isArray(polygon) || polygon.length < 3) {
    return false;
  }
  let inside = false;
  let j = polygon.length - 1;
  for (let i = 0; i < polygon.length; i += 1) {
    const yi = Number(polygon[i].lat);
    const xi = Number(polygon[i].lng);
    const yj = Number(polygon[j].lat);
    const xj = Number(polygon[j].lng);
    const denominator = yj - yi === 0 ? 1 : yj - yi;
    const intersects = ((yi > lat) !== (yj > lat)) &&
      (lng < ((xj - xi) * (lat - yi)) / denominator + xi);
    if (intersects) {
      inside = !inside;
    }
    j = i;
  }
  return inside;
}

function formatTimeMinutes(totalMinutes) {
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  return `${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}`;
}

function buildCandidateTimeSlots(durationMinutes) {
  const normalizedDurationMinutes = Math.round(Number(durationMinutes || 120));
  const slots = [];
  for (
    let startMinutes = MANUAL_BOOKING_START_MINUTE;
    startMinutes + normalizedDurationMinutes <= MANUAL_BOOKING_END_MINUTE;
    startMinutes += MANUAL_BOOKING_STEP_MINUTES
  ) {
    const endMinutes = startMinutes + normalizedDurationMinutes;
    slots.push({
      startMinutes,
      endMinutes,
      time: `${formatTimeMinutes(startMinutes)} - ${formatTimeMinutes(endMinutes)}`,
      totalDurationMinutes: normalizedDurationMinutes
    });
  }
  return slots;
}

async function getCleanerScheduledSlots(cleanerId, referenceDate, options = {}) {
  const targetDateKey = toIsoDate(referenceDate);
  const excludeSlotId = options.excludeSlotId || null;
  const [assignedSnap, preferredSnap] = await Promise.all([
    db.collection('schedule_slots')
      .where('cleanerId', '==', cleanerId)
      .where('scheduledDateKey', '==', targetDateKey)
      .get(),
    db.collection('schedule_slots')
      .where('preferredCleanerId', '==', cleanerId)
      .where('scheduledDateKey', '==', targetDateKey)
      .get()
  ]);
  const docsById = new Map();
  for (const doc of [...assignedSnap.docs, ...preferredSnap.docs]) {
    docsById.set(doc.id, doc);
  }

  return [...docsById.values()]
    .filter((doc) => doc.id !== excludeSlotId)
    .map((doc) => ({id: doc.id, ...doc.data()}))
    .filter((slot) => activeSlotStatus(slot.status))
    .map((slot) => ({
      id: slot.id,
      time: String(slot.time || '10:00 - 13:00'),
      range: buildAssignmentRange(slot),
      area: Number(slot.area || 0),
      hours: Number(slot.totalDurationHours || slot.estimatedDurationHours || estimateCleaningDuration(slot.area || 0)),
      minutes: Number(slot.totalDurationMinutes || Math.round(Number(slot.totalDurationHours || slot.estimatedDurationHours || estimateCleaningDuration(slot.area || 0)) * 60))
    }));
}

async function calculateDailyScheduleInternal(cleanerId, date) {
  const targetDate = startOfDay(new Date(date));
  if (!cleanerId || Number.isNaN(targetDate.getTime())) {
    throw new HttpsError('invalid-argument', 'cleanerId and valid date required');
  }
  const slotsSnap = await db.collection('schedule_slots')
    .where('cleanerId', '==', cleanerId)
    .where('scheduledDateKey', '==', toIsoDate(targetDate))
    .get();
  const slots = slotsSnap.docs
    .map((doc) => ({id: doc.id, ...doc.data()}))
    .filter((slot) => String(slot.status || '') !== 'canceled')
    .sort((a, b) => slotScheduledAt(a).getTime() - slotScheduledAt(b).getTime());

  let occupiedMinutes = 0;
  let totalArea = 0;
  let totalAddonCount = 0;
  const items = slots.map((slot) => {
    const metrics = buildSchedulerMetrics(slot);
    occupiedMinutes += metrics.totalDurationMinutes;
    totalArea += Number(slot.area || 0);
    totalAddonCount += metrics.addonCount;
    return {
      id: slot.id,
      time: String(slot.time || ''),
      customerName: String(slot.customerName || slot.client || 'Клиент'),
      address: String(slot.address || slot.residentialComplex || ''),
      area: Number(slot.area || 0),
      status: String(slot.status || ''),
      addonCount: metrics.addonCount,
      estimatedDurationMinutes: metrics.estimatedDurationMinutes,
      addonBufferMinutes: metrics.addonBufferMinutes,
      travelTimeMinutes: metrics.travelTimeMinutes,
      totalDurationMinutes: metrics.totalDurationMinutes,
      canArriveEarlier: metrics.addonCount === 0 && metrics.totalDurationMinutes <= 180
    };
  });

  return {
    ok: true,
    cleanerId,
    date: toIsoDate(targetDate),
    items,
    summary: {
      ordersCount: items.length,
      totalArea,
      totalAddonCount,
      occupiedMinutes,
      occupiedHours: Number((occupiedMinutes / 60).toFixed(1)),
      limitArea: DAILY_AREA_LIMIT_SQM,
      remainingArea: Math.max(DAILY_AREA_LIMIT_SQM - totalArea, 0),
      limitMinutes: DAILY_SCHEDULE_LIMIT_MINUTES,
      limitHours: Number((DAILY_SCHEDULE_LIMIT_MINUTES / 60).toFixed(1)),
      remainingMinutes: Math.max(DAILY_SCHEDULE_LIMIT_MINUTES - occupiedMinutes, 0),
      overbooked:
        occupiedMinutes > DAILY_SCHEDULE_LIMIT_MINUTES ||
        totalArea > DAILY_AREA_LIMIT_SQM
    }
  };
}

async function resolveSubscriptionSchedulingContext(subscriptionId) {
  const subscriptionRef = db.collection('subscriptions').doc(subscriptionId);
  const subscriptionSnap = await subscriptionRef.get();
  if (!subscriptionSnap.exists) {
    throw new HttpsError('not-found', 'Subscription not found');
  }

  const subscription = {id: subscriptionSnap.id, ...subscriptionSnap.data()};
  let sourceOrder = null;
  if (subscription.sourceOrderId) {
    const orderSnap = await db.collection('customer_orders').doc(String(subscription.sourceOrderId)).get();
    if (orderSnap.exists) {
      sourceOrder = {id: orderSnap.id, ...orderSnap.data()};
    }
  }

  const mergedOrder = {
    ...sourceOrder,
    ...subscription,
    id: subscription.sourceOrderId || subscription.id
  };
  const cluster = await detectClusterForOrder(mergedOrder);
  const policies = await getPolicyConfig();
  const area = Number(subscription.area || sourceOrder?.area || 0);
  const durationHours = Number(
    subscription.estimatedDurationHours ||
    sourceOrder?.estimatedDurationHours ||
    estimateCleaningDuration(area, policies)
  );

  return {
    subscription,
    sourceOrder,
    cluster,
    area,
    durationHours,
    mergedOrder,
    policies
  };
}

function firestoreDateValue(value) {
  if (value instanceof admin.firestore.Timestamp) {
    return value.toDate();
  }
  if (value instanceof Date) {
    return value;
  }
  if (value && typeof value === 'object') {
    const seconds = value.seconds ?? value._seconds;
    if (Number.isFinite(Number(seconds))) {
      return new Date(Number(seconds) * 1000);
    }
  }
  if (typeof value === 'string' && value.trim()) {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  return null;
}

function subscriptionMonthlyIncludedVisits(subscription = {}) {
  const packageId = String(subscription.packageId || subscription.package_id || '').trim().toLowerCase();
  const frequency = parseFrequencyConfig(subscription.frequencyLabel, subscription.package);
  const requestedVisits = Number(
    subscription.cleaningsPerMonth ||
    subscription.monthlyIncludedVisits ||
    frequency.monthlyVisits ||
    subscription.includedVisits ||
    1
  );
  const visitsPerMonth = resolvePackageVisitsPerMonth(packageId, requestedVisits);
  return frequency.kind === 'one_time' && !packageId && requestedVisits <= 1
    ? 1
    : Math.max(1, visitsPerMonth);
}

function subscriptionCurrentPeriodBounds(subscription = {}, now = new Date()) {
  const frequency = parseFrequencyConfig(subscription.frequencyLabel, subscription.package);
  const billingPeriodMonths = Math.max(1, Number(
    subscription.billingPeriodMonths || frequency.billingPeriodMonths || 1
  ));
  const validFrom = startOfDay(
    firestoreDateValue(subscription.validFrom) ||
    firestoreDateValue(subscription.createdAt) ||
    new Date()
  );
  const validUntil = startOfDay(
    firestoreDateValue(subscription.validUntil) ||
    addMonths(validFrom, billingPeriodMonths)
  );
  const today = startOfDay(now);
  let periodStart = validFrom;
  let nextStart = addMonths(periodStart, 1);
  while (nextStart <= today && nextStart < validUntil) {
    periodStart = nextStart;
    nextStart = addMonths(periodStart, 1);
  }
  const periodEnd = nextStart < validUntil ? nextStart : validUntil;
  return {
    periodStart,
    periodEnd,
    periodKey: `${toIsoDate(periodStart)}_${toIsoDate(periodEnd)}`
  };
}

function scheduledSlotDate(slot = {}) {
  return firestoreDateValue(slot.scheduledFor) ||
    firestoreDateValue(slot.date) ||
    firestoreDateValue(slot.scheduledDateKey);
}

function slotIsInPeriod(slot, bounds) {
  const scheduledAt = scheduledSlotDate(slot);
  if (!scheduledAt) {
    return false;
  }
  const day = startOfDay(scheduledAt);
  return day >= bounds.periodStart && day < bounds.periodEnd;
}

function getSubscriptionCurrentPeriodUsage(subscription = {}, slots = []) {
  const bounds = subscriptionCurrentPeriodBounds(subscription);
  const periodSlots = slots.filter((slot) => slotIsInPeriod(slot, bounds));
  const completedVisits = periodSlots.filter((slot) => String(slot.status || '') === 'completed').length;
  const forfeitedVisits = periodSlots.filter((slot) =>
    String(slot.status || '') === 'canceled' && slot.cancellationPenaltyApplied === true
  ).length;
  const usedVisits = completedVisits + forfeitedVisits;
  const scheduledVisits = periodSlots.filter((slot) => selectedSlotStatus(slot.status)).length;
  const includedVisits = subscriptionMonthlyIncludedVisits(subscription);
  const remainingVisits = Math.max(includedVisits - usedVisits, 0);
  return {
    ...bounds,
    includedVisits,
    completedVisits,
    forfeitedVisits,
    usedVisits,
    scheduledVisits,
    remainingVisits,
    pendingSelections: Math.max(includedVisits - usedVisits - scheduledVisits, 0)
  };
}

function getSubscriptionSelectionRequirement(subscription, slots) {
  const usage = getSubscriptionCurrentPeriodUsage(subscription, slots);
  const totalRemaining = Math.max(
    subscriptionIncludedVisits(subscription) - Number(subscription.usedVisits || 0),
    0
  );
  return Math.max(Math.min(usage.pendingSelections, totalRemaining), 0);
}

function subscriptionHasRemainingVisits(subscription = {}) {
  const explicitRemaining = Number(subscription.remainingVisits);
  if (Number.isFinite(explicitRemaining) && explicitRemaining > 0) {
    return true;
  }
  const includedVisits = subscriptionIncludedVisits(subscription);
  const usedVisits = Number(subscription.usedVisits || subscription.completedVisits || 0);
  return includedVisits - usedVisits > 0;
}

function effectiveSubscriptionValidUntil(subscription = {}) {
  const rawValidUntil = subscription.validUntil instanceof admin.firestore.Timestamp
    ? subscription.validUntil.toDate()
    : subscription.validUntil
      ? new Date(subscription.validUntil)
      : addMonths(new Date(), SUBSCRIPTION_TERM_MONTHS);
  const currentValidUntil = startOfDay(rawValidUntil);
  const status = String(subscription.status || subscription.subscriptionStatus || '').toLowerCase();
  if (
    status === 'active' &&
    subscriptionHasRemainingVisits(subscription) &&
    currentValidUntil < startOfDay()
  ) {
    return startOfDay(addMonths(new Date(), SUBSCRIPTION_TERM_MONTHS));
  }
  return currentValidUntil;
}

async function getAvailableSlotsInternal({subscriptionId, uid, date, excludeSlotId = null}) {
  const {subscription, cluster, durationHours, sourceOrder, policies} = await resolveSubscriptionSchedulingContext(subscriptionId);
  if (subscription.customerId !== uid) {
    throw new HttpsError('permission-denied', 'Not your subscription');
  }

  const targetDate = parseIsoDate(date);
  if (Number.isNaN(targetDate.getTime())) {
    throw new HttpsError('invalid-argument', 'Invalid date');
  }
  if (targetDate < BOOKING_START_DATE) {
    return {
      ok: true,
      date: toIsoDate(targetDate),
      estimatedHours: durationHours,
      slots: []
    };
  }

  const validFrom = subscription.validFrom instanceof admin.firestore.Timestamp
    ? startOfDay(subscription.validFrom.toDate())
    : startOfDay(subscription.validFrom ? new Date(subscription.validFrom) : new Date());
  const validUntil = effectiveSubscriptionValidUntil(subscription);
  if (targetDate < validFrom || targetDate > validUntil) {
    return {
      ok: true,
      date: toIsoDate(targetDate),
      estimatedHours: durationHours,
      slots: []
    };
  }

  const cleanersQuery = cluster?.name
    ? db.collection('cleaners')
      .where('clusterName', '==', String(cluster.name))
      .where('verificationStatus', '==', 'approved')
    : db.collection('cleaners')
      .where('verificationStatus', '==', 'approved');
  const cleanersSnap = await cleanersQuery.limit(25).get();
  const schedulingScope = {
    ...(sourceOrder || {}),
    ...subscription,
    clusterName: subscription.clusterName || cluster?.name || sourceOrder?.clusterName || null,
    residentialComplex: subscription.residentialComplex || sourceOrder?.residentialComplex || null,
    address: subscription.address || sourceOrder?.address || null
  };
  const cleaners = filterCleanersByServiceArea(filterCleanersByCity(
    cleanersSnap.docs.map((doc) => ({id: doc.id, ...doc.data()})),
    resolveCityFromSource(subscription) || resolveCityFromSource(sourceOrder || {})
  ), schedulingScope);
  const schedulerMetrics = buildSchedulerMetrics({
    area: subscription.area || sourceOrder?.area || 0,
    addonsDetailed: [],
    addons: [],
    estimatedDurationHours: durationHours
  }, policies);
  const candidateSlots = buildCandidateTimeSlots(schedulerMetrics.totalDurationMinutes);
  const cleanerDayAssignments = new Map();

  await Promise.all(
    cleaners.map(async (cleaner) => {
      const daySlots = await getCleanerScheduledSlots(cleaner.id, targetDate, {excludeSlotId});
      cleanerDayAssignments.set(cleaner.id, {
        daySlots,
        dayArea: daySlots.reduce((sum, item) => sum + Number(item.area || 0), 0),
        dayMinutes: daySlots.reduce((sum, item) => sum + Number(item.minutes || 0), 0),
        dailyLimitMinutes: Math.round(
          Number(
            cleaner.daily_work_limit_hours ||
            cleaner.dailyWorkLimitHours ||
            (DAILY_SCHEDULE_LIMIT_MINUTES / 60)
          ) * 60
        )
      });
    })
  );

  const scored = [];
  for (const slot of candidateSlots) {
    const scheduledAt = buildScheduledDateTime(targetDate, slot.time);
    const hoursUntil = (scheduledAt.getTime() - Date.now()) / 3600000;
    if (hoursUntil < 0 || (MIN_BOOKING_HOURS > 0 && hoursUntil < MIN_BOOKING_HOURS)) {
      continue;
    }
    let availableCleaners = 0;
    for (const cleaner of cleaners) {
      const assignment = cleanerDayAssignments.get(cleaner.id) || {
        daySlots: [],
        dayArea: 0,
        dayMinutes: 0,
        dailyLimitMinutes: DAILY_SCHEDULE_LIMIT_MINUTES
      };
      const daySlots = assignment.daySlots;
      const dayMinutes = assignment.dayMinutes;
      const dailyLimitMinutes = assignment.dailyLimitMinutes;
      const hasConflict = daySlots.some((item) => timeRangesOverlap(item.range, slot));
      if (hasConflict || (dayMinutes + schedulerMetrics.totalDurationMinutes) > dailyLimitMinutes) {
        continue;
      }
      availableCleaners += 1;
    }
    if (availableCleaners > 0) {
      scored.push({
        time: slot.time,
        availableCleaners,
        estimatedHours: durationHours,
        totalDurationMinutes: schedulerMetrics.totalDurationMinutes
      });
    }
  }

  return {
    ok: true,
    date: toIsoDate(targetDate),
    estimatedHours: durationHours,
    slots: scored
  };
}

async function getAvailableDatesInternal({subscriptionId, uid, month}) {
  const {subscription} = await resolveSubscriptionSchedulingContext(subscriptionId);
  if (subscription.customerId !== uid) {
    throw new HttpsError('permission-denied', 'Not your subscription');
  }

  const monthDate = month ? parseMonthKey(month) : new Date();
  const from = bookingFloor(monthDate < startOfDay() ? startOfDay() : monthDate);
  const until = endOfMonth(monthDate);
  const validFrom = subscription.validFrom instanceof admin.firestore.Timestamp
    ? startOfDay(subscription.validFrom.toDate())
    : startOfDay(subscription.validFrom ? new Date(subscription.validFrom) : new Date());
  const validUntil = effectiveSubscriptionValidUntil(subscription);
  const slotsSnap = await db.collection('schedule_slots')
    .where('subscriptionId', '==', subscriptionId)
    .get();
  const subscriptionSlots = slotsSnap.docs.map((doc) => ({id: doc.id, ...doc.data()}));
  const bookedDateKeys = new Set(
    subscriptionSlots
      .filter((slot) => selectedSlotStatus(slot.status))
      .map((slot) => String(slot.scheduledDateKey || ''))
  );

  const dates = [];
  let cursor = from;
  while (cursor <= until) {
    const dateKey = toIsoDate(cursor);
    if (cursor >= validFrom && cursor <= validUntil && !bookedDateKeys.has(dateKey)) {
      dates.push({
        date: dateKey,
        availableSlotsCount: 1
      });
    }
    cursor = addDays(cursor, 1);
  }

  return {ok: true, dates};
}

async function bookScheduleInternal({subscriptionId, uid, selections}) {
  if (!Array.isArray(selections) || selections.length === 0) {
    throw new HttpsError('invalid-argument', 'selections required');
  }

  const {subscription, cluster, sourceOrder, mergedOrder, area, durationHours} =
    await resolveSubscriptionSchedulingContext(subscriptionId);
  if (subscription.customerId !== uid) {
    throw new HttpsError('permission-denied', 'Not your subscription');
  }
  const customerProfileSnap = await db.collection('customers').doc(uid).get();
  const customerProfile = customerProfileSnap.exists
    ? customerProfileSnap.data() || {}
    : {};
  const selectedAddress = Array.isArray(customerProfile.addresses)
    ? customerProfile.addresses.find((item) =>
      String(item?.houseId || '').trim() &&
      String(item?.houseId || '').trim() === String(subscription.houseId || sourceOrder?.houseId || '').trim()
    ) || null
    : null;
  assertCustomerAreaReadyForOrdering({
    customerProfile,
    selectedAddress,
    selectedArea: area || subscription.area || sourceOrder?.area || 0
  });

  const slotsSnap = await db.collection('schedule_slots')
    .where('subscriptionId', '==', subscriptionId)
    .get();
  const existingSlots = slotsSnap.docs.map((doc) => ({id: doc.id, ...doc.data()}));
  const requiredSelections = getSubscriptionSelectionRequirement(subscription, existingSlots);
  if (requiredSelections <= 0) {
    throw new HttpsError('failed-precondition', 'No remaining visits require scheduling');
  }
  if (selections.length > requiredSelections) {
    throw new HttpsError(
      'failed-precondition',
      `Maximum ${requiredSelections} selections allowed`
    );
  }

  const uniqueKeys = new Set();
  for (const selection of selections) {
    const parsedDate = parseIsoDate(selection.date);
    assertBookingDateOpen(parsedDate);
    const dateKey = toIsoDate(parsedDate);
    const composite = `${dateKey}_${selection.time || ''}`;
    if (uniqueKeys.has(composite)) {
      throw new HttpsError('invalid-argument', 'Duplicate selection');
    }
    uniqueKeys.add(composite);
    ensureMinBookingLeadTime(
      buildScheduledDateTime(dateKey, String(selection.time || ''))
    );
  }

  const cleanersQuery = cluster?.name
    ? db.collection('cleaners')
      .where('clusterName', '==', String(cluster.name))
      .where('verificationStatus', '==', 'approved')
    : db.collection('cleaners')
      .where('verificationStatus', '==', 'approved');
  const cleanersSnap = await cleanersQuery.limit(25).get();
  const schedulingScope = {
    ...(sourceOrder || {}),
    ...subscription,
    clusterName: subscription.clusterName || cluster?.name || sourceOrder?.clusterName || null,
    residentialComplex: subscription.residentialComplex || sourceOrder?.residentialComplex || null,
    address: subscription.address || sourceOrder?.address || null
  };
  const cleaners = filterCleanersByServiceArea(filterCleanersByCity(
    cleanersSnap.docs.map((doc) => ({id: doc.id, ...doc.data()})),
    resolveCityFromSource(subscription) || resolveCityFromSource(sourceOrder || {})
  ), schedulingScope);
  const projections = new Map();
  const pricingSnap = await db.collection('pricing').doc('default').get();
  const basePricing = pricingSnap.exists ? pricingSnap.data() || {} : {};
  const addonBonusSpendPercent = await getAddonBonusSpendPercent();
  const schedulingPricing = {
    ...basePricing,
    ...(sourceOrder?.pricing || {}),
    ...(subscription.pricing || {})
  };

  const writes = [];
  const addonRequestWrites = [];
  const bonusPaidAddonRequestIds = [];
  const bookedSlots = [];
  let counter = 0;
  for (const selection of selections) {
    const targetDate = parseIsoDate(selection.date);
    const dateKey = toIsoDate(targetDate);
    const time = String(selection.time || '');
    const selectionAddonsDetailed = normalizeDetailedAddons(selection.addonsDetailed || []);
    const selectionAddons = Array.isArray(selection.addons)
      ? selection.addons
      : selectionAddonsDetailed
        .map((item) => item.label || item.key)
        .filter(Boolean);
    const selectionNewAddonsDetailed = normalizeDetailedAddons(selection.newAddonsDetailed || []);
    const selectionNewAddons = selectionNewAddonsDetailed
      .map((item) => {
        const label = String(item.label || item.key || '').trim();
        const quantity = Math.max(1, Number(item.quantity || 1));
        return quantity > 1 ? `${label} × ${quantity}` : label;
      })
      .filter(Boolean);
    const newAddonPricing = calculateDetailedAddonPricing(
      schedulingPricing,
      selectionNewAddonsDetailed
    );
    const newAddonAmount = Math.max(
      0,
      Number(newAddonPricing.billableTotal || 0) +
        Number(newAddonPricing.separatePaymentTotal || 0)
    );
    const schedulerMetrics = buildSchedulerMetrics({
      area,
      addonsDetailed: selectionAddonsDetailed,
      addons: selectionAddons,
      estimatedDurationHours: durationHours
    });
    const addonPayload = orderAddonPayload(
      {
        addons: selectionAddons,
        addonsDetailed: selectionAddonsDetailed
      },
      schedulingPricing
    );
    const orderContext = {
      ...mergedOrder,
      id: sourceOrder?.id || `${subscriptionId}_${dateKey}`,
      date: targetDate,
      scheduledDate: targetDate,
      time,
      area,
      estimatedDurationHours: durationHours,
      estimatedDurationMinutes: schedulerMetrics.estimatedDurationMinutes,
      price: Number(sourceOrder?.price || subscription.price || 0)
    };

    const monthlyStatsEntries = await Promise.all(
      cleaners.map(async (cleaner) => ({
        cleaner,
        monthStats: await getCleanerMonthlyStats(cleaner.id, targetDate),
        dayAssignments: await getCleanerScheduledSlots(cleaner.id, targetDate)
      }))
    );

    const monthlyTargets = monthlyStatsEntries.reduce((acc, item) => {
      const projection = projections.get(item.cleaner.id);
      acc.area += item.monthStats.area + Number(projection?.area || 0);
      acc.hours += item.monthStats.hours + Number(projection?.hours || 0);
      acc.income += item.monthStats.income + Number(projection?.income || 0);
      acc.apartments += item.monthStats.apartments + Number(projection?.apartments || 0);
      return acc;
    }, {area: 0, hours: 0, income: 0, apartments: 0});
    monthlyTargets.area /= Math.max(monthlyStatsEntries.length, 1);
    monthlyTargets.hours /= Math.max(monthlyStatsEntries.length, 1);
    monthlyTargets.income /= Math.max(monthlyStatsEntries.length, 1);
    monthlyTargets.apartments /= Math.max(monthlyStatsEntries.length, 1);

    const ranked = monthlyStatsEntries.map((item) => ({
      cleaner: item.cleaner,
      score: calculateCleanerFairnessScore({
        cleaner: item.cleaner,
        order: orderContext,
        monthStats: {
          area: item.monthStats.area + Number(projections.get(item.cleaner.id)?.area || 0),
          hours: item.monthStats.hours + Number(projections.get(item.cleaner.id)?.hours || 0),
          income: item.monthStats.income + Number(projections.get(item.cleaner.id)?.income || 0),
          apartments: item.monthStats.apartments + Number(projections.get(item.cleaner.id)?.apartments || 0)
        },
        monthlyTargets,
        dayAssignments: [
          ...item.dayAssignments,
          ...(projections.get(item.cleaner.id)?.dayAssignments?.[dateKey] || [])
        ],
        cluster,
        entrance: subscription.entrance || null
      })
    }))
      .filter((item) => !item.score.hasTimeConflict && item.score.fitsDailyLimit)
      .sort((left, right) => left.score.totalScore - right.score.totalScore);

    const selected = pickWeightedCleaner(
      ranked.slice(0, Math.min(3, ranked.length)),
      `${subscriptionId}_${dateKey}_${time}`
    );
    if (!selected?.cleaner?.id) {
      throw new HttpsError(
        'failed-precondition',
        'На выбранное время нет свободных исполнителей. Выберите другое время.'
      );
    }

    const slotRef = db.collection('schedule_slots').doc(`${subscriptionId}_${dateKey}_${counter}`);
    const waitsAddonPayment = selectionNewAddonsDetailed.length > 0 && newAddonAmount > 0;
    const normalizedTime = buildTimeRangeForDuration(time, schedulerMetrics.totalDurationMinutes);
    writes.push({slotRef, payload: {
      subscriptionId,
      sourceOrderId: sourceOrder?.id || null,
      orderNumber: null,
      displayOrderId: null,
      customerId: subscription.customerId,
      customerName: subscription.customerName || sourceOrder?.customerName || null,
      cleanerId: null,
      cleanerName: null,
      cleanerPhone: null,
      preferredCleanerId: selected?.cleaner.id || null,
      preferredCleanerName: selected?.cleaner.name || null,
      clusterId: cluster?.id || subscription.clusterId || null,
      clusterName: cluster?.name || subscription.clusterName || null,
      houseId: subscription.houseId || sourceOrder?.houseId || null,
      houseStatus: subscription.houseStatus || sourceOrder?.houseStatus || null,
      serviceArea: subscription.serviceArea || sourceOrder?.serviceArea || null,
      serviceAreaId: subscription.serviceAreaId || sourceOrder?.serviceAreaId || null,
      zoneId: subscription.zoneId || sourceOrder?.zoneId || null,
      residentialComplex: subscription.residentialComplex || sourceOrder?.residentialComplex || null,
      entrance: subscription.entrance || sourceOrder?.entrance || null,
      apartment: subscription.apartment || sourceOrder?.apartment || null,
      address: subscription.address || sourceOrder?.address || null,
      frequencyLabel: subscription.frequencyLabel || null,
      package: subscription.package || null,
      accessMethod: subscription.accessMethod || null,
      ...addonPayload,
      area,
      estimatedDurationHours: durationHours,
      estimatedDurationMinutes: schedulerMetrics.estimatedDurationMinutes,
      addonCount: schedulerMetrics.addonCount,
      addonBufferMinutes: schedulerMetrics.addonBufferMinutes,
      travelTimeMinutes: schedulerMetrics.travelTimeMinutes,
      totalDurationMinutes: schedulerMetrics.totalDurationMinutes,
      totalDurationHours: schedulerMetrics.totalDurationHours,
      scheduledFor: admin.firestore.Timestamp.fromDate(targetDate),
      scheduledDateKey: dateKey,
      time: normalizedTime,
      status: waitsAddonPayment ? 'pending_payment' : 'pending_assignment',
      assignmentStatus: waitsAddonPayment ? 'payment_pending' : ORDER_ASSIGNMENT_STATUSES.SEARCHING,
      pendingAddonPayment: waitsAddonPayment,
      remindersSent: [],
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      bookingMode: 'manual_selection'
    }});
    bookedSlots.push({
      id: slotRef.id,
      date: dateKey,
      time: normalizedTime,
      waitsAddonPayment
    });
    if (selectionNewAddonsDetailed.length > 0 && newAddonAmount > 0) {
      const requestedAddonBonusAmount = Math.max(0, Number(selection.bonusToSpend || 0));
      const maxAddonBonusPaymentAmount = Math.floor(
        newAddonAmount * (addonBonusSpendPercent / 100)
      );
      const addonRequestRef = db.collection('addon_requests').doc();
      const paymentId = `addon_${addonRequestRef.id}`;
      const commonAddonPayload = {
        slotId: slotRef.id,
        sourceOrderId: sourceOrder?.id || null,
        customerOrderId: sourceOrder?.id || null,
        subscriptionId,
        customerId: subscription.customerId || null,
        customerName: subscription.customerName || sourceOrder?.customerName || null,
        customerPhone: subscription.customerPhone || sourceOrder?.customerPhone || null,
        cleanerId: null,
        cleanerName: null,
        address: subscription.address || sourceOrder?.address || null,
        residentialComplex: subscription.residentialComplex || sourceOrder?.residentialComplex || null,
        package: subscription.package || null,
        frequencyLabel: subscription.frequencyLabel || null,
        addons: selectionNewAddons,
        addonsDetailed: selectionNewAddonsDetailed,
        originalAddonAmount: newAddonAmount,
        amount: newAddonAmount,
        price: newAddonAmount,
        bonusToSpend: requestedAddonBonusAmount,
        bonusAppliedAmount: 0,
        maxBonusPaymentPercent: addonBonusSpendPercent,
        maxBonusPaymentAmount: maxAddonBonusPaymentAmount,
        bonusProgram: null,
        addonsSeparatePaymentTotal: Number(newAddonPricing.separatePaymentTotal || 0),
        separatePaymentAddons: Array.isArray(newAddonPricing.separatePaymentAddons)
          ? newAddonPricing.separatePaymentAddons
          : [],
        scheduledFor: admin.firestore.Timestamp.fromDate(targetDate),
        scheduledDateKey: dateKey,
        time,
        kaspiPhone: String(selection.kaspiPhone || subscription.customerPhone || sourceOrder?.customerPhone || '').trim() || null,
        requestSource: 'client_schedule_confirmation'
      };
      addonRequestWrites.push({
        requestRef: addonRequestRef,
        paymentRef: db.collection('payments').doc(paymentId),
        baseAmount: newAddonAmount,
        requestedBonusAmount: requestedAddonBonusAmount,
        requestPayload: {
          id: addonRequestRef.id,
          ...commonAddonPayload,
          status: 'invoice_requested',
          paymentStatus: 'invoice_requested',
          paymentId,
          customerApprovedAt: admin.firestore.FieldValue.serverTimestamp(),
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        },
        paymentPayload: {
          id: paymentId,
          orderId: paymentId,
          type: 'addon_request',
          addonRequestId: addonRequestRef.id,
          ...commonAddonPayload,
          provider: 'kaspi_manual_request',
          status: 'invoice_requested',
          paymentStatus: 'invoice_requested',
          kaspiPhone: commonAddonPayload.kaspiPhone,
          currency: 'KZT',
          packageName: 'Доп. услуги к уборке',
          frequencyLabel: 'Клиент выбрал при подтверждении даты',
          invoiceRequestedAt: admin.firestore.FieldValue.serverTimestamp(),
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        }
      });
    }
    if (selected?.cleaner?.id) {
      const current = projections.get(selected.cleaner.id) || {
        area: 0,
        hours: 0,
        income: 0,
        apartments: 0,
        dayAssignments: {}
      };
      const nextDayAssignments = {...current.dayAssignments};
      nextDayAssignments[dateKey] = [
        ...(nextDayAssignments[dateKey] || []),
        {
          time,
          range: parseTimeRange(time),
          hours: schedulerMetrics.totalDurationHours,
          minutes: schedulerMetrics.totalDurationMinutes
        }
      ];
      projections.set(selected.cleaner.id, {
        area: Number(current.area || 0) + area,
        hours: Number(current.hours || 0) + schedulerMetrics.totalDurationHours,
        income: Number(current.income || 0) + Number(sourceOrder?.price || subscription.price || 0),
        apartments: Number(current.apartments || 0) + 1,
        dayAssignments: nextDayAssignments
      });
    }
    counter += 1;
  }

  await db.runTransaction(async (tx) => {
    const bonusRequestedForAddons = addonRequestWrites.some(
      (write) => Number(write.requestedBonusAmount || 0) > 0
    );
    let customerRef = null;
    let availableBonusPointsForAddons = 0;
    let totalAddonBonusApplied = 0;
    if (bonusRequestedForAddons) {
      customerRef = db.collection('customers').doc(String(uid));
      const customerSnap = await tx.get(customerRef);
      availableBonusPointsForAddons = Math.max(
        0,
        Number(customerSnap.data()?.bonusPoints || 0)
      );
    }
    for (const write of writes) {
      tx.set(write.slotRef, write.payload, {merge: true});
    }
    for (const write of addonRequestWrites) {
      const requestedBonusAmount = Math.max(0, Number(write.requestedBonusAmount || 0));
      const baseAmount = Math.max(0, Number(write.baseAmount || 0));
      const maxBonusPaymentAmount = Math.floor(
        baseAmount * (addonBonusSpendPercent / 100)
      );
      let bonusAppliedAmount = 0;
      if (requestedBonusAmount > 0) {
        bonusAppliedAmount = Math.min(
          requestedBonusAmount,
          availableBonusPointsForAddons,
          maxBonusPaymentAmount
        );
        if (bonusAppliedAmount <= 0) {
          throw new HttpsError(
            'failed-precondition',
            `Недостаточно бонусов или превышен лимит списания ${addonBonusSpendPercent}%.`
          );
        }
        availableBonusPointsForAddons -= bonusAppliedAmount;
        totalAddonBonusApplied += bonusAppliedAmount;
      }
      const finalAddonAmount = Math.max(baseAmount - bonusAppliedAmount, 0);
      const bonusOnlyPaid = finalAddonAmount === 0 && bonusAppliedAmount > 0;
      const bonusPayload = {
        originalAddonAmount: baseAmount,
        amount: finalAddonAmount,
        price: finalAddonAmount,
        bonusToSpend: requestedBonusAmount,
        bonusAppliedAmount,
        maxBonusPaymentPercent: addonBonusSpendPercent,
        maxBonusPaymentAmount,
        bonusProgram: bonusAppliedAmount > 0 ? 'package_addons_50_percent' : null,
        bonusReservedAt: bonusAppliedAmount > 0
          ? admin.firestore.FieldValue.serverTimestamp()
          : null,
      };
      tx.set(write.requestRef, {
        ...write.requestPayload,
        ...bonusPayload,
        status: bonusOnlyPaid ? 'payment_confirmed' : write.requestPayload.status,
        paymentStatus: bonusOnlyPaid ? 'paid' : write.requestPayload.paymentStatus,
        paidAt: bonusOnlyPaid ? admin.firestore.FieldValue.serverTimestamp() : null,
        ...(bonusOnlyPaid ? {
          bonusSettledAt: admin.firestore.FieldValue.serverTimestamp(),
        } : {}),
      }, {merge: true});
      tx.set(write.paymentRef, {
        ...write.paymentPayload,
        ...bonusPayload,
        provider: bonusOnlyPaid ? 'bonus' : write.paymentPayload.provider,
        status: bonusOnlyPaid ? 'paid' : write.paymentPayload.status,
        paymentStatus: bonusOnlyPaid ? 'paid' : write.paymentPayload.paymentStatus,
        paidAt: bonusOnlyPaid ? admin.firestore.FieldValue.serverTimestamp() : null,
        ...(bonusOnlyPaid ? {
          bonusSettledAt: admin.firestore.FieldValue.serverTimestamp(),
        } : {}),
      }, {merge: true});
      if (bonusOnlyPaid) {
        bonusPaidAddonRequestIds.push(write.requestRef.id);
      }
    }
    if (customerRef && totalAddonBonusApplied > 0) {
      tx.set(customerRef, {
        bonusPoints: availableBonusPointsForAddons,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      }, {merge: true});
      tx.set(db.collection('bonus_transactions').doc(), {
        userId: String(uid),
        amount: -totalAddonBonusApplied,
        type: 'bonus_debit',
        title: 'Оплата бонусами',
        reason: 'Списано за доп. услуги при выборе даты',
        orderId: addonRequestWrites.map((write) => write.paymentRef.id).join(','),
        createdAt: admin.firestore.FieldValue.serverTimestamp()
      });
    }
    tx.set(db.collection('subscriptions').doc(subscriptionId), {
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});
  });
  await refreshSubscriptionUsage(subscriptionId);
  await Promise.all(bonusPaidAddonRequestIds.map((id) =>
    applyAddonRequestToSlot(id, 'bonus_payment')
  ));
  await Promise.all(bookedSlots.map((slot) =>
    slot.waitsAddonPayment
      ? Promise.resolve()
      : safelyOfferScopeToNextCleaner('schedule_slot', slot.id, {
        forceRebuild: true
      })
  ));
  await logAssignmentDecision('manual_schedule_booking', {
    subscriptionId,
    customerId: uid,
    selections
  });
  return {
    ok: true,
    booked: selections.length,
    bookedSlots,
    addonPaymentIds: addonRequestWrites.map((write) => write.paymentRef.id)
  };
}

async function rescheduleInternal({slotId, uid, date, time}) {
  const slotRef = db.collection('schedule_slots').doc(slotId);
  const slotSnap = await slotRef.get();
  if (!slotSnap.exists) {
    throw new HttpsError('not-found', 'Slot not found');
  }

  const slot = {id: slotSnap.id, ...slotSnap.data()};
  if (slot.customerId !== uid) {
    throw new HttpsError('permission-denied', 'No access to this slot');
  }
  if (!activeSlotStatus(slot.status)) {
    throw new HttpsError('failed-precondition', 'Only active slots can be rescheduled');
  }
  ensureMinBookingLeadTime(buildScheduledDateTime(date, time));

  const {subscription, cluster, sourceOrder, mergedOrder, area, durationHours, policies} =
    await resolveSubscriptionSchedulingContext(String(slot.subscriptionId || ''));
  const schedulerMetrics = buildSchedulerMetrics({
    area,
    addonsDetailed: slot.addonsDetailed || [],
    addons: slot.addons || [],
    estimatedDurationHours: durationHours
  }, policies);
  const availability = await getAvailableSlotsInternal({
    subscriptionId: String(slot.subscriptionId || ''),
    uid,
    date,
    excludeSlotId: slotId
  });
  const matched = availability.slots.find((item) => item.time === String(time || '')) || {
    estimatedHours: durationHours,
    totalDurationMinutes: schedulerMetrics.totalDurationMinutes
  };

  const targetDate = startOfDay(new Date(date));
  const cleanersQuery = cluster?.name
    ? db.collection('cleaners')
      .where('clusterName', '==', String(cluster.name))
      .where('verificationStatus', '==', 'approved')
    : db.collection('cleaners')
      .where('verificationStatus', '==', 'approved');
  const cleanersSnap = await cleanersQuery.limit(25).get();
  const schedulingScope = {
    ...(sourceOrder || {}),
    ...subscription,
    ...slot,
    clusterName: slot.clusterName || subscription.clusterName || cluster?.name || sourceOrder?.clusterName || null,
    residentialComplex: slot.residentialComplex || subscription.residentialComplex || sourceOrder?.residentialComplex || null,
    address: slot.address || subscription.address || sourceOrder?.address || null
  };
  const cleaners = filterCleanersByServiceArea(filterCleanersByCity(
    cleanersSnap.docs.map((doc) => ({id: doc.id, ...doc.data()})),
    resolveCityFromSource(subscription) || resolveCityFromSource(sourceOrder || {}) || resolveCityFromSource(slot)
  ), schedulingScope);
  const orderContext = {
    ...mergedOrder,
    id: sourceOrder?.id || slot.sourceOrderId || slotId,
    date: targetDate,
    scheduledDate: targetDate,
    time,
    area,
    estimatedDurationHours: durationHours,
    estimatedDurationMinutes: schedulerMetrics.estimatedDurationMinutes,
    totalDurationMinutes: schedulerMetrics.totalDurationMinutes,
    price: Number(sourceOrder?.price || subscription.price || 0)
  };
  const monthlyStatsEntries = await Promise.all(
    cleaners.map(async (cleaner) => ({
      cleaner,
      monthStats: await getCleanerMonthlyStats(cleaner.id, targetDate),
      dayAssignments: await getCleanerScheduledSlots(cleaner.id, targetDate, {excludeSlotId: slotId})
    }))
  );
  const monthlyTargets = monthlyStatsEntries.reduce((acc, item) => {
    acc.area += item.monthStats.area;
    acc.hours += item.monthStats.hours;
    acc.income += item.monthStats.income;
    acc.apartments += item.monthStats.apartments;
    return acc;
  }, {area: 0, hours: 0, income: 0, apartments: 0});
  monthlyTargets.area /= Math.max(monthlyStatsEntries.length, 1);
  monthlyTargets.hours /= Math.max(monthlyStatsEntries.length, 1);
  monthlyTargets.income /= Math.max(monthlyStatsEntries.length, 1);
  monthlyTargets.apartments /= Math.max(monthlyStatsEntries.length, 1);
  const ranked = monthlyStatsEntries.map((item) => ({
    cleaner: item.cleaner,
    score: calculateCleanerFairnessScore({
      cleaner: item.cleaner,
      order: orderContext,
      monthStats: item.monthStats,
      monthlyTargets,
      dayAssignments: item.dayAssignments,
      cluster,
      entrance: subscription.entrance || null
    })
  }))
    .filter((item) => !item.score.hasTimeConflict && item.score.fitsDailyLimit)
    .sort((left, right) => left.score.totalScore - right.score.totalScore);
  const selected = pickWeightedCleaner(
    ranked.slice(0, Math.min(3, ranked.length)),
    `${slotId}_${toIsoDate(targetDate)}_${time}`
  );
  const normalizedTime = buildTimeRangeForDuration(time, schedulerMetrics.totalDurationMinutes);

  await db.runTransaction(async (tx) => {
    tx.set(slotRef, {
      scheduledFor: admin.firestore.Timestamp.fromDate(targetDate),
      scheduledDateKey: toIsoDate(targetDate),
      time: normalizedTime,
      estimatedDurationHours: matched.estimatedHours,
      estimatedDurationMinutes: schedulerMetrics.estimatedDurationMinutes,
      addonCount: schedulerMetrics.addonCount,
      addonBufferMinutes: schedulerMetrics.addonBufferMinutes,
      travelTimeMinutes: schedulerMetrics.travelTimeMinutes,
      totalDurationMinutes: schedulerMetrics.totalDurationMinutes,
      totalDurationHours: schedulerMetrics.totalDurationHours,
      cleanerId: null,
      cleanerName: null,
      cleanerPhone: null,
      preferredCleanerId: selected?.cleaner.id || null,
      preferredCleanerName: selected?.cleaner.name || null,
      status: 'pending_assignment',
      assignmentStatus: ORDER_ASSIGNMENT_STATUSES.SEARCHING,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      bookingMode: 'manual_reschedule'
    }, {merge: true});
  });

  await logAssignmentDecision('manual_schedule_reschedule', {
    slotId,
    customerId: uid,
    date,
    time: normalizedTime
  });
  await safelyOfferScopeToNextCleaner('schedule_slot', slotId, {
    forceRebuild: true
  });

  return {ok: true};
}

async function updateScheduledCleaningInternal({
  slotId,
  uid,
  date = null,
  time = null,
  addonsDetailed = null
}) {
  if (!slotId) {
    throw new HttpsError('invalid-argument', 'slotId required');
  }
  const slotRef = db.collection('schedule_slots').doc(slotId);
  const slotSnap = await slotRef.get();
  if (!slotSnap.exists) {
    throw new HttpsError('not-found', 'Slot not found');
  }

  const slot = {id: slotSnap.id, ...slotSnap.data()};
  if (slot.customerId !== uid) {
    throw new HttpsError('permission-denied', 'No access to this slot');
  }
  if (!activeSlotStatus(slot.status)) {
    throw new HttpsError('failed-precondition', 'Only active slots can be updated');
  }

  const updated = [];
  if (date != null && time != null) {
    await rescheduleInternal({slotId, uid, date, time});
    updated.push('schedule');
  }

  if (addonsDetailed != null) {
    const pricingSnap = await db.collection('pricing').doc('default').get();
    const pricing = pricingSnap.data() || {};
    const normalizedDetailedAddons = normalizeDetailedAddons(addonsDetailed);
    const detailedAddonPricing = calculateDetailedAddonPricing(
      pricing,
      normalizedDetailedAddons
    );
    const addons = normalizedDetailedAddons.map((item) => String(item.label || item.key || ''));
    const schedulerMetrics = buildSchedulerMetrics({
      area: slot.area || 0,
      addonsDetailed: normalizedDetailedAddons,
      addons,
      estimatedDurationHours: slot.estimatedDurationHours || estimateCleaningDuration(slot.area || 0)
    });
    const normalizedTime = buildTimeRangeForDuration(slot.time || '10:00 - 13:00', schedulerMetrics.totalDurationMinutes);
    const addonUpdatePayload = {
      addons,
      addonsDetailed: normalizedDetailedAddons,
      addonTotalPrice: detailedAddonPricing.billableTotal,
      addonsSeparatePaymentTotal: detailedAddonPricing.separatePaymentTotal,
      separatePaymentAddons: detailedAddonPricing.separatePaymentAddons,
      addonCount: schedulerMetrics.addonCount,
      addonBufferMinutes: schedulerMetrics.addonBufferMinutes,
      travelTimeMinutes: schedulerMetrics.travelTimeMinutes,
      estimatedDurationMinutes: schedulerMetrics.estimatedDurationMinutes,
      totalDurationMinutes: schedulerMetrics.totalDurationMinutes,
      totalDurationHours: schedulerMetrics.totalDurationHours,
      time: normalizedTime,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    };
    await slotRef.set(addonUpdatePayload, {merge: true});
    await db.collection('cleaner_orders').doc(slotId).set(addonUpdatePayload, {merge: true});
    await db.collection('cleaner_shifts').doc(slotId).set(addonUpdatePayload, {merge: true});
    await updatePendingOffersForScope('schedule_slot', slotId, addonUpdatePayload);

    if (slot.sourceOrderId) {
      await db.collection('customer_orders').doc(String(slot.sourceOrderId)).set({
        addons,
        addonsDetailed: normalizedDetailedAddons,
        addonTotalPrice: detailedAddonPricing.billableTotal,
        addonsSeparatePaymentTotal: detailedAddonPricing.separatePaymentTotal,
        separatePaymentAddons: detailedAddonPricing.separatePaymentAddons,
        addonCount: schedulerMetrics.addonCount,
        addonBufferMinutes: schedulerMetrics.addonBufferMinutes,
        travelTimeMinutes: schedulerMetrics.travelTimeMinutes,
        estimatedDurationMinutes: schedulerMetrics.estimatedDurationMinutes,
        totalDurationMinutes: schedulerMetrics.totalDurationMinutes,
        totalDurationHours: schedulerMetrics.totalDurationHours,
        time: normalizedTime,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      }, {merge: true});
    }
    updated.push('addons');
    if (slot.sourceOrderId) {
      await recalculateScheduleAfterAddonInternal(String(slot.sourceOrderId));
    }
  }

  return {ok: true, updated};
}

function mergeDetailedAddons(existing = [], incoming = []) {
  const byKey = new Map();
  for (const item of normalizeDetailedAddons(existing)) {
    const key = String(item.key || item.label || '').trim();
    if (!key) continue;
    byKey.set(key, {...item});
  }
  for (const item of normalizeDetailedAddons(incoming)) {
    const key = String(item.key || item.label || '').trim();
    if (!key) continue;
    const previous = byKey.get(key) || {};
    byKey.set(key, {
      ...previous,
      ...item,
      quantity: Math.max(1, Number(previous.quantity || 0) + Number(item.quantity || 1)),
    });
  }
  return [...byKey.values()];
}

function addonCompareKey(item = {}) {
  return String(item.key || item.label || item.name || '').trim().toLowerCase();
}

function subtractDetailedAddons(existing = [], removing = [], fallbackLabels = []) {
  const removeByKey = new Map();
  for (const item of normalizeDetailedAddons(removing)) {
    const key = addonCompareKey(item);
    if (!key) continue;
    removeByKey.set(key, (removeByKey.get(key) || 0) + Math.max(1, Number(item.quantity || 1)));
  }
  for (const label of Array.isArray(fallbackLabels) ? fallbackLabels : []) {
    const key = String(label || '').trim().toLowerCase();
    if (!key || removeByKey.has(key)) continue;
    removeByKey.set(key, 1);
  }

  return normalizeDetailedAddons(existing).reduce((result, item) => {
    const key = addonCompareKey(item);
    const removeQuantity = removeByKey.get(key) || 0;
    if (removeQuantity <= 0) {
      result.push(item);
      return result;
    }
    const nextQuantity = Math.max(0, Number(item.quantity || 0) - removeQuantity);
    if (nextQuantity > 0) {
      result.push({...item, quantity: nextQuantity});
    }
    removeByKey.set(key, Math.max(0, removeQuantity - Number(item.quantity || 0)));
    return result;
  }, []);
}

function schedulerMetricsForAddonsRollback(slot = {}, addons = [], addonsDetailed = []) {
  return buildSchedulerMetrics({
    ...slot,
    addons,
    addonsDetailed,
    addonBufferMinutes: 0,
    totalDurationMinutes: 0,
    totalDurationHours: 0
  });
}

function clearAddonPayload() {
  return {
    addons: [],
    addonsDetailed: [],
    addonCount: 0,
    addonTotalPrice: 0,
    addonsSeparatePaymentTotal: 0,
    separatePaymentAddons: [],
    pendingAddonPayment: false,
    lastAddonRequestId: null,
    lastAddonOrderId: null,
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  };
}

function isAddonPaymentRecord(payment = {}) {
  const type = String(payment.type || '').trim().toLowerCase();
  const pricingMode = String(payment.pricingMode || '').trim().toLowerCase();
  const packageId = String(payment.packageId || '').trim().toLowerCase();
  const orderId = String(payment.orderId || payment.id || '').trim();
  return type === 'addon_request' ||
    pricingMode === 'addons_only' ||
    packageId === 'addons_only' ||
    orderId.startsWith('addon_') ||
    Boolean(payment.addonRequestId);
}

async function applyAddonRequestToSlot(addonRequestId, reviewerId = null) {
  const requestRef = db.collection('addon_requests').doc(String(addonRequestId));
  const requestSnap = await requestRef.get();
  if (!requestSnap.exists) {
    throw new HttpsError('not-found', 'Addon request not found');
  }
  const request = {id: requestSnap.id, ...requestSnap.data()};
  const slotId = String(request.slotId || '').trim();
  if (!slotId) {
    throw new HttpsError('failed-precondition', 'Addon request has no slot');
  }
  const slotRef = db.collection('schedule_slots').doc(slotId);
  const slotSnap = await slotRef.get();
  if (!slotSnap.exists) {
    throw new HttpsError('not-found', 'Slot not found');
  }
  const slot = {id: slotSnap.id, ...slotSnap.data()};
  const wasWaitingAddonPayment = String(slot.status || '') === 'pending_payment' &&
    slot.pendingAddonPayment === true;
  const pricingSnap = await db.collection('pricing').doc('default').get();
  const pricing = pricingSnap.data() || {};
  const combinedDetailedAddons = mergeDetailedAddons(
    slot.addonsDetailed,
    request.addonsDetailed
  );
  const detailedAddonPricing = calculateDetailedAddonPricing(pricing, combinedDetailedAddons);
  const addons = combinedDetailedAddons.map((item) => String(item.label || item.key || ''));
  const schedulerMetrics = buildSchedulerMetrics({
    ...slot,
    addons,
    addonsDetailed: combinedDetailedAddons
  });
  const normalizedTime = buildTimeRangeForDuration(slot.time || '10:00 - 13:00', schedulerMetrics.totalDurationMinutes);
  const payload = {
    addons,
    addonsDetailed: combinedDetailedAddons,
    addonTotalPrice: detailedAddonPricing.billableTotal,
    addonsSeparatePaymentTotal: detailedAddonPricing.separatePaymentTotal,
    separatePaymentAddons: detailedAddonPricing.separatePaymentAddons,
    addonCount: schedulerMetrics.addonCount,
    addonBufferMinutes: schedulerMetrics.addonBufferMinutes,
    travelTimeMinutes: schedulerMetrics.travelTimeMinutes,
    estimatedDurationMinutes: schedulerMetrics.estimatedDurationMinutes,
    totalDurationMinutes: schedulerMetrics.totalDurationMinutes,
    totalDurationHours: schedulerMetrics.totalDurationHours,
    time: normalizedTime,
    ...(wasWaitingAddonPayment ? {
      status: 'pending_assignment',
      assignmentStatus: ORDER_ASSIGNMENT_STATUSES.SEARCHING,
      pendingAddonPayment: false,
      addonPaymentConfirmedAt: admin.firestore.FieldValue.serverTimestamp(),
    } : {}),
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  };
  const batch = db.batch();
  batch.set(slotRef, payload, {merge: true});
  batch.set(db.collection('cleaner_orders').doc(slotId), {
    ...payload,
    lastAddonRequestId: requestRef.id,
  }, {merge: true});
  batch.set(db.collection('cleaner_shifts').doc(slotId), {
    ...payload,
    lastAddonRequestId: requestRef.id,
  }, {merge: true});
  if (slot.sourceOrderId) {
    batch.set(db.collection('customer_orders').doc(String(slot.sourceOrderId)), {
      ...payload,
      lastAddonRequestId: requestRef.id,
    }, {merge: true});
  }
  batch.set(requestRef, {
    status: 'paid',
    appliedAt: admin.firestore.FieldValue.serverTimestamp(),
    appliedBy: reviewerId || null,
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, {merge: true});
  await batch.commit();
  await updatePendingOffersForScope('schedule_slot', slotId, {
    ...payload,
    lastAddonRequestId: requestRef.id,
  });
  if (wasWaitingAddonPayment) {
    await safelyOfferScopeToNextCleaner('schedule_slot', slotId, {
      forceRebuild: true
    });
  }
  if (slot.cleanerId && !wasWaitingAddonPayment) {
    await reassignCleanerOverlapsAfterScheduleChange({
      changedSlotId: slotId,
      cleanerId: String(slot.cleanerId),
      changedScope: {
        ...slot,
        ...payload,
        id: slotId,
        scopeType: 'schedule_slot'
      },
      reason: 'addons_duration_conflict'
    }).catch((error) => console.error('Failed to reassign cleaner overlaps after addon update', {
      slotId,
      cleanerId: slot.cleanerId,
      error: String(error?.message || error)
    }));
  }
  if (slot.cleanerId) {
    await sendPushToUser(
      String(slot.cleanerId),
      'Доп. услуги оплачены',
      'Клиент оплатил предложенные доп. услуги. Они добавлены в чек-лист.',
      {type: 'addon_request_paid', orderId: slotId}
    ).catch(() => {});
  }
  if (slot.customerId) {
    await sendPushToUser(
      String(slot.customerId),
      'Доп. услуги добавлены',
      'Оплата подтверждена, доп. услуги добавлены к уборке.',
      {type: 'addon_request_paid', orderId: slotId}
    ).catch(() => {});
  }
  return {ok: true, slotId, addonRequestId: requestRef.id};
}

async function rollbackAddonRequestFromSlot(addonRequestId, reviewerId = null) {
  const requestRef = db.collection('addon_requests').doc(String(addonRequestId));
  const requestSnap = await requestRef.get();
  if (!requestSnap.exists) {
    return {ok: true, skipped: true, reason: 'request_not_found'};
  }
  const request = {id: requestSnap.id, ...requestSnap.data()};
  const slotId = String(request.slotId || '').trim();
  if (!slotId) {
    return {ok: true, skipped: true, reason: 'slot_not_found'};
  }
  const slotRef = db.collection('schedule_slots').doc(slotId);
  const slotSnap = await slotRef.get();
  if (!slotSnap.exists) {
    return {ok: true, skipped: true, reason: 'slot_not_found'};
  }

  const slot = {id: slotSnap.id, ...slotSnap.data()};
  const remainingDetailedAddons = subtractDetailedAddons(
    slot.addonsDetailed,
    request.addonsDetailed,
    request.addons
  );
  const addons = remainingDetailedAddons.map((item) => String(item.label || item.key || ''));
  const pricingSnap = await db.collection('pricing').doc('default').get();
  const pricing = pricingSnap.data() || {};
  const detailedAddonPricing = calculateDetailedAddonPricing(pricing, remainingDetailedAddons);
  const schedulerMetrics = schedulerMetricsForAddonsRollback(slot, addons, remainingDetailedAddons);
  const normalizedTime = buildTimeRangeForDuration(
    slot.time || '10:00 - 13:00',
    schedulerMetrics.totalDurationMinutes
  );
  const payload = {
    addons,
    addonsDetailed: remainingDetailedAddons,
    addonTotalPrice: detailedAddonPricing.billableTotal,
    addonsSeparatePaymentTotal: detailedAddonPricing.separatePaymentTotal,
    separatePaymentAddons: detailedAddonPricing.separatePaymentAddons,
    addonCount: schedulerMetrics.addonCount,
    addonBufferMinutes: schedulerMetrics.addonBufferMinutes,
    travelTimeMinutes: schedulerMetrics.travelTimeMinutes,
    estimatedDurationMinutes: schedulerMetrics.estimatedDurationMinutes,
    estimatedDurationHours: schedulerMetrics.estimatedDurationHours,
    totalDurationMinutes: schedulerMetrics.totalDurationMinutes,
    totalDurationHours: schedulerMetrics.totalDurationHours,
    time: normalizedTime,
    lastRolledBackAddonRequestId: requestRef.id,
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  };
  const customerOrderId = String(
    slot.sourceOrderId ||
      request.sourceOrderId ||
      request.customerOrderId ||
      request.orderId ||
      ''
  ).trim();
  let customerOrderPayload = null;
  if (customerOrderId) {
    const customerOrderSnap = await db.collection('customer_orders').doc(customerOrderId).get();
    if (customerOrderSnap.exists) {
      const customerOrder = customerOrderSnap.data() || {};
      const orderRemainingDetailedAddons = subtractDetailedAddons(
        customerOrder.addonsDetailed,
        request.addonsDetailed,
        request.addons
      );
      const orderAddons = orderRemainingDetailedAddons.map((item) =>
        String(item.label || item.key || '')
      );
      const orderAddonPricing = calculateDetailedAddonPricing(pricing, orderRemainingDetailedAddons);
      customerOrderPayload = {
        addons: orderAddons,
        addonsDetailed: orderRemainingDetailedAddons,
        addonTotalPrice: orderAddonPricing.billableTotal,
        addonsSeparatePaymentTotal: orderAddonPricing.separatePaymentTotal,
        separatePaymentAddons: orderAddonPricing.separatePaymentAddons,
        lastRolledBackAddonRequestId: requestRef.id,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      };
    }
  }
  const batch = db.batch();
  batch.set(slotRef, payload, {merge: true});
  batch.set(db.collection('cleaner_orders').doc(slotId), payload, {merge: true});
  batch.set(db.collection('cleaner_shifts').doc(slotId), payload, {merge: true});
  if (customerOrderId && customerOrderPayload) {
    batch.set(db.collection('customer_orders').doc(customerOrderId), customerOrderPayload, {merge: true});
  }
  batch.set(requestRef, {
    rolledBackAt: admin.firestore.FieldValue.serverTimestamp(),
    rolledBackBy: reviewerId || null,
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, {merge: true});
  await batch.commit();
  await updatePendingOffersForScope('schedule_slot', slotId, payload);

  if (slot.customerId) {
    await sendPushToUser(
      String(slot.customerId),
      'Доп. услуги отменены',
      'Оплата не подтверждена, доп. услуги убраны из уборки.',
      {type: 'addon_request_rejected', orderId: slotId}
    ).catch(() => {});
  }
  if (slot.cleanerId) {
    await sendPushToUser(
      String(slot.cleanerId),
      'Доп. услуги отменены',
      'Оплата клиента не подтверждена, доп. услуги убраны из чек-листа.',
      {type: 'addon_request_rejected', orderId: slotId}
    ).catch(() => {});
  }

  return {ok: true, slotId, addonRequestId: requestRef.id};
}

async function applyAddonsOnlyOrderToSlot(orderId, reviewerId = null) {
  const orderRef = db.collection('customer_orders').doc(String(orderId));
  const orderSnap = await orderRef.get();
  if (!orderSnap.exists) {
    throw new HttpsError('not-found', 'Order not found');
  }
  const order = {id: orderSnap.id, ...orderSnap.data()};
  const slotId = String(order.slotId || '').trim();
  if (!slotId) {
    return {ok: true, orderId, merged: false};
  }
  const slotRef = db.collection('schedule_slots').doc(slotId);
  const slotSnap = await slotRef.get();
  if (!slotSnap.exists) {
    throw new HttpsError('not-found', 'Slot not found');
  }
  const slot = {id: slotSnap.id, ...slotSnap.data()};
  const pricingSnap = await db.collection('pricing').doc('default').get();
  const pricing = pricingSnap.data() || {};
  const combinedDetailedAddons = mergeDetailedAddons(
    slot.addonsDetailed,
    order.addonsDetailed
  );
  const detailedAddonPricing = calculateDetailedAddonPricing(
    pricing,
    combinedDetailedAddons
  );
  const addons = combinedDetailedAddons.map((item) =>
    String(item.label || item.key || '')
  );
  const schedulerMetrics = buildSchedulerMetrics({
    ...slot,
    addons,
    addonsDetailed: combinedDetailedAddons
  });
  const normalizedTime = buildTimeRangeForDuration(slot.time || '10:00 - 13:00', schedulerMetrics.totalDurationMinutes);
  const payload = {
    addons,
    addonsDetailed: combinedDetailedAddons,
    addonTotalPrice: detailedAddonPricing.billableTotal,
    addonsSeparatePaymentTotal: detailedAddonPricing.separatePaymentTotal,
    separatePaymentAddons: detailedAddonPricing.separatePaymentAddons,
    addonCount: schedulerMetrics.addonCount,
    addonBufferMinutes: schedulerMetrics.addonBufferMinutes,
    travelTimeMinutes: schedulerMetrics.travelTimeMinutes,
    estimatedDurationMinutes: schedulerMetrics.estimatedDurationMinutes,
    totalDurationMinutes: schedulerMetrics.totalDurationMinutes,
    totalDurationHours: schedulerMetrics.totalDurationHours,
    time: normalizedTime,
    lastAddonOrderId: String(orderId),
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  };
  const batch = db.batch();
  batch.set(slotRef, payload, {merge: true});
  batch.set(db.collection('cleaner_orders').doc(slotId), payload, {merge: true});
  batch.set(db.collection('cleaner_shifts').doc(slotId), payload, {merge: true});
  if (slot.sourceOrderId) {
    batch.set(db.collection('customer_orders').doc(String(slot.sourceOrderId)), payload, {merge: true});
  }
  batch.set(orderRef, {
    status: 'merged',
    orderStatus: 'merged',
    paymentStatus: 'paid',
    mergedIntoSlotId: slotId,
    paidAt: admin.firestore.FieldValue.serverTimestamp(),
    reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
    reviewedBy: reviewerId || 'bonus_payment',
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, {merge: true});
  batch.set(db.collection('payments').doc(String(orderId)), {
    status: 'paid',
    paymentStatus: 'paid',
    provider: 'bonus',
    paidAt: admin.firestore.FieldValue.serverTimestamp(),
    reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
    reviewedBy: reviewerId || 'bonus_payment',
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, {merge: true});
  await batch.commit();
  await updatePendingOffersForScope('schedule_slot', slotId, payload);
  return {ok: true, orderId, slotId, merged: true};
}

async function reviewAddonRequestPaymentInternal({paymentId, approved, reviewerId, note = null}) {
  const paymentRef = db.collection('payments').doc(String(paymentId));
  let addonRequestId = null;
  await db.runTransaction(async (tx) => {
    const paymentSnap = await tx.get(paymentRef);
    if (!paymentSnap.exists) {
      throw new HttpsError('not-found', 'Payment not found');
    }
    const payment = paymentSnap.data() || {};
    addonRequestId = String(payment.addonRequestId || '').trim();
    if (!addonRequestId) {
      throw new HttpsError('failed-precondition', 'Payment is not addon request');
    }
    const bonusAppliedAmount = Math.max(0, Number(payment.bonusAppliedAmount || 0));
    const paymentCustomerId = String(payment.customerId || '').trim();
    tx.set(paymentRef, {
      status: approved ? 'paid' : 'failed',
      reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
      reviewedBy: reviewerId,
      reviewNote: note || null,
      paidAt: approved ? admin.firestore.FieldValue.serverTimestamp() : null,
      bonusSettledAt: approved && bonusAppliedAmount > 0
        ? admin.firestore.FieldValue.serverTimestamp()
        : null,
      bonusRefundedAt: !approved && bonusAppliedAmount > 0
        ? admin.firestore.FieldValue.serverTimestamp()
        : null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});
    tx.set(db.collection('addon_requests').doc(addonRequestId), {
      status: approved ? 'payment_confirmed' : 'payment_rejected',
      reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
      reviewedBy: reviewerId,
      reviewNote: note || null,
      bonusSettledAt: approved && bonusAppliedAmount > 0
        ? admin.firestore.FieldValue.serverTimestamp()
        : null,
      bonusRefundedAt: !approved && bonusAppliedAmount > 0
        ? admin.firestore.FieldValue.serverTimestamp()
        : null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});
    if (!approved && bonusAppliedAmount > 0 && paymentCustomerId) {
      tx.set(db.collection('customers').doc(paymentCustomerId), {
        bonusPoints: admin.firestore.FieldValue.increment(bonusAppliedAmount),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      }, {merge: true});
    }
  });
  if (approved) {
    await applyAddonRequestToSlot(addonRequestId, reviewerId);
  } else {
    await rollbackAddonRequestFromSlot(addonRequestId, reviewerId);
  }
  return {ok: true, addonRequestId};
}

async function recalculateScheduleAfterAddonInternal(orderId) {
  if (!orderId) {
    throw new HttpsError('invalid-argument', 'orderId required');
  }
  const orderSnap = await db.collection('customer_orders').doc(String(orderId)).get();
  if (!orderSnap.exists) {
    throw new HttpsError('not-found', 'Order not found');
  }
  const order = {id: orderSnap.id, ...orderSnap.data()};
  const metrics = buildSchedulerMetrics(order);
  const slotsSnap = await db.collection('schedule_slots')
    .where('sourceOrderId', '==', String(orderId))
    .get();
  const batch = db.batch();
  batch.set(orderSnap.ref, {
    estimatedDurationMinutes: metrics.estimatedDurationMinutes,
    estimatedDurationHours: metrics.estimatedDurationHours,
    addonCount: metrics.addonCount,
    addonBufferMinutes: metrics.addonBufferMinutes,
    travelTimeMinutes: metrics.travelTimeMinutes,
    totalDurationMinutes: metrics.totalDurationMinutes,
    totalDurationHours: metrics.totalDurationHours,
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, {merge: true});
  for (const doc of slotsSnap.docs) {
    batch.set(doc.ref, {
      estimatedDurationMinutes: metrics.estimatedDurationMinutes,
      estimatedDurationHours: metrics.estimatedDurationHours,
      addonCount: metrics.addonCount,
      addonBufferMinutes: metrics.addonBufferMinutes,
      travelTimeMinutes: metrics.travelTimeMinutes,
      totalDurationMinutes: metrics.totalDurationMinutes,
      totalDurationHours: metrics.totalDurationHours,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});
  }
  await batch.commit();

  if (order.cleanerId) {
    await sendPushToUser(
      String(order.cleanerId),
      'Расписание обновлено',
      'У клиента изменились доп. услуги. Проверьте длительность уборки.',
      {type: 'cleaner_schedule_update', orderId: String(orderId)}
    );
  }

  return {
    ok: true,
    orderId: String(orderId),
    slotCount: slotsSnap.size,
    ...metrics
  };
}

async function notifyClientDelayInternal({
  orderId,
  mode = 'delay',
  minutes = 0,
  customBody = null
}) {
  const orderSnap = await db.collection('customer_orders').doc(String(orderId)).get();
  if (!orderSnap.exists) {
    throw new HttpsError('not-found', 'Order not found');
  }
  const order = orderSnap.data() || {};
  if (!order.customerId) {
    return {ok: true, skipped: true};
  }
  let body = customBody;
  if (!body) {
    if (mode === 'early') {
      body = `Уборщица может приехать раньше. Подготовьтесь за 1 час до визита.`;
    } else if (mode === 'home_1h') {
      body = `До уборки остался 1 час. Пожалуйста, будьте дома к началу визита.`;
    } else if (mode === 'addons_update') {
      body = `В заказе появились новые доп. услуги. Проверьте обновленные детали визита.`;
    } else {
      body = minutes > 0
        ? `Уборщица задерживается примерно на ${minutes} мин.`
        : 'Время визита обновлено. Проверьте детали заказа.';
    }
  }
  await sendPushToUser(
    String(order.customerId),
    'Обновление по уборке Domly',
    body,
    {type: 'cleaning_schedule_update', orderId: String(orderId), mode: String(mode)}
  );
  return {ok: true};
}

async function notifyCleanerUpdateInternal({
  orderId,
  customBody = null,
  type = 'schedule_update'
}) {
  const orderSnap = await db.collection('customer_orders').doc(String(orderId)).get();
  if (!orderSnap.exists) {
    throw new HttpsError('not-found', 'Order not found');
  }
  const order = orderSnap.data() || {};
  if (!order.cleanerId) {
    return {ok: true, skipped: true};
  }
  const body = customBody || 'В расписании есть изменения. Проверьте заказ и календарь.';
  await sendPushToUser(
    String(order.cleanerId),
    'Обновление расписания Domly Pro',
    body,
    {type: String(type), orderId: String(orderId)}
  );
  return {ok: true};
}

function normalizeOrderDate(value) {
  if (value instanceof admin.firestore.Timestamp) {
    return value.toDate();
  }
  if (value instanceof Date) {
    return value;
  }
  if (value && typeof value.toDate === 'function') {
    return value.toDate();
  }
  const parsed = new Date(value || Date.now());
  return Number.isNaN(parsed.getTime()) ? new Date() : parsed;
}

function fairnessSeed(input) {
  const source = String(input || '');
  let hash = 0;
  for (let index = 0; index < source.length; index += 1) {
    hash = ((hash << 5) - hash) + source.charCodeAt(index);
    hash |= 0;
  }
  return (Math.abs(hash) % 10000) / 10000;
}

function pickWeightedCleaner(candidates, seedInput) {
  if (candidates.length === 0) {
    return null;
  }
  const weights = candidates.map((candidate) => 1 / Math.max(Number(candidate.score.totalScore || 0), 0.0001));
  const totalWeight = weights.reduce((sum, weight) => sum + weight, 0);
  let pivot = fairnessSeed(seedInput) * totalWeight;
  for (let index = 0; index < candidates.length; index += 1) {
    pivot -= weights[index];
    if (pivot <= 0) {
      return candidates[index];
    }
  }
  return candidates[0];
}

async function logAssignmentDecision(type, payload) {
  try {
    await db.collection('admin_actions').add({
      type,
      payload,
      createdAt: admin.firestore.FieldValue.serverTimestamp()
    });
  } catch (error) {
    console.error('Failed to log assignment decision', error);
  }
}

async function logAdminNotification(type, payload = {}) {
  try {
    await db.collection('admin_actions').add({
      type,
      payload,
      status: 'new',
      createdAt: admin.firestore.FieldValue.serverTimestamp()
    });
  } catch (error) {
    console.error('Failed to log admin notification', error);
  }
}

function notificationDedupeId(type, parts = []) {
  return [type, ...parts]
    .map((part) => String(part || '').trim().replace(/[^A-Za-z0-9_-]+/g, '_'))
    .filter(Boolean)
    .join('__')
    .slice(0, 900);
}

async function shouldSendNotificationOnce(type, parts = []) {
  const dedupeId = notificationDedupeId(type, parts);
  if (!dedupeId) {
    return true;
  }
  const ref = db.collection('notification_dedupe').doc(dedupeId);
  try {
    await ref.create({
      type,
      parts: parts.map((part) => String(part || '')),
      createdAt: admin.firestore.FieldValue.serverTimestamp()
    });
    return true;
  } catch (error) {
    if (String(error?.code || '').includes('already-exists') || error?.code === 6) {
      return false;
    }
    console.error('Failed to write notification dedupe marker', error);
    return true;
  }
}

async function getCleanerMonthlyStats(cleanerId, referenceDate) {
  const monthStart = startOfMonth(referenceDate);
  const monthEnd = endOfMonth(referenceDate);
  const snap = await db.collection('customer_orders')
    .where('cleanerId', '==', cleanerId)
    .get();

  const stats = {
    area: 0,
    hours: 0,
    income: 0,
    apartments: 0
  };

  for (const doc of snap.docs) {
    const order = doc.data();
    const orderDate = normalizeOrderDate(order.date || order.createdAt);
    if (orderDate < monthStart || orderDate > monthEnd) {
      continue;
    }
    if (['canceled'].includes(String(order.orderStatus || order.status || ''))) {
      continue;
    }
    const area = Number(order.area || order.form?.area || 0);
    stats.area += area;
    stats.hours += Number(order.estimatedDurationHours || estimateCleaningDuration(area));
    stats.income += Number(order.price || 0);
    stats.apartments += 1;
  }

  return stats;
}

async function getCleanerDayAssignments(cleanerId, referenceDate) {
  const targetDateKey = toIsoDate(referenceDate);
  const snap = await db.collection('customer_orders')
    .where('cleanerId', '==', cleanerId)
    .get();

  const assignments = [];
  for (const doc of snap.docs) {
    const order = doc.data();
    const orderDate = normalizeOrderDate(order.date || order.createdAt);
    if (toIsoDate(orderDate) !== targetDateKey) {
      continue;
    }
    if (['canceled'].includes(String(order.orderStatus || order.status || ''))) {
      continue;
    }
    const area = Number(order.area || order.form?.area || 0);
    assignments.push({
      id: doc.id,
      time: String(order.time || '10:00 - 13:00'),
      range: buildAssignmentRange(order),
      area,
      hours: Number(order.estimatedDurationHours || estimateCleaningDuration(area)),
      minutes: Number(order.totalDurationMinutes || order.estimatedDurationMinutes || estimateCleaningDurationMinutes(area)),
      price: Number(order.price || 0)
    });
  }
  return assignments;
}

async function getCleanerAssignmentsForDate(cleanerId, referenceDate, options = {}) {
  const [slotAssignments, orderAssignments] = await Promise.all([
    getCleanerScheduledSlots(cleanerId, referenceDate, {
      excludeSlotId: options.excludeSlotId || null
    }),
    getCleanerDayAssignments(cleanerId, referenceDate)
  ]);
  const excludeOrderId = options.excludeOrderId ? String(options.excludeOrderId) : null;
  const seen = new Set();
  const merged = [];
  for (const item of [...slotAssignments, ...orderAssignments]) {
    const itemId = String(item.id || '');
    if (!itemId || seen.has(itemId) || (excludeOrderId && itemId === excludeOrderId)) {
      continue;
    }
    seen.add(itemId);
    merged.push(item);
  }
  return merged.sort((left, right) => left.range.startMinutes - right.range.startMinutes);
}

function calculateCleanerFairnessScore({
  cleaner,
  order,
  monthStats,
  monthlyTargets,
  dayAssignments,
  cluster,
  entrance
}) {
  const orderArea = Number(order.area || order.form?.area || 0);
  const orderMetrics = buildSchedulerMetrics(order);
  const orderMinutes = orderMetrics.totalDurationMinutes;
  const orderHours = Number((orderMinutes / 60).toFixed(2));
  const orderIncome = Number(order.price || 0);
  const orderRange = buildAssignmentRange({
    ...order,
    estimatedDurationMinutes: orderMetrics.estimatedDurationMinutes,
    totalDurationMinutes: orderMinutes
  });
  const dayArea = dayAssignments.reduce((sum, item) => sum + Number(item.area || 0), 0);
  const dayMinutes = dayAssignments.reduce((sum, item) =>
    sum + Number(item.minutes || Math.round(Number(item.hours || 0) * 60)), 0);
  const hasTimeConflict = dayAssignments.some((item) => timeRangesOverlap(item.range, orderRange));
  const dailyLimitMinutes = cleanerDailyLimitMinutes(cleaner);
  const dailyLimit = dailyLimitMinutes / 60;
  const fitsDailyAreaLimit = true;
  const overDailyAreaLimit = (dayArea + orderArea) > (DAILY_AREA_LIMIT_SQM + DAILY_AREA_OVERBOOK_TOLERANCE_SQM);
  const fitsDailyLimit = (dayMinutes + orderMinutes) <= dailyLimitMinutes;
  const entrances = Array.isArray(cleaner.assignedEntrances) ? cleaner.assignedEntrances.map(String) : [];
  const sameEntrance = entrance != null && entrances.includes(String(entrance));
  const sameCluster = cluster != null && String(cleaner.clusterName || '') === String(cluster.name || '');
  const districtPenalty = sameEntrance ? -0.15 : sameCluster ? 0 : 0.35;
  const projectedArea = monthStats.area + orderArea;
  const projectedHours = monthStats.hours + orderHours;
  const projectedIncome = monthStats.income + orderIncome;
  const projectedApartments = monthStats.apartments + 1;
  const targetArea = Math.max(monthlyTargets.area, 1);
  const targetHours = Math.max(monthlyTargets.hours, 1);
  const targetIncome = Math.max(monthlyTargets.income, 1);
  const targetApartments = Math.max(monthlyTargets.apartments, 1);
  const addonBucket = classifyAddonBucket(order);
  const cleanerStatus = cleaner.cleanerStatus || CLEANER_STATUSES.NEWBIE;
  const statusPriority = CLEANER_STATUS_PRIORITY[cleanerStatus] || 1;

  const areaDeviation = Math.abs(projectedArea - targetArea) / targetArea;
  const hoursDeviation = Math.abs(projectedHours - targetHours) / targetHours;
  const incomeDeviation = Math.abs(projectedIncome - targetIncome) / targetIncome;
  const apartmentsDeviation = Math.abs(projectedApartments - targetApartments) / targetApartments;
  const statusPenalty =
    addonBucket === 'high' ? ((5 - statusPriority) / 4) :
    addonBucket === 'medium' ? ((5 - statusPriority) / 8) :
    0;

  const totalScore =
    areaDeviation * FAIRNESS_WEIGHTS.area +
    hoursDeviation * FAIRNESS_WEIGHTS.hours +
    incomeDeviation * FAIRNESS_WEIGHTS.income +
    apartmentsDeviation * FAIRNESS_WEIGHTS.apartments +
    districtPenalty * FAIRNESS_WEIGHTS.district +
    statusPenalty * FAIRNESS_WEIGHTS.status;

  return {
    cleanerId: cleaner.id,
    totalScore,
    hasTimeConflict,
    fitsDailyAreaLimit,
    overDailyAreaLimit,
    fitsDailyLimit,
    reasons: [
      `areaDeviation=${areaDeviation.toFixed(4)}`,
      `hoursDeviation=${hoursDeviation.toFixed(4)}`,
      `incomeDeviation=${incomeDeviation.toFixed(4)}`,
      `apartmentsDeviation=${apartmentsDeviation.toFixed(4)}`,
      `districtPenalty=${districtPenalty.toFixed(4)}`,
      `addonBucket=${addonBucket}`,
      `cleanerStatus=${cleanerStatus}`,
      `statusPenalty=${statusPenalty.toFixed(4)}`,
      `projectedDayArea=${(dayArea + orderArea).toFixed(0)}/${DAILY_AREA_LIMIT_SQM}`,
      `projectedDayHours=${((dayMinutes + orderMinutes) / 60).toFixed(2)}/${dailyLimit.toFixed(2)}`
    ],
    snapshot: {
      monthStats,
      monthlyTargets,
      dayArea,
      dayHours: Number((dayMinutes / 60).toFixed(2)),
      dayMinutes,
      orderArea,
      orderHours,
      orderMinutes,
      orderIncome,
      addonBucket,
      cleanerStatus,
      sameCluster,
      sameEntrance
    }
  };
}

async function evaluateCleanerAssignmentCandidate({
  cleaner,
  scope,
  targetDate,
  assignmentType,
  monthStats = null,
  dayAssignments = null,
  requireServiceArea = true
}) {
  const normalizedDate = startOfDay(targetDate);
  const scheduledAt = resolveScopeScheduledAt(scope);
  const scopeArea = Number(scope.area || scope.form?.area || 0);
  const scopeMetrics = buildSchedulerMetrics(scope);
  const cleanerAssignments = dayAssignments || await getCleanerAssignmentsForDate(
    cleaner.id,
    normalizedDate,
    {
      excludeSlotId: scope.scopeType === 'schedule_slot' ? scope.id : null,
      excludeOrderId: scope.scopeType === 'order' ? scope.id : null
    }
  );
  const cleanerMonthStats = monthStats || await getCleanerMonthlyStats(cleaner.id, normalizedDate);
  const dayArea = cleanerAssignments.reduce((sum, item) => sum + Number(item.area || 0), 0);
  const dayMinutes = cleanerAssignments.reduce((sum, item) => sum + Number(item.minutes || 0), 0);
  const dailyAreaLimit = cleanerDailyAreaLimit(cleaner);
  const dailyLimitMinutes = cleanerDailyLimitMinutes(cleaner);
  const travelMinutes = estimateTravelMinutes({
    cleaner,
    scope,
    dayAssignments: cleanerAssignments
  });
  const prepMinutes = assignmentType === 'today' ? URGENT_ORDER_PREP_BUFFER_MINUTES : 0;
  const now = new Date();
  const minutesUntilStart = Math.round((scheduledAt.getTime() - now.getTime()) / 60000);
  const statusEligible = cleanerStatusEligibleForAssignment(cleaner, assignmentType);
  const worksThatDay = cleanerWorksOnDate(cleaner, normalizedDate);
  const sameServiceArea = serviceAreaMatches(cleaner, scope);
  const hasConflict = cleanerAssignments.some((item) =>
    timeRangesOverlap(item.range, buildAssignmentRange(scope))
  );
  const projectedArea = dayArea + scopeArea;
  const projectedMinutes = dayMinutes + scopeMetrics.totalDurationMinutes;
  const fitsAreaLimit = true;
  const overAreaLimit = projectedArea > (dailyAreaLimit + DAILY_AREA_OVERBOOK_TOLERANCE_SQM);
  const fitsHourLimit = projectedMinutes <= dailyLimitMinutes;
  const canReachToday = assignmentType !== 'today' || minutesUntilStart >= 0;
  const rating = Number(
    cleaner.currentRating ||
    cleaner.averageRating30d ||
    cleaner.averageRating90d ||
    cleaner.rating ||
    5
  );
  const rank = CLEANER_STATUS_PRIORITY[cleaner.cleanerStatus || CLEANER_STATUSES.NEWBIE] || 1;
  const completedOrders = Number(cleaner.completedOrdersCount || cleaner.jobsCount || 0);
  const complaints = Number(cleaner.complaintsCount || 0);
  const cancellations = Number(cleaner.cancellationCount || 0);
  const fillScore = Math.max(0, 1 - (Math.abs(dailyAreaLimit - projectedArea) / Math.max(dailyAreaLimit, 1)));
  const workloadPenalty = (projectedArea / Math.max(dailyAreaLimit, 1)) * 14;
  const score =
    (Math.max(0, 45 - travelMinutes) * 1.15) +
    (Math.max(0, Math.min(rating, 5)) * 10) +
    (rank * 8) +
    (sameServiceArea ? 12 : 0) +
    Math.min(completedOrders, 120) * 0.12 +
    (fillScore * 20) -
    (complaints * 3) -
    (cancellations * 2) -
    workloadPenalty;

  const eligible =
    statusEligible &&
    worksThatDay &&
    (!requireServiceArea || sameServiceArea) &&
    !hasConflict &&
    fitsHourLimit &&
    canReachToday;

  return {
    cleanerId: cleaner.id,
    eligible,
    score: Number(score.toFixed(4)),
    travelMinutes,
    projectedArea,
    projectedMinutes,
    dailyAreaLimit,
    dailyLimitMinutes,
    assignmentType,
    reasons: {
      statusEligible,
      worksThatDay,
      sameServiceArea,
      hasConflict,
      fitsAreaLimit,
      overAreaLimit,
      fitsHourLimit,
      canReachToday,
      rating,
      rank,
      completedOrders,
      complaints,
      cancellations,
      fillScore: Number(fillScore.toFixed(4)),
      workloadPenalty: Number(workloadPenalty.toFixed(4)),
      minutesUntilStart,
      travelMinutes,
      prepMinutes
    }
  };
}

async function findCleanerCandidatesInternal({
  scope,
  preferredCleanerId = null,
  excludeCleanerIds = []
}) {
  const cleanersSnap = await db.collection('cleaners')
    .where('verificationStatus', '==', 'approved')
    .limit(80)
    .get();
  const allApprovedCleaners = cleanersSnap.docs.map((doc) => ({id: doc.id, ...doc.data()}));
  const requestedCity = resolveExplicitCityFromSource(scope);
  const cityCleaners = filterCleanersByCity(allApprovedCleaners, requestedCity);
  const excluded = new Set(excludeCleanerIds.map((item) => String(item || '')));
  const serviceAreaCleaners = filterCleanersByServiceArea(cityCleaners, scope)
    .filter((cleaner) => !excluded.has(String(cleaner.id || '')));
  const usingServiceAreaFallback = serviceAreaCleaners.length === 0;
  const cleaners = (usingServiceAreaFallback ? cityCleaners : serviceAreaCleaners)
    .filter((cleaner) => !excluded.has(String(cleaner.id || '')));
  if (cleaners.length === 0) {
    return [];
  }

  const scheduledAt = resolveScopeScheduledAt(scope);
  const assignmentType = assignmentTypeForDate(scheduledAt);
  const referenceDate = startOfDay(scheduledAt);
  const candidates = await Promise.all(
    cleaners.map(async (cleaner) => {
      const [monthStats, dayAssignments] = await Promise.all([
        getCleanerMonthlyStats(cleaner.id, referenceDate),
        getCleanerAssignmentsForDate(cleaner.id, referenceDate, {
          excludeSlotId: scope.scopeType === 'schedule_slot' ? scope.id : null,
          excludeOrderId: scope.scopeType === 'order' ? scope.id : null
        })
      ]);
      const evaluation = await evaluateCleanerAssignmentCandidate({
        cleaner,
        scope,
        targetDate: referenceDate,
        assignmentType,
        monthStats,
        dayAssignments,
        requireServiceArea: !usingServiceAreaFallback
      });
      return {
        cleaner,
        monthStats,
        dayAssignments,
        evaluation
      };
    })
  );

  const ranked = candidates
    .filter((item) => item.evaluation.eligible)
    .sort((left, right) => {
      if (String(left.cleaner.id || '') === String(preferredCleanerId || '')) {
        return -1;
      }
      if (String(right.cleaner.id || '') === String(preferredCleanerId || '')) {
        return 1;
      }
      const leftTravel = Number.isFinite(Number(left.evaluation.travelMinutes))
        ? Number(left.evaluation.travelMinutes)
        : Number.MAX_SAFE_INTEGER;
      const rightTravel = Number.isFinite(Number(right.evaluation.travelMinutes))
        ? Number(right.evaluation.travelMinutes)
        : Number.MAX_SAFE_INTEGER;
      if (leftTravel !== rightTravel) {
        return leftTravel - rightTravel;
      }
      return right.evaluation.score - left.evaluation.score;
    });

  return ranked.slice(0, ASSIGNMENT_WAVE_SIZE).map((item) => ({
    cleanerId: item.cleaner.id,
    cleanerName: item.cleaner.name || 'Исполнитель',
    serviceAreaFallback: usingServiceAreaFallback,
    assignmentType,
    score: item.evaluation.score,
    travelMinutes: item.evaluation.travelMinutes,
    projectedArea: item.evaluation.projectedArea,
    projectedMinutes: item.evaluation.projectedMinutes,
    availabilityStatus: normalizeCleanerAvailabilityStatus(
      item.cleaner.availabilityStatus || item.cleaner.operationalStatus || item.cleaner.status
    ),
    reasons: item.evaluation.reasons
  }));
}

function resolveUserTier(monthlySpent = 0, monthlyOrders = 0) {
  const spent = Number(monthlySpent || 0);
  let resolved = USER_TIER_RULES[0];
  for (const rule of USER_TIER_RULES) {
    if (spent >= rule.minSpent) {
      resolved = rule;
    }
  }
  return resolved;
}

function nextTierRule(currentTier) {
  const index = USER_TIER_RULES.findIndex((rule) => rule.tier === currentTier);
  if (index < 0 || index >= USER_TIER_RULES.length - 1) {
    return null;
  }
  return USER_TIER_RULES[index + 1];
}

function userTierLabel(tier) {
  switch (String(tier || '')) {
    case USER_TIERS.CLEANSTER:
      return 'Наш любимый чистюля';
    case USER_TIERS.GURU:
      return 'Гуру чистоты';
    case USER_TIERS.GOD:
      return 'Бог чистоты';
    default:
      return 'Наш любимый Новичок';
  }
}

function buildUserProgressSnapshot(profile, now = new Date()) {
  const spent = Number(profile.monthly_spent || 0);
  const orders = Number(profile.monthly_orders || 0);
  const currentRule = resolveUserTier(spent, orders);
  const nextRule = nextTierRule(currentRule.tier);
  const currentMin = Number(currentRule.minSpent || 0);
  const currentMax = nextRule ? Number(nextRule.minSpent || currentMin) : null;
  const spentInsideTier = Math.max(spent - currentMin, 0);
  const tierRange = currentMax == null ? null : Math.max(currentMax - currentMin, 1);
  const progress = currentMax == null ? 1 : Math.min(spentInsideTier / tierRange, 1);
  return {
    current_tier: currentRule.tier,
    next_tier: nextRule?.tier || null,
    monthly_spent: spent,
    monthly_orders: orders,
    progress,
    current_tier_min_spent: currentMin,
    current_tier_max_spent: currentMax,
    tier_discount_percent: Number(currentRule.discountPercent || 0),
    next_tier_threshold: nextRule ? Number(nextRule.minSpent || 0) : null,
    next_tier_discount_percent: nextRule ? Number(nextRule.discountPercent || 0) : null,
    remaining_amount: nextRule ? Math.max(nextRule.minSpent - spent, 0) : 0,
    days_left: daysLeftInMonth(now),
    month_key: monthKey(now)
  };
}

function parseFrequencyConfig(frequencyLabel, packageName = '') {
  const source = String(frequencyLabel || packageName || '').toLowerCase();
  const isQuarter = source.includes('кварт');
  let config = null;
  if (
    source.includes('8/месяц') ||
    source.includes('8 раз/месяц') ||
    source.includes('8 раз в месяц') ||
    source.includes('2 раза в неделю')
  ) {
    config = {kind: 'monthly', intervalDays: 3, slotsAhead: 9, monthlyVisits: 8};
  } else if (
    source.includes('4/месяц') ||
    source.includes('4 раза/месяц') ||
    source.includes('4 раза в месяц') ||
    source.includes('раз в неделю')
  ) {
    config = {kind: 'monthly', intervalDays: 7, slotsAhead: 5, monthlyVisits: 4};
  } else if (
    source.includes('2/месяц') ||
    source.includes('2 раза/месяц') ||
    source.includes('2 раза в месяц') ||
    source.includes('два раза в месяц')
  ) {
    config = {kind: 'monthly', intervalDays: 14, slotsAhead: 3, monthlyVisits: 2};
  } else if (source.includes('кварт')) {
    config = {kind: 'monthly', intervalDays: 7, slotsAhead: 5, monthlyVisits: 4};
  } else {
    config = {kind: 'one_time', intervalDays: 0, slotsAhead: 1, monthlyVisits: 1};
  }

  if (isQuarter && config.kind !== 'one_time') {
    return {
      ...config,
      kind: 'quarter',
      billingPeriodMonths: 3
    };
  }
  return {
    ...config,
    billingPeriodMonths: 1
  };
}

async function detectClusterForOrder(order) {
  const clusterId = order.clusterId || null;
  if (clusterId) {
    const clusterSnap = await db.collection('clusters').doc(clusterId).get();
    if (clusterSnap.exists) {
      return {id: clusterSnap.id, ...clusterSnap.data()};
    }
  }

  const residentialComplex = order.residentialComplex || '';
  if (!residentialComplex) {
    return null;
  }

  const clusterSnap = await db
    .collection('clusters')
    .where('residentialComplex', '==', residentialComplex)
    .limit(1)
    .get();

  if (clusterSnap.empty) {
    return null;
  }

  const doc = clusterSnap.docs[0];
  return {id: doc.id, ...doc.data()};
}

async function findCleanerForCluster(cluster, entrance = null, preferredCleanerId = null, orderContext = null) {
  const requiredCity = resolveCityFromSource(orderContext || {});
  if (preferredCleanerId) {
    const preferredSnap = await db.collection('cleaners').doc(preferredCleanerId).get();
    if (preferredSnap.exists) {
      const preferred = {id: preferredSnap.id, ...preferredSnap.data()};
      if (orderContext && !serviceAreaMatches(preferred, orderContext)) {
        throw new HttpsError(
          'failed-precondition',
          'Нельзя назначить уборщицу вне ее рабочего района.'
        );
      }
      if (requiredCity && resolveCityFromSource(preferred) !== requiredCity) {
        throw new HttpsError(
          'failed-precondition',
          'Нельзя назначить уборщицу из другого города.'
        );
      }
      if (!orderContext) {
        return preferred;
      }
      const dayAssignments = await getCleanerDayAssignments(
        preferred.id,
        normalizeOrderDate(orderContext.date || orderContext.scheduledFor || new Date())
      );
      const preferredScore = calculateCleanerFairnessScore({
        cleaner: preferred,
        order: orderContext,
        monthStats: await getCleanerMonthlyStats(
          preferred.id,
          normalizeOrderDate(orderContext.date || orderContext.scheduledFor || new Date())
        ),
        monthlyTargets: {area: 1, hours: 1, income: 1, apartments: 1},
        dayAssignments,
        cluster,
        entrance
      });
      if (!preferredScore.hasTimeConflict && preferredScore.fitsDailyLimit) {
        return preferred;
      }
    }
  }

  if (!cluster) {
    return null;
  }

  let query = db.collection('cleaners')
    .where('clusterName', '==', cluster.name)
    .where('verificationStatus', '==', 'approved')
    .limit(20);

  const cleanersSnap = await query.get();
  if (cleanersSnap.empty) {
    return null;
  }

  const cleaners = filterCleanersByServiceArea(filterCleanersByCity(
    cleanersSnap.docs.map((doc) => ({id: doc.id, ...doc.data()})),
    requiredCity
  ), orderContext || {
    clusterName: cluster?.name || null,
    residentialComplex: cluster?.residentialComplex || null
  });
  if (cleaners.length === 0) {
    return null;
  }
  if (entrance != null) {
    const exact = cleaners.find((cleaner) => {
      const entrances = Array.isArray(cleaner.assignedEntrances) ? cleaner.assignedEntrances : [];
      return entrances.map(String).includes(String(entrance));
    });
    if (exact && !orderContext) {
      return exact;
    }
  }

  if (!orderContext) {
    cleaners.sort((a, b) => Number(a.jobsCount || 0) - Number(b.jobsCount || 0));
    return cleaners[0];
  }

  const referenceDate = normalizeOrderDate(orderContext.date || orderContext.scheduledFor || new Date());
  const monthlyStatsEntries = await Promise.all(
    cleaners.map(async (cleaner) => ({
      cleaner,
      monthStats: await getCleanerMonthlyStats(cleaner.id, referenceDate),
      dayAssignments: await getCleanerDayAssignments(cleaner.id, referenceDate)
    }))
  );

  const monthlyTargets = monthlyStatsEntries.reduce((acc, item) => {
    acc.area += item.monthStats.area;
    acc.hours += item.monthStats.hours;
    acc.income += item.monthStats.income;
    acc.apartments += item.monthStats.apartments;
    return acc;
  }, {area: 0, hours: 0, income: 0, apartments: 0});
  monthlyTargets.area /= Math.max(monthlyStatsEntries.length, 1);
  monthlyTargets.hours /= Math.max(monthlyStatsEntries.length, 1);
  monthlyTargets.income /= Math.max(monthlyStatsEntries.length, 1);
  monthlyTargets.apartments /= Math.max(monthlyStatsEntries.length, 1);

  const ranked = monthlyStatsEntries.map((item) => ({
    cleaner: item.cleaner,
    score: calculateCleanerFairnessScore({
      cleaner: item.cleaner,
      order: orderContext,
      monthStats: item.monthStats,
      monthlyTargets,
      dayAssignments: item.dayAssignments,
      cluster,
      entrance
    })
  }))
    .filter((item) => !item.score.hasTimeConflict && item.score.fitsDailyLimit)
    .sort((left, right) => left.score.totalScore - right.score.totalScore);

  const pool = ranked.slice(0, Math.min(3, ranked.length));
  const selected = pickWeightedCleaner(
    pool,
    `${orderContext.id || ''}_${toIsoDate(referenceDate)}_${orderContext.time || ''}`
  );
  if (!selected) {
    return null;
  }

  await logAssignmentDecision('fair_assignment_decision', {
    orderId: orderContext.id || null,
    cleanerId: selected.cleaner.id,
    ranked: ranked.map((item) => ({
      cleanerId: item.cleaner.id,
      totalScore: Number(item.score.totalScore.toFixed(6)),
      reasons: item.score.reasons
    }))
  });

  return selected.cleaner;
}

async function createScheduleSlotsForSubscription(subscriptionId, order, options = {}) {
  if (order.scheduleSelectionRequired === true) {
    await refreshSubscriptionUsage(subscriptionId);
    return;
  }
  const now = startOfDay();
  const frequency = parseFrequencyConfig(order.frequencyLabel, order.package);
  const existingSlotsSnap = await db.collection('schedule_slots')
    .where('subscriptionId', '==', subscriptionId)
    .get();
  const existingSlots = existingSlotsSnap.docs.map((doc) => ({id: doc.id, ...doc.data()}));
  const validFrom = order.validFrom instanceof admin.firestore.Timestamp ?
    startOfDay(order.validFrom.toDate()) :
    order.validFrom ? startOfDay(new Date(order.validFrom)) :
    now;
  const validUntil = order.validUntil instanceof admin.firestore.Timestamp ?
    startOfDay(order.validUntil.toDate()) :
    order.validUntil ? startOfDay(new Date(order.validUntil)) :
    startOfDay(addMonths(
      validFrom,
      Number(order.billingPeriodMonths || frequency.billingPeriodMonths || SUBSCRIPTION_TERM_MONTHS)
    ));
  const windowUntil = addDays(now, SUBSCRIPTION_WINDOW_DAYS);
  const generationUntil = validUntil < windowUntil ? validUntil : windowUntil;
  const startDate = options.startDate ? startOfDay(new Date(options.startDate)) : validFrom;
  const expectedIncludedVisits = frequency.kind === 'one_time'
    ? 1
    : Number(frequency.monthlyVisits || 1) * Number(
      order.billingPeriodMonths || frequency.billingPeriodMonths || 1
    );
  const includedVisits = Math.max(Number(order.includedVisits || 0), expectedIncludedVisits);
  const existingDateKeys = new Set(existingSlots.map((slot) => String(slot.scheduledDateKey || '')));
  let plannedVisits = existingSlots.filter(slotConsumesVisit).length;
  plannedVisits += existingSlots.filter((slot) => {
    if (!activeSlotStatus(slot.status)) {
      return false;
    }
    return true;
  }).length;

  const cluster = await detectClusterForOrder(order);
  const cleaner = await findCleanerForCluster(
    cluster,
    order.entrance || null,
    order.cleanerId || null,
    order
  );
  const schedulerMetrics = buildSchedulerMetrics(order);

  const batch = db.batch();
  let cursor = startDate < validFrom ? validFrom : startDate;
  const intervalDays = frequency.kind === 'one_time' ? 0 : frequency.intervalDays;

  while (cursor <= generationUntil && plannedVisits < includedVisits) {
    const date = cursor;
    const scheduledDateKey = toIsoDate(date);
    if (existingDateKeys.has(scheduledDateKey)) {
      cursor = frequency.kind === 'one_time' ? addDays(cursor, 400) : addDays(cursor, intervalDays);
      continue;
    }
    const slotId = `${subscriptionId}_${toIsoDate(date)}`;
    const slotRef = db.collection('schedule_slots').doc(slotId);
    const slotSnap = await slotRef.get();
    if (slotSnap.exists) {
      existingDateKeys.add(scheduledDateKey);
      cursor = frequency.kind === 'one_time' ? addDays(cursor, 400) : addDays(cursor, intervalDays);
      continue;
    }

    const addonPayload = orderAddonPayload(order, order.pricing || {});
    const baseTime = order.time && order.time !== 'Ожидает оплаты' ? order.time : '10:00 - 13:00';
    const normalizedTime = buildTimeRangeForDuration(baseTime, schedulerMetrics.totalDurationMinutes);
    batch.set(slotRef, {
      subscriptionId,
      sourceOrderId: order.id || null,
      orderNumber: null,
      displayOrderId: null,
      customerId: order.customerId,
      customerName: order.customerName || null,
      cleanerId: null,
      cleanerName: null,
      preferredCleanerId: cleaner?.id || null,
      preferredCleanerName: cleaner?.name || null,
      clusterId: cluster?.id || null,
      clusterName: cluster?.name || null,
      houseId: order.houseId || null,
      houseStatus: order.houseStatus || null,
      serviceArea: order.serviceArea || null,
      serviceAreaId: order.serviceAreaId || null,
      zoneId: order.zoneId || null,
      residentialComplex: order.residentialComplex || cluster?.residentialComplex || null,
      entrance: order.entrance || null,
      apartment: order.apartment || null,
      address: order.address || null,
      frequencyLabel: order.frequencyLabel || null,
      package: order.package || null,
      accessMethod: order.accessMethod || null,
      ...addonPayload,
      area: Number(order.area || 0),
      estimatedDurationHours: schedulerMetrics.estimatedDurationHours,
      estimatedDurationMinutes: schedulerMetrics.estimatedDurationMinutes,
      addonCount: schedulerMetrics.addonCount,
      addonBufferMinutes: schedulerMetrics.addonBufferMinutes,
      travelTimeMinutes: schedulerMetrics.travelTimeMinutes,
      totalDurationMinutes: schedulerMetrics.totalDurationMinutes,
      totalDurationHours: schedulerMetrics.totalDurationHours,
      scheduledFor: admin.firestore.Timestamp.fromDate(date),
      scheduledDateKey: toIsoDate(date),
      time: normalizedTime,
      status: 'pending_assignment',
      assignmentStatus: ORDER_ASSIGNMENT_STATUSES.SEARCHING,
      remindersSent: [],
      createdAt: admin.firestore.FieldValue.serverTimestamp()
    });
    existingDateKeys.add(scheduledDateKey);
    plannedVisits += 1;
    cursor = frequency.kind === 'one_time' ? addDays(cursor, 400) : addDays(cursor, intervalDays);
  }

  batch.set(
    db.collection('subscriptions').doc(subscriptionId),
    {
      clusterId: cluster?.id || null,
      clusterName: cluster?.name || null,
      houseId: order.houseId || null,
      houseStatus: order.houseStatus || null,
      serviceArea: order.serviceArea || null,
      serviceAreaId: order.serviceAreaId || null,
      zoneId: order.zoneId || null,
      fixedCleanerId: cleaner?.id || null,
      fixedCleanerName: cleaner?.name || null,
      nextGenerationAt: admin.firestore.Timestamp.fromDate(addDays(windowUntil, -7)),
      includedVisits,
      validFrom: admin.firestore.Timestamp.fromDate(validFrom),
      validUntil: admin.firestore.Timestamp.fromDate(validUntil),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    },
    {merge: true}
  );

  await batch.commit();
  await refreshSubscriptionUsage(subscriptionId);
}

async function refreshSubscriptionUsage(subscriptionId) {
  const subscriptionRef = db.collection('subscriptions').doc(subscriptionId);
  const [subscriptionSnap, slotsSnap] = await Promise.all([
    subscriptionRef.get(),
    db.collection('schedule_slots').where('subscriptionId', '==', subscriptionId).get()
  ]);

  if (!subscriptionSnap.exists) {
    return;
  }

  const subscription = subscriptionSnap.data();
  const includedVisits = subscriptionIncludedVisits(subscription);
  const slots = slotsSnap.docs.map((doc) => doc.data());
  const completedVisits = slots.filter((slot) => String(slot.status || '') === 'completed').length;
  const forfeitedVisits = slots.filter((slot) =>
    String(slot.status || '') === 'canceled' && slot.cancellationPenaltyApplied === true
  ).length;
  const usedVisits = completedVisits + forfeitedVisits;
  const scheduledVisits = slots.filter((slot) => selectedSlotStatus(slot.status)).length;
  const totalRemainingVisits = Math.max(includedVisits - usedVisits, 0);
  const pendingSelectionsTotal = Math.max(includedVisits - usedVisits - scheduledVisits, 0);
  const currentPeriodUsage = getSubscriptionCurrentPeriodUsage(subscription, slots);
  const pendingSelections = Math.min(currentPeriodUsage.pendingSelections, pendingSelectionsTotal);

  await subscriptionRef.set({
    includedVisits,
    totalIncludedVisits: includedVisits,
    monthlyIncludedVisits: currentPeriodUsage.includedVisits,
    completedVisits,
    forfeitedVisits,
    usedVisits,
    totalRemainingVisits,
    remainingVisits: currentPeriodUsage.remainingVisits,
    scheduledVisits,
    selectedVisitsCount: scheduledVisits,
    currentPeriodKey: currentPeriodUsage.periodKey,
    currentPeriodStart: admin.firestore.Timestamp.fromDate(currentPeriodUsage.periodStart),
    currentPeriodEnd: admin.firestore.Timestamp.fromDate(currentPeriodUsage.periodEnd),
    currentPeriodIncludedVisits: currentPeriodUsage.includedVisits,
    currentPeriodCompletedVisits: currentPeriodUsage.completedVisits,
    currentPeriodForfeitedVisits: currentPeriodUsage.forfeitedVisits,
    currentPeriodUsedVisits: currentPeriodUsage.usedVisits,
    currentPeriodScheduledVisits: currentPeriodUsage.scheduledVisits,
    currentPeriodRemainingVisits: currentPeriodUsage.remainingVisits,
    currentPeriodPendingSelections: pendingSelections,
    scheduleSelectionRequired: pendingSelections > 0,
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, {merge: true});
}

async function notifyTierChange(userId, payload) {
  const title = payload.kind === 'downgraded' ? 'Статус понижен' : 'Новый статус';
  const toTierLabel = userTierLabel(payload.toTier);
  const body =
    payload.kind === 'downgraded'
      ? `Ваш статус изменен на ${toTierLabel}. Активность в новом месяце началась заново.`
      : `Ваш новый статус: ${toTierLabel}. Продолжайте, чтобы дойти до следующего уровня.`;

  await db.collection('notifications').add({
    userId,
    type: 'tier_change',
    title,
    body,
    payload,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    read: false
  });

  await sendPushToUser(userId, title, body, {
    type: 'tier_change',
    fromTier: payload.fromTier || '',
    toTier: payload.toTier || '',
    skipInbox: true
  });
}

async function calculateUserTierInternal(userId, options = {}) {
  const customerRef = db.collection('customers').doc(userId);
  const now = options.now instanceof Date ? options.now : new Date();
  let change = null;
  let progress = null;

  await db.runTransaction(async (tx) => {
    const customerSnap = await tx.get(customerRef);
    if (!customerSnap.exists) {
      throw new HttpsError('not-found', 'User not found');
    }

    const customer = customerSnap.data() || {};
    const currentMonthKey = monthKey(now);
    const storedMonthKey = customer.month_key || currentMonthKey;
    const normalizedSpent = storedMonthKey === currentMonthKey ? Number(customer.monthly_spent || 0) : 0;
    const normalizedOrders = storedMonthKey === currentMonthKey ? Number(customer.monthly_orders || 0) : 0;
    const previousTier = String(customer.tier || USER_TIERS.NEWBIE);
    const nextRule = resolveUserTier(normalizedSpent, normalizedOrders);

    progress = buildUserProgressSnapshot({
      monthly_spent: normalizedSpent,
      monthly_orders: normalizedOrders,
      tier: nextRule.tier
    }, now);

    tx.set(customerRef, {
      month_key: currentMonthKey,
      monthly_spent: normalizedSpent,
      monthly_orders: normalizedOrders,
      tier: nextRule.tier,
      next_tier_threshold: progress.next_tier_threshold,
      tier_discount_percent: progress.tier_discount_percent,
      tier_progress: progress.progress,
      tier_updated_at: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});

    if (previousTier !== nextRule.tier) {
      change = {
        fromTier: previousTier,
        toTier: nextRule.tier,
        kind: USER_TIER_RULES.findIndex((rule) => rule.tier === nextRule.tier) <
          USER_TIER_RULES.findIndex((rule) => rule.tier === previousTier)
          ? 'downgraded'
          : 'upgraded',
        monthKey: currentMonthKey
      };
      tx.set(db.collection('tier_events').doc(`${userId}_${currentMonthKey}_${Date.now()}`), {
        userId,
        ...change,
        monthly_spent: normalizedSpent,
        monthly_orders: normalizedOrders,
        createdAt: admin.firestore.FieldValue.serverTimestamp()
      });
    }
  });

  if (change) {
    await notifyTierChange(userId, change);
  }

  return progress;
}

async function applyPaidOrderUserMetrics(orderId, options = {}) {
  const orderRef = db.collection('customer_orders').doc(orderId);
  const now = options.now instanceof Date ? options.now : new Date();
  let userId = null;
  let change = null;
  let progress = null;

  await db.runTransaction(async (tx) => {
    const orderSnap = await tx.get(orderRef);
    if (!orderSnap.exists) {
      throw new HttpsError('not-found', 'Order not found');
    }
    const order = orderSnap.data() || {};
    if (order.monthlyMetricsApplied === true) {
      userId = order.customerId || null;
      return;
    }

    userId = order.customerId || null;
    if (!userId) {
      throw new HttpsError('failed-precondition', 'Order has no customerId');
    }

    const customerRef = db.collection('customers').doc(userId);
    const customerSnap = await tx.get(customerRef);
    if (!customerSnap.exists) {
      throw new HttpsError('not-found', 'Customer not found');
    }

    const customer = customerSnap.data() || {};
    const currentMonthKey = monthKey(now);
    const storedMonthKey = customer.month_key || currentMonthKey;
    const baseSpent = storedMonthKey === currentMonthKey ? Number(customer.monthly_spent || 0) : 0;
    const baseOrders = storedMonthKey === currentMonthKey ? Number(customer.monthly_orders || 0) : 0;
    const nextSpent = baseSpent + Number(order.price || 0);
    const nextOrders = baseOrders + 1;
    const previousTier = String(customer.tier || USER_TIERS.NEWBIE);
    const nextRule = resolveUserTier(nextSpent, nextOrders);

    progress = buildUserProgressSnapshot({
      monthly_spent: nextSpent,
      monthly_orders: nextOrders,
      tier: nextRule.tier
    }, now);

    tx.set(customerRef, {
      month_key: currentMonthKey,
      monthly_spent: nextSpent,
      monthly_orders: nextOrders,
      tier: nextRule.tier,
      total_spent: Number(customer.total_spent || 0) + Number(order.price || 0),
      next_tier_threshold: progress.next_tier_threshold,
      tier_discount_percent: progress.tier_discount_percent,
      tier_progress: progress.progress,
      tier_updated_at: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});

    tx.set(orderRef, {
      monthlyMetricsApplied: true,
      monthlyMetricsAppliedAt: admin.firestore.FieldValue.serverTimestamp(),
      month_key: currentMonthKey
    }, {merge: true});

    if (previousTier !== nextRule.tier) {
      change = {
        fromTier: previousTier,
        toTier: nextRule.tier,
        kind: USER_TIER_RULES.findIndex((rule) => rule.tier === nextRule.tier) <
          USER_TIER_RULES.findIndex((rule) => rule.tier === previousTier)
          ? 'downgraded'
          : 'upgraded',
        monthKey: currentMonthKey
      };
      tx.set(db.collection('tier_events').doc(`${userId}_${orderId}_${currentMonthKey}`), {
        userId,
        orderId,
        ...change,
        monthly_spent: nextSpent,
        monthly_orders: nextOrders,
        createdAt: admin.firestore.FieldValue.serverTimestamp()
      });
    }
  });

  if (userId && change) {
    await notifyTierChange(userId, change);
  }

  return progress;
}

async function getUserProgressInternal(userId, options = {}) {
  const now = options.now instanceof Date ? options.now : new Date();
  const customerSnap = await db.collection('customers').doc(userId).get();
  if (!customerSnap.exists) {
    throw new HttpsError('not-found', 'User not found');
  }
  const customer = customerSnap.data() || {};
  const currentMonthKey = monthKey(now);
  const storedMonthKey = customer.month_key || currentMonthKey;
  const normalized = {
    monthly_spent: storedMonthKey === currentMonthKey ? Number(customer.monthly_spent || 0) : 0,
    monthly_orders: storedMonthKey === currentMonthKey ? Number(customer.monthly_orders || 0) : 0,
    tier: storedMonthKey === currentMonthKey ? String(customer.tier || USER_TIERS.NEWBIE) : USER_TIERS.NEWBIE
  };
  return buildUserProgressSnapshot(normalized, now);
}

async function resetMonthlyStatsInternal(options = {}) {
  const now = options.now instanceof Date ? options.now : new Date();
  const currentMonthKey = monthKey(now);
  const snap = await db.collection('customers').get();
  let processed = 0;
  let batch = db.batch();
  let batchSize = 0;
  const tierChanges = [];

  for (const doc of snap.docs) {
    const customer = doc.data() || {};
    const previousTier = String(customer.tier || USER_TIERS.NEWBIE);
    const previousMonthKey = customer.month_key || '';
    if (previousMonthKey === currentMonthKey &&
      Number(customer.monthly_spent || 0) === 0 &&
      Number(customer.monthly_orders || 0) === 0 &&
      previousTier === USER_TIERS.NEWBIE) {
      continue;
    }

    batch.set(doc.ref, {
      month_key: currentMonthKey,
      monthly_spent: 0,
      monthly_orders: 0,
      tier: USER_TIERS.NEWBIE,
      next_tier_threshold: nextTierRule(USER_TIERS.NEWBIE)?.minSpent || null,
      tier_discount_percent: 0,
      tier_progress: 0,
      monthlyStatsResetAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});
    processed += 1;
    batchSize += 1;

    if (previousTier !== USER_TIERS.NEWBIE) {
      tierChanges.push({
        userId: doc.id,
        fromTier: previousTier,
        toTier: USER_TIERS.NEWBIE,
        kind: 'downgraded',
        monthKey: currentMonthKey
      });
    }
    if (batchSize >= 450) {
      await batch.commit();
      batch = db.batch();
      batchSize = 0;
    }
  }

  if (batchSize > 0) {
    await batch.commit();
  }

  for (const change of tierChanges) {
    await notifyTierChange(change.userId, {
      fromTier: change.fromTier,
      toTier: change.toTier,
      kind: change.kind,
      monthKey: change.monthKey
    });
  }

  return {ok: true, processed, month_key: currentMonthKey};
}

async function sendPushToUser(userId, title, body, data = {}) {
  if (!userId) {
    return false;
  }

  const normalizedPayload = Object.fromEntries(
    Object.entries(data || {}).filter(([key]) => key !== 'skipInbox')
  );
  if (data.skipInbox !== true) {
    await db.collection('notifications').add({
      userId,
      type: String(normalizedPayload.type || 'general'),
      title: String(title || ''),
      body: String(body || ''),
      payload: normalizedPayload,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      read: false
    });
  }

  if (await shouldDelayCleanerPush(userId, normalizedPayload)) {
    await queueDelayedCleanerNotification(userId, title, body, normalizedPayload);
    return true;
  }

  const tokenSnap = await db.collection('device_tokens').doc(userId).get();
  const tokenData = tokenSnap.data() || {};
  const tokenCandidates = [
    tokenData.token,
    tokenData.androidToken,
    tokenData.iosToken,
    tokenData.webToken,
    ...Object.values(tokenData.tokens || {})
  ]
    .map((token) => String(token || '').trim())
    .filter(Boolean);
  const tokens = [...new Set(tokenCandidates)];
  if (tokens.length === 0) {
    return false;
  }

  const settingsSnap = await db.collection('customer_settings').doc(userId).get();
  if (settingsSnap.exists && settingsSnap.data()?.notifications === false) {
    return false;
  }

  try {
    const channelId = String(normalizedPayload.channel || 'domly_main');
    const isOrderAlarmChannel = [
      'domly_order_offer_alarm_v2',
      'domly_schedule_offer_alarm_v2'
    ].includes(channelId);
    const messageBase = {
      notification: {title, body},
      data: Object.fromEntries(
        Object.entries(normalizedPayload).map(([key, value]) => [key, String(value)])
      ),
      android: {
        priority: 'high',
        notification: {
          channelId,
          sound: isOrderAlarmChannel ? 'domly_order_alarm' : 'default',
          priority: isOrderAlarmChannel ? 'max' : 'high',
          defaultVibrateTimings: true,
          visibility: 'PUBLIC'
        }
      }
    };
    const responses = await Promise.allSettled(tokens.map((token) =>
      admin.messaging().send({
        ...messageBase,
        token
      })
    ));
    const successCount = responses.filter((result) => result.status === 'fulfilled').length;
    const invalidTokens = [];
    responses.forEach((result, index) => {
      if (result.status === 'rejected') {
        const errorText = String(result.reason || '');
        if (
          errorText.includes('registration-token-not-registered') ||
          errorText.includes('invalid-registration-token') ||
          errorText.includes('Device unregistered')
        ) {
          invalidTokens.push(tokens[index]);
        }
        console.error('Push send failed for token', {
          userId,
          tokenIndex: index,
          error: errorText
        });
      }
    });
    if (invalidTokens.length > 0) {
      await removeInvalidDeviceTokens(userId, invalidTokens);
    }
    return successCount > 0;
  } catch (error) {
    console.error('Push send failed', {userId, error: String(error)});
    return false;
  }
}

function adminDisplayName(data = {}) {
  return [
    data.fullName,
    data.name,
    [data.lastName, data.firstName, data.middleName].filter(Boolean).join(' '),
    data.phone,
    data.phoneNumber,
    data.customerPhone,
    data.cleanerPhone,
    data.userId,
    data.customerId,
    data.cleanerId
  ].map((value) => String(value || '').trim()).find(Boolean) || 'Без имени';
}

function adminOrderLabel(data = {}, fallbackId = '') {
  return String(data.orderNumber || data.orderNo || data.number || data.sequenceNumber || fallbackId || '').trim();
}

function adminMoney(value) {
  const amount = Number(value || 0);
  return Number.isFinite(amount) && amount > 0 ? `${Math.round(amount)} ₸` : '';
}

async function sendPushToAdmins(title, body, data = {}) {
  const normalizedPayload = {
    type: String(data.type || 'admin_event'),
    route: String(data.route || '/admin/web'),
    targetRole: 'admin',
    ...Object.fromEntries(
      Object.entries(data || {}).map(([key, value]) => [key, String(value ?? '')])
    )
  };

  await db.collection('admin_notifications').add({
    type: normalizedPayload.type,
    title: String(title || ''),
    body: String(body || ''),
    payload: normalizedPayload,
    readBy: {},
    createdAt: admin.firestore.FieldValue.serverTimestamp()
  });

  const tokenDocs = new Map();
  const byRole = await db.collection('device_tokens').where('role', '==', 'admin').limit(500).get();
  byRole.docs.forEach((doc) => tokenDocs.set(doc.id, doc));
  const byFlag = await db.collection('device_tokens').where('adminSurface', '==', true).limit(500).get();
  byFlag.docs.forEach((doc) => tokenDocs.set(doc.id, doc));

  const targets = [];
  for (const [userId, doc] of tokenDocs.entries()) {
    const tokenData = doc.data() || {};
    const tokens = [
      tokenData.token,
      tokenData.androidToken,
      tokenData.iosToken,
      tokenData.webToken,
      ...Object.values(tokenData.tokens || {})
    ].map((token) => String(token || '').trim()).filter(Boolean);
    for (const token of [...new Set(tokens)]) {
      targets.push({userId, token});
    }
  }
  if (targets.length === 0) {
    console.error('Admin push skipped: no admin device tokens', {
      type: normalizedPayload.type,
      sourceId: normalizedPayload.sourceId || ''
    });
    return false;
  }

  const messageBase = {
    notification: {title: String(title || ''), body: String(body || '')},
    data: normalizedPayload,
    android: {
      priority: 'high',
      notification: {
        channelId: 'domly_main',
        sound: 'default',
        priority: 'high',
        defaultVibrateTimings: true,
        visibility: 'PUBLIC'
      }
    },
    webpush: {
      fcmOptions: {
        link: `https://domly-admin-web.web.app/#${String(normalizedPayload.route || '/admin/web')}`
      }
    }
  };

  const responses = await Promise.allSettled(targets.map((target) =>
    admin.messaging().send({...messageBase, token: target.token})
  ));
  const invalidByUser = new Map();
  responses.forEach((result, index) => {
    if (result.status !== 'rejected') {
      return;
    }
    const errorText = String(result.reason || '');
    if (
      errorText.includes('registration-token-not-registered') ||
      errorText.includes('invalid-registration-token') ||
      errorText.includes('Device unregistered')
    ) {
      const target = targets[index];
      invalidByUser.set(target.userId, [...(invalidByUser.get(target.userId) || []), target.token]);
    }
    console.error('Admin push send failed', {error: errorText});
  });
  for (const [userId, invalidTokens] of invalidByUser.entries()) {
    await removeInvalidDeviceTokens(userId, invalidTokens);
  }
  return responses.some((result) => result.status === 'fulfilled');
}

async function notifyAdminsOnce(type, sourceId, title, body, data = {}, signature = '') {
  const canSend = await shouldSendNotificationOnce(
    `admin_${type}`,
    [sourceId, signature || data.status || data.orderStatus || data.paymentStatus || 'created']
  );
  if (!canSend) {
    return false;
  }
  return sendPushToAdmins(title, body, {type, sourceId, ...data});
}

async function recordCustomerBonusTransaction({
  userId,
  amount,
  title,
  reason,
  type = 'bonus_credit',
  orderId = null
}) {
  if (!userId || !Number(amount)) {
    return;
  }
  await db.collection('bonus_transactions').add({
    userId: String(userId),
    amount: Number(amount),
    type: String(type),
    title: String(title || ''),
    reason: String(reason || ''),
    ...(orderId ? {orderId: String(orderId)} : {}),
    createdAt: admin.firestore.FieldValue.serverTimestamp()
  });
}

function appLocalNow(date = new Date()) {
  return new Date(date.getTime() + APP_TIMEZONE_OFFSET_MINUTES * 60 * 1000);
}

function isCleanerQuietHours(date = new Date()) {
  const hour = appLocalNow(date).getUTCHours();
  if (CLEANER_QUIET_HOURS_START > CLEANER_QUIET_HOURS_END) {
    return hour >= CLEANER_QUIET_HOURS_START || hour < CLEANER_QUIET_HOURS_END;
  }
  return hour >= CLEANER_QUIET_HOURS_START && hour < CLEANER_QUIET_HOURS_END;
}

function nextCleanerNotificationWindowStart(date = new Date()) {
  const local = appLocalNow(date);
  const targetLocal = new Date(Date.UTC(
    local.getUTCFullYear(),
    local.getUTCMonth(),
    local.getUTCDate(),
    CLEANER_QUIET_HOURS_END,
    0,
    0,
    0
  ));
  if (local.getUTCHours() >= CLEANER_QUIET_HOURS_START) {
    targetLocal.setUTCDate(targetLocal.getUTCDate() + 1);
  }
  return new Date(targetLocal.getTime() - APP_TIMEZONE_OFFSET_MINUTES * 60 * 1000);
}

async function isCleanerUser(userId) {
  const cleanerSnap = await db.collection('cleaners').doc(String(userId)).get();
  return cleanerSnap.exists;
}

async function shouldDelayCleanerPush(userId, payload = {}) {
  const type = String(payload.type || '');
  if (type === 'new_order_offer' || type === 'scheduled_order_offer') {
    return false;
  }
  if (!isCleanerQuietHours()) {
    return false;
  }
  if (payload.delayDuringQuietHours === false || payload.skipQuietHours === true) {
    return false;
  }
  return isCleanerUser(userId);
}

async function queueDelayedCleanerNotification(userId, title, body, payload = {}) {
  await db.collection('delayed_notifications').add({
    userId: String(userId),
    role: 'cleaner',
    title: String(title || ''),
    body: String(body || ''),
    payload,
    status: 'pending',
    dueAt: admin.firestore.Timestamp.fromDate(nextCleanerNotificationWindowStart()),
    createdAt: admin.firestore.FieldValue.serverTimestamp()
  });
}

async function sendPushTransportOnly(userId, title, body, data = {}) {
  const normalizedPayload = Object.fromEntries(
    Object.entries(data || {}).filter(([key]) => key !== 'skipInbox')
  );
  const tokenSnap = await db.collection('device_tokens').doc(userId).get();
  const tokenData = tokenSnap.data() || {};
  const tokenCandidates = [
    tokenData.token,
    tokenData.androidToken,
    tokenData.iosToken,
    tokenData.webToken,
    ...Object.values(tokenData.tokens || {})
  ]
    .map((token) => String(token || '').trim())
    .filter(Boolean);
  const tokens = [...new Set(tokenCandidates)];
  if (tokens.length === 0) {
    console.error('Push skipped: no device tokens', {
      userId,
      type: normalizedPayload.type || 'general'
    });
    return false;
  }

  const channelId = String(normalizedPayload.channel || 'domly_main');
  const isOrderAlarmChannel = [
    'domly_order_offer_alarm_v2',
    'domly_schedule_offer_alarm_v2'
  ].includes(channelId);
  const messageBase = {
    notification: {title, body},
    data: Object.fromEntries(
      Object.entries(normalizedPayload).map(([key, value]) => [key, String(value)])
    ),
    android: {
      priority: 'high',
      notification: {
        channelId,
        sound: isOrderAlarmChannel ? 'domly_order_alarm' : 'default',
        priority: isOrderAlarmChannel ? 'max' : 'high',
        defaultVibrateTimings: true,
        visibility: 'PUBLIC'
      }
    }
  };
  const responses = await Promise.allSettled(tokens.map((token) =>
    admin.messaging().send({
      ...messageBase,
      token
    })
  ));
  const invalidTokens = [];
  responses.forEach((result, index) => {
    if (result.status === 'rejected') {
      const errorText = String(result.reason || '');
      if (
        errorText.includes('registration-token-not-registered') ||
        errorText.includes('invalid-registration-token') ||
        errorText.includes('Device unregistered')
      ) {
        invalidTokens.push(tokens[index]);
      }
      console.error('Delayed push send failed for token', {
        userId,
        tokenIndex: index,
        error: errorText
      });
    }
  });
  if (invalidTokens.length > 0) {
    await removeInvalidDeviceTokens(userId, invalidTokens);
  }
  return responses.some((result) => result.status === 'fulfilled');
}

async function flushDelayedCleanerNotificationsInternal(limit = 100) {
  const dueSnap = await db.collection('delayed_notifications')
    .where('role', '==', 'cleaner')
    .where('status', '==', 'pending')
    .where('dueAt', '<=', admin.firestore.Timestamp.fromDate(new Date()))
    .limit(limit)
    .get();
  let sent = 0;
  for (const doc of dueSnap.docs) {
    const item = doc.data() || {};
    const userId = String(item.userId || '').trim();
    if (!userId) {
      await doc.ref.set({
        status: 'failed',
        error: 'missing_userId',
        processedAt: admin.firestore.FieldValue.serverTimestamp()
      }, {merge: true});
      continue;
    }
    const ok = await sendPushTransportOnly(
      userId,
      String(item.title || ''),
      String(item.body || ''),
      item.payload || {}
    );
    await doc.ref.set({
      status: ok ? 'sent' : 'failed',
      processedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});
    if (ok) {
      sent += 1;
    }
  }
  return {ok: true, checked: dueSnap.size, sent};
}

async function removeInvalidDeviceTokens(userId, invalidTokens = []) {
  const invalidSet = new Set(invalidTokens.map((token) => String(token || '').trim()).filter(Boolean));
  if (!userId || invalidSet.size === 0) {
    return;
  }
  const tokenRef = db.collection('device_tokens').doc(String(userId));
  const snap = await tokenRef.get();
  if (!snap.exists) {
    return;
  }
  const data = snap.data() || {};
  const updates = {updatedAt: admin.firestore.FieldValue.serverTimestamp()};
  for (const key of ['token', 'androidToken', 'iosToken', 'webToken']) {
    if (invalidSet.has(String(data[key] || '').trim())) {
      updates[key] = admin.firestore.FieldValue.delete();
    }
  }
  const tokenMap = data.tokens && typeof data.tokens === 'object' ? data.tokens : {};
  for (const [platform, token] of Object.entries(tokenMap)) {
    if (invalidSet.has(String(token || '').trim())) {
      updates[`tokens.${platform}`] = admin.firestore.FieldValue.delete();
    }
  }
  await tokenRef.set(updates, {merge: true});
}

function houseWaitlistId(userId, houseId) {
  return `${userId}_${houseId}`;
}

function chatSummaryId(userId, orderId) {
  return `${userId}_${orderId}`;
}

function referralStatsId(userId) {
  return String(userId);
}

function normalizeReferralCode(code) {
  return String(code || '').trim().toUpperCase();
}

function referralCodeCandidates(userId) {
  const base = String(userId || '')
    .replace(/[^A-Za-z0-9]/g, '')
    .toUpperCase();
  const rawCandidates = [
    `DOMLY-${base.slice(0, 8)}`,
    `DOMLY-${base.slice(0, 10)}`,
    `DOMLY-${base.slice(0, 12)}`,
    `DOMLY-${base.slice(0, 16)}`
  ].filter((item) => item !== 'DOMLY-');
  return [...new Set(rawCandidates)];
}

function buildReferralLink(referralCode) {
  const normalized = normalizeReferralCode(referralCode);
  const projectId =
    process.env.GCLOUD_PROJECT ||
    process.env.PROJECT_ID ||
    admin.app().options.projectId ||
    'domly-d0f91';
  const baseUrl = String(
    process.env.REFERRAL_BASE_URL || `https://${projectId}.web.app`
  ).replace(/\/+$/, '');
  return `${baseUrl}/?ref=${encodeURIComponent(normalized)}`;
}

async function ensureReferralLinkInternal(userId) {
  const customerRef = db.collection('customers').doc(String(userId));
  const customerSnap = await customerRef.get();
  const customer = customerSnap.exists ? (customerSnap.data() || {}) : {};
  const existingCode = normalizeReferralCode(customer.referralCode);
  if (existingCode) {
    return {
      ok: true,
      referralCode: existingCode,
      referralLink: buildReferralLink(existingCode),
      created: false
    };
  }

  const candidates = referralCodeCandidates(userId);
  let chosenCode = '';
  for (const candidate of candidates) {
    const conflictSnap = await db.collection('customers')
      .where('referralCode', '==', candidate)
      .limit(1)
      .get();
    if (conflictSnap.empty || conflictSnap.docs[0].id === String(userId)) {
      chosenCode = candidate;
      break;
    }
  }

  if (!chosenCode) {
    const safeUserId = String(userId)
      .replace(/[^A-Za-z0-9]/g, '')
      .toUpperCase();
    chosenCode = `DOMLY-${safeUserId.slice(-16)}`;
  }

  await customerRef.set({
    referralCode: chosenCode,
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, {merge: true});

  return {
    ok: true,
    referralCode: chosenCode,
    referralLink: buildReferralLink(chosenCode),
    created: true
  };
}

function normalizeProfileText(value, maxLength = 200) {
  return String(value || '').trim().slice(0, maxLength);
}

const KNOWN_CITY_ALIASES = [
  ['астана', 'astana', 'нур султан', 'нурсултан'],
  ['алматы', 'almaty'],
  ['шымкент', 'shymkent'],
  ['караганда', 'қарағанды', 'karaganda'],
  ['актобе', 'ақтөбе', 'aktobe'],
  ['атырау', 'atyrau'],
  ['актау', 'ақтау', 'aktau'],
  ['павлодар', 'pavlodar'],
  ['костанай', 'қостанай', 'kostanay'],
  ['усть каменогорск', 'oskemen', 'өскемен'],
  ['семей', 'semey'],
  ['кокшетау', 'көкшетау', 'kokshetau'],
  ['петропавловск', 'petropavl'],
  ['тараз', 'taraz'],
  ['туркестан', 'turkistan'],
  ['уральск', 'oral', 'uralsk'],
  ['кызылорда', 'қызылорда', 'kyzylorda'],
];

function normalizeCityName(value) {
  const raw = String(value || '')
    .trim()
    .toLowerCase()
    .replace(/ё/g, 'е')
    .replace(/[^a-zа-яәіңғүұқөһ0-9]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  if (!raw) {
    return '';
  }
  for (const aliases of KNOWN_CITY_ALIASES) {
    if (aliases.some((alias) => raw === alias || raw.includes(alias))) {
      return aliases[0];
    }
  }
  return raw.split(',')[0].trim();
}

function resolveCityFromSource(source = {}) {
  const directCandidates = [
    source.city,
    source.customerCity,
    source.workCity,
    source.serviceCity,
  ];
  for (const candidate of directCandidates) {
    const normalized = normalizeCityName(candidate);
    if (normalized) {
      return normalized;
    }
  }

  const addressCandidates = [
    source.homeAddress,
    source.address,
    source.residentialComplex,
  ];
  for (const candidate of addressCandidates) {
    const normalized = normalizeCityName(candidate);
    if (normalized) {
      return normalized;
    }
  }

  return '';
}

function resolveExplicitCityFromSource(source = {}) {
  const directCandidates = [
    source.city,
    source.customerCity,
    source.workCity,
    source.serviceCity,
  ];
  for (const candidate of directCandidates) {
    const normalized = normalizeCityName(candidate);
    if (normalized) {
      return normalized;
    }
  }
  return '';
}

async function resolveHouseCityById(houseId) {
  const normalizedHouseId = String(houseId || '').trim();
  if (!normalizedHouseId) {
    return '';
  }
  const houseSnap = await db.collection('houses').doc(normalizedHouseId).get();
  if (!houseSnap.exists) {
    return '';
  }
  return resolveCityFromSource(houseSnap.data() || {});
}

async function resolveCustomerCity(customerId, customerProfile = null) {
  const profile = customerProfile || {};
  const direct = resolveCityFromSource(profile);
  if (direct) {
    return direct;
  }

  const houseCity = await resolveHouseCityById(profile.houseId);
  if (houseCity) {
    return houseCity;
  }

  const normalizedCustomerId = String(customerId || '').trim();
  if (!normalizedCustomerId || customerProfile != null) {
    return '';
  }
  const customerSnap = await db.collection('customers').doc(normalizedCustomerId).get();
  if (!customerSnap.exists) {
    return '';
  }
  return resolveCustomerCity(normalizedCustomerId, customerSnap.data() || {});
}

function filterCleanersByCity(cleaners, customerCity) {
  const normalizedCustomerCity = normalizeCityName(customerCity);
  if (!normalizedCustomerCity) {
    return cleaners;
  }
  return cleaners.filter((cleaner) => resolveCityFromSource(cleaner) === normalizedCustomerCity);
}

async function recalculateCleanerDailyScheduleInternal(cleanerId, targetDate) {
  const referenceDate = startOfDay(targetDate);
  const dateKey = toIsoDate(referenceDate);
  const assignments = await getCleanerAssignmentsForDate(cleanerId, referenceDate);
  const totalSqm = assignments.reduce((sum, item) => sum + Number(item.area || 0), 0);
  const totalMinutes = assignments.reduce((sum, item) => sum + Number(item.minutes || 0), 0);
  const totalTravelMinutes = assignments.reduce((sum, item) => {
    const minutes = Number(item.travelTimeMinutes || 0);
    return sum + (Number.isFinite(minutes) ? minutes : 0);
  }, 0);
  await db.collection('cleaner_daily_schedule').doc(`${cleanerId}_${dateKey}`).set({
    cleanerId,
    date: dateKey,
    dateKey,
    orders: assignments.map((item) => ({
      id: item.id,
      time: item.time,
      area: Number(item.area || 0),
      minutes: Number(item.minutes || 0)
    })),
    totalSqm,
    totalMinutes,
    totalTravelMinutes,
    isFull: totalMinutes >= DAILY_SCHEDULE_LIMIT_MINUTES,
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, {merge: true});
}

function scopeStatusForCleanerAcceptance(scope = {}) {
  const assignmentType = scope.assignmentType || assignmentTypeForDate(resolveScopeScheduledAt(scope));
  return assignmentType === 'today'
    ? ORDER_ASSIGNMENT_STATUSES.ASSIGNED
    : ORDER_ASSIGNMENT_STATUSES.SCHEDULED_CONFIRMED;
}

async function loadAssignmentScope(scopeType, scopeId) {
  const normalizedScopeType = scopeType === 'schedule_slot' ? 'schedule_slot' : 'order';
  const collectionName = normalizedScopeType === 'schedule_slot' ? 'schedule_slots' : 'customer_orders';
  const snap = await db.collection(collectionName).doc(String(scopeId)).get();
  if (!snap.exists) {
    throw new HttpsError('not-found', `${normalizedScopeType} not found`);
  }
  const data = {id: snap.id, scopeType: normalizedScopeType, ...snap.data()};
  if (normalizedScopeType === 'schedule_slot') {
    data.orderId = data.sourceOrderId || data.customerOrderId || null;
    if (!scopeHasServiceAreaIdentity(data) && data.orderId) {
      const sourceOrderSnap = await db.collection('customer_orders').doc(String(data.orderId)).get();
      if (sourceOrderSnap.exists) {
        Object.assign(data, mergeServiceAreaIdentity(data, sourceOrderSnap.data() || {}));
      }
    }
  } else {
    data.orderId = data.id;
  }
  data.assignmentType = assignmentTypeForDate(resolveScopeScheduledAt(data));
  return {ref: snap.ref, data};
}

function offerExpiryForScope(scope = {}, assignmentType = 'today') {
  if (isCleanerQuietHours()) {
    return new Date(nextCleanerNotificationWindowStart().getTime() + ORDER_OFFER_TTL_SECONDS * 1000);
  }
  return new Date(Date.now() + ORDER_OFFER_TTL_SECONDS * 1000);
}

function scopeHasConcreteSchedule(scope = {}) {
  const time = String(scope.time || '').trim().toLowerCase();
  if (!time || time.includes('ожидает')) {
    return false;
  }
  if (scope.scheduledFor instanceof admin.firestore.Timestamp || scope.scheduledFor instanceof Date) {
    return true;
  }
  if (scope.date instanceof admin.firestore.Timestamp || scope.date instanceof Date) {
    return true;
  }
  if (typeof scope.scheduledDateKey === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(scope.scheduledDateKey)) {
    return true;
  }
  return false;
}

function assignmentRoutingInputChanged(before = {}, after = {}, statusField = 'status') {
  const keys = [
    statusField,
    'cleanerId',
    'scheduledFor',
    'date',
    'scheduledDateKey',
    'time',
    'area',
    'areaSqm',
    'totalDurationMinutes',
    'estimatedDurationMinutes',
    'serviceArea',
    'serviceAreaId',
    'zoneId',
    'houseId',
    'clusterName',
    'residentialComplex',
    'address',
    'city',
    'customerCity',
    'preferredCleanerId'
  ];
  return keys.some((key) => {
    const left = before?.[key];
    const right = after?.[key];
    const normalize = (value) => {
      if (value instanceof admin.firestore.Timestamp) {
        return value.toMillis();
      }
      if (value instanceof Date) {
        return value.getTime();
      }
      if (value && typeof value === 'object') {
        return JSON.stringify(value);
      }
      return value ?? null;
    };
    return normalize(left) !== normalize(right);
  });
}

async function rebuildScopeCandidateQueueInternal(scopeType, scopeId, options = {}) {
  const scope = await loadAssignmentScope(scopeType, scopeId);
  const candidates = await findCleanerCandidatesInternal({
    scope: scope.data,
    preferredCleanerId: options.preferredCleanerId || scope.data.currentOfferCleanerId || null,
    excludeCleanerIds: options.excludeCleanerIds || []
  });
  const candidateQueue = candidates.map((item) => String(item.cleanerId || ''));
  await scope.ref.set({
    assignmentType: scope.data.assignmentType,
    candidateQueue,
    candidateQueueDetails: candidates,
    rejectedBy: Array.isArray(scope.data.rejectedBy) ? scope.data.rejectedBy : [],
    timeoutBy: Array.isArray(scope.data.timeoutBy) ? scope.data.timeoutBy : [],
    assignmentStatus: candidateQueue.length > 0
      ? ORDER_ASSIGNMENT_STATUSES.SEARCHING
      : ORDER_ASSIGNMENT_STATUSES.REASSIGNMENT_NEEDED,
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, {merge: true});
  return {
    ...scope,
    data: {
      ...scope.data,
      candidateQueue,
      candidateQueueDetails: candidates
    }
  };
}

function nextCleanerIdFromScope(scope = {}) {
  const queue = Array.isArray(scope.candidateQueue) ? scope.candidateQueue.map(String) : [];
  const rejected = new Set((Array.isArray(scope.rejectedBy) ? scope.rejectedBy : []).map(String));
  const timedOut = new Set((Array.isArray(scope.timeoutBy) ? scope.timeoutBy : []).map(String));
  return queue.find((cleanerId) => !rejected.has(cleanerId) && !timedOut.has(cleanerId)) || null;
}

async function resetAssignmentOfferRound(scope) {
  await scope.ref.set({
    rejectedBy: [],
    timeoutBy: [],
    currentOfferCleanerId: null,
    currentOfferId: null,
    offerExpiresAt: null,
    assignmentRound: Number(scope.data.assignmentRound || 0) + 1,
    assignmentStatus: ORDER_ASSIGNMENT_STATUSES.SEARCHING,
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, {merge: true});
  scope.data.rejectedBy = [];
  scope.data.timeoutBy = [];
  scope.data.currentOfferCleanerId = null;
  scope.data.currentOfferId = null;
  scope.data.offerExpiresAt = null;
  scope.data.assignmentRound = Number(scope.data.assignmentRound || 0) + 1;
  return scope;
}

async function notifyCustomerSearchStarted(scope = {}) {
  const userId = String(scope.customerId || '').trim();
  if (!userId) {
    return;
  }
  const scopeType = String(scope.scopeType || 'order').trim();
  const scopeId = String(
    scopeType === 'schedule_slot'
      ? (scope.id || scope.slotId || scope.orderId || '')
      : (scope.orderId || scope.id || '')
  ).trim();
  const shouldSend = await shouldSendNotificationOnce('cleaner_search_started', [
    scopeType,
    scopeId || userId
  ]);
  if (!shouldSend) {
    return;
  }
  const title = 'Ищем уборщицу';
  const body = scope.assignmentType === 'today'
    ? 'Подбираем ближайшую свободную уборщицу, которая успеет приехать вовремя.'
    : 'Подбираем уборщицу и отправляем заказ на подтверждение.';
  await sendPushToUser(userId, title, body, {
    type: 'cleaner_search_started',
    scopeType,
    orderId: scope.orderId || scope.id,
    slotId: scopeType === 'schedule_slot' ? scope.id : ''
  });
}

async function notifyCleanerAboutOffer(scope = {}, offer = {}, cleaner = {}) {
  const cleanerId = String(cleaner.id || offer.cleanerId || '').trim();
  if (!cleanerId) {
    return;
  }
  const isToday = scope.assignmentType === 'today';
  const title = isToday ? 'Новый срочный заказ' : 'Заказ на подтверждение';
  const body = isToday
    ? `Начало: ${scope.time || '10:00'}. У вас есть 2 минуты на ответ.`
    : `Дата: ${toIsoDate(resolveScopeScheduledAt(scope))} ${scope.time || '10:00'}. Подтвердите заказ в приложении.`;
  await sendPushToUser(cleanerId, title, body, {
    type: isToday ? 'new_order_offer' : 'scheduled_order_offer',
    orderId: scope.orderId || scope.id,
    slotId: scope.scopeType === 'schedule_slot' ? scope.id : '',
    offerId: offer.id || '',
    scopeType: scope.scopeType || 'order',
    assignmentType: scope.assignmentType || 'today',
    clickAction: 'OPEN_ORDER_OFFER',
    channel: isToday ? 'domly_order_offer_alarm_v2' : 'domly_schedule_offer_alarm_v2'
  });
}

async function offerScopeToNextCleanerInternal(scopeType, scopeId, options = {}) {
  let scope = await loadAssignmentScope(scopeType, scopeId);
  const scopeData = scope.data;
  if (scopeData.scopeType === 'schedule_slot' && String(scopeData.status || '') !== 'pending_assignment') {
    return {ok: true, status: 'inactive_scope', scopeId};
  }
  if (scopeData.scopeType !== 'schedule_slot' && String(scopeData.orderStatus || '') !== 'pending_assignment') {
    return {ok: true, status: 'inactive_scope', scopeId};
  }
  const currentExpiry = scopeData.offerExpiresAt instanceof admin.firestore.Timestamp
    ? scopeData.offerExpiresAt.toDate()
    : scopeData.offerExpiresAt instanceof Date
      ? scopeData.offerExpiresAt
      : null;
  if (scopeData.cleanerId) {
    return {ok: true, status: 'already_assigned', scopeId};
  }
  if (
    scopeData.currentOfferCleanerId &&
    currentExpiry &&
    currentExpiry.getTime() > Date.now() &&
    options.force !== true
  ) {
    return {ok: true, status: 'active_offer_exists', scopeId};
  }

  let candidateQueue = Array.isArray(scopeData.candidateQueue) ? scopeData.candidateQueue : [];
  let nextCleanerId = nextCleanerIdFromScope(scopeData);
  if (candidateQueue.length === 0 || !nextCleanerId || options.forceRebuild === true) {
    scope = await rebuildScopeCandidateQueueInternal(scopeType, scopeId, {
      preferredCleanerId: options.preferredCleanerId || scopeData.preferredCleanerId || scopeData.currentOfferCleanerId || null,
      excludeCleanerIds: []
    });
    candidateQueue = Array.isArray(scope.data.candidateQueue) ? scope.data.candidateQueue : [];
    nextCleanerId = nextCleanerIdFromScope(scope.data);
  }

  if (!nextCleanerId) {
    await scope.ref.set({
      assignmentStatus: ORDER_ASSIGNMENT_STATUSES.REASSIGNMENT_NEEDED,
      currentOfferCleanerId: null,
      currentOfferId: null,
      offerExpiresAt: null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});
    return {ok: true, status: 'no_candidates', scopeId};
  }

  const cleanerSnap = await db.collection('cleaners').doc(String(nextCleanerId)).get();
  if (!cleanerSnap.exists) {
    await scope.ref.set({
      timeoutBy: admin.firestore.FieldValue.arrayUnion(String(nextCleanerId)),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});
    return offerScopeToNextCleanerInternal(scopeType, scopeId, {
      ...options,
      force: true,
      forceRebuild: true
    });
  }
  const cleaner = {id: cleanerSnap.id, ...cleanerSnap.data()};
  const queueDetails = Array.isArray(scope.data.candidateQueueDetails)
    ? scope.data.candidateQueueDetails
    : [];
  const queueDetail = queueDetails.find((item) =>
    String(item?.cleanerId || '') === String(nextCleanerId)
  );
  const serviceAreaFallback = queueDetail?.serviceAreaFallback === true;
  if (!serviceAreaFallback && !serviceAreaMatches(cleaner, scope.data)) {
    await scope.ref.set({
      timeoutBy: admin.firestore.FieldValue.arrayUnion(String(nextCleanerId)),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});
    return offerScopeToNextCleanerInternal(scopeType, scopeId, {
      ...options,
      force: true
    });
  }
  const policies = await getPolicyConfig();
  const assignmentType = scope.data.assignmentType || assignmentTypeForDate(resolveScopeScheduledAt(scope.data));
  const expiresAt = offerExpiryForScope(scope.data, assignmentType);
  const offerRef = db.collection('order_offers').doc();

  await db.runTransaction(async (tx) => {
    const freshSnap = await tx.get(scope.ref);
    if (!freshSnap.exists) {
      throw new HttpsError('not-found', 'Scope not found');
    }
    const fresh = {id: freshSnap.id, scopeType, ...scope.data, ...freshSnap.data()};
    const freshExpiry = fresh.offerExpiresAt instanceof admin.firestore.Timestamp
      ? fresh.offerExpiresAt.toDate()
      : fresh.offerExpiresAt instanceof Date
        ? fresh.offerExpiresAt
        : null;
    if (fresh.cleanerId) {
      return;
    }
    if (
      fresh.currentOfferCleanerId &&
      freshExpiry &&
      freshExpiry.getTime() > Date.now() &&
      options.force !== true
    ) {
      return;
    }

    tx.set(offerRef, {
      orderId: fresh.orderId || fresh.id,
      slotId: scopeType === 'schedule_slot' ? fresh.id : null,
      scopeType,
      scopeId: fresh.id,
      cleanerId: cleaner.id,
      cleanerName: cleaner.name || 'Исполнитель',
      customerId: fresh.customerId || null,
      status: 'pending',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      offeredAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
      assignmentType,
      time: fresh.time || null,
      scheduledFor: resolveScopeScheduledAt(fresh),
      scheduledDateKey: fresh.scheduledDateKey || toIsoDate(resolveScopeScheduledAt(fresh)),
      dateText: toIsoDate(resolveScopeScheduledAt(fresh)),
      areaSqm: Number(fresh.area || 0),
      area: Number(fresh.area || 0),
      package: fresh.package || fresh.packageName || null,
      packageId: fresh.packageId || null,
      frequencyLabel: fresh.frequencyLabel || null,
      addons: Array.isArray(fresh.addons) ? fresh.addons : [],
      addonsDetailed: normalizeDetailedAddons(fresh.addonsDetailed),
      addonCount: Number(fresh.addonCount || 0),
      addonTotalPrice: Number(fresh.addonTotalPrice || 0),
      addonsSeparatePaymentTotal: Number(fresh.addonsSeparatePaymentTotal || 0),
      separatePaymentAddons: Array.isArray(fresh.separatePaymentAddons)
        ? fresh.separatePaymentAddons
        : [],
      estimatedDurationMinutes: Number(fresh.estimatedDurationMinutes || 0),
      totalDurationMinutes: Number(fresh.totalDurationMinutes || 0),
      travelMinutes: Number(fresh.travelTimeMinutes || 0),
      cleanerSqmRate: cleanerSqmRateFromPolicies(policies),
      cleanerIncome: cleanerIncomeForSource(fresh, policies),
      address: fresh.address || null
    });
    tx.set(scope.ref, {
      assignmentType,
      assignmentStatus: assignmentType === 'today'
        ? ORDER_ASSIGNMENT_STATUSES.OFFER_PENDING
        : ORDER_ASSIGNMENT_STATUSES.SCHEDULED_PENDING_CONFIRMATION,
      currentOfferCleanerId: cleaner.id,
      currentOfferId: offerRef.id,
      offerExpiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});
  });

  await notifyCustomerSearchStarted(scope.data);
  await notifyCleanerAboutOffer(
    {
      ...scope.data,
      assignmentType
    },
    {id: offerRef.id, cleanerId: cleaner.id},
    cleaner
  );

  return {
    ok: true,
    status: 'offered',
    scopeId,
    scopeType,
    cleanerId: cleaner.id,
    offerId: offerRef.id,
    expiresAt: expiresAt.toISOString()
  };
}

async function cancelPendingOffersForScope(scopeType, scopeId, reason = 'cancelled') {
  const snap = await db.collection('order_offers')
    .where('scopeType', '==', scopeType === 'schedule_slot' ? 'schedule_slot' : 'order')
    .where('scopeId', '==', String(scopeId))
    .where('status', '==', 'pending')
    .get();
  if (snap.empty) {
    return;
  }
  const batch = db.batch();
  for (const doc of snap.docs) {
    batch.set(doc.ref, {
      status: reason,
      respondedAt: admin.firestore.FieldValue.serverTimestamp(),
      response: reason,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});
  }
  await batch.commit();
}

async function updatePendingOffersForScope(scopeType, scopeId, payload = {}) {
  const snap = await db.collection('order_offers')
    .where('scopeType', '==', scopeType === 'schedule_slot' ? 'schedule_slot' : 'order')
    .where('scopeId', '==', String(scopeId))
    .where('status', '==', 'pending')
    .get();
  if (snap.empty) {
    return;
  }
  const batch = db.batch();
  for (const doc of snap.docs) {
    batch.set(doc.ref, {
      ...payload,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});
  }
  await batch.commit();
}

function hasActiveOffer(scope = {}) {
  const offerId = String(scope.currentOfferId || '').trim();
  const cleanerId = String(scope.currentOfferCleanerId || '').trim();
  const expiresAt = scope.offerExpiresAt instanceof admin.firestore.Timestamp
    ? scope.offerExpiresAt.toDate()
    : scope.offerExpiresAt instanceof Date
      ? scope.offerExpiresAt
      : null;
  return Boolean(offerId && cleanerId && expiresAt && expiresAt.getTime() > Date.now());
}

async function findCleanerTimeConflictInTransaction(tx, {
  cleanerId,
  scopeType,
  scopeId,
  scope = {}
}) {
  const normalizedCleanerId = String(cleanerId || '').trim();
  if (!normalizedCleanerId) {
    return null;
  }
  const targetDate = resolveScopeScheduledAt(scope);
  const targetDateKey = toIsoDate(targetDate);
  const targetRange = buildAssignmentRange(scope);
  const normalizedScopeId = String(scopeId || '').trim();
  const sourceOrderId = String(scope.sourceOrderId || scope.customerOrderId || scope.orderId || '').trim();

  const slotSnap = await tx.get(
    db.collection('schedule_slots')
      .where('cleanerId', '==', normalizedCleanerId)
      .where('scheduledDateKey', '==', targetDateKey)
  );
  for (const doc of slotSnap.docs) {
    if (scopeType === 'schedule_slot' && doc.id === normalizedScopeId) {
      continue;
    }
    const slot = doc.data() || {};
    if (!activeSlotStatus(slot.status)) {
      continue;
    }
    if (timeRangesOverlap(buildAssignmentRange(slot), targetRange)) {
      return {
        type: 'schedule_slot',
        id: doc.id,
        time: slot.time || null
      };
    }
  }

  const orderSnap = await tx.get(
    db.collection('customer_orders').where('cleanerId', '==', normalizedCleanerId)
  );
  for (const doc of orderSnap.docs) {
    if (scopeType === 'order' && doc.id === normalizedScopeId) {
      continue;
    }
    if (sourceOrderId && doc.id === sourceOrderId) {
      continue;
    }
    const order = doc.data() || {};
    const status = String(order.orderStatus || order.status || '');
    if (!['assigned', 'confirmed', 'start_pending', 'in_progress'].includes(status)) {
      continue;
    }
    const orderDate = resolveScopeScheduledAt(order);
    if (toIsoDate(orderDate) !== targetDateKey) {
      continue;
    }
    if (timeRangesOverlap(buildAssignmentRange(order), targetRange)) {
      return {
        type: 'order',
        id: doc.id,
        time: order.time || null
      };
    }
  }

  return null;
}

async function cancelOverlappingPendingOffersForCleaner({
  cleanerId,
  acceptedScopeType,
  acceptedScopeId,
  acceptedOfferId,
  acceptedScope = {}
}) {
  const normalizedCleanerId = String(cleanerId || '').trim();
  if (!normalizedCleanerId) {
    return;
  }
  const acceptedDateKey = toIsoDate(resolveScopeScheduledAt(acceptedScope));
  const acceptedRange = buildAssignmentRange(acceptedScope);
  const snap = await db.collection('order_offers')
    .where('cleanerId', '==', normalizedCleanerId)
    .where('status', '==', 'pending')
    .get();
  const scopesToReoffer = [];
  const batch = db.batch();

  for (const doc of snap.docs) {
    if (doc.id === String(acceptedOfferId || '')) {
      continue;
    }
    const offer = doc.data() || {};
    const scopeType = String(offer.scopeType || 'order') === 'schedule_slot'
      ? 'schedule_slot'
      : 'order';
    const scopeId = String(offer.scopeId || '').trim();
    if (!scopeId || (scopeType === acceptedScopeType && scopeId === String(acceptedScopeId || ''))) {
      continue;
    }
    const offerDate = offer.scheduledFor instanceof admin.firestore.Timestamp
      ? offer.scheduledFor.toDate()
      : offer.scheduledFor instanceof Date
        ? offer.scheduledFor
        : resolveScopeScheduledAt(offer);
    if (toIsoDate(offerDate) !== acceptedDateKey) {
      continue;
    }
    if (!timeRangesOverlap(buildAssignmentRange(offer), acceptedRange)) {
      continue;
    }

    batch.set(doc.ref, {
      status: 'cancelled_conflict',
      respondedAt: admin.firestore.FieldValue.serverTimestamp(),
      response: 'cleaner_time_conflict',
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});

    const scopeRef = db.collection(scopeType === 'schedule_slot' ? 'schedule_slots' : 'customer_orders').doc(scopeId);
    batch.set(scopeRef, {
      timeoutBy: admin.firestore.FieldValue.arrayUnion(normalizedCleanerId),
      currentOfferCleanerId: null,
      currentOfferId: null,
      offerExpiresAt: null,
      assignmentStatus: ORDER_ASSIGNMENT_STATUSES.SEARCHING,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});
    scopesToReoffer.push({scopeType, scopeId});
  }

  if (scopesToReoffer.length === 0) {
    return;
  }
  await batch.commit();
  for (const item of scopesToReoffer) {
    await offerScopeToNextCleanerInternal(item.scopeType, item.scopeId, {
      force: true,
      forceRebuild: true
    }).catch((error) => console.error('Failed to reoffer after cleaner conflict cancellation', {
      scopeType: item.scopeType,
      scopeId: item.scopeId,
      error: String(error?.message || error)
    }));
  }
}

async function reassignCleanerOverlapsAfterScheduleChange({
  changedSlotId,
  cleanerId,
  changedScope = {},
  reason = 'cleaner_time_conflict'
}) {
  const normalizedCleanerId = String(cleanerId || '').trim();
  const normalizedChangedSlotId = String(changedSlotId || '').trim();
  if (!normalizedCleanerId || !normalizedChangedSlotId) {
    return {ok: true, reassigned: 0};
  }
  const changedDateKey = toIsoDate(resolveScopeScheduledAt(changedScope));
  const changedRange = buildAssignmentRange(changedScope);
  const sameDaySlotsSnap = await db.collection('schedule_slots')
    .where('cleanerId', '==', normalizedCleanerId)
    .where('scheduledDateKey', '==', changedDateKey)
    .get();
  const conflicts = [];
  for (const doc of sameDaySlotsSnap.docs) {
    if (doc.id === normalizedChangedSlotId) {
      continue;
    }
    const slot = {id: doc.id, ...doc.data()};
    if (!activeSlotStatus(slot.status)) {
      continue;
    }
    const range = buildAssignmentRange(slot);
    if (range.startMinutes < changedRange.startMinutes) {
      continue;
    }
    if (!timeRangesOverlap(range, changedRange)) {
      continue;
    }
    conflicts.push({ref: doc.ref, id: doc.id, data: slot});
  }
  if (conflicts.length === 0) {
    return {ok: true, reassigned: 0};
  }

  const batch = db.batch();
  for (const conflict of conflicts) {
    const slot = conflict.data;
    const update = {
      cleanerId: null,
      cleanerName: null,
      cleanerPhone: null,
      status: 'pending_assignment',
      assignmentStatus: ORDER_ASSIGNMENT_STATUSES.SEARCHING,
      reassignmentReason: reason,
      previousCleanerId: normalizedCleanerId,
      previousCleanerName: slot.cleanerName || null,
      currentOfferCleanerId: null,
      currentOfferId: null,
      offerExpiresAt: null,
      rejectedBy: admin.firestore.FieldValue.arrayUnion(normalizedCleanerId),
      timeoutBy: admin.firestore.FieldValue.arrayUnion(normalizedCleanerId),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    };
    batch.set(conflict.ref, update, {merge: true});
    batch.set(db.collection('cleaner_orders').doc(conflict.id), update, {merge: true});
    batch.set(db.collection('cleaner_shifts').doc(conflict.id), update, {merge: true});
    if (slot.sourceOrderId) {
      batch.set(db.collection('customer_orders').doc(String(slot.sourceOrderId)), {
        cleanerId: null,
        cleanerName: null,
        cleanerPhone: null,
        status: 'pending_assignment',
        orderStatus: 'pending_assignment',
        assignmentStatus: ORDER_ASSIGNMENT_STATUSES.SEARCHING,
        reassignmentReason: reason,
        previousCleanerId: normalizedCleanerId,
        previousCleanerName: slot.cleanerName || null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      }, {merge: true});
    }
    const pendingOffersSnap = await db.collection('order_offers')
      .where('scopeType', '==', 'schedule_slot')
      .where('scopeId', '==', conflict.id)
      .where('status', '==', 'pending')
      .get();
    for (const offerDoc of pendingOffersSnap.docs) {
      batch.set(offerDoc.ref, {
        status: 'cancelled_conflict',
        response: reason,
        respondedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      }, {merge: true});
    }
  }
  await batch.commit();

  for (const conflict of conflicts) {
    const slot = conflict.data;
    if (slot.customerId) {
      await sendPushToUser(
        String(slot.customerId),
        'Ищем другую уборщицу',
        'Из-за изменения длительности предыдущей уборки мы подбираем другого исполнителя на ваш визит.',
        {
          type: 'cleaner_reassignment',
          orderId: conflict.id,
          slotId: conflict.id,
          reason
        }
      ).catch(() => {});
    }
    await offerScopeToNextCleanerInternal('schedule_slot', conflict.id, {
      force: true,
      forceRebuild: true
    }).catch((error) => console.error('Failed to reoffer conflicted slot after addon update', {
      slotId: conflict.id,
      error: String(error?.message || error)
    }));
  }
  return {ok: true, reassigned: conflicts.length};
}

async function acceptedOfferResultIfAssignedToCleaner(offer = {}, cleanerId = '') {
  try {
    const scope = await loadAssignmentScope(offer.scopeType, offer.scopeId);
    const assignedCleanerId = String(
      scope.data.cleanerId ||
      scope.data.assignedCleanerId ||
      scope.data.executorId ||
      ''
    ).trim();
    if (assignedCleanerId !== String(cleanerId).trim()) {
      return null;
    }
    return {
      ok: true,
      alreadyAccepted: true,
      offerId: offer.id,
      scopeType: offer.scopeType,
      scopeId: offer.scopeId,
      cleanerId
    };
  } catch (error) {
    console.error('Failed to verify accepted offer scope', error);
    return null;
  }
}

async function safelyOfferScopeToNextCleaner(scopeType, scopeId, options = {}) {
  try {
    return await offerScopeToNextCleanerInternal(scopeType, scopeId, options);
  } catch (error) {
    console.error('Failed to offer scope to cleaner', {
      scopeType,
      scopeId,
      error: String(error?.message || error)
    });
    return {ok: false, status: 'offer_failed', scopeId, error: String(error?.message || error)};
  }
}

async function backfillPendingAssignmentOffersInternal(limit = 50) {
  const results = {
    slotsChecked: 0,
    ordersChecked: 0,
    offered: 0,
    skipped: 0,
    errors: 0
  };
  const slotSnap = await db.collection('schedule_slots')
    .where('status', '==', 'pending_assignment')
    .limit(limit)
    .get();
  for (const doc of slotSnap.docs) {
    results.slotsChecked += 1;
    const data = doc.data() || {};
    if (
      String(data.cleanerId || '').trim() ||
      hasActiveOffer(data) ||
      !scopeHasConcreteSchedule(data)
    ) {
      results.skipped += 1;
      continue;
    }
    try {
      const result = await offerScopeToNextCleanerInternal('schedule_slot', doc.id, {
        forceRebuild: true,
        preferredCleanerId: String(data.preferredCleanerId || '').trim() || null
      });
      if (result.status === 'offered') {
        results.offered += 1;
      } else {
        results.skipped += 1;
      }
    } catch (error) {
      results.errors += 1;
      console.error('Failed to backfill schedule slot offer', doc.id, error);
    }
  }

  const orderSnap = await db.collection('customer_orders')
    .where('orderStatus', '==', 'pending_assignment')
    .limit(limit)
    .get();
  for (const doc of orderSnap.docs) {
    results.ordersChecked += 1;
    const data = doc.data() || {};
    if (
      String(data.cleanerId || '').trim() ||
      hasActiveOffer(data) ||
      !scopeHasConcreteSchedule(data)
    ) {
      results.skipped += 1;
      continue;
    }
    try {
      const result = await offerScopeToNextCleanerInternal('order', doc.id, {
        forceRebuild: true
      });
      if (result.status === 'offered') {
        results.offered += 1;
      } else {
        results.skipped += 1;
      }
    } catch (error) {
      results.errors += 1;
      console.error('Failed to backfill order offer', doc.id, error);
    }
  }

  return results;
}

async function notifyCustomerCleanerAssigned(scope = {}, cleaner = {}) {
  const customerId = String(scope.customerId || '').trim();
  if (!customerId) {
    return;
  }
  await sendPushToUser(
    customerId,
    'Уборщица назначена',
    `${cleaner.name || 'Исполнитель'} подтвердила заказ на ${scope.time || 'выбранное время'}.`,
    {
      type: 'cleaner_assigned',
      orderId: scope.orderId || scope.id,
      slotId: scope.scopeType === 'schedule_slot' ? scope.id : '',
      cleanerId: cleaner.id || '',
      scopeType: scope.scopeType || 'order'
    }
  );
}

async function notifyCleanerAssignmentConfirmed(scope = {}, cleaner = {}) {
  const cleanerId = String(cleaner.id || '').trim();
  if (!cleanerId) {
    return;
  }
  await sendPushToUser(
    cleanerId,
    'Заказ закреплен за вами',
    `${scope.time || 'Выбранное время'} · ${scope.address || 'Адрес уточняется'}`,
    {
      type: 'order_assignment_confirmed',
      orderId: scope.orderId || scope.id,
      slotId: scope.scopeType === 'schedule_slot' ? scope.id : '',
      scopeType: scope.scopeType || 'order'
    }
  );
}

async function notifyCustomerCleaningStartRequested(scope = {}) {
  const customerId = String(scope.customerId || '').trim();
  if (!customerId) {
    return false;
  }
  const dateText = String(scope.dateText || scope.date || '').trim();
  const timeText = String(scope.time || '').trim();
  const bodyParts = [
    scope.cleanerName || 'Уборщица',
    'нажала "Начать уборку".',
    dateText || timeText ? `Подтвердите старт: ${[dateText, timeText].filter(Boolean).join(' · ')}.` : 'Подтвердите старт уборки.'
  ];
  return sendPushToUser(
    customerId,
    'Уборщица начала уборку?',
    bodyParts.join(' '),
    {
      type: 'cleaning_start_confirmation',
      orderId: scope.orderId || scope.id || '',
      slotId: scope.scopeType === 'schedule_slot' ? scope.id || scope.slotId || '' : '',
      cleanerId: scope.cleanerId || '',
      scopeType: scope.scopeType || 'order'
    }
  );
}

async function notifyCleanerCleaningStartResponse(scope = {}, confirmed = false) {
  const cleanerId = String(scope.cleanerId || '').trim();
  if (!cleanerId) {
    return false;
  }
  return sendPushToUser(
    cleanerId,
    confirmed ? 'Клиент подтвердил старт' : 'Клиент не подтвердил старт',
    confirmed
      ? 'Можно продолжать уборку и отправить фотоотчёт после завершения.'
      : 'Завершить заказ нельзя, пока клиент не подтвердит начало уборки.',
    {
      type: confirmed ? 'cleaning_start_confirmed' : 'cleaning_start_rejected',
      orderId: scope.orderId || scope.id || '',
      slotId: scope.scopeType === 'schedule_slot' ? scope.id || scope.slotId || '' : '',
      scopeType: scope.scopeType || 'order'
    }
  );
}

function slugifyAddressPart(value, fallback = 'house') {
  const normalized = String(value || '')
    .toLowerCase()
    .replace(/ё/g, 'е')
    .replace(/[ә]/g, 'а')
    .replace(/[ғ]/g, 'г')
    .replace(/[қ]/g, 'к')
    .replace(/[ң]/g, 'н')
    .replace(/[ө]/g, 'о')
    .replace(/[ұү]/g, 'у')
    .replace(/[һ]/g, 'х')
    .replace(/[і]/g, 'и')
    .replace(/жилой комплекс/g, 'жк')
    .replace(/[^a-zа-я0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 80);
  return normalized || fallback;
}

function normalizeAddressLookupText(value) {
  return String(value || '')
    .toLowerCase()
    .replace(/ё/g, 'е')
    .replace(/[ә]/g, 'а')
    .replace(/[ғ]/g, 'г')
    .replace(/[қ]/g, 'к')
    .replace(/[ң]/g, 'н')
    .replace(/[ө]/g, 'о')
    .replace(/[ұү]/g, 'у')
    .replace(/[һ]/g, 'х')
    .replace(/[і]/g, 'и')
    .replace(/жилой комплекс/g, 'жк')
    .replace(/\b(улица|ул|проспект|пр|переулок|пер)\b/g, ' ')
    .replace(/\b(кошеси|көшесі|коше|көше|дангылы|даңғылы)\b/g, ' ')
    .replace(/[^a-zа-я0-9]+/g, ' ')
    .trim()
    .replace(/\s+/g, ' ');
}

function normalizeAddressLooseLookupText(value) {
  return normalizeAddressLookupText(value).replace(/ы/g, 'и');
}

function addressLookupTokens(value) {
  return normalizeAddressLooseLookupText(value)
    .split(' ')
    .filter((token) => token.length > 1);
}

function isAddressNumberToken(token) {
  return /^\d+[a-zа-я]?$/.test(String(token || ''));
}

function levenshteinDistance(a, b) {
  const left = String(a || '');
  const right = String(b || '');
  if (left === right) return 0;
  if (!left) return right.length;
  if (!right) return left.length;
  let previous = Array.from({length: right.length + 1}, (_, index) => index);
  for (let i = 0; i < left.length; i += 1) {
    const current = Array(right.length + 1).fill(0);
    current[0] = i + 1;
    for (let j = 0; j < right.length; j += 1) {
      const cost = left[i] === right[j] ? 0 : 1;
      current[j + 1] = Math.min(
        current[j] + 1,
        previous[j + 1] + 1,
        previous[j] + cost
      );
    }
    previous = current;
  }
  return previous[right.length];
}

function fuzzyAddressTokenScore(queryTokens = [], houseTokens = []) {
  const queryNumbers = queryTokens.filter(isAddressNumberToken);
  const houseNumberSet = new Set(houseTokens.filter(isAddressNumberToken));
  const numberMatched = queryNumbers.some((token) => houseNumberSet.has(token));
  let fuzzyStreetMatches = 0;
  for (const queryToken of queryTokens.filter((token) => !isAddressNumberToken(token))) {
    for (const houseToken of houseTokens.filter((token) => !isAddressNumberToken(token))) {
      const maxDistance = queryToken.length <= 4 || houseToken.length <= 4 ? 1 : 2;
      if (addressTokenLooksLikePart(queryToken, houseToken, maxDistance)) {
        fuzzyStreetMatches += 1;
        break;
      }
    }
  }
  if (numberMatched && fuzzyStreetMatches > 0) {
    return 55 + fuzzyStreetMatches * 20;
  }
  return fuzzyStreetMatches * 12;
}

function addressTokenLooksLikePart(queryToken, houseToken, maxDistance) {
  if (
    Math.abs(queryToken.length - houseToken.length) <= maxDistance &&
    levenshteinDistance(queryToken, houseToken) <= maxDistance
  ) {
    return true;
  }
  if (queryToken.length < 3 || houseToken.length <= queryToken.length) {
    return false;
  }
  for (let index = 0; index <= houseToken.length - queryToken.length; index += 1) {
    const part = houseToken.slice(index, index + queryToken.length);
    if (levenshteinDistance(queryToken, part) <= maxDistance) {
      return true;
    }
  }
  return false;
}

function addressAliasesText(data = {}) {
  const aliases = Array.isArray(data.aliases) ? data.aliases.join(' ') : '';
  return [
    data.addressRu,
    data.addressKk,
    data.titleRu,
    data.titleKk,
    data.searchKeywords,
    data.keywords,
    aliases
  ].filter(Boolean).join(' ');
}

function distanceMeters(lat1, lng1, lat2, lng2) {
  const earthRadius = 6371000;
  const toRadians = (value) => value * Math.PI / 180;
  const dLat = toRadians(lat2 - lat1);
  const dLng = toRadians(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRadians(lat1)) *
      Math.cos(toRadians(lat2)) *
      Math.sin(dLng / 2) *
      Math.sin(dLng / 2);
  return earthRadius * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function scoreHouseAddressMatch(house = {}, queryText = '', queryLooseText = '', lat = NaN, lng = NaN) {
  const houseText = normalizeAddressLookupText([
    house.id,
    house.address,
    house.residentialComplex,
    house.title,
    addressAliasesText(house)
  ].filter(Boolean).join(' '));
  const houseLooseText = normalizeAddressLooseLookupText(houseText);
  if (!queryText && !Number.isFinite(lat)) {
    return 0;
  }

  let score = 0;
  const queryTokens = queryText.split(' ').filter((token) => token.length > 1);
  const queryLooseTokens = queryLooseText.split(' ').filter((token) => token.length > 1);
  const houseTokens = addressLookupTokens(houseText);
  if (queryText && houseText) {
    if (houseText === queryText) {
      score += 120;
    } else if (houseText.includes(queryText) || queryText.includes(houseText)) {
      score += 90;
    }
    const matchedTokens = queryTokens.filter((token) => houseText.includes(token)).length;
    score += matchedTokens * 20;
    if (queryTokens.length > 1 && queryTokens.every((token) => houseText.includes(token))) {
      score += 45;
    }
  }
  if (queryLooseText && houseLooseText) {
    if (houseLooseText === queryLooseText) {
      score += 110;
    } else if (houseLooseText.includes(queryLooseText) || queryLooseText.includes(houseLooseText)) {
      score += 80;
    }
    const matchedLooseTokens = queryLooseTokens.filter((token) => houseLooseText.includes(token)).length;
    score += matchedLooseTokens * 18;
    if (queryLooseTokens.length > 1 && queryLooseTokens.every((token) => houseLooseText.includes(token))) {
      score += 40;
    }
    score += fuzzyAddressTokenScore(queryLooseTokens, houseTokens);
  }

  const houseLat = Number(house.lat);
  const houseLng = Number(house.lng);
  if (Number.isFinite(lat) && Number.isFinite(lng) && Number.isFinite(houseLat) && Number.isFinite(houseLng)) {
    const distance = distanceMeters(lat, lng, houseLat, houseLng);
    const radius = Math.min(Math.max(Number(house.radiusMeters || 500), 150), 1500);
    if (distance <= radius) {
      score += 100;
    } else if (distance <= radius * 2) {
      score += 35;
    }
  }
  return score;
}

async function resolveExistingHouseForAddress({address, residentialComplex, city, lat, lng}) {
  const queryText = normalizeAddressLookupText(`${residentialComplex || ''} ${address || ''}`);
  const queryLooseText = normalizeAddressLooseLookupText(queryText);
  if (!queryText && (!Number.isFinite(lat) || !Number.isFinite(lng))) {
    return null;
  }
  const snap = await db.collection('houses').get();
  let best = null;
  let bestScore = 0;
  for (const doc of snap.docs) {
    const data = {id: doc.id, ...(doc.data() || {})};
    const status = String(data.status || '').toUpperCase();
    if (status && status !== HOUSE_STATUS.ACTIVE && status !== HOUSE_STATUS.IN_PROGRESS) {
      continue;
    }
    const cityNormalized = normalizeCityName(city);
    const houseCity = normalizeCityName(data.city || data.cityNormalized);
    let score = scoreHouseAddressMatch(data, queryText, queryLooseText, lat, lng);
    if (cityNormalized && houseCity && cityNormalized === houseCity) {
      score += 15;
    }
    if (score > bestScore) {
      bestScore = score;
      best = data;
    }
  }
  return bestScore >= 35 ? best : null;
}

function normalizeProfileArea(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    throw new HttpsError('invalid-argument', 'Площадь квартиры должна быть больше 0.');
  }
  return Math.max(1, Math.round(parsed));
}

function normalizeCustomerAddressItem(item, index = 0) {
  const source = item && typeof item === 'object' ? item : {};
  const address = normalizeProfileText(source.address, 320);
  const residentialComplex = normalizeProfileText(source.residentialComplex, 240);
  const area = source.area == null || source.area === ''
    ? null
    : normalizeProfileArea(source.area);
  if (!address && !residentialComplex && area == null) {
    return null;
  }
  if ((!address && !residentialComplex) || area == null) {
    throw new HttpsError(
      'invalid-argument',
      'Для каждой квартиры нужны адрес и площадь.'
    );
  }
  const normalized = {
    id: normalizeProfileText(source.id, 80) || `address_${index + 1}`,
    address,
    residentialComplex: residentialComplex || address,
    addressPlaceId: normalizeProfileText(source.addressPlaceId, 240),
    houseId: normalizeProfileText(source.houseId, 120),
    houseStatus: normalizeProfileText(source.houseStatus, 40),
    entrance: normalizeProfileText(source.entrance, 40),
    apartment: normalizeProfileText(source.apartment, 40),
    area,
    isPrimary: source.isPrimary === true,
    updatedAt: admin.firestore.Timestamp.now()
  };
  const lat = Number(source.addressLat);
  if (Number.isFinite(lat)) {
    normalized.addressLat = lat;
  }
  const lng = Number(source.addressLng);
  if (Number.isFinite(lng)) {
    normalized.addressLng = lng;
  }
  return normalized;
}

function normalizeServiceAreas(value) {
  if (!Array.isArray(value)) {
    return [];
  }
  const seen = new Set();
  const result = [];
  for (const raw of value) {
    const item = normalizeProfileText(raw, 160);
    const key = item.toLowerCase();
    if (item && !seen.has(key)) {
      seen.add(key);
      result.push(item);
    }
  }
  return result.slice(0, 30);
}

async function loadAdminHouse(houseId) {
  const normalizedHouseId = normalizeProfileText(houseId, 120);
  if (!normalizedHouseId) {
    throw new HttpsError(
      'failed-precondition',
      'Выберите адрес из списка подключенных домов.'
    );
  }
  const houseSnap = await db.collection('houses').doc(normalizedHouseId).get();
  if (!houseSnap.exists) {
    throw new HttpsError(
      'failed-precondition',
      'Этот адрес не добавлен в зоне обслуживания.'
    );
  }
  return {...(houseSnap.data() || {}), id: houseSnap.id};
}

async function assertProfileHouseExists(houseId) {
  return loadAdminHouse(houseId);
}

async function assertActiveOrderHouse(houseId) {
  const house = await loadAdminHouse(houseId);
  const status = String(house.status || '').trim().toUpperCase();
  if (status !== HOUSE_STATUS.ACTIVE) {
    throw new HttpsError(
      'failed-precondition',
      'Заказы доступны только в активированных домах. Выберите активный адрес.'
    );
  }
  return house;
}

async function updateCustomerProfileInternal({userId, payload}) {
  const customerId = String(userId || '').trim();
  if (!customerId) {
    throw new HttpsError('invalid-argument', 'userId required');
  }

  const customerRef = db.collection('customers').doc(customerId);
  const customerSnap = await customerRef.get();
  const customer = customerSnap.exists ? (customerSnap.data() || {}) : {};
  const updates = {
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  };

  if (Object.prototype.hasOwnProperty.call(payload, 'name')) {
    updates.name = normalizeProfileText(payload.name, 120);
  }

  if (Object.prototype.hasOwnProperty.call(payload, 'residentialComplex')) {
    updates.residentialComplex = normalizeProfileText(payload.residentialComplex, 240);
  }

  if (Object.prototype.hasOwnProperty.call(payload, 'address')) {
    updates.address = normalizeProfileText(payload.address, 320);
  }

  if (Object.prototype.hasOwnProperty.call(payload, 'city')) {
    updates.city = normalizeProfileText(payload.city, 120);
  }

  if (Object.prototype.hasOwnProperty.call(payload, 'addressPlaceId')) {
    updates.addressPlaceId = normalizeProfileText(payload.addressPlaceId, 240);
  }

  if (Object.prototype.hasOwnProperty.call(payload, 'addressLat')) {
    const lat = Number(payload.addressLat);
    if (Number.isFinite(lat)) {
      updates.addressLat = lat;
    }
  }

  if (Object.prototype.hasOwnProperty.call(payload, 'addressLng')) {
    const lng = Number(payload.addressLng);
    if (Number.isFinite(lng)) {
      updates.addressLng = lng;
    }
  }

  if (Object.prototype.hasOwnProperty.call(payload, 'addresses')) {
    const rawAddresses = Array.isArray(payload.addresses) ? payload.addresses : [];
    const addresses = rawAddresses
      .slice(0, 10)
      .map((item, index) => normalizeCustomerAddressItem(item, index))
      .filter(Boolean);
    if (addresses.length > 0 && !addresses.some((item) => item.isPrimary)) {
      addresses[0].isPrimary = true;
    }
    updates.addresses = addresses;
  }

  if (Object.prototype.hasOwnProperty.call(payload, 'houseId')) {
    const house = await assertProfileHouseExists(payload.houseId);
    updates.houseId = house.id;
    updates.houseStatus = String(house.status || HOUSE_STATUS.INACTIVE).toUpperCase();
    updates.serviceArea = normalizeProfileText(
      house.serviceArea || house.zoneId || house.clusterName || house.residentialComplex,
      160
    );
    updates.zoneId = normalizeProfileText(house.zoneId, 120);
    updates.clusterName = normalizeProfileText(house.clusterName, 160);
  }

  if (
    !Object.prototype.hasOwnProperty.call(payload, 'houseId') &&
    Object.prototype.hasOwnProperty.call(payload, 'houseStatus')
  ) {
    updates.houseStatus = normalizeProfileText(payload.houseStatus, 40);
  }

  if (Object.prototype.hasOwnProperty.call(payload, 'entrance')) {
    updates.entrance = normalizeProfileText(payload.entrance, 40);
  }

  if (Object.prototype.hasOwnProperty.call(payload, 'apartment')) {
    updates.apartment = normalizeProfileText(payload.apartment, 40);
  }

  if (Object.prototype.hasOwnProperty.call(payload, 'gender')) {
    const gender = normalizeProfileText(payload.gender, 16);
    if (gender && !['female', 'male'].includes(gender)) {
      throw new HttpsError('invalid-argument', 'Некорректное значение пола.');
    }
    updates.gender = gender;
  }

  const hasAreaUpdate =
    Object.prototype.hasOwnProperty.call(payload, 'area') ||
    Object.prototype.hasOwnProperty.call(payload, 'initialArea') ||
    Object.prototype.hasOwnProperty.call(payload, 'actualArea');
  if (hasAreaUpdate) {
    const normalizedArea = normalizeProfileArea(
      payload.area ?? payload.actualArea ?? payload.initialArea
    );
    const areaUpdateIsExplicit =
      Object.prototype.hasOwnProperty.call(payload, 'actualArea') ||
      Object.prototype.hasOwnProperty.call(payload, 'initialArea');
    const isVerifiedArea =
      customer.areaVerified === true ||
      String(customer.areaStatus || '').toUpperCase() === 'VERIFIED';
    if (isVerifiedArea && !areaUpdateIsExplicit) {
      // Background writes from package/address screens may carry house area.
      // Do not let them overwrite a quality-control confirmed area.
    } else {
    const previousBaseline = Number(
      (isVerifiedArea
        ? (customer.actualArea || customer.apartmentArea || customer.area)
        : (customer.initialArea || customer.area || customer.apartmentArea)) || 0
    );
    const areaChanged = previousBaseline > 0 && previousBaseline !== normalizedArea;

    updates.area = normalizedArea;
    updates.initialArea = normalizedArea;
    updates.actualArea = normalizedArea;
    if (!areaChanged || isVerifiedArea) {
      updates.apartmentArea = normalizedArea;
    }

    if (areaChanged) {
      updates.areaVerified = false;
      updates.areaStatus = 'PENDING_REVIEW';
      updates.areaVerifiedAt = admin.firestore.FieldValue.delete();
      updates.apartmentArea = admin.firestore.FieldValue.delete();
    }
    }
  }

  if (Object.prototype.hasOwnProperty.call(payload, 'referredByCode')) {
    const normalizedCode = normalizeReferralCode(payload.referredByCode);
    const existingCode = normalizeReferralCode(customer.referredByCode);
    if (existingCode && normalizedCode !== existingCode) {
      throw new HttpsError(
        'failed-precondition',
        'Реферальный код уже сохранен и не может быть изменен.'
      );
    }
    if (!existingCode && normalizedCode) {
      const ownReferral = await ensureReferralLinkInternal(customerId);
      if (normalizedCode === normalizeReferralCode(ownReferral.referralCode)) {
        throw new HttpsError('invalid-argument', 'Нельзя использовать собственный реферальный код.');
      }
      const referrerSnap = await db.collection('customers')
        .where('referralCode', '==', normalizedCode)
        .limit(1)
        .get();
      if (referrerSnap.empty) {
        throw new HttpsError('not-found', 'Реферальный код не найден.');
      }
      if (referrerSnap.docs[0].id === customerId) {
        throw new HttpsError('invalid-argument', 'Нельзя использовать собственный реферальный код.');
      }
      updates.referredByCode = normalizedCode;
    }
  }

  await customerRef.set(updates, {merge: true});
  return {ok: true};
}

async function updateCleanerProfileInternal({userId, payload}) {
  const cleanerId = String(userId || '').trim();
  if (!cleanerId) {
    throw new HttpsError('invalid-argument', 'userId required');
  }

  const cleanerRef = db.collection('cleaners').doc(cleanerId);
  const updates = {
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  };

  if (Object.prototype.hasOwnProperty.call(payload, 'name')) {
    const name = normalizeProfileText(payload.name, 120);
    if (!name) {
      throw new HttpsError('invalid-argument', 'ФИО обязательно для заполнения.');
    }
    updates.name = name;
    updates.fullName = name;
  }

  if (Object.prototype.hasOwnProperty.call(payload, 'fullName')) {
    const fullName = normalizeProfileText(payload.fullName, 120);
    if (!fullName) {
      throw new HttpsError('invalid-argument', 'ФИО обязательно для заполнения.');
    }
    updates.name = fullName;
    updates.fullName = fullName;
  }

  if (Object.prototype.hasOwnProperty.call(payload, 'homeAddress')) {
    const homeAddress = normalizeProfileText(payload.homeAddress, 240);
    if (!homeAddress) {
      throw new HttpsError('invalid-argument', 'Домашний адрес обязателен для заполнения.');
    }
    updates.homeAddress = homeAddress;
  }

  if (Object.prototype.hasOwnProperty.call(payload, 'emergencyContactPhone')) {
    const emergencyContactPhone = normalizeProfileText(
      payload.emergencyContactPhone,
      40
    );
    if (!emergencyContactPhone) {
      throw new HttpsError(
        'invalid-argument',
        'Дополнительный номер знакомого обязателен для заполнения.'
      );
    }
    updates.emergencyContactPhone = emergencyContactPhone;
  }

  if (Object.prototype.hasOwnProperty.call(payload, 'emergencyContactRelation')) {
    const emergencyContactRelation = normalizeProfileText(
      payload.emergencyContactRelation,
      80
    );
    if (!emergencyContactRelation) {
      throw new HttpsError(
        'invalid-argument',
        'Поле "Кем приходится" обязательно для заполнения.'
      );
    }
    updates.emergencyContactRelation = emergencyContactRelation;
  }

  if (Object.prototype.hasOwnProperty.call(payload, 'email')) {
    updates.email = normalizeProfileText(payload.email, 160);
  }

  if (Object.prototype.hasOwnProperty.call(payload, 'city')) {
    const city = normalizeProfileText(payload.city, 120);
    if (!city) {
      throw new HttpsError('invalid-argument', 'Город обязателен для заполнения.');
    }
    updates.city = city;
  }

  if (Object.prototype.hasOwnProperty.call(payload, 'serviceAreas')) {
    const serviceAreas = normalizeServiceAreas(payload.serviceAreas);
    if (serviceAreas.length === 0) {
      throw new HttpsError(
        'invalid-argument',
        'Выберите хотя бы один рабочий район.'
      );
    }
    updates.serviceAreas = serviceAreas;
  }

  if (Object.prototype.hasOwnProperty.call(payload, 'serviceAreaIds')) {
    const serviceAreaIds = normalizeServiceAreas(payload.serviceAreaIds);
    if (serviceAreaIds.length === 0) {
      throw new HttpsError(
        'invalid-argument',
        'Выберите хотя бы один рабочий район.'
      );
    }
    updates.serviceAreaIds = serviceAreaIds;
  }

  await cleanerRef.set(updates, {merge: true});
  return {ok: true};
}

function calculateCustomPackageQuoteFromPricing({
  pricing = {},
  rooms = 0,
  bathrooms = 0,
  area = 0,
  frequency = 1,
  billingPeriodMonths = 1,
  windows = false,
  ironing = false,
  balcony = false,
  addonsDetailed = []
}) {
  const base = Number(pricing.basePrice ?? 0);
  const roomRate = Number(pricing.roomRate || 2000);
  const bathroomRate = Number(pricing.bathroomRate || 1500);
  const areaRate = Number(pricing.areaRate ?? 120);
  const areaThreshold = Number(pricing.areaThreshold ?? 0);
  const windowsPrice = Number(pricing.windowsPrice || 3000);
  const ironingPrice = Number(pricing.ironingPrice || 2000);
  const balconyPrice = Number(pricing.balconyPrice || 1500);
  const addonPricing = calculateDetailedAddonPricing(pricing, addonsDetailed);
  const addonTotalPrice =
    addonPricing.billableTotal > 0
      ? addonPricing.billableTotal
      : (windows ? windowsPrice : 0) +
        (ironing ? ironingPrice : 0) +
        (balcony ? balconyPrice : 0);

  const normalizedFrequency = Math.max(1, Number(frequency || 1));
  const normalizedBillingPeriodMonths = Math.max(1, Number(billingPeriodMonths || 1));
  const basePerCleaning = Math.round(
    base +
    Number(rooms || 0) * roomRate +
    Number(bathrooms || 0) * bathroomRate +
    Math.max(Number(area || 0) - areaThreshold, 0) * areaRate
  );

  const discountRate =
    normalizedBillingPeriodMonths >= 3 && normalizedFrequency > 1 ? 0.20 :
    normalizedFrequency >= 4 ? 0.12 :
    normalizedFrequency >= 2 ? 0.07 :
    0;

  const cleaningCount = normalizedFrequency * normalizedBillingPeriodMonths;
  const packageSubtotal = basePerCleaning * cleaningCount;
  const subtotal = packageSubtotal + addonTotalPrice;
  const discountAmount = Math.round(packageSubtotal * discountRate);
  const monthlyPrice = subtotal - discountAmount;

  return {
    perCleaningPrice: basePerCleaning,
    monthlyPrice,
    subtotal,
    discountRate,
    discountAmount,
    cleaningCount,
    billingPeriodMonths: normalizedBillingPeriodMonths,
    addonTotalPrice,
    addonsBillableTotal: addonPricing.billableTotal,
    addonsSeparatePaymentTotal: addonPricing.separatePaymentTotal,
    separatePaymentAddons: addonPricing.separatePaymentAddons
  };
}

function buildAddonPricingCatalog(pricing = {}) {
  const fromConfig = pricing.addonCatalog && typeof pricing.addonCatalog === 'object'
    ? pricing.addonCatalog
    : {};
  const defaults = {
    window_standard: {label: 'Мытье окон стандарт', price: 3000},
    window_panorama: {label: 'Панорама', price: 5500},
    window_mosquito: {label: 'Мытье москитных сеток', price: 1200},
    balcony_window_standard: {label: 'Балкон: мытье окон стандарт', price: 3000},
    balcony_panorama: {label: 'Балкон: панорама', price: 5500},
    balcony_balcony: {label: 'Балкон', price: 2500},
    balcony_loggia: {label: 'Лоджия', price: 2500},
    balcony_terrace: {label: 'Терасса', price: 5000},
    kitchen_oven: {label: 'Чистка духовки внутри', price: 2500},
    kitchen_hood: {label: 'Чистка вытяжки и фильтров', price: 2200},
    kitchen_fridge: {label: 'Мытье холодильника внутри', price: 2500},
    kitchen_facades: {label: 'Мытье фасадов кухонного гарнитура', price: 3000},
    kitchen_full_set: {label: 'Полное мытье кухонного гарнитура', price: 6500},
    kitchen_stove: {label: 'Чистка плит и варочных панелей', price: 1800},
    kitchen_microwave: {label: 'Чистка микроволновки', price: 1200},
    kitchen_apron: {label: 'Мытье фартука', price: 1500},
    kitchen_dishes_hand: {label: 'Мытье посуды вручную', price: 2500},
    kitchen_dishwasher_loading: {label: 'Загрузка посуды в посудомойку', price: 800},
    bath_tile_walls: {label: 'Стены кафель', price: 3000},
    bath_glass_walls: {label: 'Стеклянные стены душа и ванны', price: 2800},
    bath_washer_wipe: {label: 'Протирка стиральной машины', price: 900},
    textile_bed_linen_ironing: {label: 'Глажка постельного белья', price: 1800},
    textile_clothes_ironing: {label: 'Глажка одежды', price: 1800},
    textile_curtains_ironing: {label: 'Глажка штор', price: 3500},
    textile_bed_change: {label: 'Замена постельного белья и заправка кроватей', price: 1500},
    hard_chandelier_standard: {label: 'Чистка люстр стандартная', price: 2500},
    hard_chandelier_complex: {label: 'Чистка люстр сложная', price: 4500},
    hard_chandelier_super: {label: 'Чистка люстр супер сложная', price: 7000},
    hard_lamps: {label: 'Светильники и плафоны', price: 1200},
    hard_upper_shelves: {label: 'Чистка верхних полок, антресолей и шкафов', price: 1800},
    hard_baseboards: {label: 'Чистка плинтусов', price: 1400},
    hard_doors: {label: 'Мытье дверей', price: 900},
    hard_cobweb: {label: 'Удаление паутины и пыли в труднодоступных местах', price: 1600},
    furniture_sofa: {
      label: 'Химчистка диванов',
      price: 9000,
      separatePayment: true
    },
    furniture_mattress: {
      label: 'Химчистка матрасов',
      price: 7000,
      separatePayment: true
    },
    carpet_cleaning: {
      label: 'Химчистка ковров и паласов',
      price: 0,
      separatePayment: true
    }
  };
  const catalog = {...defaults};
  for (const [key, value] of Object.entries(fromConfig)) {
    catalog[key] = {
      ...catalog[key],
      ...(value && typeof value === 'object' ? value : {})
    };
  }
  const defaultDurations = {
    window_standard: 15,
    window_panorama: 20,
    window_mosquito: 10,
    balcony_window_standard: 15,
    balcony_panorama: 20,
    balcony_balcony: 20,
    balcony_loggia: 20,
    balcony_terrace: 30,
    kitchen_oven: 25,
    kitchen_hood: 25,
    kitchen_fridge: 25,
    kitchen_facades: 30,
    kitchen_full_set: 60,
    kitchen_stove: 20,
    kitchen_microwave: 15,
    kitchen_apron: 15,
    kitchen_dishes_hand: 25,
    kitchen_dishwasher_loading: 10,
    bath_tile_walls: 30,
    bath_glass_walls: 25,
    bath_washer_wipe: 10,
    textile_bed_linen_ironing: 20,
    textile_clothes_ironing: 20,
    textile_curtains_ironing: 35,
    textile_bed_change: 15,
    hard_chandelier_standard: 25,
    hard_chandelier_complex: 45,
    hard_chandelier_super: 70,
    hard_lamps: 15,
    hard_upper_shelves: 25,
    hard_baseboards: 20,
    hard_doors: 15,
    hard_cobweb: 20,
    furniture_sofa: 60,
    furniture_mattress: 45,
    carpet_cleaning: 60
  };
  for (const [key, minutes] of Object.entries(defaultDurations)) {
    if (catalog[key] && !Number(catalog[key].durationMinutes || 0)) {
      catalog[key].durationMinutes = minutes;
    }
  }
  return catalog;
}

function normalizeDetailedAddons(addonsDetailed = []) {
  return (Array.isArray(addonsDetailed) ? addonsDetailed : [])
    .map((item) => ({
      key: String(item?.key || '').trim(),
      label: String(item?.label || '').trim(),
      quantity: Math.max(0, Number(item?.quantity || 0)),
      separatePayment: item?.separatePayment === true,
      price: Math.max(0, Number(item?.price || 0)),
      durationMinutes: Math.max(0, Number(item?.durationMinutes || 0))
    }))
    .filter((item) => item.key && item.quantity > 0);
}

function calculateDetailedAddonPricing(pricing = {}, addonsDetailed = []) {
  const catalog = buildAddonPricingCatalog(pricing);
  const normalized = normalizeDetailedAddons(addonsDetailed);
  let billableTotal = 0;
  let separatePaymentTotal = 0;
  const separatePaymentAddons = [];

  for (const item of normalized) {
    const pricingItem = catalog[item.key] || {};
    const unitPrice = Math.max(0, Number(pricingItem.price || item.price || 0));
    const lineTotal = unitPrice * item.quantity;
    const lineDurationMinutes = Math.max(
      0,
      Number(item.durationMinutes || 0) ||
        (Number(pricingItem.durationMinutes || 0) * item.quantity)
    );
    if (pricingItem.separatePayment === true || item.separatePayment === true) {
      separatePaymentTotal += lineTotal;
      separatePaymentAddons.push({
        key: item.key,
        label: item.label || pricingItem.label || item.key,
        quantity: item.quantity,
        price: lineTotal,
        durationMinutes: lineDurationMinutes
      });
    } else {
      billableTotal += lineTotal;
    }
  }

  return {
    billableTotal,
    separatePaymentTotal,
    separatePaymentAddons
  };
}

function orderAddonPayload(source = {}, pricing = {}) {
  const addonsDetailed = normalizeDetailedAddons(source.addonsDetailed);
  const detailedAddonPricing = calculateDetailedAddonPricing(pricing, addonsDetailed);
  return {
    addons: Array.isArray(source.addons) ? source.addons : [],
    addonsDetailed,
    addonsSeparatePaymentTotal: detailedAddonPricing.separatePaymentTotal,
    separatePaymentAddons: detailedAddonPricing.separatePaymentAddons
  };
}

function calculateAddonTotalPriceFromPricing(pricing = {}, addons = []) {
  const normalizedAddons = new Set(
    (Array.isArray(addons) ? addons : []).map((item) => String(item))
  );
  let total = 0;
  if (normalizedAddons.has('Мытье окон')) {
    total += Number(pricing.windowsPrice || 3000);
  }
  if (normalizedAddons.has('Глажка белья')) {
    total += Number(pricing.ironingPrice || 2000);
  }
  if (normalizedAddons.has('Уборка балкона')) {
    total += Number(pricing.balconyPrice || 1500);
  }
  return total;
}

function normalizeOrderPackageId(rawId, rawName = '') {
  const normalizedId = String(rawId || '').trim().toLowerCase();
  if (normalizedId) {
    switch (normalizedId) {
      case 'single':
        return 'single';
      case 'basic':
      case 'twice':
        return 'basic';
      case 'standard':
      case 'four':
        return 'standard';
      case 'premium':
      case 'eight':
        return 'premium';
      case 'quarter':
      case 'quarterly':
        return 'quarter';
      case 'general':
      case 'general_cleaning':
        return 'general_cleaning';
      case 'renovation':
      case 'post_renovation':
        return 'post_renovation';
      case 'addons_only':
        return 'addons_only';
      default:
        return normalizedId;
    }
  }

  const normalizedName = String(rawName || '').trim().toLowerCase();
  if (normalizedName.includes('доп. услуг')) return 'addons_only';
  if (normalizedName.includes('после ремонта')) return 'post_renovation';
  if (normalizedName.includes('генераль')) return 'general_cleaning';
  if (normalizedName.includes('кварт')) return 'quarter';
  if (normalizedName.includes('8 раз')) return 'premium';
  if (normalizedName.includes('4 раз')) return 'standard';
  if (normalizedName.includes('два раза') || normalizedName.includes('2 раза')) return 'basic';
  if (normalizedName.includes('разов')) return 'single';
  return normalizedName;
}

function resolvePackageVisitsPerMonth(packageId, requestedVisits = 1) {
  switch (packageId) {
    case 'single':
      return 1;
    case 'basic':
      return 2;
    case 'standard':
      return 4;
    case 'premium':
      return 8;
    case 'quarter': {
      const visits = Number(requestedVisits || 0);
      return [2, 4, 8].includes(visits) ? visits : 2;
    }
    default:
      return Math.max(1, Number(requestedVisits || 1));
  }
}

function subscriptionIncludedVisits(subscription = {}) {
  const packageId = String(subscription.packageId || subscription.package_id || '').trim().toLowerCase();
  const frequency = parseFrequencyConfig(subscription.frequencyLabel, subscription.package);
  const billingPeriodMonths = Number(
    subscription.billingPeriodMonths || frequency.billingPeriodMonths || 1
  );
  const requestedVisits = Number(
    subscription.cleaningsPerMonth ||
    frequency.monthlyVisits ||
    subscription.includedVisits ||
    1
  );
  const visitsPerMonth = resolvePackageVisitsPerMonth(packageId, requestedVisits);
  const expectedIncludedVisits = frequency.kind === 'one_time' && !packageId && requestedVisits <= 1
    ? 1
    : visitsPerMonth * billingPeriodMonths;
  return Math.max(
    Number(subscription.includedVisits || 0),
    Number(subscription.cleaningsPerMonth || 0) * billingPeriodMonths,
    expectedIncludedVisits
  );
}

function defaultFixedPackagePrice(packageId) {
  if (packageId === 'general_cleaning') return 45000;
  if (packageId === 'post_renovation') return 60000;
  return 0;
}

async function loadCustomerPackageConfig(packageId) {
  if (!packageId || packageId === 'addons_only') {
    return {};
  }
  const snap = await db.collection('customer_packages').doc(String(packageId)).get();
  return snap.exists ? (snap.data() || {}) : {};
}

function referralDiscountPercentForCount(count) {
  const normalized = Math.max(0, Number(count || 0));
  for (const tier of REFERRAL_DISCOUNT_TIERS) {
    if (normalized >= tier.count) {
      return tier.percent;
    }
  }
  return 0;
}

function nextReferralDiscountTier(count) {
  const normalized = Math.max(0, Number(count || 0));
  const ordered = [...REFERRAL_DISCOUNT_TIERS].sort((a, b) => a.count - b.count);
  return ordered.find((tier) => normalized < tier.count) || null;
}

async function recalculateReferralStatsInternal(userId) {
  const statsRef = db.collection('referralStats').doc(referralStatsId(userId));
  const sentSnap = await db.collection('referrals')
    .where('user_id', '==', userId)
    .get();

  let invited = 0;
  let registered = 0;
  let paid = 0;
  let bonus = 0;
  let monthlyActivated = 0;
  const referrals = [];

  for (const doc of sentSnap.docs) {
    const item = doc.data() || {};
    const referredUserId = item.referredUserId || item.invited_user_id || null;
    const invitedPhone = String(item.invited_phone || item.invitedPhone || '').trim();
    let referredUserName = null;
    let referredUserPhone = null;
    if (referredUserId) {
      const referredSnap = await db.collection('customers').doc(String(referredUserId)).get();
      if (referredSnap.exists) {
        const referredData = referredSnap.data() || {};
        referredUserName = referredData.name || null;
        referredUserPhone = referredData.phone || null;
      }
    }
    const hasConcreteInvite = Boolean(referredUserId || invitedPhone);
    if (hasConcreteInvite) {
      invited += 1;
    }
    if (referredUserId) {
      registered += 1;
    }
    if (item.bonusStatus === 'paid') {
      paid += 1;
      bonus += Number(item.bonusAmount || 0);
    }
    if (item.monthlyPackageActivatedAt || item.qualifiedAt || item.bonusStatus === 'paid') {
      monthlyActivated += 1;
    }
    referrals.push({
      id: doc.id,
      invitedPhone: invitedPhone || null,
      referredUserId,
      referredUserName,
      referredUserPhone,
      status: item.status || 'sent',
      bonusStatus: item.bonusStatus || 'pending',
      bonusAmount: Number(item.bonusAmount || 0),
      paymentVisibleStatus: (item.monthlyPackageActivatedAt || item.qualifiedAt) ? 'monthly_paid' : (
        item.bonusStatus === 'paid' ? 'paid' : 'pending'
      ),
      monthlyPackageActivatedAt: item.monthlyPackageActivatedAt || null,
      qualifiedAt: item.qualifiedAt || null,
      paidAt: item.paidAt || null,
      createdAt: item.createdAt || null
    });
  }

  const referralDiscountPercent = referralDiscountPercentForCount(monthlyActivated);
  const nextDiscountTier = nextReferralDiscountTier(monthlyActivated);
  const remainingForNextDiscount = nextDiscountTier
    ? Math.max(nextDiscountTier.count - monthlyActivated, 0)
    : 0;

  await statsRef.set({
    userId,
    invited,
    registered,
    paid,
    bonus,
    monthlyActivated,
    referralDiscountPercent,
    nextReferralDiscountThreshold: nextDiscountTier?.count || null,
    nextReferralDiscountPercent: nextDiscountTier?.percent || null,
    remainingForNextDiscount,
    referrals,
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, {merge: true});

  await db.collection('customers').doc(String(userId)).set({
    referralQualifiedCount: monthlyActivated,
    referralDiscountPercent,
    referralDiscountUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, {merge: true});

  return {
    userId,
    invited,
    registered,
    paid,
    bonus,
    monthlyActivated,
    referralDiscountPercent,
    nextReferralDiscountThreshold: nextDiscountTier?.count || null,
    nextReferralDiscountPercent: nextDiscountTier?.percent || null,
    remainingForNextDiscount,
    referrals
  };
}

async function applyReferralPaymentBonusInternal(orderId) {
  const orderSnap = await db.collection('customer_orders').doc(orderId).get();
  if (!orderSnap.exists) {
    throw new HttpsError('not-found', 'Order not found');
  }
  const order = orderSnap.data() || {};
  const packageId = String(order.packageId || order.package_id || '').trim().toLowerCase();
  if (packageId === 'addons_only') {
    return {ok: true, applied: false, reason: 'addons_only'};
  }
  const paidAmount = Number(order.price || order.total || order.amount || 0);
  if (!Number.isFinite(paidAmount) || paidAmount <= 0) {
    return {ok: true, applied: false, reason: 'zero_amount'};
  }
  const referredUserId = order.customerId || null;
  if (!referredUserId) {
    return {ok: true, applied: false, reason: 'no_customer'};
  }

  const customerSnap = await db.collection('customers').doc(referredUserId).get();
  if (!customerSnap.exists) {
    return {ok: true, applied: false, reason: 'customer_not_found'};
  }
  const customer = customerSnap.data() || {};
  const referrerCode = normalizeReferralCode(customer.referredByCode);
  if (!referrerCode) {
    return {ok: true, applied: false, reason: 'no_referral_code'};
  }

  const referrerSnap = await db.collection('customers')
    .where('referralCode', '==', referrerCode)
    .limit(1)
    .get();
  if (referrerSnap.empty) {
    return {ok: true, applied: false, reason: 'referrer_not_found'};
  }

  const referrerDoc = referrerSnap.docs[0];
  const referrerUserId = referrerDoc.id;
  if (referrerUserId === referredUserId) {
    return {ok: true, applied: false, reason: 'self_referral'};
  }

  const referralQuery = await db.collection('referrals')
    .where('user_id', '==', referrerUserId)
    .where('referredUserId', '==', referredUserId)
    .limit(1)
    .get();

  const policies = await getPolicyConfig();
  const bonusAmount = Number(
    order.referralBonusAmount || policies.referralBonusAmount
  );
  const referralRef = referralQuery.empty
    ? db.collection('referrals').doc(`${referrerUserId}_${referredUserId}`)
    : referralQuery.docs[0].ref;

  await db.runTransaction(async (tx) => {
    const referralSnap = await tx.get(referralRef);
    const existing = referralSnap.exists ? referralSnap.data() || {} : {};
    if (existing.bonusStatus === 'paid' && (existing.monthlyPackageActivatedAt || existing.qualifiedAt)) {
      return;
    }

    tx.set(referralRef, {
      user_id: referrerUserId,
      referredUserId,
      invited_user_id: referredUserId,
      referredOrderId: orderId,
      referredByCode: referrerCode,
      status: 'registered',
      bonusStatus: 'paid',
      bonusAmount:
        existing.bonusStatus === 'paid'
          ? Number(existing.bonusAmount || bonusAmount)
          : bonusAmount,
      monthlyPackageActivatedAt:
        existing.monthlyPackageActivatedAt ||
        admin.firestore.FieldValue.serverTimestamp(),
      qualifiedAt:
        existing.qualifiedAt ||
        existing.monthlyPackageActivatedAt ||
        admin.firestore.FieldValue.serverTimestamp(),
      paidAt: admin.firestore.FieldValue.serverTimestamp(),
      createdAt: existing.createdAt || admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});

    if (existing.bonusStatus !== 'paid') {
      tx.set(referrerDoc.ref, {
        bonusPoints: Number(referrerDoc.data().bonusPoints || 0) + bonusAmount,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      }, {merge: true});
    }

    tx.set(db.collection('customers').doc(referredUserId), {
      referralAppliedAt: admin.firestore.FieldValue.serverTimestamp(),
      referralPaidOrderId: orderId,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});
  });

  await recalculateReferralStatsInternal(referrerUserId);
  await recordCustomerBonusTransaction({
    userId: referrerUserId,
    amount: bonusAmount,
    title: 'Бонус за покупку пакета',
    reason: 'Приглашенный пользователь оплатил пакет',
    orderId
  });
  await sendPushToUser(
    referrerUserId,
    'Реферал оплатил',
    `Вам начислен бонус ${bonusAmount} ₸ за приглашенного пользователя.`,
    {type: 'referral_paid', referredUserId, orderId}
  );

  return {ok: true, applied: true, referrerUserId, referredUserId, bonusAmount};
}

async function hasActiveMonthlyPackage(customerId) {
  const subscriptionsSnap = await db.collection('subscriptions')
    .where('customerId', '==', String(customerId))
    .where('status', '==', 'active')
    .limit(10)
    .get();
  return subscriptionsSnap.docs.some((doc) => {
    const data = doc.data() || {};
    return parseFrequencyConfig(data.frequencyLabel, data.package).kind === 'monthly';
  });
}

async function settleReservedBonusForOrderInternal(orderId) {
  const orderRef = db.collection('customer_orders').doc(String(orderId));
  await db.runTransaction(async (tx) => {
    const orderSnap = await tx.get(orderRef);
    if (!orderSnap.exists) {
      return;
    }
    const order = orderSnap.data() || {};
    const reserved = Number(order.bonusAppliedAmount || 0);
    if (reserved <= 0 || order.bonusReleasedAt || order.bonusSettledAt) {
      return;
    }
    tx.set(orderRef, {
      bonusSettledAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});
  });
}

async function releaseReservedBonusForOrderInternal(orderId, reason = 'payment_failed') {
  const orderRef = db.collection('customer_orders').doc(String(orderId));
  await db.runTransaction(async (tx) => {
    const orderSnap = await tx.get(orderRef);
    if (!orderSnap.exists) {
      return;
    }
    const order = orderSnap.data() || {};
    const reserved = Number(order.bonusAppliedAmount || 0);
    if (reserved <= 0 || order.bonusReleasedAt || order.bonusSettledAt || !order.customerId) {
      return;
    }
    const customerRef = db.collection('customers').doc(String(order.customerId));
    const customerSnap = await tx.get(customerRef);
    const customer = customerSnap.exists ? (customerSnap.data() || {}) : {};
    tx.set(customerRef, {
      bonusPoints: Number(customer.bonusPoints || 0) + reserved,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});
    tx.set(orderRef, {
      bonusReleasedAt: admin.firestore.FieldValue.serverTimestamp(),
      bonusReleaseReason: String(reason)
    }, {merge: true});
  });
}

async function refundBonusForCanceledSlotInternal({
  slotId,
  customerId,
  orderId = null,
  reason = 'customer_cancelled_schedule_slot'
}) {
  const slotKey = String(slotId || '').trim();
  const userId = String(customerId || '').trim();
  if (!slotKey || !userId) {
    return 0;
  }

  const [paymentsSnap, addonRequestsSnap, addonOrdersSnap] = await Promise.all([
    db.collection('payments').where('slotId', '==', slotKey).get(),
    db.collection('addon_requests').where('slotId', '==', slotKey).get(),
    db.collection('customer_orders').where('slotId', '==', slotKey).get()
  ]);

  const paymentRefs = paymentsSnap.docs
    .filter((doc) => {
      const payment = doc.data() || {};
      return String(payment.customerId || userId) === userId;
    })
    .map((doc) => doc.ref);
  const paymentOrderIds = new Set(paymentsSnap.docs.map((doc) => {
    const payment = doc.data() || {};
    return String(payment.orderId || doc.id || '').trim();
  }).filter(Boolean));
  const paymentAddonRequestIds = new Set(paymentsSnap.docs.map((doc) => {
    const payment = doc.data() || {};
    return String(payment.addonRequestId || '').trim();
  }).filter(Boolean));
  const addonRequestRefs = addonRequestsSnap.docs
    .filter((doc) => {
      const request = doc.data() || {};
      return String(request.customerId || userId) === userId &&
        !paymentAddonRequestIds.has(doc.id);
    })
    .map((doc) => doc.ref);
  const addonOrderRefs = addonOrdersSnap.docs
    .filter((doc) => {
      const order = doc.data() || {};
      const isAddonOrder = String(order.pricingMode || '').trim() === 'addons_only' ||
        String(order.packageId || '').trim() === 'addons_only' ||
        String(order.mergedIntoSlotId || '').trim() === slotKey;
      return isAddonOrder &&
        String(order.customerId || userId) === userId &&
        !paymentOrderIds.has(doc.id);
    })
    .map((doc) => doc.ref);

  if (paymentRefs.length === 0 && addonRequestRefs.length === 0 && addonOrderRefs.length === 0) {
    return 0;
  }

  let refundedAmount = 0;
  await db.runTransaction(async (tx) => {
    let total = 0;
    const linkedAddonRequestRefs = new Map();
    const linkedAddonOrderRefs = new Map();
    const paymentSnaps = [];
    const addonRequestSnaps = [];
    const addonOrderSnaps = [];

    for (const ref of paymentRefs) {
      const snap = await tx.get(ref);
      paymentSnaps.push(snap);
      const payment = snap.exists ? (snap.data() || {}) : {};
      const addonRequestId = String(payment.addonRequestId || '').trim();
      if (addonRequestId) {
        linkedAddonRequestRefs.set(addonRequestId, db.collection('addon_requests').doc(addonRequestId));
      }
      const paymentOrderId = String(payment.orderId || snap.id || '').trim();
      if (paymentOrderId && isAddonPaymentRecord(payment)) {
        linkedAddonOrderRefs.set(paymentOrderId, db.collection('customer_orders').doc(paymentOrderId));
      }
    }
    for (const ref of addonRequestRefs) {
      addonRequestSnaps.push(await tx.get(ref));
    }
    for (const ref of addonOrderRefs) {
      addonOrderSnaps.push(await tx.get(ref));
    }

    for (const snap of paymentSnaps) {
      if (!snap.exists) {
        continue;
      }
      const payment = snap.data() || {};
      const amount = Math.max(0, Number(payment.bonusAppliedAmount || 0));
      if (String(payment.customerId || userId) !== userId) {
        continue;
      }
      const paidAmount = Math.max(0, Number(payment.amount || payment.price || 0));
      const paymentStatus = String(payment.paymentStatus || payment.status || '').toLowerCase();
      const needsMoneyRefund = paidAmount > 0 && ['paid', 'payment_confirmed'].includes(paymentStatus);
      if (amount > 0 && !payment.bonusRefundedAt) {
        total += amount;
      }
      tx.set(snap.ref, {
        status: 'canceled',
        paymentStatus: 'canceled',
        refundRequired: needsMoneyRefund,
        refundStatus: needsMoneyRefund ? 'pending' : (amount > 0 && !payment.bonusRefundedAt ? 'bonus_refunded' : 'not_required'),
        ...(amount > 0 && !payment.bonusRefundedAt ? {
          bonusRefundedAt: admin.firestore.FieldValue.serverTimestamp(),
          bonusRefundReason: String(reason)
        } : {}),
        canceledAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      }, {merge: true});
    }

    for (const snap of addonRequestSnaps) {
      if (!snap.exists) {
        continue;
      }
      const request = snap.data() || {};
      const amount = Math.max(0, Number(request.bonusAppliedAmount || 0));
      if (String(request.customerId || userId) !== userId) {
        continue;
      }
      const paidAmount = Math.max(0, Number(request.amount || request.price || 0));
      const paymentStatus = String(request.paymentStatus || request.status || '').toLowerCase();
      const needsMoneyRefund = paidAmount > 0 && ['paid', 'payment_confirmed'].includes(paymentStatus);
      if (amount > 0 && !request.bonusRefundedAt) {
        total += amount;
      }
      tx.set(snap.ref, {
        status: 'canceled',
        paymentStatus: 'canceled',
        refundRequired: needsMoneyRefund,
        refundStatus: needsMoneyRefund ? 'pending' : (amount > 0 && !request.bonusRefundedAt ? 'bonus_refunded' : 'not_required'),
        ...(amount > 0 && !request.bonusRefundedAt ? {
          bonusRefundedAt: admin.firestore.FieldValue.serverTimestamp(),
          bonusRefundReason: String(reason)
        } : {}),
        canceledAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      }, {merge: true});
    }

    for (const snap of addonOrderSnaps) {
      if (!snap.exists) {
        continue;
      }
      const order = snap.data() || {};
      const amount = Math.max(0, Number(order.bonusAppliedAmount || 0));
      if (String(order.customerId || userId) !== userId) {
        continue;
      }
      const paidAmount = Math.max(0, Number(order.amount || order.price || 0));
      const paymentStatus = String(order.paymentStatus || order.status || '').toLowerCase();
      const needsMoneyRefund = paidAmount > 0 && ['paid', 'payment_confirmed'].includes(paymentStatus);
      if (amount > 0 && !order.bonusRefundedAt) {
        total += amount;
      }
      tx.set(snap.ref, {
        status: 'canceled',
        orderStatus: 'canceled',
        paymentStatus: 'canceled',
        refundRequired: needsMoneyRefund,
        refundStatus: needsMoneyRefund ? 'pending' : (amount > 0 && !order.bonusRefundedAt ? 'bonus_refunded' : 'not_required'),
        ...(amount > 0 && !order.bonusRefundedAt ? {
          bonusRefundedAt: admin.firestore.FieldValue.serverTimestamp(),
          bonusRefundReason: String(reason)
        } : {}),
        canceledAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      }, {merge: true});
    }

    for (const ref of linkedAddonRequestRefs.values()) {
      tx.set(ref, {
        status: 'canceled',
        paymentStatus: 'canceled',
        refundStatus: 'bonus_refunded',
        bonusRefundedAt: admin.firestore.FieldValue.serverTimestamp(),
        bonusRefundReason: String(reason),
        canceledAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      }, {merge: true});
    }

    for (const ref of linkedAddonOrderRefs.values()) {
      tx.set(ref, {
        status: 'canceled',
        orderStatus: 'canceled',
        paymentStatus: 'canceled',
        ...clearAddonPayload(),
        canceledAt: admin.firestore.FieldValue.serverTimestamp(),
        cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
        bonusRefundedAt: admin.firestore.FieldValue.serverTimestamp(),
        bonusRefundReason: String(reason)
      }, {merge: true});
    }

    if (total <= 0) {
      return;
    }
    tx.set(db.collection('customers').doc(userId), {
      bonusPoints: admin.firestore.FieldValue.increment(total),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});
    tx.set(db.collection('bonus_transactions').doc(), {
      userId,
      amount: total,
      type: 'bonus_refund',
      title: 'Возврат бонусов',
      reason: 'Возврат за отмененные доп. услуги',
      orderId: String(orderId || slotKey),
      slotId: slotKey,
      createdAt: admin.firestore.FieldValue.serverTimestamp()
    });
    refundedAmount = total;
  });

  return refundedAmount;
}

function safeAwardDocId(customerId, promotionId) {
  return `${String(customerId || '').trim()}_${String(promotionId || '').trim()}`
    .replace(/[^A-Za-z0-9_-]/g, '_')
    .slice(0, 140);
}

async function awardStartupPackageBonusInternal(orderId) {
  const policies = await getPolicyConfig();
  const orderRef = db.collection('customer_orders').doc(String(orderId));
  const promotionsSnap = await db.collection('promotions')
    .where('isActive', '==', true)
    .where('type', '==', 'package_purchase_bonus')
    .get();
  let awardedCustomerId = null;
  let awardedAmount = 0;
  let awardedReason = '';
  await db.runTransaction(async (tx) => {
    const orderSnap = await tx.get(orderRef);
    if (!orderSnap.exists) {
      return;
    }
    const order = orderSnap.data() || {};
    const packageId = String(order.packageId || '').trim().toLowerCase();
    if (
      !order.customerId ||
      packageId === 'addons_only'
    ) {
      return;
    }
    const promotionAwards = Array.isArray(order.promotionBonusAwards)
      ? order.promotionBonusAwards
      : [];
    const alreadyAwardedPromotionIds = new Set(
      promotionAwards.map((item) => String(item?.promotionId || ''))
    );
    const customerRef = db.collection('customers').doc(String(order.customerId));
    const customerSnap = await tx.get(customerRef);
    const customer = customerSnap.exists ? (customerSnap.data() || {}) : {};
    const legacyAlreadyAwarded =
      customer.startupPackageBonusAwardedAt ||
      Number(customer.startupPackageBonusTotal || 0) > 0;
    const legacyBonusAmount =
      policies.packagePurchaseBonusEnabled === true &&
      !order.startupPackageBonusAwardedAt &&
      !legacyAlreadyAwarded
        ? Math.max(Number(policies.packagePurchaseBonusAmount || 0), 0)
        : 0;
    const customerPromotionAwards =
      customer.promotionAwards && typeof customer.promotionAwards === 'object'
        ? customer.promotionAwards
        : {};
    const promotionLockSnaps = await Promise.all(
      promotionsSnap.docs.map((doc) => tx.get(
        db.collection('promotion_awards').doc(
          safeAwardDocId(order.customerId, doc.id)
        )
      ))
    );
    const promotionLocksById = new Set(
      promotionLockSnaps
        .filter((snap) => snap.exists)
        .map((snap) => String(snap.data()?.promotionId || ''))
    );
    const matchedPromotions = promotionsSnap.docs
      .map((doc) => ({id: doc.id, ...(doc.data() || {})}))
      .map((promotion) => {
        const rewardMode = String(promotion.rewardMode || 'fixed');
        const paidAmount = Math.max(
          Number(order.price || order.finalAmount || order.amount || order.total || 0),
          0
        );
        const rewardPercent = Math.min(
          Math.max(Number(promotion.rewardPercent || 0), 0),
          100
        );
        const rewardAmount = rewardMode === 'percent'
          ? Math.round(paidAmount * (rewardPercent / 100))
          : Math.max(Number(promotion.rewardAmount || 0), 0);
        return {
          ...promotion,
          rewardMode: rewardMode === 'percent' ? 'percent' : 'fixed',
          rewardPercent,
          rewardAmount
        };
      })
      .filter((promotion) => {
        const promotionId = String(promotion.id || '').trim();
        if (!promotionId || alreadyAwardedPromotionIds.has(promotionId)) {
          return false;
        }
        const targetPackageId = String(promotion.packageId || '').trim().toLowerCase();
        if (targetPackageId && targetPackageId !== packageId) {
          return false;
        }
        if (
          promotion.oncePerCustomer !== false &&
          (customerPromotionAwards[promotionId] || promotionLocksById.has(promotionId))
        ) {
          return false;
        }
        return Math.max(Number(promotion.rewardAmount || 0), 0) > 0;
      });
    const stackablePromotions = matchedPromotions.filter(
      (promotion) => promotion.stackable === true
    );
    const exclusivePromotions = matchedPromotions
      .filter((promotion) => promotion.stackable !== true)
      .sort((a, b) =>
        Math.max(Number(b.rewardAmount || 0), 0) -
        Math.max(Number(a.rewardAmount || 0), 0)
      );
    const selectedPromotions = [
      ...stackablePromotions,
      ...(exclusivePromotions[0] ? [exclusivePromotions[0]] : [])
    ];
    const promotionBonusAmount = selectedPromotions.reduce(
      (sum, promotion) => sum + Math.max(Number(promotion.rewardAmount || 0), 0),
      0
    );
    const totalBonusAmount = legacyBonusAmount + promotionBonusAmount;
    if (totalBonusAmount <= 0) {
      return;
    }
    awardedCustomerId = String(order.customerId);
    awardedAmount = totalBonusAmount;
    awardedReason = selectedPromotions.length > 0
      ? selectedPromotions.map((promotion) => String(promotion.title || 'Акция')).join(', ')
      : 'Бонус за покупку пакета';
    const newPromotionAwards = selectedPromotions.map((promotion) => ({
      promotionId: String(promotion.id),
      title: String(promotion.title || 'Акция'),
      rewardAmount: Math.max(Number(promotion.rewardAmount || 0), 0),
      rewardMode: String(promotion.rewardMode || 'fixed'),
      rewardPercent: Math.max(Number(promotion.rewardPercent || 0), 0),
      rewardTarget: String(promotion.rewardTarget || 'addons'),
      maxSpendPercent: Math.max(Number(promotion.maxSpendPercent || 50), 0),
      stackable: promotion.stackable === true
    }));
    const promotionAwardsById = {...customerPromotionAwards};
    for (const award of newPromotionAwards) {
      promotionAwardsById[award.promotionId] = {
        title: award.title,
        rewardAmount: award.rewardAmount,
        rewardMode: award.rewardMode,
        rewardPercent: award.rewardPercent,
        rewardTarget: award.rewardTarget,
        orderId: String(orderId),
        awardedAt: admin.firestore.FieldValue.serverTimestamp()
      };
    }
    tx.set(customerRef, {
      bonusPoints: Number(customer.bonusPoints || 0) + totalBonusAmount,
      startupPackageBonusTotal:
        Number(customer.startupPackageBonusTotal || 0) + totalBonusAmount,
      ...(legacyBonusAmount > 0
        ? {startupPackageBonusAwardedAt: admin.firestore.FieldValue.serverTimestamp()}
        : {}),
      promotionAwards: promotionAwardsById,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});
    for (const award of newPromotionAwards) {
      tx.set(
        db.collection('promotion_awards').doc(
          safeAwardDocId(order.customerId, award.promotionId)
        ),
        {
          customerId: String(order.customerId),
          promotionId: award.promotionId,
          orderId: String(orderId),
          title: award.title,
          rewardAmount: award.rewardAmount,
          rewardMode: award.rewardMode,
          rewardPercent: award.rewardPercent,
          rewardTarget: award.rewardTarget,
          awardedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        },
        {merge: false}
      );
    }
    const orderUpdate = {
      promotionBonusAwards: [...promotionAwards, ...newPromotionAwards],
      promotionBonusAmount,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    };
    if (legacyBonusAmount > 0) {
      orderUpdate.startupPackageBonusAwardedAt =
        admin.firestore.FieldValue.serverTimestamp();
      orderUpdate.startupPackageBonusAmount = legacyBonusAmount;
    }
    tx.set(orderRef, orderUpdate, {merge: true});
  });
  if (awardedCustomerId && awardedAmount > 0) {
    await recordCustomerBonusTransaction({
      userId: awardedCustomerId,
      amount: awardedAmount,
      title: 'Бонус за покупку пакета',
      reason: awardedReason,
      orderId
    });
    await sendPushToUser(
      awardedCustomerId,
      'Начислены бонусы',
      `Вам начислено ${awardedAmount} ₸ за покупку пакета.`,
      {
        type: 'package_bonus',
        bonusAmount: String(awardedAmount),
        orderId: String(orderId),
        reason: 'package_purchase'
      }
    );
  }
}

async function verifyApartmentAreaInternal({
  userId,
  actualArea,
  areaTechnicalPlanUrl = null,
  actorId = null
}) {
  if (!Number.isFinite(Number(actualArea)) || Number(actualArea) <= 0) {
    throw new HttpsError('invalid-argument', 'actualArea must be a positive number');
  }

  const customerRef = db.collection('customers').doc(userId);
  const areaConfigSnap = await db.collection('area_config').doc('main').get();
  const areaConfig = areaConfigSnap.exists ? (areaConfigSnap.data() || {}) : {};
  const configuredBonusAmount = Math.max(Number(areaConfig.bonusAmount || 2000), 0);
  const normalizedActualArea = Number(actualArea);
  const adminTriggeredReview = Boolean(actorId && actorId !== userId);
  const outcome = await db.runTransaction(async (tx) => {
    const customerSnap = await tx.get(customerRef);
    if (!customerSnap.exists) {
      throw new HttpsError('not-found', 'Customer not found');
    }
    const customer = customerSnap.data() || {};
    const initialArea = Number(customer.initialArea || customer.area || customer.apartmentArea || 0);
    const hasBaselineArea = initialArea > 0;
    const areaVerified = adminTriggeredReview ? true : false;
    const bonusAlreadyAwarded = customer.areaVerificationBonusAwardedAt != null;
    const areaStatus = adminTriggeredReview
      ? 'VERIFIED'
      : 'PENDING_REVIEW';
    const shouldAwardBonus =
      adminTriggeredReview &&
      configuredBonusAmount > 0 &&
      !bonusAlreadyAwarded;

    const customerUpdate = {
      initialArea: hasBaselineArea ? initialArea : normalizedActualArea,
      apartmentArea: normalizedActualArea,
      actualArea: normalizedActualArea,
      areaVerified,
      areaStatus,
      areaVerificationSubmittedAt: admin.firestore.FieldValue.serverTimestamp(),
      areaVerificationSubmittedBy: actorId || userId,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    };

    if (areaTechnicalPlanUrl) {
      customerUpdate.areaTechnicalPlanUrl = String(areaTechnicalPlanUrl);
    }

    if (adminTriggeredReview) {
      customerUpdate.areaVerifiedAt = admin.firestore.FieldValue.serverTimestamp();
    } else {
      customerUpdate.areaVerifiedAt = admin.firestore.FieldValue.delete();
    }

    if (shouldAwardBonus) {
      customerUpdate.bonusPoints = Number(customer.bonusPoints || 0) + configuredBonusAmount;
      customerUpdate.areaVerificationBonusAwardedAt = admin.firestore.FieldValue.serverTimestamp();
      customerUpdate.areaVerificationBonusAmount = configuredBonusAmount;
    }

    tx.set(customerRef, customerUpdate, {merge: true});

    return {
      customer,
      initialArea: hasBaselineArea ? initialArea : normalizedActualArea,
      hasBaselineArea,
      areaVerified,
      areaStatus,
      pendingReview: !adminTriggeredReview,
      bonusAwarded: shouldAwardBonus,
      bonusAmount: shouldAwardBonus ? configuredBonusAmount : 0
    };
  });

  if (!adminTriggeredReview || !outcome.areaVerified) {
    await db.collection('areaMismatchReports').add({
      userId,
      customerId: userId,
      houseId: outcome.customer.houseId || null,
      initialArea: outcome.initialArea,
      actualArea: normalizedActualArea,
      difference: outcome.hasBaselineArea ? normalizedActualArea - outcome.initialArea : 0,
      status: 'open',
      reviewStatus: adminTriggeredReview ? 'mismatch' : 'pending',
      areaTechnicalPlanUrl: areaTechnicalPlanUrl || outcome.customer.areaTechnicalPlanUrl || null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      createdBy: actorId || userId
    });
  }

  await sendPushToUser(
    userId,
    outcome.pendingReview
      ? 'Площадь отправлена на проверку'
      : outcome.areaVerified
        ? 'Площадь подтверждена'
        : 'Найдена разница в площади',
    outcome.pendingReview
      ? `Документы отправлены администратору на проверку. Площадь ${normalizedActualArea} м² пока не подтверждена.`
      : outcome.areaVerified
        ? `Площадь квартиры подтверждена: ${normalizedActualArea} м².${outcome.bonusAwarded ? ` Бонус ${outcome.bonusAmount} ₸ начислен.` : ''}`
        : `Зафиксировано расхождение: было ${outcome.initialArea} м², стало ${normalizedActualArea} м².`,
    {type: 'area_verification', areaStatus: outcome.areaStatus}
  );
  if (outcome.bonusAwarded && outcome.bonusAmount > 0) {
    await recordCustomerBonusTransaction({
      userId,
      amount: outcome.bonusAmount,
      title: 'Бонус за подтверждение площади',
      reason: 'Площадь квартиры подтверждена отделом контроля качества'
    });
    await sendPushToUser(
      userId,
      'Начислены бонусы',
      `Вам начислено ${outcome.bonusAmount} ₸ за подтверждение площади.`,
      {
        type: 'area_bonus',
        bonusAmount: String(outcome.bonusAmount),
        reason: 'area_verification'
      }
    );
  }

  if (adminTriggeredReview && outcome.areaVerified) {
    await createAreaRecalculationPaymentForLatestOrder({
      userId,
      previousArea: outcome.initialArea,
      actualArea: normalizedActualArea,
      reportId: null
    });
  }

  return {
    ok: true,
    userId,
    initialArea: outcome.initialArea,
    actualArea: normalizedActualArea,
    areaVerified: outcome.areaVerified,
    areaStatus: outcome.areaStatus,
    pendingReview: outcome.pendingReview,
    bonusAwarded: outcome.bonusAwarded,
    bonusAmount: outcome.bonusAmount,
    areaTechnicalPlanUrl: areaTechnicalPlanUrl || outcome.customer.areaTechnicalPlanUrl || null
  };
}

function recalculateAreaAdjustmentForOrder(order = {}, actualArea = 0) {
  const previousArea = Number(order.area || order.apartmentArea || 0);
  const originalPrice = Number(order.originalPrice || order.price || order.amount || 0);
  const previousPaidAmount = Number(order.price || order.amount || originalPrice || 0);
  const addonTotal = Number(order.addonTotalPrice || 0);
  const tierPercent = Number(order.tierDiscountPercent || 0);
  const referralPercent = Number(order.referralDiscountPercent || 0);
  const bonusApplied = Number(order.bonusAppliedAmount || 0);
  if (!previousArea || !originalPrice || !actualArea) {
    return null;
  }
  let recalculatedOriginal = originalPrice;
  if (originalPrice > addonTotal) {
    const packagePart = originalPrice - addonTotal;
    recalculatedOriginal = (packagePart / previousArea * Number(actualArea)) + addonTotal;
  }
  const tierDiscount = Math.round(recalculatedOriginal * (tierPercent / 100));
  const afterTier = Math.max(0, recalculatedOriginal - tierDiscount);
  const referralDiscount = Math.round(afterTier * (referralPercent / 100));
  const afterReferral = Math.max(0, afterTier - referralDiscount);
  const finalPrice = Math.round(Math.max(0, afterReferral - bonusApplied));
  const amountDue = Math.max(0, finalPrice - Math.round(previousPaidAmount));
  return {
    previousArea: Math.round(previousArea),
    previousPaidAmount: Math.round(previousPaidAmount),
    recalculatedAmount: finalPrice,
    amountDue
  };
}

async function createAreaRecalculationPaymentForLatestOrder({
  userId,
  previousArea,
  actualArea,
  reportId = null
}) {
  const orderSnap = await db.collection('customer_orders')
    .where('customerId', '==', String(userId))
    .orderBy('createdAt', 'desc')
    .limit(10)
    .get();
  const orderDoc = orderSnap.docs.find((doc) => {
    const data = doc.data() || {};
    const paymentStatus = String(data.paymentStatus || '').toLowerCase();
    const orderStatus = String(data.orderStatus || data.status || '').toLowerCase();
    return paymentStatus === 'paid' && !['canceled', 'cancelled', 'failed'].includes(orderStatus);
  });
  if (!orderDoc) {
    return null;
  }
  const order = orderDoc.data() || {};
  const recalculation = recalculateAreaAdjustmentForOrder(
    {...order, area: previousArea || order.area},
    actualArea
  );
  if (!recalculation || recalculation.amountDue <= 0) {
    return null;
  }
  const paymentId = `area_recalc_${orderDoc.id}`;
  const batch = db.batch();
  batch.set(orderDoc.ref, {
    area: Number(actualArea),
    apartmentArea: Number(actualArea),
    areaVerified: true,
    areaStatus: 'VERIFIED',
    previousArea: recalculation.previousArea,
    previousPaidAmount: recalculation.previousPaidAmount,
    areaRecalculatedPrice: recalculation.recalculatedAmount,
    areaAdjustmentAmount: recalculation.amountDue,
    areaAdjustmentPaymentStatus: 'pending_invoice',
    qualityControlRecalculatedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, {merge: true});
  batch.set(db.collection('payments').doc(paymentId), {
    id: paymentId,
    orderId: orderDoc.id,
    sourceOrderId: orderDoc.id,
    type: 'area_recalculation',
    packageName: 'Доплата за подтверждение площади',
    frequencyLabel: order.frequencyLabel || null,
    customerId: order.customerId || userId,
    customerName: order.customerName || order.client || null,
    customerPhone: order.customerPhone || order.phone || null,
    address: order.address || null,
    residentialComplex: order.residentialComplex || null,
    houseId: order.houseId || null,
    previousArea: recalculation.previousArea,
    actualArea: Number(actualArea),
    previousPaidAmount: recalculation.previousPaidAmount,
    recalculatedAmount: recalculation.recalculatedAmount,
    areaAdjustmentAmount: recalculation.amountDue,
    amount: recalculation.amountDue,
    price: recalculation.amountDue,
    currency: 'KZT',
    provider: 'kaspi_manual_request',
    status: 'pending_invoice',
    paymentStatus: 'pending_invoice',
    areaMismatchReportId: reportId || '',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, {merge: true});
  await batch.commit();
  return {paymentId, orderId: orderDoc.id, amountDue: recalculation.amountDue};
}

async function requestAreaQualityCheckInternal({
  userId,
  actualArea,
  preferredDate,
  preferredTime,
  orderId = null,
  actorId = null
}) {
  const normalizedArea = Number(actualArea || 0);
  const dateText = String(preferredDate || '').trim();
  const timeText = String(preferredTime || '').trim();
  if (!Number.isFinite(normalizedArea) || normalizedArea <= 0) {
    throw new HttpsError('invalid-argument', 'actualArea must be a positive number');
  }
  if (!dateText || !timeText) {
    throw new HttpsError('invalid-argument', 'preferredDate and preferredTime are required');
  }

  const customerRef = db.collection('customers').doc(userId);
  const reportRef = db.collection('areaMismatchReports').doc();
  const result = await db.runTransaction(async (tx) => {
    const customerSnap = await tx.get(customerRef);
    if (!customerSnap.exists) {
      throw new HttpsError('not-found', 'Customer not found');
    }
    const customer = customerSnap.data() || {};
    const initialArea = Number(customer.initialArea || customer.area || customer.apartmentArea || normalizedArea);
    const customerName = customer.fullName || customer.name || customer.displayName || null;
    const customerPhone = customer.phone || customer.phoneNumber || null;
    const address = customer.address || customer.addressLine || null;
    const houseId = customer.houseId || null;
    tx.set(customerRef, {
      initialArea,
      apartmentArea: normalizedArea,
      area: normalizedArea,
      areaVerified: false,
      areaStatus: 'QUALITY_CHECK_SCHEDULED',
      areaQualityCheckRequestedAt: admin.firestore.FieldValue.serverTimestamp(),
      areaQualityCheckDate: dateText,
      areaQualityCheckTime: timeText,
      areaQualityCheckOrderId: orderId || null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});
    tx.set(reportRef, {
      type: 'quality_area_check',
      userId,
      customerId: userId,
      customerName,
      customerPhone,
      houseId,
      address,
      initialArea,
      actualArea: normalizedArea,
      difference: normalizedArea - initialArea,
      preferredDate: dateText,
      preferredTime: timeText,
      orderId: orderId || null,
      status: 'open',
      reviewStatus: 'scheduled',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      createdBy: actorId || userId
    });
    return {initialArea, customerName, customerPhone};
  });

  const isFortyEightHourCheck = timeText.toLowerCase().includes('48');
  await sendPushToUser(
    userId,
    'Назначена проверка квадратуры',
    isFortyEightHourCheck
      ? 'В течение 48 часов отдел контроля качества приедет к вам для проверки площади. Также вы можете пройти проверку в приложении, загрузив план квартиры.'
      : `Контроль качества проверит площадь ${dateText} в ${timeText}.`,
    {
      type: 'area_quality_check',
      reportId: reportRef.id,
      orderId: orderId || '',
      preferredDate: dateText,
      preferredTime: timeText
    }
  );

  return {
    ok: true,
    reportId: reportRef.id,
    userId,
    initialArea: result.initialArea,
    actualArea: normalizedArea,
    preferredDate: dateText,
    preferredTime: timeText
  };
}

async function notifyUsersAboutVideo(videoId, video) {
  const audienceType = String(video.audienceType || 'client');
  const title = audienceType === 'cleaner' ? 'Новое обучение' : 'Новое полезное видео';
  const body = String(video.title || 'Добавлено новое видео');
  const targetCollections = audienceType === 'both'
    ? ['customers', 'cleaners']
    : audienceType === 'cleaner'
      ? ['cleaners']
      : ['customers'];

  const userIds = new Set();
  for (const collectionName of targetCollections) {
    const snap = await db.collection(collectionName).get();
    for (const doc of snap.docs) {
      userIds.add(doc.id);
    }
  }

  let batch = db.batch();
  let batchSize = 0;
  for (const userId of userIds) {
    batch.set(db.collection('notifications').doc(), {
      userId,
      type: 'video_content',
      title,
      body,
      payload: {
        videoId,
        audienceType
      },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      read: false
    });
    batchSize += 1;

    if (batchSize >= 450) {
      await batch.commit();
      batch = db.batch();
      batchSize = 0;
    }
  }

  if (batchSize > 0) {
    await batch.commit();
  }

  for (const userId of userIds) {
    await sendPushToUser(userId, title, body, {
      type: 'video_content',
      videoId,
      audienceType,
      skipInbox: true
    });
  }
}

async function getHouseStatsInternal(houseId) {
  const houseSnap = await db.collection('houses').doc(houseId).get();
  if (!houseSnap.exists) {
    throw new HttpsError('not-found', 'House not found');
  }

  const house = {id: houseSnap.id, ...houseSnap.data()};
  const policies = await getPolicyConfig();
  const usersSnap = await db.collection('customers')
    .where('houseId', '==', houseId)
    .get();
  const activeUsers = usersSnap.docs.map((doc) => doc.data());
  const packageBreakdown = {};
  for (const user of activeUsers) {
    const packageName = String(user.planName || user.packageName || 'Без пакета');
    packageBreakdown[packageName] = (packageBreakdown[packageName] || 0) + 1;
  }

  let popularPackage = null;
  let popularCount = -1;
  for (const [pkg, count] of Object.entries(packageBreakdown)) {
    if (count > popularCount) {
      popularPackage = pkg;
      popularCount = count;
    }
  }

  const threshold = Number(house.threshold || policies.defaultHouseThreshold);
  const currentCount = Number(house.current_users || house.waitlistCount || 0);
  const progress = threshold <= 0 ? 0 : Math.min(currentCount / threshold, 1);
  const remaining = Math.max(threshold - currentCount, 0);
  const normalizedStatus = house.status || HOUSE_STATUS.INACTIVE;

  return {
    house: {
      id: house.id,
      status: normalizedStatus,
      address: house.address || house.title || null,
      threshold,
      current_users: currentCount,
      total_users: activeUsers.length,
      waitlistCount: Number(house.waitlistCount || 0)
    },
    packageBreakdown,
    popularPackage,
    progress,
    remaining,
    activationText:
      normalizedStatus === HOUSE_STATUS.ACTIVE
        ? 'Дом уже активирован'
        : normalizedStatus === HOUSE_STATUS.IN_PROGRESS
            ? `Почти запустились. До старта осталось ${remaining} квартир`
            : `Пока набираем заявки. До запуска осталось ${remaining} квартир`
  };
}

async function activateHouseIfThresholdReachedInternal(houseId) {
  const houseRef = db.collection('houses').doc(houseId);
  const snap = await houseRef.get();
  if (!snap.exists) {
    throw new HttpsError('not-found', 'House not found');
  }

  const house = snap.data();
  const policies = await getPolicyConfig();
  const threshold = Number(house.threshold || policies.defaultHouseThreshold);
  const currentUsers = Number(house.current_users || 0);
  const nextStatus =
    currentUsers >= threshold ? HOUSE_STATUS.ACTIVE :
    currentUsers > 0 ? HOUSE_STATUS.IN_PROGRESS :
    HOUSE_STATUS.INACTIVE;

  await houseRef.set({
    status: nextStatus,
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, {merge: true});

  return nextStatus;
}

function overpassPolygonString(polygon) {
  return polygon
    .map((point) => `${point.lat} ${point.lng}`)
    .join(' ');
}

function normalizeOsmHouseId(element) {
  const type = String(element.type || 'item').replace(/[^a-z0-9_-]/gi, '_');
  const id = String(element.id || '').replace(/[^a-z0-9_-]/gi, '_');
  return `osm_${type}_${id}`;
}

function normalizeOsmAddress(tags = {}, fallbackTitle = '') {
  const street = normalizeProfileText(tags['addr:street'], 180);
  const place = normalizeProfileText(tags['addr:place'], 180);
  const houseNumber = normalizeProfileText(tags['addr:housenumber'], 60);
  const name = normalizeProfileText(tags.name || tags['addr:housename'], 180);
  const city = normalizeProfileText(tags['addr:city'], 120);
  const parts = [];
  if (street) {
    parts.push(houseNumber ? `${street}, ${houseNumber}` : street);
  } else if (place) {
    parts.push(houseNumber ? `${place}, ${houseNumber}` : place);
  } else if (name) {
    parts.push(name);
  } else if (fallbackTitle) {
    parts.push(fallbackTitle);
  }
  if (city) {
    parts.push(city);
  }
  return parts.join(', ');
}

async function importHousesForServiceZoneInternal({zoneId, auth}) {
  assertAdmin(auth);
  const normalizedZoneId = normalizeProfileText(zoneId, 120);
  if (!normalizedZoneId) {
    throw new HttpsError('invalid-argument', 'zoneId required');
  }
  const zoneSnap = await db.collection('service_zones').doc(normalizedZoneId).get();
  if (!zoneSnap.exists) {
    throw new HttpsError('not-found', 'Service zone not found');
  }
  const zone = {id: zoneSnap.id, ...zoneSnap.data()};
  const polygon = geoPolygonFrom(zone.polygon);
  if (polygon.length < 3) {
    throw new HttpsError(
      'failed-precondition',
      'Район должен содержать минимум 3 точки.'
    );
  }

  const polygonText = overpassPolygonString(polygon);
  const query = `
    [out:json][timeout:30];
    (
      node["addr:housenumber"](poly:"${polygonText}");
      way["addr:housenumber"](poly:"${polygonText}");
      relation["addr:housenumber"](poly:"${polygonText}");
      way["building"](poly:"${polygonText}");
      relation["building"](poly:"${polygonText}");
    );
    out center tags 1200;
  `;
  const overpassEndpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter'
  ];
  let payload = null;
  let lastError = null;
  for (const endpoint of overpassEndpoints) {
    try {
      const response = await fetch(endpoint, {
        method: 'POST',
        headers: {
          'content-type': 'application/x-www-form-urlencoded;charset=UTF-8',
          'user-agent': 'Domly Admin OSM Import/1.0 (admin@domly.kz)'
        },
        body: new URLSearchParams({data: query})
      });
      if (!response.ok) {
        lastError = `${endpoint} returned ${response.status}`;
        continue;
      }
      payload = await response.json();
      break;
    } catch (error) {
      lastError = `${endpoint} failed: ${error.message || error}`;
    }
  }
  if (!payload) {
    throw new HttpsError(
      'unavailable',
      `OSM import failed: ${lastError || 'unknown error'}`
    );
  }
  const elements = Array.isArray(payload.elements) ? payload.elements : [];
  const title = normalizeProfileText(zone.title || zone.name || zone.id, 160);
  const city = normalizeProfileText(zone.city, 120);
  const seen = new Set();
  const imported = [];

  for (const element of elements) {
    const tags = element.tags || {};
    const lat = Number(element.lat ?? element.center?.lat);
    const lng = Number(element.lon ?? element.lng ?? element.center?.lon ?? element.center?.lng);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
      continue;
    }
    if (!geoPointInPolygon({lat, lng, polygon})) {
      continue;
    }
    const address = normalizeOsmAddress(tags, normalizeProfileText(tags.name, 180));
    if (!address) {
      continue;
    }
    const key = address.toLowerCase();
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    imported.push({
      id: normalizeOsmHouseId(element),
      title: normalizeProfileText(tags.name, 180) || address,
      address,
      residentialComplex: normalizeProfileText(tags.name, 180) || address,
      city,
      lat,
      lng,
      zoneId: normalizedZoneId,
      serviceAreaId: normalizedZoneId,
      serviceArea: title,
      clusterName: title,
      status: HOUSE_STATUS.ACTIVE,
      threshold: 1,
      current_users: 1,
      source: 'osm',
      osmType: element.type || null,
      osmId: element.id || null,
      importedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    });
  }

  let importedCount = 0;
  for (let i = 0; i < imported.length; i += 450) {
    const batch = db.batch();
    for (const house of imported.slice(i, i + 450)) {
      batch.set(db.collection('houses').doc(house.id), house, {merge: true});
      importedCount += 1;
    }
    await batch.commit();
  }

  await db.collection('service_zones').doc(normalizedZoneId).set({
    importedHousesCount: importedCount,
    importedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, {merge: true});

  return {
    ok: true,
    zoneId: normalizedZoneId,
    importedCount,
    scannedCount: elements.length
  };
}

async function notifyHouseProgressInternal(houseId, options = {}) {
  const reason = String(options.reason || '').trim().toLowerCase();
  const stats = await getHouseStatsInternal(houseId);
  const house = stats.house;
  const remaining = Math.max(Number(house.threshold) - Number(house.current_users), 0);
  const shouldNotifyProgress = reason === 'neighbor_joined';
  const shouldNotifyActivation = reason === 'neighbor_joined' && house.status === HOUSE_STATUS.ACTIVE;
  if (!shouldNotifyProgress && !shouldNotifyActivation) {
    return {ok: true, remaining, skipped: true};
  }
  const waitlistSnap = await db.collection('house_waitlist')
    .where('houseId', '==', houseId)
    .where('status', '==', 'joined')
    .get();

  for (const doc of waitlistSnap.docs) {
    const entry = doc.data();
    const title = house.status === HOUSE_STATUS.ACTIVE
      ? 'Ваш дом активирован'
      : 'Статус подключения дома';
    const body = house.status === HOUSE_STATUS.ACTIVE
      ? 'Дом активирован. Теперь можно оформлять уборку.'
      : `До запуска осталось ${remaining} квартир. Сейчас ${house.current_users} из ${house.threshold}.`;
    await sendPushToUser(entry.userId, title, body, {
      type: 'house_progress',
      houseId
    });
  }

  return {ok: true, remaining};
}

async function joinWaitlistInternal(userId, houseId, source = 'app') {
  const houseRef = db.collection('houses').doc(houseId);
  const waitlistRef = db.collection('house_waitlist').doc(houseWaitlistId(userId, houseId));
  let houseStatus = HOUSE_STATUS.INACTIVE;

  await db.runTransaction(async (tx) => {
    const [houseSnap, waitlistSnap, customerSnap] = await Promise.all([
      tx.get(houseRef),
      tx.get(waitlistRef),
      tx.get(db.collection('customers').doc(userId))
    ]);

    if (!houseSnap.exists) {
      throw new HttpsError('not-found', 'House not found');
    }

    const house = houseSnap.data();
    houseStatus = house.status || HOUSE_STATUS.INACTIVE;
    if (waitlistSnap.exists) {
      return;
    }

    const current = Number(house.waitlistCount || 0) + 1;
    const threshold = Number(house.threshold || 20);
    const nextStatus =
      current >= threshold ? HOUSE_STATUS.ACTIVE :
      current > 0 ? HOUSE_STATUS.IN_PROGRESS :
      HOUSE_STATUS.INACTIVE;

    tx.set(waitlistRef, {
      houseId,
      userId,
      source,
      status: 'joined',
      createdAt: admin.firestore.FieldValue.serverTimestamp()
    });

    tx.set(houseRef, {
      waitlistCount: current,
      current_users: current,
      status: nextStatus,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});

    tx.set(customerSnap.ref, {
      houseId,
      houseStatus: nextStatus
    }, {merge: true});

    houseStatus = nextStatus;
  });

  await notifyHouseProgressInternal(houseId, {reason: 'neighbor_joined'});
  return {ok: true, status: houseStatus};
}

async function inviteNeighborsInternal(userId, houseId, invitedPhone = null) {
  const ref = db.collection('referrals').doc();
  await ref.set({
    user_id: userId,
    house_id: houseId,
    invited_user_id: null,
    invited_phone: invitedPhone,
    status: 'sent',
    bonusStatus: 'pending',
    createdAt: admin.firestore.FieldValue.serverTimestamp()
  });
  await recalculateReferralStatsInternal(userId);
  return {ok: true, referralId: ref.id};
}

async function resolveCanonicalChatOrderId(orderId) {
  const normalizedOrderId = String(orderId || '').trim();
  if (!normalizedOrderId) {
    throw new HttpsError('invalid-argument', 'orderId required');
  }

  const customerOrderSnap = await db.collection('customer_orders').doc(normalizedOrderId).get();
  if (customerOrderSnap.exists) {
    return normalizedOrderId;
  }

  const cleanerOrderSnap = await db.collection('cleaner_orders').doc(normalizedOrderId).get();
  if (cleanerOrderSnap.exists) {
    const cleanerOrder = cleanerOrderSnap.data() || {};
    const linkedOrderId = String(cleanerOrder.customerOrderId || cleanerOrder.sourceOrderId || '').trim();
    if (linkedOrderId) {
      return linkedOrderId;
    }
  }

  const slotSnap = await db.collection('schedule_slots').doc(normalizedOrderId).get();
  if (slotSnap.exists) {
    const slot = slotSnap.data() || {};
    const linkedOrderId = String(slot.sourceOrderId || slot.customerOrderId || slot.orderId || '').trim();
    if (linkedOrderId) {
      return linkedOrderId;
    }
  }

  throw new HttpsError('not-found', 'Order not found');
}

function sanitizeChatIdPart(value) {
  return String(value || '').trim().replace(/[^A-Za-z0-9_-]/g, '_');
}

function assignmentChatId(scopeType, scopeId, cleanerId) {
  const prefix = scopeType === 'schedule_slot' ? 'slot' : 'order';
  return `${prefix}_${sanitizeChatIdPart(scopeId)}_${sanitizeChatIdPart(cleanerId)}`;
}

async function resolveOrderDisplayForSource(sourceOrderId) {
  const normalized = String(sourceOrderId || '').trim();
  if (!normalized) {
    return {orderNumber: null, displayOrderId: null};
  }
  const orderSnap = await db.collection('customer_orders').doc(normalized).get();
  if (!orderSnap.exists) {
    return {orderNumber: null, displayOrderId: orderDisplayIdFromNumber(normalized)};
  }
  const order = orderSnap.data() || {};
  return {
    orderNumber: order.orderNumber || normalizeOrderNumber(normalized) || null,
    displayOrderId:
      order.displayOrderId ||
      orderDisplayIdFromNumber(order.orderNumber) ||
      orderDisplayIdFromNumber(normalized) ||
      null
  };
}

function normalizedChatName(value) {
  const raw = String(value || '').trim();
  return raw || null;
}

function chatPeerNameForUser(userId, contextOrChat) {
  const currentUserId = String(userId || '').trim();
  const customerId = String(contextOrChat.customerId || contextOrChat.clientId || '').trim();
  const cleanerId = String(contextOrChat.cleanerId || '').trim();
  const customerName = normalizedChatName(contextOrChat.customerName || contextOrChat.clientName || contextOrChat.client);
  const cleanerName = normalizedChatName(contextOrChat.cleanerName || contextOrChat.cleaner);
  if (currentUserId && currentUserId === customerId) {
    return cleanerName || 'Уборщица';
  }
  if (currentUserId && currentUserId === cleanerId) {
    return customerName || 'Клиент';
  }
  return cleanerName || customerName || 'Участник';
}

function chatUserHasAccess(chat, userId, auth) {
  const normalizedUserId = String(userId || '').trim();
  if (!normalizedUserId) {
    return false;
  }
  if (isBackofficeAuth(auth)) {
    return true;
  }
  const participants = Array.isArray(chat.participants) ? chat.participants.map((item) => String(item || '').trim()) : [];
  return participants.includes(normalizedUserId) ||
    String(chat.customerId || '').trim() === normalizedUserId ||
    String(chat.clientId || '').trim() === normalizedUserId ||
    String(chat.cleanerId || '').trim() === normalizedUserId;
}

function chatParticipantsFromContext(context, chat = {}) {
  return [...new Set([
    context.customerId,
    context.cleanerId,
    chat.customerId,
    chat.clientId,
    chat.cleanerId,
    ...(Array.isArray(chat.participants) ? chat.participants : [])
  ].map((item) => String(item || '').trim()).filter(Boolean))];
}

async function buildExistingChatContext(chatSnap) {
  const chat = chatSnap.data() || {};
  const chatId = chatSnap.id;
  const scopeType = chat.scopeType || 'order';
  const scopeId = String(chat.scopeId || chat.orderId || chat.targetOrderId || chatId).trim();
  const sourceOrderId = String(chat.sourceOrderId || chat.targetOrderId || chat.orderId || '').trim();
  let customerId = String(chat.clientId || chat.customerId || '').trim() || null;
  let cleanerId = String(chat.cleanerId || '').trim() || null;
  let orderNumber = chat.orderNumber || null;
  let displayOrderId = chat.displayOrderId || null;
  let customerName = normalizedChatName(chat.customerName || chat.clientName || chat.client);
  let cleanerName = normalizedChatName(chat.cleanerName || chat.cleaner);
  let linkedData = null;

  if (scopeType === 'schedule_slot' && scopeId) {
    const slotSnap = await db.collection('schedule_slots').doc(scopeId).get();
    if (slotSnap.exists) {
      const slot = slotSnap.data() || {};
      linkedData = {id: slotSnap.id, ...slot};
      customerId = String(slot.customerId || customerId || '').trim() || null;
      cleanerId = String(slot.cleanerId || cleanerId || '').trim() || null;
      customerName = normalizedChatName(slot.customerName || slot.client || customerName);
      cleanerName = normalizedChatName(slot.cleanerName || cleanerName);
      orderNumber = slot.orderNumber || orderNumber;
      displayOrderId = slot.displayOrderId || displayOrderId;
      const slotSourceOrderId = String(slot.sourceOrderId || slot.customerOrderId || sourceOrderId || '').trim();
      if ((!orderNumber || !displayOrderId) && slotSourceOrderId) {
        const sourceDisplay = await resolveOrderDisplayForSource(slotSourceOrderId);
        orderNumber = orderNumber || sourceDisplay.orderNumber;
        displayOrderId = displayOrderId || sourceDisplay.displayOrderId;
      }
    }
  }

  if ((!customerId || !cleanerId || !orderNumber || !displayOrderId) && sourceOrderId) {
    const orderSnap = await db.collection('customer_orders').doc(sourceOrderId).get();
    if (orderSnap.exists) {
      const order = orderSnap.data() || {};
      linkedData = linkedData || {id: orderSnap.id, ...order};
      customerId = String(order.customerId || customerId || '').trim() || null;
      cleanerId = String(order.cleanerId || cleanerId || '').trim() || null;
      customerName = normalizedChatName(order.customerName || customerName);
      cleanerName = normalizedChatName(order.cleanerName || order.cleaner || cleanerName);
      orderNumber = order.orderNumber || orderNumber;
      displayOrderId = order.displayOrderId || displayOrderId || orderDisplayIdFromNumber(order.orderNumber);
    }
  }

  return {
    chatId,
    scopeType,
    scopeId,
    sourceOrderId: sourceOrderId || null,
    customerId,
    cleanerId,
    customerName,
    cleanerName,
    orderNumber,
    displayOrderId,
    status: chat.status || 'active',
    data: {id: chatId, ...chat, ...(linkedData || {})},
  };
}

async function resolveChatContext(targetId, options = {}) {
  const normalizedTargetId = String(targetId || '').trim();
  if (!normalizedTargetId) {
    throw new HttpsError('invalid-argument', 'orderId required');
  }

  const chatSnap = await db.collection('order_chats').doc(normalizedTargetId).get();
  if (chatSnap.exists) {
    return buildExistingChatContext(chatSnap);
  }

  const orderSnap = await db.collection('customer_orders').doc(normalizedTargetId).get();
  if (orderSnap.exists) {
    const order = orderSnap.data() || {};
    if (!order.customerId || !order.cleanerId) {
      throw new HttpsError('failed-precondition', 'Chat is available only when cleaner is assigned');
    }
    const chatId = String(order.chatId || '').trim() ||
      assignmentChatId('order', orderSnap.id, order.cleanerId);
    return {
      chatId,
      scopeType: 'order',
      scopeId: orderSnap.id,
      sourceOrderId: orderSnap.id,
      customerId: order.customerId,
      cleanerId: order.cleanerId,
      customerName: normalizedChatName(order.customerName),
      cleanerName: normalizedChatName(order.cleanerName || order.cleaner),
      orderNumber: order.orderNumber || null,
      displayOrderId: order.displayOrderId || orderDisplayIdFromNumber(order.orderNumber) || null,
      status: 'active',
      data: {id: orderSnap.id, ...order},
    };
  }

  const slotSnap = await db.collection('schedule_slots').doc(normalizedTargetId).get();
  if (slotSnap.exists) {
    const slot = slotSnap.data() || {};
    if (!slot.customerId || !slot.cleanerId) {
      throw new HttpsError('failed-precondition', 'Chat is available only when cleaner is assigned');
    }
    const chatId = String(slot.chatId || '').trim() ||
      assignmentChatId('schedule_slot', slotSnap.id, slot.cleanerId);
    const sourceOrderId = String(slot.sourceOrderId || slot.customerOrderId || '').trim() || null;
    const sourceDisplay = await resolveOrderDisplayForSource(sourceOrderId);
    return {
      chatId,
      scopeType: 'schedule_slot',
      scopeId: slotSnap.id,
      sourceOrderId,
      customerId: slot.customerId,
      cleanerId: slot.cleanerId,
      customerName: normalizedChatName(slot.customerName || slot.client),
      cleanerName: normalizedChatName(slot.cleanerName),
      orderNumber: slot.orderNumber || sourceDisplay.orderNumber || null,
      displayOrderId: slot.displayOrderId || sourceDisplay.displayOrderId || null,
      status: 'active',
      data: {id: slotSnap.id, ...slot},
    };
  }

  const cleanerOrderSnap = await db.collection('cleaner_orders').doc(normalizedTargetId).get();
  if (cleanerOrderSnap.exists) {
    const cleanerOrder = cleanerOrderSnap.data() || {};
    const chatId = String(cleanerOrder.chatId || '').trim();
    if (chatId) {
      return resolveChatContext(chatId, options);
    }
    const slotId = String(cleanerOrder.scheduleSlotId || cleanerOrder.slotId || '').trim();
    if (slotId) {
      return resolveChatContext(slotId, options);
    }
    const linkedOrderId = String(cleanerOrder.customerOrderId || cleanerOrder.sourceOrderId || '').trim();
    if (linkedOrderId) {
      return resolveChatContext(linkedOrderId, options);
    }
  }

  throw new HttpsError('not-found', 'Order not found');
}

async function ensureOrderChat(orderId, options = {}) {
  const context = await resolveChatContext(orderId);
  const isComplaintChat = String(context.scopeType || '') === 'complaint';
  if (!context.customerId || (!context.cleanerId && !isComplaintChat)) {
    throw new HttpsError('failed-precondition', 'Chat is available only when customer and cleaner are assigned');
  }
  const chatRef = db.collection('order_chats').doc(context.chatId);
  const chatSnap = await chatRef.get();
  const existingChat = chatSnap.exists ? (chatSnap.data() || {}) : {};
  const existingStatus = chatSnap.exists ? String(chatSnap.data()?.status || '') : '';
  const status = existingStatus === 'closed' && options.status !== 'active'
    ? 'closed'
    : (options.status || existingStatus || 'active');
  const optionParticipants = Array.isArray(options.participants) ? options.participants : [];
  const participants = chatParticipantsFromContext(context, {
    ...existingChat,
    participants: [
      ...(Array.isArray(existingChat.participants) ? existingChat.participants : []),
      ...optionParticipants
    ]
  });
  const baseData = {
    orderId: context.chatId,
    targetOrderId: context.sourceOrderId || context.scopeId,
    sourceOrderId: context.sourceOrderId || null,
    scopeType: context.scopeType,
    scopeId: context.scopeId,
    orderNumber: context.orderNumber || null,
    displayOrderId: context.displayOrderId || null,
    clientId: context.customerId,
    customerId: context.customerId,
    cleanerId: context.cleanerId,
    customerName: context.customerName || null,
    cleanerName: context.cleanerName || null,
    participants,
    status,
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  };

  if (!chatSnap.exists) {
    await chatRef.set({
      ...baseData,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      lastMessage: options.systemText || '',
      lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
      lastMessageSenderId: 'system'
    }, {merge: true});

    if (options.systemText) {
      const messageRef = chatRef.collection('messages').doc();
      await messageRef.set({
        senderId: 'system',
        senderRole: 'system',
        text: options.systemText,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        readBy: [],
        type: 'system'
      });
    }
  } else {
    await chatRef.set(baseData, {merge: true});
  }

  await Promise.all([
    db.collection('chat_summaries').doc(chatSummaryId(context.customerId, context.chatId)).set({
      userId: context.customerId,
      orderId: context.chatId,
      targetOrderId: context.sourceOrderId || context.scopeId,
      scopeType: context.scopeType,
      scopeId: context.scopeId,
      orderNumber: context.orderNumber || null,
      displayOrderId: context.displayOrderId || null,
      customerName: context.customerName || null,
      cleanerName: context.cleanerName || null,
      participantName: isComplaintChat ? 'Администратор' : chatPeerNameForUser(context.customerId, context),
      participantRole: isComplaintChat ? 'admin' : 'cleaner',
      status,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true}),
    context.cleanerId ? db.collection('chat_summaries').doc(chatSummaryId(context.cleanerId, context.chatId)).set({
      userId: context.cleanerId,
      orderId: context.chatId,
      targetOrderId: context.sourceOrderId || context.scopeId,
      scopeType: context.scopeType,
      scopeId: context.scopeId,
      orderNumber: context.orderNumber || null,
      displayOrderId: context.displayOrderId || null,
      customerName: context.customerName || null,
      cleanerName: context.cleanerName || null,
      participantName: chatPeerNameForUser(context.cleanerId, context),
      participantRole: 'customer',
      status,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true}) : Promise.resolve()
  ]);

  return {ok: true, orderId: context.chatId, chatId: context.chatId, scopeType: context.scopeType, scopeId: context.scopeId};
}

async function ensureComplaintChat(complaintId, adminUserId) {
  const normalizedComplaintId = String(complaintId || '').trim();
  if (!normalizedComplaintId) {
    throw new HttpsError('invalid-argument', 'complaintId required');
  }
  const complaintRef = db.collection('complaints').doc(normalizedComplaintId);
  const complaintSnap = await complaintRef.get();
  if (!complaintSnap.exists) {
    throw new HttpsError('not-found', 'Complaint not found');
  }
  const complaint = complaintSnap.data() || {};
  const customerId = String(complaint.customerId || complaint.clientId || '').trim();
  if (!customerId) {
    throw new HttpsError('failed-precondition', 'Complaint has no customer');
  }

  const orderId = String(complaint.orderId || complaint.slotId || '').trim();
  if (orderId) {
    const chat = await ensureOrderChat(orderId, {participants: [adminUserId]});
    await complaintRef.set({chatId: chat.chatId, updatedAt: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
    return chat;
  }

  let customerName = normalizedChatName(complaint.customerName || complaint.clientName);
  if (!customerName) {
    const customerSnap = await db.collection('users').doc(customerId).get();
    const customer = customerSnap.exists ? (customerSnap.data() || {}) : {};
    customerName = normalizedChatName(customer.name || customer.fullName || customer.displayName);
  }

  const chatId = String(complaint.chatId || '').trim() || `complaint_${normalizedComplaintId}`;
  const chatRef = db.collection('order_chats').doc(chatId);
  await chatRef.set({
    orderId: chatId,
    targetOrderId: null,
    sourceOrderId: null,
    scopeType: 'complaint',
    scopeId: normalizedComplaintId,
    complaintId: normalizedComplaintId,
    clientId: customerId,
    customerId,
    cleanerId: null,
    customerName: customerName || null,
    cleanerName: 'Администратор',
    participants: [...new Set([customerId, adminUserId].filter(Boolean))],
    status: 'active',
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    createdAt: admin.firestore.FieldValue.serverTimestamp()
  }, {merge: true});
  const chat = await ensureOrderChat(chatId, {participants: [adminUserId]});
  await complaintRef.set({chatId, updatedAt: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
  return chat;
}

async function sendChatMessageInternal({orderId, senderId, senderRole, text, type = 'text', auth = null}) {
  const ensured = await ensureOrderChat(orderId);
  const context = await resolveChatContext(ensured.chatId || ensured.orderId || orderId);
  const chatRef = db.collection('order_chats').doc(context.chatId);
  const freshChatSnap = await chatRef.get();
  const chat = freshChatSnap.data();
  if (!chatUserHasAccess(chat, senderId, auth)) {
    throw new HttpsError('permission-denied', 'Sender is not a chat participant');
  }
  if (String(chat.status || '') === 'closed') {
    throw new HttpsError('failed-precondition', 'Chat is closed');
  }

  const participants = chatParticipantsFromContext(context, chat);
  const recipientId = participants.find((id) => id !== senderId) || null;
  const messageRef = chatRef.collection('messages').doc();
  const batch = db.batch();
  batch.set(messageRef, {
    senderId,
    senderRole,
    text,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    readBy: [senderId],
    type
  });
  batch.set(chatRef, {
    lastMessage: text,
    lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
    lastMessageSenderId: senderId,
    customerName: context.customerName || chat.customerName || null,
    cleanerName: context.cleanerName || chat.cleanerName || null,
    participants,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    status: 'active'
  }, {merge: true});

  for (const participant of participants) {
    const chatIdentity = {
      customerId: context.customerId || chat.customerId || chat.clientId,
      clientId: context.customerId || chat.customerId || chat.clientId,
      cleanerId: context.cleanerId || chat.cleanerId,
      customerName: context.customerName || chat.customerName || chat.clientName || chat.client,
      cleanerName: context.cleanerName || chat.cleanerName || chat.cleaner
    };
    batch.set(db.collection('chat_summaries').doc(chatSummaryId(participant, context.chatId)), {
      userId: participant,
      orderId: context.chatId,
      targetOrderId: chat.targetOrderId || chat.sourceOrderId || chat.scopeId || null,
      scopeType: chat.scopeType || context.scopeType,
      scopeId: chat.scopeId || context.scopeId,
      orderNumber: context.orderNumber || chat.orderNumber || null,
      displayOrderId: context.displayOrderId || chat.displayOrderId || null,
      customerName: chatIdentity.customerName || null,
      cleanerName: chatIdentity.cleanerName || null,
      participantName: chatPeerNameForUser(participant, chatIdentity),
      participantRole: String(participant || '') === String(chatIdentity.cleanerId || '') ? 'customer' : 'cleaner',
      lastMessage: text,
      lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
      status: 'active',
      unreadCount: participant === senderId ? 0 : admin.firestore.FieldValue.increment(1),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});
  }
  await batch.commit();

  if (recipientId) {
    await sendPushToUser(recipientId, 'Новое сообщение по заказу', text, {
      type: 'chat_message',
      orderId: context.chatId,
      chatId: context.chatId,
      targetOrderId: chat.targetOrderId || chat.sourceOrderId || chat.scopeId || null,
      scopeType: chat.scopeType || context.scopeType,
      scopeId: chat.scopeId || context.scopeId
    });
  }

  return {ok: true, messageId: messageRef.id, orderId: context.chatId, chatId: context.chatId};
}

async function markChatAsReadInternal({orderId, userId}) {
  const ensured = await ensureOrderChat(orderId);
  const context = await resolveChatContext(ensured.chatId || ensured.orderId || orderId);
  const chatRef = db.collection('order_chats').doc(context.chatId);
  const chatSnap = await chatRef.get();
  if (!chatSnap.exists) {
    throw new HttpsError('not-found', 'Chat not found');
  }
  const chat = chatSnap.data();
  if (!chatUserHasAccess(chat, userId, null)) {
    throw new HttpsError('permission-denied', 'No access to chat');
  }
  const participants = chatParticipantsFromContext(context, chat);
  if (participants.length) {
    await chatRef.set({participants}, {merge: true});
  }

  const unreadSnap = await chatRef.collection('messages')
    .where('senderId', '!=', userId)
    .get();
  if (!unreadSnap.empty) {
    const batch = db.batch();
    for (const doc of unreadSnap.docs) {
      batch.set(doc.ref, {
        readBy: admin.firestore.FieldValue.arrayUnion(userId)
      }, {merge: true});
    }
    batch.set(db.collection('chat_summaries').doc(chatSummaryId(userId, context.chatId)), {
      unreadCount: 0,
      lastSeenAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});
    await batch.commit();
  } else {
    await db.collection('chat_summaries').doc(chatSummaryId(userId, context.chatId)).set({
      unreadCount: 0,
      lastSeenAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});
  }

  return {ok: true, orderId: context.chatId, chatId: context.chatId};
}

async function getChatMessagesInternal({orderId, userId, auth}) {
  const ensured = await ensureOrderChat(orderId);
  const context = await resolveChatContext(ensured.chatId || ensured.orderId || orderId);
  const chatRef = db.collection('order_chats').doc(context.chatId);
  const chatSnap = await chatRef.get();
  if (!chatSnap.exists) {
    throw new HttpsError('not-found', 'Chat not found');
  }
  const chat = chatSnap.data() || {};
  const participants = chatParticipantsFromContext(context, chat);
  if (!chatUserHasAccess(chat, userId, auth)) {
    throw new HttpsError('permission-denied', 'No access to chat');
  }
  if (participants.length) {
    await chatRef.set({participants}, {merge: true});
  }
  const snap = await chatRef.collection('messages')
    .orderBy('createdAt')
    .limit(300)
    .get();
  return {
    ok: true,
    orderId: context.chatId,
    chatId: context.chatId,
    items: snap.docs.map((doc) => {
      const data = doc.data() || {};
      return {
        id: doc.id,
        ...data,
        createdAtMillis: timestampMillis(data.createdAt)
      };
    })
  };
}

async function closeOrderChat(chatOrTargetId, reasonText = 'Чат закрыт') {
  let context;
  try {
    context = await resolveChatContext(chatOrTargetId);
  } catch (error) {
    if (error instanceof HttpsError && error.code === 'not-found') {
      return;
    }
    throw error;
  }
  const chatRef = db.collection('order_chats').doc(context.chatId);
  const chatSnap = await chatRef.get();
  if (!chatSnap.exists) {
    return;
  }
  const chat = chatSnap.data() || {};
  const participants = Array.isArray(chat.participants) ? chat.participants : [];
  const batch = db.batch();
  const messageRef = chatRef.collection('messages').doc();
  batch.set(messageRef, {
    senderId: 'system',
    senderRole: 'system',
    text: reasonText,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    readBy: [],
    type: 'system'
  });
  batch.set(chatRef, {
    lastMessage: reasonText,
    lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
    lastMessageSenderId: 'system',
    status: 'closed',
    closedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, {merge: true});
  for (const participant of participants) {
    const chatIdentity = {
      customerId: context.customerId || chat.customerId || chat.clientId,
      clientId: context.customerId || chat.customerId || chat.clientId,
      cleanerId: context.cleanerId || chat.cleanerId,
      customerName: context.customerName || chat.customerName || chat.clientName || chat.client,
      cleanerName: context.cleanerName || chat.cleanerName || chat.cleaner
    };
    batch.set(db.collection('chat_summaries').doc(chatSummaryId(participant, context.chatId)), {
      userId: participant,
      orderId: context.chatId,
      orderNumber: context.orderNumber || chat.orderNumber || null,
      displayOrderId: context.displayOrderId || chat.displayOrderId || null,
      customerName: chatIdentity.customerName || null,
      cleanerName: chatIdentity.cleanerName || null,
      participantName: chatPeerNameForUser(participant, chatIdentity),
      participantRole: String(participant || '') === String(chatIdentity.cleanerId || '') ? 'customer' : 'cleaner',
      lastMessage: reasonText,
      lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
      status: 'closed',
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});
  }
  await batch.commit();
}

async function submitCleanerVerificationInternal({cleanerId, payload}) {
  const requiredFields = [
    'selfieUrl',
    'selfieWithIdUrl',
    'idDocumentUrl',
    'policeClearanceUrl',
    'psychDispenserUrl',
    'phthisiatricianUrl',
    'residenceProofUrl'
  ];
  for (const field of requiredFields) {
    if (!payload[field]) {
      throw new HttpsError('invalid-argument', `${field} is required`);
    }
  }

  const documentEntries = [
    {type: 'selfie', fileUrl: payload.selfieUrl || null},
    {type: 'selfie_with_id', fileUrl: payload.selfieWithIdUrl || null},
    {type: 'id_document', fileUrl: payload.idDocumentUrl || null},
    {type: 'police_clearance', fileUrl: payload.policeClearanceUrl || null},
    {type: 'psych_dispenser', fileUrl: payload.psychDispenserUrl || null},
    {type: 'phthisiatrician', fileUrl: payload.phthisiatricianUrl || null},
    {type: 'residence_proof', fileUrl: payload.residenceProofUrl || null}
  ].filter((item) => item.fileUrl);

  const verificationPayload = {
    cleanerId,
    ...payload,
    expiresAt: payload.expiresAt || null,
    status: 'pending',
    rejectionReason: null,
    submittedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  };
  await Promise.all([
    db.collection('cleaner_verification').doc(cleanerId).set(verificationPayload, {merge: true}),
    db.collection('cleaner_verifications').doc(cleanerId).set(verificationPayload, {merge: true})
  ]);

  const batch = db.batch();
  for (const entry of documentEntries) {
    batch.set(
      db.collection('cleaner_documents').doc(`${cleanerId}_${entry.type}`),
      {
        cleanerId,
        type: entry.type,
        fileUrl: entry.fileUrl,
        uploadedAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAt: payload.expiresAt || null,
        status: 'pending',
        verifiedBy: null
      },
      {merge: true}
    );
  }
  await batch.commit();

  await db.collection('cleaners').doc(cleanerId).set({
    verificationStatus: 'pending',
    expiresAt: payload.expiresAt || null,
    documentExpiresAt: payload.expiresAt || null,
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, {merge: true});

  return {ok: true};
}

async function getAddonBonusSpendPercent() {
  try {
    const promotionsSnap = await db.collection('promotions')
      .where('isActive', '==', true)
      .get();
    let percent = 50;
    promotionsSnap.docs.forEach((doc) => {
      const promotion = doc.data() || {};
      const target = String(promotion.rewardTarget || 'addons');
      if (target !== 'addons' && target !== 'all') {
        return;
      }
      const value = Math.max(Number(promotion.maxSpendPercent || 50), 0);
      if (value > percent) {
        percent = value;
      }
    });
    return Math.min(percent, 100);
  } catch (error) {
    console.warn('Failed to load addon bonus spend policy', error);
    return 50;
  }
}

async function requestServiceAddressInternal(userId, payload) {
  const normalizedAddress = normalizeProfileText(
    payload.address || payload.residentialComplex,
    240
  );
  const normalizedResidential = normalizeProfileText(
    payload.residentialComplex || normalizedAddress,
    200
  );
  const city = normalizeProfileText(payload.city, 120);
  const normalizedCity = normalizeCityName(city);
  const lat = Number(payload.lat);
  const lng = Number(payload.lng);
  const area = normalizeProfileArea(payload.area || 1);

  if (!normalizedAddress) {
    throw new HttpsError('invalid-argument', 'address required');
  }
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
    throw new HttpsError('invalid-argument', 'lat/lng required');
  }

  const existingHouse = await resolveExistingHouseForAddress({
    address: normalizedAddress,
    residentialComplex: normalizedResidential,
    city: city || normalizedCity,
    lat,
    lng
  });
  const hash = crypto
    .createHash('sha1')
    .update(`${normalizedCity}|${normalizedAddress}`.toLowerCase())
    .digest('hex')
    .slice(0, 16);
  const houseId = existingHouse?.id ||
    `requested_${slugifyAddressPart(normalizedCity || city, 'kz')}_${hash}`;
  const waitlistId = houseWaitlistId(userId, houseId);
  const policies = await getPolicyConfig();
  let nextStatus = HOUSE_STATUS.IN_PROGRESS;
  let responseAddress = normalizedAddress;
  let responseResidential = normalizedResidential;

  await db.runTransaction(async (tx) => {
    const houseRef = db.collection('houses').doc(houseId);
    const waitlistRef = db.collection('house_waitlist').doc(waitlistId);
    const customerRef = db.collection('customers').doc(userId);
    const [houseSnap, waitlistSnap] = await Promise.all([
      tx.get(houseRef),
      tx.get(waitlistRef)
    ]);

    const previous = houseSnap.exists ? houseSnap.data() || {} : {};
    const alreadyJoined = waitlistSnap.exists;
    const threshold = Number(previous.threshold || policies.defaultHouseThreshold || 20);
    const currentUsers = Number(previous.current_users || previous.waitlistCount || 0) +
      (alreadyJoined ? 0 : 1);
    nextStatus = previous.status === HOUSE_STATUS.ACTIVE || currentUsers >= threshold
      ? HOUSE_STATUS.ACTIVE
      : HOUSE_STATUS.IN_PROGRESS;
    responseAddress = previous.address || normalizedAddress;
    responseResidential = previous.residentialComplex || previous.title || normalizedResidential;

    tx.set(houseRef, {
      title: previous.title || normalizedResidential,
      residentialComplex: previous.residentialComplex || normalizedResidential,
      address: previous.address || normalizedAddress,
      addressPlaceId: previous.addressPlaceId || normalizeProfileText(payload.addressPlaceId, 180),
      city: previous.city || city || normalizedCity,
      cityNormalized: previous.cityNormalized || normalizedCity,
      lat: Number.isFinite(Number(previous.lat)) ? Number(previous.lat) : lat,
      lng: Number.isFinite(Number(previous.lng)) ? Number(previous.lng) : lng,
      status: nextStatus,
      threshold,
      current_users: currentUsers,
      waitlistCount: currentUsers,
      source: previous.source || 'customer_request',
      requestedBy: previous.requestedBy || userId,
      requestedAt: previous.requestedAt || admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});

    tx.set(waitlistRef, {
      houseId,
      userId,
      status: 'joined',
      source: 'address_request',
      residentialComplex: normalizedResidential,
      address: normalizedAddress,
      addressPlaceId: normalizeProfileText(payload.addressPlaceId, 180),
      city: city || normalizedCity,
      cityNormalized: normalizedCity,
      entrance: normalizeProfileText(payload.entrance, 80),
      apartment: normalizeProfileText(payload.apartment, 80),
      area,
      lat,
      lng,
      createdAt: alreadyJoined
        ? waitlistSnap.data()?.createdAt || admin.firestore.FieldValue.serverTimestamp()
        : admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});

    tx.set(customerRef, {
      address: normalizedAddress,
      residentialComplex: normalizedResidential,
      addressPlaceId: normalizeProfileText(payload.addressPlaceId, 180),
      addressLat: lat,
      addressLng: lng,
      city: city || normalizedCity,
      cityNormalized: normalizedCity,
      entrance: normalizeProfileText(payload.entrance, 80),
      apartment: normalizeProfileText(payload.apartment, 80),
      area,
      houseId,
      houseStatus: nextStatus,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});
  });

  await notifyHouseProgressInternal(houseId, {reason: 'neighbor_joined'});
  return {
    ok: true,
    houseId,
    status: nextStatus,
    address: responseAddress,
    residentialComplex: responseResidential,
    city: city || normalizedCity,
    lat,
    lng
  };
}

async function reviewCleanerVerificationInternal({cleanerId, status, reviewedBy, rejectionReason = null}) {
  const allowed = ['approved', 'rejected'];
  if (!allowed.includes(status)) {
    throw new HttpsError('invalid-argument', 'Invalid verification status');
  }

  await db.collection('cleaner_verification').doc(cleanerId).set({
    status,
    rejectionReason: status === 'rejected' ? rejectionReason || 'Требуется корректировка документов' : null,
    reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
    reviewedBy,
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, {merge: true});

  await db.collection('cleaners').doc(cleanerId).set({
    verificationStatus: status
  }, {merge: true});

  const docsSnap = await db.collection('cleaner_documents')
    .where('cleanerId', '==', cleanerId)
    .get();
  if (!docsSnap.empty) {
    const batch = db.batch();
    for (const doc of docsSnap.docs) {
      batch.set(doc.ref, {
        status,
        verifiedBy: reviewedBy,
        reviewedAt: admin.firestore.FieldValue.serverTimestamp()
      }, {merge: true});
    }
    await batch.commit();
  }

  await sendPushToUser(
    cleanerId,
    'Статус верификации обновлен',
    status === 'approved'
      ? 'Верификация подтверждена. Вы можете принимать заказы.'
      : 'Верификация отклонена. Исправьте документы и отправьте повторно.',
    {type: 'verification_status'}
  );

  return {ok: true};
}

async function cancelScheduleSlotInternal({slotId, uid, adminMode = false}) {
  const slotRef = db.collection('schedule_slots').doc(slotId);
  let subscriptionId = null;
  let freeCancellation = true;
  let orderId = null;
  let assignedCleanerId = null;
  let customerId = null;
  let canceledScheduledAt = null;
  let canceledSlotDetails = '';

  await db.runTransaction(async (tx) => {
    const slotSnap = await tx.get(slotRef);
    if (!slotSnap.exists) {
      throw new HttpsError('not-found', 'Slot not found');
    }

    const slot = slotSnap.data();
    if (!adminMode && slot.customerId !== uid) {
      throw new HttpsError('permission-denied', 'No access to this slot');
    }
    if (!activeSlotStatus(slot.status)) {
      throw new HttpsError('failed-precondition', 'This cleaning cannot be canceled');
    }
    if (!adminMode && String(slot.status || '').trim().toLowerCase() === 'in_progress') {
      throw new HttpsError('failed-precondition', 'Cleaning already started and cannot be canceled by customer');
    }
    const sourceOrderId = slot.sourceOrderId || slot.customerOrderId || null;

    const scheduledAt = slotScheduledAt(slot);
    canceledScheduledAt = scheduledAt;
    const hoursUntil = (scheduledAt.getTime() - Date.now()) / 3600000;
    freeCancellation = adminMode ? hoursUntil >= FREE_CANCELLATION_HOURS : true;
    subscriptionId = slot.subscriptionId || null;
    orderId = sourceOrderId;
    assignedCleanerId = slot.cleanerId || slot.assignedCleanerId || null;
    customerId = slot.customerId || uid || null;
    canceledSlotDetails = `${String(slot.scheduledDateKey || '')} ${String(slot.time || '')}`.trim();

    tx.set(slotRef, {
      status: 'canceled',
      orderStatus: 'canceled',
      assignmentStatus: 'canceled',
      ...clearAddonPayload(),
      cleanerId: null,
      cleanerName: null,
      cleanerPhone: null,
      currentOfferCleanerId: null,
      currentOfferId: null,
      offerExpiresAt: null,
      canceledAt: admin.firestore.FieldValue.serverTimestamp(),
      canceledBy: uid || 'admin',
      cancellationPolicyHours: FREE_CANCELLATION_HOURS,
      cancellationPenaltyApplied: !freeCancellation
    }, {merge: true});

    tx.set(db.collection('cleaner_orders').doc(String(slotId)), {
      status: 'canceled',
      orderStatus: 'canceled',
      ...clearAddonPayload(),
      canceledAt: admin.firestore.FieldValue.serverTimestamp(),
      canceledBy: uid || 'admin',
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});

    tx.set(db.collection('cleaner_shifts').doc(String(slotId)), {
      status: 'canceled',
      canceledAt: admin.firestore.FieldValue.serverTimestamp(),
      canceledBy: uid || 'admin',
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});
  });

  await cancelPendingOffersForScope('schedule_slot', String(slotId), 'cancelled')
    .catch((error) => console.error('Failed to cancel pending slot offers after customer cancellation', error));

  if (subscriptionId) {
    await refreshSubscriptionUsage(subscriptionId);
  }

  if (assignedCleanerId) {
    await recalculateCleanerDailyScheduleInternal(assignedCleanerId, canceledScheduledAt || new Date())
      .catch((error) => console.error('Failed to recalculate cleaner schedule after customer cancellation', error));
  }

  if (orderId) {
    await db.collection('customer_orders').doc(orderId).set({
      lastCanceledSlotId: String(slotId),
      lastCanceledSlotDetails: canceledSlotDetails || null,
      lastCanceledSlotAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});
    await db.collection('debug_bridge_orders').doc(String(slotId)).set({
      status: 'canceled',
      orderStatus: 'canceled',
      assignmentStatus: 'canceled',
      sourceOrderId: orderId,
      canceledAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true}).catch(() => {});
  }

  let refundedBonusAmount = 0;
  if (customerId) {
    refundedBonusAmount = await refundBonusForCanceledSlotInternal({
      slotId,
      customerId,
      orderId,
      reason: adminMode ? 'admin_cancelled_schedule_slot' : 'customer_cancelled_schedule_slot'
    }).catch((error) => {
      console.error('Failed to refund slot bonus after cancellation', {slotId, customerId, error});
      return 0;
    });
  }

  const detailsText = canceledSlotDetails ? ` ${canceledSlotDetails}` : '';
  const bonusRefundText = refundedBonusAmount > 0
    ? ` Бонусы возвращены: ${refundedBonusAmount} ₸.`
    : '';
  if (assignedCleanerId) {
    await sendPushToUser(
      String(assignedCleanerId),
      'Уборка отменена клиентом',
      `Клиент отменил уборку${detailsText}. Заказ снят с расписания.`,
      {
        type: 'schedule_slot_canceled',
        orderId: String(orderId || slotId),
        slotId: String(slotId),
        route: '/cleaner/orders'
      }
    );
  }
  if (customerId) {
    await sendPushToUser(
      String(customerId),
      'Уборка отменена',
      freeCancellation
        ? `Вы отменили уборку${detailsText}. Визит вернулся в доступные уборки пакета.${bonusRefundText}`
        : `Вы отменили уборку${detailsText}. Уборка списана по правилам отмены.${bonusRefundText}`,
      {
        type: 'customer_schedule_slot_canceled',
        orderId: String(orderId || slotId),
        slotId: String(slotId),
        route: '/client/orders'
      }
    );
  }

  return {
    ok: true,
    freeCancellation,
    penaltyApplied: !freeCancellation
  };
}

async function ensureSubscriptionForOrder(orderId) {
  const orderRef = db.collection('customer_orders').doc(orderId);
  const orderSnap = await orderRef.get();
  if (!orderSnap.exists) {
    throw new HttpsError('not-found', 'Order not found');
  }

  const order = {id: orderSnap.id, ...orderSnap.data()};
  const policies = await getPolicyConfig();
  const frequency = parseFrequencyConfig(order.frequencyLabel, order.package);
  const subscriptionId = order.subscriptionId || orderId;
  const subscriptionRef = db.collection('subscriptions').doc(subscriptionId);
  const subscriptionSnap = await subscriptionRef.get();
  const validFrom = startOfDay(new Date());
  const billingPeriodMonths = Number(
    order.billingPeriodMonths || frequency.billingPeriodMonths || SUBSCRIPTION_TERM_MONTHS
  );
  const validUntil = startOfDay(addMonths(validFrom, billingPeriodMonths));
  const includedVisits = subscriptionIncludedVisits({
    ...order,
    billingPeriodMonths
  });
  const subscriptionAddonsDetailed = normalizeDetailedAddons(order.addonsDetailed);
  const subscriptionAddons = Array.isArray(order.addons)
    ? order.addons
    : subscriptionAddonsDetailed.map((item) => item.label || item.key).filter(Boolean);
  const subscriptionSeparatePaymentAddons = Array.isArray(order.separatePaymentAddons)
    ? order.separatePaymentAddons
    : [];

  if (!subscriptionSnap.exists) {
    await subscriptionRef.set({
      customerId: order.customerId,
      sourceOrderId: orderId,
      packageId: order.packageId || null,
      package: order.package || null,
      frequencyLabel: order.frequencyLabel || null,
      billingPeriodMonths,
      accessMethod: order.accessMethod || null,
      addons: subscriptionAddons,
      addonsDetailed: subscriptionAddonsDetailed,
      separatePaymentAddons: subscriptionSeparatePaymentAddons,
      addonCount: Number(order.addonCount || subscriptionAddonsDetailed.length || 0),
      addonTotalPrice: Number(order.addonTotalPrice || 0),
      addonsSeparatePaymentTotal: Number(order.addonsSeparatePaymentTotal || 0),
      houseId: order.houseId || null,
      houseStatus: order.houseStatus || null,
      serviceArea: order.serviceArea || null,
      serviceAreaId: order.serviceAreaId || null,
      zoneId: order.zoneId || null,
      clusterName: order.clusterName || null,
      residentialComplex: order.residentialComplex || null,
      entrance: order.entrance || null,
      apartment: order.apartment || null,
      address: order.address || null,
      area: order.area || null,
      status: 'active',
      scheduleSelectionRequired: true,
      autoRenew: frequency.kind === 'one_time' ? false : true,
      includedVisits,
      usedVisits: 0,
      remainingVisits: includedVisits,
      scheduledVisits: 0,
      selectedVisitsCount: 0,
      estimatedDurationHours: estimateCleaningDuration(order.area || 0, policies),
      estimatedDurationMinutes: estimateCleaningDurationMinutes(order.area || 0, policies),
      validFrom: admin.firestore.Timestamp.fromDate(validFrom),
      validUntil: admin.firestore.Timestamp.fromDate(validUntil),
      renewalAt: admin.firestore.Timestamp.fromDate(validUntil),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});
  } else {
    await subscriptionRef.set({
      includedVisits,
      remainingVisits: Math.max(
        includedVisits - Number(subscriptionSnap.data()?.usedVisits || 0),
        0
      ),
      billingPeriodMonths,
      validUntil: admin.firestore.Timestamp.fromDate(validUntil),
      renewalAt: admin.firestore.Timestamp.fromDate(validUntil),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});
  }

  await orderRef.set({
    subscriptionId,
    subscriptionStatus: 'active',
    validUntil: admin.firestore.Timestamp.fromDate(validUntil)
  }, {merge: true});

  return subscriptionId;
}

async function getEpayToken(mode = 'invoice') {
  const creds = getEpayCredentials(mode);
  if (!creds.clientId || !creds.clientSecret) {
    throw new HttpsError(
      'failed-precondition',
      `${mode} ePay credentials are not configured`
    );
  }

  const body = new URLSearchParams({
    grant_type: 'client_credentials',
    scope: 'payment',
    client_id: creds.clientId,
    client_secret: creds.clientSecret
  });

  const response = await fetch(EPAY_TOKEN_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded'
    },
    body
  });

  if (!response.ok) {
    const text = await response.text();
    throw new HttpsError('internal', `ePay token error: ${response.status} ${text}`);
  }

  const data = await response.json();
  return data.access_token;
}

async function epayCreateInvoice({orderId, amount, customerId}) {
  if (!EPAY_SHOP_ID) {
    throw new HttpsError('failed-precondition', 'EPAY_SHOP_ID is not configured');
  }
  const token = await getEpayToken('invoice');

  const checksum = Array.from(orderId).reduce(
    (acc, char, index) => acc + char.charCodeAt(0) * (index + 1),
    0
  );
  const invoiceExternalId = `${Date.now()}${checksum}`.slice(0, 20);

  const payload = {
    amount,
    invoice_id: invoiceExternalId,
    language: 'rus',
    currency: 'KZT',
    description: `Domly order ${orderId}`,
    account_id: customerId,
    expire_period: '3d'
  };
  payload.shop_id = EPAY_SHOP_ID;
  if (EPAY_TERMINAL_ID) {
    payload.terminal_id = EPAY_TERMINAL_ID;
  }

  const response = await fetch(EPAY_INVOICE_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`
    },
    body: JSON.stringify(payload)
  });

  if (!response.ok) {
    const text = await response.text();
    throw new HttpsError('internal', `ePay invoice error: ${response.status} ${text}`);
  }

  return response.json();
}

function bccTimestamp() {
  const now = new Date();
  const pad = (value) => String(value).padStart(2, '0');
  return `${now.getUTCFullYear()}${pad(now.getUTCMonth() + 1)}${pad(now.getUTCDate())}${pad(now.getUTCHours())}${pad(now.getUTCMinutes())}${pad(now.getUTCSeconds())}`;
}

function bccNonce(length = 32) {
  return crypto.randomBytes(Math.ceil(length / 2)).toString('hex').toUpperCase().slice(0, length);
}

function bccMInfo({customerPhone, address}) {
  const digits = String(customerPhone || '').replace(/\D/g, '');
  const subscriber = digits.startsWith('7') ? digits.slice(1) : digits;
  return Buffer.from(JSON.stringify({
    browserScreenHeight: '1920',
    browserScreenWidth: '1080',
    mobilePhone: {
      cc: '7',
      subscriber: subscriber || '7000000000'
    },
    billAddrLine1: String(address || 'Kazakhstan').slice(0, 50)
  })).toString('base64');
}

function bccMacPart(value) {
  const raw = value === undefined || value === null ? '' : String(value);
  return `${raw.length}${raw}`;
}

function bccSignPurchase(fields) {
  const macData = [
    fields.AMOUNT,
    fields.CURRENCY,
    fields.ORDER,
    fields.MERCHANT,
    fields.TERMINAL,
    fields.MERCH_GMT,
    fields.TIMESTAMP,
    fields.TRTYPE,
    fields.NONCE
  ].map(bccMacPart).join('');
  return crypto
    .createHmac('sha1', Buffer.from(BCC_ECOMMERCE_MAC_KEY, 'hex'))
    .update(macData, 'utf8')
    .digest('hex')
    .toUpperCase();
}

function escapeHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function buildBccAutoSubmitHtml({actionUrl, fields}) {
  const inputs = Object.entries(fields)
    .map(([key, value]) =>
      `<input type="hidden" name="${escapeHtml(key)}" value="${escapeHtml(value)}">`
    )
    .join('\n');
  return `<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>DOMLY payment</title>
  <style>
    body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;background:#f6fbf7;font-family:Arial,sans-serif;color:#263f34}
    .box{text-align:center;padding:24px}
    .spinner{width:32px;height:32px;border:4px solid #e2eee8;border-top-color:#cf6f4e;border-radius:50%;animation:spin 1s linear infinite;margin:0 auto 16px}
    @keyframes spin{to{transform:rotate(360deg)}}
  </style>
</head>
<body>
  <div class="box"><div class="spinner"></div><div>Открываем оплату...</div></div>
  <form id="payment-form" method="post" action="${escapeHtml(actionUrl)}">
    ${inputs}
  </form>
  <script>document.getElementById('payment-form').submit();</script>
</body>
</html>`;
}

async function createBccPaymentForOrder({orderId, auth, clientIp = '0.0.0.0'}) {
  if (!auth || !orderId) {
    throw new HttpsError('invalid-argument', 'orderId required');
  }
  if (!BCC_ECOMMERCE_TERMINAL || !BCC_ECOMMERCE_MAC_KEY) {
    throw new HttpsError('failed-precondition', 'BCC payment is not configured');
  }

  const normalizedOrderId = String(orderId).trim();
  const paymentRef = db.collection('payments').doc(normalizedOrderId);
  const orderRef = db.collection('customer_orders').doc(normalizedOrderId);
  const paymentSnap = await paymentRef.get();
  const orderSnap = await orderRef.get();
  if (!orderSnap.exists && !paymentSnap.exists) {
    throw new HttpsError('not-found', 'Order/payment not found');
  }
  const payment = paymentSnap.exists ? (paymentSnap.data() || {}) : {};
  const order = orderSnap.exists ? (orderSnap.data() || {}) : {};
  const ownerId = payment.customerId || order.customerId;
  if (ownerId !== auth.uid && !isAdminAuth(auth)) {
    throw new HttpsError('permission-denied', 'Not your payment');
  }
  const orderStatus = String(order.orderStatus || '').toLowerCase();
  const paymentStatus = String(order.paymentStatus || payment.status || '').toLowerCase();
  const canOpenPayment =
    orderStatus === 'pending_payment' ||
    paymentStatus === 'initiated' ||
    paymentStatus === 'pending_invoice' ||
    paymentStatus === 'invoice_requested';
  if (!canOpenPayment) {
    throw new HttpsError('failed-precondition', 'Order is not waiting payment');
  }
  const amount = Math.max(0, Number(payment.amount ?? order.price ?? 0));
  if (!Number.isFinite(amount) || amount <= 0) {
    throw new HttpsError('failed-precondition', 'Payment amount is empty');
  }

  const timestamp = bccTimestamp();
  const nonce = bccNonce();
  const merchRnId = bccNonce(16);
  const orderDigits = normalizedOrderId.replace(/\D/g, '');
  const bccOrderId = (orderDigits || String(Date.now()).slice(-12))
    .slice(0, 32)
    .padStart(6, '0');
  const backref = `${BCC_ECOMMERCE_BACKREF}?orderId=${encodeURIComponent(normalizedOrderId)}`;
  const fields = {
    AMOUNT: String(amount),
    CURRENCY: '398',
    ORDER: bccOrderId,
    MERCH_RN_ID: merchRnId,
    DESC: `DOMLY order ${normalizedOrderId}`,
    MERCHANT: BCC_ECOMMERCE_MERCHANT,
    MERCH_NAME: BCC_ECOMMERCE_MERCH_NAME,
    TERMINAL: BCC_ECOMMERCE_TERMINAL,
    TIMESTAMP: timestamp,
    MERCH_GMT: '0',
    TRTYPE: '1',
    BACKREF: backref,
    LANG: 'ru',
    NONCE: nonce,
    MK_TOKEN: 'MERCH',
    NOTIFY_URL: BCC_ECOMMERCE_NOTIFY_URL,
    CLIENT_IP: clientIp || '0.0.0.0',
    M_INFO: bccMInfo({
      customerPhone: order.customerPhone || payment.customerPhone,
      address: order.address || order.houseAddress || order.customerAddress || payment.address
    })
  };
  fields.P_SIGN = bccSignPurchase(fields);
  const html = buildBccAutoSubmitHtml({
    actionUrl: BCC_ECOMMERCE_URL,
    fields
  });

  await Promise.all([
    paymentRef.set({
      orderId: normalizedOrderId,
      orderNumber: order.orderNumber || payment.orderNumber || null,
      displayOrderId: order.displayOrderId || payment.displayOrderId || null,
      customerId: ownerId,
      customerName: order.customerName || payment.customerName || null,
      customerPhone: order.customerPhone || payment.customerPhone || null,
      packageName: order.package || payment.packageName || null,
      packageId: order.packageId || payment.packageId || null,
      amount,
      currency: 'KZT',
      provider: 'bcc_ecommerce_webview',
      status: 'invoice_requested',
      bccOrderId,
      bccMerchRnId: merchRnId,
      bccTerminal: BCC_ECOMMERCE_TERMINAL,
      invoiceRequestedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true}),
    orderRef.set({
      paymentProvider: 'bcc_ecommerce_webview',
      paymentStatus: 'invoice_requested',
      invoiceRequestedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true})
  ]);

  return {
    ok: true,
    orderId: normalizedOrderId,
    provider: 'bcc_ecommerce_webview',
    paymentHtml: html,
    actionUrl: BCC_ECOMMERCE_URL,
    bccOrderId
  };
}

async function epayCheckInvoice(invoiceId) {
  const token = await getEpayToken('invoice');

  const response = await fetch(EPAY_STATUS_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`
    },
    body: JSON.stringify({
      paging: {skip: 0, limit: 1},
      searchParameters: [
        {
          name: 'invoice_id',
          method: '=',
          searchParameter: [invoiceId]
        }
      ],
      orderParameters: {field: 'id', typeOrder: 'DESC'}
    })
  });

  if (!response.ok) {
    const text = await response.text();
    throw new HttpsError('internal', `ePay status error: ${response.status} ${text}`);
  }

  return response.json();
}

async function epayCreatePayout({cleanerId, amount, weekId}) {
  const token = await getEpayToken('payout');

  const payload = {
    shop_id: EPAY_SHOP_ID || undefined,
    terminal_id: EPAY_PAYOUT_TERMINAL_ID || undefined,
    account_id: cleanerId,
    amount,
    currency: 'KZT',
    payout_id: `${cleanerId}-${weekId}`
  };
  Object.keys(payload).forEach((key) => {
    if (payload[key] === undefined || payload[key] === null || payload[key] === '') {
      delete payload[key];
    }
  });

  const response = await fetch(EPAY_PAYOUT_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`
    },
    body: JSON.stringify(payload)
  });

  if (!response.ok) {
    const text = await response.text();
    throw new HttpsError('internal', `ePay payout error: ${response.status} ${text}`);
  }

  return response.json();
}

function extractInvoiceId(invoice) {
  return invoice?.id || invoice?.invoice_id || null;
}

function extractInvoiceUrl(invoice) {
  return invoice?.invoice_url || invoice?.url || invoice?.link || null;
}

function extractStatusPayload(statusResult) {
  const rows =
    statusResult?.rows ||
    statusResult?.items ||
    statusResult?.content ||
    statusResult?.Records ||
    [];
  if (Array.isArray(rows) && rows.length > 0) {
    return rows[0];
  }
  return statusResult?.result || statusResult || {};
}

function normalizePaymentStatus(statusResult) {
  const payload = extractStatusPayload(statusResult);
  const rc = String(payload.RC || payload.rc || payload.responseCode || '').trim();
  const action = String(payload.ACTION || payload.action || '').trim();
  if (rc === '00' || action === '0') return 'paid';
  if (rc || action) return 'failed';
  const raw = String(
    payload.status ||
    payload.payment_status ||
    payload.state ||
    payload.invoice_status ||
    ''
  ).toLowerCase();

  const successStatuses = ['paid', 'success', 'succeeded', 'completed', 'approved', 'charged'];
  const pendingStatuses = ['created', 'pending', 'processing', 'in_progress', 'new', 'wait'];
  const failStatuses = ['failed', 'declined', 'canceled', 'cancelled', 'expired', 'error'];

  if (successStatuses.some((token) => raw.includes(token))) return 'paid';
  if (failStatuses.some((token) => raw.includes(token))) return 'failed';
  if (pendingStatuses.some((token) => raw.includes(token))) return 'pending';
  return 'unknown';
}

async function applyPaymentStatus(orderId, statusResult, fallbackTransactionId = null) {
  const normalized = normalizePaymentStatus(statusResult);
  const payload = extractStatusPayload(statusResult);
  const transactionId =
    fallbackTransactionId ||
    payload.transaction_id ||
    payload.payment_id ||
    payload.id ||
    null;

  const paymentRef = db.collection('payments').doc(orderId);
  const orderRef = db.collection('customer_orders').doc(orderId);
  let transitionedToPaid = false;
  let transitionedToFailed = false;

  await db.runTransaction(async (tx) => {
    const paymentSnap = await tx.get(paymentRef);
    const orderSnap = await tx.get(orderRef);
    if (!paymentSnap.exists || !orderSnap.exists) {
      throw new HttpsError('not-found', 'Order/payment not found');
    }

    const order = orderSnap.data();
    const previousPaymentStatus = String(
      paymentSnap.data()?.status || order?.paymentStatus || '',
    ).toLowerCase();
    const paymentUpdate = {
      statusSync: statusResult,
      normalizedStatus: normalized,
      syncedAt: admin.firestore.FieldValue.serverTimestamp()
    };
    if (transactionId) {
      paymentUpdate.transactionId = String(transactionId);
    }

    if (normalized === 'paid') {
      transitionedToPaid = previousPaymentStatus !== 'paid';
      paymentUpdate.status = 'paid';
      paymentUpdate.paidAt = admin.firestore.FieldValue.serverTimestamp();
      tx.update(orderRef, {
        paymentStatus: 'paid',
        orderStatus: order.orderStatus === 'pending_payment' ? 'pending_assignment' : order.orderStatus,
        status: order.orderStatus === 'pending_payment' ? 'pending' : order.status,
        time: order.time === 'Ожидает оплаты' ? 'Ожидает выбора даты' : order.time,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
    } else if (normalized === 'failed') {
      transitionedToFailed = previousPaymentStatus !== 'failed';
      paymentUpdate.status = 'failed';
      tx.update(orderRef, {
        paymentStatus: 'failed',
        status: order.orderStatus === 'pending_payment' ? 'canceled' : order.status,
        orderStatus: order.orderStatus === 'pending_payment' ? 'canceled' : order.orderStatus,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
    }

    tx.set(paymentRef, paymentUpdate, {merge: true});
  });

  if (normalized === 'paid') {
    await settleReservedBonusForOrderInternal(orderId);
    await ensureSubscriptionForOrder(orderId);
    await applyPaidOrderUserMetrics(orderId);
    await awardStartupPackageBonusInternal(orderId);
    await applyReferralPaymentBonusInternal(orderId);
    if (transitionedToPaid) {
      await notifyPaymentConfirmed(orderId);
    }
  } else if (normalized === 'failed') {
    await releaseReservedBonusForOrderInternal(orderId, 'payment_failed');
    if (transitionedToFailed) {
      await notifyPaymentRejected(orderId);
    }
  }

  return {normalized, transactionId};
}

function buildSeedPayload(options = {}) {
  const cleanerId = options.cleanerId || null;
  const cleanerName = options.cleanerName || 'Исполнитель';
  const cleanerPhone = options.cleanerPhone || '+7 (700) 000-00-00';
  const residentialComplex = options.residentialComplex || 'ЖК Изумрудный';
  const clusterId = options.clusterId || 'astana_1';
  const clusterName = options.clusterName || 'ЖК Изумрудный кластер';
  const assignedEntrances = Array.isArray(options.assignedEntrances)
    ? options.assignedEntrances.map(String)
    : (options.entrance != null ? [String(options.entrance)] : []);

  const payload = {
    customer_packages: {
      basic: {
        name: '2 раза в месяц',
        price: 15000,
        frequency: '2 раза в месяц',
        features: ['Уборка комнат', 'Мытье полов', 'Протирка пыли'],
        popular: false,
        sortOrder: 1,
        isActive: true
      },
      standard: {
        name: '4 раза в месяц',
        price: 25000,
        frequency: '4 раза в месяц',
        features: ['Все из Базового', 'Мытье окон', 'Глажка белья'],
        popular: true,
        sortOrder: 2,
        isActive: true
      },
      premium: {
        name: '8 раз',
        price: 40000,
        frequency: '8 раз',
        features: ['Все из Стандарта', 'Балкон', 'Организация пространства'],
        popular: false,
        sortOrder: 3,
        isActive: true
      },
      quarter: {
        name: 'Квартал',
        price: 75000,
        frequency: 'Квартал',
        features: [
          'Подписка на 3 месяца',
          'Экономия при долгом периоде',
          'Заморозка до 14 дней'
        ],
        popular: false,
        sortOrder: 4,
        isActive: true,
        isQuarterly: true
      },
      general_cleaning: {
        name: 'Ген уборка',
        price: 45000,
        frequency: 'Разовая',
        features: [
          'Глубокая уборка кухни и санузлов',
          'Мытье фасадов и доступных поверхностей',
          'Удаление стойких загрязнений'
        ],
        popular: false,
        sortOrder: 5,
        isActive: true
      },
      post_renovation: {
        name: 'После ремонта',
        price: 60000,
        frequency: 'Разовая',
        features: [
          'Удаление строительной пыли',
          'Очистка поверхностей после ремонта',
          'Вынос мелкого строительного мусора'
        ],
        popular: false,
        sortOrder: 6,
        isActive: true
      }
    },
    pricing: {
      default: {
        basePrice: 5000,
        roomRate: 2000,
        bathroomRate: 1500,
        areaRate: 50,
        areaThreshold: 50,
        windowsPrice: 3000,
        ironingPrice: 2000,
        balconyPrice: 1500
      }
    },
    clusters: {
      [clusterId]: {
        name: clusterName,
        residentialComplex,
        lat: 51.1605,
        lng: 71.4704,
        radiusMeters: 300,
        cleanersCount: cleanerId ? 1 : 8
      }
    },
    houses: {
      emerald_1: {
        address: `${residentialComplex}, подъезд 1`,
        status: HOUSE_STATUS.IN_PROGRESS,
        threshold: 20,
        current_users: 8,
        waitlistCount: 8,
        city: 'Астана',
        lat: 51.1605,
        lng: 71.4704,
        zoneId: 'astana_center'
      }
    },
    service_zones: {
      astana_center: {
        title: 'Астана центр',
        city: 'Астана',
        status: 'activating',
        centerLat: 51.1605,
        centerLng: 71.4704,
        houseIds: ['emerald_1']
      }
    },
    admin: {
      dashboard: {
        users: 1284,
        activeOrders: 236,
        onlineCleaners: 87
      }
    },
    meta: {
      seed: {
        seedVersion: 2,
        seededAt: admin.firestore.FieldValue.serverTimestamp(),
        seededBy: 'functions.seedFirestore'
      }
    }
  };

  if (cleanerId) {
    payload.cleaners = {
      [cleanerId]: {
        name: cleanerName,
        phone: cleanerPhone,
        clusterName,
        verificationStatus: 'approved',
        assignedEntrances,
        jobsCount: 0,
        rating: 5,
        todayEarnings: 0,
        monthlyEarnings: 0,
        weekOrders: 0,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      }
    };
  }

  return payload;
}

async function applySeedPayload(options = {}) {
  const batch = db.batch();
  const payload = buildSeedPayload(options);
  for (const [collectionName, docs] of Object.entries(payload)) {
    for (const [docId, docData] of Object.entries(docs)) {
      batch.set(db.collection(collectionName).doc(docId), docData, {merge: true});
    }
  }
  await batch.commit();

  if (options.orderId && options.cleanerId) {
    await assignCleanerInternal({
      orderId: options.orderId,
      cleanerId: options.cleanerId,
      cleanerName: payload.cleaners?.[options.cleanerId]?.name || options.cleanerName || 'Исполнитель',
      scheduledDate: options.scheduledDate || null,
      time: options.time || null,
      address: options.address || null
    });
  }
}

exports.createOrderFromRequest = onDocumentCreated(
  'order_requests/{requestId}',
  async (event) => {
    const data = event.data?.data();
    if (!data) return;
    if (String(data.type || '') === 'prelaunch_prebooking') {
      return;
    }

    const customerId = data.customerId;
    const price = data.price;
    const pkg = data.package;
    const customerSnap = customerId
      ? await db.collection('customers').doc(String(customerId)).get()
      : null;
    const customerProfile = customerSnap?.exists ? (customerSnap.data() || {}) : {};
    let activeHouse;
    try {
      activeHouse = await assertActiveOrderHouse(data.houseId || customerProfile.houseId);
    } catch (error) {
      await event.data.ref.set({
        status: 'rejected',
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
        processingError: String(error?.message || error)
      }, {merge: true});
      return;
    }
    const address = normalizeProfileText(
      data.address || customerProfile.address || activeHouse.address || activeHouse.residentialComplex,
      320
    );
    const residentialComplex = normalizeProfileText(
      data.residentialComplex || customerProfile.residentialComplex || activeHouse.residentialComplex || activeHouse.title,
      240
    );

    await db.runTransaction(async (tx) => {
      const orderNumber = await allocateNextOrderNumber(tx);
      const displayOrderId = orderDisplayIdFromNumber(orderNumber);
      const orderId = String(orderNumber);
      const orderRef = db.collection('customer_orders').doc(orderId);
      const paymentRef = db.collection('payments').doc(orderId);

      tx.set(orderRef, {
        customerId,
        status: 'pending',
        orderStatus: 'pending_payment',
        paymentStatus: 'initiated',
        cleanerId: null,
        cleaner: null,
        package: pkg,
        price,
        houseId: activeHouse.id,
        houseStatus: String(activeHouse.status || HOUSE_STATUS.ACTIVE).toUpperCase(),
        serviceArea: normalizeProfileText(
          activeHouse.serviceArea || activeHouse.zoneId || activeHouse.clusterName || activeHouse.residentialComplex,
          160
        ),
        serviceAreaId: normalizeProfileText(activeHouse.serviceAreaId || activeHouse.zoneId, 120),
        zoneId: normalizeProfileText(activeHouse.zoneId, 120),
        clusterName: normalizeProfileText(activeHouse.clusterName, 160),
        residentialComplex: residentialComplex || null,
        address: address || null,
        area: Number(data.area || customerProfile.area || 0) || null,
        time: 'Ожидает оплаты',
        date: admin.firestore.FieldValue.serverTimestamp(),
        dateText: 'Ожидает подтверждения',
        rating: 0,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        sourceRequestId: event.params.requestId,
        orderNumber,
        displayOrderId
      });

      tx.set(paymentRef, {
        orderId,
        orderNumber,
        displayOrderId,
        customerId,
        amount: price,
        houseId: activeHouse.id,
        houseStatus: String(activeHouse.status || HOUSE_STATUS.ACTIVE).toUpperCase(),
        serviceArea: normalizeProfileText(
          activeHouse.serviceArea || activeHouse.zoneId || activeHouse.clusterName || activeHouse.residentialComplex,
          160
        ),
        zoneId: normalizeProfileText(activeHouse.zoneId, 120),
        clusterName: normalizeProfileText(activeHouse.clusterName, 160),
        address: address || null,
        currency: data.currency || 'KZT',
        provider: 'kaspi_manual_request',
        status: 'initiated',
        createdAt: admin.firestore.FieldValue.serverTimestamp()
      });

      tx.update(event.data.ref, {
        orderId,
        orderNumber,
        displayOrderId,
        status: 'processed',
        processedAt: admin.firestore.FieldValue.serverTimestamp()
      });
    });
  }
);

// OTP-based authentication via Wappi.pro WhatsApp
exports.requestOtp = callable(async (request) => {
  const phone = normalizePhone(request.data?.phone);
  if (!phone) {
    throw new HttpsError('invalid-argument', 'valid phone required');
  }

  const reviewAccount = REVIEW_TEST_ACCOUNTS[phone] || null;
  const code = reviewAccount ? REVIEW_TEST_OTP_CODE : generateOtpCode();
  await db.collection('otp_codes').doc(phone).set({
    phone,
    code,
    reviewTestAccount: Boolean(reviewAccount),
    attempts: 0,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    expiresAt: admin.firestore.Timestamp.fromDate(
      new Date(Date.now() + (reviewAccount ? 24 * 60 : 5) * 60 * 1000)
    )
  });

  if (reviewAccount) {
    return {ok: true, codeSent: true, fallbackCode: REVIEW_TEST_OTP_CODE};
  }

  try {
    await sendOtpViaWappi(phone, code);
    return {ok: true, codeSent: true};
  } catch (error) {
    console.error('requestOtp delivery failed', {
      phone,
      reason: String(error?.message || error || 'otp-delivery-unavailable')
    });
    throw new HttpsError(
      'failed-precondition',
      'Не удалось отправить код. Проверьте WhatsApp на номере или попробуйте позже.'
    );
  }
});

function createAuthSessionSecret() {
  return crypto.randomBytes(32).toString('base64url');
}

function hashAuthSessionSecret(secret) {
  return crypto.createHash('sha256').update(String(secret || '')).digest('hex');
}

async function createPersistentAuthSession({uid, flavor}) {
  const userId = String(uid || '').trim();
  if (!userId) {
    throw new HttpsError('invalid-argument', 'uid required');
  }
  const secret = createAuthSessionSecret();
  await db.collection('auth_sessions').doc(userId).set({
    uid: userId,
    flavor: String(flavor || '').trim(),
    secretHash: hashAuthSessionSecret(secret),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    expiresAt: admin.firestore.Timestamp.fromDate(
      new Date(Date.now() + AUTH_SESSION_TTL_DAYS * 24 * 60 * 60 * 1000)
    )
  }, {merge: true});
  return secret;
}

exports.signInWithOtp = callable(async (request) => {
  const phone = normalizePhone(request.data?.phone);
  const code = String(request.data?.code || '').trim();
  const flavor = String(request.data?.flavor || '').trim();
  if (!phone || !code || !flavor) {
    throw new HttpsError('invalid-argument', 'phone, code and flavor required');
  }

  const reviewAccount = REVIEW_TEST_ACCOUNTS[phone] || null;
  if (reviewAccount && reviewAccount.flavor !== flavor) {
    throw new HttpsError('permission-denied', 'Неверный код.');
  }
  const isReviewLogin =
    reviewAccount &&
    reviewAccount.flavor === flavor &&
    code === REVIEW_TEST_OTP_CODE;
  const otpRef = db.collection('otp_codes').doc(phone);
  const otpSnap = await otpRef.get();
  if (!otpSnap.exists && !isReviewLogin) {
    throw new HttpsError('failed-precondition', 'Код не запрашивался или срок действия истек.');
  }

  const otpData = otpSnap.exists ? (otpSnap.data() || {}) : {};
  const attempts = Number(otpData.attempts || 0);
  if (attempts >= 5) {
    throw new HttpsError('resource-exhausted', 'Слишком много попыток. Запросите код заново.');
  }

  const expiresAt = otpData.expiresAt instanceof admin.firestore.Timestamp
    ? otpData.expiresAt.toDate()
    : null;
  if (expiresAt && Date.now() > expiresAt.getTime()) {
    await otpRef.delete().catch(() => {});
    throw new HttpsError('failed-precondition', 'Срок действия кода истек. Запросите новый.');
  }

  if (!isReviewLogin && String(otpData.code || '') !== code) {
    await otpRef.set({
      attempts: attempts + 1,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});
    throw new HttpsError('permission-denied', 'Неверный код.');
  }

  await otpRef.delete().catch(() => {});

  const collectionName = flavor === 'pro' ? 'cleaners' : 'customers';
  const existingDoc = await resolveCanonicalPhoneProfile(collectionName, phone);

  let uid;
  if (existingDoc) {
    uid = existingDoc.id;
  } else {
    const newUserRef = db.collection(collectionName).doc();
    uid = newUserRef.id;
    const now = admin.firestore.FieldValue.serverTimestamp();
    await newUserRef.set({
      uid,
      phone,
      name: flavor === 'pro' ? 'Исполнитель' : 'Пользователь',
      createdAt: now,
      updatedAt: now,
      ...(flavor === 'pro' ? {
        verificationStatus: 'pending',
        status: 'active'
      } : {})
    });
    await db.collection('identity_phone_index').doc(`${collectionName}_${phone}`).set({
      uid,
      phone,
      collectionName,
      updatedAt: now
    }, {merge: true});
  }

  const sessionSecret = await createPersistentAuthSession({uid, flavor});
  if (isReviewLogin) {
    const reviewPayload = {
      phone,
      name: reviewAccount.name,
      fullName: reviewAccount.name,
      reviewTestAccount: true,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    };
    if (flavor === 'pro') {
      Object.assign(reviewPayload, {
        verificationStatus: 'approved',
        status: 'active',
        city: 'Алматы',
        serviceAreas: ['Алматы'],
        serviceAreaIds: [],
        rating: 5,
        cleanerStatus: 'RELIABLE'
      });
    }
    await db.collection(collectionName).doc(uid).set(reviewPayload, {merge: true});
  }
  const customToken = await admin.auth().createCustomToken(uid);
  return {token: customToken, uid, isNew: !existingDoc, sessionSecret};
});

exports.restoreAuthSession = callable(async (request) => {
  const uid = String(request.data?.uid || '').trim();
  const sessionSecret = String(request.data?.sessionSecret || '').trim();
  const flavor = String(request.data?.flavor || '').trim();
  if (!uid || !sessionSecret) {
    throw new HttpsError('invalid-argument', 'uid and sessionSecret required');
  }

  const sessionRef = db.collection('auth_sessions').doc(uid);
  const sessionSnap = await sessionRef.get();
  if (!sessionSnap.exists) {
    throw new HttpsError('unauthenticated', 'Session not found');
  }
  const session = sessionSnap.data() || {};
  const expiresAt = session.expiresAt instanceof admin.firestore.Timestamp
    ? session.expiresAt.toDate()
    : null;
  if (expiresAt && Date.now() > expiresAt.getTime()) {
    await sessionRef.delete().catch(() => {});
    throw new HttpsError('unauthenticated', 'Session expired');
  }
  if (flavor && session.flavor && String(session.flavor) !== flavor) {
    throw new HttpsError('permission-denied', 'Session flavor mismatch');
  }
  if (String(session.secretHash || '') !== hashAuthSessionSecret(sessionSecret)) {
    throw new HttpsError('unauthenticated', 'Invalid session');
  }

  await sessionRef.set({
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    restoredAt: admin.firestore.FieldValue.serverTimestamp()
  }, {merge: true});
  const customToken = await admin.auth().createCustomToken(uid);
  return {token: customToken, uid};
});

exports.createPaymentInvoice = callable(async (request) => {
  const {orderId, amount, customerId} = request.data || {};
  if (!request.auth || !orderId || !amount || !customerId) {
    throw new HttpsError('invalid-argument', 'orderId, amount, customerId required');
  }

  if (request.auth.uid !== customerId && !isAdminAuth(request.auth)) {
    throw new HttpsError('permission-denied', 'Not your order');
  }

  const paymentSnap = await db.collection('payments').doc(orderId).get();
  if (!paymentSnap.exists) {
    throw new HttpsError('not-found', 'Payment not found');
  }

  const invoice = await epayCreateInvoice({orderId, amount, customerId});

  await db.collection('payments').doc(orderId).set(
    {
      invoice: invoice,
      invoiceId: extractInvoiceId(invoice),
      invoiceUrl: extractInvoiceUrl(invoice),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    },
    {merge: true}
  );

  return {
    ok: true,
    invoiceUrl: extractInvoiceUrl(invoice),
    invoiceId: extractInvoiceId(invoice),
    raw: invoice
  };
});

exports.createBccPaymentSession = callable(async (request) => {
  const {orderId} = request.data || {};
  try {
    console.info('createBccPaymentSession request', {
      orderId,
      uid: request.auth?.uid || null
    });
    return await createBccPaymentForOrder({orderId, auth: request.auth});
  } catch (error) {
    console.error('createBccPaymentSession failed', {
      orderId,
      uid: request.auth?.uid || null,
      code: error?.code || null,
      message: error?.message || String(error)
    });
    throw error;
  }
});

exports.createBccPaymentSessionHttp = onRequest(async (req, res) => {
  res.set('Access-Control-Allow-Origin', req.headers.origin || '*');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }
  if (req.method !== 'POST') {
    res.status(405).json({ok: false, error: 'method-not-allowed'});
    return;
  }
  try {
    const authHeader = String(req.headers.authorization || '');
    const token = authHeader.startsWith('Bearer ')
      ? authHeader.substring('Bearer '.length)
      : '';
    if (!token) {
      res.status(401).json({ok: false, error: 'auth-required'});
      return;
    }
    const decoded = await admin.auth().verifyIdToken(token);
    const orderId = req.body?.orderId;
    const forwardedFor = String(req.headers['x-forwarded-for'] || '')
      .split(',')[0]
      .trim();
    const result = await createBccPaymentForOrder({
      orderId,
      auth: {uid: decoded.uid, token: decoded},
      clientIp: forwardedFor || req.ip || '0.0.0.0'
    });
    res.json(result);
  } catch (error) {
    console.error('createBccPaymentSessionHttp failed', {
      code: error?.code || null,
      message: error?.message || String(error)
    });
    const status =
      error?.code === 'permission-denied' ? 403 :
      error?.code === 'not-found' ? 404 :
      error?.code === 'unauthenticated' ? 401 :
      400;
    res.status(status).json({
      ok: false,
      error: error?.message || String(error),
      code: error?.code || 'bad-request'
    });
  }
});

async function authFromBearerRequest(req) {
  const authHeader = String(req.headers.authorization || '');
  const token = authHeader.startsWith('Bearer ')
    ? authHeader.substring('Bearer '.length)
    : '';
  if (!token) {
    throw new HttpsError('unauthenticated', 'auth-required');
  }
  const decoded = await admin.auth().verifyIdToken(token);
  return {uid: decoded.uid, token: decoded};
}

function setJsonCors(req, res) {
  res.set('Access-Control-Allow-Origin', req.headers.origin || '*');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
}

function httpErrorStatus(error) {
  return error?.code === 'permission-denied' ? 403 :
    error?.code === 'not-found' ? 404 :
      error?.code === 'unauthenticated' ? 401 :
        error?.code === 'failed-precondition' ? 409 :
          400;
}

exports.bookScheduleHttp = onRequest(async (req, res) => {
  setJsonCors(req, res);
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }
  if (req.method !== 'POST') {
    res.status(405).json({ok: false, error: 'method-not-allowed'});
    return;
  }
  try {
    const auth = await authFromBearerRequest(req);
    const subscriptionId = String(req.body?.subscriptionId || '');
    const selections = Array.isArray(req.body?.selections) ? req.body.selections : [];
    if (!subscriptionId) {
      throw new HttpsError('invalid-argument', 'subscriptionId required');
    }
    const result = await bookScheduleInternal({
      subscriptionId,
      uid: auth.uid,
      selections
    });
    res.json(result);
  } catch (error) {
    console.error('bookScheduleHttp failed', {
      code: error?.code || null,
      message: error?.message || String(error)
    });
    res.status(httpErrorStatus(error)).json({
      ok: false,
      error: error?.message || String(error),
      code: error?.code || 'bad-request'
    });
  }
});

exports.cancelPendingOrderHttp = onRequest(async (req, res) => {
  setJsonCors(req, res);
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }
  if (req.method !== 'POST') {
    res.status(405).json({ok: false, error: 'method-not-allowed'});
    return;
  }
  try {
    const auth = await authFromBearerRequest(req);
    const orderId = String(req.body?.orderId || '').trim();
    if (!orderId) {
      throw new HttpsError('invalid-argument', 'orderId required');
    }
    const result = await cancelPendingOrderInternal({orderId, auth});
    res.json(result);
  } catch (error) {
    console.error('cancelPendingOrderHttp failed', {
      code: error?.code || null,
      message: error?.message || String(error)
    });
    res.status(httpErrorStatus(error)).json({
      ok: false,
      error: error?.message || String(error),
      code: error?.code || 'bad-request'
    });
  }
});

exports.acceptOrderOfferHttp = onRequest(async (req, res) => {
  setJsonCors(req, res);
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }
  if (req.method !== 'POST') {
    res.status(405).json({ok: false, error: 'method-not-allowed'});
    return;
  }
  try {
    const auth = await authFromBearerRequest(req);
    const offerId = String(req.body?.offerId || '').trim();
    if (!offerId) {
      throw new HttpsError('invalid-argument', 'offerId required');
    }
    const result = await acceptOrderOfferInternal({
      offerId,
      cleanerId: auth.uid
    });
    res.json(result);
  } catch (error) {
    console.error('acceptOrderOfferHttp failed', {
      code: error?.code || null,
      message: error?.message || String(error)
    });
    res.status(httpErrorStatus(error)).json({
      ok: false,
      error: error?.message || String(error),
      code: error?.code || 'bad-request'
    });
  }
});

exports.rejectOrderOfferHttp = onRequest(async (req, res) => {
  setJsonCors(req, res);
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }
  if (req.method !== 'POST') {
    res.status(405).json({ok: false, error: 'method-not-allowed'});
    return;
  }
  try {
    const auth = await authFromBearerRequest(req);
    const offerId = String(req.body?.offerId || '').trim();
    if (!offerId) {
      throw new HttpsError('invalid-argument', 'offerId required');
    }
    const result = await rejectOrderOfferInternal({
      offerId,
      cleanerId: auth.uid,
      reason: 'rejected'
    });
    res.json(result);
  } catch (error) {
    console.error('rejectOrderOfferHttp failed', {
      code: error?.code || null,
      message: error?.message || String(error)
    });
    res.status(httpErrorStatus(error)).json({
      ok: false,
      error: error?.message || String(error),
      code: error?.code || 'bad-request'
    });
  }
});

exports.cancelScheduleSlotHttp = onRequest(async (req, res) => {
  setJsonCors(req, res);
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }
  if (req.method !== 'POST') {
    res.status(405).json({ok: false, error: 'method-not-allowed'});
    return;
  }
  try {
    const auth = await authFromBearerRequest(req);
    const slotId = String(req.body?.slotId || '').trim();
    if (!slotId) {
      throw new HttpsError('invalid-argument', 'slotId required');
    }
    const result = await cancelScheduleSlotInternal({
      slotId,
      uid: auth.uid,
      adminMode: isAdminAuth(auth)
    });
    res.json(result);
  } catch (error) {
    console.error('cancelScheduleSlotHttp failed', {
      code: error?.code || null,
      message: error?.message || String(error)
    });
    res.status(httpErrorStatus(error)).json({
      ok: false,
      error: error?.message || String(error),
      code: error?.code || 'bad-request'
    });
  }
});

exports.createOrderAndInvoice = callable(async (request) => {
  const {
    amount,
    customerId,
    packageName,
    packageId,
    pricingMode,
    cleaningsPerMonth,
    accessMethod,
    addons,
    addonsDetailed,
    frequencyLabel,
    billingPeriodMonths,
    rooms,
    bathrooms,
    area,
    bonusToSpend,
    address,
    residentialComplex,
    entrance,
    apartment,
    houseId
  } = request.data || {};
  if (!request.auth || !customerId) {
    throw new HttpsError('invalid-argument', 'customerId required');
  }
  if (request.auth.uid !== customerId && !isAdminAuth(request.auth)) {
    throw new HttpsError('permission-denied', 'Not your order');
  }

  const customerProfileSnap = await db.collection('customers').doc(customerId).get();
  const customerProfile = customerProfileSnap.exists ? customerProfileSnap.data() : {};
  const requestedHouseId = normalizeProfileText(houseId || customerProfile?.houseId, 120);
  const activeHouse = await assertActiveOrderHouse(requestedHouseId);
  const customerAddresses = Array.isArray(customerProfile?.addresses)
    ? customerProfile.addresses
    : [];
  const selectedProfileAddress = customerAddresses.find((item) =>
    String(item?.houseId || '').trim() === requestedHouseId
  ) || null;
  const selectedResidentialComplex = normalizeProfileText(
    selectedProfileAddress?.residentialComplex ||
      residentialComplex ||
      customerProfile?.residentialComplex ||
      activeHouse.residentialComplex ||
      activeHouse.title ||
      activeHouse.address,
    240
  );
  const selectedAddressLine = normalizeProfileText(
    selectedProfileAddress?.address ||
      address ||
      customerProfile?.address ||
      activeHouse.address ||
      selectedResidentialComplex,
    320
  );
  const selectedEntrance = normalizeProfileText(
    selectedProfileAddress?.entrance || entrance || customerProfile?.entrance,
    40
  );
  const selectedApartment = normalizeProfileText(
    selectedProfileAddress?.apartment || apartment || customerProfile?.apartment,
    40
  );
  const selectedArea = Number(
    area ||
      selectedProfileAddress?.area ||
      customerProfile?.area ||
      0
  );
  assertCustomerAreaReadyForOrdering({
    customerProfile,
    selectedAddress: selectedProfileAddress,
    selectedArea
  });
  const customerCity = await resolveCustomerCity(customerId, customerProfile || {});
  const policies = await getPolicyConfig();
  const pricingSnap = await db.collection('pricing').doc('default').get();
  const pricing = pricingSnap.exists ? pricingSnap.data() || {} : {};
  const normalizedPackageId = normalizeOrderPackageId(packageId, packageName);
  const packageConfig = await loadCustomerPackageConfig(normalizedPackageId);
  const normalizedPricingMode = (() => {
    const rawMode = String(pricingMode || '').trim().toLowerCase();
    if (rawMode === 'addons_only' || normalizedPackageId === 'addons_only') {
      return 'addons_only';
    }
    if (normalizedPackageId) {
      return 'package_catalog';
    }
    return rawMode === 'package_catalog' ? 'package_catalog' : 'custom_quote';
  })();
  const customerAddress = [
    selectedAddressLine || selectedResidentialComplex,
    selectedEntrance ? `подъезд ${selectedEntrance}` : null,
    selectedApartment ? `кв. ${selectedApartment}` : null
  ].filter(Boolean).join(', ');
  const normalizedDetailedAddons = normalizeDetailedAddons(addonsDetailed);
  const detailedAddonPricing = calculateDetailedAddonPricing(
    pricing,
    normalizedDetailedAddons
  );
  const schedulerMetrics = buildSchedulerMetrics({
    area: selectedArea,
    addonsDetailed: normalizedDetailedAddons,
    addons: Array.isArray(addons) ? addons : []
  }, policies);
  const addonTotalPrice =
    detailedAddonPricing.billableTotal > 0
      ? detailedAddonPricing.billableTotal
      : calculateAddonTotalPriceFromPricing(
          pricing,
          Array.isArray(addons) ? addons : []
        );
  const baseQuote = calculateCustomPackageQuoteFromPricing({
    pricing,
    rooms: Number(rooms || 0),
    bathrooms: Number(bathrooms || 0),
    area: selectedArea,
    frequency: 1,
    billingPeriodMonths: 1,
    addonsDetailed: normalizedDetailedAddons
  });
  const effectiveVisitsPerMonth = resolvePackageVisitsPerMonth(
    normalizedPackageId,
    Number(
      packageConfig.cleaningsPerMonth ||
      cleaningsPerMonth ||
      parseFrequencyConfig(frequencyLabel, packageName).monthlyVisits ||
      1
    )
  );
  const effectiveBillingPeriodMonths =
    normalizedPackageId === 'quarter'
      ? Math.max(
          1,
          Number(packageConfig.billingPeriodMonths || billingPeriodMonths || 3)
        )
      : Math.max(
          1,
          Number(packageConfig.billingPeriodMonths || billingPeriodMonths || 1)
        );
  const packageDiscountPercent = Math.max(
    0,
    Number(
      normalizedPackageId === 'quarter'
        ? (packageConfig.discountPercent || 10)
        : (packageConfig.discountPercent || 0)
    )
  );
  const clientProvidedAmount = Math.max(0, Number(amount || 0));
  let trustedBaseAmount = 0;
  if (normalizedPricingMode === 'addons_only') {
    trustedBaseAmount = addonTotalPrice;
  } else if (
    normalizedPackageId === 'general_cleaning' ||
    normalizedPackageId === 'post_renovation'
  ) {
    trustedBaseAmount =
      Math.max(0, Number(packageConfig.price || defaultFixedPackagePrice(normalizedPackageId))) +
      addonTotalPrice;
  } else {
    const configuredUnitAreaPrice = Math.max(0, Number(packageConfig.price || 0));
    const effectiveArea = Math.max(0, selectedArea);
    const perCleaningPrice = configuredUnitAreaPrice > 0
      ? configuredUnitAreaPrice * effectiveArea
      : Math.max(0, Number(baseQuote.perCleaningPrice || 0));
    const cleaningCount = effectiveVisitsPerMonth * effectiveBillingPeriodMonths;
    const packageSubtotal = perCleaningPrice * cleaningCount;
    const packageDiscountAmount = Math.round(
      packageSubtotal * (packageDiscountPercent / 100)
    );
    trustedBaseAmount = Math.max(
      packageSubtotal - packageDiscountAmount + addonTotalPrice,
      0
    );
  }
  const serverCalculatedAmount = trustedBaseAmount;
  if (
    normalizedPricingMode === 'package_catalog' &&
    clientProvidedAmount > 0 &&
    serverCalculatedAmount > 0
  ) {
    const minAllowedClientAmount = Math.floor(serverCalculatedAmount * 0.5);
    if (clientProvidedAmount < minAllowedClientAmount) {
      throw new HttpsError(
        'invalid-argument',
        'Сумма платежа не совпадает с расчетом пакета. Обновите экран и попробуйте снова.'
      );
    }
    trustedBaseAmount = clientProvidedAmount;
  }
  const requestedBonusAmount = normalizedPricingMode === 'addons_only'
    ? Math.max(0, Number(bonusToSpend || 0))
    : 0;
  const availableBonusPoints = Math.max(0, Number(customerProfile?.bonusPoints || 0));
  const tierDiscountPercent = Math.max(
    0,
    Number(customerProfile?.tier_discount_percent || 0)
  );
  const referralDiscountPercent = Math.max(
    0,
    Number(
      customerProfile?.referralDiscountPercent ||
      customerProfile?.referral_discount_percent ||
      0
    )
  );
  const tierDiscountAmount = Math.round(
    trustedBaseAmount * (tierDiscountPercent / 100)
  );
  const priceAfterTierDiscount = Math.max(trustedBaseAmount - tierDiscountAmount, 0);
  const referralDiscountAmount = Math.round(
    priceAfterTierDiscount * (referralDiscountPercent / 100)
  );
  const discountedAmount = Math.max(priceAfterTierDiscount - referralDiscountAmount, 0);
  const maxBonusPaymentPercent = normalizedPricingMode === 'addons_only'
    ? await getAddonBonusSpendPercent()
    : 50;
  const maxBonusPaymentAmount = Math.floor(
    discountedAmount * (maxBonusPaymentPercent / 100)
  );
  const bonusAppliedAmount = Math.min(
    requestedBonusAmount,
    availableBonusPoints,
    maxBonusPaymentAmount
  );
  if (requestedBonusAmount > 0 && bonusAppliedAmount <= 0) {
    throw new HttpsError(
      'failed-precondition',
      `Недостаточно бонусов или превышен лимит списания ${maxBonusPaymentPercent}%.`
    );
  }
  const finalAmount = Math.max(discountedAmount - bonusAppliedAmount, 0);
  const bonusOnlyPaid = normalizedPricingMode === 'addons_only' && finalAmount === 0;
  const orderFingerprint = buildPendingOrderFingerprint({
    customerId,
    normalizedPackageId,
    packageName: packageName || 'Индивидуальный',
    normalizedPricingMode,
    effectiveVisitsPerMonth,
    effectiveBillingPeriodMonths,
    finalAmount,
    area: selectedArea,
    customerAddress,
    normalizedDetailedAddons,
  });
  const reusablePendingOrder = await findReusablePendingOrder({
    customerId,
    fingerprint: orderFingerprint,
  });
  if (reusablePendingOrder) {
    const existing = reusablePendingOrder.data || {};
    return {
      ok: true,
      reused: true,
      orderId: reusablePendingOrder.id,
      orderNumber: existing.orderNumber || null,
      displayOrderId:
        existing.displayOrderId ||
        orderDisplayIdFromNumber(existing.orderNumber) ||
        reusablePendingOrder.id,
      tierDiscountPercent,
      tierDiscountAmount,
      bonusAppliedAmount,
      referralDiscountPercent,
      referralDiscountAmount,
      finalAmount: existing.price ?? finalAmount
    };
  }
  let createdOrderId = null;
  let createdOrderNumber = null;
  let createdDisplayOrderId = null;

  await db.runTransaction(async (tx) => {
    const orderNumber = await allocateNextOrderNumber(tx);
    const displayOrderId = orderDisplayIdFromNumber(orderNumber);
    const orderId = String(orderNumber);
    const orderRef = db.collection('customer_orders').doc(orderId);
    const paymentRef = db.collection('payments').doc(orderId);
    createdOrderId = orderId;
    createdOrderNumber = orderNumber;
    createdDisplayOrderId = displayOrderId;

    tx.set(orderRef, {
      orderNumber,
      displayOrderId,
      orderFingerprint,
      customerId,
      customerName: customerProfile?.name || null,
      customerPhone: customerProfile?.phone || null,
      customerCity: customerCity || null,
      residentialComplex: selectedResidentialComplex || null,
      entrance: selectedEntrance || null,
      apartment: selectedApartment || null,
      area: selectedArea || null,
      houseId: requestedHouseId,
      houseStatus: String(activeHouse.status || HOUSE_STATUS.ACTIVE).toUpperCase(),
      serviceArea: normalizeProfileText(
        activeHouse.serviceArea || activeHouse.zoneId || activeHouse.clusterName || activeHouse.residentialComplex,
        160
      ),
      serviceAreaId: normalizeProfileText(activeHouse.serviceAreaId || activeHouse.zoneId, 120),
      zoneId: normalizeProfileText(activeHouse.zoneId, 120),
      clusterName: normalizeProfileText(activeHouse.clusterName, 160),
      status: bonusOnlyPaid ? 'pending' : 'pending',
      orderStatus: bonusOnlyPaid ? 'pending_assignment' : 'pending_payment',
      paymentStatus: bonusOnlyPaid ? 'paid' : 'initiated',
      cleanerId: null,
      cleaner: null,
      package: packageName || 'Индивидуальный',
      packageId: normalizedPackageId || null,
      pricingMode: normalizedPricingMode,
      frequencyLabel: frequencyLabel || null,
      billingPeriodMonths: effectiveBillingPeriodMonths,
      cleaningsPerMonth: effectiveVisitsPerMonth,
      accessMethod: accessMethod || 'home',
      addons: Array.isArray(addons) ? addons : [],
      addonsDetailed: normalizedDetailedAddons,
      rooms: rooms || null,
      bathrooms: bathrooms || null,
      estimatedDurationMinutes: schedulerMetrics.estimatedDurationMinutes,
      estimatedDurationHours: schedulerMetrics.estimatedDurationHours,
      addonCount: schedulerMetrics.addonCount,
      addonBufferMinutes: schedulerMetrics.addonBufferMinutes,
      travelTimeMinutes: schedulerMetrics.travelTimeMinutes,
      totalDurationMinutes: schedulerMetrics.totalDurationMinutes,
      totalDurationHours: schedulerMetrics.totalDurationHours,
      originalPrice: trustedBaseAmount,
      clientProvidedAmount,
      serverCalculatedAmount,
      tierDiscountPercent,
      tierDiscountAmount,
      priceAfterTierDiscount,
      referralDiscountPercent,
      referralDiscountAmount,
      priceAfterReferralDiscount: discountedAmount,
      price: finalAmount,
      addonTotalPrice,
      maxBonusPaymentPercent,
      maxBonusPaymentAmount,
      addonsSeparatePaymentTotal: detailedAddonPricing.separatePaymentTotal,
      separatePaymentAddons: detailedAddonPricing.separatePaymentAddons,
      bonusAppliedAmount,
      bonusProgram: bonusAppliedAmount > 0 ? 'package_addons_50_percent' : null,
      bonusReservedAt: bonusAppliedAmount > 0
        ? admin.firestore.FieldValue.serverTimestamp()
        : null,
      bonusSettledAt: bonusOnlyPaid && bonusAppliedAmount > 0
        ? admin.firestore.FieldValue.serverTimestamp()
        : null,
      time: bonusOnlyPaid ? 'Ожидает выбора даты' : 'Ожидает оплаты',
      address: customerAddress || null,
      date: admin.firestore.FieldValue.serverTimestamp(),
      dateText: 'Ожидает подтверждения',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      paidAt: bonusOnlyPaid ? admin.firestore.FieldValue.serverTimestamp() : null
    });
    tx.set(paymentRef, {
      orderId,
      orderNumber,
      displayOrderId,
      customerId,
      customerName: customerProfile?.name || null,
      customerPhone: customerProfile?.phone || null,
      customerCity: customerCity || null,
      houseId: requestedHouseId,
      houseStatus: String(activeHouse.status || HOUSE_STATUS.ACTIVE).toUpperCase(),
      serviceArea: normalizeProfileText(
        activeHouse.serviceArea || activeHouse.zoneId || activeHouse.clusterName || activeHouse.residentialComplex,
        160
      ),
      zoneId: normalizeProfileText(activeHouse.zoneId, 120),
      clusterName: normalizeProfileText(activeHouse.clusterName, 160),
      packageName: packageName || 'Индивидуальный',
      packageId: normalizedPackageId || null,
      pricingMode: normalizedPricingMode,
      frequencyLabel: frequencyLabel || null,
      address: customerAddress || null,
      cleaningsPerMonth: effectiveVisitsPerMonth,
      addons: Array.isArray(addons) ? addons : [],
      addonsDetailed: normalizedDetailedAddons,
      addonCount: schedulerMetrics.addonCount,
      baseAmount: trustedBaseAmount,
      clientProvidedAmount,
      tierDiscountPercent,
      tierDiscountAmount,
      referralDiscountPercent,
      referralDiscountAmount,
      priceAfterTierDiscount,
      billingPeriodMonths: effectiveBillingPeriodMonths,
      amount: finalAmount,
      bonusAppliedAmount,
      maxBonusPaymentPercent,
      maxBonusPaymentAmount,
      addonTotalPrice,
      addonsSeparatePaymentTotal: detailedAddonPricing.separatePaymentTotal,
      separatePaymentAddons: detailedAddonPricing.separatePaymentAddons,
      currency: 'KZT',
      provider: bonusOnlyPaid ? 'bonus' : 'kaspi_manual_request',
      status: bonusOnlyPaid ? 'paid' : 'initiated',
      paymentStatus: bonusOnlyPaid ? 'paid' : 'initiated',
      bonusToSpend: requestedBonusAmount,
      paidAt: bonusOnlyPaid ? admin.firestore.FieldValue.serverTimestamp() : null,
      bonusSettledAt: bonusOnlyPaid && bonusAppliedAmount > 0
        ? admin.firestore.FieldValue.serverTimestamp()
        : null,
      createdAt: admin.firestore.FieldValue.serverTimestamp()
    });
    if (bonusAppliedAmount > 0) {
      tx.set(db.collection('customers').doc(String(customerId)), {
        bonusPoints: availableBonusPoints - bonusAppliedAmount,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      }, {merge: true});
    }
  });

  if (normalizedPricingMode === 'addons_only' && finalAmount === 0) {
    await applyAddonsOnlyOrderToSlot(createdOrderId, 'bonus_payment');
  }
  if (bonusAppliedAmount > 0) {
    await recordCustomerBonusTransaction({
      userId: customerId,
      amount: -bonusAppliedAmount,
      title: 'Оплата бонусами',
      reason: normalizedPricingMode === 'addons_only'
        ? 'Списано за доп. услуги'
        : 'Списано при оформлении заказа',
      type: 'bonus_debit',
      orderId: createdOrderId
    });
  }

  return {
    ok: true,
    orderId: createdOrderId,
    orderNumber: createdOrderNumber,
    displayOrderId: createdDisplayOrderId,
    tierDiscountPercent,
    tierDiscountAmount,
    bonusAppliedAmount,
    maxBonusPaymentPercent,
    maxBonusPaymentAmount,
    referralDiscountPercent,
    referralDiscountAmount,
    finalAmount
  };
});

exports.submitKaspiInvoiceRequest = callable(async (request) => {
  const {orderId, kaspiPhone} = request.data || {};
  if (!request.auth || !orderId || !kaspiPhone) {
    throw new HttpsError('invalid-argument', 'orderId and kaspiPhone required');
  }

  const paymentRef = db.collection('payments').doc(orderId);
  const orderRef = db.collection('customer_orders').doc(orderId);

  await db.runTransaction(async (tx) => {
    const paymentSnap = await tx.get(paymentRef);
    const orderSnap = await tx.get(orderRef);

    if (!paymentSnap.exists || !orderSnap.exists) {
      throw new HttpsError('not-found', 'Order/payment not found');
    }

    const payment = paymentSnap.data();
    const order = orderSnap.data();

    if (payment.customerId !== request.auth.uid && !isAdminAuth(request.auth)) {
      throw new HttpsError('permission-denied', 'Not your payment');
    }

    if (order.orderStatus !== 'pending_payment') {
      throw new HttpsError('failed-precondition', 'Order is not waiting payment');
    }

    const payableAmount = Math.max(
      0,
      Number(payment.amount ?? payment.price ?? order.amount ?? order.price ?? 0)
    );
    const originalAmount = Math.max(
      payableAmount,
      Number(order.originalPrice || payment.originalPrice || payment.baseAmount || payableAmount)
    );

    tx.update(paymentRef, {
      status: 'invoice_requested',
      kaspiPhone: String(kaspiPhone).trim(),
      amount: payableAmount,
      price: payableAmount,
      originalPrice: originalAmount,
      baseAmount: originalAmount,
      bonusToSpend: Number(order.bonusToSpend || payment.bonusToSpend || 0),
      bonusAppliedAmount: Number(
        order.bonusAppliedAmount || payment.bonusAppliedAmount || 0
      ),
      maxBonusPaymentPercent: Number(
        order.maxBonusPaymentPercent || payment.maxBonusPaymentPercent || 50
      ),
      maxBonusPaymentAmount: Number(
        order.maxBonusPaymentAmount || payment.maxBonusPaymentAmount || 0
      ),
      packageName: order.package || null,
      frequencyLabel: order.frequencyLabel || null,
      addons: [],
      addonsDetailed: [],
      addonCount: 0,
      addonTotalPrice: 0,
      addonsSeparatePaymentTotal: 0,
      separatePaymentAddons: [],
      customerName: order.customerName || payment.customerName || null,
      customerPhone: order.customerPhone || payment.customerPhone || null,
      address: order.address || payment.address || null,
      invoiceRequestedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    });

    tx.update(orderRef, {
      paymentStatus: 'invoice_requested',
      kaspiPhone: String(kaspiPhone).trim(),
      price: payableAmount,
      amount: payableAmount,
      originalPrice: originalAmount,
      invoiceRequestedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    });
  });

  return {ok: true};
});

async function cancelPendingOrderInternal({orderId, auth}) {
  if (!auth || !orderId) {
    throw new HttpsError('invalid-argument', 'orderId required');
  }

  const normalizedOrderId = String(orderId).trim();
  const paymentRef = db.collection('payments').doc(normalizedOrderId);
  const orderRef = db.collection('customer_orders').doc(normalizedOrderId);
  const slotRef = db.collection('schedule_slots').doc(normalizedOrderId);
  let bonusAppliedAmount = 0;
  let ownerIdForAddonCleanup = '';
  let slotIdForAddonCleanup = normalizedOrderId;

  await db.runTransaction(async (tx) => {
    const [paymentSnap, orderSnap, slotSnap] = await Promise.all([
      tx.get(paymentRef),
      tx.get(orderRef),
      tx.get(slotRef)
    ]);

    if (!orderSnap.exists && !paymentSnap.exists && !slotSnap.exists) {
      throw new HttpsError('not-found', 'Order/payment not found');
    }

    const order = orderSnap.exists ? orderSnap.data() || {} : {};
    const payment = paymentSnap.exists ? paymentSnap.data() || {} : {};
    const slot = slotSnap.exists ? slotSnap.data() || {} : {};
    const ownerId = String(
      order.customerId || payment.customerId || slot.customerId || ''
    );
    ownerIdForAddonCleanup = ownerId;
    if (ownerId !== auth.uid && !isAdminAuth(auth)) {
      throw new HttpsError('permission-denied', 'Not your order');
    }
    slotIdForAddonCleanup = String(
      order.slotId ||
        payment.slotId ||
        slot.id ||
        normalizedOrderId
    ).trim() || normalizedOrderId;

    const currentOrderStatus = String(
      order.orderStatus ||
        order.status ||
        slot.orderStatus ||
        slot.status ||
        payment.orderStatus ||
        payment.status ||
        ''
    ).trim().toLowerCase();
    if (!['pending_payment', 'pending_assignment'].includes(currentOrderStatus)) {
      throw new HttpsError('failed-precondition', 'Order can no longer be cancelled');
    }

    const currentPaymentStatus = String(
      order.paymentStatus || payment.paymentStatus || payment.status || slot.paymentStatus || ''
    ).trim().toLowerCase();
    if (currentPaymentStatus === 'paid') {
      throw new HttpsError('failed-precondition', 'Paid order cannot be cancelled by customer');
    }
    const refundRequired = currentPaymentStatus === 'paid';

    bonusAppliedAmount = Math.max(0, Number(order.bonusAppliedAmount || payment.bonusAppliedAmount || 0));

    if (orderSnap.exists) {
      tx.set(orderRef, {
        status: 'canceled',
        orderStatus: 'canceled',
        paymentStatus: 'canceled',
        ...clearAddonPayload(),
        refundRequired,
        refundStatus: refundRequired ? 'pending' : null,
        cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      }, {merge: true});
    }

    if (slotSnap.exists) {
      tx.set(slotRef, {
        status: 'canceled',
        orderStatus: 'canceled',
        paymentStatus: 'canceled',
        assignmentStatus: 'canceled',
        ...clearAddonPayload(),
        cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      }, {merge: true});
      tx.set(db.collection('cleaner_orders').doc(slotRef.id), {
        status: 'canceled',
        orderStatus: 'canceled',
        paymentStatus: 'canceled',
        ...clearAddonPayload(),
        cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      }, {merge: true});
      tx.set(db.collection('cleaner_shifts').doc(slotRef.id), {
        status: 'canceled',
        ...clearAddonPayload(),
        cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      }, {merge: true});
    }

    if (paymentSnap.exists) {
      tx.set(paymentRef, {
        status: 'canceled',
        paymentStatus: 'canceled',
        refundRequired,
        refundStatus: refundRequired ? 'pending' : null,
        cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      }, {merge: true});
    }

  });

  if (bonusAppliedAmount > 0) {
    await releaseReservedBonusForOrderInternal(normalizedOrderId, 'customer_cancelled_pending_order');
  }

  if (ownerIdForAddonCleanup) {
    await refundBonusForCanceledSlotInternal({
      slotId: slotIdForAddonCleanup,
      customerId: ownerIdForAddonCleanup,
      orderId: normalizedOrderId,
      reason: 'customer_cancelled_pending_order'
    }).catch((error) => {
      console.error('Failed to cancel linked addons after pending order cancellation', {
        orderId: normalizedOrderId,
        slotId: slotIdForAddonCleanup,
        customerId: ownerIdForAddonCleanup,
        error
      });
      return 0;
    });
  }

  return {ok: true, orderId: normalizedOrderId};
}

exports.cancelPendingOrder = callable(async (request) => {
  const {orderId} = request.data || {};
  return cancelPendingOrderInternal({orderId, auth: request.auth});
});

async function reviewAreaRecalculationPaymentInternal({paymentId, approved, reviewerId, note = null}) {
  const paymentRef = db.collection('payments').doc(String(paymentId));
  let sourceOrderId = '';
  let customerId = '';
  let amount = 0;

  await db.runTransaction(async (tx) => {
    const paymentSnap = await tx.get(paymentRef);
    if (!paymentSnap.exists) {
      throw new HttpsError('not-found', 'Payment not found');
    }
    const payment = paymentSnap.data() || {};
    sourceOrderId = String(
      payment.orderId ||
      payment.sourceOrderId ||
      String(paymentId).replace(/^area_recalc_/, '')
    ).trim();
    customerId = String(payment.customerId || payment.userId || '').trim();
    amount = Math.max(0, Number(payment.areaAdjustmentAmount || payment.amount || payment.price || 0));
    if (!sourceOrderId) {
      throw new HttpsError('failed-precondition', 'Source order not found');
    }

    const orderRef = db.collection('customer_orders').doc(sourceOrderId);
    const bridgeRef = db.collection('debug_bridge_orders').doc(sourceOrderId);
    const orderSnap = await tx.get(orderRef);
    if (!customerId && orderSnap.exists) {
      customerId = String(orderSnap.data()?.customerId || orderSnap.data()?.userId || '').trim();
    }

    const status = approved ? 'paid' : 'failed';
    const update = {
      status,
      paymentStatus: status,
      reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
      reviewedBy: reviewerId || null,
      reviewNote: note || null,
      paidAt: approved ? admin.firestore.FieldValue.serverTimestamp() : null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    };
    tx.set(paymentRef, update, {merge: true});

    const orderUpdate = {
      areaAdjustmentPaymentStatus: status,
      areaAdjustmentPaymentId: String(paymentId),
      areaAdjustmentReviewedAt: admin.firestore.FieldValue.serverTimestamp(),
      areaAdjustmentReviewNote: note || null,
      areaRecalculationPaymentStatus: status,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    };
    if (approved) {
      orderUpdate.areaAdjustmentPaidAt = admin.firestore.FieldValue.serverTimestamp();
      orderUpdate.areaAdjustmentAmountPaid = amount;
    } else {
      orderUpdate.areaAdjustmentRejectedAt = admin.firestore.FieldValue.serverTimestamp();
    }
    tx.set(orderRef, orderUpdate, {merge: true});
    tx.set(bridgeRef, orderUpdate, {merge: true});
  });

  if (customerId) {
    await sendPushToUser(
      customerId,
      approved ? 'Доплата подтверждена' : 'Доплата отклонена',
      approved
        ? `Доплата за перерасчет площади ${Math.round(amount)} ₸ подтверждена.`
        : 'Доплата за перерасчет площади отклонена.',
      {
        type: approved ? 'area_recalculation_paid' : 'area_recalculation_rejected',
        orderId: sourceOrderId,
        paymentId: String(paymentId),
        route: '/client/payment-history'
      }
    );
  }

  return {ok: true, paymentId: String(paymentId), orderId: sourceOrderId, approved};
}

exports.reviewManualPayment = callable(async (request) => {
  assertBackoffice(request.auth);
  const {orderId, approved, note} = request.data || {};
  if (!orderId || typeof approved !== 'boolean') {
    throw new HttpsError('invalid-argument', 'orderId and approved required');
  }

  const paymentRef = db.collection('payments').doc(String(orderId));
  const paymentTypeSnap = await paymentRef.get();
  if (paymentTypeSnap.exists &&
      String(paymentTypeSnap.data()?.type || '') === 'addon_request') {
    return reviewAddonRequestPaymentInternal({
      paymentId: String(orderId),
      approved,
      reviewerId: request.auth.uid,
      note: note || null
    });
  }
  if (paymentTypeSnap.exists &&
      String(paymentTypeSnap.data()?.type || '') === 'area_recalculation') {
    return reviewAreaRecalculationPaymentInternal({
      paymentId: String(orderId),
      approved,
      reviewerId: request.auth.uid,
      note: note || null
    });
  }
  const orderRef = db.collection('customer_orders').doc(String(orderId));
  let bonusAppliedAmount = 0;
  let transitionedToPaid = false;
  let transitionedToFailed = false;

  await db.runTransaction(async (tx) => {
    const paymentSnap = await tx.get(paymentRef);
    const orderSnap = await tx.get(orderRef);

    if (!paymentSnap.exists || !orderSnap.exists) {
      throw new HttpsError('not-found', 'Order/payment not found');
    }

    const order = orderSnap.data();
    bonusAppliedAmount = Math.max(0, Number(order?.bonusAppliedAmount || 0));
    const previousPaymentStatus = String(
      paymentSnap.data()?.status || order?.paymentStatus || '',
    ).toLowerCase();
    transitionedToPaid = approved && previousPaymentStatus !== 'paid';
    transitionedToFailed = !approved && previousPaymentStatus !== 'failed';

    tx.update(paymentRef, {
      status: approved ? 'paid' : 'failed',
      reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
      reviewedBy: request.auth.uid,
      reviewNote: note || null,
      paidAt: approved ? admin.firestore.FieldValue.serverTimestamp() : null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    });

    tx.update(orderRef, {
      paymentStatus: approved ? 'paid' : 'failed',
      orderStatus: approved ? 'pending_assignment' : 'canceled',
      status: approved ? 'pending' : 'canceled',
      time: approved && order.time === 'Ожидает оплаты' ? 'Ожидает выбора даты' : order.time,
      reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
      reviewedBy: request.auth.uid,
      reviewNote: note || null,
      paidAt: approved ? admin.firestore.FieldValue.serverTimestamp() : null,
      bonusSettledAt: approved && bonusAppliedAmount > 0
        ? admin.firestore.FieldValue.serverTimestamp()
        : null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    });
  });

  if (approved) {
    await ensureSubscriptionForOrder(String(orderId));
    await applyPaidOrderUserMetrics(String(orderId));
    await awardStartupPackageBonusInternal(String(orderId));
    await applyReferralPaymentBonusInternal(String(orderId));
    if (transitionedToPaid) {
      await notifyPaymentConfirmed(String(orderId));
    }
  } else if (bonusAppliedAmount > 0) {
    await releaseReservedBonusForOrderInternal(String(orderId), 'manual_payment_declined');
  }

  if (!approved && transitionedToFailed) {
    await notifyPaymentRejected(String(orderId), note || null);
  }

  return {ok: true};
});

exports.syncPaymentStatus = callable(async (request) => {
  const {orderId} = request.data || {};
  if (!request.auth || !orderId) {
    throw new HttpsError('invalid-argument', 'orderId required');
  }

  const paymentRef = db.collection('payments').doc(orderId);
  const paymentSnap = await paymentRef.get();
  if (!paymentSnap.exists) {
    throw new HttpsError('not-found', 'Payment not found');
  }

  const payment = paymentSnap.data();
  if (payment.customerId !== request.auth.uid && !isAdminAuth(request.auth)) {
    throw new HttpsError('permission-denied', 'No access');
  }

  if (!payment.invoiceId) {
    throw new HttpsError('failed-precondition', 'Invoice ID not found');
  }

  const statusResult = await epayCheckInvoice(String(payment.invoiceId));

  const paymentDecision = await applyPaymentStatus(orderId, statusResult);

  return {ok: true, status: statusResult, decision: paymentDecision};
});

exports.epayWebhook = onRequest(async (req, res) => {
  try {
    if (req.method !== 'POST') {
      res.status(405).json({ok: false, error: 'method-not-allowed'});
      return;
    }
    if (EPAY_WEBHOOK_TOKEN) {
      const token =
        req.headers['x-webhook-token'] ||
        req.query.token ||
        req.body?.token;
      if (token !== EPAY_WEBHOOK_TOKEN) {
        res.status(403).json({ok: false, error: 'forbidden'});
        return;
      }
    }

    const orderId =
      req.body?.orderId ||
      req.body?.order_id ||
      req.body?.invoice_id ||
      req.body?.invoiceId;
    if (!orderId) {
      res.status(400).json({ok: false, error: 'orderId is required'});
      return;
    }

    const statusResult = req.body?.statusResult || req.body || {};
    const result = await applyPaymentStatus(String(orderId), statusResult, req.body?.transactionId || null);
    res.json({ok: true, ...result});
  } catch (error) {
    res.status(500).json({ok: false, error: String(error)});
  }
});

exports.bccPaymentWebhook = onRequest(async (req, res) => {
  try {
    if (!['GET', 'POST'].includes(req.method)) {
      res.status(405).json({ok: false, error: 'method-not-allowed'});
      return;
    }
    const payload = req.method === 'GET' ? req.query : req.body || {};
    const bccOrderId = String(payload.ORDER || payload.order || '').trim();
    let orderId = String(
      payload.orderId ||
      payload.order_id ||
      payload.DOMLY_ORDER_ID ||
      ''
    ).trim();
    if (!orderId && bccOrderId) {
      const snap = await db.collection('payments')
        .where('bccOrderId', '==', bccOrderId)
        .limit(1)
        .get();
      if (!snap.empty) {
        orderId = snap.docs[0].id;
      }
    }
    if (!orderId) {
      res.status(400).json({ok: false, error: 'orderId is required'});
      return;
    }
    const result = await applyPaymentStatus(orderId, payload, payload.INT_REF || payload.RRN || null);
    res.json({ok: true, ...result});
  } catch (error) {
    res.status(500).json({ok: false, error: String(error)});
  }
});

exports.seedFirestore = onRequest(async (req, res) => {
  try {
    if (req.method !== 'POST') {
      res.status(405).json({ok: false, error: 'method-not-allowed'});
      return;
    }
    if (SEED_TOKEN) {
      const token =
        req.headers['x-seed-token'] ||
        req.query.token ||
        req.body?.token;
      if (token !== SEED_TOKEN) {
        res.status(403).json({ok: false, error: 'forbidden'});
        return;
      }
    }
    await applySeedPayload(req.body || {});
    res.json({ok: true});
  } catch (error) {
    res.status(500).json({ok: false, error: String(error)});
  }
});

exports.acceptOrderOffer = callable(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError('unauthenticated', 'Authentication required');
  }
  const offerId = String(request.data?.offerId || '').trim();
  if (!offerId) {
    throw new HttpsError('invalid-argument', 'offerId required');
  }
  return acceptOrderOfferInternal({
    offerId,
    cleanerId: request.auth.uid
  });
});

exports.rejectOrderOffer = callable(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError('unauthenticated', 'Authentication required');
  }
  const offerId = String(request.data?.offerId || '').trim();
  if (!offerId) {
    throw new HttpsError('invalid-argument', 'offerId required');
  }
  return rejectOrderOfferInternal({
    offerId,
    cleanerId: request.auth.uid,
    reason: 'rejected'
  });
});

exports.assignCleaner = callable(async (request) => {
  assertAdmin(request.auth);

  const {orderId, cleanerId, cleanerName, scheduledDate, time, address, scopeType} = request.data || {};
  if (!orderId || !cleanerId || !cleanerName) {
    throw new HttpsError('invalid-argument', 'orderId, cleanerId, cleanerName required');
  }

  if (String(scopeType || '').trim() === 'schedule_slot') {
    await assignScheduleSlotInternal({
      slotId: orderId,
      cleanerId,
      cleanerName
    });
  } else {
    await assignCleanerInternal({
      orderId,
      cleanerId,
      cleanerName,
      scheduledDate,
      time,
      address
    });
  }

  return {ok: true};
});

exports.estimateCleaningDuration = callable(async (request) => {
  assertAdmin(request.auth);
  const area = Number(request.data?.area || 0);
  const policies = await getPolicyConfig();
  return {
    ok: true,
    area,
    estimatedHours: estimateCleaningDuration(area, policies),
    estimatedMinutes: estimateCleaningDurationMinutes(area, policies)
  };
});

exports.calculateCleanerFairnessScore = callable(async (request) => {
  assertAdmin(request.auth);
  const orderId = request.data?.orderId || null;
  const cleanerId = request.data?.cleanerId || null;
  if (!orderId || !cleanerId) {
    throw new HttpsError('invalid-argument', 'orderId and cleanerId required');
  }

  const [orderSnap, cleanerSnap] = await Promise.all([
    db.collection('customer_orders').doc(orderId).get(),
    db.collection('cleaners').doc(cleanerId).get()
  ]);
  if (!orderSnap.exists) {
    throw new HttpsError('not-found', 'Order not found');
  }
  if (!cleanerSnap.exists) {
    throw new HttpsError('not-found', 'Cleaner not found');
  }

  const order = {id: orderSnap.id, ...orderSnap.data()};
  const cleaner = {id: cleanerSnap.id, ...cleanerSnap.data()};
  const cluster = await detectClusterForOrder(order);
  const referenceDate = normalizeOrderDate(order.date || new Date());
  const monthStats = await getCleanerMonthlyStats(cleanerId, referenceDate);
  const dayAssignments = await getCleanerDayAssignments(cleanerId, referenceDate);
  const peersSnap = await db.collection('cleaners')
    .where('clusterName', '==', cluster?.name || cleaner.clusterName || '')
    .where('verificationStatus', '==', 'approved')
    .limit(20)
    .get();
  const peers = peersSnap.docs.map((doc) => doc.id);
  const peerStats = await Promise.all(peers.map((id) => getCleanerMonthlyStats(id, referenceDate)));
  const monthlyTargets = peerStats.reduce((acc, item) => {
    acc.area += item.area;
    acc.hours += item.hours;
    acc.income += item.income;
    acc.apartments += item.apartments;
    return acc;
  }, {area: 0, hours: 0, income: 0, apartments: 0});
  monthlyTargets.area /= Math.max(peerStats.length, 1);
  monthlyTargets.hours /= Math.max(peerStats.length, 1);
  monthlyTargets.income /= Math.max(peerStats.length, 1);
  monthlyTargets.apartments /= Math.max(peerStats.length, 1);

  return {
    ok: true,
    score: calculateCleanerFairnessScore({
      cleaner,
      order,
      monthStats,
      monthlyTargets,
      dayAssignments,
      cluster,
      entrance: order.entrance || null
    })
  };
});

exports.calculateDailySchedule = callable(async (request) => {
  const {cleanerId, date} = request.data || {};
  if (!request.auth || !cleanerId || !date) {
    throw new HttpsError('invalid-argument', 'cleanerId and date required');
  }
  if (request.auth.uid !== cleanerId && !isAdminAuth(request.auth)) {
    throw new HttpsError('permission-denied', 'No access to cleaner schedule');
  }
  return calculateDailyScheduleInternal(String(cleanerId), String(date));
});

exports.recalculateScheduleAfterAddon = callable(async (request) => {
  const {orderId} = request.data || {};
  if (!request.auth || !orderId) {
    throw new HttpsError('invalid-argument', 'orderId required');
  }
  const orderSnap = await db.collection('customer_orders').doc(String(orderId)).get();
  if (!orderSnap.exists) {
    throw new HttpsError('not-found', 'Order not found');
  }
  const order = orderSnap.data() || {};
  if (request.auth.uid !== String(order.customerId || '') && !isAdminAuth(request.auth)) {
    throw new HttpsError('permission-denied', 'No access to this order');
  }
  return recalculateScheduleAfterAddonInternal(String(orderId));
});

exports.notifyClientDelay = callable(async (request) => {
  const {orderId, mode, minutes, customBody} = request.data || {};
  if (!request.auth || !orderId) {
    throw new HttpsError('invalid-argument', 'orderId required');
  }
  const orderSnap = await db.collection('customer_orders').doc(String(orderId)).get();
  if (!orderSnap.exists) {
    throw new HttpsError('not-found', 'Order not found');
  }
  const order = orderSnap.data() || {};
  const isCleaner = request.auth.uid === String(order.cleanerId || '');
  if (!isCleaner && !isAdminAuth(request.auth)) {
    throw new HttpsError('permission-denied', 'No access to this order');
  }
  return notifyClientDelayInternal({
    orderId: String(orderId),
    mode: String(mode || 'delay'),
    minutes: Number(minutes || 0),
    customBody: customBody ? String(customBody) : null
  });
});

exports.notifyCleanerUpdate = callable(async (request) => {
  const {orderId, customBody, type} = request.data || {};
  if (!request.auth || !orderId) {
    throw new HttpsError('invalid-argument', 'orderId required');
  }
  const orderSnap = await db.collection('customer_orders').doc(String(orderId)).get();
  if (!orderSnap.exists) {
    throw new HttpsError('not-found', 'Order not found');
  }
  const order = orderSnap.data() || {};
  const isCustomer = request.auth.uid === String(order.customerId || '');
  if (!isCustomer && !isAdminAuth(request.auth)) {
    throw new HttpsError('permission-denied', 'No access to this order');
  }
  return notifyCleanerUpdateInternal({
    orderId: String(orderId),
    customBody: customBody ? String(customBody) : null,
    type: type ? String(type) : 'schedule_update'
  });
});

exports.assignOrdersForDay = callable(async (request) => {
  assertAdmin(request.auth);
  const targetDate = request.data?.date || toIsoDate(new Date());
  return assignOrdersForDayInternal(targetDate);
});

exports.rebalanceAssignments = callable(async (request) => {
  assertAdmin(request.auth);
  const targetDate = request.data?.date || toIsoDate(new Date());
  return rebalanceAssignmentsInternal(targetDate);
});

exports.getAvailableDates = callable(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication required');
  }
  const subscriptionId = String(request.data?.subscriptionId || '');
  const month = request.data?.month ? String(request.data.month) : null;
  if (!subscriptionId) {
    throw new HttpsError('invalid-argument', 'subscriptionId required');
  }
  return getAvailableDatesInternal({
    subscriptionId,
    uid: request.auth.uid,
    month
  });
});

exports.getAvailableSlots = callable(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication required');
  }
  const subscriptionId = String(request.data?.subscriptionId || '');
  const date = String(request.data?.date || '');
  if (!subscriptionId || !date) {
    throw new HttpsError('invalid-argument', 'subscriptionId and date required');
  }
  return getAvailableSlotsInternal({
    subscriptionId,
    uid: request.auth.uid,
    date
  });
});

exports.bookSchedule = callable(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication required');
  }
  const subscriptionId = String(request.data?.subscriptionId || '');
  const selections = Array.isArray(request.data?.selections) ? request.data.selections : [];
  if (!subscriptionId) {
    throw new HttpsError('invalid-argument', 'subscriptionId required');
  }
  return bookScheduleInternal({
    subscriptionId,
    uid: request.auth.uid,
    selections
  });
});

exports.reschedule = callable(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication required');
  }
  const slotId = String(request.data?.slotId || '');
  const date = String(request.data?.date || '');
  const time = String(request.data?.time || '');
  if (!slotId || !date || !time) {
    throw new HttpsError('invalid-argument', 'slotId, date and time required');
  }
  return rescheduleInternal({
    slotId,
    uid: request.auth.uid,
    date,
    time
  });
});

exports.updateScheduledCleaning = callable(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication required');
  }
  return updateScheduledCleaningInternal({
    slotId: String(request.data?.slotId || ''),
    uid: request.auth.uid,
    date: request.data?.date ? String(request.data.date) : null,
    time: request.data?.time ? String(request.data.time) : null,
    addonsDetailed: request.data?.addonsDetailed ?? null
  });
});

exports.submitCleanerAddonRequest = callable(async (request) => {
  const {slotId, addonsDetailed, note} = request.data || {};
  if (!request.auth || !slotId) {
    throw new HttpsError('invalid-argument', 'slotId required');
  }
  const normalizedAddons = normalizeDetailedAddons(addonsDetailed);
  if (normalizedAddons.length === 0) {
    throw new HttpsError('invalid-argument', 'Select at least one addon');
  }
  const slotSnap = await db.collection('schedule_slots').doc(String(slotId)).get();
  if (!slotSnap.exists) {
    throw new HttpsError('not-found', 'Slot not found');
  }
  const slot = {id: slotSnap.id, ...slotSnap.data()};
  if (String(slot.cleanerId || '') !== request.auth.uid) {
    throw new HttpsError('permission-denied', 'No access to this slot');
  }
  const status = String(slot.status || '').toLowerCase();
  if (!['assigned', 'confirmed', 'in_progress'].includes(status)) {
    throw new HttpsError('failed-precondition', 'Addon request is available only for active assigned cleaning');
  }
  const pricingSnap = await db.collection('pricing').doc('default').get();
  const pricing = pricingSnap.data() || {};
  const detailedAddonPricing = calculateDetailedAddonPricing(pricing, normalizedAddons);
  const amount = Math.max(
    0,
    Number(detailedAddonPricing.billableTotal || 0) +
      Number(detailedAddonPricing.separatePaymentTotal || 0)
  );
  if (amount <= 0) {
    throw new HttpsError('failed-precondition', 'Selected addons have no billable amount');
  }
  const requestRef = db.collection('addon_requests').doc();
  const labels = normalizedAddons.map((item) => {
    const label = String(item.label || item.key || '').trim();
    const quantity = Math.max(1, Number(item.quantity || 1));
    return quantity > 1 ? `${label} × ${quantity}` : label;
  }).filter(Boolean);
  await requestRef.set({
    slotId: slotSnap.id,
    sourceOrderId: slot.sourceOrderId || slot.customerOrderId || null,
    customerId: slot.customerId || null,
    cleanerId: request.auth.uid,
    cleanerName: slot.cleanerName || null,
    customerName: slot.customerName || null,
    customerPhone: slot.customerPhone || null,
    address: slot.address || null,
    package: slot.package || null,
    addons: labels,
    addonsDetailed: normalizedAddons,
    amount,
    addonsSeparatePaymentTotal: detailedAddonPricing.separatePaymentTotal,
    separatePaymentAddons: detailedAddonPricing.separatePaymentAddons,
    note: String(note || '').trim() || null,
    status: 'pending_customer',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  });
  if (slot.customerId) {
    await sendPushToUser(
      String(slot.customerId),
      'Уборщица предложила доп. услуги',
      labels.length ? labels.join(', ') : 'Проверьте предложение по текущей уборке.',
      {type: 'addon_request', orderId: slotSnap.id, addonRequestId: requestRef.id}
    ).catch(() => {});
  }
  return {ok: true, addonRequestId: requestRef.id, amount};
});

exports.approveCleanerAddonRequest = callable(async (request) => {
  const {requestId, kaspiPhone, paymentMethod = 'kaspi', bonusToSpend = 0} = request.data || {};
  const normalizedPaymentMethod = String(paymentMethod || 'kaspi').trim().toLowerCase();
  if (!request.auth || !requestId) {
    throw new HttpsError('invalid-argument', 'requestId required');
  }
  if (!['online', 'bonus'].includes(normalizedPaymentMethod) && !kaspiPhone) {
    throw new HttpsError('invalid-argument', 'kaspiPhone required');
  }
  const requestRef = db.collection('addon_requests').doc(String(requestId));
  const requestSnap = await requestRef.get();
  if (!requestSnap.exists) {
    throw new HttpsError('not-found', 'Addon request not found');
  }
  const addonRequest = {id: requestSnap.id, ...requestSnap.data()};
  if (String(addonRequest.customerId || '') !== request.auth.uid) {
    throw new HttpsError('permission-denied', 'Not your addon request');
  }
  if (String(addonRequest.status || '') !== 'pending_customer') {
    throw new HttpsError('failed-precondition', 'Addon request is not waiting customer approval');
  }
  const paymentId = `addon_${requestSnap.id}`;
  const addonBonusSpendPercent = await getAddonBonusSpendPercent();
  let paidByBonusOnly = false;
  let bonusAppliedAmount = 0;
  await db.runTransaction(async (tx) => {
    const baseAmount = Math.max(0, Number(addonRequest.amount || 0));
    const requestedBonusAmount = Math.max(0, Number(bonusToSpend || 0));
    const maxBonusPaymentAmount = Math.floor(
      baseAmount * (addonBonusSpendPercent / 100)
    );
    bonusAppliedAmount = 0;
    if (requestedBonusAmount > 0) {
      const customerRef = db.collection('customers').doc(String(addonRequest.customerId || request.auth.uid));
      const customerSnap = await tx.get(customerRef);
      const availableBonusPoints = Math.max(0, Number(customerSnap.data()?.bonusPoints || 0));
      bonusAppliedAmount = Math.min(
        requestedBonusAmount,
        availableBonusPoints,
        maxBonusPaymentAmount
      );
      if (bonusAppliedAmount <= 0) {
        throw new HttpsError(
          'failed-precondition',
          `Недостаточно бонусов или превышен лимит списания ${addonBonusSpendPercent}%.`
        );
      }
      tx.set(customerRef, {
        bonusPoints: availableBonusPoints - bonusAppliedAmount,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      }, {merge: true});
    }
    const finalAmount = Math.max(baseAmount - bonusAppliedAmount, 0);
    paidByBonusOnly = normalizedPaymentMethod === 'bonus' && finalAmount === 0;
    tx.set(requestRef, {
      status: paidByBonusOnly ? 'payment_confirmed' : 'invoice_requested',
      paymentStatus: paidByBonusOnly ? 'paid' : 'invoice_requested',
      paymentId,
      paymentMethod: normalizedPaymentMethod,
      kaspiPhone: kaspiPhone ? String(kaspiPhone).trim() : null,
      originalAddonAmount: baseAmount,
      amount: finalAmount,
      price: finalAmount,
      bonusToSpend: requestedBonusAmount,
      bonusAppliedAmount,
      maxBonusPaymentPercent: addonBonusSpendPercent,
      maxBonusPaymentAmount,
      bonusProgram: bonusAppliedAmount > 0 ? 'package_addons_50_percent' : null,
      bonusReservedAt: bonusAppliedAmount > 0
        ? admin.firestore.FieldValue.serverTimestamp()
        : null,
      paidAt: paidByBonusOnly ? admin.firestore.FieldValue.serverTimestamp() : null,
      bonusSettledAt: paidByBonusOnly && bonusAppliedAmount > 0
        ? admin.firestore.FieldValue.serverTimestamp()
        : null,
      approvedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});
    tx.set(db.collection('payments').doc(paymentId), {
      id: paymentId,
      orderId: paymentId,
      type: 'addon_request',
      addonRequestId: requestSnap.id,
      slotId: addonRequest.slotId || null,
      sourceOrderId: addonRequest.sourceOrderId || null,
      customerId: addonRequest.customerId || null,
      cleanerId: addonRequest.cleanerId || null,
      status: paidByBonusOnly ? 'paid' : 'invoice_requested',
      paymentStatus: paidByBonusOnly ? 'paid' : 'invoice_requested',
      provider: normalizedPaymentMethod === 'online'
        ? 'bcc_ecommerce_webview'
        : normalizedPaymentMethod === 'bonus'
          ? 'bonus'
          : 'kaspi_manual_request',
      kaspiPhone: kaspiPhone ? String(kaspiPhone).trim() : null,
      originalAddonAmount: baseAmount,
      amount: finalAmount,
      price: finalAmount,
      bonusToSpend: requestedBonusAmount,
      bonusAppliedAmount,
      maxBonusPaymentPercent: addonBonusSpendPercent,
      maxBonusPaymentAmount,
      bonusProgram: bonusAppliedAmount > 0 ? 'package_addons_50_percent' : null,
      bonusReservedAt: bonusAppliedAmount > 0
        ? admin.firestore.FieldValue.serverTimestamp()
        : null,
      paidAt: paidByBonusOnly ? admin.firestore.FieldValue.serverTimestamp() : null,
      bonusSettledAt: paidByBonusOnly && bonusAppliedAmount > 0
        ? admin.firestore.FieldValue.serverTimestamp()
        : null,
      currency: 'KZT',
      packageName: 'Доп. услуги по текущей уборке',
      frequencyLabel: 'Согласование клиента',
      addons: Array.isArray(addonRequest.addons) ? addonRequest.addons : [],
      addonsDetailed: normalizeDetailedAddons(addonRequest.addonsDetailed),
      addonsSeparatePaymentTotal: Number(addonRequest.addonsSeparatePaymentTotal || 0),
      separatePaymentAddons: Array.isArray(addonRequest.separatePaymentAddons)
        ? addonRequest.separatePaymentAddons
        : [],
      customerName: addonRequest.customerName || null,
      customerPhone: addonRequest.customerPhone || null,
      address: addonRequest.address || null,
      invoiceRequestedAt: admin.firestore.FieldValue.serverTimestamp(),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});
  });
  if (bonusAppliedAmount > 0) {
    await recordCustomerBonusTransaction({
      userId: addonRequest.customerId,
      amount: -bonusAppliedAmount,
      title: 'Оплата бонусами',
      reason: 'Списано за доп. услуги к уборке',
      type: 'bonus_debit',
      orderId: paymentId
    });
  }
  if (paidByBonusOnly) {
    await applyAddonRequestToSlot(requestSnap.id, 'bonus_payment');
  }
  return {ok: true, paymentId};
});

exports.rejectCleanerAddonRequest = callable(async (request) => {
  const {requestId} = request.data || {};
  if (!request.auth || !requestId) {
    throw new HttpsError('invalid-argument', 'requestId required');
  }
  const requestRef = db.collection('addon_requests').doc(String(requestId));
  const requestSnap = await requestRef.get();
  if (!requestSnap.exists) {
    throw new HttpsError('not-found', 'Addon request not found');
  }
  const addonRequest = requestSnap.data() || {};
  if (String(addonRequest.customerId || '') !== request.auth.uid) {
    throw new HttpsError('permission-denied', 'Not your addon request');
  }
  if (String(addonRequest.status || '') !== 'pending_customer') {
    throw new HttpsError('failed-precondition', 'Addon request is not waiting customer approval');
  }
  await requestRef.set({
    status: 'rejected_by_customer',
    rejectedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, {merge: true});
  if (addonRequest.cleanerId) {
    await sendPushToUser(
      String(addonRequest.cleanerId),
      'Клиент отклонил доп. услуги',
      'Предложение по доп. услугам отклонено.',
      {type: 'addon_request_rejected', orderId: String(addonRequest.slotId || '')}
    ).catch(() => {});
  }
  return {ok: true};
});

exports.advanceOrderStatus = callable(async (request) => {
  const {orderId, toStatus} = request.data || {};
  if (!request.auth || !orderId || !toStatus) {
    throw new HttpsError('invalid-argument', 'orderId and toStatus required');
  }

  await advanceOrderStatusInternal({
    orderId,
    toStatus,
    uid: request.auth.uid,
    adminMode: isAdminAuth(request.auth)
  });

  return {ok: true};
});

exports.confirmCleaningStart = callable(async (request) => {
  const {orderId, confirmed} = request.data || {};
  if (!request.auth || !orderId || typeof confirmed !== 'boolean') {
    throw new HttpsError('invalid-argument', 'orderId and confirmed required');
  }

  await confirmCleaningStartInternal({
    orderId: String(orderId),
    confirmed,
    uid: request.auth.uid
  });

  return {ok: true};
});

exports.getHouseStats = callable(async (request) => {
  const {houseId} = request.data || {};
  if (!request.auth || !houseId) {
    throw new HttpsError('invalid-argument', 'houseId required');
  }
  return getHouseStatsInternal(houseId);
});

exports.joinWaitlist = callable(async (request) => {
  const {houseId, source} = request.data || {};
  if (!request.auth || !houseId) {
    throw new HttpsError('invalid-argument', 'houseId required');
  }
  return joinWaitlistInternal(request.auth.uid, houseId, source || 'app');
});

exports.requestServiceAddress = callable(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Login required');
  }
  return requestServiceAddressInternal(request.auth.uid, request.data || {});
});

exports.inviteNeighbors = callable(async (request) => {
  const {houseId, invitedPhone} = request.data || {};
  if (!request.auth || !houseId) {
    throw new HttpsError('invalid-argument', 'houseId required');
  }
  return inviteNeighborsInternal(request.auth.uid, houseId, invitedPhone || null);
});

exports.activateHouseIfThresholdReached = callable(async (request) => {
  assertAdmin(request.auth);
  const {houseId} = request.data || {};
  if (!houseId) {
    throw new HttpsError('invalid-argument', 'houseId required');
  }
  const status = await activateHouseIfThresholdReachedInternal(houseId);
  return {ok: true, status};
});

exports.importHousesForServiceZone = callable(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication required');
  }
  return importHousesForServiceZoneInternal({
    zoneId: String(request.data?.zoneId || ''),
    auth: request.auth
  });
});

function assertDebugBridgeUid(debugUid) {
  const normalized = String(debugUid || '').trim();
  if (!['customer_demo', 'admin_demo'].includes(normalized)) {
    throw new HttpsError('permission-denied', 'Debug bridge access denied');
  }
  return normalized;
}

exports.submitSharedDebugComplaint = callable(async (request) => {
  const debugUid = assertDebugBridgeUid(request.data?.debugUid);
  const orderId = String(request.data?.orderId || '').trim();
  const customerId = String(request.data?.customerId || debugUid).trim();
  const text = String(request.data?.text || '').trim();
  const photoUrl = request.data?.photoUrl ? String(request.data.photoUrl) : null;
  const photoUrls = Array.isArray(request.data?.photoUrls) ?
    request.data.photoUrls.map((item) => String(item || '').trim()).filter(Boolean).slice(0, 5) :
    [];
  if (!orderId || !text) {
    throw new HttpsError('invalid-argument', 'orderId and text required');
  }
  const docRef = db.collection('debug_bridge_complaints').doc();
  await docRef.set({
    orderId,
    customerId,
    text,
    photoUrl,
    photoUrls,
    status: 'open',
    sourceDebugUid: debugUid,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return {ok: true, id: docRef.id};
});

exports.getSharedDebugComplaints = callable(async (request) => {
  assertDebugBridgeUid(request.data?.debugUid);
  const snap = await db
    .collection('debug_bridge_complaints')
    .orderBy('createdAt', 'desc')
    .limit(20)
    .get();
  return {
    ok: true,
    items: snap.docs.map((doc) => ({id: doc.id, ...doc.data()})),
  };
});

exports.submitSharedDebugReview = callable(async (request) => {
  const debugUid = assertDebugBridgeUid(request.data?.debugUid);
  const orderId = String(request.data?.orderId || '').trim();
  const rating = Number(request.data?.rating || 0);
  const text = String(request.data?.text || '').trim();
  const positiveTraits = Array.isArray(request.data?.positiveTraits) ?
    request.data.positiveTraits.map((item) => String(item || '').trim()).filter(Boolean) :
    [];
  const negativeTraits = Array.isArray(request.data?.negativeTraits) ?
    request.data.negativeTraits.map((item) => String(item || '').trim()).filter(Boolean) :
    [];
  const photoUrl = request.data?.photoUrl ? String(request.data.photoUrl) : null;
  if (!orderId || !text || !rating) {
    throw new HttpsError('invalid-argument', 'orderId, rating and text required');
  }
  await db.collection('debug_bridge_reviews').doc(orderId).set({
    orderId,
    customerId: debugUid,
    rating,
    text,
    positiveTraits,
    negativeTraits,
    photoUrl,
    sourceDebugUid: debugUid,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
  return {ok: true, id: orderId};
});

async function submitCustomerReviewInternal({orderId, cleanerId, rating, text = ''}) {
  const normalizedOrderId = String(orderId || '').trim();
  const normalizedCleanerId = String(cleanerId || '').trim();
  const normalizedRating = Math.round(Number(rating || 0));
  if (!normalizedOrderId || !normalizedCleanerId || normalizedRating < 1 || normalizedRating > 5) {
    throw new HttpsError('invalid-argument', 'orderId, cleanerId and rating 1..5 required');
  }

  let orderSnap = await db.collection('customer_orders').doc(normalizedOrderId).get();
  let order = orderSnap.exists ? (orderSnap.data() || {}) : null;
  if (!order) {
    orderSnap = await db.collection('schedule_slots').doc(normalizedOrderId).get();
    order = orderSnap.exists ? (orderSnap.data() || {}) : null;
  }
  if (!order) {
    const slotSnap = await db.collection('schedule_slots')
      .where('sourceOrderId', '==', normalizedOrderId)
      .limit(1)
      .get();
    if (!slotSnap.empty) {
      order = slotSnap.docs[0].data() || {};
    }
  }
  if (!order) {
    throw new HttpsError('not-found', 'Order not found');
  }
  if (String(order.cleanerId || '').trim() && String(order.cleanerId).trim() !== normalizedCleanerId) {
    throw new HttpsError('permission-denied', 'Cleaner cannot review this customer');
  }
  const customerId = String(order.customerId || order.userId || '').trim();
  if (!customerId) {
    throw new HttpsError('failed-precondition', 'Order has no customerId');
  }

  const reviewId = `${normalizedOrderId}_${normalizedCleanerId}`;
  await db.collection('customer_reviews').doc(reviewId).set({
    id: reviewId,
    orderId: normalizedOrderId,
    customerId,
    cleanerId: normalizedCleanerId,
    rating: normalizedRating,
    text: String(text || '').trim().slice(0, 500),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, {merge: true});

  const reviewsSnap = await db.collection('customer_reviews')
    .where('customerId', '==', customerId)
    .get();
  let sum = 0;
  let count = 0;
  const counts = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
  for (const doc of reviewsSnap.docs) {
    const value = Math.round(Number((doc.data() || {}).rating || 0));
    if (value >= 1 && value <= 5) {
      sum += value;
      count += 1;
      counts[value] += 1;
    }
  }
  const average = count > 0 ? Number((sum / count).toFixed(1)) : 5.0;
  await db.collection('customers').doc(customerId).set({
    rating: average,
    customerRating: average,
    customerRatingCount: count,
    customerRating5Count: counts[5],
    customerRating4Count: counts[4],
    customerRating3Count: counts[3],
    customerRating2Count: counts[2],
    customerRating1Count: counts[1],
    ratingUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, {merge: true});

  return {ok: true, reviewId, customerId, rating: average, ratingCount: count};
}

exports.submitCustomerReview = callable(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication required');
  }
  return submitCustomerReviewInternal({
    orderId: request.data?.orderId,
    cleanerId: request.auth.uid,
    rating: request.data?.rating,
    text: request.data?.text || ''
  });
});

exports.getSharedDebugReviews = callable(async (request) => {
  assertDebugBridgeUid(request.data?.debugUid);
  const snap = await db
    .collection('debug_bridge_reviews')
    .orderBy('createdAt', 'desc')
    .limit(20)
    .get();
  return {
    ok: true,
    items: snap.docs.map((doc) => ({id: doc.id, ...doc.data()})),
  };
});

exports.createOrOpenOrderChat = callable(async (request) => {
  const {orderId} = request.data || {};
  if (!request.auth || !orderId) {
    throw new HttpsError('invalid-argument', 'orderId required');
  }
  const chat = await ensureOrderChat(orderId);
  const chatSnap = await db.collection('order_chats').doc(chat.chatId || chat.orderId).get();
  const chatData = chatSnap.data() || {};
  if (!chatUserHasAccess(chatData, request.auth.uid, request.auth)) {
    throw new HttpsError('permission-denied', 'No access to this chat');
  }
  return chat;
});

exports.createOrOpenComplaintChat = callable(async (request) => {
  assertBackoffice(request.auth);
  const {complaintId} = request.data || {};
  return ensureComplaintChat(complaintId, request.auth.uid);
});

exports.sendChatMessage = callable(async (request) => {
  const {orderId, text, senderRole, type} = request.data || {};
  if (!request.auth || !orderId || !text) {
    throw new HttpsError('invalid-argument', 'orderId and text required');
  }
  return sendChatMessageInternal({
    orderId,
    senderId: request.auth.uid,
    senderRole: senderRole || 'user',
    text,
    type: type || 'text',
    auth: request.auth
  });
});

exports.markChatAsRead = callable(async (request) => {
  const {orderId} = request.data || {};
  if (!request.auth || !orderId) {
    throw new HttpsError('invalid-argument', 'orderId required');
  }
  return markChatAsReadInternal({
    orderId,
    userId: request.auth.uid
  });
});

exports.getChatMessages = callable(async (request) => {
  const {orderId} = request.data || {};
  if (!request.auth || !orderId) {
    throw new HttpsError('invalid-argument', 'orderId required');
  }
  return getChatMessagesInternal({
    orderId,
    userId: request.auth.uid,
    auth: request.auth
  });
});

exports.submitCleanerVerification = callable(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication required');
  }
  return submitCleanerVerificationInternal({
    cleanerId: request.auth.uid,
    payload: request.data || {}
  });
});

exports.reviewCleanerVerification = callable(async (request) => {
  assertBackoffice(request.auth);
  const {cleanerId, status, rejectionReason} = request.data || {};
  if (!cleanerId || !status) {
    throw new HttpsError('invalid-argument', 'cleanerId and status required');
  }
  return reviewCleanerVerificationInternal({
    cleanerId,
    status,
    rejectionReason: rejectionReason || null,
    reviewedBy: request.auth.uid
  });
});

exports.calculateUserTier = callable(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication required');
  }
  const userId = isAdminAuth(request.auth) && request.data?.userId
    ? String(request.data.userId)
    : request.auth.uid;
  const progress = await calculateUserTierInternal(userId);
  return {ok: true, ...progress};
});

exports.getUserProgress = callable(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication required');
  }
  const userId = isAdminAuth(request.auth) && request.data?.userId
    ? String(request.data.userId)
    : request.auth.uid;
  const progress = await getUserProgressInternal(userId);
  return {ok: true, ...progress};
});

exports.getReferralStats = callable(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication required');
  }
  const userId = isAdminAuth(request.auth) && request.data?.userId
    ? String(request.data.userId)
    : request.auth.uid;
  const stats = await recalculateReferralStatsInternal(userId);
  return {ok: true, ...stats};
});

exports.ensureReferralLink = callable(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication required');
  }
  return ensureReferralLinkInternal(request.auth.uid);
});

exports.uploadUserImage = callable(async (request) => {
  const folder = String(request.data?.folder || '').trim();
  const filePrefix = String(request.data?.filePrefix || 'image')
    .trim()
    .replace(/[^a-zA-Z0-9_-]/g, '_')
    .slice(0, 48) || 'image';
  const base64 = String(request.data?.base64 || '').trim();
  const contentType = String(request.data?.contentType || 'image/jpeg').trim();
  const allowedFolder = folder === 'promo_banners'
    || folder === 'promotion_home_banners'
    || /^(complaints|reviews|photo_reports)\/[a-zA-Z0-9_-]{1,160}$/.test(folder);
  if (!allowedFolder) {
    throw new HttpsError('invalid-argument', 'Unsupported upload folder');
  }
  if (!contentType.startsWith('image/')) {
    throw new HttpsError('invalid-argument', 'Only image uploads are allowed');
  }
  if (!base64) {
    throw new HttpsError('invalid-argument', 'Image data required');
  }
  const buffer = Buffer.from(base64, 'base64');
  if (!buffer.length || buffer.length > 10 * 1024 * 1024) {
    throw new HttpsError('invalid-argument', 'Image must be less than 10 MB');
  }

  const extension = contentType.includes('png') ? 'png' : 'jpg';
  const token = crypto.randomUUID();
  const fileName = `${filePrefix}-${Date.now()}-${crypto.randomUUID()}.${extension}`;
  const path = `${folder}/${fileName}`;
  const bucket = admin.storage().bucket();
  const file = bucket.file(path);
  await file.save(buffer, {
    resumable: false,
    metadata: {
      contentType,
      metadata: {
        firebaseStorageDownloadTokens: token,
        uploadedBy: request.auth?.uid || 'anonymous_callable',
        source: 'uploadUserImage'
      }
    }
  });
  const encodedPath = encodeURIComponent(path);
  return {
    ok: true,
    path,
    downloadUrl: `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodedPath}?alt=media&token=${token}`
  };
});

exports.updateCustomerProfile = callable(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication required');
  }
  return updateCustomerProfileInternal({
    userId: request.auth.uid,
    payload: request.data || {}
  });
});

exports.updateCleanerProfile = callable(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication required');
  }
  return updateCleanerProfileInternal({
    userId: request.auth.uid,
    payload: request.data || {}
  });
});

exports.verifyApartmentArea = callable(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication required');
  }
  const userId = isAdminAuth(request.auth) && request.data?.userId
    ? String(request.data.userId)
    : request.auth.uid;
  const actualArea = Number(request.data?.actualArea || 0);
  const areaTechnicalPlanUrl = request.data?.areaTechnicalPlanUrl
    ? String(request.data.areaTechnicalPlanUrl)
    : null;
  return verifyApartmentAreaInternal({
    userId,
    actualArea,
    areaTechnicalPlanUrl,
    actorId: request.auth.uid
  });
});

exports.requestAreaQualityCheck = callable(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication required');
  }
  const userId = isAdminAuth(request.auth) && request.data?.userId
    ? String(request.data.userId)
    : request.auth.uid;
  return requestAreaQualityCheckInternal({
    userId,
    actualArea: Number(request.data?.actualArea || 0),
    preferredDate: request.data?.preferredDate,
    preferredTime: request.data?.preferredTime,
    orderId: request.data?.orderId ? String(request.data.orderId) : null,
    actorId: request.auth.uid
  });
});

exports.getCustomPackageQuote = callable(async (request) => {
  const pricingSnap = await db.collection('pricing').doc('default').get();
  const pricing = pricingSnap.exists ? pricingSnap.data() || {} : {};
  const quote = calculateCustomPackageQuoteFromPricing({
    pricing,
    rooms: Number(request.data?.rooms || 0),
    bathrooms: Number(request.data?.bathrooms || 0),
    area: Number(request.data?.area || 0),
    frequency: Number(request.data?.frequency || 1),
    billingPeriodMonths: Number(request.data?.billingPeriodMonths || 1),
    windows: request.data?.windows === true,
    ironing: request.data?.ironing === true,
    balcony: request.data?.balcony === true,
    addonsDetailed: request.data?.addonsDetailed
  });

  return {ok: true, ...quote};
});

exports.saveCustomPackageDraft = callable(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication required');
  }

  const uid = request.auth.uid;
  const payload = request.data || {};
  const pricingSnap = await db.collection('pricing').doc('default').get();
  const pricing = pricingSnap.exists ? pricingSnap.data() || {} : {};
  const quote = calculateCustomPackageQuoteFromPricing({
    pricing,
    rooms: Number(payload.rooms || 0),
    bathrooms: Number(payload.bathrooms || 0),
    area: Number(payload.area || 0),
    frequency: Number(payload.frequency || 1),
    billingPeriodMonths: Number(payload.billingPeriodMonths || 1),
    windows: payload.windows === true,
    ironing: payload.ironing === true,
    balcony: payload.balcony === true,
    addonsDetailed: payload.addonsDetailed
  });

  const normalizedDetailedAddons = normalizeDetailedAddons(payload.addonsDetailed);

  await db.collection('customPackageDrafts').doc(uid).set({
    userId: uid,
    rooms: Number(payload.rooms || 0),
    bathrooms: Number(payload.bathrooms || 0),
    area: Number(payload.area || 0),
    frequency: Number(payload.frequency || 1),
    billingPeriodMonths: Number(payload.billingPeriodMonths || 1),
    frequencyLabel: String(payload.frequencyLabel || 'Разовая'),
    windows: payload.windows === true,
    ironing: payload.ironing === true,
    balcony: payload.balcony === true,
    addonsDetailed: normalizedDetailedAddons,
    accessMethod: String(payload.accessMethod || 'Я дома'),
    preferredDays: Array.isArray(payload.preferredDays) ? payload.preferredDays : [],
    preferredTimeRanges: Array.isArray(payload.preferredTimeRanges) ? payload.preferredTimeRanges : [],
    quote,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    createdAt: admin.firestore.FieldValue.serverTimestamp()
  }, {merge: true});

  return {ok: true, ...quote};
});

exports.evaluateCleanerStatus = callable(async (request) => {
  assertAdmin(request.auth);
  const cleanerId = request.data?.cleanerId || null;
  if (!cleanerId) {
    throw new HttpsError('invalid-argument', 'cleanerId required');
  }
  return recalculateCleanerStatusInternal(String(cleanerId));
});

exports.recalculateAllCleanerStatuses = callable(async (request) => {
  assertAdmin(request.auth);
  const snap = await db.collection('cleaners').get();
  const results = [];
  for (const doc of snap.docs) {
    results.push(await recalculateCleanerStatusInternal(doc.id, {cleanerSnap: doc}));
  }
  return {ok: true, results};
});

exports.notifyTierChange = callable(async (request) => {
  assertAdmin(request.auth);
  const {userId, payload} = request.data || {};
  if (!userId || !payload?.toTier) {
    throw new HttpsError('invalid-argument', 'userId and payload.toTier required');
  }
  await notifyTierChange(String(userId), payload);
  return {ok: true};
});

exports.resetMonthlyStats = callable(async (request) => {
  assertAdmin(request.auth);
  return resetMonthlyStatsInternal();
});

exports.userProgress = onRequest(async (req, res) => {
  try {
    if (req.method !== 'GET') {
      res.status(405).json({ok: false, error: 'method-not-allowed'});
      return;
    }
    const auth = await verifyBearerToken(req);
    const userId = auth.uid;
    const progress = await getUserProgressInternal(userId);
    res.json({ok: true, ...progress});
  } catch (error) {
    const status = error instanceof HttpsError ?
      (error.code === 'unauthenticated' ? 401 :
        error.code === 'permission-denied' ? 403 :
          error.code === 'not-found' ? 404 : 400) :
      500;
    res.status(status).json({ok: false, error: String(error.message || error)});
  }
});

exports.api = onRequest(async (req, res) => {
  try {
    if (req.method === 'GET' && req.path === '/user/progress') {
      const auth = await verifyBearerToken(req);
      const progress = await getUserProgressInternal(auth.uid);
      res.json({ok: true, ...progress});
      return;
    }
    res.status(404).json({ok: false, error: 'not-found'});
  } catch (error) {
    const status = error instanceof HttpsError ?
      (error.code === 'unauthenticated' ? 401 :
        error.code === 'permission-denied' ? 403 :
          error.code === 'not-found' ? 404 : 400) :
      500;
    res.status(status).json({ok: false, error: String(error.message || error)});
  }
});

exports.cancelScheduleSlot = callable(async (request) => {
  const {slotId} = request.data || {};
  if (!request.auth || !slotId) {
    throw new HttpsError('invalid-argument', 'slotId required');
  }

  return cancelScheduleSlotInternal({
    slotId,
    uid: request.auth.uid,
    adminMode: isAdminAuth(request.auth)
  });
});

async function createPayouts(cleanerIdFilter = null) {
  const end = new Date();
  const start = new Date(end);
  start.setDate(start.getDate() - 7);
  const weekId = `${start.getFullYear()}-${start.getMonth() + 1}-${start.getDate()}_${end.getFullYear()}-${end.getMonth() + 1}-${end.getDate()}`;

  let query = db.collection('cleaner_orders').where('status', '==', 'completed');
  if (cleanerIdFilter && cleanerIdFilter !== 'all') {
    query = query.where('cleanerId', '==', cleanerIdFilter);
  }

  const snap = await query.get();
  const byCleaner = new Map();
  const policies = await getPolicyConfig();

  for (const doc of snap.docs) {
    const data = doc.data();
    const cleanerId = data.cleanerId;
    const income = cleanerIncomeForSource(data, policies) || Number(data.price || 0);
    byCleaner.set(cleanerId, (byCleaner.get(cleanerId) || 0) + income);
  }

  const results = [];
  for (const [cleanerId, gross] of byCleaner.entries()) {
    const tax = Math.round(gross * 0.04);
    const net = gross - tax;

    let payoutResp = null;
    let payoutError = null;
    try {
      payoutResp = await epayCreatePayout({cleanerId, amount: net, weekId});
    } catch (error) {
      payoutError = String(error);
    }

    await db.collection('payouts').add({
      cleanerId,
      weekId,
      gross,
      tax,
      net,
      currency: 'KZT',
      provider: 'epay',
      providerResponse: payoutResp,
      providerError: payoutError,
      createdAt: admin.firestore.FieldValue.serverTimestamp()
    });

    results.push({cleanerId, gross, tax, net, ok: payoutError == null});
  }

  return results;
}

async function assignCleanerInternal({
  orderId,
  cleanerId,
  cleanerName,
  scheduledDate,
  time,
  address,
  expectedOfferId = null
}) {
  const orderRef = db.collection('customer_orders').doc(orderId);
  const cleanerOrderRef = db.collection('cleaner_orders').doc(orderId);
  const shiftRef = db.collection('cleaner_shifts').doc(orderId);
  const cleanerSnap = await db.collection('cleaners').doc(cleanerId).get();
  if (!cleanerSnap.exists) {
    throw new HttpsError('not-found', 'Cleaner not found');
  }
  const cleaner = cleanerSnap.data();
  const policies = await getPolicyConfig();
  if ((cleaner.verificationStatus || '') !== 'approved') {
    throw new HttpsError('failed-precondition', 'Cleaner verification must be approved');
  }
  let cluster = null;
  let normalizedAddress = address || null;
  let normalizedTime = time || '10:00 - 13:00';
  let normalizedDate = scheduledDate ? new Date(scheduledDate) : new Date();
  let customerPhone = null;
  let customerCity = '';
  let customerId = null;
  let assignedOrderData = {};
  const chatId = assignmentChatId('order', orderId, cleanerId);

  await db.runTransaction(async (tx) => {
    const orderSnap = await tx.get(orderRef);
    if (!orderSnap.exists) {
      throw new HttpsError('not-found', 'Order not found');
    }
    const order = orderSnap.data();
    assignedOrderData = order;
    customerPhone = order.customerPhone || null;
    customerCity = resolveCityFromSource(order);
    customerId = order.customerId || null;
    cluster = await detectClusterForOrder({id: orderId, ...order});
    if (!serviceAreaMatches({id: cleanerId, ...cleaner}, {
      id: orderId,
      scopeType: 'order',
      ...order,
      clusterName: order.clusterName || cluster?.name || null
    })) {
      throw new HttpsError(
        'failed-precondition',
        'Заказ находится вне рабочих районов уборщицы.'
      );
    }

    if (!customerCity && order.customerId) {
      const customerSnap = await tx.get(db.collection('customers').doc(String(order.customerId)));
      customerCity = await resolveCustomerCity(order.customerId, customerSnap.exists ? (customerSnap.data() || {}) : {});
    }

    const cleanerCity = resolveCityFromSource(cleaner);
    if (customerCity && cleanerCity && cleanerCity !== customerCity) {
      throw new HttpsError(
        'failed-precondition',
        'Нельзя назначить уборщицу из другого города.'
      );
    }

    const activeOfferId = String(order.currentOfferId || '').trim();
    const activeOfferCleanerId = String(order.currentOfferCleanerId || '').trim();
    const activeOfferExpiresAt = order.offerExpiresAt instanceof admin.firestore.Timestamp
      ? order.offerExpiresAt.toDate()
      : order.offerExpiresAt instanceof Date
        ? order.offerExpiresAt
        : null;

    if (expectedOfferId) {
      if (String(order.cleanerId || '').trim()) {
        throw new HttpsError('failed-precondition', 'Order is already assigned');
      }
      if (activeOfferId !== String(expectedOfferId) || activeOfferCleanerId !== String(cleanerId)) {
        throw new HttpsError('failed-precondition', 'Offer is no longer active for this cleaner');
      }
      if (!activeOfferExpiresAt || activeOfferExpiresAt.getTime() <= Date.now()) {
        throw new HttpsError('deadline-exceeded', 'Offer has expired');
      }
    } else if (order.orderStatus !== 'pending_assignment') {
      throw new HttpsError('failed-precondition', 'Order must be pending assignment');
    }

    normalizedDate = scheduledDate ? new Date(scheduledDate) : new Date();
    normalizedAddress = address || order.address || null;
    const schedulerMetrics = buildSchedulerMetrics(order, policies);
    normalizedTime = buildTimeRangeForDuration(
      time || order.time || '10:00 - 13:00',
      schedulerMetrics.totalDurationMinutes
    );
    const conflict = await findCleanerTimeConflictInTransaction(tx, {
      cleanerId,
      scopeType: 'order',
      scopeId: orderId,
      scope: {
        ...order,
        scheduledFor: normalizedDate,
        date: normalizedDate,
        time: normalizedTime
      }
    });
    if (conflict) {
      throw new HttpsError(
        'failed-precondition',
        `У уборщицы уже есть заказ на это время: ${conflict.time || conflict.id}`
      );
    }
    const dateText = `${normalizedDate.getDate()}.${normalizedDate.getMonth() + 1}.${normalizedDate.getFullYear()}`;
    const earning = cleanerEarningPayload(order, policies);
    const addonPayload = orderAddonPayload(order, order.pricing || {});

    tx.update(orderRef, {
      cleanerId,
      cleaner: cleanerName,
      cleanerName,
      cleanerPhone: cleaner.phone || null,
      orderStatus: 'assigned',
      status: 'confirmed',
      assignmentStatus: ORDER_ASSIGNMENT_STATUSES.ASSIGNED,
      currentOfferCleanerId: null,
      currentOfferId: null,
      offerExpiresAt: null,
      time: normalizedTime,
      estimatedDurationMinutes: schedulerMetrics.estimatedDurationMinutes,
      totalDurationMinutes: schedulerMetrics.totalDurationMinutes,
      totalDurationHours: schedulerMetrics.totalDurationHours,
      dateText,
      date: admin.firestore.Timestamp.fromDate(normalizedDate),
      address: normalizedAddress,
      customerCity: customerCity || null,
      clusterId: cluster?.id || order.clusterId || null,
      clusterName: cluster?.name || order.clusterName || null,
      cleanerSqmRate: earning.cleanerSqmRate,
      cleanerIncome: earning.cleanerIncome,
      chatId,
      assignedAt: admin.firestore.FieldValue.serverTimestamp()
    });

    tx.set(cleanerOrderRef, {
      cleanerId,
      orderNumber: order.orderNumber || null,
      displayOrderId: order.displayOrderId || orderDisplayIdFromNumber(order.orderNumber) || null,
      status: 'confirmed',
      orderStatus: 'assigned',
      date: admin.firestore.Timestamp.fromDate(normalizedDate),
      dateText,
      time: normalizedTime,
      client: order.customerName || 'Клиент',
      customerPhone: order.customerPhone || null,
      cleanerPhone: cleaner.phone || null,
      customerCity: customerCity || null,
      address: normalizedAddress || '',
      package: order.package || '',
      price: order.price || 0,
      ...addonPayload,
      area: earning.area,
      cleanerSqmRate: earning.cleanerSqmRate,
      cleanerIncome: earning.cleanerIncome,
      customerOrderId: orderId,
      chatId,
      scopeType: 'order',
      assignmentStatus: ORDER_ASSIGNMENT_STATUSES.ASSIGNED
    }, {merge: true});

    tx.set(shiftRef, {
      cleanerId,
      orderNumber: order.orderNumber || null,
      displayOrderId: order.displayOrderId || orderDisplayIdFromNumber(order.orderNumber) || null,
      date: normalizedDate.toISOString(),
      time: normalizedTime,
      client: order.customerName || 'Клиент',
      customerPhone: order.customerPhone || null,
      cleanerPhone: cleaner.phone || null,
      customerCity: customerCity || null,
      address: normalizedAddress || '',
      package: order.package || '',
      price: order.price || 0,
      ...addonPayload,
      area: earning.area,
      cleanerSqmRate: earning.cleanerSqmRate,
      cleanerIncome: earning.cleanerIncome,
      customerOrderId: orderId,
      chatId,
      scopeType: 'order'
    }, {merge: true});
  });

  const slotsSnap = await db.collection('schedule_slots')
    .where('sourceOrderId', '==', orderId)
    .get();
  if (!slotsSnap.empty) {
    const batch = db.batch();
    for (const doc of slotsSnap.docs) {
      const slotEarning = cleanerEarningPayload(doc.data() || assignedOrderData, policies);
      batch.set(doc.ref, {
        cleanerId,
        cleanerName,
        cleanerPhone: cleaner.phone || null,
        customerPhone,
        customerCity: customerCity || null,
        clusterId: cluster?.id || null,
        clusterName: cluster?.name || null,
        scheduledFor: admin.firestore.Timestamp.fromDate(normalizedDate),
        scheduledDateKey: toIsoDate(normalizedDate),
        time: normalizedTime,
        address: normalizedAddress,
        cleanerSqmRate: slotEarning.cleanerSqmRate,
        cleanerIncome: slotEarning.cleanerIncome,
        chatId: assignmentChatId('schedule_slot', doc.id, cleanerId),
        status: 'assigned',
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      }, {merge: true});
    }
    await batch.commit();
  }

  await ensureOrderChat(orderId, {systemText: 'Уборщица назначена'});
  await cancelPendingOffersForScope('order', orderId, 'cancelled');
  await recalculateCleanerDailyScheduleInternal(cleanerId, normalizedDate);
  await cancelOverlappingPendingOffersForCleaner({
    cleanerId,
    acceptedScopeType: 'order',
    acceptedScopeId: orderId,
    acceptedScope: {
      scheduledFor: normalizedDate,
      date: normalizedDate,
      time: normalizedTime,
      totalDurationMinutes: assignedOrderData.totalDurationMinutes ||
        Math.round(Number(assignedOrderData.totalDurationHours || assignedOrderData.estimatedDurationHours || 0) * 60) ||
        undefined,
      area: assignedOrderData.area || null
    }
  }).catch((error) => console.error('Failed to cancel overlapping cleaner offers after order assignment', error));
  await notifyCustomerCleanerAssigned(
    {
      id: orderId,
      orderId,
      customerId,
      time: normalizedTime,
      address: normalizedAddress || null,
      scopeType: 'order'
    },
    {id: cleanerId, name: cleanerName}
  ).catch((error) => console.error('Failed to notify customer about assignment', error));
}

async function assignScheduleSlotInternal({
  slotId,
  cleanerId,
  cleanerName,
  expectedOfferId = null
}) {
  const slotRef = db.collection('schedule_slots').doc(String(slotId));
  const cleanerOrderRef = db.collection('cleaner_orders').doc(String(slotId));
  const shiftRef = db.collection('cleaner_shifts').doc(String(slotId));
  const cleanerSnap = await db.collection('cleaners').doc(String(cleanerId)).get();
  if (!cleanerSnap.exists) {
    throw new HttpsError('not-found', 'Cleaner not found');
  }
  const cleaner = cleanerSnap.data() || {};
  const policies = await getPolicyConfig();
  if ((cleaner.verificationStatus || '') !== 'approved') {
    throw new HttpsError('failed-precondition', 'Cleaner verification must be approved');
  }

  let normalizedDate = new Date();
  let sourceOrderId = null;
  let customerId = null;
  let slotTime = '10:00 - 13:00';
  let slotAddress = null;
  let slotOrderNumber = null;
  let slotDisplayOrderId = null;
  let assignedSlotData = {};
  const chatId = assignmentChatId('schedule_slot', slotId, cleanerId);

  await db.runTransaction(async (tx) => {
    const slotSnap = await tx.get(slotRef);
    if (!slotSnap.exists) {
      throw new HttpsError('not-found', 'Slot not found');
    }
    const slot = slotSnap.data() || {};
    assignedSlotData = slot;
    const activeOfferId = String(slot.currentOfferId || '').trim();
    const activeOfferCleanerId = String(slot.currentOfferCleanerId || '').trim();
    const activeOfferExpiresAt = slot.offerExpiresAt instanceof admin.firestore.Timestamp
      ? slot.offerExpiresAt.toDate()
      : slot.offerExpiresAt instanceof Date
        ? slot.offerExpiresAt
        : null;
    if (expectedOfferId) {
      if (String(slot.cleanerId || '').trim()) {
        throw new HttpsError('failed-precondition', 'Slot is already assigned');
      }
      if (activeOfferId !== String(expectedOfferId) || activeOfferCleanerId !== String(cleanerId)) {
        throw new HttpsError('failed-precondition', 'Offer is no longer active for this cleaner');
      }
      if (!activeOfferExpiresAt || activeOfferExpiresAt.getTime() <= Date.now()) {
        throw new HttpsError('deadline-exceeded', 'Offer has expired');
      }
    } else if (String(slot.status || '') !== 'pending_assignment') {
      throw new HttpsError('failed-precondition', 'Slot must be pending assignment');
    }

    sourceOrderId = String(slot.sourceOrderId || slot.customerOrderId || '').trim() || null;
    let sourceOrderForArea = {};
    if (sourceOrderId) {
      const sourceOrderSnap = await tx.get(db.collection('customer_orders').doc(sourceOrderId));
      if (sourceOrderSnap.exists) {
        sourceOrderForArea = sourceOrderSnap.data() || {};
      }
    }
    const slotWithServiceArea = mergeServiceAreaIdentity(slot, sourceOrderForArea);

    if (!serviceAreaMatches({id: cleanerId, ...cleaner}, {
      id: slotId,
      scopeType: 'schedule_slot',
      ...slotWithServiceArea
    })) {
      throw new HttpsError(
        'failed-precondition',
        'Заказ находится вне рабочих районов уборщицы.'
      );
    }

    normalizedDate = slotScheduledAt(slot);
    customerId = slot.customerId || null;
    const slotMetrics = buildSchedulerMetrics(slot, policies);
    slotTime = buildTimeRangeForDuration(
      slot.time || '10:00 - 13:00',
      slotMetrics.totalDurationMinutes
    );
    slotAddress = slot.address || null;
    const conflict = await findCleanerTimeConflictInTransaction(tx, {
      cleanerId,
      scopeType: 'schedule_slot',
      scopeId: slotId,
      scope: {
        ...slot,
        scheduledFor: normalizedDate,
        date: normalizedDate,
        time: slotTime
      }
    });
    if (conflict) {
      throw new HttpsError(
        'failed-precondition',
        `У уборщицы уже есть заказ на это время: ${conflict.time || conflict.id}`
      );
    }
    slotOrderNumber = slot.orderNumber || null;
    slotDisplayOrderId = slot.displayOrderId || null;
    const sourceOrderNumber = sourceOrderForArea.orderNumber || normalizeOrderNumber(sourceOrderId);
    const slotReusesPackageNumber = sourceOrderNumber &&
      normalizeOrderNumber(slotOrderNumber) === normalizeOrderNumber(sourceOrderNumber);
    if (!slotOrderNumber || !slotDisplayOrderId || slotReusesPackageNumber) {
      const newSlotOrderNumber = await allocateNextOrderNumber(tx);
      slotOrderNumber = newSlotOrderNumber;
      slotDisplayOrderId = orderDisplayIdFromNumber(newSlotOrderNumber);
    }
    const earning = cleanerEarningPayload(slot, policies);
    const addonPayload = orderAddonPayload(slot, slot.pricing || {});

    tx.set(slotRef, {
      cleanerId,
      cleanerName,
      cleanerPhone: cleaner.phone || null,
      status: 'assigned',
      assignmentStatus: scopeStatusForCleanerAcceptance({
        ...slot,
        assignmentType: assignmentTypeForDate(normalizedDate)
      }),
      currentOfferCleanerId: null,
      currentOfferId: null,
      offerExpiresAt: null,
      cleanerSqmRate: earning.cleanerSqmRate,
      cleanerIncome: earning.cleanerIncome,
      orderNumber: slotOrderNumber,
      displayOrderId: slotDisplayOrderId,
      time: slotTime,
      estimatedDurationMinutes: slotMetrics.estimatedDurationMinutes,
      totalDurationMinutes: slotMetrics.totalDurationMinutes,
      totalDurationHours: slotMetrics.totalDurationHours,
      chatId,
      assignedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});

    tx.set(cleanerOrderRef, {
      cleanerId,
      cleanerName,
      scheduleSlotId: slotId,
      sourceOrderId: sourceOrderId,
      customerOrderId: sourceOrderId,
      customerId,
      orderNumber: slotOrderNumber,
      displayOrderId: slotDisplayOrderId,
      status: 'confirmed',
      orderStatus: 'assigned',
      date: admin.firestore.Timestamp.fromDate(normalizedDate),
      dateText: `${normalizedDate.getDate()}.${normalizedDate.getMonth() + 1}.${normalizedDate.getFullYear()}`,
      time: slotTime,
      client: slot.customerName || 'Клиент',
      customerPhone: slot.customerPhone || null,
      cleanerPhone: cleaner.phone || null,
      customerCity: resolveCityFromSource(slot) || null,
      address: slot.address || '',
      package: slot.package || '',
      price: Number(slot.price || 0),
      ...addonPayload,
      area: earning.area,
      cleanerSqmRate: earning.cleanerSqmRate,
      cleanerIncome: earning.cleanerIncome,
      chatId,
      scopeType: 'schedule_slot',
      assignmentStatus: ORDER_ASSIGNMENT_STATUSES.SCHEDULED_CONFIRMED,
      assignedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});

    tx.set(shiftRef, {
      cleanerId,
      cleanerName,
      scheduleSlotId: slotId,
      sourceOrderId: sourceOrderId,
      customerOrderId: sourceOrderId,
      customerId,
      orderNumber: slotOrderNumber,
      displayOrderId: slotDisplayOrderId,
      date: normalizedDate.toISOString(),
      time: slotTime,
      client: slot.customerName || 'Клиент',
      customerPhone: slot.customerPhone || null,
      cleanerPhone: cleaner.phone || null,
      customerCity: resolveCityFromSource(slot) || null,
      address: slot.address || '',
      package: slot.package || '',
      price: Number(slot.price || 0),
      ...addonPayload,
      area: earning.area,
      cleanerSqmRate: earning.cleanerSqmRate,
      cleanerIncome: earning.cleanerIncome,
      chatId,
      scopeType: 'schedule_slot'
    }, {merge: true});
  });

  await recalculateCleanerDailyScheduleInternal(cleanerId, normalizedDate)
    .catch((error) => console.error('Failed to recalculate cleaner schedule after slot assignment', error));
  await cancelOverlappingPendingOffersForCleaner({
    cleanerId,
    acceptedScopeType: 'schedule_slot',
    acceptedScopeId: slotId,
    acceptedScope: {
      ...assignedSlotData,
      scheduledFor: normalizedDate,
      date: normalizedDate,
      time: slotTime
    }
  }).catch((error) => console.error('Failed to cancel overlapping cleaner offers after slot assignment', error));
  await cancelPendingOffersForScope('schedule_slot', slotId, 'cancelled')
    .catch((error) => console.error('Failed to cancel pending slot offers after assignment', error));
  await ensureOrderChat(slotId, {systemText: 'Уборщица назначена на визит'})
    .catch((error) => console.error('Failed to ensure slot order chat after assignment', error));
  await notifyCustomerCleanerAssigned(
    {
      id: slotId,
      orderId: sourceOrderId,
      customerId,
      time: slotTime,
      address: slotAddress,
      scopeType: 'schedule_slot'
    },
    {id: cleanerId, name: cleanerName}
  ).catch((error) => console.error('Failed to notify customer about slot assignment', error));
}

async function acceptOrderOfferInternal({offerId, cleanerId}) {
  const offerRef = db.collection('order_offers').doc(String(offerId));
  const offerSnap = await offerRef.get();
  if (!offerSnap.exists) {
    throw new HttpsError('not-found', 'Offer not found');
  }
  const offer = {id: offerSnap.id, ...offerSnap.data()};
  if (String(offer.cleanerId || '') !== String(cleanerId)) {
    throw new HttpsError('permission-denied', 'Offer does not belong to this cleaner');
  }
  const offerStatus = String(offer.status || '');
  if (offerStatus !== 'pending') {
    const alreadyAssigned = await acceptedOfferResultIfAssignedToCleaner(offer, cleanerId);
    if (offerStatus === 'accepted' && alreadyAssigned) {
      return alreadyAssigned;
    }
    throw new HttpsError('failed-precondition', 'Offer is no longer active');
  }
  const expiresAt = offer.expiresAt instanceof admin.firestore.Timestamp
    ? offer.expiresAt.toDate()
    : offer.expiresAt instanceof Date
      ? offer.expiresAt
      : null;
  if (!expiresAt || expiresAt.getTime() <= Date.now()) {
    const alreadyAssigned = await acceptedOfferResultIfAssignedToCleaner(offer, cleanerId);
    if (alreadyAssigned) {
      return alreadyAssigned;
    }
    throw new HttpsError('deadline-exceeded', 'Offer has expired');
  }

  const cleanerSnap = await db.collection('cleaners').doc(String(cleanerId)).get();
  if (!cleanerSnap.exists) {
    throw new HttpsError('not-found', 'Cleaner not found');
  }
  const cleaner = {id: cleanerSnap.id, ...cleanerSnap.data()};

  if (offer.scopeType === 'schedule_slot') {
    const slotSnap = await db.collection('schedule_slots').doc(String(offer.scopeId || '')).get();
    if (!slotSnap.exists) {
      throw new HttpsError('not-found', 'Slot not found');
    }
    const slot = slotSnap.data() || {};
    if (
      String(slot.status || '') === 'pending_payment' ||
      slot.pendingAddonPayment === true
    ) {
      await offerRef.set({
        status: 'payment_pending',
        respondedAt: admin.firestore.FieldValue.serverTimestamp(),
        response: 'payment_pending',
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      }, {merge: true});
      throw new HttpsError(
        'failed-precondition',
        'Order is waiting addon payment confirmation'
      );
    }
    await assignScheduleSlotInternal({
      slotId: offer.scopeId,
      cleanerId,
      cleanerName: cleaner.name || offer.cleanerName || 'Исполнитель',
      expectedOfferId: offer.id
    });
  } else {
    const scope = await loadAssignmentScope('order', offer.scopeId);
    await assignCleanerInternal({
      orderId: offer.scopeId,
      cleanerId,
      cleanerName: cleaner.name || offer.cleanerName || 'Исполнитель',
      scheduledDate: resolveScopeScheduledAt(scope.data),
      time: scope.data.time || '10:00 - 13:00',
      address: scope.data.address || null,
      expectedOfferId: offer.id
    });
  }

  await offerRef.set({
    status: 'accepted',
    respondedAt: admin.firestore.FieldValue.serverTimestamp(),
    response: 'accepted',
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, {merge: true});
  await cancelPendingOffersForScope(offer.scopeType, offer.scopeId, 'cancelled')
    .catch((error) => console.error('Failed to cancel pending offers after acceptance', error));

  const scope = await loadAssignmentScope(offer.scopeType, offer.scopeId)
    .catch((error) => {
      console.error('Failed to load assignment scope after acceptance', error);
      return null;
    });
  if (scope) {
    await notifyCleanerAssignmentConfirmed(scope.data, cleaner)
      .catch((error) => console.error('Failed to notify cleaner about accepted assignment', error));
  }

  return {
    ok: true,
    offerId: offer.id,
    scopeType: offer.scopeType,
    scopeId: offer.scopeId,
    cleanerId
  };
}

async function rejectOrderOfferInternal({offerId, cleanerId, reason = 'rejected'}) {
  const offerRef = db.collection('order_offers').doc(String(offerId));
  let scopeType = 'order';
  let scopeId = '';
  await db.runTransaction(async (tx) => {
    const offerSnap = await tx.get(offerRef);
    if (!offerSnap.exists) {
      throw new HttpsError('not-found', 'Offer not found');
    }
    const offer = offerSnap.data() || {};
    scopeType = String(offer.scopeType || 'order') === 'schedule_slot' ? 'schedule_slot' : 'order';
    scopeId = String(offer.scopeId || '');
    if (String(offer.cleanerId || '') !== String(cleanerId)) {
      throw new HttpsError('permission-denied', 'Offer does not belong to this cleaner');
    }
    if (String(offer.status || '') !== 'pending') {
      throw new HttpsError('failed-precondition', 'Offer is no longer active');
    }
    const scopeRef = db.collection(scopeType === 'schedule_slot' ? 'schedule_slots' : 'customer_orders').doc(scopeId);
    const scopeSnap = await tx.get(scopeRef);
    if (!scopeSnap.exists) {
      throw new HttpsError('not-found', 'Scope not found');
    }
    tx.set(offerRef, {
      status: 'rejected',
      respondedAt: admin.firestore.FieldValue.serverTimestamp(),
      response: reason,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});
    tx.set(scopeRef, {
      rejectedBy: admin.firestore.FieldValue.arrayUnion(String(cleanerId)),
      currentOfferCleanerId: null,
      currentOfferId: null,
      offerExpiresAt: null,
      assignmentStatus: ORDER_ASSIGNMENT_STATUSES.SEARCHING,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});
  });

  const nextOfferResult = await offerScopeToNextCleanerInternal(scopeType, scopeId, {force: true});
  return {
    ok: true,
    offerId: String(offerId),
    scopeType,
    scopeId,
    nextOffer: nextOfferResult || null
  };
}

async function expirePendingOfferInternal(offerId) {
  const offerRef = db.collection('order_offers').doc(String(offerId));
  let scopeType = 'order';
  let scopeId = '';
  let cleanerId = '';
  let shouldContinue = false;
  await db.runTransaction(async (tx) => {
    const offerSnap = await tx.get(offerRef);
    if (!offerSnap.exists) {
      return;
    }
    const offer = offerSnap.data() || {};
    scopeType = String(offer.scopeType || 'order') === 'schedule_slot' ? 'schedule_slot' : 'order';
    scopeId = String(offer.scopeId || '');
    cleanerId = String(offer.cleanerId || '');
    if (String(offer.status || '') !== 'pending') {
      return;
    }
    const expiresAt = offer.expiresAt instanceof admin.firestore.Timestamp
      ? offer.expiresAt.toDate()
      : offer.expiresAt instanceof Date
        ? offer.expiresAt
        : null;
    if (!expiresAt || expiresAt.getTime() > Date.now()) {
      return;
    }
    const scopeRef = db.collection(scopeType === 'schedule_slot' ? 'schedule_slots' : 'customer_orders').doc(scopeId);
    const scopeSnap = await tx.get(scopeRef);
    if (!scopeSnap.exists) {
      tx.set(offerRef, {
        status: 'expired',
        respondedAt: admin.firestore.FieldValue.serverTimestamp(),
        response: 'expired',
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      }, {merge: true});
      return;
    }
    const scope = scopeSnap.data() || {};
    tx.set(offerRef, {
      status: 'expired',
      respondedAt: admin.firestore.FieldValue.serverTimestamp(),
      response: 'expired',
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});
    tx.set(scopeRef, {
      timeoutBy: admin.firestore.FieldValue.arrayUnion(cleanerId),
      currentOfferCleanerId: String(scope.currentOfferCleanerId || '') === cleanerId ? null : (scope.currentOfferCleanerId || null),
      currentOfferId: String(scope.currentOfferId || '') === String(offerId) ? null : (scope.currentOfferId || null),
      offerExpiresAt: String(scope.currentOfferId || '') === String(offerId) ? null : (scope.offerExpiresAt || null),
      assignmentStatus: ORDER_ASSIGNMENT_STATUSES.SEARCHING,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, {merge: true});
    shouldContinue = true;
  });

  if (shouldContinue && scopeId) {
    await offerScopeToNextCleanerInternal(scopeType, scopeId, {force: true});
  }
}

async function unassignOrderInternal(orderId) {
  const orderRef = db.collection('customer_orders').doc(orderId);
  const cleanerOrderRef = db.collection('cleaner_orders').doc(orderId);
  const shiftRef = db.collection('cleaner_shifts').doc(orderId);
  let previousCleanerId = null;
  let previousDate = null;

  await db.runTransaction(async (tx) => {
    const orderSnap = await tx.get(orderRef);
    if (!orderSnap.exists) {
      throw new HttpsError('not-found', 'Order not found');
    }
    const order = orderSnap.data();
    if (String(order.orderStatus || '') !== 'assigned') {
      return;
    }
    previousCleanerId = String(order.cleanerId || '').trim() || null;
    previousDate = normalizeOrderDate(order.date || order.scheduledFor || new Date());
    tx.update(orderRef, {
      cleanerId: null,
      cleaner: null,
      cleanerName: null,
      cleanerPhone: null,
      orderStatus: 'pending_assignment',
      status: 'pending',
      assignmentStatus: ORDER_ASSIGNMENT_STATUSES.REASSIGNMENT_NEEDED,
      currentOfferCleanerId: null,
      currentOfferId: null,
      offerExpiresAt: null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    });
    tx.delete(cleanerOrderRef);
    tx.delete(shiftRef);
  });

  const slotsSnap = await db.collection('schedule_slots')
    .where('sourceOrderId', '==', orderId)
    .get();
  if (!slotsSnap.empty) {
    const batch = db.batch();
    for (const doc of slotsSnap.docs) {
      batch.set(doc.ref, {
        cleanerId: null,
        cleanerName: null,
        cleanerPhone: null,
        status: 'pending_assignment',
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      }, {merge: true});
    }
    await batch.commit();
  }
  if (previousCleanerId && previousDate) {
    await recalculateCleanerDailyScheduleInternal(previousCleanerId, previousDate);
  }
}

async function assignOrdersForDayInternal(targetDate) {
  const dateKey = toIsoDate(new Date(targetDate));
  const slotSnap = await db.collection('schedule_slots')
    .where('scheduledDateKey', '==', dateKey)
    .where('status', '==', 'pending_assignment')
    .get();
  const results = [];

  for (const doc of slotSnap.docs) {
    const slot = {id: doc.id, ...doc.data()};
    const preferredCleanerId = String(slot.preferredCleanerId || '').trim() || null;
    const result = await offerScopeToNextCleanerInternal('schedule_slot', slot.id, {
      forceRebuild: true,
      preferredCleanerId
    });
    results.push({
      orderId: slot.sourceOrderId || slot.customerOrderId || slot.id,
      scopeId: slot.id,
      status: result.status || 'offered',
      cleanerId: result.cleanerId || null
    });
  }

  return {ok: true, date: dateKey, results};
}

async function rebalanceAssignmentsInternal(targetDate) {
  const dateKey = toIsoDate(new Date(targetDate));
  const slotSnap = await db.collection('schedule_slots')
    .where('scheduledDateKey', '==', dateKey)
    .where('status', '==', 'assigned')
    .get();

  const rebalanced = [];
  for (const doc of slotSnap.docs) {
    const slot = doc.data();
    const orderId = slot.sourceOrderId || slot.customerOrderId || null;
    if (!orderId) {
      continue;
    }
    const orderSnap = await db.collection('customer_orders').doc(orderId).get();
    if (!orderSnap.exists) {
      continue;
    }
    const order = orderSnap.data();
    if (String(order.orderStatus || '') !== 'assigned') {
      continue;
    }
    await unassignOrderInternal(orderId);
    rebalanced.push(orderId);
  }

  const result = await assignOrdersForDayInternal(dateKey);
  await logAssignmentDecision('fair_rebalance_decision', {
    date: dateKey,
    rebalancedOrderIds: rebalanced,
    resultCount: result.results.length
  });
  return result;
}

async function confirmCleaningStartInternal({orderId, confirmed, uid}) {
  const targetId = String(orderId || '').trim();
  if (!targetId || !uid) {
    throw new HttpsError('invalid-argument', 'orderId required');
  }

  let scope = null;
  const directSlotSnap = await db.collection('schedule_slots').doc(targetId).get();
  if (directSlotSnap.exists) {
    scope = {type: 'schedule_slot', id: directSlotSnap.id, data: directSlotSnap.data() || {}};
  } else {
    const slotBySourceSnap = await db.collection('schedule_slots')
      .where('sourceOrderId', '==', targetId)
      .where('customerId', '==', uid)
      .get();
    const candidate = slotBySourceSnap.docs.find((doc) =>
      ['start_pending', 'assigned', 'confirmed', 'in_progress'].includes(String(doc.data()?.status || ''))
    );
    if (candidate) {
      scope = {type: 'schedule_slot', id: candidate.id, data: candidate.data() || {}};
    }
  }

  if (!scope) {
    const orderSnap = await db.collection('customer_orders').doc(targetId).get();
    if (!orderSnap.exists) {
      throw new HttpsError('not-found', 'Order not found');
    }
    scope = {type: 'order', id: orderSnap.id, data: orderSnap.data() || {}};
  }

  const data = scope.data || {};
  if (String(data.customerId || '') !== String(uid)) {
    throw new HttpsError('permission-denied', 'No access to this order');
  }
  if (String(data.status || data.orderStatus || '') !== 'start_pending') {
    throw new HttpsError('failed-precondition', 'Cleaning start confirmation is not pending');
  }

  const cleanerId = String(data.cleanerId || '').trim();
  const statusPayload = confirmed
    ? {
        status: 'in_progress',
        orderStatus: 'in_progress',
        cleaningStartConfirmed: true,
        cleaningStartRejected: false,
        cleaningStartConfirmedAt: admin.firestore.FieldValue.serverTimestamp(),
        startedAt: data.startedAt || admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      }
    : {
        status: 'start_pending',
        orderStatus: 'start_pending',
        cleaningStartConfirmed: false,
        cleaningStartRejected: true,
        cleaningStartRejectedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      };

  await db.runTransaction(async (tx) => {
    if (scope.type === 'schedule_slot') {
      const slotRef = db.collection('schedule_slots').doc(scope.id);
      tx.set(slotRef, statusPayload, {merge: true});
      tx.set(db.collection('cleaner_orders').doc(scope.id), statusPayload, {merge: true});
      tx.set(db.collection('cleaner_shifts').doc(scope.id), statusPayload, {merge: true});
    } else {
      const orderRef = db.collection('customer_orders').doc(scope.id);
      tx.set(orderRef, statusPayload, {merge: true});
      if (cleanerId) {
        tx.set(db.collection('cleaner_orders').doc(scope.id), statusPayload, {merge: true});
      }
    }
  });

  await notifyCleanerCleaningStartResponse({
    id: scope.id,
    slotId: scope.type === 'schedule_slot' ? scope.id : '',
    orderId: data.sourceOrderId || data.customerOrderId || scope.id,
    cleanerId,
    scopeType: scope.type
  }, confirmed).catch((error) => {
    console.error('Failed to notify cleaner about cleaning start response', error);
  });
  await logAdminNotification('cleaning_start_response', {
    orderId: data.sourceOrderId || data.customerOrderId || scope.id,
    slotId: scope.type === 'schedule_slot' ? scope.id : '',
    customerId: uid,
    cleanerId,
    confirmed,
    response: confirmed ? 'yes' : 'no'
  });
}

async function advanceOrderStatusInternal({orderId, toStatus, uid = null, adminMode = false}) {
  const cleanerAllowed = ['in_progress', 'completed', 'disputed', 'canceled'];
  if (!adminMode && uid && cleanerAllowed.includes(String(toStatus || ''))) {
    const directSlotSnap = await db.collection('schedule_slots').doc(String(orderId)).get();
    if (directSlotSnap.exists && String(directSlotSnap.data()?.cleanerId || '') === String(uid)) {
      if (String(toStatus || '') === 'canceled') {
        await cancelCleanerScheduleSlotAssignmentInternal({
          slotId: directSlotSnap.id,
          uid,
          adminMode
        });
        return;
      }
      await advanceScheduleSlotStatusInternal({
        slotId: directSlotSnap.id,
        toStatus,
        uid,
        adminMode
      });
      return;
    }
    const slotByOrderSnap = await db.collection('schedule_slots')
      .where('sourceOrderId', '==', String(orderId))
      .where('cleanerId', '==', String(uid))
      .get();
    const activeSlotDoc = slotByOrderSnap.docs.find((doc) =>
      ['assigned', 'confirmed', 'in_progress'].includes(String(doc.data()?.status || ''))
    );
    if (activeSlotDoc) {
      if (String(toStatus || '') === 'canceled') {
        await cancelCleanerScheduleSlotAssignmentInternal({
          slotId: activeSlotDoc.id,
          uid,
          adminMode
        });
        return;
      }
      await advanceScheduleSlotStatusInternal({
        slotId: activeSlotDoc.id,
        toStatus,
        uid,
        adminMode
      });
      return;
    }
  }

  const orderRef = db.collection('customer_orders').doc(orderId);
  let hasCleaner = false;
  let cleanerIdForStatusUpdate = null;
  let subscriptionId = null;
  let startConfirmationRequested = false;
  let startNotificationScope = null;
  let effectiveToStatus = String(toStatus || '');

  await db.runTransaction(async (tx) => {
    const orderSnap = await tx.get(orderRef);
    if (!orderSnap.exists) {
      throw new HttpsError('not-found', 'Order not found');
    }

    const order = orderSnap.data();
    const current = order.orderStatus;
    const isCleaner = uid != null && order.cleanerId === uid;
    const isCustomer = uid != null && order.customerId === uid;
    const requestStartConfirmation = !adminMode &&
      isCleaner &&
      String(toStatus || '') === 'in_progress' &&
      ['assigned', 'confirmed'].includes(String(current || ''));
    effectiveToStatus = requestStartConfirmation ? 'start_pending' : String(toStatus || '');
    if (String(current || '') === effectiveToStatus) {
      hasCleaner = !!order.cleanerId;
      cleanerIdForStatusUpdate = order.cleanerId || null;
      subscriptionId = order.subscriptionId || null;
      return;
    }

    const allowed = ORDER_TRANSITIONS[current] || [];
    if (!allowed.includes(effectiveToStatus)) {
      throw new HttpsError('failed-precondition', `Transition ${current} -> ${effectiveToStatus} is forbidden`);
    }

    const customerAllowed = ['canceled'];

    if (!adminMode) {
      if (isCustomer && !customerAllowed.includes(effectiveToStatus)) {
        throw new HttpsError('permission-denied', 'Customer cannot set this status');
      }
      if (isCleaner && !cleanerAllowed.includes(String(toStatus || ''))) {
        throw new HttpsError('permission-denied', 'Cleaner cannot set this status');
      }
      if (!isCustomer && !isCleaner) {
        throw new HttpsError('permission-denied', 'No access to this order');
      }
    }
    if (
      effectiveToStatus === 'completed' &&
      order.startRequiresCustomerConfirmation === true &&
      order.cleaningStartConfirmed !== true
    ) {
      throw new HttpsError(
        'failed-precondition',
        'Customer must confirm that cleaning has started before completion'
      );
    }

    const publicStatus =
      effectiveToStatus === 'completed' ? 'completed' :
      effectiveToStatus === 'in_progress' ? 'in_progress' :
      effectiveToStatus === 'start_pending' ? 'start_pending' :
      effectiveToStatus === 'assigned' ? 'confirmed' :
      effectiveToStatus === 'canceled' ? 'canceled' :
      'pending';
    hasCleaner = !!order.cleanerId;
    cleanerIdForStatusUpdate = order.cleanerId || null;
    subscriptionId = order.subscriptionId || null;

    const statusPayload = {
      orderStatus: effectiveToStatus,
      status: publicStatus,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      ...(effectiveToStatus === 'completed' ? {completedAt: admin.firestore.FieldValue.serverTimestamp()} : {}),
      ...(effectiveToStatus === 'in_progress' ? {
        startedAt: order.startedAt || admin.firestore.FieldValue.serverTimestamp()
      } : {}),
      ...(effectiveToStatus === 'start_pending' ? {
        startRequiresCustomerConfirmation: true,
        cleaningStartConfirmed: false,
        cleaningStartRejected: false,
        startRequestedAt: admin.firestore.FieldValue.serverTimestamp(),
        startRequestedBy: uid || '',
        startedAt: admin.firestore.FieldValue.serverTimestamp()
      } : {})
    };

    tx.update(orderRef, statusPayload);

    if (order.cleanerId) {
      tx.set(
        db.collection('cleaner_orders').doc(orderId),
        {
          ...statusPayload,
          status: publicStatus,
          orderStatus: effectiveToStatus
        },
        {merge: true}
      );
    }
    if (effectiveToStatus === 'start_pending') {
      startConfirmationRequested = true;
      startNotificationScope = {
        id: orderId,
        orderId,
        customerId: String(order.customerId || '').trim(),
        cleanerId: String(order.cleanerId || '').trim(),
        cleanerName: order.cleanerName || order.cleaner || '',
        dateText: order.dateText || order.date || '',
        time: order.time || '',
        scopeType: 'order'
      };
    }
  });

  if (hasCleaner) {
    const slotStatus =
      effectiveToStatus === 'completed' ? 'completed' :
      effectiveToStatus === 'in_progress' ? 'in_progress' :
      effectiveToStatus === 'start_pending' ? 'start_pending' :
      effectiveToStatus === 'assigned' ? 'assigned' :
      effectiveToStatus === 'canceled' ? 'canceled' :
      null;
    if (slotStatus) {
      const slotsSnap = await db.collection('schedule_slots')
        .where('sourceOrderId', '==', orderId)
        .get();
      if (!slotsSnap.empty) {
        const batch = db.batch();
        for (const doc of slotsSnap.docs) {
          batch.set(doc.ref, {
            status: slotStatus,
            orderStatus: effectiveToStatus,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            ...(effectiveToStatus === 'start_pending' ? {
              startRequiresCustomerConfirmation: true,
              cleaningStartConfirmed: false,
              cleaningStartRejected: false,
              startRequestedAt: admin.firestore.FieldValue.serverTimestamp(),
              startRequestedBy: uid || '',
              startedAt: admin.firestore.FieldValue.serverTimestamp()
            } : {}),
            ...(effectiveToStatus === 'in_progress' ? {
              cleaningStartConfirmed: true,
              cleaningStartRejected: false,
              cleaningStartConfirmedAt: admin.firestore.FieldValue.serverTimestamp()
            } : {})
          }, {merge: true});
        }
        await batch.commit();
      }
    }
  }

  if (subscriptionId) {
    await refreshSubscriptionUsage(subscriptionId);
  }

  if (startConfirmationRequested && startNotificationScope) {
    await notifyCustomerCleaningStartRequested(startNotificationScope).catch((error) => {
      console.error('Failed to notify customer about cleaning start confirmation', error);
    });
    await logAdminNotification('cleaning_start_confirmation_requested', {
      orderId: startNotificationScope.orderId || '',
      slotId: startNotificationScope.slotId || '',
      customerId: startNotificationScope.customerId || '',
      cleanerId: startNotificationScope.cleanerId || '',
      cleanerName: startNotificationScope.cleanerName || '',
      dateText: startNotificationScope.dateText || '',
      time: startNotificationScope.time || '',
      scopeType: startNotificationScope.scopeType || 'order'
    });
  }

  if (effectiveToStatus === 'completed') {
    try {
      await ensureOrderChat(orderId);
      const orderSnap = await db.collection('customer_orders').doc(orderId).get();
      const order = orderSnap.data();
      if (order?.cleanerId) {
        await sendChatMessageInternal({
          orderId,
          senderId: order.cleanerId,
          senderRole: 'system',
          text: 'Уборка завершена',
          type: 'system'
        });
      }
    } catch (error) {
      console.error('Failed to post completion system message', error);
    }
  }
  if (['completed', 'canceled'].includes(String(effectiveToStatus || ''))) {
    try {
      await closeOrderChat(orderId, effectiveToStatus === 'completed' ? 'Заказ закрыт. Чат завершен.' : 'Заказ отменен. Чат закрыт.');
    } catch (error) {
      console.error('Failed to close order chat', error);
    }
  }

  if (cleanerIdForStatusUpdate && ['completed', 'canceled'].includes(String(effectiveToStatus || ''))) {
    try {
      await recalculateCleanerStatusInternal(cleanerIdForStatusUpdate);
    } catch (error) {
      console.error('Failed to recalculate cleaner status', error);
    }
  }
}

async function cancelCleanerScheduleSlotAssignmentInternal({slotId, uid, adminMode = false}) {
  const slotRef = db.collection('schedule_slots').doc(String(slotId));
  let subscriptionId = null;
  let sourceOrderId = null;
  let cleanerId = null;
  let cleanerOrderId = String(slotId);
  let previousChatId = null;

  await db.runTransaction(async (tx) => {
    const slotSnap = await tx.get(slotRef);
    if (!slotSnap.exists) {
      throw new HttpsError('not-found', 'Schedule slot not found');
    }
    const slot = slotSnap.data() || {};
    cleanerId = String(slot.cleanerId || '').trim();
    previousChatId = String(slot.chatId || '').trim() || assignmentChatId('schedule_slot', slotSnap.id, cleanerId);
    if (!adminMode && (!uid || cleanerId !== String(uid))) {
      throw new HttpsError('permission-denied', 'No access to this schedule slot');
    }
    const status = String(slot.status || '').trim().toLowerCase();
    if (!['assigned', 'confirmed'].includes(status)) {
      throw new HttpsError('failed-precondition', 'Only assigned future cleanings can be cancelled by cleaner');
    }
    const scheduledAt = resolveScopeScheduledAt({id: slotSnap.id, ...slot});
    const hoursBeforeStart = (scheduledAt.getTime() - Date.now()) / (60 * 60 * 1000);
    if (!adminMode && hoursBeforeStart < 12) {
      throw new HttpsError('failed-precondition', 'Cleaner can cancel no later than 12 hours before the cleaning');
    }

    subscriptionId = slot.subscriptionId || null;
    sourceOrderId = String(slot.sourceOrderId || slot.customerOrderId || '').trim() || null;
    cleanerOrderId = String(slot.id || slotSnap.id);
    const now = admin.firestore.FieldValue.serverTimestamp();
    const reassignmentPayload = {
      cleanerId: null,
      cleanerName: null,
      assignedCleanerId: null,
      executorId: null,
      status: 'pending_assignment',
      orderStatus: 'pending_assignment',
      assignmentStatus: ORDER_ASSIGNMENT_STATUSES.SEARCHING,
      currentOfferCleanerId: null,
      currentOfferId: null,
      offerExpiresAt: null,
      chatId: null,
      rejectedBy: admin.firestore.FieldValue.arrayUnion(cleanerId),
      cleanerCancelledBy: cleanerId,
      cleanerCancelledAt: now,
      updatedAt: now
    };
    tx.set(slotRef, reassignmentPayload, {merge: true});
    tx.set(db.collection('cleaner_orders').doc(cleanerOrderId), {
      status: 'canceled',
      orderStatus: 'canceled',
      canceledByCleanerId: cleanerId,
      canceledAt: now,
      updatedAt: now
    }, {merge: true});
    tx.set(db.collection('cleaner_shifts').doc(cleanerOrderId), {
      status: 'canceled',
      orderStatus: 'canceled',
      canceledByCleanerId: cleanerId,
      canceledAt: now,
      updatedAt: now
    }, {merge: true});
  });

  await cancelPendingOffersForScope('schedule_slot', String(slotId), 'cancelled');
  if (previousChatId) {
    await closeOrderChat(previousChatId, 'Уборщица отказалась от визита. Чат закрыт.')
      .catch((error) => console.error('Failed to close previous slot chat', error));
  }
  if (subscriptionId) {
    await refreshSubscriptionUsage(subscriptionId);
  }
  if (cleanerId) {
    await recalculateCleanerStatusInternal(cleanerId).catch((error) => {
      console.error('Failed to recalculate cleaner status after cleaner cancellation', error);
    });
  }
  await offerScopeToNextCleanerInternal('schedule_slot', String(slotId), {
    force: true,
    forceRebuild: true
  });
  if (sourceOrderId) {
    await notifyCustomerSearchStarted({
      id: String(slotId),
      scopeType: 'schedule_slot',
      orderId: sourceOrderId,
      customerId: null
    }).catch(() => {});
  }
  return {ok: true, status: 'reassignment_started', slotId: String(slotId)};
}

async function advanceScheduleSlotStatusInternal({slotId, toStatus, uid = null, adminMode = false}) {
  const slotRef = db.collection('schedule_slots').doc(String(slotId));
  let cleanerIdForStatusUpdate = null;
  let subscriptionId = null;
  let sourceOrderId = null;
  let chatId = null;
  let startConfirmationRequested = false;
  let startNotificationScope = null;
  let effectiveToStatus = String(toStatus || '');

  await db.runTransaction(async (tx) => {
    const slotSnap = await tx.get(slotRef);
    if (!slotSnap.exists) {
      throw new HttpsError('not-found', 'Schedule slot not found');
    }
    const slot = slotSnap.data() || {};
    const current = String(slot.status || '');
    const isCleaner = uid != null && String(slot.cleanerId || '') === String(uid);
    const isCustomer = uid != null && String(slot.customerId || '') === String(uid);
    const requestStartConfirmation = !adminMode &&
      isCleaner &&
      String(toStatus || '') === 'in_progress' &&
      ['assigned', 'confirmed'].includes(current);
    effectiveToStatus = requestStartConfirmation ? 'start_pending' : String(toStatus || '');
    if (current === effectiveToStatus) {
      cleanerIdForStatusUpdate = slot.cleanerId || null;
      subscriptionId = slot.subscriptionId || null;
      sourceOrderId = String(slot.sourceOrderId || slot.customerOrderId || '').trim() || null;
      chatId = String(slot.chatId || '').trim() ||
        (cleanerIdForStatusUpdate ? assignmentChatId('schedule_slot', slotSnap.id, cleanerIdForStatusUpdate) : null);
      return;
    }
    if (effectiveToStatus === 'canceled' && uid && String(slot.cleanerId || '') === String(uid) && !adminMode) {
      throw new HttpsError('failed-precondition', 'Use cleaner reassignment cancellation');
    }
    const allowedByStatus = {
      assigned: ['start_pending', 'in_progress', 'canceled'],
      confirmed: ['start_pending', 'in_progress', 'canceled'],
      start_pending: ['in_progress', 'canceled'],
      in_progress: ['completed', 'disputed'],
      disputed: ['completed', 'canceled'],
      completed: [],
      canceled: [],
      cancelled: []
    };
    const allowed = allowedByStatus[current] || [];
    if (!allowed.includes(effectiveToStatus)) {
      throw new HttpsError('failed-precondition', `Transition ${current} -> ${effectiveToStatus} is forbidden`);
    }
    const customerAllowed = ['canceled'];
    const cleanerAllowed = ['in_progress', 'completed', 'disputed'];

    if (!adminMode) {
      if (isCustomer && !customerAllowed.includes(effectiveToStatus)) {
        throw new HttpsError('permission-denied', 'Customer cannot set this status');
      }
      if (isCleaner && !cleanerAllowed.includes(String(toStatus || ''))) {
        throw new HttpsError('permission-denied', 'Cleaner cannot set this status');
      }
      if (!isCustomer && !isCleaner) {
        throw new HttpsError('permission-denied', 'No access to this schedule slot');
      }
    }
    if (
      effectiveToStatus === 'completed' &&
      slot.startRequiresCustomerConfirmation === true &&
      slot.cleaningStartConfirmed !== true
    ) {
      throw new HttpsError(
        'failed-precondition',
        'Customer must confirm that cleaning has started before completion'
      );
    }

    const slotStatus =
      effectiveToStatus === 'completed' ? 'completed' :
      effectiveToStatus === 'in_progress' ? 'in_progress' :
      effectiveToStatus === 'start_pending' ? 'start_pending' :
      effectiveToStatus === 'canceled' ? 'canceled' :
      effectiveToStatus;
    const publicStatus =
      effectiveToStatus === 'completed' ? 'completed' :
      effectiveToStatus === 'in_progress' ? 'in_progress' :
      effectiveToStatus === 'start_pending' ? 'start_pending' :
      effectiveToStatus === 'canceled' ? 'canceled' :
      'confirmed';
    cleanerIdForStatusUpdate = slot.cleanerId || null;
    subscriptionId = slot.subscriptionId || null;
    sourceOrderId = String(slot.sourceOrderId || slot.customerOrderId || '').trim() || null;
    chatId = String(slot.chatId || '').trim() ||
      (cleanerIdForStatusUpdate ? assignmentChatId('schedule_slot', slotSnap.id, cleanerIdForStatusUpdate) : null);

    const statusPayload = {
      status: slotStatus,
      orderStatus: effectiveToStatus,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      ...(effectiveToStatus === 'completed' ? {completedAt: admin.firestore.FieldValue.serverTimestamp()} : {}),
      ...(effectiveToStatus === 'in_progress' ? {
        startedAt: slot.startedAt || admin.firestore.FieldValue.serverTimestamp()
      } : {}),
      ...(effectiveToStatus === 'start_pending' ? {
        startRequiresCustomerConfirmation: true,
        cleaningStartConfirmed: false,
        cleaningStartRejected: false,
        startRequestedAt: admin.firestore.FieldValue.serverTimestamp(),
        startRequestedBy: uid || '',
        startedAt: admin.firestore.FieldValue.serverTimestamp()
      } : {})
    };
    tx.set(slotRef, statusPayload, {merge: true});
    tx.set(db.collection('cleaner_orders').doc(String(slotId)), {
      status: publicStatus,
      orderStatus: effectiveToStatus,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      ...(effectiveToStatus === 'completed' ? {completedAt: admin.firestore.FieldValue.serverTimestamp()} : {}),
      ...(effectiveToStatus === 'in_progress' ? {
        startedAt: slot.startedAt || admin.firestore.FieldValue.serverTimestamp()
      } : {}),
      ...(effectiveToStatus === 'start_pending' ? {
        startRequiresCustomerConfirmation: true,
        cleaningStartConfirmed: false,
        cleaningStartRejected: false,
        startRequestedAt: admin.firestore.FieldValue.serverTimestamp(),
        startRequestedBy: uid || '',
        startedAt: admin.firestore.FieldValue.serverTimestamp()
      } : {})
    }, {merge: true});
    tx.set(db.collection('cleaner_shifts').doc(String(slotId)), statusPayload, {merge: true});
    if (effectiveToStatus === 'start_pending') {
      startConfirmationRequested = true;
      startNotificationScope = {
        id: slotSnap.id,
        slotId: slotSnap.id,
        orderId: sourceOrderId || slotSnap.id,
        customerId: String(slot.customerId || '').trim(),
        cleanerId: String(slot.cleanerId || '').trim(),
        cleanerName: slot.cleanerName || slot.cleaner || '',
        dateText: slot.dateText || slot.date || '',
        time: slot.time || '',
        scopeType: 'schedule_slot'
      };
    }
  });

  if (subscriptionId) {
    await refreshSubscriptionUsage(subscriptionId);
  }

  if (startConfirmationRequested && startNotificationScope) {
    await notifyCustomerCleaningStartRequested(startNotificationScope).catch((error) => {
      console.error('Failed to notify customer about cleaning start confirmation', error);
    });
    await logAdminNotification('cleaning_start_confirmation_requested', {
      orderId: startNotificationScope.orderId || '',
      slotId: startNotificationScope.slotId || '',
      customerId: startNotificationScope.customerId || '',
      cleanerId: startNotificationScope.cleanerId || '',
      cleanerName: startNotificationScope.cleanerName || '',
      dateText: startNotificationScope.dateText || '',
      time: startNotificationScope.time || '',
      scopeType: startNotificationScope.scopeType || 'schedule_slot'
    });
  }

  if (effectiveToStatus === 'completed' && chatId) {
    try {
      await ensureOrderChat(chatId);
      if (cleanerIdForStatusUpdate) {
        await sendChatMessageInternal({
          orderId: chatId,
          senderId: cleanerIdForStatusUpdate,
          senderRole: 'system',
          text: 'Уборка завершена',
          type: 'system'
        });
      }
    } catch (error) {
      console.error('Failed to post slot completion system message', error);
    }
  }
  if (['completed', 'canceled'].includes(String(effectiveToStatus || '')) && chatId) {
    try {
      await closeOrderChat(chatId, effectiveToStatus === 'completed' ? 'Визит закрыт. Чат завершен.' : 'Визит отменен. Чат закрыт.');
    } catch (error) {
      console.error('Failed to close slot chat', error);
    }
  }

  if (cleanerIdForStatusUpdate && ['completed', 'canceled'].includes(String(effectiveToStatus || ''))) {
    try {
      await recalculateCleanerStatusInternal(cleanerIdForStatusUpdate);
    } catch (error) {
      console.error('Failed to recalculate cleaner status after slot update', error);
    }
  }
}

async function resolveComplaintInternal({
  complaintId,
  status,
  resolution,
  compensationAmount = 0
}) {
  const complaintRef = db.collection('complaints').doc(complaintId);
  const snap = await complaintRef.get();
  if (!snap.exists) {
    throw new HttpsError('not-found', 'Complaint not found');
  }

  await complaintRef.set({
    status,
    resolution,
    compensationAmount,
    resolvedAt: admin.firestore.FieldValue.serverTimestamp()
  }, {merge: true});
}

exports.requestWeeklyPayout = callable(async (request) => {
  assertAdmin(request.auth);
  const cleanerId = request.data?.cleanerId || 'all';
  const results = await createPayouts(cleanerId);
  return {ok: true, results};
});

exports.requestCleanerCashout = callable(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError('unauthenticated', 'Authentication required');
  }
  const cleanerId = String(request.data?.cleanerId || request.auth.uid);
  if (cleanerId !== request.auth.uid && !isAdminAuth(request.auth)) {
    throw new HttpsError('permission-denied', 'No access to this wallet');
  }
  const payoutType = String(request.data?.payoutType || 'partial');
  if (!['partial', 'full', 'manual'].includes(payoutType)) {
    throw new HttpsError('invalid-argument', 'Unsupported payout type');
  }

  await recalculateCleanerStatusInternal(cleanerId);
  const cleanerSnap = await db.collection('cleaners').doc(cleanerId).get();
  if (!cleanerSnap.exists) {
    throw new HttpsError('not-found', 'Cleaner not found');
  }
  const cleaner = cleanerSnap.data();
  const availableAmount = payoutType === 'full'
    ? Number(cleaner.availableFullCashoutAmount || 0)
    : payoutType === 'manual'
      ? Number(cleaner.availableWithdrawalAmount || 0)
      : Number(cleaner.availableWeeklyCashoutAmount || 0);
  const requestedAmount = Math.floor(Number(request.data?.amount || availableAmount));
  if (requestedAmount <= 0 || requestedAmount > availableAmount) {
    throw new HttpsError('failed-precondition', 'Requested amount is unavailable');
  }

  const bonusPortion = Math.min(
    requestedAmount,
    Number(cleaner.unlockedBonusAmount || 0)
  );
  const gross = requestedAmount;
  const tax = 0;
  const net = requestedAmount;

  await db.collection('payouts').add({
    cleanerId,
    payoutType,
    status: 'requested',
    gross,
    tax,
    net,
    bonusPortion,
    basePortion: requestedAmount - bonusPortion,
    currency: 'KZT',
    provider: 'manual_request',
    kaspiPhone: request.data?.kaspiPhone ? String(request.data.kaspiPhone).trim() : null,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    requestedBy: request.auth.uid
  });

  await recalculateCleanerStatusInternal(cleanerId);
  return {ok: true, cleanerId, payoutType, amount: requestedAmount};
});

exports.generateSubscriptionSlots = callable(async (request) => {
  assertAdmin(request.auth);
  const subscriptionId = request.data?.subscriptionId || null;

  let query = db.collection('subscriptions').where('status', '==', 'active');
  if (subscriptionId) {
    query = db.collection('subscriptions').where(admin.firestore.FieldPath.documentId(), '==', subscriptionId);
  }

  const snap = await query.get();
  for (const doc of snap.docs) {
    const subscription = {id: doc.id, ...doc.data()};
    const sourceOrderId = subscription.sourceOrderId;
    if (!sourceOrderId) {
      continue;
    }
    const orderSnap = await db.collection('customer_orders').doc(sourceOrderId).get();
    if (!orderSnap.exists) {
      continue;
    }
    await createScheduleSlotsForSubscription(doc.id, {
      id: orderSnap.id,
      ...orderSnap.data(),
      ...subscription
    });
  }

  return {ok: true, subscriptions: snap.size};
});

exports.subscriptionSlotScheduler = onSchedule('every day 06:00', async () => {
  const today = startOfDay();
  const threshold = admin.firestore.Timestamp.fromDate(addDays(today, 7));
  const snap = await db.collection('subscriptions')
    .where('status', '==', 'active')
    .where('nextGenerationAt', '<=', threshold)
    .get();

  for (const doc of snap.docs) {
    const subscription = {id: doc.id, ...doc.data()};
    const sourceOrderId = subscription.sourceOrderId;
    if (!sourceOrderId) {
      continue;
    }
    const orderSnap = await db.collection('customer_orders').doc(sourceOrderId).get();
    if (!orderSnap.exists) {
      continue;
    }
    await createScheduleSlotsForSubscription(doc.id, {
      id: orderSnap.id,
      ...orderSnap.data(),
      ...subscription
    });
  }
});

exports.slotReminderScheduler = onSchedule('every 60 minutes', async () => {
  const now = new Date();
  const from = admin.firestore.Timestamp.fromDate(addDays(now, -1));
  const until = admin.firestore.Timestamp.fromDate(addDays(now, 2));
  const snap = await db.collection('schedule_slots')
    .where('scheduledFor', '>=', from)
    .where('scheduledFor', '<=', until)
    .get();

  for (const doc of snap.docs) {
    const slot = {id: doc.id, ...doc.data()};
    if (!activeSlotStatus(slot.status)) {
      continue;
    }

    const scheduledAt = slotScheduledAt(slot);
    const diffHours = (scheduledAt.getTime() - now.getTime()) / 3600000;
    const sent = Array.isArray(slot.remindersSent) ? slot.remindersSent.map(Number) : [];
    const dueReminders = SLOT_REMINDER_HOURS.filter((hours) => {
      return diffHours <= hours && diffHours > hours - 1 && !sent.includes(hours);
    });

    if (dueReminders.length === 0) {
      continue;
    }

    const bodyDate = `${toIsoDate(scheduledAt)} ${slot.time || '10:00 - 13:00'}`;
    const newSent = [];
    for (const hours of dueReminders) {
      const sentOk = await sendPushToUser(
        slot.customerId,
        'Напоминание об уборке Domly',
        `До уборки осталось ${hours} ч. Визит запланирован на ${bodyDate}.`,
        {
          slotId: slot.id,
          subscriptionId: slot.subscriptionId || '',
          type: 'cleaning_reminder'
        }
      );
      if (sentOk) {
        newSent.push(hours);
      }
    }

    if (newSent.length > 0) {
      await doc.ref.set({
        remindersSent: admin.firestore.FieldValue.arrayUnion(...newSent),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      }, {merge: true});
    }
  }
});

exports.flushDelayedCleanerNotifications = onSchedule(
  {schedule: 'every day 07:00', timeZone: 'Asia/Almaty'},
  async () => {
    const result = await flushDelayedCleanerNotificationsInternal(500);
    console.log('Delayed cleaner notifications flushed', result);
    return result;
  }
);

exports.expireOrderOffers = onSchedule('every 2 minutes', async () => {
  const now = admin.firestore.Timestamp.fromDate(new Date());
  const snap = await db.collection('order_offers')
    .where('status', '==', 'pending')
    .where('expiresAt', '<=', now)
    .limit(100)
    .get();
  for (const doc of snap.docs) {
    await expirePendingOfferInternal(doc.id);
  }
  const backfill = await backfillPendingAssignmentOffersInternal(20);
  if (backfill.offered > 0 || backfill.errors > 0) {
    console.log('Pending assignment offer backfill', backfill);
  }
});

exports.reassignUnconfirmedTomorrowOrders = onSchedule('every 30 minutes', async () => {
  const now = admin.firestore.Timestamp.fromDate(new Date());
  const snap = await db.collection('order_offers')
    .where('status', '==', 'pending')
    .where('assignmentType', 'in', ['tomorrow', 'future'])
    .where('expiresAt', '<=', now)
    .limit(100)
    .get();
  for (const doc of snap.docs) {
    await expirePendingOfferInternal(doc.id);
  }
});

exports.offerOrderOnPendingAssignment = onDocumentWritten(
  assignmentOfferTriggerOptions('customer_orders/{orderId}'),
  async (event) => {
    const before = event.data?.before?.exists ? (event.data.before.data() || {}) : null;
    const after = event.data?.after?.exists ? (event.data.after.data() || {}) : null;
    if (!after) {
      return;
    }
    if (String(after.orderStatus || '') !== 'pending_assignment') {
      return;
    }
    if (String(after.cleanerId || '').trim()) {
      return;
    }
    if (!scopeHasConcreteSchedule(after)) {
      return;
    }
    const hadPendingBefore = before && String(before.orderStatus || '') === 'pending_assignment';
    const routingInputChanged = before
      ? assignmentRoutingInputChanged(before, after, 'orderStatus')
      : true;
    const currentOfferChanged = String(before?.currentOfferId || '') !== String(after.currentOfferId || '');
    if (hadPendingBefore && (currentOfferChanged || !routingInputChanged)) {
      return;
    }
    await offerScopeToNextCleanerInternal('order', event.params.orderId, {
      forceRebuild: !hadPendingBefore || routingInputChanged
    });
  }
);

exports.offerScheduleSlotOnPendingAssignment = onDocumentWritten(
  assignmentOfferTriggerOptions('schedule_slots/{slotId}'),
  async (event) => {
    const before = event.data?.before?.exists ? (event.data.before.data() || {}) : null;
    const after = event.data?.after?.exists ? (event.data.after.data() || {}) : null;
    if (!after) {
      return;
    }
    if (String(after.status || '') !== 'pending_assignment') {
      return;
    }
    if (String(after.cleanerId || '').trim()) {
      return;
    }
    if (!scopeHasConcreteSchedule(after)) {
      return;
    }
    const hadPendingBefore = before && String(before.status || '') === 'pending_assignment';
    const routingInputChanged = before
      ? assignmentRoutingInputChanged(before, after, 'status')
      : true;
    const currentOfferChanged = String(before?.currentOfferId || '') !== String(after.currentOfferId || '');
    if (hadPendingBefore && (currentOfferChanged || !routingInputChanged)) {
      return;
    }
    await offerScopeToNextCleanerInternal('schedule_slot', event.params.slotId, {
      forceRebuild: !hadPendingBefore || routingInputChanged,
      preferredCleanerId: String(after.preferredCleanerId || '').trim() || null
    });
  }
);

exports.recalculateScheduleOnAddonUpdate = onDocumentWritten(
  'customer_orders/{orderId}',
  async (event) => {
    const before = event.data?.before?.exists ? (event.data.before.data() || {}) : null;
    const after = event.data?.after?.exists ? (event.data.after.data() || {}) : null;
    if (!after) {
      return;
    }
    const beforeAddons = JSON.stringify(before?.addonsDetailed || before?.addons || []);
    const afterAddons = JSON.stringify(after.addonsDetailed || after.addons || []);
    if (beforeAddons === afterAddons) {
      return;
    }
    const status = String(after.orderStatus || after.status || '');
    if (!['pending_assignment', 'assigned', 'in_progress'].includes(status)) {
      return;
    }
    await recalculateScheduleAfterAddonInternal(event.params.orderId);
    await notifyCleanerUpdateInternal({
      orderId: event.params.orderId,
      customBody: 'Клиент изменил доп. услуги. Проверьте обновленную длительность уборки.',
      type: 'addons_update'
    });
    await notifyClientDelayInternal({
      orderId: event.params.orderId,
      mode: 'addons_update'
    });
  }
);

exports.notifyOnScheduleSlotChanged = onDocumentWritten(
  'schedule_slots/{slotId}',
  async (event) => {
    const before = event.data?.before?.exists ? (event.data.before.data() || {}) : null;
    const after = event.data?.after?.exists ? (event.data.after.data() || {}) : null;
    if (!before || !after) {
      return;
    }
    const orderId = String(after.sourceOrderId || after.customerOrderId || '');
    if (!orderId) {
      return;
    }
    const beforeStatus = String(before.status || before.orderStatus || '').toLowerCase();
    const afterStatus = String(after.status || after.orderStatus || '').toLowerCase();
    if (afterStatus === 'canceled' || afterStatus === 'cancelled') {
      return;
    }
    const scheduleChanged =
      String(before.time || '') !== String(after.time || '') ||
      String(before.scheduledDateKey || '') !== String(after.scheduledDateKey || '') ||
      String(before.cleanerId || '') !== String(after.cleanerId || '') ||
      beforeStatus !== afterStatus;
    if (!scheduleChanged) {
      return;
    }
    const details = `${String(after.scheduledDateKey || '')} ${String(after.time || '')}`.trim();
    await notifyCleanerUpdateInternal({
      orderId,
      customBody: `Расписание изменилось. Новый визит: ${details}.`,
      type: 'schedule_update'
    });
    await notifyClientDelayInternal({
      orderId,
      mode: 'delay',
      customBody: `Детали уборки обновлены. Новый визит: ${details}.`
    });
  }
);

async function resolveChecklistCustomer(orderId) {
  const normalized = String(orderId || '').trim();
  if (!normalized) {
    return null;
  }

  const slotSnap = await db.collection('schedule_slots').doc(normalized).get();
  if (slotSnap.exists) {
    const slot = slotSnap.data() || {};
    const customerId = String(slot.customerId || slot.userId || '').trim();
    if (customerId) {
      return {
        customerId,
        sourceOrderId: String(slot.sourceOrderId || slot.customerOrderId || normalized)
      };
    }
  }

  const orderSnap = await db.collection('customer_orders').doc(normalized).get();
  if (orderSnap.exists) {
    const order = orderSnap.data() || {};
    const customerId = String(order.customerId || order.userId || '').trim();
    if (customerId) {
      return {customerId, sourceOrderId: normalized};
    }
  }

  const cleanerOrderSnap = await db.collection('cleaner_orders').doc(normalized).get();
  if (cleanerOrderSnap.exists) {
    const cleanerOrder = cleanerOrderSnap.data() || {};
    const linkedOrderId = String(cleanerOrder.customerOrderId || cleanerOrder.sourceOrderId || '').trim();
    if (linkedOrderId) {
      return resolveChecklistCustomer(linkedOrderId);
    }
  }

  const linkedSlotsSnap = await db
    .collection('schedule_slots')
    .where('sourceOrderId', '==', normalized)
    .limit(1)
    .get();
  if (!linkedSlotsSnap.empty) {
    const slot = linkedSlotsSnap.docs[0].data() || {};
    const customerId = String(slot.customerId || slot.userId || '').trim();
    if (customerId) {
      return {customerId, sourceOrderId: normalized};
    }
  }

  return null;
}

exports.notifyClientOnCleanerChecklist = onDocumentWritten(
  'cleaner_checklists/{orderId}',
  async (event) => {
    const after = event.data?.after?.exists ? (event.data.after.data() || {}) : null;
    if (!after || after.clientNotificationSentAt) {
      return;
    }
    const orderId = String(event.params.orderId || after.orderId || '').trim();
    const context = await resolveChecklistCustomer(orderId);
    if (!context?.customerId) {
      console.warn('Checklist customer not found', {orderId});
      return;
    }
    const title = 'Чек-лист уборки заполнен';
    const body = 'Уборщица отметила выполненные пункты по заказу.';
    await sendPushToUser(context.customerId, title, body, {
      type: 'cleaner_checklist_completed',
      orderId,
      sourceOrderId: context.sourceOrderId || orderId,
      route: '/client/orders'
    });
    await event.data.after.ref.set({
      clientNotificationSentAt: admin.firestore.FieldValue.serverTimestamp(),
      clientNotificationUserId: context.customerId
    }, {merge: true});
  }
);

exports.notifyHouseProgress = onSchedule('every 24 hours', async () => {
  return null;
});

exports.monthlyTierResetScheduler = onSchedule('every day 01:00', async () => {
  const now = new Date();
  if (now.getDate() !== 1) {
    return;
  }
  await resetMonthlyStatsInternal({now});
});

exports.cleanerStatusScheduler = onSchedule('every day 02:00', async () => {
  const snap = await db.collection('cleaners').get();
  for (const doc of snap.docs) {
    await recalculateCleanerStatusInternal(doc.id, {cleanerSnap: doc});
  }
});

exports.weeklyPayoutScheduler = onSchedule('every monday 09:00', async () => {
  await createPayouts('all');
});

exports.recalculateCleanerStatusOnReview = onDocumentCreated(
  'order_reviews/{orderId}',
  async (event) => {
    const data = event.data?.data();
    if (!data) {
      return;
    }
    const orderId = data.orderId || event.params.orderId;
    const orderSnap = await db.collection('customer_orders').doc(String(orderId)).get();
    if (!orderSnap.exists) {
      return;
    }
    const order = orderSnap.data();
    if (!order?.cleanerId) {
      return;
    }
    await recalculateCleanerStatusInternal(String(order.cleanerId));
  }
);

exports.recalculateCleanerStatusOnComplaint = onDocumentCreated(
  'complaints/{complaintId}',
  async (event) => {
    const data = event.data?.data();
    if (!data?.orderId) {
      return;
    }
    const orderId = String(data.orderId);
    const orderSnap = await db.collection('customer_orders').doc(orderId).get();
    const sourceSnap = orderSnap.exists
      ? orderSnap
      : await db.collection('schedule_slots').doc(orderId).get();
    if (!sourceSnap.exists) {
      return;
    }
    const source = sourceSnap.data();
    if (!source?.cleanerId) {
      return;
    }
    await recalculateCleanerStatusInternal(String(source.cleanerId));
  }
);

exports.notifyOnVideoPublished = onDocumentWritten(
  'videoContent/{videoId}',
  async (event) => {
    const beforeExists = event.data.before.exists;
    const afterExists = event.data.after.exists;
    if (!afterExists) {
      return;
    }

    const before = beforeExists ? event.data.before.data() : null;
    const after = event.data.after.data();
    if (!after || after.isActive !== true) {
      return;
    }

    const wasActive = before?.isActive === true;
    if (wasActive) {
      return;
    }

    await notifyUsersAboutVideo(event.params.videoId, after);
  }
);

exports.notifyAdminsOnCustomerCreated = onDocumentCreated(
  'users/{userId}',
  async (event) => {
    const data = event.data?.data() || {};
    await notifyAdminsOnce(
      'admin_customer_created',
      event.params.userId,
      'Новый клиент',
      adminDisplayName({...data, userId: event.params.userId}),
      {userId: event.params.userId, route: '/admin/web'}
    );
  }
);

exports.notifyAdminsOnCustomerProfileCreated = onDocumentCreated(
  'customers/{userId}',
  async (event) => {
    const data = event.data?.data() || {};
    await notifyAdminsOnce(
      'admin_customer_created',
      event.params.userId,
      'Новый клиент',
      adminDisplayName({...data, userId: event.params.userId}),
      {userId: event.params.userId, route: '/admin/web'}
    );
  }
);

exports.notifyAdminsOnCleanerCreated = onDocumentCreated(
  'cleaners/{cleanerId}',
  async (event) => {
    const data = event.data?.data() || {};
    await notifyAdminsOnce(
      'admin_cleaner_created',
      event.params.cleanerId,
      'Новая уборщица',
      adminDisplayName({...data, cleanerId: event.params.cleanerId}),
      {cleanerId: event.params.cleanerId, route: '/admin/web'}
    );
  }
);

exports.notifyAdminsOnCleanerChanged = onDocumentWritten(
  'cleaners/{cleanerId}',
  async (event) => {
    const before = event.data?.before?.exists ? (event.data.before.data() || {}) : null;
    const after = event.data?.after?.exists ? (event.data.after.data() || {}) : null;
    if (!before || !after) {
      return;
    }
    const fields = ['status', 'verificationStatus', 'isApproved', 'approved'];
    const changed = fields.some((field) => String(before[field] ?? '') !== String(after[field] ?? ''));
    if (!changed) {
      return;
    }
    const status = String(after.verificationStatus || after.status || after.isApproved || after.approved || '').trim();
    await notifyAdminsOnce(
      'admin_cleaner_status_changed',
      event.params.cleanerId,
      'Статус уборщицы изменен',
      `${adminDisplayName({...after, cleanerId: event.params.cleanerId})}: ${status || 'обновлено'}`,
      {cleanerId: event.params.cleanerId, status, route: '/admin/web'},
      status
    );
  }
);

exports.notifyAdminsOnOrderCreated = onDocumentCreated(
  'customer_orders/{orderId}',
  async (event) => {
    const data = event.data?.data() || {};
    const orderLabel = adminOrderLabel(data, event.params.orderId);
    const amount = adminMoney(data.totalAmount || data.amount || data.price);
    await notifyAdminsOnce(
      'admin_order_created',
      event.params.orderId,
      'Новый заказ',
      `Заказ ${orderLabel}${amount ? `, ${amount}` : ''}: ${adminDisplayName(data)}`,
      {orderId: event.params.orderId, orderNumber: orderLabel, route: '/admin/web'}
    );
  }
);

exports.notifyAdminsOnOrderChanged = onDocumentWritten(
  'customer_orders/{orderId}',
  async (event) => {
    const before = event.data?.before?.exists ? (event.data.before.data() || {}) : null;
    const after = event.data?.after?.exists ? (event.data.after.data() || {}) : null;
    if (!before || !after) {
      return;
    }
    const signature = [
      after.status,
      after.orderStatus,
      after.paymentStatus,
      after.cleanerId,
      JSON.stringify(after.addonsDetailed || after.addons || [])
    ].map((value) => String(value ?? '')).join('|');
    const beforeSignature = [
      before.status,
      before.orderStatus,
      before.paymentStatus,
      before.cleanerId,
      JSON.stringify(before.addonsDetailed || before.addons || [])
    ].map((value) => String(value ?? '')).join('|');
    if (signature === beforeSignature) {
      return;
    }
    const orderLabel = adminOrderLabel(after, event.params.orderId);
    const status = String(after.orderStatus || after.status || after.paymentStatus || '').trim();
    await notifyAdminsOnce(
      'admin_order_changed',
      event.params.orderId,
      'Заказ обновлен',
      `Заказ ${orderLabel}: ${status || 'изменены детали'}`,
      {orderId: event.params.orderId, orderNumber: orderLabel, status, route: '/admin/web'},
      signature
    );
  }
);

exports.notifyAdminsOnScheduleSlotChanged = onDocumentWritten(
  'schedule_slots/{slotId}',
  async (event) => {
    const before = event.data?.before?.exists ? (event.data.before.data() || {}) : null;
    const after = event.data?.after?.exists ? (event.data.after.data() || {}) : null;
    if (!after) {
      return;
    }
    const signature = [after.status, after.orderStatus, after.paymentStatus, after.cleanerId, after.scheduledDateKey, after.time]
      .map((value) => String(value ?? '')).join('|');
    const beforeSignature = before
      ? [before.status, before.orderStatus, before.paymentStatus, before.cleanerId, before.scheduledDateKey, before.time]
        .map((value) => String(value ?? '')).join('|')
      : '';
    if (before && signature === beforeSignature) {
      return;
    }
    const orderId = String(after.sourceOrderId || after.customerOrderId || event.params.slotId);
    await notifyAdminsOnce(
      'admin_schedule_changed',
      event.params.slotId,
      before ? 'Расписание обновлено' : 'Новый слот уборки',
      `${String(after.scheduledDateKey || '')} ${String(after.time || '')}`.trim() || `Заказ ${orderId}`,
      {slotId: event.params.slotId, orderId, route: '/admin/web'},
      signature
    );
  }
);

exports.notifyAdminsOnPaymentWritten = onDocumentWritten(
  'payments/{paymentId}',
  async (event) => {
    const before = event.data?.before?.exists ? (event.data.before.data() || {}) : null;
    const after = event.data?.after?.exists ? (event.data.after.data() || {}) : null;
    if (!after) {
      return;
    }
    const signature = [after.status, after.amount, after.orderId, after.paymentMethod, after.provider]
      .map((value) => String(value ?? '')).join('|');
    const beforeSignature = before
      ? [before.status, before.amount, before.orderId, before.paymentMethod, before.provider]
        .map((value) => String(value ?? '')).join('|')
      : '';
    if (before && signature === beforeSignature) {
      return;
    }
    await notifyAdminsOnce(
      'admin_payment_changed',
      event.params.paymentId,
      before ? 'Платеж обновлен' : 'Новый платеж',
      `${adminMoney(after.amount || after.totalAmount)} ${String(after.status || '').trim()}`.trim(),
      {
        paymentId: event.params.paymentId,
        orderId: String(after.orderId || ''),
        route: '/admin/web?section=payments'
      },
      signature
    );

    const paymentType = String(after.type || '').trim();
    const status = String(after.status || after.paymentStatus || '').trim();
    const customerId = String(after.customerId || after.userId || '').trim();
    const amount = Number(after.amount || after.price || 0);
    if (
      paymentType === 'area_recalculation' &&
      customerId &&
      amount > 0 &&
      ['pending_invoice', 'invoice_requested', 'initiated'].includes(status)
    ) {
      await notifyAdminsOnce(
        'customer_area_recalculation_payment',
        event.params.paymentId,
        'Перерасчет площади',
        `К доплате ${Math.round(amount)} ₸ после проверки площади.`,
        {paymentId: event.params.paymentId, customerId, route: '/admin/web?section=payments'},
        signature
      );
      await sendPushToUser(
        customerId,
        'Перерасчет площади',
        `После проверки площади сформирована доплата ${Math.round(amount)} ₸.`,
        {
          type: 'area_recalculation_payment',
          paymentId: event.params.paymentId,
          orderId: String(after.orderId || ''),
          amount: String(Math.round(amount)),
          route: '/client/payment-history'
        }
      );
    }
  }
);

exports.notifyAdminsOnComplaintCreated = onDocumentCreated(
  'complaints/{complaintId}',
  async (event) => {
    const data = event.data?.data() || {};
    await notifyAdminsOnce(
      'admin_complaint_created',
      event.params.complaintId,
      'Новая жалоба',
      `${adminDisplayName(data)}: ${String(data.text || data.message || data.reason || '').slice(0, 90)}`,
      {complaintId: event.params.complaintId, orderId: String(data.orderId || ''), route: '/admin/web'}
    );
  }
);

exports.notifyAdminsOnReviewCreated = onDocumentCreated(
  'order_reviews/{reviewId}',
  async (event) => {
    const data = event.data?.data() || {};
    const rating = String(data.rating || data.cleanerRating || data.customerRating || '').trim();
    await notifyAdminsOnce(
      'admin_review_created',
      event.params.reviewId,
      'Новый отзыв',
      `${adminDisplayName(data)}${rating ? `, оценка ${rating}` : ''}`,
      {reviewId: event.params.reviewId, orderId: String(data.orderId || ''), route: '/admin/web'}
    );
  }
);

exports.notifyAdminsOnAreaReportCreated = onDocumentCreated(
  'areaMismatchReports/{reportId}',
  async (event) => {
    const data = event.data?.data() || {};
    await notifyAdminsOnce(
      'admin_area_report_created',
      event.params.reportId,
      'Проверка площади',
      `${adminDisplayName(data)}: заявка на контроль квадратуры`,
      {reportId: event.params.reportId, userId: String(data.userId || data.customerId || ''), route: '/admin/web'}
    );
  }
);

exports.notifyAdminsOnHouseWaitlistCreated = onDocumentCreated(
  'house_waitlist/{waitlistId}',
  async (event) => {
    const data = event.data?.data() || {};
    await notifyAdminsOnce(
      'admin_house_waitlist_created',
      event.params.waitlistId,
      'Новая заявка на адрес',
      String(data.address || data.houseTitle || data.houseId || event.params.waitlistId),
      {waitlistId: event.params.waitlistId, userId: String(data.userId || ''), route: '/admin/web'}
    );
  }
);

exports.processAdminAction = onDocumentCreated(
  'admin_actions/{actionId}',
  async (event) => {
    const data = event.data?.data();
    if (!data) {
      return;
    }

    try {
      if (data.type === 'order_status') {
        await advanceOrderStatusInternal({
          orderId: data.orderId,
          toStatus: data.toStatus,
          adminMode: true
        });
      } else if (data.type === 'assign_cleaner') {
        await assignCleanerInternal({
          orderId: data.orderId,
          cleanerId: data.cleanerId,
          cleanerName: data.cleanerName,
          scheduledDate: data.scheduledDate || null,
          time: data.time || null,
          address: data.address || null
        });
      } else if (data.type === 'complaint_resolution') {
        await resolveComplaintInternal({
          complaintId: data.complaintId,
          status: data.status || 'resolved',
          resolution: data.resolution || '',
          compensationAmount: Number(data.compensationAmount || 0)
        });
      }

      await event.data.ref.set({
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
        processingStatus: 'done'
      }, {merge: true});
    } catch (error) {
      await event.data.ref.set({
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
        processingStatus: 'failed',
        processingError: String(error)
      }, {merge: true});
    }
  }
);

// Automatically generate a referral code when a new customer document is created
exports.ensureReferralLinkOnCustomerCreated = onDocumentCreated(
  'customers/{customerId}',
  async (event) => {
    const customerId = event.params.customerId;
    if (!customerId) return;
    try {
      await ensureReferralLinkInternal(customerId);
    } catch (error) {
      console.error(`Failed to generate referral link for customer ${customerId}:`, error);
    }
  }
);

// One-time backfill: generate referral codes for existing customers without them
exports.backfillReferralCodes = onSchedule(
  'every 24 hours',
  async () => {
    if (process.env.BACKFILL_REFERRAL_CODES !== 'true') {
      return {skipped: true, reason: 'Set BACKFILL_REFERRAL_CODES=true to enable'};
    }
    console.log('Starting referral code backfill...');
    // Query for customers with empty referralCode (Firestore doesn't index missing fields with ==)
    const snapshot = await db.collection('customers')
      .where('referralCode', '==', '')
      .limit(500)
      .get();
    if (snapshot.empty) {
      console.log('No customers without referral codes found. Backfill complete.');
      return {ok: true, processed: 0};
    }
    let processed = 0;
    let errors = 0;
    for (const doc of snapshot.docs) {
      try {
        await ensureReferralLinkInternal(doc.id);
        processed++;
      } catch (error) {
        console.error(`Failed to generate referral code for ${doc.id}:`, error);
        errors++;
      }
    }
    console.log(`Backfill complete: ${processed} processed, ${errors} errors`);
    return {ok: true, processed, errors};
  }
);

module.exports.__test__ = {
  estimateCleaningDuration,
  estimateCleaningDurationMinutes,
  buildSchedulerMetrics,
  buildTimeRangeForDuration,
  timeRangesOverlap,
  assignmentTypeForDate,
  cleanerStatusEligibleForAssignment,
  cleanerWorksOnDate,
  serviceAreaMatches,
  filterCleanersByServiceArea,
  evaluateCleanerAssignmentCandidate,
  offerScopeToNextCleanerInternal
};
