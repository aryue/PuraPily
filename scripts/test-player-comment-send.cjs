const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const ts = require(process.env.ARK_TYPESCRIPT ||
  'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');

const root = new URL('../entry/src/main/ets/', require('node:url').pathToFileURL(__filename));
function load(source, modules = {}) {
  const exports = {};
  vm.runInNewContext(ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, { exports, require: name => modules[name] ?? {} });
  return exports;
}

async function main() {
  const apiCalls = [];
  const imageCalls = [];
  let upload = async path => ({ url: 'https://cdn.example/' + path, width: 12, height: 34 });
  const success = { ok: true, code: 0, message: '' };
  let response = Promise.resolve(success);
  const api = {
    uploadCommentImage(...args) { imageCalls.push(args); return upload(...args); },
    addVideoComment(...args) { apiCalls.push(args); return response; }
  };
  const serviceSource = fs.readFileSync(new URL('services/PlaybackComments.ets', root), 'utf8');
  const { PlaybackComments } = load(serviceSource, { '../api/BilibiliApi': api });
  const service = new PlaybackComments();
  const image = { path: 'first.png', mime: 'image/png', ext: 'png' };
  const second = { path: 'second.gif', mime: 'image/gif', ext: 'gif' };
  const target = { aid: 12, root: 34, parent: 56 };

  assert.equal(await service.send(target, 'draft', [image, second], () => true), success);
  assert.deepEqual(imageCalls, [['first.png', 'image/png', 'png'], ['second.gif', 'image/gif', 'gif']]);
  assert.deepEqual(apiCalls[0].slice(0, 4), [12, 'draft', 34, 56]);
  assert.deepEqual(JSON.parse(apiCalls[0][4]), [
    { img_src: 'https://cdn.example/first.png', img_width: 12, img_height: 34 },
    { img_src: 'https://cdn.example/second.gif', img_width: 12, img_height: 34 }
  ]);
  upload = async () => null;
  assert.equal((await service.send(target, 'draft', [image], () => true)).message, '图片上传失败');
  assert.equal(apiCalls.length, 1);

  let active = true;
  upload = async () => {
    active = false;
    return { url: 'https://cdn.example/late', width: 12, height: 34 };
  };
  const count = imageCalls.length;
  assert.equal(await service.send(target, 'draft', [image, second], () => active), null);
  assert.equal(imageCalls.length, count + 1, 'an obsolete composer must stop before uploading the next image');
  assert.equal(apiCalls.length, 1, 'an obsolete composer must not submit its comment after upload');

  const pageSource = fs.readFileSync(new URL('pages/VideoPlayerPage.ets', root), 'utf8');
  const start = pageSource.indexOf('  private async handleCommentSend(');
  const end = pageSource.indexOf('  /** 打开评论输入弹层', start);
  assert.ok(start >= 0 && end > start);
  const { Player } = load('export class Player {' + pageSource.slice(start, end) + '}');
  const page = new Player();
  const notices = [];
  const reloads = [];
  Object.assign(page, {
    vi: { bvid: 'BVone' }, vd: { aid: 12 }, referenceAlive: true, referenceSwitchGeneration: 7,
    commentSheetVisible: true, commentSheetMode: 'new',
    commentTarget_: { aid: 12, root: 0, parent: 0, bvid: 'BVone', generation: 7 },
    playbackComments_: service, detailIsCurrentVideo: () => true,
    getUIContext: () => ({ getPromptAction: () => ({ showToast: entry => notices.push(entry.message) }) }),
    closeCommentComposer: () => { page.commentSheetVisible = false; },
    loadC: aid => reloads.push(aid)
  });
  let complete;
  response = new Promise(resolve => { complete = resolve; });
  const sending = page.handleCommentSend('first video', []);
  assert.deepEqual(apiCalls[1], [12, 'first video', 0, 0, '']);
  page.vi.bvid = 'BVtwo';
  page.vd = { aid: 42 };
  page.referenceSwitchGeneration++;
  const newTarget = { aid: 42, root: 0, parent: 0, bvid: 'BVtwo', generation: 8 };
  page.commentTarget_ = newTarget;
  complete(success);
  assert.equal(await sending, false);
  assert.equal(page.commentTarget_, newTarget);
  assert.equal(page.commentSheetVisible, true);
  assert.deepEqual(notices, []);
  assert.deepEqual(reloads, []);

  let uploaded;
  upload = () => new Promise(resolve => { uploaded = resolve; });
  response = Promise.resolve(success);
  const dismissed = page.handleCommentSend('already requested', [image]);
  const reopened = { ...newTarget, root: 22, parent: 33 };
  page.commentTarget_ = reopened;
  uploaded({ url: 'https://cdn.example/first.png', width: 12, height: 34 });
  assert.equal(await dismissed, false);
  assert.deepEqual(apiCalls[2].slice(0, 4), [42, 'already requested', 0, 0]);
  assert.equal(page.commentTarget_, reopened, 'same-video reopening keeps the new reply draft intact');
  assert.deepEqual(notices, []);
  assert.deepEqual(reloads, []);

  page.commentTarget_ = newTarget;
  assert.equal(await page.handleCommentSend('second video', []), true);
  assert.deepEqual(notices, ['评论成功']);
  assert.deepEqual(reloads, [42]);
  console.log('PASS: ordered image uploads, fixed comment identity, cancellation and stale completion isolation');
}

main().catch(error => { console.error(error); process.exitCode = 1; });
