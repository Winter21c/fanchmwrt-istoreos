#!/bin/sh
#
# 构建合并后的 fanchmwrt + iStoreOS x86_64 固件。
#
# 产物在 bin/targets/x86/64/。
#
# 用法:  ./build-merged-x86_64.sh [jobs]
#
# 这个脚本只是把下面几步串起来；同样的 .config 手工敲一遍也能得到一样的结果。
#
set -e

TOPDIR="$(cd "$(dirname "$0")" && pwd)"
cd "$TOPDIR"

JOBS="${1:-$(nproc)}"

# 慢镜像保护。
#
# scripts/download.pl 会把 CURL_OPTIONS 拼进每一次 curl 调用，并逐个镜像重试。
# 裸 curl 没有速率下限，一个「能用但极慢」的镜像会把 make download 永久挂住，
# 而不是自动换下一个。cdn.kernel.org 在本机实测约 20 KB/s，曾把 kernel 与
# 611 MB 的 linux-firmware 两个包卡死。让平均速率连续 60 秒低于 50 KB/s 就
# 放弃该镜像，交给 download.pl 换下一个；全都慢则快速失败报错，而不是挂几小时。
export CURL_OPTIONS="${CURL_OPTIONS:---speed-limit 51200 --speed-time 60}"

# 目标标识：apply-build-options.sh 与 verify-merged-firmware.sh 都读它，
# 用来决定「哪些与产物形态相关的开关该动」。
#
# 它还会被写进 .build-options，参与「构建参数是否变化」的比较 ——
# 这一点很关键：从 HT2 切回 x86 时不作废 tmp/ 的 Kconfig 元数据，
# 会复用到另一个架构的 DEFAULT_PACKAGES。详见 apply-build-options.sh 第 5 节。
export FANCHMWRT_TARGET="x86_64"

echo "==> 合并树 : $TOPDIR"
echo "==> 目标   : x86_64"
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
# 幂等；锚点对不上会显式报错中止。make 的 fwx_init 也会跑一次，
# 这里提前跑是为了让下面第 3 步的校验反映真实状态。
echo "==> 应用 iStoreOS 集成补丁"
./scripts/istoreos-merge.sh

# --- 3. 构建参数 ------------------------------------------------------------
# 把 LAN_IP / ROOTFS_PARTSIZE / ENABLE_DOCKER 落成树里的具体改动
# （.build-options + 一个 uci-defaults）。不传则全部用默认值，
# 也就是和之前完全一样的行为。
echo "==> 应用构建参数"
./scripts/apply-build-options.sh

# 分区大小以脚本解析后的值为准（它已经做过范围校验）。
PART_SIZE="$(sed -n 's/^FANCHMWRT_ROOTFS_PARTSIZE=//p' .build-options 2>/dev/null | head -1)"
[ -n "$PART_SIZE" ] || PART_SIZE=1024

# --- 4. 配置 ----------------------------------------------------------------
# 只给目标、rootfs 大小与镜像类型，其余（fanchmwrt 的 fwx 全家桶 +
# iStoreOS 的面板/Docker/iStore + 磁盘与共享套件）都由 include/target.mk
# 的 DEFAULT_PACKAGES 推导出来。
#
# TARGZ 显式关掉：它同时控制 -targz-* 三个镜像和 rootfs.tar.gz，
# 而本项目只出 squashfs / ext4 各两种（efi 与非 efi）共 4 个镜像。
# 见 include/image.mk 的 fs-types-$(CONFIG_TARGET_ROOTFS_TARGZ)。
#
# ---------------------------------------------------------------------------
# 为什么不能只判「.config 在不在」
# ---------------------------------------------------------------------------
# 这个脚本与 build-merged-ht2.sh **共用同一棵源码树**，也就共用同一个 .config。
# 只判存在的话，上一次编过 HT2 留下的 rockchip 配置会被原样复用 —— 这个脚本
# 会拿着 aarch64 的配置编下去，最后去 bin/targets/x86/64/ 找产物，什么也找不到。
#
# apply-build-options.sh 其实已经挡住了这条路（FANCHMWRT_TARGET 参与「参数是否
# 变化」的比较），但那是隔了一层、依赖 .build-options 与实际 .config 同步的保护。
# 这里直接看 .config 本身的目标符号，两者互不替代。
#
# 目标不对时要连 .config 一起删掉再重建：defconfig 只补缺失的符号、不覆盖已有值，
# 旧目标那批 "# ... is not set" 会留下来，混出一份四不像的配置。
if [ -f .config ] && ! grep -q '^CONFIG_TARGET_x86_64=y$' .config; then
	echo "==> 现有 .config 不是 x86_64 目标（上次编的多半是 HT2），作废重建"
	cp .config .config.old
	rm -f .config
fi

if [ ! -f .config ]; then
	echo "==> 生成 .config"
	cat > .config <<EOF
CONFIG_TARGET_x86=y
CONFIG_TARGET_x86_64=y
CONFIG_TARGET_x86_64_DEVICE_generic=y
CONFIG_TARGET_ROOTFS_PARTSIZE=$PART_SIZE
CONFIG_TARGET_ROOTFS_SQUASHFS=y
CONFIG_TARGET_ROOTFS_EXT4FS=y
# CONFIG_TARGET_ROOTFS_TARGZ is not set
EOF
	make defconfig
fi

# 集成要是没活过依赖解析，就在这里失败，而不是编出一个缺东西的固件。
MUST_HAVE="luci-theme-fanchmwrt luci-app-fwx-dashboard \
           luci-app-quickstart quickstart luci-app-store \
           luci-app-diskman luci-app-mosdns mosdns luci-app-ttyd ttyd \
           luci-app-nfs luci-app-mergerfs luci-app-unishare \
           build-defaults wsdd2 xz-utils uhttpd samba4-server"

# 关掉 Docker 时这些必须不在；开着的时候下面再补进 MUST_HAVE。
DOCKER_PKGS="luci-app-dockerman dockerd docker docker-compose istoreos-merge"
DOCKER_ON="$(sed -n 's/^FANCHMWRT_ENABLE_DOCKER=//p' .build-options 2>/dev/null | head -1)"
if [ "$DOCKER_ON" = "1" ]; then
	MUST_HAVE="$MUST_HAVE $DOCKER_PKGS"
else
	MUST_NOT_HAVE="$MUST_NOT_HAVE $DOCKER_PKGS"
fi

# 这些是本项目明确不要的（见 include/target.mk 的移除块）。
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

echo "==> .config 校验通过：$(echo $MUST_HAVE | wc -w) 个必需包已启用，$(echo $MUST_NOT_HAVE | wc -w) 个排除包确认未启用"

# 给 CI 用：只做到"准备就绪"，把下载和编译留给调用方分步执行，
# 这样 GitHub Actions 里每一步都有独立的日志与重试边界。
if [ -n "$SKIP_BUILD" ]; then
	echo "==> SKIP_BUILD 已设置，停在准备阶段（feeds / 补丁 / 配置均已就绪）"
	exit 0
fi

# --- 5. 构建 ----------------------------------------------------------------
echo "==> 下载源码"
make -j"$JOBS" download || echo "WARNING: 部分下载失败，make 会重试"

echo "==> 开始构建（数小时）"
make -j"$JOBS" BUILD_LOG=1

echo
echo "==> 完成。镜像："
ls -1 bin/targets/x86/64/ 2>/dev/null | grep -E -- '-((squashfs|ext4)-combined(-efi)?)\.img\.gz$' || true
