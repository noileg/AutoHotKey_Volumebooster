; ==============================================================================
;  VolumeBoost.ahk  –  常駐本体 (AutoHotkey v2)
;  複数アプリ対応 ＋ 終了時音量の自動保存・自動復元機能付き
; ==============================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
#NoTrayIcon

global INI_PATH   := A_ScriptDir "\VolumeBoost.ini"
global g_entries  := []
global g_iniStamp := 0

LoadINI()
SetTimer(WatchINI, 2000)
SetTimer(WatchProcesses, 500) ; 追加: 0.5秒間隔でプロセスと音量を監視

; ==============================================================================
;  INI 読み込み
; ==============================================================================
LoadINI() {
    global INI_PATH, g_entries

    for e in g_entries
        try Hotkey(e.hotkey, "Off")
    g_entries := []

    if !FileExist(INI_PATH) {
        IniWrite("Microsoft.Media.Player.exe", INI_PATH, "Entry1", "TargetProcess")
        IniWrite("5",                          INI_PATH, "Entry1", "BoostFactor")
        IniWrite("!v",                         INI_PATH, "Entry1", "Hotkey")
    }

    sections := IniRead(INI_PATH)
    loop parse, sections, "`n", "`r" {
        sec := Trim(A_LoopField)
        if !sec
            continue
        proc   := IniRead(INI_PATH, sec, "TargetProcess", "")
        factor := Integer(IniRead(INI_PATH, sec, "BoostFactor", "5"))
        hk     := IniRead(INI_PATH, sec, "Hotkey", "")
        if (!proc || !hk)
            continue
            
        ; 管理用パラメータ（sec, sessionActive, lastVol）を追加
        entry := {sec: sec, process: proc, factor: factor, hotkey: hk,
                  boosting: false, saved: -1.0, sessionActive: false, lastVol: -1.0}
        g_entries.Push(entry)
        RegisterHotkey(entry)
    }
}

; ==============================================================================
;  音量の自動保存＆復元ループ (プロセス監視)
; ==============================================================================
WatchProcesses() {
    global INI_PATH, g_iniStamp
    for e in g_entries {
        vol := GetAppVolume(e.process)
        
        if (vol != -1) {
            ; プロセス（オーディオセッション）が起動中の場合
            if (!e.sessionActive) {
                ; ■たった今起動した（前回まで落ちていた）場合
                e.sessionActive := true
                defVol := IniRead(INI_PATH, e.sec, "DefaultVolume", "")
                if (defVol != "") {
                    ; 保存されていた前回の音量に強制上書き（100%リセット対策）
                    SetAppVolume(e.process, Float(defVol))
                }
            } else {
                ; ■起動中の場合：ブースト中でなければ現在の音量を常に記憶する
                if (!e.boosting) {
                    e.lastVol := vol
                }
            }
        } else {
            ; プロセスが落ちている場合
            if (e.sessionActive) {
                ; ■たった今閉じた（終了した）場合
                e.sessionActive := false
                e.boosting := false ; ブースト状態もリセット
                if (e.lastVol > 0) {
                    ; 閉じる直前の「通常音量」をINIに保存
                    IniWrite(Round(e.lastVol, 4), INI_PATH, e.sec, "DefaultVolume")
                    
                    ; INIファイルが更新されたことでWatchINIが誤爆ループするのを防ぐため、スタンプを同期
                    g_iniStamp := FileGetTime(INI_PATH, "M")
                }
            }
        }
    }
}

; ==============================================================================
;  INI 監視
; ==============================================================================
WatchINI() {
    global INI_PATH, g_iniStamp
    if !FileExist(INI_PATH)
        return
    stamp := FileGetTime(INI_PATH, "M")
    if (stamp = g_iniStamp)
        return
    g_iniStamp := stamp
    for e in g_entries
        if e.boosting
            DoToggle(e)
    LoadINI()
}

; ==============================================================================
;  ホットキー登録
; ==============================================================================
RegisterHotkey(entry) {
    try Hotkey(entry.hotkey, MakeToggleFn(entry), "On")

    MakeToggleFn(e) {
        return (*) => DoToggle(e)
    }
}

; ==============================================================================
;  ブーストトグル
; ==============================================================================
DoToggle(e) {
    if !e.boosting {
        vol := GetAppVolume(e.process)
        if (vol <= 0.0)   ; 0 または取得失敗 → 弾く
            return
        e.saved    := vol
        e.boosting := true
        SetAppVolume(e.process, Min(vol * e.factor, 1.0))
    } else {
        e.boosting := false
        if (e.saved > 0.0)
            SetAppVolume(e.process, e.saved)
        e.saved := -1.0   ; リセット
    }
}

; ==============================================================================
;  Core Audio API
; ==============================================================================
MakeGUID(str) {
    buf := Buffer(16, 0)
    DllCall("ole32\CLSIDFromString", "wstr", str, "ptr", buf)
    return buf
}

GetAppVolume(processName) {
    iVol := GetISimpleAudioVolume(processName)
    if !iVol
        return -1
    vol := 0.0
    hr  := ComCall(4, iVol, "float*", &vol)
    ObjRelease(iVol)
    return (hr = 0) ? vol : -1
}

SetAppVolume(processName, level) {
    iVol := GetISimpleAudioVolume(processName)
    if !iVol
        return false
    hr := ComCall(3, iVol, "float", Max(0.0, Min(1.0, level)), "ptr", 0)
    ObjRelease(iVol)
    return (hr = 0)
}

GetISimpleAudioVolume(processName) {
    pEnum := ComObject(
        "{BCDE0395-E52F-467C-8E3D-C4579291692E}",
        "{A95664D2-9614-4F35-A746-DE8DB63617E6}"
    )
    pDevice := 0
    if (ComCall(4, pEnum, "int", 0, "int", 1, "ptr*", &pDevice) != 0 || !pDevice)
        return 0

    guidSM2 := MakeGUID("{77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F}")
    pSM2    := 0
    hr      := ComCall(3, pDevice, "ptr", guidSM2, "uint", 1, "ptr", 0, "ptr*", &pSM2)
    ObjRelease(pDevice)
    if (hr != 0 || !pSM2)
        return 0

    pSessEnum := 0
    hr := ComCall(5, pSM2, "ptr*", &pSessEnum)
    ObjRelease(pSM2)
    if (hr != 0 || !pSessEnum)
        return 0

    count := 0
    ComCall(3, pSessEnum, "int*", &count)

    targetPID := GetPIDByName(processName)
    result    := 0
    guidSC2   := MakeGUID("{BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D}")
    guidSAV   := MakeGUID("{87CE5498-68D6-44E5-9215-6DA47EF883D8}")

    loop count {
        pCtrl := 0
        ComCall(4, pSessEnum, "int", A_Index - 1, "ptr*", &pCtrl)
        if !pCtrl
            continue
    
        pCtrl2 := 0
        ComCall(0, pCtrl, "ptr", guidSC2, "ptr*", &pCtrl2)
        ObjRelease(pCtrl)
        if !pCtrl2
            continue
        pid := 0
        ComCall(14, pCtrl2, "uint*", &pid)
        if (pid = targetPID) {
            pVol := 0
     
            ComCall(0, pCtrl2, "ptr", guidSAV, "ptr*", &pVol)
            ObjRelease(pCtrl2)
            if pVol {
                result := pVol
                break
            }
        } else {
            ObjRelease(pCtrl2)
        }
    }

    ObjRelease(pSessEnum)
    return result
}

GetPIDByName(processName) {
    for proc in ComObjGet("winmgmts:").ExecQuery(
        "SELECT ProcessId FROM Win32_Process WHERE Name='" processName "'")
        return proc.ProcessId
    return 0
}