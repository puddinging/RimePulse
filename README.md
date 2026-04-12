# RimePulse

macOS 菜单栏打字统计工具，实时展示 [Rime 输入法](https://rime.im) 的键入数据。

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift 5.10](https://img.shields.io/badge/Swift-5.10-orange) ![License](https://img.shields.io/badge/license-MIT-green)

## 功能

- **状态栏实时显示** — 今日字数、打字速度、峰值速度，一眼掌握
- **今日详情** — 中英文分布、活跃时长、提交次数
- **7 天历史** — 每日字数、速度、活跃时长一览
- **累计统计** — 总字数、总时长、总提交，按天汇总
- **开机自启** — 一键开关，无需手动配置登录项
- **实时监听** — 基于文件系统事件，数据文件变化后即时刷新

## 数据来源

RimePulse 读取 Rime 输入法 Lua 插件 `tstats.lua` 生成的统计文件：

| 文件 | 说明 |
|------|------|
| `typing_stats_today.txt` | 今日实时统计（每次上屏后覆盖更新，JSON 内容） |
| `typing_stats.txt` | 历史记录（每天一行 JSON，跨日自动归档） |

### 安装 Lua 统计插件

#### 1. 复制脚本

将仓库中的 `rime/tstats.lua` 复制到 Rime 用户目录的 `lua/` 文件夹：

```bash
cp rime/tstats.lua ~/Library/Rime/lua/tstats.lua
```

> 其他平台路径：Linux `~/.local/share/fcitx5/rime/lua/`，Windows `%APPDATA%\Rime\lua\`

#### 2. 在输入方案中挂载

编辑你使用的输入方案的 `.custom.yaml` 文件，将 `lua_filter@*tstats` 添加到 `engine/filters` 列表中。

以雾凇拼音为例，编辑 `~/Library/Rime/rime_ice.custom.yaml`：

```yaml
patch:
  "engine/filters":
    - lua_filter@*tstats          # ← 添加这一行
    - lua_filter@*corrector
    - reverse_lookup_filter@radical_reverse_lookup
    # ... 其他 filter 保持不变
    - uniquifier
```

如果同时使用多个方案（如小鹤双拼），每个方案的 `.custom.yaml` 都需要添加。

#### 3. 重新部署

在 Squirrel 菜单中点击「重新部署」，或运行：

```bash
/Library/Input\ Methods/Squirrel.app/Contents/MacOS/Squirrel --reload
```

部署完成后，正常打字即可在 `~/Library/Rime/` 下看到 `typing_stats_today.txt` 文件生成。

### tstats.lua 工作原理

- **挂载方式**：作为 `lua_filter` 运行，对候选词透传不修改，仅在后台统计
- **字符计数**：区分 CJK（中日韩统一表意文字）和 ASCII，按 Unicode 码点范围判断
- **活跃时长**：毫秒级计时，从组合开始（首次按键）到上屏，累加每次组合时间，超过 120 秒的间隔自动忽略
- **当前速度**：15 秒窗口估算实时 CPM，并做指数平滑（`current_cpm`），减少短时抖动
- **峰值速度**：60 秒滑动窗口，至少 3 次上屏、窗口跨度 ≥ 10 秒且最少字符数满足门槛时更新
- **新造词统计**：已移除（`new_words_*` 字段仅为兼容旧数据保留）
- **写入策略**：1 秒防抖，跨日自动归档到 `typing_stats.txt` 并重置当日统计（同时兼容旧文件名）
- **生命周期**：`init` 加载已有数据 → `func` 透传候选词 → `fini` 落盘保存

## 安装

### 从源码构建

```bash
git clone https://github.com/yourname/RimePulse.git
cd RimePulse
make release
```

### 安装到系统

```bash
# 安装命令行可执行文件
make install

# 或打包为 .app bundle（推荐，支持开机自启）
make bundle
```

`make bundle` 会在 `~/Applications/RimePulse.app` 生成应用包。

## 配置

默认读取 `~/Library/Rime` 目录下的统计文件（Squirrel 标准路径）。

如需自定义数据目录，创建配置文件 `~/.config/rimestats/config.json`：

```json
{
  "data_dir": "/path/to/your/rime"
}
```

配置文件中的路径优先级高于默认路径，支持 `~` 展开。

## 数据文件格式

### typing_stats_today.txt

```json
{
  "date": "2026-04-04",
  "created_at": 1743724800000,
  "updated_at": 1743768000000,
  "chars": 1730,
  "chars_cjk": 1424,
  "words_en": 92,
  "commits": 646,
  "avg_word_length": 2.1,
  "chars_per_minute": 52,
  "current_cpm": 49,
  "peak_cpm": 158,
  "active_minutes": 33.3,
  "new_words_count": 283,
  "new_words": ["新词1", "新词2"]
}
```

### typing_stats.txt

每行一条 JSON，格式同上，每天一条记录。

## 技术栈

- Swift 5.10 / SwiftUI
- Swift Package Manager
- `DispatchSource` 文件系统监听
- `SMAppService` 登录项管理
- macOS 14 (Sonoma) +

## License

MIT
