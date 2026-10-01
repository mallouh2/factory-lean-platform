const keys = ['request','product','unit','technician','shift','from','to','scrap','minimum_scrap','corrected'];
export function historyQuery(factory, filters, sort = 'date', direction = 'desc', page = 1) {
  const query = new URLSearchParams({factory, sort, direction, page:String(page)});
  for (const key of keys) if (filters[key]) query.set(key,String(filters[key]));
  return query.toString();
}
export function parseHistoryQuery(query) {
  const filters = Object.fromEntries(keys.filter(k=>query.get(k)).map(k=>[k,query.get(k)]));
  const page=Number(query.get('page') || 1),sort=query.get('sort') || 'date',direction=query.get('direction') || 'desc';
  if (!Number.isSafeInteger(page) || page<1 || page>1000000 || !['date','good','scrap','unit','technician','shift'].includes(sort)
    || !['asc','desc'].includes(direction)) throw Error('invalid_input');
  for (const key of ['from','to']) if (filters[key] && !/^\d{4}-\d{2}-\d{2}$/.test(filters[key])) throw Error('invalid_input');
  if (filters.from && filters.to && filters.from>filters.to) throw Error('invalid_input');
  if (filters.minimum_scrap && (!Number.isFinite(Number(filters.minimum_scrap)) || Number(filters.minimum_scrap)<0)) throw Error('invalid_input');
  return {filters,sort_key:sort,sort_direction:direction,page};
}
