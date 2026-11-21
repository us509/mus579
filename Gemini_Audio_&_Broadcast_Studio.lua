-- Extension Name : Gemini Audio & Broadcast Studio
-- Created By     : Mohammed Usman (WhatsApp: 03261421100)
-- Platform       : Jieshuo Screen Reader (Lua 5.3+)
-- Modes          : 1) Single Speaker (TTS & Story)
-- 2) 2-Host Broadcast (Male + Female)

-- PART 1 OF 3: Imports, State, Lists, English Guide, Logger, HTTP & WAV

require "import"
import "com.androlua.Http"
import "cjson"
import "com.androlua.LuaDialog"
import "android.widget.*"
import "android.view.*"
import "android.content.Context"
import "android.content.Intent"
import "android.content.ContentValues"
import "android.content.ClipboardManager"
import "android.content.ClipData"
import "android.net.Uri"
import "android.media.MediaPlayer"
import "android.util.Base64"
import "android.os.*"
import "android.graphics.Typeface"
import "android.graphics.Color"
import "java.io.*"
import "java.util.HashMap"
import "android.text.InputFilter"
import "android.text.InputType"
import "android.view.accessibility.AccessibilityEvent"

local context = activity or service
local mainHandler = Handler(Looper.getMainLooper())

-- Network Timeouts (4 minutes for large chunks)
pcall(function() Http.setConnTimeout(60000) end)
pcall(function() Http.setReadTimeout(240000) end)
pcall(function() Http.setTimeout(240000) end)

-- Global Background State (Survives EXIT / Re-open)
if not _G.GEMINI_ABS_STATE then
    _G.GEMINI_ABS_STATE = {
        isGenerating = false,
        isWritingScript = false,
        percent = 0,
        statusText = "Status: Ready",
        generatedAudioPath = nil,
        currentDurationStr = "",
        mediaPlayer = nil,
        isPlaying = false,
        ui = nil
    }
end
local S = _G.GEMINI_ABS_STATE

-- Unified Module Table (Avoids Lua 200-local limit)
local M = {}

M.APP_TITLE = "Gemini Audio & Broadcast Studio"
M.CREATOR_NAME = "Mohammed Usman"
M.WHATSAPP_LOCAL = "03261421100"
M.WHATSAPP_INTL = "923261421100"
M.MAX_CHAR_LIMIT = 25000
M.TARGET_CHARS_PER_PART = 2900
M.PAUSE_DURATION_MS = 420

M.MODE_LIST = {
    "Single Speaker (TTS & Story)",
    "2-Host Broadcast (Male + Female)"
}

M.MODEL_LIST = {
    "gemini-3.8-flash-tts",
    "gemini-3.8-flash-lite-tts"
}
M.DEFAULT_MODEL = "gemini-3.8-flash-tts"

-- 30 Voices for Single Speaker Mode
M.VOICE_LIST = {
    "Puck (Male)", "Kore (Female)", "Charon (Male)", "Zephyr (Female)",
    "Fenrir (Male)", "Leda (Female)", "Orus (Male)", "Aoede (Female)",
    "Callirrhoe (Female)", "Autonoe (Female)", "Enceladus (Male)", "Iapetus (Male)",
    "Umbriel (Male)", "Algieba (Female)", "Despina (Female)", "Erinome (Female)",
    "Algenib (Male)", "Rasalgethi (Male)", "Laomedeia (Female)", "Achernar (Male)",
    "Alnilam (Male)", "Schedar (Male)", "Gacrux (Male)", "Pulcherrima (Female)",
    "Achird (Friendly)", "Zubenelgenubi (Casual)", "Vindemiatrix (Gentle)",
    "Sadachbia (Lively)", "Sadaltager (Knowledgeable)", "Sulafat (Warm)"
}

M.RAW_VOICES = {
    "Puck", "Kore", "Charon", "Zephyr", "Fenrir", "Leda",
    "Orus", "Aoede", "Callirrhoe", "Autonoe", "Enceladus", "Iapetus",
    "Umbriel", "Algieba", "Despina", "Erinome", "Algenib", "Rasalgethi",
    "Laomedeia", "Achernar", "Alnilam", "Schedar", "Gacrux", "Pulcherrima",
    "Achird", "Zubenelgenubi", "Vindemiatrix", "Sadachbia", "Sadaltager", "Sulafat"
}

-- Separate Male & Female Voices for 2-Host Broadcast Mode
M.MALE_VOICES = {
    "Puck", "Charon", "Fenrir", "Orus", "Enceladus",
    "Iapetus", "Umbriel", "Algenib", "Rasalgethi", "Achernar",
    "Alnilam", "Schedar", "Gacrux", "Zubenelgenubi", "Sadaltager"
}

M.FEMALE_VOICES = {
    "Kore", "Zephyr", "Leda", "Aoede", "Callirrhoe",
    "Autonoe", "Algieba", "Despina", "Erinome", "Laomedeia",
    "Pulcherrima", "Vindemiatrix", "Sadachbia", "Sulafat"
}

-- 20 Languages
M.LANGUAGES = {
    "English (USA)",
    "Urdu (Pakistan - اردو)",
    "Roman Urdu (Pakistan - ABC)",
    "Hindi (हिन्दी)",
    "Bengali (বাংলা)",
    "Nepali (नेपाली)",
    "Arabic (العربية)",
    "Punjabi (پنجابی)",
    "Pashto (پښتو)",
    "Sindhi (سنڌي)",
    "Persian / Farsi (فارسی)",
    "Chinese / Mandarin (中文)",
    "Tamil (தமிழ்)",
    "Telugu (తెలుగు)",
    "Marathi (मराठी)",
    "Gujarati (ગુજરાતી)",
    "Malayalam (മലയാളം)",
    "Turkish (Türkçe)",
    "Spanish (Español)",
    "French (Français)"
}

M.DURATION_LIST = {
    "1 Minute",
    "5 Minutes",
    "10 Minutes",
    "15 Minutes",
    "Custom Minutes"
}

-- 24 Styles for Single Speaker Mode
M.SINGLE_STYLE_LIST = {
    "Default / Normal",
    "Funny Jokes / Comedy",
    "Islamic: Tilawat (Sudais/Shuraim - Fixed Pace)",
    "Islamic: Hadees (Arabic + Tarjuma)",
    "Islamic: Dua (Humble & Crying)",
    "Islamic: Naat / Kalam (Melodic)",
    "Islamic: Waqia / Story (Deep & Serious)",
    "Dynamic Human (Auto-Emotion: Laugh/Cry)",
    "Cartoon: Thin & Squeaky (Patli Aawaz)",
    "Cartoon: Thick & Goofy (Moti Aawaz)",
    "Storytelling (Expressive)",
    "Poetry / Shayari (Deep & Rhythmic)",
    "Horror / Scary / Suspense",
    "Angry / Aggressive (Gusse wala)",
    "Whispering / Secretive (Sargoshi)",
    "Happy / Joyful (Khushi)",
    "Comedy / Funny",
    "Romantic / Soft",
    "Dramatic / Thriller",
    "Sad / Emotional",
    "Sarcastic / Irony (Tanzana)",
    "Motivational / Inspiring",
    "News / Professional",
    "Documentary / Informative"
}

M.SINGLE_STYLE_TEXT = {
    ["Default / Normal"] = "calm, steady, natural studio narrator with uniform medium pace and neutral tone",
    ["Funny Jokes / Comedy"] = "witty, cheerful stand-up comedian delivering funny jokes with crisp comedic timing, light natural laughter on punchlines, and consistent voice",
    ["Islamic: Tilawat (Sudais/Shuraim - Fixed Pace)"] = "slow, melodic, deeply spiritual Quran recitation in a steady rhythmic pace",
    ["Islamic: Hadees (Arabic + Tarjuma)"] = "dignified and respectful Islamic scholar, calm, clear, slow and uniform pace",
    ["Islamic: Dua (Humble & Crying)"] = "humble, pleading, emotional prayerful voice at a slow steady pace",
    ["Islamic: Naat / Kalam (Melodic)"] = "sweet, melodic and rhythmic Naat recitation at a steady tempo",
    ["Islamic: Waqia / Story (Deep & Serious)"] = "deep, moving, serious Islamic historical narrator at a steady pace",
    ["Dynamic Human (Auto-Emotion: Laugh/Cry)"] = "natural expressive narrator keeping the exact same speaker voice and steady tempo",
    ["Cartoon: Thin & Squeaky (Patli Aawaz)"] = "high-pitched, squeaky cartoon character voice at a consistent pace",
    ["Cartoon: Thick & Goofy (Moti Aawaz)"] = "deep, thick, heavy goofy cartoon voice at a consistent slow pace",
    ["Storytelling (Expressive)"] = "warm, engaging audiobook storyteller with a steady, unhurried pace",
    ["Poetry / Shayari (Deep & Rhythmic)"] = "deep, rhythmic poet voice with measured pauses and constant tempo",
    ["Horror / Scary / Suspense"] = "low, creepy, suspenseful whisper at a slow, steady pace",
    ["Angry / Aggressive (Gusse wala)"] = "firm, intense, forceful voice at a controlled, steady pace",
    ["Whispering / Secretive (Sargoshi)"] = "quiet, secretive whisper at a constant volume and pace",
    ["Happy / Joyful (Khushi)"] = "warm, cheerful, pleasant voice at a steady medium pace",
    ["Comedy / Funny"] = "lighthearted, playful narrator voice at a steady pace",
    ["Romantic / Soft"] = "soft, warm, gentle voice at a slow, steady pace",
    ["Dramatic / Thriller"] = "serious, focused, intense narrator at a steady pace",
    ["Sad / Emotional"] = "sorrowful, heavy, calm emotional voice at a slow steady pace",
    ["Sarcastic / Irony (Tanzana)"] = "dry, composed, ironic narrator voice at a steady pace",
    ["Motivational / Inspiring"] = "strong, confident, clear speaker at a steady, measured pace",
    ["News / Professional"] = "clear, formal, professional news anchor at a strictly constant medium pace",
    ["Documentary / Informative"] = "calm, serious, informative documentary narrator at a steady pace"
}

-- 19 Moods for 2-Host Broadcast Mode
M.BROADCAST_MOODS = {
    "Funny Jokes (Male & Female Jokes)",
    "Funny / Comedy",
    "Storytelling",
    "Islamic / Spiritual",
    "Islamic Bayan / Waqia",
    "Tilawat / Quranic Reflection",
    "Romantic",
    "Sad / Emotional",
    "Informative / Educational",
    "News / Breaking",
    "Motivational / Inspiring",
    "Debate / Discussion",
    "Horror / Mystery",
    "Poetry / Shayari",
    "Thriller / Suspense",
    "Sarcastic / Roast",
    "Documentary / Deep Dive",
    "Kids / Cartoon Fun",
    "Interview / Talk Show"
}

-- Complete English (USA) User Guide
M.USER_GUIDE_TEXT = table.concat({
    "GEMINI AUDIO & BROADCAST STUDIO - USER GUIDE (ENGLISH USA)",
    "",
    "Welcome to Gemini Audio & Broadcast Studio, an all-in-one AI audio production extension for Jieshuo Screen Reader. You can generate studio-quality single-narrator voiceovers or realistic two-host (Male + Female) podcasts and broadcasts in 20 languages.",
    "",
    "1. FIRST-TIME SETUP (API KEY):",
    "- Open SETTING at the bottom of the main screen and tap SET API KEY.",
    "- Paste your Google Gemini API Key, tap TEST API KEY to verify it is active, and tap SAVE API KEY.",
    "- One single API Key powers both Single Speaker and 2-Host Broadcast modes.",
    "",
    "2. CHOOSING YOUR MODE:",
    "- Use the Select Mode dropdown at the top of the main screen:",
    "  * Single Speaker (TTS & Story): Choose from 30 voices and 24 narration styles (including Funny Jokes, Storytelling, Islamic Tilawat/Naat/Waqia, News, and more).",
    "  * 2-Host Broadcast (Male + Female): Choose a Male Voice (Speaker 1), a Female Voice (Speaker 2), and 19 broadcast moods (including Funny Jokes, Comedy, Debate, Storytelling, and Talk Show).",
    "",
    "3. LANGUAGE & DURATION:",
    "- Select any of the 20 supported languages (English USA, Urdu Pakistan, Roman Urdu, Hindi, Bengali, Nepali, Arabic, Punjabi, Pashto, Sindhi, Farsi, Chinese, and more).",
    "- Select a target duration (1, 5, 10, 15 Minutes) or choose Custom Minutes to enter any exact length you want.",
    "",
    "4. TWO-STEP WORKFLOW (CREATE SCRIPT vs. GENERATE AUDIO):",
    "- CREATE SCRIPT: Type any topic (or instructions to improve an existing script) in the text box and tap CREATE SCRIPT. The AI will write a clean script directly into the text box without generating audio yet. You can read, edit, copy, or clear it until you are satisfied.",
    "- GENERATE AUDIO: When your script or pasted text is ready, tap GENERATE AUDIO. The extension will convert it into smooth, consistent studio audio with locked voice tone and pitch.",
    "",
    "5. PROGRESS, BACKGROUND WORK & AUTO-RESUME:",
    "- Progress updates in 5% steps (5%, 10%, 15%... 100%) and shows how many parts are completed and remaining.",
    "- If you tap EXIT while audio is generating, the job continues safely in the background. Re-open the extension anytime to check progress.",
    "- If a network or server error occurs mid-way, all completed parts are saved automatically. Tap RESUME AUDIO to continue from the exact unfinished part.",
    "",
    "6. PLAY, SHARE, DOWNLOAD & REPORT ISSUE:",
    "- Tap PLAY / PAUSE to listen with full duration display.",
    "- Tap SHARE to send your generated audio directly to WhatsApp, Telegram, or any app via Android's share menu.",
    "- Tap DOWNLOAD to save the WAV file to your Downloads folder. Downloading automatically clears the text box and any old error logs.",
    "- If you ever encounter a technical issue, open SETTING -> REPORT ISSUE to copy or send the error log directly on WhatsApp for support."
}, "\n")

-- Preferences & Storage Paths
M.prefs = context.getSharedPreferences("Jieshuo_Gemini_ABS_Pro", Context.MODE_PRIVATE)
M.baseStorageDir = context.getFilesDir() or context.getCacheDir()
M.singleResumeDir = File(M.baseStorageDir, "abs_single_resume")
M.bcResumeDir = File(M.baseStorageDir, "abs_bc_resume")
if not M.singleResumeDir.exists() then M.singleResumeDir.mkdirs() end
if not M.bcResumeDir.exists() then M.bcResumeDir.mkdirs() end

-- Active User Config
M.cfg = {
    mode = "Single Speaker (TTS & Story)",
    singleVoice = "Puck",
    singleStyle = "Default / Normal",
    maleVoice = "Puck",
    femaleVoice = "Kore",
    bcMood = "Funny Jokes (Male & Female Jokes)",
    lang = "English (USA)",
    duration = "1 Minute",
    customMinutes = "3",
    model = M.DEFAULT_MODEL,
    apiKey = "",
    userText = ""
}
M.isUiInitializing = true

-- Issue / Error Report Logger (Only logs errors; auto-clears on Download)

function M.logIssue(source, message)
    pcall(function()
        local ts = os.date("%Y-%m-%d %H:%M:%S")
        local entry = string.format("[%s] Mode: %s | Model: %s | %s: %s",
            ts, tostring(M.cfg.mode), tostring(M.cfg.model), tostring(source), tostring(message))
        local existing = M.prefs.getString("issue_report_log", "")
        if existing ~= "" then
            existing = existing .. "\n\n" .. entry
        else
            existing = entry
        end
        if #existing > 8000 then
            existing = string.sub(existing, -8000)
        end
        local ed = M.prefs.edit()
        ed.putString("issue_report_log", existing)
        ed.commit()
    end)
end

function M.getIssueReport()
    return M.prefs.getString("issue_report_log", "")
end

function M.clearIssueReport()
    local ed = M.prefs.edit()
    ed.remove("issue_report_log")
    ed.commit()
end

-- Common Helpers

function M.trim(s)
    return (tostring(s or ""):match("^%s*(.-)%s*$"))
end

function M.sanitizeKey(s)
    local t = M.trim(s)
    t = t:gsub("[\r\n%s\"'`]+", "")
    return t
end

function M.utf8CharCount(s)
    if not s or s == "" then return 0 end
    local count = 0
    for i = 1, #s do
        local b = string.byte(s, i)
        if b < 128 or b >= 192 then count = count + 1 end
    end
    return count
end

function M.hashText(s)
    local h = 5381
    for i = 1, #s do
        h = ((h * 33) + string.byte(s, i)) & 0xFFFFFFFF
    end
    return tostring(h)
end

function M.getEffectiveMinutes()
    if M.cfg.duration == "Custom Minutes" then
        local n = tonumber(M.cfg.customMinutes)
        if not n or n < 1 then n = 1 end
        if n > 60 then n = 60 end
        return math.floor(n)
    end
    local n = tonumber(tostring(M.cfg.duration):match("(%d+)"))
    return n or 1
end

function M.setBtnColor(btn, hex)
    pcall(function() btn.setBackgroundColor(Color.parseColor(hex)) end)
end

function M.runOnUi(callback)
    mainHandler.post(Runnable({
        run = function() pcall(callback) end
    }))
end

function M.delay(ms, callback)
    mainHandler.postDelayed(Runnable({
        run = function() pcall(callback) end
    }), ms)
end

function M.showToast(msg)
    M.runOnUi(function()
        pcall(function() Toast.makeText(context, tostring(msg), Toast.LENGTH_SHORT).show() end)
    end)
end

function M.speakOnly(msg)
    local ok = pcall(function() service.speak(tostring(msg)) end)
    if not ok then M.showToast(msg) end
end

-- 5% Step Progress Updater (0%, 5%, 10%, 15% ... 100%)
function M.updateProgress(pct, msg, shouldSpeak)
    if pct ~= nil then
        local p = math.max(0, math.min(100, math.floor(pct)))
        if p > 0 and p < 100 then
            p = math.max(5, math.min(95, math.floor((p + 2.5) / 5) * 5))
        end
        S.percent = p
    end
    if msg ~= nil then
        S.statusText = tostring(msg)
    end
    local displayStr = "[" .. tostring(S.percent) .. "%] " .. S.statusText

    M.runOnUi(function()
        if S.ui then
            if S.ui.statusText then
                pcall(function() S.ui.statusText.setText(displayStr) end)
            end
            if S.ui.generateBtn and S.isGenerating then
                pcall(function()
                    S.ui.generateBtn.setEnabled(false)
                    S.ui.generateBtn.setText("GENERATING AUDIO (" .. tostring(S.percent) .. "%)...")
                    M.setBtnColor(S.ui.generateBtn, "#9E9E9E")
                end)
            end
            if S.ui.createScriptBtn and S.isWritingScript then
                pcall(function()
                    S.ui.createScriptBtn.setEnabled(false)
                    S.ui.createScriptBtn.setText("WRITING SCRIPT (" .. tostring(S.percent) .. "%)...")
                    M.setBtnColor(S.ui.createScriptBtn, "#9E9E9E")
                end)
            end
        end
    end)

    if shouldSpeak and msg then
        M.speakOnly(msg)
    end
end

function M.safe(name, fn)
    return function(...)
        local args = {...}
        local ok, err = pcall(function() return fn(table.unpack(args)) end)
        if not ok then
            S.isGenerating = false
            S.isWritingScript = false
            M.logIssue("CodeError:" .. tostring(name), tostring(err))
            M.updateProgress(S.percent, "Code error (" .. name .. "): " .. tostring(err), true)
            if M.refreshActionButtons then M.refreshActionButtons() end
        end
    end
end

function M.saveSettings()
    local ed = M.prefs.edit()
    ed.putString("mode", M.cfg.mode)
    ed.putString("single_voice", M.cfg.singleVoice)
    ed.putString("single_style", M.cfg.singleStyle)
    ed.putString("male_voice", M.cfg.maleVoice)
    ed.putString("female_voice", M.cfg.femaleVoice)
    ed.putString("bc_mood", M.cfg.bcMood)
    ed.putString("lang", M.cfg.lang)
    ed.putString("duration", M.cfg.duration)
    ed.putString("custom_minutes", M.cfg.customMinutes)
    ed.putString("model", M.cfg.model)
    ed.putString("apikey", M.cfg.apiKey)
    ed.commit()
end

function M.saveDraftText(txt)
    local ed = M.prefs.edit()
    ed.putString("draft_text", txt or "")
    ed.commit()
end

function M.loadSettings()
    M.cfg.mode = M.prefs.getString("mode", M.MODE_LIST[1])
    M.cfg.singleVoice = M.prefs.getString("single_voice", "Puck")
    M.cfg.singleStyle = M.prefs.getString("single_style", "Default / Normal")
    M.cfg.maleVoice = M.prefs.getString("male_voice", "Puck")
    M.cfg.femaleVoice = M.prefs.getString("female_voice", "Kore")
    M.cfg.bcMood = M.prefs.getString("bc_mood", M.BROADCAST_MOODS[1])
    M.cfg.lang = M.prefs.getString("lang", M.LANGUAGES[1])
    M.cfg.duration = M.prefs.getString("duration", "1 Minute")
    M.cfg.customMinutes = M.prefs.getString("custom_minutes", "3")
    M.cfg.model = M.prefs.getString("model", M.DEFAULT_MODEL)
    M.cfg.apiKey = M.sanitizeKey(M.prefs.getString("apikey", ""))
    M.cfg.userText = M.prefs.getString("draft_text", "")

    local validM = false
    for _, m in ipairs(M.MODEL_LIST) do
        if m == M.cfg.model then validM = true break end
    end
    if not validM then
        M.cfg.model = M.DEFAULT_MODEL
        M.saveSettings()
    end
end

function M.formatDurationText(totalSeconds)
    if not totalSeconds or totalSeconds < 0 then totalSeconds = 0 end
    totalSeconds = math.floor(totalSeconds + 0.5)
    local mins = math.floor(totalSeconds / 60)
    local secs = math.floor(totalSeconds % 60)
    if mins > 0 then
        return string.format("%d min %02d sec", mins, secs), string.format("%d minute %d second", mins, secs)
    else
        return string.format("0 min %02d sec", secs), string.format("%d second", secs)
    end
end

function M.extractApiError(content)
    local msg = nil
    pcall(function()
        local d = cjson.decode(content)
        if d and d.error and d.error.message then msg = d.error.message end
    end)
    return msg
end

-- HTTP Helpers & Auto Model Discovery

function M.httpPost(url, body, headers, cb)
    local wrappedCb = function(code, content)
        local ok, err = pcall(cb, code, content)
        if not ok then
            S.isGenerating = false
            S.isWritingScript = false
            M.logIssue("HttpPostCallback", tostring(err))
            M.updateProgress(S.percent, "Response Error: " .. tostring(err), true)
            if M.refreshActionButtons then M.refreshActionButtons() end
        end
    end
    local ok1, r1 = pcall(function() return Http.post(url, body, headers, wrappedCb) end)
    if ok1 then return true, r1 end
    local ok2, r2 = pcall(function() return Http.post(url, body, nil, "utf8", headers, wrappedCb) end)
    if ok2 then return true, r2 end
    return false, tostring(r1) .. " | " .. tostring(r2)
end

function M.httpGet(url, cb)
    local wrappedCb = function(code, content) pcall(cb, code, content) end
    local ok1, r1 = pcall(function() return Http.get(url, wrappedCb) end)
    if ok1 then return true, r1 end
    local ok2, r2 = pcall(function() return Http.get(url, nil, wrappedCb) end)
    if ok2 then return true, r2 end
    return false, tostring(r1) .. " | " .. tostring(r2)
end

function M.discoverWorkingScriptModels(apikey, callback)
    local url = "https://generativelanguage.googleapis.com/v1beta/models?key=" .. apikey
    local okGet, errGet = M.httpGet(url, function(code, content)
        if code ~= 200 then
            local msg = "Models list error (" .. tostring(code) .. "): " .. tostring(M.extractApiError(content) or "")
            M.logIssue("ListModels", msg)
            callback(nil, msg)
            return
        end
        local okDec, data = pcall(cjson.decode, content)
        if not okDec or not data or not data.models then
            M.logIssue("ListModels", "Invalid JSON response")
            callback(nil, "Models list could not be parsed.")
            return
        end

        local flashModels, otherGemini = {}, {}
        for _, m in ipairs(data.models) do
            local shortName = tostring(m.name or ""):gsub("^models/", "")
            local lower = shortName:lower()
            local supportsGen = false
            if type(m.supportedGenerationMethods) == "table" then
                for _, meth in ipairs(m.supportedGenerationMethods) do
                    if meth == "generateContent" then supportsGen = true break end
                end
            end
            if supportsGen and lower:find("gemini", 1, true)
                and not lower:find("tts", 1, true) and not lower:find("image", 1, true)
                and not lower:find("audio", 1, true) and not lower:find("embedding", 1, true)
                and not lower:find("veo", 1, true) and not lower:find("robotics", 1, true)
                and not lower:find("computer", 1, true) then
                if lower:find("flash", 1, true) then
                    table.insert(flashModels, shortName)
                else
                    table.insert(otherGemini, shortName)
                end
            end
        end

        table.sort(flashModels, function(a, b) return a > b end)
        table.sort(otherGemini, function(a, b) return a > b end)

        local finalList = {}
        for _, v in ipairs(flashModels) do table.insert(finalList, v) end
        for _, v in ipairs(otherGemini) do table.insert(finalList, v) end

        if #finalList == 0 then
            M.logIssue("ListModels", "No text generation models available")
            callback(nil, "No active text model found for this API Key.")
        else
            callback(finalList, nil)
        end
    end)
    if not okGet then
        M.logIssue("ListModels", tostring(errGet))
        callback(nil, "Models check failed: " .. tostring(errGet))
    end
end

-- Media Player & Clean WAV/PCM Engine (Smooth Edge Trimming)

function M.deleteOldAudioFile()
    if S.generatedAudioPath then
        pcall(function()
            local f = File(S.generatedAudioPath)
            if f.exists() then f.delete() end
        end)
        S.generatedAudioPath = nil
        S.currentDurationStr = ""
    end
end

function M.initMediaPlayer()
    if S.mediaPlayer ~= nil then
        if S.isPlaying then
            pcall(function() S.mediaPlayer.stop() end)
            S.isPlaying = false
        end
        pcall(function() S.mediaPlayer.release() end)
    end
    S.mediaPlayer = MediaPlayer()
    S.mediaPlayer.setOnCompletionListener(MediaPlayer.OnCompletionListener({
        onCompletion = function(mp)
            S.isPlaying = false
            M.speakOnly("Playback completed.")
            M.runOnUi(function()
                if S.ui and S.ui.playBtn then
                    S.ui.playBtn.setText(S.currentDurationStr ~= "" and ("PLAY (" .. S.currentDurationStr .. ")") or "PLAY")
                end
            end)
        end
    }))
end

function M.togglePlayPause(playBtn)
    if not S.generatedAudioPath or not File(S.generatedAudioPath).exists() then
        M.speakOnly("No audio loaded.")
        return
    end
    if S.mediaPlayer == nil then
        M.initMediaPlayer()
        S.mediaPlayer.setDataSource(S.generatedAudioPath)
        S.mediaPlayer.prepare()
    end
    if S.isPlaying then
        pcall(function() S.mediaPlayer.pause() end)
        S.isPlaying = false
        M.runOnUi(function()
            playBtn.setText(S.currentDurationStr ~= "" and ("PLAY (" .. S.currentDurationStr .. ")") or "PLAY")
        end)
    else
        local ok = pcall(function() S.mediaPlayer.start() end)
        if ok then
            S.isPlaying = true
            M.runOnUi(function()
                playBtn.setText(S.currentDurationStr ~= "" and ("PAUSE (" .. S.currentDurationStr .. ")") or "PAUSE")
            end)
        end
    end
end

function M.writeWavHeader(outStream, totalAudioLen)
    local sampleRate, channels, bitsPerSample = 24000, 1, 16
    local byteRate = sampleRate * channels * (bitsPerSample // 8)
    local blockAlign = channels * (bitsPerSample // 8)
    local totalSize = totalAudioLen + 36
    local function gb(v)
        v = math.floor(v)
        return { v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff }
    end
    local ts, sr, br, dl = gb(totalSize), gb(sampleRate), gb(byteRate), gb(totalAudioLen)
    local header = {
        0x52,0x49,0x46,0x46, ts[1],ts[2],ts[3],ts[4], 0x57,0x41,0x56,0x45,
        0x66,0x6d,0x74,0x20, 0x10,0x00,0x00,0x00, 0x01,0x00,
        channels & 0xff,(channels >> 8) & 0xff, sr[1],sr[2],sr[3],sr[4],
        br[1],br[2],br[3],br[4], blockAlign & 0xff,(blockAlign >> 8) & 0xff,
        bitsPerSample & 0xff,(bitsPerSample >> 8) & 0xff,
        0x64,0x61,0x74,0x61, dl[1],dl[2],dl[3],dl[4]
    }
    for i = 1, #header do outStream.write(header[i]) end
end

local function detectArrayBase(arr)
    local ok0, v0 = pcall(function() return arr[0] end)
    return (ok0 and v0 ~= nil) and 0 or 1
end

local function readUByte(arr, pos, base)
    local ok, val = pcall(function() return arr[pos + base] end)
    if not ok or val == nil then return 0 end
    return val < 0 and (val + 256) or val
end

function M.extractCleanPcmSegment(audioBytes)
    local totalLen = #audioBytes
    if totalLen <= 100 then return 0, 0 end
    local base = detectArrayBase(audioBytes)
    local pcmStart, exactDataEnd = 0, totalLen

    if readUByte(audioBytes, 0, base) == 82 and readUByte(audioBytes, 1, base) == 73
        and readUByte(audioBytes, 2, base) == 70 and readUByte(audioBytes, 3, base) == 70 then
        pcmStart = 44
        local limit = math.min(totalLen - 12, 1024)
        for i = 12, limit do
            if readUByte(audioBytes, i, base) == 100 and readUByte(audioBytes, i + 1, base) == 97
                and readUByte(audioBytes, i + 2, base) == 116 and readUByte(audioBytes, i + 3, base) == 97 then
                local declared = readUByte(audioBytes, i + 4, base)
                    + (readUByte(audioBytes, i + 5, base) * 256)
                    + (readUByte(audioBytes, i + 6, base) * 65536)
                    + (readUByte(audioBytes, i + 7, base) * 16777216)
                pcmStart = i + 8
                if declared > 0 and (pcmStart + declared) <= totalLen then
                    exactDataEnd = pcmStart + declared
                end
                break
            end
        end
    end

    if pcmStart % 2 ~= 0 then pcmStart = pcmStart + 1 end

    -- Trim tiny boundary clicks so transitions between merged parts sound seamless
    local avail = exactDataEnd - pcmStart
    if avail > 12000 then
        pcmStart = pcmStart + 640
        exactDataEnd = exactDataEnd - 1920
    elseif avail > 2400 then
        pcmStart = pcmStart + 200
        exactDataEnd = exactDataEnd - 400
    end

    local pcmLen = exactDataEnd - pcmStart
    if pcmLen % 2 ~= 0 then pcmLen = pcmLen - 1 end
    if pcmLen <= 0 then return 0, 0 end
    return pcmStart, pcmLen
end

-- PART 2 OF 3: Resume System, Create Script Engine & Audio Engines

-- Resume & Checkpoint Helpers

function M.clearDirFiles(dir)
    pcall(function()
        if dir and dir.exists() then
            local files = dir.listFiles()
            if files then
                for i = 0, #files - 1 do
                    pcall(function() files[i].delete() end)
                end
            end
        end
    end)
end

function M.clearSingleResume()
    M.clearDirFiles(M.singleResumeDir)
    local ed = M.prefs.edit()
    ed.remove("s_job_tag")
    ed.remove("s_full_text")
    ed.remove("s_total_parts")
    ed.commit()
end

function M.clearBroadcastResume()
    M.clearDirFiles(M.bcResumeDir)
    local ed = M.prefs.edit()
    ed.remove("bc_job_tag")
    ed.remove("bc_script")
    ed.remove("bc_total_parts")
    ed.commit()
end

function M.clearAllResumeData()
    M.clearSingleResume()
    M.clearBroadcastResume()
end

function M.getSinglePartFile(idx)
    if not M.singleResumeDir.exists() then M.singleResumeDir.mkdirs() end
    return File(M.singleResumeDir, "s_part_" .. tostring(idx) .. ".pcm")
end

function M.getBcPartFile(idx)
    if not M.bcResumeDir.exists() then M.bcResumeDir.mkdirs() end
    return File(M.bcResumeDir, "bc_part_" .. tostring(idx) .. ".pcm")
end

function M.makeSingleJobTag(txt)
    return table.concat({
        "S3", tostring(M.cfg.singleVoice), tostring(M.cfg.singleStyle),
        tostring(M.cfg.lang), tostring(M.cfg.model),
        tostring(#txt), M.hashText(txt)
    }, "|")
end

function M.makeBcJobTag(txt)
    return table.concat({
        "BC3", tostring(M.cfg.maleVoice), tostring(M.cfg.femaleVoice),
        tostring(M.cfg.lang), tostring(M.cfg.bcMood), tostring(M.cfg.model),
        tostring(#txt), M.hashText(txt)
    }, "|")
end

function M.getSingleResumeStatus(txt)
    local clean = M.trim(txt)
    if clean == "" then return 0, 0, nil end
    if M.prefs.getString("s_job_tag", "") ~= M.makeSingleJobTag(clean) then
        return 0, 0, nil
    end
    local savedText = M.prefs.getString("s_full_text", "")
    local totalParts = M.prefs.getInt("s_total_parts", 0)
    if savedText == "" or totalParts <= 0 then return 0, 0, nil end

    local done = 0
    for i = 1, totalParts do
        local f = M.getSinglePartFile(i)
        if f.exists() and f.length() > 100 then done = done + 1 else break end
    end
    return done, totalParts, savedText
end

function M.getBcResumeStatus(txt)
    local clean = M.trim(txt)
    if clean == "" then return 0, 0, nil end
    if M.prefs.getString("bc_job_tag", "") ~= M.makeBcJobTag(clean) then
        return 0, 0, nil
    end
    local savedScript = M.prefs.getString("bc_script", "")
    local totalParts = M.prefs.getInt("bc_total_parts", 0)
    if savedScript == "" or totalParts <= 0 then return 0, 0, nil end

    local done = 0
    for i = 1, totalParts do
        local f = M.getBcPartFile(i)
        if f.exists() and f.length() > 100 then done = done + 1 else break end
    end
    return done, totalParts, savedScript
end

function M.refreshActionButtons()
    M.runOnUi(function()
        if not S.ui then return end

        -- Refresh Create Script Button
        if S.ui.createScriptBtn then
            if S.isWritingScript then
                S.ui.createScriptBtn.setEnabled(false)
                S.ui.createScriptBtn.setText("WRITING SCRIPT (" .. tostring(S.percent) .. "%)...")
                M.setBtnColor(S.ui.createScriptBtn, "#9E9E9E")
            elseif S.isGenerating then
                S.ui.createScriptBtn.setEnabled(false)
                S.ui.createScriptBtn.setText("CREATE SCRIPT")
                M.setBtnColor(S.ui.createScriptBtn, "#9E9E9E")
            else
                S.ui.createScriptBtn.setEnabled(true)
                S.ui.createScriptBtn.setText("CREATE SCRIPT")
                M.setBtnColor(S.ui.createScriptBtn, "#6A1B9A")
            end
        end

        -- Refresh Generate Audio Button
        if S.ui.generateBtn then
            if S.isGenerating then
                S.ui.generateBtn.setEnabled(false)
                S.ui.generateBtn.setText("GENERATING AUDIO (" .. tostring(S.percent) .. "%)...")
                M.setBtnColor(S.ui.generateBtn, "#9E9E9E")
                return
            elseif S.isWritingScript then
                S.ui.generateBtn.setEnabled(false)
                S.ui.generateBtn.setText("GENERATE AUDIO")
                M.setBtnColor(S.ui.generateBtn, "#9E9E9E")
                return
            end

            local txt = M.cfg.userText
            if S.ui.textInput then
                pcall(function() txt = S.ui.textInput.getText().toString() end)
            end

            local doneCount, totalParts = 0, 0
            if M.cfg.mode == M.MODE_LIST[1] then
                doneCount, totalParts = M.getSingleResumeStatus(txt)
            else
                doneCount, totalParts = M.getBcResumeStatus(txt)
            end

            S.ui.generateBtn.setEnabled(true)
            if doneCount > 0 and doneCount < totalParts then
                S.ui.generateBtn.setText("RESUME AUDIO (PART " .. tostring(doneCount + 1) .. "/" .. tostring(totalParts) .. ")")
                M.setBtnColor(S.ui.generateBtn, "#FF8F00")
            elseif doneCount > 0 and doneCount == totalParts then
                S.ui.generateBtn.setText("MERGE SAVED (" .. tostring(totalParts) .. "/" .. tostring(totalParts) .. ")")
                M.setBtnColor(S.ui.generateBtn, "#43A047")
            else
                S.ui.generateBtn.setText("GENERATE AUDIO")
                M.setBtnColor(S.ui.generateBtn, "#2196F3")
            end
        end
    end)
end

-- Shared WAV Merger & UI Completion

function M.mergePcmFilesToWav(partFilesList, pauseMs, filePrefix)
    local totalDurationSec = 0
    local okMerge, errMerge = pcall(function()
        M.deleteOldAudioFile()
        local finalPath = M.baseStorageDir.getPath() .. "/" .. filePrefix .. "_" .. os.time() .. ".wav"
        local pauseBytes = math.floor((24000 * 2 * (pauseMs or 350)) / 1000)
        if pauseBytes % 2 ~= 0 then pauseBytes = pauseBytes + 1 end

        local validItems = {}
        local totalPcmBytes = 0
        for _, f in ipairs(partFilesList) do
            if f.exists() and f.length() > 100 then
                local len = math.floor(f.length())
                if len % 2 ~= 0 then len = len - 1 end
                table.insert(validItems, { file = f, length = len })
                totalPcmBytes = totalPcmBytes + len
            end
        end

        if #validItems > 1 and pauseBytes > 0 then
            totalPcmBytes = totalPcmBytes + ((#validItems - 1) * pauseBytes)
        end
        if totalPcmBytes <= 0 then error("Audio data is empty") end

        totalDurationSec = totalPcmBytes / 48000.0
        local fos = FileOutputStream(File(finalPath))
        M.writeWavHeader(fos, totalPcmBytes)

        local copyBuf = byte[8192]
        local silenceBuf = (pauseBytes > 0) and byte[pauseBytes] or nil

        for idx, item in ipairs(validItems) do
            local fis = FileInputStream(item.file)
            local rem = item.length
            while rem > 0 do
                local r = fis.read(copyBuf, 0, math.min(8192, rem))
                if not r or r <= 0 then break end
                fos.write(copyBuf, 0, r)
                rem = rem - r
            end
            fis.close()
            if idx < #validItems and silenceBuf then
                fos.write(silenceBuf, 0, pauseBytes)
            end
        end

        fos.flush()
        fos.close()
        S.generatedAudioPath = finalPath
    end)

    if not okMerge or not S.generatedAudioPath then
        M.logIssue("MergeWAV", tostring(errMerge))
        return false, tostring(errMerge)
    end
    return true, totalDurationSec
end

function M.onAudioReadyUI(totalDurationSec, labelPrefix)
    local shortDur, spokenDur = M.formatDurationText(totalDurationSec)
    S.currentDurationStr = shortDur
    S.isGenerating = false
    M.updateProgress(100, labelPrefix .. " Ready (" .. shortDur .. ")", true)

    M.runOnUi(function()
        if S.ui then
            pcall(function()
                if S.ui.resultLayout then S.ui.resultLayout.setVisibility(View.VISIBLE) end
                if S.ui.durationLabel then
                    S.ui.durationLabel.setText(labelPrefix .. " Length: " .. S.currentDurationStr)
                end
                if S.ui.playBtn then
                    S.ui.playBtn.setText("PLAY (" .. S.currentDurationStr .. ")")
                    S.ui.playBtn.setEnabled(true)
                end
            end)
        end
    end)
    M.refreshActionButtons()
end

-- Text & Script Parsers

function M.extractSpeakerAndBody(rawLine)
    local l = M.trim(rawLine):gsub("^[%*%-%•%d%.%)%s]+", ""):gsub("%*", ""):gsub("%b[]", "")
    l = M.trim(l)
    if l == "" then return nil, "" end

    local spk, body = nil, l
    if l:match("^[Ss]peaker%s*1%s*[:%-–—]") then
        spk, body = "Speaker1", M.trim(l:gsub("^[Ss]peaker%s*1%s*[:%-–—]+", ""))
    elseif l:match("^[Ss]peaker%s*2%s*[:%-–—]") then
        spk, body = "Speaker2", M.trim(l:gsub("^[Ss]peaker%s*2%s*[:%-–—]+", ""))
    elseif l:match("^[Hh]ost%s*1%s*[:%-–—]") then
        spk, body = "Speaker1", M.trim(l:gsub("^[Hh]ost%s*1%s*[:%-–—]+", ""))
    elseif l:match("^[Hh]ost%s*2%s*[:%-–—]") then
        spk, body = "Speaker2", M.trim(l:gsub("^[Hh]ost%s*2%s*[:%-–—]+", ""))
    elseif l:match("^[Mm]ale%s*[:%-–—]") then
        spk, body = "Speaker1", M.trim(l:gsub("^[Mm]ale%s*[:%-–—]+", ""))
    elseif l:match("^[Ff]emale%s*[:%-–—]") then
        spk, body = "Speaker2", M.trim(l:gsub("^[Ff]emale%s*[:%-–—]+", ""))
    end

    body = M.trim(body:gsub("[Ss]peaker%s*[12]%s*:?", ""):gsub("[Hh]ost%s*[12]%s*:?", ""))
    return spk, body
end

function M.normalizeBcScript(rawText)
    local text = tostring(rawText or ""):gsub("\r\n", "\n")
    local sec = text:match("%-%-%-%s*Script%s*%-%-%-\n?(.*)")
    if sec then text = sec end

    local lines, count = {}, 0
    for line in text:gmatch("[^\n]+") do
        local spk, body = M.extractSpeakerAndBody(line)
        if spk and body ~= "" then
            count = count + 1
            table.insert(lines, spk .. ": " .. body)
        end
    end
    if count >= 2 then return true, table.concat(lines, "\n") end
    return false, nil
end

function M.parseBcTurnsIntoChunks(scriptText)
    local allTurns, lastSpk = {}, "Speaker1"
    for line in scriptText:gmatch("[^\n]+") do
        local spk, body = M.extractSpeakerAndBody(line)
        if body ~= "" then
            spk = spk or lastSpk
            lastSpk = spk
            table.insert(allTurns, { speaker = spk, text = body })
        end
    end

    local chunks, cur, chars = {}, {}, 0
    for _, t in ipairs(allTurns) do
        table.insert(cur, t)
        chars = chars + #t.text
        if #cur >= 18 or chars >= 2200 then
            table.insert(chunks, cur)
            cur, chars = {}, 0
        end
    end
    if #cur > 0 then table.insert(chunks, cur) end
    return chunks
end

function M.normalizeSingleChunk(chunk)
    chunk = chunk:gsub("!+", "."):gsub("%?+", "?"):gsub("؟+", "؟")
    chunk = chunk:gsub("%.%.%.+", "."):gsub("—", ", "):gsub("%-%-+", ", ")
    chunk = chunk:gsub("[\"\'“”‘’«»%*]", ""):gsub("\n+", " "):gsub("%s+", " ")
    chunk = M.trim(chunk)
    local l1, l2, l3 = string.sub(chunk, -1), string.sub(chunk, -2), string.sub(chunk, -3)
    if l1 ~= "." and l1 ~= "?" and l2 ~= "۔" and l2 ~= "؟" and l3 ~= "।" then
        chunk = chunk .. "."
    end
    return chunk
end

function M.findCleanBoundary(str, targetBytePos)
    local len = #str
    if targetBytePos >= len or targetBytePos <= 1 then return len end
    local minB = math.max(1, targetBytePos - 450)
    local maxB = math.min(len, targetBytePos + 450)

    local bestPos, bestDist = nil, 999999
    for i = minB, maxB do
        local c = string.sub(str, i, i)
        local isEnd, endIdx = false, i
        if c == "." or c == "?" or c == "!" or c == "\n" then
            isEnd = true
        else
            local b1, b2, b3 = string.byte(str, i, i + 2)
            if (b1 == 219 and b2 == 148) or (b1 == 216 and b2 == 159) then
                isEnd, endIdx = true, i + 1
            elseif b1 == 224 and b2 == 165 and b3 == 164 then
                isEnd, endIdx = true, i + 2
            end
        end
        if isEnd then
            local dist = math.abs(endIdx - targetBytePos)
            if dist < bestDist then bestDist, bestPos = dist, endIdx end
        end
    end
    if bestPos then return bestPos end

    local sMin, sMax = math.max(1, targetBytePos - 700), math.min(len, targetBytePos + 700)
    for i = sMin, sMax do
        local c = string.sub(str, i, i)
        if c == " " or c == "\t" or c == "\n" then
            local dist = math.abs(i - targetBytePos)
            if dist < bestDist then bestDist, bestPos = dist, i end
        end
    end
    if bestPos then return bestPos end

    local pos = targetBytePos
    while pos < len do
        local b = string.byte(str, pos + 1)
        if not b or b < 128 or b >= 192 then break end
        pos = pos + 1
    end
    return pos
end

function M.splitSingleTextIntoChunks(text)
    local t = M.trim(tostring(text or ""):gsub("\r\n", "\n"))
    if t == "" then return {} end

    local totalChars = M.utf8CharCount(t)
    if totalChars <= 3100 then
        return { M.normalizeSingleChunk(t) }
    end

    local numParts = math.max(1, math.ceil(totalChars / M.TARGET_CHARS_PER_PART))
    local rawChunks, remaining, partsLeft = {}, t, numParts

    while partsLeft > 1 and #remaining > 0 do
        local cut = M.findCleanBoundary(remaining, math.floor(#remaining / partsLeft))
        local c = M.trim(string.sub(remaining, 1, cut))
        if c ~= "" then table.insert(rawChunks, c) end
        remaining = M.trim(string.sub(remaining, cut + 1))
        partsLeft = partsLeft - 1
    end
    if #remaining > 0 then table.insert(rawChunks, remaining) end

    if #rawChunks > 1 and M.utf8CharCount(rawChunks[#rawChunks]) < 400 then
        rawChunks[#rawChunks - 1] = rawChunks[#rawChunks - 1] .. " " .. rawChunks[#rawChunks]
        table.remove(rawChunks, #rawChunks)
    end

    local finalChunks = {}
    for _, c in ipairs(rawChunks) do
        table.insert(finalChunks, M.normalizeSingleChunk(c))
    end
    return finalChunks
end

-- STEP A: DEDICATED "CREATE SCRIPT" ENGINE (Writes Script Only)

function M.startCreateScriptJob(inputText)
    S.isWritingScript = true
    M.refreshActionButtons()

    local isSingle = (M.cfg.mode == M.MODE_LIST[1])
    local lang = M.cfg.lang
    local mins = M.getEffectiveMinutes()
    local targetWords = mins * 145
    local targetTurns = math.max(8, mins * 7)
    local apikey = M.cfg.apiKey

    local headers = HashMap()
    headers.put("Content-Type", "application/json")

    local function failScript(msg)
        S.isWritingScript = false
        M.logIssue("CreateScript", msg)
        M.updateProgress(0, msg, true)
        M.refreshActionButtons()
    end

    M.updateProgress(10, "Finding active script model...", true)

    M.discoverWorkingScriptModels(apikey, function(models, discErr)
        if discErr or not models or #models == 0 then
            failScript(discErr or "No active script model found.")
            return
        end

        local prompt
        if isSingle then
            prompt = table.concat({
                "Write a complete, engaging single-narrator script or story based on the user's input.",
                "If the user provided an existing script with instructions to improve it, rewrite and improve it accordingly.",
                "Language: " .. lang .. ".",
                "Style / Mood: " .. M.cfg.singleStyle .. ".",
                "Target Length: " .. tostring(mins) .. " minute(s) (approx " .. tostring(targetWords) .. " words).",
                "STRICT RULES:",
                "1. Do NOT use markdown stars (*), headings (#), brackets [], or emojis.",
                "2. Output ONLY clean spoken narration text ready for voiceover.",
                "User Input / Topic:",
                inputText
            }, "\n")
        else
            prompt = table.concat({
                "Write a natural, realistic 2-host podcast/broadcast conversation between Speaker1 (Male) and Speaker2 (Female).",
                "If the user provided an existing script with instructions to improve it, rewrite and improve it accordingly.",
                "Language: " .. lang .. ".",
                "Mood / Style: " .. M.cfg.bcMood .. ".",
                "Target Length: " .. tostring(mins) .. " minute(s) (approx " .. tostring(targetTurns) .. " dialogue turns, ~" .. tostring(targetWords) .. " words).",
                "STRICT RULES:",
                "1. Every single line MUST start with either 'Speaker1: ' or 'Speaker2: '.",
                "2. NEVER write 'Speaker1', 'Speaker2', 'Speaker 1', 'Speaker 2', 'Host 1', or 'Host 2' inside the spoken dialogue.",
                "3. Do NOT use brackets [], parentheses (), asterisks *, emojis, or stage directions like [laughs]. Express humor, jokes, or emotion naturally through the spoken words.",
                "4. Output ONLY the clean dialogue lines with no intro/outro titles.",
                "User Input / Topic:",
                inputText
            }, "\n")
        end

        local function tryModel(idx)
            local curM = models[idx]
            if not curM then
                failScript("All script models failed. Please try again.")
                return
            end

            M.updateProgress(35, "Writing " .. tostring(mins) .. " min script (" .. curM .. ")...", false)
            local url = "https://generativelanguage.googleapis.com/v1beta/models/" .. curM .. ":generateContent?key=" .. apikey
            local payload = { contents = { { role = "user", parts = { { text = prompt } } } } }

            local okS, errS = M.httpPost(url, cjson.encode(payload), headers, function(code, content)
                if (code == 404 or code == 429 or code == 503 or code == 400 or code == -1) and idx < #models then
                    M.updateProgress(45, "Switching script model (code " .. tostring(code) .. ")...", false)
                    M.delay(800, function() tryModel(idx + 1) end)
                    return
                end

                if code == 200 then
                    local okJ, data = pcall(cjson.decode, content)
                    local outText = nil
                    if okJ and data and data.candidates and data.candidates[1]
                        and data.candidates[1].content and data.candidates[1].content.parts
                        and data.candidates[1].content.parts[1] then
                        outText = data.candidates[1].content.parts[1].text
                    end

                    if not outText or M.trim(outText) == "" then
                        failScript("Script returned empty. Please try again.")
                        return
                    end

                    local finalText
                    if isSingle then
                        finalText = M.trim(outText:gsub("%*", ""):gsub("%b[]", ""):gsub("#+", ""))
                    else
                        local _, cleanFmt = M.normalizeBcScript(outText)
                        finalText = cleanFmt or M.trim(outText:gsub("%*", ""):gsub("%b[]", ""))
                    end

                    M.cfg.userText = finalText
                    M.saveDraftText(finalText)
                    M.clearAllResumeData()

                    M.runOnUi(function()
                        if S.ui and S.ui.textInput then
                            M.isUiInitializing = true
                            pcall(function()
                                S.ui.textInput.setText(finalText)
                                if S.ui.charCounter then
                                    S.ui.charCounter.setText(tostring(S.ui.textInput.getText().length()) .. " / " .. M.MAX_CHAR_LIMIT)
                                end
                            end)
                            M.isUiInitializing = false
                        end
                    end)

                    S.isWritingScript = false
                    M.updateProgress(100, "Script Ready in EditBox! Review it and tap GENERATE AUDIO.", true)
                    M.refreshActionButtons()
                else
                    failScript("Script Error (" .. tostring(code) .. "): " .. tostring(M.extractApiError(content) or "Server error"))
                end
            end)

            if not okS then failScript("Script request failed: " .. tostring(errS)) end
        end

        tryModel(1)
    end)
end

-- STEP B1: SINGLE SPEAKER AUDIO ENGINE (Enhanced Voice Continuity Lock)

function M.startSingleSpeakerAudioJob(inputText)
    S.isGenerating = true
    M.refreshActionButtons()

    local activeJobText = inputText
    local voice = M.cfg.singleVoice
    local style = M.cfg.singleStyle
    local lang = M.cfg.lang
    local apikey = M.cfg.apiKey
    local primaryModel = M.cfg.model

    local headers = HashMap()
    headers.put("Content-Type", "application/json")

    local ttsQueue = { primaryModel }
    for _, m in ipairs(M.MODEL_LIST) do
        if m ~= primaryModel then table.insert(ttsQueue, m) end
    end

    local function pauseOnError(msg)
        S.isGenerating = false
        M.logIssue("SingleAudio", msg)
        M.updateProgress(S.percent, msg, true)
        M.refreshActionButtons()
    end

    local function runTts(textToSpeak)
        local chunks = M.splitSingleTextIntoChunks(textToSpeak)
        local totalParts = #chunks
        if totalParts == 0 then
            pauseOnError("Text is empty. Cannot generate audio.")
            return
        end

        local ed = M.prefs.edit()
        ed.putString("s_job_tag", M.makeSingleJobTag(activeJobText))
        ed.putString("s_full_text", textToSpeak)
        ed.putInt("s_total_parts", totalParts)
        ed.commit()

        local startIdx = 1
        for i = 1, totalParts do
            local pf = M.getSinglePartFile(i)
            if pf.exists() and pf.length() > 100 then startIdx = i + 1 else break end
        end

        local function finishMerge()
            M.updateProgress(95, "Merging all " .. tostring(totalParts) .. " parts...", false)
            local files = {}
            for i = 1, totalParts do table.insert(files, M.getSinglePartFile(i)) end
            local okM, durOrErr = M.mergePcmFilesToWav(files, M.PAUSE_DURATION_MS, "gemini_single")
            if not okM then
                pauseOnError("Merge error: " .. tostring(durOrErr))
                return
            end
            M.onAudioReadyUI(durOrErr, "Audio")
        end

        if startIdx > totalParts then
            M.updateProgress(95, "All parts saved. Merging audio...", true)
            finishMerge()
            return
        end

        local baseStyle = M.SINGLE_STYLE_TEXT[style] or M.SINGLE_STYLE_TEXT["Default / Normal"]

        local function processChunk(partIdx, ttsIdx, modeIdx)
            local curModel = ttsQueue[ttsIdx]
            if not curModel then
                pauseOnError("Paused at Part " .. tostring(partIdx) .. "/" .. tostring(totalParts) .. ". Tap RESUME AUDIO to continue.")
                return
            end

            local doneBefore = partIdx - 1
            local remParts = totalParts - doneBefore
            local pct = math.max(5, math.floor((doneBefore / totalParts) * 90))
            M.updateProgress(pct, "Parts: " .. tostring(doneBefore) .. "/" .. tostring(totalParts) .. " done | " .. tostring(remParts) .. " remaining", partIdx == startIdx and modeIdx == 1)

            -- Tight continuity lock across all parts so voice pitch & tone never shift
            local continuityNote = (partIdx > 1)
                and "continuing seamlessly from the previous part with the exact same speaker voice (" .. voice .. "), identical vocal pitch, volume, and speaking speed"
                or "consistent studio speaker (" .. voice .. ") maintaining identical vocal pitch, volume, and speaking speed throughout"

            local stylePrompt = baseStyle .. ", language: " .. lang .. ", " .. continuityNote

            local url = "https://generativelanguage.googleapis.com/v1beta/models/" .. curModel .. ":generateContent?key=" .. apikey
            local partObj = { text = chunks[partIdx] }
            if modeIdx == 3 then
                partObj.speechMetadata = { style = stylePrompt }
            else
                partObj.speech_metadata = { style = stylePrompt }
            end

            local genCfg = {
                responseModalities = { "AUDIO" },
                speechConfig = { voiceConfig = { voice = voice } }
            }
            if modeIdx == 1 then
                genCfg.temperature = 0.0
                genCfg.seed = 424242
            elseif modeIdx == 2 then
                genCfg.temperature = 0.05
                genCfg.seed = 424242
            end

            local payload = {
                contents = { { role = "user", parts = { partObj } } },
                generationConfig = genCfg
            }

            local okP, errP = M.httpPost(url, cjson.encode(payload), headers, function(code, content)
                if code == 400 and modeIdx < 4 then
                    M.delay(400, function() processChunk(partIdx, ttsIdx, modeIdx + 1) end)
                    return
                end
                if (code == 404 or code == 429 or code == 503 or code == -1) and ttsIdx < #ttsQueue then
                    M.delay(1500, function() processChunk(partIdx, ttsIdx + 1, 1) end)
                    return
                end

                if code == 200 then
                    local okDec, data = pcall(cjson.decode, content)
                    local byteArrays = {}
                    if okDec and data and data.candidates and #data.candidates > 0 then
                        local cand = data.candidates[1]
                        if cand.content and cand.content.parts then
                            for i = 1, #cand.content.parts do
                                local inl = cand.content.parts[i].inlineData or cand.content.parts[i].inline_data
                                if inl and inl.data then
                                    local okB, bArr = pcall(function() return Base64.decode(inl.data, Base64.DEFAULT) end)
                                    if okB and bArr and #bArr > 0 then table.insert(byteArrays, bArr) end
                                end
                            end
                        end
                    end

                    if #byteArrays == 0 then
                        pauseOnError("Part " .. tostring(partIdx) .. " returned empty audio. Tap RESUME AUDIO.")
                        return
                    end

                    local pf = M.getSinglePartFile(partIdx)
                    local okSave, errSave = pcall(function()
                        local fos = FileOutputStream(pf)
                        for i = 1, #byteArrays do
                            local off, len = M.extractCleanPcmSegment(byteArrays[i])
                            if len > 0 then fos.write(byteArrays[i], off, len) end
                        end
                        fos.flush()
                        fos.close()
                    end)

                    if not okSave or not pf.exists() or pf.length() <= 100 then
                        pcall(function() if pf.exists() then pf.delete() end end)
                        pauseOnError("Part " .. tostring(partIdx) .. " save error: " .. tostring(errSave))
                        return
                    end

                    local remAfter = totalParts - partIdx
                    local donePct = math.max(5, math.floor((partIdx / totalParts) * 90))
                    M.updateProgress(donePct, "Parts: " .. tostring(partIdx) .. "/" .. tostring(totalParts) .. " done | " .. tostring(remAfter) .. " remaining", false)

                    if partIdx < totalParts then
                        M.delay(1500, function() processChunk(partIdx + 1, 1, 1) end)
                    else
                        finishMerge()
                    end
                else
                    pauseOnError("Part " .. tostring(partIdx) .. " error (" .. tostring(code) .. "): " .. tostring(M.extractApiError(content) or "Server error"))
                end
            end)
            if not okP then pauseOnError("Request failed: " .. tostring(errP)) end
        end

        processChunk(startIdx, 1, 1)
    end

    local _, totalParts, savedText = M.getSingleResumeStatus(inputText)
    if savedText and savedText ~= "" and totalParts > 0 then
        runTts(savedText)
        return
    end

    M.clearSingleResume()
    local bodyOnly = inputText:match("%-%-%-%s*Story%s*%-%-%-\n?(.*)") or inputText
    runTts(M.trim(bodyOnly))
end

-- STEP B2: 2-HOST BROADCAST AUDIO ENGINE (Dual Voice Lock + 5% Steps)

function M.startBroadcastAudioJob(inputText)
    S.isGenerating = true
    M.refreshActionButtons()

    local activeJobText = inputText
    local maleVoice = M.cfg.maleVoice
    local femaleVoice = M.cfg.femaleVoice
    local lang = M.cfg.lang
    local mood = M.cfg.bcMood
    local apikey = M.cfg.apiKey
    local primaryModel = M.cfg.model

    local headers = HashMap()
    headers.put("Content-Type", "application/json")

    local ttsQueue = { primaryModel }
    for _, m in ipairs(M.MODEL_LIST) do
        if m ~= primaryModel then table.insert(ttsQueue, m) end
    end

    local function pauseOnError(msg)
        S.isGenerating = false
        M.logIssue("BroadcastAudio", msg)
        M.updateProgress(S.percent, msg, true)
        M.refreshActionButtons()
    end

    local function runBcTts(cleanScript)
        local turnChunks = M.parseBcTurnsIntoChunks(cleanScript)
        local totalParts = #turnChunks
        if totalParts == 0 then
            pauseOnError("Script format not found. First tap CREATE SCRIPT or use Speaker1:/Speaker2: lines.")
            return
        end

        local ed = M.prefs.edit()
        ed.putString("bc_job_tag", M.makeBcJobTag(activeJobText))
        ed.putString("bc_script", cleanScript)
        ed.putInt("bc_total_parts", totalParts)
        ed.commit()

        local startIdx = 1
        for i = 1, totalParts do
            local pf = M.getBcPartFile(i)
            if pf.exists() and pf.length() > 100 then startIdx = i + 1 else break end
        end

        local function finishMerge()
            M.updateProgress(95, "Merging all " .. tostring(totalParts) .. " broadcast parts...", false)
            local files = {}
            for i = 1, totalParts do table.insert(files, M.getBcPartFile(i)) end
            local okM, durOrErr = M.mergePcmFilesToWav(files, 300, "gemini_broadcast")
            if not okM then
                pauseOnError("Merge error: " .. tostring(durOrErr))
                return
            end
            M.onAudioReadyUI(durOrErr, "Broadcast")
        end

        if startIdx > totalParts then
            M.updateProgress(95, "All parts saved. Merging broadcast...", true)
            finishMerge()
            return
        end

        local maleStyle = "consistent male broadcast host (" .. maleVoice .. ") speaking in " .. lang
            .. ", mood: " .. mood .. ", strictly locked to the exact same male voice identity, vocal pitch, and steady tempo throughout"
        local femaleStyle = "consistent female broadcast host (" .. femaleVoice .. ") speaking in " .. lang
            .. ", mood: " .. mood .. ", strictly locked to the exact same female voice identity, vocal pitch, and steady tempo throughout"

        local function processBcPart(partIdx, ttsIdx, modeIdx)
            local curModel = ttsQueue[ttsIdx]
            if not curModel then
                pauseOnError("Paused at Part " .. tostring(partIdx) .. "/" .. tostring(totalParts) .. ". Tap RESUME AUDIO to continue.")
                return
            end

            local doneBefore = partIdx - 1
            local remParts = totalParts - doneBefore
            local pct = math.max(5, math.floor((doneBefore / totalParts) * 90))
            M.updateProgress(pct, "Parts: " .. tostring(doneBefore) .. "/" .. tostring(totalParts) .. " done | " .. tostring(remParts) .. " remaining", partIdx == startIdx and modeIdx == 1)

            local url = "https://generativelanguage.googleapis.com/v1beta/models/" .. curModel .. ":generateContent?key=" .. apikey
            local partsArray = {}
            for _, turn in ipairs(turnChunks[partIdx]) do
                local st = (turn.speaker == "Speaker1") and maleStyle or femaleStyle
                if modeIdx <= 2 then
                    table.insert(partsArray, { text = turn.text, speech_metadata = { speaker = turn.speaker, style = st } })
                elseif modeIdx == 3 then
                    table.insert(partsArray, { text = turn.text, speech_metadata = { speaker = turn.speaker } })
                else
                    table.insert(partsArray, { text = turn.text, speechMetadata = { speaker = turn.speaker } })
                end
            end

            local spkCfgs = (modeIdx <= 3) and {
                { speaker = "Speaker1", voiceConfig = { voice = maleVoice } },
                { speaker = "Speaker2", voiceConfig = { voice = femaleVoice } }
            } or {
                { speaker = "Speaker1", voiceConfig = { prebuiltVoiceConfig = { voiceName = maleVoice } } },
                { speaker = "Speaker2", voiceConfig = { prebuiltVoiceConfig = { voiceName = femaleVoice } } }
            }

            local genCfg = {
                responseModalities = { "AUDIO" },
                speechConfig = { multiSpeakerVoiceConfig = { speakerVoiceConfigs = spkCfgs } }
            }
            if modeIdx == 1 then
                genCfg.temperature = 0.0
                genCfg.seed = 424242
            elseif modeIdx == 2 then
                genCfg.temperature = 0.05
                genCfg.seed = 424242
            end

            local payload = {
                contents = { { role = "user", parts = partsArray } },
                generationConfig = genCfg
            }

            local okP, errP = M.httpPost(url, cjson.encode(payload), headers, function(code, content)
                if code == 400 and modeIdx < 4 then
                    M.delay(400, function() processBcPart(partIdx, ttsIdx, modeIdx + 1) end)
                    return
                end
                if (code == 404 or code == 429 or code == 503 or code == -1) and ttsIdx < #ttsQueue then
                    M.delay(1500, function() processBcPart(partIdx, ttsIdx + 1, 1) end)
                    return
                end

                if code == 200 then
                    local okDec, data = pcall(cjson.decode, content)
                    local byteArrays = {}
                    if okDec and data and data.candidates and #data.candidates > 0 then
                        local cand = data.candidates[1]
                        if cand.content and cand.content.parts then
                            for i = 1, #cand.content.parts do
                                local inl = cand.content.parts[i].inlineData or cand.content.parts[i].inline_data
                                if inl and inl.data then
                                    local okB, bArr = pcall(function() return Base64.decode(inl.data, Base64.DEFAULT) end)
                                    if okB and bArr and #bArr > 0 then table.insert(byteArrays, bArr) end
                                end
                            end
                        end
                    end

                    if #byteArrays == 0 then
                        pauseOnError("Part " .. tostring(partIdx) .. " returned empty audio. Tap RESUME AUDIO.")
                        return
                    end

                    local pf = M.getBcPartFile(partIdx)
                    local okSave, errSave = pcall(function()
                        local fos = FileOutputStream(pf)
                        for i = 1, #byteArrays do
                            local off, len = M.extractCleanPcmSegment(byteArrays[i])
                            if len > 0 then fos.write(byteArrays[i], off, len) end
                        end
                        fos.flush()
                        fos.close()
                    end)

                    if not okSave or not pf.exists() or pf.length() <= 100 then
                        pcall(function() if pf.exists() then pf.delete() end end)
                        pauseOnError("Part " .. tostring(partIdx) .. " save error: " .. tostring(errSave))
                        return
                    end

                    local remAfter = totalParts - partIdx
                    local donePct = math.max(5, math.floor((partIdx / totalParts) * 90))
                    M.updateProgress(donePct, "Parts: " .. tostring(partIdx) .. "/" .. tostring(totalParts) .. " done | " .. tostring(remAfter) .. " remaining", false)

                    if partIdx < totalParts then
                        M.delay(1500, function() processBcPart(partIdx + 1, 1, 1) end)
                    else
                        finishMerge()
                    end
                else
                    pauseOnError("Part " .. tostring(partIdx) .. " error (" .. tostring(code) .. "): " .. tostring(M.extractApiError(content) or "Server error"))
                end
            end)
            if not okP then pauseOnError("Request failed: " .. tostring(errP)) end
        end

        processBcPart(startIdx, 1, 1)
    end

    local _, totalParts, savedScript = M.getBcResumeStatus(inputText)
    if savedScript and savedScript ~= "" and totalParts > 0 then
        runBcTts(savedScript)
        return
    end

    M.clearBroadcastResume()
    local isValid, normScript = M.normalizeBcScript(inputText)
    if not isValid or not normScript then
        pauseOnError("Broadcast script not detected. Tap CREATE SCRIPT first to generate Male/Female dialogue.")
        return
    end

    runBcTts(normScript)
end

-- PART 3 OF 3: Share (Auto-Close Fix), Download Name Dialog, Settings & Main UI

-- Stream Copy & File Name Sanitizer Helpers

local function copyStream(input, output)
    local buffer = byte[8192]
    while true do
        local len = input.read(buffer)
        if len == nil or len == -1 then break end
        output.write(buffer, 0, len)
    end
end

local function makeSafeFileName(rawName)
    local s = M.trim(rawName or "")
    s = s:gsub("%.wav$", ""):gsub("%.WAV$", "")
    s = s:gsub("[^%w%-%_ ]", ""):gsub("%s+", "_")
    s = s:gsub("_+", "_"):gsub("^_", ""):gsub("_$", "")
    if #s > 45 then s = string.sub(s, 1, 45) end
    if s == "" then s = "Gemini_Audio_" .. os.date("%H%M%S") end
    return s
end

local function getDefaultDownloadName()
    local isSingle = (M.cfg.mode == M.MODE_LIST[1])
    local prefix = isSingle and "Single_" or "Broadcast_"
    local moodOrStyle = isSingle and M.cfg.singleStyle or M.cfg.bcMood
    local cleanTag = tostring(moodOrStyle or "Audio"):gsub("[^%w ]", ""):gsub("%s+", "_")
    if #cleanTag > 22 then cleanTag = string.sub(cleanTag, 1, 22) end
    cleanTag = cleanTag:gsub("_$", "")
    return prefix .. cleanTag .. "_" .. os.date("%H%M%S")
end

-- Share Audio (Auto-Closes Overlay First So Share Menu Opens Immediately)

function M.shareAudio()
    if not S.generatedAudioPath then
        M.speakOnly("Please generate audio first.")
        return
    end

    local sourceFile = File(S.generatedAudioPath)
    if not sourceFile.exists() then
        M.speakOnly("Audio file not found.")
        return
    end

    local fileName = getDefaultDownloadName() .. ".wav"
    local shareUri = nil
    local lastErr = ""

    if Build.VERSION.SDK_INT >= 29 then
        local ok, err = pcall(function()
            local input = FileInputStream(sourceFile)
            local values = ContentValues()
            values.put("_display_name", fileName)
            values.put("mime_type", "audio/wav")
            values.put("relative_path", Environment.DIRECTORY_DOWNLOADS)
            local resolver = context.getContentResolver()
            local DownloadsClass = luajava.bindClass("android.provider.MediaStore$Downloads")
            local uri = resolver.insert(DownloadsClass.EXTERNAL_CONTENT_URI, values)
            local output = resolver.openOutputStream(uri)
            copyStream(input, output)
            output.flush()
            output.close()
            input.close()
            shareUri = uri
        end)
        if not ok then lastErr = tostring(err) end
    end

    if not shareUri then
        local ok, err = pcall(function()
            local downloadDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            if not downloadDir.exists() then downloadDir.mkdirs() end
            local destFile = File(downloadDir, fileName)
            local input = FileInputStream(sourceFile)
            local output = FileOutputStream(destFile)
            copyStream(input, output)
            output.flush()
            output.close()
            input.close()
            shareUri = Uri.fromFile(destFile)
        end)
        if not ok then lastErr = lastErr .. " | " .. tostring(err) end
    end

    if not shareUri then
        M.logIssue("ShareAudio", lastErr)
        M.speakOnly("Could not prepare audio for sharing: " .. lastErr)
        return
    end

    -- Close overlay dialog first so Android Share Sheet appears right on top
    if M.mainDialogRef then
        pcall(function()
            if S.ui and S.ui.textInput then
                M.saveDraftText(S.ui.textInput.getText().toString())
            end
            S.ui = nil
            M.mainDialogRef.dismiss()
            M.mainDialogRef = nil
        end)
    end

    M.speakOnly("Opening share menu.")
    M.delay(200, function()
        local okIntent, errIntent = pcall(function()
            local sendIntent = Intent(Intent.ACTION_SEND)
            sendIntent.setType("audio/wav")
            sendIntent.putExtra(Intent.EXTRA_STREAM, shareUri)
            sendIntent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            local chooser = Intent.createChooser(sendIntent, "Share Audio via")
            chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(chooser)
        end)
        if not okIntent then
            M.logIssue("ShareIntent", tostring(errIntent))
            M.speakOnly("Share failed: " .. tostring(errIntent))
        end
    end)
end

-- Download System (With Custom File Name Dialog)

function M.performDownload(customBaseName)
    if not S.generatedAudioPath then
        M.speakOnly("Please generate audio first.")
        return false
    end

    local sourceFile = File(S.generatedAudioPath)
    if not sourceFile.exists() then
        M.speakOnly("Audio file not found.")
        return false
    end

    local safeBase = makeSafeFileName(customBaseName)
    local fileName = safeBase .. ".wav"
    local success = false
    local lastErr = ""

    if Build.VERSION.SDK_INT >= 29 then
        local ok, err = pcall(function()
            local input = FileInputStream(sourceFile)
            local values = ContentValues()
            values.put("_display_name", fileName)
            values.put("mime_type", "audio/x-wav")
            values.put("relative_path", Environment.DIRECTORY_DOWNLOADS)
            local resolver = context.getContentResolver()
            local DownloadsClass = luajava.bindClass("android.provider.MediaStore$Downloads")
            local uri = resolver.insert(DownloadsClass.EXTERNAL_CONTENT_URI, values)
            local output = resolver.openOutputStream(uri)
            copyStream(input, output)
            output.flush()
            output.close()
            input.close()
        end)
        if ok then success = true else lastErr = tostring(err) end
    end

    if not success then
        local ok, err = pcall(function()
            local downloadDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            if not downloadDir.exists() then downloadDir.mkdirs() end
            local destFile = File(downloadDir, fileName)
            local input = FileInputStream(sourceFile)
            local output = FileOutputStream(destFile)
            copyStream(input, output)
            output.flush()
            output.close()
            input.close()
            pcall(function()
                local intent = Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE)
                intent.setData(Uri.fromFile(destFile))
                context.sendBroadcast(intent)
            end)
        end)
        if ok then success = true else lastErr = lastErr .. " | " .. tostring(err) end
    end

    if success then
        M.clearAllResumeData()
        M.clearIssueReport()
        M.cfg.userText = ""
        M.saveDraftText("")
        M.runOnUi(function()
            if S.ui then
                M.isUiInitializing = true
                if S.ui.textInput then S.ui.textInput.setText("") end
                if S.ui.charCounter then S.ui.charCounter.setText("0 / " .. M.MAX_CHAR_LIMIT) end
                M.isUiInitializing = false
            end
        end)
        M.refreshActionButtons()
        M.updateProgress(100, "Saved as " .. fileName .. "! Box and logs cleared.", true)
        return true
    else
        M.logIssue("Download", lastErr)
        M.speakOnly("Download failed: " .. lastErr)
        return false
    end
end

function M.showDownloadDialog()
    if not S.generatedAudioPath or not File(S.generatedAudioPath).exists() then
        M.speakOnly("Please generate audio first.")
        return
    end

    local defaultName = getDefaultDownloadName()
    local views = {}
    local layout = {
        LinearLayout,
        orientation = "vertical",
        padding = "20dp",
        layout_width = "fill",
        layout_height = "wrap",
        {
            TextView,
            text = "Enter file name (or tap SAVE for default):",
            textSize = 14,
            textColor = "#333333",
            paddingBottom = "8dp"
        },
        {
            EditText,
            id = "fileNameInput",
            hint = "Enter file name...",
            layout_width = "fill",
            layout_height = "wrap",
            backgroundColor = "#F5F5F5",
            padding = "10dp",
            textSize = 14,
            singleLine = true,
            layout_marginBottom = "14dp"
        },
        {
            Button,
            id = "saveFileBtn",
            text = "SAVE",
            layout_width = "fill",
            layout_height = "wrap",
            backgroundColor = "#2E7D32",
            textColor = "#FFFFFF",
            padding = "12dp",
            layout_marginBottom = "10dp"
        },
        {
            Button,
            id = "cancelBtn",
            text = "GO BACK",
            layout_width = "fill",
            layout_height = "wrap",
            backgroundColor = "#9E9E9E",
            textColor = "#FFFFFF",
            padding = "12dp"
        }
    }

    local dlDialog = LuaDialog(context)
    dlDialog.setTitle("Save Audio")
    dlDialog.setView(loadlayout(layout, views))
    dlDialog.setCancelable(true)

    views.fileNameInput.setText(defaultName)

    views.saveFileBtn.onClick = M.safe("saveFile", function()
        local entered = M.trim(views.fileNameInput.getText().toString())
        if entered == "" then entered = defaultName end
        dlDialog.dismiss()
        M.performDownload(entered)
    end)

    views.cancelBtn.onClick = function()
        dlDialog.dismiss()
    end

    dlDialog.show()
    M.speakOnly("File ka name likhein ya Save daba kar default name se save karein.")
end

-- Dialog: Report Issue (Copy, Send on WhatsApp, Clear Log)

function M.showReportIssueDialog()
    local views = {}
    local reportText = M.getIssueReport()
    local hasReport = (reportText ~= nil and M.trim(reportText) ~= "")
    local displayReport = hasReport and reportText or "No errors or issues recorded yet. Everything is working smoothly."

    local layout = {
        LinearLayout,
        orientation = "vertical",
        padding = "18dp",
        layout_width = "fill",
        layout_height = "wrap",
        {
            ScrollView,
            layout_width = "fill",
            layout_height = "240dp",
            backgroundColor = "#F5F5F5",
            layout_marginBottom = "12dp",
            {
                TextView,
                id = "reportTv",
                text = displayReport,
                textSize = 13,
                textColor = "#222222",
                padding = "10dp"
            }
        },
        {
            Button,
            id = "copyRepBtn",
            text = "COPY REPORT",
            layout_width = "fill",
            layout_height = "wrap",
            backgroundColor = "#0277BD",
            textColor = "#FFFFFF",
            padding = "11dp",
            layout_marginBottom = "8dp"
        },
        {
            Button,
            id = "sendWaRepBtn",
            text = "SEND ON WHATSAPP",
            layout_width = "fill",
            layout_height = "wrap",
            backgroundColor = "#2E7D32",
            textColor = "#FFFFFF",
            padding = "11dp",
            layout_marginBottom = "8dp"
        },
        {
            Button,
            id = "clearRepBtn",
            text = "CLEAR LOG",
            layout_width = "fill",
            layout_height = "wrap",
            backgroundColor = "#D84315",
            textColor = "#FFFFFF",
            padding = "11dp",
            layout_marginBottom = "8dp"
        },
        {
            Button,
            id = "backBtn",
            text = "GO BACK",
            layout_width = "fill",
            layout_height = "wrap",
            backgroundColor = "#9E9E9E",
            textColor = "#FFFFFF",
            padding = "11dp"
        }
    }

    local repDialog = LuaDialog(context)
    repDialog.setTitle("Report Issue")
    repDialog.setView(loadlayout(layout, views))
    repDialog.setCancelable(true)

    views.copyRepBtn.onClick = M.safe("copyReport", function()
        local cur = M.getIssueReport()
        if cur == "" then
            M.speakOnly("No error report to copy.")
            return
        end
        local cm = context.getSystemService(Context.CLIPBOARD_SERVICE)
        cm.setPrimaryClip(ClipData.newPlainText("Issue Report", cur))
        M.speakOnly("Issue report copied to clipboard.")
    end)

    views.sendWaRepBtn.onClick = M.safe("sendWaReport", function()
        local cur = M.getIssueReport()
        if cur == "" then
            M.speakOnly("No error report to send.")
            return
        end
        local msg = M.APP_TITLE .. " Issue Report:\n" .. string.sub(cur, -1500)
        local encoded = Uri.encode(msg)
        local intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://wa.me/" .. M.WHATSAPP_INTL .. "?text=" .. encoded))
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
        M.speakOnly("Opening WhatsApp to send report.")
    end)

    views.clearRepBtn.onClick = M.safe("clearReport", function()
        M.clearIssueReport()
        views.reportTv.setText("No errors or issues recorded yet. Everything is working smoothly.")
        M.speakOnly("Issue log cleared.")
    end)

    views.backBtn.onClick = function()
        repDialog.dismiss()
    end

    repDialog.show()
end

-- Dialogs: About & Support, Description/Guide, API Key, Settings

function M.showAboutDialog()
    local views = {}
    local layout = {
        LinearLayout,
        orientation = "vertical",
        padding = "20dp",
        layout_width = "fill",
        layout_height = "wrap",
        {
            TextView,
            text = M.APP_TITLE,
            textSize = 18,
            textColor = "#2E7D32",
            gravity = "center",
            typeface = Typeface.DEFAULT_BOLD,
            paddingBottom = "10dp"
        },
        {
            TextView,
            text = "Created By: " .. M.CREATOR_NAME,
            textSize = 15,
            textColor = "#222222",
            paddingBottom = "6dp"
        },
        {
            TextView,
            text = "WhatsApp: " .. M.WHATSAPP_LOCAL,
            textSize = 15,
            textColor = "#1565C0",
            paddingBottom = "16dp"
        },
        {
            Button,
            id = "copyWaBtn",
            text = "COPY WHATSAPP",
            layout_width = "fill",
            layout_height = "wrap",
            backgroundColor = "#0277BD",
            textColor = "#FFFFFF",
            padding = "12dp",
            layout_marginBottom = "10dp"
        },
        {
            Button,
            id = "contactWaBtn",
            text = "CONTACT WHATSAPP",
            layout_width = "fill",
            layout_height = "wrap",
            backgroundColor = "#2E7D32",
            textColor = "#FFFFFF",
            padding = "12dp",
            layout_marginBottom = "10dp"
        },
        {
            Button,
            id = "backBtn",
            text = "GO BACK",
            layout_width = "fill",
            layout_height = "wrap",
            backgroundColor = "#9E9E9E",
            textColor = "#FFFFFF",
            padding = "12dp"
        }
    }

    local aboutDialog = LuaDialog(context)
    aboutDialog.setTitle("About & Support")
    aboutDialog.setView(loadlayout(layout, views))
    aboutDialog.setCancelable(true)

    views.copyWaBtn.onClick = M.safe("copyWa", function()
        local cm = context.getSystemService(Context.CLIPBOARD_SERVICE)
        cm.setPrimaryClip(ClipData.newPlainText("WhatsApp", M.WHATSAPP_LOCAL))
        M.speakOnly("WhatsApp number " .. M.WHATSAPP_LOCAL .. " copied.")
    end)

    views.contactWaBtn.onClick = M.safe("contactWa", function()
        local intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://wa.me/" .. M.WHATSAPP_INTL))
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
        M.speakOnly("Opening WhatsApp chat.")
    end)

    views.backBtn.onClick = function()
        aboutDialog.dismiss()
    end

    aboutDialog.show()
end

function M.showGuideDialog()
    local views = {}
    local layout = {
        LinearLayout,
        orientation = "vertical",
        padding = "18dp",
        layout_width = "fill",
        layout_height = "wrap",
        {
            ScrollView,
            layout_width = "fill",
            layout_height = "340dp",
            layout_marginBottom = "14dp",
            {
                TextView,
                text = M.USER_GUIDE_TEXT,
                textSize = 14,
                textColor = "#222222",
                padding = "6dp"
            }
        },
        {
            Button,
            id = "backBtn",
            text = "GO BACK",
            layout_width = "fill",
            layout_height = "wrap",
            backgroundColor = "#9E9E9E",
            textColor = "#FFFFFF",
            padding = "12dp"
        }
    }

    local guideDialog = LuaDialog(context)
    guideDialog.setTitle("Description / User Guide")
    guideDialog.setView(loadlayout(layout, views))
    guideDialog.setCancelable(true)

    views.backBtn.onClick = function()
        guideDialog.dismiss()
    end

    guideDialog.show()
end

function M.showSetApiDialog()
    local views = {}
    local layout = {
        LinearLayout,
        orientation = "vertical",
        padding = "20dp",
        layout_width = "fill",
        layout_height = "wrap",
        {
            EditText,
            id = "apiInput",
            hint = "Paste Gemini API Key here...",
            layout_width = "fill",
            layout_height = "wrap",
            backgroundColor = "#F5F5F5",
            padding = "10dp",
            textSize = 14,
            layout_marginBottom = "10dp"
        },
        {
            Button,
            id = "testBtn",
            text = "TEST API KEY",
            layout_width = "fill",
            layout_height = "wrap",
            backgroundColor = "#FF9800",
            textColor = "#FFFFFF",
            padding = "10dp",
            layout_marginBottom = "10dp"
        },
        {
            Button,
            id = "saveBtn",
            text = "SAVE API KEY",
            layout_width = "fill",
            layout_height = "wrap",
            backgroundColor = "#4CAF50",
            textColor = "#FFFFFF",
            padding = "10dp",
            layout_marginBottom = "10dp"
        },
        {
            Button,
            id = "backBtn",
            text = "GO BACK",
            layout_width = "fill",
            layout_height = "wrap",
            backgroundColor = "#9E9E9E",
            textColor = "#FFFFFF",
            padding = "10dp"
        }
    }

    local apiDialog = LuaDialog(context)
    apiDialog.setTitle("Set API Key")
    apiDialog.setView(loadlayout(layout, views))
    apiDialog.setCancelable(true)

    views.apiInput.setText(M.cfg.apiKey)

    views.testBtn.onClick = M.safe("testApi", function()
        local key = M.sanitizeKey(views.apiInput.getText().toString())
        views.apiInput.setText(key)
        if key == "" then
            M.speakOnly("Please paste an API key first.")
            return
        end

        M.speakOnly("Testing API key.")
        views.testBtn.setText("TESTING...")
        views.testBtn.setEnabled(false)

        local testUrl = "https://generativelanguage.googleapis.com/v1beta/models?key=" .. key
        local okGet, errGet = M.httpGet(testUrl, function(code, content)
            M.runOnUi(function()
                views.testBtn.setText("TEST API KEY")
                views.testBtn.setEnabled(true)
                if code == 200 then
                    M.speakOnly("API key is valid and active.")
                else
                    M.logIssue("TestApiKey", "HTTP " .. tostring(code))
                    M.speakOnly("API key is invalid. Code: " .. tostring(code))
                end
            end)
        end)
        if not okGet then
            views.testBtn.setText("TEST API KEY")
            views.testBtn.setEnabled(true)
            M.logIssue("TestApiKey", tostring(errGet))
            M.speakOnly("Test request failed: " .. tostring(errGet))
        end
    end)

    views.saveBtn.onClick = M.safe("saveApi", function()
        local apikey = M.sanitizeKey(views.apiInput.getText().toString())
        views.apiInput.setText(apikey)
        if apikey == "" then
            M.speakOnly("Please paste an API key first.")
            return
        end
        M.cfg.apiKey = apikey
        M.saveSettings()
        M.speakOnly("API key saved.")
        apiDialog.dismiss()
    end)

    views.backBtn.onClick = function()
        apiDialog.dismiss()
    end

    apiDialog.show()
end

function M.showSettingsDialog()
    local views = {}
    local layout = {
        LinearLayout,
        orientation = "vertical",
        padding = "20dp",
        layout_width = "fill",
        layout_height = "wrap",
        {
            Button,
            id = "setApiBtn",
            text = "SET API KEY",
            layout_width = "fill",
            layout_height = "wrap",
            backgroundColor = "#2196F3",
            textColor = "#FFFFFF",
            padding = "12dp",
            layout_marginBottom = "12dp"
        },
        {
            TextView,
            text = "Select Audio Model:",
            textSize = 14,
            textColor = "#333333",
            paddingBottom = "5dp"
        },
        {
            Spinner,
            id = "modelSpin",
            layout_width = "fill",
            layout_height = "wrap",
            backgroundColor = "#F5F5F5",
            layout_marginBottom = "14dp"
        },
        {
            Button,
            id = "guideBtn",
            text = "DESCRIPTION / GUIDE",
            layout_width = "fill",
            layout_height = "wrap",
            backgroundColor = "#00897B",
            textColor = "#FFFFFF",
            padding = "12dp",
            layout_marginBottom = "10dp"
        },
        {
            Button,
            id = "reportBtn",
            text = "REPORT ISSUE",
            layout_width = "fill",
            layout_height = "wrap",
            backgroundColor = "#E65100",
            textColor = "#FFFFFF",
            padding = "12dp",
            layout_marginBottom = "10dp"
        },
        {
            Button,
            id = "aboutBtn",
            text = "ABOUT & SUPPORT",
            layout_width = "fill",
            layout_height = "wrap",
            backgroundColor = "#5E35B1",
            textColor = "#FFFFFF",
            padding = "12dp",
            layout_marginBottom = "14dp"
        },
        {
            Button,
            id = "goBackBtn",
            text = "GO BACK",
            layout_width = "fill",
            layout_height = "wrap",
            backgroundColor = "#9E9E9E",
            textColor = "#FFFFFF",
            padding = "12dp"
        }
    }

    local settingDialog = LuaDialog(context)
    settingDialog.setTitle("Settings")
    settingDialog.setView(loadlayout(layout, views))
    settingDialog.setCancelable(true)

    views.setApiBtn.onClick = M.safe("setApi", function() M.showSetApiDialog() end)
    views.guideBtn.onClick = M.safe("guide", function() M.showGuideDialog() end)
    views.reportBtn.onClick = M.safe("report", function() M.showReportIssueDialog() end)
    views.aboutBtn.onClick = M.safe("about", function() M.showAboutDialog() end)

    local modelAdapter = ArrayAdapter(context, android.R.layout.simple_spinner_item, M.MODEL_LIST)
    modelAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
    views.modelSpin.setAdapter(modelAdapter)

    for i, m in ipairs(M.MODEL_LIST) do
        if m == M.cfg.model then views.modelSpin.setSelection(i - 1) break end
    end

    views.modelSpin.onItemSelectedListener = {
        onItemSelected = function(p, v, pos)
            local newModel = M.MODEL_LIST[pos + 1]
            if newModel and newModel ~= M.cfg.model then
                M.cfg.model = newModel
                M.saveSettings()
                M.refreshActionButtons()
            end
        end
    }

    views.goBackBtn.onClick = function()
        settingDialog.dismiss()
    end

    settingDialog.show()
end

-- Main Screen (Single Title + Keyboard Resize Safe + Share + Name Download)

function M.showMain()
    M.isUiInitializing = true
    M.loadSettings()

    local views = {}
    local mainLayout = {
        LinearLayout,
        orientation = "vertical",
        layout_width = "fill",
        layout_height = "fill",
        {
            ScrollView,
            layout_width = "fill",
            layout_height = "0dp",
            layout_weight = "1",
            {
                LinearLayout,
                orientation = "vertical",
                padding = "18dp",
                layout_width = "fill",
                layout_height = "wrap",
                {
                    TextView,
                    text = M.APP_TITLE,
                    textSize = 19,
                    textColor = "#2E7D32",
                    gravity = "center",
                    paddingBottom = "12dp",
                    typeface = Typeface.DEFAULT_BOLD
                },
                {
                    TextView,
                    text = "Select Mode:",
                    textSize = 13,
                    textColor = "#1565C0",
                    typeface = Typeface.DEFAULT_BOLD,
                    paddingBottom = "4dp"
                },
                {
                    Spinner,
                    id = "modeSpin",
                    layout_width = "fill",
                    layout_height = "wrap",
                    backgroundColor = "#E3F2FD",
                    layout_marginBottom = "10dp"
                },

                -- SINGLE SPEAKER OPTIONS
                {
                    LinearLayout,
                    id = "singleOptionsLayout",
                    orientation = "vertical",
                    layout_width = "fill",
                    layout_height = "wrap",
                    {
                        TextView,
                        text = "Select Voice (30 Voices):",
                        textSize = 13,
                        textColor = "#333333",
                        paddingBottom = "4dp"
                    },
                    {
                        Spinner,
                        id = "singleVoiceSpin",
                        layout_width = "fill",
                        layout_height = "wrap",
                        backgroundColor = "#F5F5F5",
                        layout_marginBottom = "10dp"
                    },
                    {
                        TextView,
                        text = "Select Mood / Style (24 Styles):",
                        textSize = 13,
                        textColor = "#333333",
                        paddingBottom = "4dp"
                    },
                    {
                        Spinner,
                        id = "singleStyleSpin",
                        layout_width = "fill",
                        layout_height = "wrap",
                        backgroundColor = "#F5F5F5",
                        layout_marginBottom = "10dp"
                    }
                },

                -- 2-HOST BROADCAST OPTIONS
                {
                    LinearLayout,
                    id = "bcOptionsLayout",
                    orientation = "vertical",
                    layout_width = "fill",
                    layout_height = "wrap",
                    visibility = View.GONE,
                    {
                        TextView,
                        text = "Speaker 1 Voice (Male):",
                        textSize = 13,
                        textColor = "#333333",
                        paddingBottom = "4dp"
                    },
                    {
                        Spinner,
                        id = "maleSpin",
                        layout_width = "fill",
                        layout_height = "wrap",
                        backgroundColor = "#F5F5F5",
                        layout_marginBottom = "10dp"
                    },
                    {
                        TextView,
                        text = "Speaker 2 Voice (Female):",
                        textSize = 13,
                        textColor = "#333333",
                        paddingBottom = "4dp"
                    },
                    {
                        Spinner,
                        id = "femaleSpin",
                        layout_width = "fill",
                        layout_height = "wrap",
                        backgroundColor = "#F5F5F5",
                        layout_marginBottom = "10dp"
                    },
                    {
                        TextView,
                        text = "Select Broadcast Mood (19 Moods):",
                        textSize = 13,
                        textColor = "#333333",
                        paddingBottom = "4dp"
                    },
                    {
                        Spinner,
                        id = "bcMoodSpin",
                        layout_width = "fill",
                        layout_height = "wrap",
                        backgroundColor = "#F5F5F5",
                        layout_marginBottom = "10dp"
                    }
                },

                -- SHARED OPTIONS (20 Languages + Duration + Custom Minutes)
                {
                    TextView,
                    text = "Select Language (20 Languages):",
                    textSize = 13,
                    textColor = "#333333",
                    paddingBottom = "4dp"
                },
                {
                    Spinner,
                    id = "langSpin",
                    layout_width = "fill",
                    layout_height = "wrap",
                    backgroundColor = "#F5F5F5",
                    layout_marginBottom = "10dp"
                },
                {
                    TextView,
                    text = "Select Script Duration:",
                    textSize = 13,
                    textColor = "#333333",
                    paddingBottom = "4dp"
                },
                {
                    Spinner,
                    id = "durationSpin",
                    layout_width = "fill",
                    layout_height = "wrap",
                    backgroundColor = "#F5F5F5",
                    layout_marginBottom = "8dp"
                },
                {
                    LinearLayout,
                    id = "customMinLayout",
                    orientation = "horizontal",
                    layout_width = "fill",
                    layout_height = "wrap",
                    gravity = "center_vertical",
                    visibility = View.GONE,
                    layout_marginBottom = "10dp",
                    {
                        TextView,
                        text = "Custom Minutes (1-60): ",
                        textSize = 13,
                        textColor = "#333333"
                    },
                    {
                        EditText,
                        id = "customMinInput",
                        hint = "e.g. 3",
                        layout_width = "0dp",
                        layout_weight = "1",
                        layout_height = "wrap",
                        backgroundColor = "#F5F5F5",
                        padding = "8dp",
                        textSize = 14,
                        singleLine = true
                    }
                },

                -- SHARED TOPIC / SCRIPT INPUT
                {
                    EditText,
                    id = "textInput",
                    hint = "Enter topic to CREATE SCRIPT, or paste text/script to GENERATE AUDIO...",
                    layout_width = "fill",
                    layout_height = "150dp",
                    backgroundColor = "#F5F5F5",
                    padding = "12dp",
                    gravity = Gravity.TOP,
                    textSize = 14,
                    layout_marginBottom = "6dp"
                },
                {
                    LinearLayout,
                    orientation = "horizontal",
                    layout_width = "fill",
                    layout_height = "wrap",
                    gravity = "center_vertical",
                    layout_marginBottom = "6dp",
                    {
                        Button,
                        id = "clearTextBtn",
                        text = "CLEAR TEXT",
                        layout_width = "wrap",
                        layout_height = "wrap",
                        backgroundColor = "#78909C",
                        textColor = "#FFFFFF",
                        textSize = 11,
                        paddingLeft = "12dp",
                        paddingRight = "12dp",
                        paddingTop = "6dp",
                        paddingBottom = "6dp"
                    },
                    {
                        TextView,
                        id = "charCounter",
                        text = "0 / " .. M.MAX_CHAR_LIMIT,
                        layout_width = "0dp",
                        layout_weight = "1",
                        textSize = 12,
                        textColor = "#888888",
                        gravity = "right"
                    }
                }
            }
        },

        -- FIXED BOTTOM CONTROLS (Always visible even when keyboard opens)
        {
            LinearLayout,
            orientation = "vertical",
            layout_width = "fill",
            layout_height = "wrap",
            paddingLeft = "18dp",
            paddingRight = "18dp",
            paddingTop = "8dp",
            paddingBottom = "18dp",
            {
                TextView,
                id = "statusText",
                text = "[0%] Status: Ready",
                layout_width = "fill",
                layout_height = "wrap",
                textSize = 13,
                textColor = "#1565C0",
                paddingBottom = "6dp",
                typeface = Typeface.DEFAULT_BOLD
            },
            {
                Button,
                id = "createScriptBtn",
                text = "CREATE SCRIPT",
                layout_width = "fill",
                layout_height = "wrap",
                backgroundColor = "#6A1B9A",
                textColor = "#FFFFFF",
                padding = "11dp",
                textSize = 14,
                layout_marginBottom = "6dp"
            },
            {
                Button,
                id = "generateBtn",
                text = "GENERATE AUDIO",
                layout_width = "fill",
                layout_height = "wrap",
                backgroundColor = "#2196F3",
                textColor = "#FFFFFF",
                padding = "11dp",
                textSize = 14,
                layout_marginBottom = "6dp"
            },
            {
                LinearLayout,
                id = "resultLayout",
                orientation = "vertical",
                layout_width = "fill",
                layout_height = "wrap",
                visibility = View.GONE,
                layout_marginBottom = "6dp",
                {
                    TextView,
                    id = "durationLabel",
                    text = "Audio Length: 0 min 00 sec",
                    textSize = 14,
                    textColor = "#1B5E20",
                    gravity = "center",
                    paddingBottom = "4dp",
                    typeface = Typeface.DEFAULT_BOLD
                },
                {
                    LinearLayout,
                    orientation = "horizontal",
                    layout_width = "fill",
                    layout_height = "wrap",
                    {
                        Button,
                        id = "playBtnID",
                        text = "PLAY",
                        layout_width = "0dp",
                        layout_weight = "1.2",
                        backgroundColor = "#4CAF50",
                        textColor = "#FFFFFF",
                        padding = "10dp",
                        layout_marginRight = "4dp",
                        enabled = false
                    },
                    {
                        Button,
                        id = "shareBtn",
                        text = "SHARE",
                        layout_width = "0dp",
                        layout_weight = "0.9",
                        backgroundColor = "#0288D1",
                        textColor = "#FFFFFF",
                        padding = "10dp",
                        layout_marginRight = "4dp"
                    },
                    {
                        Button,
                        id = "downloadBtn",
                        text = "DOWNLOAD",
                        layout_width = "0dp",
                        layout_weight = "1",
                        backgroundColor = "#FF9800",
                        textColor = "#FFFFFF",
                        padding = "10dp"
                    }
                }
            },
            {
                LinearLayout,
                orientation = "horizontal",
                layout_width = "fill",
                layout_height = "wrap",
                {
                    Button,
                    id = "settingBtn",
                    text = "SETTING",
                    layout_width = "0dp",
                    layout_weight = "1",
                    backgroundColor = "#607D8B",
                    textColor = "#FFFFFF",
                    padding = "10dp",
                    layout_marginRight = "5dp"
                },
                {
                    Button,
                    id = "exitBtn",
                    text = "EXIT",
                    layout_width = "0dp",
                    layout_weight = "1",
                    backgroundColor = "#D32F2F",
                    textColor = "#FFFFFF",
                    padding = "10dp",
                    layout_marginLeft = "5dp"
                }
            }
        }
    }

    local mainDialog = LuaDialog(context)
    M.mainDialogRef = mainDialog
    mainDialog.setCancelable(false)
    mainDialog.setView(loadlayout(mainLayout, views))

    pcall(function()
        local win = mainDialog.getWindow()
        if win then
            win.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
        end
    end)

    S.ui = {
        statusText = views.statusText,
        createScriptBtn = views.createScriptBtn,
        generateBtn = views.generateBtn,
        resultLayout = views.resultLayout,
        durationLabel = views.durationLabel,
        playBtn = views.playBtnID,
        textInput = views.textInput,
        charCounter = views.charCounter
    }

    local function applyModeVisibility()
        local isSingle = (M.cfg.mode == M.MODE_LIST[1])
        views.singleOptionsLayout.setVisibility(isSingle and View.VISIBLE or View.GONE)
        views.bcOptionsLayout.setVisibility(isSingle and View.GONE or View.VISIBLE)
    end

    local function applyCustomMinVisibility()
        local isCustom = (M.cfg.duration == "Custom Minutes")
        views.customMinLayout.setVisibility(isCustom and View.VISIBLE or View.GONE)
    end

    pcall(function()
        views.textInput.setFilters({InputFilter.LengthFilter(M.MAX_CHAR_LIMIT)})
        views.customMinInput.setInputType(InputType.TYPE_CLASS_NUMBER)
    end)

    views.customMinInput.setText(M.cfg.customMinutes)
    views.customMinInput.addTextChangedListener({
        afterTextChanged = function(editable)
            if M.isUiInitializing then return end
            pcall(function()
                M.cfg.customMinutes = M.trim(editable.toString())
                M.saveSettings()
            end)
        end
    })

    if M.cfg.userText ~= nil and M.cfg.userText ~= "" then
        views.textInput.setText(M.cfg.userText)
        views.charCounter.setText(tostring(views.textInput.getText().length()) .. " / " .. M.MAX_CHAR_LIMIT)
    end

    views.statusText.setText("[" .. tostring(S.percent) .. "%] " .. S.statusText)
    M.refreshActionButtons()
    if not S.isGenerating and S.generatedAudioPath and File(S.generatedAudioPath).exists() then
        views.resultLayout.setVisibility(View.VISIBLE)
        views.durationLabel.setText("Audio Length: " .. S.currentDurationStr)
        views.playBtnID.setEnabled(true)
        views.playBtnID.setText((S.isPlaying and "PAUSE (" or "PLAY (") .. S.currentDurationStr .. ")")
    end

    views.textInput.addTextChangedListener({
        afterTextChanged = function(editable)
            if M.isUiInitializing then return end
            pcall(function()
                local newTxt = editable.toString()
                if newTxt ~= M.cfg.userText then
                    M.cfg.userText = newTxt
                    M.saveDraftText(newTxt)
                end
                views.charCounter.setText(tostring(editable.length()) .. " / " .. M.MAX_CHAR_LIMIT)
                M.refreshActionButtons()
            end)
        end
    })

    views.clearTextBtn.onClick = M.safe("clear", function()
        if S.isGenerating or S.isWritingScript then
            M.speakOnly("Please wait for the current task to finish.")
            return
        end
        M.cfg.userText = ""
        M.saveDraftText("")
        M.clearAllResumeData()
        M.deleteOldAudioFile()
        views.textInput.setText("")
        views.charCounter.setText("0 / " .. M.MAX_CHAR_LIMIT)
        views.resultLayout.setVisibility(View.GONE)
        M.refreshActionButtons()
        M.updateProgress(0, "Status: Ready", true)
    end)

    local function bindSpinner(spin, displayList, valueList, currentVal, onChange)
        local adapter = ArrayAdapter(context, android.R.layout.simple_spinner_item, displayList)
        adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        spin.setAdapter(adapter)
        local vals = valueList or displayList
        for i, v in ipairs(vals) do
            if v == currentVal then spin.setSelection(i - 1) break end
        end
        spin.onItemSelectedListener = {
            onItemSelected = function(p, v, pos)
                if not M.isUiInitializing and vals[pos + 1] then
                    onChange(vals[pos + 1])
                    M.saveSettings()
                    M.refreshActionButtons()
                end
            end
        }
    end

    bindSpinner(views.modeSpin, M.MODE_LIST, nil, M.cfg.mode, function(v)
        M.cfg.mode = v
        applyModeVisibility()
    end)
    bindSpinner(views.singleVoiceSpin, M.VOICE_LIST, M.RAW_VOICES, M.cfg.singleVoice, function(v) M.cfg.singleVoice = v end)
    bindSpinner(views.singleStyleSpin, M.SINGLE_STYLE_LIST, nil, M.cfg.singleStyle, function(v) M.cfg.singleStyle = v end)
    bindSpinner(views.maleSpin, M.MALE_VOICES, nil, M.cfg.maleVoice, function(v) M.cfg.maleVoice = v end)
    bindSpinner(views.femaleSpin, M.FEMALE_VOICES, nil, M.cfg.femaleVoice, function(v) M.cfg.femaleVoice = v end)
    bindSpinner(views.bcMoodSpin, M.BROADCAST_MOODS, nil, M.cfg.bcMood, function(v) M.cfg.bcMood = v end)
    bindSpinner(views.langSpin, M.LANGUAGES, nil, M.cfg.lang, function(v) M.cfg.lang = v end)
    bindSpinner(views.durationSpin, M.DURATION_LIST, nil, M.cfg.duration, function(v)
        M.cfg.duration = v
        applyCustomMinVisibility()
    end)

    applyModeVisibility()
    applyCustomMinVisibility()

    views.playBtnID.onClick = M.safe("play", function()
        M.togglePlayPause(views.playBtnID)
    end)

    views.shareBtn.onClick = M.safe("share", function()
        M.shareAudio()
    end)

    views.downloadBtn.onClick = M.safe("download", function()
        M.showDownloadDialog()
    end)

    -- BUTTON 1: CREATE SCRIPT ONLY
    views.createScriptBtn.onClick = M.safe("createScript", function()
        if S.isWritingScript or S.isGenerating then
            M.speakOnly("A task is already running, " .. tostring(S.percent) .. " percent done.")
            return
        end

        local currentText = M.trim(views.textInput.getText().toString())
        if currentText == "" then
            M.speakOnly("Please enter a topic or instructions first.")
            return
        end

        if M.cfg.apiKey == "" then
            M.speakOnly("API key is not set. Please set it in Settings.")
            return
        end

        M.cfg.userText = currentText
        M.saveDraftText(currentText)
        M.startCreateScriptJob(currentText)
    end)

    -- BUTTON 2: GENERATE AUDIO
    views.generateBtn.onClick = M.safe("generateAudio", function()
        if S.isGenerating or S.isWritingScript then
            M.speakOnly("A task is already running, " .. tostring(S.percent) .. " percent done.")
            return
        end

        local currentText = M.trim(views.textInput.getText().toString())
        if currentText == "" then
            M.speakOnly("Please enter text or create a script first.")
            return
        end

        if M.cfg.apiKey == "" then
            M.speakOnly("API key is not set. Please set it in Settings.")
            return
        end

        M.cfg.userText = currentText
        M.saveDraftText(currentText)

        if S.mediaPlayer ~= nil then
            pcall(function()
                if S.isPlaying then S.mediaPlayer.stop() end
                S.mediaPlayer.release()
            end)
            S.mediaPlayer = nil
            S.isPlaying = false
        end

        M.deleteOldAudioFile()
        views.playBtnID.setEnabled(false)
        views.playBtnID.setText("PLAY")
        views.resultLayout.setVisibility(View.GONE)

        if M.cfg.mode == M.MODE_LIST[1] then
            M.startSingleSpeakerAudioJob(currentText)
        else
            M.startBroadcastAudioJob(currentText)
        end
    end)

    views.settingBtn.onClick = M.safe("setting", function()
        M.showSettingsDialog()
    end)

    views.exitBtn.onClick = function()
        pcall(function() M.saveDraftText(views.textInput.getText().toString()) end)
        S.ui = nil
        M.mainDialogRef = nil
        if S.isGenerating or S.isWritingScript then
            M.speakOnly("Continuing in background. Re-open anytime to check progress.")
        end
        mainDialog.dismiss()
    end

    mainDialog.show()
    M.delay(300, function()
        M.isUiInitializing = false
        M.refreshActionButtons()
    end)
end

-- Entry Point

local okMain, errMain = pcall(M.showMain)
if not okMain then
    pcall(function() M.logIssue("Startup", tostring(errMain)) end)
    pcall(function() Toast.makeText(context, "Script start error: " .. tostring(errMain), Toast.LENGTH_LONG).show() end)
    pcall(function() service.speak("Script start error: " .. tostring(errMain)) end)
end