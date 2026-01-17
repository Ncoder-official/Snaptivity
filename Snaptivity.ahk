; A
#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook

ProcessSetPriority("High")

; Close existing CONTROL PANEL if any
DetectHiddenWindows(true)
if WinExist("Snaptivity CONTROL PANEL") {
    WinKill()
}


; ======================================================
; GLOBAL STATE
; ======================================================

global szodActive := false
global toggleKey := ""

; Physical key states
global physicalKeys := Map("w", false, "a", false, "s", false, "d", false) ; This stayed since the dinasours because it was the begining

; Split lane channels
global currentSOD_H := ""   ; a / d
global currentSOD_V := ""   ; w / s

; Unified channel
global currentSOD_All := ""

; Picker GUI state (Snaptivity toggle)
global pickerGui := ""
global statusText := ""
global goBtn := ""
global pickedKey := ""

global ncoderMode := false
global osdLetters := []
global osdColors  := []
global gradientTimerRunning := false
global cbNcoder := ""

; Picker GUI state (Menu toggle)
global menuPickerGui := ""
global menuStatusText := ""
global menuGoBtn := ""
global menuPickedKey := ""

; Absolute priority keys
global absUnifiedKey := ""
global absSplitHKey := ""
global absSplitVKey := ""

; Menu Gui
global menuGui := ""

; Engine latency profiler
global traceLatency := false
global latencySum := 0
global latencyCount := 0
global lastLatency := 0
global t0 := 0
global latencyAvg := 0

; Int Crash
global intentionalCrash := false

OnError(HandleIntentionalCrash)

HandleIntentionalCrash(e, mode) {
    global intentionalCrash

    if (intentionalCrash) {
        ; swallow error window completely
        return true   ; tells AHK: "handled, don’t show error dialog"
    }

    ; otherwise allow normal AHK error popup
    return false
}

; Latency OSD position offsets
global latencyOffsetX := 0   ; move left/right
global latencyOffsetY := 4   ; move up/down (positive = lower)

; ===== Drag System =====
global isDragging   := false
global dragGui := ""
global dragStartX := 0
global dragStartY := 0
global dragThreshold := 4
global dragArmed := false
global dragTitleHwnd := 0

OnMessage(0x201, WM_LBUTTONDOWN) ; left button down
OnMessage(0x202, WM_LBUTTONUP)   ; left button up
OnMessage(0x201, WM_LBUTTONDOWN) ; WM_LBUTTONDOWN = 0x201

; block physicalKeys
global blockPhysical := false

;special
global isResettingKey := false

;OSD helper (Universal)
global editOsdGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
editOsdGui.BackColor := "000000"
WinSetTransColor("000000", editOsdGui)
editOsdGui.SetFont("s12 Bold", "Segoe UI")

; Fixed window size (wide enough for long text)
editOsdGui.Show("Hide w700 h60")

global editOsdText := editOsdGui.AddText(
    "x10 y10 w680 h40 c00FFAA Center",
    ""
)
ShowEditOSD(msg, color := "00FFAA", duration := 4000) {
    global editOsdGui, editOsdText

    editOsdText.Text := msg
    editOsdText.Opt("c" color)

    ; Show first (keeps its original X position)
    editOsdGui.Show("NoActivate")

    ; Get current position
    editOsdGui.GetPos(&x, &y, &w, &h)

    ; Move it UP only
    y -= 120   ; adjust this value for how high you want it

    editOsdGui.Move(x, y)

    SetTimer(() => editOsdGui.Hide(), -duration)
}

;Overrides
    ; Override modes:
; 1 = Last input wins (default)
; 2 = First input wins
; 3 = Disable input on override
; 4 = Absolute priority on one selected key (NEW)
global overrideMode := 1
;snappy mode
global snappyMode := true  ; true = raw overlap, false = intent-based
global trulySnappy := false ; didnt want to rewrite the boolean based conflict detection so just 2 strings now
;traytip
global trayTipsEnabled := true
;tooltip
global toolTipMap := Map()
global lastTTCtrl := ""
; Globalize this or wont run
global cbDebug := ""
global cbSnappy := ""
; Core folder
global CoreDir := A_ScriptDir "\Core"

if !DirExist(CoreDir)
    DirCreate(CoreDir)

; crash isnide CoreDir
global CrashBaseDir := CoreDir "\crashes"
global CrashRecoveredDir := CrashBaseDir "\History"
global CrashFailedDir := CrashBaseDir "\Current"

for dir in [CrashBaseDir, CrashRecoveredDir, CrashFailedDir] {
    if !DirExist(dir)
        DirCreate(dir)
}

; Lcrash
global LastCrashError := ""
OnError(CaptureCrashError)

global Safemod := true   ; true = supervision ON, false = UNCHAINED

global suppressOSD := false

global gradientTarget := "osd"   ; "osd" or "ncoder"

; add traytip for traytipcooldown for for for for for fro watchdog
global trayTipCooldown := false

OnMessage(0x200, WM_MOUSEMOVE)  ; 0x200 = WM_MOUSEMOVE

WM_MOUSEMOVE(wParam, lParam, msg, hwnd) {
    global toolTipMap, lastTTCtrl
    global dragArmed, dragStartX, dragStartY, dragThreshold, dragGui

    ; ======================
    ; TOOLTIP SYSTEM
    ; ======================
    MouseGetPos(, , &win, &ctrlHwnd, 2)

    if toolTipMap.Has(ctrlHwnd) {
        if (lastTTCtrl != ctrlHwnd) {
            ToolTip(toolTipMap[ctrlHwnd])
            lastTTCtrl := ctrlHwnd
        }
    } else {
        ToolTip()
        lastTTCtrl := ""
    }

    ; ======================
    ; DRAG SYSTEM (MERGED)
    ; ======================
    if (!dragArmed)
        return

    if (!GetKeyState("LButton", "P")) {
        dragArmed := false
        return
    }

    MouseGetPos(&x, &y)
    dx := Abs(x - dragStartX)
    dy := Abs(y - dragStartY)

    if (dx > dragThreshold || dy > dragThreshold) {
        PostMessage(0xA1, 2,,, dragGui.Hwnd) ; WM_NCLBUTTONDOWN, HTCAPTION
        dragArmed := false
    }
}


; ======================================================
; MENU TOGGLES
; ======================================================

global neutralizeMode := false
global debugOverlay := 0
global menuToggleKey := ""
global splitLanes := true   ; true = WS and AD separate, false = unified

; HUD positioning / sizing adjust mode
global hudX := 40
global hudY := 220
global adjustingHud := false

; ======================================================
; REAL WASD HUD (GAMER STYLE)
; ======================================================

fontScale := 0.45

keySize := 46
gap := 8

global debugGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
debugGui.BackColor := "000000"
WinSetTransColor("000000", debugGui)
debugGui.SetFont("s" Round(keySize * fontScale) " Bold", "Segoe UI")

global hudW := debugGui.AddText("w" keySize " h" keySize " Center Border c444444", "W")
global hudA := debugGui.AddText("w" keySize " h" keySize " Center Border c444444", "A")
global hudS := debugGui.AddText("w" keySize " h" keySize " Center Border c444444", "S")
global hudD := debugGui.AddText("w" keySize " h" keySize " Center Border c444444", "D")

; Layout
hudW.Move(keySize + gap, 0)
hudA.Move(0, keySize + gap)
hudS.Move(keySize + gap, keySize + gap)
hudD.Move((keySize + gap) * 2, keySize + gap)

; Fix window cropping + add padding so borders are never cut
; Add GUI margins (inner padding)
debugGui.MarginX := 4
debugGui.MarginY := 4

; Increase window size slightly to account for borders
hudWidth  := (keySize + gap) * 3 - gap + 8
hudHeight := (keySize + gap) * 2 - gap + 8

debugGui.Show("w" hudWidth " h" hudHeight " NoActivate x" hudX " y" hudY)
debugGui.Hide()

; ======================================================
; HUD REFRESH
; ======================================================

UpdateDebugOSD() {
    global debugOverlay, debugGui, physicalKeys, szodActive, splitLanes
    global hudW, hudA, hudS, hudD, hudX, hudY
    global currentSOD_H, currentSOD_V, currentSOD_All

    if (!debugOverlay) {
        debugGui.Hide()
        return
    }

    SnaptivityColor := "00FFFF"   ; cyan
    physColor       := "00FF00"   ; green
    idleColor       := "333333"   ; dark gray

    ; =========================
    ; BASE LAYER
    ; =========================
    if (debugOverlay = 1 || debugOverlay = 3) {
        ; Physical mode
        hudW.Opt("c" (physicalKeys["w"] ? physColor : idleColor))
        hudA.Opt("c" (physicalKeys["a"] ? physColor : idleColor))
        hudS.Opt("c" (physicalKeys["s"] ? physColor : idleColor))
        hudD.Opt("c" (physicalKeys["d"] ? physColor : idleColor))
    }
    else {
        ; Logical-only base → idle background
        hudW.Opt("c" idleColor)
        hudA.Opt("c" idleColor)
        hudS.Opt("c" idleColor)
        hudD.Opt("c" idleColor)
    }

    ; =========================
    ; LOGICAL LAYER
    ; =========================
    if (debugOverlay = 2 || debugOverlay = 3) {
        if (szodActive) {
            if (splitLanes) {
                if (currentSOD_V = "w")
                    hudW.Opt("c" SnaptivityColor)
                if (currentSOD_V = "s")
                    hudS.Opt("c" SnaptivityColor)

                if (currentSOD_H = "a")
                    hudA.Opt("c" SnaptivityColor)
                if (currentSOD_H = "d")
                    hudD.Opt("c" SnaptivityColor)
            }
            else {
                if (currentSOD_All = "w")
                    hudW.Opt("c" SnaptivityColor)
                if (currentSOD_All = "a")
                    hudA.Opt("c" SnaptivityColor)
                if (currentSOD_All = "s")
                    hudS.Opt("c" SnaptivityColor)
                if (currentSOD_All = "d")
                    hudD.Opt("c" SnaptivityColor)
            }
        }
    }
    ; =========================
    ; 🥚 EASTER EGG MODE
    ; Hold W + A + S + D together → GOD MODE PURPLE HUD
    ; =========================
    eggColor := "FF00FF"  ; purple chaos energy

    if (physicalKeys["w"] && physicalKeys["a"] && physicalKeys["s"] && physicalKeys["d"]) {
        hudW.Opt("c" eggColor)
        hudA.Opt("c" eggColor)
        hudS.Opt("c" eggColor)
        hudD.Opt("c" eggColor)
    }


    debugGui.Show("NoActivate x" hudX " y" hudY)
    StickLatencyToHud()
}
GetDebugOSD() {
    global physicalKeys, currentSOD_H, currentSOD_V, currentSOD_All, debugOverlay, splitLanes, szodActive

    state := Map()

    ; raw physical
    state["physical"] := Map(
        "w", physicalKeys["w"],
        "a", physicalKeys["a"],
        "s", physicalKeys["s"],
        "d", physicalKeys["d"]
    )

    ; logical ownership
    state["logical"] := Map(
        "H", currentSOD_H,
        "V", currentSOD_V,
        "A", currentSOD_All
    )

    ; mode flags
    state["engine"] := Map(
        "Snaptivity", szodActive,
        "SplitLanes", splitLanes,
        "OverlayMode", debugOverlay
    )

    return state
}


; ===== LATENCY OSD =====
global latencyGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
latencyGui.BackColor := "000000"
WinSetTransColor("000000", latencyGui)

; small font, compact, readable
latencyGui.SetFont("s9 Bold", "Segoe UI")

global latencyText := latencyGui.AddText(
    "w220 Center c00FF9C",
    ""
)
UpdateLatencyOSD() {
    global traceLatency, latencyCount, latencyAvg, lastLatency
    global latencyGui, latencyText

    if (!traceLatency || latencyCount = 0) {
        latencyGui.Hide()
        return
    }

    latencyText.Text :=
        "⚡ " lastLatency " ms | Avg " Round(latencyAvg, 3) " ms | N " latencyCount

    StickLatencyToHud()
}





latencyGui.Show("Hide")




configDir := A_ScriptDir "\config"
configFile := configDir "\Snaptivity.ini"

InitConfig() {
    global configDir, configFile

    if !DirExist(configDir)
        DirCreate(configDir)

    if !FileExist(configFile) {
        IniWrite("", configFile, "Keys", "Snaptivity_Toggle")
        IniWrite("", configFile, "Keys", "Menu_Toggle")
        IniWrite(0, configFile, "Settings", "NeutralizeMode")
        IniWrite(1, configFile, "Settings", "SplitLanes")
        IniWrite(0, configFile, "Settings", "DebugOverlay")
        IniWrite(40, configFile, "HUD", "X")
        IniWrite(220, configFile, "HUD", "Y")
        IniWrite(46, configFile, "HUD", "KeySize")
        IniWrite(1, configFile, "Settings", "SnappyMode")
        IniWrite(1, configFile, "Settings", "TrayTips")
        IniWrite("", configFile, "AbsolutePriority", "Unified")
        IniWrite("", configFile, "AbsolutePriority", "SplitH")
        IniWrite("", configFile, "AbsolutePriority", "SplitV")
        IniWrite(0, configFile, "Advanced-Settings", "BlockPhysical")
        IniWrite(0, configFile, "Advanced-Settings", "TraceLatency")
        IniWrite(0, configFile, "HUD", "LatencyOffsetX")
        IniWrite(4, configFile, "HUD", "LatencyOffsetY")
        IniWrite(1, configFile, "Settings", "SnappyMode")
        IniWrite(0, configFile, "Settings", "TrulySnappy")
        IniWrite(0, configFile, "Fun", "NcoderMode")
        IniWrite(1, configFile, "Advanced-Settings", "Safemod")
    }
}

SaveConfig() {
    global toggleKey, menuToggleKey, neutralizeMode, splitLanes, debugOverlay
    global hudX, hudY, keySize, snappyMode, trayTipsEnabled
    global absUnifiedKey, absSplitHKey, absSplitVKey
    global traceLatency, latencyOffsetX, latencyOffsetY
    global trulySnappy, blockPhysical, ncoderMode, Safemod


    IniWrite(toggleKey, configFile, "Keys", "Snaptivity_Toggle")
    IniWrite(menuToggleKey, configFile, "Keys", "Menu_Toggle")
    IniWrite(neutralizeMode, configFile, "Settings", "NeutralizeMode")
    IniWrite(splitLanes, configFile, "Settings", "SplitLanes")
    IniWrite(debugOverlay, configFile, "Settings", "DebugOverlay")
    IniWrite(hudX, configFile, "HUD", "X")
    IniWrite(hudY, configFile, "HUD", "Y")
    IniWrite(keySize, configFile, "HUD", "KeySize")
    IniWrite(snappyMode, configFile, "Settings", "SnappyMode")
    IniWrite(trayTipsEnabled, configFile, "Settings", "TrayTips")
    IniWrite(absUnifiedKey, configFile, "AbsolutePriority", "Unified")
    IniWrite(absSplitHKey,  configFile, "AbsolutePriority", "SplitH")
    IniWrite(absSplitVKey,  configFile, "AbsolutePriority", "SplitV")
    IniWrite(blockPhysical, configFile, "Advanced-Settings", "BlockPhysical")
    IniWrite(traceLatency, configFile, "Advanced-Settings", "TraceLatency")
    IniWrite(latencyOffsetX, configFile, "HUD", "LatencyOffsetX")
    IniWrite(latencyOffsetY, configFile, "HUD", "LatencyOffsetY")
    IniWrite(trulySnappy, configFile, "Settings", "TrulySnappy")
    IniWrite(ncoderMode, configFile, "Fun", "NcoderMode")
    IniWrite(Safemod, configFile, "Advanced-Settings", "Safemod")
}

LoadConfig() {
    global toggleKey, menuToggleKey
    global neutralizeMode, splitLanes, debugOverlay
    global hudX, hudY, keySize
    global snappyMode, trayTipsEnabled, blockPhysical
    global absUnifiedKey, absSplitHKey, absSplitVKey
    global traceLatency, latencyOffsetX, latencyOffsetY
    global trulySnappy, ncoderMode, Safemod

    toggleKey       := IniLoadD("Keys", "Snaptivity_Toggle", "", "string")
    menuToggleKey   := IniLoadD("Keys", "Menu_Toggle", "", "string")

    neutralizeMode  := IniLoadD("Settings", "NeutralizeMode", 0, "bool")
    splitLanes      := IniLoadD("Settings", "SplitLanes", 1, "bool")
    debugOverlay    := IniLoadD("Settings", "DebugOverlay", 0, "int")

    snappyMode      := IniLoadD("Settings", "SnappyMode", 1, "bool")
    trayTipsEnabled := IniLoadD("Settings", "TrayTips", 1, "bool")
    blockPhysical   := IniLoadD("Advanced-Settings", "BlockPhysical", 0, "bool")

    hudX := IniLoadD("HUD", "X", 40, "int")
    hudY := IniLoadD("HUD", "Y", 220, "int")
    keySize := IniLoadD("HUD", "KeySize", 46, "int")

    absUnifiedKey := IniLoadD("AbsolutePriority", "Unified", "", "string")
    absSplitHKey  := IniLoadD("AbsolutePriority", "SplitH", "", "string")
    absSplitVKey  := IniLoadD("AbsolutePriority", "SplitV", "", "string")

    traceLatency := IniLoadD("Advanced-Settings", "TraceLatency", 0, "bool")

    latencyOffsetX := IniLoadD("HUD", "LatencyOffsetX", 0, "int")
    latencyOffsetY := IniLoadD("HUD", "LatencyOffsetY", 4, "int")

    trulySnappy := IniLoadD("Settings", "TrulySnappy", 0, "bool")

    ncoderMode := IniLoadD("Fun", "NcoderMode", 0, "bool")

    Safemod := IniLoadD("Advanced-Settings", "Safemod", 0, "bool")

    ; FORCE ENGINE STATE BEFORE UI EXISTS
    if (trulySnappy)
        EnableEngineOverclock()
    else
        DisableEngineOverclock()

    return (toggleKey != "" && menuToggleKey != "")
}

; ======================================================
; Snaptivity STATUS OSD (TOP TEXT)
; ======================================================

global osdGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
osdGui.BackColor := "000000"
WinSetTransColor("000000", osdGui)
osdGui.SetFont("s13 Bold", "Segoe UI")

global osdText := osdGui.AddText("c00FF00", "Snaptivity: OFF")

UpdateOSD() {
    global szodActive, osdGui, osdText, ncoderMode

    if (szodActive) {
        if (ncoderMode) {
            osdText.Visible := false
            for txt in osdLetters
                txt.Visible := true

            osdGui.Show("NoActivate")
            StartGradientOSD()
        } else {
            StopGradientOSD()
            for txt in osdLetters                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              ; Hi
                txt.Visible := false

            osdText.Visible := true
            osdText.Text := "Snaptivity: ON"
            osdText.Opt("c" GetRandomSafeColor())
            osdGui.Show("NoActivate")
        }
    } else {
        StopGradientOSD()
        for txt in osdLetters
            txt.Visible := false

        osdText.Visible := true
        osdText.Text := "Snaptivity: OFF"
        osdText.Opt("cFF3333")
        osdGui.Show("NoActivate")
    }


    SetTimer(HideOSD, 0)
    SetTimer(HideOSD, -2000)
}



HideOSD() {
    global osdGui
    osdGui.Hide()
}

GetRandomSafeColor() {
    ; Avoid red / orange rage colors
    ; Using bright cyber colors only
    colors := [
        "00FFFF", ; cyan
        "00FFAF", ; spring blue
        "00FFAA", ; aqua green
        "66FF66", ; neon green
        "3399FF", ; electric blue
        "9966FF", ; purple
        "FF66FF", ; pink neon
        "66FFFF", ; ice blue
        "33FFCC", ; mint
        "6699FF"  ; soft blue
        "FF66CC"  ; magenta
        "FF99CC"  ; light pink
    ]

    r := Random(1, colors.Length)
    return colors[r]
}

; ======================================================
; START
; ======================================================

if (A_IsCompiled) {
    SetWorkingDir(A_ScriptDir "\..")
} else {
    SetWorkingDir(A_ScriptDir)
}

InitConfig()
LoadConfig()
ApplySnappyState()
CreateGradientOSD()
SetTimer(() => MarkLastCrashRecovered(), -3000)

if (toggleKey != "" && menuToggleKey != "") {
    Hotkey("$" toggleKey, (*) => ToggleSZOD())
    Hotkey("$" menuToggleKey, (*) => ShowMenu())
    UpdateDebugOSD()
    UpdateOSD()
    ShowTrayTip("Snaptivity SCRIPT", "⚡ Config loaded from /config/Snaptivity.ini", 2000)
} else {
    ShowTogglePicker()
    UpdateDebugOSD()
    UpdateLatencyOSD()
}
SetTimer(ForceHUDRedraw, 1000)
SetTimer(ForceAlwaysOnTop, 1000)

; ======================================================
; HOTKEYS (PHYSICAL CAPTURE)
; ======================================================

; Horizontal
~*a::HandleSOD_H("a", true)
~*d::HandleSOD_H("d", true)
~*a up::HandleSOD_H("a", false)
~*d up::HandleSOD_H("d", false)

; Vertical
~*w::HandleSOD_V("w", true)
~*s::HandleSOD_V("s", true)
~*w up::HandleSOD_V("w", false)
~*s up::HandleSOD_V("s", false)

; ======================================================
; HOTKEYS (BLOCKED PHYSICAL)
; ======================================================

#HotIf (szodActive && blockPhysical)

; Horizontal
*a::HandleSOD_H("a", true)
*d::HandleSOD_H("d", true)
*a up::HandleSOD_H("a", false)
*d up::HandleSOD_H("d", false)

; Vertical
*w::HandleSOD_V("w", true)
*s::HandleSOD_V("s", true)
*w up::HandleSOD_V("w", false)
*s up::HandleSOD_V("s", false)

#HotIf

; ========================================================= (haha)
; Snaptivity TOGGLE
; ======================================================

ToggleSZOD(*) {
    global szodActive, currentSOD_H, currentSOD_V, currentSOD_All

    szodActive := !szodActive
    UpdateOSD()

    if (!szodActive) {
        if (currentSOD_H != "")
            TraceSend("{Blind}{" currentSOD_H " up}")
        if (currentSOD_V != "")
            TraceSend("{Blind}{" currentSOD_V " up}")
        if (currentSOD_All != "")
            TraceSend("{Blind}{" currentSOD_All " up}")

        currentSOD_H := ""
        currentSOD_V := ""
        currentSOD_All := ""
    }

    ShowTrayTip(
        "SOD SCRIPT",
        szodActive ? "🟢 Snaptivity MODE: ACTIVE" : "🔴 Snaptivity MODE: OFF",
        1200
    )
    UpdateDebugOSD()
}

; ======================================================
; SOD RESOLVERS (ROUTER)
; ======================================================

HandleSOD_H(key, isDown) {
    global szodActive, blockPhysical, physicalKeys, splitLanes
    global traceLatency, t0

    if (traceLatency)
        t0 := A_TickCount
    
    ; Always update physical state
    physicalKeys[key] := isDown

    ; HUD always reacts
    UpdateDebugOSD()

    ; If Snaptivity is OFF → pure physical mode
    if (!szodActive)
        return

    ; If Snaptivity is ON
    ; Decide whether raw physical leaks or not
    if (!blockPhysical) {
        TraceSend("{Blind}{" key (isDown ? " down" : " up") "}")
    }

    ; Engine logic
    if (splitLanes)
        HandleSplitH(key, isDown)
    else
        HandleUnifiedSOD(key, isDown)
}


HandleSOD_V(key, isDown) {
    global szodActive, blockPhysical, physicalKeys, splitLanes
    global traceLatency, t0

    if (traceLatency)
        t0 := A_TickCount

    physicalKeys[key] := isDown
    UpdateDebugOSD()

    if (!szodActive)
        return

    if (!blockPhysical) {
        TraceSend("{Blind}{" key (isDown ? " down" : " up") "}")
    }

    if (splitLanes)
        HandleSplitV(key, isDown)
    else
        HandleUnifiedSOD(key, isDown)
}


; ======================================================
; SPLIT-LANE HANDLERS
; ======================================================

; =========================
; SPLIT H
; =========================
HandleSplitH(key, isDown) {
    global physicalKeys, currentSOD_H, overrideMode, neutralizeMode
    global absSplitHKey, snappyMode

    ; Pair-logic opposite (A/D lane)
    opp := (key = "a") ? "d" : "a"

    ; ===== Conflict detection =====
    if ((snappyMode && physicalKeys[key] && physicalKeys[opp])
     || (!snappyMode && isDown && physicalKeys[opp])) {

        ; 1 = Last input wins
        if (overrideMode = 1 && isDown) {
            if (currentSOD_H != "")
                TraceSend("{Blind}{" currentSOD_H " up}")
            currentSOD_H := key
            TraceSend("{Blind}{" key " down}")
            UpdateDebugOSD()
            return
        }

        ; 2 = First input wins
        else if (overrideMode = 2) {
            if (neutralizeMode && key != currentSOD_H)
                TraceSend("{Blind}{" key " up}")
            UpdateDebugOSD()
            return
        }

        ; 3 = Disable both
        else if (overrideMode = 3) {
            if (currentSOD_H != "") {
                TraceSend("{Blind}{" currentSOD_H " up}")
                currentSOD_H := ""
            }
            UpdateDebugOSD()
            return
        }

        ; 4 = Absolute Priority Mode (Split H)
        else if (overrideMode = 4 && absSplitHKey != "") {
            if (isDown) {
                if (key != absSplitHKey) {
                    ; illegal key, kill it
                    TraceSend("{Blind}{" key " up}")
                    UpdateDebugOSD()
                    return
                } else {
                    ; ABS key pressed → assert authority
                    if (currentSOD_H != absSplitHKey) {
                        if (currentSOD_H != "")
                            TraceSend("{Blind}{" currentSOD_H " up}")

                        currentSOD_H := absSplitHKey
                        TraceSend("{Blind}{" absSplitHKey " down}")
                        UpdateDebugOSD()
                    }
                    return
                }
            } else {
                ; ABS released → clear SOD
                if (key = absSplitHKey && currentSOD_H = absSplitHKey) {
                    TraceSend("{Blind}{" absSplitHKey " up}")
                    currentSOD_H := ""
                    UpdateDebugOSD()
                    return
                }
            }
        }   
    }

    ; ===== Winner lock =====
    if (neutralizeMode && currentSOD_H != "" && isDown && key != currentSOD_H) {
        UpdateDebugOSD()
        return
    }

    ; ===== Normal flow =====
    if (isDown) {
        if (currentSOD_H != key) {
            if (currentSOD_H != "")
                TraceSend("{Blind}{" currentSOD_H " up}")
            currentSOD_H := key
            TraceSend("{Blind}{" key " down}")
        }
    } else { 
        if (currentSOD_H == key) {
            TraceSend("{Blind}{" key " up}")
            currentSOD_H := ""
            ; 🔥 THIS IS THE LOST LINE THAT CAUSED EVERYTHING AHHHHHH
            if (!neutralizeMode) {
                for k in ["a","d"] {
                    if (physicalKeys[k]) {
                        currentSOD_H := k
                        TraceSend("{Blind}{" k " down}")
                        break
                    }
                }
            }
        }
    }

    UpdateDebugOSD()
}



; =========================
; SPLIT V
; =========================
HandleSplitV(key, isDown) {
    global physicalKeys, currentSOD_V, overrideMode, neutralizeMode
    global absSplitVKey, snappyMode

    ; Pair-logic opposite (W/S lane)
    opp := (key = "w") ? "s" : "w"

    if ((snappyMode && physicalKeys[key] && physicalKeys[opp])
     || (!snappyMode && isDown && physicalKeys[opp])) {

        ; 1 = Last input wins
        if (overrideMode = 1 && isDown) {
            if (currentSOD_V != "")
                TraceSend("{Blind}{" currentSOD_V " up}")
            currentSOD_V := key
            TraceSend("{Blind}{" key " down}")
            UpdateDebugOSD()
            return
        }

        ; 2 = First input wins
        else if (overrideMode = 2) {
            if (neutralizeMode && key != currentSOD_V)
                TraceSend("{Blind}{" key " up}")
            UpdateDebugOSD()
            return
        }

        ; 3 = Disable both
        else if (overrideMode = 3) {
            if (currentSOD_V != "") {
                TraceSend("{Blind}{" currentSOD_V " up}")
                currentSOD_V := ""
            }
            UpdateDebugOSD()
            return
        }

        ; 4 = Absolute Priority Mode (Split V)
        else if (overrideMode = 4 && absSplitVKey != "") {
            if (isDown) {
                if (key != absSplitVKey) {
                    TraceSend("{Blind}{" key " up}")
                    UpdateDebugOSD()
                    return
                } else {
                    if (currentSOD_V != absSplitVKey) {
                        if (currentSOD_V != "")
                            TraceSend("{Blind}{" currentSOD_V " up}")
                        currentSOD_V := absSplitVKey
                        TraceSend("{Blind}{" absSplitVKey " down}")
                    }
                    UpdateDebugOSD()
                    return
                }
            } else {
                if (key = absSplitVKey && currentSOD_V = absSplitVKey) {
                    TraceSend("{Blind}{" absSplitVKey " up}")
                    currentSOD_V := ""
                    UpdateDebugOSD()
                    return
                }
            }
        }
    }

    if (neutralizeMode && currentSOD_V != "" && isDown && key != currentSOD_V) {
        UpdateDebugOSD()
        return
    }

    if (isDown) {
        if (currentSOD_V != key) {
            if (currentSOD_V != "")
                TraceSend("{Blind}{" currentSOD_V " up}")
            currentSOD_V := key
            TraceSend("{Blind}{" key " down}")
        }
    } else {
        if (currentSOD_V == key) {
            TraceSend("{Blind}{" key " up}")
            currentSOD_V := ""
            if (!neutralizeMode) {
                for k in ["w","s"] {
                    if (physicalKeys[k]) {
                        currentSOD_V := k
                        TraceSend("{Blind}{" k " down}")
                        break
                    }
                }
            }
        }
    }
    UpdateDebugOSD()
}





; =========================
; UNIFIED
; =========================
HandleUnifiedSOD(key, isDown) {
    global physicalKeys, currentSOD_All, overrideMode, neutralizeMode
    global absUnifiedKey, snappyMode

    opposites := Map("w","s","s","w","a","d","d","a")
    opp := opposites[key]

    if ((snappyMode && physicalKeys[key] && physicalKeys[opp])
     || (!snappyMode && isDown && physicalKeys[opp])) {

        ; 1 = Last input wins
        if (overrideMode = 1 && isDown) {
            if (currentSOD_All != "")
                TraceSend("{Blind}{" currentSOD_All " up}")
            currentSOD_All := key
            TraceSend("{Blind}{" key " down}")
            UpdateDebugOSD()
            return
        }

        ; 2 = First input wins
        else if (overrideMode = 2) {
            if (neutralizeMode && key != currentSOD_All)
                TraceSend("{Blind}{" key " up}")
            UpdateDebugOSD()
            return
        }

        ; 3 = Disable both
        else if (overrideMode = 3) {
            if (currentSOD_All != "") {
                TraceSend("{Blind}{" currentSOD_All " up}")
                currentSOD_All := ""
            }
            UpdateDebugOSD()
            return
        }

        ; 4 = Absolute Priority Mode (Unified)
        else if (overrideMode = 4 && absUnifiedKey != "") {
            if (isDown) {
                if (key != absUnifiedKey) {
                    TraceSend("{Blind}{" key " up}")
                    UpdateDebugOSD()
                    return
                } else {
                    if (currentSOD_All != absUnifiedKey) {
                        if (currentSOD_All != "")
                            TraceSend("{Blind}{" currentSOD_All " up}")
                        currentSOD_All := absUnifiedKey
                        TraceSend("{Blind}{" absUnifiedKey " down}")
                    }
                    UpdateDebugOSD()
                    return
                }
            } else {
                if (key = absUnifiedKey && currentSOD_All = absUnifiedKey) {
                    TraceSend("{Blind}{" absUnifiedKey " up}")
                    currentSOD_All := ""
                    UpdateDebugOSD()
                    return
                }
            }
        }
    }

    if (neutralizeMode && currentSOD_All != "" && isDown && key != currentSOD_All) {
        UpdateDebugOSD()
        return
    }

    if (isDown) {
        if (currentSOD_All != key) {
            if (currentSOD_All != "")
                TraceSend("{Blind}{" currentSOD_All " up}")
            currentSOD_All := key
            TraceSend("{Blind}{" key " down}")
        }
    } else {
        if (currentSOD_All == key) {
            TraceSend("{Blind}{" key " up}")
            currentSOD_All := ""
            if (!neutralizeMode) {
                for k in ["w","a","s","d"] {
                    if (physicalKeys[k]) {
                        currentSOD_All := k
                        TraceSend("{Blind}{" k " down}")
                        break
                    }
                }
            }
        }
    }
    UpdateDebugOSD()
}




; ======================================================
; Snaptivity TOGGLE PICKER
; ======================================================

ShowTogglePicker() {
    global pickerGui, statusText, goBtn, pickedKey

    DisableHotkeys()

    pickerGui := Gui("+AlwaysOnTop", "🎮 Snaptivity Toggle Key")
    pickerGui.BackColor := "101010"
    pickerGui.SetFont("s11 Bold", "Segoe UI")

    pickerGui.AddText("c00FFFF w300 Center", "PRESS A KEY FOR Snaptivity TOGGLE")
    statusText := pickerGui.AddText("cFFFFFF w300 Center", "No key selected")

    goBtn := pickerGui.AddButton("w120 Center Disabled", "CONFIRM")
    goBtn.OnEvent("Click", SetToggleKey)

    pickerGui.Show("AutoSize Center")
    SetTimer(ListenForKey, 10)
}

ListenForKey() {
    global pickedKey, statusText, goBtn

    ctrl  := GetKeyState("Ctrl", "P")
    alt   := GetKeyState("Alt", "P")
    shift := GetKeyState("Shift", "P")

    for key in GetAllKeys() {
        if GetKeyState(key, "P") {

            combo := ""

            if (ctrl)
                combo .= "^"
            if (alt)
                combo .= "!"
            if (shift)
                combo .= "+"

            combo .= key

            pickedKey := combo
            statusText.Text := "Selected: " combo
            goBtn.Enabled := true

            ; wait for everything to be released so it doesn't spam
            KeyWait(key)
            if (ctrl)
                KeyWait("Ctrl")
            if (alt)
                KeyWait("Alt")
            if (shift)
                KeyWait("Shift")

            break
        }
    }
}

SetToggleKey(*) {
    global pickedKey, toggleKey, pickerGui, isResettingKey

    EnableHotkeys()
    SetTimer(ListenForKey, 0)

    toggleKey := pickedKey
    Hotkey(toggleKey, (*) => ToggleSZOD())

    ShowTrayTip("SOD SCRIPT", "Snaptivity Toggle set to: " toggleKey, 1500)

    pickerGui.Destroy()

    if (!isResettingKey)
        ShowMenuTogglePicker()
    else
        isResettingKey := false

    SaveConfig()
}

; ======================================================
; MENU TOGGLE PICKER
; ======================================================

ShowMenuTogglePicker() {
    global menuPickerGui, menuStatusText, menuGoBtn, menuPickedKey

    DisableHotkeys()

    menuPickerGui := Gui("+AlwaysOnTop", "⚙️ MENU Toggle Key")
    menuPickerGui.BackColor := "101010"
    menuPickerGui.SetFont("s11 Bold", "Segoe UI")

    menuPickerGui.AddText("c00FFFF w300 Center", "PRESS A KEY TO OPEN MENU")
    menuStatusText := menuPickerGui.AddText("cFFFFFF w300 Center", "No key selected")

    menuGoBtn := menuPickerGui.AddButton("w120 Center Disabled", "CONFIRM")
    menuGoBtn.OnEvent("Click", SetMenuToggleKey)

    menuPickerGui.Show("AutoSize Center")
    SetTimer(ListenForMenuKey, 10)
}

ListenForMenuKey() {
    global menuPickedKey, menuStatusText, menuGoBtn

    ctrl  := GetKeyState("Ctrl", "P")
    alt   := GetKeyState("Alt", "P")
    shift := GetKeyState("Shift", "P")

    for key in GetAllKeys() {
        if GetKeyState(key, "P") {

            combo := ""
            if (ctrl)
                combo .= "^"
            if (alt)
                combo .= "!"
            if (shift)
                combo .= "+"

            combo .= key

            menuPickedKey := combo
            menuStatusText.Text := "Selected: " combo
            menuGoBtn.Enabled := true

            KeyWait(key)
            if (ctrl)
                KeyWait("Ctrl")
            if (alt)
                KeyWait("Alt")
            if (shift)
                KeyWait("Shift")

            break
        }
    }
}
SetMenuToggleKey(*) {
    global menuPickedKey, menuToggleKey, menuPickerGui

    EnableHotkeys()
    SetTimer(ListenForMenuKey, 0)

    menuToggleKey := menuPickedKey
    Hotkey(menuToggleKey, (*) => ShowMenu())

    SaveConfig()

    ShowTrayTip("SOD SCRIPT", "Menu Toggle set to: " menuToggleKey, 1500)
    menuPickerGui.Destroy()
}

; ======================================================
; GAMER MENU UI
; ======================================================

ShowMenu() {
    global neutralizeMode, debugOverlay, splitLanes
    global trayTipsEnabled, snappyMode, overrideMode
    global isResettingKey, cbDebug, blockPhysical
    global absUnifiedKey, absSplitHKey, absSplitVKey
    global trulySnappy, ncoderMode

    global menuGui := Gui("+AlwaysOnTop -Caption +ToolWindow")
    menu := menuGui

    menu.BackColor := "0B0F1A"
    menu.SetFont("s11 Bold", "Segoe UI")

    ; ===== CUSTOM GAMER TITLE BAR (FLOW SAFE) =====
    titleBar := menu.AddText("w230 h30 Center c00FFFF", "🎮 Snaptivity CONTROL PANEL")
    titleBar.SetFont("s11 Bold", "CopperPlate Gothic Bold")
    OnMessage(0x201, WM_LBUTTONDOWN)

    titleIcon := menu.AddText("x6 y-2 w40 h48 Center c00FFFF", "🎮")
    titleIcon.SetFont("s22 Bold", "Copperplate Gothic Bold")

    ; 🔁 REBIND BUTTONS
    btnRebindSnaptivity := menu.AddText(
        "w300 h32 Center +0x200 Border Background1E90FF cFFFFFF",
        "🔁 Reselect Snaptivity Toggle Key"
    )



    btnRebindSnaptivity.OnEvent("Click", (*) => (
        menu.Destroy(),
        ShowTogglePicker()
        isResettingKey := true
    ))

    btnRebindMenu := menu.AddButton("w300 h32", "🔁 Reselect Menu Toggle Key")
    btnRebindMenu.OnEvent("Click", (*) => (
        menu.Destroy(),
        ShowMenuTogglePicker()
        isResettingKey := true
    ))

    ; HUD Edit Button
    btnHud := menu.AddButton("w300 h32", "🛠️ Edit HUD Position / Size")
    btnHud.OnEvent("Click", (*) => StartHudAdjust())

    ; Tray notifications
    cbTray := menu.AddCheckbox("cAAAAFF w300", "🔕 Disable Tray Notifications")
    cbTray.Value := !trayTipsEnabled
    cbTray.OnEvent("Click", (*) => (
        trayTipsEnabled := !cbTray.Value,
        SaveConfig()
    ))

    ; Snappy mode
    global cbSnappy := menu.AddCheckbox("cFFAA00 w300", "⚡ Snappy Mode")
    cbSnappy.OnEvent("Click", (*) => ToggleSnappyMode())
    ApplySnappyState()

    ; Neutralize / Lock winner
    global cbNeutral := menu.AddCheckbox("c00FFAA w300", "🔥 Lock Winner Opposites (W+S / A+D)")
    cbNeutral.Value := neutralizeMode
    cbNeutral.OnEvent("Click", (*) => neutralizeMode := cbNeutral.Value)
    SaveConfig()

    ; Split lanes
    cbSplit := menu.AddCheckbox("c00FFFF w300", "🧭 Split Direction Lanes (WS / AD)")
    cbSplit.Value := splitLanes
    cbSplit.OnEvent("Click", (*) => (
        splitLanes := cbSplit.Value,
        OverrideModeChanged({Value:overrideMode}),
        SaveConfig()
    ))

    ; debug overlay updated
    cbDebug := menu.AddCheckbox("c00FF00 w300", "🧪 Show WASD HUD Overlay")

    ; checkbox is ON for both ON and ULTRA
    cbDebug.Value := (debugOverlay != 0)

    cbDebug.OnEvent("Click", (*) => (
        debugOverlay := Mod(debugOverlay + 1, 4),   
        cbDebug.Value := (debugOverlay != 0),

        ShowTrayTip(
            "DEBUG HUD",
            debugOverlay = 0 ? "HUD: OFF" :
            debugOverlay = 1 ? "HUD: ON" :
                            "HUD: ULTRA MODE",
            500
        ),
        UpdateDebugCheckboxStyle(),
        UpdateDebugOSD(),
        SaveConfig()
    ))
    cbNcoder := menu.AddCheckbox("c8A00FF w300", "🗿 Ncoder Mode")
    cbNcoder.Value := ncoderMode
    cbNcoder.OnEvent("Click", (*) => (
        ncoderMode := cbNcoder.Value,
        SaveConfig(),
        ShowTrayTip(
            "NCODER MODE",
            ncoderMode ? "🗿 Chaos erupts ACTIVATED" : "⚡ Ncoder is disabled",
            1200
        )
    ))


    ; Override mode
    menu.AddText("c00FFFF w300", "⚡ Override Mode")
    ddlOverride := menu.AddDropDownList("w300", [
        "Last input wins",
        "First input wins",
        "Disable input on override",
        "Absolute Priority Mode"
    ])
    ddlOverride.Value := overrideMode
    ddlOverride.OnEvent("Change", OverrideModeChanged)

    ; =========================
    ; ABSOLUTE PRIORITY UI (HIDDEN BY DEFAULT)
    ; =========================

    global absTitle := menu.AddText("cFF66FF w300 Center", "👑 Absolute Priority Settings")
    absTitle.Visible := false

    global absUnifiedDDL := menu.AddDropDownList("w300", ["None","W","A","S","D"])
    absUnifiedDDL.Visible := false

    global absSplitHDDL := menu.AddDropDownList("w300", ["None","A","D"])
    absSplitHDDL.Visible := false

    global absSplitVDDL := menu.AddDropDownList("w300", ["None","W","S"])
    absSplitVDDL.Visible := false

    ; 🔁 Load saved Absolute Priority values into UI
    absUnifiedDDL.Text := (absUnifiedKey = "" ? "None" : StrUpper(absUnifiedKey))
    absSplitHDDL.Text  := (absSplitHKey  = "" ? "None" : StrUpper(absSplitHKey))
    absSplitVDDL.Text  := (absSplitVKey  = "" ? "None" : StrUpper(absSplitVKey))

    absUnifiedDDL.OnEvent("Change", (*) => (
        absUnifiedKey := (absUnifiedDDL.Text = "None" ? "" : StrLower(absUnifiedDDL.Text)),
        SaveConfig()
    ))

    absSplitHDDL.OnEvent("Change", (*) => (
        absSplitHKey := (absSplitHDDL.Text = "None" ? "" : StrLower(absSplitHDDL.Text)),
        SaveConfig()
    ))


    absSplitVDDL.OnEvent("Change", (*) => (
        absSplitVKey := (absSplitVDDL.Text = "None" ? "" : StrLower(absSplitVDDL.Text)),
        SaveConfig()
    ))



    ; SHOW MENU FIRST
    menu.Show("AutoSize Center")
    UpdateDebugCheckboxStyle()
    ApplySnappyState()

    ; ===== SETTINGS ICON (ADVANCED) =====
    titleBar.GetPos(&tx, &ty, &tw, &th)

    btnAdvanced := menu.AddButton(
        "x" (300 - 10 - 6 - 34) " y" 8 " w30 h28",
        "⚙"
    )

    btnAdvanced.Opt("Background333366 cFFFFFF")
    btnAdvanced.OnEvent("Click", (*) => (
        menu.Destroy(),
        SetTimer(ShowAdvancedMenu, -10)
    ))

    OverrideModeChanged({Value: overrideMode})
    
    ; ===== CLOSE BUTTON (ADD LAST SO IT DOESN’T BREAK FLOW) =====
    titleBar.GetPos(&tx, &ty, &tw, &th)

    btnClose := menu.AddButton(
        "x" (300 - 10 - 6) " y" 8 " w30 h28",
        "✖"
    )

    btnClose.Opt("BackgroundAA3333 cFFFFFF")
    btnClose.OnEvent("Click", (*) => (
    menu.Destroy()
    ))


    ; =========================
    ; TOOLTIPS
    ; =========================

    AttachToolTip(btnRebindSnaptivity, "Change the key used to toggle Snaptivity on and off.")
    AttachToolTip(btnRebindMenu, "Change the key used to open this control panel.")
    AttachToolTip(btnHud, "Move and resize the WASD HUD overlay.")

    AttachToolTip(cbTray, "Prevents Windows tray notifications from appearing.")

    AttachToolTip(cbSnappy,
        "Uses raw physical key overlap detection. Feels faster and more arcade-like, but less filtered."
    )

    AttachToolTip(cbNeutral,
        "When both opposite directions are pressed, keeps the winning direction instead of neutralizing."
    )

    AttachToolTip(cbSplit,
        "Separates horizontal (A/D) and vertical (W/S) input handling into independent lanes."
    )
    AttachToolTip(cbDebug,
        "Shows a real-time WASD HUD overlay for debugging input behavior."
    )

    AttachToolTip(ddlOverride,
        "Defines what happens when opposite directions are pressed together."
    )
}

ShowAdvancedMenu() {
    global blockPhysical, cbLegacy, hudLatency, debugGui, t0, cbTraceLatency, traceLatency
    global latencyCount, latencySum, lastLatency, Safemod

    advGui := Gui("+AlwaysOnTop -Caption +ToolWindow")
    adv := advGui

    adv.BackColor := "120B1F"
    adv.SetFont("s11 Bold", "Segoe UI")

    ; ===== TITLE BAR =====
    title := adv.AddText("w300 h30 Center cFF66FF", "⚙ Advanced Engine Settings")
    title.SetFont("s11 Bold")
    OnMessage(0x201, WM_LBUTTONDOWN)

    adv.AddText("w300 Center cFF4444", "⚠ DANGER ZONE ⚠")
    adv.AddText("w300 Center c777777",
        "These settings bypass Snaptivity safety systems.`n" .
        "Only touch if you understand what you are doing."
    )

    ; =========================
    ; LEGACY INPUT MODE
    ; =========================
    cbLegacy := adv.AddCheckbox(
        "w300 cFFAA00",
        "🧟 Legacy Input Mode (Allow Physical Passthrough)"
    )

    ; Logic:
    ; blockPhysical = 1 → Engine Mode
    ; blockPhysical = 0 → Legacy Mode
    ; Checkbox ON  = Legacy (0)
    ; Checkbox OFF = Engine (1)
    cbLegacy.Value := !blockPhysical

    cbLegacy.OnEvent("Click", (*) => LegacyToggle())

    AttachToolTip(cbLegacy,
        "⚠ Legacy Input Mode allows physical keyboard passthrough.`n" .
        "This may cause:`n" .
        "- Triple keystrokes (Previously Double)`n" .
        "- Input desync`n" .
        "- Unexpected behavior`n" .
        "Use only for compatibility or debugging."
    )

    ; =========================
    ; ENGINE LATENCY PROFILER
    ; =========================
    cbTraceLatency := adv.AddCheckbox("c00FF9C w300", "📊 Engine Latency Profiler")
    cbTraceLatency.Value := traceLatency

    cbTraceLatency.OnEvent("Click", (*) => (
        traceLatency := cbTraceLatency.Value,

        ; reset stats when turning ON so measurements are clean
        traceLatency ? (
            latencySum := 0,
            latencyCount := 0,
            lastLatency := 0
        ) : "",

        ShowTrayTip(
            "ENGINE PROFILER",
            traceLatency
                ? "📊 Latency profiler ENABLED (measuring logic pipeline)"
                : "📴 Latency profiler DISABLED",
            1200
        ),

        UpdateDebugOSD(),
        SaveConfig()
    ))
    ; =========================
    ; 🛡️ SAFEMOD TOGGLE
    ; =========================
    cbSafemod := adv.AddCheckbox("c66FF66 w300", "🛡️ SafeMod (Engine Supervision)")
    cbSafemod.Value := Safemod

    cbSafemod.OnEvent("Click", (*) => (
        Safemod := cbSafemod.Value,
        SaveConfig(),
        ShowTrayTip(
            "SAFEMOD",
            Safemod
                ? "🛡️ SafeMod ENABLED (Crash protection & watchdog active)"
                : "☠️ SafeMod DISABLED (UNCHAINED MODE)",
            1400
        )
    ))

    ; =========================
    ; 💥 MANUAL CRASH BUTTON
    ; =========================
    btnCrash := adv.AddButton("w300 h32", "CRASH NOW 💥")
    btnCrash.Opt("BackgroundAA0000 cFFFFFF")
    btnCrash.OnEvent("Click", (*) => ForceCrash())

    ; =========================
    ; BUTTONS
    ; =========================

    btnBack := adv.AddButton("w300 h32", "⬅ Back")
    btnBack.OnEvent("Click", (*) => (
        advGui.Destroy(),
        SetTimer(ShowMenu, -10)
    ))

    ; Show first so overlay buttons don’t reserve space
    adv.Show("AutoSize Center")

    ; ===== CLOSE BUTTON OVERLAY =====
    title.GetPos(&tx, &ty, &tw, &th)

    btnClose := adv.AddButton(
        "x" (300 - 10 - 6) " y" 8 " w30 h28",
        "✖"
    )
    btnClose.Opt("BackgroundAA3333 cFFFFFF")
    btnClose.OnEvent("Click", (*) => advGui.Destroy())
}
ForceCrash() {
    crashGui := Gui("+AlwaysOnTop", "☠️ Crash Selector")
    crashGui.BackColor := "0A0A0A"
    crashGui.SetFont("s11 Bold", "Segoe UI")

    crashGui.AddText("cFF4444 w300 Center", "CHOOSE HOW YOU WANT TO CRASH 💀")

    ddl := crashGui.AddDropDownList("w300", [
        "💥 Soft Crash (Exception) || WEAK",
        "💀 Hard Crash (TerminateProcess) || STRONG",
        "🌀 Freeze (Infinite Loop) || WEAK",
        "☠️ Exit(999) (Fake Crash) || HANDLED",
        "🧨 Memory Corruption (Invalid Access) || WEAK",
        "⚡ Stack Overflow (Deep Recursion) || STRONG",
        "🧯 Resource Leak (RAM Bomb) || WEAK",
        "🕳️ Null Call (Invalid DLLCall) || WEAK",
        "🧬 Thread Explosion (Timer Storm) || WEAK",
        "🧬 Atomic Timer Storm (Parallel writes) || WEAK",
        "🪓 Self Destruct (Kill & Respawn) || HANDLED"
    ])
    ddl.Value := 1

    btnGo := crashGui.AddButton("w300 h32", "🔥 EXECUTE CRASH")
    btnGo.Opt("Background550000 cFFFFFF")

    btnGo.OnEvent("Click", (*) => (
        crashType := ddl.Value,
        crashGui.Destroy(),
        ExecuteCrash(crashType)
    ))

    crashGui.Show("AutoSize Center")
}

ExecuteCrash(type) {
    global intentionalCrash
    intentionalCrash := true   ; ARM THE SILENCER
    var := ""

    switch type {

        case 1: ; 💥 Soft crash (exception)
            throw Error("SOFT CRASH TEST")

        case 2: ; 💀 Hard kill
            DllCall("TerminateProcess", "Ptr", DllCall("GetCurrentProcess", "Ptr"), "UInt", 1)

        case 3: ; 🌀 Freeze
            Loop {
                ; infinite loop
            }

        case 4: ; ☠️ Fake crash
            ExitApp(999)

        case 5: ; 🧨 Memory corruption
            x := []
            MsgBox(x[999999999])   ; invalid index = runtime error

        case 6: ; ⚡ Stack overflow
            CrashRecursion()

        case 7: ; 🧯 RAM bomb
            arr := []
            Loop 1000000 {
                arr.Push(Random(1,999999))
            }

        case 8: ; 🕳️ Invalid DLLCall
            DllCall("ThisFunctionDoesNotExist")

        case 9: ; 🧬 Timer storm (parallel)
            Loop 100 {
                SetTimer(() => var = "a", 1)
            }

        case 10: ; 🧬 Timer storm (Atomic)
            Loop 100 {
                SetTimer(AtomicStormTick, 1)
            }


        case 11: ; 🪓 Kill & Respawn combo
            Run('"' A_ScriptFullPath '"')
            Sleep(100)
            DllCall("TerminateProcess", "Ptr", DllCall("GetCurrentProcess", "Ptr"), "UInt", 1)
    }
}

CrashRecursion() {
    return CrashRecursion()
}
global CrashTick := 0
AtomicStormTick() {
    global CrashTick
    Loop 100 {
        CrashTick++
    }
}

; ======================================================
; KEY LIST
; ======================================================

GetAllKeys() {
    return [
        "F1","F2","F3","F4","F5","F6","F7","F8","F9","F10","F11","F12",
        "CapsLock","ScrollLock","NumLock","Pause","Insert","Delete","Home","End","PgUp","PgDn",
        "Up","Down","Left","Right","PrintScreen",
        "Numpad0","Numpad1","Numpad2","Numpad3","Numpad4","Numpad5","Numpad6","Numpad7","Numpad8","Numpad9",
        "NumpadAdd","NumpadSub","NumpadMult","NumpadDiv","NumpadDot","NumpadEnter",
        "Volume_Up","Volume_Down","Volume_Mute","Media_Play_Pause","Media_Next","Media_Prev","Media_Stop",
        "a","b","c","d","e","f","g","h","i","j","k","l","m","n","o","p","q","r","s","t","u","v","w","x","y","z",
        "1","2","3","4","5","6","7","8","9","0"
    ]
}



; ======================================================
; HUD ADJUST MODE HOTKEYS
; ======================================================

#HotIf adjustingHud

Up::MoveHud(0, -5)
Down::MoveHud(0, 5)
Left::MoveHud(-5, 0)
Right::MoveHud(5, 0)

NumpadAdd::ResizeHud(2)
NumpadSub::ResizeHud(-2)

Numpad4::AdjustLatencyOffset(-1, 0)
Numpad6::AdjustLatencyOffset(1, 0)
Numpad8::AdjustLatencyOffset(0, -1)
Numpad2::AdjustLatencyOffset(0, 1)

Enter::FinishHudAdjust()

#HotIf


MoveHud(dx, dy) {
    global hudX, hudY
    hudX += dx
    hudY += dy
    UpdateDebugOSD()
}

ResizeHud(delta) {
    global keySize, gap, debugGui, hudW, hudA, hudS, hudD

    keySize += delta
    if (keySize < 20)
        keySize := 20

    hudW.SetFont("s" Round(keySize * fontScale) " Bold")
    hudA.SetFont("s" Round(keySize * fontScale) " Bold")
    hudS.SetFont("s" Round(keySize * fontScale) " Bold")
    hudD.SetFont("s" Round(keySize * fontScale) " Bold")


    ; resize HUD elements
    hudW.Move(, , keySize, keySize)
    hudA.Move(, , keySize, keySize)
    hudS.Move(, , keySize, keySize)
    hudD.Move(, , keySize, keySize)

    ; re-layout
    hudW.Move(keySize + gap, 0)
    hudA.Move(0, keySize + gap)
    hudS.Move(keySize + gap, keySize + gap)
    hudD.Move((keySize + gap) * 2, keySize + gap)

    ; resize window
    hudWidth  := (keySize + gap) * 3 - gap + 8
    hudHeight := (keySize + gap) * 2 - gap + 8
    debugGui.Show("w" hudWidth " h" hudHeight " NoActivate x" hudX " y" hudY)
}

FinishHudAdjust() {
    global adjustingHud
    adjustingHud := false
    SaveConfig()

    ShowEditOSD("✅ HUD position saved!", "00FF00", 2000)
}

StartHudAdjust() {
    global adjustingHud
    adjustingHud := true

    ShowEditOSD(
        "Use Arrow keys to move and numpad -/+ to resize HUD`nPress ENTER to save position",
        "00FFAA",
        6000
    )

    ShowTrayTip("HUD EDIT MODE", "Use OSD instructions to adjust HUD", 1500)
}
OverrideModeChanged(ctrl, *) {
    global overrideMode, cbNeutral, neutralizeMode
    global absTitle, absUnifiedDDL, absSplitHDDL, absSplitVDDL
    global splitLanes, menuGui

    overrideMode := ctrl.Value

    modes := Map(
        1,"Last Input Wins ⚡",
        2,"First Input Wins 🧱",
        3,"Disable On Override ❌",
        4,"Absolute Priority 👑"
    )

    ShowTrayTip("OVERRIDE MODE", "Mode set to: " modes[overrideMode], 1200)

    ; Grey-out Lock Winner on Mode 3 and 4
    if (overrideMode=3 || overrideMode=4) {
        neutralizeMode := false
        cbNeutral.Value := 0
        cbNeutral.Enabled := false
        cbNeutral.Opt("c666666")
    } else {
        cbNeutral.Enabled := true
        cbNeutral.Opt("c00FFAA")
    }

    ; 👑 SHOW/HIDE ABSOLUTE PRIORITY CONTROLS
    showAbs := (overrideMode = 4)

    absTitle.Visible := showAbs

    if (splitLanes) {
        absUnifiedDDL.Visible := false
        absSplitHDDL.Visible := showAbs
        absSplitVDDL.Visible := showAbs
    } else {
        absUnifiedDDL.Visible := showAbs
        absSplitHDDL.Visible := false
        absSplitVDDL.Visible := false
    }
    menuGui.Show("AutoSize")

    ; Make sure that ABS values are not hallucinated by the UI
    if (overrideMode = 4) {
        absUnifiedDDL.Text := (absUnifiedKey = "" ? "None" : StrUpper(absUnifiedKey))
        absSplitHDDL.Text  := (absSplitHKey  = "" ? "None" : StrUpper(absSplitHKey))
        absSplitVDDL.Text  := (absSplitVKey  = "" ? "None" : StrUpper(absSplitVKey))
    }

}



ShowTrayTip(title, text, time := 300) {
    global trayTipsEnabled, trayTipCooldown

    ; hard mute during restart window
    if (trayTipCooldown)
        return

    if (trayTipsEnabled)
        TrayTip(title, text, time)
}

AttachToolTip(ctrl, text) {
    global toolTipMap
    toolTipMap[ctrl.Hwnd] := text
}
ShowStatusOSD(msg, color := "66FF66") {
    global editOsdGui, editOsdText, debugGui, debugOverlay

    ; Only show status if WASD HUD is enabled
    if (!debugOverlay) {
        editOsdGui.Hide()
        return
    }

    ; Set text + color
    editOsdText.Text := "🟢 " msg
    editOsdText.Opt("c" color)

    ; Show so we can measure size
    editOsdGui.Show("NoActivate")

    ; Get real HUD position
    debugGui.GetPos(&hx, &hy, &hw, &hh)

    ; Get OSD size
    editOsdGui.GetPos(&x, &y, &w, &h)

    ; Place directly under WASD HUD
    newX := hx
    newY := hy + hh + 6   ; small gap

    editOsdGui.Move(newX, newY)
}
DisableHotkeys() {
    global toggleKey, menuToggleKey
    if (toggleKey != "")
        Hotkey(toggleKey, "Off")
    if (menuToggleKey != "")
        Hotkey(menuToggleKey, "Off")
}

EnableHotkeys() {
    global toggleKey, menuToggleKey
    if (toggleKey != "")
        Hotkey(toggleKey, "On")
    if (menuToggleKey != "")
        Hotkey(menuToggleKey, "On")
}
; does anyone even read this
; why does copilot keep suggesting me 2... WHATS THE MEANING OF 2!
StartDrag(guiObj) {
    global dragArmed, dragStartX, dragStartY, dragGui

    dragGui := guiObj
    dragArmed := true

    MouseGetPos(&mx, &my)
    dragStartX := mx
    dragStartY := my
}


WM_LBUTTONDOWN(wParam, lParam, msg, hwnd) {
    global titleBar, menuGui
    global dragArmed, dragStartX, dragStartY, dragGui

    ; Only start drag if click was on the title bar
    if (!IsSet(titleBar) || hwnd != titleBar.Hwnd)
        return

    dragGui := menuGui
    dragArmed := true
    MouseGetPos(&dragStartX, &dragStartY)
}


WM_LBUTTONUP(wParam, lParam, msg, hwnd) {
    global dragArmed
    dragArmed := false
}
UpdateDebugCheckboxStyle() {
    global cbDebug, debugOverlay

    if (debugOverlay = 0) {
        cbDebug.Value := 0
        cbDebug.Opt("c777777")
        cbDebug.Text := "🧪 Debug HUD (OFF)"
    }
    else if (debugOverlay = 1) {
        cbDebug.Value := 1
        cbDebug.Opt("c00FF00")
        cbDebug.Text := "🧪 Debug HUD (PHYSICAL 🟢)"
    }
    else if (debugOverlay = 2) {
        cbDebug.Value := 1
        cbDebug.Opt("c00FFFF")
        cbDebug.Text := "🧪 Debug HUD (LOGICAL 🔵)"
    }
    else if (debugOverlay = 3) {
        cbDebug.Value := 1
        cbDebug.Opt("cFF66FF")
        cbDebug.Text := "🧪 Debug HUD (ULTRA ⚡)"
    }
}
ToggleSnappyMode() {
    global snappyMode, trulySnappy, cbSnappy

    ; OFF → ON → TRULY → OFF
    if (!snappyMode && !trulySnappy) {
        snappyMode := true
        trulySnappy := false
    }
    else if (snappyMode && !trulySnappy) {
        snappyMode := true
        trulySnappy := true
    }
    else {
        snappyMode := false
        trulySnappy := false
    }

    ApplySnappyState()
    SaveConfig()
}

ApplySnappyState() {
    global snappyMode, trulySnappy, cbSnappy

    ; Engine always applies
    if (trulySnappy)
        EnableEngineOverclock()
    else
        DisableEngineOverclock()

    ; UI SAFETY GUARD
    if !IsObject(cbSnappy)
        return

    ; UI
    if (!snappyMode && !trulySnappy) {
        cbSnappy.Value := 0
        cbSnappy.Opt("c777777")
        cbSnappy.Text := "⚡ Snappy Mode (OFF)"
    }
    else if (snappyMode && !trulySnappy) {
        cbSnappy.Value := 1
        cbSnappy.Opt("cFF9900")
        cbSnappy.Text := "⚡ Snappy Mode (ON)"
    }
    else {
        cbSnappy.Value := 1
        cbSnappy.Opt("cFF3333")
        cbSnappy.Text := "⚡ Snappy Mode (TRULY SNAPPY)"
    }
}


IniLoadTranslator(value, type := "string") {
    switch type {
        case "bool":
            return (value = "1" || value = 1 || value = true)
        case "int":
            return value + 0
        case "float":
            return value + 0.0
        case "string":
            return value ""
        default:
            return value
    }
}
IniLoadD(section, key, default, type := "string") {
    val := IniRead(configFile, section, key, default)
    return IniLoadTranslator(val, type)
}
LegacyToggle() {
    global cbLegacy, blockPhysical

    ; First read UI
    newValue := cbLegacy.Value

    ; Then update engine
    blockPhysical := !newValue

    ; THEN save
    SaveConfig()

    ShowTrayTip(
        "INPUT ENGINE",
        blockPhysical
            ? "⚡ Engine Mode (Physical BLOCKED)"
            : "🧟 Legacy Mode (Physical PASSTHROUGH)",
        1200
    )
}
TraceSend(cmd) {
    global traceLatency, lastLatency, latencyAvg, latencyCount, Safemod

    ; =========================
    ; STATE
    ; =========================
    static keyCount := Map()
    static frameCount := 0
    static windowCount := 0
    static lastFrame := 0
    static lastWindow := 0
    static blockUntil := 0

    ; =========================
    ; CONFIG (tuned to stay UNDER AHK panic)
    ; =========================
    if (Safemod) {
        maxPerKey    := 100000      ; per key per frame
        maxPerFrame  := 100000     ; total sends per ~16ms
        maxPerWindow := 1000000    ; total sends per 100ms
        cooldownMS := 50      ; Time taken to block inputs
    } else {
        maxPerKey    := 500000
        maxPerFrame  := 3000000
        maxPerWindow := 1000000
    }

    now := A_TickCount

    ; ======================
    ; COOLDOWN GATE
    ; ======================
    if (now < blockUntil)
        return   ; full shutdown window

    ; =========================
    ; FRAME RESET (~60 FPS)
    ; =========================
    if (now - lastFrame > 16) {
        keyCount.Clear()
        frameCount := 0
        lastFrame := now
    }

    ; =========================
    ; FLOOD WINDOW RESET (100ms)
    ; =========================
    if (now - lastWindow > 100) {
        windowCount := 0
        lastWindow := now
    }

    ; =========================
    ; EXTRACT KEY
    ; =========================
    pos := InStr(cmd, "{", false, -1)
    if (pos) {
        part := SubStr(cmd, pos + 1)
        part := RegExReplace(part, "[{}]", "")
        key := StrSplit(part, " ")[1]
    } else {
        key := "_unknown"
    }

    if !keyCount.Has(key)
        keyCount[key] := 0

    ; =========================
    ; LIMITER LAYERS
    ; =========================

    ; 1. Per-key limiter
    if (keyCount[key] >= maxPerKey && !InStr(cmd, " up")) {
        sleep(0)
        return
    }

    ; 2. Per-frame limiter
    if (frameCount >= maxPerFrame) {
        sleep(0)
        return
    }

    ; 3. Rolling flood limiter (prevents AHK panic dialog)
    if (windowCount >= maxPerWindow) {
        sleep(0)
        return
    }

    ; =========================
    ; ACCEPT SEND
    ; =========================
    keyCount[key]++
    frameCount++
    windowCount++

    if (traceLatency)
        t0 := QPC_Now()

    Send(cmd)

    if (traceLatency) {
        t1 := QPC_Now()
        delta := t1 - t0

        lastLatency := Round(delta, 3)
        if (latencyCount = 0)
            latencyAvg := delta
        else
            latencyAvg := (latencyAvg * 0.85) + (delta * 0.15)

        latencyCount++
        UpdateLatencyOSD()
    }
}



GetAvgLatency() {
    global latencySum
    return Round(latencySum, 3)
}
StickLatencyToHud() {
    global latencyGui, debugGui, traceLatency, latencyCount
    global latencyOffsetX, latencyOffsetY

    if (!traceLatency || latencyCount = 0) {
        latencyGui.Hide()
        return
    }

    debugGui.GetPos(&x, &y, &w, &h)

    newX := x + latencyOffsetX
    newY := y + h + latencyOffsetY

    latencyGui.Move(newX, newY)
    latencyGui.Show("NoActivate")
}
AdjustLatencyOffset(dx, dy) {
    global latencyOffsetX, latencyOffsetY

    latencyOffsetX += dx
    latencyOffsetY += dy

    StickLatencyToHud()   ; instant visual update
    SaveConfig()
}
QPC_Now() {
    static freq := 0
    if (!freq) {
        DllCall("QueryPerformanceFrequency", "Int64*", &freq)
    }
    counter := 0
    DllCall("QueryPerformanceCounter", "Int64*", &counter)
    return counter * 1000.0 / freq   ; returns time in ms (float)
}
ForceRedraw(gui) {
    gui.Show("NoActivate")
    gui.Hide()
    gui.Show("NoActivate")
}
ForceHUDRedraw() {
    global debugGui, latencyGui, debugOverlay, traceLatency

    ; Only redraw if they should exist
    if (debugOverlay)
        ForceRedraw(debugGui)

    if (traceLatency)
        ForceRedraw(latencyGui)
}
EnableEngineOverclock() {
    A_BatchLines := -1
    A_SendMode := "Input"
    ProcessSetPriority("High")

    SetKeyDelay(-1, -1)
    SetMouseDelay(-1)
    SetWinDelay(-1)
    SetControlDelay(-1)
}

DisableEngineOverclock() {
    A_BatchLines := 10
    A_SendMode := "Input"
    ProcessSetPriority("High")

    SetKeyDelay(10, 10)
    SetMouseDelay(10)
    SetWinDelay(100)
    SetControlDelay(20)
}
ForceAlwaysOnTop() {
    global debugGui, latencyGui, osdGui, editOsdGui

    try debugGui.Opt("+AlwaysOnTop")
    try latencyGui.Opt("+AlwaysOnTop")
    try osdGui.Opt("+AlwaysOnTop")
    try editOsdGui.Opt("+AlwaysOnTop")
}
if (Safemod)
    SetTimer(CheckStuckKeys, 190)

CheckStuckKeys() {
    global physicalKeys, currentSOD_H, currentSOD_V, currentSOD_All

    for k, v in physicalKeys {

        logicalHeld :=
            (k = currentSOD_H) ||
            (k = currentSOD_V) ||
            (k = currentSOD_All)

        ; If logical says DOWN but physical says NO → kill logical
        if (logicalHeld && !v) {
            Send("{Blind}{" k " up}")

            if (currentSOD_H = k)
                currentSOD_H := ""
            if (currentSOD_V = k)
                currentSOD_V := ""
            if (currentSOD_All = k)
                currentSOD_All := ""
        }
    }
}

if Safemod{
    OnExit(HandleCrash)
    }

HandleCrash(ExitReason, ExitCode) {
    ; classify exit
    if (ExitReason = "Exit" && ExitCode = 0) {
        return
    }

    if (ExitReason = "Reload"
     || ExitReason = "Menu"
     || ExitReason = "Close"
     || ExitReason = "Single") {
        return
    }

    ; everything else = crash
    crash := "CRASH|" ExitReason "|Code=" ExitCode "|PID=" DllCall("GetCurrentProcessId")
}


LogCrash(ExitReason, ExitCode) {
    global CrashFailedDir
    global LastCrashError
    global szodActive, overrideMode, snappyMode, trulySnappy, splitLanes
    global neutralizeMode, blockPhysical, Safemod
    global currentSOD_H, currentSOD_V, currentSOD_All
    global CrashTick

    ts := FormatTime(A_Now, "yyyy-MM-dd_HH-mm-ss")
    file := CrashFailedDir "\" ts ".log"

    crashText :=
    (
    "🔥 SNAPTIVITY CRASH REPORT" "`n"
    "=========================" "`n"
    "Time:       " ts "`n"
    "ExitReason: " ExitReason "`n"
    "ExitCode:   " ExitCode "`n"
    "`n"
    "---- ENGINE STATE ----" "`n"
    "Snaptivity Active: " szodActive "`n"
    "Override Mode:     " overrideMode "`n"
    "Split Lanes:       " splitLanes "`n"
    "Snappy Mode:       " snappyMode "`n"
    "Truly Snappy:      " trulySnappy "`n"
    "Neutralize Mode:   " neutralizeMode "`n"
    "Block Physical:    " blockPhysical "`n"
    "SafeMod:           " Safemod "`n"
    "`n"
    "---- INPUT STATE ----" "`n"
    "Current H: " currentSOD_H "`n"
    "Current V: " currentSOD_V "`n"
    "Current A: " currentSOD_All "`n"
    "`n"
    "---- CRASH LAB ----" "`n"
    "CrashTick Counter: " CrashTick "`n"
    "`n"
    "---- SCRIPT INFO ----" "`n"
    "Script:  " A_ScriptFullPath "`n"
    "AHK Ver: " A_AhkVersion "`n"
    "OS:      " A_OSVersion "`n"
    "`n"
    )

    if (LastCrashError != "")
        crashText .= "`n" LastCrashError
    else
        crashText .= "`n---- NO AHK ERROR ----`nThis was not an AHK exception (likely forced kill or ExitApp)."

    FileAppend(crashText, file)
    CleanupCrashLogs(5, CrashFailedDir)

    return file
}


CleanupCrashLogs(max := 5, dir := "") {
    if (dir = "")
        return

    while true {
        count := 0
        oldestFile := ""
        oldestTime := 99999999999999

        Loop Files, dir "\*.log", "F" {
            count++
            if (A_LoopFileTimeModified < oldestTime) {
                oldestTime := A_LoopFileTimeModified
                oldestFile := A_LoopFileFullPath
            }
        }

        ; If we're under the limit, stop
        if (count <= max)
            break

        ; Otherwise delete the oldest one
        if (oldestFile != "")
            FileDelete(oldestFile)
        else
            break
    }
}



CaptureCrashError(e, mode) {
    global LastCrashError

    ; Build a full error report
    LastCrashError :=
    (
    "---- AHK ERROR ----" "`n"
    "Message: " e.Message "`n"
    "What:    " e.What "`n"
    "File:    " e.File "`n"
    "Line:    " e.Line "`n"
    "`n"
    "---- STACK TRACE ----" "`n"
    e.Stack
    )

    ; Let script terminate normally so OnExit runs
    return false
}

MarkLastCrashRecovered() {
    global CrashFailedDir, CrashRecoveredDir

    ; find newest failed crash
    latest := ""
    latestTime := 0

    Loop Files, CrashFailedDir "\*.log", "F" {
        if (A_LoopFileTimeModified > latestTime) {
            latestTime := A_LoopFileTimeModified
            latest := A_LoopFileFullPath
        }
    }

    if (latest != "") {
        SplitPath(latest, &name)
        FileMove(latest, CrashRecoveredDir "\" name, true)
    }
}



GetRainbowColor() {
    static idx := 0
    rainbow := [
        ; 🔴 Red → Orange
        "FF0000","FF1100","FF2200","FF3300","FF4400","FF5500","FF6600","FF7700","FF8800","FF9900",
        ; 🟠 Orange → Yellow
        "FFAA00","FFBB00","FFCC00","FFDD00","FFEE00","FFFF00",
        ; 🟡 Yellow → Green
        "EEFF00","DDFF00","CCFF00","BBFF00","AAFF00","99FF00","88FF00","77FF00","66FF00","55FF00","44FF00","33FF00","22FF00","11FF00","00FF00",
        ; 🟢 Green → Cyan
        "00FF11","00FF22","00FF33","00FF44","00FF55","00FF66","00FF77","00FF88","00FF99","00FFAA","00FFBB","00FFCC","00FFDD","00FFEE","00FFFF",
        ; 🟦 Cyan → Blue
        "00EEFF","00DDFF","00CCFF","00BBFF","00AAFF","0099FF","0088FF","0077FF","0066FF","0055FF","0044FF","0033FF","0022FF","0011FF","0000FF",
        ; 🔵 Blue → Violet
        "1100FF","2200FF","3300FF","4400FF","5500FF","6600FF","7700FF","8800FF","9900FF","AA00FF","BB00FF","CC00FF","DD00FF","EE00FF","FF00FF",
        ; 🟣 Violet → Back to Red
        "FF00EE","FF00DD","FF00CC","FF00BB","FF00AA","FF0099","FF0088","FF0077","FF0066","FF0055","FF0044","FF0033","FF0022","FF0011"
    ]

    idx++
    if (idx > rainbow.Length)
        idx := 1

    return rainbow[idx]
}

CreateGradientOSD() {
    global osdGui, osdLetters, osdColors

    ; do not create OSD here it already exists

    word := "SNAPTIVITY: ON"

    osdColors := [
        "FF0000","FF0055","FF00AA","CC00FF","8800FF",
        "4400FF","0044FF","0088FF","00CCFF","00FFCC",
        "00FF88","00FF44","66FF00","99FF00" ; idk why but this isnt useful at all but if i dont keep this stuff breaks so no                                                                                                                                                                             
    ]                                                                                                                                                                            
                                                                                                                                                                             
    x := 0                                                                                                                                                                           
    Loop StrLen(word) {                                                                                                                                                                              
        char := SubStr(word, A_Index, 1)                                                                               ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;                                                               
        c := osdColors[A_Index]                                                                                        ;                              ;                                                      
                                                                                                                       ;    ;;;;;         ;;;;;       ;                        
        txt := osdGui.AddText("x" x " y0 c" c, char)                                                                   ;    ;;;;;         ;;;;;       ;                                                                           
        osdLetters.Push(txt)                                                                                           ;                              ;                                                   
                                                                                                                       ;       ;;;;;     ;;;;;        ;                       
        txt.GetPos(,, &w,)                                                                                             ;            ;;;;;             ;                                               
        x += w                                                                                                         ;            ;;;;;             ;                                   
    }                                                                                                                  ;                              ;                           
}                                                                                                                      ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;                                                      

UpdateGradientOSD() {
    global osdLetters, osdColors, cbNcoder, gradientTarget

    osdColors.InsertAt(1, GetRainbowColor())
    osdColors.RemoveAt(osdColors.Length)

    if (gradientTarget = "osd") {
        for i, txt in osdLetters
            txt.Opt("c" osdColors[i])
    }
    else if (gradientTarget = "ncoder") {
        ; Checkbox only has ONE color → take first gradient color                                                                                                                                                                                                                                       
        try cbNcoder.Opt("c" osdColors[1])                                                                                                                                                                                                                                      
    }                                                                                                                                                                                                                                       
}                                                                                                                                                                                                                                       
                                                                                                                                                                                        ;;               ;;
StartGradientOSD() {                                                                                                                                                                        ;;                                                                
    global gradientTimerRunning
    if (gradientTimerRunning)                                                                                                                                                               ;              ;;  ;;
        return                                                                                                                                                                            ;;  ;;
                                                                                                                                                                        ;;  ;;
    gradientTimerRunning := true                                                                                                                                                                              ;;  ;;
    SetTimer(UpdateGradientOSD, 16)   ; In ms                                                                                                                                                  ; ;   ;;                      ;;  ;; HEHE
}                                                                                                                                                                             ;;  ;;
                                                                                                                                                                        ;;  ;;
StopGradientOSD() {                                                                                                                                                                           ; ;    ; ;
    global gradientTimerRunning                                                                                                                                                                           ; ;    ; ;
    if (!gradientTimerRunning)                                                                                                                                                                           ; ;    ; ;
        return                                                                                                                                                                           ; ;    ; ;
                                                                                                                                                                           ; ;    ; ;
    gradientTimerRunning := false                                                                                                                                                                           ; ;    ; ;
    SetTimer(UpdateGradientOSD, 0)                                                                                                                                                                           ; ;    ; ;
}                                                                                                                                                                           ; ;    ; ;



; ⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷
; ⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿
; ⣿⣿⣿⡟⠉⠉⠉⠉⢻⣿⣿⣿⣿⡟⠉⠉⠉⠉⢻⣿⣿⣿
; ⣿⣿⣿⡇ 🟢⠀ ⢸⣿⣿⣿⣿⡇⠀🔥⠀⢸⣿⣿⣿
; ⣿⣿⣿⣇⣀⣀⣀⣀⡸⠿⠿⠿⠿⢇⣀⣀⣀⣀⣸⣿⣿⣿
; ⣿⣿⣿⣿⣿⣿⣿⣿⡇⠀⠀⠀⠀⢸⣿⣿⣿⣿⣿⣿⣿⣿
; ⣿⣿⣿⣿⣿⣿⠉⠉⠁⠀⠀⠀⠀⠈⠉⠉⣿⣿⣿⣿⣿⣿
; ⣿⣿⣿⣿⣿⣿⠀⠀⠀ ⠀⠀⠀⠀⠀⠀⠀⣿⣿⣿⣿⣿⣿
; ⣿⣿⣿⣿⣿⣿⠀⠀⣶⣶⣶⣶⣶⣶⠀⠀⣿⣿⣿⣿⣿⣿
; ⣿⣿⣿⣿⣿⣿⣶⣾⣿⣿⣿⣿⣿⣿⣷⣶⣿⣿⣿⣿⣿⣿
; ⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿

