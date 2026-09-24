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
# 读取构建参数：Docker 是可选项，它开着和关着要核验的东西正好相反。
# 文件不存在（比如直接拿别人给的 manifest 来验）时按「含 Docker」处理。
DOCKER_ON="$(sed -n 's/^FANCHMWRT_ENABLE_DOCKER=//p' "$TOPDIR/.build-options" 2>/dev/null | head -1)"
[ -n "$DOCKER_ON" ] || DOCKER_ON=1

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

MUST_HAVE_PKGS="base-files busybox firewall4 dnsmasq-full \
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
         luci-app-mosdns mosdns geo2txt \
         luci-app-ttyd ttyd \
         build-defaults \
         luci-app-diskman luci-app-nfs \
         luci-app-mergerfs luci-app-unishare mergerfs unishare webdav2 wsdd2 \
         xz-utils \
         uhttpd uhttpd-mod-ubus samba4-server"

DOCKER_PKGS="luci-app-dockerman dockerd docker docker-compose containerd runc istoreos-merge"

if [ "$DOCKER_ON" = "1" ]; then
	MUST_HAVE_PKGS="$MUST_HAVE_PKGS $DOCKER_PKGS"
fi

for p in $MUST_HAVE_PKGS; do
	check_pkg "$p"
done

# ---------------------------------------------------------------------------
head_ "确认已排除的包确实不在固件里"

# check_absent <包名> <说明>
check_absent() {
	if pkg_installed "$1"; then
		bad "$1 仍在固件里（$2）"
	else
		ok "$1 已排除（$2）"
	fi
}

check_absent luci-app-ddns   "本项目不需要 DDNS"
check_absent luci-app-hd-idle "本项目不需要硬盘休眠"
check_absent luci-app-wol    "本项目不需要网络唤醒"
check_absent luci-app-upnp   "本项目不需要 UPnP"
check_absent luci-app-uhttpd "只需要 uhttpd 本体，不需要它的配置界面"
check_absent luci-app-samba4 "只需要 samba4-server（unishare 依赖），不需要它的配置界面"

# Docker 是可选项：这次构建把它关掉了，就反过来确认整条链都不在。
if [ "$DOCKER_ON" != "1" ]; then
	for p in $DOCKER_PKGS; do
		check_absent "$p" "本次构建选择了不含 Docker"
	done
	# 关掉 Docker 不该影响 Web 终端：luci-app-ttyd 自带 +ttyd 依赖。
	if pkg_installed ttyd && pkg_installed luci-app-ttyd; then
		ok "ttyd 未受 Docker 关闭影响（luci-app-ttyd 自带 +ttyd 依赖）"
	else
		bad "关闭 Docker 后 ttyd 被误删 —— luci-app-ttyd 会缺依赖"
	fi
fi

# 顺带确认这两个"界面没了但本体还在"的包没有被连带删掉。
if pkg_installed uhttpd; then
	ok "uhttpd 本体仍在（由 luci-light 依赖，未受 luci-app-uhttpd 移除影响）"
else
	bad "uhttpd 本体被误删 —— Web 管理界面会不可用！"
fi
if pkg_installed samba4-server; then
	ok "samba4-server 仍在（由 unishare 依赖，未受 luci-app-samba4 移除影响）"
else
	bad "samba4-server 被误删 —— unishare 会缺依赖"
fi

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
# 文件级核验需要一个「能解开的 rootfs」。优先用 rootfs.tar.gz；
# 本项目为了只出 4 个镜像把 TARGZ 关掉了（连带没有 rootfs.tar.gz），
# 这时退回到 squashfs-rootfs.img.gz —— 它由 x86 的 IMAGES-y 无条件产出，
# 而且解出来的文件清单与 rootfs.tar.gz 逐一对得上（已实测 2760/2760 一致）。
if [ -z "$ROOTFS" ]; then
	SQUASHFS_ROOTFS="$(ls -1 "$OUT"/*-squashfs-rootfs.img.gz 2>/dev/null | head -1)"
	if [ -n "$SQUASHFS_ROOTFS" ]; then
		ROOTFS="$SQUASHFS_ROOTFS"
		ROOTFS_KIND="squashfs"
	fi
fi

if [ -z "$ROOTFS" ]; then
	head_ "文件级核验"
	skip "既没有 rootfs.tar.gz 也没有 squashfs-rootfs.img.gz，跳过文件级核验"
else
	WORK="$(mktemp -d)"
	trap 'rm -rf "$WORK"' EXIT

	if [ "${ROOTFS_KIND:-tar}" = "squashfs" ]; then
		head_ "从 squashfs-rootfs 镜像解出 rootfs 做文件级核验"
		gunzip -c "$ROOTFS" > "$WORK/rootfs.squashfs" 2>/dev/null \
			|| { echo "解压 $ROOTFS 失败" >&2; exit 1; }
		# unsquashfs 对「squashfs 后面还跟着 pad-to 补的零」会返回 2，
		# 但内容其实是完整的 —— 所以不看退出码，改用哨兵文件判断。
		unsquashfs -q -d "$WORK/x" "$WORK/rootfs.squashfs" >/dev/null 2>&1
		R="$WORK/x"
		if [ ! -e "$R/bin/busybox" ] || [ ! -e "$R/etc/openwrt_release" ]; then
			echo "从 squashfs 镜像解出的 rootfs 不完整（缺 busybox 或 openwrt_release）" >&2
			exit 1
		fi
		rm -f "$WORK/rootfs.squashfs"
	else
		head_ "解开 rootfs.tar.gz 做文件级核验"
		mkdir -p "$WORK/x"
		tar -xzf "$ROOTFS" -C "$WORK/x" 2>/dev/null || { echo "解包失败" >&2; exit 1; }
		R="$WORK/x"
	fi

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
	g /www/luci-static/fanchmwrt/cascade.css ".menu-icon-store:before"     "CSS 含 .menu-icon-store"
	g /www/luci-static/fanchmwrt/cascade.css ".menu-icon-quickstart:before" "CSS 含 .menu-icon-quickstart"
	f /etc/uci-defaults/31_luci-theme-fanchmwrt        "主题默认项（默认主题=fanchmwrt）"

	# 菜单归类：只有 fwx* 进「普通模式」，其余（含 store / quickstart）一律高级模式。
	#
	# 这一条曾经写成「store / quickstart 应被特判进普通模式」——那是错的：
	# render() 会用当前页面所属分类去 switchCategory()，也就是点哪个页面、
	# 整个菜单就切到那个分类。它们若归普通模式，人在高级模式点一下 iStore，
	# 菜单会整体跳回普通模式。所以这里要断言的是**没有**特判。
	gE /www/luci-static/resources/menu-fanchmwrt.js "startsWith\('fwx'\)" "菜单归类：fwx* 进普通模式"
	for name in store quickstart; do
		if grep -qE "normalizedName[[:space:]]*===[[:space:]]*'$name'" \
			"$R/www/luci-static/resources/menu-fanchmwrt.js" 2>/dev/null; then
			bad "$name 被特判（它应当落在默认分支＝高级模式）"
		else
			ok "$name 未被特判，归高级模式"
		fi
	done

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

	if [ "$DOCKER_ON" = "1" ]; then
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
	else
	head_ "iStoreOS 侧：Docker（本次构建已关闭）"
	if [ -e "$R/usr/bin/dockerd" ] || [ -e "$R/etc/init.d/dockerd" ]; then
		bad "Docker 已关闭，但固件里仍有 dockerd"
	else
		ok "Docker 相关文件确认未打包"
	fi
	if [ -e "$R/etc/uci-defaults/99_docker_nat_fw4" ] || [ -e "$R/etc/uci-defaults/20_docker_data_root" ]; then
		bad "Docker 已关闭，但 istoreos-merge 的 uci-defaults 仍在"
	else
		ok "istoreos-merge 的 uci-defaults 确认未打包"
	fi
	fi

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
	f /etc/init.d/unishare                               "unishare 服务"

	head_ "DNS 与终端"
	# mosdns 只有二进制（GoPackage 安装），init 脚本与 /etc/config/mosdns
	# 都由 luci-app-mosdns 提供 —— 两个包必须同时在。
	f /usr/bin/mosdns                                    "mosdns 主程序"
	f /etc/init.d/mosdns                                 "mosdns 服务（由 luci-app-mosdns 提供）"
	f /etc/config/mosdns                                 "mosdns 配置"
	f /usr/share/luci/menu.d/luci-app-mosdns.json        "mosdns 菜单"
	f /usr/share/rpcd/ucode/luci.mosdns                  "mosdns RPC 后端"
	f /usr/share/mosdns/mosdns.uc                        "mosdns ucode 模块"
	if [ -d "$R/etc/mosdns/rule" ]; then ok "mosdns 规则目录"; else bad "mosdns 规则目录缺失"; fi
	f /usr/bin/geo2txt                                   "geo2txt 数据转换工具"
	f /usr/bin/ttyd                                      "ttyd 终端"
	f /etc/init.d/ttyd                                   "ttyd 服务"
	f /usr/share/luci/menu.d/luci-app-ttyd.json          "luci-app-ttyd 菜单"

	head_ "构建参数（build-defaults）"
	f /etc/build-options                                 "构建参数记录 /etc/build-options"
	BUILD_LAN_IP="$(sed -n 's/^FANCHMWRT_LAN_IP=//p' "$TOPDIR/.build-options" 2>/dev/null | head -1)"
	if [ -n "$BUILD_LAN_IP" ]; then
		if [ -f "$R/etc/uci-defaults/25_lan_ip" ]; then
			ok "管理地址 uci-defaults 已打包（$BUILD_LAN_IP）"
			# 必须用 add_list：config_generate 生成的是 list，
			# 写成标量会同时留下新旧两个地址。
			g /etc/uci-defaults/25_lan_ip "add_list network.lan.ipaddr=" "用 add_list 写入（与 config_generate 的 list 形式一致）"
			g /etc/uci-defaults/25_lan_ip "$BUILD_LAN_IP" "地址值与构建参数一致"
		else
			bad "构建参数里指定了管理地址 $BUILD_LAN_IP，但固件里没有对应的 uci-defaults"
		fi
	else
		skip "本次构建未指定管理地址，按预期没有 25_lan_ip"
	fi

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
