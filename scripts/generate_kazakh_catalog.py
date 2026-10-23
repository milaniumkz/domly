#!/usr/bin/env python3
"""Generate bundled Dart and additive PostgreSQL seed from the shared UI catalog.
Run from the repository root. No translation services or customer data are used.
Existing nonempty PostgreSQL translations remain editable and are preserved.
"""
import json
import hashlib
from pathlib import Path

data = dict(sorted(json.loads(Path('backend/src/localization/kazakh.json').read_text()).items()))
escape=lambda x:json.dumps(x,ensure_ascii=False).replace('$','\\$')
Path('lib/localization/kazakh_translations.dart').write_text('// Bundled Kazakh UI catalog; source strings and parameter names stay stable.\nconst Map<String,String> kKazakhTranslations = {\n'+''.join(f'  {escape(s)}: {escape(t)},\n'for s,t in data.items())+'};\n')
quote=lambda s:"'"+s.replace("'","''")+"'"
values=',\n'.join('('+','.join(map(quote,['t_'+hashlib.sha1(s.encode()).hexdigest()[:16],s,t]))+')'for s,t in data.items())
sql='''-- Fill missing Kazakh translations; preserve nonempty editorial overrides.
BEGIN;
CREATE TEMP TABLE domly_kk_seed (key text, ru text, kk text) ON COMMIT DROP;
INSERT INTO domly_kk_seed VALUES
'''+values+''';
UPDATE translations t SET kk=s.kk,updated_at=NOW() FROM domly_kk_seed s
 WHERE regexp_replace(btrim(t.ru),'[[:space:]]+',' ','g')=s.ru AND (t.kk IS NULL OR btrim(t.kk)='');
INSERT INTO translations (key,ru,kk,namespace)
 SELECT key,ru,kk,'app' FROM domly_kk_seed
 ON CONFLICT(key) DO UPDATE SET kk=EXCLUDED.kk,updated_at=NOW()
 WHERE translations.kk IS NULL OR btrim(translations.kk)='';
'''
for table,fields in [('catalog_packages',['name','description']),('catalog_addons',['title','description','hint']),('addon_groups',['title']),('banners',['title','subtitle']),('promotions',['title','description']),('content_pages',['title'])]:
 for f in fields:sql+=f"UPDATE {table} t SET {f}_kk=s.kk FROM domly_kk_seed s WHERE regexp_replace(btrim(t.{f}_ru),'[[:space:]]+',' ','g')=s.ru AND (t.{f}_kk IS NULL OR btrim(t.{f}_kk)='');\n"
sql+="UPDATE notifications t SET title_kk=s.kk FROM domly_kk_seed s WHERE t.title_ru=s.ru AND (t.title_kk IS NULL OR btrim(t.title_kk)='');\nUPDATE notifications t SET body_kk=s.kk FROM domly_kk_seed s WHERE t.body_ru=s.ru AND (t.body_kk IS NULL OR btrim(t.body_kk)='');\nCOMMIT;\n";Path('backend/sql/kazakh_translations.sql').write_text(sql)
print(f'Generated {len(data)} Kazakh entries')
