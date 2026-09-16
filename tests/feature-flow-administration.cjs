const assert=require('node:assert/strict');
module.exports=async function administrationFlows({owner,browser,credentials,origin,initial,factory,call,get,save,stamp,center,cell,line,area,order,operator}) {
  const checks=[]; let snapshot;
  const logo = await owner.post(origin + '/api/logo',{timeout:120000,headers:{origin},multipart:{factory,file:{name:'test.png',mimeType:'image/png',buffer:Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=','base64')}}});
  assert.equal(logo.status(),200);const uploaded=await logo.json();
  await call(owner,'update_settings',{name:initial.factory.name,timezone:initial.factory.timezone,logo:uploaded.path});
  assert.equal((await owner.get(origin+'/api/logo?factory='+factory,{timeout:120000})).status(),200);
  await call(owner,'update_settings',{name:initial.factory.name,timezone:initial.factory.timezone,logo:initial.factory.logo_path});
  checks.push('Private logo upload, display and factory settings save work');
  const role=await save('roles',{name:stamp+' viewer',name_ar:'دور اختبار'});
  await call(owner,'set_permissions',{role,permissions:[{module:'factory',action:'view'},{module:'dashboard',action:'view'},{module:'centers',action:'view'}]});
  const manager=initial.tables.memberships.find(m=>m.display_name==='Sara Haddad');
  await call(owner,'manage_member',{id:manager.id,role,status:'approved'});
  snapshot=await get(owner);assert.equal(snapshot.tables.memberships.find(m=>m.id===manager.id).role_id,role);
  await call(owner,'manage_member',{id:manager.id,role:manager.role_id,status:'approved'});
  checks.push('Custom role permissions and employee role changes persist');
  const supportContext=await browser.newContext();
  try {
    const login=await supportContext.request.post(origin+'/api/auth',{timeout:120000,headers:{origin},data:{action:'signin',email:credentials.support.email,password:credentials.support.password}});
    assert.equal(login.status(),200);
    let support=await get(supportContext.request);
    if(!support.membership){
      const code=await call(owner,'get_join_code',{});
      await call(supportContext.request,'request_membership',{code,display_name:'Functional test employee',factory:undefined});
      support=await get(supportContext.request);assert.equal(support.membership.status,'pending');
      await call(owner,'manage_member',{id:support.membership.id,role:operator.role_id,status:'approved'});
      assert.equal((await get(supportContext.request)).factory.id,factory);
      await call(owner,'manage_member',{id:support.membership.id,role:operator.role_id,status:'rejected'});
      checks.push('Employee requests access, receives approval and can be rejected');
    }
    await call(owner,'set_support_by_email',{email:credentials.support.email,role:manager.role_id,mode:'temporary',expires_at:new Date(Date.now()+3600000).toISOString()});
    assert.equal((await get(supportContext.request,'?factory='+factory)).factory.id,factory);
    checks.push('Temporary support grant by email opens the authorized factory');
  }finally{
    await call(owner,'set_support_by_email',{email:credentials.support.email,role:manager.role_id,mode:'disabled',expires_at:null});
    await supportContext.close().catch(() => {});
  }
  await call(owner,'change_status',{work_center:center,status:'idle'});
  await save('orders',{status:'completed'},order);
  await save('centers',{archived:true},center);await save('centers',{archived:true},cell);await save('lines',{archived:true},line);await save('factory',{archived:true},area);
  snapshot=await get(owner);assert.equal(snapshot.tables.work_centers.find(c=>c.id===center).archived,true);assert.equal(snapshot.tables.status_events.filter(e=>e.work_center_id===center).length,4);
  checks.push('Archiving preserves operational history');
  return checks;
};
