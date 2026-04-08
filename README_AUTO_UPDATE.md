# OpenClaw 自动更新系统

完整的自动化更新解决方案，支持定期更新、配置保护、自动回滚和健康检查。

## 📋 功能特性

✅ **自动更新** - 定期检查并更新到最新版本  
✅ **配置保护** - 自动备份和恢复配置文件  
✅ **安全回滚** - 更新失败时自动回滚到稳定版本  
✅ **健康检查** - 确保更新后服务正常运行  
✅ **日志记录** - 详细的更新过程日志  
✅ **报告生成** - 生成HTML格式的更新报告

## 🚀 快速开始

### 1. 文件结构

```
openclaw/
├── auto-update-simple.sh      # 简化版自动更新脚本
├── validate-update.sh          # 验证脚本
├── auto-update-test.sh         # 测试脚本
├── logs/                       # 日志目录
│   ├── auto-update-*.log       # 更新日志
│   ├── validate-*.log         # 验证日志
│   └── gateway-*.log          # 网关日志
└── backups/                    # 备份目录
    └── auto-update/           # 自动更新备份
        ├── config-backup-*/   # 配置备份
        └── latest-backup.txt  # 最新备份路径
```

### 2. 基本使用

#### 手动执行更新

```bash
cd /Users/xutaohuang/workspace/ai/openclaw
./auto-update-simple.sh
```

#### 验证系统状态

```bash
cd /Users/xutaohuang/workspace/ai/openclaw
./validate-update.sh
```

#### 运行测试

```bash
cd /Users/xutaohuang/workspace/ai/openclaw
./auto-update-test.sh
```

## ⚙️ 配置说明

### 自动更新脚本配置

在 `auto-update-simple.sh` 中可以修改以下配置：

```bash
# 工作目录
OPENCLAW_DIR="/Users/xutaohuang/workspace/ai/openclaw"

# 日志目录
LOG_DIR="${OPENCLAW_DIR}/logs"

# 备份目录
BACKUP_DIR="${OPENCLAW_DIR}/backups/auto-update"

# 服务端口
GATEWAY_PORT=18789
```

### 备份策略

- **自动备份**: 每次更新前自动备份配置
- **备份保留**: 保留最近7天的备份
- **备份内容**:
  - 主配置文件 (`config-private-multi-agent.json`)
  - 全局配置文件 (`~/.openclaw/openclaw.json`)
  - 插件目录 (`~/.openclaw/extensions/`)
  - Canvas数据 (`~/.openclaw/canvas/`)

### 回滚机制

脚本在以下情况下会自动回滚：

1. Git更新失败
2. 依赖安装失败
3. 项目构建失败
4. 服务启动失败
5. 健康检查失败

## 📅 定时任务配置

### 方法1: 使用cron定时任务

编辑crontab:

```bash
crontab -e
```

添加以下内容（每天凌晨3点执行更新）：

```bash
# OpenClaw自动更新 - 每天凌晨3点执行
0 3 * * * cd /Users/xutaohuang/workspace/ai/openclaw && ./auto-update-simple.sh >> /Users/xutaohuang/workspace/ai/openclaw/logs/cron.log 2>&1
```

### 方法2: 使用launchd (推荐macOS)

创建plist文件:

```bash
cat > ~/Library/LaunchAgents/com.openclaw.auto-update.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.openclaw.auto-update</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Users/xutaohuang/workspace/ai/openclaw/auto-update-simple.sh</string>
    </array>
    <key>WorkingDirectory</key>
    <string>/Users/xutaohuang/workspace/ai/openclaw</string>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>3</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>/Users/xutaohuang/workspace/ai/openclaw/logs/launchd.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/xutaohuang/workspace/ai/openclaw/logs/launchd-error.log</string>
</dict>
</plist>
EOF
```

加载服务:

```bash
launchctl load ~/Library/LaunchAgents/com.openclaw.auto-update.plist
```

卸载服务:

```bash
launchctl unload ~/Library/LaunchAgents/com.openclaw.auto-update.plist
```

### 方法3: 使用launchctl每周更新

修改StartCalendarInterval部分为每周执行:

```xml
<key>StartCalendarInterval</key>
<array>
    <dict>
        <key>Weekday</key>
        <integer>0</integer>  <!-- 0=周日, 1=周一, ..., 6=周六 -->
        <key>Hour</key>
        <integer>3</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
</array>
```

## 🔍 监控和维护

### 查看日志

#### 最新的更新日志

```bash
tail -50 /Users/xutaohuang/workspace/ai/openclaw/logs/auto-update-*.log
```

#### 查看所有日志

```bash
ls -lt /Users/xutaohuang/workspace/ai/openclaw/logs/
```

### 查看备份

#### 最新的备份

```bash
cat /Users/xutaohuang/workspace/ai/openclaw/backups/auto-update/latest-backup.txt
```

#### 查看所有备份

```bash
ls -lt /Users/xutaohuang/workspace/ai/openclaw/backups/auto-update/
```

### 手动回滚

如果需要手动回滚到上一个版本:

```bash
cd /Users/xutaohuang/workspace/ai/openclaw

# 获取最新备份路径
LATEST_BACKUP=$(cat backups/auto-update/latest-backup.txt)

# 停止服务
pkill -f "openclaw.*gateway"

# 恢复配置
cp "${LATEST_BACKUP}/config-private-multi-agent.json" ./
cp "${LATEST_BACKUP}/openclaw.json" ~/.openclaw/
cp -r "${LATEST_BACKUP}/extensions" ~/.openclaw/
cp -r "${LATEST_BACKUP}/canvas" ~/.openclaw/

# 重启服务
./start-with-private.sh gateway --port 18789
```

## 🛠️ 故障排除

### 问题1: 更新脚本执行失败

**症状**: 脚本执行出错，服务未更新

**解决方案**:

1. 检查日志文件: `logs/auto-update-*.log`
2. 验证Git仓库状态: `git status`
3. 手动测试更新步骤
4. 查看是否有回滚发生

### 问题2: 服务启动失败

**症状**: 更新后服务无法启动

**解决方案**:

1. 检查网关日志: `logs/gateway-*.log`
2. 验证配置文件格式
3. 检查端口是否被占用: `lsof -i :18789`
4. 手动回滚到上一个版本

### 问题3: 配置文件丢失

**症状**: 更新后配置文件消失或损坏

**解决方案**:

1. 检查备份目录: `backups/auto-update/`
2. 从备份恢复配置文件
3. 验证配置文件的JSON格式
4. 重新运行验证脚本

### 问题4: 定时任务未执行

**症状**: 设置了定时任务但没有执行

**解决方案**:

```bash
# 检查cron任务
crontab -l

# 检查launchd任务
launchctl list | grep openclaw

# 查看系统日志
log show --predicate 'process == "launchd"' --last 1h
```

## 📊 更新流程图

```
开始
  ↓
检查Git更新
  ↓ (有更新)
备份配置文件
  ↓
停止服务
  ↓
执行Git更新
  ↓
更新依赖
  ↓
构建项目
  ↓
验证配置
  ↓ (成功)
启动服务
  ↓
健康检查
  ↓ (成功)
清理旧备份
  ↓
生成报告
  ↓
更新成功

任何步骤失败 → 自动回滚 → 报告失败
```

## 🔒 安全注意事项

1. **备份定期检查**: 定期验证备份文件的完整性
2. **权限管理**: 确保脚本只有必要用户可以执行
3. **日志安全**: 定期清理敏感信息，保护日志文件
4. **网络连接**: 确保系统可以访问Git仓库和npm仓库
5. **磁盘空间**: 定期清理旧的备份和日志文件

## 📞 技术支持

如果遇到问题：

1. 查看详细的日志文件
2. 运行验证脚本检查系统状态
3. 查看GitHub Issues: https://github.com/openclaw/openclaw/issues
4. 查看官方文档: https://github.com/openclaw/openclaw#readme

## 📝 更新历史

- **2026-03-05**: 初始版本发布
  - 支持自动更新
  - 配置保护
  - 自动回滚
  - 健康检查
  - 详细的日志记录

## 🎯 最佳实践

1. **定期更新**: 建议每周执行一次更新
2. **监控日志**: 定期检查更新日志，及时发现潜在问题
3. **测试验证**: 在生产环境执行前，先在测试环境验证
4. **备份管理**: 定期清理旧备份，释放磁盘空间
5. **版本跟踪**: 记录每次更新的版本号和变更内容

---

**最后更新**: 2026-03-05  
**脚本版本**: 1.0.0  
**维护人员**: OpenClaw Team
