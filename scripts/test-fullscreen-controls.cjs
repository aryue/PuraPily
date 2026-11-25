const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

const root = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');

const controls = read('entry/src/main/ets/components/VideoControls.ets');
const page = read('entry/src/main/ets/pages/VideoPlayerPage.ets');

assert.ok(!/referencePortraitFullscreen/.test(controls), 'portrait fullscreen controls must not exist');
assert.ok(!/ReferencePortraitFullscreen/.test(controls), 'portrait fullscreen builder must not exist');
assert.ok(!/sideButtons/.test(controls), 'legacy side-button group must be deleted');
assert.ok(!/PlayerLegacyVideoOptions/.test(page), 'legacy option panel must be deleted');
assert.ok(!/legacyVideoOptions/.test(page), 'legacy option builder must be deleted');
assert.ok(!fs.existsSync(path.join(root, 'entry/src/main/ets/components/PlayerLegacyVideoOptions.ets')),
  'legacy option component file must be deleted');
assert.ok(fs.existsSync(path.join(root, 'entry/src/main/ets/components/PlayerReferenceVideoOptions.ets')),
  'reference portrait option panel must exist');

const branch = controls.slice(controls.indexOf('if (this.isControlsVisible && !this.hidePlaybackControls)'),
  controls.indexOf('if ((this.referenceHalfScreen || this.referenceLandscapeFullscreen)'));
assert.match(branch, /this\.ReferenceLandscapeHalfScreenControls\(\)/, 'landscape split keeps its control layer');
assert.match(branch, /this\.ReferenceHalfScreenControls\(\)/, 'portrait split keeps its control layer');
assert.match(branch, /this\.ReferenceLandscapeFullscreenControls\(\)/, 'landscape fullscreen keeps its control layer');
assert.ok(!/Column\(\) \{/.test(branch), 'no generic legacy control column remains');
assert.ok(!/Slider\(\{/.test(branch), 'legacy fullscreen slider must not remain in the control layer');

assert.match(page, /hidePlaybackControls: this\.referenceLayout &&\s*\n\s*\(!this\.fs && !this\.isLs && \(this\.referenceFeed \|\| this\.referenceModeAnimating\)\)/,
  'portrait fullscreen must not have a dedicated hide path');
assert.ok(!/\(this\.fs && !this\.isLs\)/.test(page), 'no portrait-fullscreen-only state remains');
assert.match(page, /if \(!this\.fs && this\.referenceLayout && !this\.isLs && this\.ar < 1\) \{[\s\S]{0,200}?this\.referenceSetFeed\(true\)/,
  'portrait fullscreen entry must route to continuous feed');

const enterAt = page.indexOf('private async enterFullscreenAnimated()');
const enter = page.slice(enterAt, page.indexOf('private async exitFullscreenAnimated()', enterAt));
const enterHide = enter.indexOf('this.cv = false;');
const enterRotate = enter.indexOf('rotateReferenceFullscreen(true');
assert.ok(enterHide > 0 && enterRotate > enterHide,
  'enter must remove controls before the system rotation snapshot');

const exitAt = page.indexOf('private async exitFullscreenAnimated()');
const exit = page.slice(exitAt, page.indexOf('async toggleFS()', exitAt));
const exitHide = exit.indexOf('this.cv = false;');
const exitRotate = exit.indexOf('rotateReferenceFullscreen(false');
assert.ok(exitHide > 0 && exitRotate > exitHide,
  'exit must remove fullscreen controls before rotating back');

console.log('PASS: legacy control layer removed; only portrait split / landscape split / landscape fullscreen remain; no portrait fullscreen UI.');
