# 证据与坑（每条都可复跑）

环境：macOS 26.6.2 / UU 远程 4.42.0 / `uuyc-cli` 位于 `/Applications/UURemote.app/Contents/Helpers/uuyc-cli`
被测设备：office-pc（Windows，`aeawuXXXXXXXXXXXX`），实测日 2026-10-22。

## 1. 通道确实成立

```
$ ssh -i ~/.ssh/id_ed25519 -p 2222 Administrator@127.0.0.1 'hostname; whoami'
office-pc
office-pc\administrator

$ perl -MIO::Socket::INET -MTime::HiRes=time -e '...读 banner 计时...'
  44ms / 46ms / 56ms   SSH-2.0-OpenSSH_for_Windows_9.5
```

对照（同一天、同两台机器）：

```
$ ssh Administrator@100.100.100.10 'hostname'      # Tailscale 公网路径
ssh: connect to host 100.100.100.10 port 22: Operation timed out
```

同日更早（13:10）在 Mac 侧跑 `tailscale ping -c 3 100.100.100.10`，三次 **330 / 372 / 331 ms**，路径为 `DERP(sfo)`、`direct connection not established`。原始记录见项目内「连接稳定性排查」文档的 F2 项。SKILL.md 里"330ms / 快约 7 倍"这个说法就来自这里，注意它是 `tailscale ping`（走 DERP）的口径，与上表 banner 往返不是同一种测量。

## 2. 「能连上」不等于「通」——两次实例

### 实例 A：公网 IP 的 22 端口是假开放

```
$ nc -vz -G 6 -w 6 203.0.113.45 22     → succeeded!
$ nc -vz -G 6 -w 6 203.0.113.45 47111  → succeeded!
$ nc -w 5 203.0.113.45 22              → 无 banner
```

两个端口都报 `succeeded`、都拿不到 banner ⇒ 这台设备不是"按端口放行"，至少 22 和 47111 的"成功"都不代表有服务在听。

**能说的**：这个 IP 的 22 端口从外部拿不到 SSH banner，不能作为直连入口。
**不能说的**：不能说"任意端口都假通"（只测了两个）；也不能断言"公网直连整条路线排除"（本次没有在路由器侧加过端口转发再测）。

### 实例 B：本地映射端口的幽灵监听

```
$ ssh ... -p 2222 Administrator@127.0.0.1 'hostname'
Connection timed out during banner exchange
Connection to 127.0.0.1 port 2222 timed out

$ lsof -nP -iTCP:2222 -sTCP:LISTEN
UURemote  1252                       ← 端口还在 LISTEN
```

**判据只能是协议层 banner，不是 TCP 连接成功。** 这是整个 Skill 最重要的一条。

## 3. `device disconnect` 制造幽灵监听

| 手段 | 命令返回 | 端口 | 会话 |
|---|---|---|---|
| `uuyc-cli device disconnect <id>` | `"success": true` | **仍在 LISTEN** | 后端已死 |
| `uuyc-cli term exit <id>` | `"已关闭终端（远端会话保留）"` | 仍在 | 保留 |
| 关闭 `session1` 窗口（AXPress） | — | 仍在，**且通路继续可用** | 保留 |

`term exit --help` 原文：

```
OVERVIEW: 退出指定设备的远程终端列表（会话保留，结束会话请用 lterm kill）
```

但 `lterm` 管的是**本机会话**：

```
$ uuyc-cli lterm ls          → {"sessions": []}      ← 远端会话它看不见
$ uuyc-cli lterm kill session1 → {"error":{"message":"会话不存在"}}
```

**结论：UU 没有提供"结束远端终端会话"的命令，三条 CLI/GUI 路径都试过。清幽灵只能重启客户端——新会话顶替实测不可靠：banner 曾在顶替后 60s 才回来，随后又回落到超时（见第 4 节）。

## 4. 重启 UU 的两个陷阱

**陷阱一：按应用名 quit 无效。**

```
$ osascript -e 'quit application "UURemote"'    # 无报错
$ pgrep -fl 'MacOS/UURemote$'                   # PID 1252 纹丝不动，端口不退
```

必须用 bundle id：

```
$ osascript -e 'tell application id "com.netease.uuremote" to quit'   # 生效，端口释放
```

**陷阱二：重启后规则显示「✓ 成功」但端口不绑。**

现场：面板里 `2222 / 127.0.0.1 / 22 / 映射状态 ✓ 成功 / 开关 ON`，同时

```
$ lsof -nP -iTCP:2222 -sTCP:LISTEN     → 空
$ uulink check                          → office-pc 127.0.0.1:2222 无监听
```

把开关**关一次再开一次**后：

```
$ lsof -nP -iTCP:2222 -sTCP:LISTEN
UURemote  23845                        ← 立刻回来（新 PID）
$ 读 banner → 51ms SSH-2.0-OpenSSH_for_Windows_9.5
```

所以「✓ 成功」是**规则态**，不是**端口绑定态**。这两个不能混。

## 5. 映射规则不在本机明文配置里

```
$ ls "$HOME/Library/Application Support/UURemote"            → 空目录
$ defaults read com.netease.uuremote | grep -iE 'port|map'   → 无相关键
$ find ~/Library -maxdepth 4 -iname '*portmap*'              → 无
```

**能说的**：在 macOS 常见配置目录、`defaults`、以及 `~/Library` 四层内按文件名搜 `portmap`，都没找到映射配置。
**不能说的**：不能据此断言"规则存在服务端、换机自动同步"。没查 `~/Library/Containers`、没查 SQLite、没在第二台机器登录同一账号验证过。跨机同步机制**未实测**。

## 6. `uuyc-cli` 的能力边界（本节是操作记录，未逐条附输出）

有：`version / status / user / device list|info|connect|disconnect|status / cloudpc / assist / term open|exit / lterm ls|new|attach|has|kill|rename / echo`

没有：**端口映射**。二进制里能搜到 `PortMappingService`、`PortMappingWindowController`、`CT_PORTMAPPING`，但 CLI 不暴露。所以规则只能 GUI 加。

## 7. 其他踩过的坑（现场记录，未逐条附输出）

- **`$var` 紧贴全角标点**会被 bash 当成变量名的一部分：`"$name」"` → `name?: unbound variable`。一律写 `${name}`。
- **`awk` 无匹配时仍 exit 0**，用 `$(...) || die` 判断"配置项不存在"会失效，必须显式判空。
- **等待循环别数循环次数**：幽灵态每次探测耗 7s，`while [ $i -lt 90 ]` 实际是 10 分钟。用 `date +%s` 墙钟。
- **screencapture -R 用像素、System Events 用点**，只有两者相等（非 Retina / 1:1）才可直接换算；窗口被遮挡时截到的是上层窗口，先 `AXRaise`。
- **往 GUI `keystroke` 前先切英文输入法**：微信输入法会把 `sshd` 合成"谁说的"、`ft` 合成"丰田"。
- **AX click 对 Qt 自绘按钮无效**，要发真实鼠标事件（CGEvent）。本轮用的 12 行 Swift 点击器在 `scripts/click.swift`。
- **`scp` 在幽灵期会挂死**（>2 分钟无输出）。健康通道上已验证：见 §8。

## 8. 隧道「活着」但链路死了（第三种幽灵），以及 scp 的四向验证

### 8.1 现场：进程在、退出码 0、CPU 0%，但整条是死的

对端掉线期间，`launchd` 管着的反向隧道表现如下：

```
$ launchctl list | grep mac-reverse
94591   0   com.chengchen.mac-reverse-tunnel          # PID 在，上次退出码 0

$ ps -o pid,stat,%cpu -p 94591
94591   S   0.0                                        # 完全空闲，不报错

$ lsof -nP -a -p 94591 -iTCP
ssh 94591  TCP 127.0.0.1:60997->127.0.0.1:2222 (ESTABLISHED)   # 显示"已连接"
```

同时读该通路的 banner：

```
$ python3 -c "import socket;s=socket.create_connection(('127.0.0.1',2222),timeout=6);print(s.recv(64))"
（超时 / 空）
```

**根因**：UU 本地代理在链路已死时仍让 socket 保持 `ESTABLISHED`，`ssh` 往里写既不报错也不超时。于是 `-o ServerAliveInterval=20 -o ServerAliveCountMax=3` **探不到**（它靠"写出去、等到超时没回应"来判定，而这里写出去对方默默吞掉），进程永不退出 ⇒ `launchd` 的 `KeepAlive` 永不触发（它只在进程退出后拉起）。结果是隧道"永远在线"的假象，同时在对端留下幽灵监听（远端 `LISTEN` 在、读不到 banner）。

**结论**：无人值守的隧道，健康判据只能是**banner 级**，且必须由外部定时器驱动（`uulink watch`，`StartInterval=60`）；进程级/端口级检查在这个链路上是无效的。

### 8.2 `nc` 读 banner 的恒定假阴性

```
$ nc -G 6 127.0.0.1 2222 </dev/null | head -c 40    # 空
$ nc -d -G 6 127.0.0.1 2222 | head -c 40            # SSH-2.0-OpenSSH_for_Windows_9.5
```

同一条健康链路，两种写法两个结论。macOS 的 `nc` 默认读 stdin，`</dev/null` 让它一 EOF 就退出、来不及读 banner。**这不是"偶尔失灵"，是恒定假阴性**——链路好和坏都返回空，等于把判据废掉。要么加 `-d`，要么用 python socket。

### 8.3 scp 四向验证（双向 × 正反通道）

样本：512KB 随机文件，两端 SHA256 比对。

| 通道 | 方向 | 结果 | 耗时 |
|---|---|---|---|
| 正向 `-P 2222` | Mac → 对端 | RC=0，SHA 一致 | 1.69 s |
| 正向 `-P 2222` | 对端 → Mac | RC=0，字节一致 | 1.29 s |
| 反向 `-P 2223` | 对端 → Mac | RC=0，SHA 一致 | 1014 ms |
| 反向 `-P 2223` | Mac → 对端 | RC=0，SHA 一致 | 586 ms |

两条附带结论：

- **必须用 ssh 别名**（`scp file office-pc:`）。直接写 `-p 2222 user@127.0.0.1` 会 `Permission denied (publickey)`——密钥绑在别名的 `IdentityFile` 上，裸 IP 那条没有 identity。
- **scp 挂死不一定是通道问题**：本轮最初两次"scp 卡住"都是对端掉线造成的，链路恢复后同一命令 1 秒内完成。先读 banner 再怀疑 scp。

### 8.4 测试看护时，mock 必须走 `UU_LINK_CLI`，塞 PATH 无效

`uulink` 里的 `uu` 是**脚本内函数**，直接 `"$PY" - "$UUCLI" "$@"`，根本不查 PATH：

```bash
uu() { "$PY" - "$UUCLI" "$@" <<'PY' ... }   # $UUCLI 由 $UU_LINK_CLI 或固定路径决定
```

所以 `PATH=/tmp/mock:$PATH uulink watch --once` 这一招**拦不住**，会真的调 `uuyc-cli`。
本轮实测代价：一次"隔离"测试跑了 5 轮，真的对 UU 客户端发了约 15 次 `term open`（日志里 id 是真实设备 id，不是 mock 的 `id-tars`），并在客户端留下会话窗口。

正确做法：

```bash
UU_LINK_CLI=/tmp/mockcli HOME=/tmp/sandbox uulink watch --once
```

**识别征兆**：日志里出现 `term open 成功` 而你明明让 mock 返回 `success:false`
⇒ 说明 mock 没生效，正在打真实 CLI。立刻停下，去 UU 客户端清会话。

回归脚本 `regress-watch.sh` 已按这个约定写好（7 组用例、18 项断言），改完看护先跑它。
