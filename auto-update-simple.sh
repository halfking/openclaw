#!/bin/bash
# OpenClaw 自动更新脚本 - 简化版本
# 功能：定期自动更新OpenClaw，保护现有配置，支持回滚

set -e

# 配置变量
SCRIPT_DIR="/Users/xutaohuang/workspace/ai/openclaw"
OPENCLAW_DIR="${SCRIPT_DIR}"
LOG_DIR="${SCRIPT_DIR}/logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/auto-update-${TIMESTAMP}.log"
BACKUP_DIR="${OPENCLAW_DIR}/backups/auto-update"

# 初始化
mkdir -p "${LOG_DIR}"
mkdir -p "${BACKUP_DIR}"

# 日志函数
log() {
    local level=$1
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $@" | tee -a "${LOG_FILE}"
}

# 错误处理
error_exit() {
    log "ERROR" "$1"
    log "ERROR" "更新失败，查看日志: ${LOG_FILE}"
    exit 1
}

# 检查服务状态
check_service() {
    if lsof -Pi :18789 -sTCP:LISTEN -t >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# 停止服务
stop_service() {
    log "INFO" "停止OpenClaw服务..."
    local pids=$(pgrep -f "openclaw.*gateway" || true)
    if [ -n "$pids" ]; then
        echo "$pids" | xargs kill -TERM 2>/dev/null || true
        sleep 5
        if pgrep -f "openclaw.*gateway" >/dev/null 2>&1; then
            pkill -9 -f "openclaw.*gateway" || true
        fi
        log "INFO" "服务已停止"
    fi
}

# 启动服务
start_service() {
    log "INFO" "启动OpenClaw服务..."
    cd "${OPENCLAW_DIR}"
    nohup ./start-with-private.sh gateway --port 18789 > "${LOG_DIR}/gateway-${TIMESTAMP}.log" 2>&1 &
    sleep 5
    
    if check_service; then
        log "INFO" "服务启动成功"
        return 0
    else
        log "ERROR" "服务启动失败"
        return 1
    fi
}

# 备份配置
backup_configs() {
    log "INFO" "备份配置文件..."
    local backup_path="${BACKUP_DIR}/config-backup-${TIMESTAMP}"
    mkdir -p "${backup_path}"
    
    # 备份配置文件
    [ -f "${OPENCLAW_DIR}/config-private-multi-agent.json" ] && cp "${OPENCLAW_DIR}/config-private-multi-agent.json" "${backup_path}/"
    [ -f "${HOME}/.openclaw/openclaw.json" ] && cp "${HOME}/.openclaw/openclaw.json" "${backup_path}/"
    [ -d "${HOME}/.openclaw/extensions" ] && cp -r "${HOME}/.openclaw/extensions" "${backup_path}/"
    [ -d "${HOME}/.openclaw/canvas" ] && cp -r "${HOME}/.openclaw/canvas" "${backup_path}/"
    
    echo "${backup_path}" > "${BACKUP_DIR}/latest-backup.txt"
    log "INFO" "配置备份完成: ${backup_path}"
}

# 回滚配置
rollback_configs() {
    log "WARN" "开始配置回滚..."
    if [ ! -f "${BACKUP_DIR}/latest-backup.txt" ]; then
        error_exit "找不到备份文件"
    fi
    
    local backup_path=$(cat "${BACKUP_DIR}/latest-backup.txt")
    if [ ! -d "${backup_path}" ]; then
        error_exit "备份目录不存在"
    fi
    
    # 恢复配置
    [ -f "${backup_path}/config-private-multi-agent.json" ] && cp "${backup_path}/config-private-multi-agent.json" "${OPENCLAW_DIR}/"
    [ -f "${backup_path}/openclaw.json" ] && cp "${backup_path}/openclaw.json" "${HOME}/.openclaw/"
    [ -d "${backup_path}/extensions" ] && cp -r "${backup_path}/extensions" "${HOME}/.openclaw/"
    [ -d "${backup_path}/canvas" ] && cp -r "${backup_path}/canvas" "${HOME}/.openclaw/"
    
    log "INFO" "配置回滚完成"
}

# 检查更新
check_updates() {
    cd "${OPENCLAW_DIR}"
    if [ ! -d ".git" ]; then
        log "WARN" "不是Git仓库"
        return 1
    fi
    
    git fetch origin >/dev/null 2>&1
    local current=$(git rev-parse HEAD)
    local remote=$(git rev-parse origin/main)
    
    if [ "$current" != "$remote" ]; then
        log "INFO" "发现新版本可用"
        return 0
    else
        log "INFO" "已是最新版本"
        return 1
    fi
}

# 执行更新
do_updates() {
    log "INFO" "执行代码更新..."
    cd "${OPENCLAW_DIR}"
    local commit_count=$(git rev-list --count HEAD..origin/main)
    log "INFO" "有 ${commit_count} 个新提交"
    
    git pull origin main >> "${LOG_FILE}" 2>&1 || error_exit "Git更新失败"
    log "INFO" "代码更新完成"
}

# 更新依赖
update_dependencies() {
    log "INFO" "更新依赖..."
    cd "${OPENCLAW_DIR}"
    pnpm install >> "${LOG_FILE}" 2>&1 || error_exit "依赖更新失败"
    log "INFO" "依赖更新完成"
}

# 构建项目
build_project() {
    log "INFO" "构建项目..."
    cd "${OPENCLAW_DIR}"
    pnpm build >> "${LOG_FILE}" 2>&1 || error_exit "项目构建失败"
    log "INFO" "项目构建完成"
}

# 健康检查
health_check() {
    log "INFO" "执行健康检查..."
    for i in {1..10}; do
        if check_service; then
            if curl -s http://127.0.0.1:18789/__openclaw__/health >/dev/null 2>&1; then
                log "INFO" "健康检查通过"
                return 0
            fi
        fi
        log "INFO" "健康检查失败，重试中... ($i/10)"
        sleep 3
    done
    log "ERROR" "健康检查失败"
    return 1
}

# 清理旧备份
cleanup_old_backups() {
    log "INFO" "清理旧备份..."
    find "${BACKUP_DIR}" -name "config-backup-*" -type d -mtime +7 -exec rm -rf {} \; 2>/dev/null || true
    log "INFO" "旧备份清理完成"
}

# 主函数
main() {
    log "INFO" "=========================================="
    log "INFO" "开始OpenClaw自动更新"
    log "INFO" "时间戳: ${TIMESTAMP}"
    log "INFO" "=========================================="
    
    # 检查更新
    if ! check_updates; then
        log "INFO" "没有可用更新，退出"
        exit 0
    fi
    
    # 备份配置
    backup_configs || error_exit "配置备份失败"
    
    # 停止服务
    if check_service; then
        stop_service
    fi
    
    # 执行更新
    local update_success=true
    do_updates || update_success=false
    update_dependencies || update_success=false
    build_project || update_success=false
    
    if [ "$update_success" = false ]; then
        log "ERROR" "更新失败，开始回滚"
        rollback_configs
        error_exit "更新失败并已回滚"
    fi
    
    # 启动服务
    if ! start_service; then
        log "ERROR" "服务启动失败，开始回滚"
        rollback_configs
        start_service
        error_exit "服务启动失败并已回滚"
    fi
    
    # 健康检查
    if ! health_check; then
        log "ERROR" "健康检查失败，开始回滚"
        stop_service || true
        rollback_configs
        start_service || true
        error_exit "健康检查失败并已回滚"
    fi
    
    # 清理旧备份
    cleanup_old_backups
    
    log "INFO" "=========================================="
    log "INFO" "更新成功完成"
    log "INFO" "=========================================="
}

# 捕获中断信号
trap 'log "ERROR" "更新被中断"; exit 1' INT TERM

# 执行主函数
main "$@"
