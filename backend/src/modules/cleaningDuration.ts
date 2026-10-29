/** Standard cleaning has no fixed setup time; add-ons contribute their own minutes. */
export function cleaningDurationMinutes(area: number, addonMinutes=0, baseMinutes=0, minutesPerM2=1.6): number {
  const squareMeters=Number.isFinite(area)&&area>0?area:50;
  return Math.max(1,Math.round(baseMinutes+squareMeters*minutesPerM2+addonMinutes));
}
