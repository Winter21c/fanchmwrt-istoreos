#!/bin/sh
#
# 构建合并后的 fanchmwrt + iStoreOS **HINLINK HT2（Rockchip RK3528）** 固件。
#
# 产物在 bin/targets/rockchip/armv8/。
#
# 用法:  ./build-merged-ht2.sh [jobs]
#
# 环境变量（与 x86 版完全一致，见 scripts/apply-build-options.sh）：
#   LAN_IP           管理地址，可带前缀长度。默认 192.168.1.1
#   ROOTFS_PARTSIZE  rootfs 分区大小（MB）。默认 1024
#   ENABLE_DOCKER    是否包含 Docker。默认 1
#   SKIP_BUILD       设了就只做到「准备就绪」
#
# ---------------------------------------------------------------------------
# 为什么与 x86 分成两个脚本，而不是加一个 --target 参数
# ---------------------------------------------------------------------------
# 目标决定的不是「包选集」而是**设备层与产物形态**：
#
#    x86_64          GRUB 引导；4 个镜像（squashfs/ext4 × efi/非 efi）；
#                    管理地址落在 br-lan，网口由内核自动命名
#    rockchip-armv8  一个 sysupgrade.img.gz（GPT：boot + rootfs，
#                    前面 32768 扇区放 u-boot-rockchip.bin）；
#                    设备树决定唯一的网口是 eth0 且是 LAN
#
# 两者的「准备阶段」只有 feeds / 补丁 / 构建参数三步是共用的，
# 配置种子与断言清单都不一样。写成一个脚本加 if 分叉，会让每一次
# 读这个文件的人都要在脑子里同时装下两套形态 —— 拆开更清楚。
#
# 共用逻辑（feeds、iStoreOS 补丁、构建参数、包集断言）仍然只在
# 各自被调用的脚本里实现一份，没有复制粘贴。
#
set -e

TOPDIR="$(cd "$(dirname "$0")" && pwd)"
cd "$TOPDIR"

JOBS="${1:-$(nproc)}"

# 目标标识：apply-build-options.sh 与 verify-merged-firmware.sh 都读它，
# 用来决定「哪些与产物形态相关的开关该动」。
export FANCHMWRT_TARGET="rockchip-armv8"

# 慢镜像保护。同 x86 版：让平均速率连续 60 秒低于 50 KB/s 就放弃该镜像。
export CURL_OPTIONS="${CURL_OPTIONS:---speed-limit 51200 --speed-time 60}"

echo "==> 合并树 : $TOPDIR"
echo "==> 目标   : rockchip-armv8（HINLINK HT2 / RK3528）"
echo "==> 并发   : $JOBS"

# --- 1. feeds ---------------------------------------------------------------
if [ ! -d feeds/luci ] || [ ! -d feeds/istore ] || [ ! -d feeds/nas_luci ] \
   || [ ! -d feeds/diskman ] || [ ! -d feeds/istoreapps ] || [ ! -d feeds/mosdns ]; then
	echo "==> 拉取并安装 feed"
	./scripts/feeds update -a
	./scripts/feeds install -a
else
	echo "==> feed 已存在（要强制刷新就删掉 feeds/）"
fi

# --- 2. 打 iStoreOS 补丁 ----------------------------------------------------
# 补丁是架构无关的（LuCI 应用、Docker 配置、共享套件），两个目标共用同一套。
echo "==> 应用 iStoreOS 集成补丁"
./scripts/istoreos-merge.sh

# --- 3. 构建参数 ------------------------------------------------------------
echo "==> 应用构建参数"
./scripts/apply-build-options.sh

PART_SIZE="$(sed -n 's/^FANCHMWRT_ROOTFS_PARTSIZE=//p' .build-options 2>/dev/null | head -1)"
[ -n "$PART_SIZE" ] || PART_SIZE=1024

# --- 4. 配置 ----------------------------------------------------------------
#
# 只给目标与 rootfs 大小，其余（fwx 全家桶 + iStoreOS 面板/Docker/iStore +
# 磁盘与共享套件）由 include/target.mk 的 DEFAULT_PACKAGES 推导 ——
# 其中「本项目额外选中的包」那一块现在对 x86_64 **与 aarch64** 同时生效，
# 所以 ARM 版拿到的特性集与 x86 版一致。
#
# 设备符号 CONFIG_TARGET_rockchip_armv8_DEVICE_hinlink_ht2 是必须的：
# 不点它的话 defconfig 会把这个子目标下**所有**板子都选上，构建时间成倍增长。
#
# 这里不写 squashfs / ext4 / targz 那几个开关：rockchip 的产物形态由
# target/linux/rockchip/image/Makefile 决定，与 .config 无关
# （scripts/apply-build-options.sh 第 4 节也按同样理由只对 x86 生效）。
#
# ---------------------------------------------------------------------------
# 为什么不能只判「.config 在不在」
# ---------------------------------------------------------------------------
# 这个脚本与 build-merged-x86_64.sh **共用同一棵源码树**，也就共用同一个 .config。
# 只判存在的话，上一次编过 x86 留下的 .config 会被原样复用 —— 于是这个脚本
# 会拿着 x86 的配置一路编下去，并声称产物在 bin/targets/rockchip/armv8/。
#
# 这条路径其实已经被 apply-build-options.sh 挡住了（FANCHMWRT_TARGET 参与
# 「参数是否变化」的比较，换了目标就会删掉 .config），但那是**隔了一层**的
# 保护：它依赖 .build-options 里的记录与实际 .config 始终同步。
# 这里是**本地的**保护，直接看 .config 本身的目标符号，两者互不替代。
#
# 目标不对时要连 .config 一起删掉再重建，不能只重写内容再 make defconfig ——
# defconfig 只补缺失的符号，不覆盖已有值，旧目标那批 "# ... is not set" 会留下来。
if [ -f .config ] && ! grep -q '^CONFIG_TARGET_rockchip=y$' .config; then
	echo "==> 现有 .config 不是 rockchip 目标（上次编的多半是 x86），作废重建"
	cp .config .config.old
	rm -f .config
fi

if [ ! -f .config ]; then
	echo "==> 生成 .config（rockchip / armv8 / hinlink_ht2）"
	cat > .config <<EOF
CONFIG_TARGET_rockchip=y
CONFIG_TARGET_rockchip_armv8=y
CONFIG_TARGET_rockchip_armv8_DEVICE_hinlink_ht2=y
CONFIG_TARGET_KERNEL_PARTSIZE=16
CONFIG_TARGET_ROOTFS_PARTSIZE=$PART_SIZE
EOF
	make defconfig
fi

# --- 5. 断言 ----------------------------------------------------------------
# 与 x86 版同一份包集：目标不改变特性，只改变设备层。
MUST_HAVE="luci-theme-fanchmwrt luci-app-fwx-dashboard \
           luci-app-quickstart quickstart luci-app-store \
           luci-app-diskman luci-app-mosdns mosdns luci-app-ttyd ttyd \
           luci-app-nfs luci-app-mergerfs luci-app-unishare \
           build-defaults wsdd2 xz-utils uhttpd samba4-server"

# HT2 的设备层：驱动与固件。少了任何一个，对应批次的无线就上不来 ——
# 而现象是「网卡根本不出现」，不报错，很难查。
HT2_PKGS="kmod-brcmfmac brcmfmac-firmware-43752-sdio brcmfmac-nvram-43752-sdio \
          kmod-aic8800-sdio aic8800-sdio-firmware"
MUST_HAVE="$MUST_HAVE $HT2_PKGS"

DOCKER_PKGS="luci-app-dockerman dockerd docker docker-compose istoreos-merge"
DOCKER_ON="$(sed -n 's/^FANCHMWRT_ENABLE_DOCKER=//p' .build-options 2>/dev/null | head -1)"
if [ "$DOCKER_ON" = "1" ]; then
	MUST_HAVE="$MUST_HAVE $DOCKER_PKGS"
else
	MUST_NOT_HAVE="$MUST_NOT_HAVE $DOCKER_PKGS"
fi

MUST_NOT_HAVE="luci-app-ddns luci-app-hd-idle luci-app-samba4 \
               luci-app-uhttpd luci-app-upnp luci-app-wol $MUST_NOT_HAVE"

MISSING=""
for pkg in $MUST_HAVE; do
	grep -q "^CONFIG_PACKAGE_${pkg}=y" .config || MISSING="$MISSING $pkg"
done
if [ -n "$MISSING" ]; then
	echo "ERROR: 以下包没有出现在 .config 里：$MISSING" >&2
	echo "       拒绝继续构建。" >&2
	exit 1
fi

UNWANTED=""
for pkg in $MUST_NOT_HAVE; do
	grep -q "^CONFIG_PACKAGE_${pkg}=y" .config && UNWANTED="$UNWANTED $pkg"
done
if [ -n "$UNWANTED" ]; then
	echo "ERROR: 以下包本应被移除，却仍然启用：$UNWANTED" >&2
	echo "       多半是旧 .config 没重新生成 —— 删掉 .config 再跑一次。" >&2
	exit 1
fi

# 只构建 HT2 这一块板子。子目标下有别的设备被选上的话，构建时间会成倍增长，
# 产物里也会混进别人的镜像。
EXTRA_DEVICES="$(sed -n 's/^CONFIG_TARGET_rockchip_armv8_DEVICE_\(.*\)=y$/\1/p' .config \
                 | grep -v '^hinlink_ht2$' || true)"
if [ -n "$EXTRA_DEVICES" ]; then
	echo "ERROR: 除 hinlink_ht2 外还选中了别的 rockchip 设备：" >&2
	for d in $EXTRA_DEVICES; do echo "         $d" >&2; done
	echo "       只应构建 hinlink_ht2。删掉 .config 再跑一次。" >&2
	exit 1
fi

echo "==> .config 校验通过：$(echo $MUST_HAVE | wc -w) 个必需包已启用，$(echo $MUST_NOT_HAVE | wc -w) 个排除包确认未启用，且只选了 hinlink_ht2"

# 给 CI 用：只做到「准备就绪」，把下载和编译留给调用方分步执行。
if [ -n "$SKIP_BUILD" ]; then
	echo "==> SKIP_BUILD 已设置，停在准备阶段（feeds / 补丁 / 配置均已就绪）"
	exit 0
fi

# --- 6. 构建 ----------------------------------------------------------------
echo "==> 下载源码"
make -j"$JOBS" download || echo "WARNING: 部分下载失败，make 会重试"

echo "==> 开始构建（数小时）"
make -j"$JOBS" BUILD_LOG=1

echo
echo "==> 完成。镜像："
ls -1 bin/targets/rockchip/armv8/ 2>/dev/null | grep -E -- 'sysupgrade\.img\.gz$' || true
