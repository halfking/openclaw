#!/bin/bash
# OpenClaw 自动更新设置脚本
# 功能：快速配置和管理自动更新系统

SCRIPT_DIR="/Users/xutaohuang/workspace/ai/openclaw"
PLIST_FILE="$HOME/Library/LaunchAgents/com.openclaw.auto-update.plist"
LOG_DIR="${SCRIPT_DIR}/logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/setup-${TIMESTAMP}.log"

# 创建日志目录
mkdir -p "${LOG_DIR}"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $@" | tee -a "${LOG_FILE}"
}

# 显示菜单
show_menu() {
    clear
    echo "=========================================="
    echo "  OpenClaw 自动更新管理系统"
    echo "=========================================="
    echo ""
    echo "1. 安装定时任务 (每天凌晨3点)"
    echo "2. 安装定时任务 (每周日凌晨3点)"
    echo "3. 安装定时任务 (自定义时间)"
    echo "4. 查看定时任务状态"
    echo "5. 停用定时任务"
    echo "6. 删除定时任务"
    echo "7. 手动执行更新"
    echo "8. 验证系统状态"
    echo "9. 查看最近日志"
    echo "0. 退出"
    echo ""
    echo "=========================================="
}

# 检查定时任务状态
check_status() {
    log "检查定时任务状态..."
    
    if launchctl list | grep -q "com.openclaw.auto-update"; then
        log "✓ 定时任务已安装并运行"
        return 0
    else
        log "✗ 定时任务未安装"
        return 1
    fi
}

# 安装定时任务
install_scheduler() {
    local schedule_type=$1
    local hour=$2
    local minute=$3
    local weekday=$4
    
    log "安装定时任务..."
    
    # 创建plist文件
    cat > "${PLIST_FILE}" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.openclaw.auto-update</string>
    
    <key>ProgramArguments</key>
    <array>
        <string>${SCRIPT_DIR}/auto-update-simple.sh</string>
    </array>
    
    <key>WorkingDirectory</key>
    <string>${SCRIPT_DIR}</string>
    
    <key>StartCalendarInterval</key>
EOF

    # 根据调度类型添加时间配置
    case $schedule_type in
        "daily")
            cat >> "${PLIST_FILE}" << EOF
    <dict>
        <key>Hour</key>
        <integer>${hour}</integer>
        <key>Minute</key>
        <integer>${minute}</integer>
    </dict>
EOF
            ;;
        "weekly")
            cat >> "${PLIST_FILE}" << EOF
    <dict>
        <key>Weekday</key>
        <integer>${weekday}</integer>
        <key>Hour</key>
        <integer>${hour}</integer>
        <key>Minute</key>
        <integer>${minute}</integer>
    </dict>
EOF
            ;;
    esac
    
    cat >> "${PLIST_FILE}" << EOF
    
    <key>StandardOutPath</key>
    <string>${LOG_DIR}/launchd.log</string>
    
    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/launchd-error.log</string>
    
    <key>Nice</key>
    <integer>10</integer>
    
    <key>RunAtLoad</key>
    <false/>
</dict>
</plist>
EOF

    # 卸载旧任务（如果存在）
    if launchctl list | grep -q "com.openclaw.auto-update"; then
        launchctl unload "${PLIST_FILE}" 2>/dev/null || true
        log "已卸载旧任务"
    fi
    
    # 加载新任务
    if launchctl load "${PLIST_FILE}"; then
        log "✓ 定时任务安装成功"
        log "  - 类型: $([ "$schedule_type" = "daily" ] && echo "每天" || echo "每周")"
        log "  - 时间: ${hour}:${minute}"
        if [ "$schedule_type" = "weekly" ]; then
            local weekday_name=$(date -v "$weekday"d "+%A" 2>/dev/null || echo "第${weekday}天")
            log "  - 星期: ${weekday_name}"
        fi
        return 0
    else
        log "✗ 定时任务安装失败"
        return 1
    fi
}

# 停用定时任务
stop_scheduler() {
    log "停用定时任务..."
    
    if [ ! -f "${PLIST_FILE}" ]; then
        log "✗ 定时任务未安装"
        return 1
    fi
    
    if launchctl unload "${PLIST_FILE}"; then
        log "✓ 定时任务已停用"
        return 0
    else
        log "✗ 定时任务停用失败"
        return 1
    fi
}

# 删除定时任务
remove_scheduler() {
    log "删除定时任务..."
    
    if [ ! -f "${PLIST_FILE}" ]; then
        log "✗ 定时任务未安装"
        return 1
    fi
    
    # 先卸载
    if launchctl list | grep -q "com.openclaw.auto-update"; then
        launchctl unload "${PLIST_FILE}" 2>/dev/null || true
    fi
    
    # 删除文件
    if rm "${PLIST_FILE}"; then
        log "✓ 定时任务已删除"
        return 0
    else
        log "✗ 定时任务删除失败"
        return 1
    fi
}

# 手动执行更新
manual_update() {
    log "手动执行更新..."
    
    if [ ! -f "${SCRIPT_DIR}/auto-update-simple.sh" ]; then
        log "✗ 找不到更新脚本"
        return 1
    fi
    
    cd "${SCRIPT_DIR}"
    if ./auto-update-simple.sh; then
        log "✓ 更新执行成功"
        return 0
    else
        log "✗ 更新执行失败"
        return 1
    fi
}

# 验证系统状态
validate_system() {
    log "验证系统状态..."
    
    if [ -f "${SCRIPT_DIR}/validate-update.sh" ]; then
        cd "${SCRIPT_DIR}"
        ./validate-update.sh
    else
        log "✗ 找不到验证脚本"
        return 1
    fi
}

# 查看最近日志
view_logs() {
    log "查看最近日志..."
    
    echo "=========================================="
    echo "  可用日志文件"
    echo "=========================================="
    
    if [ -d "${LOG_DIR}" ]; then
        ls -lt "${LOG_DIR}"/*.log 2>/dev/null | head -10
    else
        log "✗ 日志目录不存在"
    fi
    
    echo ""
    echo "选择要查看的日志文件 (输入编号，或按回车返回):"
    read -r choice
    
    if [ -n "$choice" ]; then
        local log_file=$(ls -t "${LOG_DIR}"/*.log 2>/dev/null | sed -n "${choice}p")
        if [ -n "$log_file" ]; then
            echo "=========================================="
            echo "  ${log_file}"
            echo "=========================================="
            tail -50 "${log_file}"
        fi
    fi
}

# 主菜单循环
main() {
    while true; do
        show_menu
        read -p "请选择操作 [0-9]: " choice
        
        case $choice in
            1)
                log "安装每天更新任务"
                install_scheduler "daily" 3 0
                read -p "按回车键继续..."
                ;;
            2)
                log "安装每周更新任务"
                install_scheduler "weekly" 3 0 0
                read -p "按回车键继续..."
                ;;
            3)
                log "安装自定义更新任务"
                read -p "请输入小时 (0-23): " hour
                read -p "请输入分钟 (0-59): " minute
                read -p "请输入类型 (1=每天, 2=每周): " type
                
                if [ "$type" = "1" ]; then
                    install_scheduler "daily" "$hour" "$minute"
                elif [ "$type" = "2" ]; then
                    read -p "请输入星期 (0=周日, 1=周一, ..., 6=周六): " weekday
                    install_scheduler "weekly" "$hour" "$minute" "$weekday"
                else
                    log "✗ 无效的类型"
                fi
                read -p "按回车键继续..."
                ;;
            4)
                log "查看定时任务状态"
                if check_status; then
                    echo "定时任务详情:"
                    launchctl list | grep "com.openclaw.auto-update"
                fi
                read -p "按回车键继续..."
                ;;
            5)
                log "停用定时任务"
                stop_scheduler
                read -p "按回车键继续..."
                ;;
            6)
                log "删除定时任务"
                read -p "确定要删除定时任务吗? (y/n): " confirm
                if [ "$confirm" = "y" ]; then
                    remove_scheduler
                else
                    log "已取消删除操作"
                fi
                read -p "按回车键继续..."
                ;;
            7)
                log "手动执行更新"
                manual_update
                read -p "按回车键继续..."
                ;;
            8)
                log "验证系统状态"
                validate_system
                read -p "按回车键继续..."
                ;;
            9)
                log "查看最近日志"
                view_logs
                ;;
            0)
                log "退出设置程序"
                exit 0
                ;;
            *)
                log "✗ 无效的选择"
                read -p "按回车键继续..."
                ;;
        esac
    done
}

# 运行主程序
main "$@"
