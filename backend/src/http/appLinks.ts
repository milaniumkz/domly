import { Router } from 'express';

export function appLinksRouter() {
  const router = Router();
  router.get('/.well-known/apple-app-site-association', (_req,res) => {
    const team = process.env.APPLE_TEAM_ID || 'Z3NZN92Y7P';
    res.json({applinks: {apps: [], details: [
      {appID: `${team}.com.domly.customer`, paths: ['/customer/*']},
      {appID: `${team}.com.domly.pro`, paths: ['/pro/*']},
    ]}});
  });
  router.get('/.well-known/assetlinks.json', (_req,res) => {
    const apps = [['com.domly.customer',process.env.ANDROID_CUSTOMER_CERT_SHA256], ['com.domly.pro',process.env.ANDROID_PRO_CERT_SHA256]];
    const links = apps.map(([packageName,raw]) => ({relation: ['delegate_permission/common.handle_all_urls'], target: {
      namespace:'android_app', package_name: packageName,
      sha256_cert_fingerprints: (raw ?? '').split(',').map(value=>value.trim()).filter(value=>/^([0-9A-Fa-f]{2}:){31}[0-9A-Fa-f]{2}$/.test(value)),
    }}));
    if (links.some(link=>link.target.sha256_cert_fingerprints.length===0)) {
      res.status(503).json({ok:false, code:'app_links_not_configured', message:'Настройте SHA-256 сертификатов обеих Android-версий.'});
      return;
    }
    res.json(links);
  });
  router.get('/app-links', (_req,res) => res.json({ok:true,data:{
    customer: 'https://domly.kz/customer/', pro:'https://domly.kz/pro/',
    customerNative:'domly://customer', proNative:'domly-pro://pro',
  }}));
  return router;
}
