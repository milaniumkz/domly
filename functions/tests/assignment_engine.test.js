const test = require('node:test');
const assert = require('node:assert/strict');

const {__test__} = require('../index.js');

function enabledScheduleFor(date) {
  const weekday = date.getDay();
  return {[String(weekday)]: {enabled: true}};
}

test('cleaning duration uses business formula 1.6 min per sqm', () => {
  assert.equal(__test__.estimateCleaningDurationMinutes(220), 382);
  const metrics = __test__.buildSchedulerMetrics({
    area: 220,
    addons: ['inside_oven', 'balcony']
  });
  assert.equal(metrics.estimatedDurationMinutes, 382);
  assert.equal(metrics.addonBufferMinutes, 30);
  assert.equal(metrics.totalDurationMinutes, 427);
});

test('time overlap detection prevents intersecting orders', () => {
  assert.equal(
    __test__.timeRangesOverlap(
      {startMinutes: 600, endMinutes: 780},
      {startMinutes: 720, endMinutes: 840}
    ),
    true
  );
  assert.equal(
    __test__.timeRangesOverlap(
      {startMinutes: 540, endMinutes: 660},
      {startMinutes: 661, endMinutes: 780}
    ),
    false
  );
});

test('display time range expands to full calculated duration', () => {
  assert.equal(
    __test__.buildTimeRangeForDuration('10:00 - 13:27', 542),
    '10:00 - 19:02'
  );
});

test('full calculated duration blocks later overlapping cleaning', async () => {
  const scheduledAt = new Date(Date.now() + 26 * 60 * 60 * 1000);
  const candidate = await __test__.evaluateCleanerAssignmentCandidate({
    cleaner: {
      id: 'cleaner-full-duration',
      availabilityStatus: 'offline',
      serviceAreas: ['Auezov'],
      dailyAreaLimit: 220,
      dailyHourLimit: 12,
      workSchedule: enabledScheduleFor(scheduledAt),
      rating: 5
    },
    scope: {
      id: 'scope-full-duration',
      serviceArea: 'Auezov',
      area: 60,
      address: 'Test',
      time: '13:30 - 16:00',
      scheduledFor: scheduledAt,
      totalDurationMinutes: 180
    },
    targetDate: scheduledAt,
    assignmentType: 'tomorrow',
    monthStats: {area: 0, hours: 0, income: 0, apartments: 0},
    dayAssignments: [
      {
        id: 'existing-long',
        area: 150,
        minutes: 542,
        range: {startMinutes: 600, endMinutes: 1142}
      }
    ]
  });

  assert.equal(candidate.reasons.hasConflict, true);
  assert.equal(candidate.eligible, false);
});

test('offline cleaner is ineligible for urgent same-day order', async () => {
  const scheduledAt = new Date(Date.now() + 3 * 60 * 60 * 1000);
  const candidate = await __test__.evaluateCleanerAssignmentCandidate({
    cleaner: {
      id: 'cleaner-1',
      availabilityStatus: 'offline',
      serviceAreas: ['Auezov'],
      dailyAreaLimit: 220,
      dailyHourLimit: 510,
      workSchedule: enabledScheduleFor(scheduledAt),
      currentLocation: {lat: 43.238, lng: 76.889},
      rating: 5
    },
    scope: {
      id: 'scope-1',
      serviceArea: 'Auezov',
      area: 60,
      address: 'Test',
      time: '18:00 - 21:00',
      scheduledFor: scheduledAt,
      currentLocation: {lat: 43.239, lng: 76.89}
    },
    targetDate: scheduledAt,
    assignmentType: 'today',
    monthStats: {area: 0, hours: 0, income: 0, apartments: 0},
    dayAssignments: []
  });

  assert.equal(candidate.reasons.statusEligible, false);
  assert.equal(candidate.eligible, false);
});

test('offline cleaner may participate in tomorrow scheduling', async () => {
  const scheduledAt = new Date(Date.now() + 26 * 60 * 60 * 1000);
  const candidate = await __test__.evaluateCleanerAssignmentCandidate({
    cleaner: {
      id: 'cleaner-2',
      availabilityStatus: 'offline',
      serviceAreas: ['Auezov'],
      dailyAreaLimit: 220,
      dailyHourLimit: 510,
      workSchedule: enabledScheduleFor(scheduledAt),
      homeLocation: {lat: 43.238, lng: 76.889},
      rating: 4.9
    },
    scope: {
      id: 'scope-2',
      serviceArea: 'Auezov',
      area: 80,
      address: 'Test',
      time: '12:00 - 15:00',
      scheduledFor: scheduledAt
    },
    targetDate: scheduledAt,
    assignmentType: 'tomorrow',
    monthStats: {area: 0, hours: 0, income: 0, apartments: 0},
    dayAssignments: []
  });

  assert.equal(candidate.reasons.statusEligible, true);
  assert.equal(candidate.eligible, true);
});

test('cleaner without selected service areas is not eligible for offers', async () => {
  const scheduledAt = new Date(Date.now() + 26 * 60 * 60 * 1000);
  const candidate = await __test__.evaluateCleanerAssignmentCandidate({
    cleaner: {
      id: 'cleaner-no-area',
      availabilityStatus: 'offline',
      serviceAreas: [],
      dailyAreaLimit: 220,
      dailyHourLimit: 510,
      workSchedule: enabledScheduleFor(scheduledAt),
      rating: 5
    },
    scope: {
      id: 'scope-no-area',
      serviceArea: 'Auezov',
      area: 60,
      address: 'Auezov',
      time: '12:00 - 15:00',
      scheduledFor: scheduledAt
    },
    targetDate: scheduledAt,
    assignmentType: 'tomorrow',
    monthStats: {area: 0, hours: 0, income: 0, apartments: 0},
    dayAssignments: []
  });

  assert.equal(candidate.reasons.sameServiceArea, false);
  assert.equal(candidate.eligible, false);
});

test('cleaner receives offers only from selected service areas', async () => {
  const scheduledAt = new Date(Date.now() + 26 * 60 * 60 * 1000);
  const candidate = await __test__.evaluateCleanerAssignmentCandidate({
    cleaner: {
      id: 'cleaner-wrong-area',
      availabilityStatus: 'offline',
      serviceAreas: ['Auezov'],
      dailyAreaLimit: 220,
      dailyHourLimit: 510,
      workSchedule: enabledScheduleFor(scheduledAt),
      rating: 5
    },
    scope: {
      id: 'scope-wrong-area',
      serviceArea: 'Bostandyk',
      residentialComplex: 'ЖК Bostandyk',
      area: 60,
      address: 'Bostandyk',
      time: '12:00 - 15:00',
      scheduledFor: scheduledAt
    },
    targetDate: scheduledAt,
    assignmentType: 'tomorrow',
    monthStats: {area: 0, hours: 0, income: 0, apartments: 0},
    dayAssignments: []
  });

  assert.equal(candidate.reasons.sameServiceArea, false);
  assert.equal(candidate.eligible, false);
});

test('service area filter removes cleaners outside the order district', () => {
  const cleaners = [
    {id: 'no-area', serviceAreas: []},
    {id: 'wrong-area', serviceAreas: ['Auezov']},
    {id: 'matching-area', serviceAreas: ['Bostandyk']},
    {id: 'matching-by-house', serviceAreas: ['emerald_1']},
  ];
  const filtered = __test__.filterCleanersByServiceArea(cleaners, {
    serviceArea: 'Bostandyk',
    houseId: 'emerald_1',
    residentialComplex: 'ЖК Bostandyk',
  });

  assert.deepEqual(
    filtered.map((item) => item.id),
    ['matching-area', 'matching-by-house']
  );
  assert.equal(__test__.serviceAreaMatches(cleaners[0], {serviceArea: 'Bostandyk'}), false);
  assert.equal(__test__.serviceAreaMatches(cleaners[1], {serviceArea: 'Bostandyk'}), false);
});

test('service area matching does not use partial address matches', () => {
  const scope = {
    serviceArea: 'Бостандык',
    serviceAreaId: 'zone_bostandyk',
    zoneId: 'zone_bostandyk',
    houseId: 'house_110',
    address: 'улица Брусиловского, 110'
  };

  assert.equal(
    __test__.serviceAreaMatches({serviceAreas: ['Бостан']}, scope),
    false
  );
  assert.equal(
    __test__.serviceAreaMatches({serviceAreas: ['Брусиловского']}, scope),
    false
  );
  assert.equal(
    __test__.serviceAreaMatches({serviceAreaIds: ['zone_bostandyk']}, scope),
    true
  );
  assert.equal(
    __test__.serviceAreaMatches({serviceAreas: ['Бостандык']}, scope),
    true
  );
});

test('daily 220 sqm limit does not block cleaner when time still fits', async () => {
  const scheduledAt = new Date(Date.now() + 26 * 60 * 60 * 1000);
  const candidate = await __test__.evaluateCleanerAssignmentCandidate({
    cleaner: {
      id: 'cleaner-3',
      availabilityStatus: 'online_ready',
      serviceAreas: ['Auezov'],
      dailyAreaLimit: 220,
      dailyHourLimit: 510,
      workSchedule: enabledScheduleFor(scheduledAt),
      homeLocation: {lat: 43.238, lng: 76.889},
      rating: 5
    },
    scope: {
      id: 'scope-3',
      serviceArea: 'Auezov',
      area: 40,
      address: 'Test',
      time: '12:00 - 15:00',
      scheduledFor: scheduledAt
    },
    targetDate: scheduledAt,
    assignmentType: 'tomorrow',
    monthStats: {area: 0, hours: 0, income: 0, apartments: 0},
    dayAssignments: [
      {
        id: 'existing',
        area: 210,
        minutes: 320,
        range: {startMinutes: 480, endMinutes: 660}
      }
    ]
  });

  assert.equal(candidate.reasons.fitsAreaLimit, true);
  assert.equal(candidate.reasons.overAreaLimit, true);
  assert.equal(candidate.eligible, true);
});

test('daily time limit blocks cleaner even when area is acceptable', async () => {
  const scheduledAt = new Date(Date.now() + 26 * 60 * 60 * 1000);
  const candidate = await __test__.evaluateCleanerAssignmentCandidate({
    cleaner: {
      id: 'cleaner-time-limit',
      availabilityStatus: 'online_ready',
      serviceAreas: ['Auezov'],
      dailyAreaLimit: 220,
      dailyHourLimit: 8,
      workSchedule: enabledScheduleFor(scheduledAt),
      homeLocation: {lat: 43.238, lng: 76.889},
      rating: 5
    },
    scope: {
      id: 'scope-time-limit',
      serviceArea: 'Auezov',
      area: 20,
      address: 'Test',
      time: '17:00 - 20:00',
      scheduledFor: scheduledAt,
      totalDurationMinutes: 180
    },
    targetDate: scheduledAt,
    assignmentType: 'tomorrow',
    monthStats: {area: 0, hours: 0, income: 0, apartments: 0},
    dayAssignments: [
      {
        id: 'existing-long-day',
        area: 150,
        minutes: 420,
        range: {startMinutes: 540, endMinutes: 960}
      }
    ]
  });

  assert.equal(candidate.reasons.fitsHourLimit, false);
  assert.equal(candidate.eligible, false);
});

test('same-day order is blocked when cleaner cannot reach start after travel and prep buffer', async () => {
  const scheduledAt = new Date(Date.now() + 20 * 60 * 1000);
  const candidate = await __test__.evaluateCleanerAssignmentCandidate({
    cleaner: {
      id: 'cleaner-4',
      availabilityStatus: 'online_ready',
      serviceAreas: ['Auezov'],
      dailyAreaLimit: 220,
      dailyHourLimit: 510,
      workSchedule: enabledScheduleFor(scheduledAt),
      homeLocation: {lat: 43.1, lng: 76.5},
      rating: 5,
    },
    scope: {
      id: 'scope-4',
      serviceArea: 'Auezov',
      area: 50,
      address: 'Far away',
      time: '12:00 - 15:00',
      scheduledFor: scheduledAt,
      currentLocation: {lat: 43.35, lng: 76.95},
    },
    targetDate: scheduledAt,
    assignmentType: 'today',
    monthStats: {area: 0, hours: 0, income: 0, apartments: 0},
    dayAssignments: [],
  });

  assert.equal(candidate.reasons.canReachToday, false);
  assert.equal(candidate.eligible, false);
});

test('better cleaner gets higher aggregate score', async () => {
  const scheduledAt = new Date(Date.now() + 26 * 60 * 60 * 1000);
  const scope = {
    id: 'scope-score',
    serviceArea: 'Auezov',
    area: 90,
    address: 'Auezov',
    time: '12:00 - 15:00',
    scheduledFor: scheduledAt,
    currentLocation: {lat: 43.238, lng: 76.889},
  };
  const baseConfig = {
    serviceAreas: ['Auezov'],
    dailyAreaLimit: 220,
    dailyHourLimit: 510,
    workSchedule: enabledScheduleFor(scheduledAt),
  };

  const stronger = await __test__.evaluateCleanerAssignmentCandidate({
    cleaner: {
      id: 'cleaner-top',
      availabilityStatus: 'offline',
      homeLocation: {lat: 43.2381, lng: 76.8891},
      rating: 5,
      completedOrdersCount: 120,
      complaintsCount: 0,
      cancellationCount: 0,
      cleanerStatus: 'expert',
      ...baseConfig,
    },
    scope,
    targetDate: scheduledAt,
    assignmentType: 'tomorrow',
    monthStats: {area: 0, hours: 0, income: 0, apartments: 0},
    dayAssignments: [{id: 'existing', area: 100, minutes: 180, range: {startMinutes: 480, endMinutes: 660}}],
  });

  const weaker = await __test__.evaluateCleanerAssignmentCandidate({
    cleaner: {
      id: 'cleaner-low',
      availabilityStatus: 'offline',
      homeLocation: {lat: 43.33, lng: 76.99},
      rating: 4.1,
      completedOrdersCount: 8,
      complaintsCount: 2,
      cancellationCount: 2,
      cleanerStatus: 'newbie',
      ...baseConfig,
    },
    scope,
    targetDate: scheduledAt,
    assignmentType: 'tomorrow',
    monthStats: {area: 0, hours: 0, income: 0, apartments: 0},
    dayAssignments: [{id: 'existing', area: 30, minutes: 80, range: {startMinutes: 480, endMinutes: 560}}],
  });

  assert.equal(stronger.eligible, true);
  assert.equal(weaker.eligible, true);
  assert.ok(stronger.score > weaker.score);
});

test('assignment type distinguishes today, tomorrow and future', () => {
  const today = new Date();
  const tomorrow = new Date(Date.now() + 24 * 60 * 60 * 1000);
  const future = new Date(Date.now() + 4 * 24 * 60 * 60 * 1000);

  assert.equal(__test__.assignmentTypeForDate(today), 'today');
  assert.equal(__test__.assignmentTypeForDate(tomorrow), 'tomorrow');
  assert.equal(__test__.assignmentTypeForDate(future), 'future');
});

test('only online_ready and at_home_ready are eligible for urgent same-day assignment', () => {
  assert.equal(
    __test__.cleanerStatusEligibleForAssignment({availabilityStatus: 'online_ready'}, 'today'),
    true
  );
  assert.equal(
    __test__.cleanerStatusEligibleForAssignment({availabilityStatus: 'at_home_ready'}, 'today'),
    true
  );
  assert.equal(
    __test__.cleanerStatusEligibleForAssignment({availabilityStatus: 'offline'}, 'today'),
    false
  );
  assert.equal(
    __test__.cleanerStatusEligibleForAssignment({availabilityStatus: 'busy'}, 'today'),
    false
  );
  assert.equal(
    __test__.cleanerStatusEligibleForAssignment({availabilityStatus: 'cleaning'}, 'today'),
    false
  );
});

test('offline cleaner stays eligible for tomorrow while active field statuses remain blocked', () => {
  assert.equal(
    __test__.cleanerStatusEligibleForAssignment({availabilityStatus: 'offline'}, 'tomorrow'),
    true
  );
  assert.equal(
    __test__.cleanerStatusEligibleForAssignment({availabilityStatus: 'break'}, 'tomorrow'),
    true
  );
  assert.equal(
    __test__.cleanerStatusEligibleForAssignment({availabilityStatus: 'busy'}, 'tomorrow'),
    false
  );
  assert.equal(
    __test__.cleanerStatusEligibleForAssignment({availabilityStatus: 'on_way_to_client'}, 'tomorrow'),
    false
  );
  assert.equal(
    __test__.cleanerStatusEligibleForAssignment({availabilityStatus: 'arrived'}, 'tomorrow'),
    false
  );
  assert.equal(
    __test__.cleanerStatusEligibleForAssignment({availabilityStatus: 'cleaning'}, 'tomorrow'),
    false
  );
});
