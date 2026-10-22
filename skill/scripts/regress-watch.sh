#!/bin/bash
# 看护（uulink watch）回归测试。
#
# 纪律：
#   · 只用 /tmp 下的沙箱 HOME，绝不读写真实 ~/.config/uulink
#   · 必须用 UU_LINK_CLI 指向 mock —— uulink 里的 uu() 是内部函数，
#     直接把 mock 放进 PATH 是拦不住的，会真的打到 UURemote 客户端去开会话
#   · 不装/不卸 launchd，只测脚本行为
#
# 用法：bash skill/scripts/regress-watch.sh [-v]
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
UU="$HERE/uulink"
[ -f "$UU" ] || { echo "找不到 $UU"; exit 1; }
VERBOSE=0
[ "${1:-}" = "-v" ] && VERBOSE=1
ROOT=$(mktemp -d /tmp/uulink-regress.XXXXXX) || exit 1
trap 'rm -rf "$ROOT"' EXIT
PASS=0; FAIL=0

ok()  { PASS=$((PASS+1)); printf '  \033[32mok\033[0m   %s\n' "$*"; }
bad() { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m %s\n' "$*"; }
head2() { printf '\n\033[1m%s\033[0m\n' "$*"; }

# 造一个沙箱 HOME：devices.tsv + mock CLI（term open 恒失败）
mkhome() { # $1=端口 $2=设备名(默认 TARS) $3=id
  local h n p i
  h=$(mktemp -d "$ROOT/h.XXXXXX")
  n="${2:-TARS}"; p="$1"; i="${3:-id-tars}"
  mkdir -p "$h/.config/uulink"
  printf '%s\t%s\t%s\troot\tk\n' "$n" "$i" "$p" >"$h/.config/uulink/devices.tsv"
  cat >"$h/mockcli" <<MOCK
#!/bin/bash
if [ "\${1:-} \${2:-}" = "device list" ]; then
  echo '{"data":{"devices":[{"deviceName":"$n","deviceId":"$i","isOnline":true}]}}'
  exit 0
fi
if [ "\${1:-} \${2:-}" = "term open" ]; then
  echo '{"success":false,"message":"mock: 对端无响应"}'
  exit 0
fi
echo '{}'
MOCK
  chmod +x "$h/mockcli"
  printf '%s' "$h"
}

# 造一个"设备在 UU 里离线"的 mock
mkhome_offline() {
  local h n p
  h=$(mktemp -d "$ROOT/h.XXXXXX"); n="${2:-TARS}"; p="$1"
  mkdir -p "$h/.config/uulink"
  printf '%s\tid-tars\t%s\troot\tk\n' "$n" "$p" >"$h/.config/uulink/devices.tsv"
  cat >"$h/mockcli" <<MOCK
#!/bin/bash
if [ "\${1:-} \${2:-}" = "device list" ]; then
  echo '{"data":{"devices":[{"deviceName":"$n","deviceId":"id-tars","isOnline":false}]}}'
  exit 0
fi
echo '{}'
MOCK
  chmod +x "$h/mockcli"
  printf '%s' "$h"
}

run_watch() { # $1=home 其余=参数
  local h="$1"; shift
  HOME="$h" UU_LINK_CLI="$h/mockcli" \
    perl -e 'alarm 45; exec @ARGV' bash "$UU" watch "$@" >"$h/out.txt" 2>&1
}

# ---------- T1：不通 + 设备列表里查无此设备，不许崩 ----------
head2 "T1 断线且设备名不在列表：不崩、有日志、有状态"
# 关键：devices.tsv 里写 ghost，但 mock 的 UU 列表里只有 TARS ⇒ 触发"查无此设备"分支，
# 这个分支必走 wlog —— 老版本就是在 wlog 里读未定义的 WERR 而整轮崩掉
H=$(mkhome 59991 TARS)
printf 'ghost\tid-ghost\t59991\troot\tk\n' >"$H/.config/uulink/devices.tsv"
run_watch "$H" --once -q; rc=$?
[ "$rc" -eq 0 ] && ok "退出码 0（此前 WERR 未定义会崩成 1）" || bad "退出码 ${rc}，期望 0"
[ -f "$H/.config/uulink/watch.log" ] && ok "写了 watch.log" || bad "没有 watch.log（日志会全丢）"
[ -f "$H/.config/uulink/watch.state" ] && ok "写了 watch.state" || bad "没有 watch.state（退避状态全丢）"
! grep -q 'unbound variable' "$H/out.txt" 2>/dev/null && ok "无 unbound variable" || bad "仍然 unbound variable"

# ---------- T2：设备离线不应计入补救次数 ----------
head2 "T2 设备在 UU 里离线：不尝试、也不累加失败次数"
H=$(mkhome_offline 59992)
for _ in 1 2 3; do run_watch "$H" --once -q; done
fails=$(awk -F'\t' '{print $2}' "$H/.config/uulink/watch.state" 2>/dev/null)
[ "${fails:-x}" = "0" ] && ok "3 轮后 fails=0（离线不算补救失败，回网立刻首修）" || bad "fails=${fails}，期望 0"
grep -q '离线' "$H/.config/uulink/watch.log" 2>/dev/null && ok "日志说明了是离线" || bad "日志没记录离线判断"

# ---------- T3：退避正好在"尝试 3 次"之后 ----------
head2 "T3 连续失败：真正动手补救 3 次后才退避"
H=$(mkhome 59993)
for _ in 1 2 3 4 5; do run_watch "$H" --once -q; done
n=$(grep -c '开始自愈' "$H/.config/uulink/watch.log" 2>/dev/null)
[ "${n:-0}" -eq 3 ] && ok "5 轮里只尝试 3 次" || bad "尝试了 $n 次，期望 3"
grep -q '转入 15 分钟退避' "$H/.config/uulink/watch.log" 2>/dev/null \
  && ok "退避这件事落了日志（launchd 下 stdout 会丢）" || bad "退避没有落日志，运维看不见"

# ---------- T4：通路自己好了也要踢隧道 ----------
head2 "T4 通路自己恢复（不是看护修的）：必须踢一次旧隧道"
H=$(mkhome 59994)
printf 'TARS\t2\t1\n' >"$H/.config/uulink/watch.state"          # 假装上一轮刚失败过
printf 'TARS\tcom.uulink.regress.nonexistent\n' >"$H/.config/uulink/tunnels.tsv"
cat >"$H/banner.py" <<'PY'
import socket, threading, time, sys
port = int(sys.argv[1])
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", port)); s.listen(16)
def loop():
    while True:
        try: c, _ = s.accept()
        except Exception: return
        try: c.sendall(b"SSH-2.0-regress\r\n")
        except Exception: pass
        finally: c.close()
threading.Thread(target=loop, daemon=True).start()
time.sleep(30)
PY
python3 "$H/banner.py" 59994 &
BANNER_PID=$!
sleep 1
run_watch "$H" --once -q
kill $BANNER_PID 2>/dev/null; wait $BANNER_PID 2>/dev/null
grep -q '通路恢复' "$H/.config/uulink/watch.log" 2>/dev/null && ok "识别为恢复" || bad "没识别成恢复"
grep -q 'kickstart com.uulink.regress.nonexistent' "$H/.config/uulink/watch.log" 2>/dev/null \
  && ok "恢复了也踢了隧道（旧 ssh 不会自己发现链路死）" || bad "恢复后没踢隧道，旧连接会一直挂着"

# ---------- T5：新鲜的外部锁 —— 跳过，而且不能删 ----------
head2 "T5 别人正持锁：本轮跳过，且绝不删别人的锁"
H=$(mkhome 59995)
mkdir -p "$H/.config/uulink/watch.lock"
printf 'other-token\n' >"$H/.config/uulink/watch.lock/owner"
run_watch "$H" --once
[ -d "$H/.config/uulink/watch.lock" ] && ok "锁还在（EXIT trap 只删自己的）" || bad "锁被删了 → 第三个实例会并发进场"
[ "$(cat "$H/.config/uulink/watch.lock/owner" 2>/dev/null)" = "other-token" ] && ok "未篡改 owner" || bad "owner 被覆盖"
grep -q '上一轮看护还在跑' "$H/out.txt" 2>/dev/null && ok "提示了在跳过" || bad "没有任何提示"

# ---------- T6：陈旧锁要被回收 ----------
head2 "T6 陈旧锁（崩溃残留）：必须能回收"
H=$(mkhome 59996)
mkdir -p "$H/.config/uulink/watch.lock"
printf 'stale-token\n' >"$H/.config/uulink/watch.lock/owner"
touch -t 202001010000 "$H/.config/uulink/watch.lock"
run_watch "$H" --once -q
grep -q '开始自愈' "$H/.config/uulink/watch.log" 2>/dev/null && ok "回收后正常执行了" || bad "被陈旧锁挡住，看护永久停摆"
[ ! -d "$H/.config/uulink/watch.lock" ] && ok "跑完清干净" || bad "锁残留"

# ---------- T7：抖动不许触发破坏性动作 ----------
head2 "T7 单次采样失败但复采正常（抖动）：不动手、不踢隧道"
H=$(mkhome 59997)
printf 'TARS\tcom.uulink.regress.nonexistent\n' >"$H/.config/uulink/tunnels.tsv"
cat >"$H/flaky.py" <<'PY'
import socket, threading, time, sys
port = int(sys.argv[1]); n = {"c": 0}
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", port)); s.listen(16)
def loop():
    while True:
        try: c, _ = s.accept()
        except Exception: return
        n["c"] += 1
        try:
            if n["c"] == 1:
                pass                      # 第一次：连上就关，读不到 banner
            else:
                c.sendall(b"SSH-2.0-regress\r\n")
        except Exception: pass
        finally: c.close()
threading.Thread(target=loop, daemon=True).start()
time.sleep(30)
PY
python3 "$H/flaky.py" 59997 &
FL_PID=$!
sleep 1
run_watch "$H" --once -q
kill $FL_PID 2>/dev/null; wait $FL_PID 2>/dev/null
grep -q '抖动' "$H/.config/uulink/watch.log" 2>/dev/null && ok "认出是抖动" || bad "没认出抖动"
! grep -q '开始自愈' "$H/.config/uulink/watch.log" 2>/dev/null && ok "没有动手自愈" || bad "抖动也去自愈了（会误踢好隧道）"
! grep -q 'kickstart' "$H/.config/uulink/watch.log" 2>/dev/null && ok "没有踢隧道" || bad "抖动把隧道踢了"

# ---------- 汇总 ----------
printf '\n\033[1m结果：%d 通过，%d 失败\033[0m\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
