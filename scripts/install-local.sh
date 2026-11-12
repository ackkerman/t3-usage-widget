#!/bin/bash
set -euo pipefail

# This script replaces only this project's app and keeps the old bundle as a recovery copy.
repo_root=$(cd "$(dirname "$0")/.." && pwd)
source_app="$repo_root/build/Build/Products/Release/T3Usage.app"
target_app="$HOME/Applications/T3 Usage.app"
expected_id='local.t3usagewidget.app'
app_executable="$target_app/Contents/MacOS/T3Usage"
extension_executable="$target_app/Contents/PlugIns/T3UsageWidgetExtension.appex/Contents/MacOS/T3UsageWidgetExtension"

bundle_id() { /usr/bin/plutil -extract CFBundleIdentifier raw "$1/Contents/Info.plist"; }
if [[ ! -d "$source_app" ]] || [[ "$(bundle_id "$source_app")" != "$expected_id" ]]; then
  printf '%s\n' 'ビルド済みの T3 Usage.app が見つからないか、識別子が一致しません。' >&2
  exit 1
fi
/usr/bin/codesign --verify --deep --strict "$source_app"
if [[ -d "$target_app" ]] && [[ "$(bundle_id "$target_app")" != "$expected_id" ]]; then
  printf '%s\n' '配置先に異なるアプリがあります。上書きしません。' >&2
  exit 1
fi
# Compare process executable paths exactly; matching a name or regular expression is insufficient.
matching_pids() {
  local executable="$1" candidate actual
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    actual=$(/bin/ps -p "$candidate" -o comm= 2>/dev/null || true)
    if [[ "$actual" == "$executable" ]]; then printf '%s\n' "$candidate"; fi
  done < <(/usr/bin/pgrep -u "$(/usr/bin/id -u)" -f 'T3Usage' || true)
}
if [[ -n "$(matching_pids "$app_executable")" ]]; then
  printf '%s\n' 'T3 Usage が起動中です。終了してから再実行してください。' >&2
  exit 1
fi
# The extension may remain alive after the app quits. Only this app's exact executable is targeted.
extension_pids=$(matching_pids "$extension_executable")
/bin/mkdir -p "$HOME/Applications"
backup_dir=$(/usr/bin/mktemp -d /tmp/t3usage-backup.XXXXXX)
if [[ -d "$target_app" ]]; then /bin/mv "$target_app" "$backup_dir/T3 Usage.app"; fi
if ! /usr/bin/ditto "$source_app" "$target_app" || ! /usr/bin/codesign --verify --deep --strict "$target_app"; then
  printf '%s\n' '配置または署名の検証に失敗しました。復旧コピーを戻します。' >&2
  if [[ -d "$backup_dir/T3 Usage.app" ]]; then
    /bin/mv "$target_app" "$backup_dir/failed-install.app" 2>/dev/null || true
    /bin/mv "$backup_dir/T3 Usage.app" "$target_app"
  fi
  exit 1
fi
# A copied bundle can retain an old modification date and keep its previous system icon cached.
/usr/bin/touch "$target_app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$target_app"
/usr/bin/pluginkit -r "$source_app/Contents/PlugIns/T3UsageWidgetExtension.appex" || true
if [[ -n "$extension_pids" ]]; then
  while IFS= read -r pid; do /bin/kill -TERM "$pid" 2>/dev/null || true; done <<< "$extension_pids"
fi
printf '配置完了。以前のアプリ: %s\n' "$backup_dir"
