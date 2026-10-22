# 新机器上线清单

> 每加一台设备（或在新的发起方 Mac 上装 uu-link）照这张表走一遍，别跳步。
> 内容全部提炼自 `SKILL.md`、`references/traps.md` 和连接方案 handoff 文档，原因与原始输出去那边查。

## 一、发起方（Mac）准备

- [ ] 装好并登录网易 UU 远程（自带 `/Applications/UURemote.app/Contents/Helpers/uuyc-cli`）
- [ ] 仓库根目录跑 `./install.sh`，命令进 `~/.local/bin/uulink`
- [ ] `uulink list` 拿到目标设备的**准确名称**
- [ ] （可选）系统设置 → 隐私与安全性 → 「辅助功能」「自动化」给终端授权；不授权也能用，但 `up` 拉起的窗口要手动关，`uulink down --force` 会走不完（osascript 被拒 `-128`）

## 二、在 UU 图形界面加端口映射（只能 GUI）

- [ ] **Windows 版 UU 没有 CLI，Mac 版 `uuyc-cli` 也不暴露端口映射**——映射规则只能在 UU 图形界面里加
- [ ] UU 主窗口 → **先选中目标设备** → 端口映射 → 添加
- [ ] 填：本地端口 `<每台设备不同，如 2222 / 2223 / 2224>` / 目标地址 `127.0.0.1` / 目标端口 `22`
- [ ] 打开开关，界面显示「✓ 成功」——**这只是规则态，不代表端口已绑定**，后面必须用 `uulink check` 验
- [ ] 别动已在用的 2222 端口和 `tars` 别名（tdx 数据桥也走这条）

## 三、被控端开 sshd 并装公钥

- [ ] Windows：`Get-WindowsCapability -Online -Name OpenSSH.Server*` 查是否安装；管理员公钥写 `C:\ProgramData\ssh\administrators_authorized_keys`，ACL 只留 Administrators 与 SYSTEM
- [ ] macOS：系统设置 → 通用 → 共享 → 远程登录（默认关）；公钥写 `~/.ssh/authorized_keys`
- [ ] Windows 语法坑：`%TEMP%` 在 PowerShell 不展开；PowerShell 5.1 不支持 `&&`；`ssh-keygen -N ""` 要经 `cmd.exe /c` 否则静默失败
- [ ] 判断 sshd 有没有起来**读 banner**，别用 `lsof`（普通用户看不见 root 的 socket）

## 四、写配置

- [ ] `~/.config/uulink/devices.tsv` 加一行（tab 分隔，`deviceId` 写 `-` 自动解析）：
  ```
  # name	deviceId	localport	sshuser	key
  <名称>	-	<本地端口>	<用户>	<私钥路径>
  ```
- [ ] 改 tsv 用编辑器或 python `split("\t")`，别用 BSD `sed` 的 `\t`（静默不替换）
- [ ] `~/.ssh/config` 加别名（HostName 127.0.0.1 / Port <本地端口> / IdentityFile / IdentitiesOnly yes）；之后 `scp` 一律用别名，裸 `-P 端口 user@127.0.0.1` 会 `Permission denied (publickey)`

## 五、建会话并验证

- [ ] `uulink up <名称>`
- [ ] `uulink check` 必须看到「真通」（读到 `SSH-` banner）；端口 LISTEN、`nc -z` 成功都不算
- [ ] `uulink ssh <名称> 'hostname'`——`up` 只验网络层不验认证，被拒多半是公钥
- [ ] 需要无人值守：`uulink watch --install`；有依赖这条通路的 launchd 隧道就写进 `~/.config/uulink/tunnels.tsv`
- [ ] 改过 `uulink` 代码：先跑 `skill/scripts/regress-watch.sh`（mock 必须走 `UU_LINK_CLI`，塞 PATH 无效）

## 六、上线后必须知道的

- [ ] **UU 重启（开机、应用更新）后端口不会自己回来**：规则还在、显示「✓ 成功」，但端口不监听，看护也修不了。处理：打开「端口映射」面板，把那条映射的开关**关一次再打开**，端口约 2 秒内回来
- [ ] 不要用 `device disconnect` / `term exit` 收尾或制造断线演练——前者会留幽灵监听，两者都不动映射
- [ ] 通道状态别抄进文档，现场跑 `uulink check`
