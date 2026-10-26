#!/bin/bash
# set-rf-offset.sh —— 快速切换 2.4G eeprom 在 factory 分区里的偏移
#
# 闭源 mt_wifi 按 defconfig 里写死的偏移读校准数据。FUR-602 的正确值未知，
# 常见三个候选：0x0 / 0x80000 / 0xc0000。
#
# 用法：
#   bash set-rf-offset.sh 0x0        # 改成 0x0
#   bash set-rf-offset.sh 0x80000    # 改成 0x80000
#   bash set-rf-offset.sh            # 只查看当前值

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="$SCRIPT_DIR/defconfig/mt7981-honor-fur602.config"
KEY="CONFIG_MTK_RT_FIRST_IF_RF_OFFSET"

[ -f "$CFG" ] || { echo "找不到 $CFG" >&2; exit 1; }

CUR="$(grep -m1 "^$KEY=" "$CFG" | cut -d= -f2)"
if [ $# -eq 0 ]; then
	echo "当前 $KEY=$CUR"
	echo "候选: 0x0 / 0x80000 / 0xc0000"
	exit 0
fi

NEW="$1"
case "$NEW" in
	0x0|0x80000|0xc0000) ;;
	*) echo "不推荐的偏移: $NEW（确认无误请直接改 $CFG）" >&2; exit 1;;
esac

python3 - "$CFG" "$KEY" "$NEW" <<'PY'
import io, sys
p, key, new = sys.argv[1], sys.argv[2], sys.argv[3]
lines = io.open(p, encoding='utf-8').read().splitlines()
out, hit = [], False
for ln in lines:
    if ln.startswith(key + '='):
        out.append('%s=%s' % (key, new)); hit = True
    else:
        out.append(ln)
if not hit:
    out.append('%s=%s' % (key, new))
io.open(p, 'w', encoding='utf-8', newline='\n').write('\n'.join(out) + '\n')
print('已写入 %s=%s' % (key, new))
PY

echo "改完记得重编（或重跑 GitHub Actions）。"
