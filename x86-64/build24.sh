#!/bin/bash
# =========================================================
# 修复补丁：针对 ImmortalWrt 24.10 强制重写 ImageBuilder 仓库地址
# =========================================================
echo "正在执行深层镜像源替换补丁..."

# 定义北京大学镜像源（目前最稳定的国内源）
MIRROR_URL="https://mirrors.pku.edu.cn/immortalwrt"

# 1. 强制重写核心配置文件 repositories.conf
# ImageBuilder 在构建时会读取这个文件，我们直接把里面的 downloads.immortalwrt.org 全部换掉
if [ -f "repositories.conf" ]; then
    sed -i "s|https://downloads.immortalwrt.org|$MIRROR_URL|g" repositories.conf
    echo "✅ 成功重写当前目录下的 repositories.conf"
fi

# 2. 补充替换系统级 opkg 配置，双重保险
[ -f /etc/opkg.conf ] && sed -i "s|https://downloads.immortalwrt.org|$MIRROR_URL|g" /etc/opkg.conf
[ -d /etc/opkg ] && sed -i "s|https://downloads.immortalwrt.org|$MIRROR_URL|g" /etc/opkg/*.conf 2>/dev/null || true

# =========================================================
# 原有逻辑继续执行
# =========================================================
source shell/custom-packages.sh
echo "第三方软件包: $CUSTOM_PACKAGES"
echo "编译固件大小为: $PROFILE MB"
echo "Include Docker: $INCLUDE_DOCKER"

echo "创建 PPPoE 配置信息..."
mkdir -p /home/build/immortalwrt/files/etc/config
cat << EOF > /home/build/immortalwrt/files/etc/config/pppoe-settings
enable_pppoe=${ENABLE_PPPOE}
pppoe_account=${PPPOE_ACCOUNT}
pppoe_password=${PPPOE_PASSWORD}
EOF

if [ -z "$CUSTOM_PACKAGES" ]; then
  echo "⚪️ 未选择任何第三方软件包"
else
  echo "🔄 正在同步第三方软件仓库..."
  git clone --depth=1 https://github.com/wukongdaily/store.git /tmp/store-run-repo
  mkdir -p /home/build/immortalwrt/extra-packages
  cp -r /tmp/store-run-repo/run/x86/* /home/build/immortalwrt/extra-packages/
  sh shell/prepare-packages.sh
fi

# 组装软件包列表
PACKAGES="curl luci-i18n-diskman-zh-cn luci-i18n-firewall-zh-cn luci-theme-argon luci-app-argon-config \
luci-i18n-argon-config-zh-cn luci-i18n-package-manager-zh-cn luci-i18n-ttyd-zh-cn \
luci-i18n-passwall-zh-cn luci-app-openclash luci-i18n-homeproxy-zh-cn openssh-sftp-server \
luci-i18n-samba4-zh-cn luci-i18n-filemanager-zh-cn $CUSTOM_PACKAGES"

[ "$INCLUDE_DOCKER" = "yes" ] && PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"

# 下载 OpenClash 内核
if echo "$PACKAGES" | grep -q "luci-app-openclash"; then
    echo "下载 OpenClash 内核..."
    mkdir -p files/etc/openclash/core
    wget -qO- https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-amd64.tar.gz | tar xOvz > files/etc/openclash/core/clash_meta
    chmod +x files/etc/openclash/core/clash_meta
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat -O files/etc/openclash/GeoIP.dat
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat -O files/etc/openclash/GeoSite.dat
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始构建固件..."

# 执行构建
make image PROFILE="generic" \
    PACKAGES="$PACKAGES" \
    FILES="/home/build/immortalwrt/files" \
    ROOTFS_PARTSIZE=$PROFILE

if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - 错误：固件构建失败！"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - 固件构建成功！"
