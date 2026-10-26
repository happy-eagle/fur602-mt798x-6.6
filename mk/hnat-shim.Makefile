# 依赖垫片：kmod-mediatek_hnat
#
# 背景：padavanonly/immortalwrt-mt798x-6.6 把 HNAT 做成了内核内建驱动
#   target/linux/mediatek/files-6.6/drivers/net/ethernet/mediatek/mtk_hnat/
#   （由 patches-6.6/999-2745-mtkhnat-add-mtkhnat-driver-support.patch 引入，
#     配置符号 CONFIG_NET_MEDIATEK_HNAT）
# 但 package/mtk/drivers/mt_wifi/Makefile 里仍然写着
#   DEPENDS+=+kmod-mediatek_hnat
# 而这棵树里根本没有定义 kmod-mediatek_hnat 这个包 —— 依赖不可满足，
# 配置系统会直接把 kmod-mt_wifi 丢掉，闭源 WiFi 就整个消失了。
#
# 这个垫片只负责把依赖名补上；真正的驱动由内核配置开启（见 diy-part2.sh）。

include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/kernel.mk

PKG_NAME:=mediatek_hnat
PKG_VERSION:=1.0
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define KernelPackage/mediatek_hnat
  SUBMENU:=Network Support
  TITLE:=MediaTek HNAT (PPE) hardware NAT offload
  KCONFIG:=CONFIG_NET_MEDIATEK_HNAT
  FILES:=
endef

define KernelPackage/mediatek_hnat/description
 MediaTek HNAT/PPE hardware NAT offload. The driver is built into the
 kernel image (CONFIG_NET_MEDIATEK_HNAT=y); this package exists only to
 provide the dependency name that kmod-mt_wifi refers to.
endef

$(eval $(call KernelPackage,mediatek_hnat))
