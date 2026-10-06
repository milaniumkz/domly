/// Data models for DOMLY app
/// Replaces Map<String, dynamic> with typed models for safety and clarity

// ============================================================================
// CUSTOMER MODEL
// ============================================================================

class Customer {
  final String id;
  final String? name;
  final String? phone;
  final String? email;
  final String? gender;
  final String? residentialComplex;
  final String? address;
  final double? apartmentArea;
  final String? referralCode;
  final String? referredByCode;
  final int bonusPoints;
  final String tier;
  final double monthlySpent;
  final int monthlyOrders;
  final double totalSpent;
  final int tierDiscountPercent;
  final int referralDiscountPercent;
  final int referralQualifiedCount;
  final bool areaVerified;
  final String? areaTechnicalPlanUrl;
  final DateTime? areaVerifiedAt;
  final List<String>? menu;

  const Customer({
    required this.id,
    this.name,
    this.phone,
    this.email,
    this.gender,
    this.residentialComplex,
    this.address,
    this.apartmentArea,
    this.referralCode,
    this.referredByCode,
    this.bonusPoints = 0,
    this.tier = 'NEWBIE',
    this.monthlySpent = 0,
    this.monthlyOrders = 0,
    this.totalSpent = 0,
    this.tierDiscountPercent = 0,
    this.referralDiscountPercent = 0,
    this.referralQualifiedCount = 0,
    this.areaVerified = false,
    this.areaTechnicalPlanUrl,
    this.areaVerifiedAt,
    this.menu,
  });

  factory Customer.fromFirestore(String id, Map<String, dynamic> data) {
    return Customer(
      id: id,
      name: data['name'] as String?,
      phone: data['phone'] as String?,
      email: data['email'] as String?,
      gender: data['gender'] as String?,
      residentialComplex: data['residentialComplex'] as String?,
      address: data['address'] as String?,
      apartmentArea: (data['apartmentArea'] as num?)?.toDouble(),
      referralCode: data['referralCode'] as String?,
      referredByCode: data['referredByCode'] as String?,
      bonusPoints: (data['bonusPoints'] as num?)?.toInt() ?? 0,
      tier: (data['tier'] as String?) ?? 'NEWBIE',
      monthlySpent: (data['monthly_spent'] as num?)?.toDouble() ?? 0,
      monthlyOrders: (data['monthly_orders'] as num?)?.toInt() ?? 0,
      totalSpent: (data['total_spent'] as num?)?.toDouble() ?? 0,
      tierDiscountPercent:
          (data['tier_discount_percent'] as num?)?.toInt() ?? 0,
      referralDiscountPercent:
          (data['referralDiscountPercent'] as num?)?.toInt() ?? 0,
      referralQualifiedCount:
          (data['referralQualifiedCount'] as num?)?.toInt() ?? 0,
      areaVerified: data['areaVerified'] == true,
      areaTechnicalPlanUrl: data['areaTechnicalPlanUrl'] as String?,
      areaVerifiedAt: data['areaVerifiedAt'] != null
          ? (data['areaVerifiedAt'] as dynamic).toDate()
          : null,
      menu: data['menu'] is List
          ? (data['menu'] as List).map((e) => e.toString()).toList()
          : null,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      if (name != null) 'name': name,
      if (phone != null) 'phone': phone,
      if (email != null) 'email': email,
      if (gender != null) 'gender': gender,
      if (residentialComplex != null) 'residentialComplex': residentialComplex,
      if (address != null) 'address': address,
      if (apartmentArea != null) 'apartmentArea': apartmentArea,
      if (referralCode != null) 'referralCode': referralCode,
      if (referredByCode != null) 'referredByCode': referredByCode,
      'bonusPoints': bonusPoints,
      'tier': tier,
      'monthly_spent': monthlySpent,
      'monthly_orders': monthlyOrders,
      'total_spent': totalSpent,
      'tier_discount_percent': tierDiscountPercent,
      'referralDiscountPercent': referralDiscountPercent,
      'referralQualifiedCount': referralQualifiedCount,
      'areaVerified': areaVerified,
      if (areaTechnicalPlanUrl != null)
        'areaTechnicalPlanUrl': areaTechnicalPlanUrl,
      if (areaVerifiedAt != null) 'areaVerifiedAt': areaVerifiedAt,
      if (menu != null) 'menu': menu,
    };
  }

  Customer copyWith({
    String? name,
    String? phone,
    String? email,
    String? gender,
    String? residentialComplex,
    String? address,
    double? apartmentArea,
    String? referralCode,
    String? referredByCode,
    int? bonusPoints,
    String? tier,
    double? monthlySpent,
    int? monthlyOrders,
    double? totalSpent,
    int? tierDiscountPercent,
    int? referralDiscountPercent,
    int? referralQualifiedCount,
    bool? areaVerified,
    String? areaTechnicalPlanUrl,
    DateTime? areaVerifiedAt,
    List<String>? menu,
  }) {
    return Customer(
      id: id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      gender: gender ?? this.gender,
      residentialComplex: residentialComplex ?? this.residentialComplex,
      address: address ?? this.address,
      apartmentArea: apartmentArea ?? this.apartmentArea,
      referralCode: referralCode ?? this.referralCode,
      referredByCode: referredByCode ?? this.referredByCode,
      bonusPoints: bonusPoints ?? this.bonusPoints,
      tier: tier ?? this.tier,
      monthlySpent: monthlySpent ?? this.monthlySpent,
      monthlyOrders: monthlyOrders ?? this.monthlyOrders,
      totalSpent: totalSpent ?? this.totalSpent,
      tierDiscountPercent: tierDiscountPercent ?? this.tierDiscountPercent,
      referralDiscountPercent:
          referralDiscountPercent ?? this.referralDiscountPercent,
      referralQualifiedCount:
          referralQualifiedCount ?? this.referralQualifiedCount,
      areaVerified: areaVerified ?? this.areaVerified,
      areaTechnicalPlanUrl: areaTechnicalPlanUrl ?? this.areaTechnicalPlanUrl,
      areaVerifiedAt: areaVerifiedAt ?? this.areaVerifiedAt,
      menu: menu ?? this.menu,
    );
  }
}

// ============================================================================
// ORDER MODEL
// ============================================================================

class Order {
  final String id;
  final String customerId;
  final String? cleanerId;
  final String? cleanerName;
  final String status;
  final String orderStatus;
  final String paymentStatus;
  final String? package;
  final String? frequencyLabel;
  final int price;
  final String currency;
  final String form;
  final String? accessMethod;
  final String? residentialComplex;
  final String? address;
  final int? area;
  final int rooms;
  final int bathrooms;
  final List<String>? addons;
  final List<Map<String, dynamic>>? addonsDetailed;
  final int billingPeriodMonths;
  final int bonusToSpend;
  final int bonusAppliedAmount;
  final String? subscriptionId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? paidAt;

  const Order({
    required this.id,
    required this.customerId,
    this.cleanerId,
    this.cleanerName,
    this.status = 'created',
    this.orderStatus = 'pending_payment',
    this.paymentStatus = 'initiated',
    this.package,
    this.frequencyLabel,
    this.price = 0,
    this.currency = 'KZT',
    this.form = 'standard',
    this.accessMethod,
    this.residentialComplex,
    this.address,
    this.area,
    this.rooms = 0,
    this.bathrooms = 0,
    this.addons,
    this.addonsDetailed,
    this.billingPeriodMonths = 1,
    this.bonusToSpend = 0,
    this.bonusAppliedAmount = 0,
    this.subscriptionId,
    this.createdAt,
    this.updatedAt,
    this.paidAt,
  });

  factory Order.fromFirestore(String id, Map<String, dynamic> data) {
    return Order(
      id: id,
      customerId: data['customerId'] as String? ?? '',
      cleanerId: data['cleanerId'] as String?,
      cleanerName: data['cleanerName'] as String?,
      status: data['status'] as String? ?? 'created',
      orderStatus: data['orderStatus'] as String? ?? 'pending_payment',
      paymentStatus: data['paymentStatus'] as String? ?? 'initiated',
      package: data['package'] as String?,
      frequencyLabel: data['frequencyLabel'] as String?,
      price: (data['price'] as num?)?.toInt() ?? 0,
      currency: data['currency'] as String? ?? 'KZT',
      form: data['form'] as String? ?? 'standard',
      accessMethod: data['accessMethod'] as String?,
      residentialComplex: data['residentialComplex'] as String?,
      address: data['address'] as String?,
      area: (data['area'] as num?)?.toInt(),
      rooms: (data['rooms'] as num?)?.toInt() ?? 0,
      bathrooms: (data['bathrooms'] as num?)?.toInt() ?? 0,
      addons: data['addons'] is List
          ? (data['addons'] as List).map((e) => e.toString()).toList()
          : null,
      addonsDetailed: data['addonsDetailed'] is List
          ? (data['addonsDetailed'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList()
          : null,
      billingPeriodMonths: (data['billingPeriodMonths'] as num?)?.toInt() ?? 1,
      bonusToSpend: (data['bonusToSpend'] as num?)?.toInt() ?? 0,
      bonusAppliedAmount: (data['bonusAppliedAmount'] as num?)?.toInt() ?? 0,
      subscriptionId: data['subscriptionId'] as String?,
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as dynamic).toDate()
          : null,
      updatedAt: data['updatedAt'] != null
          ? (data['updatedAt'] as dynamic).toDate()
          : null,
      paidAt:
          data['paidAt'] != null ? (data['paidAt'] as dynamic).toDate() : null,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'customerId': customerId,
      if (cleanerId != null) 'cleanerId': cleanerId,
      if (cleanerName != null) 'cleanerName': cleanerName,
      'status': status,
      'orderStatus': orderStatus,
      'paymentStatus': paymentStatus,
      if (package != null) 'package': package,
      if (frequencyLabel != null) 'frequencyLabel': frequencyLabel,
      'price': price,
      'currency': currency,
      'form': form,
      if (accessMethod != null) 'accessMethod': accessMethod,
      if (residentialComplex != null) 'residentialComplex': residentialComplex,
      if (address != null) 'address': address,
      if (area != null) 'area': area,
      'rooms': rooms,
      'bathrooms': bathrooms,
      if (addons != null) 'addons': addons,
      if (addonsDetailed != null) 'addonsDetailed': addonsDetailed,
      'billingPeriodMonths': billingPeriodMonths,
      'bonusToSpend': bonusToSpend,
      'bonusAppliedAmount': bonusAppliedAmount,
      if (subscriptionId != null) 'subscriptionId': subscriptionId,
    };
  }

  bool get isPaid => paymentStatus.toLowerCase() == 'paid';
  bool get isPending {
    final normalizedOrderStatus = orderStatus.toLowerCase();
    final normalizedPaymentStatus = paymentStatus.toLowerCase();
    return normalizedOrderStatus == 'pending_payment' ||
        normalizedOrderStatus == 'pending_assignment' ||
        normalizedPaymentStatus == 'pending_invoice' ||
        normalizedPaymentStatus == 'invoice_requested' ||
        normalizedPaymentStatus == 'initiated';
  }

  bool get isCompleted => orderStatus.toLowerCase() == 'completed';
  bool get isCanceled {
    final normalizedOrderStatus = orderStatus.toLowerCase();
    return normalizedOrderStatus == 'canceled' ||
        normalizedOrderStatus == 'cancelled';
  }
}

// ============================================================================
// PAYMENT MODEL
// ============================================================================

class Payment {
  final String id;
  final String orderId;
  final String customerId;
  final int amount;
  final String currency;
  final String status; // initiated, pending, paid, failed, canceled
  final DateTime? createdAt;
  final DateTime? paidAt;
  final DateTime? updatedAt;

  const Payment({
    required this.id,
    required this.orderId,
    required this.customerId,
    required this.amount,
    this.currency = 'KZT',
    this.status = 'initiated',
    this.createdAt,
    this.paidAt,
    this.updatedAt,
  });

  factory Payment.fromFirestore(String id, Map<String, dynamic> data) {
    return Payment(
      id: id,
      orderId: data['orderId'] as String? ?? id,
      customerId: data['customerId'] as String? ?? '',
      amount: (data['amount'] as num?)?.toInt() ?? 0,
      currency: data['currency'] as String? ?? 'KZT',
      status: data['status'] as String? ?? 'initiated',
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as dynamic).toDate()
          : null,
      paidAt:
          data['paidAt'] != null ? (data['paidAt'] as dynamic).toDate() : null,
      updatedAt: data['updatedAt'] != null
          ? (data['updatedAt'] as dynamic).toDate()
          : null,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'orderId': orderId,
      'customerId': customerId,
      'amount': amount,
      'currency': currency,
      'status': status,
    };
  }

  bool get isPaid => status.toLowerCase() == 'paid';
  bool get isFailed => status.toLowerCase() == 'failed';
  bool get isPending {
    final normalizedStatus = status.toLowerCase();
    return normalizedStatus == 'pending' || normalizedStatus == 'initiated';
  }
}

// ============================================================================
// SUBSCRIPTION MODEL
// ============================================================================

class Subscription {
  final String id;
  final String customerId;
  final String? package;
  final String? frequencyLabel;
  final int billingPeriodMonths;
  final String status; // draft, active, paused, expired, canceled
  final int includedVisits;
  final int usedVisits;
  final int remainingVisits;
  final int scheduledVisits;
  final int selectedVisitsCount;
  final String? fixedCleanerId;
  final String? fixedCleanerName;
  final String? clusterName;
  final String? residentialComplex;
  final double? area;
  final double? estimatedDurationHours;
  final int? estimatedDurationMinutes;
  final bool scheduleSelectionRequired;
  final bool autoRenew;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final DateTime? renewalAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Subscription({
    required this.id,
    required this.customerId,
    this.package,
    this.frequencyLabel,
    this.billingPeriodMonths = 1,
    this.status = 'draft',
    this.includedVisits = 0,
    this.usedVisits = 0,
    this.remainingVisits = 0,
    this.scheduledVisits = 0,
    this.selectedVisitsCount = 0,
    this.fixedCleanerId,
    this.fixedCleanerName,
    this.clusterName,
    this.residentialComplex,
    this.area,
    this.estimatedDurationHours,
    this.estimatedDurationMinutes,
    this.scheduleSelectionRequired = false,
    this.autoRenew = false,
    this.validFrom,
    this.validUntil,
    this.renewalAt,
    this.createdAt,
    this.updatedAt,
  });

  factory Subscription.fromFirestore(String id, Map<String, dynamic> data) {
    return Subscription(
      id: id,
      customerId: data['customerId'] as String? ?? '',
      package: data['package'] as String?,
      frequencyLabel: data['frequencyLabel'] as String?,
      billingPeriodMonths: (data['billingPeriodMonths'] as num?)?.toInt() ?? 1,
      status: data['status'] as String? ?? 'draft',
      includedVisits: (data['includedVisits'] as num?)?.toInt() ?? 0,
      usedVisits: (data['usedVisits'] as num?)?.toInt() ?? 0,
      remainingVisits: (data['remainingVisits'] as num?)?.toInt() ?? 0,
      scheduledVisits: (data['scheduledVisits'] as num?)?.toInt() ?? 0,
      selectedVisitsCount: (data['selectedVisitsCount'] as num?)?.toInt() ?? 0,
      fixedCleanerId: data['fixedCleanerId'] as String?,
      fixedCleanerName: data['fixedCleanerName'] as String?,
      clusterName: data['clusterName'] as String?,
      residentialComplex: data['residentialComplex'] as String?,
      area: (data['area'] as num?)?.toDouble(),
      estimatedDurationHours:
          (data['estimatedDurationHours'] as num?)?.toDouble(),
      estimatedDurationMinutes:
          (data['estimatedDurationMinutes'] as num?)?.toInt(),
      scheduleSelectionRequired: data['scheduleSelectionRequired'] == true,
      autoRenew: data['autoRenew'] == true,
      validFrom: data['validFrom'] != null
          ? (data['validFrom'] as dynamic).toDate()
          : null,
      validUntil: data['validUntil'] != null
          ? (data['validUntil'] as dynamic).toDate()
          : null,
      renewalAt: data['renewalAt'] != null
          ? (data['renewalAt'] as dynamic).toDate()
          : null,
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as dynamic).toDate()
          : null,
      updatedAt: data['updatedAt'] != null
          ? (data['updatedAt'] as dynamic).toDate()
          : null,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'customerId': customerId,
      if (package != null) 'package': package,
      if (frequencyLabel != null) 'frequencyLabel': frequencyLabel,
      'billingPeriodMonths': billingPeriodMonths,
      'status': status,
      'includedVisits': includedVisits,
      'usedVisits': usedVisits,
      'remainingVisits': remainingVisits,
      'scheduledVisits': scheduledVisits,
      'selectedVisitsCount': selectedVisitsCount,
      if (fixedCleanerId != null) 'fixedCleanerId': fixedCleanerId,
      if (fixedCleanerName != null) 'fixedCleanerName': fixedCleanerName,
      if (clusterName != null) 'clusterName': clusterName,
      if (residentialComplex != null) 'residentialComplex': residentialComplex,
      if (area != null) 'area': area,
      if (estimatedDurationHours != null)
        'estimatedDurationHours': estimatedDurationHours,
      if (estimatedDurationMinutes != null)
        'estimatedDurationMinutes': estimatedDurationMinutes,
      'scheduleSelectionRequired': scheduleSelectionRequired,
      'autoRenew': autoRenew,
      if (validFrom != null) 'validFrom': validFrom,
      if (validUntil != null) 'validUntil': validUntil,
      if (renewalAt != null) 'renewalAt': renewalAt,
    };
  }

  bool get isActive => status.toLowerCase() == 'active';
  bool get isExpired => status.toLowerCase() == 'expired';
  bool get isPaused => status.toLowerCase() == 'paused';
  bool get needsScheduleSelection =>
      scheduleSelectionRequired && selectedVisitsCount == 0;
}

// ============================================================================
// CLEANER MODEL
// ============================================================================

class Cleaner {
  final String id;
  final String? name;
  final String? phone;
  final String? email;
  final String? homeAddress;
  final String? emergencyContactPhone;
  final String? emergencyContactRelation;
  final String status; // pending, approved, rejected
  final String cleanerStatus; // NEWBIE, RELIABLE, EXPERT, LEGEND
  final String? cleanerStatusLabel;
  final double rating;
  final int completedOrdersCount;
  final int totalCleanedArea;
  final int todayEarnings;
  final int weekEarnings;
  final int monthEarnings;
  final int totalEarned;
  final int totalWithdrawn;
  final int currentWalletBalance;
  final int lockedBonusAmount;
  final int unlockedBonusAmount;
  final int availableWithdrawalAmount;
  final DateTime? joinedAt;
  final DateTime? statusEvaluatedAt;

  const Cleaner({
    required this.id,
    this.name,
    this.phone,
    this.email,
    this.homeAddress,
    this.emergencyContactPhone,
    this.emergencyContactRelation,
    this.status = 'pending',
    this.cleanerStatus = 'NEWBIE',
    this.cleanerStatusLabel,
    this.rating = 0,
    this.completedOrdersCount = 0,
    this.totalCleanedArea = 0,
    this.todayEarnings = 0,
    this.weekEarnings = 0,
    this.monthEarnings = 0,
    this.totalEarned = 0,
    this.totalWithdrawn = 0,
    this.currentWalletBalance = 0,
    this.lockedBonusAmount = 0,
    this.unlockedBonusAmount = 0,
    this.availableWithdrawalAmount = 0,
    this.joinedAt,
    this.statusEvaluatedAt,
  });

  factory Cleaner.fromFirestore(String id, Map<String, dynamic> data) {
    return Cleaner(
      id: id,
      name: data['name'] as String?,
      phone: data['phone'] as String?,
      email: data['email'] as String?,
      homeAddress: data['homeAddress'] as String?,
      emergencyContactPhone: data['emergencyContactPhone'] as String?,
      emergencyContactRelation: data['emergencyContactRelation'] as String?,
      status: data['status'] as String? ?? 'pending',
      cleanerStatus: data['cleanerStatus'] as String? ?? 'NEWBIE',
      cleanerStatusLabel: data['cleanerStatusLabel'] as String?,
      rating: (data['rating'] as num?)?.toDouble() ?? 0,
      completedOrdersCount:
          (data['completedOrdersCount'] as num?)?.toInt() ?? 0,
      totalCleanedArea: (data['totalCleanedArea'] as num?)?.toInt() ?? 0,
      todayEarnings: (data['todayEarnings'] as num?)?.toInt() ?? 0,
      weekEarnings: (data['weekEarnings'] as num?)?.toInt() ??
          (data['weeklyEarnings'] as num?)?.toInt() ??
          0,
      monthEarnings: (data['monthEarnings'] as num?)?.toInt() ??
          (data['monthlyEarnings'] as num?)?.toInt() ??
          0,
      totalEarned: (data['totalEarned'] as num?)?.toInt() ?? 0,
      totalWithdrawn: (data['totalWithdrawn'] as num?)?.toInt() ?? 0,
      currentWalletBalance:
          (data['currentWalletBalance'] as num?)?.toInt() ?? 0,
      lockedBonusAmount: (data['lockedBonusAmount'] as num?)?.toInt() ?? 0,
      unlockedBonusAmount: (data['unlockedBonusAmount'] as num?)?.toInt() ?? 0,
      availableWithdrawalAmount:
          (data['availableWithdrawalAmount'] as num?)?.toInt() ?? 0,
      joinedAt: data['joinedAt'] != null
          ? (data['joinedAt'] as dynamic).toDate()
          : null,
      statusEvaluatedAt: data['statusEvaluatedAt'] != null
          ? (data['statusEvaluatedAt'] as dynamic).toDate()
          : null,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      if (name != null) 'name': name,
      if (phone != null) 'phone': phone,
      if (email != null) 'email': email,
      if (homeAddress != null) 'homeAddress': homeAddress,
      if (emergencyContactPhone != null)
        'emergencyContactPhone': emergencyContactPhone,
      if (emergencyContactRelation != null)
        'emergencyContactRelation': emergencyContactRelation,
      'status': status,
      'cleanerStatus': cleanerStatus,
      if (cleanerStatusLabel != null) 'cleanerStatusLabel': cleanerStatusLabel,
      'rating': rating,
      'completedOrdersCount': completedOrdersCount,
      'totalCleanedArea': totalCleanedArea,
      'todayEarnings': todayEarnings,
      'weekEarnings': weekEarnings,
      'monthEarnings': monthEarnings,
      'totalEarned': totalEarned,
      'totalWithdrawn': totalWithdrawn,
      'currentWalletBalance': currentWalletBalance,
      'lockedBonusAmount': lockedBonusAmount,
      'unlockedBonusAmount': unlockedBonusAmount,
      'availableWithdrawalAmount': availableWithdrawalAmount,
    };
  }

  String get statusDisplayText {
    switch (status) {
      case 'approved':
        return 'Одобрена';
      case 'rejected':
        return 'Отклонена';
      default:
        return 'На проверке';
    }
  }
}

// ============================================================================
// PRICE CALCULATION HELPER
// ============================================================================

class PriceCalculation {
  /// Calculate cleaning duration in minutes: area * 1.6 + 30
  static int calculateDurationMinutes(double area) {
    if (area <= 0) return 120; // minimum 2 hours
    final minutes = (area * 1.6 + 30).round();
    return minutes.clamp(0, 480); // cap at 8 hours
  }

  /// Calculate duration in hours (for backward compatibility)
  static double calculateDurationHours(double area) {
    final minutes = calculateDurationMinutes(area);
    return minutes / 60.0;
  }

  /// Calculate final price with all discounts
  static PriceBreakdown calculatePrice({
    required int basePrice,
    int tierDiscountPercent = 0,
    int referralDiscountPercent = 0,
    int bonusPoints = 0,
    int addonTotalPrice = 0,
    bool hasActiveMonthlyPackage = false,
    bool useBonuses = false,
  }) {
    // Tier discount
    final tierDiscountAmount =
        ((basePrice * tierDiscountPercent) / 100).round();
    final afterTierDiscount = basePrice - tierDiscountAmount;

    // Referral discount (applied after tier)
    final referralDiscountAmount =
        referralDiscountPercent > 0 && afterTierDiscount > 0
            ? ((afterTierDiscount * referralDiscountPercent) / 100).round()
            : 0;
    final afterReferralDiscount = afterTierDiscount - referralDiscountAmount;

    // Bonus application: up to 50% of package + add-ons after discounts.
    int appliedBonus = 0;
    if (useBonuses && afterReferralDiscount > 0) {
      final maxBonus = (afterReferralDiscount * 0.5).floor();
      appliedBonus = bonusPoints < maxBonus ? bonusPoints : maxBonus;
    }

    // Final payable amount
    final discountedAmount = afterReferralDiscount.clamp(0, basePrice);
    final payableAmount =
        (discountedAmount - appliedBonus).clamp(0, discountedAmount);

    return PriceBreakdown(
      basePrice: basePrice,
      tierDiscountPercent: tierDiscountPercent,
      tierDiscountAmount: tierDiscountAmount,
      referralDiscountPercent: referralDiscountPercent,
      referralDiscountAmount: referralDiscountAmount,
      addonTotalPrice: addonTotalPrice,
      bonusPoints: bonusPoints,
      appliedBonus: appliedBonus,
      payableAmount: payableAmount,
    );
  }
}

class PriceBreakdown {
  final int basePrice;
  final int tierDiscountPercent;
  final int tierDiscountAmount;
  final int referralDiscountPercent;
  final int referralDiscountAmount;
  final int addonTotalPrice;
  final int bonusPoints;
  final int appliedBonus;
  final int payableAmount;

  const PriceBreakdown({
    required this.basePrice,
    this.tierDiscountPercent = 0,
    this.tierDiscountAmount = 0,
    this.referralDiscountPercent = 0,
    this.referralDiscountAmount = 0,
    this.addonTotalPrice = 0,
    this.bonusPoints = 0,
    this.appliedBonus = 0,
    required this.payableAmount,
  });

  int get totalDiscount =>
      tierDiscountAmount + referralDiscountAmount + appliedBonus;
  double get effectiveDiscountPercent =>
      basePrice > 0 ? (totalDiscount / basePrice) * 100 : 0;

  Map<String, dynamic> toMap() {
    return {
      'basePrice': basePrice,
      'tierDiscountPercent': tierDiscountPercent,
      'tierDiscountAmount': tierDiscountAmount,
      'referralDiscountPercent': referralDiscountPercent,
      'referralDiscountAmount': referralDiscountAmount,
      'addonTotalPrice': addonTotalPrice,
      'bonusPoints': bonusPoints,
      'appliedBonus': appliedBonus,
      'payableAmount': payableAmount,
      'totalDiscount': totalDiscount,
      'effectiveDiscountPercent': effectiveDiscountPercent,
    };
  }
}
