; ==============================================================================
;  VolumeBoost.ahk  –  常駐本体 (AutoHotkey v2)
;  複数アプリ対応 ＋ 終了時音量の自動保存・自動復元機能付き (完全検証・堅牢版)
; ==============================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
#NoTrayIcon

global INI_PATH   := A_ScriptDir "\VolumeBoost.ini"
global g_entries  := []
global g_iniStamp := 0

LoadINI()
SetTimer(WatchINI, 2000)
SetTimer(WatchProcesses, 500) ; 0.5秒間隔でプロセスと音量を監視

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
            
        ; 管理用パラメータ (restoreAttempts: アプリ初期化時の音量上書きをねじ伏せるためのカウンタ)
        entry := {sec: sec, process: proc, factor: factor, hotkey: hk,
                  boosting: false, saved: -1.0, sessionActive: false, lastVol: -1.0, 
                  restoreAttempts: 0, targetDefVol: 0.0}
        g_entries.Push(entry)
        RegisterHotkey(entry)
    }
}

; ==============================================================================
;  音量の自動保存＆復元ループ (オーディオセッション逆引き監視)
; ==============================================================================
WatchProcesses() {
    global INI_PATH, g_iniStamp
    for e in g_entries {
        vol := GetAppVolume(e.process)
        
        if (vol != -1) {
            ; ミキサー（オーディオセッション）にアプリが存在している場合
            if (!e.sessionActive) {
                ; ■再生が開始され、ミキサーに「たった今出現した」瞬間
                e.sessionActive := true
                defVol := IniRead(INI_PATH, e.sec, "DefaultVolume", "")
                if (defVol != "") {
                    e.targetDefVol := Float(defVol)
                    e.restoreAttempts := 4 ; アプリ自身の初期化上書きを防ぐため、今後2秒間(4回)強制適用する
                }
            }
            
            ; 復元（強制適用）モード中
            if (e.restoreAttempts > 0) {
                SetAppVolume(e.process, e.targetDefVol)
                e.restoreAttempts--
            } 
            ; 通常の監視モード（ブースト中でなければ音量を記憶）
            else if (!e.boosting) {
                e.lastVol := vol
            }
        } else {
            ; ミキサーにアプリが存在しない場合
            if (e.sessionActive) {
                ; ■ミキサーから消えた瞬間
                e.sessionActive := false
                e.boosting := false
                e.restoreAttempts := 0
                if (e.lastVol > 0) {
                    ; 消える直前の「通常音量」をINIに保存
                    IniWrite(Round(e.lastVol, 4), INI_PATH, e.sec, "DefaultVolume")
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
    e.restoreAttempts := 0 ; 手動操作が自動復元に上書きされないようキャンセル

    if !e.boosting {
        vol := GetAppVolume(e.process)
        if (vol <= 0.0)
            return
        e.saved    := vol
        e.boosting := true
        SetAppVolume(e.process, Min(vol * e.factor, 1.0))
    } else {
        e.boosting := false
        if (e.saved > 0.0)
            SetAppVolume(e.process, e.saved)
        e.saved := -1.0
    }
}

; ==============================================================================
;  Core Audio API (完全版：PID推測を廃止し、セッションからプロセス名を逆引き)
; ==============================================================================
MakeGUID(str) {
    buf := Buffer(16, 0)
    DllCall("ole32\CLSIDFromString", "wstr", str, "ptr", buf)
    return buf
}

GetAppVolume(processName) {
    if (processName = "")
        return -1

    pEnum := ComObject("{BCDE0395-E52F-467C-8E3D-C4579291692E}", "{A95664D2-9614-4F35-A746-DE8DB63617E6}")
    pDevice := 0
    if (ComCall(4, pEnum, "int", 0, "int", 1, "ptr*", &pDevice) != 0 || !pDevice)
        return -1

    guidSM2 := MakeGUID("{77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F}")
    pSM2 := 0
    hr := ComCall(3, pDevice, "ptr", guidSM2, "uint", 1, "ptr", 0, "ptr*", &pSM2)
    ObjRelease(pDevice)
    if (hr != 0 || !pSM2)
        return -1

    pSessEnum := 0
    hr := ComCall(5, pSM2, "ptr*", &pSessEnum)
    ObjRelease(pSM2)
    if (hr != 0 || !pSessEnum)
        return -1

    count := 0
    ComCall(3, pSessEnum, "int*", &count)

    result := -1
    guidSC2 := MakeGUID("{BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D}")
    guidSAV := MakeGUID("{87CE5498-68D6-44E5-9215-6DA47EF883D8}")

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
        
        ; セッションのPIDからプロセス名を直接取得して比較する（システム音のPID:0も弾く）
        if (pid > 0) {
            sName := ""
            try sName := ProcessGetName(pid)
            if (sName = processName) {
                pVol := 0
                ComCall(0, pCtrl2, "ptr", guidSAV, "ptr*", &pVol)
                if pVol {
                    vol := 0.0
                    if (ComCall(4, pVol, "float*", &vol) == 0)
                        result := vol
                    ObjRelease(pVol)
                }
                ObjRelease(pCtrl2)
                break
            }
        }
        ObjRelease(pCtrl2)
    }

    ObjRelease(pSessEnum)
    return result
}

SetAppVolume(processName, level) {
    if (processName = "")
        return false

    pEnum := ComObject("{BCDE0395-E52F-467C-8E3D-C4579291692E}", "{A95664D2-9614-4F35-A746-DE8DB63617E6}")
    pDevice := 0
    if (ComCall(4, pEnum, "int", 0, "int", 1, "ptr*", &pDevice) != 0 || !pDevice)
        return false

    guidSM2 := MakeGUID("{77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F}")
    pSM2 := 0
    hr := ComCall(3, pDevice, "ptr", guidSM2, "uint", 1, "ptr", 0, "ptr*", &pSM2)
    ObjRelease(pDevice)
    if (hr != 0 || !pSM2)
        return false

    pSessEnum := 0
    hr := ComCall(5, pSM2, "ptr*", &pSessEnum)
    ObjRelease(pSM2)
    if (hr != 0 || !pSessEnum)
        return false

    count := 0
    ComCall(3, pSessEnum, "int*", &count)

    success := false
    guidSC2 := MakeGUID("{BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D}")
    guidSAV := MakeGUID("{87CE5498-68D6-44E5-9215-6DA47EF883D8}")
    safeLevel := Max(0.0, Min(1.0, level))

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
        
        ; 該当するすべてのセッションに音量を適用する
        if (pid > 0) {
            sName := ""
            try sName := ProcessGetName(pid)
            if (sName = processName) {
                pVol := 0
                ComCall(0, pCtrl2, "ptr", guidSAV, "ptr*", &pVol)
                if pVol {
                    if (ComCall(3, pVol, "float", safeLevel, "ptr", 0) == 0)
                        success := true
                    ObjRelease(pVol)
                }
            }
        }
        ObjRelease(pCtrl2)
    }

    ObjRelease(pSessEnum)
    return success
}