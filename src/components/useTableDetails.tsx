import {useId,useRef} from 'react';
import type {HTMLAttributes} from 'react';
import {detailsRowHandlers} from '@/utils/table-details.mjs';
import type {Translate} from '@/types';

export function useTableDetails(){
 const pointer=useRef('');
 return (select:()=>void,open:()=>void,disabled=false):HTMLAttributes<HTMLElement>=>detailsRowHandlers(pointer,select,open,disabled);
}

/** Used only by legacy tables which do not yet have a toolbar. */
export function TableDetailsAction({t,disabled,onOpen}:{t:Translate;disabled:boolean;onOpen:()=>void}){
 const id=useId();
 return <div className="table-details-actions"><button type="button" popoverTarget={id} disabled={disabled}>{t('historyActions')} ▾</button>
  <div id={id} popover="auto"><button type="button" disabled={disabled} onClick={event=>{event.currentTarget.parentElement?.hidePopover();onOpen();}}>{t('historyViewDetails')}</button></div>
 </div>;
}
