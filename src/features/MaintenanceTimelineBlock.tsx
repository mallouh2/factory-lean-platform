import { formatTime } from '@/components/ui';
import { maintenanceVisualWindow } from '@/utils/maintenance-planning-view.mjs';
import type { MaintenanceSchedule } from './maintenance-planning-types';
import type { FeatureProps } from './types';

/** Positioned on the existing Production Gantt axis; no independent timeline or stored state. */
export default function MaintenanceTimelineBlock({schedule,from,until,top,onOpen,t,lang,zone,compact=false,captionEnd=false}: {
  schedule:MaintenanceSchedule;from:number;until:number;top:number;onOpen:()=>void;
  compact?:boolean;captionEnd?:boolean;t:FeatureProps['t'];lang:FeatureProps['lang'];zone:string;
}) {
  const window=maintenanceVisualWindow(schedule), now=Date.now();
  if(schedule.occupancy?.continues)window.finish=Math.max(window.finish,until);
  if (!Number.isFinite(window.start) || !Number.isFinite(window.finish) || window.start>=until || window.finish<=from) return null;
  const left=(Math.max(from,window.start)-from)/(until-from)*100;
  const width=(Math.min(until,window.finish)-Math.max(from,window.start))/(until-from)*100;
  const overrun = schedule.overrun || (schedule.actual_hold && now>window.plannedEnd);
  const label=`${schedule.code} · ${schedule.machine_code||''} · ${t(`mpState_${schedule.state}`)} · ${formatTime(schedule.planned_start,lang,zone)} — ${formatTime(schedule.planned_end,lang,zone)}`+
    (schedule.actual_hold ? ` · ${t('mpHold')}` : '')+(overrun ? ` · ${t('mpOverrun')}` : '')+(window.continuing ? ` · ${t('mpContinuing')}` : '')+
    (schedule.actual_stops?.length?` · ${t('mpPhysicalStops')}: ${schedule.actual_stops.length}`:'');
  const extensionStart=Math.max(from,window.plannedEnd), extensionEnd=Math.min(until,window.finish);
  return <button type="button" className={"mp-timeline-block"+(compact?" mp-timeline-compact":"")} data-caption-end={captionEnd} data-reservation={schedule.id} data-state={schedule.state}
    data-overrun={overrun || undefined} style={{left:`${left}%`,width:`${width}%`,top}} onClick={onOpen}
    aria-label={label} title={label}>
    {extensionEnd>extensionStart && <i className="mp-overrun-extension" aria-hidden="true"
      style={{left:`${(extensionStart-Math.max(from,window.start))/(Math.min(until,window.finish)-Math.max(from,window.start))*100}%`}}/>}
    <span>⚙ <bdi>{schedule.code}</bdi> · {t(`mpState_${schedule.state}`)}{overrun ? ` · ${t('mpOverrun')}` : ''}{window.continuing ? ' →' : ''}</span>
    {(schedule.actual_stops||[]).map(stop=>{
      const a=Math.max(from,Date.parse(stop.started_at)),b=Math.min(until,stop.ended_at?Date.parse(stop.ended_at):now);
      if(b<=a)return null;
      return <i key={stop.id} className="mp-physical-stop" data-stop={stop.id} role="img"
        aria-label={`${t('mpPhysicalStops')} · ${schedule.machine_code||schedule.code} · ${formatTime(stop.started_at,lang,zone)} — ${stop.ended_at?formatTime(stop.ended_at,lang,zone):t('mpHold')}`}
        style={{left:`${(a-Math.max(from,window.start))/(Math.min(until,window.finish)-Math.max(from,window.start))*100}%`,width:`${(b-a)/(Math.min(until,window.finish)-Math.max(from,window.start))*100}%`}}/>;
    })}
  </button>;
}
