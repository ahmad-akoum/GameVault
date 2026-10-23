// Read-only capability inspection; no Steam connection, evaluation or invocation.
// Run only in the external test process. Not a client bridge or product feature.
'use strict';
function inspectQueueContext(appId, root = globalThis) {
  const result = {validAppId: Number.isInteger(appId) && appId > 0 && appId <= 0xffffffff,
    bindingPresent: false, signatureVerified: false, requestSent: false,
    downloadConfirmed: false, canRequestUpdate: false};
  if (!result.validAppId) return {...result, reason: 'invalid_app_id'};
  try {
    const downloads = root?.SteamClient?.Downloads;
    result.bindingPresent = typeof downloads?.QueueAppUpdate === 'function';
    return {...result, reason: result.bindingPresent
      ? 'binding_shape_only_requires_authorized_context_and_live_validation'
      : 'steam_client_binding_absent'};
  } catch (_) {
    return {...result, reason: 'context_inspection_failed'};
  }
}
module.exports = {inspectQueueContext};
if (require.main === module) {
  const arg = process.argv[2];
  const id = typeof arg === 'string' && /^[1-9][0-9]*$/.test(arg) ? Number(arg) : NaN;
  process.stdout.write(JSON.stringify(inspectQueueContext(id)) + '\n');
}
