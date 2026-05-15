#!/bin/bash
# init.sh
# ==============================================================================
# 脚本作用: 幂等创建方便软件开发人员开发的目录结构，并读取配置批量克隆软件仓库
# 用法: ./init.sh <workspace_root>
# 依赖: 需要提前安装 jq (解析 JSON 用)
# ==============================================================================

set -e

WORKSPACE_ROOT="$1"

if [ -z "$WORKSPACE_ROOT" ]; then
    echo "Usage: $0 <workspace_root>"
    exit 1
fi

echo "创建 开发环境目录: $WORKSPACE_ROOT"

# ==========================================
# 1. 初始化标准开发目录结构 (幂等操作)
# ==========================================
# 顶层目录（每行一个 mkdir -p，即使目录已存在也不会报错，保证幂等性）

# 1.1 核心代码区
mkdir -p "$WORKSPACE_ROOT/repos"     # 软件仓库：所有批量 clone 下来的项目都在这里，每一个子目录代表一个 git 项目
mkdir -p "$WORKSPACE_ROOT/features"  # 需求开发：日常干活的目录，每一个子目录代表一个需求开发任务或分支的组合工作区

# 1.2 实验与测试区
mkdir -p "$WORKSPACE_ROOT/labs"      # 实验代码：用于写一些 Demo、验证某个 API 或语言特性的草稿代码
mkdir -p "$WORKSPACE_ROOT/labs/json" # 实验用的 JSON 数据存储
touch "$WORKSPACE_ROOT/labs/json/1.json" # 占位文件，方便在 IDE (如 Cursor/VSCode) 中用 cmd+p 输入 1.json 快速打开并格式化临时数据
mkdir -p "$WORKSPACE_ROOT/labs/logs" # 实验产生的日志文件
touch "$WORKSPACE_ROOT/labs/logs/2.log"  # 占位文件，方便 cmd+p 快速打开查看实验日志

# 1.3 工具与文档区
mkdir -p "$WORKSPACE_ROOT/tools/git" # 工具脚本：存放常用的 git 批量化操作脚本或其他高频使用的定制脚本
mkdir -p "$WORKSPACE_ROOT/tools/polyrepo-scaffold"
cp "$0" "$WORKSPACE_ROOT/tools/polyrepo-scaffold"
mkdir -p "$WORKSPACE_ROOT/docs/read" # 阅读记录：源码阅读笔记、架构图、思维导图等
mkdir -p "$WORKSPACE_ROOT/docs/plan" # 需求记录：需求分析、排期表、TODO list 等

# 1.4 临时文件区 (用完即焚)
mkdir -p "$WORKSPACE_ROOT/tmp/json"  # JSON 临时文件：存放抓包临时 copy 的报文等
touch "$WORKSPACE_ROOT/tmp/json/1.json"  # 占位文件，cmd+p 快速打开
mkdir -p "$WORKSPACE_ROOT/tmp/logs"  # 临时日志文件
touch "$WORKSPACE_ROOT/tmp/logs/2.log"   # 占位文件，cmd+p 快速打开
mkdir -p "$WORKSPACE_ROOT/tmp/scripts" # 临时脚本：不常用的、一次性的清理或刷数据脚本放这里；高频重用的放 tools/ 下

# ==========================================
# 2. 初始化 IDE 环境配置
# ==========================================
# 创建 .cursor 文件，如果不存在的话
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
# 3. 解析并执行 git clone 配置文件
# ==========================================

# 将配置文件的相对路径转换为绝对路径，防止稍后 cd 切换目录后找不到该文件
CONFIG_FILE="$(pwd)/clone_repos.json"
cp "$CONFIG_FILE" "$WORKSPACE_ROOT/tools/git/"

# REPOS_DIR 是我们所有仓库的归宿
REPOS_DIR="$WORKSPACE_ROOT/repos"

# 查找配置文件，如果不存在或者为空则终止脚本
if [ ! -s "$CONFIG_FILE" ]; then
    echo "❌ 失败: 配置文件 $CONFIG_FILE 不存在或为空"
    exit 1
fi

# 检查是否安装了 jq 环境（JSON 解析必须依赖）
if ! command -v jq &> /dev/null; then
    echo "❌ 失败: 解析 JSON 需要 jq 工具，未找到 jq。"
    echo "💡 提示: 请先安装 (Mac: brew install jq / Ubuntu: apt install jq)"
    exit 1
fi

# 进入克隆工作目录
cd "$REPOS_DIR" || { echo "❌ 失败: 无法进入目录 $REPOS_DIR"; exit 1; }
echo "📂 已进入克隆工作目录: $(pwd)"
echo "🔄 开始解析配置文件并构建克隆命令..."

# ----------------------------------------------------------------------------------
# 📖 clone_repos.json 填写指南与常见场景示例 (供开发者参考)
# 
# 配置文件必须是一个 JSON 数组。以下是三种最常见场景的配置写法：
# 
# 场景 1: 极简模式 (默认分支 + 默认文件夹名)
# 说明: 只要 master/main 等默认分支，文件夹名字直接用远程仓库的名字。
# {
#     "url": "https://github.com/company/repo-a.git"
# }
# 
# 场景 2: 高效模式 (指定特定分支 + 极致提速) -> 推荐日常使用！
# 说明: 只要 xwx_syh 分支。加上 --single-branch 可以极大地缩短 clone 时间，节省磁盘。
# {
#     "url": "https://github.com/company/repo-b.git",
#     "args": "--branch xwx_syh --single-branch"
# }
# 
# 场景 3: 重命名模式 (解决名字冲突 或 名字太长的问题)
# 说明: 远程叫 hwapi.xesv5.com，本地想把它放在 hwapi 文件夹下。
# {
#     "url": "https://github.com/company/hwapi.xesv5.com.git",
#     "target_dir": "hwapi",
#     "args": "--single-branch"
# }
# ----------------------------------------------------------------------------------

# 使用 jq 以紧凑模式 (-c) 遍历 JSON 数组中的每一项
jq -c '.[]' "$CONFIG_FILE" | while read -r repo; do
    
    # 解析命令字段。默认使用原生的 git clone。极少情况需要修改。
    cmd=$(echo "$repo" | jq -r '.cmd // "git clone"')
    
    # 解析参数字段。存放像 "--branch dev" 这样的纯文本字符串。
    args=$(echo "$repo" | jq -r '.args // ""')
    
    # 解析克隆地址。必须有值，为空则跳过。
    url=$(echo "$repo" | jq -r '.url // ""')
    
    # 解析目标目录名。控制本地文件夹叫什么。如果为空，后面会自动根据 url 推导。
    target_dir=$(echo "$repo" | jq -r '.target_dir // ""')
    
    # 如果该项没有配置 URL (可能是占位符或者填错了)，直接跳过，防止报错
    if [ -z "$url" ]; then
        continue
    fi

    # 【核心：目标目录推导】
    # 如果 JSON 里没有手动写 target_dir，则利用 basename 命令从 URL 中提取。
    # 例如：从 "https://.../watcher.git" 中提取出 "watcher"
    if [ -z "$target_dir" ]; then
        target_dir=$(basename "$url" .git)
    fi

    # 【核心：幂等防重检查】
    # 在实际执行 clone 前，先检查最终要创建的文件夹是否已经存在。
    # 存在说明以前 clone 过，直接跳过。这样脚本执行 100 次都不会重复下载或报错。
    if [ -d "$target_dir" ]; then
        echo "⏭️  目录 '$target_dir' 已存在，跳过克隆: $url"
        continue
    fi

    # 构建完整的 shell 执行命令
    # 格式拼接： git clone [参数] "URL" "目标目录"
    # 这里巧妙地使用了变量包裹，能完美兼容 args 为空、目标目录包含空格等情况
    full_cmd="$cmd $args \"$url\" \"$target_dir\""
    
    echo "🚀 执行: $full_cmd"
    
    # 使用 eval 解析并执行这个纯文本命令
    eval "$full_cmd"
    
done

echo "✅ 所有仓库初始化任务执行完毕！"