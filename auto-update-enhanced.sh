#!/bin/bash
# OpenClaw 自动更新脚本 - 增强版
# 功能：定期自动更新OpenClaw，保护现有配置，支持回滚，集成故障排除经验

set -e

# 配置变量
SCRIPT_DIR="/Users/xutaohuang/workspace/ai/openclaw"
OPENCLAW_DIR="${SCRIPT_DIR}"
LOG_DIR="${SCRIPT_DIR}/logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/auto-update-enhanced-${TIMESTAMP}.log"
BACKUP_DIR="${OPENCLAW_DIR}/backups/auto-update"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 初始化
mkdir -p "${LOG_DIR}"
mkdir -p "${BACKUP_DIR}"

# 日志函数
log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 输出到控制台
    case $level in
        "INFO")  echo -e "${GREEN}[INFO]${NC} $message" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
        "DEBUG") echo -e "${BLUE}[DEBUG]${NC} $message" ;;
    esac
    
    # 输出到日志文件
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}"
}

# 错误处理
error_exit() {
    log "ERROR" "$1"
    log "ERROR" "更新失败，请查看日志: ${LOG_FILE}"
    exit 1
}

# 增强配置验证
validate_config_enhanced() {
    log "INFO" "增强配置文件验证..."
    
    local config_valid=true
    
    # 1. 检查主配置文件
    if [ ! -f "${OPENCLAW_DIR}/config-private-multi-agent.json" ]; then
        log "WARN" "主配置文件不存在"
        config_valid=false
    else
        # 验证JSON格式
        if ! python3 -c "import json; json.load(open('${OPENCLAW_DIR}/config-private-multi-agent.json'))" 2>/dev/null; then
            log "ERROR" "主配置文件JSON格式错误"
            config_valid=false
        else
            log "INFO" "主配置文件JSON格式正确"
        fi
        
        # 检查不支持的配置项（基于经验教训）
        if grep -q '"email"' "${OPENCLAW_DIR}/config-private-multi-agent.json" 2>/dev/null; then
            log "WARN" "主配置文件包含不支持的'email'配置项，建议删除"
        fi
    fi
    
    # 2. 检查全局配置文件
    if [ ! -f "${HOME}/.openclaw/openclaw.json" ]; then
        log "WARN" "全局配置文件不存在"
        config_valid=false
    else
        # 验证JSON格式
        if ! python3 -c "import json; json.load(open('${HOME}/.openclaw/openclaw.json'))" 2>/dev/null; then
            log "ERROR" "全局配置文件JSON格式错误"
            config_valid=false
        else
            log "INFO" "全局配置文件JSON格式正确"
        fi
        
        # 检查不支持的配置项
        if grep -q '"email"' "${HOME}/.openclaw/openclaw.json" 2>/dev/null; then
            log "WARN" "全局配置文件包含不支持的'email'配置项，建议删除"
        fi
    fi
    
    # 3. 检查飞书配置
    if grep -q "feishu" "${HOME}/.openclaw/openclaw.json" 2>/dev/null; then
        log "INFO" "飞书配置存在"
        
        # 提取飞书配置信息
        local app_id=$(grep -o '"appId": "[^"]*"' "${HOME}/.openclaw/openclaw.json" 2>/dev/null | cut -d'"' -f4)
        local conn_mode=$(grep -o '"connectionMode": "[^"]*"' "${HOME}/.openclaw/openclaw.json" 2>/dev/null | cut -d'"' -f4)
        
        log "INFO" "飞书配置: App ID=${app_id}, 连接模式=${conn_mode}"
    else
        log "INFO" "未检测到飞书配置"
    fi
    
    if [ "$config_valid" = true ]; then
        log "INFO" "配置验证通过"
        return 0
    else
        log "ERROR" "配置验证失败"
        return 1
    fi
}

# 增强插件验证
validate_plugins_enhanced() {
    log "INFO" "增强插件验证..."
    
    local plugins_valid=true
    
    # 1. 检查飞书插件
    local feishu_plugin_path="${OPENCLAW_DIR}/extensions/feishu"
    if [ -d "${feishu_plugin_path}" ]; then
        # 检查插件目录是否为空（基于经验教训）
        local file_count=$(find "${feishu_plugin_path}" -type f | wc -l)
        if [ "$file_count" -eq 0 ]; then
            log "ERROR" "飞书插件目录为空，插件未正确安装"
            plugins_valid=false
        else
            log "INFO" "飞书插件目录存在且包含 ${file_count} 个文件"
        fi
    else
        log "WARN" "飞书插件目录不存在"
    fi
    
    # 2. 检查插件配置
    if grep -q '"installs"' "${HOME}/.openclaw/openclaw.json" 2>/dev/null; then
        log "INFO" "插件配置存在"
        
        # 检查飞书插件配置
        if grep -q '"feishu"' "${HOME}/.openclaw/openclaw.json" 2>/dev/null; then
            local plugin_version=$(grep -o '"version": "[^"]*"' "${HOME}/.openclaw/openclaw.json" | grep -A1 "feishu" | tail -1 | cut -d'"' -f4)
            log "INFO" "飞书插件版本: ${plugin_version}"
        fi
    else
        log "WARN" "插件配置不存在"
    fi
    
    if [ "$plugins_valid" = true ]; then
        log "INFO" "插件验证通过"
        return 0
    else
        log "ERROR" "插件验证失败"
        return 1
    fi
}

# 增强飞书连接验证
validate_feishu_connection() {
    log "INFO" "验证飞书连接状态..."
    
    # 1. 检查服务是否运行
    if ! lsof -Pi :18789 -sTCP:LISTEN -t >/dev/null 2>&1; then
        log "WARN" "Gateway服务未运行，无法验证飞书连接"
        return 1
    fi
    
    # 2. 检查最近日志中的飞书状态
    local latest_log=$(ls -t /tmp/openclaw/openclaw-*.log 2>/dev/null | head -1)
    if [ -n "$latest_log" ]; then
        # 检查WebSocket连接状态
        if grep -q "WebSocket client started" "${latest_log}" 2>/dev/null; then
            log "INFO" "飞书WebSocket客户端已启动"
        else
            log "WARN" "飞书WebSocket客户端未启动"
        fi
        
        # 检查事件调度器状态
        if grep -q "event-dispatch is ready" "${latest_log}" 2>/dev/null; then
            log "INFO" "飞书事件调度器已就绪"
        else
            log "WARN" "飞书事件调度器未就绪"
        fi
        
        # 检查WS连接状态
        if grep -q "ws client ready" "${latest_log}" 2>/dev/null; then
            log "INFO" "飞书WebSocket连接已就绪"
        else
            log "WARN" "飞书WebSocket连接未就绪"
        fi
        
        # 检查最近的错误
        local recent_feishu_errors=$(tail -100 "${latest_log}" 2>/dev/null | grep -c "feishu.*ERROR\|feishu.*error" || echo "0")
        if [ "$recent_feishu_errors" -gt 0 ]; then
            log "WARN" "最近发现 ${recent_feishu_errors} 条飞书相关错误"
        else
            log "INFO" "最近没有发现飞书相关错误"
        fi
    fi
    
    log "INFO" "飞书连接验证完成"
    return 0
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
    
    # 使用标准停止命令（基于经验教训）
    if [ -f "${OPENCLAW_DIR}/openclaw.mjs" ]; then
        cd "${OPENCLAW_DIR}"
        ./openclaw.mjs gateway stop 2>/dev/null || true
    fi
    
    sleep 2
    
    # 检查端口占用
    local pids=$(lsof -ti :18789 2>/dev/null || true)
    if [ -n "$pids" ]; then
        log "INFO" "发现进程: $pids"
        echo "$pids" | xargs kill -TERM 2>/dev/null || true
        sleep 3
        
        # 如果还在运行，强制杀死
        pids=$(lsof -ti :18789 2>/dev/null || true)
        if [ -n "$pids" ]; then
            log "WARN" "服务未正常停止，强制终止"
            echo "$pids" | xargs kill -9 2>/dev/null || true
            sleep 2
        fi
    fi
    
    log "INFO" "服务已停止"
}

# 启动服务
start_service() {
    log "INFO" "启动OpenClaw服务..."
    
    cd "${OPENCLAW_DIR}"
    
    # 使用配置文件启动
    if [ -f "./start-with-private.sh" ]; then
        nohup ./start-with-private.sh gateway --port 18789 > "${LOG_DIR}/gateway-${TIMESTAMP}.log" 2>&1 &
    elif [ -f "./openclaw.mjs" ]; then
        nohup ./openclaw.mjs gateway --port 18789 > "${LOG_DIR}/gateway-${TIMESTAMP}.log" 2>&1 &
    else
        error_exit "找不到启动脚本"
    fi
    
    # 等待服务启动
    sleep 5
    
    # 验证服务是否启动成功
    if check_service; then
        log "INFO" "服务启动成功"
        return 0
    else
        log "ERROR" "服务启动失败"
        return 1
    fi
}

# 备份配置文件
backup_configs() {
    log "INFO" "备份配置文件..."
    
    local backup_timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="${BACKUP_DIR}/config-backup-${backup_timestamp}"
    
    mkdir -p "${backup_path}"
    
    # 备份主要配置文件
    if [ -f "${OPENCLAW_DIR}/config-private-multi-agent.json" ]; then
        cp "${OPENCLAW_DIR}/config-private-multi-agent.json" "${backup_path}/"
        log "INFO" "已备份: config-private-multi-agent.json"
    fi
    
    if [ -f "${HOME}/.openclaw/openclaw.json" ]; then
        cp "${HOME}/.openclaw/openclaw.json" "${backup_path}/"
        log "INFO" "已备份: ~/.openclaw/openclaw.json"
    fi
    
    # 备份插件配置
    if [ -d "${HOME}/.openclaw/extensions" ]; then
        cp -r "${HOME}/.openclaw/extensions" "${backup_path}/"
        log "INFO" "已备份: 插件目录"
    fi
    
    # 备份Canvas数据
    if [ -d "${HOME}/.openclaw/canvas" ]; then
        cp -r "${HOME}/.openclaw/canvas" "${backup_path}/"
        log "INFO" "已备份: Canvas数据"
    fi
    
    echo "${backup_path}" > "${BACKUP_DIR}/latest-backup.txt"
    log "INFO" "配置备份完成: ${backup_path}"
    
    return 0
}

# 回滚配置
rollback_configs() {
    log "WARN" "开始配置回滚..."
    
    if [ ! -f "${BACKUP_DIR}/latest-backup.txt" ]; then
        error_exit "找不到备份文件"
    fi
    
    local backup_path=$(cat "${BACKUP_DIR}/latest-backup.txt")
    
    if [ ! -d "${backup_path}" ]; then
        error_exit "备份目录不存在: ${backup_path}"
    fi
    
    log "INFO" "从备份恢复: ${backup_path}"
    
    # 恢复配置文件
    if [ -f "${backup_path}/config-private-multi-agent.json" ]; then
        cp "${backup_path}/config-private-multi-agent.json" "${OPENCLAW_DIR}/"
        log "INFO" "已恢复: config-private-multi-agent.json"
    fi
    
    if [ -f "${backup_path}/openclaw.json" ]; then
        cp "${backup_path}/openclaw.json" "${HOME}/.openclaw/"
        log "INFO" "已恢复: ~/.openclaw/openclaw.json"
    fi
    
    # 恢复插件
    if [ -d "${backup_path}/extensions" ]; then
        cp -r "${backup_path}/extensions" "${HOME}/.openclaw/"
        log "INFO" "已恢复: 插件目录"
    fi
    
    # 恢复Canvas数据
    if [ -d "${backup_path}/canvas" ]; then
        cp -r "${backup_path}/canvas" "${HOME}/.openclaw/"
        log "INFO" "已恢复: Canvas数据"
    fi
    
    log "INFO" "配置回滚完成"
}

# 检查Git更新
check_updates() {
    log "INFO" "检查Git更新..."
    
    cd "${OPENCLAW_DIR}"
    
    if [ ! -d ".git" ]; then
        log "WARN" "不是Git仓库，跳过更新检查"
        return 1
    fi
    
    # 获取最新信息
    git fetch origin >/dev/null 2>&1
    
    # 检查是否有更新
    local current_commit=$(git rev-parse HEAD)
    local remote_commit=$(git rev-parse origin/main)
    
    if [ "$current_commit" != "$remote_commit" ]; then
        log "INFO" "发现新版本可用"
        return 0
    else
        log "INFO" "已是最新版本"
        return 1
    fi
}

# 执行Git更新
do_updates() {
    log "INFO" "执行代码更新..."
    
    cd "${OPENCLAW_DIR}"
    
    # 显示更新信息
    local commit_count=$(git rev-list --count HEAD..origin/main)
    log "INFO" "有 ${commit_count} 个新提交"
    
    # 拉取更新
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
    
    local max_attempts=10
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        # 检查端口
        if check_service; then
            # 检查健康端点
            if curl -s http://127.0.0.1:18789/__openclaw__/health >/dev/null 2>&1; then
                log "INFO" "健康检查通过"
                
                # 执行增强验证
                validate_config_enhanced
                validate_plugins_enhanced
                validate_feishu_connection
                
                return 0
            fi
        fi
        
        log "INFO" "健康检查失败，重试中... ($attempt/$max_attempts)"
        sleep 3
        attempt=$((attempt + 1))
    done
    
    log "ERROR" "健康检查失败"
    return 1
}

# 清理旧备份
cleanup_old_backups() {
    log "INFO" "清理旧备份..."
    
    # 保留最近7天的备份
    find "${BACKUP_DIR}" -name "config-backup-*" -type d -mtime +7 -exec rm -rf {} \; 2>/dev/null || true
    
    log "INFO" "旧备份清理完成"
}

# 主函数
main() {
    log "INFO" "=========================================="
    log "INFO" "开始OpenClaw自动更新 (增强版)"
    log "INFO" "时间戳: ${TIMESTAMP}"
    log "INFO" "=========================================="
    
    # 初始验证
    validate_config_enhanced
    validate_plugins_enhanced
    
    # 检查更新
    if ! check_updates; then
        log "INFO" "没有可用更新，执行健康检查"
        health_check
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
    
    return 0
}

# 捕获中断信号
trap 'log "ERROR" "更新被中断"; exit 1' INT TERM

# 执行主函数
main "$@"
