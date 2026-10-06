import React, { useEffect, useState } from 'react';
import { getPackageCalendar } from '../api/calendarApi';
import { BookingCalendar } from '../components/BookingCalendar';
import { AvailableDate } from '../types/calendar';

type Props = {
  userId: string;
  packageId: string;
  userPackageId: string;
  apartmentId: string;
  requiredCount: number;
  month: string;
};

export function PackageBookingPage({ userId, packageId, userPackageId, apartmentId, requiredCount, month }: Props) {
  const [dates, setDates] = useState<AvailableDate[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    setLoading(true);
    void getPackageCalendar(packageId, userId, apartmentId, month)
      .then((payload) => setDates(payload.dates))
      .finally(() => setLoading(false));
  }, [packageId, userId, apartmentId, month]);

  if (loading) {
    return <div>Загружаем календарь...</div>;
  }

  return (
    <div style={{ maxWidth: 960, margin: '0 auto', padding: 24, display: 'grid', gap: 20 }}>
      <div>
        <h1 style={{ margin: 0 }}>Выберите даты уборок</h1>
        <p style={{ color: '#5f6c63' }}>Сначала выберите все даты, затем время для каждой уборки.</p>
      </div>
      <BookingCalendar
        packageId={packageId}
        userPackageId={userPackageId}
        apartmentId={apartmentId}
        requiredCount={requiredCount}
        availableDates={dates}
      />
    </div>
  );
}
