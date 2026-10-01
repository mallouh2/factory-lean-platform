const keys = ['request','product','unit','technician','shift','from','to','scrap','minimum_scrap','corrected','measurement_unit','scrap_metric','scrap_scope', ...['good','scrap','unfinished'].flatMap(k=>[`${k}_op`,`${k}_min`,`${k}_max`])];
export function historyQuery(factory, filters, sort = 'date', direction = 'desc', page = 1) {
  const query = new URLSearchParams({factory, sort, direction, page:String(page)});
  for (const key of keys) if (filters[key]) query.set(key,String(filters[key]));
  return query.toString();
}
export function parseHistoryQuery(query) {
  const filters = Object.fromEntries(keys.filter(k=>query.get(k)).map(k=>[k,query.get(k)]));
  const page=Number(query.get('page') || 1),sort=query.get('sort') || 'date',direction=query.get('direction') || 'desc';
  if (!Number.isSafeInteger(page) || page<1 || page>1000000 || !['date','good','scrap','unfinished','unit','technician','shift'].includes(sort)
    || !['asc','desc'].includes(direction)) throw Error('invalid_input');
  for (const key of ['from','to']) if (filters[key] && !/^\d{4}-\d{2}-\d{2}$/.test(filters[key])) throw Error('invalid_input');
  if (filters.from && filters.to && filters.from>filters.to) throw Error('invalid_input');
  if (filters.minimum_scrap && (!Number.isFinite(Number(filters.minimum_scrap)) || Number(filters.minimum_scrap)<0)) throw Error('invalid_input');
  for(const key of ['request','product','unit','technician','shift','corrected']) if(filters[key] && (filters[key].length>3000 || filters[key].split(',').length>30)) throw Error('invalid_input');
  if(filters.measurement_unit && !['meter','piece'].includes(filters.measurement_unit)) throw Error('invalid_input');
  if(filters.scrap_metric && !['quantity','percentage'].includes(filters.scrap_metric)) throw Error('invalid_input');
  if(filters.scrap_scope && !['row','shift'].includes(filters.scrap_scope)) throw Error('invalid_input');
  for(const key of ['good','scrap','unfinished']) if(filters[`${key}_op`]) {
    const op=filters[`${key}_op`],min=filters[`${key}_min`],max=filters[`${key}_max`];
    if(!['eq','gte','lte','between'].includes(op) || min==null || min==='' || !Number.isFinite(Number(min)) || Number(min)<0 || (op==='between' && (max==null || max==='' || !Number.isFinite(Number(max)) || Number(max)<Number(min)))) throw Error('invalid_input');
    if(!filters.measurement_unit) throw Error('history_unit_required');
  }
  return {filters,sort_key:sort,sort_direction:direction,page};
}
export function scrapPercentage(good,scrap,unfinished=0) {
  const total=Number(good)+Number(scrap)+Number(unfinished);
  return total>0?Number(scrap)*100/total:null;
}
export function selectedHistoryValues(previous, visible, selected) {
  const onPage=new Set(visible);
  return [...new Set([...previous.filter(value=>!onPage.has(value)),...selected])];
}
