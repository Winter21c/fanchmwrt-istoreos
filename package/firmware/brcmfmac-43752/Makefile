# SPDX-License-Identifier: GPL-2.0-only
#
# Broadcom BCM43752 (AMPAK AP6275S) SDIO firmware.
#
# 为什么需要单独一个包
# --------------------
# OpenWrt 树内两个可能的来源都**完全没有**这颗芯片，这是核对过的，不是推测：
#
#   * linux-firmware-20260221.tar.xz 的 4866 个文件里，brcm/ 下没有
#     brcmfmac43752-*，cypress/ 下也没有 cyfmac43752-*；
#   * Infineon 的 ifx-linux-firmware（cypress-firmware 包的上游）同样没有。
#
# 所以 linux-firmware 与 cypress-firmware 两个包都提供不了它。ImmortalWrt 是
# 从 Armbian 的 firmware 仓库取这几个文件的，这里跟随**同一个 commit**，
# 让 immortalwrt-fusion 与本树用上逐字节相同的固件。
#
# 为什么不直接 PKG_SOURCE_PROTO:=git 拉整仓
# -----------------------------------------
# armbian/firmware 整仓约 200 MB（最大的单个文件 74 MB，是高通基带），
# 而我们只要其中 4 个文件、合计约 860 KB。用 Download/ 逐个取，只下这 4 个。
#
# 校验和是对着上面那个 commit 实际算出来的，不是抄的。
#
# NVRAM 的由来
# ------------
# brcmfmac43752-sdio.txt 的文件头写的是
#     # AP6275S_NVRAM_V1.7_20210726
#     # AP6275S v00 WLBGA reference board, iPA version.
# 也就是 AMPAK AP6275S 参考板的 NVRAM —— 与厂商 DTS 里的
# wifi_chip_type = "ap6275s" 对得上。
#

include $(TOPDIR)/rules.mk

PKG_NAME:=brcmfmac-43752
PKG_RELEASE:=1

PKG_MAINTAINER:=Winter21c <winter21c@users.noreply.github.com>
PKG_LICENSE:=Proprietary

ARMFW_REF:=7f2e18ecac75d50acb843395ad07a0f2b9a12a50
ARMFW_URL:=https://raw.githubusercontent.com/armbian/firmware/$(ARMFW_REF)/brcm

include $(INCLUDE_DIR)/package.mk

define Download/firmware
  FILE:=brcmfmac43752-sdio.bin
  URL:=$(ARMFW_URL)
  HASH:=46f62076768e50938d0e29b306b24d4663de20b07b474c4759d5801fcbf0bdde
endef

define Download/clm_blob
  FILE:=brcmfmac43752-sdio.clm_blob
  URL:=$(ARMFW_URL)
  HASH:=5143146e1923f87f7aab8df043abcf89a657fa9fdc3b22a38806399730d9a97a
endef

define Download/nvram
  FILE:=brcmfmac43752-sdio.txt
  URL:=$(ARMFW_URL)
  HASH:=2d2723101fe9c66c853ddb1e2d715851ba100a4390f8ac72fc84dd35736cc66f
endef

define Download/bt_firmware
  FILE:=BCM4362A2.hcd
  URL:=$(ARMFW_URL)
  HASH:=18901a5bef1d418b6895e92d0afae36234f4160b237465dfca3d75e9844e93ef
endef

define Build/Prepare
	$(eval $(call Download,firmware))
	$(eval $(call Download,clm_blob))
	$(eval $(call Download,nvram))
	$(eval $(call Download,bt_firmware))
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Compile
endef

define Package/brcmfmac-firmware-43752-sdio
  SECTION:=firmware
  CATEGORY:=Firmware
  TITLE:=Broadcom BCM43752 (AMPAK AP6275S) FullMac SDIO firmware
  URL:=https://github.com/armbian/firmware
endef

define Package/brcmfmac-firmware-43752-sdio/install
	$(INSTALL_DIR) $(1)/lib/firmware/brcm
	$(INSTALL_DATA) $(DL_DIR)/brcmfmac43752-sdio.bin $(1)/lib/firmware/brcm/
	$(INSTALL_DATA) $(DL_DIR)/brcmfmac43752-sdio.clm_blob $(1)/lib/firmware/brcm/
	$(INSTALL_DATA) $(DL_DIR)/BCM4362A2.hcd $(1)/lib/firmware/brcm/
endef

$(eval $(call BuildPackage,brcmfmac-firmware-43752-sdio))

define Package/brcmfmac-nvram-43752-sdio
  SECTION:=firmware
  CATEGORY:=Firmware
  TITLE:=Broadcom BCM43752 (AMPAK AP6275S) SDIO NVRAM
  URL:=https://github.com/armbian/firmware
endef

define Package/brcmfmac-nvram-43752-sdio/install
	$(INSTALL_DIR) $(1)/lib/firmware/brcm
	$(INSTALL_DATA) $(DL_DIR)/brcmfmac43752-sdio.txt $(1)/lib/firmware/brcm/
endef

$(eval $(call BuildPackage,brcmfmac-nvram-43752-sdio))
