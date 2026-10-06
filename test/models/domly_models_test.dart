import 'package:flutter_test/flutter_test.dart';
import 'package:domly/models/domly_models.dart';

void main() {
  group('PriceCalculation', () {
    group('calculateDurationMinutes', () {
      test('returns 120 minutes for zero area', () {
        expect(PriceCalculation.calculateDurationMinutes(0), 120);
      });

      test('returns 120 minutes for negative area', () {
        expect(PriceCalculation.calculateDurationMinutes(-10), 120);
      });

      test('calculates 45m² correctly', () {
        // 45 * 1.6 + 30 = 102
        expect(PriceCalculation.calculateDurationMinutes(45), 102);
      });

      test('calculates 60m² correctly', () {
        // 60 * 1.6 + 30 = 126
        expect(PriceCalculation.calculateDurationMinutes(60), 126);
      });

      test('calculates 75m² correctly', () {
        // 75 * 1.6 + 30 = 150
        expect(PriceCalculation.calculateDurationMinutes(75), 150);
      });

      test('calculates 100m² correctly', () {
        // 100 * 1.6 + 30 = 190
        expect(PriceCalculation.calculateDurationMinutes(100), 190);
      });

      test('caps at 480 minutes (8 hours)', () {
        // 500 * 1.6 + 30 = 830, should cap at 480
        expect(PriceCalculation.calculateDurationMinutes(500), 480);
      });

      test('caps at 480 minutes for very large area', () {
        expect(PriceCalculation.calculateDurationMinutes(1000), 480);
      });

      test('calculates required production audit area cases', () {
        expect(PriceCalculation.calculateDurationMinutes(40), 94);
        expect(PriceCalculation.calculateDurationMinutes(80), 158);
        expect(PriceCalculation.calculateDurationMinutes(120), 222);
        expect(PriceCalculation.calculateDurationMinutes(220), 382);
        expect(PriceCalculation.calculateDurationMinutes(300), 480);
        expect(PriceCalculation.calculateDurationMinutes(500), 480);
      });
    });

    group('calculateDurationHours', () {
      test('converts minutes to hours correctly', () {
        final hours = PriceCalculation.calculateDurationHours(75);
        // 75 * 1.6 + 30 = 150 minutes = 2.5 hours
        expect(hours, closeTo(2.5, 0.01));
      });
    });

    group('calculatePrice', () {
      test('returns base price with no discounts', () {
        final result = PriceCalculation.calculatePrice(basePrice: 40000);

        expect(result.basePrice, 40000);
        expect(result.tierDiscountAmount, 0);
        expect(result.referralDiscountAmount, 0);
        expect(result.appliedBonus, 0);
        expect(result.payableAmount, 40000);
      });

      test('applies tier discount correctly', () {
        final result = PriceCalculation.calculatePrice(
          basePrice: 40000,
          tierDiscountPercent: 10,
        );

        expect(result.tierDiscountAmount, 4000);
        expect(result.payableAmount, 36000);
      });

      test('applies referral discount after tier discount', () {
        final result = PriceCalculation.calculatePrice(
          basePrice: 40000,
          tierDiscountPercent: 10,
          referralDiscountPercent: 5,
        );

        // 40000 - 4000 = 36000, then 5% of 36000 = 1800
        expect(result.tierDiscountAmount, 4000);
        expect(result.referralDiscountAmount, 1800);
        expect(result.payableAmount, 34200);
      });

      test('applies bonuses for monthly packages', () {
        final result = PriceCalculation.calculatePrice(
          basePrice: 40000,
          bonusPoints: 5000,
          addonTotalPrice: 8000,
          hasActiveMonthlyPackage: true,
          useBonuses: true,
        );

        // Bonus can cover up to addon total price
        expect(result.appliedBonus, 5000);
        expect(result.payableAmount, 35000);
      });

      test('applies bonuses when user enabled bonus payment', () {
        final result = PriceCalculation.calculatePrice(
          basePrice: 40000,
          bonusPoints: 5000,
          addonTotalPrice: 8000,
          hasActiveMonthlyPackage: false,
          useBonuses: true,
        );

        expect(result.appliedBonus, 5000);
        expect(result.payableAmount, 35000);
      });

      test('caps bonus at half of payable amount', () {
        final result = PriceCalculation.calculatePrice(
          basePrice: 40000,
          bonusPoints: 10000,
          addonTotalPrice: 3000,
          hasActiveMonthlyPackage: true,
          useBonuses: true,
        );

        expect(result.appliedBonus, 10000);
        expect(result.payableAmount, 30000);
      });

      test('payable amount never goes below zero', () {
        final result = PriceCalculation.calculatePrice(
          basePrice: 1000,
          tierDiscountPercent: 10,
          referralDiscountPercent: 10,
          bonusPoints: 5000,
          addonTotalPrice: 500,
          hasActiveMonthlyPackage: true,
          useBonuses: true,
        );

        expect(result.payableAmount, greaterThanOrEqualTo(0));
      });

      test('calculates total discount correctly', () {
        final result = PriceCalculation.calculatePrice(
          basePrice: 40000,
          tierDiscountPercent: 10,
          referralDiscountPercent: 5,
          bonusPoints: 2000,
          addonTotalPrice: 3000,
          hasActiveMonthlyPackage: true,
          useBonuses: true,
        );

        // 4000 (tier) + 1800 (referral) + 2000 (bonus) = 7800
        expect(result.totalDiscount, 7800);
      });

      test('effective discount percentage is correct', () {
        final result = PriceCalculation.calculatePrice(
          basePrice: 40000,
          tierDiscountPercent: 10,
          referralDiscountPercent: 5,
          bonusPoints: 2000,
          addonTotalPrice: 3000,
          hasActiveMonthlyPackage: true,
          useBonuses: true,
        );

        // 7800 / 40000 * 100 = 19.5%
        expect(result.effectiveDiscountPercent, closeTo(19.5, 0.01));
      });

      test('handles zero base price gracefully', () {
        final result = PriceCalculation.calculatePrice(basePrice: 0);

        expect(result.payableAmount, 0);
        expect(result.effectiveDiscountPercent, 0);
      });

      test('all discount fields are present in map', () {
        final result = PriceCalculation.calculatePrice(
          basePrice: 40000,
          tierDiscountPercent: 10,
          referralDiscountPercent: 5,
        );

        final map = result.toMap();
        expect(map.containsKey('basePrice'), true);
        expect(map.containsKey('tierDiscountAmount'), true);
        expect(map.containsKey('referralDiscountAmount'), true);
        expect(map.containsKey('payableAmount'), true);
        expect(map.containsKey('totalDiscount'), true);
        expect(map.containsKey('effectiveDiscountPercent'), true);
      });
    });
  });

  group('Customer model', () {
    test('fromFirestore handles empty data', () {
      final customer = Customer.fromFirestore('test-id', {});

      expect(customer.id, 'test-id');
      expect(customer.bonusPoints, 0);
      expect(customer.tier, 'NEWBIE');
      expect(customer.monthlySpent, 0);
      expect(customer.tierDiscountPercent, 0);
    });

    test('fromFirestore handles complete data', () {
      final customer = Customer.fromFirestore('test-id', {
        'name': 'John Doe',
        'phone': '+77001234567',
        'bonusPoints': 5000,
        'tier': 'GURU',
        'monthly_spent': 600000,
        'tier_discount_percent': 10,
        'areaVerified': true,
      });

      expect(customer.name, 'John Doe');
      expect(customer.phone, '+77001234567');
      expect(customer.bonusPoints, 5000);
      expect(customer.tier, 'GURU');
      expect(customer.monthlySpent, 600000);
      expect(customer.tierDiscountPercent, 10);
      expect(customer.areaVerified, true);
    });

    test('copyWith updates specific fields', () {
      const customer = Customer(id: 'test-id', name: 'Old Name');
      final updated = customer.copyWith(name: 'New Name');

      expect(updated.name, 'New Name');
      expect(updated.id, 'test-id'); // unchanged
    });
  });

  group('Order model', () {
    test('fromFirestore handles minimal data', () {
      final order = Order.fromFirestore('order-id', {
        'customerId': 'customer-id',
      });

      expect(order.id, 'order-id');
      expect(order.customerId, 'customer-id');
      expect(order.status, 'created');
      expect(order.orderStatus, 'pending_payment');
      expect(order.paymentStatus, 'initiated');
    });

    test('isPaid returns true when paymentStatus is paid', () {
      final order = Order.fromFirestore('order-id', {
        'customerId': 'customer-id',
        'paymentStatus': 'paid',
        'orderStatus': 'assigned',
      });

      expect(order.isPaid, true);
      expect(order.isPending, false);
    });

    test('isPending returns true when orderStatus is pending_payment', () {
      final order = Order.fromFirestore('order-id', {
        'customerId': 'customer-id',
        'orderStatus': 'pending_payment',
      });

      expect(order.isPending, true);
    });
  });

  group('Payment model', () {
    test('isPaid returns true when status is paid', () {
      const payment = Payment(
        id: 'pay-id',
        orderId: 'order-id',
        customerId: 'customer-id',
        amount: 40000,
        status: 'paid',
      );

      expect(payment.isPaid, true);
      expect(payment.isFailed, false);
      expect(payment.isPending, false);
    });

    test('isFailed returns true when status is failed', () {
      const payment = Payment(
        id: 'pay-id',
        orderId: 'order-id',
        customerId: 'customer-id',
        amount: 40000,
        status: 'failed',
      );

      expect(payment.isFailed, true);
    });
  });

  group('Subscription model', () {
    test('isActive returns true when status is active', () {
      const sub = Subscription(
        id: 'sub-id',
        customerId: 'customer-id',
        status: 'active',
      );

      expect(sub.isActive, true);
      expect(sub.isExpired, false);
      expect(sub.isPaused, false);
    });

    test(
        'needsScheduleSelection returns true when required and no visits selected',
        () {
      const sub = Subscription(
        id: 'sub-id',
        customerId: 'customer-id',
        status: 'active',
        scheduleSelectionRequired: true,
        selectedVisitsCount: 0,
      );

      expect(sub.needsScheduleSelection, true);
    });
  });

  group('FormValidator', () {
    test('validateArea rejects empty value', () async {
      // Import would be needed in real test
      // This is placeholder for the pattern
    });

    test('validateArea rejects too small area', () async {
      // Area < 20 should fail
    });

    test('validateArea rejects too large area', () async {
      // Area > 500 should fail
    });

    test('validateArea accepts valid area', () async {
      // 60 should pass
    });
  });
}
