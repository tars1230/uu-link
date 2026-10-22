---
name: uu-link
description: 通过网易 UU 远程自带的端口映射，建立到任意一台 UU 账号设备的 SSH 通路，含自动建会话、通路健康判定与排障。This skill should be used when the user asks to 连接/操控另一台电脑、建跨机通道、去另一台机器取文件或跑命令，或提到 uulink、UU 端口映射、办公室电脑、家里的电脑。
description_zh: "用 UU 远程端口映射一键建立跨机 SSH 通路；用户提到 uulink、UU 端口映射、连办公室/家里的电脑时使用"
description_en: "One-command SSH channel to any device on your UU Remote account; use when asked to reach another machine via UU port mapping"
version: 1.0.3
agent_created: true
allowed-tools: Bash,Read
metadata:
  tags:
    - "remote access"
    - "ssh tunnel"
    - "uu remote"
    - "cross-device"
    - "port mapping"
---

# UU-Link：跨机 SSH 通路

把「探测 → 建会话 → 连」压成一条命令。底层不新造隧道，而是**借网易 UU 远程自带的端口映射**——它已经有一条调好的境内稳定通道。

实测（同城跨运营商，两台机器）：经映射读 SSH banner 往返 **44–56 ms**；同一天同一对机器走 Tailscale 境外中继 `ssh` 直接 **Operation timed out**（偶尔通时约 330 ms）。

## 什么时候用

- 用户说「连某台机器」「连办公室电脑」「连家里那台」
- 要在另一台机器上跑命令 / 找文件 / 查服务状态
- 用户提到 `uulink`、UU 端口映射、跨机通道

## 安装

仓库根目录有 `install.sh`（**注意：装到 `~/.workbuddy/skills/uu-link/` 之后，该目录里不含 install.sh**）：

```bash
git clone <repo> && cd uu-link && ./install.sh
```

装两处：`~/.local/bin/uulink` 和 `~/.workbuddy/skills/uu-link/`。

**依赖**：macOS + bash + `python3` + `lsof` + `osascript` + `open` + `ssh` + 已安装并登录的 UU 客户端（自带 `uuyc-cli`）。脚本按 `UU_LINK_CLI` 环境变量 → 脚本同级目录 → `/Applications/UURemote.app/Contents/Helpers/` 的顺序自动定位。

**首次运行会请求授权**：`up` 成功后脚本用 AppleScript 关掉多出来的终端窗口，macOS 会要求给终端/WorkBuddy 授予「辅助功能」与「自动化」权限。不授权也能用，只是窗口要手动关。

## 从零跑通的完整顺序（别跳步）

1. `./install.sh` —— 命令进 PATH
2. `uulink list` —— 拿到目标设备的**准确名称**
3. 在 **UU 图形界面**给这台设备加映射（见下节）
4. 被控端跑起 sshd，并把**公钥装进去**
   - Windows：`Get-WindowsCapability -Online -Name OpenSSH.Server*` 查是否安装；管理员公钥写 `C:\ProgramData\ssh\administrators_authorized_keys`，并收紧 ACL（只留 Administrators 与 SYSTEM）
   - macOS：系统设置 → 通用 → 共享 → 远程登录（**默认关着**，要管理员开）；公钥写 `~/.ssh/authorized_keys`
5. `uulink check` —— **必须看到「真通」**，只看「✓ 成功」不算
6. `uulink ssh <名称> 'hostname'`

`up` 只验证网络层能读到 SSH banner，**不验证认证**——所以可能出现 `up` 报就绪而 `ssh` 被拒（多半是公钥没装对）。

## 首次配置分配（每对设备一次）

映射规则只能**在 UU 的图形界面里加**（CLI 没有这个命令，`--help` 与二进制字符串都确认过）。在**发起方**那台机器上：

1. UU 主窗口 → **先选中目标设备**（点进去，让顶部显示那台设备名）→ **端口映射** → 添加
2. 填三项：`本地端口 <自己定，每台不同>` / `目标地址 127.0.0.1` / `目标端口 22`
3. 打开开关，界面会显示「✓ 成功」

⚠️ **「✓ 成功」是规则态，不是端口绑定态。** 实测：界面显示「✓ 成功」、开关也开着，本地端口却没有监听。必须用 `uulink check` 看到「真通」才算配好。

设备写进 `~/.config/uulink/devices.tsv`（首次运行自动生成模板，权限 600）：

```
# name	deviceId	localport	sshuser	key
office-pc	-	2222	administrator	~/.ssh/id_ed25519
```

`deviceId` 写 `-` 表示每次从 `uulink list` 按名称自动取。

## 用法

```bash
uulink                  # 体检：UU 登录态、设备在线、通路是「真通/幽灵/无监听」
uulink check <名称>     # 只查这一条通路（名称写错会报错，不会静默查别人）
uulink list             # 设备列表 + 哪些已配通路
uulink up <名称>        # 没通路就自己建，通了才返回
uulink ssh <名称> 'hostname'
uulink down             # 解释为什么"关掉单向连接"不该做（不执行任何动作）
```

## 三条铁律

**① 禁止用 `device disconnect` 收尾。** 它会把端口变成**幽灵监听**：`lsof` 还看得见、`nc -z` 还成功，但后端已死，SSH 卡在 banner 交换。`term exit`（帮助原文「会话保留」）和关窗口也都关不掉会话。
遇到幽灵的正确顺序是：**先 `uulink up` 让新会话顶上；顶不掉再 `uulink down <名称> --force`** 重启 UU（注意 `--force` 会断所有远控，非交互环境必须显式加 `-y`）。

**② 避免端口冲突靠「每台设备不同 localPort」，不靠「用完关掉」。** 设备 A 用 2222、B 用 2223、C 用 2224，多台可同时在线互不干扰。

**③ 判断"通"必须读到协议层 banner。** TCP 能连 ≠ 通。健康判定是 `chan_ok`（读 `SSH-` banner），不是 `nc -z`。注意它强绑定 SSH 协议——映射到非 SSH 服务会被判不通。

## 稳定性边界（重要）

- **规则本身配一次就长期存在**（不会因为重连消失）
- **但端口绑定在「UU 冷启动/重启后」不会自动恢复**：必须去面板把那条开关**关一次再开一次**
- 所以这不是「装完永久在线」的链路，是「开机后、或重启 UU 后，需要一次点击」的链路

## 排障（按出现概率）

| 现象 | 原因 | 处理 |
|---|---|---|
| 面板「✓ 成功」但端口不监听 | UU 冷启动后规则不自动绑 | 面板里把开关**关一次再开一次** |
| 端口在、`nc` 通、SSH 卡 banner | 幽灵监听 | 先 `uulink up <名称>` 顶替；顶不掉再 `uulink down <名称> --force -y`，之后仍需按上一条重绑 |
| `term open` 返回成功但没反应 | 该返回只代表请求已派发 | 等 `up` 的健康判定结果 |
| 设备离线 | 目标机 UU 没开/没登录 | `uulink list` 确认；到那台机器把 UU 开起来 |
| `up` 说就绪但 `ssh` 被拒 | 认证没过，不是通路问题 | 查被控端 sshd 与公钥 |
| 每条命令 1.4–1.8s | Windows 每条新起 PowerShell | 正常。进交互会话后就不重启 shell 了 |

`up` 结束会自动关掉它自己拉起的 `sessionN` 终端窗口——**只是清理窗口，映射挂在会话上，不受影响**。

## 反方向（A ⇄ B）怎么建

同前：映射配在发起方、只能 GUI 加。每对设备首次都要配一次，「两边都装了」不等于「能连」。

```bash
# Windows 端加完映射后（端口与用户名按你自己的来，别照抄）
ssh -p <本地端口> -i <私钥路径> <用户名>@127.0.0.1
```

## 平台边界

- 脚本是 **macOS 客户端**（依赖 `uuyc-cli`、`lsof`、`osascript`、`open`）
- Windows 版 UU 不带 CLI：Windows 端用 GUI 加映射，然后直接 `ssh`
- 手机不能当发起方（没有 CLI、没有 shell）——手机下指令，实际执行要靠某台常驻在线的 agent

## 危险动作

`uulink down --force` 会**强制退出 UU 客户端**，切断本机所有远控（包括别人正连着你这台）。
- 交互执行：要求 `[y/N]`
- 非交互执行：**必须显式 `-y`，否则直接拒绝**
- 必须写清设备名，不允许自动挑一台

## 深层资料

- `references/traps.md`：每条结论的原始命令与输出
- `scripts/click.swift`：Qt 自绘按钮点不动的绕法（发 CGEvent 真实鼠标事件）。**只在需要自动化 GUI 时参考，`uulink` 本身不调用它**
