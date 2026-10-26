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
# 这个垫片只负责把依赖名补上，并把内建的 mtkhnat.ko 按模块打出来。
# NET_MEDIATEK_HNAT 在 Kconfig 里是 tristate，所以走 =m：
#   - 它 depends on IP_NF_NAT，而 IP_NF_NAT 由 kmod-ipt-nat 提供为 =m，
#     tristate 依赖 m 是合法的（如果强推 =y，就得把 IP_NF_NAT 也改成 y，
#     那样 kmod-ipt-nat / kmod-ipt-core 的 .ko 会变成内建，打包阶段必然报错）。
#   - 模块化还能让 mt_wifi 通过 modules.dep 自动带起它。

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
  FILES:=$(LINUX_DIR)/drivers/net/ethernet/mediatek/mtk_hnat/mtkhnat.ko
  AUTOLOAD:=$(call AutoLoad,50,mtkhnat)
endef

define KernelPackage/mediatek_hnat/description
 MediaTek HNAT/PPE hardware NAT offload. The driver source ships in
 target/linux/mediatek/files-6.6 (added by patches-6.6/999-2745); this
 package builds it as mtkhnat.ko and provides the dependency name that
 kmod-mt_wifi refers to.
endef

$(eval $(call KernelPackage,mediatek_hnat))
