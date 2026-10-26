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

# ---------- 3. 02_network 加接口分发 ----------
if grep -q 'honor,fur-602)' "$NET_DST"; then
	log "02_network 已包含 honor,fur-602，跳过"
else
	python3 - "$NET_DST" <<'PY'
import sys, io
p = sys.argv[1]
s = io.open(p, encoding='utf-8').read()
anchor = '\n\t*)\n\t\tucidef_set_interfaces_lan_wan "lan1 lan2 lan3 lan4" wan\n'
block = (
    '\thonor,fur-602|\\\n'
    '\thonor,fur-603)\n'
    '\t\tucidef_set_interfaces_lan_wan "lan1 lan2 lan3" wan\n'
    '\t\t;;\n'
)
if anchor not in s:
    sys.exit('02_network: 找不到默认分支锚点，上游结构已变，请手工处理')
i = s.rindex(anchor)
s = s[:i] + '\n' + block + s[i+1:]
io.open(p, 'w', encoding='utf-8', newline='\n').write(s)
PY
	grep -q 'honor,fur-602)' "$NET_DST" || die "02_network 注入失败"
	log "02_network += honor,fur-602 -> lan1 lan2 lan3 / wan"
fi

# ---------- 4. 写设备 defconfig ----------
cp -f "$SCRIPT_DIR/defconfig/mt7981-honor-fur602.config" "$DEFCONFIG_DST"
grep -q 'CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_honor_fur-602=y' "$DEFCONFIG_DST" || \
	die "defconfig 里没有选中 honor_fur-602"
log "defconfig -> defconfig/mt7981-honor-fur602.config"

# ---------- 5. 冲突检查：不允许开源 mt76 混进来 ----------
if grep -qE '^CONFIG_PACKAGE_kmod-mt7915e=y|^CONFIG_PACKAGE_kmod-mt76' "$DEFCONFIG_DST"; then
	die "defconfig 里混入了开源 mt76 包，会和闭源 mt_wifi 冲突"
fi
grep -q '^CONFIG_PACKAGE_kmod-mt_wifi=y' "$DEFCONFIG_DST" || die "defconfig 未启用 kmod-mt_wifi"
grep -q '^CONFIG_PACKAGE_kmod-mediatek_hnat=y' "$DEFCONFIG_DST" || die "defconfig 未启用 HNAT"
log "冲突检查通过：只启用闭源 mt_wifi + HNAT + WARP"

log "设备适配完成。下一步："
log "  cp defconfig/mt7981-honor-fur602.config .config && make defconfig"
log "  make -j\$(nproc) V=s"
