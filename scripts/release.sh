#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "用法: scripts/release.sh [--dry-run] <版本号> <说明文件>"
  echo "Windows: scripts\release.cmd [--dry-run] <版本号> <说明文件>"
}

fail() {
  echo "错误: $*" >&2
  exit 1
}

if [[ ${1:-} == --help || ${1:-} == -h ]]; then
  usage
  exit 0
fi

dry_run=false
if [[ ${1:-} == --dry-run ]]; then
  dry_run=true
  shift
fi
if [[ $# != 2 ]]; then
  usage >&2
  exit 1
fi

version="$1"
tag="v$version"
[[ -f "$2" ]] && LC_ALL=C grep -q '[^[:space:]]' -- "$2" || fail "说明文件不存在或为空：$2"
notes_file=$(realpath -- "$2")
cd "$(git rev-parse --show-toplevel)"
source scripts/release-version.sh
code=$(release_version_code "$version")

[[ "$(git symbolic-ref --quiet --short HEAD)" == main ]] || fail "请在 main 分支上运行"
[[ -z "$(git status --porcelain)" ]] || fail "请先提交或移走工作区中的改动"
read_app_version
current_version_code=$(release_version_code "$VERSION_NAME")
(( code > VERSION_CODE && code > current_version_code )) ||
  fail "目标版本须高于当前版本 $VERSION_NAME ($VERSION_CODE)"
if git show-ref --verify --quiet "refs/tags/$tag"; then
  fail "本地 tag $tag 已存在"
fi

push_url=$(git remote get-url --push origin)
remote_refs=$(git ls-remote --refs "$push_url" refs/heads/main "refs/tags/$tag")
remote_main=$(awk '$2 == "refs/heads/main" { print $1 }' <<< "$remote_refs")
remote_tag=$(awk -v ref="refs/tags/$tag" '$2 == ref { print $1 }' <<< "$remote_refs")
[[ -n "$remote_main" ]] || fail "远端 main 不存在"
[[ -z "$remote_tag" ]] || fail "远端 tag $tag 已存在"
git merge-base --is-ancestor "$remote_main" HEAD 2>/dev/null ||
  fail "本地 main 未包含远端最新提交，请先同步 origin/main"

echo "版本 $VERSION_NAME ($VERSION_CODE) → $version ($code)"
echo "目标 origin/main、$tag"
echo "发版说明预览"
sed -n '1,8p' "$notes_file"
if "$dry_run"; then
  echo "预检通过。"
  exit 0
fi

git var GIT_AUTHOR_IDENT >/dev/null
git var GIT_COMMITTER_IDENT >/dev/null
sed -i -E \
  -e "s/^([[:space:]]*\"versionCode\"[[:space:]]*:[[:space:]]*)[0-9]+/\1$code/" \
  -e "s/^([[:space:]]*\"versionName\"[[:space:]]*:[[:space:]]*)\"[^\"]*\"/\1\"$version\"/" \
  AppScope/app.json5
read_app_version
[[ "$VERSION_NAME" == "$version" && "$VERSION_CODE" == "$code" ]] ||
  fail "写入版本号后校验失败"

git add -- AppScope/app.json5
git commit -m "release: $version"
git tag -a "$tag" --cleanup=verbatim -F "$notes_file"

if ! git push --atomic --no-follow-tags origin refs/heads/main "refs/tags/$tag"; then
  echo "推送未确认成功，发布提交和 tag 已保留在本地。" >&2
  echo "确认远端状态并解决推送问题后，可重试：" >&2
  echo "  git push --atomic --no-follow-tags origin refs/heads/main refs/tags/$tag" >&2
  exit 1
fi

echo "已推送 $tag，GitHub Actions 将构建并发布未签名 HAP。"
echo "构建记录：gh run list --workflow build-unsigned.yml --branch $tag"
