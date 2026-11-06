const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const hex = /^[0-9a-f]{64}$/;
const cursorKeys = ['version','factory','occurrence','as_of','revision','schedule_revision','page_size','context','last_state','last_start','last_id'];
const invalid = () => { throw {code:'22023'}; };

// Opaque transport, not an authorization token. SQL rechecks scope and context.
export function parseShiftWorkQuery(query) {
  if ([...query.keys()].some(k=>!['factory','cursor','page_size'].includes(k)) ||
      [...new Set(query.keys())].some(k=>query.getAll(k).length!==1)) invalid();
  const factory=query.get('factory');
  if (!factory || !uuid.test(factory)) invalid();
  const size=query.get('page_size') ?? '50';
  if (!/^\d+$/.test(size) || Number(size)<1 || Number(size)>100) invalid();
  let cursor=null;
  if (query.has('cursor')) {
    const value=query.get('cursor');
    if (!value || value.length>4000 || !/^[A-Za-z0-9_-]+$/.test(value)) invalid();
    try {
      cursor=JSON.parse(Buffer.from(value,'base64url').toString('utf8'));
    } catch { invalid(); }
    if (!cursor || Array.isArray(cursor) || typeof cursor!=='object' ||
        Object.keys(cursor).length!==cursorKeys.length || Object.keys(cursor).some(k=>!cursorKeys.includes(k)) ||
        cursor.version!==1 || cursor.factory!==factory.toLowerCase() || cursor.page_size!==Number(size) ||
        !hex.test(cursor.occurrence) || !hex.test(cursor.context) || !uuid.test(cursor.last_id) ||
        ![0,1].includes(cursor.last_state) || !/^\d+$/.test(String(cursor.revision)) ||
        !/^\d+$/.test(String(cursor.schedule_revision)) ||
        ![cursor.as_of,cursor.last_start].every(x=>typeof x==='string' && /(?:Z|[+-]\d\d:\d\d)$/.test(x) && Number.isFinite(Date.parse(x)))) invalid();
  }
  return {factory:factory.toLowerCase(),cursor,page_size:Number(size)};
}

export function shiftWorkResponse(data) {
  if (!data || data.contract_version!==3 || !Array.isArray(data.rows) ||
      !Number.isSafeInteger(data.total) || typeof data.complete!=='boolean' ||
      typeof data.late_recording_available!=='boolean' ||
      (data.late_recording_available && (data.available!==true || data.can_edit!==true)) ||
      data.rows.some(r=>typeof r.late_recording_available!=='boolean' ||
        (r.same_shift_recording_available!==undefined && typeof r.same_shift_recording_available!=='boolean') ||
        (r.same_shift_recording_available===true && (data.available!==true || data.can_edit!==true || r.status!=='completed' || r.policy_late_eligible!==true || r.can_record!==true)) ||
        (r.late_recording_available && (!data.late_recording_available || r.status!=='completed' ||
          r.policy_late_eligible!==true || r.can_record!==true))))
    throw {code:'P0001'};
  return {...data,next_cursor:data.next_cursor ? Buffer.from(JSON.stringify(data.next_cursor),'utf8').toString('base64url') : null};
}
