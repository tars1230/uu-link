# uu-link

用 **网易 UU 远程**自带的端口映射，一条命令建立到任意一台 UU 账号设备的 SSH 通路。

不新造隧道、不开公网端口、不买云主机——借 UU 已经调好的那条境内稳定通道。

通路一旦建起来，`ssh` / `scp` / `rsync` / VS Code Remote / 任何自动化脚本都能直接用；断了看护会自己重建。**把"人点鼠标看桌面"变成可编程的 `ssh`**。

```
$ uulink ssh office-pc 'hostname'
office-pc
```

## 为什么不用 Tailscale / frp / 公网 IP

实测同两台机器、同一天：

| 路径 | 结果 |
|---|---|
| UU 端口映射（本方案） | **44–56 ms**，`whoami` → `office-pc\administrator` |
| Tailscale 走境外中继 | `Operation timed out`（偶尔通时约 330 ms） |
| 目标机公网 IP 直连 | TCP 能"连上"但拿不到 banner —— **中间盒假通** |

同城跨运营商（移动 ↔ 电信）打洞失败、境外中继绕路，是那两个方案在这里失效的原因。UU 的落点在境内，同城只需要一个节点。

## 安装

```bash
git clone https://github.com/tars1230/uu-link.git
cd uu-link
./install.sh
```

装两样东西：

- `~/.local/bin/uulink` —— 命令行工具
- `~/.workbuddy/skills/uu-link/` —— WorkBuddy Skill（让 AI 自动用，不用记命令）

前提：macOS + 已登录的 UU 远程客户端（自带 `uuyc-cli`，脚本会自动定位：环境变量 `UU_LINK_CLI` > 脚本同级目录 > `/Applications/UURemote.app/Contents/Helpers/`）。

**首次运行会请求授权**：`up` 成功后脚本用 AppleScript 关掉多出来的终端窗口，macOS 会要求给终端授予「辅助功能」与「自动化」权限。不授权也能用，只是窗口要手动关。

## 首次配置（每对设备一次）

映射规则只能**在 UU 的图形界面里加**（CLI 没有这个命令）。在**发起方**那台机器上：

1. UU 主窗口 → **先选中目标设备**（点进去，让顶部显示那台设备名）→ **端口映射** → 添加
2. 填三项：`本地端口 2222` / `目标地址 127.0.0.1` / `目标端口 22`
3. 打开开关，状态显示「✓ 成功」

再把设备写进 `~/.config/uulink/devices.tsv`（首次运行 `uulink` 会自动创建模板）：

```
# name	deviceId	localport	sshuser	key
office-pc	-	2222	administrator	~/.ssh/id_ed25519
```

`deviceId` 写 `-` 表示每次从 `uulink list` 按名称自动取。

## 用法

```bash
uulink                   # 体检：UU 登录态、设备在线、通路是「真通 / 幽灵 / 无监听」
uulink check office-pc   # 只查这一条（名称写错会报错，不会静默查别人）
uulink list              # 设备列表 + 哪些已配通路
uulink up office-pc      # 没通路就自己建会话，通了才返回
uulink ssh office-pc     # 进去
uulink ssh office-pc 'hostname; whoami'
uulink watch --install   # 装常驻看护：每分钟 banner 检测，断了自动修
```

`up` 建的是**轻会话**（UU 的远程终端，不拉整块桌面），起来后会自动把弹出的窗口关掉。窗口关掉不影响映射。

## 日常怎么用（以及它到底省了什么）

### 一次准备，之后零操作

```bash
uulink up office-pc          # 建一次轻会话，确认能通
uulink watch --install       # 装常驻看护：每分钟检查，断了自动修
```

之后每天就一条命令：

```bash
ssh office-pc                # 或 uulink ssh office-pc 'hostname'
```

断网回来、睡醒合盖、网络抖动 —— 看护会在 60 秒内把会话重建起来，不用手动做什么。

如果 `ssh` 直接连不上，先跑一条命令：

```bash
uulink up office-pc          # 建会话，通了才返回
uulink check                 # 还是不行就看它报什么：幽灵 / 无监听 / 设备离线
```

> **UU 客户端本身重启过（开机、应用更新）之后**，映射规则的开关可能需要重开一次才绑端口——这是 UU 自己的行为，`uulink up` 能不能替它完成取决于当时的状态。先试 `uulink up`，不行再按 README 末尾「装完连不上？」的步骤，去映射面板把开关关一次再开。

### 「只登录 UU 就行吗」——不行，但很接近

这四个问题要分清，因为网上讲端口映射的文章经常把它们混成一件事：

| 问题 | 答案 |
|---|---|
| 需要一直开着远程桌面窗口吗 | **不需要**。`up` 建的是轻会话，窗口还会自己关掉 |
| 需要登录 UU 客户端并保持运行吗 | **需要**。这是 UU 自身的机制 |
| 需要你手动点「连接」吗 | **不需要**。看护发现端口没起来，自己建 |
| **只登录、不建任何会话，能 ssh 吗** | **不能** |

最后一行的原因是 UU 的机制：**映射规则挂在会话上**。没有会话，本地端口根本不会监听，`ssh` 直接 `Connection refused`——不是慢，是没人听。

所以准确的描述是：**不需要你点连接，但链路仍然依赖一次会话，这一次由看护替你完成。**

真实场景对照：

```bash
# 只登录 UU，没有会话
$ ssh office-pc
ssh: connect to host 127.0.0.1 port 2222: Connection refused

# 看护跑起来之后（最多等 60 秒，或者手动 uulink up office-pc）
$ ssh office-pc
office-pc\administrator        # 通了
```

### 省掉的到底是什么

| | 用 UU 远程桌面 | 用 uu-link |
|---|---|---|
| 每次开工 | 打开 UU → 选中设备 → 点「远程桌面」→ 等桌面出来 → 在里面开终端 | `ssh office-pc` |
| 传文件 | 桌面里拖拽，或走剪切板 | `scp` / `rsync` / VS Code Remote 直接连 |
| 跑脚本、定时任务、CI | 做不到（要人点鼠标） | 和本地一样，随便写 |
| 断线之后 | 手动重连，重新等桌面 | 60 秒内自动重建，日志可查 |
| 占带宽 | 传整块画面 | 只传 SSH 字节流（实测 44–56 ms） |
| 关机重启 | 再来一遍（点连接 + 等桌面） | 看护自动重建会话；端口没回来就一条 `uulink up` |

**这才是它真正的价值**：UU 已经调好了一条境内通道（同城 44 ms，同一个环境下 Tailscale 走境外中继是超时的），但这条通道的入口是「人点鼠标 + 一块桌面」。uu-link 把这条通道接进命令行——于是 `ssh`、`scp`、`rsync`、`git`、编辑器远程、自动化脚本全都能用，而且断了会自己回来。

一句话：**不另造隧道，把现成的好通道变成可编程的。** 省的不是配置时间，是"这件事能不能被自动化"这个天壤之别。

## 断线自愈：`uulink watch`

`up` 是"人发现不通了才去修"。**无人值守的隧道需要看护**，而这个仓库踩过的最大一个坑就是：**launchd 的 `KeepAlive` 保不住它**。

链路死掉时，UU 本地代理仍让 socket 保持 `ESTABLISHED`，`ssh` 往里写既不报错也不超时，于是 `-o ServerAliveInterval=20` 根本探不到 —— 进程永不退出，`KeepAlive` 也就永不触发（它只管"进程死了再拉起"，管不了"进程活着但链路是死的"）。结果：隧道"看起来一切正常"，实际整条是死的，同时在对端留下一个幽灵监听。

所以看护只有一个判据：**读得到 banner 才算通**。

```bash
uulink watch --install     # 装 launchd 常驻（每 60s 一轮），装完立刻生效
uulink watch --once        # 只跑一轮，看它怎么判断
uulink watch               # 前台循环（调试用）
uulink watch --uninstall   # 卸掉
```

每轮做四件事：

1. 读 banner 判活（端口在监听不算数，必须读到 `SSH-` 开头那一行）；失败会**隔 2s 再采一次**，抖动的这一次不动手。
2. 真断了 → `term open` 重建会话，等 banner 通。
3. **等通路确认通了，才**重启 `~/.config/uulink/tunnels.tsv` 里登记的常驻隧道（踢掉卡在死 socket 上的旧连接）。
4. 若通路是**它自己好的**（不是看护修的），但上一轮还显示失败，也要踢一次——旧 ssh 进程不会自己发现链路死了，不踢就一直挂着。

> 顺序不能反：先踢隧道再建会话，新连会打在一个还没恢复的端口上，白耗一轮 launchd 重启配额。

**断网时它会自动退避**（**真正动手补救**且失败 3 次后改 15 分钟一次），不会每分钟硬撞；设备在 UU 里显示离线、或名字在设备列表里查不到时干脆不试，也**不占用**这 3 次额度——设备一回来就立刻首修，不用等退避窗走完。状态和流水账：

```bash
cat ~/.config/uulink/watch.state   # 每台设备：已动手补救几次 / 上次尝试时刻
tail ~/.config/uulink/watch.log    # 什么时候断的、自愈成功没有
uulink check                       # 末尾显示看护上次运行；超过 5 分钟没动会告警"疑似停摆"
```

装了看护记得登记依赖隧道，否则它只会修通路、不会重启隧道：

```
# ~/.config/uulink/tunnels.tsv    设备名<TAB>launchd 标签
office-pc	com.example.mac-reverse-tunnel
```

关于窗口：`term open` 会拉起一个 UU 终端窗口。**手动在终端里跑** `uulink watch` 时会顺手关掉；但 launchd 环境下不会去碰 System Events（那里弹「自动化」授权框没人能点，会一直卡着），所以无人值守时窗口可能累积——不影响通路，介意就手动关。

## 四条铁律

**① 不要用 `device disconnect` 收尾。** 它会把端口变成"幽灵监听"——`lsof` 还看得见、`nc` 还连得上，但后端已死，SSH 卡在 banner 交换，命令行清不掉。`term exit`（帮助原文"会话保留"）和关窗口也都关不掉会话。

**② 避免端口冲突靠"每台设备不同 localPort"，不靠"用完关掉"。** office-pc 用 2222、家里用 2223、N100 用 2224，多台可同时在线互不干扰。

**③ 判断"通"必须读到协议层 banner。** TCP 能连 ≠ 通。这个仓库里两次栽在这上面（公网中间盒、幽灵监听），所以脚本的健康判定是 `chan_ok`（读 `SSH-` banner），不是 `nc -z`。

**④ 常驻隧道必须配 `uulink watch`，不能只靠 launchd 的 `KeepAlive`。** `KeepAlive` 只在进程**退出**时生效；链路死了而进程不退，它就永远不会触发。这不是理论——本仓库实测到隧道"假装在线"空转了十几分钟，而 `launchctl` 全程报退出码 `0`、CPU `0.0%`、`lsof` 显示 `ESTABLISHED`。

## 排障

| 现象 | 原因 | 处理 |
|---|---|---|
| 面板显示「✓ 成功」但端口不监听 | **UU 冷启动后规则不会自动绑** | 把那条开关**关一次再开一次** |
| 端口在、`nc` 通、SSH 卡 banner | 幽灵监听 | `uulink down <名称> --force` 重启 UU，然后按上一条重绑 |
| 设备离线 | 目标机 UU 没开/没登录 | 到那台机器把 UU 开起来 |
| 隧道进程在、`launchctl` 报退出码 0，但怎么都不通 | 链路死了而进程没退（`KeepAlive` 不触发） | `uulink watch --install` 后交给看护；临时可 `launchctl kickstart -k gui/$UID/<标签>` |
| 每条命令 1.4–1.8 s | Windows 每条新起 PowerShell | 正常；进交互会话后就不重启 shell 了 |

## 装完连不上？按这个顺序查

这一节是**别人装的时候真的卡住过的地方**，不是理论清单。

**① 先确认「被控端」到底有没有开 SSH —— 但别用 `lsof` 判断**

```bash
lsof -nP -iTCP:22 -sTCP:LISTEN     # 普通用户跑，常常什么都不输出
```

**空输出 ≠ 没开。** `sshd` 是 root 进程，普通用户的 `lsof` 看不到它的 socket。正确判据是读 banner：

```bash
python3 -c "import socket;s=socket.create_connection(('127.0.0.1',22),timeout=5);print(s.recv(64))"
# b'SSH-2.0-OpenSSH_10.3\r\n'  ← 这才是"开着"
```

这条坑在本项目里骗过两次：一次是公网 IP 的中间盒，一次是把"看不见"当成"没有"。

**② Windows 端装不了 `uulink` —— 别试了**

`uulink` 是 bash 脚本，还依赖 `uuyc-cli`。而 **Windows 版 UU 根本不带 `uuyc-cli`**。Windows 端只有两条路：图形界面加映射 + 手敲 `ssh -p 2222 user@127.0.0.1`，或者干脆用下面的 ③。

**③ 反向通道（公司 → 家里）不用配 UU 映射，借道就行**

如果 A → B 已经通了，要在 B 上反向访问 A，**不需要动 B 的 UU**，在 A 上起一条反向转发即可：

```bash
# 在 A（家里那台）执行：把 B 的 2223 转回本机 22
ssh -fN -o ExitOnForwardFailure=yes -R 2223:127.0.0.1:22 <B 的 ssh 别名>

# 在 B（公司那台）验证，能看到对端 banner 才算通
ssh -p 2223 <A 的用户名>@127.0.0.1
```

好处：B 上什么都不用装、不用配、不用点图形界面。代价：A 上那条 `ssh -fN` 得活着（A 关机或进程被杀，通路就没了）。

**④ Windows 上做这些事，三个引号/语法坑**

- **`%TEMP%` 在 PowerShell 里不展开**：`ssh host 'type %TEMP%\x'` 会被当成字面路径 → `PathNotFound`，看着像"文件没传上去"。要写 `$env:TEMP`，或 `cmd /c "type %TEMP%\x"`。
- **PowerShell 5.1 不支持 `&&`**：`cmd /c a && b` 会 `ParserError`。拆成两条，或 `; if ($?) { b }`。
- **给 `ssh-keygen` 传空 passphrase**：`-N ""` 经 PowerShell 会被吞掉。用 `cmd.exe /c 'ssh-keygen ... -N "" ...'`（单引号原样传给 cmd），否则命令静默失败、你还会以为密钥生成了。

**⑤ 别在一条通道上并发做重活**

同一时刻跑着 `ssh -fN` 隧道、另一个 `uulink ssh`、再来个 `scp`，可能拿到 `Connection closed by 127.0.0.1 port 2222`。不是通道坏了——串行做就好。

**⑥ 用 `nc` 读 banner 时，别把 stdin 接到 `/dev/null`**

这是个纯假阴性，害我误判过一次"链路挂了"：

```bash
nc -G 6 127.0.0.1 2222 </dev/null | head -c 40     # 什么都不输出，像后端拒绝
nc -d -G 6 127.0.0.1 2222 | head -c 40             # b'SSH-2.0-OpenSSH_...' 正确
```

原因：macOS 的 `nc` 默认会读 stdin，stdin 一 EOF 它就直接退出、来不及读 banner。加 `-d`（man 原文 "do not attempt to read from stdin"）才对。**链路正常时这个写法同样是空的**，所以它不是"偶尔失灵"，是恒定假阴性。

要探 banner 就用脚本里的 `chan_ok` 或：

```bash
python3 -c "import socket;s=socket.create_connection(('127.0.0.1',2222),timeout=6);print(s.recv(64))"
```

## 边界

- **只有 macOS 客户端。** Windows 版 UU 不带 CLI，Windows 端请用图形界面按「首次配置」加映射，然后直接 `ssh -p 2222 administrator@127.0.0.1`
- **映射方向是「主控端本地 → 被控端地址」。** 所以要 A 访问 B，规则得配在 A 上，且 B 要跑 sshd（macOS 默认**关着**远程登录）
- **会话在才有通路，光登录不算。** 映射规则挂在会话上，没有会话时本地端口不监听、`ssh` 直接 `Connection refused`。会话由 `uulink up` 或常驻看护自动建立——**只登录 UU 不会让端口自己出现**
- **手机不能当发起方**（没有 CLI、没有 shell）。手机下层指令，实际执行要靠某台常驻在线的 agent

## 更多

- `skill/references/traps.md` —— 每条结论的原始命令与输出
- 授权：MIT

## 免责

会操作 UU 客户端的会话（`--force` 会重启 UU，断掉所有正在进行的远控）。在你自己的设备上用，别拿它去连不属于你的机器。
