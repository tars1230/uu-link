#!/usr/bin/env bash
# uu-link 安装脚本（macOS）
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="${UU_LINK_BIN:-$HOME/.local/bin}"
SKILL_DIR="${UU_LINK_SKILL:-$HOME/.workbuddy/skills/uu-link}"
UUCLI="/Applications/UURemote.app/Contents/Helpers/uuyc-cli"

say() { printf '%s\n' "$*"; }
ok()  { printf '\033[32m✓ %s\033[0m\n' "$*"; }
warn(){ printf '\033[33m! %s\033[0m\n' "$*"; }
die() { printf '\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

say "── 环境检查 ──"
[ "$(uname -s)" = "Darwin" ] || die "这个安装脚本只支持 macOS（Windows 版 UU 没有 CLI）"

for c in python3 perl lsof osascript; do
  command -v "$c" >/dev/null 2>&1 && ok "$c" || die "缺依赖：$c"
done

if [ -x "$UUCLI" ]; then
  ok "UU 客户端 CLI 就位"
else
  warn "没找到 $UUCLI"
  warn "先安装并登录网易 UU 远程，再重跑本脚本"
  exit 1
fi

say "── 安装 ──"
mkdir -p "$BIN_DIR" "$SKILL_DIR/scripts" "$SKILL_DIR/references"
install -m 755 "$SRC/skill/scripts/uulink"      "$BIN_DIR/uulink"
install -m 755 "$SRC/skill/scripts/uulink"      "$SKILL_DIR/scripts/uulink"
install -m 644 "$SRC/skill/scripts/click.swift" "$SKILL_DIR/scripts/click.swift"
install -m 644 "$SRC/skill/SKILL.md"            "$SKILL_DIR/SKILL.md"
install -m 644 "$SRC/skill/references/traps.md" "$SKILL_DIR/references/traps.md"
ok "命令装到 $BIN_DIR/uulink"
ok "Skill 装到 $SKILL_DIR"

case ":$PATH:" in
  *":$BIN_DIR:"*) ok "PATH 已包含 $BIN_DIR" ;;
  *) warn "$BIN_DIR 不在 PATH 里，加一行到 ~/.zshrc："
     printf '    export PATH="%s:$PATH"\n' "$BIN_DIR" ;;
esac

say "── 自检 ──"
if "$BIN_DIR/uulink" check; then
  say ""
  ok "装好了。下一步："
  say "    1. 在 UU 里给目标设备加一条端口映射（本地 2222 → 127.0.0.1:22）"
  say "    2. 把设备写进 ~/.config/uulink/devices.tsv"
  say "    3. uulink up <名称> && uulink ssh <名称>"
  say ""
  warn "如果这条通路要无人值守（比如开机就挂着的隧道），还要装看护："
  say "    uulink watch --install"
  say "  不装的话，链路断掉时 ssh 进程不会退出，launchd 的 KeepAlive 也就不会触发，"
  say "  隧道会「看起来在线」但实际上整条是死的（详见 references/traps.md §8）。"
  say "  装完记得登记依赖：~/.config/uulink/tunnels.tsv（设备名<TAB>launchd 标签），"
  say "  否则看护只会修通路、不会重启你的隧道。"
else
  warn "自检没跑完，先确认 UU 已登录"
fi
