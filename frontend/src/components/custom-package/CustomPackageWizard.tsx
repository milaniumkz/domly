import React, { useEffect, useMemo, useState } from 'react';
import { calculateCustomPackage, checkoutCustomPackage, confirmCustomPackage, getAddons } from '../../api/customPackageApi';

type Addon = {
  id: string;
  name: string;
  pricingType: 'FIXED' | 'PER_VISIT' | 'PER_SQM';
  price: number;
  repeatable: boolean;
};

type Props = {
  userId: string;
  apartmentId: string;
};

export function CustomPackageWizard({ userId, apartmentId }: Props) {
  const [step, setStep] = useState(1);
  const [addons, setAddons] = useState<Addon[]>([]);
  const [draftId, setDraftId] = useState<string | undefined>();
  const [confirmedPackageId, setConfirmedPackageId] = useState<string | null>(null);
  const [form, setForm] = useState({
    userId,
    apartmentId,
    area: 45,
    cleaningCount: 4,
    baseCleaningType: 'Стандарт',
    recurringAddons: [] as string[],
    oneTimeAddons: [] as string[],
    preferredDays: [] as string[],
    preferredTimeRanges: [] as string[],
  });
  const [calculation, setCalculation] = useState<any>(null);

  useEffect(() => {
    void getAddons().then((payload) => setAddons(payload.addons));
  }, []);

  useEffect(() => {
    void calculateCustomPackage({ ...form, draftId }).then((payload) => {
      setDraftId(payload.draft.id);
      setCalculation(payload.calculation);
    });
  }, [form, draftId]);

  const recurring = useMemo(() => addons.filter((addon) => form.recurringAddons.includes(addon.id)), [addons, form.recurringAddons]);
  const oneTime = useMemo(() => addons.filter((addon) => form.oneTimeAddons.includes(addon.id)), [addons, form.oneTimeAddons]);

  const toggleArrayValue = (key: 'recurringAddons' | 'oneTimeAddons' | 'preferredDays' | 'preferredTimeRanges', value: string) => {
    setForm((prev) => ({
      ...prev,
      [key]: prev[key].includes(value)
        ? prev[key].filter((item) => item !== value)
        : [...prev[key], value],
    }));
  };

  const onConfirm = async () => {
    if (!draftId) return;
    const payload = await confirmCustomPackage(draftId);
    setConfirmedPackageId(payload.customPackage.id);
    setStep(5);
  };

  const onCheckout = async () => {
    if (!confirmedPackageId) return;
    await checkoutCustomPackage(confirmedPackageId);
  };

  return (
    <div style={{ maxWidth: 840, margin: '0 auto', padding: 24, display: 'grid', gap: 20 }}>
      <h1 style={{ margin: 0 }}>Ваш индивидуальный пакет</h1>
      <div style={{ color: '#5f6c63' }}>Шаг {step} из 5</div>

      {step === 1 && (
        <div style={{ display: 'grid', gap: 12 }}>
          <input value={form.apartmentId} readOnly />
          <input type="number" value={form.area} onChange={(e) => setForm((prev) => ({ ...prev, area: Number(e.target.value) }))} />
          <select value={form.baseCleaningType} onChange={(e) => setForm((prev) => ({ ...prev, baseCleaningType: e.target.value }))}>
            <option>Базовый</option>
            <option>Стандарт</option>
            <option>Премиум</option>
            <option>Генеральная уборка</option>
            <option>Уборка после ремонта</option>
          </select>
          <button onClick={() => setStep(2)}>Далее</button>
        </div>
      )}

      {step === 2 && (
        <div style={{ display: 'grid', gap: 12 }}>
          <input type="number" value={form.cleaningCount} onChange={(e) => setForm((prev) => ({ ...prev, cleaningCount: Number(e.target.value) }))} />
          <div>Стоимость одной уборки: {calculation?.oneVisitPrice ?? 0} ₸</div>
          <button onClick={() => setStep(1)}>Назад</button>
          <button onClick={() => setStep(3)}>Далее</button>
        </div>
      )}

      {step === 3 && (
        <div style={{ display: 'grid', gap: 16 }}>
          <div>
            <h3>Обязательные на каждую уборку</h3>
            {addons.filter((addon) => addon.repeatable).map((addon) => (
              <label key={addon.id} style={{ display: 'block' }}>
                <input type="checkbox" checked={form.recurringAddons.includes(addon.id)} onChange={() => toggleArrayValue('recurringAddons', addon.id)} /> {addon.name}
              </label>
            ))}
          </div>
          <div>
            <h3>Разовые допуслуги</h3>
            {addons.map((addon) => (
              <label key={`${addon.id}_one`} style={{ display: 'block' }}>
                <input type="checkbox" checked={form.oneTimeAddons.includes(addon.id)} onChange={() => toggleArrayValue('oneTimeAddons', addon.id)} /> {addon.name}
              </label>
            ))}
          </div>
          <button onClick={() => setStep(2)}>Назад</button>
          <button onClick={() => setStep(4)}>Далее</button>
        </div>
      )}

      {step === 4 && (
        <div style={{ display: 'grid', gap: 16 }}>
          <div>
            <h3>Дни недели</h3>
            {['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб'].map((day) => (
              <label key={day} style={{ marginRight: 12 }}>
                <input type="checkbox" checked={form.preferredDays.includes(day)} onChange={() => toggleArrayValue('preferredDays', day)} /> {day}
              </label>
            ))}
          </div>
          <div>
            <h3>Удобное время</h3>
            {['09:00-12:00', '12:00-15:00', '15:00-18:00'].map((range) => (
              <label key={range} style={{ display: 'block' }}>
                <input type="checkbox" checked={form.preferredTimeRanges.includes(range)} onChange={() => toggleArrayValue('preferredTimeRanges', range)} /> {range}
              </label>
            ))}
          </div>
          <button onClick={() => setStep(3)}>Назад</button>
          <button onClick={onConfirm}>Подтвердить пакет</button>
        </div>
      )}

      {step === 5 && (
        <div style={{ display: 'grid', gap: 16 }}>
          <div>Стоимость за месяц: {calculation?.monthlyPrice ?? 0} ₸</div>
          <div>Стоимость одной уборки: {calculation?.oneVisitPrice ?? 0} ₸</div>
          <div>Экономия: {calculation?.savingsComparedToSingles ?? 0} ₸</div>
          <div>Повторяющиеся услуги: {recurring.map((item) => item.name).join(', ') || 'Нет'}</div>
          <div>Разовые услуги: {oneTime.map((item) => item.name).join(', ') || 'Нет'}</div>
          <button onClick={onCheckout}>Перейти к оплате</button>
        </div>
      )}
    </div>
  );
}
