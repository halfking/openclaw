#!/bin/bash
# 使用私有配置启动 OpenClaw

# 加载环境变量或指定配置文件
# OpenClaw 核心通常通过环境变量 OPENCLAW_CONFIG_PATH 指定主配置文件
export OPENCLAW_CONFIG_PATH="$PWD/config-private-multi-agent.json"

# 如果有额外的环境变量（如飞书/邮件配置），可在此注入
# 某些组件可能直接读取特定路径，我们可以通过软连接或环境变量引导
export PRIVATE_FEISHU_EMAIL_CONFIG="$PWD/config-private-feishu-email.json"

echo "正在使用私有配置启动 OpenClaw..."
echo "配置文件: $OPENCLAW_CONFIG_PATH"

# 转发所有参数给主程序
./openclaw.mjs "$@"
