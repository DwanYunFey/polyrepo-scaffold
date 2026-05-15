# Role & Task
You are an expert configuration generator. Your task is to generate a strictly valid JSON file (`clone_repos.json`) used by a Bash script to automate Git repository cloning.

# Context: How the Script Consumes This JSON
The target Bash script parses this JSON file using `jq` and executes the command via `eval`. The exact execution logic in the script is:
`full_cmd="$cmd $args \"$url\" \"$target_dir\""`
`eval "$full_cmd"`
The script also uses `target_dir` (or `basename "$url" .git` if empty) to check if the directory already exists to ensure idempotency.

# JSON Schema definition
The output MUST be a valid JSON array of objects. Each object represents a cloning task and MUST adhere to the following schema:

- `url` (String, REQUIRED): The repository URL (HTTPS or SSH). If empty, the script skips the entry.
- `target_dir` (String, OPTIONAL): The exact name of the destination folder. 
  - Omit or set to `""` if you want to use the default repository name. 
  - Provide a specific string ONLY if renaming is required or to avoid directory name collisions.
- `args` (String, OPTIONAL): Additional arguments passed to the clone command (e.g., branch selection, depth). 
  - CRITICAL: Must be a single space-separated string, NOT an array (e.g., `"--depth 1 --branch dev"`).
  - Avoid complex nested quotes to prevent `eval` escaping errors in Bash.
- `cmd` (String, OPTIONAL): The base command. 
  - DO NOT provide this field unless explicitly requested to use a tool other than Git (e.g., `"gh repo clone"`). The script defaults to `"git clone"`.

# Strict Constraints for the AI Generator
1. **Strict JSON:** The output must be strictly valid JSON. NO trailing commas. NO comments (`//` or `/* */`).
2. **No Array for Args:** Do not use `["--depth", "1"]` for `args`. It must be `"args": "--depth 1"`.
3. **Idempotency Awareness:** If the user requests two repositories with the same default name, you MUST explicitly provide different `target_dir` values to prevent conflicts.

# Branch Handling Rules for AI
When the user specifies a branch requirement, follow these rules:
1. **Default Branch (`main`, `master`, etc.):** If the user wants the default branch, DO NOT add any branch arguments. Git handles this automatically.
2. **Specific/Custom Branch (`xwx`, `dev`, etc.):** If the user explicitly requests a non-default branch, you MUST append `--branch <branch_name>` to the `args` string. It is highly recommended to also append `--single-branch` for efficiency (e.g., `"args": "--branch xwx --single-branch"`).

# Example Output
[
    {
        "url": "https://github.com/example/standard-repo.git"
    },
    {
        "url": "git@github.com:example/specific-branch.git",
        "args": "--branch v2.0 --single-branch",
        "target_dir": "specific-branch-v2"
    },
    {
        "url": "https://github.com/example/shallow-clone.git",
        "args": "--depth 1"
    }
]


---

### 📝 配置文件 `clone_repos.json` 填写指南中文版

配置文件必须是一个 **JSON 数组（Array）**，数组里的每一个对象（Object）代表一个要执行的克隆任务。

#### 1. 字段说明（按代码解析逻辑）

| JSON 字段 | 类型 | 是否必填 | 代码中的默认值 | 作用说明 |
| --- | --- | --- | --- | --- |
| **`url`** | 字符串 | **必填** | `""` | 仓库的 Git 下载地址。代码规定，如果这个字段为空，会直接跳过该任务。 |
| **`target_dir`** | 字符串 | 选填 | `""`（自动推导） | 克隆后的目标文件夹名称。如果不填，代码会执行 `basename "$url" .git`，即**自动截取 URL 的最后一部分作为文件夹名**。它也是脚本用来判断“是否已经克隆过”的关键字段。 |
| **`args`** | 字符串 | 选填 | `""` | 传递给 `git clone` 的额外参数。注意：在这段代码的设计下，**它必须是一个纯文本字符串**（例如 `"--depth 1 -b dev"`），参数之间用空格隔开。 |
| **`cmd`** | 字符串 | 选填 | `"git clone"` | 基础执行命令。一般不需要填，代码会自动使用 `git clone`。除非你想用 `gh repo clone` 等其他工具覆盖它。 |

---

### 💡 各种场景的配置示例

为了让你完全掌握怎么填，这里提供 3 个常见工作流的具体配置写法：

#### 场景一：极简模式（只管下载，什么都不改）

如果你只需要把仓库下载下来，名字就用仓库自带的名字，分支就用默认分支，你**只需要填 `url**`。

```json
[
    {
        "url": "https://github.com/your-org/my-project.git"
    }
]

```

> **代码底层行为：**
> * `target_dir` 会被代码自动推导为 `my-project`。
> * 拼接出的最终命令：`git clone "" "[https://github.com/your-org/my-project.git](https://github.com/your-org/my-project.git)" "my-project"`。
> * 再次执行脚本时，发现 `my-project` 文件夹存在，直接跳过，实现幂等。
> 
> 

#### 场景二：进阶模式（指定分支 + 重命名文件夹）

如果你想克隆特定的分支，并且不想用原来的仓库名（比如想把 `user-service` 重命名为 `backend`）。

```json
[
    {
        "url": "git@github.com:your-org/user-service.git",
        "target_dir": "backend",
        "args": "--branch release-v1 --single-branch"
    }
]

```

> **代码底层行为：**
> * 拼接出的最终命令：`git clone --branch release-v1 --single-branch "git@github.com:your-org/user-service.git" "backend"`。
> * 脚本会检查 `backend` 文件夹是否存在，而不是去检查 `user-service`。
> 
> 

#### 场景三：覆盖命令模式（极少用，但代码支持）

假设你想用 GitHub 官方 CLI 工具 `gh` 来下载，而不是原生的 `git clone`。

```json
[
    {
        "cmd": "gh repo clone",
        "url": "your-org/frontend-project",
        "target_dir": "frontend-web"
    }
]

```

> **代码底层行为：**
> * 此时代码提取到的 `cmd` 变成了 `gh repo clone`。
> * 拼接出的最终命令：`gh repo clone "" "your-org/frontend-project" "frontend-web"`。
> 
> 

---

### ⚠️ 填写配置时的避坑指南（针对你的这段代码）

1. **`args` 的格式陷阱**
因为你的代码最终是使用 `eval "$full_cmd"` 来执行拼接的字符串，如果你的 `args` 里面本身就带有**双引号或者特殊转义符**（例如配置复杂的 ssh 证书命令），在写 JSON 时非常容易因为转义错误导致脚本崩溃。尽量让 `args` 保持简单（如指定分支、深度）。
2. **绝对不要手贱加恶意的 `cmd**`
既然你决定使用结构化旧方案，团队成员在填写时，**尽量不要去填写 `cmd` 字段**。让它乖乖走系统默认的 `git clone` 逻辑是最安全的。
3. **JSON 格式必须严格合法**
配置文件是 `.json`，不能像 Python 或 JS 里那样在最后一个元素后面加逗号（Trailing comma），也不能加 `//` 注释，否则 `jq` 解析时会直接报错。