import test from 'node:test';
import assert from 'node:assert/strict';
import { BCC_TEST,bccConfig,bccReady,bccSign,bccResultStatus,parseBccResponse } from '../modules/bcc';
import { env } from '../common/env';

test('BCC MAC matches the official purchase, status and refund examples',()=>{
  const fields={ORDER:'3558714461568',AMOUNT:'350.00',ORG_AMOUNT:'350.00',CURRENCY:'398',MERCHANT:'merchantname',TERMINAL:'88888881',
    MERCH_GMT:'0',TIMESTAMP:'20200224073921',NONCE:'F2B2DD7E603A7AAF5E1BC35DEE1F6C9A',RRN:'821185120045',INT_REF:'9C2176F638FDC05C'};
  for(const [TRTYPE,expected] of [['1','9B1C58714CFF6E4BCC6E97B4D503275838F4ED68'],['90','7C0D8BF3F6C7DCB0AA35E88F045292E176184B5E'],['14','0D8ABFC1215135BD51AB27C10E2CD621C5AF1432']])
    assert.equal(bccSign({...fields,TRTYPE},BCC_TEST.macKey),expected);
});
test('BCC sandbox must be explicitly enabled; test terminal is forbidden for live payments',()=>{
  const testConfig={...env,bccMode:'test',bccNotifyUrl:'https://domly.kz:443/api/v1/payments/bcc/webhook'};
  assert.equal(bccReady(testConfig),true);
  assert.equal(bccConfig(testConfig).terminalId,'88888881');
  assert.equal(bccReady({...testConfig,bccMode:'disabled'}),false);
  assert.equal(bccReady({...testConfig,bccMode:'live',bccMerchantId:'00000001',bccTerminalId:'88888881',bccPrivateKey:BCC_TEST.macKey}),false);
});
test('BCC success requires both ACTION and RC; a status string cannot approve a payment',()=>{
  assert.equal(bccResultStatus({status:'paid',RC:'00'}),'pending');
  assert.equal(bccResultStatus({ACTION:'2',RC:'00'}),'rejected');
  assert.equal(bccResultStatus({ACTION:'0',RC:'00'}),'paid');
  assert.equal(bccResultStatus({ACTION:'14',RC:'00'}),'cancelled');
  assert.equal(bccResultStatus({ACTION:'4',RC:'00'}),'pending');
  assert.equal(bccResultStatus({ACTION:'3',RC:'-40'}),'pending');
  assert.equal(bccResultStatus({ACTION:'3',RC:'-25'}),'cancelled');
});
test('BCC response parsing supports JSON, bank HTML forms, XML and URL encoding',()=>{
  for(const raw of ['{"ACTION":"0","RC":"00","ORDER":"1000001"}',
    '<input value="0" name="ACTION"><input name=RC value="00"><input name="ORDER" value="1000001">',
    '<response><ACTION>0</ACTION><RC>00</RC><ORDER>1000001</ORDER></response>',
    'ACTION=0&RC=00&ORDER=1000001'])
    assert.deepEqual(parseBccResponse(raw),{ACTION:'0',RC:'00',ORDER:'1000001'});
  assert.deepEqual(parseBccResponse('This script can only be used to decode form results.'),{});
});
