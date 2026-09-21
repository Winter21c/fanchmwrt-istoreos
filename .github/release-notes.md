## FanchmWrt × iStoreOS 融合固件 @TAG@

以 **[FanchmWrt](https://github.com/fanchmwrt/fanchmwrt)** 为底座，移植 **[iStoreOS](https://github.com/istoreos/istoreos)** 的首页面板、Docker 与 iStore 应用商店。面向 **x86_64**。

- **构建版本**：`@VERSION@`
- **构建日期**：@DATE@
- **管理地址**：`@LANIP@`
- **rootfs 分区**：@ROOTSIZE@ MB
- **Docker**：@DOCKER@
- **已安装软件包**：@PKGCOUNT@ 个
- **自动校验**：构建流水线里 `scripts/verify-merged-firmware.sh` 全部通过

---

### 快速开始

| | |
|---|---|
| 🌐 **管理地址** | **http://@LANIP@** |
| 👤 **用户名** | `root` |
| 🔑 **密码** | `password` |

> ⚠️ 首次登录后请立刻改密码。

#### ⚠️ 管理地址取决于你的网口数量

FanchmWrt 在没有 WAN 口时会自动进入**旁路模式**：

| 网口数量 | 工作模式 | LAN 地址 |
|---|---|---|
| **2 个及以上** | 网关模式 | **192.168.1.1**（静态） |
| **只有 1 个** | 旁路模式 | DHCP，地址由上游路由器分配 |

单网口想固定成 192.168.1.1：接显示器/串口，在 FanchmWrt 控制台菜单里选
`[2] Set LAN(br-lan) Static IP`。

---

### 镜像怎么选

| 镜像 | 说明 |
|---|---|
| `…squashfs-combined-efi.img.gz` | ⭐ **推荐**。UEFI 启动，squashfs 支持一键恢复出厂 |
| `…squashfs-combined.img.gz` | 传统 BIOS 启动，同样支持恢复出厂 |
| `…ext4-combined-efi.img.gz` | UEFI 启动，ext4 根文件系统 |
| `…ext4-combined.img.gz` | 传统 BIOS + ext4 |
| `…targz-*.img.gz` | 归档格式，适合装到已有系统 |
| `…rootfs.tar.gz` | 只看/提取文件内容，不刷机 |
| `sha256sums` | 校验用 |

```sh
gunzip openwrt-x86-64-generic-squashfs-combined-efi.img.gz
sudo dd if=openwrt-x86-64-generic-squashfs-combined-efi.img of=/dev/sdX bs=4M status=progress
```

---

### 包含什么

- **FanchmWrt 侧**：fwx 应用识别与行为管理（17 个 `luci-app-fwx-*`）、应用/MAC 过滤、
  上网记录、流量统计、fullcone NAT、FanchmWrt 仪表盘与主题
- **iStoreOS 侧**：QuickStart 首页面板、iStore 应用商店、Docker（Dockerman）、
  磁盘管理 DiskMan、Web 终端 ttyd
- **DNS 分流**：mosdns + geoip / geosite 规则数据
- **轻 NAS**：Samba4（服务端）/ NFS / WebDAV / wsdd2、mergerfs + UniShare

**不含**：DDNS、网络唤醒（WOL）、UPnP、硬盘休眠，以及 uhttpd / Samba 的
LuCI 配置界面。需要的话在 iStore 商店里装，或改 `include/target.mk` 重新编译。

---

### 验证情况

镜像由 GitHub Actions 在线编译，流水线里已经：

- 校验 `.config` 里必需包齐全、应排除的包确实没被选中
- 编译后运行 `scripts/verify-merged-firmware.sh` 逐项核对 rootfs 内容
- 全部通过才会走到发布这一步

**尚未验证**：fwx 应用识别需要真实流量；iStore 拉取应用列表依赖外网连通性；
Dockerman 只验证到后端 RPC 与 daemon 正常；mosdns 只验证到二进制、配置与菜单就位。
建议刷真机后自行确认。

---

### ⚠️ 授权提示

本固件是 FanchmWrt 的衍生固件，遵守其授权条款：

1. 个人使用免费，可转发、可移植；
2. **必须保留所有源码文件中的版权信息**；
3. **应用特征库（`/etc/fwxd/feature.bin`）个人免费、商业使用禁止**，版权归 FanchmWrt。

完整说明见仓库 [README](https://github.com/Winter21c/fanchmwrt-istoreos#-授权与声明)。
