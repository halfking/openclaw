#!/bin/bash
# OpenClaw 更新验证脚本
# 功能：验证更新脚本的各项功能

SCRIPT_DIR="/Users/xutaohuang/workspace/ai/openclaw"
LOG_DIR="${SCRIPT_DIR}/logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/validate-${TIMESTAMP}.log"

mkdir -p "${LOG_DIR}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $@" | tee -a "${LOG_FILE}"
}

test_service() {
    log "=== 测试服务检查 ==="
    if lsof -Pi :18789 -sTCP:LISTEN -t >/dev/null 2>&1; then
        log "✓ 服务正在运行 (端口18789)"
        return 0
    else
        log "✗ 服务未运行"
        return 1
    fi
}

test_configs() {
    log "=== 测试配置文件 ==="
    
    local all_ok=true
    
    # 检查主配置
    if [ -f "${SCRIPT_DIR}/config-private-multi-agent.json" ]; then
        if python3 -c "import json; json.load(open('${SCRIPT_DIR}/config-private-multi-agent.json'))" 2>/dev/null; then
            log "✓ 主配置文件格式正确"
        else
            log "✗ 主配置文件格式错误"
            all_ok=false
        fi
    else
        log "✗ 主配置文件不存在"
        all_ok=false
    fi
    
    # 检查全局配置
    if [ -f "${HOME}/.openclaw/openclaw.json" ]; then
        if python3 -c "import json; json.load(open('${HOME}/.openclaw/openclaw.json'))" 2>/dev/null; then
            log "✓ 全局配置文件格式正确"
        else
            log "✗ 全局配置文件格式错误"
            all_ok=false
        fi
    else
        log "✗ 全局配置文件不存在"
        all_ok=false
    fi
    
    # 检查插件
    if [ -d "${HOME}/.openclaw/extensions/feishu" ]; then
        log "✓ 飞书插件目录存在"
    else
        log "✗ 飞书插件目录不存在"
        all_ok=false
    fi
    
    return 0
}

test_scripts() {
    log "=== 测试脚本文件 ==="
    
    local scripts_ok=true
    
    # 检查启动脚本
    if [ -f "${SCRIPT_DIR}/start-with-private.sh" ]; then
        if [ -x "${SCRIPT_DIR}/start-with-private.sh" ]; then
            log "✓ 启动脚本存在且可执行"
        else
            log "✗ 启动脚本不可执行"
            chmod +x "${SCRIPT_DIR}/start-with-private.sh"
            log "✓ 已修复权限"
        fi
    else
        log "✗ 启动脚本不存在"
        scripts_ok=false
    fi
    
    # 检查更新脚本
    if [ -f "${SCRIPT_DIR}/auto-update-simple.sh" ]; then
        if [ -x "${SCRIPT_DIR}/auto-update-simple.sh" ]; then
            log "✓ 自动更新脚本存在且可执行"
        else
            log "✗ 自动更新脚本不可执行"
            chmod +x "${SCRIPT_DIR}/auto-update-simple.sh"
            log "✓ 已修复权限"
        fi
    else
        log "✗ 自动更新脚本不存在"
        scripts_ok=false
    fi
    
    return 0
}

test_backup() {
    log "=== 测试备份功能 ==="
    
    local backup_dir="${SCRIPT_DIR}/backups/test-backup-${TIMESTAMP}"
    mkdir -p "${backup_dir}"
    
    # 测试备份主配置
    if [ -f "${SCRIPT_DIR}/config-private-multi-agent.json" ]; then
        if cp "${SCRIPT_DIR}/config-private-multi-agent.json" "${backup_dir}/"; then
            log "✓ 主配置备份成功"
            rm "${backup_dir}/config-private-multi-agent.json"
        else
            log "✗ 主配置备份失败"
        fi
    fi
    
    # 测试备份全局配置
    if [ -f "${HOME}/.openclaw/openclaw.json" ]; then
        if cp "${HOME}/.openclaw/openclaw.json" "${backup_dir}/"; then
            log "✓ 全局配置备份成功"
            rm "${backup_dir}/openclaw.json"
        else
            log "✗ 全局配置备份失败"
        fi
    fi
    
    # 清理测试备份
    rmdir "${backup_dir}" 2>/dev/null || true
    rmdir "${SCRIPT_DIR}/backups/test-backup-${TIMESTAMP}" 2>/dev/null || true
    
    return 0
}

main() {
    log "=========================================="
    log "开始OpenClaw更新验证"
    log "时间戳: ${TIMESTAMP}"
    log "=========================================="
    
    test_service
    test_configs
    test_scripts
    test_backup
    
    log "=========================================="
    log "验证完成"
    log "详细日志: ${LOG_FILE}"
    log "=========================================="
}

main "$@"
