#!/bin/sh
# Merge observer hooks without replacing existing hooks; inputs may be overridden for tests.
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
codex_config=${YOGO_CODEX_CONFIG:-"$HOME/.codex/hooks.json"}
zcode_config=${YOGO_ZCODE_CONFIG:-"$HOME/.zcode/cli/config.json"}
signal=${YOGO_SIGNAL_PATH:-"$project_dir/.build/YogoLab.app/Contents/MacOS/YogoSignal"}

test -x "$signal" || { printf '%s\n' '找不到 YogoSignal，请先构建 App。' >&2; exit 1; }
test -f "$codex_config" && test -f "$zcode_config" || { printf '%s\n' '未找到现有配置，未作修改。' >&2; exit 1; }
jq -e '(.hooks|type == "object") and ([.hooks[] | type] | all(. == "array"))' "$codex_config" >/dev/null
jq -e '(.hooks|type == "object") and (.hooks.events|type == "object") and ([.hooks.events[] | type] | all(. == "array"))' "$zcode_config" >/dev/null

codex_tmp=$(mktemp "${codex_config}.yogo-tmp.XXXXXX")
zcode_tmp=$(mktemp "${zcode_config}.yogo-tmp.XXXXXX")
trap 'rm -f "$codex_tmp" "$zcode_tmp"' EXIT HUP INT TERM
codex_command=$(jq -nr --arg path "$signal" '$path | @sh + " codex"')
jq --arg command "$codex_command" '
  def add($name):
    .hooks[$name] = ((.hooks[$name] // []) as $groups |
      if any($groups[]?; any(.hooks[]?; .type == "command" and .command == $command)) then $groups
      else $groups + [{hooks:[{type:"command",command:$command,timeout:3}]}] end);
  reduce ["UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse", "Stop", "SessionEnd"][] as $event (. ; add($event))
' "$codex_config" > "$codex_tmp"
jq --arg executable "$signal" '
  def add($name):
    .hooks.events[$name] = ((.hooks.events[$name] // []) as $groups |
      if any($groups[]?; any(.hooks[]?; .type == "process" and .command == $executable and .args == ["zcode"])) then $groups
      else $groups + [{hooks:[{type:"process",command:$executable,args:["zcode"],timeoutMs:3000}]}] end);
  .hooks.enabled = true |
  reduce ["UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse", "PostToolUseFailure", "Stop"][] as $event (. ; add($event))
' "$zcode_config" > "$zcode_tmp"

chmod "$(stat -f %Lp "$codex_config")" "$codex_tmp"
chmod "$(stat -f %Lp "$zcode_config")" "$zcode_tmp"
codex_backup=$(mktemp "${codex_config}.yogo-backup.XXXXXX")
zcode_backup=$(mktemp "${zcode_config}.yogo-backup.XXXXXX")
cp -p "$codex_config" "$codex_backup"
cp -p "$zcode_config" "$zcode_backup"
mv "$codex_tmp" "$codex_config"
if ! mv "$zcode_tmp" "$zcode_config"; then
    cp -p "$codex_backup" "$codex_config"
    printf '%s\n' 'ZCode 配置写入失败，已回滚 Codex 配置。' >&2
    exit 1
fi
printf '已合并状态 Hook。备份：\n%s\n%s\n' "$codex_backup" "$zcode_backup"
printf '%s\n' 'Codex 需审阅信任新 Hook；ZCode 需新建会话。'
