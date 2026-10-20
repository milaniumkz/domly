import sharp from 'sharp';
import {randomUUID,createHash} from 'node:crypto';
import {Request} from 'express';
import {Database} from '../infrastructure/db/Database';
import {StorageService} from '../modules/integrations';
import {env} from '../common/env';
import {ApiError} from '../common/api';
import {readRules,problem,collectorFailure,sanitize} from './core';

export const privateBucket=()=>process.env.TECH_PRIVATE_BUCKET??'domly-technical-private';
export async function ensurePrivateBucket(storage:StorageService){const name=privateBucket();if(!await storage.client.bucketExists(name))await storage.client.makeBucket(name).catch(async(error)=>{if(!await storage.client.bucketExists(name))throw error;});await storage.client.setBucketPolicy(name,'');}
export async function inspectImage(buffer:Buffer,mime:string,document:boolean,rules:any){
 const config=rules.config??{},version=rules.version??1;
 const base:any={algorithmVersion:'raster-quality-v1',rulesVersion:version,decision:'accepted',reason:'Формат проверен; автоматическая оценка не подтверждает подлинность содержания.',screenRecapture:{assessed:false,statement:'Нет достоверного заключения о пересъёмке экрана.'}};
 if(buffer.length>50*1024*1024)return {...base,decision:'rejected',reason:'Размер файла превышает 50 МБ.'};
 const head=buffer.subarray(0,32);
 if(mime==='application/pdf'){
  if(!head.toString().startsWith('%PDF-'))return {...base,decision:'rejected',reason:'Содержимое не соответствует PDF.'};
  if(/\/(JavaScript|JS|Launch|EmbeddedFile)\b/.test(buffer.toString('latin1')))return {...base,decision:'rejected',reason:'PDF содержит активные действия или вложенный исполняемый контент.'};
  return {...base,decision:'manual_review',reason:'PDF принят для ручной проверки читаемости и содержания. Антивирусная экспертиза не выполнялась.'};
 }
 if(!/^image\/(jpeg|png|webp|heic|heif)$/.test(mime))return {...base,decision:'rejected',reason:'Недопустимый формат: разрешены JPEG, PNG, WebP, HEIC/HEIF и PDF.'};
 try{
  const meta=await sharp(buffer,{limitInputPixels:40000000}).metadata();
  const {data,info}=await sharp(buffer,{limitInputPixels:40000000}).rotate().resize({width:512,height:512,fit:'inside',withoutEnlargement:true}).greyscale().raw().toBuffer({resolveWithObject:true});
  let sum=0,sq=0,lap=0,lapSq=0,count=0,periodic=0;
  for(let i=0;i<data.length;i++){sum+=data[i];sq+=data[i]*data[i];}
  const stdDev=Math.sqrt(Math.max(0,sq/data.length-(sum/data.length)**2));
  for(let y=1;y<info.height-1;y++)for(let x=1;x<info.width-1;x++){const i=y*info.width+x;const v=4*data[i]-data[i-1]-data[i+1]-data[i-info.width]-data[i+info.width];lap+=v;lapSq+=v*v;count++;if(Math.abs(v)>100)periodic++;}
  const variance=count?Math.max(0,lapSq/count-(lap/count)**2):0;
  Object.assign(base,{width:meta.width,height:meta.height,format:meta.format,stdDev:Math.round(stdDev*100)/100,laplacianVariance:Math.round(variance*100)/100,
   lowResolution:Math.min(meta.width??0,meta.height??0)<300,
   screenRecapture:{assessed:true,heuristicScore:count?Math.round(periodic/count*1000)/1000:0,statement:'Плотность резких границ — слабая эвристика; не доказательство пересъёмки и не основание для обвинения.'}});
  if(document&&(stdDev<Number(config.blankDocumentStdDev??1)||(variance<Number(config.blurReject??0.4)&&stdDev<5)))return {...base,decision:'rejected',reason:'На документе практически нет различимых деталей: однородное либо явно нечитаемое изображение. Нужен чёткий снимок.'};
  if(variance<Number(config.blurReview??12)||base.lowResolution)return {...base,decision:'manual_review',reason:base.lowResolution?'Небольшое разрешение: файл принят, читаемость проверит сотрудник. Само разрешение не является отказом.':'Возможна размытость: файл принят с отметкой для ручной проверки.'};
  return base;
 }catch(error:any){
  if(['image/heic','image/heif'].includes(mime))return {...base,decision:'manual_review',reason:'HEIC/HEIF не удалось декодировать установленным обработчиком. Требуется ручная проверка или повторный снимок JPEG.'};
  return {...base,decision:'rejected',reason:/pixel limit/i.test(String(error.message))?'Превышен безопасный лимит 40 миллионов пикселей.':'Файл повреждён или его содержимое не является допустимым изображением.'};
 }
}
export async function inspectUpload(db:Database,storage:StorageService,req:Request){
 if(!req.file)return;
 const type=String(req.body.folder??req.body.type??req.path);
 const document=/document|quality|area|technical|plan|passport|selfie|verification/i.test(type);
 const rules=await readRules(db);
 const analysis=await inspectImage(req.file.buffer,req.file.mimetype,document,rules);
 req.techFileReview={analysis,sha256:createHash('sha256').update(req.file.buffer).digest('hex'),documentType:document?'document':'media'};
 if(analysis.decision!=='rejected')return;
 const objectKey='quarantine/'+new Date().toISOString().slice(0,10)+'/'+randomUUID();
 let available=true;
 try{await ensurePrivateBucket(storage);await storage.client.putObject(privateBucket(),objectKey,req.file.buffer,req.file.size,{'Content-Type':'application/octet-stream'});}catch{available=false;collectorFailure();}
 const row=(await db.query(`INSERT INTO tech_files(event_id,owner_id,bucket,object_key,mime_type,size_bytes,sha256,filename,document_type,decision,reason,analysis,algorithm_version,rules_version,quarantined,original_available,expires_at)
 VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,'rejected',$10,$11,$12,$13,TRUE,$14,NOW()+($15||' days')::interval) RETURNING id`,
 [req.techEventId??null,req.user?.id??null,privateBucket(),objectKey,req.file.mimetype,req.file.size,req.techFileReview.sha256,'отклонённый файл',document?'document':'media',analysis.reason,sanitize(analysis),analysis.algorithmVersion,analysis.rulesVersion,available,Number(rules.config.quarantineDays??14)])).rows[0];
 await problem(db,{kind:'file',severity:'warning',fingerprint:'file_rejected:'+analysis.reason,title:'Отклонена загрузка файла',code:'file_quality_rejected',eventId:req.techEventId,recommendation:'Откройте именно файл этого события. Проверьте причину автоматической оценки; запросите новый снимок при необходимости. Оригинал может отсутствовать при недоступности хранилища.'});
 throw new ApiError(422,'file_quality_rejected',analysis.reason+' Номер проверки: '+row.id);
}
export async function registerUploadedFile(db:Database,req:Request,file:any){
 if(!req.techFileReview||!file?.id)return;
 const {analysis,sha256,documentType}=req.techFileReview;
 await db.query('UPDATE files SET technical_sha256=$2,technical_quality=$3 WHERE id=$1',[file.id,sha256,analysis]);
 await db.query(`INSERT INTO tech_files(file_id,event_id,owner_id,bucket,object_key,mime_type,size_bytes,sha256,document_type,decision,reason,analysis,algorithm_version,rules_version)
 VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14) ON CONFLICT(file_id) DO NOTHING`,
 [file.id,req.techEventId??null,req.user?.id??file.owner_id??null,file.bucket??env.minioBucket,file.object_key,file.mime_type??req.file?.mimetype,file.size_bytes??req.file?.size??null,sha256,documentType,analysis.decision,analysis.reason,analysis,analysis.algorithmVersion,analysis.rulesVersion]);
 if(analysis.decision==='manual_review')await problem(db,{kind:'file',fingerprint:'file_manual_review:'+analysis.reason,title:'Требуется ручная проверка файла',code:'file_manual_review',eventId:req.techEventId,recommendation:'Файл принят основным процессом с отметкой. Сотрудник должен проверить читаемость и содержание; автоматическая оценка не является решением по документу.'});
}
