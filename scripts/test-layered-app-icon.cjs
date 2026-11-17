/**
 * 应用图标分层规范回归（华为通用应用 UX 体验标准 2.1.4.3.1）：
 *   - app.json5 / module.json5 的 icon 都必须指向分层资源（module 优先级更高，只改 app 不生效）；
 *   - 前景图、背景图都是 1024x1024 PNG；
 *   - 背景图不允许含透明像素、不允许自行裁圆角、不允许四周加内间距；
 *   - 前景图非主体区域 100% 透明，主体不是一张被裁过圆角的满幅方形图；
 *   - AppScope 与 entry 同名资源必须字节一致（打包时 AppScope 会覆盖模块资源）。
 *
 * 只依赖 Node 标准库，直接解析 PNG 的 IHDR/IDAT（含 unfilter），无需第三方包。
 */
const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');
const assert = require('node:assert/strict');

const root = path.resolve(__dirname, '..');
const read = (rel) => fs.readFileSync(path.join(root, rel));
const text = (rel) => read(rel).toString('utf8').replace(/\r\n/g, '\n');

function iconOf(rel) {
  const m = text(rel).match(/"icon"\s*:\s*"([^"]+)"/);
  assert.ok(m, `${rel} 缺少 icon 字段`);
  return m[1];
}

function parsePng(rel) {
  const buf = read(rel);
  assert.equal(buf.subarray(1, 4).toString('ascii'), 'PNG', `${rel} 不是 PNG`);
  let off = 8;
  let w = 0, h = 0, bit = 0, ct = -1;
  const idat = [];
  while (off + 8 <= buf.length) {
    const len = buf.readUInt32BE(off);
    const type = buf.subarray(off + 4, off + 8).toString('ascii');
    const data = buf.subarray(off + 8, off + 8 + len);
    if (type === 'IHDR') {
      w = data.readUInt32BE(0);
      h = data.readUInt32BE(4);
      bit = data[8];
      ct = data[9];
    } else if (type === 'IDAT') {
      idat.push(data);
    }
    off += 12 + len;
    if (type === 'IEND') break;
  }
  assert.ok(w > 0 && h > 0 && ct >= 0 && idat.length > 0, `${rel} PNG 头不完整`);
  assert.equal(bit, 8, `${rel} 位深必须为 8`);
  assert.ok(ct === 2 || ct === 6, `${rel} 必须是 RGB(2) 或 RGBA(6)`);
  const ch = ct === 6 ? 4 : 3;
  const stride = w * ch;
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const px = Buffer.alloc(h * stride);
  let p = 0;
  for (let y = 0; y < h; y++) {
    const filter = raw[p++];
    const row = raw.subarray(p, p + stride);
    p += stride;
    const out = px.subarray(y * stride, (y + 1) * stride);
    const prev = y > 0 ? px.subarray((y - 1) * stride, y * stride) : null;
    for (let x = 0; x < stride; x++) {
      const a = x >= ch ? out[x - ch] : 0;
      const b = prev ? prev[x] : 0;
      const c = (prev && x >= ch) ? prev[x - ch] : 0;
      let v = row[x];
      if (filter === 1) v += a;
      else if (filter === 2) v += b;
      else if (filter === 3) v += (a + b) >> 1;
      else if (filter === 4) {
        const pa = Math.abs(b - c), pb = Math.abs(a - c), pc = Math.abs(a + b - 2 * c);
        v += (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c);
      } else {
        assert.equal(filter, 0, `${rel} 存在未知 PNG filter ${filter}`);
      }
      out[x] = v & 0xff;
    }
  }
  const at = (x, y) => {
    const i = y * stride + x * ch;
    return { r: px[i], g: px[i + 1], b: px[i + 2], a: ct === 6 ? px[i + 3] : 255 };
  };
  return { w, h, ct, ch, at, px, stride };
}

function layeredJson(rel) {
  const j = JSON.parse(text(rel));
  const li = j['layered-image'];
  assert.ok(li, `${rel} 缺少 layered-image 节点`);
  assert.equal(li.background, '$media:background', `${rel} 背景层引用错误`);
  assert.equal(li.foreground, '$media:foreground', `${rel} 前景层引用错误`);
}

// 1) 两处 icon 都必须是分层资源：module.json5 的 ability icon 优先级高于 app.json5，
//    只改 app.json5 会被模块级单层图标覆盖，自检依旧报「图标资源需分层」。
assert.equal(iconOf('AppScope/app.json5'), '$media:layered_image', 'app.json5 的 icon 必须指向分层资源');
assert.equal(iconOf('entry/src/main/module.json5'), '$media:layered_image', 'module.json5 的 icon 必须指向分层资源');
assert.ok(text('entry/src/main/module.json5').includes('"startWindowIcon": "$media:startIcon"'),
  '启动窗口图标保持单层资源（不属于分层应用图标检查项）');

// 2) 两个模块目录各自的分层描述与资源都要齐（AppScope 同名文件会在打包时覆盖模块文件）。
const dirs = ['AppScope/resources/base/media', 'entry/src/main/resources/base/media'];
layeredJson('AppScope/resources/base/media/layered_image.json');
layeredJson('entry/src/main/resources/base/media/layered_image.json');

const appFg = read('AppScope/resources/base/media/foreground.png');
const appBg = read('AppScope/resources/base/media/background.png');
assert.deepEqual(appFg, read('entry/src/main/resources/base/media/foreground.png'), '两处 foreground.png 必须一致');
assert.deepEqual(appBg, read('entry/src/main/resources/base/media/background.png'), '两处 background.png 必须一致');

for (const dir of dirs) {
  const fg = parsePng(`${dir}/foreground.png`);
  const bg = parsePng(`${dir}/background.png`);

  // 尺寸：两层都必须是 1024x1024 正方形。
  assert.equal(fg.w, 1024, `${dir}/foreground.png 宽度`);
  assert.equal(fg.h, 1024, `${dir}/foreground.png 高度`);
  assert.equal(bg.w, 1024, `${dir}/background.png 宽度`);
  assert.equal(bg.h, 1024, `${dir}/background.png 高度`);

  // 背景：不允许透明像素（RGB 无 alpha 通道最稳妥），四角必须是实色渐变，
  // 边缘一圈也不能是统一常量的「白边/内间距」。
  assert.equal(bg.ct, 2, `${dir}/background.png 必须不含 alpha 通道`);
  const bgCorners = [bg.at(0, 0), bg.at(1023, 0), bg.at(0, 1023), bg.at(1023, 1023)];
  for (const c of bgCorners) assert.equal(c.a, 255, `${dir}/background.png 四角不得透明（禁止自行裁圆角）`);
  const cornerKeys = new Set(bgCorners.map((c) => `${c.r},${c.g},${c.b}`));
  assert.ok(cornerKeys.size > 1, `${dir}/background.png 四角颜色不能是同一常量（禁止纯色内间距/白边）`);
  let edgeMin = 255, edgeMax = 0;
  for (let x = 0; x < 1024; x += 8) {
    for (const c of [bg.at(x, 0), bg.at(x, 1023)]) {
      edgeMin = Math.min(edgeMin, c.r, c.g, c.b);
      edgeMax = Math.max(edgeMax, c.r, c.g, c.b);
    }
  }
  assert.ok(edgeMax - edgeMin > 30, `${dir}/background.png 边缘应是铺满的渐变，不是一圈内间距`);

  // 前景：必须带 alpha，非主体区域 100% 透明，四角透明；
  // 主体 bbox 明显小于画布，说明不是把一整张裁了圆角的方形图塞进来。
  assert.equal(fg.ct, 6, `${dir}/foreground.png 必须带透明通道`);
  const fgCorners = [fg.at(0, 0), fg.at(1023, 0), fg.at(0, 1023), fg.at(1023, 1023)];
  for (const c of fgCorners) assert.equal(c.a, 0, `${dir}/foreground.png 四角必须 100% 透明`);
  let transparent = 0, opaque = 0;
  let minX = 1024, minY = 1024, maxX = -1, maxY = -1;
  for (let y = 0; y < 1024; y++) {
    for (let x = 0; x < 1024; x++) {
      const a = fg.at(x, y).a;
      if (a === 0) transparent++;
      else if (a === 255) { opaque++; if (x < minX) minX = x; if (x > maxX) maxX = x; }
      if (y < minY && a > 0) minY = y;
      if (y > maxY && a > 0) maxY = y;
    }
  }
  assert.ok(transparent / (1024 * 1024) > 0.6, `${dir}/foreground.png 非主体区域应 100% 透明`);
  assert.ok(opaque / (1024 * 1024) > 0.2, `${dir}/foreground.png 主体应是不透明的核心图形`);
  assert.ok(minX > 100 && minY > 60 && maxX < 924 && maxY < 964,
    `${dir}/foreground.png 主体应在中心安全区，禁止把一张满幅圆角图当前景`);
}

console.log('PASS 分层应用图标：两处 icon / layered_image.json / 1024x1024 两层 / 前景透明 / 背景不透明无圆角无内间距');
