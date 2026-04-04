# RimePulse

macOS 菜单栏打字统计工具，实时展示 [Rime 输入法](https://rime.im) 的键入数据。

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift 5.10](https://img.shields.io/badge/Swift-5.10-orange) ![License](https://img.shields.io/badge/license-MIT-green)

## 功能

- **状态栏实时显示** — 今日字数、打字速度、峰值速度，一眼掌握
- **今日详情** — 中英文分布、活跃时长、提交次数、新造词数
- **7 天历史** — 每日字数、速度、活跃时长一览
- **累计统计** — 总字数、总时长、总提交，按天汇总
- **开机自启** — 一键开关，无需手动配置登录项
- **实时监听** — 基于文件系统事件，数据文件变化后即时刷新

## 数据来源

RimePulse 读取 Rime 输入法 Lua 插件生成的统计文件：

| 文件 | 说明 |
|------|------|
| `typing_stats_today.json` | 今日实时统计 |
| `typing_stats.jsonl` | 历史记录（每天一行 JSON） |

> 需要在 Rime 中配置对应的 Lua 统计插件来生成这些文件。

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

### typing_stats_today.json

```json
{
  "date": "2026-04-04",
  "created_at": 1743724800,
  "updated_at": 1743768000,
  "chars": 1730,
  "chars_cjk": 1424,
  "chars_ascii": 92,
  "commits": 646,
  "avg_word_length": 2.1,
  "chars_per_minute": 52,
  "peak_cpm": 158,
  "active_minutes": 33.3,
  "new_words_count": 283,
  "new_words": ["新词1", "新词2"]
}
```

### typing_stats.jsonl

每行一条 JSON，格式同上，每天一条记录。

## 技术栈

- Swift 5.10 / SwiftUI
- Swift Package Manager
- `DispatchSource` 文件系统监听
- `SMAppService` 登录项管理
- macOS 14 (Sonoma) +

## License

MIT
