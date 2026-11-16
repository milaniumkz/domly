const {Database}=require('./dist/infrastructure/db/Database');
(async()=>{
 const db=new Database(process.env.DATABASE_URL);
 try {
  const result=await db.atomic(async()=>{
   if(!(await db.query('SELECT domly_service_zones_enforced() AS enabled')).rows[0].enabled)throw Error('coverage_protection_disabled');
   await db.query("SELECT pg_advisory_xact_lock(hashtextextended('connect-house:astana:tauelsizdik:43',0))");
   const zones=(await db.query("SELECT id FROM service_zones WHERE active AND domly_city_key(city)='астана' AND name_ru='Астана' FOR SHARE")).rows;
   if(zones.length!==1)throw Error('active_zone_missing_or_ambiguous');
   const zone=zones[0].id;
   const houses=(await db.query("SELECT id,active,zone_id FROM connected_houses WHERE domly_city_key(city)='астана' AND domly_address_key(house)='43' AND (domly_street_key(street_ru)=domly_street_key('Тауелсиздик') OR domly_street_key(street_kk)=domly_street_key('Тауелсиздик')) FOR UPDATE")).rows;
   if(houses.length>1)throw Error('building_match_ambiguous');
   let id,changed=true;
   if(houses.length){
    id=houses[0].id;
    changed=!houses[0].active||houses[0].zone_id!==zone;
    if(changed)await db.query('UPDATE connected_houses SET active=TRUE,zone_id=$2 WHERE id=$1',[id,zone]);
   }else{
    id=(await db.query("INSERT INTO connected_houses(city,street_ru,street_kk,house,zone_id,active) VALUES('Астана','проспект Тауелсиздик','Тәуелсіздік даңғылы','43',$1,TRUE) RETURNING id",[zone])).rows[0].id;
   }
   for(const street of ['тауелсыздык','проспект Тауелсиздик','Тәуелсіздік даңғылы']){
    const check=(await db.query('SELECT domly_location_in_service_zone($1,$2,$3,NULL,NULL) AS covered',['Астана',street,'43'])).rows[0];
    if(!check.covered)throw Error('connected_house_not_recognized');
   }
   if(changed)await db.query("INSERT INTO audit_logs(action,entity_type,entity_id,payload) VALUES('house.connected','connected_house',$1,$2)",[id,{source:'authorized_house_connection',building:'Тауелсіздік, 43',city:'Астана',active:true}]);
   return {houseConnected:true,activeZone:true,streetSpellingsRecognized:true,changedBuildings:changed?1:0,customerRecordsChanged:false,paymentsChanged:false};
  });
  console.log(JSON.stringify(result));
 }finally{await db.close();}
})().catch(()=>{console.error('House connection stopped; no customer data exported.');process.exitCode=1;});
