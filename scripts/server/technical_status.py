#!/usr/bin/env python3
"""Fixed, read-only host probes. No command string or SQL supplied by browser."""
import datetime, hashlib, hmac, json, os, pathlib, subprocess, sys, urllib.request
root=pathlib.Path(sys.argv[1]); shared=root/'shared'; target=shared/'technical-status'; target.mkdir(mode=0o750,exist_ok=True)
values={}
for line in (shared/'backend.env').read_text().splitlines():
    if '=' in line and not line.startswith('#'):
        key,value=line.split('=',1); values[key]=value.strip("\"'")
key=values.get('TECH_AUDIT_KEY')
if not key: sys.exit(0)
def command(args):
    p=subprocess.run(args,capture_output=True,text=True,timeout=20,check=True)
    return p.stdout.strip()
def probe(url):
    try:
        with urllib.request.urlopen(url,timeout=8) as r: return {'available':r.status==200,'httpStatus':r.status}
    except Exception: return {'available':False,'reason':'HTTP probe failed'}
now=datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='milliseconds').replace('+00:00','Z')
state={'observedAt':now,'source':'Read-only host agent','apps':{p:probe('https://domly.kz/'+p+'/') for p in ['customer','pro','admin']},'readiness':probe('http://127.0.0.1:8080/ready'),'requestedRelease':(root/'REVISION').read_text().strip() if (root/'REVISION').exists() else None,'deployment':None}
disk=os.statvfs(root);state['disk']={'availableBytes':disk.f_bavail*disk.f_frsize,'totalBytes':disk.f_blocks*disk.f_frsize};state['loadAverage']=list(os.getloadavg())
mem={}
for line in pathlib.Path('/proc/meminfo').read_text().splitlines():
    parts=line.split();
    if parts[0] in ['MemTotal:','MemAvailable:']: mem[parts[0][:-1]]=int(parts[1])*1024
state['memory']=mem
try:
    raw=command(['docker','compose','-p','domly-backend','-f',str(root/'current/docker-compose.yml'),'--project-directory',str(root/'current'),'ps','--format','json'])
    containers=json.loads(raw) if raw.startswith('[') else [json.loads(line) for line in raw.splitlines() if line.strip()]
    state['containers']=[{k:c.get(k) for k in ['Service','State','Health','ExitCode']} for c in containers]
except Exception: state['containers']={'available':False}
backups=[]
for manifest in [root/'backups/scheduled/manifest.latest.jsonl',root/'current/backend/backups/manifest.latest.jsonl']:
    if manifest.exists():
        try: backups.append(json.loads(manifest.read_text().strip().splitlines()[-1]))
        except Exception: pass
state['scheduledBackup']=backups[-1] if backups else {'available':False,'reason':'No completed backup manifest found'}
pg=list((root/'backups').glob('*/postgres.sql')) if (root/'backups').exists() else []
if pg:
    last=max(pg,key=lambda p:p.stat().st_mtime);state['preDeploymentBackup']={'createdAt':datetime.datetime.fromtimestamp(last.stat().st_mtime,datetime.timezone.utc).isoformat(),'bytes':last.stat().st_size,'available':last.stat().st_size>0}
if (shared/'deployment-status.json').exists():
    try: state['deployment']=json.loads((shared/'deployment-status.json').read_text())
    except Exception: pass
# Independently persist the observed audit chain head outside the database.
try:
    out=command(['docker','compose','-p','domly-backend','-f',str(root/'current/docker-compose.yml'),'--project-directory',str(root/'current'),'exec','-T','api','node','-e',"const {Database}=require('./dist/infrastructure/db/Database');const {verifyAudit}=require('./dist/technical/core');const d=new Database(process.env.DATABASE_URL);verifyAudit(d,2000).then(x=>{console.log(JSON.stringify({...x,installedRelease:process.env.APP_RELEASE||null}));return d.close()}).catch(()=>process.exit(1));"])
    verified=json.loads(out);state['installedRelease']=verified.get('installedRelease'); witness=shared/'technical-audit-witness.json'; previous=json.loads(witness.read_text()) if witness.exists() else None
    valid=verified.get('valid') is True and (not previous or int(verified.get('lastSeq') or 0)>=int(previous.get('lastSeq') or 0))
    if previous and verified.get('lastSeq')==previous.get('lastSeq') and verified.get('head')!=previous.get('head'): valid=False
    state['auditWitness']={'valid':valid,'observedAt':now,'lastSeq':verified.get('lastSeq'),'scope':'Last 2000 signatures plus monotonic host checkpoint; not an independent remote immutable archive'}
    if valid:
        witness.write_text(json.dumps(verified));witness.chmod(0o600)
except Exception: state['auditWitness']={'valid':None,'reason':'Audit witness probe unavailable'}
def normalize(v):
    if isinstance(v,float) and v.is_integer(): return int(v)
    if isinstance(v,list): return [normalize(x) for x in v]
    if isinstance(v,dict): return {k:normalize(x) for k,x in v.items()}
    return v
state=normalize(state)
signature=hmac.new(key.encode(),json.dumps(state,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode(),hashlib.sha256).hexdigest()
state['signature']=signature
pending=target/'status.tmp';pending.write_text(json.dumps(state,ensure_ascii=False));pending.chmod(0o644);pending.replace(target/'status.json')
