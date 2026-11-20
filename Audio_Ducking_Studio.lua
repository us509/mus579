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
  "What It Does:\n" ..
  "- Combines your main voice audio with any background music.\n" ..
  "- Automatically lowers background music whenever you speak, and smoothly raises it during pauses.\n" ..
  "- Adds a 1.5-second background music intro before your voice starts and a 1.5-second outro after your voice finishes.\n" ..
  "- Automatically loops background music if it is shorter than your main audio.\n\n" ..
  "How To Use:\n" ..
  "1. Tap Audio to choose your main voice recording (tap any file to preview and select, then tap Done).\n" ..
  "2. Tap BG Music to choose your background music track.\n" ..
  "3. Adjust Voice Volume and Music Volume from 5% to 100% (50% is Normal).\n" ..
  "4. Tap Create and wait for progress to reach 100%.\n" ..
  "5. Once finished, use Play/Pause to listen, Save to store in Music/AudioDucking, or Share directly to WhatsApp and other apps."

-- ==========================================
-- HELPERS
-- ==========================================
local function speak(msg)
  pcall(function()
    if service and service.speak then
      service.speak(msg)
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

-- ==========================================
-- STATE VARIABLES
-- ==========================================
local mainAudioPath = nil
local mainAudioName = "None"
local bgMusicPath = nil
local bgMusicName = "None"

local mainVolPct = 50 -- 50% = Normal
local bgVolPct = 50   -- 50% = Normal

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
      text = "Description",
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
    speak("Settings menu")
  end

  descDlg = createFullScreenDialog(view)
  speak("Description")
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
      local clip = ClipData.newPlainText("WhatsApp", WHATSAPP_LOCAL)
      cm.setPrimaryClip(clip)
    end)
    speak("WhatsApp number copy ho gaya")
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
    speak("Settings menu")
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
local function openVolumePicker(currentPct, onPicked)
  local items = {}
  local checkedIdx = 0
  local idx = 0
  for p = 5, 100, 5 do
    local label = tostring(p) .. "%"
    if p == 50 then label = label .. " (Normal)" end
    table.insert(items, label)
    if p == currentPct then checkedIdx = idx end
    idx = idx + 1
  end

  local builder = AlertDialog.Builder(ctx)
  builder.setSingleChoiceItems(items, checkedIdx, DialogInterface.OnClickListener{
    onClick = function(dialog, which)
      local chosenPct = (which + 1) * 5
      dialog.dismiss()
      onPicked(chosenPct)
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
-- AUDIO LIST LOADER & FULL-SCREEN PICKER
-- ==========================================
local function getAllAudioFiles()
  local list = {}
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
  return list
end

local function openAudioPicker(onSelected)
  local files = getAllAudioFiles()
  if #files == 0 then
    speak("Phone storage mein koi audio file nahi mili")
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
      pcall(function()
        previewPlayer = MediaPlayer()
        previewPlayer.setDataSource(files[selectedIndex].path)
        previewPlayer.prepare()
        previewPlayer.start()
      end)
    end
  })

  ids.btnPickerCancel.onClick = function()
    stopPreview()
    if pickerDialog then pickerDialog.dismiss() end
    speak("Cancel")
  end

  ids.btnPickerDone.onClick = function()
    stopPreview()
    if selectedIndex == -1 then
      speak("Pehle koi audio select karein")
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
-- Bottom: Main Controls OR Result Controls (Play/Save/Share/Close)
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
      text = "Audio: None\nBG Music: None\nVoice: 50% | Music: 50%",
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

  -- BOTTOM BAR 1: MAIN CONTROLS (Hidden after generation completes)
  {
    LinearLayout,
    id = "mainControlsBox",
    orientation = "vertical",
    layout_width = "fill",
    layout_height = "wrap",
    paddingTop = "8dp",

    -- Row 1: Audio, BG Music, Settings
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
        id = "btnSettings",
        text = "Settings",
        layout_width = "0dp",
        layout_weight = "1",
        layout_height = "wrap"
      }
    },

    -- Row 2: Voice Vol, Music Vol, Create, Close
    {
      LinearLayout,
      orientation = "horizontal",
      layout_width = "fill",
      layout_height = "wrap",
      paddingTop = "4dp",
      {
        Button,
        id = "btnMainVol",
        text = "Voice 50%",
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
    ui.txtStatus.setText("Status: Audio select ho gayi")
    speak("Audio select ho gayi")
  end)
end

ui.btnSelectBg.onClick = function()
  if isProcessing then return end
  openAudioPicker(function(path, name)
    bgMusicPath = path
    bgMusicName = name
    refreshSelectedInfo()
    ui.txtStatus.setText("Status: Background music select ho gaya")
    speak("Background music select ho gaya")
  end)
end

ui.btnSettings.onClick = function()
  if isProcessing then return end
  openSettingsDialog()
end

ui.btnMainVol.onClick = function()
  if isProcessing then return end
  openVolumePicker(mainVolPct, function(pct)
    mainVolPct = pct
    ui.btnMainVol.setText("Voice " .. pct .. "%")
    refreshSelectedInfo()
    speak("Audio voice volume " .. pct .. " percent")
  end)
end

ui.btnBgVol.onClick = function()
  if isProcessing then return end
  openVolumePicker(bgVolPct, function(pct)
    bgVolPct = pct
    ui.btnBgVol.setText("Music " .. pct .. "%")
    refreshSelectedInfo()
    speak("Background music volume " .. pct .. " percent")
  end)
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
-- IMPROVED AUTO-DUCKING ENGINE
-- (1.5s Intro + 25ms Snappy Ducking + 1.5s Outro)
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
    if trackIndex == -1 then error("Audio track nahi mila") end

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
      for step = 1, 10 do
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
        onFailed("Audio decode khali rahi")
      else
        updateStepProgress(pctEnd, label)
        onFinished(totalBytes, sr, ch)
      end
    else
      mainHandler.postDelayed(Runnable{ run = tick }, 5)
    end
  end

  mainHandler.postDelayed(Runnable{ run = tick }, 5)
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
    ui.txtCenterProgress.setVisibility(View.GONE)
    ui.txtStatus.setText("Status: Error - " .. tostring(openErr))
    speak("Mixing shuru karne mein masla aaya")
    return
  end

  local mGain = mainVolPct / 50.0
  local bGain = bgVolPct / 50.0
  local mFrameSize = mCh * 2
  local bFrameSize = bCh * 2
  local totalMainFrames = math.floor(mBytes / mFrameSize)

  local padFrames = math.floor(mSr * 1.5)
  local mainStartFrame = padFrames
  local mainEndFrame = padFrames + totalMainFrames
  local totalOutFrames = padFrames + totalMainFrames + padFrames

  local winFrames = math.max(1, math.floor(mSr * 0.025))
  local srRatio = bSr / mSr

  local threshold = 450
  local duckFloor = 0.15
  local currentDuck = 1.0
  local attackRate = 0.65
  local releaseRate = 0.18
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
      for step = 1, 4 do
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
            holdWindows = 8
          elseif holdWindows > 0 then
            holdWindows = holdWindows - 1
          end

          local targetDuck = (holdWindows > 0) and duckFloor or 1.0
          if targetDuck < currentDuck then
            currentDuck = currentDuck + (targetDuck - currentDuck) * attackRate
          else
            currentDuck = currentDuck + (targetDuck - currentDuck) * releaseRate
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
      ui.txtCenterProgress.setVisibility(View.GONE)
      ui.txtStatus.setText("Status: Error - " .. tostring(mixErr))
      speak("Mixing mein masla aaya")
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
      ui.txtStatus.setText("Status: 100% - Audio mukammal ho gayi!")
      ui.txtCenterProgress.setVisibility(View.GONE)
      ui.txtDuration.setText("Ready Audio - Duration: " .. durStr)
      ui.txtDuration.setVisibility(View.VISIBLE)

      -- Hide main buttons and show ONLY Play/Pause, Save, Share, Close at bottom
      ui.mainControlsBox.setVisibility(View.GONE)
      ui.resultControlsBox.setVisibility(View.VISIBLE)

      speak("100 percent, audio ban gayi hai, duration " .. durStr)
    else
      local rawPct = 50 + math.floor((outFramePos / totalOutFrames) * 50)
      updateStepProgress(rawPct, "Audio ducking...")
      collectgarbage("step", 20)
      mainHandler.postDelayed(Runnable{ run = mixTick }, 5)
    end
  end

  mainHandler.postDelayed(Runnable{ run = mixTick }, 5)
end

-- ==========================================
-- CREATE BUTTON CLICK (Auto-Focus on Status)
-- ==========================================
ui.btnGenerate.onClick = function()
  if isProcessing then
    speak("Processing chal rahi hai")
    return
  end
  if not mainAudioPath or not bgMusicPath then
    speak("Pehle Audio aur Background Music dono select karein")
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
  ui.txtStatus.setText("Status: 5% - Shuru ho raha hai...")
  ui.txtCenterProgress.setText("Processing: 5%\nShuru ho raha hai...")

  focusViewForJieshuo(ui.txtStatus)
  speak("Processing shuru ho gayi hai")

  local function onFail(err)
    cleanupTemp()
    isProcessing = false
    ui.txtCenterProgress.setVisibility(View.GONE)
    ui.txtStatus.setText("Status: Error - " .. tostring(err))
    speak("Audio banane mein masla aaya")
  end

  decodeStepByStep(mainAudioPath, tempMainPcm, 5, 25, "Main audio decode...", function(mBytes, mSr, mCh)
    decodeStepByStep(bgMusicPath, tempBgPcm, 25, 50, "Background music decode...", function(bBytes, bSr, bCh)
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
    speak("Pause")
  else
    if not resultPlayer then
      pcall(function()
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
    error("MediaStore mein file create nahi ho saki")
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
    speak("Audio phone storage mein save ho gayi hai")
    toast("Saved: " .. tostring(savedPath))
  else
    ui.txtStatus.setText("Status: Save Error - " .. tostring(uriOrErr))
    speak("Save karne mein masla aaya")
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
      toast("File save/share mein masla aaya")
      speak("Share karne mein masla aaya")
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
  speak("Extension close ho gayi")
end

ui.btnClose.onClick = closeExtension
ui.btnResultClose.onClick = closeExtension

-- ==========================================
-- SHOW MAIN FULL-SCREEN DIALOG
-- ==========================================
mainDialog = createFullScreenDialog(rootView)
speak(EXT_NAME .. " open ho gaya")