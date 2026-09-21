#!/bin/sh
#
# 从构建产物核验合并结果。
#
# 直接读 bin/targets/x86/64/ 下的 *.manifest（包清单）与 *rootfs.tar.gz（文件内容），
# 不依赖真机。用法：
#
#   ./scripts/verify-merged-firmware.sh
#
set -u

TOPDIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$TOPDIR/bin/targets/x86/64"

PASS=0
FAIL=0
SKIP=0

ok()   { PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m  %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m  %s\n' "$*"; }
skip() { SKIP=$((SKIP+1)); printf '  \033[33mSKIP\033[0m  %s\n' "$*"; }
head_() { printf '\n== %s ==\n' "$*"; }

[ -d "$OUT" ] || { echo "找不到产物目录：$OUT" >&2; exit 1; }

MANIFEST="$(ls -1 "$OUT"/*.manifest 2>/dev/null | head -1)"
ROOTFS="$(ls -1 "$OUT"/*rootfs.tar.gz 2>/dev/null | head -1)"

[ -n "$MANIFEST" ] || { echo "找不到 .manifest" >&2; exit 1; }

# ---------------------------------------------------------------------------
head_ "包清单（$(basename "$MANIFEST")）"

# pkg_installed <包名>
# OpenWrt 的 .manifest 是 "包名 - 版本"（opkg 时代）或 "包名 版本"（apk 时代），两种都认。
pkg_installed() {
	grep -qE "^$1( -)? " "$MANIFEST" 2>/dev/null
}

# pkg_ver <包名>
pkg_ver() {
	awk -v p="$1" '$1==p {print $NF; exit}' "$MANIFEST"
}

check_pkg() {
	if pkg_installed "$1"; then
		ok "包 $1 ($(pkg_ver "$1"))"
	else
		bad "包 $1 不在清单里"
	fi
}

for p in base-files busybox firewall4 dnsmasq-full \
         luci-base luci-compat luci-lua-runtime \
         luci-theme-fanchmwrt \
         fwxd kmod-fwx libfwx_common \
         luci-app-fwx-dashboard luci-app-fwx-appfilter luci-app-fwx-feature \
         luci-app-fwx-macfilter luci-app-fwx-network luci-app-fwx-record \
         luci-app-fwx-resources luci-app-fwx-user luci-app-fwx-system \
         luci-app-fwx-wireless luci-app-fwx-traffic-stat luci-app-fwx-session-stat \
         luci-app-fwx-user-record luci-app-fwx-mac-blacklist \
         luci-app-fwx-record-whitelist \
         luci-app-fwx-dashboard-setting luci-app-fwx-app-center \
         luci-app-quickstart quickstart \
         luci-app-store taskd luci-lib-taskd luci-lib-xterm \
         luci-app-dockerman dockerd docker docker-compose \
         istoreos-merge \
         luci-app-diskman luci-app-hd-idle luci-app-samba4 luci-app-nfs \
         luci-app-mergerfs luci-app-unishare mergerfs unishare webdav2 wsdd2 \
         xz-utils ; do
	check_pkg "$p"
done

# fanchmwrt 的 DEFAULT_PACKAGES.router 里列了 luci-app-fwx-firewall，但
# feeds/fanchmwrt/ 里根本没有这个包 —— Kconfig 会静默忽略它（连
# "# ... is not set" 都不写）。这是上游 fanchmwrt 自带的悬空引用，
# 不是本次合并引入的，所以这里只作提示、不算失败。
if pkg_installed luci-app-fwx-firewall; then
	ok "luci-app-fwx-firewall 已装上（上游后来补了这个包）"
else
	printf '  \033[36mNOTE\033[0m  luci-app-fwx-firewall 不存在于 feeds/fanchmwrt，\n'
	printf '        这是上游 fanchmwrt 自带的悬空引用，本次合并未引入也未修复。\n'
fi

# ---------------------------------------------------------------------------
if [ -z "$ROOTFS" ]; then
	head_ "文件级核验"
	skip "没有 rootfs.tar.gz，跳过文件级核验"
else
	head_ "解开 rootfs 做文件级核验"
	WORK="$(mktemp -d)"
	trap 'rm -rf "$WORK"' EXIT
	tar -xzf "$ROOTFS" -C "$WORK" 2>/dev/null || { echo "解包失败" >&2; exit 1; }
	R="$WORK"

	# f <路径> <说明>
	f() {
		if [ -e "$R$1" ]; then ok "$2  ($1)"; else bad "$2 缺 $1"; fi
	}
	nf() {
		if [ -e "$R$1" ]; then bad "$2 不该存在：$1"; else ok "$2 已按预期移除 ($1)"; fi
	}
	g() {
		if [ -f "$R$1" ] && grep -q -- "$2" "$R$1" 2>/dev/null; then
			ok "$3"
		else
			bad "$3（$1 里没找到 '$2'）"
		fi
	}
	# gE <路径> <扩展正则> <说明>
	#
	# 用于 JS：LuCI 打包时会把 .js 交给 jsmin 压缩，空格会被吃掉，
	# 所以源码里的 "'store': 'store'" 到镜像里变成 "'store':'store'"。
	# 这类断言必须用容忍空白的正则，否则会得到假阴性。
	gE() {
		if [ -f "$R$1" ] && grep -qE -- "$2" "$R$1" 2>/dev/null; then
			ok "$3"
		else
			bad "$3（$1 里没匹配到 /$2/）"
		fi
	}

	head_ "fanchmwrt 侧：主题与仪表盘"
	f /www/luci-static/fanchmwrt/cascade.css            "主题样式"
	f /www/luci-static/fanchmwrt/icons/store.svg        "iStore 图标"
	f /www/luci-static/fanchmwrt/icons/quickstart.svg   "QuickStart 图标"
	f /www/luci-static/resources/menu-fanchmwrt.js      "主题菜单 JS"
	gE /www/luci-static/resources/menu-fanchmwrt.js "'store'[[:space:]]*:[[:space:]]*'store'" "菜单图标映射含 store（压缩后）"
	gE /www/luci-static/resources/menu-fanchmwrt.js "'quickstart'[[:space:]]*:[[:space:]]*'quickstart'" "菜单图标映射含 quickstart（压缩后）"
	gE /www/luci-static/resources/menu-fanchmwrt.js "normalizedName==='store'" "菜单归类含 store"
	gE /www/luci-static/resources/menu-fanchmwrt.js "normalizedName==='quickstart'" "菜单归类含 quickstart"
	g /www/luci-static/fanchmwrt/cascade.css ".menu-icon-store:before"     "CSS 含 .menu-icon-store"
	g /www/luci-static/fanchmwrt/cascade.css ".menu-icon-quickstart:before" "CSS 含 .menu-icon-quickstart"
	f /etc/uci-defaults/31_luci-theme-fanchmwrt        "主题默认项（默认主题=fanchmwrt）"

	head_ "fanchmwrt 侧：fwx 服务"
	f /usr/lib/lua/luci/controller/fwx_dashboard.lua   "仪表盘 controller"
	f /etc/init.d/fwx                                   "fwx 服务（fwxd 包把 init 脚本装成 /etc/init.d/fwx）"
	f /usr/bin/fwxd                                     "fwxd 守护进程"
	f /usr/lib/lua/luci/controller/fwx_app_center.lua  "fwx 应用中心 controller"
	g /usr/lib/lua/luci/controller/fwx_dashboard.lua 'entry({"admin", "fwx_dashboard"}' "仪表盘注册在 admin 下"
	g /usr/lib/lua/luci/controller/fwx_dashboard.lua ', 1)' "仪表盘 order 为 1"

	head_ "iStoreOS 侧：QuickStart 面板"
	f /usr/sbin/quickstart                              "quickstart 后端"
	f /etc/init.d/quickstart                            "quickstart 服务"
	f /usr/lib/lua/luci/controller/quickstart.lua       "quickstart controller"
	f /www/luci-static/quickstart/index.js              "面板前端"
	g /usr/share/luci/menu.d/luci-app-quickstart.json '"order": 2' "菜单序号已让位到 2（首页留给仪表盘）"

	head_ "iStoreOS 侧：Docker"
	f /usr/bin/dockerd                                  "dockerd"
	f /usr/bin/docker                                   "docker cli"
	f /etc/init.d/dockerd                               "dockerd 服务"
	f /etc/config/dockerd                               "dockerd 配置"
	g /etc/config/dockerd "option iptables '0'"         "docker 自己的 iptables 已默认关闭"
	f /etc/hotplug.d/net/10-docker-br-netfilter         "br-netfilter 按需开启脚本"
	f /etc/uci-defaults/16_docker-netifd-migrate        "netifd 迁移脚本"
	f /etc/uci-defaults/17_docker-fw4                   "fw4 zone/forwarding 脚本"
	f /lib/fstab.d/dockerd.sh                           "data_root essential mountpoint"
	nf /etc/sysctl.d/12-br-netfilter-ip.conf            "旧的全局 br-netfilter sysctl"
	f /etc/uci-defaults/99_docker_nat_fw4               "docker 出网 NAT 规则"
	f /etc/uci-defaults/20_docker_data_root             "squashfs 上的 data_root 落点"
	f /usr/share/luci/menu.d/luci-app-dockerman.json    "Dockerman 菜单"
	f /usr/share/rpcd/ucode/docker_rpc.uc               "Dockerman RPC 后端"
	f /www/luci-static/resources/view/dockerman/overview.js "Dockerman 概览页"

	head_ "iStoreOS 侧：iStore 商店"
	f /usr/lib/lua/luci/controller/store.lua            "iStore controller"
	f /etc/init.d/istore                                "iStore 服务"
	f /etc/config/istore                                "iStore 配置"
	f /usr/libexec/istore/backup                        "iStore 备份脚本"
	f /bin/is-opkg                                      "iStore 的 opkg 兼容层"
	if [ -d "$R/www/luci-static/istore" ]; then ok "iStore 前端资源"; else bad "iStore 前端资源缺 /www/luci-static/istore"; fi
	f /usr/libexec/taskd                                "taskd 后端"
	f /etc/init.d/tasks                                 "taskd 服务脚本"

	head_ "磁盘与共享套件"
	f /usr/lib/lua/luci/controller/diskman.lua          "DiskMan controller"
	f /usr/bin/mergerfs                                  "mergerfs"
	f /usr/sbin/smbd                                     "samba4-server"
	f /usr/bin/wsdd2                                     "wsdd2"
	f /usr/sbin/webdav2                                  "webdav2"
	f /usr/lib/lua/luci/controller/nfs.lua               "luci-app-nfs controller"
	f /usr/sbin/rpc.nfsd                                 "nfs-kernel-server"
	f /etc/init.d/hd-idle                                "hd-idle 服务"
	f /etc/init.d/unishare                               "unishare 服务"

	head_ "运行时健全性"
	f /bin/busybox                                       "busybox"
	f /usr/lib/lua/luci/dispatcher.lua                   "LuCI Lua dispatcher"
	[ -x "$R/bin/busybox" ] && ok "busybox 可执行位正常" || bad "busybox 无执行位"
fi

# ---------------------------------------------------------------------------
head_ "结果"
printf '  通过 %d，失败 %d，跳过 %d\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
