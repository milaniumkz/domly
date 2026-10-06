const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const rules = fs.readFileSync(
  path.resolve(__dirname, '../../firestore.rules'),
  'utf8'
);

test('customer_orders rule does not allow direct cleanerId reassignment by client', () => {
  assert.match(
    rules,
    /match \/customer_orders\/\{orderId\}[\s\S]*changedKeys\(\)\.hasOnly\(\[\s*'status',\s*'orderStatus',\s*'paymentStatus',/m
  );
  assert.doesNotMatch(rules, /changedKeys\(\)\.hasOnly\([\s\S]*'cleanerId'/m);
});

test('order_offers remain backend-owned for writes', () => {
  assert.match(
    rules,
    /match \/order_offers\/\{offerId\}[\s\S]*allow create, update, delete: if isAdmin\(\);/m
  );
});

test('schedule_slots are not writable by cleaners or customers', () => {
  assert.match(
    rules,
    /match \/schedule_slots\/\{slotId\}[\s\S]*allow create, update, delete: if isAdmin\(\);/m
  );
});

test('cleaner_daily_schedule remains backend-owned for writes', () => {
  assert.match(
    rules,
    /match \/cleaner_daily_schedule\/\{docId\}[\s\S]*allow create, update, delete: if isAdmin\(\);/m
  );
});

test('customer_orders protected fields still exclude assignment mutation by clients', () => {
  assert.doesNotMatch(rules, /customerProtectedFieldsUnchanged\(\)[\s\S]*'currentOfferCleanerId'/m);
  assert.doesNotMatch(rules, /customerProtectedFieldsUnchanged\(\)[\s\S]*'candidateQueue'/m);
  assert.doesNotMatch(rules, /customerProtectedFieldsUnchanged\(\)[\s\S]*'timeoutBy'/m);
});

test('customer profile address and service area fields are backend-owned', () => {
  for (const field of [
    'houseId',
    'houseStatus',
    'serviceArea',
    'serviceAreaId',
    'zoneId',
    'clusterName',
    'address',
    'residentialComplex',
    'addressPlaceId',
    'addressLat',
    'addressLng',
    'addresses',
  ]) {
    assert.match(
      rules,
      new RegExp(`request\\.resource\\.data\\.${field} == resource\\.data\\.${field}`)
    );
  }
});
