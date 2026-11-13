"""One-time scoped ordering credential setup; no customer queries or messages."""
import argparse,datetime,json,os,re,secrets,subprocess,time,urllib.request,urllib.error
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--app-dir',required=True);p.add_argument('--revision',required=True);p.add_argument('--public-key',required=True);p.add_argument('--output',required=True);a=p.parse_args()
app=Path(a.app_dir);current=app/'current'
assert (app/'REVISION').read_text().strip()==a.revision,'Unexpected deployed revision'
assert re.fullmatch('[a-f0-9]{40}',a.revision)
files=[app/'shared/backend.env',current/'backend/.env'];originals={f:f.read_bytes() for f in files}
key='MOON_AI_ORDERING_TOKEN'
values=[line.split('=',1)[1].strip().strip('\"\'') for line in originals[files[0]].decode().splitlines() if line.startswith(key+'=')]
token=values[-1] if values and re.fullmatch('[A-Za-z0-9_.:-]{32,180}',values[-1]) else secrets.token_hex(32)
# Encrypt directly from memory. Only the recipient holds the private key.
subprocess.run(['openssl','pkeyutl','-encrypt','-pubin','-inkey',a.public_key,'-pkeyopt','rsa_padding_mode:oaep','-pkeyopt','rsa_oaep_md:sha256','-out',a.output],input=token.encode(),check=True,capture_output=True)
os.chmod(a.output,0o600)
stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
backup=app/'backups'/('bot-ordering-key-'+stamp);backup.mkdir(mode=0o700,parents=True,exist_ok=False)
for i,(f,b) in enumerate(originals.items()):
 dest=backup/('config-'+str(i)+'.env');dest.write_bytes(b);dest.chmod(0o600)
def atomic_write(f,b):
 temp=f.with_name(f.name+'.bot-ordering.tmp')
 fd=os.open(temp,os.O_CREAT|os.O_TRUNC|os.O_WRONLY,0o600)
 with os.fdopen(fd,'wb') as out:out.write(b)
 os.replace(temp,f)
def recreate():
 subprocess.run(['docker','compose','-p','domly-backend','-f',str(current/'docker-compose.yml'),'--project-directory',str(current),'up','-d','--no-build','--force-recreate','api','worker'],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
def get(url,secret=None):
 request=urllib.request.Request(url,headers={'X-MoonAI-Ordering-Token':secret} if secret else {})
 with urllib.request.urlopen(request,timeout=12) as response:return response.status,json.load(response)
try:
 for f,b in originals.items():
  lines=b.decode().splitlines();lines=[line for line in lines if not line.startswith(key+'=')];lines.append(key+'='+token)
  atomic_write(f,('\n'.join(lines)+'\n').encode())
 recreate()
 for _ in range(35):
  try:
   status,ready=get('http://127.0.0.1:8080/ready')
   if status==200 and ready.get('ok'):break
  except (urllib.error.URLError,TimeoutError,ConnectionError):pass
  time.sleep(2)
 else:raise RuntimeError('Readiness check failed')
 status,catalog=get('http://127.0.0.1:8080/api/v1/integrations/moon-ai/ordering/catalog',token)
 assert status==200 and catalog.get('ok') and isinstance(catalog['data']['packages'],list),'Authorized API check failed'
 try:get('http://127.0.0.1:8080/api/v1/integrations/moon-ai/ordering/catalog','invalid-fixture-token')
 except urllib.error.HTTPError as error:assert error.code==401
 else:raise RuntimeError('Invalid ordering token accepted')
 print(json.dumps({'revision':a.revision,'orderingTokenConfigured':True,'authorizedCatalog':200,'invalidToken':401,'customerDataRead':False,'invoicesCreated':0}))
except BaseException:
 for f,b in originals.items():atomic_write(f,b)
 recreate()
 raise
