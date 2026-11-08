const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/components/VideoListItem.ets'), 'utf8');
const format = source.slice(source.indexOf('export function'), source.indexOf('/** Layout only:'))
  .replace(/export /g, '').replace(/: number/g, '').replace(/: string/g, '');
// Execute the actual shipped formatter bodies; fix the clock for midnight boundaries.
const now = new Date(2026, 9, 23, 0, 5).getTime();
const NativeDate = Date;
class FixedDate extends NativeDate { constructor(...args) { super(...(args.length ? args : [now])); } }
const f = new Function('Date', 'fmtRelativeTime', format + '; return { videoListDuration, videoListCount, videoListPublished };')(FixedDate, ts => `relative:${ts}`);
for (const [seconds, expected] of [[-1,'0:00'],[0,'0:00'],[59,'0:59'],[60,'1:00'],[3599,'59:59'],[3600,'1:00:00'],[3661,'1:01:01']]) assert.equal(f.videoListDuration(seconds), expected);
for (const [count, expected] of [[0,'0'],[9999,'9999'],[10000,'1.0万'],[123456,'12.3万'],[100000000,'1.0亿']]) assert.equal(f.videoListCount(count), expected);
assert.equal(f.videoListPublished(0), '');
assert.equal(f.videoListPublished(new NativeDate(2026,9,22,23,59).getTime()/1000), '昨天 23:59');
assert.equal(f.videoListPublished(new NativeDate(2026,9,22,0,0).getTime()/1000), '昨天 00:00');
const older = new NativeDate(2026,9,21,23,59).getTime()/1000;
assert.equal(f.videoListPublished(older), `relative:${older}`);
const today = now/1000;
assert.equal(f.videoListPublished(today), `relative:${today}`);
console.log('Video list: duration/hour, count-unit, unknown date and calendar-midnight boundaries passed.');
