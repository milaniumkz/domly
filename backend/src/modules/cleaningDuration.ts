/** Standard cleaning has no fixed setup time; add-ons contribute their own minutes. */
export function cleaningDurationMinutes(area: number, addonMinutes=0, baseMinutes=0, minutesPerM2=1.6): number {
  const squareMeters=Number.isFinite(area)&&area>0?area:50;
  return Math.max(1,Math.round(baseMinutes+squareMeters*minutesPerM2+addonMinutes));
}

/** A running visit needs room for the added work from now, even if already late. */
export function durationAfterAddonChange(order:any,previousAddonMinutes:number,nextAddonMinutes:number,now=Date.now()) {
  const delta=nextAddonMinutes-previousAddonMinutes;
  const estimate=Math.max(1,Number(order.estimated_duration_minutes??0)+delta);
  if(order.status!=='in_progress'||delta<=0||!order.scheduled_date||!order.start_time)return estimate;
  const date=order.scheduled_date instanceof Date?order.scheduled_date.toISOString().slice(0,10):String(order.scheduled_date).slice(0,10);
  const start=Date.parse(date+'T'+String(order.start_time).slice(0,8)+(String(order.start_time).length===5?':00':'')+'+05:00');
  return Number.isFinite(start)?Math.max(estimate,Math.ceil((now-start)/60000)+delta):estimate;
}
