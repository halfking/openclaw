#!/bin/bash
# OpenClaw 自动更新测试脚本 - 简化版本用于测试

SCRIPT_DIR="/Users/xutaohuang/workspace/ai/openclaw"
OPENCLAW_DIR="${SCRIPT_DIR}"
LOG_DIR="${SCRIPT_DIR}/logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/auto-update-test-${TIMESTAMP}.log"

# 创建日志目录
mkdir -p "${LOG_DIR}"

# 日志函数
log_msg() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}"
    echo "[${level}] ${message}"
}

# 测试函数
test_backup() {
    log_msg "INFO" "测试配置备份功能..."
    
    # 创建测试备份
    local backup_dir="${OPENCLAW_DIR}/backups/test-backup-${TIMESTAMP}"
    mkdir -p "${backup_dir}"
    
    # 备份主配置
    if [ -f "${OPENCLAW_DIR}/config-private-multi-agent.json" ]; then
        cp "${OPENCLAW_DIR}/config-private-multi-agent.json" "${backup_dir}/"
        log_msg "SUCCESS" "主配置备份成功"
    fi
    
    # 备份全局配置
    if [ -f "${HOME}/.openclaw/openclaw.json" ]; then
        cp "${HOME}/.openclaw/openclaw.json" "${backup_dir}/"
        log_msg "SUCCESS" "全局配置备份成功"
    fi
    
    log_msg "SUCCESS" "配置备份测试完成"
}

test_service_check() {
    log_msg "INFO" "测试服务状态检查..."
    
    if lsof -Pi :18789 -sTCP:LISTEN -t >/dev/null 2>&1; then
        log_msg "SUCCESS" "服务正在运行 (端口18789)"
        return 0
    else
        log_msg "INFO" "服务未运行"
        return 1
    fi
}

test_config_validation() {
    log_msg "INFO" "测试配置文件验证..."
    
    local config_valid=true
    
    # 验证主配置
    if [ -f "${OPENCLAW_DIR}/config-private-multi-agent.json" ]; then
        if python3 -c "import json; json.load(open('${OPENCLAW_DIR}/config-private-multi-agent.json'))" 2>/dev/null; then
            log_msg "SUCCESS" "主配置文件格式正确"
        else
            log_msg "ERROR" "主配置文件格式错误"
            config_valid=false
        fi
    fi
    
    # 验证全局配置
    if [ -f "${HOME}/.openclaw/openclaw.json" ]; then
        if python3 -c "import json; json.load(open('${HOME}/.openclaw/openclaw.json'))" 2>/dev/null; then
            log_msg "SUCCESS" "全局配置文件格式正确"
        else
            log_msg "ERROR" "全局配置文件格式错误"
            config_valid=false
        fi
    fi
    
    if [ "$config_valid" = true ]; then
        log_msg "SUCCESS" "配置验证测试完成"
        return 0
    else
        log_msg "ERROR" "配置验证测试失败"
        return 1
    fi
}

# 主测试函数
main() {
    log_msg "INFO" "=========================================="
    log_msg "INFO" "开始OpenClaw自动更新测试"
    log_msg "INFO" "时间戳: ${TIMESTAMP}"
    log_msg "INFO" "=========================================="
    
    # 执行测试
    test_backup
    test_service_check
    test_config_validation
    
    log_msg "INFO" "=========================================="
    log_msg "INFO" "测试完成"
    log_msg "INFO" "详细日志: ${LOG_FILE}"
    log_msg "INFO" "=========================================="
    
    return 0
}

main "$@"
