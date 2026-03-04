#!/bin/bash
# OpenClaw 自动更新脚本
# 功能：定期自动更新OpenClaw，保护现有配置，支持回滚

set -e  # 遇到错误立即退出

# 配置变量
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCLAW_DIR="${SCRIPT_DIR}"
LOG_DIR="${SCRIPT_DIR}/logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/auto-update-${TIMESTAMP}.log"
BACKUP_DIR="${OPENCLAW_DIR}/backups/auto-update"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# 创建必要目录
init_dirs() {
    log "INFO" "初始化目录..."
    mkdir -p "${LOG_DIR}" || error_exit "无法创建日志目录"
    mkdir -p "${BACKUP_DIR}" || error_exit "无法创建备份目录"
    mkdir -p "${OPENCLAW_DIR}/.git" || log "WARN" "不是git仓库，跳过git更新"
}

# 检查服务状态
check_service() {
    log "INFO" "检查服务状态..."
    
    if lsof -Pi :18789 -sTCP:LISTEN -t >/dev/null 2>&1; then
        log "INFO" "发现运行中的OpenClaw服务"
        return 0
    else
        log "INFO" "未发现运行中的OpenClaw服务"
        return 1
    fi
}

# 停止服务
stop_service() {
    log "INFO" "停止OpenClaw服务..."
    
    # 查找并停止运行中的openclaw进程
    local pids=$(pgrep -f "openclaw.*gateway" || true)
    if [ -n "$pids" ]; then
        log "INFO" "发现进程: $pids"
        echo "$pids" | xargs kill -TERM 2>/dev/null || true
        
        # 等待进程结束
        local count=0
        while pgrep -f "openclaw.*gateway" >/dev/null 2>&1 && [ $count -lt 30 ]; do
            sleep 1
            count=$((count + 1))
        done
        
        # 如果还在运行，强制杀死
        if pgrep -f "openclaw.*gateway" >/dev/null 2>&1; then
            log "WARN" "服务未正常停止，强制终止"
            pkill -9 -f "openclaw.*gateway" || true
            sleep 2
        fi
        
        log "INFO" "服务已停止"
    else
        log "INFO" "没有运行中的服务需要停止"
    fi
}

# 启动服务
start_service() {
    log "INFO" "启动OpenClaw服务..."
    
    cd "${OPENCLAW_DIR}"
    
    # 使用配置文件启动
    if [ -f "./start-with-private.sh" ]; then
        nohup ./start-with-private.sh gateway --port 18789 > "${LOG_DIR}/gateway-${TIMESTAMP}.log" 2>&1 &
        log "INFO" "服务启动命令已执行"
    elif [ -f "./openclaw.mjs" ]; then
        nohup node ./openclaw.mjs gateway --port 18789 > "${LOG_DIR}/gateway-${TIMESTAMP}.log" 2>&1 &
        log "INFO" "服务启动命令已执行"
    else
        error_exit "找不到启动脚本"
    fi
    
    # 等待服务启动
    sleep 5
    
    # 验证服务是否启动成功
    if lsof -Pi :18789 -sTCP:LISTEN -t >/dev/null 2>&1; then
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

# 验证配置
verify_configs() {
    log "INFO" "验证配置文件..."
    
    local config_valid=true
    
    # 检查主配置文件
    if [ ! -f "${OPENCLAW_DIR}/config-private-multi-agent.json" ]; then
        log "WARN" "找不到主配置文件"
        config_valid=false
    else
        # 验证JSON格式
        if ! python3 -c "import json; json.load(open('${OPENCLAW_DIR}/config-private-multi-agent.json'))" 2>/dev/null; then
            log "ERROR" "主配置文件JSON格式错误"
            config_valid=false
        fi
    fi
    
    # 检查全局配置文件
    if [ ! -f "${HOME}/.openclaw/openclaw.json" ]; then
        log "WARN" "找不到全局配置文件"
        config_valid=false
    else
        # 验证JSON格式
        if ! python3 -c "import json; json.load(open('${HOME}/.openclaw/openclaw.json'))" 2>/dev/null; then
            log "ERROR" "全局配置文件JSON格式错误"
            config_valid=false
        fi
    fi
    
    if [ "$config_valid" = false ]; then
        log "ERROR" "配置验证失败"
        return 1
    fi
    
    log "INFO" "配置验证通过"
    return 0
}

# 健康检查
health_check() {
    log "INFO" "执行健康检查..."
    
    local max_attempts=10
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        # 检查端口
        if lsof -Pi :18789 -sTCP:LISTEN -t >/dev/null 2>&1; then
            log "INFO" "端口18789已监听"
            
            # 检查健康端点
            if curl -s http://127.0.0.1:18789/__openclaw__/health >/dev/null 2>&1; then
                log "INFO" "健康检查通过"
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

# 生成更新报告
generate_report() {
    local status=$1
    local report_file="${LOG_DIR}/update-report-${TIMESTAMP}.html"
    
    cat > "${report_file}" << EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>OpenClaw 更新报告</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f0f0f0; padding: 15px; border-radius: 5px; }
        .success { color: green; font-weight: bold; }
        .failure { color: red; font-weight: bold; }
        .section { margin: 15px 0; padding: 10px; border: 1px solid #ddd; border-radius: 5px; }
        .timestamp { color: #666; font-size: 0.9em; }
    </style>
</head>
<body>
    <div class="header">
        <h1>OpenClaw 自动更新报告</h1>
        <p>更新时间: ${TIMESTAMP}</p>
        <p>状态: <span class="${status}">${status}</span></p>
    </div>
    
    <div class="section">
        <h2>更新日志</h2>
        <pre>$(tail -50 "${LOG_FILE}")</pre>
    </div>
    
    <div class="section">
        <h2>配置文件状态</h2>
        <ul>
            <li>主配置文件: $([ -f "${OPENCLAW_DIR}/config-private-multi-agent.json" ] && echo "✓ 存在" || echo "✗ 缺失")</li>
            <li>全局配置文件: $([ -f "${HOME}/.openclaw/openclaw.json" ] && echo "✓ 存在" || echo "✗ 缺失")</li>
            <li>备份目录: $([ -d "${BACKUP_DIR}" ] && echo "✓ 存在" || echo "✗ 缺失")</li>
        </ul>
    </div>
    
    <div class="section">
        <h2>服务状态</h2>
        <p>端口18789: $(lsof -Pi :18789 -sTCP:LISTEN -t >/dev/null 2>&1 && echo "✓ 正在监听" || echo "✗ 未监听")</p>
    </div>
</body>
</html>
