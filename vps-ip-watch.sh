#!/usr/bin/env bash
set -euo pipefail

# ===================== 基础路径 =====================

BASE_DIR="/var/lib/vps-ip-watch"
CONFIG_FILE="${BASE_DIR}/config.conf"
STATE_FILE="${BASE_DIR}/last_ipv4.txt"
REPORT_FILE="${BASE_DIR}/ip_quality_report.txt"

MANAGER_FILE="/usr/local/bin/ipip"
SCRIPT_FILE="/usr/local/bin/vps-ip-watch"

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
  source "$CONFIG_FILE"
}

# ===================== 获取IPv4 =====================

get_ipv4() {

(
curl -4 -sS --max-time 10 https://api.ipify.org ||
curl -4 -sS --max-time 10 https://ipv4.icanhazip.com ||
curl -4 -sS --max-time 10 https://ifconfig.me/ip ||
curl -4 -sS --max-time 10 https://checkip.amazonaws.com
) | head -n1 | tr -d '\r\n'

}

# ===================== TG发送 =====================

send_tg() {

  local text="$1"
  local i=0

  while [ "$i" -lt 3 ]; do

    curl -sS -X POST \
      "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
      -d "chat_id=${TG_CHAT_ID}" \
      --data-urlencode "text=${text}" \
      -d "disable_web_page_preview=true" \
      >/dev/null 2>&1 && return 0

    i=$((i+1))

    sleep 3

  done

  return 1
}

# ===================== 卸载 =====================

uninstall_all() {

  echo
  echo "正在彻底卸载 VPS IP 监控..."
  echo

  pkill -f vps-ip-watch 2>/dev/null || true

  crontab -l 2>/dev/null | grep -v "$CRON_MARK" | crontab - 2>/dev/null || true

  rm -rf "$BASE_DIR"

  rm -f "$MANAGER_FILE"
  rm -f "$SCRIPT_FILE"

  rm -f /etc/systemd/system/vps-ip-watch.service
  rm -f /etc/systemd/system/vps-ip-watch.timer

  systemctl daemon-reload 2>/dev/null || true

  hash -r 2>/dev/null || true

  echo "卸载完成，已彻底清理"
  echo
}

# ===================== 首次配置 =====================

first_setup() {

  clear

  echo "=============================="
  echo " VPS IPv4监控首次配置"
  echo "=============================="
  echo

  read -rp "请输入 VPS 名称: " VPS_NAME

  read -rp "请输入 Telegram Bot Token: " TG_BOT_TOKEN

  read -rp "请输入 Telegram Chat ID: " TG_CHAT_ID

  read -rp "请输入检测间隔分钟数(例如30): " CHECK_INTERVAL

  [ -z "${VPS_NAME:-}" ] && VPS_NAME="未命名VPS"

  [ -z "${CHECK_INTERVAL:-}" ] && CHECK_INTERVAL="30"

  if ! [[ "$CHECK_INTERVAL" =~ ^[0-9]+$ ]]; then
    CHECK_INTERVAL="30"
  fi

  save_config

  echo
  echo "配置已保存"
  echo
}

# ===================== 安装管理器 =====================

install_manager() {

cat > "$MANAGER_FILE" <<'EOF'
#!/usr/bin/env bash

if [ "${1:-}" = "--uninstall" ]; then
  exec /usr/local/bin/vps-ip-watch --uninstall
fi

exec /usr/local/bin/vps-ip-watch --menu
EOF

chmod +x "$MANAGER_FILE"

}

# ===================== 安装自身 =====================

install_self() {

  cp "$0" "$SCRIPT_FILE"

  chmod +x "$SCRIPT_FILE"

}

# ===================== 设置定时任务 =====================

setup_cron() {

  crontab -l 2>/dev/null | grep -v "$CRON_MARK" > /tmp/ipipcron || true

  echo "*/${CHECK_INTERVAL} * * * * ${SCRIPT_FILE} >/var/lib/vps-ip-watch/vps-ip-watch.log 2>&1 ${CRON_MARK}" >> /tmp/ipipcron

  crontab /tmp/ipipcron

  rm -f /tmp/ipipcron

  echo
  echo "已设置自动检测：每 ${CHECK_INTERVAL} 分钟运行一次"
  echo
}

# ===================== 暂停 =====================

pause_wait() {

  echo
  printf "按回车继续..."

  read -r _
}

# ===================== 管理菜单 =====================

show_menu() {

  load_config

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
    echo "6. 测试TG通知"
    echo "7. 卸载脚本"
    echo "0. 退出"
    echo

    printf "请输入数字: "

    read -r CHOICE

    case "$CHOICE" in

      1)

        read -rp "新的 VPS 名称: " VPS_NAME

        save_config

        echo "已保存"

        pause_wait

        ;;

      2)

        read -rp "新的 TG Bot Token: " TG_BOT_TOKEN

        read -rp "新的 TG Chat ID: " TG_CHAT_ID

        save_config

        echo "已保存"

        pause_wait

        ;;

      3)

        read -rp "新的检测间隔分钟数: " CHECK_INTERVAL

        if ! [[ "$CHECK_INTERVAL" =~ ^[0-9]+$ ]]; then
          CHECK_INTERVAL="30"
        fi

        save_config

        setup_cron

        echo "已更新定时任务"

        pause_wait

        ;;

      4)

        echo
        echo "VPS名称: $VPS_NAME"
        echo "TG_CHAT_ID: $TG_CHAT_ID"
        echo "检测间隔: ${CHECK_INTERVAL}分钟"
        echo

        pause_wait

        ;;

      5)

        rm -f "$STATE_FILE"

        "$SCRIPT_FILE"

        pause_wait

        ;;

      6)

        CURRENT_IP="$(get_ipv4)"

        [ -z "$CURRENT_IP" ] && CURRENT_IP="获取失败"

        send_tg "📨 ${VPS_NAME} 测试消息

当前IPv4：${CURRENT_IP}"

        echo "测试消息已发送"

        pause_wait

        ;;

      7)

        clear

        echo "========================="
        echo " 即将卸载 VPS IP监控脚本"
        echo "========================="
        echo

        read -rp "确认卸载？(y/n): " CONFIRM

        if [[ "$CONFIRM" == "y" || "$CONFIRM" == "Y" ]]; then

          uninstall_all

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

# ===================== IP检测逻辑 =====================

run_check() {

  load_config

  CURRENT_IP="$(get_ipv4)"

  if [ -z "$CURRENT_IP" ]; then

    send_tg "⚠️ ${VPS_NAME} 获取IPv4失败"

    exit 1
  fi

  LAST_IP=""

  [ -f "$STATE_FILE" ] && LAST_IP="$(cat "$STATE_FILE")"

  if [ "$CURRENT_IP" != "$LAST_IP" ]; then

    echo "$CURRENT_IP" > "$STATE_FILE"

    NOW="$(date '+%Y-%m-%d %H:%M:%S')"

    send_tg "🚨 VPS IPv4发生变更

VPS：${VPS_NAME}
旧IPv4：${LAST_IP:-首次记录}
新IPv4：${CURRENT_IP}
时间：${NOW}

正在执行IPv4质量检测..."

    rm -f "$REPORT_FILE" "$REPORT_FILE.tmp" "$REPORT_FILE.all"

    curl -sL https://IP.Check.Place | bash -s -- -4 -o "$REPORT_FILE" > "$REPORT_FILE.tmp" 2>&1 || true

    cat "$REPORT_FILE" "$REPORT_FILE.tmp" 2>/dev/null > "$REPORT_FILE.all"

    REPORT_LINK="$(grep -aoE 'https?://Report\.Check\.Place/ip/[A-Za-z0-9]+\.svg' "$REPORT_FILE.all" | tail -n1 || true)"

    if [ -n "$REPORT_LINK" ]; then

      send_tg "📊 ${VPS_NAME} IPv4质量检测报告：

${REPORT_LINK}"

      send_tg "✅ ${VPS_NAME} 本次IP检测任务已完成"

    else

      send_tg "⚠️ ${VPS_NAME} IPv4质量检测完成，但没有提取到报告链接"

    fi

    rm -f "$REPORT_FILE.tmp"

  fi
}

# ===================== 主逻辑 =====================

if [ "${1:-}" = "--uninstall" ]; then

  uninstall_all

  exit 0

fi

if [ "${1:-}" = "--menu" ]; then

  show_menu

  exit 0

fi

if [ ! -f "$CONFIG_FILE" ]; then

  first_setup

  install_self

  install_manager

  setup_cron

  CURRENT_IP="$(get_ipv4)"

  [ -z "$CURRENT_IP" ] && CURRENT_IP="获取失败"

  send_tg "✅ ${VPS_NAME} 连接成功

当前IPv4：${CURRENT_IP}

正在执行首次IPv4质量检测..."

  rm -f "$STATE_FILE"

fi

run_check
