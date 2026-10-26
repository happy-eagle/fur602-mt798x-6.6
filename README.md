# HONOR FUR-602 / FUR-603 — ImmortalWrt 24.10-6.6 + MTK SDK 闭源驱动

给荣耀 FUR-602（联通定制 XU50，MT7981B / Filogic 820）编一版 **内核 6.6 + MTK 厂商补丁 + 闭源 mt_wifi 7.6.6.1 + HNAT + WARP v2** 的固件。

源码基线：`padavanonly/immortalwrt-mt798x-6.6` @ `openwrt-24.10-6.6`（最后更新 2026-07-23）。

---

## 0. 先泼一盆冷水：这台机器编不了

已检查过：

| 项 | 结果 |
|---|---|
| Docker | 未安装 |
| WSL | 被安全策略拉黑（`wsl.exe` 在程序黑名单，不可绕过） |
| 磁盘 | 618 GB 空闲，够 |

OpenWrt 必须在 Linux 下编译（大小写敏感文件系统 + POSIX 工具链），Windows 原生无解。所以这个工程给的是**完整可编译的移植套件**，编译动作走两条路：

- **A. GitHub Actions（推荐）**：fork 到你的账号，push 后自动编，约 2.5–4 小时出包。
- **B. 任意 Linux 机器 / VPS / 云主机**：`bash build-local.sh`，40GB 磁盘、4GB 内存起。

两条路用同一套设备适配文件，结果一致。

---

## 1. 可行性：已有实机出包的先例

`fur602 dts.rar` 里的 `dts/6.6-padavanonly` 和 `dts/6.6-closewrt` 就是**同一棵树、同一个闭源驱动、同一块板**已经出过包的版本（对应那个包的固件 02 / 04）。这比我上一版靠 360T7 类推要硬得多——不再是"应该能行"，是"有人跑通过"。

再加上树内同平台机型佐证：

| 项 | 360T7（树内已支持） | FUR-602 |
|---|---|---|
| SoC / 内存 | MT7981B / 256MB | MT7981B / 256MB |
| Flash | 128MB SPI-NAND + NMBM | 128MB SPI-NAND + NMBM |
| 交换芯片 | MT7531（DSA） | MT7531（DSA） |
| 无线驱动 | 闭源 `kmod-mt_wifi` | 同 |

所以本工程的重点不在"能不能跑"，而在**编译流程、配置取舍、可复现性**——这些参考包没做（它只有 DTS 和成品固件，没有 CI、没有锁定源码版本、没有断言）。

---

## 2. 与那四份参考 DTS 的逐项对比

压缩包里四份 DTS，内核/驱动栈各不相同，先理清它们的关系：

| 目录 | 内核 | 交换芯片写法 | wifi eeprom | MAC 来源 | 用途 |
|---|---|---|---|---|---|
| `5.4-original` | 5.4 | switchdev（`mediatek,portmap="wllll"`）+ `&hnat` 节点 | 无（驱动直读 flash） | 无 | hanwckf 原始基准 |
| `6.6-padavanonly` | 6.6 | DSA（mt7531） | `nvmem-cells = <&eeprom_factory_0>` | Factory@0x2a | 闭源 mt_wifi 实机出包 |
| `6.6-closewrt` | 6.6 | DSA | 同上 | Factory@0x2a | 同上，换主题配置 |
| `25.12-imm2512` | 6.12 | DSA | 同上 | Factory@0x2a | chasey-dev 25.12 树 |

四份的硬件事实完全一致：`gpio 0/1` 按键、`gpio 8/13` LED、`gpio 39` switch reset、`gmac0 = 2500base-x`、WAN = port0、LAN = port1/2/3、`0x580000 + 0x7200000` 的 UBI。**没有互相矛盾的地方，这套硬件参数可以定死。**

### 我这版 DTS 和 `6.6-padavanonly` 的差异

上一版我用的是 `mediatek,mtd-eeprom = <&factory 0x0>`，**这是错的写法**，已经改掉。三处有意差异：

| 项 | 参考版 `6.6-padavanonly` | 本工程 | 为什么改 |
|---|---|---|---|
| wifi eeprom | `nvmem-cells = <&eeprom_factory_0>` + `nvmem-cell-names = "eeprom"` | 同 | 本树标准写法（对照 `mt7981b-cmcc-rax3000m-mtk.dts`）。`mediatek,mtd-eeprom` 是 5.15 时代的老绑定 |
| MAC | 只设 `macaddr_factory_2a`（gmac0） | 追加 `macaddr_factory_24`（wan 口） | 参考版 WAN 和 LAN 共用同一个 MAC；schema12 开源版用 0x24，交叉验证过 |
| pinctrl | `MTK_DRIVE_8mA` / `MTK_PUPD_SET_R1R0_11` 宏 | `drive-strength = <8>` / `mediatek,pull-up-adv = <3>` | 宏来自 SDK 的 dtsi，树内 360T7 / RAX3000M-mtk 都用裸数值，换树不会踩空。数值等价（8mA、R1R0_11=3） |
| LED | `label = "green:status"` | `function` + `color` | 24.10 规范写法，25.x 不会弃用，生成的名字一样 |
| 分区名 | `BL2` / `Factory` / `Trace` / `FIP` | 同 | 照抄原厂 / U-Boot mtdparts，别改小写 |
| CPU 口 | 无 label | 无 label | 上一版我加了 `label = "cpu"`，已删，跟树内一致 |

> 参考版那句注释"MAC 布局需自行核对"是对的：`0x2a` 是从 asr3000 模板抄的。刷机前建议先备份 Factory 分区，用 `hexdump` 看一眼 `0x24` 和 `0x2a` 处是不是合法的 MAC（首字节不能是多播/全 FF）。

---

## 3. eeprom 偏移：已实证，不用猜了

闭源 `mt_wifi` **不读 DTS 的 eeprom 节点**，它按 defconfig 写死的偏移直接读 flash：

```
CONFIG_MTK_RT_FIRST_CARD_EEPROM="flash"
CONFIG_MTK_RT_FIRST_IF_RF_OFFSET=0xc0000
```

这也解释了为什么 `5.4-original` 的 DTS 里根本没有 wifi eeprom 节点——驱动自己找。

**`0xc0000` 已经证实是对的。** 证据链：`01-imm2410-5.4-mtwifi` 那版固件你用了好几天、无线正常，而它对应的源码树（`RuijieNetworksCommunity/immortalwrt-mt798x-24.10`）的 `defconfig/mt7981-ax3000.config` 里就是 `RF_OFFSET=0xc0000` + `SECOND_IF_NONE=y`。同一个 SoC、同一个 factory 分区布局、同一个闭源驱动，偏移自然一致。

所以本工程的 `0xc0000` 不用改。真出问题（5G 扫不到 / TX power 个位数）再动：

```bash
bash set-rf-offset.sh 0x0       # 或 0x80000
```

---

## 4. 目录结构

```
fur602-mt798x-6.6/
├── dts/mt7981b-honor-fur-602.dts          # 设备树（对齐实机出包版本）
├── mk/filogic.mk.append                   # Device/honor_fur-602 定义
├── mk/hnat-shim.Makefile                  # kmod-mediatek_hnat 依赖垫片
├── defconfig/mt7981-honor-fur602.config   # 设备配置：闭源 mt_wifi + HNAT + WARP v2
├── diy-part2.sh                           # 一键注入设备适配（幂等 + 带断言）
├── build-local.sh                         # Linux 本地编译
├── set-rf-offset.sh                       # 快速切 eeprom 偏移并重编
└── .github/workflows/build.yml            # GitHub Actions 编译
```

`defconfig` 的要点：

- `CONFIG_PACKAGE_kmod-mt_wifi=y` —— 闭源驱动，7.6.6.1
- `CONFIG_PACKAGE_kmod-mediatek_hnat=y` —— 硬件 NAT（PPE/HNAT 卸载）
- `CONFIG_PACKAGE_kmod-warp=y` + `CONFIG_WARP_VERSION=2` + `CONFIG_WED_HW_RRO_SUPPORT=y` —— WARP v2 + WED 硬件重排，WiFi 转发绕过 CPU
- `CONFIG_PACKAGE_luci-app-turboacc-mtk=y` —— LuCI 里开关加速
- `CONFIG_PACKAGE_luci-app-eqos-mtk=y` + `mtkhqos_util` —— MTK 硬件 QoS
- **没有** `kmod-mt7915e` / `kmod-mt7981-firmware` —— 和闭源驱动抢同一个 wifi 节点，`diy-part2.sh` 会断言拦下

---

## 4.1 首次 CI 暴露的坑（已全部修掉）

第一次 Actions 编译挂在 `Apply FUR-602 device support`，日志最后一行是
`[fur602][FAIL] 02_network 注入失败`。顺着查下去一共三个坑，都不是"随手改改"能过的：

**坑 1：`02_network` 的断言自己写错了**

插入的是多行 case 标签，第一行以续行符结尾：

```sh
	honor,fur-602|\
	honor,fur-603)
```

所以文本里根本不存在 `honor,fur-602)` 这个子串（括号只在最后一行），
而判重和断言都用 `grep -q 'honor,fur-602)'` —— 注入其实成功了，断言必然失败。
现在统一用 `honor,fur-602|` 匹配。

**坑 2：DSA 下没有 `eth0`，MAC 分发会写出空的 `MacAddress=`**

6.6 树的 `mediatek_setup_macs()` 默认分支是
`base_mac=$(cat /sys/class/net/eth0/address)`。DSA 之后网卡叫 `wan`/`lan1..3`，
没有 `eth0`，于是 `base_mac` 为空，`base+3` / `base+4` 算出来也是空，
最后往 mt_wifi 的 dat 文件里写一行 `MacAddress=`。

现在给 `honor,fur-602` 单独加了 MAC 分支，偏移直接对齐 DTS 的 nvmem-cells：

| 接口 | 来源 | 说明 |
|---|---|---|
| LAN (gmac0) | `Factory 0x2a` | 同时也是 `label-mac-device` |
| WAN (port0)  | `Factory 0x24` | |

这两个偏移不是我猜的：`RuijieNetworksCommunity/immortalwrt-mt798x-24.10`
里 `mediatek_setup_macs()` 的默认值就是 `lan_mac_offset="0x2A"` / `wan_mac_offset="0x24"`，
而那正是你这台机器能正常跑的 5.4 固件用的树。

**坑 3（最隐蔽）：`kmod-mediatek_hnat` 这棵树里根本不存在**

`package/mtk/drivers/mt_wifi/Makefile` 里写着：

```make
DEPENDS+=+kmod-mediatek_hnat
```

但全树搜索 `hnat` 只有两处：`mt_wifi/src/.../plug_in/whnat`（WiFi 侧插件）
和 `target/linux/mediatek/files-6.6/.../mtk_hnat`（内核内建驱动源码）。
**没有 `kmod-mediatek_hnat` 这个包的定义。**

依赖不可满足 → 配置系统会把 `kmod-mt_wifi` 整包丢掉 → 编出来的固件没有闭源 WiFi，
而且 `make defconfig` 不会报错，是静默的。这是最危险的一种失败。

处理方式：

1. `mk/hnat-shim.Makefile` 补一个空壳 `KernelPackage/mediatek_hnat`
   （`FILES` 为空 = 内建），只负责把依赖名补上；
2. `diy-part2.sh` 往 `target/linux/mediatek/filogic/config-6.6` 追加
   `CONFIG_NET_MEDIATEK_HNAT=y` + `CONFIG_IP_NF_NAT=y` + `CONFIG_IP_NF_IPTABLES=y`。

`CONFIG_IP_NF_NAT` 必须是 `y` 不能是 `m`：`NET_MEDIATEK_HNAT` 是 bool，
Kconfig 里 `depends on IP_NF_NAT`，依赖项为 `m` 时 bool 符号只能取 `n`，
HNAT 就直接不可选了。

**顺带修的两处**

- `&wifi` 去掉 `nvmem-cells = <&eeprom_factory_0>`，只留 `status = "okay"`，
  和上游 `cmcc,rax3000m` 等 `-mtk` 机型一致。闭源 mt_wifi 走 flash 直读，
  这个属性没有任何作用，留着只会增加歧义。
- 补 `&hnat` 节点：

  ```dts
  &hnat {
          mtketh-max-gmac = <1>;
          mtkdsa-wan-port = <0>;
          status = "okay";
  };
  ```

  `mtkdsa-wan-port` 是必须的 —— 驱动里 `hnat_dsa_is_enable()` 就是
  `return priv->wan_dsa_port != NONE_DSA_PORT;`，不写这个属性，DSA 下的
  硬件 NAT 卸载永远不会启用。`mtketh-max-gmac` 从 dtsi 默认的 2 改成 1，
  因为本机只有一个 gmac0。

---

## 5. 编译

### A. GitHub Actions

```bash
cd fur602-mt798x-6.6
git init && git add -A && git commit -m "FUR-602 mt798x-6.6 build kit"
git branch -M main
git remote add origin git@github.com:<你的账号>/fur602-mt798x-6.6.git
git push -u origin main
```

push 完去 Actions 页面，`Build FUR-602` 会自动跑。也可手动 `Run workflow`，`source_ref` 可指定分支。

产物在 artifact `fur602-mt798x-6.6-openwrt-24.10-6.6` 里：

| 文件 | 用途 |
|---|---|
| `*honor*fur*-squashfs-factory.bin` | 首次刷写，U-Boot Web 恢复页上传 |
| `*honor*fur*-squashfs-sysupgrade.bin` | 系统内升级，保留配置 |
| `*honor*fur*-initramfs-kernel.bin` | 救援镜像，只在内存跑，不写 flash |
| `sha256sums.txt` | 校验 |

### B. Linux 本地

```bash
# Debian/Ubuntu 装依赖
sudo apt update && sudo apt install -y build-essential clang flex bison g++ gawk \
  gcc-multilib g++-multilib gettext git libncurses5-dev libncursesw5-dev libssl-dev \
  python3-distutils rsync unzip zlib1g-dev file wget ccache libelf-dev

bash build-local.sh        # 全量编译
bash build-local.sh -c     # 先进 menuconfig
JOBS=8 bash build-local.sh # 指定并发
```

默认工作目录 `~/fur602-build/immortalwrt`，产物在 `bin/targets/mediatek/filogic/`。

---

## 6. 刷机（顺序错了会砖）

1. **先刷 U-Boot**：`hanwckf/bl-mt798x` 的 `mt7981_honor_fur-602`。原厂 U-Boot 有签名锁，刷不进任何第三方固件。
2. **切分区布局到 `expand(114m)`**。U-Boot 默认 `default` 布局只有 64MiB UBI，本固件 `IMAGE_SIZE = 116736k`，直接刷必溢出。
3. 进 U-Boot Web 恢复页（默认 `192.168.1.1`），上传 `*-squashfs-factory.bin`。
4. 起来后默认地址 **`192.168.6.1`**（padavanonly 树默认），用户名 `root`，密码空。

> 参考包的固件把 IP 改成了 `192.168.1.1`。本工程没改，沿用树默认的 `192.168.6.1`——刷完打不开页面先换这个地址试。

**保底**：先准备好 `*-initramfs-kernel.bin` 和 U-Boot 恢复页的进入方式（通常按住 reset 上电）。砖了靠它救。

---

## 7. 上机验证清单

刷完先别急着测速，按顺序确认：

```sh
# ① 驱动加载了吗
dmesg | grep -iE "mt_wifi|mt_wlan|warp|hnat" | head -40
lsmod | grep -E "mt_wifi|mt_warp|hnat"

# ② 无线接口在不在
iw dev
wifi status          # mtwifi-cfg 提供
iwinfo

# ③ Factory 分区和 eeprom（关键）
cat /proc/mtd | grep -i factory
# 分区名是大写 Factory，别 grep 小写
hexdump -C -n 64 /dev/mtd$(cat /proc/mtd | awk -F: '/"Factory"/{print substr($1,4)}')

# ④ 5G 是否真的起来了（不是"看到接口"就算成功）
iw dev wlan1 info
iwinfo wlan1 info | head -20     # TX power 不该是个位数 dBm

# ⑤ HNAT 有没有生效
cat /sys/kernel/debug/hnat/hnat_entry 2>/dev/null | head
# 打流之后这里应该有条目；空的就是没卸载

# ⑥ 加速状态
cat /sys/module/mt_warp/parameters/* 2>/dev/null
```

**5G 起不来 / 功率异常** → 换 eeprom 偏移重编：

```bash
bash set-rf-offset.sh 0x0       # 或 0x80000
```

**无线正常但吞吐上不去** → 关掉 `luci-app-wrtbwmon`（HNAT 卸载后流量统计会失效，而且它会拖慢转发），确认 LuCI → Turbo ACC 里 HNAT/WARP 都开着。

---

## 8. 预期收益 vs 代价

**收益**（相对开源 mt76 版本）：

- NAT 走 HNAT 硬件卸载，千兆满速时 CPU 从 40–60% 掉到个位数
- WiFi 转发走 WARP v2 + WED HW RRO，无线打流不再吃满 CPU
- MTK 硬件 QoS（eqos-mtk），按端口/SSID 限速不牺牲转发性能
- 闭源驱动对 MT7981 + MT7976CN 的射频调教比 mt76 激进，近距离速率和抗干扰通常更好

**代价**：

- 闭源驱动，出问题只能等 padavanonly 跟 MTK SDK 更新；该分支 2026-07-23 之后没动过，内核安全补丁滞后
- 驱动栈是移植过来的（DSA + 6.6 版 mt_wifi），只有参考包出过包，你没实机跑过；5.4 那条线你跑了几天
- 不能用 mt76 生态的调试手段（`iw` 部分命令、`mt76` debugfs 都没了）
- 上游 ImmortalWrt 25.12（6.12）的新特性拿不到，这条线永远停在 6.6

**想稳**：用同目录下的 `fur602-5.4-sdk/`，那是你现在用的固件的可复现版本，设备在该树里原生支持，零移植。**想试新内核**：才用本工程，编完和 5.4 版对比 iperf3 再决定。
