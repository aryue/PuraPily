#!/usr/bin/env bash

# 校验发布版本并计算 AppScope 使用的 versionCode。
release_version_code() {
  local version="$1"
  if [[ "$version" =~ ^(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})$ ]]; then
    echo "$((BASH_REMATCH[1] * 1000000 + BASH_REMATCH[2] * 1000 + BASH_REMATCH[3]))"
  else
    echo "版本号须为 X.Y.Z，每段为 0–999，且无前导零：$version" >&2
    return 1
  fi
}

read_app_version() {
  VERSION_NAME=$(sed -nE 's/^[[:space:]]*"versionName"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' AppScope/app.json5)
  VERSION_CODE=$(sed -nE 's/^[[:space:]]*"versionCode"[[:space:]]*:[[:space:]]*([0-9]+)[[:space:]]*,?[[:space:]]*$/\1/p' AppScope/app.json5)
  if [[ ! "$VERSION_CODE" =~ ^[1-9][0-9]{0,8}$ ]] || ! release_version_code "$VERSION_NAME" >/dev/null; then
    echo "AppScope/app.json5 中的 versionName 或 versionCode 无效" >&2
    return 1
  fi
}
