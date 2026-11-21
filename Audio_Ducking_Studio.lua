require "import"
import "android.app.*"
import "android.os.*"
import "android.widget.*"
import "android.view.*"
import "android.view.accessibility.*"
import "android.content.*"
import "android.net.*"
import "android.media.*"
import "android.provider.*"
import "java.io.*"
import "java.lang.*"
import "java.text.SimpleDateFormat"
import "java.util.Date"

local ctx = service or activity
local mainHandler = Handler(Looper.getMainLooper())

-- ==========================================
-- CONSTANTS & INFO
-- ==========================================
local EXT_NAME = "Audio Ducking Studio"
local CREATOR_NAME = "Mohammad Usman"
local WHATSAPP_LOCAL = "03261421100"
local WHATSAPP_INTL = "923261421100"

local ENGLISH_DESCRIPTION =
  "Audio Ducking Studio is a fast, 100% offline audio mixing and auto-ducking extension built for Jieshuo Screen Reader.\n\n" ..
  "Key Features:\n" ..
  "- Combines your main voice audio with any background music.\n" ..
  "- Automatically lowers background music when you speak and smoothly raises it during silence.\n" ..
  "- Adds a 1.5-second background music intro before your voice starts and a 1.5-second outro after your voice ends.\n" ..
  "- Automatically loops background music if it is shorter than your main audio.\n" ..
  "- Customizable Ducking Settings directly on the home screen: Audio Ducking Percentage (10% to 80%), Silence Duration (0.2s to 2.0s), Gradual Fade Down (0.1s to 1.0s), and Gradual Fade Up (0.3s to 1.5s).\n" ..
  "- Built-in Diagnostic Report in Settings to inspect device details, feature health, and error logs.\n\n" ..
  "How To Use:\n" ..
  "1. Tap Audio to choose your main voice recording, then tap Done.\n" ..
  "2. Tap BG Music to choose your background music track, then tap Done.\n" ..
  "3. Adjust Voice Volume (default 100%) and Music Volume (default 50%).\n" ..
  "4. Tap Ducking to customize ducking percentage, silence duration, fade down, and fade up.\n" ..
  "5. Tap Create and wait for progress to reach 100%.\n" ..
  "6. Once generated, use Play/Pause to listen, Save to store in Music/AudioDucking, or Share directly to WhatsApp and other apps."

-- ==========================================
-- DIAGNOSTIC LOGS & SAVED PREFERENCES
-- ==========================================
local errorLogs = {}
local function addLog(msg)
  local ts = SimpleDateFormat("HH:mm:ss").format(Date())
  table.insert(errorLogs, "[" .. ts .. "] " .. tostring(msg))
  if #errorLogs > 40 then
    table.remove(errorLogs, 1)
  end
end

local prefs = ctx.getSharedPreferences("AudioDuckingStudioPrefs", Context.MODE_PRIVATE)
local duckPct = prefs.getInt("duckPct", 20)        -- Default: 20%
local silenceMs = prefs.getInt("silenceMs", 500)   -- Default: 0.5s
local fadeDownMs = prefs.getInt("fadeDownMs", 300) -- Default: 0.3s
local fadeUpMs = prefs.getInt("fadeUpMs", 600)     -- Default: 0.6s

local function saveDuckingPrefs()
  pcall(function()
    local ed = prefs.edit()
    ed.putInt("duckPct", duckPct)
    ed.putInt("silenceMs", silenceMs)
    ed.putInt("fadeDownMs", fadeDownMs)
    ed.putInt("fadeUpMs", fadeUpMs)
    ed.apply()
  end)
end

-- ==========================================
-- HELPERS
-- ==========================================
local function speak(msg)
  pcall(function()
    if service and service.speak then
      service.speak(tostring(msg))
    end
  end)
end

local function toast(msg)
  pcall(function()
    Toast.makeText(ctx, tostring(msg), Toast.LENGTH_SHORT).show()
  end)
end

local function formatDuration(ms)
  local totalSec = math.floor((ms or 0) / 1000)
  local mins = math.floor(totalSec / 60)
  local secs = totalSec % 60
  return string.format("%02d:%02d", mins, secs)
end

local function formatSec(ms)
  return string.format("%.1f sec", ms / 1000.0)
end

local function focusViewForJieshuo(view)
  pcall(function()
    view.requestFocus()
    view.performAccessibilityAction(AccessibilityNodeInfo.ACTION_ACCESSIBILITY_FOCUS, nil)
    view.sendAccessibilityEvent(AccessibilityEvent.TYPE_VIEW_FOCUSED)
  end)
end

local function createFullScreenDialog(contentView)
  local dlg = Dialog(ctx, android.R.style.Theme_DeviceDefault_NoActionBar)
  dlg.setContentView(contentView)
  dlg.setCancelable(false)
  pcall(function()
    local win = dlg.getWindow()
    win.setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
    win.setLayout(WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.MATCH_PARENT)
    win.setGravity(Gravity.BOTTOM)
    win.setBackgroundDrawableResource(android.R.color.black)
  end)
  dlg.show()
  pcall(function()
    local win = dlg.getWindow()
    win.setLayout(WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.MATCH_PARENT)
  end)
  return dlg
end

local function showChoiceDialog(items, checkedIdx, onPicked)
  local builder = AlertDialog.Builder(ctx)
  builder.setSingleChoiceItems(items, checkedIdx, DialogInterface.OnClickListener{
    onClick = function(dialog, which)
      dialog.dismiss()
      onPicked(which + 1)
    end
  })
  builder.setNegativeButton("Cancel", nil)
  local dlg = builder.create()
  pcall(function()
    dlg.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
  end)
  dlg.show()
end

-- ==========================================
-- STATE VARIABLES
-- ==========================================
local mainAudioPath = nil
local mainAudioName = "None"
local bgMusicPath = nil
local bgMusicName = "None"

local mainVolPct = 100 -- Default: 100% (Normal 1.0x)
local bgVolPct = 50    -- Default: 50% (Normal 1.0x)

local cacheDir = ctx.getCacheDir().getAbsolutePath()
local tempMainPcm = cacheDir .. "/duck_main.pcm"
local tempBgPcm = cacheDir .. "/duck_bg.pcm"
local tempOutPath = cacheDir .. "/duck_preview.wav"

local finalSavedUri = nil
local finalSavedPath = nil
local isProcessing = false
local isCancelled = false

local previewPlayer = nil
local resultPlayer = nil
local isResultPlaying = false
local mainDialog = nil

-- ==========================================
-- MEDIA PLAYER HELPERS
-- ==========================================
local function stopPreview()
  if previewPlayer then
    pcall(function()
      if previewPlayer.isPlaying() then previewPlayer.stop() end
      previewPlayer.release()
    end)
    previewPlayer = nil
  end
end

local function stopResultPlayer(playBtn)
  if resultPlayer then
    pcall(function()
      if resultPlayer.isPlaying() then resultPlayer.stop() end
      resultPlayer.release()
    end)
    resultPlayer = nil
  end
  isResultPlaying = false
  if playBtn then playBtn.setText("Play") end
end

-- ==========================================
-- AUDIO DUCKING SETTINGS SCREEN
-- ==========================================
local function openDuckingSettingsDialog()
  local dsDlg = nil
  local ids = {}

  local layout = {
    LinearLayout,
    orientation = "vertical",
    layout_width = "fill",
    layout_height = "fill",
    padding = "14dp",
    backgroundColor = "#121212",
    {
      TextView,
      text = "Audio Ducking Settings",
      textSize = "21sp",
      textColor = "#00E676",
      gravity = "center",
      layout_width = "fill",
      layout_height = "wrap",
      paddingBottom = "12dp"
    },
    {
      LinearLayout,
      orientation = "vertical",
      layout_width = "fill",
      layout_height = "0dp",
      layout_weight = "1",
      gravity = "center",
      {
        Button,
        id = "btnDuckPct",
        text = "Audio Ducking: " .. duckPct .. "%",
        layout_width = "fill",
        layout_height = "wrap",
        layout_marginBottom = "10dp"
      },
      {
        Button,
        id = "btnSilenceDur",
        text = "Silence Duration: " .. formatSec(silenceMs),
        layout_width = "fill",
        layout_height = "wrap",
        layout_marginBottom = "10dp"
      },
      {
        Button,
        id = "btnFadeDown",
        text = "Fade Down (Slow Down): " .. formatSec(fadeDownMs),
        layout_width = "fill",
        layout_height = "wrap",
        layout_marginBottom = "10dp"
      },
      {
        Button,
        id = "btnFadeUp",
        text = "Fade Up (Speed Up): " .. formatSec(fadeUpMs),
        layout_width = "fill",
        layout_height = "wrap"
      }
    },
    {
      Button,
      id = "btnDsBack",
      text = "Go Back",
      layout_width = "fill",
      layout_height = "wrap",
      layout_marginTop = "10dp"
    }
  }

  local view = loadlayout(layout, ids)

  ids.btnDuckPct.onClick = function()
    local vals = {10, 20, 30, 40, 50, 60, 70, 80}
    local labels = {}
    local checked = 1
    for i, v in ipairs(vals) do
      labels[i] = v .. "%" .. (v == 20 and " (Default)" or "")
      if v == duckPct then checked = i - 1 end
    end
    showChoiceDialog(labels, checked, function(idx)
      duckPct = vals[idx]
      saveDuckingPrefs()
      ids.btnDuckPct.setText("Audio Ducking: " .. duckPct .. "%")
      speak("Audio ducking " .. duckPct .. " percent")
    end)
  end

  ids.btnSilenceDur.onClick = function()
    local vals = {200, 500, 1000, 1500, 2000}
    local labels = {"0.2 sec", "0.5 sec (Default)", "1.0 sec", "1.5 sec", "2.0 sec"}
    local checked = 1
    for i, v in ipairs(vals) do
      if v == silenceMs then checked = i - 1 end
    end
    showChoiceDialog(labels, checked, function(idx)
      silenceMs = vals[idx]
      saveDuckingPrefs()
      ids.btnSilenceDur.setText("Silence Duration: " .. formatSec(silenceMs))
      speak("Silence duration " .. formatSec(silenceMs))
    end)
  end

  ids.btnFadeDown.onClick = function()
    local vals = {100, 300, 500, 1000}
    local labels = {"Fast (0.1 sec)", "Medium (0.3 sec - Default)", "Smooth (0.5 sec)", "Slow (1.0 sec)"}
    local checked = 1
    for i, v in ipairs(vals) do
      if v == fadeDownMs then checked = i - 1 end
    end
    showChoiceDialog(labels, checked, function(idx)
      fadeDownMs = vals[idx]
      saveDuckingPrefs()
      ids.btnFadeDown.setText("Fade Down (Slow Down): " .. formatSec(fadeDownMs))
      speak("Fade down " .. formatSec(fadeDownMs))
    end)
  end

  ids.btnFadeUp.onClick = function()
    local vals = {300, 600, 1000, 1500}
    local labels = {"Fast (0.3 sec)", "Medium (0.6 sec - Default)", "Smooth (1.0 sec)", "Slow (1.5 sec)"}
    local checked = 1
    for i, v in ipairs(vals) do
      if v == fadeUpMs then checked = i - 1 end
    end
    showChoiceDialog(labels, checked, function(idx)
      fadeUpMs = vals[idx]
      saveDuckingPrefs()
      ids.btnFadeUp.setText("Fade Up (Speed Up): " .. formatSec(fadeUpMs))
      speak("Fade up " .. formatSec(fadeUpMs))
    end)
  end

  ids.btnDsBack.onClick = function()
    if dsDlg then dsDlg.dismiss() end
    speak("Main screen")
  end

  dsDlg = createFullScreenDialog(view)
  speak("Audio Ducking Settings")
end

-- ==========================================
-- SETTINGS -> DIAGNOSTIC REPORT SCREEN
-- ==========================================
local function buildDiagnosticReport()
  local phoneName = tostring(Build.MANUFACTURER) .. " " .. tostring(Build.MODEL)
  local androidVer = tostring(Build.VERSION.RELEASE) .. " (SDK " .. tostring(Build.VERSION.SDK_INT) .. ")"
  local cacheOk = File(cacheDir).canWrite() and "OK" or "NOT WRITABLE"
  local logText = (#errorLogs > 0) and table.concat(errorLogs, "\n") or "No errors recorded. All features working normally."

  return "=== " .. EXT_NAME .. " Report ===\n" ..
         "Phone: " .. phoneName .. "\n" ..
         "Android: " .. androidVer .. "\n" ..
         "Cache Status: " .. cacheOk .. "\n" ..
         "Voice Vol: " .. mainVolPct .. "% | Music Vol: " .. bgVolPct .. "%\n" ..
         "Ducking: " .. duckPct .. "% | Silence: " .. formatSec(silenceMs) .. "\n" ..
         "Fade Down: " .. formatSec(fadeDownMs) .. " | Fade Up: " .. formatSec(fadeUpMs) .. "\n" ..
         "Audio Selected: " .. mainAudioName .. "\n" ..
         "BG Music Selected: " .. bgMusicName .. "\n\n" ..
         "--- Logs / Errors ---\n" .. logText
end

local function openReportDialog(settingsDlg)
  local repDlg = nil
  local ids = {}
  local reportText = buildDiagnosticReport()

  local layout = {
    LinearLayout,
    orientation = "vertical",
    layout_width = "fill",
    layout_height = "fill",
    padding = "14dp",
    backgroundColor = "#121212",
    {
      TextView,
      text = "Diagnostic Report",
      textSize = "21sp",
      textColor = "#00E676",
      gravity = "center",
      layout_width = "fill",
      layout_height = "wrap",
      paddingBottom = "10dp"
    },
    {
      ScrollView,
      layout_width = "fill",
      layout_height = "0dp",
      layout_weight = "1",
      backgroundColor = "#1E1E1E",
      padding = "12dp",
      {
        TextView,
        text = reportText,
        textSize = "14sp",
        textColor = "#FFFFFF",
        layout_width = "fill",
        layout_height = "wrap"
      }
    },
    {
      LinearLayout,
      orientation = "vertical",
      layout_width = "fill",
      layout_height = "wrap",
      paddingTop = "10dp",
      {
        LinearLayout,
        orientation = "horizontal",
        layout_width = "fill",
        layout_height = "wrap",
        {
          Button,
          id = "btnCopyRep",
          text = "Copy Report",
          layout_width = "0dp",
          layout_weight = "1",
          layout_height = "wrap"
        },
        {
          Button,
          id = "btnSendRepWa",
          text = "Send WhatsApp",
          layout_width = "0dp",
          layout_weight = "1",
          layout_height = "wrap"
        }
      },
      {
        Button,
        id = "btnRepBack",
        text = "Go Back",
        layout_width = "fill",
        layout_height = "wrap",
        layout_marginTop = "6dp"
      }
    }
  }

  local view = loadlayout(layout, ids)

  ids.btnCopyRep.onClick = function()
    pcall(function()
      local cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE)
      cm.setPrimaryClip(ClipData.newPlainText("Diagnostic Report", reportText))
    end)
    speak("Report copied")
    toast("Report copied")
  end

  ids.btnSendRepWa.onClick = function()
    if repDlg then repDlg.dismiss() end
    if settingsDlg then settingsDlg.dismiss() end
    if mainDialog then mainDialog.dismiss() end
    pcall(function()
      local url = "https://wa.me/" .. WHATSAPP_INTL .. "?text=" .. Uri.encode(reportText)
      local intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
      intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      ctx.startActivity(intent)
    end)
  end

  ids.btnRepBack.onClick = function()
    if repDlg then repDlg.dismiss() end
    speak("Settings")
  end

  repDlg = createFullScreenDialog(view)
  speak("Diagnostic Report")
end

-- ==========================================
-- SETTINGS -> DESCRIPTION SCREEN
-- ==========================================
local function openDescriptionDialog()
  local descDlg = nil
  local ids = {}
  local layout = {
    LinearLayout,
    orientation = "vertical",
    layout_width = "fill",
    layout_height = "fill",
    padding = "14dp",
    backgroundColor = "#121212",
    {
      TextView,
      text = "Extension Description",
      textSize = "21sp",
      textColor = "#00E676",
      gravity = "center",
      layout_width = "fill",
      layout_height = "wrap",
      paddingBottom = "10dp"
    },
    {
      ScrollView,
      layout_width = "fill",
      layout_height = "0dp",
      layout_weight = "1",
      backgroundColor = "#1E1E1E",
      padding = "12dp",
      {
        TextView,
        text = ENGLISH_DESCRIPTION,
        textSize = "15sp",
        textColor = "#FFFFFF",
        layout_width = "fill",
        layout_height = "wrap"
      }
    },
    {
      Button,
      id = "btnDescBack",
      text = "Go Back",
      layout_width = "fill",
      layout_height = "wrap",
      layout_marginTop = "10dp"
    }
  }

  local view = loadlayout(layout, ids)
  ids.btnDescBack.onClick = function()
    if descDlg then descDlg.dismiss() end
    speak("Settings")
  end

  descDlg = createFullScreenDialog(view)
  speak("Extension Description")
end

-- ==========================================
-- SETTINGS -> ABOUT & SUPPORT SCREEN
-- ==========================================
local function openAboutSupportDialog(settingsDlg)
  local aboutDlg = nil
  local ids = {}
  local layout = {
    LinearLayout,
    orientation = "vertical",
    layout_width = "fill",
    layout_height = "fill",
    padding = "14dp",
    backgroundColor = "#121212",
    {
      TextView,
      text = "About & Support",
      textSize = "21sp",
      textColor = "#00E676",
      gravity = "center",
      layout_width = "fill",
      layout_height = "wrap",
      paddingBottom = "12dp"
    },
    {
      LinearLayout,
      orientation = "vertical",
      layout_width = "fill",
      layout_height = "0dp",
      layout_weight = "1",
      gravity = "center",
      backgroundColor = "#1E1E1E",
      padding = "16dp",
      {
        TextView,
        text = "Extension Name: " .. EXT_NAME ..
               "\n\nCreator: " .. CREATOR_NAME ..
               "\n\nWhatsApp: " .. WHATSAPP_LOCAL,
        textSize = "16sp",
        textColor = "#FFFFFF",
        gravity = "center",
        layout_width = "fill",
        layout_height = "wrap"
      }
    },
    {
      LinearLayout,
      orientation = "vertical",
      layout_width = "fill",
      layout_height = "wrap",
      paddingTop = "10dp",
      {
        LinearLayout,
        orientation = "horizontal",
        layout_width = "fill",
        layout_height = "wrap",
        {
          Button,
          id = "btnCopyWa",
          text = "Copy",
          layout_width = "0dp",
          layout_weight = "1",
          layout_height = "wrap"
        },
        {
          Button,
          id = "btnContactWa",
          text = "Contact WhatsApp",
          layout_width = "0dp",
          layout_weight = "1",
          layout_height = "wrap"
        }
      },
      {
        Button,
        id = "btnAboutBack",
        text = "Go Back",
        layout_width = "fill",
        layout_height = "wrap",
        layout_marginTop = "6dp"
      }
    }
  }

  local view = loadlayout(layout, ids)

  ids.btnCopyWa.onClick = function()
    pcall(function()
      local cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE)
      cm.setPrimaryClip(ClipData.newPlainText("WhatsApp", WHATSAPP_LOCAL))
    end)
    speak("WhatsApp number copied")
    toast("Copied: " .. WHATSAPP_LOCAL)
  end

  ids.btnContactWa.onClick = function()
    if aboutDlg then aboutDlg.dismiss() end
    if settingsDlg then settingsDlg.dismiss() end
    if mainDialog then mainDialog.dismiss() end
    pcall(function()
      local intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://wa.me/" .. WHATSAPP_INTL))
      intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      ctx.startActivity(intent)
    end)
  end

  ids.btnAboutBack.onClick = function()
    if aboutDlg then aboutDlg.dismiss() end
    speak("Settings")
  end

  aboutDlg = createFullScreenDialog(view)
  speak("About and Support")
end

-- ==========================================
-- SETTINGS MENU SCREEN
-- ==========================================
local function openSettingsDialog()
  local settingsDlg = nil
  local ids = {}
  local layout = {
    LinearLayout,
    orientation = "vertical",
    layout_width = "fill",
    layout_height = "fill",
    padding = "14dp",
    backgroundColor = "#121212",
    {
      TextView,
      text = "Settings",
      textSize = "21sp",
      textColor = "#00E676",
      gravity = "center",
      layout_width = "fill",
      layout_height = "wrap",
      paddingBottom = "12dp"
    },
    {
      LinearLayout,
      orientation = "vertical",
      layout_width = "fill",
      layout_height = "0dp",
      layout_weight = "1",
      gravity = "center",
      {
        Button,
        id = "btnOpenReport",
        text = "Diagnostic Report",
        layout_width = "fill",
        layout_height = "wrap",
        layout_marginBottom = "10dp"
      },
      {
        Button,
        id = "btnOpenDesc",
        text = "Extension Description",
        layout_width = "fill",
        layout_height = "wrap",
        layout_marginBottom = "10dp"
      },
      {
        Button,
        id = "btnOpenAbout",
        text = "About & Support",
        layout_width = "fill",
        layout_height = "wrap"
      }
    },
    {
      Button,
      id = "btnSettingsBack",
      text = "Go Back",
      layout_width = "fill",
      layout_height = "wrap",
      layout_marginTop = "10dp"
    }
  }

  local view = loadlayout(layout, ids)

  ids.btnOpenReport.onClick = function()
    openReportDialog(settingsDlg)
  end

  ids.btnOpenDesc.onClick = function()
    openDescriptionDialog()
  end

  ids.btnOpenAbout.onClick = function()
    openAboutSupportDialog(settingsDlg)
  end

  ids.btnSettingsBack.onClick = function()
    if settingsDlg then settingsDlg.dismiss() end
    speak("Main screen")
  end

  settingsDlg = createFullScreenDialog(view)
  speak("Settings")
end

-- ==========================================
-- VOLUME PICKER (5% to 100%, 5% step)
-- ==========================================
local function openVolumePicker(currentPct, normalPct, onPicked)
  local items = {}
  local checkedIdx = 0
  local idx = 0
  for p = 5, 100, 5 do
    local label = tostring(p) .. "%"
    if p == normalPct then label = label .. " (Default)" end
    table.insert(items, label)
    if p == currentPct then checkedIdx = idx end
    idx = idx + 1
  end
  showChoiceDialog(items, checkedIdx, function(chosenIdx)
    onPicked(chosenIdx * 5)
  end)
end

-- ==========================================
-- AUDIO LIST LOADER & FULL-SCREEN PICKER
-- ==========================================
local function getAllAudioFiles()
  local list = {}
  local ok, err = pcall(function()
    local resolver = ctx.getContentResolver()
    local uri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
    local projection = {
      MediaStore.Audio.Media.DISPLAY_NAME,
      MediaStore.Audio.Media.DATA,
      MediaStore.Audio.Media.DURATION
    }
    local sortOrder = MediaStore.Audio.Media.DATE_MODIFIED .. " DESC"
    local cursor = resolver.query(uri, projection, nil, nil, sortOrder)
    if cursor then
      while cursor.moveToNext() do
        local name = cursor.getString(0)
        local path = cursor.getString(1)
        local dur = cursor.getLong(2)
        if path and File(path).exists() then
          table.insert(list, {
            name = name or File(path).getName(),
            path = path,
            duration = dur
          })
        end
      end
      cursor.close()
    end
  end)
  if not ok then addLog("Audio scan error: " .. tostring(err)) end
  return list
end

local function openAudioPicker(onSelected)
  local files = getAllAudioFiles()
  if #files == 0 then
    speak("No audio files found")
    toast("No audio files found")
    return
  end

  local selectedIndex = -1
  local pickerDialog = nil

  local pickerLayout = {
    LinearLayout,
    orientation = "vertical",
    layout_width = "fill",
    layout_height = "fill",
    padding = "10dp",
    backgroundColor = "#121212",
    {
      ListView,
      id = "audioListView",
      layout_width = "fill",
      layout_height = "0dp",
      layout_weight = "1",
      dividerHeight = "2dp"
    },
    {
      LinearLayout,
      orientation = "horizontal",
      layout_width = "fill",
      layout_height = "wrap",
      paddingTop = "8dp",
      {
        Button,
        id = "btnPickerCancel",
        text = "Cancel",
        layout_width = "0dp",
        layout_weight = "1",
        layout_height = "wrap"
      },
      {
        Button,
        id = "btnPickerDone",
        text = "Done",
        layout_width = "0dp",
        layout_weight = "1",
        layout_height = "wrap"
      }
    }
  }

  local ids = {}
  local view = loadlayout(pickerLayout, ids)

  local displayNames = {}
  for i = 1, #files do
    displayNames[i] = files[i].name .. " (" .. formatDuration(files[i].duration) .. ")"
  end

  local adapter = ArrayAdapter(ctx, android.R.layout.simple_list_item_1, displayNames)
  ids.audioListView.setAdapter(adapter)

  ids.audioListView.setOnItemClickListener(AdapterView.OnItemClickListener{
    onItemClick = function(parent, v, pos, id)
      local idx = pos + 1
      if selectedIndex ~= -1 and files[selectedIndex] then
        displayNames[selectedIndex] = files[selectedIndex].name .. " (" .. formatDuration(files[selectedIndex].duration) .. ")"
      end
      selectedIndex = idx
      displayNames[selectedIndex] = "Selected: " .. files[selectedIndex].name .. " (" .. formatDuration(files[selectedIndex].duration) .. ")"
      adapter.notifyDataSetChanged()

      stopPreview()
      local okPlay, errPlay = pcall(function()
        previewPlayer = MediaPlayer()
        previewPlayer.setDataSource(files[selectedIndex].path)
        previewPlayer.prepare()
        previewPlayer.start()
      end)
      if not okPlay then addLog("Preview error: " .. tostring(errPlay)) end
    end
  })

  ids.btnPickerCancel.onClick = function()
    stopPreview()
    if pickerDialog then pickerDialog.dismiss() end
    speak("Cancelled")
  end

  ids.btnPickerDone.onClick = function()
    stopPreview()
    if selectedIndex == -1 then
      speak("Please select an audio file first")
      return
    end
    local chosen = files[selectedIndex]
    if pickerDialog then pickerDialog.dismiss() end
    onSelected(chosen.path, chosen.name)
  end

  pickerDialog = createFullScreenDialog(view)
end

-- ==========================================
-- MAIN UI LAYOUT
-- Top: Extension Name + Status
-- Middle: Info / Progress / Duration
-- Bottom Row 1: Audio, BG Music, Voice 100%, Music 50%
-- Bottom Row 2: Ducking, Create, Settings, Close
-- ==========================================
local ui = {}
local mainLayout = {
  LinearLayout,
  orientation = "vertical",
  layout_width = "fill",
  layout_height = "fill",
  padding = "10dp",
  backgroundColor = "#121212",

  -- TOP HEADER (Name + Status)
  {
    TextView,
    text = EXT_NAME,
    textSize = "22sp",
    textColor = "#00E676",
    gravity = "center",
    layout_width = "fill",
    layout_height = "wrap",
    paddingTop = "6dp",
    paddingBottom = "4dp"
  },
  {
    TextView,
    id = "txtStatus",
    text = "Status: Ready",
    textSize = "16sp",
    textColor = "#FFFFFF",
    gravity = "center",
    focusable = true,
    focusableInTouchMode = true,
    layout_width = "fill",
    layout_height = "wrap",
    paddingBottom = "10dp"
  },

  -- MIDDLE AREA
  {
    LinearLayout,
    orientation = "vertical",
    layout_width = "fill",
    layout_height = "0dp",
    layout_weight = "1",
    gravity = "center",
    padding = "12dp",
    backgroundColor = "#1E1E1E",
    {
      TextView,
      id = "txtSelectedInfo",
      text = "Audio: None\nBG Music: None\nVoice: 100% | Music: 50%",
      textSize = "14sp",
      textColor = "#CCCCCC",
      gravity = "center",
      layout_width = "fill",
      layout_height = "wrap",
      paddingBottom = "12dp"
    },
    {
      TextView,
      id = "txtCenterProgress",
      text = "",
      textSize = "18sp",
      textColor = "#FFD54F",
      gravity = "center",
      layout_width = "fill",
      layout_height = "wrap",
      visibility = View.GONE,
      paddingBottom = "10dp"
    },
    {
      TextView,
      id = "txtDuration",
      text = "",
      textSize = "17sp",
      textColor = "#00E676",
      gravity = "center",
      layout_width = "fill",
      layout_height = "wrap",
      visibility = View.GONE
    }
  },

  -- BOTTOM BAR 1: MAIN CONTROLS (2 Rows x 4 Buttons)
  {
    LinearLayout,
    id = "mainControlsBox",
    orientation = "vertical",
    layout_width = "fill",
    layout_height = "wrap",
    paddingTop = "8dp",

    -- Row 1: Audio, BG Music, Voice Vol, Music Vol
    {
      LinearLayout,
      orientation = "horizontal",
      layout_width = "fill",
      layout_height = "wrap",
      {
        Button,
        id = "btnSelectAudio",
        text = "Audio",
        layout_width = "0dp",
        layout_weight = "1",
        layout_height = "wrap"
      },
      {
        Button,
        id = "btnSelectBg",
        text = "BG Music",
        layout_width = "0dp",
        layout_weight = "1",
        layout_height = "wrap"
      },
      {
        Button,
        id = "btnMainVol",
        text = "Voice 100%",
        layout_width = "0dp",
        layout_weight = "1",
        layout_height = "wrap"
      },
      {
        Button,
        id = "btnBgVol",
        text = "Music 50%",
        layout_width = "0dp",
        layout_weight = "1",
        layout_height = "wrap"
      }
    },

    -- Row 2: Audio Ducking, Create, Settings, Close
    {
      LinearLayout,
      orientation = "horizontal",
      layout_width = "fill",
      layout_height = "wrap",
      paddingTop = "4dp",
      {
        Button,
        id = "btnDucking",
        text = "Ducking",
        layout_width = "0dp",
        layout_weight = "1",
        layout_height = "wrap"
      },
      {
        Button,
        id = "btnGenerate",
        text = "Create",
        layout_width = "0dp",
        layout_weight = "1",
        layout_height = "wrap"
      },
      {
        Button,
        id = "btnSettings",
        text = "Settings",
        layout_width = "0dp",
        layout_weight = "1",
        layout_height = "wrap"
      },
      {
        Button,
        id = "btnClose",
        text = "Close",
        layout_width = "0dp",
        layout_weight = "1",
        layout_height = "wrap"
      }
    }
  },

  -- BOTTOM BAR 2: RESULT CONTROLS (Shown ONLY after 100% completion)
  {
    LinearLayout,
    id = "resultControlsBox",
    orientation = "vertical",
    layout_width = "fill",
    layout_height = "wrap",
    visibility = View.GONE,
    paddingTop = "8dp",
    {
      LinearLayout,
      orientation = "horizontal",
      layout_width = "fill",
      layout_height = "wrap",
      {
        Button,
        id = "btnPlayPause",
        text = "Play",
        layout_width = "0dp",
        layout_weight = "1",
        layout_height = "wrap"
      },
      {
        Button,
        id = "btnSave",
        text = "Save",
        layout_width = "0dp",
        layout_weight = "1",
        layout_height = "wrap"
      }
    },
    {
      LinearLayout,
      orientation = "horizontal",
      layout_width = "fill",
      layout_height = "wrap",
      paddingTop = "4dp",
      {
        Button,
        id = "btnShare",
        text = "Share",
        layout_width = "0dp",
        layout_weight = "1",
        layout_height = "wrap"
      },
      {
        Button,
        id = "btnResultClose",
        text = "Close",
        layout_width = "0dp",
        layout_weight = "1",
        layout_height = "wrap"
      }
    }
  }
}

local rootView = loadlayout(mainLayout, ui)

local function refreshSelectedInfo()
  ui.txtSelectedInfo.setText(
    "Audio: " .. mainAudioName ..
    "\nBG Music: " .. bgMusicName ..
    "\nVoice: " .. mainVolPct .. "% | Music: " .. bgVolPct .. "%"
  )
end

-- ==========================================
-- BUTTON EVENTS
-- ==========================================
ui.btnSelectAudio.onClick = function()
  if isProcessing then return end
  openAudioPicker(function(path, name)
    mainAudioPath = path
    mainAudioName = name
    refreshSelectedInfo()
    ui.txtStatus.setText("Status: Audio selected")
    speak("Audio selected")
  end)
end

ui.btnSelectBg.onClick = function()
  if isProcessing then return end
  openAudioPicker(function(path, name)
    bgMusicPath = path
    bgMusicName = name
    refreshSelectedInfo()
    ui.txtStatus.setText("Status: Background music selected")
    speak("Background music selected")
  end)
end

ui.btnMainVol.onClick = function()
  if isProcessing then return end
  openVolumePicker(mainVolPct, 100, function(pct)
    mainVolPct = pct
    ui.btnMainVol.setText("Voice " .. pct .. "%")
    refreshSelectedInfo()
    speak("Voice volume " .. pct .. " percent")
  end)
end

ui.btnBgVol.onClick = function()
  if isProcessing then return end
  openVolumePicker(bgVolPct, 50, function(pct)
    bgVolPct = pct
    ui.btnBgVol.setText("Music " .. pct .. "%")
    refreshSelectedInfo()
    speak("Music volume " .. pct .. " percent")
  end)
end

ui.btnDucking.onClick = function()
  if isProcessing then return end
  openDuckingSettingsDialog()
end

ui.btnSettings.onClick = function()
  if isProcessing then return end
  openSettingsDialog()
end

-- ==========================================
-- STRICT 5% STEP PROGRESS TRACKER (5, 10, 15 ... 95, 100)
-- ==========================================
local currentStepPct = 0
local function updateStepProgress(rawPct, msg)
  local snapped = math.floor(rawPct / 5) * 5
  if snapped > 95 then snapped = 95 end
  if snapped > currentStepPct then
    currentStepPct = snapped
    local txt = currentStepPct .. "% - " .. msg
    ui.txtStatus.setText("Status: " .. txt)
    ui.txtCenterProgress.setText("Processing: " .. currentStepPct .. "%\n" .. msg)
  end
end

-- ==========================================
-- FAST & SAFE AUTO-DUCKING ENGINE
-- (1.5s Intro + Custom Ducking/Silence/FadeDown/FadeUp + 1.5s Outro)
-- ==========================================
local function cleanupTemp()
  pcall(function() File(tempMainPcm).delete() end)
  pcall(function() File(tempBgPcm).delete() end)
end

local function decodeStepByStep(inPath, outPcmPath, pctStart, pctEnd, label, onFinished, onFailed)
  local extractor, codec, fos = nil, nil, nil

  local function closeAll()
    pcall(function() if fos then fos.flush(); fos.close() end end)
    pcall(function() if codec then codec.stop(); codec.release() end end)
    pcall(function() if extractor then extractor.release() end end)
  end

  local okInit, sr, ch, durUs = pcall(function()
    extractor = MediaExtractor()
    extractor.setDataSource(inPath)
    local trackIndex, format = -1, nil
    for i = 0, extractor.getTrackCount() - 1 do
      local f = extractor.getTrackFormat(i)
      local mime = f.getString(MediaFormat.KEY_MIME)
      if mime and mime:find("^audio/") then
        trackIndex, format = i, f
        break
      end
    end
    if trackIndex == -1 then error("Audio track not found") end

    extractor.selectTrack(trackIndex)
    local mime = format.getString(MediaFormat.KEY_MIME)
    local sRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
    local chans = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
    local dUs = 0
    pcall(function() dUs = format.getLong(MediaFormat.KEY_DURATION) end)

    codec = MediaCodec.createDecoderByType(mime)
    codec.configure(format, nil, nil, 0)
    codec.start()
    fos = FileOutputStream(outPcmPath)
    return sRate, chans, dUs
  end)

  if not okInit then
    closeAll()
    onFailed(tostring(sr))
    return
  end

  local info = MediaCodec.BufferInfo()
  local inEOS, outEOS = false, false
  local emptyLoops = 0
  local totalBytes = 0

  local function tick()
    if isCancelled then
      closeAll()
      cleanupTemp()
      return
    end

    local okTick, errTick = pcall(function()
      for step = 1, 14 do
        if outEOS then break end

        if not inEOS then
          local inIdx = codec.dequeueInputBuffer(1000)
          if inIdx >= 0 then
            local buf = codec.getInputBuffer(inIdx)
            local sz = extractor.readSampleData(buf, 0)
            if sz < 0 then
              codec.queueInputBuffer(inIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
              inEOS = true
            else
              local pts = extractor.getSampleTime()
              codec.queueInputBuffer(inIdx, 0, sz, pts, 0)
              extractor.advance()
              if durUs and durUs > 0 then
                local p = pctStart + math.floor((pts / durUs) * (pctEnd - pctStart))
                if p > pctEnd then p = pctEnd end
                updateStepProgress(p, label)
              end
            end
          end
        end

        local outIdx = codec.dequeueOutputBuffer(info, 1000)
        if outIdx >= 0 then
          emptyLoops = 0
          if info.size > 0 then
            local outBuf = codec.getOutputBuffer(outIdx)
            outBuf.position(info.offset)
            outBuf.limit(info.offset + info.size)
            local bytes = byte[info.size]
            outBuf.get(bytes)
            fos.write(bytes)
            totalBytes = totalBytes + info.size
          end
          codec.releaseOutputBuffer(outIdx, false)
          if (info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) ~= 0 then
            outEOS = true
          end
        else
          emptyLoops = emptyLoops + 1
          if inEOS and emptyLoops > 60 then
            outEOS = true
          end
        end
      end
    end)

    if not okTick then
      closeAll()
      onFailed(tostring(errTick))
      return
    end

    if outEOS then
      closeAll()
      if totalBytes == 0 then
        onFailed("Decoded audio is empty")
      else
        updateStepProgress(pctEnd, label)
        onFinished(totalBytes, sr, ch)
      end
    else
      mainHandler.postDelayed(Runnable{ run = tick }, 3)
    end
  end

  mainHandler.postDelayed(Runnable{ run = tick }, 3)
end

local function mixStepByStep(mBytes, mSr, mCh, bBytes, bSr, bCh)
  local mFile, bFile, outFile = nil, nil, nil

  local function closeFiles()
    pcall(function() if mFile then mFile:close() end end)
    pcall(function() if bFile then bFile:close() end end)
    pcall(function() if outFile then outFile:flush(); outFile:close() end end)
  end

  local okOpen, openErr = pcall(function()
    mFile = assert(io.open(tempMainPcm, "rb"))
    bFile = assert(io.open(tempBgPcm, "rb"))
    outFile = assert(io.open(tempOutPath, "wb"))
    outFile:write(string.rep("\0", 44))
  end)

  if not okOpen then
    closeFiles()
    cleanupTemp()
    isProcessing = false
    addLog("Mix open error: " .. tostring(openErr))
    ui.txtCenterProgress.setVisibility(View.GONE)
    ui.txtStatus.setText("Status: Error - " .. tostring(openErr))
    speak("Mixing error")
    return
  end

  -- Voice default 100% = 1.0x (clean, no distortion); Music default 50% = 1.0x
  local mGain = mainVolPct / 100.0
  local bGain = bgVolPct / 50.0
  local mFrameSize = mCh * 2
  local bFrameSize = bCh * 2
  local totalMainFrames = math.floor(mBytes / mFrameSize)

  local padFrames = math.floor(mSr * 1.5)
  local mainStartFrame = padFrames
  local mainEndFrame = padFrames + totalMainFrames
  local totalOutFrames = padFrames + totalMainFrames + padFrames

  local winMs = 25
  local winFrames = math.max(1, math.floor(mSr * (winMs / 1000.0)))
  local srRatio = bSr / mSr

  -- User-configured Ducking Parameters
  local threshold = 450
  local duckFloor = duckPct / 100.0
  local silenceWinCount = math.max(1, math.floor(silenceMs / winMs))
  local fadeDownStep = (1.0 - duckFloor) / math.max(1, fadeDownMs / winMs)
  local fadeUpStep = (1.0 - duckFloor) / math.max(1, fadeUpMs / winMs)

  local currentDuck = 1.0
  local holdWindows = 0
  local outFramePos = 0
  local writtenBytes = 0

  local function readBgChunk(framesCount)
    local bgFramesNeeded = math.max(1, math.floor(framesCount * srRatio))
    local needBgBytes = bgFramesNeeded * bFrameSize
    local bgParts = {}
    local gotBg = 0
    while gotBg < needBgBytes do
      local chunk = bFile:read(needBgBytes - gotBg)
      if not chunk or #chunk == 0 then
        bFile:seek("set", 0)
      else
        table.insert(bgParts, chunk)
        gotBg = gotBg + #chunk
      end
    end
    return table.concat(bgParts), bgFramesNeeded
  end

  local function mixTick()
    if isCancelled then
      closeFiles()
      cleanupTemp()
      return
    end

    local done = false
    local okMix, mixErr = pcall(function()
      for step = 1, 6 do
        if outFramePos >= totalOutFrames then
          done = true
          break
        end

        local framesHere = 0
        local mainSamples = {}
        local avgAmp = 0

        if outFramePos < mainStartFrame then
          framesHere = math.min(winFrames, mainStartFrame - outFramePos)
          for i = 1, framesHere do mainSamples[i] = 0 end
          avgAmp = 0
        elseif outFramePos < mainEndFrame then
          local remMain = mainEndFrame - outFramePos
          local wantFrames = math.min(winFrames, remMain)
          local mRaw = mFile:read(wantFrames * mFrameSize)
          if not mRaw or #mRaw < mFrameSize then
            outFramePos = mainEndFrame
            framesHere = 0
          else
            framesHere = math.floor(#mRaw / mFrameSize)
            local sumAbs = 0
            local mPos = 1
            for i = 1, framesHere do
              local s = string.unpack("<i2", mRaw, mPos)
              if mCh >= 2 then
                local s2 = string.unpack("<i2", mRaw, mPos + 2)
                s = math.floor((s + s2) * 0.5)
              end
              mainSamples[i] = s
              if s < 0 then sumAbs = sumAbs - s else sumAbs = sumAbs + s end
              mPos = mPos + mFrameSize
            end
            avgAmp = sumAbs / framesHere
          end
        else
          framesHere = math.min(winFrames, totalOutFrames - outFramePos)
          for i = 1, framesHere do mainSamples[i] = 0 end
          avgAmp = 0
        end

        if framesHere > 0 then
          local bRaw, bgFramesNeeded = readBgChunk(framesHere)

          if avgAmp > threshold then
            holdWindows = silenceWinCount
          elseif holdWindows > 0 then
            holdWindows = holdWindows - 1
          end

          if holdWindows > 0 then
            currentDuck = math.max(duckFloor, currentDuck - fadeDownStep)
          else
            currentDuck = math.min(1.0, currentDuck + fadeUpStep)
          end

          local bgScale = bGain * currentDuck
          local outChunk = {}
          for i = 1, framesHere do
            local bIdx = math.floor((i - 1) * srRatio)
            if bIdx >= bgFramesNeeded then bIdx = bgFramesNeeded - 1 end
            local bPos = (bIdx * bFrameSize) + 1

            local bs = string.unpack("<i2", bRaw, bPos)
            if bCh >= 2 then
              local bs2 = string.unpack("<i2", bRaw, bPos + 2)
              bs = math.floor((bs + bs2) * 0.5)
            end

            local mixed = (mainSamples[i] * mGain) + (bs * bgScale)
            if mixed > 32767 then mixed = 32767
            elseif mixed < -32768 then mixed = -32768 end
            outChunk[i] = string.pack("<i2", math.floor(mixed))
          end

          local chunkData = table.concat(outChunk)
          outFile:write(chunkData)
          writtenBytes = writtenBytes + #chunkData
          outFramePos = outFramePos + framesHere
        end
      end
    end)

    if not okMix then
      closeFiles()
      cleanupTemp()
      isProcessing = false
      addLog("Mix tick error: " .. tostring(mixErr))
      ui.txtCenterProgress.setVisibility(View.GONE)
      ui.txtStatus.setText("Status: Error - " .. tostring(mixErr))
      speak("Mixing error")
      return
    end

    if done then
      pcall(function()
        outFile:seek("set", 0)
        local byteRate = mSr * 2
        local header = string.pack(
          "<c4I4c4c4I4I2I2I4I4I2I2c4I4",
          "RIFF", writtenBytes + 36, "WAVE",
          "fmt ", 16, 1, 1, mSr, byteRate, 2, 16,
          "data", writtenBytes
        )
        outFile:write(header)
      end)
      closeFiles()
      cleanupTemp()
      isProcessing = false

      local totalSec = math.floor(outFramePos / mSr)
      local durStr = string.format("%02d:%02d", math.floor(totalSec / 60), totalSec % 60)
      currentStepPct = 100
      ui.txtStatus.setText("Status: 100% - Audio generated")
      ui.txtCenterProgress.setVisibility(View.GONE)
      ui.txtDuration.setText("Duration: " .. durStr)
      ui.txtDuration.setVisibility(View.VISIBLE)

      ui.mainControlsBox.setVisibility(View.GONE)
      ui.resultControlsBox.setVisibility(View.VISIBLE)

      speak("Audio generated")
    else
      local rawPct = 50 + math.floor((outFramePos / totalOutFrames) * 50)
      updateStepProgress(rawPct, "Applying audio ducking...")
      collectgarbage("step", 20)
      mainHandler.postDelayed(Runnable{ run = mixTick }, 3)
    end
  end

  mainHandler.postDelayed(Runnable{ run = mixTick }, 3)
end

-- ==========================================
-- CREATE BUTTON CLICK (Auto-Focus on Status)
-- ==========================================
ui.btnGenerate.onClick = function()
  if isProcessing then
    speak("Processing in progress")
    return
  end
  if not mainAudioPath or not bgMusicPath then
    speak("Please select both Audio and Background Music first")
    toast("Select both Audio and Background Music first")
    return
  end

  stopResultPlayer(ui.btnPlayPause)
  isProcessing = true
  isCancelled = false
  finalSavedUri = nil
  finalSavedPath = nil
  currentStepPct = 5

  ui.txtDuration.setVisibility(View.GONE)
  ui.resultControlsBox.setVisibility(View.GONE)
  ui.txtCenterProgress.setVisibility(View.VISIBLE)
  ui.txtStatus.setText("Status: 5% - Starting...")
  ui.txtCenterProgress.setText("Processing: 5%\nStarting...")

  focusViewForJieshuo(ui.txtStatus)
  speak("Processing started")

  local function onFail(err)
    cleanupTemp()
    isProcessing = false
    addLog("Decode fail: " .. tostring(err))
    ui.txtCenterProgress.setVisibility(View.GONE)
    ui.txtStatus.setText("Status: Error - " .. tostring(err))
    speak("Error generating audio")
  end

  decodeStepByStep(mainAudioPath, tempMainPcm, 5, 25, "Decoding main audio...", function(mBytes, mSr, mCh)
    decodeStepByStep(bgMusicPath, tempBgPcm, 25, 50, "Decoding background music...", function(bBytes, bSr, bCh)
      mixStepByStep(mBytes, mSr, mCh, bBytes, bSr, bCh)
    end, onFail)
  end, onFail)
end

-- ==========================================
-- PLAY / PAUSE SINGLE BUTTON
-- ==========================================
ui.btnPlayPause.onClick = function()
  if not File(tempOutPath).exists() then return end
  if isResultPlaying and resultPlayer then
    pcall(function() resultPlayer.pause() end)
    isResultPlaying = false
    ui.btnPlayPause.setText("Play")
    speak("Paused")
  else
    if not resultPlayer then
      local okP, errP = pcall(function()
        resultPlayer = MediaPlayer()
        resultPlayer.setDataSource(tempOutPath)
        resultPlayer.prepare()
        resultPlayer.setOnCompletionListener(MediaPlayer.OnCompletionListener{
          onCompletion = function(mp)
            isResultPlaying = false
            ui.btnPlayPause.setText("Play")
          end
        })
      end)
      if not okP then addLog("Result play error: " .. tostring(errP)) end
    end
    pcall(function()
      resultPlayer.start()
      isResultPlaying = true
      ui.btnPlayPause.setText("Pause")
    end)
  end
end

-- ==========================================
-- SAVE TO PHONE STORAGE (Android 16 MediaStore Safe)
-- ==========================================
local function saveToStorage()
  local resolver = ctx.getContentResolver()
  local timeStamp = SimpleDateFormat("yyyyMMdd_HHmmss").format(Date())
  local fileName = "Ducking_" .. timeStamp .. ".wav"

  local values = ContentValues()
  values.put(MediaStore.Audio.Media.DISPLAY_NAME, fileName)
  values.put(MediaStore.Audio.Media.MIME_TYPE, "audio/wav")
  values.put(MediaStore.Audio.Media.RELATIVE_PATH, "Music/AudioDucking")

  local uri = resolver.insert(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, values)
  if not uri then
    error("Failed to create file in MediaStore")
  end

  local outStream = resolver.openOutputStream(uri)
  local fis = FileInputStream(tempOutPath)
  local buf = byte[16384]
  local len = fis.read(buf)
  while len > 0 do
    outStream.write(buf, 0, len)
    len = fis.read(buf)
  end
  fis.close()
  outStream.flush()
  outStream.close()

  finalSavedUri = uri
  finalSavedPath = "Music/AudioDucking/" .. fileName
  return finalSavedUri, finalSavedPath
end

ui.btnSave.onClick = function()
  local ok, uriOrErr, savedPath = pcall(saveToStorage)
  if ok and uriOrErr then
    ui.txtStatus.setText("Status: Saved - " .. tostring(savedPath))
    speak("Audio saved")
    toast("Saved: " .. tostring(savedPath))
  else
    addLog("Save error: " .. tostring(uriOrErr))
    ui.txtStatus.setText("Status: Save Error - " .. tostring(uriOrErr))
    speak("Save failed")
  end
end

-- ==========================================
-- SHARE BUTTON (Close Extension + Content URI Share)
-- ==========================================
ui.btnShare.onClick = function()
  isCancelled = true
  stopPreview()
  stopResultPlayer(ui.btnPlayPause)

  if not finalSavedUri then
    local ok, uriOrErr = pcall(saveToStorage)
    if not ok or not uriOrErr then
      addLog("Share save error: " .. tostring(uriOrErr))
      toast("Failed to prepare file for sharing")
      speak("Share failed")
      return
    end
  end

  if mainDialog then mainDialog.dismiss() end

  local okShare, errShare = pcall(function()
    local shareIntent = Intent(Intent.ACTION_SEND)
    shareIntent.setType("audio/wav")
    shareIntent.putExtra(Intent.EXTRA_STREAM, finalSavedUri)
    shareIntent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)

    local chooser = Intent.createChooser(shareIntent, "Share Audio")
    chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    ctx.startActivity(chooser)
  end)

  if not okShare then
    addLog("Share intent error: " .. tostring(errShare))
    toast("Share error: " .. tostring(errShare))
  end
end

-- ==========================================
-- CLOSE EXTENSION (Both Main & Result Close)
-- ==========================================
local function closeExtension()
  isCancelled = true
  stopPreview()
  stopResultPlayer(ui.btnPlayPause)
  cleanupTemp()
  if mainDialog then mainDialog.dismiss() end
  speak("Closed")
end

ui.btnClose.onClick = closeExtension
ui.btnResultClose.onClick = closeExtension

-- ==========================================
-- SHOW MAIN FULL-SCREEN DIALOG
-- ==========================================
mainDialog = createFullScreenDialog(rootView)
speak(EXT_NAME)
