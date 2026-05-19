#!/usr/bin/env bash
set -euo pipefail

# ===================== 配置目录 =====================
BASE_DIR="/var/lib/vps-ip-watch"
CONFIG_FILE="${BASE_DIR}/config.conf"
STATE_FILE="${BASE_DIR}/last_ipv4.txt"
REPORT_FILE="${BASE_DIR}/ip_quality_report.txt"
MANAGER_FILE="/usr/local/bin/ipip"
CRON_MARK="# vps-ip-watch-auto"

mkdir -p "$BASE_DIR"
chmod 700 "$BASE_DIR"

# ===================== 保存配置 =====================
save_config() {
cat > "$CONFIG_FILE" <<EOF
VPS_NAME="${VPS_NAME}"
TG_BOT_TOKEN="${TG_BOT_TOKEN}"
TG_CHAT_ID="${TG_CHAT_ID}"
CHECK_INTERVAL="${CHECK_INTERVAL}"
EOF

chmod 600 "$CONFIG_FILE"
}

# ===================== 读取配置 =====================
load_config() {
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
}

# ===================== 首次配置 =====================
first_setup() {
  clear
  echo "=============================="
  echo " VPS IPv4监控首次配置"
  echo "=============================="
  echo

  if [ -r /dev/tty ]; then
    read -rp "请输入 VPS 名称: " VPS_NAME < /dev/tty || VPS_NAME=""
    read -rp "请输入 Telegram Bot Token: " TG_BOT_TOKEN < /dev/tty || TG_BOT_TOKEN=""
    read -rp "请输入 Telegram Chat ID: " TG_CHAT_ID < /dev/tty || TG_CHAT_ID=""
    read -rp "请输入检测间隔分钟数(例如30): " CHECK_INTERVAL < /dev/tty || CHECK_INTERVAL=""
  else
    VPS_NAME=""
    TG_BOT_TOKEN=""
    TG_CHAT_ID=""
    CHECK_INTERVAL=""
  fi

  [ -z "${VPS_NAME:-}" ] && VPS_NAME="未命名VPS"
  [ -z "${CHECK_INTERVAL:-}" ] && CHECK_INTERVAL="30"

  if ! [[ "$CHECK_INTERVAL" =~ ^[0-9]+$ ]]; then
    echo "检测间隔输入无效，已自动改为 30 分钟"
    CHECK_INTERVAL="30"
  fi

  save_config

  echo
  echo "配置已保存"
  echo
}

# ===================== TG发送 =====================
send_tg() {

  local text="$1"
  local i=0

  while [ $i -lt 3 ]; do

    curl -sS -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
      -d "chat_id=${TG_CHAT_ID}" \
      --data-urlencode "text=${text}" \
      -d "disable_web_page_preview=true" \
      >/dev/null 2>&1 && break

    i=$((i+1))
    sleep 3

  done
}

# ===================== 安装面板 =====================
install_manager() {

cat > "$MANAGER_FILE" <<EOF
#!/usr/bin/env bash
curl -sL $1 | bash -- --menu $1
EOF

chmod +x "$MANAGER_FILE"
}

# ===================== 设置定时任务 =====================
setup_cron() {

  SCRIPT_URL="$1"

  crontab -l 2>/dev/null | grep -v "$CRON_MARK" > /tmp/ipipcron || true

  echo "*/${CHECK_INTERVAL} * * * * curl -sL ${SCRIPT_URL} | bash >/var/lib/vps-ip-watch/vps-ip-watch.log 2>&1 ${CRON_MARK}" >> /tmp/ipipcron

  crontab /tmp/ipipcron

  rm -f /tmp/ipipcron

  echo
  echo "已设置自动检测：每 ${CHECK_INTERVAL} 分钟运行一次"
  echo
}

# ===================== 管理面板 =====================
show_menu() {

  SCRIPT_URL="$1"

  while true; do

    clear

    echo "========================="
    echo " VPS IP监控管理面板"
    echo "========================="
    echo
    echo "1. 修改 VPS 名称"
    echo "2. 修改 Telegram 信息"
    echo "3. 修改检测间隔"
    echo "4. 查看当前配置"
    echo "5. 立即执行一次检测"
    echo "6. 卸载脚本"
    echo "0. 退出"
    echo

    read -rp "请输入数字: " CHOICE

    case "$CHOICE" in

      1)

        read -rp "新的 VPS 名称: " VPS_NAME

        save_config

        ;;

      2)

        read -rp "新的 TG Bot Token: " TG_BOT_TOKEN
        read -rp "新的 TG Chat ID: " TG_CHAT_ID

        save_config

        ;;

      3)

        read -rp "新的检测间隔分钟数: " CHECK_INTERVAL

        save_config

        setup_cron "$SCRIPT_URL"

        ;;

      4)

        echo
        echo "VPS名称: $VPS_NAME"
        echo "TG_CHAT_ID: $TG_CHAT_ID"
        echo "检测间隔: ${CHECK_INTERVAL}分钟"
        echo

        read -rp "按回车继续..."

        ;;

      5)

        curl -sL "$SCRIPT_URL" | bash

        read -rp "按回车继续..."

        ;;

      6)

        clear

        echo "========================="
        echo " 即将卸载 VPS IP监控脚本"
        echo "========================="
        echo

        read -rp "确认卸载？(y/n): " CONFIRM

        if [[ "$CONFIRM" == "y" || "$CONFIRM" == "Y" ]]; then

          crontab -l 2>/dev/null | grep -v "$CRON_MARK" > /tmp/ipipuninstall || true

          crontab /tmp/ipipuninstall

          rm -f /tmp/ipipuninstall

          rm -rf "$BASE_DIR"

          rm -f "$MANAGER_FILE"

          echo
          echo "脚本已卸载完成"
          echo

          exit 0
        fi

        ;;

      0)

        exit 0

        ;;

      *)

        echo "输入错误"

        sleep 1

        ;;

    esac

  done
}

# ===================== 主逻辑 =====================

if [ ! -f "$CONFIG_FILE" ]; then
  first_setup
fi

load_config

# 打开面板
if [ "${1:-}" = "--menu" ]; then
  show_menu "${2:-}"
  exit 0
fi

# 首次安装
if [ "${1:-}" != "" ]; then
  setup_cron "$1"
  install_manager "$1"

  CURRENT_IP="$(
  (
    curl -4 -sS --max-time 10 https://api.ipify.org ||
    curl -4 -sS --max-time 10 https://ipv4.icanhazip.com ||
    curl -4 -sS --max-time 10 https://ifconfig.me/ip ||
    curl -4 -sS --max-time 10 https://checkip.amazonaws.com
  ) | head -n1 | tr -d '\r\n'
  )"

  [ -z "$CURRENT_IP" ] && CURRENT_IP="获取失败"

  send_tg "✅ ${VPS_NAME} 连接成功

当前IPv4：${CURRENT_IP}

正在执行首次IPv4质量检测..."

  rm -f /var/lib/vps-ip-watch/last_ipv4.txt

  # 不退出，继续往下执行一次 IP 检测
fi

# 获取当前IPv4
CURRENT_IP="$(
(
curl -4 -sS --max-time 10 https://api.ipify.org ||
curl -4 -sS --max-time 10 https://ipv4.icanhazip.com ||
curl -4 -sS --max-time 10 https://ifconfig.me/ip ||
curl -4 -sS --max-time 10 https://checkip.amazonaws.com
) | head -n1 | tr -d '\r\n'
)"

if [ -z "$CURRENT_IP" ]; then

  send_tg "⚠️ ${VPS_NAME} 获取IPv4失败"

  exit 1
fi

LAST_IP=""

[ -f "$STATE_FILE" ] && LAST_IP="$(cat "$STATE_FILE")"

# IP变更检测
if [ "$CURRENT_IP" != "$LAST_IP" ]; then

  echo "$CURRENT_IP" > "$STATE_FILE"

  NOW="$(date '+%Y-%m-%d %H:%M:%S')"

  send_tg "🚨 VPS IPv4发生变更

VPS：${VPS_NAME}
旧IPv4：${LAST_IP:-首次记录}
新IPv4：${CURRENT_IP}
时间：${NOW}

正在执行IPv4质量检测..."

  # ===================== IP质量检测 =====================

rm -f "$REPORT_FILE" "$REPORT_FILE.tmp" "$REPORT_FILE.all"

curl -sL https://IP.Check.Place | bash -s -- -4 -o "$REPORT_FILE" > "$REPORT_FILE.tmp" 2>&1 || true

cat "$REPORT_FILE" "$REPORT_FILE.tmp" 2>/dev/null > "$REPORT_FILE.all"

REPORT_LINK="$(grep -aoE 'https?://Report\.Check\.Place/ip/[A-Za-z0-9]+\.svg' "$REPORT_FILE.all" | tail -n1 || true)"

if [ -n "$REPORT_LINK" ]; then

  send_tg "📊 ${VPS_NAME} IPv4质量检测报告：

${REPORT_LINK}"

  send_tg "✅ ${VPS_NAME} 本次IP检测任务已完成"

else

  send_tg "⚠️ ${VPS_NAME} IPv4质量检测完成，但没有提取到报告链接

请查看：
${REPORT_FILE}.all"

fi

rm -f "$REPORT_FILE.tmp"

fi
