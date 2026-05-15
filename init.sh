#!/bin/bash
# init.sh
# 幂等创建 方便软件开发人员开发的目录结构并执行批量克隆软件仓库
# 用法: ./init.sh <workspace_root>

set -e

WORKSPACE_ROOT="$1"

if [ -z "$WORKSPACE_ROOT" ]; then
    echo "Usage: $0 <workspace_root>"
    exit 1
fi

echo "创建 开发环境目录: $WORKSPACE_ROOT"

# 顶层目录（每行一个 mkdir -p，保证幂等性）
mkdir -p "$WORKSPACE_ROOT/repos" # 软件仓库；每一个子目录代表一个git项目
mkdir -p "$WORKSPACE_ROOT/features" # 需求开发；每一个子目录代表一个需求开发任务
mkdir -p "$WORKSPACE_ROOT/labs" # 实验代码：某些
mkdir -p "$WORKSPACE_ROOT/labs/json" # 实验代码：某些
touch "$WORKSPACE_ROOT/labs/json/1.json" # cmd+p 输入1快速打开
mkdir -p "$WORKSPACE_ROOT/labs/logs" # 实验代码：某些
touch "$WORKSPACE_ROOT/labs/logs/2.log" # cmd+p 输入1快速打开
mkdir -p "$WORKSPACE_ROOT/tools/git" # git 批量化操作工具
mkdir -p "$WORKSPACE_ROOT/docs/read" # 阅读项目代码的记录
mkdir -p "$WORKSPACE_ROOT/docs/plan" # 需求开发记录
mkdir -p "$WORKSPACE_ROOT/tmp/json" # JSON 临时文件
touch "$WORKSPACE_ROOT/tmp/json/1.json" # cmd+p 输入1快速打开
mkdir -p "$WORKSPACE_ROOT/tmp/logs" # 日志文件
touch "$WORKSPACE_ROOT/tmp/logs/2.log" # cmd+p 输入1快速打开
mkdir -p "$WORKSPACE_ROOT/tmp/scripts" # 不常用的放这里；常用的放"$WORKSPACE_ROOT/tools/"

# 创建 .cursor 文件，如果不存在
CURSOR_FILE="$WORKSPACE_ROOT/.cursor"
if [ ! -f "$CURSOR_FILE" ]; then
    cat > "$CURSOR_FILE" <<EOF
# Cursor configuration
skills=()
settings={}
EOF
    echo "已创建 cursor 配置文件: $CURSOR_FILE"
else
    echo ".cursor 文件已存在，保持原样"
fi

echo "目录创建完成"
echo "----------------------------------------"

# ==========================================
# 解析并执行 git clone 配置文件
# ==========================================

# 将配置文件的相对路径转换为绝对路径，防止 cd 后找不到文件
CONFIG_FILE="$(pwd)/clone_repos.json"

# （1）创建目录；如果存在的话则忽略 (上方已经 mkdir -p 创建，此处定义变量)
REPOS_DIR="$WORKSPACE_ROOT/repos"

# （2）查找配置文件，如果不存在或者为空则失败
if [ ! -s "$CONFIG_FILE" ]; then
    echo "❌ 失败: 配置文件 $CONFIG_FILE 不存在或为空"
    exit 1
fi

# 检查是否安装了 jq（必须依赖）
if ! command -v jq &> /dev/null; then
    echo "❌ 失败: 解析 JSON 需要 jq 工具，未找到 jq。请先安装 (如: apt install jq / brew install jq)"
    exit 1
fi

# （5）cd $WORKSPACE_ROOT/repos
cd "$REPOS_DIR" || { echo "❌ 失败: 无法进入目录 $REPOS_DIR"; exit 1; }
echo "📂 已进入克隆工作目录: $(pwd)"
echo "🔄 开始解析配置文件并构建克隆命令..."

# （3）解析配置文件 & （4）构建 cmds & （6）执行命令
# 使用 jq 遍历 JSON 数组中的每一项
jq -c '.[]' "$CONFIG_FILE" | while read -r repo; do
    
    # 解析各个字段。如果你采用旧版的字符串 args 格式，这里也能兼容
    cmd=$(echo "$repo" | jq -r '.cmd // "git clone"')
    args=$(echo "$repo" | jq -r '.args // ""')
    url=$(echo "$repo" | jq -r '.url // ""')
    
    # 尝试读取 target_dir，用来辅助重命名或校验是否已存在
    target_dir=$(echo "$repo" | jq -r '.target_dir // ""')
    
    # 忽略空的 URL
    if [ -z "$url" ]; then
        continue
    fi

    # 如果配置里没有定义 target_dir，则自动从 URL 中提取默认名称用于存在性检查
    if [ -z "$target_dir" ]; then
        target_dir=$(basename "$url" .git)
    fi

    # 防重检查：如果目录已存在，不再执行 clone，保证整个脚本的幂等性
    if [ -d "$target_dir" ]; then
        echo "⏭️  目录 '$target_dir' 已存在，跳过克隆: $url"
        continue
    fi

    # 构建完整命令并记作 full_cmd
    # 这里通过 eval 执行，允许 args 是形如 "--depth 1 -b main" 的长字符串
    full_cmd="$cmd $args \"$url\" \"$target_dir\""
    
    echo "🚀 执行: $full_cmd"
    
    # 执行克隆命令
    eval "$full_cmd"
    
done

echo "✅ 所有任务执行完毕！"