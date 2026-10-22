# uu-link

用 **网易 UU 远程**自带的端口映射，一条命令建立到任意一台 UU 账号设备的 SSH 通路。

不新造隧道、不开公网端口、不买云主机——借 UU 已经调好的那条境内稳定通道。

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
```

`up` 建的是**轻会话**（UU 的远程终端，不拉整块桌面），起来后会自动把弹出的窗口关掉。窗口关掉不影响映射。

## 三条铁律

**① 不要用 `device disconnect` 收尾。** 它会把端口变成"幽灵监听"——`lsof` 还看得见、`nc` 还连得上，但后端已死，SSH 卡在 banner 交换，命令行清不掉。`term exit`（帮助原文"会话保留"）和关窗口也都关不掉会话。

**② 避免端口冲突靠"每台设备不同 localPort"，不靠"用完关掉"。** office-pc 用 2222、家里用 2223、N100 用 2224，多台可同时在线互不干扰。

**③ 判断"通"必须读到协议层 banner。** TCP 能连 ≠ 通。这个仓库里两次栽在这上面（公网中间盒、幽灵监听），所以脚本的健康判定是 `chan_ok`（读 `SSH-` banner），不是 `nc -z`。

## 排障

| 现象 | 原因 | 处理 |
|---|---|---|
| 面板显示「✓ 成功」但端口不监听 | **UU 冷启动后规则不会自动绑** | 把那条开关**关一次再开一次** |
| 端口在、`nc` 通、SSH 卡 banner | 幽灵监听 | `uulink down <名称> --force` 重启 UU，然后按上一条重绑 |
| 设备离线 | 目标机 UU 没开/没登录 | 到那台机器把 UU 开起来 |
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

## 边界

- **只有 macOS 客户端。** Windows 版 UU 不带 CLI，Windows 端请用图形界面按「首次配置」加映射，然后直接 `ssh -p 2222 administrator@127.0.0.1`
- **映射方向是「主控端本地 → 被控端地址」。** 所以要 A 访问 B，规则得配在 A 上，且 B 要跑 sshd（macOS 默认**关着**远程登录）
- **会话在才有通路。** 不是常驻在线链路；`uulink up` 负责把它叫起来
- **手机不能当发起方**（没有 CLI、没有 shell）。手机下层指令，实际执行要靠某台常驻在线的 agent

## 更多

- `skill/references/traps.md` —— 每条结论的原始命令与输出
- 授权：MIT

## 免责

会操作 UU 客户端的会话（`--force` 会重启 UU，断掉所有正在进行的远控）。在你自己的设备上用，别拿它去连不属于你的机器。
