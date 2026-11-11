#!/usr/bin/env bash
# 发版脚本：改版本号 → commit → annotated tag → push
#
# 用法: scripts/release.sh <版本号> <说明文件>
# 例:   scripts/release.sh 2.0.6 docs/next-release.md
# Windows（CMD / PowerShell）: scripts\release.cmd <版本号> <说明文件>
#   （release.cmd 只是转交本脚本的入口，逻辑全在这里）
#
# 规则:
# - versionCode = 主版本*1000000 + 次版本*1000 + 修订号（2.0.5 → 2000005）
# - 说明文件内容原样进 tag message（--cleanup=verbatim，# 开头的行不会被删），
#   同一份文字会成为 GitHub Release 正文、以及应用内「检查更新」展示的内容，
#   所以措辞请按用户视角写
# - 必须在 Git Bash / Linux 下运行；工作区必须干净；tag 不可重复
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "用法: scripts/release.sh <版本号> <说明文件>" >&2
  echo "例:   scripts/release.sh 2.0.6 docs/next-release.md" >&2
  exit 1
fi

VERSION="$1"
NOTES_FILE="$2"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "错误: 版本号必须是 X.Y.Z 形式，收到 '$VERSION'" >&2
  exit 1
fi
if [ ! -f "$NOTES_FILE" ]; then
  echo "错误: 说明文件不存在: $NOTES_FILE" >&2
  exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
  echo "错误: 工作区有未提交改动，先提交或暂存:" >&2
  git status --short >&2
  exit 1
fi
if git rev-parse -q --verify "refs/tags/v${VERSION}" >/dev/null; then
  echo "错误: tag v${VERSION} 已存在（本地）。已发布过的话远端也在，换个版本号" >&2
  exit 1
fi

MAJOR="${VERSION%%.*}"
REST="${VERSION#*.}"
MINOR="${REST%%.*}"
PATCH="${REST##*.}"
CODE=$((MAJOR * 1000000 + MINOR * 1000 + PATCH))

sed -i "s/\"versionCode\": [0-9]*/\"versionCode\": ${CODE}/; s/\"versionName\": \"[^\"]*\"/\"versionName\": \"${VERSION}\"/" AppScope/app.json5
echo "版本号已更新:"
grep -E "versionName|versionCode" AppScope/app.json5

git add AppScope/app.json5
git commit -q -m "release: ${VERSION}"
git tag -a "v${VERSION}" --cleanup=verbatim -F "$NOTES_FILE"
echo "--- tag message 预览（前 3 行）---"
git cat-file -p "refs/tags/v${VERSION}" | sed '1,/^$/d' | head -3
echo "---"

echo "推送 main 与 tag..."
git push origin main
git push origin "v${VERSION}"
echo "完成。CI 会自动构建并发布，盯进度:"
echo "  gh run watch --repo aryue/PuraPily"
