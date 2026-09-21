#
# iStoreOS 集成所需的少量配置文件。
#
# 与 package/istoreos-merge/README 说明一致：这里只放「不属于任何上游 feed、
# 也不适合塞进 base-files」的东西。凡是能由上游包自带的配置，都不重复实现。
#
# 参考：istoreos/istoreos 的 package/istoreos-files，这里只取其与
# Docker 相关的两个 uci-defaults，其余（argon 主题、fullcone、upnp、
# linkease 代理等）要么与本树既有实现冲突，要么不在本次合并范围内。
#
include $(TOPDIR)/rules.mk

PKG_NAME:=istoreos-merge
PKG_VERSION:=1.0
PKG_RELEASE:=1
PKG_FLAGS:=hold

PKG_LICENSE:=CC0-1.0

include $(INCLUDE_DIR)/package.mk

define Package/istoreos-merge
  SECTION:=base
  CATEGORY:=Base system
  TITLE:=iStoreOS integration files
  DEPENDS:=+luci-app-dockerman
endef

define Package/istoreos-merge/description
 Docker 在 fw4 下的出网 NAT 规则，以及 squashfs 镜像上 docker 数据目录的落点。
 仅在选中 luci-app-dockerman 时才会安装。
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Compile
endef

define Package/istoreos-merge/install
	$(CP) ./files/* $(1)/
endef

$(eval $(call BuildPackage,istoreos-merge))
