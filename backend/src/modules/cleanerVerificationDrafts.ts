import {Database} from '../infrastructure/db/Database';

const documentFields:Record<string,string>={
 selfie:'selfieUrl',selfieUrl:'selfieUrl',
 'selfie-with-id':'selfieWithIdUrl',selfieWithIdUrl:'selfieWithIdUrl',
 'id-document':'idDocumentUrl',idDocumentUrl:'idDocumentUrl',
 'police-clearance':'policeClearanceUrl',policeClearanceUrl:'policeClearanceUrl',
 'psych-dispenser':'psychDispenserUrl',psychDispenserUrl:'psychDispenserUrl',
 phthisiatrician:'phthisiatricianUrl',phthisiatricianUrl:'phthisiatricianUrl',
 'residence-proof':'residenceProofUrl',residenceProofUrl:'residenceProofUrl',
};

export async function saveCleanerVerificationDraft(db:Database,cleanerId:string,type:string,fileId:string){
 const field=Object.prototype.hasOwnProperty.call(documentFields,type)?documentFields[type]:undefined;if(!field)return;
 // Only an accepted file owned by this cleaner can become their draft.
 await db.query(`INSERT INTO cleaner_verification_drafts(cleaner_id,document_type,file_id)
 SELECT $1,$2,f.id FROM files f JOIN app_users u ON u.id=f.owner_id
 WHERE f.id=$3 AND f.owner_id=$1 AND u.role='cleaner'
 AND (f.mime_type LIKE 'image/%' OR f.mime_type='application/pdf') AND f.size_bytes>0
 ON CONFLICT(cleaner_id,document_type) DO UPDATE SET file_id=EXCLUDED.file_id,updated_at=NOW()`,[cleanerId,field,fileId]);
}

export async function cleanerVerificationFields(db:Database,cleanerId:string){
 const rows=(await db.query(`SELECT d.type,f.public_url,d.status::text status,d.created_at,0 priority
 FROM cleaner_documents d JOIN files f ON f.id=d.file_id AND f.owner_id=d.cleaner_id
 WHERE d.cleaner_id=$1
 UNION ALL
 SELECT d.document_type,f.public_url,'draft',d.updated_at,1
 FROM cleaner_verification_drafts d JOIN files f ON f.id=d.file_id AND f.owner_id=d.cleaner_id
 WHERE d.cleaner_id=$1 ORDER BY created_at DESC,priority DESC`,[cleanerId])).rows;
 const fields:Record<string,string>={},seen=new Set<string>();
 for(const row of rows){const field=Object.prototype.hasOwnProperty.call(documentFields,row.type)?documentFields[row.type]:undefined;if(!field||seen.has(field))continue;seen.add(field);
  if(['draft','pending','approved'].includes(row.status)&&row.public_url)fields[field]=row.public_url;
 }
 return fields;
}
