#!/bin/sh
#
# 把 iStoreOS 侧的改动打到 feed 检出上。
#
# 为什么用补丁而不是 feeds_patches/：
#   feeds_patches/ 是整文件覆盖（`cp -fr`），一旦上游随后修了同一个文件，
#   旧副本会把上游修复静默回退掉。这里用定点补丁，锚点对不上就显式报错中止，
#   而不是产出一份错误的固件。
#
# 幂等：正向 / 反向各试一次 dry-run，已打过就跳过；两边都不匹配则报错退出。
# 由顶层 Makefile 的 fwx_init 调用，因此每次 make 都会重新确认。
#
set -e

TOPDIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TOPDIR"

PATCH_DIR="$TOPDIR/merge-patches"

say() { printf '%s\n' "istoreos-merge: $*"; }
err() { printf '%s\n' "istoreos-merge: ERROR: $*" >&2; }

# apply_patch <补丁文件> <目标目录>
apply_patch() {
	patch_file="$1"
	target_dir="$2"

	[ -f "$patch_file" ] || { err "补丁不存在：$patch_file"; return 1; }
	[ -d "$target_dir" ] || { err "目标目录不存在：$target_dir"; return 1; }

	# 已经打过？
	if patch -p1 -R --dry-run -s -f -d "$target_dir" < "$patch_file" >/dev/null 2>&1; then
		say "已应用，跳过：${patch_file##*/} -> ${target_dir#$TOPDIR/}"
		return 0
	fi

	# 可以打？
	if patch -p1 --dry-run -s -f -d "$target_dir" < "$patch_file" >/dev/null 2>&1; then
		patch -p1 -E -s -d "$target_dir" < "$patch_file"
		say "已应用：${patch_file##*/} -> ${target_dir#$TOPDIR/}"
		return 0
	fi

	err "${patch_file##*/} 在 ${target_dir#$TOPDIR/} 上既不匹配正向也不匹配反向。"
	err "多半是上游改了同一处代码 —— 请人工核对后更新该补丁，不要强行继续构建。"
	return 1
}

# ---------------------------------------------------------------------------
# 1. dockerd：iStoreOS（jjm2473/packages 分支 istoreos-25.12）对上游 dockerd
#    的改动。上游 pin 的 dockerd 版本与 iStoreOS 完全相同（27.3.1），
#    差异纯粹是 iStoreOS 的定制：
#      * 默认关闭 docker 自己的 iptables，交给 fw4 管
#      * 不再把 docker0 注册成 netifd 接口，firewall 里直接挂 device/subnet
#      * 给 docker 网络开 br-netfilter（仅在 iptables 开启时）
#      * 自动建立 docker<->wan/lan 的 forwarding，并加 172.16.0.0/12 的 NAT 规则
#      * data_root 变化时重启 dockerd；限制容器日志大小为 50m x 2
#      * 挂到 fstab.d，保证 data_root 一定被挂载
# ---------------------------------------------------------------------------
apply_patch "$PATCH_DIR/0001-dockerd-istoreos.patch" \
	"$TOPDIR/feeds/packages/utils/dockerd"

# ---------------------------------------------------------------------------
# 2. luci-app-quickstart：菜单序号 1 -> 2。
#
# 本固件的首页是 fanchmwrt 的 fwx 仪表盘，它在 controller 里注册的 order 也是 1。
# LuCI 的 resolve_firstchild() 只按 order 取最小者，相等时保留先插入的那个，
# 也就是取决于菜单扫描顺序 —— 那样首页会变得不确定。把 QuickStart 让到 2，
# 仪表盘就成为严格最小，首页稳定落在仪表盘上，面板紧随其后排在第二位。
# ---------------------------------------------------------------------------
apply_patch "$PATCH_DIR/0002-quickstart-menu-order.patch" \
	"$TOPDIR/feeds/nas_luci"

# ---------------------------------------------------------------------------
# 3. v2ray-geodata：改用滚动 release，避免构建在某天突然卡死。
#
# 这个包不编译代码，只是下载 geoip/geosite 两个 DNS 分流规则数据文件。
# 上游 v2fly 走的是「滚动发布 + 定期删除旧 tag」：
#   v2fly/geoip                   保留约一年
#   v2fly/domain-list-community   只保留约三个月（实测 571 个 release）
# packages feed pin 的 20260326050832 已经 404，构建会在这里失败。
# 改用 releases/latest/download 之后地址永不失效；代价是这两个数据文件
# 不再做哈希校验（HASH:=skip）。
#
# mosdns 及其 LuCI 界面依赖这两个数据包，所以这一步是必需的。
# ---------------------------------------------------------------------------
apply_patch "$PATCH_DIR/0003-v2ray-geodata-rolling-releases.patch" \
	"$TOPDIR/feeds/packages"

exit 0
