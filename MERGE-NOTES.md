# 合并说明：fanchmwrt + iStoreOS

本目录是一棵**合并后的 OpenWrt 固件源码树**，目标平台 **x86_64**。

| 来源 | 贡献 |
|---|---|
| **fanchmwrt**（底座） | fwx 全套服务（18 个 `luci-app-fwx-*` + `fwxd` + `kmod-fwx`）、fwx 仪表盘（首页）、`luci-theme-fanchmwrt` 主题、fullcone NAT、x86 默认网络脚本 |
| **iStoreOS** | QuickStart 首页面板、Docker（Dockerman）、iStore 应用商店、磁盘管理、硬盘休眠、Samba4 / NFS / WebDAV / wsdd2、mergerfs / unishare |

---

## 1. 版本核实

| | fanchmwrt | istoreos |
|---|---|---|
| 分支 | `fanchmwrt-25.12.4` | `istoreos-25.12` |
| **OpenWrt 基线** | **25.12.4** | **25.12.5** |
| 内核 | 6.12.87 | 6.12.94 |
| 包管理器 | apk | apk |
| 相对上游的自有提交 | 24 个（在 `OpenWrt v25.12.4` 之上） | 283 个（在 `OpenWrt v25.12.5` 之上） |

**两棵都是 OpenWrt 25.12 系列**：同一个 major、同一套 apk 打包体系、同一个 LuCI 架构，基线只差一个小版本。
（注意：网上流传的一些旧笔记把 istoreos 记成 24.10，那是错的 —— 本机克隆的 `istoreos-25.12` 分支
的 `include/version.mk` 默认版本号就是 `25.12.5`，且 `OpenWrt v25.12.5` 那个提交确实在它的历史里。）

---

## 2. 为什么以 fanchmwrt 为底

两棵都是完整的 OpenWrt 源码树，整体 diff/merge 只会得到一棵编译不出来的树。可行做法是
选一棵做底，把另一棵的组件作为**独立包 / 定点补丁**移植进来。

选 fanchmwrt 做底的理由：

1. **fwx 是内核态的东西**，最难搬：它包含 `target/linux/generic/hack-6.12/950-fwx-nf-conn-struct-user-hook.patch`
   这样的 generic 内核改动，外加 `libnftnl` / `nftables` / `firewall4` 的 fullcone 补丁。
   留在原地就不需要动它。
2. **两边各有一套 fullcone NAT 实现**。iStoreOS 在 generic 内核里放的是
   `982-add-bcm-fullconenat-support.patch` / `983-add-bcm-fullconenat-to-nft.patch`，
   fanchmwrt 走的是独立的 `fullconenat` / `fullconenat-nft` 包。以 iStoreOS 为底就要同时
   容纳两套，nft 表达式重名，冲突风险很高。以 fanchmwrt 为底则天然只有一套。
3. iStoreOS 侧我们要的东西（面板 / Docker / iStore / 磁盘 / 共享）**全部是包和配置**，
   正向移植比反向搬内核补丁容易得多。

---

## 3. 新增的 feed

`feeds.conf.default` 里原有的六个 feed 保持不变（只把上游 OpenWrt 那四个从
`git.openwrt.org` 改写成官方 GitHub 镜像，**提交 pin 一字未动** —— 本机到
`git.openwrt.org` 实测只有约 1 MB/min）。新增七个：

```conf
src-git istore     https://github.com/linkease/istore.git;main              # iStore 商店
src-git nas        https://github.com/linkease/nas-packages.git;master      # quickstart 后端 / webdav2 / unishare
src-git nas_luci   https://github.com/linkease/nas-packages-luci.git;main   # luci-app-quickstart / luci-app-unishare
src-git istoreapps https://github.com/linkease/openwrt-apps.git;main        # mergerfs / luci-app-mergerfs
src-git third      https://github.com/jjm2473/openwrt-third.git;main        # luci-app-nfs
src-git diskman    https://github.com/lisaac/luci-app-diskman.git;master    # luci-app-diskman
src-git mosdns     https://github.com/sbwml/luci-app-mosdns.git;v5          # mosdns + luci-app-mosdns
```

`mosdns` 上游（官方 packages feed）早已移除，这里用社区维护的 v5 分支。
前三个与 iStoreOS 自己 `feeds.conf.default` 以及 `linkease/openwrt-app-actions/feeds.conf`
完全一致。`istoreapps` / `third` / `diskman` 是补上 iStoreOS 官方 x86 固件里有、
但不在上面三个 feed 里的几个包（见第 5 节的来源考证）。

依赖链：

```
luci-app-quickstart (nas_luci) ── quickstart (nas, 预编译二进制) + luci-app-store (istore)
luci-app-store      (istore)   ── luci-lib-taskd → luci-lib-xterm, taskd
luci-app-dockerman  (luci)     ── docker + dockerd + docker-compose + ttyd + ucode-mod-socket
luci-app-unishare   (nas_luci) ── unishare (nas) → samba4-server + webdav2
luci-app-mergerfs   (istoreapps) ── mergerfs
luci-app-nfs        (third)    ── nfs-kernel-server + nfs-utils + mount-utils
luci-app-samba4     (luci)     ── samba4-server
luci-app-diskman    (diskman)  ── parted + e2fsprogs + smartmontools + ...
```

---

## 4. 改动清单

整棵树的改动**只有 5 个文件被修改、4 个路径被新增**，其余全部来自 feed：

### 4.1 `include/target.mk`

分两块。第一块在 `DEFAULT_PACKAGES += $(DEFAULT_PACKAGES.$(DEVICE_TYPE))` 之后，
用 `ifneq ($(filter x86_64,$(ARCH)),)` 圈定本项目**额外要**的 13 个包（其余由依赖带出）。

**`xz-utils` 不是可选项。** `luci-app-store` 依赖 `tar`，而 `tar` 的 `PACKAGE_TAR_XZ`
（默认 `y`）会在依赖者身上展开成一条 Kconfig 约束：

```
depends on !(PACKAGE_TAR_XZ) || PACKAGE_xz-utils
```

默认配置里 `PACKAGE_TAR_XZ=y` 而 `xz-utils` 未选，约束不可满足 → Kconfig 会把
`luci-app-store` / `luci-app-quickstart` **连同提示符一起隐藏并求值为 n**，
`.config` 里连 `# ... is not set` 都不会写出来。不选 `xz-utils` 就会得到这个
极难排查的现象。

第二块声明本项目**明确不要**的包：

```make
DEFAULT_PACKAGES += \
	-luci-app-ddns \
	-luci-app-hd-idle \
	-luci-app-samba4 \
	-luci-app-uhttpd \
	-luci-app-upnp \
	-luci-app-wol
```

`-包名` 是 OpenWrt 原生支持的移除语法 —— `scripts/target-metadata.pl` 的
`merge_package_lists()` 会把 `pkg` 与 `-pkg` 一并消掉。**这样就不必去改
FanchmWrt 原有的 `DEFAULT_PACKAGES.router`**：上游清单保持原样，本项目动了
哪些包全部集中在这一处，review 时一眼可见。

有两个包名看着像"删本体"，其实只是删界面，这里特意写明：

| 移除的包 | 本体 | 为什么本体还在 |
|---|---|---|
| `luci-app-uhttpd` | `uhttpd` + `uhttpd-mod-ubus` | 由 `luci-light`（→ `luci` 集合）依赖，Web 管理界面不受影响 |
| `luci-app-samba4` | `samba4-server` | 由 `unishare` 依赖；SMB 服务与数据照常，只是没有 LuCI 配置入口 |

> 如果不做这层区分、直接删 `luci-app-uhttpd` 就以为"去掉了一个界面"，
> 实际上会**连整个 LuCI 一起失去**——前提是 `uhttpd` 当时没有别的依赖来源。
> 本树里 `luci` 集合救了它，但这个依赖关系值得记一笔。

### 4.2 `feeds.conf.default`

见第 3 节。

> 顺带一提：`scripts/feeds` 的解析器是先 `s/#.+$//` 再判空，所以 feeds.conf 里
> **不能出现只有单个 `#` 的空注释行**，否则直接报 `Syntax error`。本文件已避开。

### 4.3 `merge-patches/` + `scripts/istoreos-merge.sh`

三个定点补丁，由脚本幂等地打到 feed 检出上，挂在顶层 `Makefile` 的 `fwx_init`
（`prereq` 的前置）里，因此每次 `make` 都会重新确认。

| 补丁 | 目标 | 作用 |
|---|---|---|
| `0001-dockerd-istoreos.patch` | `feeds/packages/utils/dockerd` | iStoreOS 对 dockerd 的全部定制 |
| `0002-quickstart-menu-order.patch` | `feeds/nas_luci` | QuickStart 菜单序号 1 → 2，让首页稳定落在仪表盘 |
| `0003-v2ray-geodata-rolling-releases.patch` | `feeds/packages` | geoip/geosite 改用滚动 release 地址 |

**刻意不用 `feeds_patches/`**：那套机制是 `cp -fr` 整文件覆盖，一旦上游随后修了
同一个文件，旧副本会把上游修复**静默回退**掉。这里用定点补丁，只改目标那几行；
若上游挪动了锚点，脚本会**显式报错中止**，而不是产出一份错误的固件。

正向 / 反向各试一次 dry-run 来判断是否已应用；两边都不匹配就报错退出。

#### 4.3.1 为什么需要 `0003-v2ray-geodata-rolling-releases.patch`

`mosdns` 本身不含规则数据，它的 LuCI 界面硬依赖 `v2ray-geoip` / `v2ray-geosite`
两个数据包（`LUCI_DEPENDS:=+mosdns +uclient-fetch +v2ray-geoip +v2ray-geosite +geo2txt +ucode`）。
而 `v2ray-geodata` 不编译任何代码，只在 `Build/Prepare` 阶段下载两个 `.dat` 文件。

问题在于上游的分发方式：

| 仓库 | 发布节奏 | 保留窗口 |
|---|---|---|
| `v2fly/geoip` | 滚动 | 约一年 |
| `v2fly/domain-list-community` | 每几小时一版 | **约三个月**（实测 571 个 release） |

packages feed 里 pin 的是 `GEOSITE_VER:=20260326050832`，**这个 tag 已经被上游删掉**，
下载直接 404，构建在这里失败：

```
curl: (22) The requested URL returned error: 404
https://github.com/v2fly/domain-list-community/releases/download/20260326050832/dlc.dat
```

也就是说「pin 死日期版本」这种常规做法在这两个仓库上**必然腐烂**，只是时间问题。

补丁改成 `releases/latest/download/` —— 这个地址永远指向最新 release，不会失效。
随之而来的两个约束：

1. **版本号不能再写 `latest`**。`VERSION:=$(GEOIP_VER)-r$(PKG_RELEASE)` 会变成
   `latest-r1`，而 `apk mkpkg` 要求版本号数字开头，会直接报
   `package version is invalid`。所以固定写成 `1`。
2. **放弃哈希校验**（`HASH:=skip`）。`scripts/download.pl` 第 159 行原生支持这个值。
   代价是这两个数据文件不再验签；它们是 DNS 分流规则数据、不参与编译，
   且走 HTTPS 从 GitHub 拉取，这里认为可接受。

下载缓存文件名也固定成 `geoip.dat.rolling` / `dlc.dat.rolling`，好处是同一个构建树里
不会反复下载 20+ MB 数据；要刷新数据就删掉这两个文件。

### 4.4 `package/istoreos-merge/`

一个极小的本地包，装两个 uci-defaults：

- `99_docker_nat_fw4` —— 与 iStoreOS 的 `istoreos-files` 同名文件内容一致。
  Docker 容器所在的 `172.16.0.0/12` 需要由路由器的 fw4 做 MASQUERADE 才能出网。
- `20_docker_data_root` —— 把 docker 数据目录指到 `/overlay/upper/opt/docker`。
  **加了 `[ -d /overlay/upper ]` 判断**：squashfs 镜像的 `/` 是 overlayfs，docker 的
  overlay2 驱动检测到 backing filesystem 是 overlay 会拒绝启动，指到底下的 ext4
  才正常（这就是 iStoreOS 在其 `09_istoreos` 里做这件事的原因）；而 ext4-combined
  镜像没有独立的 `/overlay/upper`（`/` 本身就是 ext4），保持默认值即可。
  iStoreOS 的 x86 只出 squashfs 镜像，所以它是无条件设置的。

### 4.5 主题菜单集成

`package/fcm/luci-theme-fanchmwrt`：

- `getMenuCategory()`：原版只把 `fwx*` 归入「普通模式」，其余全进「高级模式」。
  新增 `store` / `quickstart` 也进普通模式 —— 否则这两个招牌菜单在默认视图里看不见。
- `menuIcons`：补 `store` / `quickstart` 的图标映射。
- 新增 `icons/store.svg`（购物袋）、`icons/quickstart.svg`（滑杆）。
  沿用主题既有的 24×24、`stroke="currentColor"`、`stroke-width="1.8"` 风格，
  因此自动跟随深浅色。
- `cascade.css`：新增 `.menu-icon-store` / `.menu-icon-quickstart`。

### 4.6 `build-merged-x86_64.sh`

一键构建脚本（feeds → 补丁 → 种子 config → 校验 → download → build）。

---

## 5. 「iStoreOS 那三样」到底是哪些包

以**官方 iStoreOS 25.12.5 x86_64 固件**（`istoreos-25.12.5-2026091113-x86-64-squashfs-combined.img.gz`）
解开 rootfs 后读 `/etc/apk/world` 为准，而不是靠猜：

| 需求 | 官方固件里的包 |
|---|---|
| 面板仪表盘 | `luci-app-quickstart` + `quickstart`（`admin/quickstart`，order **1**，就是登录落地页） |
| Docker | `dockerd` + `docker` + `docker-compose` + `containerd` + `runc` + `luci-app-dockerman` |
| store 商店 | `luci-app-store` + `taskd` + `luci-lib-taskd` + `luci-lib-xterm` |

官方固件里还有 `appfilter`、`luci-app-oaf`（OpenAppFilter）——那是 iStoreOS 自带的
另一套 DPI/应用过滤，与本固件的 fwx 是同类功能，**没有引入**，避免两套 DPI 打架。

`luci-app-nfs` / `luci-app-diskman` / `mergerfs` 这几个不在 iStoreOS 仓库的
`feeds.conf.default` 里（他们官方构建显然还挂了别的源），所以按包名去找了对应的
上游仓库补上。

---

## 6. Docker 到底改了什么

上游 pin 的 `dockerd` 版本与 iStoreOS 分支**完全相同**（27.3.1），所以差异纯粹是
iStoreOS 的定制。`merge-patches/0001-dockerd-istoreos.patch` 覆盖：

| 改动 | 作用 |
|---|---|
| `iptables` 默认 `1` → `0` | 关掉 docker 自己的 iptables，交给 fw4 统一管 |
| 不再把 `docker0` 注册成 netifd interface | firewall 里直接挂 `device` / `subnet 172.16.0.0/12` |
| 新增 `hotplug.d/net/br-netfilter` | 只在 iptables 开启时才给 docker 网桥开 br-netfilter |
| 新增 `uci-defaults/16_docker-netifd-migrate` `17_docker-fw4` | 从旧配置迁移；自动建立 docker ↔ wan/lan 的 forwarding |
| `uciadd` / `ucidel` 重写 | 加/删 docker zone 时同步加/删 `_to_wan` / `_to_lan` / `lan_to_` forwarding |
| 新增 `lib/fstab.d/dockerd.sh` | 把 `data_root` 登记为 essential mountpoint，保证一定被挂载 |
| 日志限制 | `log-driver json-file` + `max-size 50m` + `max-file 2` |
| `reload_service` 检测 `data_root` 变化 | 变了就 restart 而不是 reload |
| `max-concurrent-downloads` 选项 | 新增可配项 |
| `+jsonfilter` 依赖 | `reload_service` 里用到了 |
| 删除 `etc/sysctl.d/sysctl-br-netfilter-ip.conf` | 改为上面那个按需开启的 hotplug 脚本 |

`docker` 与 `docker-compose` 的包目录**没有** iStoreOS 定制（`diff -rq` 为空 /
只有版本号差异），所以完全用上游 pin 的版本，不打补丁。

### 6.1 首页归属：菜单 order 冲突

`fwx_dashboard` 在 controller 里注册的 order 是 **1**，`luci-app-quickstart` 的
menu.d 里 order 也是 **1**。

- **可见菜单顺序**其实是确定的：`ui.js` 的 `getChildren()` 先按 order 排序，
  相等时用 `L.naturalCompare` 比名字，`fwx_dashboard` < `quickstart`。
- **首页落地顺序不确定**：服务端 `resolve_firstchild()` 只按 `node_weight()`（即 order）
  取最小者，**相等时保留先插入的那个**，也就是取决于 feed 的扫描顺序。

你选的是**以 fanchmwrt 仪表盘为首页**，所以把 QuickStart 让到 `order 2`
（`merge-patches/0002-quickstart-menu-order.patch`）。这是让「客人」给「主人」让位：
底座固件自己的仪表盘保持 order 1 不动，新加进来的页面排到第二位。

---

## 7. 构建

```sh
cd fanchmwrt-istoreos

# 一次性：拉取并安装 feed
./scripts/feeds update -a
./scripts/feeds install -a

# 种子配置（只需目标与 rootfs 大小，其余由 include/target.mk 推导）
cat > .config <<'EOF'
CONFIG_TARGET_x86=y
CONFIG_TARGET_x86_64=y
CONFIG_TARGET_x86_64_DEVICE_generic=y
CONFIG_TARGET_ROOTFS_PARTSIZE=1024
EOF
make defconfig

# 构建
make -j$(nproc) download
make -j$(nproc) BUILD_LOG=1
```

或者直接 `./build-merged-x86_64.sh`。产物在 `bin/targets/x86/64/`。

### 7.1 构建机网络注意事项

本机到 `cdn.kernel.org` 只有约 **20 KB/s**，而 curl 默认**没有速率下限**，
于是「能用但极慢」的镜像会让 `make download` **永久卡住**，而不是自动换下一个。
`scripts/download.pl` 会把环境变量 `CURL_OPTIONS` 拼进每一次 curl 调用，
所以构建脚本里设了：

```sh
export CURL_OPTIONS="--speed-limit 51200 --speed-time 60"
```

即：平均速率连续 60 秒低于 50 KB/s 就放弃该镜像，由 `download.pl` 换下一个；
全都慢则**快速失败并报错**，而不是挂几个小时。

---

## 8. 已知事项与风险

- **平台范围**：`DEFAULT_PACKAGES` 的集成块限定 `x86_64`。其它架构上
  `quickstart` 后端没有预编译二进制、`luci-app-dockerman` 自身也限定
  `@(aarch64||arm||x86_64)`。本树**没有删掉** `target/linux/` 下的其它机型
  （删了会牵连 toolchain 与大量包的条件编译），只是不为它们启用这些集成包。
- **未纳入的 feed**：没有加入提供 `luci-theme-argon` 的完整依赖链，也没引入
  iStoreOS 的 `istoreos-files`（它会硬依赖 argon 并把默认主题设成 argon，
  且 `99_theme` 排在 fanchmwrt 的 `31_luci-theme-fanchmwrt` 之后，会**覆盖掉**
  fanchmwrt 主题）。默认主题是 `luci-theme-fanchmwrt`。
- **OTA 未纳入**：按你的选择没有引入 `luci-app-ota` / `grub-conf`，以及 iStoreOS
  在 `include/kernel-defaults.mk` 里那套 `TOPDIR/.vermagic` 覆盖机制
  （那是为跨版本 OTA 保持内核模块兼容用的）。
- **LuCI 版本差异**：iStore / QuickStart / Dockerman 是跟着 iStoreOS 的 luci fork
  开发的，本树用的是 fanchmwrt pin 的**上游 luci**。两者都是 25.12 时代的标准
  LuCI 接口（`luci.template.render`、`luci.model.uci`、`luci.jsonc`、`nixio`），
  编译应当通过，但**真机运行行为需实测**。
- **上游活跃度**：QuickStart 上游 README 明确写着正在重构。如需可复现构建，
  建议把这六个新 feed 也 pin 到具体 commit。
- **`PKG_FLAGS:=hold` 在 apk 下是空操作**：`package-pack.mk` 只在 opkg/ipk 路径写
  `Status: ... hold`，apk 走 `apk mkpkg --info`，那个显式列表里没有 hold 字段。
  补丁里保留了 `PKG_FLAGS:=hold`（与 iStoreOS 上游一致、无害），但**不要指望它
  提供实际保护**。

---

## 9. 构建与验证结果

已在本机完成一次完整构建（x86_64，12 并发），随后又做了一次增量重建。
`sha256sums` 里 16 个文件全部校验通过。

### 9.1 产物

`bin/targets/x86/64/`，可刷写的镜像：

| 镜像 | 大小 | 说明 |
|---|---|---|
| `openwrt-x86-64-generic-squashfs-combined-efi.img.gz` | 131 MB | **推荐**：squashfs + EFI，支持恢复出厂 |
| `openwrt-x86-64-generic-squashfs-combined.img.gz` | 131 MB | squashfs + BIOS 引导 |
| `openwrt-x86-64-generic-ext4-combined-efi.img.gz` | 166 MB | ext4 + EFI |
| `openwrt-x86-64-generic-ext4-combined.img.gz` | 166 MB | ext4 + BIOS 引导 |
| `openwrt-x86-64-generic-targz-combined-efi.img.gz` | 166 MB | targz + EFI |
| `openwrt-x86-64-generic-rootfs.tar.gz` | 160 MB | rootfs 内容（便于免刷机核验） |

镜像比 fanchmwrt 原版大很多，主要是 `containerd`（Docker 运行时）、`samba4`、
`nfs-kernel-server`、`ntfs-3g`/`btrfs-progs`/`smartmontools`（DiskMan 依赖），
以及 `geoip.dat` / `geosite.dat` 两份 DNS 分流规则数据（合计约 5 MB 压缩后）。rootfs 分区在 `CONFIG_TARGET_ROOTFS_PARTSIZE=1024`（1 GB），
并已由 fanchmwrt 的 `fwx_init` 自动置 `EXPAND_ROOT=1`，首次启动会扩展分区。

### 9.2 集成验证

`./scripts/verify-merged-firmware.sh` 直接从固件的 `rootfs.tar.gz` 与
`.manifest` 校验，**131 项全部通过、0 失败**，覆盖：

- **包清单**：fanchmwrt 侧（主题、fwx 全套 18 个应用 + `fwxd` + `kmod-fwx`）、
  iStoreOS 侧（面板 / Docker / iStore）、磁盘与共享套件、DNS 与终端，共 50+ 个关键包
- **反向校验**：逐个确认 ddns / hd-idle / wol / upnp / uhttpd 界面 / samba4 界面
  这 6 个包**确实不在固件里**，同时确认 `uhttpd` 与 `samba4-server` 的本体仍在
- **主题改动**：两个新图标、`.menu-icon-store` / `.menu-icon-quickstart`、
  菜单归类、图标映射
- **首页归属**：`fwx_dashboard` 的 order 为 1，`quickstart` 的 menu.d 为 2
- **Docker**：`dockerd.init` 的新 hotplug/uci-defaults/fstab.d 脚本齐全，
  `iptables '0'`，旧的全局 br-netfilter sysctl 确认已移除，
  DockerNAT 与 data_root 两个 uci-defaults 到位
- **iStore / QuickStart / DiskMan / NFS / Samba4 / mergerfs / unishare / webdav2**
  的文件与 controller 均落到 rootfs

已确认的版本：

```
luci-theme-fanchmwrt     26.264.03002~afc4d28
luci-app-fwx-dashboard   1.0.1-r1        luci-app-fwx-app-center  1.0.0-r1
fwxd                     1.0.4-r1
luci-app-quickstart      0.12.10-r1      quickstart               0.13.0-r1
luci-app-dockerman       26.133.20346~e9ebca7
dockerd                  27.3.1-r5       docker   27.3.1-r2   docker-compose 2.40.3-r1
luci-app-store           0.2.1-r1        taskd    1.0.3-r2
luci-app-diskman         0.2.13-r1
luci-app-mosdns          1.7.14-r1       mosdns   5.3.4-r14   geo2txt 1.0.0-r1
v2ray-geoip              1-r1            v2ray-geosite 1-r1     （滚动数据，见 4.3.1）
luci-app-ttyd            26.133.20346~e9ebca7                     ttyd 1.7.7-r1
luci-app-nfs             1.2.0-r1        samba4-server 4.22.7-r3
luci-app-mergerfs        1.0.3-r1        mergerfs 2.40.2-r5
luci-app-unishare        1.0.2-r1        unishare 1.1.2-r1  webdav2 4.3.2-r1
wsdd2                    2023.12.21~b676d8ac-r2
istoreos-merge           1.0-r1
```

已确认**不在**清单里的包：`luci-app-ddns`、`luci-app-hd-idle`、`luci-app-wol`、
`luci-app-upnp`、`luci-app-uhttpd`、`luci-app-samba4`（及其连带拉入的
`ddns-scripts`、`miniupnpd-nftables`、`etherwake` 等）。
`uhttpd` / `uhttpd-mod-ubus` / `samba4-server` 本体仍在。

清单里共 504 个包。

### 9.3 复现用的 feed 提交

`bin/targets/x86/64/feeds.buildinfo` 记录了本次构建实际用到的提交。
新增的七个 feed 当时都在分支 HEAD 上，建议按需 pin：

```
istore      3fca15b30aeed9ecacb3efc8b4a8b9c2584ad5c7
nas         eccb7386ec14d2af36e9643f8f611d8dc92ac702a
nas_luci    7eac499c8983d814c36dc87785aabfc630c66716
istoreapps  e2e8e742f5ce3265445d0540dae2fa4c60976db5
third       335fa421e0fcd673a78986117981d4dfa3bf57d7
diskman     c20df1d4f40d86e32fd919f33122b2a48f8a99b4
mosdns      bd40245303cd0ba56804d49eed5dbc4be2a082ca
```

> `mosdns` 这个 feed 尤其建议 pin：它的 `v5` 是分支，而上游
> `v2fly/domain-list-community` 的数据 tag 每三个月轮换一次，
> 固定住 feed 提交能让「除了数据之外」的部分保持可复现。

（`fanchmwrt` feed 本身也记在 `feeds.buildinfo` 里：`75c3c55e1d…`。）

### 9.4 上游遗留问题

fanchmwrt 的 `DEFAULT_PACKAGES.router` 里列了 `luci-app-fwx-firewall`，
但 `feeds/fanchmwrt/` 里**没有这个包**。Kconfig 会静默忽略它
（连 `# ... is not set` 都不写），所以不影响构建，本次也没有去改上游那份清单。

---

## 10. QEMU 实机启动验证

固件已在 QEMU/KVM 下**实际启动过**，验证结论如下。

### 10.1 管理地址取决于网口数量（重要）

fanchmwrt 的 `/usr/bin/fwx_cli.sh` 里有个 `check_and_init_network()`：
**如果没有 WAN 接口（`network.wan.proto` 为空），它会把 LAN 切成 DHCP
并进入旁路模式**：

```sh
wan_proto=$(uci get network.wan.proto 2>/dev/null)
if [ -z "$wan_proto" ]; then
    uci set network.lan.proto=dhcp
    uci set fwx.network.work_mode=1      # 1 = 旁路模式
    ...
fi
```

而 WAN 是由 `target/linux/x86/base-files/etc/board.d/03-default-network` 按网口
数量创建的。实测两种情况：

| 网口数 | 工作模式 | `br-lan` | 管理地址 |
|---|---|---|---|
| **≥ 2**（真实软路由典型） | **Gateway Mode** | **192.168.1.1/24 静态** | **http://192.168.1.1** |
| 1 | Bypass Mode | DHCP 客户端 | 由上游路由器分配，需查上游 DHCP 租约 |

单网口情况下要改回静态，可以用串口/VGA 上的 fanchmwrt 控制台菜单
`[2] Set LAN(br-lan) Static IP`。

### 10.2 登录凭据

fanchmwrt 在 `package/base-files/files/etc/shadow` 里预置了 root 密码，
哈希为 `$5$dp/4vCQAseJ6gAD6$j0Q…`，对应明文是 **`password`**。
（已验证：`openssl passwd -5 -salt dp/4vCQAseJ6gAD6 password` 与该哈希逐字节相同。）
`dropbear` 的 `PasswordAuth` / `RootPasswordAuth` 均为 `on`。
**建议首次登录后立刻改掉。**

### 10.3 Web 服务

```
uhttpd.main.listen_http  = 0.0.0.0:80  [::]:80
uhttpd.main.listen_https = 0.0.0.0:443 [::]:443   （自签证书）
uhttpd.main.redirect_https = 0                     （不强制跳 HTTPS）
```

未登录访问 `/cgi-bin/luci/` 返回 **403 + `x-luci-login-required: yes` + 登录页 HTML**
—— 这是 LuCI 的正常行为（浏览器 JS 会据此渲染登录框），不是故障。

返回的登录页里引用的是：

```html
<link rel="stylesheet" href="/luci-static/fanchmwrt/cascade.css?v=26.264.03002~afc4d28">
```

**证明默认主题确实是 `luci-theme-fanchmwrt`。**

### 10.4 Docker 运行时

```
Server Version: 27.3.1
Storage Driver: overlay2          ← 关键
Docker Root Dir: /overlay/upper/opt/docker
Cgroup Driver: cgroupfs   Cgroup Version: 2
```

存储驱动是 `overlay2` 而不是退化成 `vfs`，说明 `package/istoreos-merge` 里的
`20_docker_data_root` 起作用了：squashfs 镜像的 `/` 是 overlayfs，docker 的
overlay2 驱动会拒绝在 overlay 上工作；把数据目录指到 `/overlay/upper`（底下的
ext4 分区本身）之后才正常。`docker0` 也在启动后自动出现（172.17.0.1）。

`dockerd` / `quickstart` / `istore` / `fwx` 四个服务启动后均为 enabled。

### 10.5 仍未验证的部分

`fwx` 的 DPI/应用识别要有**真实流量**才有意义，QEMU 的用户态网络测不出来；
iStore 能否真正拉到应用列表依赖外网到 linkease 仓库的连通性；
Dockerman 的 Web 界面只验证到后端 RPC 与 daemon 正常，没有实际拉起容器。
这些建议刷到真实设备或带桥接网络的虚拟机里再确认。



---

## 11. 在线编译（GitHub Actions）

### 11.1 为什么先删掉上游的 CI

FanchmWrt 是从 OpenWrt 直接分出来的，`.github/` 下原样带着 OpenWrt 官方的
**14 个工作流**和项目配置。它们不是「没用的东西」，而是**会真的跑起来**的：

| 文件 | 触发条件 | 在本仓库的后果 |
|---|---|---|
| `tools.yml` | `push` 命中 `include/**`、`tools/**` | 改一次 `include/target.mk` 就会触发跨平台 host tools 构建 |
| `github-release.yml` | `push` 标签 `v*` | **与我们自己的发布流程直接冲突** |
| `packages.yml` / `kernel.yml` | `push`/`pull_request` 命中若干路径 | 触发 OpenWrt 的包/内核矩阵构建 |
| `push-containers.yml` / `toolchain.yml` | `push` 命中 `tools/**`、`toolchain/**` | 触发容器与工具链构建 |
| `coverity.yml` | 每周定时 | 需要 `COVERITY_TOKEN`，必然失败 |
| `build-on-comment.yml` / `labeler.yml` / `label-*.yml` | 评论 / PR | 依赖 OpenWrt 组织的配置 |

而且它们底层都 `uses: openwrt/actions-shared-workflows/...@main` —— 是给
OpenWrt 官方基础设施用的，在派生仓库里跑不通。

`FUNDING.yml` 指向 OpenWrt 的捐赠页，`ISSUE_TEMPLATE/` 把用户引导到 OpenWrt
论坛和 triage —— 放在这个仓库里都会误导人。

所以把这些一并删掉，换成我们自己的工作流。**这些都不影响编译**，只影响 CI 行为。

### 11.2 工作流设计

`.github/workflows/build-x86_64.yml`，三种触发方式：

- `workflow_dispatch` —— 手动，可选是否建 Release、是否传构建产物
- `push: tags: v*` —— 打标签自动编译并发布
- `schedule`（默认注释掉）—— 每周构建，用来提前发现上游腐烂

几个关键取舍：

**准备阶段直接复用 `build-merged-x86_64.sh`。** 给它加了个 `SKIP_BUILD=1`
开关，让它停在编译前。这样 feeds / 补丁 / 配置 / 校验这套逻辑在本地和 CI
是**同一份代码**，不会出现「本地能编、CI 编不出来」；同时下载与编译仍是独立
的 step，日志和重试边界都清楚。

**`fetch-depth: 1`。** `scripts/getver.sh` 的解析顺序是
`try_version || try_git || try_hg`，而树里的 `version` 文件
（内容 `r32933-4ccb782af7`）已经提供了版本号，`try_version` 直接命中，
根本不会走到 git 分支。所以不需要拉 280MB 的完整历史。

**必须先释放磁盘空间。** GitHub 的 runner 根分区初始只有约 14GB 可用，
而整棵 OpenWrt 编译需要约 30GB，不清理会在编到一半时
`No space left on device`。工作流开头删掉 runner 预装但用不到的
.NET / Android SDK / CodeQL 等。

**缓存 `dl/`。** 主要目的不是省时间（编译才是大头，约 2～3 小时），
而是**防止某个上游 tarball 消失导致构建失败** —— 命中缓存时根本不会去下载。
key 只跟 `feeds.conf.default` 走：它变了才说明包来源变了。

**核验不通过就不发布。** `.config` 校验（必需包齐全 + 排除包不在）和
`verify-merged-firmware.sh` 都排在创建 Release 之前。

**标签做了字符集校验。** 标签会经 `sed` 写进 Release 说明模板、也会当参数传给
`gh`，所以限定为 `[A-Za-z0-9._-]+` —— 既挡 sed 注入，也顺带挡住非法 git tag。

### 11.3 额度的现实预期

公开仓库的 Actions 不计费。`timeout-minutes` 设为 350（GitHub 单 job 上限 360）。

**实测数据**（4 核 runner，`dl/` 缓存命中）：

| 配置 | 耗时 |
|---|---|
| 关闭 Docker（`enable_docker=false`） | **110 分钟** |
| 开启 Docker（默认） | **123 分钟** |

两者都远在 350 分钟上限之内。开 Docker 只多 13 分钟 —— 因为
`dl/` 缓存省下的是下载，而 dockerd / containerd / docker-compose
这三个 Go 包本身就是十几分钟量级，不是想象中的大头。

真正吃时间的是工具链与内核（首次构建时约占一半）。所以
**首次构建（缓存未命中）会比上表更久**，估算时按 2～3 小时留余量比较稳妥。
真跑满 6 小时（比如 runner 特别慢、或 Go 模块下载卡住）会超时失败，
重跑一次通常就好。

`fetch-depth: 1` 与 `dl/` 缓存的收益在这些数字里已经体现：
准备 + 下载阶段合计只占十几分钟，其余全是编译。

---

## 12. 可选的构建参数

构建者可以在 GitHub Actions 页面上选三件事：**管理地址**、**rootfs 分区大小**、
**是否包含 Docker**。本地构建走同一套机制。

### 12.1 机制

`scripts/apply-build-options.sh` 读取三个环境变量，把它们落成源码树里的具体改动：

| 参数 | 落到哪里 |
|---|---|
| `LAN_IP` | `package/build-defaults/files/etc/uci-defaults/25_lan_ip` |
| `ROOTFS_PARTSIZE` | `.config` 的 `CONFIG_TARGET_ROOTFS_PARTSIZE` |
| `ENABLE_DOCKER` | `.build-options`（make 片段）→ `include/target.mk` |

`include/target.mk` 用 `-include $(TOPDIR)/.build-options` 读回来，Docker 相关的
包（`luci-app-dockerman` / `istoreos-merge`）改成条件加入。其余包的「不要清单」
仍然是 `-包名` 语法，两套机制互不干扰。

### 12.2 管理地址为什么用 uci-defaults

`bin/config_generate` 是在**首次启动时**才生成 `/etc/config/network` 的，
uci-defaults 紧随其后执行、且在 `network` 服务启动之前，所以在这里改既生效，
又不必去动 base-files 的核心脚本。

一个细节：`config_generate` 生成的是 **list** 形式的 `ipaddr`，
所以脚本必须先 `delete` 再 `add_list`；直接 `set network.lan.ipaddr=...`
会同时留下新旧两个地址。核验脚本里有对应的断言盯着这一点。

### 12.3 与 FanchmWrt 旁路模式的相互作用

FanchmWrt 的 `fwx_cli.sh` 在「没有 WAN 口」时会把 LAN 改成 DHCP 进旁路模式。
查证下来它的调用链是：

```
/etc/inittab → /usr/libexec/login.sh → /usr/bin/fwx_cli.sh → check_and_init_network()
```

也就是说**只在串口/VGA 控制台登录时才会触发**。无头机器上不会跑，
这里设定的静态地址会一直保持；多网口机器有 WAN，本来也不会触发。

### 12.4 一个会静默出错的坑（已修）

改完参数重新构建时，很容易出现「**参数改了，却编出和上次一样的包集**」。
根因有两层，必须同时处理：

1. **make 不把 `.build-options` 当成 `prepare-tmpinfo` 的依赖。**
   它的时间戳变了，但 `tmp/` 里的 Kconfig 元数据不会重算 ——
   `config DEFAULT_<包>` 这个符号压根不会生成，于是包里的
   `default y if DEFAULT_<包>` 恒为假。

2. **`make defconfig` 只补缺失的符号，不覆盖已有值。**
   就算元数据重算了，`.config` 里那句 `# CONFIG_PACKAGE_x is not set`
   是显式值，会被原样保留。

所以 `apply-build-options.sh` 会在参数**发生变化**时同时删掉 `tmp/` 与 `.config`
（旧配置备份为 `.config.old`）。参数没变则什么都不动，不影响增量构建。

这个坑是实测踩出来的：当时出现了「docker 明明关掉了，验证脚本却报
『以下包本应被移除，却仍然启用』」的假失败。

### 12.5 另一个坑：GitHub Actions 的 boolean 假值

工作流里**不能**写：

```yaml
ENABLE_DOCKER: ${{ inputs.enable_docker || '1' }}
```

GitHub 表达式里 `false` 是假值，`false || '1'` 会得到 `'1'` ——
用户明明取消了勾选，固件里却仍然编进了 Docker。

正确做法是直接传输入原值（`${{ inputs.enable_docker }}`），
push 触发时它渲染为空字符串，由脚本自己判定「空 = 用默认」。
语义单一，也不会踩这个坑。

### 12.6 CI 实测验证记录

用 `lan_ip=192.168.100.1` + `rootfs_size=2048` + `enable_docker=false`
在 GitHub Actions 上跑通了一次完整构建（run `35578434536`，110 分钟）：

- 准备阶段日志确认参数生效：`管理地址：192.168.100.1/24`、
  `rootfs 分区：2048 MB`、`Docker：不含`、`已删除 tmp/（Kconfig 元数据缓存）`
- 核验阶段 **126 项通过、0 失败**，其中：
  - `luci-app-dockerman` / `dockerd` / `docker` / `docker-compose` /
    `containerd` / `runc` / `istoreos-merge` 逐个确认**不在固件里**
  - `ttyd 未受 Docker 关闭影响（luci-app-ttyd 自带 +ttyd 依赖）`
  - `管理地址 uci-defaults 已打包（192.168.100.1/24）`、
    `用 add_list 写入（与 config_generate 的 list 形式一致）`、
    `地址值与构建参数一致`
- 产物 547 MB（关掉 Docker 后比含 Docker 的 1.49 GB 小很多）

含 Docker 的默认路径也在 CI 上跑通过一次（run `35588537583`，123 分钟，
参数为 `192.168.1.1` / 1024MB / 含 Docker），结论同样是 success。

第一次跑（run `35577305339`）在准备阶段就失败，暴露了 12.4 节那个
「首次生成复用过期元数据」的问题 —— 这正是坚持在 CI 上真跑一次的价值：
本地三种复现方式都是绿的，只有真实 CI 环境能把它逼出来。

### 12.7 又一个坑：模板替换不能随便用 sed

第 12.5 节那个 boolean 假值之外，发布路径上还埋着一个更直接的：

```
sed: -e expression #4, char 27: unknown option to `s'
```

原因是 Release 说明的模板替换写成了：

```sh
sed -e "s/@LANIP@/${OPT_LANIP}/g" .github/release-notes.md
```

而 `OPT_LANIP` 是 **`192.168.100.1/24`** —— 带前缀长度的 CIDR 形式。
替换值里的 `/` 把 `s///` 的分隔符提前截断了。

这个 bug 有个很典型的特点：**只在「自定义了管理地址 + 勾选发 Release」时触发**。
我之前的验证跑的都是 `create_release=false`，发布步骤整段被 skip，
所以一路绿灯；默认地址 `192.168.1.1` 追加 `/24` 后同样带斜杠，
也就是说 **`push v*` 标签自动发布那条路也从一开始就是坏的**。

修法是改用 bash 参数展开做模板替换：

```sh
shopt -u patsub_replacement 2>/dev/null || true
template="$(cat .github/release-notes.md)"
template="${template//@LANIP@/$OPT_LANIP_HOST}"
```

替换值被当成字面量，`/`、`&`、`\` 都不需要转义。
（`shopt -u patsub_replacement` 是因为 bash 5.2 起默认开启该选项，
会让替换值里的 `&` 也展开成「匹配到的内容」—— 当前的值不含 `&`，
但关掉零成本。）

另外补了两道防线：

1. **URL 与展示分离**：`.build-options` 里存的是 `192.168.100.1/24`，
   直接拼进 URL 会变成 `http://192.168.100.1/24`。现在额外导出
   `@LANIP@`（纯主机名，给 URL）与 `@LANIPFULL@`（完整形式，给信息行）。
2. **占位符自检**：替换完扫一遍 `@[A-Z_]+@`，只要还有残留就直接失败 ——
   宁可这一步报错，也不要发一份带着 `@XXX@` 的 Release 出去。

**教训**：验证一个流程时，必须让它的每一条分支都真正跑到。
`create_release=false` 的绿灯给了我一种「发布路径没问题」的错觉。
