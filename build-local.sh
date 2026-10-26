#!/bin/bash
# build-local.sh —— 在任意 Linux 机器（或 VPS / 容器）上本地编译
#
# 要求：Debian 11/12 或 Ubuntu 20.04+，x86_64，>=4GB RAM，>=40GB 空闲磁盘
#      必须用普通用户跑，不要 sudo（除装依赖）
#
# 用法：
#   bash build-local.sh                 # 全量编译
#   bash build-local.sh -c              # 先 make menuconfig 再编译
#   JOBS=8 bash build-local.sh          # 指定并发

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="${WORK:-$HOME/fur602-build}"
SRC_BRANCH="${SRC_BRANCH:-openwrt-24.10-6.6}"
REPO="${REPO:-https://github.com/padavanonly/immortalwrt-mt798x-6.6}"
JOBS="${JOBS:-$(nproc)}"
MENUCONFIG=0
[ "${1:-}" = "-c" ] && MENUCONFIG=1

log() { printf '\033[1;32m[fur602]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[fur602][FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

# ---------- 环境自检 ----------
[ "$(uname -s)" = "Linux" ] || die "只能在 Linux 上编译（当前: $(uname -s)）"
[ "$(id -u)" -ne 0 ] || die "不要用 root 编译，OpenWrt 会报错"
case "$SCRIPT_DIR" in *" "*) die "路径含空格: $SCRIPT_DIR";; esac
FREE_GB=$(df -Pk "$(dirname "$WORK")" | awk 'NR==2{print int($4/1024/1024)}')
[ "$FREE_GB" -ge 40 ] || die "磁盘不足：需要 40GB，当前 ${FREE_GB}GB"

for t in gcc g++ make git python3 rsync unzip wget; do
	command -v "$t" >/dev/null || die "缺少依赖: $t（先按 README 装依赖）"
done

log "工作目录: $WORK"
log "源码分支: $SRC_BRANCH"
log "并发    : $JOBS"

mkdir -p "$WORK"
cd "$WORK"

# ---------- 1. 源码 ----------
if [ -d immortalwrt/.git ]; then
	log "源码已存在，跳过克隆"
else
	git clone -b "$SRC_BRANCH" --single-branch --filter=blob:none "$REPO" immortalwrt
fi
cd immortalwrt
log "HEAD: $(git rev-parse HEAD)"

# ---------- 2. feeds ----------
./scripts/feeds update -a
./scripts/feeds install -a

# ---------- 3. 设备适配 ----------
bash "$SCRIPT_DIR/diy-part2.sh"

# ---------- 4. 配置 ----------
cp defconfig/mt7981-honor-fur602.config .config
echo 'CONFIG_CCACHE=y' >> .config
make defconfig
grep -q '^CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_honor_fur-602=y' .config \
	|| die "honor_fur-602 未进入 .config"

if [ "$MENUCONFIG" = "1" ]; then
	make menuconfig
fi

# ---------- 5. 下载 & 编译 ----------
make download -j8 || make download -j1 V=s
if ! make -j"$JOBS" V=s 2>&1 | tee build.log; then
	log "并行编译失败，退到单线程重试（能看到真实报错）"
	make -j1 V=s 2>&1 | tee -a build.log
fi

# ---------- 6. 产物 ----------
OUT="$WORK/immortalwrt/bin/targets/mediatek/filogic"
ls -lh "$OUT"
log "产物目录: $OUT"
log "刷机用:   *-squashfs-factory.bin（U-Boot Web 恢复页）"
log "升级用:   *-squashfs-sysupgrade.bin（系统内 sysupgrade）"
