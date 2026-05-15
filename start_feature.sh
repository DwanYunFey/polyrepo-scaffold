#!/bin/bash
# start_feature.sh
# 作用: 基于 feature_task.json 和 clone_repos.json
# 业务流: 提取分支信息 -> 更新 repos 缓存 -> 物理拷贝到需求目录 -> 新建分支与初始化

set -e

WORKSPACE_ROOT=${1:-$(pwd)}
CONFIG_FILE="$WORKSPACE_ROOT/config/clone_repos.json"  # 全局的项目数据库
TASK_CONF="$WORKSPACE_ROOT/config/feature_task.json" # 当前的需求配置
REPOS_DIR="$WORKSPACE_ROOT/repos"                       # 本地代码缓存池

echo "=================================================="
echo "🚀 开始初始化需求开发环境 (本地缓存 Copy 模式)..."
echo "=================================================="

# 1. 前置检查
if [ ! -f "$CONFIG_FILE" ] || [ ! -f "$TASK_CONF" ]; then
    echo "❌ 失败: 配置文件缺失。请确保以下文件存在："
    echo "   - $CONFIG_FILE"
    echo "   - $TASK_CONF"
    exit 1
fi

# 2. 解析需求配置
FEATURE_ID=$(jq -r '.feature_id' "$TASK_CONF")
FEATURE_DIR="$WORKSPACE_ROOT/features/$FEATURE_ID"

echo "📌 需求 ID: $FEATURE_ID"
echo "📁 目标目录: $FEATURE_DIR"

mkdir -p "$FEATURE_DIR"

# 3. 遍历相关项目，按数组顺序执行
jq -r '.repos[]' "$TASK_CONF" | while read -r repo_name; do
    echo "--------------------------------------------------"
    echo "📦 处理项目: $repo_name"

    TARGET_PATH="$FEATURE_DIR/$repo_name"
    SOURCE_PATH="$REPOS_DIR/$repo_name"

    # 防重检查
    if [ -d "$TARGET_PATH" ]; then
        echo "⏭️  目录已存在，跳过初始化: $TARGET_PATH"
        continue
    fi

    # (1) 检查 repos 目录中是否存在基础缓存项目
    if [ ! -d "$SOURCE_PATH" ]; then
        echo "❌ 失败: 本地缓存目录 $SOURCE_PATH 不存在！请先确认 repos 中是否已克隆该项目。"
        continue
    fi

    # 从 clone_repos.json 中查询这个项目的信息
    repo_json=$(jq -c ".[] | select(.target_dir == \"$repo_name\" or ( (.target_dir == null or .target_dir == \"\") and (.url | endswith(\"$repo_name.git\")) ))" "$CONFIG_FILE")

    if [ -z "$repo_json" ]; then
        echo "⚠️ 警告: 未在 $CONFIG_FILE 中找到 '$repo_name' 的配置，跳过此项目。"
        continue
    fi

    args=$(echo "$repo_json" | jq -r '.args // ""')
    
    # 动态提取目标主分支名称 (从 --branch 参数中提取)
    # 增加 -- 告诉 grep 停止解析后续选项，避免将 --branch 误认为自带参数
    target_branch=$(echo "$args" | grep -oE -- '--branch [^ ]+' | awk '{print $2}')

    # (3) 切换到 repos 对应目录，执行 git pull
    echo "🔄 正在更新本地缓存: $SOURCE_PATH"
    cd "$SOURCE_PATH" || continue
    
    # 如果 args 中没有配置 --branch，则自动获取该仓库的默认分支 (通常为 master 或 main)
    if [ -z "$target_branch" ]; then
        target_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | awk -F'/' '{print $NF}')
        # 兜底：如果还获取不到，默认为 master
        target_branch=${target_branch:-master}
    fi

    # 切回主分支，拉取最新代码
    git checkout "$target_branch" &> /dev/null || {
        echo "❌ 警告: 无法在主库切换到 $target_branch 分支，可能存在冲突。跳过本项目。"
        continue
    }
    git pull origin "$target_branch" --quiet
    echo "✅ 缓存已更新到最新 ($target_branch)。"

    # (4) 复制到目标位置
    echo "📂 正在物理拷贝代码至需求目录..."
    # 必须使用 -a 参数 (archive) 以原样保留 .git 目录、隐藏文件和所有权限
    cp -a "$SOURCE_PATH" "$TARGET_PATH"

    # (5) 切换目录，新建需求分支，并处理依赖
    cd "$TARGET_PATH" || continue
    
    echo "🌱 创建并切换到需求新分支: $FEATURE_ID"
    # 由于刚才 repos 已经是主分支最新代码并被原样拷贝，直接 checkout -b 即可
    git checkout -b "$FEATURE_ID"

    if [ -f "go.mod" ]; then
        echo "🐹 识别到 Go 项目，正在执行 go mod tidy..."
        # 增加兜底操作：即便环境抽风失败，也不会触发 set -e 导致后续项目中断
        go mod tidy || echo "⚠️ 警告: go mod tidy 执行遇到问题，已跳过。请稍后在 IDE 中手动处理。"
    else
        echo "📄 非 Go 项目，无依赖脚本需执行。"
    fi

done

cp "$TASK_CONF" "$FEATURE_DIR/$FEATURE_ID.json"

echo "=================================================="
echo "✅ 需求环境准备就绪！纯净物理拷贝，随意删除！"
echo "👉 请前往开发: $FEATURE_DIR"