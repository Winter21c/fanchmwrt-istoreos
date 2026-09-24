<!--
  如果你把这个仓库放到别的名字下，请把全文里的
  Winter21c/fanchmwrt-istoreos 替换成实际地址。
  FanchmWrt 的授权条款明确要求：转载固件时必须附上仓库地址。
-->

# FanchmWrt × iStoreOS 融合固件

**把 [FanchmWrt](https://github.com/fanchmwrt/fanchmwrt) 的路由与流控能力，和 [iStoreOS](https://github.com/istoreos/istoreos) 的首页面板、Docker、应用商店，合进同一份 x86 软路由固件。**

面向 **x86_64**。基于 OpenWrt 25.12。

---

## 📖 这是什么

FanchmWrt 强在**网络侧**：自研的 fwx 应用识别引擎、流量统计、行为管理、一键旁路，以及一套围绕这些功能重做的主题和仪表盘。

iStoreOS 强在**应用侧**：一个开箱即用的首页面板、图形化 Docker 管理、以及 iStore 应用商店。

两者都是 OpenWrt 25.12 的衍生版，但各自解决的是不同的问题。这个项目把它们拼在一起 ——

> **以 FanchmWrt 为底座**（内核态的东西最难搬，留在原地），
> **把 iStoreOS 的面板 / Docker / iStore 作为独立组件移植进来**（它们本来就是自包含的包）。

拼完之后，你得到的是一台：**既懂流量、又能跑容器、还带应用商店**的 x86 软路由。

---

## ✨ 特性一览

### 🛡️ 来自 FanchmWrt —— 网络与流量

| 功能 | 说明 |
|---|---|
| **fwx 应用识别** | 内核态 DPI 引擎，按应用/协议特征识别流量；**特征库支持在线更新**（走 `api.openappfilter.com`） |
| **应用过滤 / 行为管理** | 按应用类型、按用户、按时间段限制上网 |
| **MAC 过滤 / 黑白名单** | 设备级准入控制 |
| **上网记录** | 记录访问过的域名与 URL，支持白名单 |
| **流量统计** | 按接口、按用户、按应用类型的实时与历史流量 |
| **在线用户 / 会话统计** | 谁在线、在用什么应用，一目了然 |
| **无线管理** | 无线设置与优化 |
| **fwx 应用中心** | FanchmWrt 自己的应用入口 |
| **fullcone NAT** | 完整锥形 NAT，改善 P2P / 游戏 / 联机体验 |
| **仪表盘** | FanchmWrt 的首页仪表盘（**本固件默认首页**） |

一共 17 个 `luci-app-fwx-*` 应用，全部启用。
（固件内置的特征库是 `v26.01.01`，含聊天 / 视频 / 购物 / 下载 / 网站等分类，
开机后可在线增量更新。）

### 🎛️ 来自 iStoreOS —— 面板、容器与应用生态

| 功能 | 说明 |
|---|---|
| **QuickStart 首页面板** | iStoreOS 的快速设置面板：上网方式、网络状态、Wi-Fi 一页搞定 |
| **iStore 应用商店** | 图形化装插件，带教程与依赖解析；支持备份/恢复 |
| **Docker（Dockerman）** | `dockerd` + `docker` + `docker-compose`，图形化管理容器 / 镜像 / 网络 / 卷 |
| **磁盘管理 DiskMan** | 分区、格式化、挂载、SMART 检测 |
| **Web 终端 ttyd** | 浏览器里直接开 shell，不用装 SSH 客户端 |

### 🗄️ 轻 NAS 套件

| 功能 | 说明 |
|---|---|
| **Samba4** | 局域网文件共享（Windows 直接访问）。保留服务端，未装 LuCI 配置界面 |
| **NFS** | Linux / 虚拟机场景的网络文件系统 |
| **WebDAV** | 跨平台远程文件访问 |
| **wsdd2** | 让 Windows 网络邻居能自动发现这台机器 |
| **mergerfs** | 把多块硬盘合并成一个池 |
| **UniShare** | 统一管理上面这些共享 |

### 🌐 DNS 分流

| 功能 | 说明 |
|---|---|
| **mosdns** | 高性能 DNS 转发 / 分流器，支持按域名与 IP 分流、缓存、防污染 |
| **geoip / geosite 规则库** | 随 mosdns 一起提供的分流规则数据 |

> 本项目**没有**包含 DDNS、网络唤醒（WOL）、UPnP、硬盘休眠，以及 uhttpd /
> Samba 的 LuCI 配置界面 —— 这是在 `include/target.mk` 里显式声明的。
> 需要的话在 iStore 商店里装，或自己改回来重新编译。

---

## 🚀 快速开始

### 1. 下载

到本仓库的 **[Releases](../../releases)** 页面下载镜像。

| 镜像 | 大小 | 什么时候用 |
|---|---|---|
| `…squashfs-combined-efi.img.gz` | 131 MB | **推荐**。UEFI 启动，squashfs 支持一键恢复出厂 |
| `…squashfs-combined.img.gz` | 131 MB | 传统 BIOS 启动，同样支持恢复出厂 |
| `…ext4-combined-efi.img.gz` | 166 MB | UEFI 启动，ext4 根文件系统，想随意改系统文件时用 |
| `…ext4-combined.img.gz` | 166 MB | 传统 BIOS + ext4 |
| `…rootfs.tar.gz` | 160 MB | 只想看/提取文件内容，不刷机 |

> **UEFI 还是 BIOS？** 近十年的机器基本都是 UEFI，选带 `efi` 的那个。
> 拿不准就先试 `squashfs-combined-efi`，起不来再换不带 `efi` 的。

### 2. 刷机

**物理机**：把 `.img.gz` 解压成 `.img`，用 [balenaEtcher](https://etcher.balena.io/) / `dd` / Rufus 写入 U 盘或硬盘。

```sh
gunzip openwrt-x86-64-generic-squashfs-combined-efi.img.gz
sudo dd if=openwrt-x86-64-generic-squashfs-combined-efi.img of=/dev/sdX bs=4M status=progress
```

**虚拟机**：直接解压后的 `.img` 当磁盘用即可（Proxmox / ESXi / VirtualBox / QEMU 都行）。

### 3. 登录

| | |
|---|---|
| 🌐 **管理地址** | **<http://192.168.1.1>** |
| 👤 **用户名** | `root` |
| 🔑 **密码** | `password` |

> ⚠️ **首次登录后请立刻改密码。**

### ⚠️ 一个必须知道的坑：管理地址取决于你有几个网口

FanchmWrt 在没有 **WAN 口** 的时候，会自动把设备切成**旁路模式**：

| 网口数量 | 工作模式 | LAN 地址 | 怎么访问 |
|---|---|---|---|
| **2 个及以上** | 网关模式 | **192.168.1.1**（静态） | <http://192.168.1.1> |
| **只有 1 个** | 旁路模式 | DHCP 客户端 | 地址由**上游路由器**分配，去上游查 DHCP 租约；或按下面的方法改回静态 |

**单网口想固定成 192.168.1.1**：接显示器/串口，在 FanchmWrt 控制台菜单里选
`[2] Set LAN(br-lan) Static IP`。

（这个行为来自 FanchmWrt 自身的 `fwx_cli.sh`，不是本项目的改动。）

---

## ☁️ 在线编译（不用自己的机器）

仓库自带 **GitHub Actions** 工作流，直接在 GitHub 的服务器上编译，编译完可以把镜像
下载下来或者直接发布成 Release。适合不想在本地装 30 GB 工具链、或者机器太慢的情况。

### 怎么用

**方式一：手动点一下**

1. 打开仓库的 **Actions** 标签页
2. 左侧选「**构建 x86_64 固件**」
3. 右边 **Run workflow**，按需填参数：

| 参数 | 默认 | 说明 |
|---|---|---|
| `lan_ip` | `192.168.1.1` | **管理地址**。可带前缀长度，如 `10.0.0.1/16` |
| `rootfs_size` | `1024` | **rootfs 分区大小（MB）**，可选 512 / 1024 / 2048 / 4096 / 8192 |
| `enable_docker` | ✅ 勾选 | **是否包含 Docker**。不勾会去掉 dockerd + docker-compose + Dockerman 界面，固件小约 60MB |
| `create_release` | ⬜ | 编译完自动创建 Release |
| `release_tag` | 留空 | 指定标签，留空则自动用日期时间 |
| `upload_artifact` | ✅ 勾选 | 把镜像上传成构建产物（Actions 页面可直接下载） |

4. 大约 **2 小时**后出结果（实测：关 Docker 110 分钟，含 Docker 123 分钟；首次构建无缓存会更久）

**方式二：打个标签就自动发布**

```sh
git tag v25.12.4-istoreos.3
git push origin v25.12.4-istoreos.3
```

推上去之后会自动编译，成功后创建一个同名 Release 并把镜像挂上去 —— 也就是
本仓库现有那三个 Release 的来法。（这条路径用的是默认参数：含 Docker、
192.168.1.1、1GB 分区。）

### 本地也能用同一套参数

工作流只是把参数转成环境变量交给 `scripts/apply-build-options.sh`，
本地一样可以：

```sh
LAN_IP=192.168.100.1 ENABLE_DOCKER=0 ROOTFS_PARTSIZE=2048 \
  ./build-merged-x86_64.sh
```

### 流水线做了什么

```
检出代码 → 释放磁盘空间（runner 初始只有约 14GB，OpenWrt 要 30GB）
        → 安装依赖 → 恢复 dl/ 缓存
        → 准备：feeds / 补丁 / 配置 / 校验   ← 复用本仓库的 build-merged-x86_64.sh
        → make download → make -j$(nproc)
        → verify-merged-firmware.sh 逐项核验
        → 上传产物 / 创建 Release
```

几个设计取舍：

- **准备阶段直接调用 `build-merged-x86_64.sh`**（带 `SKIP_BUILD=1`），
  这样 CI 和本地用的是同一套逻辑，不会出现「本地能编、CI 编不出来」。
- **`fetch-depth: 1`**：不需要完整 git 历史。`scripts/getver.sh` 是
  `try_version || try_git`，树里的 `version` 文件已经给了版本号，
  省掉 280MB 的 fetch。
- **缓存 `dl/`**：主要不是为了省时间（编译才是大头），而是防止某个上游
  tarball 哪天消失导致构建失败。
- **核验不通过就不会发布**：`.config` 校验 + rootfs 逐项核验都在发布之前。

### 关于 Actions 额度

本仓库是公开仓库，GitHub 对公开仓库的 Actions **不计费**。
单次构建约消耗 2～3 小时 runner 时间。

---

## 🛠️ 自己编译

需要 Linux（推荐 Ubuntu 22.04+）、约 30 GB 磁盘、能访问 GitHub 与 Go 模块代理。

```sh
git clone https://github.com/Winter21c/fanchmwrt-istoreos.git
cd fanchmwrt-istoreos

# 一键：拉 feed → 打补丁 → 生成配置 → 校验 → 下载 → 编译
./build-merged-x86_64.sh

# 产物在 bin/targets/x86/64/
```

> **📝 仓库地址**：上面用的是 `Winter21c/fanchmwrt-istoreos`。
> 如果你 fork 或改名了，请把地址换掉 —— 本仓库同时是 FanchmWrt 的衍生固件，
> 依据其授权条款，转载时必须附上仓库地址。

想手动来也可以：

```sh
./scripts/feeds update -a
./scripts/feeds install -a
./scripts/istoreos-merge.sh        # 打 iStoreOS 集成补丁（幂等）

cat > .config <<'EOF'
CONFIG_TARGET_x86=y
CONFIG_TARGET_x86_64=y
CONFIG_TARGET_x86_64_DEVICE_generic=y
CONFIG_TARGET_ROOTFS_PARTSIZE=1024
EOF
make defconfig

make -j$(nproc) download
make -j$(nproc) BUILD_LOG=1
```

编译完可以核验产物内容：

```sh
./scripts/verify-merged-firmware.sh
```

> **国内网络提示**：`build-merged-x86_64.sh` 里设了
> `CURL_OPTIONS="--speed-limit 51200 --speed-time 60"`。
> 因为 curl 默认没有速率下限，一个「能用但极慢」的镜像会让 `make download`
> **永久卡住**而不是自动换源；加上这个之后，慢于 50 KB/s 持续 60 秒就会放弃该镜像。

---

## 📦 这一版都有什么

- **平台**：x86_64 generic（UEFI / BIOS 均可）
- **底座**：FanchmWrt / OpenWrt **25.12.4**，内核 **6.12.87**
- **应用侧组件**：取自 iStoreOS 生态（对应其 `istoreos-25.12` 分支的 feed）
- **包管理器**：apk
- **默认主题**：`luci-theme-fanchmwrt`
- **默认首页**：FanchmWrt 仪表盘（QuickStart 面板排在菜单第二位）
- **rootfs 分区**：1 GB，首次启动自动扩容
- **已安装软件包**：504 个

<details>
<summary>点开看关键组件版本</summary>

```
luci-theme-fanchmwrt      26.264.03002~afc4d28
luci-app-fwx-dashboard    1.0.1-r1
luci-app-fwx-app-center   1.0.0-r1
fwxd                      1.0.4-r1
fwx 特征库                 v26.01.01
luci-app-quickstart       0.12.10-r1     quickstart     0.13.0-r1
luci-app-dockerman        26.133.20346~e9ebca7
dockerd                   27.3.1-r5      docker         27.3.1-r2
docker-compose            2.40.3-r1
luci-app-store            0.2.1-r1       taskd          1.0.3-r2
luci-app-diskman          0.2.13-r1
luci-app-mosdns           1.7.14-r1      mosdns         5.3.4-r14
luci-app-ttyd             26.133.20346~e9ebca7            ttyd  1.7.7-r1
luci-app-nfs              1.2.0-r1
luci-app-mergerfs         1.0.3-r1       mergerfs       2.40.2-r5
luci-app-unishare         1.0.2-r1       unishare       1.1.2-r1
webdav2                   4.3.2-r1       wsdd2          2023.12.21
samba4-server             4.22.7-r3      nfs-kernel-server
istoreos-merge            1.0-r1
```

</details>

---

## 🔧 改了哪些东西

对 FanchmWrt 原树的改动**只有 5 个文件被修改、4 个路径被新增**，其余全部来自上游 feed：

```
feeds.conf.default            新增 7 个 feed（iStore 商店、QuickStart、mergerfs、
                              NFS、DiskMan、mosdns）
include/target.mk             x86_64 专用包清单 + 「不要哪些包」的移除声明
merge-patches/                3 个定点补丁（Docker / QuickStart / v2ray-geodata）
scripts/                      补丁应用脚本 + 产物核验脚本 + 构建参数处理
package/build-defaults/       构建时选定的默认值（管理地址等）
package/istoreos-merge/       Docker 在 fw4 下的 NAT 规则、squashfs 上的数据目录落点
package/fcm/luci-theme-fanchmwrt/   新菜单的图标与归类
.github/                      在线编译工作流（替换掉 OpenWrt 上游的 CI）
```

另外**删掉了 OpenWrt 上游的 14 个 CI 工作流**和项目配置（`.github/workflows/`、
`FUNDING.yml`、`ISSUE_TEMPLATE/` 等）。它们是为 OpenWrt 官方基础设施写的：
其中 `tools.yml` 会在改动 `include/**` 时触发跨平台工具链构建，`github-release.yml`
会在推送 `v*` 标签时触发 OpenWrt 的发布流程 —— 在本仓库里既跑不通也会误导使用者。

四处值得一提的地方：

- **Docker 不是简单装个包**：上游的 `dockerd` 默认自己管 iptables，会和 OpenWrt 的
  fw4 打架。本项目移植了 iStoreOS 对 `dockerd` 的定制补丁（关闭 docker 自带
  iptables、交给 fw4 统一管理、自动建立 docker ↔ wan/lan 的转发规则、限制容器日志
  大小等），并补上 `172.16.0.0/12` 的出网 NAT 规则。
- **不要的包是用 `-包名` 声明的**，不改上游清单。OpenWrt 的 `DEFAULT_PACKAGES`
  原生支持这种移除语法，差异集中在一处，一眼能看出本项目动了哪些包。
- **`v2ray-geodata` 改用了滚动地址**：它要下载的 geoip/geosite 规则数据在上游是
  「滚动发布 + 定期删旧 tag」（`domain-list-community` 只保留约三个月），
  feed 里 pin 死的版本已经 404、会让构建直接失败。补丁改成
  `releases/latest/download`，地址永不失效。

完整的技术说明、设计取舍与验证记录见 **[MERGE-NOTES.md](MERGE-NOTES.md)**。

---

## ✅ 验证到什么程度

不是「编译过了就发」：

- 构建产物 **16 个文件 sha256 全部校验通过**
- `verify-merged-firmware.sh` 从固件 rootfs 里逐项核对，**131 项断言全部通过**，
  其中包含「确认已排除的包确实不在固件里」的反向校验
- 固件已在 **QEMU/KVM 下实际启动验证**：LuCI 正常响应、FanchmWrt 主题生效、
  Docker 起来了并且存储驱动是 `overlay2`、`dockerd`/`quickstart`/`istore`/`fwx`
  四个服务均为 enabled

**还没验证的**：fwx 的应用识别需要真实流量才有意义；iStore 能否拉到应用列表
取决于外网连通性；Dockerman 只验证到后端 RPC 与 daemon 正常，没有实际拉起容器。
这些建议刷到真机后再确认。

---

## 🙏 致谢

这个项目**没有写一行网络协议栈**，全部能力都来自这些优秀的开源项目。感谢每一位作者：

### 底座与上游系统

- **[OpenWrt](https://openwrt.org/)** —— 一切的根基。本固件的构建系统、内核、base-files、LuCI 均来自 OpenWrt。
- **[FanchmWrt](https://github.com/fanchmwrt/fanchmwrt)**（[www.fanchmwrt.com](https://www.fanchmwrt.com)）——
  **本固件的底座**。fwx 应用识别引擎、`fwxd` 守护进程、全部 `luci-app-fwx-*` 应用、
  `luci-theme-fanchmwrt` 主题、fullcone NAT、x86 默认网络脚本，都出自这里。
- **[iStoreOS](https://github.com/istoreos/istoreos)** —— **全部应用侧特性的来源**。
  QuickStart 首页面板、Docker 在 fw4 下的适配方案、iStore 应用商店生态，都来自 iStoreOS 团队的长期打磨。

### 组件与 feed

- **[易有云 LinkEase](https://github.com/linkease)** —— iStore 应用商店（[linkease/istore](https://github.com/linkease/istore)）、
  QuickStart 面板后端与 UniShare / WebDAV（[nas-packages](https://github.com/linkease/nas-packages) /
  [nas-packages-luci](https://github.com/linkease/nas-packages-luci)），
  以及 mergerfs 的 OpenWrt 封装（[openwrt-apps](https://github.com/linkease/openwrt-apps)）。
- **[jjm2473](https://github.com/jjm2473)** —— iStoreOS 的主要作者。
  本项目的 Docker 适配补丁直接取自他对 `dockerd` 的定制
  （[jjm2473/packages](https://github.com/jjm2473/packages) 的 `istoreos-25.12` 分支），
  `luci-app-nfs` 与 `luci-theme-argon` 来自 [openwrt-third](https://github.com/jjm2473/openwrt-third)，
  `webdav2` 亦由他维护。
- **[lisaac](https://github.com/lisaac)** —— [luci-app-diskman](https://github.com/lisaac/luci-app-diskman)，磁盘管理界面。
- **[trapexit](https://github.com/trapexit)** —— [mergerfs](https://github.com/trapexit/mergerfs)，多盘合并文件系统。
- **[hacdias](https://github.com/hacdias)** —— [webdav](https://github.com/hacdias/webdav)，`webdav2` 的上游。

### 运行时

- **[Docker / Moby](https://github.com/moby/moby)**、**[containerd](https://github.com/containerd/containerd)**、**[runc](https://github.com/opencontainers/runc)** —— 容器运行时。
- **[Samba Team](https://www.samba.org/)** —— SMB/CIFS 实现。
- **[nfs-utils](http://linux-nfs.org/)** 与 Linux 内核 NFS 服务端。
- **[wsdd2](https://github.com/christgau/wsdd)** —— Web Service Discovery，让 Windows 能找到这台机器。
- 以及 OpenWrt `packages` / `luci` / `routing` / `telephony` / `video` 各 feed 的全体维护者。

### 特别说明

**本项目只是整合，没有修改上述任何项目的核心代码。**
如果这些项目对你有帮助，请去给它们点 Star —— 尤其是 FanchmWrt 和 iStoreOS。

---

## ⚠️ 授权与声明

### 继承自 FanchmWrt 的条款（原文保留）

FanchmWrt 的授权对**再发布**有明确要求，本项目作为其衍生固件，一并遵守并在此转述：

> This project is free for personal use, you may redistribute the firmware or port
> the code to other projects, however, the copyright information in all source code
> files must be retained.
>
> The App feature file of OAF is used to describe the protocol characteristics of an
> app, individuals may use it for free, but commercial use is prohibited, you can
> extract application characteristics yourself but not directly use the open-source
> feature files, the copyright for these files belongs to FanchmWrt.

翻译过来就是三件事：

1. **个人使用免费**，可以转发固件、可以把代码移植到别的项目；
2. **但必须保留所有源码文件里的版权信息**；
3. **⚠️ 应用特征库（`/etc/fwxd/feature.bin`、`feature.cfg`）个人免费、商业使用禁止。**
   你可以自己提取应用特征，但不能直接拿这份开源特征文件去商用 —— 版权归 FanchmWrt。

FanchmWrt 还要求：**再发布固件时请附上仓库地址。**

### 本仓库

- 本仓库的整合部分（构建脚本、补丁、配置文件）同样以 **GPL-2.0** 发布，与 OpenWrt / FanchmWrt 保持一致。
- 各上游组件（OpenWrt、FanchmWrt、iStoreOS、iStore、mergerfs、Docker 等）**版权归各自作者所有**，
  遵循各自的许可证。详见仓库内 `LICENSES/` 目录与各组件源码。
- `README.upstream-fanchmwrt.md` 保留了 FanchmWrt 原始 README，以备查证。

### 免责声明

固件按「现状」提供，**不附带任何担保**。刷机有风险，可能变砖、可能丢数据。
请在操作前备份重要数据，并确认你知道怎么恢复。因使用本固件造成的任何损失，作者不承担责任。

**请勿将本固件用于任何违法用途。**

---

## 📄 相关链接

| | |
|---|---|
| FanchmWrt | <https://github.com/fanchmwrt/fanchmwrt> · <https://www.fanchmwrt.com> |
| iStoreOS | <https://github.com/istoreos/istoreos> · <https://site.istoreos.com> |
| iStore 商店 | <https://github.com/linkease/istore> |
| OpenWrt | <https://openwrt.org> |
| 技术细节 | [MERGE-NOTES.md](MERGE-NOTES.md) |
