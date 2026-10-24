import test from 'node:test';
import assert from 'node:assert/strict';
import fixture from './fixtures/almatau-osm-map.json';
import {residentialComplexHouses} from '../modules/residentialComplexHouses';
import {AddressSearchService, AddressSuggestion} from '../modules/integrations';

const complex: AddressSuggestion = {source:'osm',label:'ЖК Алматау',city:'Астана',residentialComplex:'ЖК Алматау',
  raw:{osm_type:'way',osm_id:1549054977,type:'residential',boundingbox:['51.1233995','51.1252664','71.4101185','71.4123659']}};
test('Almatau yields all four full addresses, without the complex centroid',()=>{
 const rows=residentialComplexHouses(complex,fixture);
 assert.deepEqual(rows.map(x=>x.house).sort(),['29','29/2','29/4','32/2']);
 assert.ok(rows.every(x=>x.street&&x.house&&x.residentialComplex==='ЖК Алматау'));
});
test('nearby addresses outside the complex polygon are excluded',()=>{
 const data={elements:[...fixture.elements,{type:'node',id:-1,lat:51.12526,lon:71.41236,tags:{'addr:street':'Other','addr:housenumber':'999'}}]};
 assert.ok(!residentialComplexHouses(complex,data).some(x=>x.house==='999'));
 assert.deepEqual(residentialComplexHouses(complex,{elements:[]}),[]);
});
test('external search expands a named residential area and caches its house lookup',async()=>{
 const original=globalThis.fetch;let maps=0;
 try{
  globalThis.fetch=(async(url:any)=>{
   if(String(url).includes('/map.json')){maps++;return {ok:true,json:async()=>fixture};}
   return {ok:true,json:async()=>[{...(complex.raw as any),display_name:complex.label,lat:51.1242,lon:71.4113,address:{city:'Астана',residential:'ЖК Алматау'}}]};
  }) as any;
  const service=new AddressSearchService();
  for(let i=0;i<2;i++){
   const rows=await service.externalSuggestions({query:'Алматау',city:'Астана',limit:100});
   assert.equal(rows.length,4);assert.ok(rows.every(x=>x.house));
  }
  assert.equal(maps,1);
 }finally{globalThis.fetch=original;}
});
