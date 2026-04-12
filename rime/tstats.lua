-- 打字统计：每日字数、打字速度、中英比例
-- 挂载：engine/filters 中添加 lua_filter@*tstats
-- 数据文件：{rime_user_dir}/
--   typing_stats_today.txt   — 当日实时统计（覆盖更新，主文件）
--   typing_stats.txt         — 历史统计（JSONL 逐日追加，主文件）
-- 兼容：同时写入旧文件
--   typing_stats_today.json
--   typing_stats.jsonl

local M = {}

local stats = nil
local last_commit_ts_ms = 0
local last_save_ts_ms = 0
local compose_start_ts_ms = 0   -- 当前组合开始时间（首次按键）
local data_dir = ""
local today_file = "typing_stats_today.txt"
local history_file = "typing_stats.txt"
local legacy_today_file = "typing_stats_today.json"
local legacy_history_file = "typing_stats.jsonl"
local archive

-- 实时速度参数（参考常见打字应用的“秒级采样 + 窗口平滑”思路）
local SPEED_WINDOW_MS = 15000
local PEAK_WINDOW_MS = 60000
local MIN_CURRENT_SPAN_MS = 6000
local MIN_CURRENT_COMMITS = 2
local MIN_CURRENT_CHARS = 4
local CURRENT_EMA_ALPHA = 0.35
local PEAK_MIN_SPAN_MS = 10000
local PEAK_MIN_COMMITS = 3
local PEAK_MIN_CHARS = 12
local IDLE_RESET_MS = 20000

local function json_esc(s)
    return s:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '')
end

local function now_ms()
    return os.time() * 1000
end

local function tick_ms()
    if rime_api and rime_api.get_time_ms then
        local ok, t = pcall(rime_api.get_time_ms)
        if ok and type(t) == "number" and t > 0 then
            return t
        end
    end
    return os.time() * 1000
end

local function read_first_existing(files)
    for _, file in ipairs(files) do
        local f = io.open(data_dir .. "/" .. file, "r")
        if f then
            local content = f:read("*a")
            f:close()
            return content
        end
    end
    return nil
end

local function write_file(path, content, mode)
    local f = io.open(path, mode or "w")
    if not f then return false end
    f:write(content)
    f:close()
    return true
end

local function history_has_date(path, date)
    local f = io.open(path, "r")
    if not f then return false end
    local content = f:read("*a")
    f:close()
    return content:find('"date"%s*:%s*"' .. date .. '"') ~= nil
end

local function clear_stale_today_files()
    os.remove(data_dir .. "/" .. today_file)
    os.remove(data_dir .. "/" .. legacy_today_file)
end

local function new_stats()
    return {
        date = os.date("%Y-%m-%d"),
        created_at = now_ms(),
        updated_at = now_ms(),
        chars = 0,
        chars_cjk = 0,
        words_en = 0,
        commits = 0,
        active_ms = 0,
        current_cpm = 0,
        peak_cpm = 0,
        new_words = {},
    }
end

local function words_json(words)
    local t = {}
    for _, w in ipairs(words) do
        t[#t + 1] = '"' .. json_esc(w) .. '"'
    end
    return table.concat(t, ', ')
end

local function derived(s)
    local min = s.active_ms / 60000
    local cpm = min > 0 and math.floor(s.chars / min) or 0
    local avg_len = s.commits > 0 and (s.chars / s.commits) or 0
    return min, cpm, avg_len
end

-- 实时速度与峰值：滑动窗口（毫秒） + 指数平滑（当前速度）
local speed_window = {}
local peak_window = {}

local function trim_window(window, cutoff_ms)
    local kept = {}
    local total = 0
    for _, entry in ipairs(window) do
        if entry.t > cutoff_ms then
            kept[#kept + 1] = entry
            total = total + entry.c
        end
    end
    return kept, total
end

local function update_current_speed(now, char_count)
    speed_window[#speed_window + 1] = { t = now, c = char_count }
    local total
    speed_window, total = trim_window(speed_window, now - SPEED_WINDOW_MS)

    if #speed_window < MIN_CURRENT_COMMITS or total < MIN_CURRENT_CHARS then
        stats.current_cpm = 0
        return
    end

    local span = speed_window[#speed_window].t - speed_window[1].t
    if span <= 0 then
        return
    end

    local span_for_calc = math.max(span, MIN_CURRENT_SPAN_MS)
    local raw_cpm = math.floor(total * 60000 / span_for_calc)
    if stats.current_cpm <= 0 then
        stats.current_cpm = raw_cpm
        return
    end

    local smoothed = stats.current_cpm * (1 - CURRENT_EMA_ALPHA) + raw_cpm * CURRENT_EMA_ALPHA
    stats.current_cpm = math.floor(smoothed + 0.5)
end

local function update_peak(now, char_count)
    peak_window[#peak_window + 1] = { t = now, c = char_count }
    local total
    peak_window, total = trim_window(peak_window, now - PEAK_WINDOW_MS)

    if #peak_window < PEAK_MIN_COMMITS or total < PEAK_MIN_CHARS then
        return
    end

    local span = peak_window[#peak_window].t - peak_window[1].t
    if span >= PEAK_MIN_SPAN_MS then
        local window_cpm = math.floor(total * 60000 / span)
        if window_cpm > stats.peak_cpm then
            stats.peak_cpm = window_cpm
        end
    end
end

local function count_text(text)
    local cjk = 0
    for _, cp in utf8.codes(text) do
        if (cp >= 0x4E00 and cp <= 0x9FFF) or
           (cp >= 0x3400 and cp <= 0x4DBF) or
           (cp >= 0x20000 and cp <= 0x2A6DF) then
            cjk = cjk + 1
        end
    end
    -- 英文按单词计数：匹配至少包含一个字母的连续非空白序列
    local words_en = 0
    for word in text:gmatch("%S+") do
        if word:match("[%a]") then
            words_en = words_en + 1
        end
    end
    return cjk, words_en
end

local function load_today()
    local c = read_first_existing({today_file, legacy_today_file})
    if not c then return nil end
    local d = c:match('"date"%s*:%s*"([^"]+)"')
    if d ~= os.date("%Y-%m-%d") then
        -- 文件是昨天（或更早）的数据，先归档再返回 nil
        local old = new_stats()
        old.date = d
        old.created_at = tonumber(c:match('"created_at"%s*:%s*(%d+)')) or 0
        old.updated_at = tonumber(c:match('"updated_at"%s*:%s*(%d+)')) or 0
        old.chars = tonumber(c:match('"chars"%s*:%s*(%d+)')) or 0
        old.chars_cjk = tonumber(c:match('"chars_cjk"%s*:%s*(%d+)')) or 0
        old.words_en = tonumber(c:match('"words_en"%s*:%s*(%d+)')) or 0
        old.commits = tonumber(c:match('"commits"%s*:%s*(%d+)')) or 0
        old.active_ms = (tonumber(c:match('"active_minutes"%s*:%s*([%d%.]+)')) or 0) * 60000
        old.current_cpm = tonumber(c:match('"current_cpm"%s*:%s*(%d+)')) or 0
        old.peak_cpm = tonumber(c:match('"peak_cpm"%s*:%s*(%d+)')) or 0
        if old.chars > 0 then
            stats = old
            local archived = archive()
            stats = nil
            if archived then
                clear_stale_today_files()
            end
        else
            clear_stale_today_files()
        end
        return nil
    end
    local s = new_stats()
    s.date = d
    s.created_at = tonumber(c:match('"created_at"%s*:%s*(%d+)')) or now_ms()
    s.chars = tonumber(c:match('"chars"%s*:%s*(%d+)')) or 0
    s.chars_cjk = tonumber(c:match('"chars_cjk"%s*:%s*(%d+)')) or 0
    s.words_en = tonumber(c:match('"words_en"%s*:%s*(%d+)')) or 0
    s.commits = tonumber(c:match('"commits"%s*:%s*(%d+)')) or 0
    s.active_ms = (tonumber(c:match('"active_minutes"%s*:%s*([%d%.]+)')) or 0) * 60000
    s.current_cpm = tonumber(c:match('"current_cpm"%s*:%s*(%d+)')) or 0
    s.peak_cpm = tonumber(c:match('"peak_cpm"%s*:%s*(%d+)')) or 0
    return s
end

local function save_today()
    if not stats or stats.chars == 0 then return end
    stats.updated_at = now_ms()
    local min, cpm, avg_len = derived(stats)
    -- 峰值仅来自滑动窗口统计，不与当日平均速度混用
    local peak = stats.peak_cpm
    local content = string.format('{\n'
        .. '  "date": "%s",\n'
        .. '  "created_at": %d,\n'
        .. '  "updated_at": %d,\n'
        .. '  "chars": %d,\n'
        .. '  "chars_cjk": %d,\n'
        .. '  "words_en": %d,\n'
        .. '  "commits": %d,\n'
        .. '  "avg_word_length": %.1f,\n'
        .. '  "chars_per_minute": %d,\n'
        .. '  "current_cpm": %d,\n'
        .. '  "peak_cpm": %d,\n'
        .. '  "active_minutes": %.1f,\n'
        .. '  "new_words_count": %d,\n'
        .. '  "new_words": [%s]\n}\n',
        stats.date, stats.created_at, stats.updated_at,
        stats.chars, stats.chars_cjk, stats.words_en,
        stats.commits, avg_len, cpm, stats.current_cpm, peak, min,
        #stats.new_words, words_json(stats.new_words)
    )

    local p1 = data_dir .. "/" .. today_file
    local p2 = data_dir .. "/" .. legacy_today_file
    local ok_primary = write_file(p1, content, "w")
    local ok_legacy = write_file(p2, content, "w")
    if not ok_primary and not ok_legacy then
        return
    end
end

archive = function()
    if not stats or stats.chars == 0 then return false end
    stats.updated_at = now_ms()
    local min, cpm, avg_len = derived(stats)
    local peak = stats.peak_cpm
    local line = string.format(
        '{"date":"%s","created_at":%d,"updated_at":%d,'
        .. '"chars":%d,"chars_cjk":%d,"words_en":%d,'
        .. '"commits":%d,"avg_word_length":%.1f,'
        .. '"chars_per_minute":%d,"current_cpm":%d,"peak_cpm":%d,"active_minutes":%.1f,'
        .. '"new_words_count":%d,"new_words":[%s]}\n',
        stats.date, stats.created_at, stats.updated_at,
        stats.chars, stats.chars_cjk, stats.words_en,
        stats.commits, avg_len, cpm, stats.current_cpm, peak, min,
        #stats.new_words, words_json(stats.new_words)
    )

    local p1 = data_dir .. "/" .. history_file
    local p2 = data_dir .. "/" .. legacy_history_file
    local ok_primary = history_has_date(p1, stats.date) or write_file(p1, line, "a")
    local ok_legacy = history_has_date(p2, stats.date) or write_file(p2, line, "a")
    return ok_primary or ok_legacy
end

local function on_commit(ctx)
    local text = ctx:get_commit_text()
    if not text or #text == 0 then return end

    local today = os.date("%Y-%m-%d")
    if stats.date ~= today then
        archive()
        stats = new_stats()
        speed_window = {}
        peak_window = {}
        last_commit_ts_ms = 0
        last_save_ts_ms = 0
        compose_start_ts_ms = 0
    end

    local now = tick_ms()
    if last_commit_ts_ms > 0 and (now < last_commit_ts_ms or now - last_commit_ts_ms >= IDLE_RESET_MS) then
        speed_window = {}
        stats.current_cpm = 0
    end

    local cjk, words_en = count_text(text)
    local n = cjk + words_en

    stats.chars = stats.chars + n
    stats.chars_cjk = stats.chars_cjk + cjk
    stats.words_en = stats.words_en + words_en
    stats.commits = stats.commits + 1

    -- 精确计时：组合开始(首次按键) → 上屏，累加这段时间
    if compose_start_ts_ms > 0 then
        local compose_time = now - compose_start_ts_ms
        if compose_time > 0 and compose_time < 120000 then
            stats.active_ms = stats.active_ms + compose_time
        end
        compose_start_ts_ms = 0
    end
    last_commit_ts_ms = now

    update_current_speed(now, n)
    update_peak(now, n)

    -- 1 秒防抖：距上次写入超过 1 秒才落盘
    if now - last_save_ts_ms >= 1000 then
        save_today()
        last_save_ts_ms = now
    end
end

function M.init(env)
    data_dir = rime_api.get_user_data_dir()
    M.page_size = env.engine.schema.page_size or 5
    stats = load_today() or new_stats()
    if stats and stats.updated_at > 0 and now_ms() - stats.updated_at >= IDLE_RESET_MS then
        stats.current_cpm = 0
    end

    env.commit_conn = env.engine.context.commit_notifier:connect(function(ctx)
        pcall(on_commit, ctx)
    end)

    -- 监听上下文变化，检测组合开始（首次按键）
    env.update_conn = env.engine.context.update_notifier:connect(function(ctx)
        if not ctx.composition:empty() then
            -- 正在组合中，如果还没记录开始时间就记录
            if compose_start_ts_ms == 0 then
                compose_start_ts_ms = tick_ms()
            end
        else
            -- 组合已清空（Esc 放弃或上屏后清空）
            -- 上屏的情况已在 on_commit 中处理，这里只重置残留状态
            compose_start_ts_ms = 0
        end
    end)
end

function M.func(input)
    for cand in input:iter() do
        yield(cand)
    end
end

function M.fini(env)
    save_today()
    if env.commit_conn then
        env.commit_conn:disconnect()
    end
    if env.update_conn then
        env.update_conn:disconnect()
    end
end

return M
