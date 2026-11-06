// Presentation only. The protected reader/writer remain eligibility authority.
export function recordingWorkMessage(page,row,selected,expired){
 if(expired)return 'prv3Expired';
 if(!page)return null;
 if(page.can_edit===false)return 'prv3NoPermission';
 if(!page.occurrence)return page.reason==='SCHEDULE_GAP'?'prv3ShiftGap':'prv3OccurrenceUnavailable';
 if(selected&&!row)return 'prv3ExactUnavailable';
 if(!selected&&!page.rows.length)return 'prv3NoWork';
 if(row&&!row.can_record)return row.blocked_reason==='OUTSIDE_CURRENT_SHIFT'?'prv3Expired':row.status==='completed'?'prv3LateDisabled':'prv3WorkUnavailable';
 return null;
}
