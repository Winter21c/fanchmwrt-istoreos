## FanchmWrt × iStoreOS 融合固件 · HINLINK HT2（@TAG@）

以 **[FanchmWrt](https://github.com/fanchmwrt/fanchmwrt)** 为底座，移植 **[iStoreOS](https://github.com/istoreos/istoreos)** 的首页面板、Docker 与 iStore 应用商店。面向 **HINLINK HT2（Rockchip RK3528，aarch64）**。

- **构建版本**：`@VERSION@`
- **构建日期**：@DATE@
- **管理地址**：`@LANIPFULL@`
- **rootfs 分区**：@ROOTSIZE@ MB
- **Docker**：@DOCKER@
- **已安装软件包**：@PKGCOUNT@ 个
- **自动校验**：构建流水线里 `FANCHMWRT_TARGET=rockchip-armv8 scripts/verify-merged-firmware.sh` 全部通过

---

### 硬件

| | |
|---|---|
| SoC | Rockchip RK3528A（4× Cortex-A53） |
| 内存 | LPDDR4 1 / 2 / 4 GB |
| 存储 | eMMC 8 / 32 / 64 GB + microSD |
| 网络 | **1 个千兆口**（RTL8211F，接在 gmac1 上） |
| 无线 | SDIO WiFi 6，**两个批次**：AMPAK AP6275S（Broadcom BCM43752）或 AICSemi AIC8800 |
| USB | 1× USB 3.0、1× USB 2.0 |
| 调试串口 | UART0，**1500000** 8N1（不是 115200） |

> 无线两个批次的驱动与固件**都编进了固件**。设备树对两者是同一套接线
> （都挂 `&sdio0`、共用 GPIO1_A6 复位脚），所以不需要你先拆机确认 ——
> 开机后 `dmesg | grep -iE "brcmfmac|aicwf"` 谁认到就是谁。

---

### 快速开始

| | |
|---|---|
| 🌐 **管理地址** | **http://@LANIP@** |
| 👤 **用户名** | `root` |
| 🔑 **密码** | `password` |

> ⚠️ 首次登录后请立刻改密码。
>
> ⚠️ HT2 **只有一个网口**，它就是 LAN。插上网线、电脑设成 DHCP，
> 或者手动设一个 `@LANIP@` 同网段的地址。

关于「旁路模式」：FanchmWrt 在检测到没有 WAN 口时会把 LAN 改成 DHCP 客户端。
但那段逻辑在 `/usr/libexec/login.sh` 里，**只在串口/VGA 控制台登录时才跑**。
HT2 无头启动时不会触发，`@LANIPFULL@` 会一直保持。

---

### 刷机

产物有**两个**，每个启用的文件系统类型各一个。两个都是完整的磁盘镜像
（MBR + boot 分区 + rootfs 分区），**u-boot 已经写在镜像开头**，所以既能写卡也能写 eMMC。

| 文件 | 说明 |
|---|---|
| `…-squashfs-sysupgrade.img.gz` | ⭐ **推荐**。只读根 + overlay，支持一键恢复出厂 |
| `…-ext4-sysupgrade.img.gz` | 可写根，装大件更省空间，但没有一键恢复出厂 |

> 为什么是两个而不是一个：rockchip 目标会为 `.config` 里每个启用的文件系统类型
> 各出一个 sysupgrade 镜像，而 defconfig 默认把 squashfs 与 ext4 都打开。
> 这一条是**编译实测**出来的 —— 最初按「一个镜像」写，Release 附件断言会把
> 一次完全正常的构建判成失败。

#### 首次安装：写 microSD 启动

```sh
gunzip -c ...-squashfs-sysupgrade.img.gz | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress
sync
```

把卡插进 HT2，上电。RK3528 的 u-boot 启动顺序是 `SD → eMMC`，
所以有卡就从卡启动。

#### 装到 eMMC

从 SD 卡启动后，**不要**直接用 `sysupgrade` —— 那样写的是当前启动的那块盘（也就是 SD 卡）。
要写 eMMC 得指名设备：

```sh
# 从 SD 启动的系统里：eMMC 是 mmcblk0，SD 卡是 mmcblk1
#（设备树里 aliases 把 mmcblk0 给了 sdhci＝eMMC、mmcblk1 给了 sdmmc＝SD）
cat /proc/partitions        # 先确认一遍，别写错盘

gunzip -c ...-squashfs-sysupgrade.img.gz | dd of=/dev/mmcblk0 bs=4M conv=fsync
sync
poweroff
```

断电、拔卡、再上电，就从 eMMC 启动了。

#### 之后升级

从 eMMC 启动之后，`sysupgrade` 就是对的 —— 它写的就是 eMMC，并且会保留配置：

```sh
sysupgrade -k ...-squashfs-sysupgrade.img.gz      # -k 保留配置
```

在 LuCI 里「系统 → 备份/刷写固件」上传同一个文件也一样。

> ⚠️ `sysupgrade` 会把 **u-boot 一起重写**。这是有意的（保证引导与内核配套），
> 但意味着刷写中途断电会变砖，需要 Maskrom 模式救回来。刷之前确认供电稳定。

#### 救砖

板上有一个 Maskrom 按键。按住它上电，SoC 会进入 Maskrom 模式，可以用
`rkdeveloptool db` + `wl` 写回镜像，或者用 `rkdevtool`（Windows）。
`ht2基础` 资料里那份 `HT2-Boot-Loader.bin` 就是这类救砖工具链用的 loader。

---

### 镜像说明

| 文件 | 说明 |
|---|---|
| `…hinlink_ht2-squashfs-sysupgrade.img.gz` | ⭐ 推荐。只读根 + overlay，支持恢复出厂 |
| `…hinlink_ht2-ext4-sysupgrade.img.gz` | 可写根，没有一键恢复出厂 |
| `sha256sums` | 校验用 |

校验：

```sh
sha256sum -c sha256sums --ignore-missing
```

---

### 已知边界（未实机验证的点）

这份固件是**离线核验通过、尚未在真机上跑过**的。下面几项是按经验最可能出问题的地方，
刷之前有个心理准备；实测有问题请带上串口日志（1500000 8N1）开 issue：

1. **PHY 延时**：厂商 DTS 用的是 `rgmii-rxid` + `tx_delay = 0x30`，本固件跟随上游
   H28K 用 `rgmii-id`（让 RTL8211F 自己出两个延时）。H28K 与 HT2 是同一颗 PHY、
   同一个地址、同一个复位脚，所以大概率没问题 —— 但网口不通的话，第一个要试的就是把它改回 `rgmii-rxid`。
2. **WiFi**：两个批次的驱动是否都能起来。BCM43752 需要 `brcmfmac43752-sdio.txt`
   这份 NVRAM（文件头写着 `AP6275S_NVRAM_V1.7`），AIC8800 需要对应的 `fmacfw_*.bin`。
3. **USB 3.0**：主线上 RK3528 的 XHCI/combo-PHY 描述还不完整，
   本固件按 USB 3.0 主机模式打开，最差情况是只跑 USB 2.0 速率。
4. **eMMC 型号兼容**：不同批次的 eMMC 对 HS200 的支持不一样。起不来就把
   `mmc-hs200-1_8v` 去掉重编。
5. **无线没有独立 MAC**：LAN 的 MAC 由 eMMC 的 CID 派生（这块板子没有 MAC 存储芯片）。
   所以换一块 eMMC 会让 MAC 变化 —— 这是设计如此，不是 bug。

---

### 许可与出处

- 底座：[FanchmWrt](https://github.com/fanchmwrt/fanchmwrt)
- 面板与商店：[iStoreOS](https://github.com/istoreos/istoreos)
- BCM43752 固件来自 [armbian/firmware](https://github.com/armbian/firmware)
- AIC8800 驱动来自 [radxa-pkg/aic8800](https://github.com/radxa-pkg/aic8800)

再发布固件时请附上以上仓库地址。
