import React, { useEffect, useMemo, useState } from 'react';
import { getAvailableTimeSlots, bookPackageSchedule } from '../api/calendarApi';
import { AvailableDate, CleaningSlot, SelectedDateWithTime } from '../types/calendar';

type Props = {
  packageId: string;
  userPackageId: string;
  apartmentId: string;
  requiredCount: number;
  availableDates: AvailableDate[];
};

export function BookingCalendar({ packageId, userPackageId, apartmentId, requiredCount, availableDates }: Props) {
  const [selectedDates, setSelectedDates] = useState<string[]>([]);
  const [slotsByDate, setSlotsByDate] = useState<Record<string, CleaningSlot[]>>({});
  const [selected, setSelected] = useState<Record<string, SelectedDateWithTime>>({});
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    selectedDates.forEach((date) => {
      if (slotsByDate[date]) return;
      void getAvailableTimeSlots(date, apartmentId).then((slots) => {
        setSlotsByDate((prev) => ({ ...prev, [date]: slots }));
      });
    });
  }, [selectedDates, slotsByDate, apartmentId]);

  const canSubmit = useMemo(() => {
    return selectedDates.length === requiredCount && selectedDates.every((date) => !!selected[date]);
  }, [selected, selectedDates, requiredCount]);

  const toggleDate = (date: string) => {
    setSelectedDates((prev) => {
      if (prev.includes(date)) {
        const next = prev.filter((item) => item !== date);
        setSelected((current) => {
          const copy = { ...current };
          delete copy[date];
          return copy;
        });
        return next;
      }
      if (prev.length >= requiredCount) return prev;
      return [...prev, date].sort();
    });
  };

  const onSelectSlot = (date: string, slot: CleaningSlot) => {
    setSelected((prev) => ({
      ...prev,
      [date]: {
        date,
        startTime: slot.startTime,
        endTime: slot.endTime,
      },
    }));
  };

  const onSubmit = async () => {
    if (!canSubmit) return;
    setSaving(true);
    try {
      await bookPackageSchedule(packageId, userPackageId, Object.values(selected).sort((a, b) => a.date.localeCompare(b.date)));
    } finally {
      setSaving(false);
    }
  };

  return (
    <div style={{ display: 'grid', gap: 20 }}>
      <div style={{ fontWeight: 700 }}>Выбрано {selectedDates.length} из {requiredCount}</div>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(140px, 1fr))', gap: 12 }}>
        {availableDates.map((item) => {
          const active = selectedDates.includes(item.date);
          return (
            <button
              key={item.date}
              onClick={() => toggleDate(item.date)}
              disabled={!active && selectedDates.length >= requiredCount}
              style={{
                borderRadius: 12,
                border: active ? '2px solid #2f7d5b' : '1px solid #d7e1da',
                padding: 16,
                background: active ? '#eef8f2' : '#fff',
                textAlign: 'left',
                cursor: 'pointer',
              }}
            >
              <div style={{ fontWeight: 700 }}>{item.date}</div>
              <div style={{ color: '#5f6c63', fontSize: 13 }}>Доступно слотов: {item.availableSlots}</div>
            </button>
          );
        })}
      </div>

      {selectedDates.map((date) => (
        <div key={date} style={{ border: '1px solid #d7e1da', borderRadius: 16, padding: 16 }}>
          <div style={{ fontWeight: 700, marginBottom: 12 }}>{date}</div>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
            {(slotsByDate[date] ?? []).map((slot) => {
              const isActive = selected[date]?.startTime === slot.startTime;
              return (
                <button
                  key={`${date}_${slot.startTime}`}
                  onClick={() => onSelectSlot(date, slot)}
                  disabled={slot.availableCapacity <= 0}
                  style={{
                    borderRadius: 999,
                    border: isActive ? '2px solid #2f7d5b' : '1px solid #d7e1da',
                    padding: '10px 14px',
                    background: isActive ? '#eef8f2' : '#fff',
                  }}
                >
                  {slot.startTime} - {slot.endTime}
                </button>
              );
            })}
          </div>
        </div>
      ))}

      <button
        onClick={onSubmit}
        disabled={!canSubmit || saving}
        style={{
          border: 'none',
          borderRadius: 14,
          background: canSubmit ? '#2f7d5b' : '#cfd8d1',
          color: '#fff',
          padding: '16px 20px',
          fontWeight: 700,
        }}
      >
        {saving ? 'Сохраняем...' : 'Подтвердить расписание'}
      </button>
    </div>
  );
}
