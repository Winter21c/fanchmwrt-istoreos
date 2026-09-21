#!/bin/sh
#
# 把「构建参数」落成源码树里的具体改动。
#
# 支持的参数（环境变量）：
#
#   LAN_IP            管理地址，可带前缀长度。
#                     例：192.168.1.1 / 10.0.0.1/16 / 192.168.100.1/24
#                     不给则保持 FanchmWrt 原默认（192.168.1.1）。
#
#   ROOTFS_PARTSIZE   rootfs 分区大小，单位 MB。不给则 1024。
#                     这个值同时写进 .config 的 CONFIG_TARGET_ROOTFS_PARTSIZE。
#
#   ENABLE_DOCKER     是否包含 Docker（dockerd / docker / docker-compose /
#                     Dockerman 界面 / istoreos-merge）。默认 1。
#                     接受 1/0、true/false、yes/no、on/off。
#
# 产出：
#
#   .build-options                                    make 片段，供 include/target.mk 读取
#   package/build-defaults/files/etc/uci-defaults/25_lan_ip
#                                                     首次启动时套用管理地址
#
# 这两个产物都是生成物，已在 .gitignore 里排除。
#
set -e

TOPDIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TOPDIR"

OPTIONS_FILE="$TOPDIR/.build-options"
UCI_DIR="$TOPDIR/package/build-defaults/files/etc/uci-defaults"
UCI_FILE="$UCI_DIR/25_lan_ip"

say() { printf '%s\n' "build-options: $*"; }
die() { printf '%s\n' "build-options: ERROR: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 1. 解析与校验
# ---------------------------------------------------------------------------

# --- 管理 IP ---
LAN_IP_RAW="${LAN_IP:-}"
LAN_IP=""
if [ -n "$LAN_IP_RAW" ]; then
	# 允许 "IP" 或 "IP/前缀"
	IP_PART="${LAN_IP_RAW%%/*}"
	PREFIX_PART=""
	case "$LAN_IP_RAW" in
		*/*) PREFIX_PART="${LAN_IP_RAW##*/}" ;;
	esac

	# 必须是点分四段的 IPv4，每段 0-255
	OLD_IFS="$IFS"; IFS=.
	# shellcheck disable=SC2086
	set -- $IP_PART
	IFS="$OLD_IFS"
	[ $# -eq 4 ] || die "管理 IP 不是合法的 IPv4：'$LAN_IP_RAW'"
	for octet in "$@"; do
		case "$octet" in
			''|*[!0-9]*) die "管理 IP 含非数字段：'$LAN_IP_RAW'" ;;
		esac
		[ "$octet" -le 255 ] || die "管理 IP 的段超过 255：'$LAN_IP_RAW'"
	done

	if [ -n "$PREFIX_PART" ]; then
		case "$PREFIX_PART" in
			''|*[!0-9]*) die "前缀长度不是数字：'$LAN_IP_RAW'" ;;
		esac
		[ "$PREFIX_PART" -ge 1 ] && [ "$PREFIX_PART" -le 32 ] \
			|| die "前缀长度必须在 1-32 之间：'$LAN_IP_RAW'"
		LAN_IP="$IP_PART/$PREFIX_PART"
	else
		LAN_IP="$IP_PART/24"
	fi
	say "管理地址：$LAN_IP"
else
	say "管理地址：未指定，保持 FanchmWrt 默认（192.168.1.1）"
fi

# --- 分区大小 ---
ROOTFS_PARTSIZE="${ROOTFS_PARTSIZE:-1024}"
case "$ROOTFS_PARTSIZE" in
	''|*[!0-9]*) die "rootfs 分区大小不是数字：'$ROOTFS_PARTSIZE'" ;;
esac
# 下限 256MB：再小放不下 squashfs + overlay；
# 上限 65536MB（64GB）：再大不如用 ext4 整盘装。
[ "$ROOTFS_PARTSIZE" -ge 256 ] || die "rootfs 分区太小（$ROOTFS_PARTSIZE MB），至少 256"
[ "$ROOTFS_PARTSIZE" -le 65536 ] || die "rootfs 分区太大（$ROOTFS_PARTSIZE MB），最多 65536"
say "rootfs 分区：${ROOTFS_PARTSIZE} MB"

# --- Docker 开关 ---
# 空值代表「没传」（比如 push 触发时没有 inputs），用默认值。
case "$(printf '%s' "${ENABLE_DOCKER:-}" | tr 'A-Z' 'a-z')" in
	'')            ENABLE_DOCKER=1 ;;
	1|true|yes|on) ENABLE_DOCKER=1 ;;
	0|false|no|off) ENABLE_DOCKER=0 ;;
	*) die "ENABLE_DOCKER 只能是 1/0、true/false、yes/no、on/off，收到：'$ENABLE_DOCKER'" ;;
esac
if [ "$ENABLE_DOCKER" = "1" ]; then
	say "Docker：包含"
else
	say "Docker：不含（会去掉 dockerd / docker / docker-compose / Dockerman / istoreos-merge）"
fi

# ---------------------------------------------------------------------------
# 2. 写 make 片段，供 include/target.mk 读取
# ---------------------------------------------------------------------------
TMP_OPT="$(mktemp)"
cat > "$TMP_OPT" <<EOF
# 由 scripts/apply-build-options.sh 生成 —— 不要手工编辑，改了会被下次构建覆盖。
#
# include/target.mk 用 -include 读它；文件不存在时用代码里的默认值。
#
# 格式说明：用普通的 VAR=VALUE（而不是 make 的 VAR:=VALUE），
# 这样 shell 侧 sed 's/^VAR=//' 就能直接取值 —— 本文件同时被
# build-merged-x86_64.sh / verify-merged-firmware.sh / CI 工作流解析。
# make 对 VAR=VALUE 一样接受。
FANCHMWRT_ENABLE_DOCKER=$ENABLE_DOCKER
FANCHMWRT_LAN_IP=$LAN_IP
FANCHMWRT_ROOTFS_PARTSIZE=$ROOTFS_PARTSIZE
EOF

OPTIONS_CHANGED=0
CHANGE_REASON=""
if [ ! -f "$OPTIONS_FILE" ]; then
	# 首次生成也算「变化」。这一条不能省：
	# scripts/feeds install -a 自己会跑 make，从而生成 tmp/ 里的 Kconfig
	# 元数据 —— 而那时候 .build-options 还不存在、Docker 取的是默认值 1。
	# 如果这里不把 tmp/ 作废，后面 make defconfig 会直接复用那批过期元数据，
	# 结果是「参数选了不含 Docker，固件里却仍然有 Docker」。
	OPTIONS_CHANGED=1
	CHANGE_REASON="首次生成构建参数"
elif ! cmp -s "$TMP_OPT" "$OPTIONS_FILE"; then
	OPTIONS_CHANGED=1
	CHANGE_REASON="构建参数有变化"
fi
mv "$TMP_OPT" "$OPTIONS_FILE"
say "已写入 $OPTIONS_FILE"

# ---------------------------------------------------------------------------
# 3. 生成首次启动套用管理地址的 uci-defaults
#
# 为什么用 uci-defaults 而不是改 bin/config_generate：
# config_generate 在首次启动时才生成 /etc/config/network，uci-defaults
# 紧随其后执行、且在 network 服务启动之前，所以在这里改既生效又不必去动
# base-files 的核心脚本。
#
# 顺带一提：FanchmWrt 的 fwx_cli.sh 在「没有 WAN 口」时会把 LAN 改成 DHCP
# 进旁路模式，但它是从 /usr/libexec/login.sh 调用的 —— 也就是只在
# 串口/VGA 控制台登录时才会跑。无头机器上这里设的静态地址会一直保持。
# ---------------------------------------------------------------------------
FILES_DIR="$TOPDIR/package/build-defaults/files"
rm -f "$UCI_FILE"
if [ -n "$LAN_IP" ]; then
	mkdir -p "$UCI_DIR"
	cat > "$UCI_FILE" <<EOF
#!/bin/sh
#
# 由 scripts/apply-build-options.sh 按构建参数生成 —— 不要手工编辑。
# 重新构建时本文件会被删除重建。
#
# config_generate 已经把 network.lan.ipaddr 生成成了 list，所以这里要
# 先 delete 再 add_list，否则会同时留下两个地址。
#
uci -q batch <<-UCIEOF
	delete network.lan.ipaddr
	set network.lan.proto='static'
	add_list network.lan.ipaddr='$LAN_IP'
	commit network
UCIEOF

exit 0
EOF
	chmod 755 "$UCI_FILE"
	say "已生成 $UCI_FILE"
else
	say "未指定管理地址，不生成 uci-defaults（保持原默认）"
fi

# ---------------------------------------------------------------------------
# 3b. 记录本次构建用的参数，装进固件的 /etc/build-options
#
# 排查问题时最常问的就是「这台机器刷的是哪一版、当时选了什么」，
# 与其去翻 CI 日志，不如直接在设备上留一份。
# ---------------------------------------------------------------------------
mkdir -p "$FILES_DIR/etc"
cat > "$FILES_DIR/etc/build-options" <<EOF
# 本次构建使用的参数，由 scripts/apply-build-options.sh 写入。
# 想改这些值就改 include/target.mk 或重新构建。
LAN_IP=${LAN_IP:-（未指定，使用 FanchmWrt 默认 192.168.1.1）}
ROOTFS_PARTSIZE=$ROOTFS_PARTSIZE
ENABLE_DOCKER=$ENABLE_DOCKER
EOF
say "已生成 $FILES_DIR/etc/build-options"

# ---------------------------------------------------------------------------
# 4. 如果 .config 已存在，同步分区大小
#
# 没有 .config 时由 build-merged-x86_64.sh 的种子负责写入。
# 只改这一行，不动其它任何配置。
# ---------------------------------------------------------------------------
if [ -f "$TOPDIR/.config" ]; then
	CUR="$(sed -n 's/^CONFIG_TARGET_ROOTFS_PARTSIZE="\?\([0-9]*\)"\?$/\1/p' "$TOPDIR/.config" | head -1)"
	if [ "$CUR" != "$ROOTFS_PARTSIZE" ]; then
		sed -i '/^CONFIG_TARGET_ROOTFS_PARTSIZE=/d' "$TOPDIR/.config"
		printf 'CONFIG_TARGET_ROOTFS_PARTSIZE=%s\n' "$ROOTFS_PARTSIZE" >> "$TOPDIR/.config"
		say "已更新现有 .config 的分区大小：${CUR:-未设置} -> ${ROOTFS_PARTSIZE}"
	fi
fi

# ---------------------------------------------------------------------------
# 5. 构建参数变了就作废两处缓存
#
# 这一步不做的话会得到一个非常隐蔽的后果：**改了参数，却编出和上次一样的包集**。
# 原因有两层，必须同时处理：
#
#   a) include/target.mk 是用 `-include .build-options` 读参数的，但 make 并不把
#      .build-options 当成 prepare-tmpinfo 的依赖。参数变了、文件时间戳变了，
#      tmp/ 里的 Kconfig 元数据却不会重算 —— DEFAULT_<包> 符号压根不会生成，
#      于是 `default y if DEFAULT_<包>` 恒为假。
#
#   b) 就算元数据重算了，`make defconfig` 也**只补缺失的符号，不覆盖已有值**。
#      .config 里那句 "# CONFIG_PACKAGE_x is not set" 是显式值，会被原样保留。
#
# 所以参数一变就把 tmp/ 和 .config 一起清掉，让它们从种子重新长出来。
# 旧 .config 备份成 .config.old（OpenWrt 既有约定，已在 .gitignore 里）。
# ---------------------------------------------------------------------------
if [ "$OPTIONS_CHANGED" = "1" ]; then
	echo "==> $CHANGE_REASON，作废过期的缓存"
	if [ -f "$TOPDIR/.config" ]; then
		cp "$TOPDIR/.config" "$TOPDIR/.config.old"
		rm -f "$TOPDIR/.config"
		say "已删除 .config（旧配置备份为 .config.old）"
	fi
	rm -rf "$TOPDIR/tmp"
	say "已删除 tmp/（Kconfig 元数据缓存）"
	say "接下来 make defconfig 会按新参数重新生成配置"
else
	say "构建参数与上次一致，保留现有配置与缓存"
fi

exit 0
