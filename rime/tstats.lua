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

-- 速度算法参数：按秒分桶的环形滑动窗口
-- 设计动机：事件级窗口对"整词一次上屏"不稳定（会被 MIN_SPAN clamp），
-- 秒桶把时间轴切成等间隔格子，空闲秒自然计入分母，停打后数字平滑衰减。
local BUCKET_COUNT           = 60     -- 环形桶总数（≥ PEAK_WINDOW_SEC）
local CURRENT_WINDOW_SEC     = 15     -- 当前速度窗口
local PEAK_WINDOW_SEC        = 60     -- 峰值速度窗口
local BUCKET_MIN_CHARS_CURR  = 4      -- 当前速度的最低触发字符数
local BUCKET_MIN_CHARS_PEAK  = 12     -- 峰值更新的最低触发字符数
local BURST_MIN_MS           = 200    -- burst 计算的最短组合时长（防除零虚高）
local BURST_MAX_MS           = 120000 -- burst 计算的最长组合时长（防候选挂起）
local IDLE_RESET_MS          = 20000  -- 空闲判定阈值（复用给 compose_start 失效）

local buckets = {}
local last_bucket_sec = 0

local function reset_buckets()
    for i = 0, BUCKET_COUNT - 1 do
        buckets[i] = 0
    end
    last_bucket_sec = 0
end

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
        chars_ascii = 0,
        commits = 0,
        active_ms = 0,
        current_cpm = 0,
        peak_cpm = 0,
        burst_cpm = 0,
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

-- 秒桶：advance 填补 (last_bucket_sec, now_sec] 之间的空秒为 0
local function advance_buckets(now_sec)
    if last_bucket_sec == 0 then
        last_bucket_sec = now_sec
        return
    end
    if now_sec <= last_bucket_sec then
        return  -- 同一秒或时钟回拨，不做清零
    end
    local gap = now_sec - last_bucket_sec
    if gap >= BUCKET_COUNT then
        for i = 0, BUCKET_COUNT - 1 do buckets[i] = 0 end
    else
        for k = 1, gap do
            buckets[(last_bucket_sec + k) % BUCKET_COUNT] = 0
        end
    end
    last_bucket_sec = now_sec
end

local function deposit(now_sec, n)
    advance_buckets(now_sec)
    local idx = now_sec % BUCKET_COUNT
    buckets[idx] = buckets[idx] + n
end

-- 求最近 window_sec 秒内的字符总数（含 now_sec 这一格）
local function window_sum(now_sec, window_sec)
    local total = 0
    local span = math.min(window_sec, BUCKET_COUNT)
    for k = 0, span - 1 do
        local sec = now_sec - k
        if sec >= 0 then
            total = total + (buckets[sec % BUCKET_COUNT] or 0)
        end
    end
    return total
end

local function update_speeds(now_sec)
    local cur_total = window_sum(now_sec, CURRENT_WINDOW_SEC)
    if cur_total < BUCKET_MIN_CHARS_CURR then
        stats.current_cpm = 0
    else
        stats.current_cpm = math.floor(cur_total * 60 / CURRENT_WINDOW_SEC)
    end

    local peak_total = window_sum(now_sec, PEAK_WINDOW_SEC)
    if peak_total >= BUCKET_MIN_CHARS_PEAK then
        local peak_cpm_new = math.floor(peak_total * 60 / PEAK_WINDOW_SEC)
        if peak_cpm_new > stats.peak_cpm then
            stats.peak_cpm = peak_cpm_new
        end
    end
    -- 当前速度不应超过峰值记录
    if stats.current_cpm > stats.peak_cpm then
        stats.peak_cpm = stats.current_cpm
    end
end

local function count_text(text)
    local cjk = 0
    local ascii = 0
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
        old.chars_ascii = tonumber(c:match('"chars_ascii"%s*:%s*(%d+)'))
                          or tonumber(c:match('"words_en"%s*:%s*(%d+)')) or 0
        old.commits = tonumber(c:match('"commits"%s*:%s*(%d+)')) or 0
        old.active_ms = (tonumber(c:match('"active_minutes"%s*:%s*([%d%.]+)')) or 0) * 60000
        old.current_cpm = tonumber(c:match('"current_cpm"%s*:%s*(%d+)')) or 0
        old.peak_cpm = tonumber(c:match('"peak_cpm"%s*:%s*(%d+)')) or 0
        old.burst_cpm = tonumber(c:match('"burst_cpm"%s*:%s*(%d+)')) or 0
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
    s.chars_ascii = tonumber(c:match('"chars_ascii"%s*:%s*(%d+)'))
                    or tonumber(c:match('"words_en"%s*:%s*(%d+)')) or 0
    s.commits = tonumber(c:match('"commits"%s*:%s*(%d+)')) or 0
    s.active_ms = (tonumber(c:match('"active_minutes"%s*:%s*([%d%.]+)')) or 0) * 60000
    s.current_cpm = tonumber(c:match('"current_cpm"%s*:%s*(%d+)')) or 0
    s.peak_cpm = tonumber(c:match('"peak_cpm"%s*:%s*(%d+)')) or 0
    s.burst_cpm = tonumber(c:match('"burst_cpm"%s*:%s*(%d+)')) or 0
    return s
end

local function save_today()
    if not stats or stats.chars == 0 then return end
    stats.updated_at = now_ms()
    local min, cpm, avg_len = derived(stats)
    local peak = stats.peak_cpm
    local content = string.format('{\n'
        .. '  "date": "%s",\n'
        .. '  "created_at": %d,\n'
        .. '  "updated_at": %d,\n'
        .. '  "chars": %d,\n'
        .. '  "chars_cjk": %d,\n'
        .. '  "chars_ascii": %d,\n'
        .. '  "commits": %d,\n'
        .. '  "avg_word_length": %.1f,\n'
        .. '  "chars_per_minute": %d,\n'
        .. '  "current_cpm": %d,\n'
        .. '  "peak_cpm": %d,\n'
        .. '  "burst_cpm": %d,\n'
        .. '  "active_minutes": %.1f,\n'
        .. '  "new_words_count": %d,\n'
        .. '  "new_words": [%s]\n}\n',
        stats.date, stats.created_at, stats.updated_at,
        stats.chars, stats.chars_cjk, stats.chars_ascii,
        stats.commits, avg_len, cpm, stats.current_cpm, peak, stats.burst_cpm, min,
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
        .. '"chars":%d,"chars_cjk":%d,"chars_ascii":%d,'
        .. '"commits":%d,"avg_word_length":%.1f,'
        .. '"chars_per_minute":%d,"current_cpm":%d,"peak_cpm":%d,"burst_cpm":%d,"active_minutes":%.1f,'
        .. '"new_words_count":%d,"new_words":[%s]}\n',
        stats.date, stats.created_at, stats.updated_at,
        stats.chars, stats.chars_cjk, stats.chars_ascii,
        stats.commits, avg_len, cpm, stats.current_cpm, peak, stats.burst_cpm, min,
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
        reset_buckets()
        last_commit_ts_ms = 0
        last_save_ts_ms = 0
        compose_start_ts_ms = 0
    end

    local now = tick_ms()
    local now_sec = math.floor(now / 1000)
    local long_idle = last_commit_ts_ms > 0 and
        (now < last_commit_ts_ms or now - last_commit_ts_ms >= IDLE_RESET_MS)

    local cjk, ascii = count_text(text)
    local n = cjk + ascii

    stats.chars = stats.chars + n
    stats.chars_cjk = stats.chars_cjk + cjk
    stats.chars_ascii = stats.chars_ascii + ascii
    stats.commits = stats.commits + 1

    -- 精确计时：组合开始(首次按键) → 上屏，累加这段时间
    -- 同时用这段时间算 burst_cpm（单次组合的瞬时速度）
    if compose_start_ts_ms > 0 then
        local compose_time = now - compose_start_ts_ms
        if compose_time > 0 and compose_time < BURST_MAX_MS then
            stats.active_ms = stats.active_ms + compose_time
            if not long_idle and n > 0 then
                local burst_ms = math.max(compose_time, BURST_MIN_MS)
                local burst = math.floor(n * 60000 / burst_ms)
                if burst > stats.burst_cpm then
                    stats.burst_cpm = burst
                end
            end
        end
        compose_start_ts_ms = 0
    end
    last_commit_ts_ms = now

    deposit(now_sec, n)
    update_speeds(now_sec)

    -- 1 秒防抖：距上次写入超过 1 秒才落盘
    if now - last_save_ts_ms >= 1000 then
        save_today()
        last_save_ts_ms = now
    end
end

function M.init(env)
    data_dir = rime_api.get_user_data_dir()
    M.page_size = env.engine.schema.page_size or 5
    reset_buckets()
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
            if compose_start_ts_ms == 0 then
                compose_start_ts_ms = tick_ms()
            end
        else
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
