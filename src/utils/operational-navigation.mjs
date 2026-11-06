/** Presentation only. Callers retain route and server authorization. */
export function operationalNavigation(can) {
  const definitions = [
    {id:'sales', label:'sales', items:['sales']},
    {id:'warehouse', label:'warehouse', items:['warehouse','warehouseRequests']},
    {id:'purchasing', label:'purchasing', primary:'purchasing', items:['purchasing','suppliers','myPurchaseRequests']},
    {id:'production', label:'production', items:['floor','orders','productionHistory','products','manageLinesMachines']},
    {id:'planning', label:'planning', items:['planning']},
    {id:'quality', label:'quality', items:['quality']},
    {id:'maintenance', label:'maintenance', items:['maintenance']},
    {id:'lean', label:'lean', items:[can('lean')?'lean':'downtime']},
    {id:'administration', label:'factoryAdministration', items:['settings','employees','roles','audit','support']},
  ];
  const permission = {warehouseRequests:'warehouse', floor:'lines', productionHistory:'orders'};
  return definitions.map(group=>({...group, items:group.items.filter(item=>item==='manageLinesMachines'?(can('lines','edit')||can('centers','edit')||can('lines','create')||can('centers','create')):can(permission[item]||item))}))
    .filter(group=>group.items.length)
    .map(group=>({...group, primary:group.primary&&group.items.includes(group.primary)?group.primary:null}));
}

export function navigationLabel(item) {
  return {sales:'navSales',warehouse:'navInventory',warehouseRequests:'navWarehouseRequests',floor:'floor'}[item]||item;
}
