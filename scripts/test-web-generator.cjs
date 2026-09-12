const fs = require('fs');
const vm = require('vm');
const assert = require('assert');
const root = require('node:path').resolve(__dirname, '..');
function web() {
  const fields = {};
  function element(id) {
    return fields[id] ||= {value:'', textContent:'', classList:{remove(){},add(){},toggle(){}}};
  }
  const inputs = {provider:'vps', profile:'lite', engine:'sing-box', preset:'custom', warpMode:'global',
    warpPrivateKey:'REVIEW-PRIVATE-KEY', warpPeerPublicKey:'REVIEW-PEER-KEY', argoMode:'off',
    outboundProxyMode:'direct', outboundProxyUdpMode:'proxy', tlsMode:'self-signed', webFrontMode:'auto', hy2ObfsMode:'off'};
  Object.entries(inputs).forEach(([k,v]) => element(k).value=v);
  const context = {window:{SBD_WEB_SCHEMA:{}}, document:{getElementById:element, querySelectorAll:()=>[{value:'vless-reality'}]},
    setTimeout(){}, clearTimeout(){}, Set, TextEncoder, URL, console};
  vm.runInNewContext(fs.readFileSync(root+'/web-generator/schema.js','utf8'), context);
  let src = fs.readFileSync(root+'/web-generator/app.js','utf8');
  src = src.slice(0, src.indexOf('byId("buildCmd").addEventListener'));
  vm.runInNewContext(src, context);
  for (const fn of ['buildCommand','buildEnvTemplate']) {
    vm.runInNewContext(fn+'()', context);
    assert(element('output').value.length);
    assert(element('output').value.includes(inputs.warpPrivateKey));
    assert(element('output').value.includes(inputs.warpPeerPublicKey));
    console.log(`[OK] ${fn}: WARP keys preserved`);
  }
}
web();
