const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/components/CommentItemComponent.ets'), 'utf8');
const behavior = {};
for (const name of ['referenceReplyCount', 'referenceVisibleReplies', 'referenceHasHiddenReplies']) {
  const body = source.match(new RegExp(`private ${name}\\(\\): [^{]+\\{([\\s\\S]*?)\\n  \\}`));
  assert.ok(body, `Missing ${name}`);
  behavior[name] = new Function(body[1]);
}

for (const [total, loaded, expanded, visible, hidden] of [
  [0, 0, false, 0, false],
  [1, 1, false, 1, false],
  [2, 2, false, 2, false],
  [2, 2, true, 2, false],
  [2, 1, false, 1, true],
  [2, 0, false, 0, true],
  [3, 3, false, 2, true],
  [3, 3, true, 3, false],
  [31, 20, true, 20, true],
  [0, 2, false, 2, false],
]) {
  const state = Object.assign({}, behavior, {
    comment: { rcount: total },
    replies_: Array.from({ length: loaded }, (_, rpid) => ({ rpid })),
    isExpanded: expanded,
  });
  assert.equal(state.referenceVisibleReplies().length, visible);
  assert.equal(state.referenceHasHiddenReplies(), hidden);
}
assert.match(source, /else if \(this\.isExpanded && this\.referenceReplyCount\(\) > 2\)/);
assert.match(source, /maxLines: this\.isExpanded \|\| this\.referenceReplyCount\(\) <= 2 \? 999 : 3/);
console.log('Reply visibility: 10 cases passed; short threads stay fully visible.');
