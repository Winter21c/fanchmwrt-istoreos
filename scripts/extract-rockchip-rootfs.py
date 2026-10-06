#!/usr/bin/env python3
#
# 从 rockchip 的 sysupgrade 镜像里取出 rootfs 分区，供离线核验使用。
#
# 用法：extract-rockchip-rootfs.py <sysupgrade.img[.gz]> <输出文件>
# 成功时在 stdout 打印文件系统类型（squashfs / ext4 / unknown），
# 失败时在 stderr 说明原因并以非零退出。
#
# ---------------------------------------------------------------------------
# 为什么要自己解析分区表
# ---------------------------------------------------------------------------
# rockchip 目标只出一个 sysupgrade.img.gz，rootfs 被拼在镜像**里面**
# （见 include/image.mk 的 pine64-img 与 scripts/gen_image_generic.sh），
# 不像 x86 那样另有一个 rootfs.tar.gz 或 squashfs-rootfs.img.gz 可以拿来解。
#
# 用 losetup / kpartx + mount 是常规做法，但：
#   * 需要 root；
#   * CI runner 上 loop 设备未必可用；
#   * 挂载之后还要处理权限，而我们要的只是「把文件清单读出来」。
# 所以直接按字节解析分区表，不碰 loop 设备。
#
# ---------------------------------------------------------------------------
# 镜像布局（gen_image_generic.sh，PADDING=1 / ALIGN=32768）
# ---------------------------------------------------------------------------
#   [0 扇区       , 32768 扇区)  预留给 u-boot-rockchip.bin（idbloader + u-boot）
#   MBR 分区表（第 0 扇区，签名 55 AA 在偏移 510）
#   part1  boot     FAT，CONFIG_TARGET_KERNEL_PARTSIZE 兆，装 kernel.img 与 boot.scr
#   part2  rootfs   CONFIG_TARGET_ROOTFS_PARTSIZE 兆
#
# 这里**不做**「part1 一定是 boot、part2 一定是 rootfs」的假设之外的推断：
# 只取第 2 个非空分区项，取不到就明确报错，不猜。
#
# ---------------------------------------------------------------------------
# 为什么要按 squashfs 超级块截断
# ---------------------------------------------------------------------------
# 分区是**补零**到固定大小的（gen_image_generic.sh 先 dd 一片零再写 rootfs），
# 所以直接抽取整个分区会得到一个「squashfs + 900MB 零」的文件。
# unsquashfs 能容忍这个（它按超级块里的 bytes_used 读），但白写 900MB 很浪费。
# squashfs 超级块的偏移 40 处是 bytes_used（u64 小端），按它截断即可。
#

import gzip
import struct
import sys

SECTOR = 512
MBR_PART_OFF = 446
MBR_PART_LEN = 16
MBR_SIG_OFF = 510
SQUASHFS_MAGIC = b"hsqs"          # 0x73717368 小端
SQUASHFS_BYTES_USED_OFF = 40


def fail(msg):
    print(msg, file=sys.stderr)
    sys.exit(1)


def read_mbr(f):
    f.seek(0)
    mbr = f.read(SECTOR)
    if len(mbr) < SECTOR:
        fail("镜像不足 512 字节，不是有效的磁盘镜像")
    if mbr[MBR_SIG_OFF:MBR_SIG_OFF + 2] != b"\x55\xaa":
        fail("第 0 扇区末尾没有 MBR 签名 55 AA —— 镜像布局与预期不符。\n"
             "     多半是上游改了 rockchip 的镜像拼装方式，请人工核对 "
             "target/linux/rockchip/image/Makefile 与 scripts/gen_image_generic.sh。")

    parts = []
    for i in range(4):
        e = mbr[MBR_PART_OFF + i * MBR_PART_LEN:MBR_PART_OFF + (i + 1) * MBR_PART_LEN]
        start = struct.unpack("<I", e[8:12])[0]
        count = struct.unpack("<I", e[12:16])[0]
        if count:
            parts.append((start, count))
    return parts


def main():
    if len(sys.argv) != 3:
        fail("用法：extract-rockchip-rootfs.py <sysupgrade.img[.gz]> <输出文件>")
    src, dst = sys.argv[1], sys.argv[2]

    opener = gzip.open if src.endswith(".gz") else open
    with opener(src, "rb") as f:
        parts = read_mbr(f)
        if len(parts) < 2:
            fail("MBR 里只有 %d 个非空分区，找不到 rootfs 分区（期望 2 个）" % len(parts))

        start, count = parts[1]
        f.seek(start * SECTOR)
        head = f.read(SECTOR)
        if len(head) < SECTOR:
            fail("读 rootfs 分区首扇区失败（偏移 %d 扇区）" % start)

        magic = head[:4]
        if magic == SQUASHFS_MAGIC:
            # 超级块在分区的第一个扇区内，bytes_used 位于偏移 40。
            if len(head) < SQUASHFS_BYTES_USED_OFF + 8:
                fail("读取 squashfs 超级块失败")
            bytes_used = struct.unpack("<Q", head[SQUASHFS_BYTES_USED_OFF:SQUASHFS_BYTES_USED_OFF + 8])[0]
            if bytes_used == 0 or bytes_used > count * SECTOR:
                fail("squashfs 超级块里的 bytes_used=%d 不合理（分区共 %d 字节）"
                     % (bytes_used, count * SECTOR))
            fs_type = "squashfs"
            want = bytes_used
        else:
            # 认不出来就整段抽出来，交给调用方判断。
            fs_type = "unknown"
            want = count * SECTOR

        f.seek(start * SECTOR)
        remaining = want
        with open(dst, "wb") as o:
            while remaining > 0:
                chunk = f.read(min(1 << 20, remaining))
                if not chunk:
                    fail("解压/读取中途结束：还差 %d 字节。镜像可能被截断了。" % remaining)
                o.write(chunk)
                remaining -= len(chunk)

    print(fs_type)


if __name__ == "__main__":
    main()
