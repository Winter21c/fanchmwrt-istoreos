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
`git.openwrt.org` 实测只有约 1 MB/min）。新增六个：

```conf
src-git istore     https://github.com/linkease/istore.git;main              # iStore 商店
src-git nas        https://github.com/linkease/nas-packages.git;master      # quickstart 后端 / webdav2 / unishare
src-git nas_luci   https://github.com/linkease/nas-packages-luci.git;main   # luci-app-quickstart / luci-app-unishare
src-git istoreapps https://github.com/linkease/openwrt-apps.git;main        # mergerfs / luci-app-mergerfs
src-git third      https://github.com/jjm2473/openwrt-third.git;main        # luci-app-nfs
src-git diskman    https://github.com/lisaac/luci-app-diskman.git;master    # luci-app-diskman
```

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

在 `DEFAULT_PACKAGES += $(DEFAULT_PACKAGES.$(DEVICE_TYPE))` 之后新增一个
`ifneq ($(filter x86_64,$(ARCH)),)` 块，把 11 个包加进默认包（其余由依赖带出）。

**`xz-utils` 不是可选项。** `luci-app-store` 依赖 `tar`，而 `tar` 的 `PACKAGE_TAR_XZ`
（默认 `y`）会在依赖者身上展开成一条 Kconfig 约束：

```
depends on !(PACKAGE_TAR_XZ) || PACKAGE_xz-utils
```

默认配置里 `PACKAGE_TAR_XZ=y` 而 `xz-utils` 未选，约束不可满足 → Kconfig 会把
`luci-app-store` / `luci-app-quickstart` **连同提示符一起隐藏并求值为 n**，
`.config` 里连 `# ... is not set` 都不会写出来。不选 `xz-utils` 就会得到这个
极难排查的现象。

### 4.2 `feeds.conf.default`

见第 3 节。

> 顺带一提：`scripts/feeds` 的解析器是先 `s/#.+$//` 再判空，所以 feeds.conf 里
> **不能出现只有单个 `#` 的空注释行**，否则直接报 `Syntax error`。本文件已避开。

### 4.3 `merge-patches/` + `scripts/istoreos-merge.sh`

两个定点补丁，由脚本幂等地打到 feed 检出上，挂在顶层 `Makefile` 的 `fwx_init`
（`prereq` 的前置）里，因此每次 `make` 都会重新确认。

**刻意不用 `feeds_patches/`**：那套机制是 `cp -fr` 整文件覆盖，一旦上游随后修了
同一个文件，旧副本会把上游修复**静默回退**掉。这里用定点补丁，只改目标那几行；
若上游挪动了锚点，脚本会**显式报错中止**，而不是产出一份错误的固件。

正向 / 反向各试一次 dry-run 来判断是否已应用；两边都不匹配就报错退出。

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
| `openwrt-x86-64-generic-squashfs-combined-efi.img.gz` | 124 MB | **推荐**：squashfs + EFI，支持恢复出厂 |
| `openwrt-x86-64-generic-squashfs-combined.img.gz` | 124 MB | squashfs + BIOS 引导 |
| `openwrt-x86-64-generic-ext4-combined-efi.img.gz` | 156 MB | ext4 + EFI |
| `openwrt-x86-64-generic-ext4-combined.img.gz` | 156 MB | ext4 + BIOS 引导 |
| `openwrt-x86-64-generic-targz-combined-efi.img.gz` | 155 MB | targz + EFI |
| `openwrt-x86-64-generic-rootfs.tar.gz` | 148 MB | rootfs 内容（便于免刷机核验） |

镜像比 fanchmwrt 原版大很多，主要是 `containerd`（Docker 运行时）、`samba4`、
`nfs-kernel-server`、`ntfs-3g`/`btrfs-progs`/`smartmontools`（DiskMan 依赖）
这几块。rootfs 分区在 `CONFIG_TARGET_ROOTFS_PARTSIZE=1024`（1 GB），
并已由 fanchmwrt 的 `fwx_init` 自动置 `EXPAND_ROOT=1`，首次启动会扩展分区。

### 9.2 集成验证

`./scripts/verify-merged-firmware.sh` 直接从固件的 `rootfs.tar.gz` 与
`.manifest` 校验，**107 项全部通过、0 失败**，覆盖：

- **包清单**：fanchmwrt 侧（主题、fwx 全套 18 个应用 + `fwxd` + `kmod-fwx`）、
  iStoreOS 侧（面板 / Docker / iStore）、磁盘与共享套件，共 40+ 个关键包
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
luci-app-nfs             1.2.0-r1        luci-app-samba4  26.133.20346~e9ebca7
luci-app-mergerfs        1.0.3-r1        mergerfs 2.40.2-r5
luci-app-unishare        1.0.2-r1        unishare 1.1.2-r1  webdav2 4.3.2-r1
wsdd2                    2023.12.21~b676d8ac-r2
istoreos-merge           1.0-r1
```

清单里共 515 个包。

### 9.3 复现用的 feed 提交

`bin/targets/x86/64/feeds.buildinfo` 记录了本次构建实际用到的提交。
新增的六个 feed 当时都在分支 HEAD 上，建议按需 pin：

```
istore      3fca15b30aeed9ecacb3efc8b4a8b9c2584ad5c7
nas         eccb7386ec14d2af36e9643f8f611d8dc92ac702a
nas_luci    7eac499c8983d814c36dc87785aabfc630c66716
istoreapps  e2e8e742f5ce3265445d0540dae2fa4c60976db5
third       335fa421e0fcd673a78986117981d4dfa3bf57d7
diskman     c20df1d4f40d86e32fd919f33122b2a48f8a99b4
```

（`fanchmwrt` feed 本身也记在 `feeds.buildinfo` 里：`75c3c55e1d…`。）

### 9.4 尚未验证的部分

编译、打包、镜像内容都已验证；**真机运行行为未验证**（需要实际刷机或起 QEMU）。
具体包括：iStore 能否拉到应用列表、QuickStart 面板能否正常渲染、Dockerman 能否
真正起容器、`fwx` 的 ubus 接口在有真实流量时的表现。这些依赖运行中的 LuCI 与网络，
建议刷到虚拟机或设备上确认。

另有一处**上游遗留问题**（非本次引入）：fanchmwrt 的 `DEFAULT_PACKAGES.router`
里列了 `luci-app-fwx-firewall`，但 `feeds/fanchmwrt/` 里**没有这个包**。
Kconfig 会静默忽略它（连 `# ... is not set` 都不写），所以不影响构建，
本次也没有去改上游那份清单。

