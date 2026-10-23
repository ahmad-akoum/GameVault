'use strict';
const assert = require('node:assert/strict');
const {inspectQueueContext} = require('../tool/queue_context_probe.cjs');
let calls = 0;
function forbidden() {calls++; throw new Error('must never execute');}
const mock = {SteamClient: {Downloads: {QueueAppUpdate: forbidden}}};
for (const id of [1, 42, 0xffffffff]) {
  const r = inspectQueueContext(id, mock);
  assert.equal(r.validAppId, true);
  assert.equal(r.bindingPresent, true);
  assert.equal(r.signatureVerified, false);
  assert.equal(r.canRequestUpdate, false);
  assert.equal(r.requestSent, false);
  assert.equal(r.downloadConfirmed, false);
}
for (const id of [0, -1, 1.2, NaN, Infinity, '42', true, null, 0x100000000])
  assert.equal(inspectQueueContext(id, mock).validAppId, false);
for (const ctx of [{}, {SteamClient: {}}, {SteamClient: {Downloads: {QueueAppUpdate: 'name only'}}}])
  assert.equal(inspectQueueContext(42, ctx).bindingPresent, false);
assert.equal(inspectQueueContext(42, {get SteamClient(){throw new Error('unavailable');}}).reason,
  'context_inspection_failed');
// Native wrappers can report misleading function.length; do not infer an ABI.
for (const fn of [function(a){}, function(a,b){}, (...args)=>{}]) {
  const r = inspectQueueContext(42, {SteamClient:{Downloads:{QueueAppUpdate:fn}}});
  assert.equal(r.bindingPresent, true);
  assert.equal(r.signatureVerified, false);
  assert.equal(r.canRequestUpdate, false);
}
assert.equal(inspectQueueContext(42).bindingPresent, false);
assert.equal(calls, 0);
console.log('Queue context probe safety assertions passed; no method invoked.');
