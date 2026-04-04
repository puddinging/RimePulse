-- 打字统计：每日字数、打字速度、中英比例、新造词
-- 挂载：engine/filters 中添加 lua_filter@*tstats
-- 数据文件：{rime_user_dir}/
--   typing_stats_today.json  — 当日实时统计（覆盖更新）
--   typing_stats.jsonl       — 历史统计（JSONL 逐日追加）

local M = {}

local stats = nil
local seen_today = {}
local user_phrases = {}
local last_commit_ts = 0
local last_save_ts = 0
local compose_start_ts = 0   -- 当前组合开始时间（首次按键）
local data_dir = ""

local function json_esc(s)
    return s:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '')
end

local function now_ms()
    return os.time() * 1000
end

local function new_stats()
    return {
        date = os.date("%Y-%m-%d"),
        created_at = now_ms(),
        updated_at = now_ms(),
        chars = 0,
        chars_cjk = 0,
        chars_ascii = 0,
        commits = 0,
        active_seconds = 0,
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
    local min = s.active_seconds / 60
    local cpm = min > 0 and math.floor(s.chars / min) or 0
    local avg_len = s.commits > 0 and (s.chars / s.commits) or 0
    return min, cpm, avg_len
end

-- 峰值速度：60 秒滑动窗口
local peak_window = {}

local function update_peak(now, char_count)
    peak_window[#peak_window + 1] = { t = now, c = char_count }
    local cutoff = now - 60
    local new_win = {}
    local total = 0
    for _, entry in ipairs(peak_window) do
        if entry.t > cutoff then
            new_win[#new_win + 1] = entry
            total = total + entry.c
        end
    end
    peak_window = new_win
    if #new_win >= 3 then
        local span = new_win[#new_win].t - new_win[1].t
        if span >= 10 then
            local window_cpm = math.floor(total / span * 60)
            if window_cpm > stats.peak_cpm then
                stats.peak_cpm = window_cpm
            end
        end
    end
end

local function count_cjk(text)
    local cjk, ascii = 0, 0
    for _, cp in utf8.codes(text) do
        if (cp >= 0x4E00 and cp <= 0x9FFF) or
           (cp >= 0x3400 and cp <= 0x4DBF) or
           (cp >= 0x20000 and cp <= 0x2A6DF) then
            cjk = cjk + 1
        elseif cp >= 0x21 and cp <= 0x7E then
            ascii = ascii + 1
        end
    end
    return cjk, ascii
end

local function load_today()
    local f = io.open(data_dir .. "/typing_stats_today.json", "r")
    if not f then return nil end
    local c = f:read("*a")
    f:close()
    local d = c:match('"date"%s*:%s*"([^"]+)"')
    if d ~= os.date("%Y-%m-%d") then return nil end
    local s = new_stats()
    s.date = d
    s.created_at = tonumber(c:match('"created_at"%s*:%s*(%d+)')) or now_ms()
    s.chars = tonumber(c:match('"chars"%s*:%s*(%d+)')) or 0
    s.chars_cjk = tonumber(c:match('"chars_cjk"%s*:%s*(%d+)')) or 0
    s.chars_ascii = tonumber(c:match('"chars_ascii"%s*:%s*(%d+)')) or 0
    s.commits = tonumber(c:match('"commits"%s*:%s*(%d+)')) or 0
    s.active_seconds = (tonumber(c:match('"active_minutes"%s*:%s*([%d%.]+)')) or 0) * 60
    s.peak_cpm = tonumber(c:match('"peak_cpm"%s*:%s*(%d+)')) or 0
    local ws = c:match('"new_words"%s*:%s*%[(.-)%]')
    if ws then
        for w in ws:gmatch('"([^"]+)"') do
            s.new_words[#s.new_words + 1] = w
            seen_today[w] = true
        end
    end
    return s
end

local function save_today()
    if not stats or stats.chars == 0 then return end
    stats.updated_at = now_ms()
    local f = io.open(data_dir .. "/typing_stats_today.json", "w")
    if not f then return end
    local min, cpm, avg_len = derived(stats)
    f:write(string.format('{\n'
        .. '  "date": "%s",\n'
        .. '  "created_at": %d,\n'
        .. '  "updated_at": %d,\n'
        .. '  "chars": %d,\n'
        .. '  "chars_cjk": %d,\n'
        .. '  "chars_ascii": %d,\n'
        .. '  "commits": %d,\n'
        .. '  "avg_word_length": %.1f,\n'
        .. '  "chars_per_minute": %d,\n'
        .. '  "peak_cpm": %d,\n'
        .. '  "active_minutes": %.1f,\n'
        .. '  "new_words_count": %d,\n'
        .. '  "new_words": [%s]\n}\n',
        stats.date, stats.created_at, stats.updated_at,
        stats.chars, stats.chars_cjk, stats.chars_ascii,
        stats.commits, avg_len, cpm, stats.peak_cpm, min,
        #stats.new_words, words_json(stats.new_words)
    ))
    f:close()
end

local function archive()
    if not stats or stats.chars == 0 then return end
    stats.updated_at = now_ms()
    local f = io.open(data_dir .. "/typing_stats.jsonl", "a")
    if not f then return end
    local min, cpm, avg_len = derived(stats)
    f:write(string.format(
        '{"date":"%s","created_at":%d,"updated_at":%d,'
        .. '"chars":%d,"chars_cjk":%d,"chars_ascii":%d,'
        .. '"commits":%d,"avg_word_length":%.1f,'
        .. '"chars_per_minute":%d,"peak_cpm":%d,"active_minutes":%.1f,'
        .. '"new_words_count":%d,"new_words":[%s]}\n',
        stats.date, stats.created_at, stats.updated_at,
        stats.chars, stats.chars_cjk, stats.chars_ascii,
        stats.commits, avg_len, cpm, stats.peak_cpm, min,
        #stats.new_words, words_json(stats.new_words)
    ))
    f:close()
end

local function on_commit(ctx)
    local text = ctx:get_commit_text()
    if not text or #text == 0 then return end

    local today = os.date("%Y-%m-%d")
    if stats.date ~= today then
        archive()
        stats = new_stats()
        seen_today = {}
        user_phrases = {}
        peak_window = {}
        last_commit_ts = 0
        last_save_ts = 0
        compose_start_ts = 0
    end

    local now = os.time()
    local n = utf8.len(text) or 0
    local cjk, ascii = count_cjk(text)

    stats.chars = stats.chars + n
    stats.chars_cjk = stats.chars_cjk + cjk
    stats.chars_ascii = stats.chars_ascii + ascii
    stats.commits = stats.commits + 1

    -- 精确计时：组合开始(首次按键) → 上屏，累加这段时间
    if compose_start_ts > 0 then
        local compose_time = now - compose_start_ts
        if compose_time > 0 and compose_time < 120 then
            stats.active_seconds = stats.active_seconds + compose_time
        end
        compose_start_ts = 0
    end
    last_commit_ts = now

    update_peak(now, n)

    if n >= 2 and user_phrases[text] and not seen_today[text] then
        seen_today[text] = true
        stats.new_words[#stats.new_words + 1] = text
    end

    -- 1 秒防抖：距上次写入超过 1 秒才落盘
    if now - last_save_ts >= 1 then
        save_today()
        last_save_ts = now
    end
end

function M.init(env)
    data_dir = rime_api.get_user_data_dir()
    M.page_size = env.engine.schema.page_size or 5
    stats = load_today() or new_stats()

    env.commit_conn = env.engine.context.commit_notifier:connect(function(ctx)
        pcall(on_commit, ctx)
    end)

    -- 监听上下文变化，检测组合开始（首次按键）
    env.update_conn = env.engine.context.update_notifier:connect(function(ctx)
        if not ctx.composition:empty() then
            -- 正在组合中，如果还没记录开始时间就记录
            if compose_start_ts == 0 then
                compose_start_ts = os.time()
            end
        else
            -- 组合已清空（Esc 放弃或上屏后清空）
            -- 上屏的情况已在 on_commit 中处理，这里只重置残留状态
            compose_start_ts = 0
        end
    end)
end

function M.func(input)
    for cand in input:iter() do
        if cand.type == "user_phrase" then
            user_phrases[cand.text] = true
        end
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
