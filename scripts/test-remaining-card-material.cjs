const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const file = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/VideoPlayerPage.ts';
const source = fs.readFileSync(file, 'utf8');
function method(name) {
  const start = source.search(new RegExp(`^    (?:private )?${name}\\(`, 'm'));
  assert.ok(start >= 0, name);
  return source.slice(start, source.indexOf('\n    }', start) + 6);
}
const context = { exports: {}, Color: { Transparent: 'transparent' } };
vm.runInNewContext(ts.transpileModule(`export class Page { ${['contentPanelWallpaperActive', 'contentCardMaterialActive', 'getCardContainerBg', 'getCardContainerBorder'].map(method).join('\n')} }`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);
const page = new context.exports.Page();
Object.assign(page, { otherCardGlassEnabled: true, isDarkMode: true, cardCustomColor: '', cardTransparentStyleVideo: false });
for (const [feed, comments, animating, active] of [
  [false, false, false, true], // Normal information/comments panel.
  [true, false, true, true], // Both directions retain material while the panel moves.
  [false, false, true, true],
  [true, false, false, false], // Stable continuous feed.
  [true, true, false, false], // Continuous-feed comments never get glass.
  [true, true, true, false]
]) {
  Object.assign(page, { referenceFeed: feed, referenceFeedComments: comments, referenceModeAnimating: animating });
  assert.equal(page.contentCardMaterialActive(), active);
  page.pageWallpaperEnabled=true;assert.equal(page.contentPanelWallpaperActive(),active,'wallpaper follows ordinary panel lifecycle, including animation');
  page.pageWallpaperEnabled=false;assert.equal(page.contentPanelWallpaperActive(),false,'wallpaper off preserves the original player panel');
  assert.equal(page.getCardContainerBg(true), '#2C2C2C', 'intro/comment background no longer follows the other-card glass switch');
  assert.equal(page.getCardContainerBorder(true).width, 0);
  page.otherCardGlassEnabled = false;
  assert.equal(page.getCardContainerBg(true), '#2C2C2C', 'disabling other-card glass restores ordinary card color');
  page.otherCardGlassEnabled = true;
}
for (const rel of ['pages/VideoPlayerPage.ts','pages/CommentDetailPage.ts','components/CommentThreadPanel.ts','components/CommentConversationPanel.ts']) {
  const body=fs.readFileSync(file.slice(0,file.indexOf('pages/VideoPlayerPage.ts'))+rel,'utf8');
  assert.ok(!body.includes('new PageSurface('),rel+': newly added intro/comment material must stay removed');
}
console.log('PASS: compiled intro/comment material removed; ordinary backgrounds independent of glass controls; wallpaper lifecycle retained.');
