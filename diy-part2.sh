#!/bin/bash
# diy-part2.sh —— 在源码树克隆完成、feeds 更新之后执行
# 作用：把 HONOR FUR-602 的设备适配打进 padavanonly/immortalwrt-mt798x-6.6
#
# 用法（在源码树根目录）：
#   bash /path/to/diy-part2.sh
#
# 幂等：重复执行不会重复插入，全部操作带断言，失败即退出。

set -euo pipefail

SRC_DIR="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DTS_SRC="$SCRIPT_DIR/dts/mt7981b-honor-fur-602.dts"
DTS_DST="$SRC_DIR/target/linux/mediatek/dts/mt7981b-honor-fur-602.dts"
MK_DST="$SRC_DIR/target/linux/mediatek/image/filogic.mk"
NET_DST="$SRC_DIR/target/linux/mediatek/filogic/base-files/etc/board.d/02_network"
DEFCONFIG_DST="$SRC_DIR/defconfig/mt7981-honor-fur602.config"

log() { printf '\033[1;32m[fur602]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[fur602][FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

# ---------- 0. 前置检查 ----------
[ -d "$SRC_DIR/target/linux/mediatek" ] || die "当前目录不是 OpenWrt/ImmortalWrt 源码树根目录"
[ -f "$SRC_DIR/package/mtk/drivers/mt_wifi/Makefile" ] || \
	die "这不是 padavanonly/immortalwrt-mt798x-6.6 树（找不到 package/mtk/drivers/mt_wifi）"
[ -f "$DTS_SRC" ] || die "找不到 $DTS_SRC"

KVER="$(sed -n 's/^LINUX_VERSION-6\.6 = \(.*\)$/\1/p' "$SRC_DIR/include/kernel-6.6" 2>/dev/null | head -1 || true)"
KVER="${KVER#.}"
log "源码树: $SRC_DIR"
log "内核  : 6.6${KVER:+.$KVER}"

# ---------- 1. 放 DTS ----------
cp -f "$DTS_SRC" "$DTS_DST"
[ -s "$DTS_DST" ] || die "DTS 复制失败"
log "DTS -> target/linux/mediatek/dts/mt7981b-honor-fur-602.dts"

# ---------- 2. 注册设备到 filogic.mk ----------
if grep -q 'define Device/honor_fur-602' "$MK_DST"; then
	log "filogic.mk 已包含 honor_fur-602，跳过"
else
	{
		echo ''
		echo '# ---- HONOR FUR-602 / FUR-603 (MT7981B, closed-source mt_wifi) ----'
		sed -e 's#^//.*$##' "$SCRIPT_DIR/mk/filogic.mk.append" | sed '/^$/d'
	} >> "$MK_DST"
	grep -q 'define Device/honor_fur-602' "$MK_DST" || die "filogic.mk 注入失败"
	grep -q 'TARGET_DEVICES += honor_fur-602' "$MK_DST" || die "TARGET_DEVICES 注入失败"
	log "filogic.mk += Device/honor_fur-602"
fi

# ---------- 3. HNAT：补依赖垫片 + 打开内核内建驱动 ----------
# 这棵树把 HNAT 做成内核内建（patches-6.6/999-2745），但没有定义
# kmod-mediatek_hnat 包；而 mt_wifi 的 Makefile 依赖它。依赖不可满足
# 会导致 kmod-mt_wifi 被配置系统直接丢弃，闭源 WiFi 整个消失。
HNAT_PKG_DIR="$SRC_DIR/package/mtk/drivers/hnat"
if [ -f "$HNAT_PKG_DIR/Makefile" ]; then
	log "HNAT 垫片包已存在，跳过"
else
	mkdir -p "$HNAT_PKG_DIR"
	cp -f "$SCRIPT_DIR/mk/hnat-shim.Makefile" "$HNAT_PKG_DIR/Makefile"
	grep -q 'KernelPackage/mediatek_hnat' "$HNAT_PKG_DIR/Makefile" || die "HNAT 垫片包写入失败"
	log "package/mtk/drivers/hnat += kmod-mediatek_hnat（依赖垫片）"
fi

# mt_wifi 依赖的包名必须真的能解析到，否则 mt_wifi 会被丢弃
grep -q 'kmod-mediatek_hnat' "$SRC_DIR/package/mtk/drivers/mt_wifi/Makefile" || \
	die "mt_wifi 的 Makefile 结构已变（找不到 kmod-mediatek_hnat 依赖）"

# 内核侧打开 HNAT。CONFIG_IP_NF_NAT 必须为 y（bool 符号不能依赖 m），
# 否则 CONFIG_NET_MEDIATEK_HNAT 根本不可选。
KCFG="$SRC_DIR/target/linux/mediatek/filogic/config-6.6"
[ -f "$KCFG" ] || die "找不到 $KCFG"
for sym in CONFIG_NET_MEDIATEK_HNAT CONFIG_IP_NF_NAT CONFIG_IP_NF_IPTABLES; do
	if grep -q "^${sym}=y$" "$KCFG"; then
		log "内核配置已有 ${sym}=y"
	else
		# 先删掉可能存在的 =m / is not set 行，再追加 =y
		sed -i "/^${sym}=/d;/^# ${sym} is not set$/d" "$KCFG"
		echo "${sym}=y" >> "$KCFG"
		log "内核配置 += ${sym}=y"
	fi
done

# ---------- 4. 02_network：接口分发 + MAC 分发 ----------
# 注意：判重不能用 'honor,fur-602)'，因为插入的是多行 case 标签，
# 第一行以续行符结尾（honor,fur-602|\），括号只出现在最后一行。
if grep -q 'honor,fur-602' "$NET_DST"; then
	log "02_network 已包含 honor,fur-602，跳过"
else
	python3 - "$NET_DST" <<'PY'
import io
import sys

p = sys.argv[1]
s = io.open(p, encoding='utf-8').read()

# --- 3a. 接口分发：插在 mediatek_setup_interfaces 的 *) 默认分支之前 ---
iface_anchor = ('\t*)\n'
                '\t\tucidef_set_interfaces_lan_wan "lan1 lan2 lan3 lan4" wan\n')
if iface_anchor not in s:
    sys.exit('02_network: 接口函数默认分支锚点未命中，上游结构已变，请手工处理')
iface_block = ('\thonor,fur-602|\\\n'
               '\thonor,fur-603)\n'
               '\t\tucidef_set_interfaces_lan_wan "lan1 lan2 lan3" wan\n'
               '\t\t;;\n')
i = s.rindex(iface_anchor)
s = s[:i] + iface_block + s[i:]

# --- 3b. MAC 分发：插在 mediatek_setup_macs 的 case 末尾（esac 之前） ---
# 6.6 树默认分支是 base_mac=$(cat /sys/class/net/eth0/address)，
# 但 DSA 下没有 eth0，会导致写进 mt_wifi 的 MacAddress= 变空。
# 这里按 DTS 的 nvmem-cells 对齐：gmac0=Factory 0x2a，wan=Factory 0x24。
ms = s.find('mediatek_setup_macs()')
if ms < 0:
    sys.exit('02_network: 找不到 mediatek_setup_macs()')
es = s.find('\tesac\n', ms)
if es < 0:
    sys.exit('02_network: 找不到 mediatek_setup_macs 的 esac')
mac_block = ('\thonor,fur-602|\\\n'
             '\thonor,fur-603)\n'
             '\t\tlan_mac=$(mtd_get_mac_binary Factory 0x2a)\n'
             '\t\twan_mac=$(mtd_get_mac_binary Factory 0x24)\n'
             '\t\tlabel_mac=$lan_mac\n'
             '\t\t;;\n')
s = s[:es] + mac_block + s[es:]

io.open(p, 'w', encoding='utf-8', newline='\n').write(s)
print('02_network: 已注入 接口分发 + MAC 分发')
PY
	grep -q 'honor,fur-602|' "$NET_DST" || die "02_network 接口注入失败"
	grep -q 'mtd_get_mac_binary Factory 0x2a' "$NET_DST" || die "02_network MAC 注入失败"
	log "02_network += honor,fur-602 -> lan1 lan2 lan3 / wan"
	log "02_network += honor,fur-602 -> MAC: lan=Factory 0x2a / wan=Factory 0x24"
fi

# ---------- 5. 写设备 defconfig ----------
cp -f "$SCRIPT_DIR/defconfig/mt7981-honor-fur602.config" "$DEFCONFIG_DST"
grep -q 'CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_honor_fur-602=y' "$DEFCONFIG_DST" || \
	die "defconfig 里没有选中 honor_fur-602"
log "defconfig -> defconfig/mt7981-honor-fur602.config"

# ---------- 6. 冲突检查：不允许开源 mt76 混进来 ----------
if grep -qE '^CONFIG_PACKAGE_kmod-mt7915e=y|^CONFIG_PACKAGE_kmod-mt76' "$DEFCONFIG_DST"; then
	die "defconfig 里混入了开源 mt76 包，会和闭源 mt_wifi 冲突"
fi
grep -q '^CONFIG_PACKAGE_kmod-mt_wifi=y' "$DEFCONFIG_DST" || die "defconfig 未启用 kmod-mt_wifi"
grep -q '^CONFIG_PACKAGE_kmod-mediatek_hnat=y' "$DEFCONFIG_DST" || die "defconfig 未启用 HNAT"
log "冲突检查通过：只启用闭源 mt_wifi + HNAT + WARP"

log "设备适配完成。下一步："
log "  cp defconfig/mt7981-honor-fur602.config .config && make defconfig"
log "  make -j\$(nproc) V=s"
