#!/usr/bin/env node
/**
 * 动画帧率门禁 —— 项目开发原则（2026-11-20 定稿，见 AGENTS.md「动画帧率」）
 *
 * 规则（不再逐次讨论、不靠人工记忆）：
 *  1. 凡带补间的动画入口 —— `animateTo` / `animateToImmediately` /
 *     `.animation({})`（含 `TransitionEffect.*.animation()`）、
 *     以及没有 `.animation()` 的裸 `.transition()` —— 都必须声明
 *     `expectedFrameRateRange: { min: 60, max: 120, expected: 120 }`。
 *     设备跑在 120Hz，不声明时 ArkUI 按 60Hz 出帧，160~380ms 的
 *     弹出/收起/转场只有十几帧，观感就是「一顿一顿」。
 *  2. 唯一自动例外：`duration: 0` —— 没有补间，该字段无作用对象。
 *  3. 其余确需保留 60Hz 的入口，必须在**同一个参数对象 / 同一条调用内**
 *     写 `// MOTION-EXEMPT: <一句话理由>`。例外必须显式、就近、可审查；
 *     禁止用「看起来像跟手动画」这类直觉分类绕过（2026-11-09 靠直觉
 *     归类漏掉浮动底栏、bgFade、握姿弹簧，返工了四轮）。
 *  4. 帧率参数值本身也校验，不允许写 30/60/90 等其它档位；helper 形式
 *     `animateTo(this.xxxMotion(), …)` 会回查函数定义。
 *
 * 本脚本属于 `scripts/test-*.cjs` 全量回归，也在 CI 里单独跑。
 * 新增动画漏加 → 直接 FAIL，不需要人工回来复查清单。
 *
 * 修复方式（二选一，不要改本脚本的判定逻辑）：
 *  - 补帧率：`{ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, … }`
 *  - 保留 60Hz：在同一参数对象里补 `// MOTION-EXEMPT: <理由>`
 */
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

const ETS_ROOT = path.join(__dirname, '../entry/src/main/ets');
const EXEMPT = 'MOTION-EXEMPT';
const RATE_RE = /expectedFrameRateRange\s*:\s*\{\s*min\s*:\s*60\s*,\s*max\s*:\s*120\s*,\s*expected\s*:\s*120\s*\}/;
const RATE_ANY = /expectedFrameRateRange/;
const RATE_SNIPPET = 'expectedFrameRateRange: { min: 60, max: 120, expected: 120 }';

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.ets')) out.push(p);
  }
  return out;
}

/** 括号配对：跳过字符串字面量与注释内的括号，避免模板字符串 / 注释干扰。 */
function matching(src, start, openCh, closeCh) {
  let depth = 0;
  let quote = null;
  let lineComment = false;
  let blockComment = false;
  for (let i = start; i < src.length; i++) {
    const c = src[i];
    const n = src[i + 1];
    if (lineComment) { if (c === '\n') lineComment = false; continue; }
    if (blockComment) { if (c === '*' && n === '/') { blockComment = false; i++; } continue; }
    if (quote) {
      if (c === '\\') { i++; continue; }
      if (c === quote) quote = null;
      continue;
    }
    if (c === '/' && n === '/') { lineComment = true; i++; continue; }
    if (c === '/' && n === '*') { blockComment = true; i++; continue; }
    if (c === '\'' || c === '"' || c === '`') { quote = c; continue; }
    if (c === openCh) depth++;
    else if (c === closeCh && --depth === 0) return i;
  }
  return -1;
}

/** 该匹配点是否落在被注释掉的源码行里。 */
function commentedOut(src, idx) {
  const lineStart = src.lastIndexOf('\n', idx) + 1;
  return /^\s*(\/\/|\*|\/\*)/.test(src.slice(lineStart, idx));
}

function lineOf(src, idx) {
  return src.slice(0, idx).split('\n').length;
}

function classify(src, idx) {
  const before = src.slice(Math.max(0, idx - 400), idx);
  return before.includes('TransitionEffect') ? 'TransitionEffect.animation' : '.animation(属性)';
}

/** helper 形式 `this.btnSwapTransition()` 的函数体（用于回查帧率声明）。 */
function helperBody(src, name) {
  const defRe = new RegExp('(?:private|public|protected|static)\\s+' + name + '\\s*\\(');
  const def = defRe.exec(src);
  if (!def) return '';
  const b = src.indexOf('{', def.index);
  const e = matching(src, b, '{', '}');
  return e > 0 ? src.slice(b, e + 1).replace(/\s+/g, ' ') : '';
}

/**
 * 剥掉注释后再做「代码里是否声明了帧率 / 是否已有 .animation()」判定。
 * 例外标记本身写在注释里，注释内容不能反过来骗过门禁；EXEMPT 检测仍用原文。
 */
function stripComments(s) {
  return s.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/\/\/[^\n]*/g, ' ');
}

const stats = { total: 0, rated: 0, durationZero: 0, exempt: 0, badRate: [], violations: [] };

for (const file of walk(ETS_ROOT)) {
  const src = fs.readFileSync(file, 'utf8');
  const rel = path.relative(path.join(__dirname, '..'), file).replace(/\\/g, '/');
  const record = (line, kind, obj) => {
    stats.total++;
    const code = stripComments(obj);
    if (RATE_ANY.test(code)) {
      if (!RATE_RE.test(code)) {
        stats.badRate.push(`${rel}:${line}  ${kind}  ${obj.slice(0, 100)}`);
        return;
      }
      stats.rated++;
      return;
    }
    if (/duration\s*:\s*0\s*(?:,|})/.test(code)) { stats.durationZero++; return; }
    if (obj.includes(EXEMPT)) { stats.exempt++; return; }
    stats.violations.push(`${rel}:${line}  ${kind}  ${obj.slice(0, 110)}`);
  };

  // 1) 带字面量参数对象的动画：animateTo / animateToImmediately / .animation
  const re = /(animateToImmediately|animateTo|\.animation)\s*\(\s*\{/g;
  let m;
  while ((m = re.exec(src))) {
    if (commentedOut(src, m.index)) continue;
    const brace = src.indexOf('{', m.index);
    const end = matching(src, brace, '{', '}');
    if (end < 0) continue;
    const obj = src.slice(brace, end + 1).replace(/\s+/g, ' ').trim();
    const kind = m[1] === '.animation' ? classify(src, m.index) : m[1];
    record(lineOf(src, m.index), kind, obj);
  }

  // 2) helper 形式：animateTo(this.resultOptionsMotion(), …)
  const re2 = /animateTo(?:Immediately)?\s*\(\s*(?:this\.)?([A-Za-z_]\w*)\s*\(/g;
  while ((m = re2.exec(src))) {
    if (commentedOut(src, m.index)) continue;
    const name = m[1];
    const body = helperBody(src, name);
    const code = stripComments(body);
    stats.total++;
    if (RATE_ANY.test(code)) {
      if (!RATE_RE.test(code)) stats.badRate.push(`${rel}:${lineOf(src, m.index)}  animateTo(${name}())  ${body.slice(0, 100)}`);
      else stats.rated++;
    } else if (body.includes(EXEMPT)) stats.exempt++;
    else stats.violations.push(`${rel}:${lineOf(src, m.index)}  animateTo(${name}())  helper 定义未声明帧率`);
  }

  // 3) 裸 .transition(TransitionEffect.X) —— 没有 AnimateParam 对象
  const re3 = /\.transition\s*\(/g;
  while ((m = re3.exec(src))) {
    if (commentedOut(src, m.index)) continue;
    const open = src.indexOf('(', m.index);
    const end = matching(src, open, '(', ')');
    if (end < 0) continue;
    const body = src.slice(open + 1, end).replace(/\s+/g, ' ').trim();
    if (stripComments(body).includes('.animation(')) continue; // 已在 1) 覆盖
    // helper 形式 `.transition(this.btnSwapTransition())`：帧率写在函数定义里
    const helper = /^(?:this\.)?([A-Za-z_]\w*)\s*\(\s*\)$/.exec(stripComments(body).trim());
    const target = helper ? helperBody(src, helper[1]) : body;
    const code = stripComments(target);
    stats.total++;
    if (RATE_ANY.test(code)) { if (RATE_RE.test(code)) stats.rated++; else stats.badRate.push(`${rel}:${lineOf(src, m.index)}  .transition()  ${target.slice(0, 100)}`); }
    else if (target.includes(EXEMPT)) stats.exempt++;
    else stats.violations.push(`${rel}:${lineOf(src, m.index)}  .transition()  ${body.slice(0, 100)}`);
  }
}

console.log(`[motion] 动画入口 ${stats.total}：已声明 120Hz ${stats.rated}，duration:0 ${stats.durationZero}，登记例外 ${stats.exempt}`);

if (stats.badRate.length) {
  console.error('\n[motion] 帧率参数值不符合项目统一档位（必须是 60/120/120）：');
  for (const r of stats.badRate) console.error('  ' + r);
}
if (stats.violations.length) {
  console.error('\n[motion] 以下动画入口未声明 120Hz，且没有登记例外：');
  for (const r of stats.violations) console.error('  ' + r);
  console.error(`\n[motion] 修复二选一：补 \`${RATE_SNIPPET}\`，或在同一参数对象内写 \`// ${EXEMPT}: <理由>\`。`);
}

assert.equal(stats.badRate.length, 0, `${stats.badRate.length} 处帧率参数值不合规`);
assert.equal(stats.violations.length, 0, `${stats.violations.length} 处动画漏加 120Hz 声明（详见上方清单）`);
console.log('PASS motion-frame-rate: 所有动画入口均已声明 120Hz 或显式登记例外');
