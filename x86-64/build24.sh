#!/bin/bash
# --- 修复补丁：强制替换下载源为北京大学镜像站 ---
echo "正在强制应用镜像源修复补丁..."
MIRROR_URL="https://mirrors.pku.edu.cn/immortalwrt"

# 1. 替换系统级配置
[ -f /etc/opkg.conf ] && sed -i "s|https://downloads.immortalwrt.org|$MIRROR_URL|g" /etc/opkg.conf
[ -d /etc/opkg ] && sed -i "s|https://downloads.immortalwrt.org|$MIRROR_URL|g" /etc/opkg/*.conf 2>/dev/null || true

# --- 原有逻辑开始 ---
source shell/custom-packages.sh
echo "第三方软件包: $CUSTOM_PACKAGES"
echo "编译固件大小为: $PROFILE MB"
echo "Include Docker: $INCLUDE_DOCKER"

echo "Create pppoe-settings"
mkdir -p /home/build/immortalwrt/files/etc/config
cat << EOF > /home/build/immortalwrt/files/etc/config/pppoe-settings
enable_pppoe=${ENABLE_PPPOE}
pppoe_account=${PPPOE_ACCOUNT}
pppoe_password=${PPPOE_PASSWORD}
EOF

if [ -z "$CUSTOM_PACKAGES" ]; then
  echo "⚪️ 未选择 任何第三方软件包"
else
  echo "🔄 正在同步第三方软件仓库..."
  git clone --depth=1 https://github.com/wukongdaily/store.git /tmp/store-run-repo
  mkdir -p /home/build/immortalwrt/extra-packages
  cp -r /tmp/store-run-repo/run/x86/* /home/build/immortalwrt/extra-packages/
  sh shell/prepare-packages.sh
fi

# ============= 插件列表 ==============
PACKAGES="curl luci-i18n-diskman-zh-cn luci-i18n-firewall-zh-cn luci-theme-argon luci-app-argon-config \
luci-i18n-argon-config-zh-cn luci-i18n-package-manager-zh-cn luci-i18n-ttyd-zh-cn \
luci-i18n-passwall-zh-cn luci-app-openclash luci-i18n-homeproxy-zh-cn openssh-sftp-server \
luci-i18n-samba4-zh-cn luci-i18n-filemanager-zh-cn $CUSTOM_PACKAGES"

if [ "$INCLUDE_DOCKER" = "yes" ]; then
    PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"
fi

# 若构建openclash则添加内核
if echo "$PACKAGES" | grep -q "luci-app-openclash"; then
    mkdir -p files/etc/openclash/core
    wget -qO- https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-amd64.tar.gz | tar xOvz > files/etc/openclash/core/clash_meta
    chmod +x files/etc/openclash/core/clash_meta
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat -O files/etc/openclash/GeoIP.dat
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat -O files/etc/openclash/GeoSite.dat
fi

# ============= 关键修复：强制在 make 指令中注入镜像源 =============
echo "$(date '+%Y-%m-%d %H:%M:%S') - Building image..."

# 通过 OPKG_CONF 强制指定已修改的配置文件
make image PROFILE="generic" \
    PACKAGES="$PACKAGES" \
    FILES="/home/build/immortalwrt/files" \
    ROOTFS_PARTSIZE=$PROFILE \
    OPKG_MIRROR="$MIRROR_URL/releases/24.10.5"

if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Build failed!"
    exit 1
fi
echo "$(date '+%Y-%m-%d %H:%M:%S') - Build completed successfully."
