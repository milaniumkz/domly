import fs from 'node:fs/promises';
import admin from 'firebase-admin';
import { env } from '../common/env';
import { Database } from '../infrastructure/db/Database';
import { CatalogExport, importCatalog } from '../modules/catalogMigration';

async function main() {
  let source: CatalogExport;
  if (process.argv[2]) source=JSON.parse(await fs.readFile(process.argv[2],'utf8'));
  else {
    admin.initializeApp({credential:admin.credential.cert({projectId:env.fcmProjectId,clientEmail:env.fcmClientEmail,privateKey:env.fcmPrivateKey})});
    const firestore=admin.firestore();
    source={};
    for (const name of ['customer_packages','addon_groups_config','addons_config','pricing','houses','service_zones']) {
      const snapshot=await firestore.collection(name).get();
      source[name]=snapshot.docs.map(doc=>({id:doc.id,data:doc.data()}));
    }
  }
  const db=new Database(env.databaseUrl);
  try {console.log(JSON.stringify(await importCatalog(db,source)));}
  finally {await db.close();}
}
main().catch(()=>{console.error('Catalogue migration failed; transaction rolled back.');process.exitCode=1;});
