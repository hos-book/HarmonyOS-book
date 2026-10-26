"""Verify the actual AGC ZIP with its callback runtime contract; no production secrets."""
from pathlib import Path
import subprocess, tempfile, zipfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='membership-offer-test-') as temporary:
    target = Path(temporary)
    with zipfile.ZipFile(root / 'server/dist/membership-offer-agc.zip') as archive:
        assert set(archive.namelist()) == {'index.js', 'membership-offer.mjs', 'membership-offer-function.mjs'}
        archive.extractall(target)
    (target / 'test.cjs').write_text(r'''
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { handler } = require('./index.js');
const keys = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
const context = {
  env: { IAP_ISSUER_ID: 'test-issuer', IAP_KEY_ID: 'test-key', IAP_OFFER_PRODUCTS: 'lastVip',
    IAP_PRIVATE_KEY: keys.privateKey.export({ format: 'der', type: 'pkcs8' }).toString('base64') },
  HTTPResponse: class {
    constructor(body, headers, contentType, statusCode) { Object.assign(this, { body, headers, contentType, statusCode }); }
  }
};
async function invoke(body, method = 'POST', encoded = false) {
  const raw = JSON.stringify(body);
  let calls = 0, result;
  await handler({ httpMethod: method, body: encoded ? Buffer.from(raw).toString('base64') : raw,
    isBase64Encoded: encoded }, context, response => { calls++; result = response; });
  assert.equal(calls, 1);
  return result;
}
(async () => {
  const valid = { productId: 'lastVip', offerId: 'lifetime_half_2026' };
  const result = await invoke(valid);
  assert.equal(result.statusCode, '200');
  assert.equal(result.headers['Cache-Control'], 'no-store');
  const [head, body, signature] = result.body.jwsRepresentation.split('.');
  assert.equal(crypto.verify('sha256', Buffer.from(head + '.' + body),
    { key: keys.publicKey, dsaEncoding: 'ieee-p1363' }, Buffer.from(signature, 'base64url')), true);
  const claims = JSON.parse(Buffer.from(body, 'base64url'));
  assert.equal(claims.iss, 'test-issuer'); assert.equal(claims.exp - claims.iat, 300);
  assert.equal(JSON.parse(claims.data).offerInfo.offerId, valid.offerId);
  assert.equal((await invoke(valid, 'POST', true)).statusCode, '200');
  assert.equal((await invoke({ ...valid, productId: 'iconYear' })).statusCode, '400');
  assert.equal((await invoke({ ...valid, offerId: 'cheaplist' })).statusCode, '400');
  assert.equal((await invoke(valid, 'GET')).statusCode, '405');
  console.log('PASS AGC ZIP callback, context.env, ES256 signature, base64 event and invalid requests');
})().catch(error => { console.error(error); process.exitCode = 1; });
''', encoding='utf-8')
    subprocess.run(['node', str(target / 'test.cjs')], check=True, cwd=target)
