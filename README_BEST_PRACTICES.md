# OpenClaw 最佳实践与故障排除指南

**文档版本：** 1.0  
**最后更新：** 2026-03-05  
**基于经验：** OpenClaw 2026.2.22 → 2026.3.3 升级项目

## 📋 目录

1. [概述](#概述)
2. [安装与配置](#安装与配置)
3. [升级最佳实践](#升级最佳实践)
4. [故障排除指南](#故障排除指南)
5. [性能优化](#性能优化)
6. [安全管理](#安全管理)
7. [监控与维护](#监控与维护)

## 概述

本文档总结了在OpenClaw升级项目中积累的最佳实践和故障排除经验，为后续的系统维护、升级和故障排除提供指导。

### 关键经验总结

> 🎯 **核心原则：**
>
> 1. **备份优先** - 任何变更前必须备份
> 2. **验证先行** - 修改前验证兼容性
> 3. **逐步执行** - 分阶段实施，每阶段验证
> 4. **完整回滚** - 任何步骤失败立即回滚
> 5. **详细记录** - 记录每个步骤和决策

## 安装与配置

### 环境准备

#### 推荐环境

```bash
# 操作系统
macOS 12+ / Ubuntu 20.04+ / Windows 10+ with WSL2

# Node.js
Node.js 18+ / 20+ (推荐20 LTS)

# 包管理器
pnpm 8+ (推荐) / npm 9+ / yarn 1.22+

# 磁盘空间
至少 2GB 可用空间

# 内存
至少 4GB RAM (推荐8GB+)
```

#### 安装步骤

```bash
# 1. 克隆项目
git clone https://github.com/openclaw/openclaw.git
cd openclaw

# 2. 安装依赖
pnpm install

# 3. 构建项目
pnpm build

# 4. 配置系统
cp config-private-multi-agent.json ~/.openclaw/openclaw.json

# 5. 启动服务
./start-with-private.sh gateway --port 18789
```

### 配置最佳实践

#### 1. 配置文件管理

**原则：**

- ✅ 使用版本控制管理配置文件
- ✅ 配置文件包含时间戳备份
- ✅ 区分开发和生产配置
- ✅ 敏感信息使用环境变量

**示例配置结构：**

```
openclaw/
├── config-private-multi-agent.json      # 主配置文件
├── config-private-multi-agent.json.backup-20260305_002151  # 时间戳备份
├── config-dev.json                   # 开发环境配置
├── config-prod.json                  # 生产环境配置
└── .env.example                     # 环境变量示例
```

#### 2. 配置验证

**重要：** 配置文件修改前必须进行验证

```bash
# JSON格式验证
python3 -c "import json; json.load(open('config.json'))"

# 使用OpenClaw内置验证
./openclaw.mjs doctor

# 生成验证报告
./openclaw.mjs doctor --report > validation-report.json
```

#### 3. 配置兼容性检查

**基于经验教训：**

❌ **不支持的配置项：**

```json
{
  "email": { ... },  // OpenClaw不支持
  "unsupported_key": "value"  // 会导致启动失败
}
```

✅ **推荐配置：**

```json
{
  "models": { ... },
  "agents": { ... },
  "channels": {
    "feishu": { ... }  // 支持的配置
  }
}
```

**验证脚本：**

```bash
#!/bin/bash
# 检查不支持的配置项

UNSUPPORTED_KEYS=("email" "unsupported_key" "legacy_config")

CONFIG_FILE="$HOME/.openclaw/openclaw.json"

for key in "${UNSUPPORTED_KEYS[@]}"; do
    if grep -q "\"${key}\"" "$CONFIG_FILE"; then
        echo "警告：发现不支持的配置项: $key"
        echo "建议：从配置文件中删除此项"
    fi
done
```

## 升级最佳实践

### 升级前准备

#### 1. 环境备份清单

```bash
#!/bin/bash
# 升级前完整备份脚本

BACKUP_DIR="backups/pre-upgrade-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

# 1. 配置文件备份
cp config-private-multi-agent.json "$BACKUP_DIR/"
cp ~/.openclaw/openclaw.json "$BACKUP_DIR/"

# 2. 插件备份
cp -r ~/.openclaw/extensions "$BACKUP_DIR/"

# 3. Canvas数据备份
cp -r ~/.openclaw/canvas "$BACKUP_DIR/"

# 4. 日志备份
cp -r logs "$BACKUP_DIR/"
cp -r /tmp/openclaw "$BACKUP_DIR/"

# 5. Git状态备份
git status > "$BACKUP_DIR/git-status.txt"
git log -10 > "$BACKUP_DIR/git-log.txt"
git diff > "$BACKUP_DIR/git-diff.txt"

echo "备份完成: $BACKUP_DIR"
```

#### 2. 升级前检查清单

- [ ] 确认当前版本正常运行
- [ ] 备份所有配置文件和数据
- [ ] 记录当前运行状态和端口占用
- [ ] 准备详细的回滚计划
- [ ] 通知相关用户维护时间
- [ ] 准备测试用例验证升级结果

#### 3. 回滚计划

**回滚触发条件：**

1. 配置文件加载失败
2. 服务无法启动
3. 关键功能不可用（如飞书连接）
4. 健康检查失败
5. 性能下降超过50%

**回滚步骤：**

```bash
#!/bin/bash
# 标准化回滚脚本

BACKUP_DIR=$1  # 备份目录

# 1. 停止服务
./openclaw.mjs gateway stop

# 2. 恢复配置文件
cp "$BACKUP_DIR/config-private-multi-agent.json" ./
cp "$BACKUP_DIR/openclaw.json" ~/.openclaw/

# 3. 恢复插件
cp -r "$BACKUP_DIR/extensions" ~/.openclaw/

# 4. 恢复Canvas数据
cp -r "$BACKUP_DIR/canvas" ~/.openclaw/

# 5. 恢复Git版本
git reset --hard $(cat "$BACKUP_DIR/git-log.txt" | head -1 | cut -d' ' -f1)

# 6. 重新构建
pnpm install
pnpm build

# 7. 重启服务
./start-with-private.sh gateway --port 18789

# 8. 验证服务
./validate-update.sh
```

### 升级过程控制

#### 1. 分阶段升级

```bash
#!/bin/bash
# 分阶段升级流程

echo "=== 阶段1: 准备阶段 ==="
./pre-upgrade-check.sh
exit_on_error

echo "=== 阶段2: 代码更新 ==="
git pull origin main
./validate-code-update.sh
exit_on_error

echo "=== 阶段3: 依赖更新 ==="
pnpm install
./validate-dependencies.sh
exit_on_error

echo "=== 阶段4: 构建阶段 ==="
pnpm build
./validate-build.sh
exit_on_error

echo "=== 阶段5: 配置整合 ==="
./merge-configs.sh
./validate-configs.sh
exit_on_error

echo "=== 阶段6: 服务重启 ==="
./restart-services.sh
./health-check.sh
exit_on_error

echo "=== 阶段7: 功能验证 ==="
./validate-functions.sh
exit_on_error

echo "=== 升级完成 ==="
```

#### 2. 详细日志记录

**重要：** 每个步骤都要有详细的日志记录

```bash
#!/bin/bash
# 增强日志函数

LOG_FILE="logs/upgrade-$(date +%Y%m%d_%H%M%S).log"

log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # 输出到控制台
    echo "[$timestamp] [$level] $message"

    # 输出到日志文件
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"

    # 输出到系统日志
    logger -t openclaw-upgrade "[$level] $message"
}

log_step() {
    local step=$1
    local description=$2
    log "INFO" "步骤 $step: $description"
}

log_result() {
    local result=$1
    local details=$2

    if [ "$result" = "SUCCESS" ]; then
        log "SUCCESS" "$details"
    else
        log "ERROR" "$details"
        exit 1
    fi
}
```

#### 3. 错误处理机制

```bash
#!/bin/bash
# 全局错误处理

set -e  # 遇到错误立即退出

# 错误处理函数
handle_error() {
    local line_number=$1
    local command_name=$2
    local exit_code=$3

    log "ERROR" "脚本在行 $line_number 出错"
    log "ERROR" "命令: $command_name"
    log "ERROR" "退出码: $exit_code"

    # 自动回滚
    log "WARN" "开始自动回滚..."
    ./rollback-from-backup.sh "$BACKUP_DIR"

    exit 1
}

# 设置错误陷阱
trap 'handle_error ${LINENO} "$BASH_COMMAND" $?' ERR
```

### 升级后验证

#### 1. 服务状态验证

```bash
#!/bin/bash
# 服务状态全面验证

validate_service_status() {
    echo "=== 服务状态验证 ==="

    # 1. 检查端口监听
    if lsof -Pi :18789 -sTCP:LISTEN -t >/dev/null 2>&1; then
        echo "✓ Gateway服务正在运行 (端口18789)"
    else
        echo "✗ Gateway服务未运行"
        return 1
    fi

    # 2. 检查进程状态
    if pgrep -f "openclaw.*gateway" >/dev/null 2>&1; then
        echo "✓ Gateway进程正在运行"
    else
        echo "✗ Gateway进程未运行"
        return 1
    fi

    # 3. 检查健康端点
    if curl -s http://127.0.0.1:18789/__openclaw__/health >/dev/null 2>&1; then
        echo "✓ 健康检查端点正常"
    else
        echo "✗ 健康检查端点异常"
        return 1
    fi

    # 4. 检查WebSocket连接
    if curl -s http://127.0.0.1:18789/__openclaw__/ws >/dev/null 2>&1; then
        echo "✓ WebSocket端点正常"
    else
        echo "✗ WebSocket端点异常"
        return 1
    fi

    echo "✓ 服务状态验证通过"
    return 0
}
```

#### 2. 功能验证

```bash
#!/bin/bash
# 核心功能验证

validate_core_functions() {
    echo "=== 核心功能验证 ==="

    # 1. 配置加载验证
    if [ -f "$HOME/.openclaw/openclaw.json" ]; then
        if python3 -c "import json; json.load(open('$HOME/.openclaw/openclaw.json'))" 2>/dev/null; then
            echo "✓ 配置文件加载正常"
        else
            echo "✗ 配置文件格式错误"
            return 1
        fi
    else
        echo "✗ 配置文件不存在"
        return 1
    fi

    # 2. 模型配置验证
    if grep -q '"models"' "$HOME/.openclaw/openclaw.json"; then
        echo "✓ 模型配置存在"
    else
        echo "✗ 模型配置不存在"
        return 1
    fi

    # 3. 智能体配置验证
    if grep -q '"agents"' "$HOME/.openclaw/openclaw.json"; then
        echo "✓ 智能体配置存在"
    else
        echo "✗ 智能体配置不存在"
        return 1
    fi

    # 4. 插件状态验证
    if [ -d "$HOME/.openclaw/extensions/feishu" ]; then
        local file_count=$(find "$HOME/.openclaw/extensions/feishu" -type f | wc -l)
        if [ "$file_count" -gt 0 ]; then
            echo "✓ 飞书插件正常 (包含 $file_count 个文件)"
        else
            echo "✗ 飞书插件目录为空"
            return 1
        fi
    else
        echo "✗ 飞书插件目录不存在"
        return 1
    fi

    echo "✓ 核心功能验证通过"
    return 0
}
```

## 故障排除指南

### 常见问题与解决方案

#### 问题1：配置兼容性问题

**症状：**

- 服务启动失败
- 日志显示"Config invalid"
- 无法加载配置文件

**原因：**
配置文件包含不支持的配置项或格式错误

**解决方案：**

```bash
# 1. 检查配置文件格式
python3 -c "import json; json.load(open('~/.openclaw/openclaw.json'))"

# 2. 查找不支持的配置项
grep -n '"email"\|"unsupported"\|"legacy"' ~/.openclaw/openclaw.json

# 3. 使用OpenClaw内置验证
./openclaw.mjs doctor --fix

# 4. 从备份恢复配置
cp backups/config-backup-*/openclaw.json ~/.openclaw/
```

**预防措施：**

- 配置文件修改前进行格式验证
- 参考最新版本的配置文档
- 使用版本控制管理配置变更

#### 问题2：飞书插件问题

**症状：**

- 通过飞书发送消息，OpenClaw没有响应
- 飞书工具无法使用
- WebSocket连接失败

**诊断流程：**

```bash
#!/bin/bash
# 飞书插件完整诊断

echo "=== 飞书插件诊断 ==="

# 1. 检查插件目录
if [ -d "/Users/xutaohuang/workspace/ai/openclaw/extensions/feishu" ]; then
    echo "✓ 飞书插件目录存在"
    file_count=$(find "/Users/xutaohuang/workspace/ai/openclaw/extensions/feishu" -type f | wc -l)
    echo "  包含 $file_count 个文件"

    if [ "$file_count" -eq 0 ]; then
        echo "✗ 插件目录为空 - 这是关键问题！"
        echo "解决方案: node openclaw.mjs plugins install feishu"
    fi
else
    echo "✗ 飞书插件目录不存在"
    echo "解决方案: node openclaw.mjs plugins install feishu"
fi

# 2. 检查飞书配置
if grep -q "feishu" ~/.openclaw/openclaw.json; then
    echo "✓ 飞书配置存在"

    # 提取配置信息
    app_id=$(grep -o '"appId": "[^"]*"' ~/.openclaw/openclaw.json | cut -d'"' -f4)
    conn_mode=$(grep -o '"connectionMode": "[^"]*"' ~/.openclaw/openclaw.json | cut -d'"' -f4)
    enabled=$(grep -o '"enabled": [^,}]*' ~/.openclaw/openclaw.json | grep -A1 "feishu" | tail -1 | cut -d':' -f2)

    echo "  App ID: $app_id"
    echo "  连接模式: $conn_mode"
    echo "  启用状态: $enabled"
else
    echo "✗ 飞书配置不存在"
fi

# 3. 检查WebSocket连接
latest_log=$(ls -t /tmp/openclaw/openclaw-*.log 2>/dev/null | head -1)
if [ -n "$latest_log" ]; then
    echo "检查日志: $latest_log"

    if grep -q "WebSocket client started" "$latest_log"; then
        echo "✓ WebSocket客户端已启动"
    else
        echo "✗ WebSocket客户端未启动"
    fi

    if grep -q "event-dispatch is ready" "$latest_log"; then
        echo "✓ 事件调度器已就绪"
    else
        echo "✗ 事件调度器未就绪"
    fi

    if grep -q "ws client ready" "$latest_log"; then
        echo "✓ WebSocket连接已就绪"
    else
        echo "✗ WebSocket连接未就绪"
    fi

    # 检查最近的错误
    recent_errors=$(tail -100 "$latest_log" | grep -c "feishu.*ERROR\|feishu.*error" || echo "0")
    if [ "$recent_errors" -gt 0 ]; then
        echo "⚠ 发现 $recent_errors 条飞书相关错误"
        echo "最近的错误:"
        tail -100 "$latest_log" | grep -E "feishu.*ERROR|feishu.*error" | tail -5
    else
        echo "✓ 最近没有飞书相关错误"
    fi
fi
```

**解决方案：**

```bash
# 1. 重新安装飞书插件
cd /Users/xutaohuang/workspace/ai/openclaw
node openclaw.mjs plugins install feishu

# 2. 验证插件安装
ls -la extensions/feishu/

# 3. 重启服务
./openclaw.mjs gateway stop
./start-with-private.sh gateway --port 18789

# 4. 验证飞书连接
tail -f /tmp/openclaw/openclaw-$(date +%Y-%m-%d).log | grep feishu
```

**预防措施：**

- 升级后验证插件安装状态
- 定期检查插件目录内容
- 建立插件健康监控机制

#### 问题3：服务启动冲突

**症状：**

- 无法启动服务
- 端口被占用错误
- 多个进程监听同一端口

**解决方案：**

```bash
# 1. 检查端口占用
lsof -i :18789

# 2. 正确停止服务
./openclaw.mjs gateway stop

# 3. 如果停止失败，强制清理
pkill -9 -f "openclaw.*gateway"

# 4. 清理僵尸进程
ps aux | grep -i defunct | grep openclaw

# 5. 检查并清理端口占用
fuser -k 18789/tcp  # Linux
lsof -ti :18789 | xargs kill -9  # macOS

# 6. 等待端口释放
sleep 5

# 7. 重新启动服务
./start-with-private.sh gateway --port 18789
```

**预防措施：**

- 使用标准的停止命令
- 启动前检查端口状态
- 实现进程锁机制

#### 问题4：性能问题

**症状：**

- 响应时间过长
- CPU使用率过高
- 内存泄漏

**诊断流程：**

```bash
#!/bin/bash
# 性能问题诊断

echo "=== 性能诊断 ==="

# 1. 检查CPU使用率
cpu_usage=$(ps aux | grep "openclaw.*gateway" | grep -v grep | awk '{print $3}')
echo "CPU使用率: ${cpu_usage}%"

if [ $(echo "$cpu_usage > 80" | bc) -eq 1 ]; then
    echo "⚠ CPU使用率过高"
    echo "建议: 检查是否有死循环或资源竞争"
fi

# 2. 检查内存使用率
memory_usage=$(ps aux | grep "openclaw.*gateway" | grep -v grep | awk '{print $4}')
echo "内存使用率: ${memory_usage}%"

if [ $(echo "$memory_usage > 80" | bc) -eq 1 ]; then
    echo "⚠ 内存使用率过高"
    echo "建议: 检查是否有内存泄漏，考虑重启服务"
fi

# 3. 检查响应时间
start_time=$(date +%s%N)
curl -s http://127.0.0.1:18789/__openclaw__/health >/dev/null
end_time=$(date +%s%N)
response_time=$(( (end_time - start_time) / 1000000 ))

echo "响应时间: ${response_time}ms"

if [ "$response_time" -gt 1000 ]; then
    echo "⚠ 响应时间过长 (>1s)"
    echo "建议: 检查网络连接和系统负载"
fi

# 4. 检查日志文件大小
log_size=$(du -sh /tmp/openclaw/openclaw-*.log | awk '{print $1}')
echo "日志文件大小: $log_size"

# 5. 检查并发连接
connections=$(lsof -i :18789 | grep ESTABLISHED | wc -l)
echo "当前连接数: $connections"
```

**解决方案：**

```bash
# 1. 清理日志文件
find /tmp/openclaw -name "*.log" -mtime +7 -delete

# 2. 清理Canvas缓存
rm -rf ~/.openclaw/canvas/cache/*

# 3. 优化配置参数
# 减少maxConcurrent设置
# 增加contextPruning的ttl时间

# 4. 重启服务
./openclaw.mjs gateway restart
```

## 性能优化

### 系统配置优化

#### 1. Node.js 优化

```bash
# 设置环境变量
export NODE_OPTIONS="--max-old-space-size=4096"
export UV_THREADPOOL_SIZE=4

# 在启动脚本中应用
NODE_OPTIONS="--max-old-space-size=4096" UV_THREADPOOL_SIZE=4 ./start-with-private.sh gateway --port 18789
```

#### 2. 操作系统优化

**Linux (sysctl.conf):**

```bash
# 增加文件句柄限制
fs.file-max = 65536

# 优化TCP连接
net.core.somaxconn = 1024
net.ipv4.tcp_max_syn_backlog = 1024

# 优化TCP keepalive
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3
```

**macOS (sysctl.conf):**

```bash
# 增加文件句柄限制
kern.maxfiles = 65536
kern.maxfilesperproc = 65536

# 优化网络
net.inet.tcp.somaxconn = 1024
net.inet.tcp.msl = 1000
```

### 应用配置优化

#### 1. 智能体并发优化

```json
{
  "agents": {
    "defaults": {
      "maxConcurrent": 2, // 从4减少到2
      "subagents": {
        "maxConcurrent": 4 // 从8减少到4
      }
    }
  }
}
```

#### 2. 上下文管理优化

```json
{
  "agents": {
    "defaults": {
      "contextPruning": {
        "mode": "cache-ttl",
        "ttl": "30m" // 从1h减少到30m
      },
      "compaction": {
        "mode": "aggressive" // 从safeguard改为aggressive
      }
    }
  }
}
```

#### 3. 模型选择优化

```json
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "zai/glm-4.5", // 使用更快的模型
        "fallbacks": [
          "github-copilot/gemini-3-flash-preview",
          "zai/glm-5" // 仅在需要时使用复杂模型
        ]
      }
    }
  }
}
```

## 安全管理

### 配置文件安全

#### 1. 敏感信息保护

```bash
# 1. 设置文件权限
chmod 600 ~/.openclaw/openclaw.json
chmod 700 ~/.openclaw/

# 2. 使用环境变量存储敏感信息
export OPENCLAW_API_KEY="your-api-key"
export OPENCLAW_SECRET="your-secret"

# 3. 在配置文件中引用环境变量
{
  "channels": {
    "feishu": {
      "appSecret": "${OPENCLAW_SECRET}"
    }
  }
}
```

#### 2. 访问控制

```bash
# 1. 限制Canvas访问
{
  "canvas": {
    "auth": {
      "mode": "token",
      "token": "secure-token-here"
    }
  }
}

# 2. 限制网关访问
{
  "gateway": {
    "auth": {
      "mode": "token",
      "token": "another-secure-token"
    },
    "bind": "127.0.0.1"  // 仅监听本地
  }
}
```

### 更新安全

#### 1. 自动更新安全配置

```bash
# 在自动更新脚本中添加安全检查

# 1. 验证Git仓库签名
if ! git verify-commit HEAD >/dev/null 2>&1; then
    echo "错误：Git提交验证失败"
    exit 1
fi

# 2. 检查依赖安全性
pnpm audit --audit-level high

# 3. 检查配置文件完整性
CHECKSUM=$(sha256sum ~/.openclaw/openclaw.json | cut -d' ' -f1)
if [ "$CHECKSUM" != "$EXPECTED_CHECKSUM" ]; then
    echo "错误：配置文件校验和不匹配"
    exit 1
fi
```

#### 2. 回滚安全

```bash
# 1. 在回滚前验证备份
if [ ! -d "$BACKUP_DIR" ]; then
    echo "错误：备份目录不存在"
    exit 1
fi

# 2. 验证备份文件完整性
if ! sha256sum -c "$BACKUP_DIR/checksums.txt"; then
    echo "错误：备份文件校验和不匹配"
    exit 1
fi

# 3. 在回滚前创建回滚的备份
ROLLBACK_BACKUP="backups/rollback-$(date +%Y%m%d_%H%M%S)"
cp -r "$BACKUP_DIR" "$ROLLBACK_BACKUP"
```

## 监控与维护

### 监控指标

#### 1. 关键指标

```bash
#!/bin/bash
# 系统健康监控脚本

monitor_health() {
    echo "=== 系统健康监控 ==="

    # 1. 服务状态
    if lsof -Pi :18789 -sTCP:LISTEN -t >/dev/null 2>&1; then
        echo "✓ 服务状态: 正常"
    else
        echo "✗ 服务状态: 异常"
        # 发送告警
        curl -X POST "https://api.telegram.org/bot$TOKEN/sendMessage" \
            -d "chat_id=$CHAT_ID" \
            -d "text=OpenClaw服务异常"
    fi

    # 2. CPU使用率
    cpu_usage=$(ps aux | grep "openclaw.*gateway" | grep -v grep | awk '{print $3}' | head -1)
    echo "CPU使用率: ${cpu_usage}%"

    # 3. 内存使用率
    memory_usage=$(ps aux | grep "openclaw.*gateway" | grep -v grep | awk '{print $4}' | head -1)
    echo "内存使用率: ${memory_usage}%"

    # 4. 响应时间
    start_time=$(date +%s%N)
    if curl -s http://127.0.0.1:18789/__openclaw__/health >/dev/null; then
        end_time=$(date +%s%N)
        response_time=$(( (end_time - start_time) / 1000000 ))
        echo "响应时间: ${response_time}ms"
    else
        echo "✗ 响应时间: 超时"
    fi

    # 5. 错误日志
    error_count=$(tail -100 /tmp/openclaw/openclaw-*.log 2>/dev/null | grep -c "ERROR\|error" || echo "0")
    echo "最近错误数: $error_count"
}

# 定期执行（每小时）
while true; do
    monitor_health
    sleep 3600
done
```

#### 2. 日志分析

```bash
#!/bin/bash
# 日志分析脚本

analyze_logs() {
    local log_file=$1

    echo "=== 日志分析: $log_file ==="

    # 1. 错误统计
    echo "错误统计:"
    grep -E "ERROR|error" "$log_file" | \
        awk '{print $NF}' | \
        sort | uniq -c | sort -rn | head -10

    # 2. 警告统计
    echo "警告统计:"
    grep -E "WARN|warn" "$log_file" | \
        awk '{print $NF}' | \
        sort | uniq -c | sort -rn | head -10

    # 3. 性能指标
    echo "性能指标:"
    grep "response.*ms\|timeout" "$log_file" | tail -20

    # 4. 飞书连接状态
    echo "飞书连接状态:"
    grep -E "WebSocket|feishu" "$log_file" | tail -10
}
```

### 维护计划

#### 1. 日常维护

```bash
#!/bin/bash
# 每日维护脚本

daily_maintenance() {
    echo "=== 开始日常维护 ==="

    # 1. 配置备份
    cp ~/.openclaw/openclaw.json "backups/daily/openclaw-$(date +%Y%m%d).json"

    # 2. 日志清理
    find /tmp/openclaw -name "*.log" -mtime +7 -delete

    # 3. 缓存清理
    find ~/.openclaw/canvas/cache -type f -mtime +1 -delete

    # 4. 健康检查
    ./validate-update.sh

    echo "=== 日常维护完成 ==="
}
```

#### 2. 每周维护

```bash
#!/bin/bash
# 每周维护脚本

weekly_maintenance() {
    echo "=== 开始每周维护 ==="

    # 1. 完整备份
    tar -czf "backups/weekly/complete-backup-$(date +%Y%m%d).tar.gz" \
        ~/.openclaw /Users/xutaohuang/workspace/ai/openclaw/logs

    # 2. 依赖更新检查
    cd /Users/xutaohuang/workspace/ai/openclaw
    pnpm outdated

    # 3. 安全审计
    pnpm audit

    # 4. 性能分析
    ./performance-diagnostics.sh

    echo "=== 每周维护完成 ==="
}
```

#### 3. 每月维护

```bash
#!/bin/bash
# 每月维护脚本

monthly_maintenance() {
    echo "=== 开始每月维护 ==="

    # 1. 系统升级
    cd /Users/xutaohuang/workspace/ai/openclaw
    ./auto-update-enhanced.sh

    # 2. 配置审查
    ./config-review.sh

    # 3. 插件更新
    ./openclaw.mjs plugins update --all

    # 4. 文档更新
    ./generate-documentation.sh

    echo "=== 每月维护完成 ==="
}
```

## 📚 参考资料

### 相关文档

- `DEPLOYMENT_SUMMARY_20260305.md` - 详细部署报告
- `FEISHU_TROUBLESHOOTING_REPORT_20260305.md` - 飞书故障排除报告
- `UPGRADE_SUMMARY_20260305.md` - 升级经验总结
- `README_AUTO_UPDATE.md` - 自动更新系统文档

### 脚本文件

- `auto-update-simple.sh` - 基础自动更新脚本
- `auto-update-enhanced.sh` - 增强自动更新脚本
- `validate-update.sh` - 系统验证脚本
- `setup-auto-update.sh` - 交互式设置脚本

### 官方资源

- OpenClaw GitHub: https://github.com/openclaw/openclaw
- 飞书开发者文档: https://open.feishu.cn/document/
- Node.js文档: https://nodejs.org/docs/

## 🎯 总结

本文档总结了OpenClaw升级项目中积累的最佳实践和故障排除经验，为后续的系统维护、升级和故障排除提供了全面的指导。

### 核心价值

- 🚀 **技术创新** - 多智能体系统和自动化升级
- 💡 **经验沉淀** - 完整的技术文档和最佳实践
- 🔧 **运维提升** - 标准化的流程和工具
- 🛡️ **风险控制** - 完善的备份和回滚机制

### 持续改进

- 建立问题反馈机制
- 定期更新文档内容
- 分享经验和最佳实践
- 优化自动化工具

---

**文档创建时间：** 2026-03-05  
**文档版本：** 1.0  
**维护人员：** OpenClaw Team
