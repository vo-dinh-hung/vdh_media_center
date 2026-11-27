;#RequireAdmin
#AutoIt3Wrapper_Res_HiDPI=Y
#include <GUIConstants.au3>
#include <ColorConstants.au3>
#include <EditConstants.au3>
#include <ButtonConstants.au3>
#include <GuiListBox.au3>
#include <WindowsConstants.au3>
#include <Constants.au3>
#include <Misc.au3>
#include <Array.au3>
#include <GuiMenu.au3>
#include <GuiTab.au3>
#include <GuiEdit.au3>
#include <WinAPI.au3>
#include <WinAPISys.au3>

; --- DIRECT LIBVLC WRAPPER (NO ACCESSIBILITY / NO PERCENTAGE) ---
; Mutex "chi cho 1 ban chay" - luu lai handle de _Quit_App co the NHA NGAY khi bat dau thoat,
; nhờ đó người dùng bấm Enter chạy lại ngay thì bản mới không bị chặn bởi bản cũ đang "đóng nốt".
Global $g_hSingletonMutex = 0

; Mac dinh van cho toi da 3 giay neu ban cu dang trong luc thoat (phong truong hop dua nhau),
; /restart thi cho lau hon (5 giay).
Local $iWaitMax = 30
If $CmdLine[0] > 0 Then
    For $i = 1 To $CmdLine[0]
        If $CmdLine[$i] = "/restart" Then
            $iWaitMax = 50 ; Wait up to 5 seconds for old instance to exit
            ExitLoop
        EndIf
    Next
EndIf

Local $iWaitCount = 0
While True
    $g_hSingletonMutex = _Singleton("VDHMediaCenterApp", 1)
    If $g_hSingletonMutex <> 0 Then ExitLoop
    If $iWaitCount >= $iWaitMax Then
        MsgBox(16, "Error", "Application is already running.")
        Exit
    EndIf
    Sleep(100)
    $iWaitCount += 1
WEnd

Global $hVLC_Dll = -1, $oVLC_Inst = 0, $oVLC_Player = 0
Global $g_sAudioDeviceID = ""
Global $sVLC_Path = ""
Global $g_iEqPreset = -1, $g_bNormalizeVolume = False ; Player tab: equalizer preset (-1 = off) and volume normalization
Global $g_iStereoMode = 0 ; Player tab: audio channel mode, 0 = Stereo, 1 = Reverse stereo, 2 = Left ear only, 3 = Right ear only, 4 = Mono

Func _VLC_Cleanup()
    If $oVLC_Player <> 0 Then
        DllCall($hVLC_Dll, "none:cdecl", "libvlc_media_player_stop", "ptr", $oVLC_Player)

        DllCall($hVLC_Dll, "none:cdecl", "libvlc_media_player_release", "ptr", $oVLC_Player)
        $oVLC_Player = 0
    EndIf

    If $oVLC_Inst <> 0 Then
        DllCall($hVLC_Dll, "none:cdecl", "libvlc_release", "ptr", $oVLC_Inst)
        $oVLC_Inst = 0
    EndIf

    If $hVLC_Dll <> -1 Then
        DllClose($hVLC_Dll)
        $hVLC_Dll = -1
    EndIf
EndFunc

Func _VLC_Direct_Init()
    If $hVLC_Dll <> -1 And $oVLC_Inst <> 0 Then Return True

    DllCall("kernel32.dll", "bool", "SetDllDirectoryW", "wstr", $sVLC_Path)

    Local $sDll = $sVLC_Path & "\libvlc.dll"
    If Not FileExists($sDll) Then Return False

    If $hVLC_Dll = -1 Then $hVLC_Dll = DllOpen($sDll)

    DllCall("kernel32.dll", "bool", "SetDllDirectoryW", "wstr", "")

    If $hVLC_Dll = -1 Then Return False

    Local $aOptions = [ _
        "vlc", _
        "--plugin-path=" & $sVLC_Path & "\plugins", _
        "--no-video-title-show", _
        "--audio-time-stretch", _
        "--clock-jitter=1000", _
        "--network-caching=1000", _
        "--file-caching=1000", _
        "--live-caching=1000", _
        "--no-stats" _
    ]

    If $g_sAudioDeviceID <> "" Then
        _ArrayAdd($aOptions, "--mmdevice-audio-device=" & $g_sAudioDeviceID)
    EndIf

    Local $iCount = UBound($aOptions)
    Local $tArgs = DllStructCreate("ptr[" & $iCount & "]")
    Local $aStructs[$iCount]

    For $i = 0 To $iCount - 1
        $aStructs[$i] = DllStructCreate("char[" & StringLen($aOptions[$i]) + 1 & "]")
        DllStructSetData($aStructs[$i], 1, $aOptions[$i])
        DllStructSetData($tArgs, 1, DllStructGetPtr($aStructs[$i]), $i + 1)
    Next

    Local $aRet = DllCall($hVLC_Dll, "ptr:cdecl", "libvlc_new", "int", $iCount, "ptr", DllStructGetPtr($tArgs))

    If @error Or Not $aRet[0] Then
        DllClose($hVLC_Dll)
        $hVLC_Dll = -1
        Return False
    EndIf
    $oVLC_Inst = $aRet[0]

    $aRet = DllCall($hVLC_Dll, "ptr:cdecl", "libvlc_media_player_new", "ptr", $oVLC_Inst)
    If @error Or Not $aRet[0] Then
        DllCall($hVLC_Dll, "none:cdecl", "libvlc_release", "ptr", $oVLC_Inst)
        $oVLC_Inst = 0
        DllClose($hVLC_Dll)
        $hVLC_Dll = -1
        Return False
    EndIf
    $oVLC_Player = $aRet[0]
    Return True
EndFunc

; Recreate the libvlc instance so that a new audio output device (Settings > Player) is used at once by the Player AND the
; Radio (they share one instance). libvlc.dll stays loaded: unloading it while VLC still has worker threads is unsafe.
Func _VLC_Reinit()
    If $hVLC_Dll = -1 Then Return _VLC_Direct_Init()
    _VLC_Direct_Stop()
    If $oVLC_Player <> 0 Then
        DllCall($hVLC_Dll, "none:cdecl", "libvlc_media_player_release", "ptr", $oVLC_Player)
        $oVLC_Player = 0
    EndIf
    If $oVLC_Inst <> 0 Then
        DllCall($hVLC_Dll, "none:cdecl", "libvlc_release", "ptr", $oVLC_Inst)
        $oVLC_Inst = 0
    EndIf
    Return _VLC_Direct_Init()
EndFunc

Func _VLC_GetAudioOutputs()
    Local $aResult[1][2] = [["", _T("Default Audio Device")]]
    If Not _VLC_Direct_Init() Then Return $aResult
    Local $aRet = DllCall($hVLC_Dll, "ptr:cdecl", "libvlc_audio_output_device_list_get", "ptr", $oVLC_Inst, "str", "mmdevice")
    If @error Or Not $aRet[0] Then Return $aResult
    Local $ptr = $aRet[0]
    While $ptr <> 0
        Local $tStruct = DllStructCreate("ptr p_next;ptr device_id;ptr description", $ptr)
        Local $pDevId = DllStructGetData($tStruct, "device_id")
        Local $pDesc = DllStructGetData($tStruct, "description")
        Local $sId = ""
        Local $sDesc = ""
        If $pDevId Then $sId = DllStructGetData(DllStructCreate("char[512]", $pDevId), 1)
        If $pDesc Then $sDesc = DllStructGetData(DllStructCreate("char[512]", $pDesc), 1)
        If $sId <> "" Then
            ReDim $aResult[UBound($aResult) + 1][2]
            $aResult[UBound($aResult) - 1][0] = $sId
            $aResult[UBound($aResult) - 1][1] = $sDesc
        EndIf
        $ptr = DllStructGetData($tStruct, "p_next")
    WEnd
    DllCall($hVLC_Dll, "none:cdecl", "libvlc_audio_output_device_list_release", "ptr", $aRet[0])
    Return $aResult
EndFunc

Func _VLC_Direct_GetRate()
    If Not $oVLC_Player Then Return 1.0
    Local $aRet = DllCall($hVLC_Dll, "float:cdecl", "libvlc_media_player_get_rate", "ptr", $oVLC_Player)
    If @error Then
        Return 1.0
    Else
        Return $aRet[0]
    EndIf
EndFunc

Func _VLC_Direct_Play($sUrl, $bAudioOnly = False)
    If Not _VLC_Direct_Init() Then Return

    Local $iState = _VLC_Direct_GetState()
    If $iState > 0 And $iState < 5 Then
        DllCall($hVLC_Dll, "none:cdecl", "libvlc_media_player_stop", "ptr", $oVLC_Player)
    EndIf

    ; $sUrl có thể gồm 2 dòng: dòng 1 = link video, dòng 2 = link audio riêng (YouTube DASH) -> ghép bằng input-slave
    Local $aUrlParts = StringSplit(StringStripWS(StringReplace($sUrl, @CR, ""), 3), @LF, 2)
    Local $aRet = DllCall($hVLC_Dll, "ptr:cdecl", "libvlc_media_new_location", "ptr", $oVLC_Inst, "str", $aUrlParts[0])
    Local $pMedia = $aRet[0]
    If Not $pMedia Then Return
    If UBound($aUrlParts) > 1 Then
        If StringStripWS($aUrlParts[1], 3) <> "" Then DllCall($hVLC_Dll, "none:cdecl", "libvlc_media_add_option", "ptr", $pMedia, "str", ":input-slave=" & StringStripWS($aUrlParts[1], 3))
    EndIf

    ; Volume normalization (Settings > Player): VLC's "normvol" audio filter, applied from this track on
    ; Version 3.2: voice enhancement adds the "compressor" filter (Settings > Player > Voice enhancement)
    Local $sAFilter = ""
    If $g_iVoiceMode > 0 Then $sAFilter = "compressor"
    If $g_bNormalizeVolume Then $sAFilter &= ($sAFilter = "" ? "" : ":") & "normvol"
    If $sAFilter <> "" Then DllCall($hVLC_Dll, "none:cdecl", "libvlc_media_add_option", "ptr", $pMedia, "str", ":audio-filter=" & $sAFilter)
    _Voice_AddMediaOptions($pMedia)

    ; Audio-only (Radio): never let libvlc open its own video window ("VLC (Direct3D11 output)"), it steals the keyboard focus.
    ; Also drop the stale window handle left over from the Player tab.
    If $bAudioOnly Then
        DllCall($hVLC_Dll, "none:cdecl", "libvlc_media_add_option", "ptr", $pMedia, "str", ":no-video")
        DllCall($hVLC_Dll, "none:cdecl", "libvlc_media_player_set_hwnd", "ptr", $oVLC_Player, "hwnd", 0)
    EndIf

    DllCall($hVLC_Dll, "none:cdecl", "libvlc_media_player_set_media", "ptr", $oVLC_Player, "ptr", $pMedia)

    DllCall($hVLC_Dll, "none:cdecl", "libvlc_media_release", "ptr", $pMedia)

    _VLC_ApplyEqualizer()
    _VLC_ApplyStereoMode()
    DllCall($hVLC_Dll, "int:cdecl", "libvlc_media_player_play", "ptr", $oVLC_Player)
EndFunc

Func _VLC_Direct_Stop()
    If $oVLC_Player Then
        Local $iState = _VLC_Direct_GetState()
        If $iState > 0 And $iState < 5 Then
            DllCall($hVLC_Dll, "none:cdecl", "libvlc_media_player_stop", "ptr", $oVLC_Player)
        EndIf
    EndIf
EndFunc

Func _VLC_Direct_Pause()
    If $oVLC_Player Then DllCall($hVLC_Dll, "none:cdecl", "libvlc_media_player_pause", "ptr", $oVLC_Player)
EndFunc

Func _VLC_Direct_GetTime()
    If Not $oVLC_Player Then Return 0
    Local $aRet = DllCall($hVLC_Dll, "int64:cdecl", "libvlc_media_player_get_time", "ptr", $oVLC_Player)
    Return $aRet[0]
EndFunc

Func _VLC_Direct_SetTime($iMS)
    If Not $oVLC_Player Then Return
    DllCall($hVLC_Dll, "none:cdecl", "libvlc_media_player_set_time", "ptr", $oVLC_Player, "int64", $iMS)
EndFunc

Func _VLC_Direct_GetLength()
    If Not $oVLC_Player Then Return 0
    Local $aRet = DllCall($hVLC_Dll, "int64:cdecl", "libvlc_media_player_get_length", "ptr", $oVLC_Player)
    Return $aRet[0]
EndFunc

; Chuyển % âm lượng hiển thị trên UI (0-100, tuyến tính) sang % gain thực gửi cho VLC,
; theo đường cong căn bậc ba giống Luna Player: rất thoải ở phần trên của thang,
; chỉ giảm rõ ở nửa dưới, và chỉ chạm 0 khi UI = 0 (không có "vách đá" giữa chừng).
Func _VolumeUIToVLC($iUIVol)
    If $iUIVol <= 0 Then Return 0
    Return Round(100 * ($iUIVol / 100) ^ (1 / 3))
EndFunc

Func _VLC_Direct_SetVolume($iVol)
    If Not $oVLC_Player Then Return
    DllCall($hVLC_Dll, "int:cdecl", "libvlc_audio_set_volume", "ptr", $oVLC_Player, "int", _VolumeUIToVLC($iVol))
EndFunc

; Mỗi lần nhấn Volume Up/Down đổi 5% (trên thang UI) ngay lập tức.
Func _StepAppVolume($iDirection) ; $iDirection: 1 = tăng, -1 = giảm
    $g_iAppVolume += $iDirection * 5
    If $g_iAppVolume > 100 Then $g_iAppVolume = 100
    If $g_iAppVolume < 0 Then $g_iAppVolume = 0
    _VLC_Direct_SetVolume($g_iAppVolume)
    _ReportStatus(_TF("Volume: {1}%", $g_iAppVolume), True)
EndFunc

; ======================================================================
; AUDIO PAN: Ctrl+Left / Ctrl+Right  (chi tac dong len am thanh cua CHINH app nay)
; libvlc 3.x khong co API pan/balance. Cach lam o day: Windows gom am thanh moi tien trinh thanh cac "audio session";
; moi session co IChannelAudioVolume (am luong rieng tung kenh Trai/Phai, 0.0 - 1.0, chi co the HA, khong the TANG).
; Ta tim session cua chinh tien trinh nay (luong phat cua VLC), tao mot IAudioClient phu "gia nhap" dung session do
; (cung GUID, cung thiet bi) de lay IChannelAudioVolume, roi dat muc kenh Trai/Phai.
; => NVDA, app khac, va am thanh he thong KHONG bi anh huong. Khong dong vao balance cua Windows.
; ======================================================================

Func _PanLog($sText)
    If Not $g_bPanDebug Then Return
    FileWriteLine($SETTINGS_DIR & "\pan_debug.log", @YEAR & "-" & @MON & "-" & @MDAY & " " & @HOUR & ":" & @MIN & ":" & @SEC & " " & $sText)
EndFunc

; Dia chi ham thu $iIndex trong vtable cua mot COM interface
Func _PanCOM_Fn($pObj, $iIndex)
    Local $iPtr = @AutoItX64 ? 8 : 4
    Local $pVtbl = DllStructGetData(DllStructCreate("ptr", $pObj), 1)
    Return DllStructGetData(DllStructCreate("ptr", $pVtbl + $iIndex * $iPtr), 1)
EndFunc

Func _PanCOM_Release(ByRef $pObj)
    If $pObj Then DllCallAddress("ulong", _PanCOM_Fn($pObj, 2), "ptr", $pObj)
    $pObj = 0
EndFunc

Func _PanGUID($sGuid)
    Local $tGuid = DllStructCreate("byte[16]")
    DllCall("ole32.dll", "long", "CLSIDFromString", "wstr", $sGuid, "ptr", DllStructGetPtr($tGuid))
    Return $tGuid
EndFunc

; Thiet bi phat ma VLC dang dung ($g_sAudioDeviceID, hoac thiet bi mac dinh). Tra ve IMMDevice* hoac 0.
Func _Pan_OpenDevice($sDevID)
    Local $tCLSID = _PanGUID("{BCDE0395-E52F-467C-8E3D-C4579291692E}") ; MMDeviceEnumerator
    Local $tIIDEnum = _PanGUID("{A95664D2-9614-4F35-A746-DE8DB63617E6}") ; IMMDeviceEnumerator
    Local $pEnum = 0, $pDev = 0
    Local $aR = DllCall("ole32.dll", "long", "CoCreateInstance", "ptr", DllStructGetPtr($tCLSID), "ptr", 0, "dword", 23, _
            "ptr", DllStructGetPtr($tIIDEnum), "ptr*", 0)
    If @error Then Return 0
    If $aR[0] <> 0 Then Return 0
    $pEnum = $aR[5]

    ; IMMDeviceEnumerator: 4 = GetDefaultAudioEndpoint(flow, role, **dev), 5 = GetDevice(id, **dev)
    If $sDevID <> "" Then
        $aR = DllCallAddress("long", _PanCOM_Fn($pEnum, 5), "ptr", $pEnum, "wstr", $sDevID, "ptr*", 0)
        If Not @error Then
            If $aR[0] = 0 Then $pDev = $aR[3]
        EndIf
    EndIf
    If Not $pDev Then
        $aR = DllCallAddress("long", _PanCOM_Fn($pEnum, 4), "ptr", $pEnum, "dword", 0, "dword", 0, "ptr*", 0) ; eRender, eConsole
        If Not @error Then
            If $aR[0] = 0 Then $pDev = $aR[4]
        EndIf
    EndIf
    _PanCOM_Release($pEnum)
    Return $pDev
EndFunc

; IMMDevice::Activate (vtable 3)
Func _PanActivate($pDev, $sIID)
    Local $tIID = _PanGUID($sIID)
    Local $aR = DllCallAddress("long", _PanCOM_Fn($pDev, 3), "ptr", $pDev, "ptr", DllStructGetPtr($tIID), "dword", 23, "ptr", 0, "ptr*", 0)
    If @error Then Return 0
    If $aR[0] <> 0 Then
        _PanLog("Activate " & $sIID & " failed hr=0x" & Hex($aR[0], 8))
        Return 0
    EndIf
    Return $aR[5]
EndFunc

; Liet ke GUID cac audio session cua CHINH tien trinh nay tren thiet bi (bo qua session da het han).
Func _Pan_MySessionGuids($pMgr)
    Local $aOut[0]
    Local $tIID2 = _PanGUID("{BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D}") ; IAudioSessionControl2
    Local $aR, $pSE = 0, $iCount = 0, $pCtl = 0, $pCtl2 = 0, $iPid = 0, $iState = 0, $pStr = 0, $sInst = "", $aM, $sGuid
    ; IAudioSessionManager2: 5 = GetSessionEnumerator
    $aR = DllCallAddress("long", _PanCOM_Fn($pMgr, 5), "ptr", $pMgr, "ptr*", 0)
    If @error Then Return $aOut
    If $aR[0] <> 0 Then Return $aOut
    $pSE = $aR[2]
    ; IAudioSessionEnumerator: 3 = GetCount, 4 = GetSession
    $aR = DllCallAddress("long", _PanCOM_Fn($pSE, 3), "ptr", $pSE, "int*", 0)
    If Not @error Then
        If $aR[0] = 0 Then $iCount = $aR[2]
    EndIf
    For $i = 0 To $iCount - 1
        $pCtl = 0
        $pCtl2 = 0
        $aR = DllCallAddress("long", _PanCOM_Fn($pSE, 4), "ptr", $pSE, "int", $i, "ptr*", 0)
        If @error Then ContinueLoop
        If $aR[0] <> 0 Then ContinueLoop
        $pCtl = $aR[3]
        $aR = DllCallAddress("long", _PanCOM_Fn($pCtl, 0), "ptr", $pCtl, "ptr", DllStructGetPtr($tIID2), "ptr*", 0) ; QueryInterface
        If Not @error Then
            If $aR[0] = 0 Then $pCtl2 = $aR[3]
        EndIf
        If $pCtl2 Then
            $iPid = 0
            $iState = 0
            $sInst = ""
            $aR = DllCallAddress("long", _PanCOM_Fn($pCtl2, 14), "ptr", $pCtl2, "dword*", 0) ; GetProcessId
            If Not @error Then
                If $aR[0] = 0 Then $iPid = $aR[2]
            EndIf
            $aR = DllCallAddress("long", _PanCOM_Fn($pCtl2, 3), "ptr", $pCtl2, "int*", 0) ; GetState (2 = expired)
            If Not @error Then
                If $aR[0] = 0 Then $iState = $aR[2]
            EndIf
            If $iPid = @AutoItPID And $iState <> 2 Then
                $aR = DllCallAddress("long", _PanCOM_Fn($pCtl2, 13), "ptr", $pCtl2, "ptr*", 0) ; GetSessionInstanceIdentifier
                If Not @error Then
                    If $aR[0] = 0 And $aR[2] Then
                        $pStr = $aR[2]
                        Local $aLen = DllCall("kernel32.dll", "int", "lstrlenW", "ptr", $pStr)
                        If Not @error Then $sInst = DllStructGetData(DllStructCreate("wchar[" & ($aLen[0] + 1) & "]", $pStr), 1)
                        DllCall("ole32.dll", "none", "CoTaskMemFree", "ptr", $pStr)
                    EndIf
                EndIf
                ; dang ...%b{GUID-cua-session}|...
                $sGuid = "{00000000-0000-0000-0000-000000000000}"
                $aM = StringRegExp($sInst, "%b(\{[0-9A-Fa-f\-]{36}\})", 1)
                If Not @error Then $sGuid = $aM[0]
                _PanLog("my session state=" & $iState & " id=" & $sInst)
                ReDim $aOut[UBound($aOut) + 1]
                $aOut[UBound($aOut) - 1] = $sGuid
            EndIf
        EndIf
        _PanCOM_Release($pCtl2)
        _PanCOM_Release($pCtl)
    Next
    _PanCOM_Release($pSE)
    Return $aOut
EndFunc

Func _Pan_HaveSession($sGuid)
    For $i = 0 To $g_iPanSess - 1
        If $g_aPanSess[$i][2] = $sGuid Then Return True
    Next
    Return False
EndFunc

Func _Pan_SetSessChan($pChanVol, $iCh, $fLevel)
    If $fLevel < 0 Then $fLevel = 0
    If $fLevel > 1 Then $fLevel = 1
    ; IChannelAudioVolume: 4 = SetChannelVolume(ch, level, ctx)
    Local $aR = DllCallAddress("long", _PanCOM_Fn($pChanVol, 4), "ptr", $pChanVol, "uint", $iCh, "float", $fLevel, "ptr", 0)
    If @error Then Return False
    Return ($aR[0] = 0)
EndFunc

; Gia nhap session $sGuid bang mot IAudioClient phu (khong Start) de lay IChannelAudioVolume cua session do.
Func _Pan_AddSession($pDev, $sGuid)
    Local $pCl = _PanActivate($pDev, "{1CB9AD4C-DBFA-4C32-B178-C2F568A703B2}") ; IAudioClient
    If Not $pCl Then Return False
    Local $tGuid = _PanGUID($sGuid)
    Local $pFmt = 0, $pCV = 0, $iHR = -1, $iCh = 0
    Local $aR = DllCallAddress("long", _PanCOM_Fn($pCl, 8), "ptr", $pCl, "ptr*", 0) ; GetMixFormat
    If Not @error Then
        If $aR[0] = 0 Then $pFmt = $aR[2]
    EndIf
    If Not $pFmt Then
        _PanCOM_Release($pCl)
        Return False
    EndIf
    ; Initialize(SHARED, NOPERSIST, 1s, 0, fmt, sessionGuid)
    $aR = DllCallAddress("long", _PanCOM_Fn($pCl, 3), "ptr", $pCl, "dword", 0, "dword", 0x00080000, "int64", 10000000, "int64", 0, _
            "ptr", $pFmt, "ptr", DllStructGetPtr($tGuid))
    If Not @error Then $iHR = $aR[0]
    DllCall("ole32.dll", "none", "CoTaskMemFree", "ptr", $pFmt)
    _PanLog("Initialize " & $sGuid & " hr=0x" & Hex($iHR, 8))
    If $iHR <> 0 Then
        _PanCOM_Release($pCl)
        Return False
    EndIf

    Local $tIIDCV = _PanGUID("{1C158861-B533-4B30-B1CF-E853E51C59B8}") ; IChannelAudioVolume
    $aR = DllCallAddress("long", _PanCOM_Fn($pCl, 14), "ptr", $pCl, "ptr", DllStructGetPtr($tIIDCV), "ptr*", 0) ; GetService
    If Not @error Then
        If $aR[0] = 0 Then $pCV = $aR[3]
    EndIf
    If $pCV Then
        $aR = DllCallAddress("long", _PanCOM_Fn($pCV, 3), "ptr", $pCV, "uint*", 0) ; GetChannelCount
        If Not @error Then
            If $aR[0] = 0 Then $iCh = $aR[2]
        EndIf
    EndIf
    _PanLog("channel count=" & $iCh)
    If Not $pCV Or $iCh < 2 Then
        _PanCOM_Release($pCV)
        _PanCOM_Release($pCl)
        Return False
    EndIf

    If $g_iPanSess >= 8 Then _Pan_DropSession(0)
    $g_aPanSess[$g_iPanSess][0] = $pCl
    $g_aPanSess[$g_iPanSess][1] = $pCV
    $g_aPanSess[$g_iPanSess][2] = $sGuid
    $g_iPanSess += 1
    Return True
EndFunc

; Tra kenh ve 1.0 va giai phong session thu $iIdx (dich cac muc phia sau len)
Func _Pan_DropSession($iIdx)
    Local $pCV = $g_aPanSess[$iIdx][1], $pCl = $g_aPanSess[$iIdx][0]
    _Pan_SetSessChan($pCV, 0, 1.0)
    _Pan_SetSessChan($pCV, 1, 1.0)
    _PanCOM_Release($pCV)
    _PanCOM_Release($pCl)
    For $i = $iIdx To $g_iPanSess - 2
        $g_aPanSess[$i][0] = $g_aPanSess[$i + 1][0]
        $g_aPanSess[$i][1] = $g_aPanSess[$i + 1][1]
        $g_aPanSess[$i][2] = $g_aPanSess[$i + 1][2]
    Next
    $g_iPanSess -= 1
EndFunc

; Dat muc kenh Trai/Phai theo $g_iPanStep cho moi session dang giu. Pan trai -> ha kenh Phai; pan phai -> ha kenh Trai.
Func _Pan_ApplyLevels()
    Local $fPan = $g_iPanStep * $PAN_INCREMENT
    If $g_bAutoPan Then $fPan = $g_fAutoPanPos
    Local $fL = 1.0, $fR = 1.0
    If $fPan < 0 Then $fR = 1.0 + $fPan
    If $fPan > 0 Then $fL = 1.0 - $fPan
    If $g_iStereoMode = 2 Then $fR = 0.0 ; left ear only: left channel stays, right ear is silent
    If $g_iStereoMode = 3 Then $fL = 0.0 ; right ear only: right channel stays, left ear is silent
    For $i = 0 To $g_iPanSess - 1
        _Pan_SetSessChan($g_aPanSess[$i][1], 0, $fL)
        _Pan_SetSessChan($g_aPanSess[$i][1], 1, $fR)
    Next
EndFunc

; Tim session cua VLC (xuat hien khi nhac bat dau phat, co the doi sang session moi khi VLC mo lai bo phat) va gan pan vao.
; $bForce: bo qua gioi han 1 lan/giay va ap lai muc cho moi session.
Func _Pan_Sync($bForce = False)
    If $g_iPanStep = 0 And $g_iPanSess = 0 And Not _StereoModeUsesSession() And Not $g_bAutoPan Then Return
    If Not $bForce And TimerDiff($g_hPanSyncTimer) < 1000 Then Return
    $g_hPanSyncTimer = TimerInit()

    Local $pDev = _Pan_OpenDevice($g_sAudioDeviceID)
    If Not $pDev Then
        _PanLog("no output device")
        Return
    EndIf
    Local $pMgr = _PanActivate($pDev, "{77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F}") ; IAudioSessionManager2
    Local $aGuids[0]
    If $pMgr Then $aGuids = _Pan_MySessionGuids($pMgr)
    _PanCOM_Release($pMgr)

    ; Session GUID 0 la session mac dinh (am bao cua app, PlaySound...). Neu VLC co session rieng thi chi pan session do;
    ; chi dung session mac dinh khi khong co session nao khac va nhac dang phat (truong hop VLC dung chung session mac dinh).
    Local $sZero = "{00000000-0000-0000-0000-000000000000}"
    Local $bPlaying = (_VLC_Direct_GetState() = 3)
    Local $bNonZero = False
    For $i = 0 To UBound($aGuids) - 1
        If $aGuids[$i] <> $sZero Then $bNonZero = True
    Next
    Local $bAdded = False
    For $i = 0 To UBound($aGuids) - 1
        If $aGuids[$i] = $sZero And ($bNonZero Or Not $bPlaying) Then ContinueLoop
        If _Pan_HaveSession($aGuids[$i]) Then ContinueLoop
        If _Pan_AddSession($pDev, $aGuids[$i]) Then $bAdded = True
    Next
    _PanCOM_Release($pDev)
    If $bAdded Or $bForce Then _Pan_ApplyLevels()
EndFunc

; Tra am thanh ve binh thuong va giai phong moi thu. An toan khi goi nhieu lan.
Func _Pan_Reset()
    While $g_iPanSess > 0
        _Pan_DropSession($g_iPanSess - 1)
    WEnd
    $g_iPanStep = 0
    $g_fPan = 0.0
    $g_fAutoPanPhase = 0.0
    $g_fAutoPanPos = 0.0
EndFunc

Func _PanStatusText()
    ; Doc chu "Pan" truoc phan tram: "Pan 0%", "Pan -5%" (trai), "Pan 5%" (phai)
    Local $iPct = Round($g_iPanStep * $PAN_INCREMENT * 100)
    Return _TF("Pan {1}%", $iPct)
EndFunc

; $iDirection: -1 = nhich sang trai, 1 = nhich sang phai (moi lan 0.05, ket o -1.0 / 1.0)
Func _StepPan($iDirection)
    ; Auto pan dang bat (Settings > Player): am thanh tu troi, Ctrl+Left / Ctrl+Right khong lam gi
    If $g_bAutoPan Then Return
    Local $iNew = $g_iPanStep + $iDirection
    If $iNew > $PAN_MAX_STEPS Then $iNew = $PAN_MAX_STEPS
    If $iNew < -$PAN_MAX_STEPS Then $iNew = -$PAN_MAX_STEPS
    If $iNew <> $g_iPanStep Then
        $g_iPanStep = $iNew
        $g_fPan = Round($iNew * $PAN_INCREMENT, 2)
        _Pan_Sync(True)
    EndIf
    ; Nhac dang phat ma khong gan duoc vao luong cua VLC -> bao thay vi im lang
    If $g_iPanStep <> 0 And $g_iPanSess = 0 And _VLC_Direct_GetState() = 3 Then
        _ReportStatus(_T("Pan could not be applied to the music"))
    Else
        _ReportStatus(_PanStatusText(), False, True)
    EndIf
EndFunc

; Auto pan: moi ~50ms (chi khi nhac dang phat) dich vi tri pan theo hinh sin giua -1.0 (trai) va 1.0 (phai).
; Goi trong vong lap cua trinh phat. $iState = trang thai VLC (3 = dang phat).
Func _AutoPan_Tick($iState)
    If Not $g_bAutoPan Then Return
    If $g_hAutoPanTimer = 0 Then $g_hAutoPanTimer = TimerInit()
    Local $fDiff = TimerDiff($g_hAutoPanTimer)
    If $fDiff < 50 Then Return
    $g_hAutoPanTimer = TimerInit()
    If $iState <> 3 Then Return ; tam dung / dung -> giu nguyen vi tri, khong troi
    $g_fAutoPanPhase += $fDiff / ($g_iAutoPanPeriod * 1000)
    If $g_fAutoPanPhase >= 1.0 Then $g_fAutoPanPhase -= Floor($g_fAutoPanPhase)
    Local $fNew = Round(Sin(6.28318530718 * $g_fAutoPanPhase), 3)
    If $fNew = $g_fAutoPanPos Then Return
    $g_fAutoPanPos = $fNew
    If $g_iPanSess > 0 Then _Pan_ApplyLevels()
EndFunc

; Names of the equalizer presets built into libvlc (read from libvlc itself, with a fixed fallback list)
Func _EQ_PresetNames()
    Local $sFallback = "Flat|Classical|Club|Dance|Full bass|Full bass and treble|Full treble|Headphones|Large Hall|Live|Party|Pop|Reggae|Rock|Ska|Soft|Soft rock|Techno"
    If $hVLC_Dll = -1 Then Return $sFallback
    Local $aCnt = DllCall($hVLC_Dll, "uint:cdecl", "libvlc_audio_equalizer_get_preset_count")
    If @error Or Not IsArray($aCnt) Or $aCnt[0] <> 18 Then Return $sFallback
    Local $sNames = ""
    For $i = 0 To 17
        Local $aName = DllCall($hVLC_Dll, "str:cdecl", "libvlc_audio_equalizer_get_preset_name", "uint", $i)
        If @error Or Not IsArray($aName) Or $aName[0] = "" Then Return $sFallback
        $sNames &= StringReplace($aName[0], "|", "/") & "|"
    Next
    Return StringTrimRight($sNames, 1)
EndFunc

; Applies the equalizer preset chosen in Settings > Player (or switches the equalizer off)
Func _VLC_ApplyEqualizer()
    If Not $oVLC_Player Then Return
    Local $pEq = 0
    If $g_iEqPreset >= 0 Then
        Local $aEq = DllCall($hVLC_Dll, "ptr:cdecl", "libvlc_audio_equalizer_new_from_preset", "uint", $g_iEqPreset)
        If Not @error And IsArray($aEq) Then $pEq = $aEq[0]
    ElseIf $g_iEqPreset = -2 Then
        Local $aEq2 = DllCall($hVLC_Dll, "ptr:cdecl", "libvlc_audio_equalizer_new")
        If Not @error And IsArray($aEq2) Then
            $pEq = $aEq2[0]
            If $pEq Then
                DllCall($hVLC_Dll, "int:cdecl", "libvlc_audio_equalizer_set_preamp", "ptr", $pEq, "float", $g_fEqPreamp)
                For $iBand = 0 To 9
                    DllCall($hVLC_Dll, "int:cdecl", "libvlc_audio_equalizer_set_amp_at_index", "ptr", $pEq, "float", $g_aEqBands[$iBand], "uint", $iBand)
                Next
            EndIf
        EndIf
    ElseIf $g_iVoiceMode > 0 Then
        Local $aEqV = DllCall($hVLC_Dll, "ptr:cdecl", "libvlc_audio_equalizer_new")
        If Not @error And IsArray($aEqV) Then
            $pEq = $aEqV[0]
            If $pEq Then _Voice_FillEq($pEq)
        EndIf
    EndIf
    DllCall($hVLC_Dll, "int:cdecl", "libvlc_media_player_set_equalizer", "ptr", $oVLC_Player, "ptr", $pEq)
    If $pEq Then DllCall($hVLC_Dll, "none:cdecl", "libvlc_audio_equalizer_release", "ptr", $pEq)
EndFunc

; Applies the audio channel mode chosen in Settings > Player. libvlc "stereo-mode" values:
; 1 = Stereo, 2 = Reverse stereo, 7 = Mono
; "Left ear only" / "Right ear only" (modes 2, 3) keep VLC on plain stereo (1) and silence the other side
; through the per-channel volume of the app's audio session (see _Pan_ApplyLevels)
Func _VLC_StereoModeValue()
    Local $aMap[5] = [1, 2, 1, 1, 7]
    Local $iMode = $g_iStereoMode
    If $iMode < 0 Or $iMode > 4 Then $iMode = 0
    Return $aMap[$iMode]
EndFunc

; True when the chosen audio channel mode needs the audio-session channel volumes (left ear only / right ear only)
Func _StereoModeUsesSession()
    Return ($g_iStereoMode = 2 Or $g_iStereoMode = 3)
EndFunc

; Returns True when VLC accepted the mode (its audio output exists); otherwise the caller retries later
Func _VLC_ApplyStereoMode()
    If Not $oVLC_Player Then Return False
    Local $aR = DllCall($hVLC_Dll, "int:cdecl", "libvlc_audio_set_channel", "ptr", $oVLC_Player, "int", _VLC_StereoModeValue())
    If @error Or Not IsArray($aR) Then Return False
    Return ($aR[0] = 0)
EndFunc

; Called every 0.5s while a track is playing. VLC creates (and sometimes re-creates) its audio output after the track
; starts and the ":stereo-mode" media option is ignored, so the mode is read back from VLC and re-applied whenever it
; differs from the one chosen in Settings (reading is free; setting only happens when needed).
Func _VLC_StereoMode_Retry()
    If Not $oVLC_Player Then Return
    If _VLC_Direct_GetState() <> 3 Then Return
    Local $aR = DllCall($hVLC_Dll, "int:cdecl", "libvlc_audio_get_channel", "ptr", $oVLC_Player)
    If @error Or Not IsArray($aR) Then Return
    If $aR[0] <> _VLC_StereoModeValue() Then _VLC_ApplyStereoMode()
EndFunc

Func _VLC_Direct_SetRate($fRate)
    If Not $oVLC_Player Then Return
    DllCall($hVLC_Dll, "int:cdecl", "libvlc_media_player_set_rate", "ptr", $oVLC_Player, "float", $fRate)
EndFunc

Func _VLC_Direct_GetState()
    If Not $oVLC_Player Then Return 0
    Local $aRet = DllCall($hVLC_Dll, "int:cdecl", "libvlc_media_player_get_state", "ptr", $oVLC_Player)
    ; libvlc_state: 3=Playing, 4=Paused, 5=Stopped, 6=Ended, 7=Error
    Return $aRet[0]
EndFunc

FileChangeDir(@ScriptDir)

Local $aGlobalMsgs = [0x0100, 0x0101, 0x0102, 0x0104, 0x0105, 0x010D, 0x010E, 0x010F, 0x0281, 0x0282, 0x0283, 0x0284, 0x0285, 0x0286, 0x0288, 0x0290, 0x0291, 0x004A, 0x003D, 0x0302, 0x0303, 0x0304, 0x0305]
For $iMsg In $aGlobalMsgs
    DllCall("user32.dll", "bool", "ChangeWindowMessageFilter", "uint", $iMsg, "dword", 1)
Next

Global $version = "3.2"
Global $YT_DLP_PATH = @ScriptDir & "\lib\yt-dlp.exe"
; Tiện ích lấy phụ đề YouTube (được đóng gói từ youtube_transcript.py).
Global $YT_TRANSCRIPT_EXE = @ScriptDir & "\lib\youtube_transcript.exe"
Global $LYRICS_EXE_PATH = @ScriptDir & "\lib\lyrics.exe" ; built from lyrics.py

; --- JS runtime cho yt-dlp (khắc phục cảnh báo "No supported JavaScript runtime could be found") ---
; yt-dlp cần một runtime JS (deno hoặc node) để giải mã một số định dạng của YouTube.
; Nếu có sẵn lib\deno.exe (bản portable, không cần cài đặt) thì dùng nó; nếu không, thử deno/node có sẵn trong PATH hệ thống.
Global $YT_DENO_PATH = @ScriptDir & "\lib\deno.exe"
Global $YT_NODE_PATH = @ScriptDir & "\lib\node.exe"
Global $YT_JS_RUNTIME_ARG = ""
If FileExists($YT_DENO_PATH) Then
    $YT_JS_RUNTIME_ARG = ' --js-runtimes "deno:' & $YT_DENO_PATH & '"'
ElseIf FileExists($YT_NODE_PATH) Then
    $YT_JS_RUNTIME_ARG = ' --js-runtimes "node:' & $YT_NODE_PATH & '"'
ElseIf _YT_IsInPath("deno.exe") Then
    $YT_JS_RUNTIME_ARG = ' --js-runtimes deno'
ElseIf _YT_IsInPath("node.exe") Then
    $YT_JS_RUNTIME_ARG = ' --js-runtimes node'
EndIf

; Chuỗi gọi yt-dlp.exe kèm sẵn tham số js-runtimes (dùng thay cho '"' & $YT_DLP_PATH & '"' ở mọi lệnh gọi yt-dlp)
Global $YT_DLP_EXE = '"' & $YT_DLP_PATH & '"' & $YT_JS_RUNTIME_ARG

; Kiểm tra 1 exe có tồn tại trong PATH hệ thống hay không
Func _YT_IsInPath($sExeName)
    Local $sResult = EnvGet("PATH")
    If $sResult = "" Then Return False
    Local $aPaths = StringSplit($sResult, ";", 2)
    For $sDir In $aPaths
        If $sDir <> "" And FileExists($sDir & "\" & $sExeName) Then Return True
    Next
    Return False
EndFunc
Global $FFMPEG_PATH = @ScriptDir & "\lib\ffmpeg.exe"
Global $DESC_EXE_PATH = @ScriptDir & "\lib\description.exe"
Global $COMMENTS_EXE_PATH = @ScriptDir & "\lib\comments.exe"
Global $VOICE_SEARCH_EXE_PATH = @ScriptDir & "\lib\voice_search.exe"
Global $g_hNVDADll = -1
Global $oVoice = 0

Global $aSearchIds[1]
Global $aSearchTitles[1]
Global $aSearchTypes[1]
Global $sCurrentKeyword = ""
Global $iTotalLoaded = 0
Global $bIsSearching = False
Global $bEndReached = False
Global $g_bAutoPlay = False
Global $g_bRepeat = False
Global $g_iFFStep = 5
Global $g_iRWStep = 5
Global $g_iSeekStep = 10
Global $g_iAppVolume = 100 ; Thêm biến track Volume ảo lên tới 100%

; --- Audio pan (Ctrl+Left / Ctrl+Right) ---
Global Const $PAN_INCREMENT = 0.05   ; mỗi lần nhấn phím đổi 0.05
Global Const $PAN_MAX_STEPS = 20     ; 20 bước x 0.05 = 1.0 (giới hạn biên)
Global $g_iPanStep = 0               ; số bước hiện tại (-20..20). Dùng số nguyên để số thực không bị trôi (0.05 x n)
Global $g_fPan = 0.0                 ; -1.0 = hoàn toàn trái, 0.0 = cân bằng (mặc định), 1.0 = hoàn toàn phải
Global $g_aPanSess[8][3]             ; các phiên âm thanh (session) của CHÍNH app này đang được pan: [i][0]=IAudioClient, [1]=IChannelAudioVolume, [2]=GUID
Global $g_iPanSess = 0
Global $g_hPanSyncTimer = 0
; --- Auto pan (Settings > Player): am thanh tu dong troi qua lai giua tai trai va tai phai khi dang phat nhac ---
Global $g_bAutoPan = False           ; settings.ini: [Settings] AutoPan=true. Khi bat, Ctrl+Left / Ctrl+Right khong con tac dung
Global $g_iAutoPanPeriod = 8        ; giay cho mot vong trai -> phai -> trai (1-60). settings.ini: [Settings] AutoPanPeriod. Chi chinh duoc khi Auto pan dang duoc check trong Settings
Global $g_fAutoPanPhase = 0.0        ; 0.0 - 1.0, chi tang khi nhac dang phat
Global $g_fAutoPanPos = 0.0          ; vi tri pan hien tai khi auto pan (-1.0 .. 1.0)
Global $g_hAutoPanTimer = 0
Global $g_bPanDebug = False          ; settings.ini: [Settings] PanDebug=true -> ghi %AppData%\VDHMediaCenter\pan_debug.log


Global $mainform
Global $cbo_dl_format, $btn_start_dl, $openbtn, $paste
Global $linkedit, $play_btn, $online_play_btn
Global $btn_Menu_Audio
Global $g_sSupportedAudioExts = ".mp3;.m4a;.wav;.ogg;.flac;.aac;.wma;.opus;.mp4;"
; Các định dạng mà tính năng Download thực sự tạo ra (khớp với $cbo_dl_format/$cboFormat:
; M4A, MP3, MP4, OGG, WAV, WebM), cộng thêm file dở dang do yt-dlp sinh ra trong lúc tải
; (*.part, *.ytdl). Dùng để lọc khi dọn file mới khi người dùng hủy tải, tránh xóa nhầm
; các file định dạng khác không phải do lần tải đó tạo ra.
Global $g_sDownloadSupportedExts = ".mp3;.wav;.m4a;.ogg;.mp4;.webm;.part;.ytdl;"
Global $inp_search, $btn_search_go, $lst_results, $btn_search_hist
Global $hDummyLoadMore = 0
Global $hCurrentSubGui = 0
Global $hResultsGui = 0
Global $hFavoritesGui = 0
Global $hHistoryGui = 0
Global $hSearchHistoryGui = 0
Global $hPlayGui = 0, $oVLCCtrl = 0
Global $g_hStatusLabel = 0, $g_lblPlayerInfo = 0, $g_lblAuto = 0, $g_lblRepeat = 0
Global $g_lblTimeInfo = 0, $g_sLastTimeInfo = "", $g_lblHint = 0 ; on-screen state/position line and key hint in the player window
Global $menu_item_download = -1, $menu_item_channel = -1, $menu_item_browser = -1, $menu_item_copy = -1, $menu_item_desc = -1, $menu_item_comments = -1, $menu_item_transcript = -1, $menu_item_fav = -1, $menu_item_goto = -1, $menu_share_telegram = -1, $menu_share_facebook = -1, $menu_item_sleeptimer = -1, $menu_item_fileinfo = -1
Global $menu_item_add_col = -1, $menu_item_remove_col = -1
Global $g_fSelectionStart = -1, $g_fSelectionEnd = -1
Global $g_fPitch = 1.0
Global $g_bCinemaMode = False
Global $g_iOriginalX, $g_iOriginalY, $g_iOriginalW, $g_iOriginalH
Global $hDummySpace, $hDummyEnter, $hDummyN, $hDummyUp, $hDummyDown, $hDummyLeft, $hDummyRight, $hDummyAltO
Global $hDummyCtrlLeft, $hDummyCtrlRight, $hDummyCtrlT, $hDummyCtrlShiftT, $hDummyHome, $hDummyEnd
Global $hDummyI
Global $hDummyC
Global $hDummy1, $hDummy2, $hDummy3, $hDummy4, $hDummy5, $hDummy6, $hDummy7, $hDummy8, $hDummy9, $hDummyP
Global $hDummyR, $hDummyRemaining, $hDummyShiftN, $hDummyShiftB, $hDummyCtrlW, $hDummyMinus, $hDummyEqual, $hDummyS, $hDummyD, $hDummyF, $hDummyCtrlShiftE, $hDummyEsc, $hDummyG, $hDummyApps, $hDummyBracketLeft, $hDummyBracketRight, $hDummyCtrlS, $hDummyCtrlK, $hDummyCtrlC, $hDummyCtrlShiftC, $hDummyCtrlShiftD, $hDummyAltB, $hDummyAltG, $hDummyAltLeft, $hDummyAltRight
Global $hDummyB ; "b" key: previous track (only active while a folder playlist is loaded)
Global $hDummyCtrlHome, $hDummyCtrlEnd ; Ctrl+Home/Ctrl+End: first/last track (folder playlist only)
Global $hDummyCtrlAltT ; Ctrl+Alt+T: mở Video Transcript
Global $hDummyCtrlAltL ; Ctrl+Alt+L: View Lyrics
Global $hDummyEq ; Ctrl+E: Equalizer
Global $menu_item_lyrics = -1 ; Options > View Lyrics...
; --- Play queue (first in, first out; kept in memory, same 1-based layout as $aSearchIds) ---
Global $g_aQueueIds[1] = [""], $g_aQueueTitles[1] = [""], $g_iQueueCount = 0
Global $menu_item_queue_add = -1, $menu_item_queue_view = -1 ; Options > Add to queue / Play queue
Global $hDummyCtrlQ = 0, $hDummyCtrlShiftQ = 0 ; Ctrl+Q: add to queue, Ctrl+Shift+Q: open the play queue
; --- Download queue (first in, first out; kept in memory, same 1-based layout as the play queue) ---
Global $g_aDQIds[1] = [""], $g_aDQTitles[1] = [""], $g_iDQCount = 0
Global $menu_item_dq_add = -1 ; Options > Add to download queue
Global $g_bTrackEnded = False ; True when _PlayInternal left because the track ended by itself (not stopped by the user)
Global $g_aLocalPlaylist[1] = [""]
Global $g_iLocalPlaylistCount = 0
Global $g_bLocalPlaylistMode = False ; True only while playing a folder-loaded playlist (enables n/b navigation)
Global $g_sLastReportedText = "", $g_iLastReportedTime = 0
Global $g_sCurrentVideoTitle = ""
Global $g_sSearchFilter = "No Filter"
Global $g_hSettingsGui, $g_hSettingsTab, $g_hSettingsDummyNext, $g_hSettingsDummyPrev
Global $g_aSettingsHelp[80][2], $g_iSettingsHelpCount = 0 ; [handle điều khiển, nội dung mô tả] cho phím F1 trong Settings
Global $g_hGuiDL, $g_hTabDL, $g_hDummyNextDL, $g_hDummyPrevDL

Global $g_iSleepTimerDuration = 0
Global $g_hSleepTimerInit = 0
Global $g_hSearchEditCallback = 0
Global $g_pOldSearchEditProc = 0

Global $SETTINGS_DIR = @AppDataDir & "\VDHMediaCenter"
If Not FileExists($SETTINGS_DIR) Then DirCreate($SETTINGS_DIR)

Global $FAVORITES_FILE = $SETTINGS_DIR & "\favorites.dat"
Global $HISTORY_FILE = $SETTINGS_DIR & "\watch_history.dat"
Global $SEARCH_HISTORY_FILE = $SETTINGS_DIR & "\search_history.dat"
Global $CONFIG_FILE = $SETTINGS_DIR & "\settings.ini"
Global $COLLECTIONS_DIR = $SETTINGS_DIR & "\Collections"
Global $PLAYBACK_POSITIONS_FILE = $SETTINGS_DIR & "\playback_positions.dat"

Func _MigrateFiles()
    Local $aFilesToMove[5] = ["settings.ini", "favorites.dat", "watch_history.dat", "search_history.dat", "playback_positions.dat"]
    For $sFile In $aFilesToMove
        If FileExists(@ScriptDir & "\" & $sFile) And Not FileExists($SETTINGS_DIR & "\" & $sFile) Then
            FileMove(@ScriptDir & "\" & $sFile, $SETTINGS_DIR & "\" & $sFile, 1)
        EndIf
    Next
    If FileExists(@ScriptDir & "\history.dat") And Not FileExists($HISTORY_FILE) Then
        FileMove(@ScriptDir & "\history.dat", $HISTORY_FILE, 1)
    EndIf
    If FileExists(@ScriptDir & "\Collections") And Not FileExists($COLLECTIONS_DIR) Then
        DirMove(@ScriptDir & "\Collections", $COLLECTIONS_DIR, 1)
    EndIf
EndFunc
_MigrateFiles()

If Not FileExists($COLLECTIONS_DIR) Then DirCreate($COLLECTIONS_DIR)
Global $g_bTypingSoundEnabled = IniRead($CONFIG_FILE, "Settings", "TypingSoundEnabled", "true") == "true"
Global $g_sTypingSoundSet = IniRead($CONFIG_FILE, "Settings", "TypingSoundSet", "1blueSwitch")
Global $g_sTypingSoundDir = @ScriptDir & "\sounds\" & $g_sTypingSoundSet & "\"
Global $g_bTypingSoundRandom = FileExists($g_sTypingSoundDir & "typing_1.wav")
Global $g_sSoundFile_Space = ""
Global $g_sSoundFile_Delete = ""
Global $g_sSoundFile_Typing = ""

Func _ResolveTypingSounds()
    $g_sTypingSoundDir = @ScriptDir & "\sounds\" & $g_sTypingSoundSet & "\"
    $g_bTypingSoundRandom = FileExists($g_sTypingSoundDir & "typing_1.wav")

    ; Tìm file cho phím Space
    If FileExists($g_sTypingSoundDir & "space.wav") Then
        $g_sSoundFile_Space = $g_sTypingSoundDir & "space.wav"
    ElseIf FileExists($g_sTypingSoundDir & "Space.wav") Then
        $g_sSoundFile_Space = $g_sTypingSoundDir & "Space.wav"
    Else
        $g_sSoundFile_Space = ""
    EndIf

    ; Tìm file cho phím Backspace/Delete
    If FileExists($g_sTypingSoundDir & "delete.wav") Then
        $g_sSoundFile_Delete = $g_sTypingSoundDir & "delete.wav"
    ElseIf FileExists($g_sTypingSoundDir & "Delete.wav") Then
        $g_sSoundFile_Delete = $g_sTypingSoundDir & "Delete.wav"
    Else
        $g_sSoundFile_Delete = ""
    EndIf

    ; Tìm file cho phím thường
    If FileExists($g_sTypingSoundDir & "typing.wav") Then
        $g_sSoundFile_Typing = $g_sTypingSoundDir & "typing.wav"
    ElseIf FileExists($g_sTypingSoundDir & "Typing.wav") Then
        $g_sSoundFile_Typing = $g_sTypingSoundDir & "Typing.wav"
    Else
        $g_sSoundFile_Typing = ""
    EndIf
EndFunc

_ResolveTypingSounds()
Global $g_iLastSoundTime = 0
Global $g_iSoundLock = 0
Global $g_iLastHookTime = 0
Global $g_iLastVkCode = 0
Global $g_bAutoUpdate = IniRead($CONFIG_FILE, "Settings", "AutoUpdate", "true") == "true"
Global $g_bAutoUpdateYTDLP = IniRead($CONFIG_FILE, "Settings", "AutoUpdateYTDLP", "true") == "true"
Global $g_bMuteAppSounds = IniRead($CONFIG_FILE, "Settings", "MuteAppSounds", "false") == "true" ; Tắt toàn bộ âm thanh trong thư mục sounds (trừ âm thanh bàn phím)
Global $g_bShowLicenseConfirm = IniRead($CONFIG_FILE, "Settings", "ShowLicenseConfirm", "true") == "true" ; Bat/tat buoc xac nhan license khi mo phan mem; tat thi khong phat dooropen.wav va vao phan mem luon
Global $g_bShowLogo = IniRead($CONFIG_FILE, "Settings", "ShowLogo", "true") == "true" ; Bật/tắt logo khởi động; tắt thì chỉ phát âm thanh cửa rồi vào phần mềm
Global $g_bSaveHistory = IniRead($CONFIG_FILE, "Settings", "SaveHistory", "true") == "true"
Global $g_bSaveSearchHistory = IniRead($CONFIG_FILE, "Settings", "SaveSearchHistory", "true") == "true"
Global $g_iUpdateBytesRead = 0
Global $g_iUpdateFileSize = 0
Global $g_iUpdatePct = 0
Global $g_sUpdateStatus = ""
Global $g_bAutoStart = IniRead($CONFIG_FILE, "Settings", "AutoStart", "false") == "true"
Global $g_bSkipSilence = IniRead($CONFIG_FILE, "Settings", "SkipSilence", "false") == "true"
Global $g_iAnnouncementMode = Int(IniRead($CONFIG_FILE, "Settings", "AnnouncementMode", "0"))
Global $g_sAudioDeviceID = IniRead($CONFIG_FILE, "Settings", "AudioDeviceID", "")
Global $g_iAfterVideoAction = Int(IniRead($CONFIG_FILE, "Settings", "AfterVideoAction", "2")) ; 0: Close, 1: Replay, 2: Do nothing
Global $g_iPlayAction = Int(IniRead($CONFIG_FILE, "Settings", "PlayAction", "0")) ; Nút Play trong hộp thoại tải xong: 0 = trình phát mặc định của máy tính, 1 = trình phát mặc định của ứng dụng
Global $g_bAutoDetectLink = IniRead($CONFIG_FILE, "Settings", "AutoDetectLink", "true") == "true"
Global $g_bVoiceAutoSearch = IniRead($CONFIG_FILE, "Settings", "VoiceAutoSearch", "true") == "true"
Global $g_bAutoPlay = IniRead($CONFIG_FILE, "Settings", "AutoPlay", "false") == "true"
Global $g_bRepeat = IniRead($CONFIG_FILE, "Settings", "Repeat", "false") == "true"
Global $g_sSearchFilter = IniRead($CONFIG_FILE, "Settings", "SearchFilter", "No Filter")
Global $g_sDownloadPath = IniRead($CONFIG_FILE, "Settings", "DownloadPath", @ScriptDir & "\download")
If StringStripWS($g_sDownloadPath, 3) = "" Then $g_sDownloadPath = @ScriptDir & "\download"
Global $PLAYBACK_POSITIONS_FILE = $SETTINGS_DIR & "\playback_positions.dat"
Global $g_bContinueWatching = IniRead($CONFIG_FILE, "Settings", "ContinueWatching", "true") == "true"
$g_iEqPreset = Int(IniRead($CONFIG_FILE, "Settings", "EqualizerPreset", "-1"))
If $g_iEqPreset < -2 Or $g_iEqPreset > 17 Then $g_iEqPreset = -1
$g_bNormalizeVolume = IniRead($CONFIG_FILE, "Settings", "NormalizeVolume", "false") == "true"
$g_iStereoMode = Int(IniRead($CONFIG_FILE, "Settings", "StereoMode", "0"))
If $g_iStereoMode < 0 Or $g_iStereoMode > 4 Then $g_iStereoMode = 0
$g_iFFStep = Int(IniRead($CONFIG_FILE, "Settings", "FFStep", "5"))
$g_iRWStep = Int(IniRead($CONFIG_FILE, "Settings", "RWStep", "5"))
$g_iSeekStep = $g_iFFStep
$g_bPanDebug = IniRead($CONFIG_FILE, "Settings", "PanDebug", "false") == "true"
$g_bAutoPan = IniRead($CONFIG_FILE, "Settings", "AutoPan", "false") == "true"
$g_iAutoPanPeriod = Int(IniRead($CONFIG_FILE, "Settings", "AutoPanPeriod", "8"))
If $g_iAutoPanPeriod < 1 Or $g_iAutoPanPeriod > 60 Then $g_iAutoPanPeriod = 8

; ---- Version 3.3: voice enhancement, chapters, podcasts, extra search sources ----
Global $g_iVoiceMode = Int(IniRead($CONFIG_FILE, "Settings", "VoiceEnhance", "0")) ; Settings > Player: 0 = Off, 1 = Light, 2 = Strong (Ctrl+Shift+V in the player)
If $g_iVoiceMode < 0 Or $g_iVoiceMode > 2 Then $g_iVoiceMode = 0
Global $g_bAnnounceChapters = IniRead($CONFIG_FILE, "Settings", "AnnounceChapters", "true") == "true" ; Settings > Player
Global $g_sSearchSource = IniRead($CONFIG_FILE, "Settings", "SearchSource", "YouTube") ; Search window > Source
If $g_sSearchSource <> "YouTube" And $g_sSearchSource <> "SoundCloud" Then $g_sSearchSource = "YouTube"
Global $g_aChapT[1] = [0], $g_aChapN[1] = [""], $g_iChapCount = 0, $g_iChapCur = -1
Global $g_iChapPid = 0, $g_iChapMode = 0, $g_sChapOut = "", $g_hChapTimer = 0
Global $menu_item_chapters = -1, $menu_item_voice = -1
Global $hDummyChapNext = 0, $hDummyChapPrev = 0, $hDummyChapList = 0, $hDummyVoice = 0
Global $PODCASTS_FILE = $SETTINGS_DIR & "\podcasts.dat"
Global $PODCAST_PLAYED_FILE = $SETTINGS_DIR & "\podcast_played.dat"

; ---- Subscriptions: YouTube channels + podcasts, check for new content (Settings > General) ----
Global $YT_SUBS_FILE = $SETTINGS_DIR & "\youtube_subs.dat"        ; one line per channel: channel id|name|id of the newest video already seen
Global $SUB_NOTIFIED_FILE = $SETTINGS_DIR & "\subs_notified.dat"  ; one line per subscription: key|newest item already announced
Global $g_bCheckSubsOnStart = IniRead($CONFIG_FILE, "Settings", "CheckSubsOnStart", "true") == "true" ; check the subscriptions when the application starts
Global $g_oSubNew = 0 ; Scripting.Dictionary: "pod:feed" / "yt:channel" -> number of new items found by the last check
Global $g_aSubJobs[1][4], $g_iSubJobN = 0, $g_iSubJobI = 0, $g_iSubPid = 0, $g_bSubData = Binary(""), $g_hSubTimer = 0 ; startup check (see _Sub_StartupCheck)
Global $g_iSubNewPod = 0, $g_iSubNewYT = 0
Global $g_hTypeCb = 0, $g_pTypeOld = 0, $g_hTypeEdit = 0 ; typing sounds in other input boxes (see _TypeSnd_Attach)
Global $menu_item_yt_sub = -1 ; player Options > Subscribe to channel

; ---- Resume theo tung file nghe, Recent files/folders, Radio, Equalizer tuy chinh, Phim tat tuy chinh ----
Global $g_bResumeLocal = IniRead($CONFIG_FILE, "Settings", "ResumeLocal", "true") == "true"
Global $LOCAL_POSITIONS_FILE = $SETTINGS_DIR & "\local_positions.dat"
Global $RECENT_FILES_FILE = $SETTINGS_DIR & "\recent_files.dat"
Global $RECENT_FOLDERS_FILE = $SETTINGS_DIR & "\recent_folders.dat"
Global $RECENT_MAX = 50
Global $g_sLocalPlaylistFolder = ""
Global $g_aEqBands[10] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
Global $g_fEqPreamp = 0
_EQ_LoadCustom()
Global $g_aRadioCountries = 0, $g_aRadioLanguages = 0, $g_sRadioServer = ""

; Radio: favorite stations file and recording settings (formats = the audio formats of the Download feature)
Global $RADIO_FAV_FILE = $SETTINGS_DIR & "\radio_favorites.dat"
Global $g_aRadioRecFormats[4] = ["M4A", "MP3", "OGG", "WAV"]
Global $g_aRadioRecBitrates[4] = [128, 192, 256, 320]
Global $g_aRadioRecRates[4] = [0, 22050, 44100, 48000] ; 0 = same as the station
Global $g_sRadioRecPath = IniRead($CONFIG_FILE, "Settings", "RadioRecPath", @ScriptDir & "\radio_recording")
If StringStripWS($g_sRadioRecPath, 3) = "" Then $g_sRadioRecPath = @ScriptDir & "\radio_recording"
Global $g_sRadioRecFormat = StringUpper(IniRead($CONFIG_FILE, "Settings", "RadioRecFormat", "MP3"))
If Not StringRegExp($g_sRadioRecFormat, "^(M4A|MP3|OGG|WAV)$") Then $g_sRadioRecFormat = "MP3"
Global $g_iRadioRecBitrate = Int(IniRead($CONFIG_FILE, "Settings", "RadioRecBitrate", "192"))
If $g_iRadioRecBitrate <> 128 And $g_iRadioRecBitrate <> 192 And $g_iRadioRecBitrate <> 256 And $g_iRadioRecBitrate <> 320 Then $g_iRadioRecBitrate = 192
Global $g_iRadioRecChannels = Int(IniRead($CONFIG_FILE, "Settings", "RadioRecChannels", "2"))
If $g_iRadioRecChannels <> 1 Then $g_iRadioRecChannels = 2
Global $g_iRadioRecRate = Int(IniRead($CONFIG_FILE, "Settings", "RadioRecSampleRate", "0"))
If $g_iRadioRecRate <> 22050 And $g_iRadioRecRate <> 44100 And $g_iRadioRecRate <> 48000 Then $g_iRadioRecRate = 0
Global $g_iRadioRecAutoStop = Int(IniRead($CONFIG_FILE, "Settings", "RadioRecAutoStop", "0")) ; minutes, 0 = never
If $g_iRadioRecAutoStop < 0 Then $g_iRadioRecAutoStop = 0
If $g_iRadioRecAutoStop > 1440 Then $g_iRadioRecAutoStop = 1440
Global $g_iRadioRecVolume = Int(IniRead($CONFIG_FILE, "Settings", "RadioRecVolume", "100")) ; 0-100, same scale as the radio volume
If $g_iRadioRecVolume < 0 Then $g_iRadioRecVolume = 0
If $g_iRadioRecVolume > 100 Then $g_iRadioRecVolume = 100
Global $g_iRadioRecPid = 0, $g_sRadioRecFile = "", $g_sRadioRecStation = "", $g_hRadioRecStart = 0
Global $g_pRecPlayer = 0 ; second libvlc media player that records the station in the background (see _RadioRec_Start)
; MP3: VLC saves the stream untouched (TS, no real-time encoding = no stutter), ffmpeg converts it to MP3 afterwards
Global $g_bRecPassthrough = False, $g_sRecTsFile = ""
Global $g_aRecConv[1][4], $g_iRecConvN = 0 ; running conversions: pid, ts file, mp3 file, ffmpeg messages

; Sleep timer fade-out (shared by the Player and the Radio)
Global $g_bSleepFade = (IniRead($CONFIG_FILE, "Settings", "SleepFade", "true") = "true")
Global $g_iSleepFadeSecs = Int(IniRead($CONFIG_FILE, "Settings", "SleepFadeSecs", "20"))
If $g_iSleepFadeSecs < 1 Then $g_iSleepFadeSecs = 1
If $g_iSleepFadeSecs > 600 Then $g_iSleepFadeSecs = 600
Global $g_bSleepFading = False, $g_hSleepFadeTimer = 0

; sounds\downloading.wav loops while a download is running (see _DLSound_Start / _DLSound_Stop)
Global $g_bDLSoundWanted = False, $g_bDLSoundOn = False, $g_bDLSoundReal = False, $g_hDLSoundAt = 0, $g_iDLSoundDelay = 0
Global $g_iHKCount = 0
Global $g_aHK[80][8], $g_aHKWork[80], $g_aHKListIdx[1]
Global $g_aHKFixedMain[2][2]
_HK_Init()

; ============================================================================
; Localization: language files live in <app folder>\lang\*.lng (UTF-8).
; Each line:  "original English text" = "translated text"   (use \n for a new line)
; The English text is the key, so a missing translation simply falls back to English.
; ============================================================================
Global $g_oLang = 0        ; Scripting.Dictionary: English key -> translation
Global $g_oLangRev = 0     ; Scripting.Dictionary: translation -> English key
Global $g_sLanguage = IniRead($CONFIG_FILE, "Settings", "Language", "english")   ; saved choice
Global $g_sLangLoaded = ""                                                        ; language in memory
Global $g_aLangCodes[1] = ["english"]
Global $g_aLangNames[1] = ["English"]
Global $g_aLangKeys[1] = ["English"]    ; English name of each language = translation key for its display name
_Lang_Load($g_sLanguage)

Func _Lang_Decode($s)
    If StringInStr($s, "\") = 0 Then Return $s
    Local $sOut = "", $n = StringLen($s), $i = 1, $c, $d
    While $i <= $n
        $c = StringMid($s, $i, 1)
        If $c = "\" And $i < $n Then
            $d = StringMid($s, $i + 1, 1)
            If $d = "n" Then
                $sOut &= @CRLF
                $i += 2
                ContinueLoop
            ElseIf $d = "\" Then
                $sOut &= "\"
                $i += 2
                ContinueLoop
            EndIf
        EndIf
        $sOut &= $c
        $i += 1
    WEnd
    Return $sOut
EndFunc

Func _Lang_Load($sCode)
    If Not StringRegExp($sCode, "^[A-Za-z0-9_\-]+$") Then $sCode = "english"
    If $sCode = "english" Then
        ; English is built into the program: no language file is needed
        $g_oLang = 0
        $g_oLangRev = 0
        $g_sLangLoaded = "english"
        Return True
    EndIf
    Local $sFile = @ScriptDir & "\lang\" & $sCode & ".lng"
    If Not FileExists($sFile) Then Return _Lang_Load("english")   ; file missing: fall back to built-in English
    Local $oFwd = ObjCreate("Scripting.Dictionary")
    Local $oRev = ObjCreate("Scripting.Dictionary")
    If Not IsObj($oFwd) Or Not IsObj($oRev) Then Return False
    Local $hFile = FileOpen($sFile, 256) ; UTF-8, no BOM
    If $hFile = -1 Then Return False
    Local $sData = FileRead($hFile)
    FileClose($hFile)
    Local $aLines = StringSplit(StringStripCR($sData), @LF, 2)
    For $i = 0 To UBound($aLines) - 1
        Local $sLine = StringStripWS($aLines[$i], 3)
        If StringLeft($sLine, 1) <> '"' Or StringRight($sLine, 1) <> '"' Then ContinueLoop
        Local $iSep = StringInStr($sLine, '" = "', 1)
        If $iSep < 2 Then ContinueLoop
        Local $sKey = StringMid($sLine, 2, $iSep - 2)
        Local $sVal = _Lang_Decode(StringMid($sLine, $iSep + 5, StringLen($sLine) - $iSep - 5))
        If $sVal = "" Then ContinueLoop
        $oFwd.Item($sKey) = $sVal
        If Not $oRev.Exists($sVal) Then $oRev.Item($sVal) = $sKey
    Next
    $g_oLang = $oFwd
    $g_oLangRev = $oRev
    $g_sLangLoaded = $sCode
    Return True
EndFunc

; Translate a plain text
Func _T($sText)
    $sText = String($sText)
    If IsObj($g_oLang) Then
        If $g_oLang.Exists($sText) Then Return $g_oLang.Item($sText)
    EndIf
    Return $sText
EndFunc

; Translate a template containing {1}..{5} placeholders and fill them in
Func _TF($sTemplate, $v1 = "", $v2 = "", $v3 = "", $v4 = "", $v5 = "")
    Local $s = String($sTemplate)
    If IsObj($g_oLang) And $g_oLang.Exists($s) Then
        $s = $g_oLang.Item($s)
    Else
        $s = _Lang_Decode($s)
    EndIf
    ; two passes so a value that itself contains "{2}" is never substituted again
    For $i = 1 To 5
        $s = StringReplace($s, "{" & $i & "}", Chr(1) & $i & Chr(2))
    Next
    Local $aVals[6] = ["", $v1, $v2, $v3, $v4, $v5]
    For $i = 1 To 5
        $s = StringReplace($s, Chr(1) & $i & Chr(2), String($aVals[$i]))
    Next
    Return $s
EndFunc

; Translate every item of a "a|b|c" list (used for combo boxes)
Func _TL($sList)
    Local $a = StringSplit($sList, "|", 2)
    Local $sOut = ""
    For $i = 0 To UBound($a) - 1
        $sOut &= _T($a[$i]) & "|"
    Next
    Return StringTrimRight($sOut, 1)
EndFunc

; Reverse lookup: translated text -> original English text (for logic that compares text)
Func _TR($sText)
    If IsObj($g_oLangRev) Then
        If $g_oLangRev.Exists($sText) Then Return $g_oLangRev.Item($sText)
    EndIf
    Return $sText
EndFunc

; Read one header line (e.g. "@Name = ...") of a language file. Tolerates BOM, CRLF and quotes.
Func _Lang_ReadHeader($sFile, $sField)
    Local $h = FileOpen($sFile, 256) ; UTF-8, no BOM
    If $h = -1 Then Return ""
    Local $sData = FileRead($h)
    FileClose($h)
    $sData = StringReplace($sData, ChrW(0xFEFF), "")   ; stray BOM would hide the first line
    Local $a = StringRegExp($sData, "(?m)^[ \t]*@" & $sField & "[ \t]*=[ \t]*(.*?)[ \t\r]*$", 1)
    If @error Then Return ""
    Local $sVal = $a[0]
    If StringLen($sVal) >= 2 And StringLeft($sVal, 1) = '"' And StringRight($sVal, 1) = '"' Then $sVal = StringMid($sVal, 2, StringLen($sVal) - 2)
    Return StringStripWS($sVal, 3)
EndFunc

; Display name of a language file (line "@Name = ...", written in that language itself)
Func _Lang_ReadName($sFile)
    Return _Lang_ReadHeader($sFile, "Name")
EndFunc

; Fill $g_aLangCodes / $g_aLangNames / $g_aLangKeys from the lang folder
;   $g_aLangNames = native name from "@Name"    (e.g. "Tieng Viet")
;   $g_aLangKeys  = English name from "@English" (e.g. "Vietnamese"), used as the translation key
Func _Lang_Scan()
    Local $sCodes = "english|", $sNames = "English|", $sKeys = "English|"    ; built-in English is always available
    Local $hSearch = FileFindFirstFile(@ScriptDir & "\lang\*.lng")
    If $hSearch <> -1 Then
        While 1
            Local $sName = FileFindNextFile($hSearch)
            If @error Then ExitLoop
            If @extended Then ContinueLoop                      ; skip folders
            Local $sCode = StringTrimRight($sName, 4)
            If Not StringRegExp($sCode, "^[A-Za-z0-9_\-]+$") Or $sCode = "english" Then ContinueLoop
            Local $sFile = @ScriptDir & "\lang\" & $sName
            Local $sDisp = StringReplace(_Lang_ReadHeader($sFile, "Name"), "|", "/")
            If $sDisp = "" Then $sDisp = $sCode
            Local $sKey = StringReplace(_Lang_ReadHeader($sFile, "English"), "|", "/")
            If $sKey = "" Then $sKey = $sDisp
            $sCodes &= $sCode & "|"
            $sNames &= $sDisp & "|"
            $sKeys &= $sKey & "|"
        WEnd
        FileClose($hSearch)
    EndIf
    $g_aLangCodes = StringSplit(StringTrimRight($sCodes, 1), "|", 2)
    $g_aLangNames = StringSplit(StringTrimRight($sNames, 1), "|", 2)
    $g_aLangKeys = StringSplit(StringTrimRight($sKeys, 1), "|", 2)
EndFunc

; Text shown in the language combo box for language number $i.
; Shown as ONE name only, in the current UI language: the key is the English name of the language
; ("@English" header of its .lng, e.g. "Vietnamese"). With the English UI it is shown as is
; (English / Vietnamese); with another UI the translation in that .lng is used
; (e.g. "Vietnamese" = "Tieng Viet", "English" = "Tieng Anh").
Func _Lang_DisplayName($i)
    Local $sShown = _T($g_aLangKeys[$i])
    If $sShown = "" Then $sShown = $g_aLangNames[$i]
    If $sShown = "" Then $sShown = $g_aLangCodes[$i]
    Return StringReplace($sShown, "|", "/")
EndFunc

If Not FileExists($g_sDownloadPath) Then DirCreate($g_sDownloadPath)
If Not FileExists($g_sRadioRecPath) Then DirCreate($g_sRadioRecPath)
_RadioRec_CleanupTemp()

If Not FileExists($YT_DLP_PATH) Then
    MsgBox(16, _T("Error"), _T("The file lib\yt-dlp.exe does not exist!") & @CRLF & _T("Please double-check the lib folder."))
EndIf

; --- Kiem tra giay phep moi lan chay, phat am thanh cua tuong ung truoc khi phat logo ---
; Da chap nhan  : phat dooropen.wav roi moi toi logo.
; Chua chap nhan: hien hop thoai License Agreement (license_agreement.wav);
;                 Accept -> dooropen.wav roi toi logo; Decline -> doorclose.wav roi thoat phan mem.
; Tuy chon Settings > General "Show license confirmation when the application starts":
;   Tat: bo qua hoan toan buoc license, KHONG phat dooropen.wav, vao phan mem luon.
;   Bat: giu nguyen hanh vi o tren, them thong bao bang van ban:
;        - Da chap nhan truoc do: doc "License accepted" cung luc voi dooropen.wav.
;        - Bam Accept : phat accept.wav va doc van ban da chap nhan license (khong dung hop thoai).
;        - Bam Decline: phat decline.wav va doc van ban neu khong chap nhan thi vui long khong su dung phan mem.
If $g_bShowLicenseConfirm Then
    If IniRead($CONFIG_FILE, "License", "Accepted", "false") = "true" Then
        _NVDA_Speak(_T("License accepted. You have already accepted the license."))
        _Play_DoorOpen_Welcome()
    Else
        If Not _Show_License_Window() Then
            _NVDA_Speak(_T("If you do not accept the license, please do not use this software."))
            _AppSoundPlaySync(@ScriptDir & "\sounds\decline.wav")
            _AppSoundPlaySync(@ScriptDir & "\sounds\doorclose.wav")
            Exit
        EndIf
        IniWrite($CONFIG_FILE, "License", "Accepted", "true")
        _NVDA_Speak(_T("You have accepted the license."))
        _AppSoundPlaySync(@ScriptDir & "\sounds\accept.wav")
        _Play_DoorOpen_Welcome()
    EndIf
EndIf

; Logo khoi dong (co the tat trong Settings > General). Khi tat: chi phat am thanh cua o tren roi vao phan mem.
If $g_bShowLogo Then
    $lding=GUICreate(_T("loading"),300,300)
    GUISetBkColor($COLOR_BLUE)
    GuiCtrlCreateLabel(_T("Welcome to VDH Productions"), 10, 25)
    GUICtrlSetColor(-1, 0xFFFFFF)
    GUISetState()
EndIf

Global $sVLC_Path = @ScriptDir & "\lib\VLC"
If @AutoItX64 Then $sVLC_Path = @ScriptDir & "\lib\VLC64"
_VLC_Direct_Init()

If $g_bShowLogo Then
    _AppSoundPlay(@ScriptDir & "\sounds\start.wav")
    Local $hStartTimer = TimerInit()
    While TimerDiff($hStartTimer) < 500
        GUIGetMsg()
        Sleep(6000)
    WEnd
    GUIDelete($lding)
EndIf

; Khong co $WS_SYSMENU => an nut Close (X), Minimize va menu he thong tren thanh tieu de.
; Thoat ung dung bang Preferences > Exit hoac Ctrl+W.
; Giu $WS_SYSMENU de thanh menu (Preferences/Help) dieu huong Trai/Phai binh thuong;
; nut Close (X) bi vo hieu hoa ngay duoi day thay vi bo han style.
$mainform = GUICreate(_TF("VDHMediaCenter version{1}", $version), 300, 630, -1, -1, BitOR($WS_CAPTION, $WS_POPUP, $WS_SYSMENU))
Local $hSysMenuMain = DllCall("user32.dll", "handle", "GetSystemMenu", "hwnd", $mainform, "bool", 0)
If Not @error And IsArray($hSysMenuMain) Then DllCall("user32.dll", "bool", "EnableMenuItem", "handle", $hSysMenuMain[0], "uint", 0xF060, "uint", 0x0001) ; SC_CLOSE, MF_BYCOMMAND|MF_GRAYED
GUISetBkColor($COLOR_BLUE)
GUISetFont(9, 400, 0, "Segoe UI")

Local $sGreeting = _GetGreeting()
$label = GUICtrlCreateLabel(_TF("{1} and warm welcome to VDHMediaCenter application.", $sGreeting), 10, 10, 280, 50, BitOR($SS_LEFT, $WS_TABSTOP))
GUICtrlSetFont(-1, 14, 800)
GUICtrlSetColor(-1, 0xFFFFFF)

Global $btn_Menu_DL = GUICtrlCreateButton(_T("Download from link (Alt+D)"), 50, 60, 200, 34)
Global $btn_Menu_PL = GUICtrlCreateButton(_T("Play Video or Music Link (Alt+P)"), 50, 97, 200, 34)
Global $btn_Menu_Direct = GUICtrlCreateButton(_T("Play direct link (Alt+L)"), 50, 134, 200, 34)
Global $btn_Menu_SC = GUICtrlCreateButton(_T("Search Videos and Music (Alt+S)"), 50, 171, 200, 34)
Global $btn_Menu_CL = GUICtrlCreateButton(_T("Your Collections (Alt+C)"), 50, 208, 200, 34)
Global $btn_Menu_Audio = GUICtrlCreateButton(_T("Listen to Audio File (Alt+U)"), 50, 245, 200, 34)
Global $btn_Menu_RF = GUICtrlCreateButton(_T("Recent Files (Alt+E)"), 50, 282, 200, 34)
Global $btn_Menu_RD = GUICtrlCreateButton(_T("Recent Folders (Alt+O)"), 50, 319, 200, 34)
Global $btn_Menu_Radio = GUICtrlCreateButton(_T("Radio Player (Alt+R)"), 50, 356, 200, 34)
Global $btn_Menu_RadioFav = GUICtrlCreateButton(_T("Favorite Stations (Alt+V)"), 50, 393, 200, 34)
Global $btn_Menu_Podcasts = GUICtrlCreateButton(_T("Podcasts (Alt+K)"), 50, 430, 200, 34)
Global $btn_Menu_YTS = GUICtrlCreateButton(_T("YouTube Subscriptions (Alt+Y)"), 50, 467, 200, 34)
Global $btn_Menu_Queue = GUICtrlCreateButton(_T("Play Queue (Alt+Q)"), 50, 504, 200, 34)
Global $btn_Menu_DQ = GUICtrlCreateButton(_T("Download Queue (Alt+Z)"), 50, 541, 200, 34)
Global $btn_Menu_FV = GUICtrlCreateButton(_T("Favorites (Alt+F)"), 10, 585, 100, 30)
Global $btn_Menu_WS = GUICtrlCreateButton(_T("Watch History (Alt+W)"), 120, 585, 150, 30)

Global $menu_main = GUICtrlCreateMenu(_T("Preferences"))
Global $menu_settings = GUICtrlCreateMenuItem(_T("Settings... (Ctrl+Shift+S)"), $menu_main)
Global $menu_exit = GUICtrlCreateMenuItem(_T("Exit..."), $menu_main)

Global $menu_help = GUICtrlCreateMenu(_T("Help"))
Global $menu_about = GUICtrlCreateMenuItem(_T("About..."), $menu_help)
Global $menu_website = GUICtrlCreateMenuItem(_T("Visit &Website..."), $menu_help)
Global $menu_readme = GUICtrlCreateMenuItem(_T("Readme... (F1)"), $menu_help)
Global $menu_contact = GUICtrlCreateMenuItem(_T("Contact..."), $menu_help)
Global $menu_update_ytdlp = GUICtrlCreateMenuItem(_T("Checked for updates &yt_dlp..."), $menu_help)
Global $menu_Update_app = GUICtrlCreateMenuItem(_T("Checked for &Updates..."), $menu_help)
Global $menuChangelog = GuiCtrlCreateMenuItem(_T("view changelog..."), $menu_help)
Global $menuContribute = GuiCtrlCreateMenuItem(_T("con&tribute..."), $menu_help)
Global $menuSendFeedback = GuiCtrlCreateMenuItem(_T("Send &feedback..."), $menu_help)

GUISetState(@SW_SHOW, $mainform)
ControlFocus($mainform, "", $label)


; ==========================================================================
;  FIX: chi cho phep MOT giao dien hoat dong tai mot thoi diem
;  - _RunSubWindow(): an giao dien chinh truoc khi mo cua so con,
;    hien lai sau khi cua so con dong.
;  - _GuiMsg(): chi lay thong diep cua dung cua so dang xu ly,
;    bo qua thong diep den tu cua so khac (tranh 2 giao dien cung hoat dong).
; ==========================================================================
Global $g_bSubWindowOpen = False

Func _RunSubWindow($sFunc)
    If $g_bSubWindowOpen Then Return ; da co mot cua so con dang mo
    $g_bSubWindowOpen = True

    ; KHONG an/vo hieu hoa giao dien chinh ngay luc nay. Neu an truoc khi cua so con
    ; kip tao, Windows se chuyen focus sang ung dung khac, khien nguoi dung phai cho
    ; (man hinh trong, NVDA doc cua so khac) roi cua so con moi hien len.
    ; Thay vao do, cua so con duoc tao va hien ra truoc; giao dien chinh se duoc an
    ; ngay sau do bang _HideMainDeferred() (chay ngam luc vong lap cua so con hoat dong).
    AdlibRegister("_HideMainDeferred", 100)

    Call($sFunc)

    AdlibUnRegister("_HideMainDeferred")

    ; Tra lai giao dien chinh
    If IsHWnd($mainform) Then
        GUISetState(@SW_ENABLE, $mainform)
        GUISetState(@SW_SHOW, $mainform)
        WinActivate($mainform)
        ControlFocus($mainform, "", $label)
    EndIf

    $g_bSubWindowOpen = False
EndFunc

; Chay ngam sau khi cua so con da hien: luc nay moi vo hieu hoa + an giao dien chinh.
Func _HideMainDeferred()
    AdlibUnRegister("_HideMainDeferred")
    If Not $g_bSubWindowOpen Then Return
    If IsHWnd($mainform) Then
        ; Luu cua so GUI hien hanh de tranh cac control dang tao do bi gan nham vao giao dien chinh
        Local $hPrevGui = GUISwitch($mainform)
        GUISetState(@SW_DISABLE, $mainform)
        GUISetState(@SW_HIDE, $mainform)
        If IsHWnd($hPrevGui) And $hPrevGui <> $mainform Then GUISwitch($hPrevGui)
    EndIf
EndFunc

; Thay cho GUIGetMsg() trong vong lap cua cua so con.
; Tra ve 0 neu thong diep khong thuoc ve $hGui.
Func _GuiMsg($hGui)
    Local $aMsg = GUIGetMsg(1)
    If Not IsArray($aMsg) Then Return 0
    If $aMsg[0] = 0 Then Return 0
    If IsHWnd($hGui) And $aMsg[1] <> $hGui Then Return 0
    Return $aMsg[0]
EndFunc

; Enter bi chan boi phim tat {ENTER} (dummy) nen nut dang focus khong tu kich hoat.
; Ham nay tra ve ID cua nut (trong mang $aIds) dang co focus trong cua so $hGui, hoac 0 neu
; focus khong nam tren nut nao. Dung de doi Enter thanh nhan nut do.
Func _EnterFocusedButton($hGui, $aIds)
    Local $hFocus = ControlGetHandle($hGui, "", ControlGetFocus($hGui))
    If Not IsHWnd($hFocus) Then Return 0
    For $i = 0 To UBound($aIds) - 1
        If GUICtrlGetHandle($aIds[$i]) = $hFocus Then Return $aIds[$i]
    Next
    Return 0
EndFunc

; Phim tat {ENTER} (dummy) chan Enter cua cac nut bam. Ham nay chi bat phim tat Enter khi
; danh sach $hList dang co focus; khi focus o nut bam thi tat no de Enter nhan nut nhu mac dinh cua Windows.
; Goi o dau moi vong lap. $aFull = bang phim tat day du cua cua so, $bOn = trang thai hien tai.
Func _SyncEnterAccel($hGui, ByRef $aFull, $idList, ByRef $bOn)
    Local $bWant = (ControlGetHandle($hGui, "", ControlGetFocus($hGui)) = GUICtrlGetHandle($idList))
    If $bWant = $bOn Then Return
    $bOn = $bWant
    If $bOn Then
        GUISetAccelerators($aFull, $hGui)
    Else
        Local $aOff = $aFull
        For $k = 0 To UBound($aOff) - 1
            If $aOff[$k][0] = "{ENTER}" Then $aOff[$k][0] = "^+!{F12}"
        Next
        GUISetAccelerators($aOff, $hGui)
    EndIf
EndFunc


Func _ShowDirectLinkPlayer()
    Local $hDirectGui = GUICreate(_T("Direct Link Player"), 400, 150, -1, -1, BitOR($WS_CAPTION, $WS_POPUPWINDOW, $WS_VISIBLE))
    GUISetBkColor($COLOR_BLUE, $hDirectGui)

    GUICtrlCreateLabel(_T("Enter Direct URL:"), 10, 20, 380, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $inpUrl = GUICtrlCreateInput("", 10, 45, 380, 20)

    Local $btnOk = GUICtrlCreateButton(_T("OK"), 80, 80, 100, 30, $GUI_DEFBUTTON)
    Local $btnCancel = GUICtrlCreateButton(_T("Cancel"), 200, 80, 100, 30)

    _AllowUIPI($hDirectGui)
    GUISetState(@SW_SHOW, $hDirectGui)
    WinActivate($hDirectGui)
    ControlFocus($hDirectGui, "", $inpUrl)

    While 1
        Local $msg = _GuiMsg($hDirectGui)
        Switch $msg
            Case $GUI_EVENT_CLOSE, $btnCancel
                _VLC_Direct_Stop()
                GUIDelete($hDirectGui)
                GUISetState(@SW_SHOW, $mainform)
                Return
            Case $btnOk
                Local $sUrl = GUICtrlRead($inpUrl)
                If $sUrl = "" Then
                    MsgBox(16, _T("Error"), _T("Please enter the Direct URL!"))
                Else
                    GUIDelete($hDirectGui)

                    ; Create loading dialog
                    Local $hLoading = GUICreate(_T("Loading"), 250, 80, -1, -1, BitOR($WS_POPUP, $WS_BORDER), BitOR($WS_EX_TOPMOST, $WS_EX_TOOLWINDOW))
                    GUICtrlCreateLabel(_T("Loading stream, please wait..."), 10, 25, 230, 30, $SS_CENTER)
                    GUISetBkColor(0xFFFFFF, $hLoading)
                    GUISetState(@SW_SHOW, $hLoading)
                    ; Thông báo cho NVDA
                    _NVDA_Speak(_T("Loading stream, please wait."))

                    ; Phát loading.wav (không chặn) và ok.wav
                    _AppSoundPlay(@ScriptDir & "\sounds\loading.wav")
                    _AppSoundPlay(@ScriptDir & "\sounds\ok.wav")

                    ; Giảm trì hoãn để phản hồi nhanh hơn
                    Sleep(30)

                    _PlayInternal($sUrl, _T("Direct Link Player"), False, $hLoading, False, "")
                    GUISetState(@SW_SHOW, $mainform)
                    Return
                EndIf
        EndSwitch
    WEnd
EndFunc
Local $hDummyUpdateApp = GUICtrlCreateDummy()
Local $hDummyUpdateYTDLP = GUICtrlCreateDummy()
Local $hDummyReadme = GUICtrlCreateDummy()
Local $hDummyChangelog = GUICtrlCreateDummy()
Local $hDummyEscMain = GUICtrlCreateDummy()
Local $hDummySettings = GUICtrlCreateDummy()
Local $hDummyEnterMain = GUICtrlCreateDummy()

; Phim tat cua cua so chinh: ghep tu bang phim tat tuy chinh (Settings > Shortcuts)
$g_aHKFixedMain[0][0] = "{ESC}"
$g_aHKFixedMain[0][1] = $hDummyEscMain
$g_aHKFixedMain[1][0] = "{ENTER}"
$g_aHKFixedMain[1][1] = $hDummyEnterMain
_HK_SetHandle("main_download", $btn_Menu_DL, $btn_Menu_DL)
_HK_SetHandle("main_play", $btn_Menu_PL, $btn_Menu_PL)
_HK_SetHandle("main_direct", $btn_Menu_Direct, $btn_Menu_Direct)
_HK_SetHandle("main_search", $btn_Menu_SC, $btn_Menu_SC)
_HK_SetHandle("main_collections", $btn_Menu_CL, $btn_Menu_CL)
_HK_SetHandle("main_audio", $btn_Menu_Audio, $btn_Menu_Audio)
_HK_SetHandle("main_recent_files", $btn_Menu_RF, $btn_Menu_RF)
_HK_SetHandle("main_recent_folders", $btn_Menu_RD, $btn_Menu_RD)
_HK_SetHandle("main_radio", $btn_Menu_Radio, $btn_Menu_Radio)
_HK_SetHandle("main_radio_fav", $btn_Menu_RadioFav, $btn_Menu_RadioFav)
_HK_SetHandle("main_podcasts", $btn_Menu_Podcasts, $btn_Menu_Podcasts)
_HK_SetHandle("main_yt_subs", $btn_Menu_YTS, $btn_Menu_YTS)
_HK_SetHandle("main_queue", $btn_Menu_Queue, $btn_Menu_Queue)
_HK_SetHandle("main_dq", $btn_Menu_DQ, $btn_Menu_DQ)
_HK_SetHandle("main_fav", $btn_Menu_FV, $btn_Menu_FV)
_HK_SetHandle("main_history", $btn_Menu_WS, $btn_Menu_WS)
_HK_SetHandle("main_settings", $hDummySettings, $menu_settings)
_HK_SetHandle("main_readme", $hDummyReadme, $menu_readme)
_HK_SetHandle("main_changelog", $hDummyChangelog, 0)
_HK_SetHandle("main_update_app", $hDummyUpdateApp, 0)
_HK_SetHandle("main_update_ytdlp", $hDummyUpdateYTDLP, 0)
_HK_SetHandle("main_exit", $menu_exit, 0)
_HK_ApplyMain()

If $g_bAutoDetectLink Then _AutoDetectClipboardLink()
_AddDefenderExclusion()
_Recent_MigrateHistory() ; mot lan: chuyen cac bai nghe cuc bo cu tu Watch History sang Recent Files

; Auto update check if enabled (app update and/or yt-dlp update)
If $g_bAutoUpdate Or $g_bAutoUpdateYTDLP Then
    AdlibRegister("_CheckUpdatesSilently", 5000) ; Wait 5s after start to not bother user immediately
EndIf

; Subscriptions: look for new podcast episodes and new YouTube videos in the background (Settings > General).
; Something new = new_content.wav + a short announcement; nothing new = silence. When the option is off, nothing is checked here.
If $g_bCheckSubsOnStart Then AdlibRegister("_Sub_StartupCheck", 8000)

While 1
    Local $msg = GUIGetMsg()

    ; Handle Enter key for buttons on Main GUI
    If $msg = $hDummyEnterMain Then
        Local $hFocus = ControlGetHandle($mainform, "", ControlGetFocus($mainform))
        Switch $hFocus
            Case GUICtrlGetHandle($btn_Menu_DL)
                $msg = $btn_Menu_DL
            Case GUICtrlGetHandle($btn_Menu_PL)
                $msg = $btn_Menu_PL
            Case GUICtrlGetHandle($btn_Menu_SC)
                $msg = $btn_Menu_SC
            Case GUICtrlGetHandle($btn_Menu_CL)
                $msg = $btn_Menu_CL
            Case GUICtrlGetHandle($btn_Menu_FV)
                $msg = $btn_Menu_FV
            Case GUICtrlGetHandle($btn_Menu_WS)
                $msg = $btn_Menu_WS
            Case GUICtrlGetHandle($btn_Menu_Direct)
                $msg = $btn_Menu_Direct
            Case GUICtrlGetHandle($btn_Menu_Audio)
                $msg = $btn_Menu_Audio
            Case GUICtrlGetHandle($btn_Menu_Queue)
                $msg = $btn_Menu_Queue
            Case GUICtrlGetHandle($btn_Menu_DQ)
                $msg = $btn_Menu_DQ
            Case GUICtrlGetHandle($btn_Menu_RF)
                $msg = $btn_Menu_RF
            Case GUICtrlGetHandle($btn_Menu_RD)
                $msg = $btn_Menu_RD
            Case GUICtrlGetHandle($btn_Menu_Radio)
                $msg = $btn_Menu_Radio
            Case GUICtrlGetHandle($btn_Menu_RadioFav)
                $msg = $btn_Menu_RadioFav
            Case GUICtrlGetHandle($btn_Menu_Podcasts)
                $msg = $btn_Menu_Podcasts
            Case GUICtrlGetHandle($btn_Menu_YTS)
                $msg = $btn_Menu_YTS
        EndSwitch
    EndIf

    Switch $msg
        Case $GUI_EVENT_CLOSE, $menu_exit
            _Quit_App() ; phat doorclose.wav, an ngay moi cua so roi ket thuc tien trinh dut khoat
            ; KHÔNG gọi _VLC_Cleanup() ở đây nữa: hàm đó gọi libvlc_media_player_stop
            ; rồi libvlc_release rồi DllClose(libvlc.dll) - yêu cầu VLC "dọn dẹp đúng
            ; chuẩn", tức phải join hết các luồng nội bộ (mạng, giải mã, âm thanh) trước
            ; khi được unload. Nếu đang phát một luồng mạng (YouTube...), bước dừng này
            ; có thể bị treo vài giây (lỗi khá phổ biến của libvlc_media_player_stop với
            ; network stream) - đây chính là lý do Alt+F4 gần đây bị chậm/đứng hình một
            ; lúc mới đóng hẳn. Vì app sắp Exit() hoàn toàn ngay sau đó, việc "dọn sạch"
            ; này không cần thiết - Windows sẽ tự thu hồi toàn bộ handle/DLL/luồng ngay
            ; khi tiến trình kết thúc, nên bỏ qua bước này giúp đóng app nhanh và ổn định
            ; như trước, bất kể đang phát gì.
            Exit

        Case $btn_Menu_DL
            _GlobalSoundPlay("sounds/enter.wav", "system")
            _RunSubWindow("_ShowDownloader")

        Case $btn_Menu_PL
            _GlobalSoundPlay("sounds/enter.wav", "system")
            _RunSubWindow("_ShowPlayer")

        Case $btn_Menu_Direct
            _GlobalSoundPlay("sounds/enter.wav", "system")
            _RunSubWindow("_ShowDirectLinkPlayer")

        Case $btn_Menu_SC
            _GlobalSoundPlay("sounds/enter.wav", "system")
            _RunSubWindow("_ShowSearch")

        Case $btn_Menu_CL
            _GlobalSoundPlay("sounds/enter.wav", "system")
            _RunSubWindow("_ShowCollections")

        Case $btn_Menu_Audio
            _GlobalSoundPlay("sounds/enter.wav", "system")
            _RunSubWindow("_ListenToAudioFile")

        Case $btn_Menu_RF
            _GlobalSoundPlay("sounds/enter.wav", "system")
            _RunSubWindow("_ShowRecentFiles")

        Case $btn_Menu_RD
            _GlobalSoundPlay("sounds/enter.wav", "system")
            _RunSubWindow("_ShowRecentFolders")

        Case $btn_Menu_Radio
            _GlobalSoundPlay("sounds/enter.wav", "system")
            _RunSubWindow("_ShowRadioPlayer")

        Case $btn_Menu_RadioFav
            _GlobalSoundPlay("sounds/enter.wav", "system")
            _RunSubWindow("_ShowRadioFavorites")

        Case $btn_Menu_Podcasts
            _GlobalSoundPlay("sounds/enter.wav", "system")
            _RunSubWindow("_ShowPodcasts")

        Case $btn_Menu_YTS
            _GlobalSoundPlay("sounds/enter.wav", "system")
            _RunSubWindow("_YTS_SubsWindow")

        Case $btn_Menu_Queue
            _GlobalSoundPlay("sounds/enter.wav", "system")
            _RunSubWindow("_ShowPlayQueue")

        Case $btn_Menu_DQ
            _GlobalSoundPlay("sounds/enter.wav", "system")
            _RunSubWindow("_ShowDownloadQueue")

        Case $btn_Menu_FV
            _GlobalSoundPlay("sounds/enter.wav", "system")
            _RunSubWindow("_ShowFavorites")

        Case $btn_Menu_WS
            _GlobalSoundPlay("sounds/enter.wav", "system")
            _RunSubWindow("_ShowHistory")

        Case $menu_about
            _GlobalSoundPlay("sounds/enter.wav", "system")
            _RunSubWindow("_Show_About_Window")
        Case $menu_website
            _GlobalSoundPlay("sounds/enter.wav", "system")
            ShellExecute("https://github.com/vo-dinh-hung/vdh_media_center")
        Case $menu_readme, $hDummyReadme
            _GlobalSoundPlay("sounds/enter.wav", "system")
            _RunSubWindow("_Show_Readme_Window")
        Case $menu_contact
            _GlobalSoundPlay("sounds/enter.wav", "system")
            _RunSubWindow("_Show_Contact_Window")
        Case $menu_update_ytdlp, $hDummyUpdateYTDLP
            _GlobalSoundPlay("sounds/enter.wav", "system")
            _Check_YTDLP_Update()
        Case $menu_Update_app, $hDummyUpdateApp
            _GlobalSoundPlay("sounds/enter.wav", "system")
            _CheckGithubUpdate()
        Case $menuChangelog, $hDummyChangelog
            _GlobalSoundPlay("sounds/enter.wav", "system")
            _RunSubWindow("_ShowChangelog")
        Case $menuContribute
            _GlobalSoundPlay("sounds/enter.wav", "system")
            _RunSubWindow("contribute")
        Case $menuSendFeedback
            _GlobalSoundPlay("sounds/enter.wav", "system")
            _RunSubWindow("_Show_Send_Feedback_Window")
        Case $menu_settings, $hDummySettings
            _GlobalSoundPlay("sounds/enter.wav", "system")
            _RunSubWindow("_ShowSettings")
        Case $hDummyEscMain
            ; Prevent closing with Escape
    EndSwitch
WEnd

Func _CheckUpdatesSilently()
    ; Neu dang co cua so con mo thi hoan lai, tranh mo them giao dien chong len nhau
    If $g_bSubWindowOpen Then Return
    AdlibUnRegister("_CheckUpdatesSilently")
    ; Kiểm tra tuần tự: cập nhật ứng dụng trước, sau đó mới đến yt-dlp,
    ; để tránh 2 hộp thoại kiểm tra cập nhật chồng lên nhau gây rối người dùng.
    If $g_bAutoUpdate Then
        If Ping("github.com", 1000) > 0 Then
            _CheckGithubUpdate(True) ; Gọi ngầm không hiển thị GUI
        EndIf
    EndIf

    If $g_bAutoUpdateYTDLP Then
        If Ping("github.com", 1000) > 0 Then
            _Check_YTDLP_Update(True) ; Gọi ngầm không hiển thị GUI
        EndIf
    EndIf
EndFunc

; Diệt TOÀN BỘ cây tiến trình bắt đầu từ $iPid (dùng "taskkill /F /T /PID").
; Lý do cần hàm riêng: yt-dlp thường tự sinh ra tiến trình ffmpeg con (để ghép
; audio/video hoặc convert sang định dạng đích như mp3) như một tiến trình Windows
; ĐỘC LẬP. Nếu chỉ ProcessClose($iPid) (diệt mỗi yt-dlp.exe) thì ffmpeg con này
; KHÔNG bị ảnh hưởng - nó vẫn tiếp tục chạy mồ côi và tiếp tục ghi vào file .mp3/
; .m4a/... dù người dùng đã bấm Yes để hủy. Đây chính là nguyên nhân file tải vẫn
; "tiếp tục" sau khi hủy và không xóa được (file đang bị ffmpeg giữ/khóa).
; "taskkill /T" diệt cả tiến trình cha lẫn mọi tiến trình con của nó theo đúng cây
; tiến trình thật (không đoán tên), nên đáng tin cậy hơn nhiều so với việc gọi
; ProcessClose("ffmpeg.exe") theo tên (cách cũ), vốn có thể: (1) trễ nhịp - nếu
; ffmpeg chưa kịp khởi động tại đúng thời điểm gọi thì sẽ không bị diệt và tiếp tục
; sống sót, hoặc (2) diệt nhầm một tiến trình ffmpeg.exe KHÁC đang chạy cho việc
; khác trong app (ví dụ ffmpeg quét khoảng lặng của tính năng Skip Silence).
; Hàm này CHỜ cho đến khi taskkill thực sự chạy xong và xác nhận $iPid đã thoát
; hẳn, trước khi trả về - để bước xóa file phía sau không bị tranh chấp khóa file.
Func _KillProcessTree($iPid)
    If $iPid = 0 Then Return
    Local $iTaskKillPid = Run(@ComSpec & ' /c taskkill /F /T /PID ' & $iPid, "", @SW_HIDE)
    ProcessWaitClose($iTaskKillPid, 5) ; Đợi lệnh taskkill tự nó chạy xong (thường gần như tức thì)
    ProcessWaitClose($iPid, 3) ; Xác nhận tiến trình chính (yt-dlp) đã thực sự thoát hẳn
    If ProcessExists($iPid) Then ProcessClose($iPid) ; Phòng hờ cực hiếm: vẫn còn sống -> thử lại lần nữa
EndFunc

; ---- Tiến độ tải THẬT từ yt-dlp (đọc từ stdout, lệnh phải có --newline) ----
; Mảng trạng thái $aP:
;   [0] = mục (video) hiện tại trong playlist   [1] = tổng số mục
;   [2] = luồng hiện tại (video/audio tải riêng) [3] = tổng số luồng của mục đó
;   [4] = % của luồng hiện tại (0-100)           [5] = phần dòng chưa trọn (đệm)
;   [6] = đã nhận được thông tin tiến độ chưa
; yt-dlp tải video và audio thành 2 luồng riêng, mỗi luồng chạy 0 -> 100%, nên nếu chỉ
; hiển thị % của từng luồng thì thanh sẽ tụt về 0 giữa chừng. Ở đây gộp tất cả các luồng
; (và các mục trong playlist) thành MỘT thanh liền mạch 0 -> 100%.
Func _DL_NewProgressState()
    ; [7] = kích thước (byte) luồng hiện tại, 0 = chưa biết   [8] = tổng byte các luồng đã xong của mục hiện tại
    ; [9] = số luồng đã xong có biết kích thước                 [10] = tổng byte các mục đã xong  [11] = số mục đã xong có biết kích thước
    ; [12] = mốc thời gian lấy mẫu tốc độ gần nhất  [13] = tỉ lệ tại mốc đó  [14] = tốc độ làm mịn (tỉ lệ/giây)
    ; [15] = mốc thời gian khi tiến độ thật xuất hiện lần đầu (0 = chưa có)
    Local $aP[16] = [1, 1, 0, 1, 0, "", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    Return $aP
EndFunc

; Nạp thêm dữ liệu stdout mới. Trả về % tổng thể (0-99), hoặc -1 nếu chưa có thông tin nào.
; (100% chỉ được đặt khi tiến trình đã thực sự kết thúc, vì sau khi tải xong còn bước ghép/chuyển đổi.)
Func _DL_FeedProgress(ByRef $aP, $sChunk)
    $aP[5] &= $sChunk
    Local $i, $aM, $sLine, $aLines, $iLast = -1, $nItemBytes, $iKnownStr, $nSz
    If $aP[5] <> "" Then
        $aLines = StringSplit(StringReplace($aP[5], @CR, @LF), @LF, 2)
        $iLast = UBound($aLines) - 1
        $aP[5] = $aLines[$iLast] ; dòng cuối có thể chưa trọn -> giữ lại cho lần sau
    EndIf
    For $i = 0 To $iLast - 1
        $sLine = StringStripWS($aLines[$i], 3)
        If StringRegExp($sLine, "^\[download\] Downloading item \d+ of \d+") Then
            $aM = StringRegExp($sLine, "item (\d+) of (\d+)", 1)
            If Not @error Then
                ; Chốt dung lượng mục vừa xong (nếu biết đủ) để ước lượng các mục còn lại chính xác hơn
                $nItemBytes = $aP[8] + $aP[7]
                $iKnownStr = $aP[9] + (($aP[7] > 0) ? 1 : 0)
                If $nItemBytes > 0 And $iKnownStr >= $aP[2] Then
                    $aP[10] += $nItemBytes
                    $aP[11] += 1
                EndIf
                $aP[7] = 0
                $aP[8] = 0
                $aP[9] = 0
                $aP[0] = Number($aM[0])
                $aP[1] = Number($aM[1])
                $aP[2] = 0
                $aP[3] = 1
                $aP[4] = 0
                $aP[6] = 1
            EndIf
        ElseIf StringRegExp($sLine, "Downloading \d+ format\(s\):") Then
            ; vd: "Downloading 1 format(s): 137+140" -> 2 luồng
            $aM = StringRegExp($sLine, "format\(s\):\s*(\S+)", 1)
            If Not @error Then $aP[3] = UBound(StringSplit($aM[0], "+", 2))
        ElseIf StringRegExp($sLine, "^\[download\] Destination:") Then
            If $aP[7] > 0 Then ; chốt dung lượng luồng trước
                $aP[8] += $aP[7]
                $aP[9] += 1
            EndIf
            $aP[7] = 0
            $aP[2] += 1
            $aP[4] = 0
            $aP[6] = 1
        ElseIf StringInStr($sLine, "has already been downloaded") Then
            If $aP[7] > 0 Then
                $aP[8] += $aP[7]
                $aP[9] += 1
            EndIf
            $aP[7] = 0
            $aP[2] += 1
            $aP[4] = 100
            $aP[6] = 1
        Else
            ; vd: "[download]  45.0% of   5.00MiB at  1.20MiB/s ETA 00:03" (cũng nhận "of ~ 5.00MiB")
            $aM = StringRegExp($sLine, "^\[download\]\s+(\d+(?:\.\d+)?)%(?:\s+of\s+~?\s*(\d+(?:\.\d+)?)\s*([KMGT]?i?B))?", 1)
            If Not @error Then
                If $aP[2] < 1 Then $aP[2] = 1
                $aP[4] = Number($aM[0])
                If UBound($aM) >= 3 Then
                    $nSz = _DL_ParseSize($aM[1], $aM[2])
                    If $nSz > 0 Then $aP[7] = $nSz
                EndIf
                $aP[6] = 1
            EndIf
        EndIf
    Next

    Local $nFrac = _DL_Fraction($aP)
    If $nFrac < 0 Then Return -1
    Return Int($nFrac * 100)
EndFunc

; Đổi "5.00" + "MiB" thành số byte.
Func _DL_ParseSize($sNum, $sUnit)
    Local $nMul = 1
    Switch StringUpper(StringLeft($sUnit, 1))
        Case "K"
            $nMul = 1024
        Case "M"
            $nMul = 1048576
        Case "G"
            $nMul = 1073741824
        Case "T"
            $nMul = 1099511627776
    EndSwitch
    Return Number($sNum) * $nMul
EndFunc

; Tỉ lệ hoàn thành tổng thể (số thực 0 -> 0.99), hoặc -1 nếu chưa có thông tin tiến độ.
; Tính theo DUNG LƯỢNG THẬT (byte) của từng luồng/mục khi yt-dlp báo kích thước, nên luồng lớn (video)
; và luồng nhỏ (audio) được cân đúng trọng số; luồng/mục chưa biết kích thước được ước bằng mức trung bình
; của những phần đã biết. Nếu chưa biết kích thước thì quay về cách chia đều theo số luồng/số mục.
Func _DL_Fraction(ByRef $aP)
    If Not $aP[6] Then Return -1
    Local $iTotStreams = $aP[3]
    If $aP[2] > $iTotStreams Then $iTotStreams = $aP[2]
    If $iTotStreams < 1 Then $iTotStreams = 1
    Local $iDoneStreams = $aP[2] - 1
    If $iDoneStreams < 0 Then $iDoneStreams = 0
    Local $nPct = $aP[4] / 100
    Local $nItem, $nItemTotal = 0

    If $aP[9] >= $iDoneStreams And ($aP[7] > 0 Or $aP[9] > 0) Then
        Local $nCur = $aP[7]
        Local $iKnown = $aP[9]
        If $nCur > 0 Then $iKnown += 1
        Local $nAvg = ($aP[8] + $nCur) / $iKnown
        If $nCur <= 0 Then $nCur = $nAvg
        Local $iRemStreams = $iTotStreams - $iDoneStreams - 1
        If $iRemStreams < 0 Then $iRemStreams = 0
        $nItemTotal = $aP[8] + $nCur + $iRemStreams * $nAvg
        $nItem = ($aP[8] + $nCur * $nPct) / $nItemTotal
    Else
        $nItem = ($iDoneStreams + $nPct) / $iTotStreams
    EndIf

    Local $nAll
    Local $iItemsDone = $aP[0] - 1
    If $aP[1] > 1 And $nItemTotal > 0 And $aP[11] >= $iItemsDone Then
        Local $nAvgItem = ($aP[10] + $nItemTotal) / ($iItemsDone + 1)
        Local $nTotAll = $aP[10] + $nItemTotal + ($aP[1] - $aP[0]) * $nAvgItem
        $nAll = ($aP[10] + $nItemTotal * $nItem) / $nTotAll
    Else
        $nAll = ($iItemsDone + $nItem) / $aP[1]
    EndIf
    If $nAll > 0.99 Then $nAll = 0.99
    If $nAll < 0 Then $nAll = 0
    Return $nAll
EndFunc

; Đổi số giây thành chuỗi dễ đọc: "5s", "2m 05s", "1h 02m 05s" (dịch được qua file ngôn ngữ).
Func _DL_FormatDuration($iSec)
    $iSec = Int($iSec)
    If $iSec < 0 Then $iSec = 0
    Local $iH = Int($iSec / 3600)
    Local $iM = Int(Mod($iSec, 3600) / 60)
    Local $iS = Mod($iSec, 60)
    If $iH > 0 Then Return _TF("{1}h {2}m {3}s", $iH, StringFormat("%02d", $iM), StringFormat("%02d", $iS))
    If $iM > 0 Then Return _TF("{1}m {2}s", $iM, StringFormat("%02d", $iS))
    Return _TF("{1}s", $iS)
EndFunc

; Ước lượng thời gian còn lại (giây). Trả về -1 nếu chưa đủ dữ liệu.
; Cách tính: tỉ lệ hoàn thành THẬT (theo byte, xem _DL_Fraction) chia cho tốc độ tiến độ, trong đó tốc độ là
; trung bình của (a) tốc độ trung bình kể từ lúc yt-dlp bắt đầu báo tiến độ (không tính thời gian lấy thông
; tin ban đầu) và (b) tốc độ gần đây làm mịn (lấy mẫu mỗi giây) để phản ứng khi mạng nhanh/chậm đi.
Func _DL_RemainingSecs(ByRef $aP)
    Local $nFrac = _DL_Fraction($aP)
    If $nFrac < 0 Then Return -1
    If $aP[15] = 0 Then ; lần đầu có tiến độ: đặt mốc, chưa tính được
        $aP[15] = TimerInit()
        $aP[12] = $aP[15]
        $aP[13] = $nFrac
        Return -1
    EndIf
    Local $nSince = TimerDiff($aP[15]) / 1000
    Local $nDt = TimerDiff($aP[12]) / 1000
    If $nDt >= 1 Then ; lấy mẫu tốc độ tức thời mỗi giây rồi làm mịn
        Local $nDf = $nFrac - $aP[13]
        If $nDf < 0 Then $nDf = 0
        Local $nInst = $nDf / $nDt
        If $aP[14] <= 0 Then
            $aP[14] = $nInst
        Else
            $aP[14] = 0.3 * $nInst + 0.7 * $aP[14]
        EndIf
        $aP[12] = TimerInit()
        $aP[13] = $nFrac
    EndIf
    If $nFrac >= 0.99 Then Return 0 ; phần tải đã xong (còn bước ghép/chuyển đổi)
    If $nSince < 2 Then Return -1
    Local $nRate = $nFrac / $nSince
    If $aP[14] > 0 And $nRate > 0 Then $nRate = 0.5 * $nRate + 0.5 * $aP[14]
    If $nRate <= 0 Then Return -1
    Local $iRem = Int(Ceiling((1 - $nFrac) / $nRate))
    If $iRem > 359999 Then $iRem = 359999
    Return $iRem
EndFunc

; Chuỗi trạng thái "Thời gian đã trôi qua: ... | Thời gian còn lại: ..." dùng cho phần tải xuống.
; Luôn hiện đủ cả hai nhãn; khi chưa đủ dữ liệu thì phần còn lại ghi "đang tính...".
Func _DL_TimeStatusText($iStartTimer, ByRef $aP)
    Local $sElapsed = _DL_FormatDuration(TimerDiff($iStartTimer) / 1000)
    Local $iRem = _DL_RemainingSecs($aP)
    Local $sRem = ($iRem < 0) ? _T("calculating...") : _DL_FormatDuration($iRem)
    Return _TF("Elapsed time: {1} | Remaining time: {2}", $sElapsed, $sRem)
EndFunc

; Chạy lệnh tải xuống (yt-dlp) với cửa sổ console ẩn.
; Đọc stdout/stderr qua pipe (được rút liên tục trong vòng lặp nên không bị đầy/treo) để lấy
; % tiến độ THẬT của yt-dlp; thanh tiến trình chạy liền mạch 0 -> 100%, không tụt về 0.
; Khi người dùng đóng cửa sổ (hủy) sẽ có hộp thoại xác nhận; nếu chọn Yes và có
; truyền $sWatchDir, file đang tải dở (*.part, *.ytdl) trong thư mục đó sẽ bị xóa.
; Trả về True nếu tải xong, False nếu người dùng huỷ (đã xác nhận).
Func _RunDownloadWithProgress($sCmd, $idProgress = -1, $idLabel = -1, $sWatchDir = "")
    Local $sFilesBefore = ""
    If $sWatchDir <> "" Then $sFilesBefore = _ListFilesRecursive($sWatchDir) ; "Trước ảnh" để biết file nào mới sinh ra

    Local $iPid = Run($sCmd, @ScriptDir, @SW_HIDE, $STDOUT_CHILD + $STDERR_CHILD)
    Local $iStart = TimerInit()
    Local $aProg = _DL_NewProgressState()
    Local $iShownPct = 0
    Local $sLastLbl = ""

    If $idProgress <> -1 Then GUICtrlSetData($idProgress, 0)
    If $idLabel <> -1 Then GUICtrlSetData($idLabel, _T("Downloading..."))
    _DLSound_Start()

    While ProcessExists($iPid)
        _DLSound_Tick()
        Local $iRealPct = _DL_FeedProgress($aProg, StdoutRead($iPid))
        StderrRead($iPid) ; rút bỏ để pipe stderr không bị đầy
        If $iRealPct > $iShownPct Then ; chỉ tăng, không bao giờ lùi
            $iShownPct = $iRealPct
            If $idProgress <> -1 Then GUICtrlSetData($idProgress, $iShownPct)
        EndIf
        If $idLabel <> -1 Then
            Local $sNewLbl = _T("Downloading...") & " " & _DL_TimeStatusText($iStart, $aProg)
            If $sNewLbl <> $sLastLbl Then ; chỉ cập nhật khi nội dung đổi để trình đọc màn hình không đọc lặp
                GUICtrlSetData($idLabel, $sNewLbl)
                $sLastLbl = $sNewLbl
            EndIf
        EndIf

        If GUIGetMsg() = $GUI_EVENT_CLOSE Then
            Local $sConfirmMsg = _T("Are you sure you want to cancel?")
            If $sWatchDir <> "" Then $sConfirmMsg &= @CRLF & @CRLF & _T("The file currently being downloaded will be deleted.")
            Local $iConfirm = MsgBox(4 + 32 + 256, _T("Cancel"), $sConfirmMsg) ; Yes/No, question icon, default = Yes
            If $iConfirm = 6 Then ; IDYES
                ; Diệt cả cây tiến trình (yt-dlp + ffmpeg con nếu có) và đợi thoát hẳn
                ; trước khi xóa file, để tránh trường hợp ffmpeg con vẫn sống sót và
                ; tiếp tục ghi vào file .mp3/... sau khi đã hủy (xem _KillProcessTree).
                _KillProcessTree($iPid)
                If $sWatchDir <> "" Then _DeleteNewFiles($sWatchDir, $sFilesBefore)
                _DLSound_Stop()
                Return False
            EndIf
            ; IDNO: tiếp tục tải, không hủy
        EndIf
        Sleep(150)
    WEnd

    If $idProgress <> -1 Then GUICtrlSetData($idProgress, 100)
    If $idLabel <> -1 Then GUICtrlSetData($idLabel, _T("Done!"))
    Return True
EndFunc

; Hộp thoại tiến trình dùng chung cho các tác vụ chạy nền (Video Transcript, Download...).
; Hiển thị một cửa sổ riêng có nhãn + thanh tiến trình + nút Hủy, thay vì để lại
; giao diện bị vô hiệu hóa/trống rỗng hoặc chạy ẩn một cửa sổ console.
; Khi người dùng bấm Hủy sẽ có hộp thoại xác nhận; nếu chọn Yes và có truyền
; $sWatchDir, các file tải dở (*.part, *.ytdl) trong thư mục đó sẽ bị xóa.
; Trả về True nếu tiến trình chạy xong, False nếu người dùng hủy (đã xác nhận).
Func _RunTaskWithProgressDialog($sCmd, $sTitle, $sLabel, ByRef $sStdOut, ByRef $sStdErr, $hParent = 0, $sWatchDir = "", $bDownloadSound = False)
    Local $hGui
    If $hParent <> 0 And IsHWnd($hParent) Then
        $hGui = GUICreate(_T($sTitle), 380, 135, -1, -1, -1, -1, $hParent)
    Else
        $hGui = GUICreate(_T($sTitle), 380, 135)
    EndIf
    GUISetBkColor($COLOR_BLUE, $hGui)

    GUICtrlCreateLabel(_T($sLabel), 10, 15, 360, 20, $SS_CENTER)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $idProgress = GUICtrlCreateProgress(10, 45, 360, 20)
    Local $idStatus = GUICtrlCreateLabel("", 10, 70, 360, 16, $SS_CENTER)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $idCancel = GUICtrlCreateButton(_T("Cancel"), 130, 96, 120, 28)

    Local $hDummyEscTask = GUICtrlCreateDummy()
    Local $aAccelTask[1][2] = [["{ESC}", $hDummyEscTask]]
    GUISetAccelerators($aAccelTask, $hGui)

    GUISetState(@SW_SHOW, $hGui)
    _AllowUIPI($hGui)

    Local $sFilesBefore = ""
    If $sWatchDir <> "" Then $sFilesBefore = _ListFilesRecursive($sWatchDir) ; "Trước ảnh" để biết file nào mới sinh ra

    Local $iPid = Run($sCmd, @ScriptDir, @SW_HIDE, $STDOUT_CHILD + $STDERR_CHILD)
    Local $iStart = TimerInit()
    Local $bCancelled = False
    If $bDownloadSound Then _DLSound_Start()
    Local $bRealPct = ($sWatchDir <> "") ; có $sWatchDir = tác vụ tải xuống -> dùng % thật của yt-dlp
    Local $aProg = _DL_NewProgressState()
    Local $iShownPct = 0
    Local $sLastSt = ""

    While ProcessExists($iPid)
        If $bDownloadSound Then _DLSound_Tick()
        Local $sNewOut = StdoutRead($iPid)
        $sStdOut &= $sNewOut
        $sStdErr &= StderrRead($iPid)

        Local $iNewPct = -1
        If $bRealPct Then
            $iNewPct = _DL_FeedProgress($aProg, $sNewOut)
        Else
            ; Tác vụ không có % thật (transcript, lyrics...): tiến dần về ~95%, tuyệt đối không quay về 0
            $iNewPct = Int(95 * (1 - Exp(-TimerDiff($iStart) / 15000)))
        EndIf
        If $iNewPct > $iShownPct Then ; chỉ tăng, không bao giờ lùi
            $iShownPct = $iNewPct
            GUICtrlSetData($idProgress, $iShownPct)
        EndIf
        Local $sNewSt
        If $bRealPct Then
            ; Tác vụ tải xuống: hiện thời gian đã trôi qua + thời gian còn lại (ước tính theo tiến độ thật)
            $sNewSt = _DL_TimeStatusText($iStart, $aProg)
        Else
            $sNewSt = _TF("{1}s", Int(TimerDiff($iStart) / 1000))
        EndIf
        If $sNewSt <> $sLastSt Then
            GUICtrlSetData($idStatus, $sNewSt)
            $sLastSt = $sNewSt
        EndIf

        Local $iMsg = _GuiMsg($hGui)
        If $iMsg = $GUI_EVENT_CLOSE Or $iMsg = $idCancel Or $iMsg = $hDummyEscTask Then
            Local $sConfirmMsg = _T("Are you sure you want to cancel?")
            If $sWatchDir <> "" Then $sConfirmMsg &= @CRLF & @CRLF & _T("The file currently being downloaded will be deleted.")
            Local $iConfirm = MsgBox(4 + 32 + 256, _T("Cancel"), $sConfirmMsg, 0, $hGui) ; Yes/No, question icon, default = Yes
            If $iConfirm = 6 Then ; IDYES
                ; Diệt cả cây tiến trình (yt-dlp + ffmpeg con nếu có) và đợi thoát hẳn
                ; trước khi xóa file, để tránh trường hợp ffmpeg con vẫn sống sót và
                ; tiếp tục ghi vào file .mp3/... sau khi đã hủy (xem _KillProcessTree).
                _KillProcessTree($iPid)
                If $sWatchDir <> "" Then _DeleteNewFiles($sWatchDir, $sFilesBefore)
                $bCancelled = True
                ExitLoop
            EndIf
            ; IDNO: tiếp tục chạy, không hủy
        EndIf
        Sleep(150)
    WEnd
    If $bDownloadSound Then _DLSound_Stop()

    $sStdOut &= StdoutRead($iPid)
    $sStdErr &= StderrRead($iPid)

    If Not $bCancelled Then
        GUICtrlSetData($idProgress, 100)
        GUICtrlSetData($idStatus, _T("Done!"))
        Sleep(200)
    EndIf

    GUIDelete($hGui)
    Return Not $bCancelled
EndFunc

; Trả về mảng các file MỚI xuất hiện trong $sDir kể từ lúc chụp "trước ảnh" $sFilesBefore
; (lấy từ _ListFilesRecursive), chỉ tính các định dạng Download tạo ra (bỏ *.part/*.ytdl).
; Mảng được sắp theo thứ tự bảng chữ cái; mảng rỗng (UBound = 0) nếu không có file mới.
Func _GetNewDownloadedFiles($sDir, $sFilesBefore)
    Local $aResult[0]
    Local $aAfter = StringSplit(_ListFilesRecursive($sDir), "|", 2)
    If Not IsArray($aAfter) Then Return $aResult
    Local $iCount = 0
    For $i = 0 To UBound($aAfter) - 1
        Local $sF = $aAfter[$i]
        If $sF = "" Then ContinueLoop
        If StringInStr($sFilesBefore, $sF & "|") Then ContinueLoop
        Local $aExt = StringRegExp($sF, "\.([A-Za-z0-9]+)$", 3)
        If Not IsArray($aExt) Then ContinueLoop
        Local $sExt = "." & StringLower($aExt[0])
        If $sExt = ".part" Or $sExt = ".ytdl" Then ContinueLoop
        If Not StringInStr($g_sDownloadSupportedExts, $sExt & ";") Then ContinueLoop
        $iCount += 1
        ReDim $aResult[$iCount]
        $aResult[$iCount - 1] = $sF
    Next
    If $iCount > 1 Then _ArraySort($aResult)
    Return $aResult
EndFunc

; Hộp thoại "Tải xuống hoàn tất" dùng chung cho mọi luồng tải xuống.
;  - Play: làm theo lựa chọn trong Settings > Player > "Play button action".
;  - Open Download Folder: mở Explorer tại nơi chứa file vừa tải (chọn sẵn file đó).
; $aFiles là mảng file mới vừa tải (từ _GetNewDownloadedFiles), có thể rỗng.
Func _ShowDownloadCompleteDialog($sFolder, $aFiles, $sTitle = "Download Complete", $sMsg = "Download Complete!")
    Local $hDlg = GUICreate(_T($sTitle), 340, 200, -1, -1, BitOR($WS_CAPTION, $WS_SYSMENU), $WS_EX_TOPMOST)
    GUISetBkColor($COLOR_BLUE, $hDlg)

    GUICtrlCreateLabel(_T($sMsg), 10, 15, 320, 20, $SS_CENTER)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $btn_Play = GUICtrlCreateButton(_T("Play (Alt+P)"), 40, 50, 260, 35)
    Local $btn_OpenFolder = GUICtrlCreateButton(_T("Open Download Folder (Alt+O)"), 40, 95, 260, 35)
    Local $btn_OK = GUICtrlCreateButton(_T("OK"), 40, 140, 260, 35)
    GUICtrlSetState($btn_OK, $GUI_DEFBUTTON)

    Local $aAccelDone[3][2] = [["!p", $btn_Play], ["!o", $btn_OpenFolder], ["{ESC}", $btn_OK]]
    GUISetAccelerators($aAccelDone, $hDlg)

    GUISetState(@SW_SHOW, $hDlg)
    _AllowUIPI($hDlg)
    GUICtrlSetState($btn_OK, $GUI_FOCUS)

    While 1
        Local $nMsg = _GuiMsg($hDlg)
        Switch $nMsg
            Case $GUI_EVENT_CLOSE, $btn_OK
                ExitLoop

            Case $btn_OpenFolder
                If UBound($aFiles) > 0 And FileExists($aFiles[0]) Then
                    Run('explorer.exe /select,"' & $aFiles[0] & '"')
                Else
                    ShellExecute($sFolder)
                EndIf

            Case $btn_Play
                _PlayDownloadedFiles($aFiles, $hDlg)
        EndSwitch
    WEnd
    GUIDelete($hDlg)
EndFunc

; Thực hiện hành động của nút Play theo $g_iPlayAction.
Func _PlayDownloadedFiles($aFiles, $hDlg)
    If UBound($aFiles) = 0 Then
        MsgBox(48, _T("Play"), _T("Could not find the downloaded file to play."), 0, $hDlg)
        Return
    EndIf

    ; Giao diện Playing đang mở (hộp thoại tải xuống được mở từ trình phát online):
    ; không thể mở thêm một trình phát lồng bên trong, nên dùng trình phát của máy tính.
    If $g_iPlayAction <> 1 Or IsHWnd($hPlayGui) Then
        ShellExecute($aFiles[0])
        Return
    EndIf

    ; Trình phát mặc định của ứng dụng: kích hoạt giao diện Playing của "Listen to Audio File"
    GUISetState(@SW_HIDE, $hDlg)
    If UBound($aFiles) = 1 Then
        _PlayLocalAudioFile($aFiles[0])
    Else
        ; Tải nhiều file (playlist/collection): phát như một danh sách, có phím n/b
        ReDim $g_aLocalPlaylist[UBound($aFiles)]
        For $i = 0 To UBound($aFiles) - 1
            $g_aLocalPlaylist[$i] = $aFiles[$i]
        Next
        $g_iLocalPlaylistCount = UBound($aFiles)
        $g_bLocalPlaylistMode = True
        _PlayLocalFolder(0)
    EndIf
    GUISetState(@SW_SHOW, $hDlg)
    WinActivate($hDlg)
EndFunc

; Chụp danh sách toàn bộ file (mọi định dạng, đệ quy) hiện có trong $sDir tại một
; thời điểm, dùng làm "trước ảnh" để so sánh sau này. Trả về chuỗi các đường dẫn
; đầy đủ, mỗi đường dẫn kết thúc bằng "|".
Func _ListFilesRecursive($sDir, $iDepth = 0)
    Local $sList = ""
    If $iDepth > 6 Or Not FileExists($sDir) Then Return $sList
    If $iDepth = 0 Then
        While StringRight($sDir, 1) = "\" Or StringRight($sDir, 1) = "/"
            $sDir = StringTrimRight($sDir, 1)
        WEnd
    EndIf
    Local $hSearch = FileFindFirstFile($sDir & "\*")
    If $hSearch = -1 Then Return $sList
    While 1
        Local $sName = FileFindNextFile($hSearch)
        If @error Then ExitLoop
        If $sName = "." Or $sName = ".." Then ContinueLoop
        Local $sFull = $sDir & "\" & $sName
        If StringInStr(FileGetAttrib($sFull), "D") Then
            $sList &= _ListFilesRecursive($sFull, $iDepth + 1)
        Else
            $sList &= $sFull & "|"
        EndIf
    WEnd
    FileClose($hSearch)
    Return $sList
EndFunc

; So sánh với "trước ảnh" $sFilesBefore (lấy từ _ListFilesRecursive) và xóa các file MỚI
; xuất hiện trong $sDir kể từ lúc chụp, CHỈ khi đó là định dạng mà tính năng Download
; thực sự hỗ trợ/tạo ra (xem $g_sDownloadSupportedExts: mp3, wav, m4a, ogg, mp4, webm,
; cùng file dở dang *.part/*.ytdl của yt-dlp). File có định dạng khác (không phải do lần
; tải vừa bị hủy sinh ra) sẽ không bị đụng tới, tránh xóa nhầm file người dùng tự thêm vào
; thư mục trong lúc tải. Các file đã có từ trước (những lần tải trước đó đã hoàn tất)
; cũng không bị đụng tới.
Func _DeleteNewFiles($sDir, $sFilesBefore, $iDepth = 0)
    If $iDepth > 6 Or Not FileExists($sDir) Then Return
    If $iDepth = 0 Then
        While StringRight($sDir, 1) = "\" Or StringRight($sDir, 1) = "/"
            $sDir = StringTrimRight($sDir, 1)
        WEnd
    EndIf
    Local $hSearch = FileFindFirstFile($sDir & "\*")
    If $hSearch = -1 Then Return
    While 1
        Local $sName = FileFindNextFile($hSearch)
        If @error Then ExitLoop
        If $sName = "." Or $sName = ".." Then ContinueLoop
        Local $sFull = $sDir & "\" & $sName
        If StringInStr(FileGetAttrib($sFull), "D") Then
            _DeleteNewFiles($sFull, $sFilesBefore, $iDepth + 1)
        Else
            If Not StringInStr($sFilesBefore, $sFull & "|") Then
                Local $aExtMatch = StringRegExp($sName, "\.([A-Za-z0-9]+)$", 3)
                If IsArray($aExtMatch) Then
                    Local $sExt = "." & StringLower($aExtMatch[0])
                    If StringInStr($g_sDownloadSupportedExts, $sExt & ";") Then
                        _DeleteWithRetry($sFull) ; File mới, đúng định dạng Download hỗ trợ -> xóa
                    EndIf
                EndIf
            EndIf
        EndIf
    WEnd
    FileClose($hSearch)
EndFunc

; Xóa theo $sPattern (đường dẫn cụ thể hoặc có ký tự đại diện), thử lại tối đa
; ~2 giây nếu file vẫn còn tồn tại (trường hợp handle chưa được hệ điều hành
; giải phóng ngay sau khi kill tiến trình).
Func _DeleteWithRetry($sPattern)
    Local $i = 0
    While $i < 16 ; ~4 giây - đủ thời gian để Windows nhả khóa file sau khi taskkill diệt tiến trình
        FileDelete($sPattern)
        If Not _AnyFileMatches($sPattern) Then Return
        Sleep(250)
        $i += 1
    WEnd
EndFunc

Func _AnyFileMatches($sPattern)
    Local $hFind = FileFindFirstFile($sPattern)
    If $hFind = -1 Then Return False
    FileClose($hFind)
    Return True
EndFunc

Func _ShowDownloader()
    $g_hGuiDL = GUICreate(_T("Video Downloader"), 400, 380)
    GUISetBkColor($COLOR_BLUE)

    $g_hTabDL = GUICtrlCreateTab(10, 10, 380, 40)
    Local $aTabNames[5] = ["YouTube", "Facebook", "TikTok", "Instagram", "SoundCloud"]
    Local $aTabItems[5]
    Local $g_aInpLinks[5]
    For $i = 0 To 4
        $aTabItems[$i] = GUICtrlCreateTabItem($aTabNames[$i])
        GUICtrlCreateLabel(_TF("Enter the {1} URL link here:", $aTabNames[$i]), 10, 60, 380, 20)
        GUICtrlSetColor(-1, 0xFFFFFF)
        $g_aInpLinks[$i] = GUICtrlCreateInput("", 10, 85, 380, 20)
        GUICtrlSetTip(-1, _TF("Enter the {1} track/video URL here", $aTabNames[$i]))
        _AllowUIPI($g_aInpLinks[$i])
    Next
    GUICtrlCreateTabItem("") ; end tab

    Local $clip = ClipGet()
    Local $iDetectedTab = -1
    For $i = 0 To 4
        If _IsUrlMatchTab($clip, $i) Then
            $iDetectedTab = $i
            ExitLoop
        EndIf
    Next

    If $iDetectedTab <> -1 Then
        GUICtrlSetState($aTabItems[$iDetectedTab], $GUI_SHOW)
        GUICtrlSetData($g_aInpLinks[$iDetectedTab], $clip)
    Else
        GUICtrlSetState($aTabItems[0], $GUI_SHOW)
    EndIf

    $paste = GUICtrlCreateButton(_T("Paste Link (Alt+P)"), 320, 115, 70, 20)

    GUICtrlCreateLabel(_T("Select Format :"), 10, 115, 180, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    $cbo_dl_format = GUICtrlCreateCombo("", 10, 140, 180, 20, $CBS_DROPDOWNLIST)
    GUICtrlSetTip(-1, _T("Select the download format. Use the arrow keys to browse the list in alphabetical order"))
    GUICtrlSetData(-1, _TL("M4A (Audio)|MP3 (Audio)|MP4 (Video, Best)|OGG (Audio)|WAV (Audio)|WebM (Video)"), _T("MP4 (Video, Best)"))

    GUICtrlCreateLabel(_T("Select Bitrate:"), 210, 115, 180, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    $cbo_dl_bitrate = GUICtrlCreateCombo("", 210, 140, 180, 20, $CBS_DROPDOWNLIST)
    GUICtrlSetTip(-1, _T("Select the bitrate (kbps). Use the arrow keys to browse from low to high"))
    GUICtrlSetData(-1, _TL("128 kbps|192 kbps|256 kbps|320 kbps"), _T("320 kbps"))

    Local $chk_custom_name = GUICtrlCreateCheckbox(_T("Choose custom output filename composition"), 10, 170, 380, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $cbo_name_type = GUICtrlCreateCombo("", 10, 195, 380, 20, $CBS_DROPDOWNLIST)
    GUICtrlSetTip(-1, _T("Select the file naming style. Use the arrow keys to browse the list in alphabetical order"))
    GUICtrlSetData(-1, _TL("No numbering|No numbering and create subdirectory|Numbering|Numbering and create subdirectory"), _T("No numbering"))
    GUICtrlSetState(-1, $GUI_DISABLE)

    $btn_start_dl = GUICtrlCreateButton(_T("Download (Alt+D)"), 10, 230, 255, 40)
    Local $btn_close = GUICtrlCreateButton(_T("Cancel"), 275, 230, 115, 40) ; Cancel sits next to Download and closes this window
    $openbtn = GUICtrlCreateButton(_T("Open Download Folder (Alt+O)"), 10, 280, 380, 30)

    Local $lbl_dl_status = GUICtrlCreateLabel("", 10, 325, 380, 16)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $prog_dl = GUICtrlCreateProgress(10, 345, 380, 20)

    Local $hDummyEscDL = GUICtrlCreateDummy()
    $g_hDummyNextDL = GUICtrlCreateDummy()
    $g_hDummyPrevDL = GUICtrlCreateDummy()
    Local $aAccelDL[4][2] = [["!p", $paste], ["!d", $btn_start_dl], ["!o", $openbtn], ["{ESC}", $hDummyEscDL]]
    GUISetAccelerators($aAccelDL, $g_hGuiDL)

    GUISetState(@SW_SHOW, $g_hGuiDL)
    _AllowUIPI($g_hGuiDL)
    If $iDetectedTab <> -1 Then
        ControlFocus($g_hGuiDL, "", $g_aInpLinks[$iDetectedTab])
    Else
        ControlFocus($g_hGuiDL, "", $g_aInpLinks[0])
    EndIf

    GUIRegisterMsg($WM_ACTIVATE, "_Downloader_WM_ACTIVATE")
    _Downloader_ToggleHotKeys(True)

    While 1
        Local $nMsg = _GuiMsg($g_hGuiDL)
        Switch $nMsg
            Case $GUI_EVENT_CLOSE, $hDummyEscDL, $btn_close
                _Downloader_ToggleHotKeys(False)
                GUIRegisterMsg($WM_ACTIVATE, "")
                GUIDelete($g_hGuiDL)
                GUISetState(@SW_SHOW, $mainform)
                ExitLoop

            Case $g_hTabDL
                ControlFocus($g_hGuiDL, "", $g_hTabDL)

            Case $g_hDummyNextDL
                Local $hTabHandle = GUICtrlGetHandle($g_hTabDL)
                Local $iCount = _GUICtrlTab_GetItemCount($hTabHandle)
                Local $iCur = _GUICtrlTab_GetCurSel($hTabHandle)
                Local $iNext = ($iCur + 1 >= $iCount) ? 0 : $iCur + 1
                GUICtrlSetState($aTabItems[$iNext], $GUI_SHOW)
                ControlFocus($g_hGuiDL, "", $g_hTabDL)

            Case $g_hDummyPrevDL
                Local $hTabHandle = GUICtrlGetHandle($g_hTabDL)
                Local $iCount = _GUICtrlTab_GetItemCount($hTabHandle)
                Local $iCur = _GUICtrlTab_GetCurSel($hTabHandle)
                Local $iPrev = ($iCur - 1 < 0) ? $iCount - 1 : $iCur - 1
                GUICtrlSetState($aTabItems[$iPrev], $GUI_SHOW)
                ControlFocus($g_hGuiDL, "", $g_hTabDL)

            Case $paste
                Local $iCur = _GUICtrlTab_GetCurSel(GUICtrlGetHandle($g_hTabDL))
                GUICtrlSetData($g_aInpLinks[$iCur], ClipGet())

            Case $chk_custom_name
                If GUICtrlRead($chk_custom_name) = $GUI_CHECKED Then
                    GUICtrlSetState($cbo_name_type, $GUI_ENABLE)
                Else
                    GUICtrlSetState($cbo_name_type, $GUI_DISABLE)
                EndIf

            Case $openbtn
                If StringStripWS($g_sDownloadPath, 3) = "" Or Not FileExists($g_sDownloadPath) Then
                    $g_sDownloadPath = @ScriptDir & "\download"
                    If Not FileExists($g_sDownloadPath) Then DirCreate($g_sDownloadPath)
                EndIf
                ShellExecute($g_sDownloadPath)

            Case $btn_start_dl
                Local $iCurTab = _GUICtrlTab_GetCurSel(GUICtrlGetHandle($g_hTabDL))
                Local $url = GUICtrlRead($g_aInpLinks[$iCurTab])
                If $url = "" Then
                    MsgBox(16, _T("Error"), _T("Please enter the URL!"))
                Else
                    If Not _IsUrlMatchTab($url, $iCurTab) Then
                        Local $sTabName = _GUICtrlTab_GetItemText(GUICtrlGetHandle($g_hTabDL), $iCurTab)
                        MsgBox(16, _T("Error"), _TF("The current link is not supported in the {1} tab. Please switch to the correct tab or use a valid link.", $sTabName))
                        ContinueLoop
                    EndIf

                    Local $sTxt = _TR(GUICtrlRead($cbo_dl_format))
                    Local $sFmt = ""

                    If StringInStr($sTxt, "MP3") Then
                        $sFmt = "-x --audio-format mp3"
                    ElseIf StringInStr($sTxt, "WAV") Then
                        $sFmt = "-x --audio-format wav"
                    ElseIf StringInStr($sTxt, "M4A") Then
                        $sFmt = "-x --audio-format m4a"
                    ElseIf StringInStr($sTxt, "OGG") Then
                        $sFmt = "-x --audio-format vorbis"
                    ElseIf StringInStr($sTxt, "WebM") Then
                        $sFmt = "bestvideo+bestaudio --merge-output-format webm"
                    Else
                        $sFmt = "-f bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best"
                    EndIf
            Local $sBitrate = GUICtrlRead($cbo_dl_bitrate)
            Local $iKbps = StringRegExpReplace($sBitrate, "[^0-9]", "")
            If $iKbps <> "" And (StringInStr($sTxt, "Audio") Or StringInStr($sTxt, "MP3") Or StringInStr($sTxt, "WAV") Or StringInStr($sTxt, "M4A") Or StringInStr($sTxt, "OGG")) Then
                $sFmt &= " --audio-quality " & $iKbps & "k"
            EndIf

                    Local $sExtraArgs = ""
                    If StringInStr($url, "watch?v=") And StringInStr($url, "list=") Then
                        $sExtraArgs = " --no-playlist"
                    EndIf

                    Local $sOutTemplate = "%(title)s.%(ext)s"
                    If GUICtrlRead($chk_custom_name) = $GUI_CHECKED Then
                        Local $sNameSel = _TR(GUICtrlRead($cbo_name_type))
                        If $sNameSel = "No numbering and create subdirectory" Then
                            $sOutTemplate = "%(title)s/%(title)s.%(ext)s"
                        ElseIf $sNameSel = "Numbering" Then
                            $sOutTemplate = "%(playlist_index)s - %(title)s.%(ext)s"
                        ElseIf $sNameSel = "Numbering and create subdirectory" Then
                            $sOutTemplate = "%(playlist_title)s/%(playlist_index)s - %(title)s.%(ext)s"
                        EndIf
                    EndIf

                    _AppSoundPlay(@ScriptDir & "\sounds\download-started.wav") ; Âm thanh báo bắt đầu tải
                    GUICtrlSetState($btn_start_dl, $GUI_DISABLE)
                    Local $sFinalDownloadPath = $g_sDownloadPath
                    If StringStripWS($sFinalDownloadPath, 3) = "" Then $sFinalDownloadPath = @ScriptDir & "\download"
                    If Not FileExists($sFinalDownloadPath) Then DirCreate($sFinalDownloadPath)
                    While StringRight($sFinalDownloadPath, 1) = "\" Or StringRight($sFinalDownloadPath, 1) = "/"
                        $sFinalDownloadPath = StringTrimRight($sFinalDownloadPath, 1)
                    WEnd
                    Local $sCmd = $YT_DLP_EXE & ' --newline ' & $sFmt & ' ' & $sExtraArgs & ' -P "' & $sFinalDownloadPath & '" --ffmpeg-location "' & @ScriptDir & '\lib" -o "' & $sOutTemplate & '" -- "' & $url & '"'
                    Local $sDLSnapshot = _ListFilesRecursive($sFinalDownloadPath)
                    Local $bDLDone = _RunDownloadWithProgress($sCmd, $prog_dl, $lbl_dl_status, $sFinalDownloadPath)
                    If Not $bDLDone Then
                        _Downloader_ToggleHotKeys(False)
                        GUIRegisterMsg($WM_ACTIVATE, "")
                        GUIDelete($g_hGuiDL)
                        GUISetState(@SW_SHOW, $mainform)
                        Return
                    EndIf
                    GUICtrlSetState($btn_start_dl, $GUI_ENABLE)
                    GUICtrlSetData($lbl_dl_status, "")
                    GUICtrlSetData($prog_dl, 0)
_DLSound_Stop()
_AppSoundPlay(@ScriptDir & "\sounds\download_finish.wav")
                    _ShowDownloadCompleteDialog($sFinalDownloadPath, _GetNewDownloadedFiles($sFinalDownloadPath, $sDLSnapshot))
                EndIf
        EndSwitch
    WEnd
EndFunc

Func _ShowPlayer()
    Local $hGuiPL = GUICreate(_T("Video and Music Link Player"), 400, 290)
    GUISetBkColor($COLOR_BLUE)

    GUICtrlCreateLabel(_T("Enter the YouTube or SoundCloud link you want to play:"), 10, 20, 380, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    $linkedit = GUICtrlCreateInput("", 10, 50, 380, 20)

    $play_btn = GUICtrlCreateButton(_T("Play (Default Player) (Alt+P)"), 50, 80, 300, 35)
    $audio_play_btn = GUICtrlCreateButton(_T("Play as Audio (Alt+A)"), 50, 125, 300, 35)
    $online_play_btn = GUICtrlCreateButton(_T("Play in Browser (Alt+B)"), 50, 170, 300, 35)
    Local $btn_close_PL = GUICtrlCreateButton(_T("Close"), 50, 215, 300, 35)

    Local $hDummyEscPL = GUICtrlCreateDummy()
    Local $aAccelPL[4][2] = [["!p", $play_btn], ["!a", $audio_play_btn], ["!b", $online_play_btn], ["{ESC}", $hDummyEscPL]]
    GUISetAccelerators($aAccelPL, $hGuiPL)

    GUISetState(@SW_SHOW, $hGuiPL)
    _AllowUIPI($hGuiPL)
    _AllowUIPI($linkedit)
    ControlFocus($hGuiPL, "", $linkedit)

    While 1
        Local $nMsg = _GuiMsg($hGuiPL)
        Switch $nMsg
            Case $GUI_EVENT_CLOSE, $btn_close_PL, $hDummyEscPL
                GUIDelete($hGuiPL)
                GUISetState(@SW_SHOW, $mainform)
                ExitLoop

            Case $play_btn
                Local $input_text = GUICtrlRead($linkedit)
                If $input_text = "" Then
                    MsgBox(16, _T("Error"), _T("Please enter the video link!"))
                Else
                    playmedia($input_text)
                EndIf

            Case $audio_play_btn
                Local $input_text = GUICtrlRead($linkedit)
                If $input_text = "" Then
                    MsgBox(16, _T("Error"), _T("Please enter the video link!"))
                Else
                    playaudio($input_text)
                EndIf

            Case $online_play_btn
                Local $input_text = GUICtrlRead($linkedit)
                If $input_text = "" Then
                    MsgBox(16, _T("Error"), _T("Please enter the video link!"))
                Else
                    online_play($input_text)
                EndIf

        EndSwitch
    WEnd
EndFunc

; Lấy transcript qua tiện ích Python đã đóng gói. yt-dlp tải phụ đề do tác giả
; cung cấp hoặc phụ đề tự động, ưu tiên tiếng Việt rồi tiếng Anh.
Func _ShowYoutubeTranscript($sUrl, $hParent)
    If Not FileExists($YT_TRANSCRIPT_EXE) Then
        MsgBox(16, _T("Transcript unavailable"), _TF("Missing file youtube_transcript.exe.\n\nPlease download or reinstall the application to restore it."), 0, $hParent)
        Return
    EndIf

    ; One dialog with two choices (with timestamps / text only) and Close. The transcript is downloaded
    ; once (the first time a choice is made); the dialog comes back after the text window is closed,
    ; so the other style can be opened without downloading again.
    Local $sRaw = ""
    While 1
        Local $iMode = _Transcript_ChooseMode($hParent)
        If $iMode = 0 Then Return
        If $sRaw = "" Then
            $sRaw = _Transcript_Fetch($sUrl, $hParent)
            If $sRaw = "" Then Return
        EndIf
        If $iMode = 2 Then
            _Transcript_ShowWindow(_Transcript_StripTimes($sRaw), $hParent)
        Else
            _Transcript_ShowWindow($sRaw, $hParent)
        EndIf
    WEnd
EndFunc

; Returns 1 = with timestamps, 2 = text only, 0 = close
Func _Transcript_ChooseMode($hParent)
    Local $hChoose
    If $hParent <> 0 And IsHWnd($hParent) Then
        $hChoose = GUICreate(_T("Video Transcript"), 340, 210, -1, -1, -1, -1, $hParent)
    Else
        $hChoose = GUICreate(_T("Video Transcript"), 340, 210)
    EndIf
    GUISetBkColor($COLOR_BLUE, $hChoose)
    GUICtrlCreateLabel(_T("Choose how to show the transcript:"), 10, 15, 320, 20, $SS_CENTER)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $btnTimes = GUICtrlCreateButton(_T("With timestamps"), 40, 50, 260, 35)
    Local $btnText = GUICtrlCreateButton(_T("Text only"), 40, 95, 260, 35)
    Local $btnCloseC = GUICtrlCreateButton(_T("Close"), 40, 140, 260, 35)
    Local $hDummyEscC = GUICtrlCreateDummy()
    Local $aAccelC[1][2] = [["{ESC}", $hDummyEscC]]
    GUISetAccelerators($aAccelC, $hChoose)
    GUISetState(@SW_SHOW, $hChoose)
    _AllowUIPI($hChoose)
    GUICtrlSetState($btnTimes, $GUI_FOCUS)

    Local $iResult = 0
    While 1
        Local $nC = _GuiMsg($hChoose)
        Switch $nC
            Case $GUI_EVENT_CLOSE, $btnCloseC, $hDummyEscC
                $iResult = 0
                ExitLoop
            Case $btnTimes
                $iResult = 1
                ExitLoop
            Case $btnText
                $iResult = 2
                ExitLoop
        EndSwitch
    WEnd
    GUIDelete($hChoose)
    If $hParent <> 0 And IsHWnd($hParent) Then WinActivate($hParent)
    Return $iResult
EndFunc

; Removes the [hh:mm:ss] marks at the start of every line (the program youtube_transcript.exe
; always writes them; the text-only view is made here).
Func _Transcript_StripTimes($sText)
    Return StringRegExpReplace($sText, "(?m)^[ \t]*\[\d{1,2}:\d{2}(?::\d{2})?(?:[.,]\d+)?\][ \t]*", "")
EndFunc

; Downloads the transcript with timestamps. Returns the text, or "" when cancelled / not available.
Func _Transcript_Fetch($sUrl, $hParent)
    Local $sOutput = @TempDir & "\VDHTranscript_" & @AutoItPID & "_" & TimerInit() & ".txt"
    Local $sSafeUrl = StringReplace($sUrl, '"', "")
    Local $sCmd = '"' & $YT_TRANSCRIPT_EXE & '" --url "' & $sSafeUrl & '" --output "' & $sOutput & '"'

    Local $sOut = "", $sError = ""
    Local $bDone = _RunTaskWithProgressDialog($sCmd, _T("Video Transcript"), _T("Downloading captions and creating transcript..."), $sOut, $sError, $hParent)
    If Not $bDone Then
        ProcessClose("youtube_transcript.exe")
        Return ""
    EndIf

    If Not FileExists($sOutput) Then
        If $sError = "" Then $sError = _T("The video may not have captions or auto-generated captions.")
        MsgBox(16, _T("Transcript unavailable"), $sError, 0, $hParent)
        Return ""
    EndIf

    Local $hFile = FileOpen($sOutput, $FO_READ + $FO_UTF8)
    Local $sTranscript = FileRead($hFile)
    FileClose($hFile)
    FileDelete($sOutput)
    If $sTranscript = "" Then
        MsgBox(16, _T("Transcript unavailable"), _T("No readable caption text was returned."), 0, $hParent)
        Return ""
    EndIf
    Return $sTranscript
EndFunc

Func _Transcript_ShowWindow($sTranscript, $hParent)
    Local $hTranscript = GUICreate(_T("Video transcript"), 700, 560, -1, -1, -1, -1, $hParent)
    GUISetBkColor(0xFFFFFF, $hTranscript)
    GUICtrlCreateLabel(_T("Transcript:"), 12, 12, 675, 20)
    Local $edtTranscript = GUICtrlCreateEdit($sTranscript, 12, 38, 675, 450, BitOR($ES_MULTILINE, $ES_AUTOVSCROLL, $ES_READONLY, $WS_VSCROLL, $WS_TABSTOP))
    GUICtrlSetFont($edtTranscript, 11)
    GUICtrlSetState($edtTranscript, $GUI_SHOW)
    _GUICtrlEdit_SetLimitText($edtTranscript, 0) ; no 32,000 character limit: long transcripts must not be cut
    Local $btnCopy = GUICtrlCreateButton(_T("Copy transcript"), 180, 505, 160, 32)
    Local $btnClose = GUICtrlCreateButton(_T("Close"), 360, 505, 160, 32)
    GUISetState(@SW_SHOW, $hTranscript)
    While 1
        Local $iMsg = _GuiMsg($hTranscript)
        Switch $iMsg
            Case $GUI_EVENT_CLOSE, $btnClose
                GUIDelete($hTranscript)
                ExitLoop
            Case $btnCopy
                ClipPut($sTranscript)
                MsgBox(64, _T("Transcript"), _T("Transcript copied to clipboard."), 0, $hTranscript)
        EndSwitch
    WEnd
EndFunc

; ===========================================================================
; VIEW LYRICS
; Finds the lyrics of the selected / playing video with lib\lyrics.exe (built from
; lyrics.py) and shows them in a read-only window with "Copy lyrics" and "Close" buttons.
; ===========================================================================

; Turns a YouTube title into a clean search phrase (removes "(Official MV)", [HD], #tags ...)
Func _Lyrics_CleanTitle($sTitle)
    Local $s = $sTitle
    $s = StringRegExpReplace($s, "(?i)\.(mp3|m4a|wav|flac|ogg|opus|aac|wma|mp4|webm|mka)$", "") ; file extension (local files)
    $s = StringReplace($s, "_", " ")
    $s = StringRegExpReplace($s, "^\s*\d{1,3}\s*[.\-)]\s+", "")                              ; track number: "01 - ", "02. "
    ; Pipes: "Artist - Song | Official MV" -> keep "Artist - Song";
    ;        "Artist | Song | Official MV" -> keep "Artist Song" (the 2nd part is the song name)
    $s = StringReplace($s, ChrW(0xFF5C), "|")
    If StringInStr($s, "|") Then
        Local $aPipeParts = StringSplit($s, "|", 2)
        If StringInStr($aPipeParts[0], " - ") Or UBound($aPipeParts) < 2 Then
            $s = $aPipeParts[0]
        Else
            $s = $aPipeParts[0] & " " & $aPipeParts[1]
        EndIf
    EndIf
    $s = StringRegExpReplace($s, "\([^)]*\)|\[[^\]]*\]|\{[^}]*\}|\x{3010}[^\x{3011}]*\x{3011}", " ") ; (..) [..] {..}
    $s = StringRegExpReplace($s, "#\S+", " ")                                            ; hashtags
    $s = StringRegExpReplace($s, "(?i)l\x{1EDD}i\s+b\x{E0}i\s+h\x{E1}t", " ")            ; Vietnamese "loi bai hat"
    $s = StringRegExpReplace($s, "(?i)\b(official|music video|lyric video|lyrics|lyric|audio|video|mv|karaoke|visualizer|hd|4k|1080p)\b", " ")
    $s = StringRegExpReplace($s, "[\x{2013}\x{2014}]", "-")                              ; en/em dash -> hyphen
    $s = StringRegExpReplace($s, "\s+", " ")
    $s = StringRegExpReplace($s, "^[\s\-:,.]+|[\s\-:,.]+$", "")
    Return $s
EndFunc

; Main entry point: runs lib\lyrics.exe (built from lyrics.py) to find the lyrics of the song,
; then shows them in a read-only window with "Copy lyrics" and "Close" buttons.
Func _ShowSongLyrics($sTitle, $hParent = 0, $sID = "")
    If Not FileExists($LYRICS_EXE_PATH) Then
        MsgBox(16, _T("View lyrics"), _TF("Missing file lyrics.exe.\n\nPlease download or reinstall the application to restore it."), 0, $hParent)
        Return
    EndIf

    Local $sQuery = _Lyrics_CleanTitle($sTitle)
    Local $sSafeID = StringRegExpReplace($sID, "[^A-Za-z0-9_\-]", "")
    If $sQuery = "" And $sSafeID = "" Then
        MsgBox(48, _T("View lyrics"), _T("Could not work out a song name from this title."), 0, $hParent)
        Return
    EndIf
    Local $sSafeQuery = StringRegExpReplace($sQuery, '["\\]', "") ; quotes / backslashes would break the command line

    Local $sOutput = @TempDir & "\VDHLyrics_" & @AutoItPID & "_" & Int(TimerInit()) & "_" & Random(1000, 9999, 1) & ".txt"
    FileDelete($sOutput)

    ; lyrics.py uses argparse: a value that starts with "-" (a YouTube id can!) is mistaken for an
    ; option when passed as a separate argument, so every value is passed as --name=value.
    Local $sCmd = '"' & $LYRICS_EXE_PATH & '"'
    If $sSafeID <> "" Then $sCmd &= ' --id=' & $sSafeID
    If $sSafeQuery <> "" Then $sCmd &= ' --query="' & $sSafeQuery & '"'
    $sCmd &= ' --output="' & $sOutput & '"'

    Local $sOut = "", $sError = ""
    Local $bDone = _RunTaskWithProgressDialog($sCmd, _T("View Lyrics"), _T("Searching for lyrics..."), $sOut, $sError, $hParent)
    If Not $bDone Then
        ProcessClose("lyrics.exe")
        FileDelete($sOutput)
        Return ; cancelled by the user
    EndIf

    Local $sRaw = ""
    If FileExists($sOutput) Then
        ; lyrics.py writes UTF-8 without BOM: flag 256 is required, otherwise AutoIt reads the file
        ; as ANSI and every Vietnamese / non-ASCII character comes out garbled.
        Local $hFile = FileOpen($sOutput, $FO_READ + 256)
        If $hFile <> -1 Then
            $sRaw = FileRead($hFile)
            FileClose($hFile)
        EndIf
        FileDelete($sOutput)
    EndIf

    ; first line may be "#HEADING: Track - Artist", the rest is the lyrics text
    Local $sHeading = _T("Lyrics")
    Local $sLyrics = $sRaw
    If StringLeft($sRaw, 9) = "#HEADING:" Then
        Local $iEol = StringInStr($sRaw, @LF)
        If $iEol > 0 Then
            $sHeading = _TF("Lyrics: {1}", StringStripWS(StringMid($sRaw, 10, $iEol - 10), 3))
            $sLyrics = StringTrimLeft($sRaw, $iEol)
        EndIf
    EndIf
    $sLyrics = StringReplace($sLyrics, @CRLF, @LF)
    $sLyrics = StringReplace($sLyrics, @LF, @CRLF) ; the Edit control needs CRLF line breaks

    If StringStripWS($sLyrics, 8) = "" Then
        If $sRaw = "" And $sError <> "" And Not StringInStr($sError, "NOT_FOUND") Then
            MsgBox(16, _T("View lyrics"), _TF("Could not get the lyrics.\n\nDetails: {1}", StringStripWS($sError, 7)), 0, $hParent)
        Else
            Local $sShown = $sQuery
            If $sShown = "" Then $sShown = $sTitle
            If MsgBox(4 + 32, _T("View lyrics"), _TF("No lyrics were found for:\n{1}\n\nDo you want to search for them on the web in your browser?", $sShown), 0, $hParent) = 6 Then
                ShellExecute("https://www.google.com/search?q=" & _URLEncode($sShown & " lyrics"))
            EndIf
        EndIf
        Return
    EndIf

    ; --- lyrics window ---
    Local $hLyrics = GUICreate(_T("View lyrics"), 700, 560, -1, -1, -1, -1, $hParent)
    GUISetBkColor(0xFFFFFF, $hLyrics)
    GUICtrlCreateLabel($sHeading, 12, 12, 675, 20)
    Local $edtLyrics = GUICtrlCreateEdit("", 12, 38, 675, 450, BitOR($ES_MULTILINE, $ES_AUTOVSCROLL, $ES_READONLY, $WS_VSCROLL, $WS_TABSTOP))
    GUICtrlSetFont($edtLyrics, 11)
    _GUICtrlEdit_SetLimitText($edtLyrics, 0) ; lift the default ~32K limit BEFORE filling the text
    GUICtrlSetData($edtLyrics, $sLyrics)
    Local $btnCopy = GUICtrlCreateButton(_T("Copy lyrics"), 180, 505, 160, 32)
    Local $btnClose = GUICtrlCreateButton(_T("Close"), 360, 505, 160, 32)
    Local $hDummyEscLyr = GUICtrlCreateDummy()
    Local $aAccelLyr[1][2] = [["{ESC}", $hDummyEscLyr]]
    GUISetAccelerators($aAccelLyr, $hLyrics)
    GUISetState(@SW_SHOW, $hLyrics)
    _AllowUIPI($hLyrics)
    GUICtrlSetState($edtLyrics, $GUI_FOCUS)
    _GUICtrlEdit_SetSel($edtLyrics, 0, 0) ; cursor at the start, nothing pre-selected

    While 1
        Local $iMsg = _GuiMsg($hLyrics)
        Switch $iMsg
            Case $GUI_EVENT_CLOSE, $btnClose, $hDummyEscLyr
                GUIDelete($hLyrics)
                ExitLoop
            Case $btnCopy
                ClipPut($sLyrics)
                MsgBox(64, _T("View lyrics"), _T("Lyrics copied to clipboard."), 0, $hLyrics)
        EndSwitch
    WEnd
EndFunc

Func _SearchEditProc($hWnd, $iMsg, $wParam, $lParam)
    Local $aRet = DllCall("user32.dll", "lresult", "CallWindowProcW", "ptr", $g_pOldSearchEditProc, "hwnd", $hWnd, "uint", $iMsg, "wparam", $wParam, "lparam", $lParam)

    If $iMsg = 0x0100 Then ; WM_KEYDOWN
        If BitAND($lParam, 0x40000000) = 0 Then
            ; Chỉ phát nếu phím khác phím cũ HOẶC quá 50ms kể từ lần phát cuối
            If $wParam <> $g_iLastVkCode Or TimerDiff($g_iLastHookTime) > 50 Then
                $g_iLastVkCode = $wParam
                $g_iLastHookTime = TimerInit()

                If $wParam < 0x25 Or $wParam > 0x28 Then
                    _PlayTypingSound($wParam)
                EndIf
            EndIf
        EndIf
    EndIf

    Return $aRet[0]
EndFunc

Func _ShowSearch()
    $hCurrentSubGui = GUICreate(_T("Search"), 400, 200)
    GUISetBkColor($COLOR_BLUE)

    GUICtrlCreateLabel(_T("Enter keyword to search:"), 10, 15, 80, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    $inp_search = GUICtrlCreateInput("", 100, 12, 210, 20)

    ; Subclass search input for typing sounds
    Local $hEdit = GUICtrlGetHandle($inp_search)
    $g_hSearchEditCallback = DllCallbackRegister("_SearchEditProc", "lresult", "hwnd;uint;wparam;lparam")
    Local $aRet = DllCall("user32.dll", "ptr", "SetWindowLong" & (@AutoItX64 ? "Ptr" : "") & "W", "hwnd", $hEdit, "int", -4, "ptr", DllCallbackGetPtr($g_hSearchEditCallback)) ; -4 = GWL_WNDPROC
    $g_pOldSearchEditProc = $aRet[0]

    GUICtrlCreateLabel(_T("Filter:"), 10, 50, 80, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $cbo_filter = GUICtrlCreateCombo("", 100, 47, 210, 20, $CBS_DROPDOWNLIST)
    GUICtrlSetTip(-1, _T("Select the search filter. Use the arrow keys to browse the list in alphabetical order"))
    GUICtrlSetData(-1, _TL("4K|Channels|lives|Most viewed|No Filter|Playlist|Rating|Shorts|This Month|This Week|upload date|Video"), _T($g_sSearchFilter))

    GUICtrlCreateLabel(_T("Source:"), 10, 85, 80, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $cbo_source = GUICtrlCreateCombo("", 100, 82, 210, 20, $CBS_DROPDOWNLIST)
    GUICtrlSetTip(-1, _T("Choose where to search: YouTube or SoundCloud. The filter above is used for YouTube only."))
    GUICtrlSetData(-1, "YouTube|SoundCloud", $g_sSearchSource)

    $btn_search_go = GUICtrlCreateButton(_T("Search (Alt+S)"), 320, 10, 70, 25)
    GUICtrlSetState(-1, $GUI_DEFBUTTON)

    Local $btn_voice_search = GUICtrlCreateButton(_T("Voice search (Alt+V)"), 320, 47, 70, 25)

    $btn_search_hist = GUICtrlCreateButton(_T("Search History (Alt+H)"), 100, 125, 210, 30)

    Local $aAccelSC[3][2] = [["!s", $btn_search_go], ["!h", $btn_search_hist], ["!v", $btn_voice_search]]
    GUISetAccelerators($aAccelSC, $hCurrentSubGui)

    GUISetState(@SW_SHOW, $hCurrentSubGui)
    ControlFocus($hCurrentSubGui, "", $inp_search)

    While 1
        Local $nMsg = _GuiMsg($hCurrentSubGui)

        Switch $nMsg
            Case $GUI_EVENT_CLOSE
                If $g_pOldSearchEditProc <> 0 Then
                    DllCall("user32.dll", "ptr", "SetWindowLong" & (@AutoItX64 ? "Ptr" : "") & "W", "hwnd", GUICtrlGetHandle($inp_search), "int", -4, "ptr", $g_pOldSearchEditProc)
                    $g_pOldSearchEditProc = 0
                EndIf
                If $g_hSearchEditCallback <> 0 Then
                    DllCallbackFree($g_hSearchEditCallback)
                    $g_hSearchEditCallback = 0
                EndIf
                GUIDelete($hCurrentSubGui)
                $hCurrentSubGui = 0
                GUISetState(@SW_SHOW, $mainform)
                Return

            Case $btn_voice_search
                If FileExists($VOICE_SEARCH_EXE_PATH) Then
                    ; Phát âm thanh và hệ thống voice search được gọi chạy cùng lúc
                    _AppSoundPlay(@ScriptDir & "\sounds\start_voice_search.wav")
                    Local $pid = Run('"' & $VOICE_SEARCH_EXE_PATH & '"', @ScriptDir & "\lib", @SW_HIDE, $STDOUT_CHILD + $STDERR_CHILD)
                    If @error Then
                        MsgBox(16, _T("Error"), _TF("Failed to start voice_search.exe. Error code: {1}", @error))
                        ContinueLoop
                    EndIf
                    ; ControlFocus($hCurrentSubGui, "", $inp_search)
                    GUICtrlSetState($btn_voice_search, $GUI_DISABLE)
                    Local $bBinaryOutput = Binary("")
                    While ProcessExists($pid)
                        $bBinaryOutput &= StdoutRead($pid, False, True)
                        $bBinaryOutput &= StderrRead($pid, False, True)
                        GUIGetMsg()
                        Sleep(10)
                    WEnd
                    $bBinaryOutput &= StdoutRead($pid, False, True)
                    $bBinaryOutput &= StderrRead($pid, False, True)

                    ; Âm thanh kết thúc tìm kiếm
                    _AppSoundPlay(@ScriptDir & "\sounds\stop_voice_search.wav")

                    Local $sFullOutput = BinaryToString($bBinaryOutput, 4)

                    ; Common encoding fixes if StdoutRead still catches broken UTF-8 as ANSI
                    If StringInStr($sFullOutput, "vÃ´ hiá»‡u hÃ³a") Then
                        $sFullOutput = StringReplace($sFullOutput, "vÃ´ hiá»‡u hÃ³a", "vô hiệu hóa")
                    EndIf

                    Local $sResult = ""
                    Local $sError = ""
                    Local $aLines = StringSplit(StringReplace($sFullOutput, @CR, ""), @LF)
                    For $i = 1 To $aLines[0]
                        Local $sLine = StringStripWS($aLines[$i], 3)
                        If $sLine == "" Then ContinueLoop
                        If StringInStr($sLine, "ERROR:") Then
                            $sError = StringStripWS(StringReplace($sLine, "ERROR:", ""), 3)
                        ElseIf Not StringInStr($sLine, "INFO:") And Not StringInStr($sLine, "LISTENING") And Not StringInStr($sLine, "RECOGNIZING") Then
                            $sResult = $sLine
                        EndIf
                    Next

                    If $sError <> "" Then
                        If StringInStr($sError, "Could not understand audio") Then
                            _AppSoundPlay(@ScriptDir & "\sounds\error.wav")
                        ElseIf StringInStr($sError, "check your microphone") Then
                            _AppSoundPlay(@ScriptDir & "\sounds\error.wav")
                        ElseIf StringInStr($sError, "listening timed out") Then
                            _AppSoundPlay(@ScriptDir & "\sounds\error.wav")
                        ElseIf StringInStr($sError, "internet") Or StringInStr($sError, "network") Or StringInStr($sError, "connection") Then
                            _AppSoundPlay(@ScriptDir & "\sounds\no_internet.wav")
                        EndIf
                    ElseIf $sResult <> "" Then
                        GUICtrlSetData($inp_search, $sResult)
                        ; ControlFocus($hCurrentSubGui, "", $inp_search)

                        If $g_bVoiceAutoSearch Then
                            $sCurrentKeyword = $sResult
                            $g_sSearchFilter = _TR(GUICtrlRead($cbo_filter))
                            $g_sSearchSource = GUICtrlRead($cbo_source)
                            IniWrite($CONFIG_FILE, "Settings", "SearchSource", $g_sSearchSource)
                            IniWrite($CONFIG_FILE, "Settings", "SearchFilter", $g_sSearchFilter)
                            _AddSearchHistory($sCurrentKeyword)
                            Local $sRes = _ShowSearchResultsWindow($sCurrentKeyword, $g_sSearchFilter)
                            If $sRes = "RETURN_MAIN" Then
                                GUIDelete($hCurrentSubGui)
                                $hCurrentSubGui = 0
                                GUISetState(@SW_SHOW, $mainform)
                                Return
                            EndIf
                        EndIf
                    Else
                        _AppSoundPlay(@ScriptDir & "\sounds\error.wav")
                    EndIf
                    GUICtrlSetState($btn_voice_search, $GUI_ENABLE)
                Else
                    MsgBox(16, _T("Error"), _T("voice_search.exe not found in lib folder!"))
                EndIf

            Case $btn_search_go
                $sCurrentKeyword = GUICtrlRead($inp_search)
                $g_sSearchFilter = _TR(GUICtrlRead($cbo_filter))
                $g_sSearchSource = GUICtrlRead($cbo_source)
                IniWrite($CONFIG_FILE, "Settings", "SearchSource", $g_sSearchSource)
                IniWrite($CONFIG_FILE, "Settings", "SearchFilter", $g_sSearchFilter)
                If $sCurrentKeyword = "" Then
                    MsgBox(16, _T("Error"), _T("Please enter a keyword to search!"))
                Else
                    _AddSearchHistory($sCurrentKeyword)
                    Local $sRes = _ShowSearchResultsWindow($sCurrentKeyword, $g_sSearchFilter)
                    If $sRes = "RETURN_MAIN" Then
                        GUIDelete($hCurrentSubGui)
                        $hCurrentSubGui = 0
                        GUISetState(@SW_SHOW, $mainform)
                        Return
                    EndIf
                EndIf

            Case $btn_search_hist
                Local $sRes = _ShowSearchHistoryWindow()
                If $sRes = "RETURN_MAIN" Then
                    GUIDelete($hCurrentSubGui)
                    $hCurrentSubGui = 0
                    GUISetState(@SW_SHOW, $mainform)
                    Return
                EndIf
        EndSwitch
    WEnd
EndFunc

Func _AddSearchHistory($sKeyword)
    If $sKeyword = "" Then Return
    If Not $g_bSaveSearchHistory Then Return ; Người dùng đã tắt lưu lịch sử tìm kiếm

    Local $sContent = ""
    If FileExists($SEARCH_HISTORY_FILE) Then
        Local $hFileRead = FileOpen($SEARCH_HISTORY_FILE, 0 + 256)
        $sContent = FileRead($hFileRead)
        FileClose($hFileRead)
    EndIf

    Local $aLines = StringSplit(StringStripCR($sContent), @LF)
    Local $sNewContent = ""

    For $i = 1 To $aLines[0]
        If $aLines[$i] <> "" And $aLines[$i] <> $sKeyword Then
            $sNewContent &= $aLines[$i] & @CRLF
        EndIf
    Next

    $sNewContent &= $sKeyword & @CRLF

    Local $hFileWrite = FileOpen($SEARCH_HISTORY_FILE, 2 + 256)
    If $hFileWrite <> -1 Then
        FileWrite($hFileWrite, $sNewContent)
        FileClose($hFileWrite)
    EndIf
EndFunc

Func _ShowSearchHistoryWindow()
    $hSearchHistoryGui = GUICreate(_T("Search History"), 350, 466)
    GUISetBkColor($COLOR_BLUE)

    GUICtrlCreateLabel(_T("Your search history:"), 10, 10, 330, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    GUICtrlSetFont(-1, 10, 800)
    Local $lst_hist = GUICtrlCreateList("", 10, 35, 330, 325, BitOR($LBS_NOTIFY, $WS_VSCROLL, $WS_BORDER))

    Local $btn_remove = GUICtrlCreateButton(_T("Delete From History"), 10, 370, 160, 30)
    Local $btn_clear = GUICtrlCreateButton(_T("Clear All History"), 180, 370, 160, 30)
    Local $btn_back = GUICtrlCreateButton(_T("Go Back"), 10, 410, 330, 30)

    GUISetState(@SW_SHOW, $hSearchHistoryGui)
    GUISetState(@SW_HIDE, $hCurrentSubGui) ; an cua so cha sau khi cua so moi da hien

    _LoadSearchHistoryList($lst_hist)
    _GUICtrlListBox_SetCurSel($lst_hist, 0)
    ControlFocus($hSearchHistoryGui, "", $lst_hist)

    Local $hDummyEnterSearchHist = GUICtrlCreateDummy()
    Local $aAccelSearchHist[1][2] = [["{ENTER}", $hDummyEnterSearchHist]]
    GUISetAccelerators($aAccelSearchHist, $hSearchHistoryGui)
    Local $bEnterAccSH = True

    While 1
        _SyncEnterAccel($hSearchHistoryGui, $aAccelSearchHist, $lst_hist, $bEnterAccSH)
        Local $nMsg = _GuiMsg($hSearchHistoryGui)
        If $nMsg = $hDummyEnterSearchHist Then
            Local $aBtnSH[3] = [$btn_remove, $btn_clear, $btn_back]
            Local $iBtnSH = _EnterFocusedButton($hSearchHistoryGui, $aBtnSH)
            If $iBtnSH <> 0 Then $nMsg = $iBtnSH
        EndIf

        Switch $nMsg
            Case $GUI_EVENT_CLOSE, $btn_back
                GUIDelete($hSearchHistoryGui)
                GUISetState(@SW_SHOW, $hCurrentSubGui)
    ControlFocus($hCurrentSubGui, "", $inp_search)
                Return

            Case $hDummyEnterSearchHist
                If ControlGetHandle($hSearchHistoryGui, "", ControlGetFocus($hSearchHistoryGui)) = GUICtrlGetHandle($lst_hist) Then
                    Local $sSelected = _GUICtrlListBox_GetText($lst_hist, _GUICtrlListBox_GetCurSel($lst_hist))
                    If $sSelected <> "" Then
                        GUIDelete($hSearchHistoryGui)
                        $hSearchHistoryGui = 0
                        $sCurrentKeyword = $sSelected
                        GUICtrlSetData($inp_search, $sCurrentKeyword)
                        Local $sRes = _ShowSearchResultsWindow($sCurrentKeyword, "No Filter")
                        If $sRes = "RETURN_MAIN" Then Return "RETURN_MAIN"
                        GUISetState(@SW_SHOW, $hCurrentSubGui)
    ControlFocus($hCurrentSubGui, "", $inp_search)
                        Return
                    EndIf
                EndIf

            Case $btn_remove
                Local $iIndex = _GUICtrlListBox_GetCurSel($lst_hist)
                If $iIndex <> -1 Then
                    Local $sTxt = _GUICtrlListBox_GetText($lst_hist, $iIndex)
                    _RemoveSearchHistoryItem($sTxt)
                    _GUICtrlListBox_DeleteString($lst_hist, $iIndex)
                EndIf

            Case $btn_clear
                If MsgBox(36, _T("Confirm"), _T("Are you sure you want to delete all search history?")) = 6 Then
                    FileDelete($SEARCH_HISTORY_FILE)
                    GUICtrlSetData($lst_hist, "")
                EndIf
        EndSwitch
    WEnd
EndFunc

Func _LoadSearchHistoryList($hListCtrl)
    GUICtrlSetData($hListCtrl, "")
    If Not FileExists($SEARCH_HISTORY_FILE) Then Return

    Local $hFile = FileOpen($SEARCH_HISTORY_FILE, 0 + 256)
    Local $sContent = FileRead($hFile)
    FileClose($hFile)
    Local $aLines = StringSplit(StringStripCR($sContent), @LF)

    For $i = $aLines[0] To 1 Step -1
        If $aLines[$i] <> "" Then
            _GUICtrlListBox_AddString($hListCtrl, $aLines[$i])
        EndIf
    Next
EndFunc

Func _RemoveSearchHistoryItem($sKeyword)
    Local $hFileRead = FileOpen($SEARCH_HISTORY_FILE, 0 + 256)
    Local $sContent = FileRead($hFileRead)
    FileClose($hFileRead)
    Local $aLines = StringSplit(StringStripCR($sContent), @LF)
    Local $sNewContent = ""

    For $i = 1 To $aLines[0]
        If $aLines[$i] <> "" And $aLines[$i] <> $sKeyword Then
            $sNewContent &= $aLines[$i] & @CRLF
        EndIf
    Next

    Local $hFileWrite = FileOpen($SEARCH_HISTORY_FILE, 2 + 256)
    If $hFileWrite <> -1 Then
        FileWrite($hFileWrite, $sNewContent)
        FileClose($hFileWrite)
    EndIf
EndFunc

Func _SearchResults_WM_COMMAND($hWnd, $iMsg, $wParam, $lParam)
    Local $iID = BitAND($wParam, 0x0000FFFF)
    Local $iCode = BitShift($wParam, 16)
    If $iID = $lst_results And $iCode = 1 Then ; 1 is LBN_SELCHANGE
        If $hDummyLoadMore <> 0 Then GUICtrlSendToDummy($hDummyLoadMore)
    EndIf
    Return $GUI_RUNDEFMSG
EndFunc

Func _ShowSearchResultsWindow($sKeyword, $sFilter = "No Filter")
    $hResultsGui = GUICreate(_T("Search Results"), 400, 472)
    GUISetBkColor($COLOR_BLUE)
    GUICtrlCreateLabel(_T("Search results:"), 10, 10, 380, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    GUICtrlSetFont(-1, 10, 800)
    $lst_results = GUICtrlCreateList("", 10, 35, 380, 355, BitOR($LBS_NOTIFY, $WS_VSCROLL, $WS_BORDER))
    Local $btn_return_main = GUICtrlCreateButton(_T("return to main window"), 10, 400, 380, 30)

    Local $hDummyAudio = GUICtrlCreateDummy()
    Local $hDummyEnterResults = GUICtrlCreateDummy()
    Local $hDummyHomeResults = GUICtrlCreateDummy()
    Local $hDummyEndResults = GUICtrlCreateDummy()
    Local $hDummyEscResults = GUICtrlCreateDummy()
    Local $hDummyAppsResults = GUICtrlCreateDummy() ; DUMMY MỚI CHO MENU CHUỘT PHẢI
    Local $aAccel[7][2] = [ _
        ["^{ENTER}", $hDummyAudio], _
        ["{ENTER}", $hDummyEnterResults], _
        ["{HOME}", $hDummyHomeResults], _
        ["{END}", $hDummyEndResults], _
        ["{ESC}", $hDummyEscResults], _
        ["{APPSKEY}", $hDummyAppsResults], _ ; Phím Applications/Context Menu ĐÃ FIX LỖI TÊN PHÍM
        ["+{F10}", $hDummyAppsResults] _  ; Phím Shift+F10
    ]
    GUISetAccelerators($aAccel, $hResultsGui)

    $hDummyLoadMore = GUICtrlCreateDummy()
    GUISetState(@SW_SHOW, $hResultsGui)
    GUISetState(@SW_HIDE, $hCurrentSubGui) ; an cua so cha sau khi cua so moi da hien
    GUIRegisterMsg($WM_COMMAND, "_SearchResults_WM_COMMAND")

    _SearchYouTube($sKeyword, False)

    While 1
        Local $nMsg = _GuiMsg($hResultsGui)

        Switch $nMsg
            Case $hDummyLoadMore
                _CheckAutoLoadMore()
            Case $GUI_EVENT_CLOSE
                GUIRegisterMsg($WM_COMMAND, "")
                GUIDelete($hResultsGui)
                $hDummyLoadMore = 0
                $hResultsGui = 0
                GUISetState(@SW_SHOW, $hCurrentSubGui)
    ControlFocus($hCurrentSubGui, "", $inp_search)
                Return
            Case $btn_return_main
                GUIDelete($hResultsGui)
                $hResultsGui = 0
                Return "RETURN_MAIN"
            Case $hDummyAppsResults
                If ControlGetHandle($hResultsGui, "", ControlGetFocus($hResultsGui)) = GUICtrlGetHandle($lst_results) Then
                    _ShowContextMenu(0)
                EndIf
            Case $hDummyEnterResults
                If ControlGetHandle($hResultsGui, "", ControlGetFocus($hResultsGui)) = GUICtrlGetHandle($lst_results) Then
                    Local $iSel = _GUICtrlListBox_GetCurSel($lst_results)
                    If $iSel <> -1 Then
                        If $aSearchTypes[$iSel + 1] = "playlist" Then
                            _ShowPlaylistVideos($aSearchIds[$iSel + 1], $aSearchTitles[$iSel + 1])
                        ElseIf $aSearchTypes[$iSel + 1] = "channel" Then
                            _ShowChannelVideos($aSearchIds[$iSel + 1], $aSearchTitles[$iSel + 1])
                        Else
                            _PlayLoop($iSel, False) ; Video
                        EndIf
                    EndIf
                ElseIf ControlGetHandle($hResultsGui, "", ControlGetFocus($hResultsGui)) = GUICtrlGetHandle($btn_return_main) Then
                    GUIDelete($hResultsGui)
                    $hResultsGui = 0
                    Return "RETURN_MAIN"
                EndIf
            Case $hDummyHomeResults
                _GUICtrlListBox_SetCurSel($lst_results, 0)
            Case $hDummyEndResults
                _GUICtrlListBox_SetCurSel($lst_results, _GUICtrlListBox_GetCount($lst_results) - 1)
                _CheckAutoLoadMore()
            Case $hDummyEscResults
                GUIDelete($hResultsGui)
                $hResultsGui = 0
                GUISetState(@SW_SHOW, $hCurrentSubGui)
    ControlFocus($hCurrentSubGui, "", $inp_search)
                Return
            Case $lst_results
                _CheckAutoLoadMore()
            Case $hDummyAudio
                If ControlGetHandle($hResultsGui, "", ControlGetFocus($hResultsGui)) = GUICtrlGetHandle($lst_results) Then
                    _PlayLoop(_GUICtrlListBox_GetCurSel($lst_results), True) ; Ctrl+Enter = Play Audio
                EndIf
        EndSwitch
    WEnd
EndFunc

Func _SearchYouTube($sKeyword, $bAppend)
    $bIsSearching = True

    Local $hWaitGui = 0
    If Not $bAppend Then
        Local $sLoadingText = $sKeyword
        If $g_sSearchFilter <> "No Filter" Then $sLoadingText &= " (" & _T($g_sSearchFilter) & ")"
        If $g_sSearchSource <> "YouTube" Then $sLoadingText = $sKeyword & " (" & $g_sSearchSource & ")"
        $hWaitGui = GUICreate(_T("Searching"), 250, 80, -1, -1, BitOR($WS_POPUP, $WS_BORDER), BitOR($WS_EX_TOPMOST, $WS_EX_TOOLWINDOW), $hResultsGui)
        GUICtrlCreateLabel($sLoadingText & "...", 10, 25, 230, 20, $SS_CENTER)
        GUISetBkColor(0xFFFFFF, $hWaitGui)
        GUISetState(@SW_SHOW, $hWaitGui)
        GUISetCursor(15, 1)
        _AppPlaySoundW(@ScriptDir & "\sounds\loading.wav", 0x0009)
        Sleep(1)
    EndIf

    Local $iStart = _Ternary($bAppend, $iTotalLoaded + 1, 1)
    Local $iFetch = 20
    Local $iEnd = $iStart + $iFetch - 1

    Local $sUrlKeyword = _URLEncode($sKeyword)
    Local $sSearchTarget = ""
    Local $sBaseUrl = 'https://www.youtube.com/results?search_query=' & $sUrlKeyword

    Switch $g_sSearchFilter
        Case "Video"
            $sSearchTarget = $sBaseUrl & '&sp=EgIQAQ%3D%3D'
        Case "Channels"
            $sSearchTarget = $sBaseUrl & '&sp=EgIQAg%3D%3D'
        Case "Playlist"
            $sSearchTarget = $sBaseUrl & '&sp=EgIQAw%3D%3D'
        Case "lives"
            $sSearchTarget = $sBaseUrl & '&sp=EgJAAQ%3D%3D'
        Case "Shorts"
            Local $sShortsKeyword = $sKeyword
            If Not StringInStr(StringLower($sKeyword), "shorts") Then $sShortsKeyword &= " shorts"
            $sSearchTarget = 'https://www.youtube.com/results?search_query=' & _URLEncode($sShortsKeyword) & '&sp=EgIYAQ%3D%3D'
        Case "This Week"
            $sSearchTarget = $sBaseUrl & '&sp=EgQIAxAB'
        Case "This Month"
            $sSearchTarget = $sBaseUrl & '&sp=EgQIBBAB'
        Case "4K"
            $sSearchTarget = $sBaseUrl & '&sp=EgJwAQ%3D%3D'
        Case "upload date"
            $sSearchTarget = $sBaseUrl & '&sp=CAI%3D'
        Case "Most viewed"
            $sSearchTarget = $sBaseUrl & '&sp=CAM%3D'
        Case "Rating"
            $sSearchTarget = $sBaseUrl & '&sp=CAE%3D'
        Case Else ; No Filter
            $sSearchTarget = "ytsearch" & $iEnd & ":" & $sKeyword
    EndSwitch

    ; Version 3.3: other sources. SoundCloud = yt-dlp keyword search.
    If $g_sSearchSource = "SoundCloud" Then $sSearchTarget = "scsearch" & $iEnd & ":" & $sKeyword

    ; Use JSON output to ensure all video metadata stays together
    Local $sParams = '--flat-playlist --print-json --playlist-start ' & $iStart & ' --playlist-end ' & $iEnd & ' --no-warnings --encoding utf-8 -- "' & $sSearchTarget & '"'

    Local $sFullCmd = $YT_DLP_EXE & ' ' & $sParams
    Local $iPID = Run($sFullCmd, @ScriptDir, @SW_HIDE, $STDOUT_CHILD + $STDERR_CHILD)

    Local $bData = Binary("")
    Local $sErr = ""
    While ProcessExists($iPID)
        $bData &= StdoutRead($iPID, False, True)
        $sErr &= StderrRead($iPID)
        GUIGetMsg()
        Sleep(1)
    WEnd
    $bData &= StdoutRead($iPID, False, True)
    $sErr &= StderrRead($iPID)

    Local $sOutput = BinaryToString($bData, 4)

    If Not $bAppend Then
        GUICtrlSetData($lst_results, "")
        Global $aSearchIds[1]
        Global $aSearchTitles[1]
        Global $aSearchTypes[1] ; Reset Types as well
        $iTotalLoaded = 0
        $bEndReached = False
    EndIf

    Local $iLoadedBefore = $iTotalLoaded
    Local $aLines = StringSplit(StringStripCR($sOutput), @LF)

    If $aLines[0] > 0 Then
        Local $sDefaultType = _Ternary(($g_sSearchFilter == "Playlist"), "playlist", "video")
        If $g_sSearchFilter == "Channels" Then $sDefaultType = "channel"
        Local $sCurrentTitle = "", $sCurrentId = "", $sCurrentDur = "", $sCurrentUp = "", $sCurrentType = $sDefaultType
        Local $sCurrentViews = "", $sCurrentDate = "", $sCurrentLive = ""
        Local $sCurrentFollowers = ""

        ; Efficiently ReDim in chunks to avoid excessive ReDimming
        Local $iInitialCount = UBound($aSearchIds)
        ReDim $aSearchIds[$iInitialCount + $aLines[0]]
        ReDim $aSearchTitles[$iInitialCount + $aLines[0]]
        ReDim $aSearchTypes[$iInitialCount + $aLines[0]]
        Local $iCount = $iInitialCount

        _GUICtrlListBox_BeginUpdate($lst_results)
        For $i = 1 To $aLines[0]
            Local $sLine = StringStripWS($aLines[$i], 3)
            If $sLine = "" Then ContinueLoop

            ; Simple but effective JSON extraction for ID, Title and Duration
            Local $sIdMatch = StringRegExp($sLine, '"id":\s*"([^"]+)"', 3)
            Local $sTitleMatch = StringRegExp($sLine, '"title":\s*"([^"]+)"', 3)
            Local $sDurMatch = StringRegExp($sLine, '"duration_string":\s*"([^"]+)"', 3)
            Local $sUploaderMatch = StringRegExp($sLine, '"uploader":\s*"([^"]+)"', 3)
            Local $sViewMatch = StringRegExp($sLine, '"view_count":\s*(\d+)', 3)
            If Not IsArray($sViewMatch) Then $sViewMatch = StringRegExp($sLine, '"view_count_text":\s*"([^"]+)"', 3)
            Local $sDateMatch = StringRegExp($sLine, '"upload_date":\s*"([^"]+)"', 3)
            Local $sLiveMatch = StringInStr($sLine, '"is_live": true')
            Local $sTypeMatch = StringRegExp($sLine, '"_type":\s*"([^"]+)"', 3)
            Local $sFollowerMatch = StringRegExp($sLine, '"channel_follower_count":\s*(\d+)', 3)

            Local $bOtherSite = ($g_sSearchSource <> "YouTube")
            If IsArray($sIdMatch) And (IsArray($sTitleMatch) Or $bOtherSite) Then
                $sCurrentId = $sIdMatch[0]
                $sCurrentTitle = ""
                If IsArray($sTitleMatch) Then $sCurrentTitle = _UnescapeJSON($sTitleMatch[0])
                If $bOtherSite Then
                    ; items of other sites keep their full link as id
                    Local $aSiteUrl = StringRegExp($sLine, '"webpage_url":\s*"(https?:[^"]+)"', 3)
                    If Not IsArray($aSiteUrl) Then $aSiteUrl = StringRegExp($sLine, '"url":\s*"(https?:[^"]+)"', 3)
                    If IsArray($aSiteUrl) Then $sCurrentId = $aSiteUrl[0]
                    If Not _IsWebLink($sCurrentId) Then ContinueLoop
                EndIf

                $sCurrentDur = ""
                If IsArray($sDurMatch) Then $sCurrentDur = $sDurMatch[0]
                $sCurrentUp = ""
                If IsArray($sUploaderMatch) Then $sCurrentUp = _UnescapeJSON($sUploaderMatch[0])
                If $bOtherSite Then
                    If $sCurrentTitle = "" Then $sCurrentTitle = _Search_TitleFromUrl($sCurrentId, $sCurrentUp)
                    If $sCurrentDur = "" Then
                        Local $aDurSec = StringRegExp($sLine, '"duration":\s*([0-9.]+)', 3)
                        If IsArray($aDurSec) Then $sCurrentDur = _FormatTime(Int(Number($aDurSec[0])))
                    EndIf
                EndIf
                $sCurrentViews = ""
                If IsArray($sViewMatch) Then $sCurrentViews = $sViewMatch[0]
                $sCurrentDate = ""
                If IsArray($sDateMatch) Then $sCurrentDate = $sDateMatch[0]
                $sCurrentType = $sDefaultType
                If IsArray($sTypeMatch) Then $sCurrentType = $sTypeMatch[0]
                If $bOtherSite Then $sCurrentType = "video"

                If IsArray($sFollowerMatch) Then
                    $sCurrentFollowers = $sFollowerMatch[0]
                Else
                    $sCurrentFollowers = ""
                EndIf

                $sCurrentLive = ""
                If $sLiveMatch Then $sCurrentLive = "True"
                ; Tự động nhận diện Playlist/Channel dựa trên ID nếu các cách trên thất bại
                If Not $bOtherSite And $sCurrentType <> "playlist" And $sCurrentType <> "channel" Then
                    If StringLeft($sCurrentId, 2) = "UC" Or StringLeft($sCurrentId, 2) = "UU" Or StringInStr($sLine, "youtube:tab") Then
                         $sCurrentType = "channel"
                    ElseIf StringLen($sCurrentId) > 11 Or StringLeft($sCurrentId, 2) = "PL" Or StringLeft($sCurrentId, 2) = "RD" Or StringLeft($sCurrentId, 2) = "OL" Then
                        $sCurrentType = "playlist"
                    EndIf
                EndIf

                $iTotalLoaded += 1
                If $sCurrentTitle == "" Or $sCurrentTitle == "NA" Then ContinueLoop ; Skip unknown titles
                Local $sDisplay = $sCurrentTitle

                If $sCurrentType == "channel" Then
                    $sDisplay &= " [Channel]"
                    If $sCurrentFollowers <> "" Then $sDisplay &= " (" & $sCurrentFollowers & " followers)"
                Else
                    If $sCurrentLive == "True" Then $sDisplay = "[LIVE] " & $sDisplay

                    ; --- BẮT ĐẦU PHẦN ĐỊNH DẠNG THEO YÊU CẦU ---
                    If $sCurrentDur <> "" And $sCurrentDur <> "NA" Then
                        Local $aTime = StringSplit($sCurrentDur, ":")
                        Local $sSpokenDur = ""
                        If $aTime[0] == 3 Then
                            $sSpokenDur = Int($aTime[1]) & " hours, " & Int($aTime[2]) & " minutes and " & Int($aTime[3]) & " seconds"
                        ElseIf $aTime[0] == 2 Then
                            $sSpokenDur = Int($aTime[1]) & " minutes and " & Int($aTime[2]) & " seconds"
                        Else
                            $sSpokenDur = Int($sCurrentDur) & " seconds"
                        EndIf

                        $sSpokenDur = StringRegExpReplace($sSpokenDur, "\b1 hours\b", "1 hour")
                        $sSpokenDur = StringRegExpReplace($sSpokenDur, "\b1 minutes\b", "1 minute")
                        $sSpokenDur = StringRegExpReplace($sSpokenDur, "\b1 seconds\b", "1 second")

                        $sDisplay &= ", Duration: " & $sSpokenDur
                    EndIf

                    If $sCurrentUp <> "" And $sCurrentUp <> "NA" Then
                        $sDisplay &= ", By " & $sCurrentUp
                    EndIf

                    If $sCurrentViews <> "" And $sCurrentViews <> "NA" Then
                        Local $sSpokenViews = $sCurrentViews
                        If StringRegExp($sSpokenViews, "^\d+$") Then
                            While StringRegExp($sSpokenViews, '(\d+)(\d{3})')
                                $sSpokenViews = StringRegExpReplace($sSpokenViews, '(\d+)(\d{3})', '\1,\2')
                            WEnd
                            $sSpokenViews &= " views"
                        Else
                            $sSpokenViews = StringReplace($sSpokenViews, "K", " thousand")
                            $sSpokenViews = StringReplace($sSpokenViews, "M", " million")
                            $sSpokenViews = StringReplace($sSpokenViews, "B", " billion")
                            If Not StringInStr(StringLower($sSpokenViews), "view") Then
                                $sSpokenViews &= " views"
                            EndIf
                        EndIf
                        $sDisplay &= ", " & $sSpokenViews
                    EndIf

                    If $g_sSearchFilter == "upload date" And $sCurrentDate <> "" And $sCurrentDate <> "NA" Then
                        Local $sFormattedDate = $sCurrentDate
                        If StringLen($sCurrentDate) == 8 Then
                            $sFormattedDate = StringMid($sCurrentDate, 7, 2) & "/" & StringMid($sCurrentDate, 5, 2) & "/" & StringLeft($sCurrentDate, 4)
                        EndIf
                        $sDisplay &= ", uploaded on " & $sFormattedDate
                    EndIf
                    ; --- KẾT THÚC PHẦN ĐỊNH DẠNG THEO YÊU CẦU ---
                EndIf

                _GUICtrlListBox_AddString($lst_results, $sDisplay)

                $aSearchIds[$iCount] = $sCurrentId
                $aSearchTitles[$iCount] = $sCurrentTitle
                $aSearchTypes[$iCount] = $sCurrentType ; Lưu loại kết quả chính xác

                $iCount += 1
            EndIf
        Next
        _GUICtrlListBox_EndUpdate($lst_results)

        ; Shrink arrays to actual size
        ReDim $aSearchIds[$iCount]
        ReDim $aSearchTitles[$iCount]
        ReDim $aSearchTypes[$iCount]
        $iTotalLoaded = $iCount - 1
    EndIf

    If $iTotalLoaded = $iLoadedBefore And $bAppend Then
        $bEndReached = True
    EndIf

    If $iTotalLoaded = 0 And Not $bAppend Then
         DllCall("winmm.dll", "int", "PlaySoundW", "ptr", 0, "ptr", 0, "dword", 0)
         MsgBox(16, _T("Search"), _TF("No results found for: {1}", $sKeyword))
    ElseIf Not $bAppend Then
        DllCall("winmm.dll", "int", "PlaySoundW", "ptr", 0, "ptr", 0, "dword", 0)
        _AppSoundPlay(@ScriptDir & "\sounds\result.wav")
    EndIf

    If Not $bAppend And IsHWnd($hWaitGui) Then
        GUIDelete($hWaitGui)
        GUISetCursor(2, 0)
        _GUICtrlListBox_SetCurSel($lst_results, 0)
        ControlFocus($hResultsGui, "", $lst_results)
    EndIf

    $bIsSearching = False
EndFunc

Func _CheckAutoLoadMore()
    If $hResultsGui = 0 Or $bIsSearching Or $bEndReached Then Return
    Local $iCur = _GUICtrlListBox_GetCurSel($lst_results)
    Local $iCount = _GUICtrlListBox_GetCount($lst_results)
    ; Trigger earlier (10 items remaining) for smoother experience
    If $iCur <> -1 And $iCur >= $iCount - 10 Then
        _SearchYouTube($sCurrentKeyword, True)
    EndIf
EndFunc


Func _ShowContextMenu($bIsFavContext = False)
    Local $iIndex = _GUICtrlListBox_GetCurSel($lst_results)
    If $iIndex = -1 Then Return

    Local $sID = $aSearchIds[$iIndex + 1]
    Local $sTitle = $aSearchTitles[$iIndex + 1]

    Local $hMenu = _GUICtrlMenu_CreatePopup()

    _GUICtrlMenu_AddMenuItem($hMenu, _T("&Play..."), 1001)
    _GUICtrlMenu_AddMenuItem($hMenu, _T("Play as &audio..."), 1002)
    _GUICtrlMenu_AddMenuItem($hMenu, _T("&Download..."), 1003)
    _GUICtrlMenu_AddMenuItem($hMenu, _T("Go to &channel..."), 1004)
    _GUICtrlMenu_AddMenuItem($hMenu, _T("Open in &Browser..."), 1005)
    _GUICtrlMenu_AddMenuItem($hMenu, _T("Copy Lin&k..."), 1006)
    _GUICtrlMenu_AddMenuItem($hMenu, _T("View &Lyrics..."), 1009)

    ; Playlists / channels in the search results cannot be queued (only single videos)
    Local $bCanSub = Not _IsWebLink($sID)
    Local $sItemType = "video"
    If $bIsFavContext = 0 And UBound($aSearchTypes) > $iIndex + 1 Then $sItemType = $aSearchTypes[$iIndex + 1]
    If $sItemType = "playlist" Then $bCanSub = False
    Local $bQueueable = True
    If $bIsFavContext = 0 And UBound($aSearchTypes) > $iIndex + 1 Then
        If $aSearchTypes[$iIndex + 1] = "playlist" Or $aSearchTypes[$iIndex + 1] = "channel" Then $bQueueable = False
    EndIf
    If $bQueueable Then _GUICtrlMenu_AddMenuItem($hMenu, _T("Add to &queue..."), 1013)
    If $bQueueable Then _GUICtrlMenu_AddMenuItem($hMenu, _T("Add to do&wnload queue..."), 1015)
    If $bCanSub Then _GUICtrlMenu_AddMenuItem($hMenu, _T("S&ubscribe to channel..."), 1016)

    Local $bIsInCollection = _IsVideoInAnyCollection($sID)
    _GUICtrlMenu_AddMenuItem($hMenu, _Ternary($bIsInCollection, _T("Remove from &Collection..."), _T("Add to &Collection...")), 1008)

    Local $hSubMenu_Share = _GUICtrlMenu_CreatePopup()
    _GUICtrlMenu_AddMenuItem($hSubMenu_Share, _T("&Telegram"), 1011)
    _GUICtrlMenu_AddMenuItem($hSubMenu_Share, _T("&Facebook"), 1012)
    _GUICtrlMenu_AddMenuItem($hMenu, _T("&Share"), -1, $hSubMenu_Share)

    Local $bIsAlreadyFav = _IsFavorite($sID)

    Local $sFavText
    If $bIsFavContext = 1 Then
        $sFavText = _T("&Remove from Favorite...")
    ElseIf $bIsFavContext = 2 Then
        ; Watch History: muc Favorite rieng (Add/Remove) + muc xoa khoi lich su rieng
        $sFavText = _Ternary($bIsAlreadyFav, _T("Remove from &Favorite..."), _T("Add to &Favorite..."))
    Else
        $sFavText = _Ternary($bIsAlreadyFav, _T("Remove from Favorite..."), _T("Add to &Favorite..."))
    EndIf
    _GUICtrlMenu_AddMenuItem($hMenu, $sFavText, 1007)
    If $bIsFavContext = 2 Then _GUICtrlMenu_AddMenuItem($hMenu, _T("Delete from &History..."), 1010)

    Local $hActiveGui = WinGetHandle("[ACTIVE]")
    Local $iCmd = _GUICtrlMenu_TrackPopupMenu($hMenu, $hActiveGui, MouseGetPos(0), MouseGetPos(1), 1, 1, 2)

    _GUICtrlMenu_DestroyMenu($hMenu)

    Switch $iCmd
        Case 1007
            If $bIsFavContext = 1 Or ($bIsFavContext <> 1 And $bIsAlreadyFav) Then
                If _RemoveFavorite($sID) Then
                    MsgBox(64, _T("Success"), _T("Removed from favorites successfully!"))
                    ; Chi lam moi danh sach khi dang o cua so Favorites
                    If $bIsFavContext = 1 Then Return "REFRESH"
                EndIf
            Else
                _AddFavorite($sID, $sTitle)
            EndIf
        Case 1010 ; Delete from history (Watch History)
            If _RemoveHistory($sID) Then
                MsgBox(64, _T("Success"), _T("Removed from history successfully!"))
                Return "REFRESH"
            EndIf
        Case 1016 ; Subscribe to / unsubscribe from the channel of this item
            _YTS_SubscribeFromItem($sID, $sTitle, $sItemType, $hActiveGui)
        Case 1001
            _PlayLoop($iIndex, False) ; Video
        Case 1002
            _PlayLoop($iIndex, True) ; Audio
        Case 1003
            _ShowDownloadDialog($aSearchIds[$iIndex + 1], $sTitle, $hActiveGui)
        Case 1004
            _Action_GoChannel($iIndex)
        Case 1005
            _Action_OpenBrowser($iIndex)
        Case 1006
            _Action_CopyLink($iIndex, $hActiveGui)
        Case 1009
            _ShowSongLyrics($sTitle, $hActiveGui, $sID)
        Case 1013
            If _Queue_Add($sID, $sTitle) Then
                MsgBox(64, _T("Success"), _TF("Added to the play queue successfully! Position: {1}", $g_iQueueCount), 0, $hActiveGui)
            EndIf
        Case 1015
            _DQ_AddNotify($sID, $sTitle, $hActiveGui)
        Case 1008
            If _IsVideoInAnyCollection($sID) Then
                _RemoveFromAllCollectionsDialog($sID)
            Else
                _AddtoCollection($sID, $sTitle)
            EndIf
        Case 1011 ; Telegram
            _ShowShareLinkDialog("telegram", $sID, $sTitle, $hActiveGui)
        Case 1012 ; Facebook
            _ShowShareLinkDialog("facebook", $sID, $sTitle, $hActiveGui)
    EndSwitch
EndFunc

Func _PathToFileURI($sPath)
    Local $sNorm = StringReplace($sPath, "\", "/")
    Local $aParts = StringSplit($sNorm, "/", 2) ; 2 = return array without count element
    Local $sResult = "file:///"
    For $i = 0 To UBound($aParts) - 1
        If $aParts[$i] = "" Then ContinueLoop
        If $i > 0 Then $sResult &= "/"
        If $i = 0 And StringRegExp($aParts[$i], "^[A-Za-z]:$") Then
            $sResult &= $aParts[$i] ; keep drive letter (e.g. C:) literal
        Else
            $sResult &= _URLEncode($aParts[$i])
        EndIf
    Next
    Return $sResult
EndFunc

Func _URLEncode($sText)
    Local $aData = StringToBinary($sText, 4)
    Local $sEncoded = ""
    For $i = 1 To BinaryLen($aData)
        Local $iByte = Int(BinaryMid($aData, $i, 1))
        If ($iByte >= 48 And $iByte <= 57) Or ($iByte >= 65 And $iByte <= 90) Or ($iByte >= 97 And $iByte <= 122) Or $iByte = 45 Or $iByte = 95 Or $iByte = 46 Or $iByte = 126 Then
            $sEncoded &= Chr($iByte)
        Else
            $sEncoded &= "%" & Hex($iByte, 2)
        EndIf
    Next
    Return $sEncoded
EndFunc

Func _Action_CopyLink($iIndex, $hParent = 0)
    If $iIndex < 0 Or $iIndex >= UBound($aSearchIds) - 1 Then Return
    _ShowCopyLinkDialog($aSearchIds[$iIndex + 1], $hParent)
EndFunc

; ======================================================================
;  COPY LINK DIALOG (version 3.2)
; ======================================================================
; Lets the user choose which kind of YouTube link to copy (links of other sites such as SoundCloud are copied straight away):
;   - the standard link   https://www.youtube.com/watch?v=<id>
;   - the short link      https://youtu.be/<id>
; The dialog stays open after a link is copied (so both kinds can be copied one after the other);
; the Close button or Esc closes it. $hParent = the window that owns the dialog (0 = the window that is active now).
Func _ShowCopyLinkDialog($sID, $hParent = 0)
    $sID = StringStripWS($sID, 3)
    If $sID = "" Then Return

    ; Links of other sites (SoundCloud...) have no short form: no dialog, the link is copied straight away
    If _IsWebLink($sID) Then
        ClipPut($sID)
        _ReportStatus(_T("Link copied to clipboard"))
        Return
    EndIf

    If Not IsHWnd($hParent) Then
        $hParent = WinGetHandle("[ACTIVE]")
        If Not IsHWnd($hParent) Or WinGetProcess($hParent) <> @AutoItPID Then $hParent = 0
    EndIf

    Local $hCopyGui = GUICreate(_T("Copy link"), 340, 205, -1, -1, BitOR($WS_CAPTION, $WS_SYSMENU), $WS_EX_TOPMOST, $hParent)
    GUISetBkColor($COLOR_BLUE)

    GUICtrlCreateLabel(_T("Choose the type of link to copy:"), 10, 15, 320, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)

    Local $btnStandard = GUICtrlCreateButton(_T("&Standard link"), 20, 45, 300, 32)
    GUICtrlSetState(-1, $GUI_DEFBUTTON)
    Local $btnShort = GUICtrlCreateButton(_T("S&hort link"), 20, 85, 300, 32)

    Local $lblStatus = GUICtrlCreateLabel("", 20, 125, 300, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)

    Local $btnClose = GUICtrlCreateButton(_T("&Close"), 110, 155, 120, 32)

    Local $hDummyEsc = GUICtrlCreateDummy()
    Local $aAccel[1][2] = [["{ESC}", $hDummyEsc]]
    GUISetAccelerators($aAccel, $hCopyGui)

    GUISetState(@SW_SHOW, $hCopyGui)
    _AllowUIPI($hCopyGui)
    ControlFocus($hCopyGui, "", $btnStandard)

    Local $nMsg, $sLink, $sDone
    While 1
        $nMsg = _GuiMsg($hCopyGui)
        Switch $nMsg
            Case $GUI_EVENT_CLOSE, $btnClose, $hDummyEsc
                ExitLoop
            Case $btnStandard, $btnShort
                If $nMsg = $btnStandard Then
                    $sLink = _VideoLink($sID)
                    $sDone = _T("Standard link copied to clipboard")
                Else
                    $sLink = _VideoShortLink($sID)
                    $sDone = _T("Short link copied to clipboard")
                EndIf
                ClipPut($sLink)
                GUICtrlSetData($lblStatus, $sDone)
                _NVDA_Speak($sDone)
        EndSwitch
    WEnd

    GUIDelete($hCopyGui)
    If IsHWnd($hParent) Then
        GUISwitch($hParent)
        WinActivate($hParent)
    EndIf
EndFunc


; ======================================================================
;  SHARE LINK DIALOG
; ======================================================================
; Shown when the user picks a platform in the Share menu (Telegram, Facebook...). Like the Copy link
; dialog, it lets the user choose which kind of YouTube link to share:
;   - the standard link   https://www.youtube.com/watch?v=<id>
;   - the short link      https://youtu.be/<id>
; After a choice the dialog closes and the share page of the platform opens in the browser with that link.
; Esc / Cancel closes the dialog without sharing anything.
; $sPlatform = "telegram" or "facebook". $hParent = the window that owns the dialog (0 = the active window).
Func _ShowShareLinkDialog($sPlatform, $sID, $sTitle = "", $hParent = 0)
    $sID = StringStripWS($sID, 3)
    If $sID = "" Then Return

    ; Links of other sites (SoundCloud...) have no short form: no dialog, the link is shared straight away
    If _IsWebLink($sID) Then
        _Share_Open($sPlatform, $sID, $sTitle)
        Return
    EndIf

    If Not IsHWnd($hParent) Then
        $hParent = WinGetHandle("[ACTIVE]")
        If Not IsHWnd($hParent) Or WinGetProcess($hParent) <> @AutoItPID Then $hParent = 0
    EndIf

    Local $sDlgTitle = _Ternary($sPlatform = "telegram", _T("Share on Telegram"), _T("Share on Facebook"))

    Local $hShareGui = GUICreate($sDlgTitle, 340, 195, -1, -1, BitOR($WS_CAPTION, $WS_SYSMENU), $WS_EX_TOPMOST, $hParent)
    GUISetBkColor($COLOR_BLUE)

    GUICtrlCreateLabel(_T("Choose the type of link to share:"), 10, 15, 320, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)

    Local $btnStandard = GUICtrlCreateButton(_T("&Standard link"), 20, 45, 300, 32)
    GUICtrlSetState(-1, $GUI_DEFBUTTON)
    Local $btnShort = GUICtrlCreateButton(_T("S&hort link"), 20, 85, 300, 32)
    Local $btnCancel = GUICtrlCreateButton(_T("&Cancel"), 110, 135, 120, 32)

    Local $hDummyEsc = GUICtrlCreateDummy()
    Local $aAccel[1][2] = [["{ESC}", $hDummyEsc]]
    GUISetAccelerators($aAccel, $hShareGui)

    GUISetState(@SW_SHOW, $hShareGui)
    _AllowUIPI($hShareGui)
    ControlFocus($hShareGui, "", $btnStandard)

    Local $nMsg, $sLink = ""
    While 1
        $nMsg = _GuiMsg($hShareGui)
        Switch $nMsg
            Case $GUI_EVENT_CLOSE, $btnCancel, $hDummyEsc
                ExitLoop
            Case $btnStandard
                $sLink = _VideoLink($sID)
                ExitLoop
            Case $btnShort
                $sLink = _VideoShortLink($sID)
                ExitLoop
        EndSwitch
    WEnd

    GUIDelete($hShareGui)
    If IsHWnd($hParent) Then
        GUISwitch($hParent)
        WinActivate($hParent)
    EndIf

    If $sLink = "" Then Return
    _Share_Open($sPlatform, $sLink, $sTitle)
EndFunc

; Opens the share page of the platform for the given link
Func _Share_Open($sPlatform, $sLink, $sTitle = "")
    Switch $sPlatform
        Case "telegram"
            ShellExecute("https://t.me/share/url?url=" & _URLEncode($sLink) & "&text=" & _URLEncode($sTitle))
        Case "facebook"
            ShellExecute("https://www.facebook.com/sharer/sharer.php?u=" & _URLEncode($sLink))
    EndSwitch
EndFunc


Func _AddDefenderExclusion()
    If Not IsAdmin() Then Return ; Skip if not admin to avoid triggering UAC or shell crashes
    Local $sDir = @ScriptDir
    If StringRight($sDir, 1) <> "\" Then $sDir &= "\"

    Local $sCmd = 'powershell -Command "Add-MpPreference -ExclusionPath ''' & $sDir & '''" -WindowStyle Hidden'
    Run($sCmd, @SystemDir, @SW_HIDE)
EndFunc

Func _Action_OpenBrowser($iIndex)
    If $iIndex < 0 Or $iIndex >= UBound($aSearchIds) - 1 Then Return
    ShellExecute(_VideoLink($aSearchIds[$iIndex + 1]))
EndFunc

Func _Action_ShowDescription($iIndex)
    If $iIndex < 0 Or $iIndex >= UBound($aSearchIds) - 1 Then Return
    Local $sID = $aSearchIds[$iIndex + 1]

    If Not FileExists($DESC_EXE_PATH) Then
        MsgBox(16, _T("Error"), _T("description.exe not found in lib folder!"))
        Return
    EndIf

    Local $hWait = GUICreate(_T("Loading..."), 250, 80, -1, -1, BitOR($WS_POPUP, $WS_BORDER), BitOR($WS_EX_TOPMOST, $WS_EX_TOOLWINDOW), $hResultsGui)
    GUICtrlCreateLabel(_T("Fetching Description from YouTube..."), 10, 25, 230, 20, $SS_CENTER)
    GUISetBkColor(0xFFFFFF, $hWait)
    GUISetState(@SW_SHOW, $hWait)

    Local $iPID = Run(@ComSpec & ' /c "' & $YT_DLP_EXE & ' --get-description --no-playlist --encoding utf-8 -- "' & $sID & '""', @ScriptDir, @SW_HIDE, $STDOUT_CHILD)
    Local $bData = Binary("")

    While ProcessExists($iPID)
        $bData &= StdoutRead($iPID, False, True) ; True = Binary Mode
        GUIGetMsg()
        Sleep(1)
    WEnd
    $bData &= StdoutRead($iPID, False, True)

    GUIDelete($hWait)

    Local $sDesc = BinaryToString($bData, 4) ; 4 = UTF-8

    If $sDesc = "" Then
        MsgBox(64, _T("Info"), _T("No description available for this video."))
    Else
        Local $sTempFile = @TempDir & "\temp_desc.txt"
        Local $hFile = FileOpen($sTempFile, 2 + 256) ; 2 = Write, 256 = UTF-8 encoding
        FileWrite($hFile, $sDesc)
        FileClose($hFile)

        Run('"' & $DESC_EXE_PATH & '" "' & $sTempFile & '"')
    EndIf
EndFunc

Func _Action_ShowComments($iIndex)
    If $iIndex < 0 Or $iIndex >= UBound($aSearchIds) - 1 Then Return
    Local $sID = $aSearchIds[$iIndex + 1]

    If Not FileExists($COMMENTS_EXE_PATH) Then
        MsgBox(16, _T("Error"), _T("comments.exe not found in lib folder!"))
        Return
    EndIf

    ; Directly run comments.exe with the YouTube URL.
    ; comments.exe already handles fetching comments internally.
    Local $sUrl = _VideoLink($sID)
    Run('"' & $COMMENTS_EXE_PATH & '" "' & $sUrl & '"')
EndFunc

Func _Action_GoChannel($iIndex)
    If $iIndex < 0 Or $iIndex >= UBound($aSearchIds) - 1 Then Return
    Local $sID = $aSearchIds[$iIndex + 1]

    ; SoundCloud: the "channel" is the page of the artist
    If _IsSoundCloudLink($sID) Then
        ShellExecute(_SC_ArtistUrl($sID))
        Return
    EndIf

    Local $hLoading = GUICreate(_T("Working..."), 250, 80, -1, -1, BitOR($WS_POPUP, $WS_BORDER), BitOR($WS_EX_TOPMOST, $WS_EX_TOOLWINDOW), $hResultsGui)
    GUICtrlCreateLabel(_T("Fetching channel information..."), 10, 25, 230, 20, $SS_CENTER)
    GUISetBkColor(0xFFFFFF, $hLoading)
    GUISetState(@SW_SHOW, $hLoading)

    Local $pid_channel = Run(@ComSpec & ' /c "' & $YT_DLP_EXE & ' --print "https://www.youtube.com/channel/%(channel_id)s" --no-playlist -- "' & $sID & '""', @ScriptDir, @SW_HIDE, $STDOUT_CHILD + $STDERR_CHILD)
    Local $sChannelUrl = ""
    While ProcessExists($pid_channel)
        $sChannelUrl &= StdoutRead($pid_channel)
        GUIGetMsg()
        Sleep(1)
    WEnd
    $sChannelUrl &= StdoutRead($pid_channel)
    GUIDelete($hLoading)

    $sChannelUrl = StringStripWS($sChannelUrl, 3)
    ; More robust regex for various channel URL formats
    Local $pattern = "(https://www\.youtube\.com/(channel/|@)[^ \r\n]+)"
    Local $aMatch = StringRegExp($sChannelUrl, $pattern, 3)

    If IsArray($aMatch) Then
        ShellExecute($aMatch[0])
    Else
        MsgBox(16, _T("Error"), _T("Cannot get channel URL. The video might be from a deleted channel or restricted."))
    EndIf
EndFunc

; ===========================================================================
; PLAY QUEUE
; First in, first out. Songs are added from the context menu of a list or from the Options menu
; of the player. When the song that is playing ends, the queue plays (each song is removed from the
; queue as it starts). When the queue is empty, playback returns to the list the user was playing
; and continues with the song after the one that was playing before the queue was inserted.
; ===========================================================================
Func _Queue_Add($sID, $sTitle)
    $sID = StringStripWS($sID, 3)
    If $sID = "" Then Return False
    $g_iQueueCount += 1
    ReDim $g_aQueueIds[$g_iQueueCount + 1]
    ReDim $g_aQueueTitles[$g_iQueueCount + 1]
    $g_aQueueIds[$g_iQueueCount] = $sID
    $g_aQueueTitles[$g_iQueueCount] = $sTitle
    Return True
EndFunc

; Takes the first song out of the queue
Func _Queue_Pop(ByRef $sID, ByRef $sTitle)
    If $g_iQueueCount < 1 Then Return False
    $sID = $g_aQueueIds[1]
    $sTitle = $g_aQueueTitles[1]
    For $i = 1 To $g_iQueueCount - 1
        $g_aQueueIds[$i] = $g_aQueueIds[$i + 1]
        $g_aQueueTitles[$i] = $g_aQueueTitles[$i + 1]
    Next
    $g_iQueueCount -= 1
    ReDim $g_aQueueIds[$g_iQueueCount + 1]
    ReDim $g_aQueueTitles[$g_iQueueCount + 1]
    Return True
EndFunc

Func _Queue_Clear()
    $g_iQueueCount = 0
    ReDim $g_aQueueIds[1]
    ReDim $g_aQueueTitles[1]
EndFunc

; Decides what _PlayLoop plays after the current song (it ended, or the user asked for the next one):
;  - queue not empty  -> the first song of the queue (remembers where to go back to in the list)
;  - playing the queue and it is now empty -> back to the list, at the song after the one that was playing before
; Returns True when it changed what has to be played; False when _PlayLoop should just go on with the list.
Func _Queue_TakeNext(ByRef $bFromQueue, ByRef $sQID, ByRef $sQTitle, ByRef $iCurrentIndex, ByRef $iResumeIndex, $iNormalNext)
    If $g_iQueueCount > 0 Then
        If Not $bFromQueue Then $iResumeIndex = $iNormalNext
        _Queue_Pop($sQID, $sQTitle)
        $bFromQueue = True
        Return True
    EndIf
    If $bFromQueue Then
        $bFromQueue = False
        $iCurrentIndex = $iResumeIndex
        Return True
    EndIf
    Return False
EndFunc

Func _Queue_FillList($idList)
    _GUICtrlListBox_ResetContent($idList)
    If $g_iQueueCount = 0 Then
        GUICtrlSetData($idList, _T("The play queue is empty."))
        Return
    EndIf
    Local $sBatch = ""
    For $i = 1 To $g_iQueueCount
        $sBatch &= $i & ". " & StringReplace($g_aQueueTitles[$i], "|", "/") & "|"
    Next
    GUICtrlSetData($idList, StringTrimRight($sBatch, 1))
EndFunc

; Alt+Up / Alt+Down in the queue window: moves the selected song one place up / down
Func _Queue_MoveSelected($idList, $iDir)
    If $g_iQueueCount = 0 Then
        _NVDA_Speak(_T("The play queue is empty."))
        Return
    EndIf
    Local $iSel = _GUICtrlListBox_GetCurSel($idList) + 1 ; 1-based
    If $iSel < 1 Or $iSel > $g_iQueueCount Then Return
    Local $iTarget = $iSel + $iDir
    If $iTarget < 1 Then
        _NVDA_Speak(_T("Already at the top of the queue."))
        Return
    ElseIf $iTarget > $g_iQueueCount Then
        _NVDA_Speak(_T("Already at the bottom of the queue."))
        Return
    EndIf
    Local $sTmpID = $g_aQueueIds[$iSel], $sTmpTitle = $g_aQueueTitles[$iSel]
    $g_aQueueIds[$iSel] = $g_aQueueIds[$iTarget]
    $g_aQueueTitles[$iSel] = $g_aQueueTitles[$iTarget]
    $g_aQueueIds[$iTarget] = $sTmpID
    $g_aQueueTitles[$iTarget] = $sTmpTitle
    _Queue_FillList($idList)
    _GUICtrlListBox_SetCurSel($idList, $iTarget - 1)
    _NVDA_Speak(_TF("Moved to position {1} of {2}", $iTarget, $g_iQueueCount))
EndFunc

; Removes song number $i (1-based) from the queue
Func _Queue_RemoveAt($i)
    If $i < 1 Or $i > $g_iQueueCount Then Return False
    For $k = $i To $g_iQueueCount - 1
        $g_aQueueIds[$k] = $g_aQueueIds[$k + 1]
        $g_aQueueTitles[$k] = $g_aQueueTitles[$k + 1]
    Next
    $g_iQueueCount -= 1
    ReDim $g_aQueueIds[$g_iQueueCount + 1]
    ReDim $g_aQueueTitles[$g_iQueueCount + 1]
    Return True
EndFunc

; Moves the selected song to the front of the queue so that it is the next one to play.
; The songs that were before it keep their order and stay in the queue.
Func _Queue_MoveSelectedToFront($idList)
    Local $iSel = _GUICtrlListBox_GetCurSel($idList) + 1
    If $iSel < 1 Or $iSel > $g_iQueueCount Then Return False
    Local $sTmpID = $g_aQueueIds[$iSel], $sTmpTitle = $g_aQueueTitles[$iSel]
    For $k = $iSel To 2 Step -1
        $g_aQueueIds[$k] = $g_aQueueIds[$k - 1]
        $g_aQueueTitles[$k] = $g_aQueueTitles[$k - 1]
    Next
    $g_aQueueIds[1] = $sTmpID
    $g_aQueueTitles[1] = $sTmpTitle
    Return True
EndFunc

; "Go to channel" for a song of the queue (same as the one of the search results, but works from an ID)
Func _Queue_GoChannel($sID, $hParent)
    If _IsSoundCloudLink($sID) Then
        ShellExecute(_SC_ArtistUrl($sID))
        Return
    EndIf
    Local $hLoading = GUICreate(_T("Working..."), 250, 80, -1, -1, BitOR($WS_POPUP, $WS_BORDER), BitOR($WS_EX_TOPMOST, $WS_EX_TOOLWINDOW), $hParent)
    GUICtrlCreateLabel(_T("Fetching channel information..."), 10, 25, 230, 20, $SS_CENTER)
    GUISetBkColor(0xFFFFFF, $hLoading)
    GUISetState(@SW_SHOW, $hLoading)

    Local $pid_channel = Run(@ComSpec & ' /c "' & $YT_DLP_EXE & ' --print "https://www.youtube.com/channel/%(channel_id)s" --no-playlist -- "' & $sID & '""', @ScriptDir, @SW_HIDE, $STDOUT_CHILD + $STDERR_CHILD)
    Local $sChannelUrl = ""
    While ProcessExists($pid_channel)
        $sChannelUrl &= StdoutRead($pid_channel)
        GUIGetMsg()
        Sleep(1)
    WEnd
    $sChannelUrl &= StdoutRead($pid_channel)
    GUIDelete($hLoading)

    $sChannelUrl = StringStripWS($sChannelUrl, 3)
    Local $aMatch = StringRegExp($sChannelUrl, "(https://www\.youtube\.com/(channel/|@)[^ \r\n]+)", 3)
    If IsArray($aMatch) Then
        ShellExecute($aMatch[0])
    Else
        MsgBox(16, _T("Error"), _T("Cannot get channel URL. The video might be from a deleted channel or restricted."), 0, $hParent)
    EndIf
EndFunc

; Context menu of the play queue: the same as the one of the YouTube results, but with
; "Remove from queue" instead of "Add to queue". Returns "PLAY" / "PLAY_AUDIO" when the user wants to play the song.
Func _Queue_ContextMenu($idList, $hQueueGui, $hParent, $bAllowPlay)
    Local $iSel = _GUICtrlListBox_GetCurSel($idList) + 1
    If $g_iQueueCount = 0 Or $iSel < 1 Or $iSel > $g_iQueueCount Then Return ""
    Local $sID = $g_aQueueIds[$iSel]
    Local $sTitle = $g_aQueueTitles[$iSel]

    Local $hMenu = _GUICtrlMenu_CreatePopup()
    If $bAllowPlay Then
        _GUICtrlMenu_AddMenuItem($hMenu, _T("&Play..."), 1001)
        ; Inside the player the queue keeps playing in the mode (video / audio) that is already open
        If $hParent = 0 Then _GUICtrlMenu_AddMenuItem($hMenu, _T("Play as &audio..."), 1002)
    EndIf
    _GUICtrlMenu_AddMenuItem($hMenu, _T("&Download..."), 1003)
    _GUICtrlMenu_AddMenuItem($hMenu, _T("Go to &channel..."), 1004)
    _GUICtrlMenu_AddMenuItem($hMenu, _T("Open in &Browser..."), 1005)
    _GUICtrlMenu_AddMenuItem($hMenu, _T("Copy Lin&k..."), 1006)
    _GUICtrlMenu_AddMenuItem($hMenu, _T("View &Lyrics..."), 1009)
    _GUICtrlMenu_AddMenuItem($hMenu, _T("Remove from &queue..."), 1014)
    _GUICtrlMenu_AddMenuItem($hMenu, _T("Add to do&wnload queue..."), 1015)

    Local $bIsInCollection = _IsVideoInAnyCollection($sID)
    _GUICtrlMenu_AddMenuItem($hMenu, _Ternary($bIsInCollection, _T("Remove from &Collection..."), _T("Add to &Collection...")), 1008)

    Local $hSubMenu_Share = _GUICtrlMenu_CreatePopup()
    _GUICtrlMenu_AddMenuItem($hSubMenu_Share, _T("&Telegram"), 1011)
    _GUICtrlMenu_AddMenuItem($hSubMenu_Share, _T("&Facebook"), 1012)
    _GUICtrlMenu_AddMenuItem($hMenu, _T("&Share"), -1, $hSubMenu_Share)

    Local $bIsAlreadyFav = _IsFavorite($sID)
    _GUICtrlMenu_AddMenuItem($hMenu, _Ternary($bIsAlreadyFav, _T("Remove from &Favorite..."), _T("Add to &Favorite...")), 1007)

    Local $iCmd = _GUICtrlMenu_TrackPopupMenu($hMenu, $hQueueGui, MouseGetPos(0), MouseGetPos(1), 1, 1, 2)
    _GUICtrlMenu_DestroyMenu($hMenu)

    Switch $iCmd
        Case 1001
            Return "PLAY"
        Case 1002
            Return "PLAY_AUDIO"
        Case 1003
            _ShowDownloadDialog($sID, $sTitle, $hQueueGui)
        Case 1004
            _Queue_GoChannel($sID, $hQueueGui)
        Case 1005
            ShellExecute(_VideoLink($sID))
        Case 1006
            _ShowCopyLinkDialog($sID, $hQueueGui)
        Case 1009
            _ShowSongLyrics($sTitle, $hQueueGui, $sID)
        Case 1015
            _DQ_AddNotify($sID, $sTitle, $hQueueGui)
        Case 1014 ; Remove from queue
            _Queue_RemoveAt($iSel)
            _Queue_FillList($idList)
            _GUICtrlListBox_SetCurSel($idList, ($iSel > $g_iQueueCount) ? $g_iQueueCount - 1 : $iSel - 1)
            If $g_iQueueCount < 1 Then _GUICtrlListBox_SetCurSel($idList, 0)
            _NVDA_Speak(_T("Removed from the play queue."))
        Case 1008
            If _IsVideoInAnyCollection($sID) Then
                _RemoveFromAllCollectionsDialog($sID)
            Else
                _AddtoCollection($sID, $sTitle)
            EndIf
        Case 1007
            If $bIsAlreadyFav Then
                If _RemoveFavorite($sID) Then MsgBox(64, _T("Success"), _T("Removed from favorites successfully!"), 0, $hQueueGui)
            Else
                _AddFavorite($sID, $sTitle)
            EndIf
        Case 1011 ; Telegram
            _ShowShareLinkDialog("telegram", $sID, $sTitle, $hQueueGui)
        Case 1012 ; Facebook
            _ShowShareLinkDialog("facebook", $sID, $sTitle, $hQueueGui)
    EndSwitch
    Return ""
EndFunc

; Play queue window. Tab order: list, "Clear all queue", "Close".
; In the list: Enter plays the selected song (Ctrl+Enter as audio), the Applications key / Shift+F10 opens the context menu.
; $hParent: the player window when it is opened from the player (Ctrl+Shift+Q / Options menu). In that case
;   choosing a song makes the player jump to it and the function returns "PLAY".
; $bAllowPlay: False when playing from here makes no sense (local audio file in the player).
Func _ShowPlayQueue($hParent = 0, $bAllowPlay = True)
    Local $hQueueGui = GUICreate(_T("Play queue"), 400, 440, -1, -1, -1, ($hParent <> 0) ? $WS_EX_TOPMOST : -1, $hParent)
    GUISetBkColor($COLOR_BLUE)
    GUICtrlCreateLabel(_T("Songs waiting to play (Alt+Up / Alt+Down: change the order):"), 10, 10, 380, 36)
    GUICtrlSetColor(-1, 0xFFFFFF)
    GUICtrlSetFont(-1, 10, 800)
    Local $lstQueue = GUICtrlCreateList("", 10, 50, 380, 285, BitOR($LBS_NOTIFY, $WS_VSCROLL, $WS_BORDER))
    Local $btnClearQueue = GUICtrlCreateButton(_T("Clear all queue"), 10, 345, 380, 30)
    Local $btnCloseQueue = GUICtrlCreateButton(_T("Close"), 10, 385, 380, 30)

    Local $hDummyEnterQ = GUICtrlCreateDummy()
    Local $hDummyCtrlEnterQ = GUICtrlCreateDummy()
    Local $hDummyEscQ = GUICtrlCreateDummy()
    Local $hDummyAltUpQ = GUICtrlCreateDummy()
    Local $hDummyAltDownQ = GUICtrlCreateDummy()
    Local $hDummyAppsQ = GUICtrlCreateDummy()
    Local $aAccelQ[7][2] = [ _
        ["{ENTER}", $hDummyEnterQ], _
        ["^{ENTER}", $hDummyCtrlEnterQ], _
        ["{ESC}", $hDummyEscQ], _
        ["!{UP}", $hDummyAltUpQ], _
        ["!{DOWN}", $hDummyAltDownQ], _
        ["{APPSKEY}", $hDummyAppsQ], _
        ["+{F10}", $hDummyAppsQ] _
    ]
    GUISetAccelerators($aAccelQ, $hQueueGui)

    _Queue_FillList($lstQueue)
    _GUICtrlListBox_SetCurSel($lstQueue, 0)
    GUISetState(@SW_SHOW, $hQueueGui)
    _AllowUIPI($hQueueGui)
    ControlFocus($hQueueGui, "", $lstQueue)

    While 1
        Local $nMsgQ = _GuiMsg($hQueueGui)
        Local $sQAct = "" ; "PLAY" / "PLAY_AUDIO" = play the selected song

        If $nMsgQ = $hDummyEnterQ Then
            ; Enter plays the song of the list, or presses the button that has the focus
            Local $hFocusQ = ControlGetHandle($hQueueGui, "", ControlGetFocus($hQueueGui))
            If $hFocusQ = GUICtrlGetHandle($btnClearQueue) Then
                $nMsgQ = $btnClearQueue
            ElseIf $hFocusQ = GUICtrlGetHandle($btnCloseQueue) Then
                $nMsgQ = $btnCloseQueue
            ElseIf $hFocusQ = GUICtrlGetHandle($lstQueue) Then
                $sQAct = "PLAY"
            EndIf
        ElseIf $nMsgQ = $hDummyCtrlEnterQ Then
            If ControlGetHandle($hQueueGui, "", ControlGetFocus($hQueueGui)) = GUICtrlGetHandle($lstQueue) Then $sQAct = "PLAY_AUDIO"
        ElseIf $nMsgQ = $hDummyAppsQ Then
            If ControlGetHandle($hQueueGui, "", ControlGetFocus($hQueueGui)) = GUICtrlGetHandle($lstQueue) Then
                $sQAct = _Queue_ContextMenu($lstQueue, $hQueueGui, $hParent, $bAllowPlay)
            EndIf
        EndIf

        If $sQAct <> "" Then
            If $bAllowPlay And $g_iQueueCount > 0 And _Queue_MoveSelectedToFront($lstQueue) Then
                If $hParent <> 0 Then
                    ; Opened from the player: the player closes this song and takes the first one of the queue
                    GUIDelete($hQueueGui)
                    Return "PLAY"
                EndIf
                _PlayLoop(-1, $sQAct = "PLAY_AUDIO", True)
                _Queue_FillList($lstQueue)
                _GUICtrlListBox_SetCurSel($lstQueue, 0)
                WinActivate($hQueueGui)
                ControlFocus($hQueueGui, "", $lstQueue)
            EndIf
            ContinueLoop
        EndIf

        Switch $nMsgQ
            Case $GUI_EVENT_CLOSE, $btnCloseQueue, $hDummyEscQ
                GUIDelete($hQueueGui)
                Return ""
            Case $btnClearQueue
                If $g_iQueueCount = 0 Then
                    MsgBox(64, _T("Info"), _T("The play queue is already empty."), 0, $hQueueGui)
                ElseIf MsgBox(36, _T("Confirm"), _T("Are you sure you want to clear the entire play queue?"), 0, $hQueueGui) = 6 Then
                    _Queue_Clear()
                    _Queue_FillList($lstQueue)
                    _GUICtrlListBox_SetCurSel($lstQueue, 0)
                    _NVDA_Speak(_T("The play queue has been cleared."))
                EndIf
            Case $hDummyAltUpQ
                _Queue_MoveSelected($lstQueue, -1)
            Case $hDummyAltDownQ
                _Queue_MoveSelected($lstQueue, 1)
        EndSwitch
    WEnd
EndFunc

; ===========================================================================
; DOWNLOAD QUEUE
; Songs are added from the context menu of the lists or from Options > Add to download queue.
; In the queue window the order can be changed (Alt+Up / Alt+Down), then Download downloads them
; one after the other, first added = first downloaded. Every song that finished is removed from the queue.
; ===========================================================================

; Returns the position (>0), 0 when the item is not valid, -1 when it is already in the queue
Func _DQ_Add($sID, $sTitle)
    $sID = StringStripWS($sID, 3)
    If $sID = "" Then Return 0
    For $i = 1 To $g_iDQCount
        If $g_aDQIds[$i] = $sID Then Return -1
    Next
    $g_iDQCount += 1
    ReDim $g_aDQIds[$g_iDQCount + 1]
    ReDim $g_aDQTitles[$g_iDQCount + 1]
    $g_aDQIds[$g_iDQCount] = $sID
    $g_aDQTitles[$g_iDQCount] = $sTitle
    Return $g_iDQCount
EndFunc

; Adds and tells the user. $bStatus = True: use the player status line (read by the screen reader) instead of a message box.
Func _DQ_AddNotify($sID, $sTitle, $hParent = 0, $bStatus = False)
    Local $iRes = _DQ_Add($sID, $sTitle)
    Local $sMsg, $iIcon = 64
    If $iRes > 0 Then
        $sMsg = _TF("Added to the download queue, position {1}", $iRes)
    ElseIf $iRes = -1 Then
        $sMsg = _T("This item is already in the download queue.")
    Else
        $sMsg = _T("Cannot add this item to the download queue.")
    EndIf
    If $bStatus Then
        _ReportStatus($sMsg)
    Else
        If Not IsHWnd($hParent) Then $hParent = 0
        MsgBox($iIcon, _T("Download queue"), $sMsg, 0, $hParent)
    EndIf
EndFunc

Func _DQ_RemoveAt($i)
    If $i < 1 Or $i > $g_iDQCount Then Return False
    For $k = $i To $g_iDQCount - 1
        $g_aDQIds[$k] = $g_aDQIds[$k + 1]
        $g_aDQTitles[$k] = $g_aDQTitles[$k + 1]
    Next
    $g_iDQCount -= 1
    ReDim $g_aDQIds[$g_iDQCount + 1]
    ReDim $g_aDQTitles[$g_iDQCount + 1]
    Return True
EndFunc

Func _DQ_Clear()
    $g_iDQCount = 0
    ReDim $g_aDQIds[1]
    ReDim $g_aDQTitles[1]
EndFunc

Func _DQ_FillList($idList)
    _GUICtrlListBox_ResetContent($idList)
    If $g_iDQCount = 0 Then
        GUICtrlSetData($idList, _T("The download queue is empty."))
        Return
    EndIf
    Local $sBatch = ""
    For $i = 1 To $g_iDQCount
        $sBatch &= $i & ". " & StringReplace($g_aDQTitles[$i], "|", "/") & "|"
    Next
    GUICtrlSetData($idList, StringTrimRight($sBatch, 1))
EndFunc

; Alt+Up / Alt+Down in the download queue window
Func _DQ_MoveSelected($idList, $iDir)
    If $g_iDQCount = 0 Then
        _NVDA_Speak(_T("The download queue is empty."))
        Return
    EndIf
    Local $iSel = _GUICtrlListBox_GetCurSel($idList) + 1
    If $iSel < 1 Or $iSel > $g_iDQCount Then Return
    Local $iTarget = $iSel + $iDir
    If $iTarget < 1 Then
        _NVDA_Speak(_T("Already at the top of the queue."))
        Return
    ElseIf $iTarget > $g_iDQCount Then
        _NVDA_Speak(_T("Already at the bottom of the queue."))
        Return
    EndIf
    Local $sTmpID = $g_aDQIds[$iSel], $sTmpTitle = $g_aDQTitles[$iSel]
    $g_aDQIds[$iSel] = $g_aDQIds[$iTarget]
    $g_aDQTitles[$iSel] = $g_aDQTitles[$iTarget]
    $g_aDQIds[$iTarget] = $sTmpID
    $g_aDQTitles[$iTarget] = $sTmpTitle
    _DQ_FillList($idList)
    _GUICtrlListBox_SetCurSel($idList, $iTarget - 1)
    _NVDA_Speak(_TF("Moved to position {1} of {2}", $iTarget, $g_iDQCount))
EndFunc

; yt-dlp format arguments from the text of the format combo box and the bitrate combo box
Func _DQ_BuildFmt($sTxt, $sBitrate)
    Local $sFmt = ""
    If StringInStr($sTxt, "MP3") Then
        $sFmt = "-x --audio-format mp3"
    ElseIf StringInStr($sTxt, "WAV") Then
        $sFmt = "-x --audio-format wav"
    ElseIf StringInStr($sTxt, "M4A") Then
        $sFmt = "-x --audio-format m4a"
    ElseIf StringInStr($sTxt, "OGG") Then
        $sFmt = "-x --audio-format vorbis"
    ElseIf StringInStr($sTxt, "WebM") Then
        $sFmt = "bestvideo+bestaudio --merge-output-format webm"
    Else
        $sFmt = "-f bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best"
    EndIf
    Local $iKbps = StringRegExpReplace($sBitrate, "[^0-9]", "")
    If $iKbps <> "" And (StringInStr($sTxt, "Audio") Or StringInStr($sTxt, "MP3") Or StringInStr($sTxt, "WAV") Or StringInStr($sTxt, "M4A") Or StringInStr($sTxt, "OGG")) Then
        $sFmt &= " --audio-quality " & $iKbps & "k"
    EndIf
    Return $sFmt
EndFunc

; Downloads the whole queue, one song after the other. $iNameMode: 0 = title, 1 = title in its own subfolder,
; 2 = numbered (the number is the order in the queue), 3 = numbered, inside the folder "Download queue".
; Every song that is downloaded is removed from the queue; a song that fails stays in it. Cancel stops at once
; (the song being downloaded is deleted and stays in the queue).
Func _DQ_RunDownloads($hParent, $sFmtTxt, $sBitrate, $iNameMode)
    Local $sFmt = _DQ_BuildFmt($sFmtTxt, $sBitrate)
    Local $sPath = $g_sDownloadPath
    If StringStripWS($sPath, 3) = "" Then $sPath = @ScriptDir & "\download"
    If Not FileExists($sPath) Then DirCreate($sPath)
    While StringRight($sPath, 1) = "\" Or StringRight($sPath, 1) = "/"
        $sPath = StringTrimRight($sPath, 1)
    WEnd

    Local $iTotal = $g_iDQCount, $iFailed = 0, $iDone = 0, $bCancelled = False, $sFailedList = ""
    Local $hProg = GUICreate(_T("Downloading"), 400, 170, -1, -1, -1, -1, $hParent)
    GUISetBkColor($COLOR_BLUE, $hProg)
    Local $lblItem = GUICtrlCreateLabel("", 10, 15, 380, 40)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $prog = GUICtrlCreateProgress(10, 65, 380, 20)
    Local $lblStatus = GUICtrlCreateLabel("", 10, 92, 380, 16)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $btnCancelRun = GUICtrlCreateButton(_T("Cancel"), 130, 122, 140, 30)
    Local $hDummyEscRun = GUICtrlCreateDummy()
    Local $aAccelRun[1][2] = [["{ESC}", $hDummyEscRun]]
    GUISetAccelerators($aAccelRun, $hProg)
    GUISetState(@SW_SHOW, $hProg)
    _AllowUIPI($hProg)
    If $hParent <> 0 And IsHWnd($hParent) Then GUISetState(@SW_DISABLE, $hParent)

    _AppSoundPlay(@ScriptDir & "\sounds\download-started.wav")
    _DLSound_Start()
    Local $sSnapshotAll = _ListFilesRecursive($sPath)

    For $k = 1 To $iTotal
        Local $iIdx = $iFailed + 1 ; songs that failed stay at the front of the queue
        If $iIdx > $g_iDQCount Then ExitLoop
        Local $sID = $g_aDQIds[$iIdx], $sTitle = $g_aDQTitles[$iIdx]

        Local $sOutTemplate = "%(title)s.%(ext)s"
        Local $sNum = StringFormat("%02d", $k)
        Switch $iNameMode
            Case 1
                $sOutTemplate = "%(title)s/%(title)s.%(ext)s"
            Case 2
                $sOutTemplate = $sNum & " - %(title)s.%(ext)s"
            Case 3
                $sOutTemplate = "Download queue/" & $sNum & " - %(title)s.%(ext)s"
        EndSwitch

        GUICtrlSetData($lblItem, _TF("Downloading {1} of {2}: {3}", $k, $iTotal, $sTitle))
        _NVDA_Speak(_TF("Downloading item {1} of {2}", $k, $iTotal))
        Local $sCmd = $YT_DLP_EXE & ' --newline ' & $sFmt & ' -P "' & $sPath & '" --ffmpeg-location "' & @ScriptDir & '\lib" -o "' & $sOutTemplate & '" -- "' & _VideoLink($sID) & '"'
        Local $sBefore = _ListFilesRecursive($sPath)
        Local $iPid = Run($sCmd, @ScriptDir, @SW_HIDE, $STDOUT_CHILD + $STDERR_CHILD)
        Local $iStart = TimerInit()
        Local $aProg = _DL_NewProgressState()
        Local $iShown = 0, $sOut = "", $sErr = "", $sLastSt = ""

        While ProcessExists($iPid)
            _DLSound_Tick()
            Local $sNew = StdoutRead($iPid)
            $sOut &= $sNew
            $sErr &= StderrRead($iPid)
            Local $iPct = _DL_FeedProgress($aProg, $sNew)
            If $iPct > $iShown Then $iShown = $iPct ; only goes up
            GUICtrlSetData($prog, Int((($k - 1) + $iShown / 100) / $iTotal * 100))
            Local $sNewSt = _DL_TimeStatusText($iStart, $aProg)
            If $sNewSt <> $sLastSt Then
                GUICtrlSetData($lblStatus, $sNewSt)
                $sLastSt = $sNewSt
            EndIf

            Local $iMsgRun = _GuiMsg($hProg)
            If $iMsgRun = $GUI_EVENT_CLOSE Or $iMsgRun = $btnCancelRun Or $iMsgRun = $hDummyEscRun Then
                Local $iConfirm = MsgBox(4 + 32 + 256, _T("Cancel"), _T("Are you sure you want to cancel?") & @CRLF & @CRLF & _T("The file currently being downloaded will be deleted."), 0, $hProg)
                If $iConfirm = 6 Then
                    _KillProcessTree($iPid)
                    _DeleteNewFiles($sPath, $sBefore)
                    $bCancelled = True
                    ExitLoop
                EndIf
            EndIf
            Sleep(150)
        WEnd
        If $bCancelled Then ExitLoop

        $sOut &= StdoutRead($iPid)
        $sErr &= StderrRead($iPid)
        ; The exit code of yt-dlp is not reliable here (the process has already ended), so success is decided
        ; by the result: a new file appeared, or yt-dlp says the file already exists.
        Local $iNewFiles = UBound(_GetNewDownloadedFiles($sPath, $sBefore))
        Local $bAlready = StringInStr($sOut, "has already been downloaded") > 0
        If $iNewFiles = 0 And Not $bAlready Then
            $iFailed += 1
            Local $aErrLines = StringRegExp($sErr & @LF & $sOut, "(?m)^ERROR:[^\r\n]*", 3)
            Local $sReason = ""
            If IsArray($aErrLines) Then $sReason = $aErrLines[UBound($aErrLines) - 1]
            If StringLen($sReason) > 200 Then $sReason = StringLeft($sReason, 200)
            $sFailedList &= "- " & $sTitle & @CRLF
            If $sReason <> "" Then $sFailedList &= "  " & $sReason & @CRLF
        Else
            _DQ_RemoveAt($iIdx)
            $iDone += 1
        EndIf
    Next
    _DLSound_Stop() ; finished or cancelled: the downloading sound ends here

    GUIDelete($hProg)
    If $hParent <> 0 And IsHWnd($hParent) Then
        GUISetState(@SW_ENABLE, $hParent)
        WinActivate($hParent)
    EndIf

    If $iDone > 0 Then
        _DLSound_Stop()
        _AppSoundPlay(@ScriptDir & "\sounds\download_finish.wav")
        _ShowDownloadCompleteDialog($sPath, _GetNewDownloadedFiles($sPath, $sSnapshotAll))
    EndIf
    If $iFailed > 0 Then
        MsgBox(48, _T("Download queue"), _TF("{1} item(s) could not be downloaded and were kept in the queue:", $iFailed) & @CRLF & @CRLF & $sFailedList, 0, $hParent)
    EndIf
    If $hParent <> 0 And IsHWnd($hParent) Then WinActivate($hParent)
EndFunc

; Download queue window. Tab order: list, Remove selected, Clear all queue, format, bitrate,
; custom name check box and combo box, Download, Cancel (Cancel closes the window).
Func _ShowDownloadQueue($hParent = 0)
    Local $hDQGui = GUICreate(_T("Download queue"), 400, 440, -1, -1, -1, ($hParent <> 0) ? $WS_EX_TOPMOST : -1, $hParent)
    GUISetBkColor($COLOR_BLUE)
    GUICtrlCreateLabel(_T("Songs waiting to download (Alt+Up / Alt+Down: change the order):"), 10, 10, 380, 36)
    GUICtrlSetColor(-1, 0xFFFFFF)
    GUICtrlSetFont(-1, 10, 800)
    Local $lstDQ = GUICtrlCreateList("", 10, 50, 380, 165, BitOR($LBS_NOTIFY, $WS_VSCROLL, $WS_BORDER))
    Local $btnDQRemove = GUICtrlCreateButton(_T("Remove selected"), 10, 223, 185, 28)
    Local $btnDQClear = GUICtrlCreateButton(_T("Clear all queue"), 205, 223, 185, 28)

    GUICtrlCreateLabel(_T("Select Format :"), 10, 262, 180, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $cboDQFormat = GUICtrlCreateCombo("", 10, 284, 180, 20, $CBS_DROPDOWNLIST)
    GUICtrlSetTip(-1, _T("Select the download format. Use the arrow keys to browse the list in alphabetical order"))
    GUICtrlSetData(-1, _TL("M4A (Audio)|MP3 (Audio)|MP4 (Video, Best)|OGG (Audio)|WAV (Audio)|WebM (Video)"), _T("MP4 (Video, Best)"))

    GUICtrlCreateLabel(_T("Select Bitrate:"), 210, 262, 180, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $cboDQBitrate = GUICtrlCreateCombo("", 210, 284, 180, 20, $CBS_DROPDOWNLIST)
    GUICtrlSetTip(-1, _T("Select the bitrate (kbps). Use the arrow keys to browse from low to high"))
    GUICtrlSetData(-1, _TL("128 kbps|192 kbps|256 kbps|320 kbps"), _T("320 kbps"))

    Local $chkDQName = GUICtrlCreateCheckbox(_T("Choose custom output filename composition"), 10, 315, 380, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $cboDQName = GUICtrlCreateCombo("", 10, 340, 380, 20, $CBS_DROPDOWNLIST)
    GUICtrlSetTip(-1, _T("Select the file naming style. Use the arrow keys to browse the list in alphabetical order"))
    GUICtrlSetData(-1, _TL("No numbering|No numbering and create subdirectory|Numbering|Numbering and create subdirectory"), _T("No numbering"))
    GUICtrlSetState(-1, $GUI_DISABLE)

    Local $btnDQStart = GUICtrlCreateButton(_T("Download (Alt+D)"), 10, 385, 255, 40)
    Local $btnDQCancel = GUICtrlCreateButton(_T("Cancel"), 275, 385, 115, 40)

    Local $hDummyEnterDQ = GUICtrlCreateDummy()
    Local $hDummyEscDQ = GUICtrlCreateDummy()
    Local $hDummyAltUpDQ = GUICtrlCreateDummy()
    Local $hDummyAltDownDQ = GUICtrlCreateDummy()
    Local $hDummyDelDQ = GUICtrlCreateDummy()
    Local $aAccelDQ[6][2] = [ _
        ["{ENTER}", $hDummyEnterDQ], _
        ["{ESC}", $hDummyEscDQ], _
        ["!{UP}", $hDummyAltUpDQ], _
        ["!{DOWN}", $hDummyAltDownDQ], _
        ["{DELETE}", $hDummyDelDQ], _
        ["!d", $btnDQStart] _
    ]
    GUISetAccelerators($aAccelDQ, $hDQGui)

    _DQ_FillList($lstDQ)
    _GUICtrlListBox_SetCurSel($lstDQ, 0)
    GUISetState(@SW_SHOW, $hDQGui)
    _AllowUIPI($hDQGui)
    ControlFocus($hDQGui, "", $lstDQ)

    While 1
        Local $nMsgDQ = _GuiMsg($hDQGui)

        If $nMsgDQ = $hDummyEnterDQ Then
            ; Enter presses the button that has the focus
            Local $hFocusDQ = ControlGetHandle($hDQGui, "", ControlGetFocus($hDQGui))
            Switch $hFocusDQ
                Case GUICtrlGetHandle($btnDQRemove)
                    $nMsgDQ = $btnDQRemove
                Case GUICtrlGetHandle($btnDQClear)
                    $nMsgDQ = $btnDQClear
                Case GUICtrlGetHandle($btnDQStart)
                    $nMsgDQ = $btnDQStart
                Case GUICtrlGetHandle($btnDQCancel)
                    $nMsgDQ = $btnDQCancel
            EndSwitch
        ElseIf $nMsgDQ = $hDummyDelDQ Then
            If ControlGetHandle($hDQGui, "", ControlGetFocus($hDQGui)) = GUICtrlGetHandle($lstDQ) Then $nMsgDQ = $btnDQRemove
        EndIf

        Switch $nMsgDQ
            Case $GUI_EVENT_CLOSE, $btnDQCancel, $hDummyEscDQ
                GUIDelete($hDQGui)
                If $hParent <> 0 And IsHWnd($hParent) Then WinActivate($hParent)
                Return

            Case $chkDQName
                If GUICtrlRead($chkDQName) = $GUI_CHECKED Then
                    GUICtrlSetState($cboDQName, $GUI_ENABLE)
                Else
                    GUICtrlSetState($cboDQName, $GUI_DISABLE)
                EndIf

            Case $hDummyAltUpDQ
                _DQ_MoveSelected($lstDQ, -1)

            Case $hDummyAltDownDQ
                _DQ_MoveSelected($lstDQ, 1)

            Case $btnDQRemove
                If $g_iDQCount = 0 Then
                    _NVDA_Speak(_T("The download queue is empty."))
                Else
                    Local $iSelDQ = _GUICtrlListBox_GetCurSel($lstDQ) + 1
                    If $iSelDQ >= 1 And $iSelDQ <= $g_iDQCount Then
                        _DQ_RemoveAt($iSelDQ)
                        _DQ_FillList($lstDQ)
                        If $iSelDQ > $g_iDQCount Then $iSelDQ = $g_iDQCount
                        If $iSelDQ < 1 Then $iSelDQ = 1
                        _GUICtrlListBox_SetCurSel($lstDQ, $iSelDQ - 1)
                        _NVDA_Speak(_T("Removed from the download queue."))
                    EndIf
                EndIf

            Case $btnDQClear
                If $g_iDQCount = 0 Then
                    MsgBox(64, _T("Info"), _T("The download queue is already empty."), 0, $hDQGui)
                ElseIf MsgBox(36, _T("Confirm"), _T("Are you sure you want to clear the entire download queue?"), 0, $hDQGui) = 6 Then
                    _DQ_Clear()
                    _DQ_FillList($lstDQ)
                    _GUICtrlListBox_SetCurSel($lstDQ, 0)
                    _NVDA_Speak(_T("The download queue has been cleared."))
                EndIf

            Case $btnDQStart
                If $g_iDQCount = 0 Then
                    MsgBox(64, _T("Info"), _T("The download queue is empty."), 0, $hDQGui)
                    ContinueLoop
                EndIf
                Local $iNameModeDQ = 0
                If GUICtrlRead($chkDQName) = $GUI_CHECKED Then
                    Local $sNameSelDQ = _TR(GUICtrlRead($cboDQName))
                    If $sNameSelDQ = "No numbering and create subdirectory" Then
                        $iNameModeDQ = 1
                    ElseIf $sNameSelDQ = "Numbering" Then
                        $iNameModeDQ = 2
                    ElseIf $sNameSelDQ = "Numbering and create subdirectory" Then
                        $iNameModeDQ = 3
                    EndIf
                EndIf
                _DQ_RunDownloads($hDQGui, _TR(GUICtrlRead($cboDQFormat)), GUICtrlRead($cboDQBitrate), $iNameModeDQ)
                _DQ_FillList($lstDQ)
                _GUICtrlListBox_SetCurSel($lstDQ, 0)
                WinActivate($hDQGui)
                ControlFocus($hDQGui, "", $lstDQ)
        EndSwitch
    WEnd
EndFunc

; $bQueueOnly: play only the play queue (used after a single link ends); then return.
Func _PlayLoop($iCurrentIndex, $bAudioOnly = False, $bQueueOnly = False)
    ; Play queue state: $bFromQueue = the song being played comes from the queue (already removed from it);
    ; $iResumeIndex = where to go back to in the list when the queue is empty.
    Local $bFromQueue = False, $sQID = "", $sQTitle = "", $iResumeIndex = -1
    If $bQueueOnly Then _Queue_TakeNext($bFromQueue, $sQID, $sQTitle, $iCurrentIndex, $iResumeIndex, -1)
    While 1
        Local $sID = "", $sTitle = "", $sType = "video"
        If $bFromQueue Then
            $sID = $sQID
            $sTitle = $sQTitle
        Else
            If $iCurrentIndex < 0 Or $iCurrentIndex >= ($iTotalLoaded) Then ExitLoop
            $sID = $aSearchIds[$iCurrentIndex + 1]
            $sTitle = $aSearchTitles[$iCurrentIndex + 1]
            If UBound($aSearchTypes) > $iCurrentIndex + 1 Then
                If $aSearchTypes[$iCurrentIndex + 1] <> "" Then $sType = $aSearchTypes[$iCurrentIndex + 1]
            EndIf
        EndIf
        _AddHistory($sID, $sTitle, $sType) ; Save to history when playing

        Local $hLoading = 0
        If IsHWnd($hPlayGui) Then
            GUICtrlSetData($g_lblPlayerInfo, _TF("Loading: {1}", $sTitle))
            GUICtrlSetData($g_hStatusLabel, _T("Fetching URL..."))
        Else
            ; Show a small loading popup ONLY if player isn't open yet
            $hLoading = GUICreate(_T("Playing"), 250, 80, -1, -1, BitOR($WS_POPUP, $WS_BORDER), BitOR($WS_EX_TOPMOST, $WS_EX_TOOLWINDOW), $hResultsGui)
            GUICtrlCreateLabel(_T("playing..."), 10, 15, 230, 40, $SS_CENTER)
            GUISetBkColor(0xFFFFFF, $hLoading)
            GUISetState(@SW_SHOW, $hLoading)
            WinActivate($hLoading)
        Sleep(1)
        EndIf

        _AppPlaySoundW(@ScriptDir & "\sounds\loading.wav", 0x0009)
        Local $sFormat = _Ternary($bAudioOnly, "bestaudio/best", "best[ext=mp4]/best/bv*[height<=1080]+ba/b")

        ; Sửa lỗi trích xuất link và hỗ trợ nâng/hạ Tone (Pitch)
        ; Nếu $g_fPitch <> 1.0, chúng ta sẽ dùng ffmpeg làm proxy để xử lý âm thanh thời gian thực
        Local $sParams = '-g -f "' & $sFormat & '" --no-playlist --no-check-certificate --no-warnings --no-mtime --socket-timeout 10 --geo-bypass --extractor-args "youtube:player-client=android,ios" --encoding utf-8'
        Local $sCmd = @ComSpec & ' /c "' & $YT_DLP_EXE & ' ' & $sParams & ' -- "' & $sID & '""'
        Local $pid_url = Run($sCmd, @ScriptDir, @SW_HIDE, $STDOUT_CHILD + $STDERR_CHILD)
        Local $sUrl = "", $sErr = ""
        Local $bCancel = False
        While ProcessExists($pid_url)
            $sUrl &= StdoutRead($pid_url)
            $sErr &= StderrRead($pid_url)
            Local $msg = GUIGetMsg()
            If $msg <> 0 Then
                If $msg = $GUI_EVENT_CLOSE Or ($hDummyEsc And $msg = $hDummyEsc) Or ($hDummyCtrlW And $msg = $hDummyCtrlW) Then
                    $bCancel = True
                    ProcessClose($pid_url)
                    ExitLoop
                ElseIf ($hDummyShiftN And $msg = $hDummyShiftN) Then
                    $bCancel = "NEXT"
                    ProcessClose($pid_url)
                    ExitLoop
                ElseIf ($hDummyShiftB And $msg = $hDummyShiftB) Then
                    $bCancel = "BACK"
                    ProcessClose($pid_url)
                    ExitLoop
                EndIf
            EndIf
            Sleep(10)
        WEnd
        $sUrl &= StdoutRead($pid_url)
        $sErr &= StderrRead($pid_url)

        $sUrl = StringStripWS(StringReplace($sUrl, @CR, ""), 3)
        DllCall("winmm.dll", "int", "PlaySoundW", "ptr", 0, "ptr", 0, "dword", 0)

        If $bCancel = True Then
            If IsHWnd($hLoading) Then GUIDelete($hLoading)
            ExitLoop
        ElseIf $bCancel = "NEXT" Then
            If IsHWnd($hLoading) Then GUIDelete($hLoading)
            If Not _Queue_TakeNext($bFromQueue, $sQID, $sQTitle, $iCurrentIndex, $iResumeIndex, $iCurrentIndex + 1) Then $iCurrentIndex += 1
            ContinueLoop
        ElseIf $bCancel = "BACK" Then
            If IsHWnd($hLoading) Then GUIDelete($hLoading)
            If Not $bFromQueue Then $iCurrentIndex -= 1 ; a song from the queue just starts again
            ContinueLoop
        EndIf

        If $sUrl <> "" And $g_fPitch <> 1.0 Then
            ; Khởi tạo server proxy bằng ffmpeg để xử lý pitch
            ; Chúng ta stream từ URL gốc, qua ffmpeg filter rubberband (hoặc atempo/asetrate) rồi output ra một pipe hoặc local server
            ; Tuy nhiên, cách đơn giản nhất để WMP chơi được là dùng chuẩn mpegts qua stdout và bắt pipe, nhưng WMP ActiveX không hỗ trợ pipe trực tiếp tốt.
            ; Một giải pháp khác là dùng ffmpeg ghi ra một file tạm (buffer) hoặc dùng nut format.
            ; Ở đây, để đảm bảo hoạt động ổn định nhất, chúng ta sẽ trích xuất audio/video rồi dùng ffmpeg filter và truyền link trực tiếp nếu có thể.
            ; Nhưng vì WMP không hỗ trợ filter, chúng ta sẽ thay đổi sUrl thành một lệnh ffmpeg chạy http server mini (nếu có thể) hoặc dùng phương pháp "atempo" giả lập.

            ; CẬP NHẬT: WMP không thể xử lý link pipe. Chúng ta sẽ dùng tính năng 'rate' của WMP nếu chỉ muốn thay đổi tốc độ.
            ; Nếu muốn thay đổi Pitch mà giữ nguyên tốc độ (Rubberband), WMP ActiveX KHÔNG hỗ trợ.
            ; HOWEVER, if the user wants to change Pitch, we can use 'asetrate' combined with 'atempo' in ffmpeg
            ; và output ra một local file hoặc stream.

            ; Do giới hạn của WMP ActiveX, chúng ta sẽ thông báo cho người dùng và tạm thời sử dụng 'rate' của WMP
            ; hoặc thực hiện việc restart stream với tham số filter nếu dùng player khác.
            ; Đối với WMP, cách duy nhất để đổi Pitch (đi kèm đổi tốc độ) là:
            ; $oVLC.Input.Rate = $g_fPitch (nhưng Pitch ở đây là số thực)
        EndIf

        If $sUrl = "" Then
            ; Nếu lỗi, thử xóa cache yt-dlp một lần rồi báo lỗi chi tiết
            Local $iPidRM = Run('"' & $YT_DLP_PATH & '" --rm-cache-dir', @ScriptDir, @SW_HIDE)
            While ProcessExists($iPidRM)
                GUIGetMsg()
                Sleep(10)
            WEnd

            If IsHWnd($hLoading) Then GUIDelete($hLoading)
            Local $sErrMsg = _T("Error 153: YouTube blocked the link extraction request.")
            If _IsWebLink($sID) Then $sErrMsg = _T("Cannot get the stream of this item from its website.")
            If StringInStr($sErr, "sign in") Or StringInStr($sErr, "confirm you are not a bot") Then
                $sErrMsg &= " " & _T("YouTube requires user verification.")
            ElseIf StringInStr($sErr, "age restricted") Then
                $sErrMsg &= " " & _T("Video is age-restricted.")
            Else
                $sErrMsg &= " " & _T("(Warning: YouTube is scanning for bots, please try again in a few minutes).")
            EndIf
            _NVDA_Speak($sErrMsg)
            MsgBox(16, _T("Error"), _TF("{1}\n\nTip: Try opening another video or restart your modem to change IP.", $sErrMsg))
            ExitLoop
        EndIf

        _AppSoundPlay(@ScriptDir & "\sounds\ok.wav")
        Local $sAction = _PlayInternal($sUrl, $sTitle, $bAudioOnly, $hLoading, True, $sID) ; True = Allow AutoPlay toggle

        ; Play queue: when the song ends by itself (or the user asks for the next one) the queue goes first
        If $sAction = "NEXT" Or ($g_bTrackEnded And ($sAction = "FINISHED" Or $sAction = "CLOSE")) Then
            If _Queue_TakeNext($bFromQueue, $sQID, $sQTitle, $iCurrentIndex, $iResumeIndex, $iCurrentIndex + 1) Then ContinueLoop
        EndIf

        If $sAction = "NEXT" Or ($sAction = "FINISHED" And $g_bAutoPlay) Then
            $iCurrentIndex += 1
        ElseIf $sAction = "BACK" Then
            If Not $bFromQueue Then $iCurrentIndex -= 1 ; a song from the queue just starts again
        Elseif $sAction = "RESTART" Then
            ; Do nothing, loop will restart with same index
        Else
            ; "STOP", "CLOSE", or "FINISHED" (if auto-play is off)
            ExitLoop
        EndIf
    WEnd

    If IsHWnd($hPlayGui) Then
        GUISetState(@SW_HIDE, $hPlayGui)
        _VLC_Direct_Stop()
        GUIDelete($hPlayGui)
        $hPlayGui = 0
        $oVLC = 0
    EndIf
EndFunc

; $hParentGui (tùy chọn): cửa sổ đã mở hộp thoại này (ví dụ giao diện Playing khi tải
; nhạc đang nghe). Truyền vào để hộp thoại Download và hộp thoại tiến trình bên trong nó
; thuộc sở hữu (owned) của cửa sổ đó, nhờ vậy Windows sẽ tự động kích hoạt lại đúng cửa
; sổ gốc khi hộp thoại này đóng, thay vì người dùng bị trôi dạt sang một giao diện khác.
Func _ShowDownloadDialog($sID, $sTitle, $hParentGui = 0)
    Local $sUrl = _VideoLink($sID)
    Local $hDLGui = GUICreate(_T("Download Options"), 400, 200, -1, -1, -1, -1, $hParentGui)
    GUISetBkColor($COLOR_BLUE)

    GUICtrlCreateLabel(_T("Select Format :"), 10, 20, 180, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $cboFormat = GUICtrlCreateCombo("", 10, 45, 180, 20, $CBS_DROPDOWNLIST)
    GUICtrlSetTip(-1, _T("Select the download format. Use the arrow keys to browse the list in alphabetical order"))
    GUICtrlSetData(-1, _TL("M4A (Audio)|MP3 (Audio)|MP4 (Video, Best)|OGG (Audio)|WAV (Audio)|WebM (Video)"), _T("MP4 (Video, Best)"))

    GUICtrlCreateLabel(_T("Select Bitrate:"), 210, 20, 180, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $cbo_dl_bitrate_local = GUICtrlCreateCombo("", 210, 45, 180, 20, $CBS_DROPDOWNLIST)
    GUICtrlSetTip(-1, _T("Select the bitrate (kbps). Use the arrow keys to browse from low to high"))
    GUICtrlSetData(-1, _TL("128 kbps|192 kbps|256 kbps|320 kbps"), _T("320 kbps"))

    Local $chk_custom_name = GUICtrlCreateCheckbox(_T("Choose custom output filename composition"), 10, 80, 380, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $cbo_name_type = GUICtrlCreateCombo("", 10, 105, 380, 20, $CBS_DROPDOWNLIST)
    GUICtrlSetTip(-1, _T("Select the file naming style. Use the arrow keys to browse the list in alphabetical order"))
    GUICtrlSetData(-1, _TL("No numbering|No numbering and create subdirectory|Numbering|Numbering and create subdirectory"), _T("No numbering"))
    GUICtrlSetState(-1, $GUI_DISABLE)

    Local $btn_DownloadNow = GUICtrlCreateButton(_T("Download (Alt+D)"), 10, 140, 255, 40)
    Local $btn_CancelNow = GUICtrlCreateButton(_T("Cancel"), 275, 140, 115, 40) ; Cancel next to Download: closes this dialog

    Local $hDummyEscDLNow = GUICtrlCreateDummy()
    Local $aAccelDLNow[2][2] = [["!d", $btn_DownloadNow], ["{ESC}", $hDummyEscDLNow]]
    GUISetAccelerators($aAccelDLNow, $hDLGui)

    GUISetState(@SW_SHOW, $hDLGui)

    While 1
        Local $nMsg = _GuiMsg($hDLGui)
        If $nMsg = $GUI_EVENT_CLOSE Or $nMsg = $hDummyEscDLNow Or $nMsg = $btn_CancelNow Then
            GUIDelete($hDLGui)
            ExitLoop
        ElseIf $nMsg = $chk_custom_name Then
            If GUICtrlRead($chk_custom_name) = $GUI_CHECKED Then
                GUICtrlSetState($cbo_name_type, $GUI_ENABLE)
            Else
                GUICtrlSetState($cbo_name_type, $GUI_DISABLE)
            EndIf
        ElseIf $nMsg = $btn_DownloadNow Then
            Local $sTxt = _TR(GUICtrlRead($cboFormat))
            Local $sBitrate = GUICtrlRead($cbo_dl_bitrate_local)

            Local $sOutTemplate = "%(title)s.%(ext)s"
            If GUICtrlRead($chk_custom_name) = $GUI_CHECKED Then
                Local $sNameSel = _TR(GUICtrlRead($cbo_name_type))
                If $sNameSel = "No numbering and create subdirectory" Then
                    $sOutTemplate = "%(title)s/%(title)s.%(ext)s"
                ElseIf $sNameSel = "Numbering" Then
                    $sOutTemplate = "%(playlist_index)s - %(title)s.%(ext)s"
                ElseIf $sNameSel = "Numbering and create subdirectory" Then
                    $sOutTemplate = "%(playlist_title)s/%(playlist_index)s - %(title)s.%(ext)s"
                EndIf
            EndIf

            Local $sFmt = ""
            If StringInStr($sTxt, "MP3") Then
                $sFmt = "-x --audio-format mp3"
            ElseIf StringInStr($sTxt, "WAV") Then
                $sFmt = "-x --audio-format wav"
            ElseIf StringInStr($sTxt, "M4A") Then
                $sFmt = "-x --audio-format m4a"
            ElseIf StringInStr($sTxt, "OGG") Then
                $sFmt = "-x --audio-format vorbis"
            ElseIf StringInStr($sTxt, "WebM") Then
                $sFmt = "bestvideo+bestaudio --merge-output-format webm"
            Else
                $sFmt = "-f bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best"
            EndIf

            Local $iKbps = StringRegExpReplace($sBitrate, "[^0-9]", "")
            If $iKbps <> "" And (StringInStr($sTxt, "Audio") Or StringInStr($sTxt, "MP3") Or StringInStr($sTxt, "WAV") Or StringInStr($sTxt, "M4A") Or StringInStr($sTxt, "OGG")) Then
                $sFmt &= " --audio-quality " & $iKbps & "k"
            EndIf

            Local $sFinalDownloadPath = $g_sDownloadPath
            If StringStripWS($sFinalDownloadPath, 3) = "" Then $sFinalDownloadPath = @ScriptDir & "\download"
            If Not FileExists($sFinalDownloadPath) Then DirCreate($sFinalDownloadPath)
            While StringRight($sFinalDownloadPath, 1) = "\" Or StringRight($sFinalDownloadPath, 1) = "/"
                $sFinalDownloadPath = StringTrimRight($sFinalDownloadPath, 1)
            WEnd
            Local $sCmd = $YT_DLP_EXE & ' --newline ' & $sFmt & ' -P "' & $sFinalDownloadPath & '" --ffmpeg-location "' & @ScriptDir & '\lib" -o "' & $sOutTemplate & '" -- "' & $sUrl & '"'

            ; Ẩn hộp thoại tùy chọn và mở một hộp thoại tiến trình riêng thay vì
            ; để lại giao diện tùy chọn bị vô hiệu hóa/trống rỗng.
            _AppSoundPlay(@ScriptDir & "\sounds\download-started.wav") ; Âm thanh báo bắt đầu tải
            GUISetState(@SW_HIDE, $hDLGui)
            Local $sDLOut = "", $sDLErr = ""
            Local $sDLSnapshot2 = _ListFilesRecursive($sFinalDownloadPath)
            Local $bDLNowDone = _RunTaskWithProgressDialog($sCmd, _T("Downloading"), _TF("Downloading ""{1}""...", $sTitle), $sDLOut, $sDLErr, $hParentGui, $sFinalDownloadPath, True)
            GUIDelete($hDLGui)
            If Not $bDLNowDone Then
                If IsHWnd($hParentGui) Then WinActivate($hParentGui) ; Đảm bảo quay lại đúng giao diện gốc (vd. Playing) sau khi hủy
                Return
            EndIf
_DLSound_Stop()
_AppSoundPlay(@ScriptDir & "\sounds\download_finish.wav")
            _ShowDownloadCompleteDialog($sFinalDownloadPath, _GetNewDownloadedFiles($sFinalDownloadPath, $sDLSnapshot2))
            ExitLoop
        EndIf
    WEnd
    If IsHWnd($hParentGui) Then WinActivate($hParentGui) ; Đảm bảo quay lại đúng giao diện gốc khi đóng bằng Esc/X
EndFunc

Func playmedia($url)
    _PlayYoutubeLink($url, False)
EndFunc

Func playaudio($url)
    _PlayYoutubeLink($url, True)
EndFunc

; Dùng chung cho "Play" và "Play as Audio" khi người dùng nhập link (hoặc link lấy từ clipboard).
; Lấy link stream giống hệt luồng phát từ kết quả tìm kiếm (_PlayLoop) để phát nhanh và tua mượt:
;  - dùng ID video thay vì nguyên link (bỏ &list=, &t=, &pp=... trong link dán vào),
;  - cùng định dạng và cùng player-client (android, ios) -> nhận được luồng mp4 trực tiếp, tua tốt,
;  - lấy tiêu đề và link stream trong CÙNG MỘT lần gọi yt-dlp (trước đây phải gọi hai lần liên tiếp).
Func _PlayYoutubeLink($url, $bAudioOnly = False)
    $url = StringStripWS($url, 3)
    If _IsSoundCloudLink($url) Then $bAudioOnly = True ; SoundCloud has no video

    ; Update existing player info or show status if GUI exists
    Local $hLoading = 0
    If IsHWnd($hPlayGui) Then
        GUICtrlSetData($g_lblPlayerInfo, _Ternary($bAudioOnly, _T("Loading audio..."), _T("Loading video...")))
        GUICtrlSetData($g_hStatusLabel, _T("Fetching stream URL..."))
    Else
        $hLoading = GUICreate(_T("Playing"), 250, 80, -1, -1, BitOR($WS_POPUP, $WS_BORDER), BitOR($WS_EX_TOPMOST, $WS_EX_TOOLWINDOW))
        GUICtrlCreateLabel(_T("Loading, please wait..."), 10, 25, 230, 30, $SS_CENTER)
        GUISetBkColor(0xFFFFFF, $hLoading)
        GUISetState(@SW_SHOW, $hLoading)
        Sleep(1)
    EndIf

    _AppPlaySoundW(@ScriptDir & "\sounds\loading.wav", 0x0009)

    ; Ưu tiên truyền ID video (giống luồng tìm kiếm); link lạ (không lấy được ID) thì truyền nguyên link
    Local $sTarget = $url
    Local $sVideoID = _GetYoutubeID($url)
    If StringRegExp($sVideoID, "^[A-Za-z0-9_-]{11}$") Then $sTarget = $sVideoID

    Local $sTitle = "", $sDLink = "", $sErr = ""
    Local $bCancel = False

    ; Lần 1: cấu hình giống luồng tìm kiếm. Lần 2 (chỉ khi lần 1 không ra link): cấu hình mặc định của yt-dlp
    For $iTry = 1 To 2
        Local $sFormat, $sClientArg
        If $iTry = 1 Then
            $sFormat = _Ternary($bAudioOnly, "bestaudio/best", "best[ext=mp4]/best/bv*[height<=1080]+ba/b")
            $sClientArg = ' --extractor-args "youtube:player-client=android,ios"'
        Else
            $sFormat = _Ternary($bAudioOnly, "bestaudio/best", "best/bv*[height<=1080]+ba/b")
            $sClientArg = ''
        EndIf

        Local $sCmd = @ComSpec & ' /c "' & $YT_DLP_EXE & ' --print title --print urls -f "' & $sFormat & '" --no-playlist --no-check-certificate --no-warnings --no-mtime --socket-timeout 10 --geo-bypass' & $sClientArg & ' --encoding utf-8 -- "' & $sTarget & '""'
        Local $pid = Run($sCmd, @ScriptDir, @SW_HIDE, $STDOUT_CHILD + $STDERR_CHILD)
        Local $bData = Binary("")
        $sErr = ""
        While ProcessExists($pid)
            $bData &= StdoutRead($pid, False, True)
            $sErr &= StderrRead($pid)
            Local $msg = GUIGetMsg()
            If $msg <> 0 Then
                If $msg = $GUI_EVENT_CLOSE Or ($hDummyEsc And $msg = $hDummyEsc) Or ($hDummyCtrlW And $msg = $hDummyCtrlW) Then
                    $bCancel = True
                    ProcessClose($pid)
                    ExitLoop
                EndIf
            EndIf
            Sleep(10)
        WEnd
        If $bCancel Then ExitLoop
        $bData &= StdoutRead($pid, False, True)
        $sErr &= StderrRead($pid)

        ; Dòng đầu = tiêu đề, các dòng sau = link stream (1 dòng, hoặc 2 dòng video + audio)
        Local $aLines = StringSplit(StringReplace(BinaryToString($bData, 4), @CR, ""), @LF, 2)
        $sTitle = ""
        $sDLink = ""
        If UBound($aLines) > 1 Then
            $sTitle = StringStripWS($aLines[0], 3)
            For $i = 1 To UBound($aLines) - 1
                Local $sLine = StringStripWS($aLines[$i], 3)
                If $sLine <> "" Then $sDLink &= ($sDLink = "" ? "" : @LF) & $sLine
            Next
        EndIf
        If $sDLink <> "" Then ExitLoop
    Next

    DllCall("winmm.dll", "int", "PlaySoundW", "ptr", 0, "ptr", 0, "dword", 0)

    If $bCancel Then
        If $hLoading <> 0 Then GUIDelete($hLoading)
        Return
    EndIf

    If $sDLink <> "" Then
        _AppSoundPlay(@ScriptDir & "\sounds\ok.wav")
        Local $id = _GetYoutubeID($url)
        If $id = "" And _IsWebLink($url) Then $id = $url ; other sites: the full link is the id (like the search results)
        Local $sPlayAct = ""
        Local $bSC = _IsSoundCloudLink($url) ; the window title (read by NVDA+T) names the site
        If $bAudioOnly Then
            If $sTitle = "" Then $sTitle = _Ternary($bSC, _T("SoundCloud Audio"), _T("YouTube Audio"))
            _AddHistory($id, $sTitle)
            $sPlayAct = _PlayInternal($sDLink, _Ternary($bSC, _T("SoundCloud Audio Player"), _T("YouTube Audio Player")), True, $hLoading, False, $id)
        Else
            If $sTitle = "" Then $sTitle = _T("YouTube Video")
            _AddHistory($id, $sTitle)
            $sPlayAct = _PlayInternal($sDLink, $sTitle, False, $hLoading, False, $id)
        EndIf
        ; Songs added to the play queue while this link was playing: they play when it ends by itself
        If $g_iQueueCount > 0 And ($sPlayAct = "NEXT" Or ($g_bTrackEnded And ($sPlayAct = "FINISHED" Or $sPlayAct = "CLOSE"))) Then _PlayLoop(-1, $bAudioOnly, True)
    Else
        If $hLoading <> 0 Then GUIDelete($hLoading)
        Local $sErrMsg = _Ternary($bAudioOnly, _T("Cannot get audio stream from this link."), _T("Cannot get video stream from this link."))
        If $sErr <> "" Then $sErrMsg &= " " & _TF("Details: {1}", StringLeft(StringStripWS($sErr, 3), 100))
        MsgBox(16, _T("Error"), $sErrMsg)
    EndIf
EndFunc

Func _ListenToAudioFile()
    Local $hChooseGui = GUICreate(_T("Listen to Audio"), 380, 210, -1, -1, BitOR($WS_CAPTION, $WS_SYSMENU))
    GUISetBkColor($COLOR_BLUE)

    GUICtrlCreateLabel(_T("Choose how you want to load audio:"), 10, 15, 360, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)

    Local $btn_AddFile = GUICtrlCreateButton(_T("Add File... (Alt+F)"), 40, 50, 300, 40)
    Local $btn_AddFolder = GUICtrlCreateButton(_T("Add Folder... (Alt+D)"), 40, 100, 300, 40)
    Local $btn_CloseChoose = GUICtrlCreateButton(_T("Close"), 40, 155, 300, 35)

    Local $hDummyEscChoose = GUICtrlCreateDummy()
    Local $aAccelChoose[3][2] = [["!f", $btn_AddFile], ["!d", $btn_AddFolder], ["{ESC}", $hDummyEscChoose]]
    GUISetAccelerators($aAccelChoose, $hChooseGui)

    GUISetState(@SW_SHOW, $hChooseGui)
    _AllowUIPI($hChooseGui)

    While 1
        Local $nMsg = _GuiMsg($hChooseGui)
        Switch $nMsg
            Case $GUI_EVENT_CLOSE, $btn_CloseChoose, $hDummyEscChoose
                GUIDelete($hChooseGui)
                ExitLoop

            Case $btn_AddFile
                GUIDelete($hChooseGui)
                _AddSingleAudioFile()
                ExitLoop

            Case $btn_AddFolder
                GUIDelete($hChooseGui)
                _AddAudioFolder()
                ExitLoop
        EndSwitch
    WEnd
EndFunc

; "Add File": pick a single audio (or .mp4) file and just play that one file.
; No n/b navigation here - this is a single-track playback.
Func _AddSingleAudioFile()
    Local $sFilter = "Supported Media Files (*.mp3;*.m4a;*.wav;*.ogg;*.flac;*.aac;*.wma;*.opus;*.mp4)|" & _
        "MP3 Audio (*.mp3)|M4A Audio (*.m4a)|WAV Audio (*.wav)|OGG Audio (*.ogg)|" & _
        "FLAC Audio (*.flac)|AAC Audio (*.aac)|WMA Audio (*.wma)|OPUS Audio (*.opus)|MP4 Video/Audio (*.mp4)"
    Local $sFile = FileOpenDialog(_T("Select an audio file to listen to"), @MyDocumentsDir, $sFilter, 1)
    If @error Then Return ; user cancelled the dialog

    ; Defensive validation, in case the user typed a filename with an unsupported extension
    Local $aExtMatch = StringRegExp($sFile, "\.([A-Za-z0-9]+)$", 3)
    Local $sExt = (UBound($aExtMatch) > 0) ? StringLower($aExtMatch[0]) : ""
    If Not StringInStr($g_sSupportedAudioExts, "." & $sExt & ";") Then
        MsgBox(16, _T("Unsupported Format"), _T("This audio format is not supported.") & @CRLF & _T("Supported formats: MP3, M4A, WAV, OGG, FLAC, AAC, WMA, OPUS, MP4."))
        Return
    EndIf

    _PlayLocalAudioFile($sFile)
EndFunc

; Phát MỘT file cục bộ bằng giao diện "Listen to Audio File" (không có phím n/b).
; Dùng chung cho "Add File..." và nút Play trong hộp thoại tải xuống hoàn tất.
Func _PlayLocalAudioFile($sFile)
    ; Get file name (without path/extension) to use as the track title
    Local $aNameMatch = StringRegExp($sFile, "([^\\\/]+)$", 3)
    Local $sTitle = (UBound($aNameMatch) > 0) ? $aNameMatch[0] : $sFile
    $sTitle = StringRegExpReplace($sTitle, "\.[A-Za-z0-9]+$", "")

    _Recent_AddFile($sFile)

    ; Single file loaded directly - n/b navigation must stay OFF
    $g_bLocalPlaylistMode = False

    Local $hLoading = 0
    If Not IsHWnd($hPlayGui) Then
        $hLoading = GUICreate(_T("Playing"), 250, 80, -1, -1, BitOR($WS_POPUP, $WS_BORDER), BitOR($WS_EX_TOPMOST, $WS_EX_TOOLWINDOW))
        GUICtrlCreateLabel(_T("Loading audio file, please wait..."), 10, 25, 230, 30, $SS_CENTER)
        GUISetBkColor(0xFFFFFF, $hLoading)
        GUISetState(@SW_SHOW, $hLoading)
        _AppPlaySoundW(@ScriptDir & "\sounds\loading.wav", 0x0009)
        Sleep(30)
    Else
        GUICtrlSetData($g_lblPlayerInfo, _T("Loading audio file..."))
        GUICtrlSetData($g_hStatusLabel, _TF("Loading {1}...", $sTitle))
    EndIf

    _PlayInternal($sFile, $sTitle, True, $hLoading, False, $sFile, True)
EndFunc

; "Add Folder": scan a folder for supported audio files and start a playlist.
; While this playlist is playing, "n" = next file, "b" = previous file.
Func _AddAudioFolder()
    Local $sFolder = FileSelectFolder(_T("Select a folder containing audio files"), @MyDocumentsDir)
    If @error Then Return ; user cancelled the dialog
    _OpenAudioFolder($sFolder, "")
EndFunc

; Quet thu muc va phat danh sach. $sStartFile = bai bat dau (vd bai dang nghe do lan truoc), "" = bai dau tien.
Func _OpenAudioFolder($sFolder, $sStartFile = "")
    While StringLen($sFolder) > 3 And StringRight($sFolder, 1) = "\"
        $sFolder = StringTrimRight($sFolder, 1)
    WEnd

    ReDim $g_aLocalPlaylist[1]
    $g_iLocalPlaylistCount = 0

    Local $sSearch = FileFindFirstFile($sFolder & "\*.*")
    If $sSearch = -1 Then
        MsgBox(48, _T("Empty Folder"), _T("No files were found in the selected folder."))
        Return
    EndIf

    While 1
        Local $sName = FileFindNextFile($sSearch)
        If @error Then ExitLoop

        ; @extended = 1 means this entry is a subfolder - skip it, only look
        ; at files directly inside the chosen folder
        If @extended Then ContinueLoop

        Local $aExtMatch = StringRegExp($sName, "\.([A-Za-z0-9]+)$", 3)
        Local $sExt = (UBound($aExtMatch) > 0) ? StringLower($aExtMatch[0]) : ""
        If StringInStr($g_sSupportedAudioExts, "." & $sExt & ";") Then
            $g_iLocalPlaylistCount += 1
            ReDim $g_aLocalPlaylist[$g_iLocalPlaylistCount]
            $g_aLocalPlaylist[$g_iLocalPlaylistCount - 1] = $sFolder & "\" & $sName
        EndIf
    WEnd
    FileClose($sSearch)

    If $g_iLocalPlaylistCount = 0 Then
        MsgBox(48, _T("No Audio Files"), _T("No supported audio files were found in this folder.") & @CRLF & _T("Supported formats: MP3, M4A, WAV, OGG, FLAC, AAC, WMA, OPUS, MP4."))
        Return
    EndIf

    _ArraySort($g_aLocalPlaylist)

    $g_sLocalPlaylistFolder = $sFolder
    _Recent_AddFolder($sFolder, "")
    Local $iStartIdx = 0
    If $sStartFile <> "" Then
        For $i = 0 To $g_iLocalPlaylistCount - 1
            If StringLower($g_aLocalPlaylist[$i]) = StringLower($sStartFile) Then
                $iStartIdx = $i
                ExitLoop
            EndIf
        Next
    EndIf

    $g_bLocalPlaylistMode = True
    _PlayLocalFolder($iStartIdx)
    $g_sLocalPlaylistFolder = ""
EndFunc

; Drives playback through a folder-loaded playlist. Pressing "n" inside the
; player moves to the next file, "b" moves to the previous one; the track
; also auto-advances to the next file when one finishes (unless Repeat is on).
Func _PlayLocalFolder($iIndex)
    While 1
        If $iIndex < 0 Then
            ; Before the first track (pressed 'b' at the first track) - wrap around to the last track
            _ReportStatus(_T("Back to the last track"))
            $iIndex = $g_iLocalPlaylistCount - 1
        ElseIf $iIndex >= $g_iLocalPlaylistCount Then
            ; Past the last track - wrap around and play the first track again
            _ReportStatus(_T("Back to the first track"))
            $iIndex = 0
        EndIf

        Local $sFile = $g_aLocalPlaylist[$iIndex]
        Local $aNameMatch = StringRegExp($sFile, "([^\\\/]+)$", 3)
        Local $sTitle = (UBound($aNameMatch) > 0) ? $aNameMatch[0] : $sFile
        $sTitle = StringRegExpReplace($sTitle, "\.[A-Za-z0-9]+$", "")

        If $g_sLocalPlaylistFolder <> "" Then _Recent_AddFolder($g_sLocalPlaylistFolder, $sFile) ; nho bai dang nghe cua thu muc

        Local $hLoading = 0
        If Not IsHWnd($hPlayGui) Then
            $hLoading = GUICreate(_T("Playing"), 250, 80, -1, -1, BitOR($WS_POPUP, $WS_BORDER), BitOR($WS_EX_TOPMOST, $WS_EX_TOOLWINDOW))
            GUICtrlCreateLabel(_T("Loading audio file, please wait..."), 10, 25, 230, 30, $SS_CENTER)
            GUISetBkColor(0xFFFFFF, $hLoading)
            GUISetState(@SW_SHOW, $hLoading)
            _AppPlaySoundW(@ScriptDir & "\sounds\loading.wav", 0x0009)
            Sleep(30)
        Else
            GUICtrlSetData($g_lblPlayerInfo, _T("Loading audio file..."))
            GUICtrlSetData($g_hStatusLabel, _TF("Loading {1}...", $sTitle))
        EndIf

        $g_bLocalPlaylistMode = True ; keep n/b navigation enabled through the whole session
        Local $sAction = _PlayInternal($sFile, $sTitle, True, $hLoading, False, $sFile, True)

        If $sAction = "NEXT" Or $sAction = "FINISHED" Then
            $iIndex += 1
        ElseIf $sAction = "BACK" Then
            $iIndex -= 1
        ElseIf $sAction = "FIRST" Then
            $iIndex = 0
        ElseIf $sAction = "LAST" Then
            $iIndex = $g_iLocalPlaylistCount - 1
        ElseIf $sAction = "RESTART" Then
            ; Repeat is on - stay on the same track
        Else
            ; "STOP" / "CLOSE"
            ExitLoop
        EndIf
    WEnd

    $g_bLocalPlaylistMode = False
EndFunc

Func _PlayInternal($sUrl, $sTitle, $bAudioOnly = False, $hLoading = 0, $allowAutoPlayToggle = False, $sID = "", $bLocalFile = False, $bPodcast = False)
    $g_bTrackEnded = False
    Local $bPod = $bPodcast
    If $bPod Then $bLocalFile = True ; podcast episodes use the same guards as local audio files (no YouTube-only features)
    Local $iWidth = 640, $iHeight = 360
    Local $aHelpLines = 0
    If $bAudioOnly Then
        ; Audio only: there is no video, so the black area shows an on-screen keyboard guide
        $aHelpLines = _GetPlayerHelpLines($bLocalFile, $allowAutoPlayToggle)
        $iWidth = 560
        $iHeight = Ceiling(UBound($aHelpLines) / 2) * 17 + 40
        If $iHeight < 150 Then $iHeight = 150
    EndIf
    Local $iStripH = ($bAudioOnly ? 92 : 114) ; height of the text strip under the video area

    If Not IsHWnd($hPlayGui) Then
        $g_sCurrentVideoTitle = $sTitle
        ; Sử dụng style tiêu chuẩn hơn để Menu Bar hiển thị tốt nhất
        $hPlayGui = GUICreate($sTitle, $iWidth, $iHeight + $iStripH, -1, -1, BitOR($WS_OVERLAPPEDWINDOW, $WS_CLIPCHILDREN), $WS_EX_TOPMOST)

        ; Tạo loading dialog NGAY TẠI ĐÂY nếu chưa có
        If $hLoading = 0 Then
            $hLoading = GUICreate(_T("Playing"), 250, 80, -1, -1, BitOR($WS_POPUP, $WS_BORDER), BitOR($WS_EX_TOPMOST, $WS_EX_TOOLWINDOW), $hPlayGui)
            GUICtrlCreateLabel(_T("Loading stream, please wait..."), 10, 25, 230, 30, $SS_CENTER)
            GUISetBkColor(0xFFFFFF, $hLoading)
            GUISetState(@SW_SHOW, $hLoading)

            ; Phát âm thanh loading
            _AppPlaySoundW(@ScriptDir & "\sounds\loading.wav", 0x0009)
        EndIf

        GUISetBkColor(0x000000, $hPlayGui)
        GUISwitch($hPlayGui)

        ; Tạo Menu Bar - Không dùng biến Local để tránh nhầm lẫn, dùng biến Global đã khai báo
        ; (Local audio files: no Options menu bar for this feature)
        $menu_item_chapters = -1
        $menu_item_voice = -1
        If $bPod Then
            Local $hMenu_PodOptions = GUICtrlCreateMenu(_T("&Options"))
            $menu_item_copy = GUICtrlCreateMenuItem(_T("Copy Lin&k..."), $hMenu_PodOptions)
            $menu_item_goto = GUICtrlCreateMenuItem(_T("&Go to Time... (Ctrl+G)"), $hMenu_PodOptions)
            $menu_item_chapters = GUICtrlCreateMenuItem(_T("Chapters... (H)"), $hMenu_PodOptions)
            $menu_item_voice = GUICtrlCreateMenuItem(_T("Voice enhancement... (Ctrl+Shift+V)"), $hMenu_PodOptions)
            GUICtrlCreateMenuItem("", $hMenu_PodOptions) ; Separator
            $menu_item_sleeptimer = GUICtrlCreateMenuItem(_T("Sleep T&imer..."), $hMenu_PodOptions)
            $menu_item_download = -1
            $menu_item_channel = -1
            $menu_item_yt_sub = -1
            $menu_item_browser = -1
            $menu_share_telegram = -1
            $menu_share_facebook = -1
            $menu_item_desc = -1
            $menu_item_comments = -1
            $menu_item_transcript = -1
            $menu_item_lyrics = -1
            $menu_item_queue_add = -1
            $menu_item_queue_view = -1
            $menu_item_dq_add = -1
            $menu_item_fav = -1
            $menu_item_add_col = -1
            $menu_item_remove_col = -1
            $menu_item_fileinfo = -1
            _GUICtrlMenu_DrawMenuBar($hPlayGui)
        ElseIf Not $bLocalFile Then
            Local $hMenu_Options = GUICtrlCreateMenu(_T("&Options"))
            $menu_item_download = GUICtrlCreateMenuItem(_T("&Download..."), $hMenu_Options)
            $menu_item_channel = GUICtrlCreateMenuItem(_T("Go to &Channel..."), $hMenu_Options)
            $menu_item_yt_sub = GUICtrlCreateMenuItem(_T("S&ubscribe to Channel..."), $hMenu_Options)
            $menu_item_browser = GUICtrlCreateMenuItem(_T("Open in &Browser..."), $hMenu_Options)
            $menu_item_copy = GUICtrlCreateMenuItem(_T("Copy Lin&k..."), $hMenu_Options)

            Local $hMenu_Share = GUICtrlCreateMenu(_T("&Share"), $hMenu_Options)
            $menu_share_telegram = GUICtrlCreateMenuItem(_T("&Telegram"), $hMenu_Share)
            $menu_share_facebook = GUICtrlCreateMenuItem(_T("&Facebook"), $hMenu_Share)

            $menu_item_desc = GUICtrlCreateMenuItem(_T("&Video Description..."), $hMenu_Options)
            $menu_item_comments = GUICtrlCreateMenuItem(_T("Video Com&ments..."), $hMenu_Options)
            $menu_item_transcript = GUICtrlCreateMenuItem(_T("Video &Transcript... (Ctrl+Alt+T)"), $hMenu_Options)
            $menu_item_lyrics = GUICtrlCreateMenuItem(_T("View &Lyrics... (Ctrl+Alt+L)"), $hMenu_Options)
            $menu_item_queue_add = GUICtrlCreateMenuItem(_T("Add to &queue... (Ctrl+Q)"), $hMenu_Options)
            $menu_item_queue_view = GUICtrlCreateMenuItem(_T("&Play queue... (Ctrl+Shift+Q)"), $hMenu_Options)
            $menu_item_dq_add = GUICtrlCreateMenuItem(_T("Add to do&wnload queue..."), $hMenu_Options)

            Local $sFavText = _Ternary(_IsFavorite($sID), _T("&Remove from Favorite..."), _T("Add to &Favorite..."))
            $menu_item_fav = GUICtrlCreateMenuItem($sFavText, $hMenu_Options)

            If _IsVideoInAnyCollection($sID) Then
                $menu_item_remove_col = GUICtrlCreateMenuItem(_T("&Remove from Collection"), $hMenu_Options)
                $menu_item_add_col = -1
            Else
                $menu_item_add_col = GUICtrlCreateMenuItem(_T("&Add to Collection..."), $hMenu_Options)
                $menu_item_remove_col = -1
            EndIf

            $menu_item_goto = GUICtrlCreateMenuItem(_T("&Go to Time... (Ctrl+G)"), $hMenu_Options)
            $menu_item_fileinfo = -1 ; File Information removed from the online listening interface

            ; NEW FEATURE Tính năng Sleep Timer vào Menu
            GUICtrlCreateMenuItem("", $hMenu_Options) ; Separator
            $menu_item_chapters = GUICtrlCreateMenuItem(_T("Chapters... (H)"), $hMenu_Options)
            $menu_item_voice = GUICtrlCreateMenuItem(_T("Voice enhancement... (Ctrl+Shift+V)"), $hMenu_Options)
            $menu_item_sleeptimer = GUICtrlCreateMenuItem(_T("Sleep T&imer..."), $hMenu_Options)

            ; Vẽ lại thanh menu để đảm bảo hiển thị
            _GUICtrlMenu_DrawMenuBar($hPlayGui)
        Else
            $menu_item_download = -1
            $menu_item_channel = -1
            $menu_item_yt_sub = -1
            $menu_item_browser = -1
            $menu_item_copy = -1
            $menu_share_telegram = -1
            $menu_share_facebook = -1
            $menu_item_desc = -1
            $menu_item_comments = -1
            $menu_item_transcript = -1
            $menu_item_lyrics = -1
            $menu_item_queue_add = -1
            $menu_item_queue_view = -1
            $menu_item_dq_add = -1
            $menu_item_fav = -1
            $menu_item_add_col = -1
            $menu_item_remove_col = -1
            $menu_item_goto = -1
            $menu_item_fileinfo = -1
            $menu_item_sleeptimer = -1
        EndIf

        ; Sử dụng phương thức gọi DLL trực tiếp (Direct libvlc) để tránh NVDA đọc %
        If Not _VLC_Direct_Init() Then
            if $hLoading <> 0 Then GUIDelete($hLoading)
            MsgBox(16, _T("Error"), _T("Could not initialize libvlc.dll. Please ensure VLC DLLs are present in the lib folder."))
            GUIDelete($hPlayGui)
            $hPlayGui = 0
            Return ""
        EndIf

        ; Tạo một cửa sổ con giả để VLC có thể render nếu cần (nhưng không dùng ActiveX)
        $oVLCCtrl = GUICtrlCreateLabel("", 0, 0, $iWidth, $iHeight)
        Local $hVlcContainer = GUICtrlGetHandle($oVLCCtrl)
        DllCall($hVLC_Dll, "none:cdecl", "libvlc_media_player_set_hwnd", "ptr", $oVLC_Player, "hwnd", $hVlcContainer)

        ; Text strip under the video area: title, state/position, last action, repeat/auto
        $g_lblPlayerInfo = GUICtrlCreateLabel(_TF("Playing: {1}", $sTitle), 10, $iHeight + 4, $iWidth - 20, 40, $SS_NOPREFIX)
        GUICtrlSetFont(-1, 11, 800, 0, "Segoe UI")
        GUICtrlSetColor(-1, 0xFFFFFF)

        $g_lblTimeInfo = GUICtrlCreateLabel("", 10, $iHeight + 48, $iWidth - 20, 20, $SS_NOPREFIX)
        GUICtrlSetFont(-1, 10, 800, 0, "Segoe UI")
        GUICtrlSetColor(-1, 0x00FF00)
        GUICtrlSetState(-1, $GUI_HIDE) ; Ẩn dòng "Playing  00:00/00:00  Volume: xx%  Speed: x.xx" theo yêu cầu
        $g_sLastTimeInfo = ""
        $g_lblHint = 0

        ; Kept disabled on purpose: it is used for focus masking (ControlFocus)
        $g_hStatusLabel = GUICtrlCreateLabel("", 10, $iHeight + 70, $iWidth - 190, 20)
        GUICtrlSetState(-1, $GUI_DISABLE)
        GUICtrlSetFont(-1, 10, 800)
        GUICtrlSetColor(-1, 0xFFFF00)

        $g_lblRepeat = GUICtrlCreateLabel(_T("Repeat: OFF"), $iWidth - 170, $iHeight + 70, 80, 18)
        GUICtrlSetColor(-1, 0xFFFF00)
        GUICtrlSetState(-1, $GUI_HIDE) ; Ẩn dòng "Repeat: OFF/ON" theo yêu cầu

        $g_lblAuto = GUICtrlCreateLabel(_T("Auto: ON"), $iWidth - 80, $iHeight + 70, 70, 18)
        GUICtrlSetColor(-1, 0xFFFF00)

        GUISetState(@SW_SHOW, $hPlayGui)

        ; Initialize Hidden Controls and Accelerators
        $hDummySpace = GUICtrlCreateDummy()
        $hDummyEnter = GUICtrlCreateDummy()
        $hDummyN = GUICtrlCreateDummy()
        $hDummyB = GUICtrlCreateDummy() ; "b": previous file (folder playlist only)
        $hDummyUp = GUICtrlCreateDummy()
        $hDummyDown = GUICtrlCreateDummy()
        $hDummyLeft = GUICtrlCreateDummy()
        $hDummyRight = GUICtrlCreateDummy()
        $hDummyCtrlLeft = GUICtrlCreateDummy()
        $hDummyCtrlRight = GUICtrlCreateDummy()
        $hDummyCtrlT = GUICtrlCreateDummy()
        $hDummyCtrlShiftT = GUICtrlCreateDummy()
        $hDummyHome = GUICtrlCreateDummy()
        $hDummyEnd = GUICtrlCreateDummy()
        $hDummy1 = GUICtrlCreateDummy()
        $hDummy2 = GUICtrlCreateDummy()
        $hDummy3 = GUICtrlCreateDummy()
        $hDummy4 = GUICtrlCreateDummy()
        $hDummy5 = GUICtrlCreateDummy()
        $hDummy6 = GUICtrlCreateDummy()
        $hDummy7 = GUICtrlCreateDummy()
        $hDummy8 = GUICtrlCreateDummy()
        $hDummy9 = GUICtrlCreateDummy()
        $hDummyP = GUICtrlCreateDummy()

        $hDummyR = GUICtrlCreateDummy()
        $hDummyRemaining = GUICtrlCreateDummy()
        $hDummyShiftN = GUICtrlCreateDummy()
        $hDummyShiftB = GUICtrlCreateDummy()
        $hDummyCtrlW = GUICtrlCreateDummy()
        $hDummyMinus = GUICtrlCreateDummy()
        $hDummyEqual = GUICtrlCreateDummy()
        $hDummyS = GUICtrlCreateDummy()
        $hDummyD = GUICtrlCreateDummy()
        $hDummyF = GUICtrlCreateDummy()
        $hDummyCtrlShiftE = GUICtrlCreateDummy()
        $hDummyEsc = GUICtrlCreateDummy()
        $hDummyG = GUICtrlCreateDummy()
        $hDummyAltO = GUICtrlCreateDummy() ; Dùng để gọi Menu an toàn

        $hDummyAltB = GUICtrlCreateDummy() ; Alt+B: Open Browser
        $hDummyAltG = GUICtrlCreateDummy() ; Alt+G: Go Channel
        $hDummyAltLeft = GUICtrlCreateDummy() ; Alt+Left: Rewind 1 minute
        $hDummyAltRight = GUICtrlCreateDummy() ; Alt+Right: Forward 1 minute

        ; New hotkeys for selection and actions
        $hDummyBracketLeft = GUICtrlCreateDummy()
        $hDummyBracketRight = GUICtrlCreateDummy()
        $hDummyCtrlS = GUICtrlCreateDummy()
        $hDummyCtrlK = GUICtrlCreateDummy()
        $hDummyCtrlC = GUICtrlCreateDummy()
        $hDummyCtrlShiftC = GUICtrlCreateDummy()
        $hDummyCtrlShiftD = GUICtrlCreateDummy() ; Ctrl+Shift+D: Description

        ; Re-initialize empty Dummy as a "black hole" to block Right-Click Menu / Shift+F10
        $hDummyApps = GUICtrlCreateDummy()

        ; "I" key: show information about the currently playing file
        $hDummyI = GUICtrlCreateDummy()

        ; "C" key: copy the title of the current track to the clipboard (no dialog)
        $hDummyC = GUICtrlCreateDummy()

        ; Ctrl+Home / Ctrl+End: jump to first/last track (folder playlist only)
        $hDummyCtrlHome = GUICtrlCreateDummy()
        $hDummyCtrlEnd = GUICtrlCreateDummy()

        ; Ctrl+Alt+T: mở Video Transcript
        $hDummyCtrlAltT = GUICtrlCreateDummy()

        ; Ctrl+Alt+L: View Lyrics
        $hDummyCtrlAltL = GUICtrlCreateDummy()

        ; Ctrl+Q: add this song to the play queue / Ctrl+Shift+Q: open the play queue
        $hDummyCtrlQ = GUICtrlCreateDummy()
        $hDummyCtrlShiftQ = GUICtrlCreateDummy()
        $hDummyEq = GUICtrlCreateDummy() ; Ctrl+E: Equalizer
        $hDummyChapNext = GUICtrlCreateDummy() ; Page Down: next chapter
        $hDummyChapPrev = GUICtrlCreateDummy() ; Page Up: previous chapter
        $hDummyChapList = GUICtrlCreateDummy() ; H: list of chapters
        $hDummyVoice = GUICtrlCreateDummy() ; Ctrl+Shift+V: voice enhancement

        ; Phim co dinh (1-9 = nhay den 10%-90%, phim Menu chuot phai bi chan) + phim tuy chinh (Settings > Shortcuts)
        Local $aFixedPlay[11][2] = [ _
            ["1", $hDummy1], ["2", $hDummy2], ["3", $hDummy3], ["4", $hDummy4], ["5", $hDummy5], _
            ["6", $hDummy6], ["7", $hDummy7], ["8", $hDummy8], ["9", $hDummy9], _
            ["{APPSKEY}", $hDummyApps], ["+{F10}", $hDummyApps] _
        ]
        _HK_SetPlayerHandles()
        Local $aAccelPlay = _HK_BuildTable("player", $aFixedPlay)
        GUISetAccelerators($aAccelPlay, $hPlayGui)
    Else
        $g_sCurrentVideoTitle = $sTitle
        WinSetTitle($hPlayGui, "", $sTitle)
        GUICtrlSetData($g_lblPlayerInfo, _TF("Playing: {1}", $sTitle))
        $g_sLastTimeInfo = ""
    EndIf

    ; Reset selection on new track
    $g_fSelectionStart = -1
    $g_fSelectionEnd = -1

    ; Clear any pending messages before starting
    While GUIGetMsg() <> 0
        Sleep(10)
    WEnd

    ; Use direct DLL calls to play music (Prevents NVDA from reading percentage)
    If $bLocalFile And Not $bPod Then
        _VLC_Direct_Play(_PathToFileURI($sUrl))
    Else
        _VLC_Direct_Play($sUrl)
    EndIf
    If $hLoading = 0 Then
        GUICtrlSetData($g_hStatusLabel, _T("Loading stream..."))
        _AppPlaySoundW(@ScriptDir & "\sounds\loading.wav", 0x0009) ; SND_FILENAME | SND_ASYNC
    EndIf

    ; Give some time for stream to initialize to prevent early interruption
    Sleep(200)
    _VLC_Direct_SetVolume($g_iAppVolume)
    _VLC_Direct_SetRate($g_fPitch)
    _VLC_ApplyEqualizer() ; the audio output exists by now: make sure the equalizer preset is active
    _VLC_ApplyStereoMode() ; same for the audio channel mode; _VLC_StereoMode_Retry in the loop re-applies it if VLC dropped it

    ; --- Logic Tiếp tục xem (Continue Watching) ---
    Local $bResumeOn = $bLocalFile ? $g_bResumeLocal : $g_bContinueWatching
    If $bPod Then $bResumeOn = True ; podcast episodes always remember their position
    If $bResumeOn Then
        Local $iSavedTime = $bLocalFile ? _LocalPos_Get($sID) : _GetPlaybackPosition($sID)
        If $iSavedTime > 0 Then
            Local $iWaitCount = 0
            While $iWaitCount < 50
                If _VLC_Direct_GetState() >= 3 Then ExitLoop ; 3=Playing, 4=Paused
                Sleep(100)
                $iWaitCount += 1
            WEnd
            _VLC_Direct_SetTime($iSavedTime)
            _ReportStatus(_TF("Continuing from {1}", _FormatTime($iSavedTime / 1000)))
        EndIf
    EndIf
    ; -------------------------------------------

    If (Not $allowAutoPlayToggle) Or (Not $g_bAutoPlay) Then GUICtrlSetState($g_lblAuto, $GUI_HIDE)
    If $allowAutoPlayToggle And $g_bAutoPlay Then
        GUICtrlSetState($g_lblAuto, $GUI_SHOW)
        GUICtrlSetData($g_lblAuto, _T("Auto: ON"))
    EndIf
    If $allowAutoPlayToggle And Not $g_bAutoPlay Then
        GUICtrlSetState($g_lblAuto, $GUI_SHOW)
        GUICtrlSetData($g_lblAuto, _T("Auto: OFF"))
    EndIf

    If Not $g_bRepeat Then GUICtrlSetData($g_lblRepeat, _T("Repeat: OFF"))
    If $g_bRepeat Then GUICtrlSetData($g_lblRepeat, _T("Repeat: ON"))

    ; Chapters (version 3.3): YouTube / other sites with yt-dlp, local files with ffmpeg. Podcast chapters are set by the podcast window.
    If Not $bPod Then
        If $bLocalFile Then
            _Chap_StartFile($sUrl)
        Else
            _Chap_StartOnline($sID)
        EndIf
    EndIf

    Local $sAction = ""
    Local $bLoaded = False
    Local $iLoadStartTime = TimerInit()
    Local $hInfoTimer = 0 ; drives the on-screen state/position line
    Local $hPosSaveTimer = TimerInit() ; luu vi tri nghe dang do cua file cuc bo moi 10 giay

    While 1
        Local $nMsg = GUIGetMsg()

        ; NEW FEATURE Logic kiểm tra hẹn giờ tắt nhạc (Sleep Timer) tắt và thoát toàn phần mềm
        _SleepTimer_Tick() ; sleep timer (with optional fade-out), shared with the Radio

        If $nMsg <> 0 Then
        Switch $nMsg
            Case $GUI_EVENT_CLOSE
                $sAction = "CLOSE"
                ExitLoop

            ; NEW FEATURE Xử lý nhấp chuột vào Menu Sleep Timer
            Case $menu_item_sleeptimer
                _ShowSleepTimerDialog()

            Case $menu_item_download
                If $bLocalFile Then
                    _ReportStatus(_T("This file is already on your device."))
                Else
                    _ShowDownloadDialog($sID, $sTitle, $hPlayGui)
                EndIf
            Case $menu_item_yt_sub
                If Not $bLocalFile And Not _IsWebLink($sID) Then _YTS_SubscribeFromItem($sID, $sTitle, "video", $hPlayGui)
            Case $menu_item_channel, $hDummyAltG
                ; Removed for local audio files (Listen to Audio File interface)
                If Not $bLocalFile And _IsSoundCloudLink($sID) Then
                    ShellExecute(_SC_ArtistUrl($sID))
                    ContinueLoop
                EndIf
                If Not $bLocalFile Then
                Local $hLoadingTmp = GUICreate(_T("Working..."), 250, 80, -1, -1, BitOR($WS_POPUP, $WS_BORDER), BitOR($WS_EX_TOPMOST, $WS_EX_TOOLWINDOW), $hPlayGui)
                GUICtrlCreateLabel(_T("Fetching channel information..."), 10, 25, 230, 20, $SS_CENTER)
                GUISetBkColor(0xFFFFFF, $hLoadingTmp)
                GUISetState(@SW_SHOW, $hLoadingTmp)
                Local $pid_channel = Run(@ComSpec & ' /c "' & $YT_DLP_EXE & ' --print "https://www.youtube.com/channel/%(channel_id)s" --no-playlist -- "' & $sID & '""', @ScriptDir, @SW_HIDE, $STDOUT_CHILD + $STDERR_CHILD)
                Local $sChannelUrl = ""
                While ProcessExists($pid_channel)
                    $sChannelUrl &= StdoutRead($pid_channel)
                    GUIGetMsg()
                    Sleep(1)
                WEnd
                $sChannelUrl &= StdoutRead($pid_channel)
                GUIDelete($hLoadingTmp)
                $sChannelUrl = StringStripWS($sChannelUrl, 3)
                Local $pattern = "(https://www\.youtube\.com/(channel/|@)[^ \r\n]+)"
                Local $aMatch = StringRegExp($sChannelUrl, $pattern, 3)
                If IsArray($aMatch) Then
                    ShellExecute($aMatch[0])
                Else
                    MsgBox(16, _T("Error"), _T("Cannot get channel URL."))
                EndIf
                EndIf
            Case $menu_item_browser, $hDummyAltB
                ; Removed for local audio files (Listen to Audio File interface)
                If Not $bLocalFile Then
                    ShellExecute(_VideoLink($sID))
                EndIf
            Case $menu_item_copy
                If $bPod Then
                    ClipPut($sUrl)
                    _ReportStatus(_T("Link copied to clipboard"))
                ElseIf $bLocalFile Then
                    ClipPut($sUrl)
                    MsgBox(64, _T("Info"), _T("File path copied to clipboard!"))
                Else
                    _ShowCopyLinkDialog($sID, $hPlayGui)
                EndIf
            Case $menu_share_telegram
                If $bLocalFile Then
                    _ReportStatus(_T("Not available for local audio files."))
                Else
                    _ShowShareLinkDialog("telegram", $sID, $sTitle, $hPlayGui)
                EndIf
            Case $menu_share_facebook
                If $bLocalFile Then
                    _ReportStatus(_T("Not available for local audio files."))
                Else
                    _ShowShareLinkDialog("facebook", $sID, $sTitle, $hPlayGui)
                EndIf
            Case $menu_item_desc, $hDummyCtrlShiftD
                ; Removed for local audio files (Listen to Audio File interface)
                If Not $bLocalFile Then
                Local $hWaitDesc = GUICreate(_T("Loading..."), 250, 80, -1, -1, BitOR($WS_POPUP, $WS_BORDER), BitOR($WS_EX_TOPMOST, $WS_EX_TOOLWINDOW), $hPlayGui)
                GUICtrlCreateLabel(_T("Fetching Description..."), 10, 25, 230, 20, $SS_CENTER)
                GUISetBkColor(0xFFFFFF, $hWaitDesc)
                GUISetState(@SW_SHOW, $hWaitDesc)
                Local $iPIDDesc = Run(@ComSpec & ' /c "' & $YT_DLP_EXE & ' --get-description --no-playlist --encoding utf-8 -- "' & $sID & '""', @ScriptDir, @SW_HIDE, $STDOUT_CHILD)
                Local $bDataDesc = Binary("")
                While ProcessExists($iPIDDesc)
                    $bDataDesc &= StdoutRead($iPIDDesc, False, True)
                    GUIGetMsg()
                    Sleep(1)
                WEnd
                $bDataDesc &= StdoutRead($iPIDDesc, False, True)
                GUIDelete($hWaitDesc)
                Local $sDescStr = BinaryToString($bDataDesc, 4)
                If $sDescStr = "" Then
                    MsgBox(64, _T("Info"), _T("No description available."))
                Else
                    Local $sTempFileDesc = @TempDir & "\temp_desc.txt"
                    Local $hFileDesc = FileOpen($sTempFileDesc, 2 + 256)
                    FileWrite($hFileDesc, $sDescStr)
                    FileClose($hFileDesc)
                    Run('"' & $DESC_EXE_PATH & '" "' & $sTempFileDesc & '"')
                EndIf
                EndIf
            Case $menu_item_comments
                If $bLocalFile Then
                    _ReportStatus(_T("Not available for local audio files."))
                Else
                    Run('"' & $COMMENTS_EXE_PATH & '" "' & _VideoLink($sID) & '"')
                EndIf
            Case $menu_item_transcript, $hDummyCtrlAltT
                If $bLocalFile Then
                    _ReportStatus(_T("Not available for local audio files."))
                Else
                    _ShowYoutubeTranscript(_VideoLink($sID), $hPlayGui)
                EndIf
            Case $menu_item_lyrics, $hDummyCtrlAltL
                If $bLocalFile Then
                    _ShowSongLyrics($sTitle, $hPlayGui, "") ; local file: no video id, search by its name only
                Else
                    _ShowSongLyrics($sTitle, $hPlayGui, $sID)
                EndIf
            Case $menu_item_queue_add, $hDummyCtrlQ
                If $bLocalFile Then
                    _ReportStatus(_T("Not available for local audio files."))
                ElseIf _Queue_Add($sID, $sTitle) Then
                    _ReportStatus(_TF("Added to play queue, position {1}", $g_iQueueCount))
                Else
                    _ReportStatus(_T("Cannot add this item to the play queue."))
                EndIf
            Case $menu_item_dq_add
                If $bLocalFile Then
                    _ReportStatus(_T("Not available for local audio files."))
                Else
                    _DQ_AddNotify($sID, $sTitle, $hPlayGui, True)
                EndIf
            Case $menu_item_queue_view, $hDummyCtrlShiftQ
                ; A song chosen in the queue window: leave this one, the play loop takes the first song of the queue
                If _ShowPlayQueue($hPlayGui, Not $bLocalFile) = "PLAY" Then
                    $sAction = "NEXT"
                    ExitLoop
                EndIf
            Case $menu_item_fav
                If _IsFavorite($sID) Then
                    If _RemoveFavorite($sID) Then
                        GUICtrlSetData($menu_item_fav, _T("Add to &Favorite..."))
                        _ReportStatus(_T("Removed from favorites"))
                    EndIf
                Else
                    _AddFavorite($sID, $sTitle)
                    GUICtrlSetData($menu_item_fav, _T("Remove from &Favorite..."))
                    _ReportStatus(_T("Added to favorites"))
                EndIf
            Case $menu_item_add_col
                _AddtoCollection($sID, $sTitle)
            Case $menu_item_remove_col
                _RemoveFromAllCollectionsDialog($sID)
            Case $menu_item_goto
                _ShowGoToTime()

            Case $menu_item_fileinfo, $hDummyI
                ; Removed for the online listening interface (kept for local audio files)
                If $bLocalFile Then
                    Local $fCurI = _VLC_Direct_GetTime() / 1000
                    Local $fLenI = _VLC_Direct_GetLength() / 1000
                    ; Local audio file: announce info inline (screen-reader friendly),
                    ; e.g. "Song Title.mp3 ;  2 seconds of 4 minutes  53 seconds;  playing;"
                    Local $aNameI = StringRegExp($sUrl, "([^\\\/]+)$", 3)
                    Local $sFileNameI = (UBound($aNameI) > 0 And Not $bPod) ? $aNameI[0] : $sTitle
                    Local $iStateI = _VLC_Direct_GetState()
                    Local $sPlayStateI = ($iStateI = 3) ? "playing" : "paused"
                    Local $sInfoMsg = _TF("{1} ;  {2} of {3};  {4};", $sFileNameI, _FormatTimeSpoken($fCurI), _FormatTimeSpoken($fLenI), $sPlayStateI)
                    _ReportStatus($sInfoMsg)
                EndIf

            Case $hDummyC
                ; Copy the title of the track being played (silent: status message only, no dialog)
                If $g_sCurrentVideoTitle <> "" Then
                    ClipPut($g_sCurrentVideoTitle)
                    _ReportStatus(_T("Title copied"))
                Else
                    _ReportStatus(_T("No title to copy"))
                EndIf

            Case $hDummyAltO
                ; Gửi lệnh WM_SYSCOMMAND (0x0112) và SC_KEYMENU (0xF100) trực tiếp tới Windows
                ; để mở Menu một cách chuẩn xác 100% không bị dội phím gây văng phần mềm.
                DllCall("user32.dll", "lresult", "PostMessage", "hwnd", $hPlayGui, "uint", 0x0112, "wparam", 0xF100, "lparam", 79)

            Case $hDummyCtrlK
                ; Removed for local audio files (Listen to Audio File interface)
                If Not $bLocalFile Then
                    _ShowCopyLinkDialog($sID, $hPlayGui)
                EndIf

            Case $hDummyCtrlC
                If $bLocalFile Then
                    _ReportStatus(_T("Not available for local audio files."))
                    ContinueLoop
                EndIf
                Local $sCleanID = StringStripWS($sID, 3)
                Local $sFinalLink = ""
                Local $fPos = (_VLC_Direct_GetTime() / 1000)

                ; Nếu chưa đặt điểm [ thì tự động lấy thời gian hiện tại
                Local $iStart = _Ternary(($g_fSelectionStart <> -1), Int($g_fSelectionStart), Int($fPos))

                If _IsWebLink($sCleanID) Then
                    ; Other sites (SoundCloud...): no range links, the link opens at the start time (#t=m:ss)
                    $sFinalLink = $sCleanID & "#t=" & _SC_TimeFragment($iStart)
                    If $g_fSelectionStart <> -1 Then
                        _ReportStatus(_TF("Link from start point copied: {1}", _FormatTime($iStart)))
                    Else
                        _ReportStatus(_TF("Current time link copied: {1}", _FormatTime($iStart)))
                    EndIf
                ElseIf $g_fSelectionEnd <> -1 Then
                    Local $iEnd = Int($g_fSelectionEnd)
                    ; Đảo ngược nếu điểm kết thúc nhỏ hơn điểm bắt đầu
                    If $iEnd < $iStart Then
                        Local $tmp = $iStart
                        $iStart = $iEnd
                        $iEnd = $tmp
                    EndIf
                    ; Tạo link đoạn (Range). Sử dụng link embed để trình duyệt tự động dừng ở điểm kết thúc.
                    $sFinalLink = "https://www.youtube.com/embed/" & $sCleanID & "?start=" & $iStart & "&end=" & $iEnd & "&autoplay=1"
                    _ReportStatus(_TF("Range link (Embed) copied: {1} to {2}", _FormatTime($iStart), _FormatTime($iEnd)))
                Else
                    ; Nếu không có điểm kết thúc, tạo link tại mốc thời gian bắt đầu
                    $sFinalLink = "https://www.youtube.com/watch?v=" & $sCleanID & "&t=" & $iStart & "s"
                    If $g_fSelectionStart <> -1 Then
                        _ReportStatus(_TF("Link from start point copied: {1}", _FormatTime($iStart)))
                    Else
                        _ReportStatus(_TF("Current time link copied: {1}", _FormatTime($iStart)))
                    EndIf
                EndIf

                ClipPut($sFinalLink)

            Case $hDummyCtrlShiftC
                If Not $bLocalFile Then
                    Run('"' & $COMMENTS_EXE_PATH & '" "' & _VideoLink($sID) & '"')
                EndIf

            Case $hDummyBracketLeft
                ; Removed for local audio files (Listen to Audio File interface)
                If Not $bLocalFile Then
                    ; Lấy vị trí hiện tại
                    Local $fPos = (_VLC_Direct_GetTime() / 1000)
                    $g_fSelectionStart = $fPos
                    _ReportStatus(_TF("Start selection: {1}", _FormatTime($g_fSelectionStart)))
                EndIf

            Case $hDummyBracketRight
                ; Removed for local audio files (Listen to Audio File interface)
                If Not $bLocalFile Then
                    Local $fPos = (_VLC_Direct_GetTime() / 1000)
                    $g_fSelectionEnd = $fPos
                    _ReportStatus(_TF("End selection: {1}", _FormatTime($g_fSelectionEnd)))
                EndIf

            Case $hDummyCtrlS
                ; Removed for local audio files (Listen to Audio File interface)
                If Not $bLocalFile Then
                    If $g_fSelectionStart = -1 Or $g_fSelectionEnd = -1 Then
                        _ReportStatus(_T("Please set both start and end selection points."))
                    Else
                        _SaveSelection($sUrl, $sTitle)
                    EndIf
                EndIf

            Case $hDummy1, $hDummy2, $hDummy3, $hDummy4, $hDummy5, $hDummy6, $hDummy7, $hDummy8, $hDummy9
                Local $iPercent = ($nMsg - $hDummy1 + 1) * 10
                Local $fDuration = (_VLC_Direct_GetLength() / 1000)
                If $fDuration > 0 Then
                    Local $iTargetSec = ($iPercent / 100) * $fDuration

                    _VLC_Direct_SetTime($iTargetSec * 1000)
                    ControlFocus($hPlayGui, "", $g_hStatusLabel) ; Focus Masking

                    If $g_iAnnouncementMode == 1 Then ; Read percentage
                        _ReportStatus($iPercent & "%")
                    ElseIf $g_iAnnouncementMode == 2 Then ; Read time
                        _ReportStatus(_FormatTime($iTargetSec))
                    Else ; Silent
                        _ReportStatus(_FormatTime($iTargetSec))
                    EndIf
                EndIf

            Case $hDummyP
                Local $fCur = _VLC_Direct_GetTime() / 1000
                Local $fLen = _VLC_Direct_GetLength() / 1000
                If $fLen > 0 Then
                    Local $iPercent = Int(($fCur / $fLen) * 100)
                    _ReportStatus($iPercent & "%")
                EndIf
            Case $hDummySpace
                Local $ps = _VLC_Direct_GetState()
                If $ps = 5 Or $ps = 6 Then
                    _VLC_Direct_SetTime(0)
                    DllCall($hVLC_Dll, "int:cdecl", "libvlc_media_player_play", "ptr", $oVLC_Player)
                    _ReportStatus(_T("play"))
                ElseIf $ps = 3 Then
                    _VLC_Direct_Pause()
                    _ReportStatus(_T("pause"))
                Else
                    _VLC_Direct_Pause()
                    _ReportStatus(_T("play"))
                EndIf

            Case $hDummyCtrlShiftE
                If Not $bAudioOnly Then
                    $g_bCinemaMode = Not $g_bCinemaMode
                    If $g_bCinemaMode Then
                        Local $aPos = WinGetPos($hPlayGui)
                        $g_iOriginalX = $aPos[0]
                        $g_iOriginalY = $aPos[1]
                        $g_iOriginalW = $aPos[2]
                        $g_iOriginalH = $aPos[3]
                        GUISetStyle(BitOR($WS_POPUP, $WS_VISIBLE), -1, $hPlayGui)
                        WinMove($hPlayGui, "", 0, 0, @DesktopWidth, @DesktopHeight)
                        GUICtrlSetPos($oVLCCtrl, 0, 0, @DesktopWidth, @DesktopHeight)
                        GUICtrlSetState($g_lblPlayerInfo, $GUI_HIDE)
                        GUICtrlSetState($g_lblTimeInfo, $GUI_HIDE)
                        If $g_lblHint <> 0 Then GUICtrlSetState($g_lblHint, $GUI_HIDE)
                        _ReportStatus(_T("Cinema Mode Enabled"))
                    Else
                        GUISetStyle(BitOR($WS_CAPTION, $WS_SYSMENU, $WS_POPUP, $WS_SIZEBOX, $WS_VISIBLE), -1, $hPlayGui)
                        WinMove($hPlayGui, "", $g_iOriginalX, $g_iOriginalY, $g_iOriginalW, $g_iOriginalH)
                        GUICtrlSetPos($oVLCCtrl, 0, 0, $iWidth, $iHeight)
                        GUICtrlSetState($g_lblPlayerInfo, $GUI_SHOW)
                        GUICtrlSetState($g_lblTimeInfo, $GUI_SHOW)
                        If $g_lblHint <> 0 Then GUICtrlSetState($g_lblHint, $GUI_SHOW)
                        _ReportStatus(_T("Cinema Mode Disabled"))
                    EndIf
                EndIf

            Case $hDummyN
                If $g_bLocalPlaylistMode Then
                    $sAction = "NEXT"
                    ExitLoop
                ElseIf $allowAutoPlayToggle Then
                    $g_bAutoPlay = Not $g_bAutoPlay
                    GUICtrlSetData($g_lblAuto, _Ternary($g_bAutoPlay, _T("Auto: ON"), _T("Auto: OFF")))
                    _ReportStatus(_Ternary($g_bAutoPlay, _T("Auto Play Next Track ON"), _T("Auto Play Next Track OFF")))
                    IniWrite($CONFIG_FILE, "Settings", "AutoPlay", _Ternary($g_bAutoPlay, "true", "false"))
                EndIf

            Case $hDummyB
                If $g_bLocalPlaylistMode Then
                    $sAction = "BACK"
                    ExitLoop
                EndIf

            Case $hDummyCtrlHome
                ; First File - only in folder playlist mode
                If $g_bLocalPlaylistMode Then
                    $sAction = "FIRST"
                    ExitLoop
                EndIf

            Case $hDummyCtrlEnd
                ; Last File - only in folder playlist mode
                If $g_bLocalPlaylistMode Then
                    $sAction = "LAST"
                    ExitLoop
                EndIf

            Case $hDummyR
                ; Removed for local audio files (Listen to Audio File interface)
                If Not $bLocalFile Then
                    $g_bRepeat = Not $g_bRepeat
                    GUICtrlSetData($g_lblRepeat, _Ternary($g_bRepeat, _T("Repeat: ON"), _T("Repeat: OFF")))
                    _ReportStatus(_Ternary($g_bRepeat, _T("Repeat ON"), _T("Repeat OFF")))
                    IniWrite($CONFIG_FILE, "Settings", "Repeat", _Ternary($g_bRepeat, "true", "false"))
                EndIf

            Case $hDummyRemaining
                ; Removed for local audio files (Listen to Audio File interface)
                If Not $bLocalFile Then
                    Local $iLength = _VLC_Direct_GetLength()
                    Local $iTime = _VLC_Direct_GetTime()
                    If $iLength > 0 Then
                        Local $iRemaining = ($iLength - $iTime) / 1000
                        If $iRemaining < 0 Then $iRemaining = 0
                        _ReportStatus(_TF("Remaining time: {1}", _FormatTime($iRemaining)))
                    EndIf
                EndIf

            Case $hDummyShiftN
                ; Disabled for local audio files (Listen to Audio File interface).
                ; Previously this fired even when $bLocalFile = True, and since
                ; _AddSingleAudioFile() ignores the "NEXT" return value, pressing
                ; Shift+N while listening to a single local file silently closed
                ; the player instead of doing nothing.
                If Not $bLocalFile Or $bPod Then
                    $sAction = "NEXT"
                    ExitLoop
                EndIf

            Case $hDummyShiftB
                ; Disabled for local audio files (Listen to Audio File interface).
                ; Same issue as Shift+N above - closed the player unexpectedly.
                If Not $bLocalFile Or $bPod Then
                    $sAction = "BACK"
                    ExitLoop
                EndIf

            Case $hDummyHome
                _VLC_Direct_SetTime(0)
                _ReportStatus(_T("Restart from beginning"))

            Case $hDummyEnd
                Local $fDuration = (_VLC_Direct_GetLength() / 1000)
                If $fDuration > 0 Then
                    _VLC_Direct_SetTime(($fDuration - 20) * 1000)
                    _ReportStatus(_T("Near end"))
                Else
                    $sAction = "STOP"
                    ExitLoop
                EndIf

            Case $hDummyCtrlW
                _Quit_App()
                Exit

            Case $hDummyMinus
                If $g_iFFStep > 1 Then $g_iFFStep -= 1
                If $g_iRWStep > 1 Then $g_iRWStep -= 1
                $g_iSeekStep = $g_iFFStep
                IniWrite($CONFIG_FILE, "Settings", "FFStep", $g_iFFStep)
                IniWrite($CONFIG_FILE, "Settings", "RWStep", $g_iRWStep)
                _ReportStatus(_TF("Seek Step: Forward {1}s, Backward {2}s", $g_iFFStep, $g_iRWStep))

            Case $hDummyEqual
                $g_iFFStep += 1
                $g_iRWStep += 1
                $g_iSeekStep = $g_iFFStep
                IniWrite($CONFIG_FILE, "Settings", "FFStep", $g_iFFStep)
                IniWrite($CONFIG_FILE, "Settings", "RWStep", $g_iRWStep)
                _ReportStatus(_TF("Seek Step: Forward {1}s, Backward {2}s", $g_iFFStep, $g_iRWStep))

            Case $hDummyUp
                _StepAppVolume(1)

            Case $hDummyDown
                _StepAppVolume(-1)

            Case $hDummyCtrlLeft
                _StepPan(-1)

            Case $hDummyCtrlRight
                _StepPan(1)

            Case $hDummyS
                $g_fPitch = Round($g_fPitch - 0.1, 1)
                If $g_fPitch < 0.1 Then $g_fPitch = 0.1
                _VLC_Direct_SetRate($g_fPitch)
                _ReportStatus(_TF("Speed: {1}x", $g_fPitch))

            Case $hDummyD
                $g_fPitch = 1.0
                _VLC_Direct_SetRate($g_fPitch)
                _ReportStatus(_T("Speed: 1.0x (Normal)"))

            Case $hDummyF
                $g_fPitch = Round($g_fPitch + 0.1, 1)
                If $g_fPitch > 5.0 Then $g_fPitch = 5.0
                _VLC_Direct_SetRate($g_fPitch)
                _ReportStatus(_TF("Speed: {1}x", $g_fPitch))

            Case $hDummyLeft
                Local $fCurPos = (_VLC_Direct_GetTime() / 1000)
                Local $fTarget = ($fCurPos - $g_iRWStep < 0) ? 0 : $fCurPos - $g_iRWStep

                _VLC_Direct_SetTime($fTarget * 1000)
                ControlFocus($hPlayGui, "", $g_hStatusLabel)

                If $g_iAnnouncementMode == 1 Then ; Read percentage
                    Local $fDur = (_VLC_Direct_GetLength() / 1000)
                    If $fDur > 0 Then
                        _ReportStatus(Int(($fTarget / $fDur) * 100) & "%")
                    Else
                        _ReportStatus(_FormatTime($fTarget))
                    EndIf
                ElseIf $g_iAnnouncementMode == 2 Then ; Read time
                    _ReportStatus(_FormatTime($fTarget))
                Else ; Silent
                    _ReportStatus(_FormatTime($fTarget))
                EndIf

            Case $hDummyRight
                Local $fCurPos = (_VLC_Direct_GetTime() / 1000)
                Local $fDur = (_VLC_Direct_GetLength() / 1000)
                Local $fTarget = $fCurPos + $g_iFFStep
                If $fDur > 0 And $fTarget > $fDur Then $fTarget = $fDur

                _VLC_Direct_SetTime($fTarget * 1000)
                ControlFocus($hPlayGui, "", $g_hStatusLabel)

                If $g_iAnnouncementMode == 1 Then ; Read percentage
                    If $fDur > 0 Then
                        _ReportStatus(Int(($fTarget / $fDur) * 100) & "%")
                    Else
                        _ReportStatus(_FormatTime($fTarget))
                    EndIf
                ElseIf $g_iAnnouncementMode == 2 Then ; Read time
                    _ReportStatus(_FormatTime($fTarget))
                Else ; Silent
                    _ReportStatus(_FormatTime($fTarget))
                EndIf

            Case $hDummyAltLeft, $hDummyAltRight
                ; Alt+Left / Alt+Right: tua lùi / tới đúng 1 phút (60 giây)
                Local $fCurPosAlt = (_VLC_Direct_GetTime() / 1000)
                Local $fDurAlt = (_VLC_Direct_GetLength() / 1000)
                Local $fTargetAlt
                If $nMsg = $hDummyAltLeft Then
                    $fTargetAlt = $fCurPosAlt - 60
                    If $fTargetAlt < 0 Then $fTargetAlt = 0
                Else
                    $fTargetAlt = $fCurPosAlt + 60
                    If $fDurAlt > 0 And $fTargetAlt > $fDurAlt Then $fTargetAlt = $fDurAlt
                EndIf

                _VLC_Direct_SetTime($fTargetAlt * 1000)
                ControlFocus($hPlayGui, "", $g_hStatusLabel)

                If $g_iAnnouncementMode == 1 And $fDurAlt > 0 Then ; Read percentage
                    _ReportStatus(Int(($fTargetAlt / $fDurAlt) * 100) & "%")
                Else ; Read time / Silent
                    _ReportStatus(_FormatTime($fTargetAlt))
                EndIf

            Case $hDummyEsc
                $sAction = "CLOSE"
                ExitLoop

            Case $hDummyEq
                _ShowEqualizerDialog($hPlayGui)

            Case $menu_item_chapters, $hDummyChapList
                _ShowChaptersDialog($hPlayGui)

            Case $hDummyChapNext
                _Chap_Step(1)

            Case $hDummyChapPrev
                _Chap_Step(-1)

            Case $menu_item_voice, $hDummyVoice
                _Voice_Cycle()
                _Voice_Restart($sUrl, ($bLocalFile And Not $bPod))
                _ReportStatus(_TF("Voice enhancement: {1}", _Voice_Name($g_iVoiceMode)))

            Case $hDummyG
                _ShowGoToTime()

            Case $hDummyCtrlT
                ; Removed for local audio files (Listen to Audio File interface)
                If Not $bLocalFile Then
                    Local $sElapsed = _FormatTime(_VLC_Direct_GetTime() / 1000)
                    _ReportStatus(_TF("Elapsed Time: {1}", $sElapsed))
                EndIf

            Case $hDummyCtrlShiftT
                ; Removed for local audio files (Listen to Audio File interface)
                If Not $bLocalFile Then
                    Local $sTotal = _FormatTime(_VLC_Direct_GetLength() / 1000)
                    _ReportStatus(_TF("Total Duration: {1}", $sTotal))
                EndIf
        EndSwitch
        EndIf

        ; --- Playback state checks: run on EVERY loop tick (even when idle,
        ; i.e. $nMsg = 0), so the loading dialog closes and end-of-track is
        ; detected promptly without needing a keypress first ---
        If $bLocalFile And ($g_bResumeLocal Or $bPod) And TimerDiff($hPosSaveTimer) >= 10000 Then
            $hPosSaveTimer = TimerInit()
            If _VLC_Direct_GetState() = 3 And Not $g_bTrackEnded Then
                Local $iPosNow = _VLC_Direct_GetTime()
                If $iPosNow >= 3000 Then _LocalPos_Save($sID, $iPosNow, _VLC_Direct_GetLength())
            EndIf
        EndIf

        ; Refresh the on-screen state / position line (twice a second, redraws only when the text changed)
        If TimerDiff($hInfoTimer) >= 500 Then
            $hInfoTimer = TimerInit()
            _Chap_Tick() ; loads the chapters and announces a new chapter
            _UpdatePlayerTimeLabel()
            _VLC_StereoMode_Retry()
            If $g_iPanStep <> 0 Or $g_bAutoPan Or _StereoModeUsesSession() Then _Pan_Sync() ; nhac moi bat dau / VLC doi session -> gan lai pan (toi da 1 lan/giay)
        EndIf

        Local $iCurState = _VLC_Direct_GetState()
        _AutoPan_Tick($iCurState) ; Settings > Player > Auto pan audio
        If $iCurState = 2 Then ; Buffering
            If GUICtrlRead($g_hStatusLabel) <> _T("Buffering...") Then GUICtrlSetData($g_hStatusLabel, _T("Buffering..."))
        ElseIf $iCurState = 3 And GUICtrlRead($g_hStatusLabel) = _T("Buffering...") Then
            GUICtrlSetData($g_hStatusLabel, _T("Playing"))
        EndIf

        If Not $bLoaded And ($iCurState = 3 Or $iCurState = 5 Or $iCurState = 6 Or $iCurState = 7 Or TimerDiff($iLoadStartTime) > 30000) Then
            If $hLoading <> 0 Then GUIDelete($hLoading)
            $hLoading = 0
            $bLoaded = True
            DllCall("winmm.dll", "int", "PlaySoundW", "ptr", 0, "ptr", 0, "dword", 0) ; Stop loading sound
            If $iCurState = 3 Then GUICtrlSetData($g_hStatusLabel, _T("Playing"))
        EndIf

        Local $iState = $iCurState
        If ($iState = 6 Or $iState = 5 Or $iState = 7) And $bLoaded Then
             $g_bTrackEnded = True ; the track ended by itself (the play queue may continue)
             If $g_bRepeat Then
                 $sAction = "RESTART"
             Else
                 Switch $g_iAfterVideoAction
                     Case 0
                         $sAction = "CLOSE"
                     Case 1
                         $sAction = "RESTART"
                     Case 2
                         $sAction = "FINISHED"
                 EndSwitch
             EndIf
             ExitLoop
        EndIf
        Sleep(20)
    WEnd

    ; Lưu vị trí trước khi thoát (Save position before exiting)
    If $bLocalFile Then
        ; Audio cuc bo: nho vi tri tung file (xoa neu bai da nghe het)
        If $g_bResumeLocal Or $bPod Then
            If $g_bTrackEnded Then
                _LocalPos_Clear($sID)
            Else
                _LocalPos_Save($sID, _VLC_Direct_GetTime(), _VLC_Direct_GetLength())
            EndIf
        EndIf
    ElseIf $g_bContinueWatching Then
        Local $iFinalState = _VLC_Direct_GetState()
        If $iFinalState = 6 Then ; Ended
            _SavePlaybackPosition($sID, 0)
        Else
            _SavePlaybackPosition($sID, _VLC_Direct_GetTime())
        EndIf
    EndIf

    ; Cleanup
    DllCall("winmm.dll", "int", "PlaySoundW", "ptr", 0, "ptr", 0, "dword", 0) ; Stop loading sound if still playing
    _VLC_Direct_Stop()
    _Chap_Reset()
    ; Roi khoi trinh phat -> pan ve 0.0 va giai phong (chuyen bai NEXT/BACK/... thi giu nguyen pan)
    If $sAction = "CLOSE" Or $sAction = "STOP" Or $sAction = "FINISHED" Then _Pan_Reset()
    If IsHWnd($hPlayGui) Then GUIDelete($hPlayGui)
    $hPlayGui = 0
    If $hLoading <> 0 Then GUIDelete($hLoading)
    Return $sAction
EndFunc

; On-screen line under the title: state, position / length, volume and speed
Func _UpdatePlayerTimeLabel()
    If $g_lblTimeInfo = 0 Or Not IsHWnd($hPlayGui) Then Return
    Local $sState
    Switch _VLC_Direct_GetState()
        Case 1, 2
            $sState = _T("Loading")
        Case 3
            $sState = _T("Playing")
        Case 4
            $sState = _T("Paused")
        Case 5
            $sState = _T("Stopped")
        Case 6
            $sState = _T("Ended")
        Case 7
            $sState = _T("Error")
        Case Else
            $sState = _T("Ready")
    EndSwitch
    Local $fCurT = _VLC_Direct_GetTime() / 1000
    Local $fLenT = _VLC_Direct_GetLength() / 1000
    If $fCurT < 0 Then $fCurT = 0
    Local $sTimeTxt = _FormatTime($fCurT)
    If $fLenT > 0 Then $sTimeTxt &= " / " & _FormatTime($fLenT)
    Local $sInfoTxt = _TF("{1}     {2}     Volume: {3}%     Speed: {4}x", $sState, $sTimeTxt, $g_iAppVolume, StringFormat("%.1f", $g_fPitch))
    If $sInfoTxt = $g_sLastTimeInfo Then Return
    $g_sLastTimeInfo = $sInfoTxt
    GUICtrlSetData($g_lblTimeInfo, $sInfoTxt)
EndFunc

; Lines of the on-screen keyboard guide shown in the audio player window
Func _GetPlayerHelpLines($bLocalFile, $bAllowAutoPlayToggle)
    Local $sHelp = _HKL("Space: Play / Pause", "play_pause") & @CRLF & _HKL("Left / Right: Rewind / Forward", "seek_back|seek_fwd") & @CRLF & _HKL("Alt+Left / Alt+Right: Rewind / Forward 1 minute", "seek_back_1m|seek_fwd_1m") & @CRLF & _HKL("Up / Down: Volume up / down", "vol_up|vol_down") & @CRLF & _HKL("Ctrl+Left / Ctrl+Right: Pan audio left / right", "pan_left|pan_right") & @CRLF & _HKL("Home / End: Restart / Jump near the end", "restart|near_end") & @CRLF & _T("1 - 9: Jump to 10% - 90% of the track") & @CRLF & _HKL("S / D / F: Slower / Normal / Faster", "slower|normal_speed|faster") & @CRLF & _HKL("- / =: Shorter / Longer seek step", "step_shorter|step_longer") & @CRLF & _HKL("P: Show percentage played", "show_percent") & @CRLF & _HKL("Ctrl+G: Go to a specific time", "goto_time") & @CRLF & _HKL("Ctrl+Alt+L: View lyrics", "lyrics") & @CRLF & _HKL("C: Copy the track title", "copy_title") & @CRLF & _HKL("Ctrl+E: Open the equalizer", "eq_dialog") & @CRLF
    If $bLocalFile Then
        $sHelp &= _HKL("I: Show file information", "file_info") & @CRLF
        If $g_bLocalPlaylistMode Then
            $sHelp &= _HKL("N / B: Next / Previous file", "next|prev") & @CRLF & _HKL("Ctrl+Home / Ctrl+End: First / Last file", "first_file|last_file") & @CRLF
        EndIf
    Else
        $sHelp &= _HKL("Ctrl+T: Elapsed time", "elapsed") & @CRLF & _HKL("Ctrl+Shift+T: Total duration", "total") & @CRLF & _HKL("Ctrl+R: Remaining time", "remaining") & @CRLF & _HKL("R: Turn repeat on / off", "repeat") & @CRLF & _HKL("Ctrl+K: Copy video link", "copy_link") & @CRLF & _HKL("[ and ]: Set selection start / end", "sel_start|sel_end") & @CRLF & _HKL("Ctrl+S: Save the selection", "save_sel") & @CRLF & _HKL("Alt+B: Open in browser", "open_browser") & @CRLF & _HKL("Alt+G: Go to channel", "goto_channel") & @CRLF & _HKL("Ctrl+Shift+D: Video description", "description") & @CRLF & _HKL("Ctrl+Shift+C: Video comments", "comments") & @CRLF & _HKL("Ctrl+Q: Add to play queue", "queue_add") & @CRLF & _HKL("Ctrl+Shift+Q: Open the play queue", "queue_open") & @CRLF & _HKL("Alt+O: Open the Options menu", "options_menu") & @CRLF
        If $bAllowAutoPlayToggle Then
            $sHelp &= _HKL("N: Auto-play next on / off", "next") & @CRLF & _HKL("Shift+N / Shift+B: Next / Previous video", "force_next|force_prev") & @CRLF
        EndIf
    EndIf
    $sHelp &= _HKL("Page Up / Page Down: Previous / Next chapter", "chapter_prev|chapter_next") & @CRLF & _HKL("H: List of chapters", "chapters") & @CRLF & _HKL("Ctrl+Shift+V: Voice enhancement", "voice") & @CRLF
    $sHelp &= _HKL("Esc: Close the player", "close_player") & @CRLF & _HKL("Ctrl+W: Exit the application", "exit_app")
    Return StringSplit($sHelp, @LF, 2) ; 2 = no count element, 0-based array
EndFunc

; NEW FEATURE Hàm GUI riêng cho tính năng Sleep Timer
; ======================================================================
;  RADIO: FAVORITE STATIONS (radio_favorites.dat, one station per line: name|url|codec|bitrate, UTF-8)
; ======================================================================
; Returns [n][5] (name, url, codec, bitrate, tags) like _Radio_SearchStations, or 0 when there is no favorite
Func _RadioFav_Load()
    If Not FileExists($RADIO_FAV_FILE) Then Return 0
    Local $hFile = FileOpen($RADIO_FAV_FILE, 0 + 256) ; read, UTF-8
    If $hFile = -1 Then Return 0
    Local $sData = FileRead($hFile)
    FileClose($hFile)
    Local $aLines = StringSplit(StringStripCR($sData), @LF, 2)
    Local $aOut[UBound($aLines)][5], $n = 0
    Local $aP
    For $i = 0 To UBound($aLines) - 1
        If StringStripWS($aLines[$i], 3) = "" Then ContinueLoop
        $aP = StringSplit($aLines[$i], "|", 2)
        If UBound($aP) < 2 Then ContinueLoop
        If $aP[0] = "" Or $aP[1] = "" Then ContinueLoop
        $aOut[$n][0] = $aP[0]
        $aOut[$n][1] = StringReplace($aP[1], "%7C", "|")
        $aOut[$n][2] = ""
        $aOut[$n][3] = 0
        $aOut[$n][4] = ""
        If UBound($aP) > 2 Then $aOut[$n][2] = $aP[2]
        If UBound($aP) > 3 Then $aOut[$n][3] = Int($aP[3])
        $n += 1
    Next
    If $n = 0 Then Return 0
    ReDim $aOut[$n][5]
    Return $aOut
EndFunc

Func _RadioFav_Line($sName, $sUrl, $sCodec, $iBitrate)
    Return StringReplace($sName, "|", "/") & "|" & StringReplace($sUrl, "|", "%7C") & "|" & StringReplace($sCodec, "|", "") & "|" & Int($iBitrate)
EndFunc

Func _RadioFav_Save(ByRef $aFav, $iCount)
    Local $hFile = FileOpen($RADIO_FAV_FILE, 2 + 8 + 256) ; write (erase), create path, UTF-8
    If $hFile = -1 Then Return False
    For $i = 0 To $iCount - 1
        FileWriteLine($hFile, _RadioFav_Line($aFav[$i][0], $aFav[$i][1], $aFav[$i][2], $aFav[$i][3]))
    Next
    FileClose($hFile)
    Return True
EndFunc

; 1 = added, 0 = it was already a favorite, -1 = the file could not be written
Func _RadioFav_Add($sName, $sUrl, $sCodec, $iBitrate)
    Local $aFav = _RadioFav_Load()
    Local $n = IsArray($aFav) ? UBound($aFav) : 0
    For $i = 0 To $n - 1
        If $aFav[$i][1] = $sUrl Then Return 0
    Next
    Local $hFile = FileOpen($RADIO_FAV_FILE, 1 + 8 + 256) ; append, create path, UTF-8
    If $hFile = -1 Then Return -1
    FileWriteLine($hFile, _RadioFav_Line($sName, $sUrl, $sCodec, $iBitrate))
    FileClose($hFile)
    Return 1
EndFunc

Func _RadioFav_RemoveAt($iIdx)
    Local $aFav = _RadioFav_Load()
    If Not IsArray($aFav) Then Return False
    Local $n = UBound($aFav)
    If $iIdx < 0 Or $iIdx >= $n Then Return False
    If $n = 1 Then Return _RadioFav_Clear()
    For $i = $iIdx To $n - 2
        For $j = 0 To 4
            $aFav[$i][$j] = $aFav[$i + 1][$j]
        Next
    Next
    ReDim $aFav[$n - 1][5]
    Return _RadioFav_Save($aFav, $n - 1)
EndFunc

Func _RadioFav_Clear()
    Local $hFile = FileOpen($RADIO_FAV_FILE, 2 + 8 + 256)
    If $hFile = -1 Then Return False
    FileClose($hFile)
    Return True
EndFunc

; ======================================================================
;  RADIO: RECORDING. A second libvlc player (same libvlc instance as the Player) opens the station again and writes it to
;  a file through VLC's own stream output (":sout" transcode), so it does not depend on the listening player.
;  Formats = the audio formats of Download (M4A, MP3, OGG, WAV).
; ======================================================================
; Index of $v in $a (0 when not found), used to select the saved value in the Settings combo boxes
Func _RadioRec_Idx(ByRef $a, $v)
    For $i = 0 To UBound($a) - 1
        If $a[$i] = $v Then Return $i
    Next
    Return 0
EndFunc

Func _RadioRec_Active()
    Return ($g_pRecPlayer <> 0)
EndFunc

Func _RadioRec_SafeName($sName)
    $sName = StringRegExpReplace($sName, '[\\/:*?"<>|\x01-\x1F]', "_")
    $sName = StringStripWS($sName, 7)
    If StringLen($sName) > 80 Then $sName = StringStripWS(StringLeft($sName, 80), 3)
    $sName = StringRegExpReplace($sName, '[\. ]+$', "")
    If $sName = "" Then $sName = "Radio"
    Return $sName
EndFunc

; libvlc wants UTF-8 text; DllCall "str" would send the ANSI code page (breaks station names with accents)
Func _VLC_Utf8Buf($s)
    Local $bBin = StringToBinary($s, 4)
    Local $tBuf = DllStructCreate("byte[" & (BinaryLen($bBin) + 1) & "]")
    DllStructSetData($tBuf, 1, $bBin)
    Return $tBuf
EndFunc

Func _VLC_AddOptionUtf8($pMedia, $sOpt)
    Local $tBuf = _VLC_Utf8Buf($sOpt)
    DllCall($hVLC_Dll, "none:cdecl", "libvlc_media_add_option", "ptr", $pMedia, "ptr", DllStructGetPtr($tBuf))
EndFunc

Func _RadioRec_Log($sText)
    Local $h = FileOpen($SETTINGS_DIR & "\radio_recording.log", 1 + 8 + 256)
    If $h = -1 Then Return
    FileWriteLine($h, @YEAR & "-" & @MON & "-" & @MDAY & " " & @HOUR & ":" & @MIN & ":" & @SEC & "  " & $sText)
    FileClose($h)
EndFunc

; VLC stream output chain for the format / bitrate / channels / sample rate chosen in Settings > Radio.
; $bPassthrough = True: no encoding at all, the stream is saved as it is (MPEG-TS) to be converted by ffmpeg afterwards.
Func _RadioRec_BuildSout($sFile, $bPassthrough = False)
    ; forward slashes + doubled % : the destination is parsed by VLC (it expands % codes like %Y)
    Local $sPath = StringReplace(StringReplace($sFile, "\", "/"), "%", "%%")
    If $bPassthrough Then Return '#std{access=file,mux=ts,dst="' & $sPath & '"}'
    Local $sCodec = "mp3", $sMux = "raw"
    Switch $g_sRadioRecFormat
        Case "M4A"
            $sCodec = "mp4a"
            $sMux = "mp4"
        Case "OGG"
            $sCodec = "vorb"
            $sMux = "ogg"
        Case "WAV"
            $sCodec = "s16l"
            $sMux = "wav"
    EndSwitch
    Local $sTrans = "acodec=" & $sCodec
    If $g_sRadioRecFormat <> "WAV" Then $sTrans &= ",ab=" & $g_iRadioRecBitrate
    $sTrans &= ",channels=" & $g_iRadioRecChannels
    If $g_iRadioRecRate > 0 Then $sTrans &= ",samplerate=" & $g_iRadioRecRate
    Return '#transcode{' & $sTrans & '}:std{access=file,mux=' & $sMux & ',dst="' & $sPath & '"}'
EndFunc

; libvlc state of the recording player: 0 nothing, 1 opening, 2 buffering, 3 playing, 4 paused, 5 stopped, 6 ended, 7 error
Func _RadioRec_State()
    If $g_pRecPlayer = 0 Or $hVLC_Dll = -1 Then Return 0
    Local $a = DllCall($hVLC_Dll, "int:cdecl", "libvlc_media_player_get_state", "ptr", $g_pRecPlayer)
    If @error Or Not IsArray($a) Then Return 0
    Return $a[0]
EndFunc

; True while the recording is running. False when it ended (stream ended / error) or the automatic stop time is reached.
Func _RadioRec_Alive()
    If $g_pRecPlayer = 0 Then Return False
    If $g_iRadioRecAutoStop > 0 And TimerDiff($g_hRadioRecStart) >= $g_iRadioRecAutoStop * 60000 Then Return False
    Local $iSt = _RadioRec_State()
    If $iSt >= 1 And $iSt <= 4 Then Return True
    If $iSt = 0 And TimerDiff($g_hRadioRecStart) < 5000 Then Return True ; right after play() the state is still 0 for a moment
    _RadioRec_Log("Recording ended, VLC state " & $iSt & " (" & $g_sRadioRecStation & ")")
    Return False
EndFunc

; Text for a recording that could not be made
Func _RadioRec_FailText()
    Return _T("Could not record this station.")
EndFunc

; 1 = recording started, 0 = could not start, -1 = VLC is not ready, -2 = the recording folder cannot be created
Func _RadioRec_Start($sName, $sUrl)
    If $g_pRecPlayer <> 0 Then Return 0
    If $hVLC_Dll = -1 Or $oVLC_Inst = 0 Then Return -1
    If StringStripWS($g_sRadioRecPath, 3) = "" Then $g_sRadioRecPath = @ScriptDir & "\radio_recording"
    If Not FileExists($g_sRadioRecPath) Then DirCreate($g_sRadioRecPath)
    If Not FileExists($g_sRadioRecPath) Then Return -2
    Local $sBase = $g_sRadioRecPath
    While StringRight($sBase, 1) = "\" Or StringRight($sBase, 1) = "/"
        $sBase = StringTrimRight($sBase, 1)
    WEnd
    Local $sStamp = @YEAR & "-" & @MON & "-" & @MDAY & " " & @HOUR & "-" & @MIN & "-" & @SEC
    Local $sFile = $sBase & "\" & _RadioRec_SafeName($sName) & " - " & $sStamp & "." & StringLower($g_sRadioRecFormat)
    ; MP3, and any recording with a volume below 100, is made offline by ffmpeg from the untouched stream
    ; (VLC's real-time MP3 encoder makes the music stutter, and VLC cannot change the volume of a recording)
    Local $bConv = _RadioRec_NeedConvert()
    Local $sOutFile = $sFile
    If $bConv Then $sOutFile = StringTrimRight($sFile, 4) & ".ts"
    Local $sSout = _RadioRec_BuildSout($sOutFile, $bConv)

    Local $tUrl = _VLC_Utf8Buf(StringStripWS($sUrl, 3))
    Local $aM = DllCall($hVLC_Dll, "ptr:cdecl", "libvlc_media_new_location", "ptr", $oVLC_Inst, "ptr", DllStructGetPtr($tUrl))
    If @error Or Not IsArray($aM) Or Not $aM[0] Then Return 0
    Local $pMedia = $aM[0]
    _VLC_AddOptionUtf8($pMedia, ":no-video")
    ; Real-time transcoding of a network stream stutters when the buffers are small: use big ones for the recording only
    _VLC_AddOptionUtf8($pMedia, ":network-caching=5000")
    _VLC_AddOptionUtf8($pMedia, ":live-caching=5000")
    _VLC_AddOptionUtf8($pMedia, ":sout-mux-caching=3000")
    _VLC_AddOptionUtf8($pMedia, ":sout=" & $sSout)
    Local $aP = DllCall($hVLC_Dll, "ptr:cdecl", "libvlc_media_player_new_from_media", "ptr", $pMedia)
    DllCall($hVLC_Dll, "none:cdecl", "libvlc_media_release", "ptr", $pMedia)
    If @error Or Not IsArray($aP) Or Not $aP[0] Then Return 0
    Local $aPlay = DllCall($hVLC_Dll, "int:cdecl", "libvlc_media_player_play", "ptr", $aP[0])
    If @error Or Not IsArray($aPlay) Or $aPlay[0] <> 0 Then
        DllCall($hVLC_Dll, "none:cdecl", "libvlc_media_player_release", "ptr", $aP[0])
        _RadioRec_Log("play() failed for " & $sName & " | " & $sSout)
        Return 0
    EndIf
    $g_pRecPlayer = $aP[0]
    $g_sRadioRecFile = $sFile
    $g_bRecPassthrough = $bConv
    $g_sRecTsFile = ""
    If $bConv Then $g_sRecTsFile = $sOutFile
    $g_sRadioRecStation = $sName
    $g_hRadioRecStart = TimerInit()
    _RadioRec_Log("Recording started: " & $sName & " | " & $sUrl & " | " & $sSout)
    Return 1
EndFunc

; Stops the recording (VLC closes the file properly). Returns the path of the saved file, "" when nothing usable was
; recorded (an empty file is deleted), or "@CONVERTING" when the MP3 is being made from the saved stream in the
; background (_RadioRec_ConvPoll announces the result). Safe to call when nothing is recording.
Func _RadioRec_Stop()
    If $g_pRecPlayer = 0 Then Return ""
    Local $sFile = $g_sRadioRecFile, $sTs = $g_sRecTsFile, $bConv = $g_bRecPassthrough
    If $hVLC_Dll <> -1 Then
        DllCall($hVLC_Dll, "none:cdecl", "libvlc_media_player_stop", "ptr", $g_pRecPlayer)
        DllCall($hVLC_Dll, "none:cdecl", "libvlc_media_player_release", "ptr", $g_pRecPlayer)
    EndIf
    $g_pRecPlayer = 0
    $g_sRadioRecFile = ""
    $g_sRecTsFile = ""
    $g_bRecPassthrough = False
    If $bConv Then
        If FileExists($sTs) And FileGetSize($sTs) > 4096 Then
            If _RadioRec_ConvStart($sTs, $sFile, $g_sRadioRecStation) Then Return "@CONVERTING"
            _RadioRec_Log("Could not start ffmpeg to convert " & $sTs)
            Return $sTs ; the saved stream is still playable
        EndIf
        _RadioRec_Log("Nothing usable was recorded: " & $sTs)
        If FileExists($sTs) Then FileDelete($sTs)
        Return ""
    EndIf
    If FileExists($sFile) And FileGetSize($sFile) > 4096 Then Return $sFile
    _RadioRec_Log("Nothing usable was recorded: " & $sFile)
    If FileExists($sFile) Then FileDelete($sFile)
    Return ""
EndFunc

; True when the recording is made offline: MP3, or a recording volume below 100 (needs ffmpeg.exe)
Func _RadioRec_NeedConvert()
    If Not FileExists($FFMPEG_PATH) Then Return False
    Return ($g_sRadioRecFormat = "MP3" Or $g_iRadioRecVolume < 100)
EndFunc

; ffmpeg turns the saved stream into the chosen format and applies the recording volume (local file to local file:
; no network, no real-time constraints)
Func _RadioRec_ConvStart($sTs, $sFinal, $sTitle)
    Local $sCmd = '"' & $FFMPEG_PATH & '" -hide_banner -loglevel error -y -i "' & $sTs & '" -vn'
    Switch $g_sRadioRecFormat
        Case "M4A"
            $sCmd &= ' -c:a aac -b:a ' & $g_iRadioRecBitrate & 'k'
        Case "OGG"
            $sCmd &= ' -c:a libvorbis -b:a ' & $g_iRadioRecBitrate & 'k'
        Case "WAV"
            $sCmd &= ' -c:a pcm_s16le'
        Case Else
            $sCmd &= ' -c:a libmp3lame -b:a ' & $g_iRadioRecBitrate & 'k'
    EndSwitch
    $sCmd &= ' -ac ' & $g_iRadioRecChannels
    If $g_iRadioRecRate > 0 Then $sCmd &= ' -ar ' & $g_iRadioRecRate
    ; Same loudness as the radio slider: the radio sends 100*(v/100)^(1/3) to VLC and VLC applies the CUBE of that
    ; (its volume is cubic), so the radio volume is a plain linear gain v/100. The recording uses that same gain.
    If $g_iRadioRecVolume < 100 Then $sCmd &= ' -af volume=' & StringFormat("%.4f", $g_iRadioRecVolume / 100)
    $sCmd &= ' -metadata title="' & StringReplace($sTitle, '"', "'") & '" "' & $sFinal & '"'
    Local $iPid = Run($sCmd, @ScriptDir, @SW_HIDE, $STDERR_CHILD + $STDOUT_CHILD)
    If $iPid = 0 Then Return False
    If $g_iRecConvN >= UBound($g_aRecConv) Then ReDim $g_aRecConv[$g_iRecConvN + 1][4]
    $g_aRecConv[$g_iRecConvN][0] = $iPid
    $g_aRecConv[$g_iRecConvN][1] = $sTs
    $g_aRecConv[$g_iRecConvN][2] = $sFinal
    $g_aRecConv[$g_iRecConvN][3] = ""
    $g_iRecConvN += 1
    _RadioRec_Log("Converting to MP3: " & $sCmd)
    Return True
EndFunc

; Looks at the running conversions; each one that has finished is announced. $lblRec = label to update (or -1)
Func _RadioRec_ConvPoll($lblRec = -1)
    Local $i = 0, $iPid, $sTs, $sFinal, $sErr, $sMsg
    While $i < $g_iRecConvN
        $iPid = $g_aRecConv[$i][0]
        $g_aRecConv[$i][3] &= StderrRead($iPid) & StdoutRead($iPid)
        If ProcessExists($iPid) Then
            $i += 1
            ContinueLoop
        EndIf
        $g_aRecConv[$i][3] &= StderrRead($iPid)
        StdioClose($iPid)
        $sTs = $g_aRecConv[$i][1]
        $sFinal = $g_aRecConv[$i][2]
        $sErr = $g_aRecConv[$i][3]
        ; remove this entry from the list
        For $k = $i To $g_iRecConvN - 2
            For $m = 0 To 3
                $g_aRecConv[$k][$m] = $g_aRecConv[$k + 1][$m]
            Next
        Next
        $g_iRecConvN -= 1
        If FileExists($sFinal) And FileGetSize($sFinal) > 4096 Then
            If FileExists($sTs) Then FileDelete($sTs)
            If $lblRec <> -1 Then GUICtrlSetData($lblRec, _TF("Recording saved: {1}", $sFinal))
            _NVDA_Speak(_TF("Recording saved: {1}", _Radio_FileName($sFinal)))
        Else
            _RadioRec_Log("MP3 conversion failed for " & $sTs & ": " & $sErr)
            If FileExists($sFinal) Then FileDelete($sFinal)
            $sMsg = _TF("The conversion failed. The recording was kept as: {1}", _Radio_FileName($sTs))
            If $lblRec <> -1 Then GUICtrlSetData($lblRec, $sMsg)
            _NVDA_Speak($sMsg)
        EndIf
    WEnd
EndFunc

; Used when the app closes: give running conversions some time to finish (anything left is kept as .ts)
Func _RadioRec_ConvWait($iMaxMs)
    Local $hWait = TimerInit()
    While $g_iRecConvN > 0 And TimerDiff($hWait) < $iMaxMs
        _RadioRec_ConvPoll()
        Sleep(200)
    WEnd
EndFunc

; A .ts left in the recording folder is only a temporary file when the finished recording exists: delete those
Func _RadioRec_CleanupTemp()
    Local $hFind = FileFindFirstFile($g_sRadioRecPath & "\*.ts")
    If $hFind = -1 Then Return
    Local $sName, $sDone
    Local $aExt[4] = [".mp3", ".m4a", ".ogg", ".wav"]
    While 1
        $sName = FileFindNextFile($hFind)
        If @error Then ExitLoop
        For $sExt In $aExt
            $sDone = $g_sRadioRecPath & "\" & StringTrimRight($sName, 3) & $sExt
            If FileExists($sDone) And FileGetSize($sDone) > 4096 Then
                FileDelete($g_sRadioRecPath & "\" & $sName)
                ExitLoop
            EndIf
        Next
    WEnd
    FileClose($hFind)
EndFunc

; ======================================================================
;  SLEEP TIMER (shared by the Player and the Radio): closes the app, optionally fading the volume out first
; ======================================================================
; Volume straight to libvlc (0-100 = libvlc scale, not the UI scale)
Func _VLC_Direct_SetVolumeRaw($iVLCVol)
    If Not $oVLC_Player Then Return
    DllCall($hVLC_Dll, "int:cdecl", "libvlc_audio_set_volume", "ptr", $oVLC_Player, "int", $iVLCVol)
EndFunc

; Put the volume back to the normal level after a fade-out was started (timer changed or cancelled)
Func _SleepTimer_EndFade()
    $g_bSleepFading = False
    _VLC_Direct_SetVolume($g_iAppVolume)
EndFunc

; Call often from the loop of the Player and of the Radio window
Func _SleepTimer_Tick()
    If $g_iSleepTimerDuration <= 0 Then
        If $g_bSleepFading Then _SleepTimer_EndFade()
        Return
    EndIf
    Local $fElapsed = TimerDiff($g_hSleepTimerInit)
    If $fElapsed >= $g_iSleepTimerDuration Then
        _ReportStatus(_T("Sleep timer reached. Exiting application."))
        Sleep(1500) ; give the screen reader time to read the message
        _Quit_App() ; plays doorclose.wav, hides every window and ends the process
        Exit
    EndIf
    If Not $g_bSleepFade Then Return
    Local $iFadeMs = $g_iSleepFadeSecs * 1000
    If $iFadeMs > $g_iSleepTimerDuration Then $iFadeMs = $g_iSleepTimerDuration
    Local $fRemain = $g_iSleepTimerDuration - $fElapsed
    If $fRemain > $iFadeMs Then Return
    If TimerDiff($g_hSleepFadeTimer) < 200 Then Return
    $g_hSleepFadeTimer = TimerInit()
    $g_bSleepFading = True
    ; fade straight down from the current libvlc volume to 0 (linear in the libvlc scale sounds even to the ear)
    _VLC_Direct_SetVolumeRaw(Round(_VolumeUIToVLC($g_iAppVolume) * $fRemain / $iFadeMs))
EndFunc

Func _ShowSleepTimerDialog($hParent = 0)
    If $hParent = 0 Then $hParent = $hPlayGui
    Local $hSleepGui = GUICreate(_T("Sleep Timer"), 300, 215, -1, -1, BitOR($WS_CAPTION, $WS_SYSMENU), $WS_EX_TOPMOST, $hParent)
    GUISetBkColor($COLOR_BLUE)

    GUICtrlCreateLabel(_T("Enter time to exit the app (0 min & 0 sec to disable):"), 10, 15, 280, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)

    GUICtrlCreateLabel(_T("Minutes:"), 20, 45, 60, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $inpMin = GUICtrlCreateInput("0", 80, 42, 60, 20, $ES_NUMBER)

    GUICtrlCreateLabel(_T("Seconds:"), 160, 45, 60, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $inpSec = GUICtrlCreateInput("0", 220, 42, 60, 20, $ES_NUMBER)

    Local $chkFade = GUICtrlCreateCheckbox(_T("Fade out the volume before closing"), 20, 82, 270, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    If $g_bSleepFade Then GUICtrlSetState(-1, $GUI_CHECKED)
    GUICtrlCreateLabel(_T("Fade duration (seconds):"), 40, 114, 150, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $inpFade = GUICtrlCreateInput(String($g_iSleepFadeSecs), 195, 111, 60, 20, $ES_NUMBER)
    If Not $g_bSleepFade Then GUICtrlSetState($inpFade, $GUI_DISABLE)

    Local $btnSet = GUICtrlCreateButton(_T("Set Timer"), 20, 155, 120, 30)
    GUICtrlSetState(-1, $GUI_DEFBUTTON)
    Local $btnCancel = GUICtrlCreateButton(_T("Cancel"), 160, 155, 120, 30)

    Local $hDummyEsc = GUICtrlCreateDummy()
    Local $aAccel[1][2] = [["{ESC}", $hDummyEsc]]
    GUISetAccelerators($aAccel, $hSleepGui)

    GUISetState(@SW_SHOW, $hSleepGui)
    _AllowUIPI($hSleepGui)
    _AllowUIPI($inpMin)
    _AllowUIPI($inpSec)
    _AllowUIPI($inpFade)
    ControlFocus($hSleepGui, "", $inpMin)
    GUICtrlSendMsg($inpMin, 0x00B1, 0, -1) ; select the text inside

    Local $nMsg, $iMins, $iSecs, $iTotalSecs, $iFadeSecs
    While 1
        $nMsg = _GuiMsg($hSleepGui)
        Switch $nMsg
            Case $GUI_EVENT_CLOSE, $btnCancel, $hDummyEsc
                GUIDelete($hSleepGui)
                Return
            Case $chkFade
                If GUICtrlRead($chkFade) = $GUI_CHECKED Then
                    GUICtrlSetState($inpFade, $GUI_ENABLE)
                Else
                    GUICtrlSetState($inpFade, $GUI_DISABLE)
                EndIf
            Case $btnSet
                $iMins = Int(GUICtrlRead($inpMin))
                $iSecs = Int(GUICtrlRead($inpSec))
                $iTotalSecs = ($iMins * 60) + $iSecs
                $g_bSleepFade = (GUICtrlRead($chkFade) = $GUI_CHECKED)
                $iFadeSecs = Int(GUICtrlRead($inpFade))
                If $iFadeSecs < 1 Then $iFadeSecs = 1
                If $iFadeSecs > 600 Then $iFadeSecs = 600
                $g_iSleepFadeSecs = $iFadeSecs
                IniWrite($CONFIG_FILE, "Settings", "SleepFade", $g_bSleepFade ? "true" : "false")
                IniWrite($CONFIG_FILE, "Settings", "SleepFadeSecs", String($g_iSleepFadeSecs))
                If $g_bSleepFading Then _SleepTimer_EndFade() ; a fade that was already running starts over with the new timer
                If $iTotalSecs > 0 Then
                    $g_iSleepTimerDuration = $iTotalSecs * 1000
                    $g_hSleepTimerInit = TimerInit()
                    _ReportStatus(_TF("Sleep timer set for {1} minutes and {2} seconds. App will close after this.", $iMins, $iSecs))
                Else
                    $g_iSleepTimerDuration = 0
                    _ReportStatus(_T("Sleep timer disabled."))
                EndIf
                GUIDelete($hSleepGui)
                Return
        EndSwitch
    WEnd
EndFunc

; ======================================================================
;  RADIO WINDOW HELPERS
; ======================================================================
; Add one accelerator row (controls that do not exist in the current mode have the id -9999 and are skipped)
Func _Radio_AccAdd(ByRef $aAcc, ByRef $n, $sKey, $id)
    If $id = -9999 Then Return
    If $n >= UBound($aAcc) Then ReDim $aAcc[$n + 8][2]
    $aAcc[$n][0] = $sKey
    $aAcc[$n][1] = $id
    $n += 1
EndFunc

; Install the accelerator table. Page Up / Page Down (previous / next station) are only added while a station is
; playing, so the list keeps its normal paging keys when nothing is playing.
Func _Radio_ApplyAccel($hGui, ByRef $aAcc, $nAcc, $bPaging, $idPgUp, $idPgDn)
    Local $aOut[$nAcc + 2][2], $n = 0
    For $i = 0 To $nAcc - 1
        $aOut[$n][0] = $aAcc[$i][0]
        $aOut[$n][1] = $aAcc[$i][1]
        $n += 1
    Next
    If $bPaging Then
        $aOut[$n][0] = "{PGUP}"
        $aOut[$n][1] = $idPgUp
        $n += 1
        $aOut[$n][0] = "{PGDN}"
        $aOut[$n][1] = $idPgDn
        $n += 1
    EndIf
    ReDim $aOut[$n][2]
    GUISetAccelerators($aOut, $hGui)
EndFunc

Func _Radio_IdAdd(ByRef $a, $id)
    If $id = -9999 Then Return
    ReDim $a[UBound($a) + 1]
    $a[UBound($a) - 1] = $id
EndFunc

Func _Radio_FillStations($idList, ByRef $aSt, $iCount)
    GUICtrlSetData($idList, "")
    If $iCount <= 0 Then Return
    Local $sBatch = ""
    For $i = 0 To $iCount - 1
        $sBatch &= ($i + 1) & ". " & _Radio_StationLabel($aSt, $i) & "|"
    Next
    GUICtrlSetData($idList, StringTrimRight($sBatch, 1))
EndFunc

; Favorites window: read the file again into $aSt, refill the list and keep the selection near $iKeep
Func _Radio_ReloadFav($idList, ByRef $aSt, ByRef $iCount, $iKeep)
    $aSt = _RadioFav_Load()
    $iCount = IsArray($aSt) ? UBound($aSt) : 0
    _Radio_FillStations($idList, $aSt, $iCount)
    If $iCount > 0 Then
        If $iKeep >= $iCount Then $iKeep = $iCount - 1
        If $iKeep < 0 Then $iKeep = 0
        _GUICtrlListBox_SetCurSel($idList, $iKeep)
    EndIf
EndFunc

Func _Radio_FileName($sPath)
    Return StringRegExpReplace($sPath, "^.*[\\/]", "")
EndFunc

; Record button text and the red recording line
Func _Radio_RecUpdateUI($btnRec, $lblRec)
    If _RadioRec_Active() Then
        GUICtrlSetData($btnRec, _T("Stop recording (Ctrl+R)"))
        GUICtrlSetData($lblRec, _TF("Recording: {1}", $g_sRadioRecStation))
    Else
        GUICtrlSetData($btnRec, _T("Record (Ctrl+R)"))
    EndIf
EndFunc

; Radio Player > Favorite Stations (main menu): same window as the station list, filled with the favorites
Func _ShowRadioFavorites()
    If Not _VLC_Direct_Init() Then
        MsgBox(16, _T("Error"), _T("Could not initialize libvlc.dll. Please ensure VLC DLLs are present in the lib folder."))
        Return
    EndIf
    If Not IsArray(_RadioFav_Load()) Then
        MsgBox(64, _T("Favorite Stations"), _T("You have no favorite stations yet. Open the Radio Player, select a station and press Ctrl+D to add it."))
        Return
    EndIf
    _Radio_StationsWindow("", "", _T("Favorite Stations"), True)
    _RadioRec_Stop()
    _VLC_Direct_Stop()
    _Pan_Reset()
EndFunc

Func _SaveSelection($sUrl, $sTitle)
    Local $fStart = $g_fSelectionStart
    Local $fEnd = $g_fSelectionEnd

    If $fStart = -1 Or $fEnd = -1 Then
        _ReportStatus(_T("Error: Please set both start [ and end ] points."))
        Return
    EndIf

    If $fStart > $fEnd Then
        Local $tmp = $fStart
        $fStart = $fEnd
        $fEnd = $tmp
        _ReportStatus(_T("Start/End swapped to match timeline."))
    EndIf

    Local $fDuration = $fEnd - $fStart
    If $fDuration <= 0 Then
        _ReportStatus(_T("Invalid selection duration."))
        Return
    EndIf

    Local $sSafeTitle = StringRegExpReplace($sTitle, '[\\/:*?"<>|]', '_')

    ; Redesigned Save Selection: Use FileSaveDialog to let user choose name, type and path
    Local $sFilter = "Video MP4 (*.mp4)|Video WebM (*.webm)|MP3 Audio (*.mp3)|M4A Audio (*.m4a)|WAV Audio (*.wav)|FLAC Audio (*.flac)|Ogg Audio (*.ogg)|All Files (*.*)"
    Local $sInitialDir = $g_sDownloadPath
    If StringStripWS($sInitialDir, 3) = "" Or Not FileExists($sInitialDir) Then $sInitialDir = @ScriptDir & "\download"
    If Not FileExists($sInitialDir) Then DirCreate($sInitialDir)

    Local $sFilePath = FileSaveDialog(_T("Save selection as..."), $sInitialDir, $sFilter, 18, $sSafeTitle & ".mp4", $hPlayGui)
    If @error Then
        _ReportStatus(_T("Save cancelled."))
        Return
    EndIf

    ; Ensure correct extension if user didn't type it
    Local $sVideoCodec = "-vn"
    Local $sAudioCodec = "-c:a libmp3lame -q:a 2" ; Default MP3

    If StringRegExp($sFilePath, "(?i)\.mp4$") Then
        $sVideoCodec = "-c:v copy"
        $sAudioCodec = "-c:a aac"
    ElseIf StringRegExp($sFilePath, "(?i)\.webm$") Then
        $sVideoCodec = "-c:v copy"
        $sAudioCodec = "-c:a libopus"
    ElseIf StringRegExp($sFilePath, "(?i)\.m4a$") Then
        $sAudioCodec = "-c:a aac -b:a 192k"
    ElseIf StringRegExp($sFilePath, "(?i)\.wav$") Then
        $sAudioCodec = "-c:a pcm_s16le"
    ElseIf StringRegExp($sFilePath, "(?i)\.flac$") Then
        $sAudioCodec = "-c:a flac"
    ElseIf StringRegExp($sFilePath, "(?i)\.ogg$") Then
        $sAudioCodec = "-c:a libvorbis -q:a 4"
    ElseIf Not StringRegExp($sFilePath, "(?i)\.mp3$") Then
        ; If no known extension, append .mp4 as default and use mp4 codecs
        $sFilePath &= ".mp4"
        $sVideoCodec = "-c:v copy"
        $sAudioCodec = "-c:a aac"
    EndIf

    _ReportStatus(_T("Saving selection... Please wait."))

    Local $sFFmpeg = @ScriptDir & "\lib\ffmpeg.exe"
    If Not FileExists($sFFmpeg) Then
        MsgBox(16, _T("Error"), _T("ffmpeg.exe not found in lib folder!"))
        Return
    EndIf

    ; ffmpeg command with dynamic codec selection
    Local $sCmd = '"' & $sFFmpeg & '" -reconnect 1 -reconnect_at_eof 1 -reconnect_streamed 1 -reconnect_delay_max 2 -ss ' & $fStart & ' -to ' & $fEnd & ' -i "' & $sUrl & '" ' & $sVideoCodec & ' ' & $sAudioCodec & ' -y "' & $sFilePath & '"'
    Local $iPid = Run($sCmd, @ScriptDir, @SW_HIDE)

    Local $iBeginWait = TimerInit()
    While ProcessExists($iPid)
        GUIGetMsg()
        Sleep(10)
        ; Safety timeout 10 mins
        If TimerDiff($iBeginWait) > 600000 Then
            ProcessClose($iPid)
            ExitLoop
        EndIf
    WEnd

    If FileExists($sFilePath) And FileGetSize($sFilePath) > 1000 Then
        _ReportStatus(_T("Selection saved successfully."))
        MsgBox(64, _T("Success"), _TF("Selection saved successfully as:\n{1}", $sFilePath), 0, $hPlayGui)
    Else
        _ReportStatus(_T("Failed to save selection."))
        MsgBox(16, _T("Error"), _T("Failed to save selection. This can happen if the YouTube stream link expired or ffmpeg was blocked."), 0, $hPlayGui)
    EndIf
EndFunc

Func _FormatTime($fSeconds)
    Local $iSec = Int($fSeconds)
    Local $iMin = Int($iSec / 60)
    Local $iHour = Int($iMin / 60)
    $iMin = Mod($iMin, 60)
    $iSec = Mod($iSec, 60)
    If $iHour > 0 Then
        Return StringFormat("%02d:%02d:%02d", $iHour, $iMin, $iSec)
    Else
        Return StringFormat("%02d:%02d", $iMin, $iSec)
    EndIf
EndFunc

; Spoken-word duration format for screen-reader announcements, e.g.:
; 2            -> "2 seconds"
; 293          -> "4 minutes  53 seconds"
; 3722         -> "1 hour  2 minutes  2 seconds"
Func _FormatTimeSpoken($fSeconds)
    Local $iSec = Int($fSeconds)
    Local $iHour = Int($iSec / 3600)
    Local $iMin = Int(Mod($iSec, 3600) / 60)
    $iSec = Mod($iSec, 60)

    Local $sResult = ""
    If $iHour > 0 Then
        $sResult &= $iHour & _Ternary($iHour = 1, " " & _T("hour"), " " & _T("hours")) & "  "
    EndIf
    If $iHour > 0 Or $iMin > 0 Then
        $sResult &= $iMin & _Ternary($iMin = 1, " " & _T("minute"), " " & _T("minutes")) & "  "
    EndIf
    $sResult &= $iSec & _Ternary($iSec = 1, " " & _T("second"), " " & _T("seconds"))
    Return $sResult
EndFunc

Func _FormatBytes($iBytes)
    Local $aUnits = [_T("Bytes"), "KB", "MB", "GB", "TB"]
    Local $i = 0
    While $iBytes >= 1024 And $i < 4
        $iBytes /= 1024
        $i += 1
    WEnd
    Return Round($iBytes, 2) & " " & $aUnits[$i]
EndFunc

Func online_play($url)
    ShellExecute($url)
EndFunc

Func _ReportStatus($sText, $bIsVolume = False, $bIsPan = False)
    If $sText == "" Then Return

    ; Classify the message by its ENGLISH text (_TR maps a translated string back to its
    ; English key) so the checks below keep working in every language.
    Local $sLow = StringLower(_TR($sText))
    Local $isTime = StringRegExp($sText, "^\d+:\d+(:\d+)?$")
    Local $isVolume = ($bIsVolume Or StringInStr($sLow, "volume"))
    ; Pan (vd "5%") cung co dang "so%" nen phai loai ra, neu khong se bi coi la phan tram tua nhac va bi im khi che do thong bao khong doc phan tram
    Local $isPercent = (Not $bIsPan) And StringRegExp($sText, "^\d+%$")
    Local $isHomeEnd = (StringInStr($sLow, "near end") Or StringInStr($sLow, "restart from beginning"))

    ; Bug fix for Skip silence: when checked, Home/End should also be silent
    If $g_bSkipSilence Then
        If $isVolume Or $sLow == "play" Or $sLow == "pause" Or $isTime Or $isHomeEnd Then
            Return
        EndIf
    EndIf

    ; Seeking Announcement Mode
    Select
        Case $g_iAnnouncementMode == 0 ; Silent
            If ($isTime Or $isPercent) And Not $isHomeEnd Then Return
        Case $g_iAnnouncementMode == 1 ; Read percentage
            If $isTime And Not $isHomeEnd Then Return
        Case $g_iAnnouncementMode == 2 ; Read time
            If $isPercent And Not $isHomeEnd Then Return
    EndSelect

    ; Suppress duplicates within 1s to be safe
    If StringLower($sText) = StringLower($g_sLastReportedText) And TimerDiff($g_iLastReportedTime) < 1000 Then Return
    $g_sLastReportedText = $sText
    $g_iLastReportedTime = TimerInit()

    ; Update the visual status label on the GUI
    If IsHWnd($hPlayGui) And $g_hStatusLabel <> 0 Then
        GUICtrlSetData($g_hStatusLabel, $sText)
        AdlibRegister("_ClearToolTip", 2000)
    EndIf

    ; speak it explicitly
    _NVDA_Speak($sText)
EndFunc

Func _NVDA_Speak($sText)
    ; Thử khởi tạo DLL nếu chưa có hoặc đã bị đóng
    If $g_hNVDADll = -1 Then
        Local $sDllName = @AutoItX64 ? "nvdaControllerClient64.dll" : "nvdaControllerClient32.dll"
        Local $sDllPath = @ScriptDir & "\lib\" & $sDllName
        $g_hNVDADll = DllOpen($sDllPath)
    EndIf

    Local $bNVDASuccess = False

    If $g_hNVDADll <> -1 Then
        ; Gọi trực tiếp nvdaController_speakText để thông báo cho NVDA
        Local $aRet = DllCall($g_hNVDADll, "int", "nvdaController_speakText", "wstr", $sText)
        If Not @error And IsArray($aRet) And $aRet[0] = 0 Then
            $bNVDASuccess = True
        EndIf
    EndIf

    ; Nếu NVDA không khả dụng hoặc lỗi, không sử dụng SAPI 5 làm phương án dự phòng (yêu cầu người dùng)
    ; If Not $bNVDASuccess Then
    ;    If Not IsObj($oVoice) Then $oVoice = ObjCreate("SAPI.SpVoice")
    ;    If IsObj($oVoice) Then $oVoice.Speak($sText, 1) ; 1 = Async
    ; EndIf

    Return $bNVDASuccess
EndFunc

; Phát file âm thanh của ứng dụng (thư mục sounds) - bị tắt khi bật "Turn off sound in application"
Func _AppSoundPlay($sFile, $iWait = 0)
    If $g_bMuteAppSounds Then Return 0
    Return SoundPlay($sFile, $iWait)
EndFunc

; ---- Download sound: sounds\downloading.wav loops from the moment a download starts (after download-started.wav
; has finished) until _DLSound_Stop is called, right before download_finish.wav plays or when the download is cancelled.
; If the file does not exist nothing is played. _DLSound_Start is safe to call again (batches of downloads).
Func _DLSound_Start()
    If $g_bDLSoundWanted Then Return
    $g_bDLSoundWanted = True
    $g_bDLSoundOn = False
    $g_iDLSoundDelay = 0
    Local $sStarted = @ScriptDir & "\sounds\download-started.wav"
    If Not $g_bMuteAppSounds And FileExists($sStarted) Then $g_iDLSoundDelay = _WavDurationMs($sStarted) + 100
    $g_hDLSoundAt = TimerInit()
    _DLSound_Tick()
EndFunc

; Call from the loops that wait for a download (cheap): starts the loop once the start sound is over
Func _DLSound_Tick()
    If Not $g_bDLSoundWanted Or $g_bDLSoundOn Then Return
    If TimerDiff($g_hDLSoundAt) < $g_iDLSoundDelay Then Return
    $g_bDLSoundOn = True
    If $g_bMuteAppSounds Then Return
    Local $sFile = @ScriptDir & "\sounds\downloading.wav"
    If Not FileExists($sFile) Then Return
    $g_bDLSoundReal = True
    DllCall("winmm.dll", "bool", "PlaySoundW", "wstr", $sFile, "ptr", 0, "dword", 0x00020009) ; SND_FILENAME | SND_LOOP | SND_ASYNC
EndFunc

Func _DLSound_Stop()
    $g_bDLSoundWanted = False
    $g_bDLSoundOn = False
    If Not $g_bDLSoundReal Then Return
    $g_bDLSoundReal = False
    DllCall("winmm.dll", "int", "PlaySoundW", "ptr", 0, "ptr", 0, "dword", 0) ; stop
EndFunc

; Loi chao theo gio trong ngay (dung cho hop thoai chao mung luc mo cua va man hinh chinh)
Func _GetGreeting()
    If @HOUR < 12 Then Return _T("Good morning")
    If @HOUR < 18 Then Return _T("Good afternoon")
    If @HOUR < 22 Then Return _T("Good evening")
    Return _T("Good night")
EndFunc

; Do dai (ms) cua file WAV, doc tu header; khong doc duoc thi uoc luong tu kich thuoc file
Func _WavDurationMs($sFile)
    Local $iDur = Int(FileGetSize($sFile) / 176.4) ; gia dinh 44.1kHz 16-bit stereo
    Local $h = FileOpen($sFile, 16)
    If $h = -1 Then Return $iDur
    Local $bData = FileRead($h, 4096)
    FileClose($h)
    Local $iLen = BinaryLen($bData)
    If $iLen < 44 Then Return $iDur
    Local $tBuf = DllStructCreate("byte[" & $iLen & "]")
    DllStructSetData($tBuf, 1, $bData)
    Local $pBase = DllStructGetPtr($tBuf)
    Local $iByteRate = 0, $iDataSize = 0, $iPos = 12
    While $iPos + 8 <= $iLen
        Local $tChunk = DllStructCreate("char id[4]; dword size", $pBase + $iPos)
        Local $sId = DllStructGetData($tChunk, "id"), $iSize = DllStructGetData($tChunk, "size")
        If $sId = "fmt " And $iPos + 8 + 12 <= $iLen Then
            Local $tFmt = DllStructCreate("ushort fmt; ushort ch; dword rate; dword byterate", $pBase + $iPos + 8)
            $iByteRate = DllStructGetData($tFmt, "byterate")
        ElseIf $sId = "data" Then
            $iDataSize = $iSize
            ExitLoop
        EndIf
        $iPos += 8 + $iSize + Mod($iSize, 2)
    WEnd
    If $iByteRate > 0 And $iDataSize > 0 Then
        ; data chunk co the khai bao qua lon (file stream) -> gioi han theo kich thuoc that cua file
        Local $iReal = FileGetSize($sFile) - $iPos - 8
        If $iDataSize > $iReal Then $iDataSize = $iReal
        Return Int($iDataSize * 1000 / $iByteRate)
    EndIf
    Return $iDur
EndFunc

; Mo cua: phat dooropen.wav va doi den khi am thanh phat xong (khong con hop thoai chao mung).
Func _Play_DoorOpen_Welcome()
    Local $sFile = @ScriptDir & "\sounds\dooropen.wav"
    If $g_bMuteAppSounds Or Not FileExists($sFile) Then Return
    Local $iWait = _WavDurationMs($sFile) + 150
    DllCall("winmm.dll", "bool", "PlaySoundW", "wstr", $sFile, "ptr", 0, "dword", 0x00020003) ; async
    Local $hTimer = TimerInit()
    While TimerDiff($hTimer) < $iWait
        Sleep(20)
    WEnd
EndFunc

; Thoat phan mem DUT KHOAT. Ham nay KHONG tro ve.
; Truoc day: phat doorclose.wav roi Exit -> cua so van hien, nhac van phat, AutoIt lai di qua buoc don dep
; (huy GUI, nha DLL VLC, go hook...) va Sleep cho het am thanh nen cam giac thoat rat cham.
; Bay gio: (1) bat dau phat doorclose.wav, (2) AN NGAY moi cua so + tat tieng nhac + dong tien trinh phu
; -> phan mem "bien mat" ngay lap tuc, (3) cho dung do dai tieng cua dong, (4) ket thuc tien trinh ngay
; bang ProcessClose(@AutoItPID) (TerminateProcess) - Windows tu thu hoi moi tai nguyen.
Func _Quit_App()
    _Pan_Reset()
    ; Khong cho tieng go phim chen len doorclose.wav (PlaySound chi co 1 kenh, am thanh sau se cat am thanh truoc)
    $g_bTypingSoundEnabled = False

    ; Do dai tieng cua dong (doc truoc khi phat de khong lam tre luc bat dau phat)
    Local $sFile = @ScriptDir & "\sounds\doorclose.wav"
    Local $iDur = 0
    If Not $g_bMuteAppSounds And FileExists($sFile) Then $iDur = _WavDurationMs($sFile) + 40

    ; (1) Phat doorclose.wav (async) va bat dau tinh gio
    Local $hTimer = 0
    If $iDur > 0 Then
        DllCall("winmm.dll", "bool", "PlaySoundW", "wstr", $sFile, "ptr", 0, "dword", 0x00020003)
        $hTimer = TimerInit()
    EndIf

    ; (2) An icon khay + an moi cua so cua phan mem ngay lap tuc
    TraySetState(2)
    Local $aWins = WinList()
    For $i = 1 To $aWins[0][0]
        If WinGetProcess($aWins[$i][1]) = @AutoItPID Then WinSetState($aWins[$i][1], "", @SW_HIDE)
    Next

    ; Tat tieng nhac dang phat de khong tron lan voi tieng cua dong (KHONG goi stop/release/DllClose de tranh treo)
    If $oVLC_Player <> 0 And $hVLC_Dll <> -1 Then _
        DllCall($hVLC_Dll, "int:cdecl", "libvlc_audio_set_volume", "ptr", $oVLC_Player, "int", 0)

    _RadioRec_Stop() ; let VLC finish a radio recording properly (closes the file) before the app ends
    _RadioRec_ConvWait(30000) ; and let ffmpeg finish an MP3 that is being made
    ProcessClose("comments.exe")
    ProcessClose("description.exe")
    ProcessClose("voice_search.exe")
    ProcessClose("youtube_transcript.exe")

    ; Diet moi tien trinh con (yt-dlp, ffmpeg quet silence, deno, ...) de khong con tien trinh mo coi
    ; nao con giu file/ban quyen sau khi nguoi dung thay app da "thoat".
    _KillChildProcesses()

    ; NHA mutex "1 ban chay" NGAY: tu day ban moi (bam Enter chay lai) khong con bi chan boi ban cu
    ; dang cho het tieng doorclose.wav.
    If $g_hSingletonMutex <> 0 Then
        DllCall("kernel32.dll", "bool", "ReleaseMutex", "handle", $g_hSingletonMutex)
        DllCall("kernel32.dll", "bool", "CloseHandle", "handle", $g_hSingletonMutex)
        $g_hSingletonMutex = 0
    EndIf

    ; (3) Cho dung do dai tieng cua dong
    If $hTimer <> 0 Then
        While TimerDiff($hTimer) < $iDur
            Sleep(5)
        WEnd
    EndIf

    ; (4) Ket thuc ngay, khong di qua buoc don dep cham cua AutoIt
    ProcessClose(@AutoItPID)
    Exit ; du phong, thuong khong bao gio toi day
EndFunc

; Diet TOAN BO tien trinh con chau cua chinh phan mem nay (chup 1 snapshot duy nhat -> rat nhanh).
Func _KillChildProcesses()
    Local $aSnap = DllCall("kernel32.dll", "handle", "CreateToolhelp32Snapshot", "dword", 0x2, "dword", 0)
    If @error Or Not IsArray($aSnap) Or $aSnap[0] = 0 Or $aSnap[0] = -1 Then Return
    Local $hSnap = $aSnap[0]
    Local $tPE = DllStructCreate("dword;dword;dword;ulong_ptr;dword;dword;dword;long;dword;wchar[260]")
    DllStructSetData($tPE, 1, DllStructGetSize($tPE))
    Local $aPid[1024], $aPpid[1024], $iN = 0
    Local $aR = DllCall("kernel32.dll", "bool", "Process32FirstW", "handle", $hSnap, "struct*", $tPE)
    While Not @error And IsArray($aR) And $aR[0]
        If $iN >= UBound($aPid) Then
            ReDim $aPid[$iN * 2]
            ReDim $aPpid[$iN * 2]
        EndIf
        $aPid[$iN] = DllStructGetData($tPE, 3)
        $aPpid[$iN] = DllStructGetData($tPE, 7)
        $iN += 1
        $aR = DllCall("kernel32.dll", "bool", "Process32NextW", "handle", $hSnap, "struct*", $tPE)
    WEnd
    DllCall("kernel32.dll", "bool", "CloseHandle", "handle", $hSnap)

    ; Tim moi hau due cua @AutoItPID
    Local $sSet = "|" & @AutoItPID & "|"
    Local $bChanged = True
    While $bChanged
        $bChanged = False
        For $i = 0 To $iN - 1
            If $aPid[$i] <> 0 And StringInStr($sSet, "|" & $aPpid[$i] & "|") And Not StringInStr($sSet, "|" & $aPid[$i] & "|") Then
                $sSet &= $aPid[$i] & "|"
                $bChanged = True
            EndIf
        Next
    WEnd
    Local $aKill = StringSplit(StringTrimRight(StringTrimLeft($sSet, 1), 1), "|", 2)
    For $i = 0 To UBound($aKill) - 1
        If Number($aKill[$i]) <> @AutoItPID Then ProcessClose(Number($aKill[$i]))
    Next
EndFunc

; Phat am thanh va CHO den khi phat xong (dung cho dooropen.wav / doorclose.wav). Bi tat khi bat "Turn off sound in application".
Func _AppSoundPlaySync($sFile)
    If $g_bMuteAppSounds Or Not FileExists($sFile) Then Return 0
    ; SND_SYNC (0x0) | SND_NODEFAULT (0x2) | SND_FILENAME (0x00020000)
    Return DllCall("winmm.dll", "int", "PlaySoundW", "wstr", $sFile, "ptr", 0, "dword", 0x00020002)
EndFunc

Func _AppPlaySoundW($sFile, $iFlags)
    If $g_bMuteAppSounds Then Return 0
    Return DllCall("winmm.dll", "int", "PlaySoundW", "wstr", $sFile, "ptr", 0, "dword", $iFlags)
EndFunc

Func _GlobalSoundPlay($sFile, $sSoundSet)
    If $sFile = "" Then Return
    ; Âm thanh hệ thống (enter.wav...) bị tắt theo tùy chọn; âm thanh bàn phím vẫn do tùy chọn riêng quản lý
    If $g_bMuteAppSounds And $sSoundSet = "system" Then Return

    ; Khóa âm thanh 20ms để phản hồi nhanh hơn khi gõ nhanh
    If TimerDiff($g_iSoundLock) < 20 Then Return
    $g_iSoundLock = TimerInit()

    ; SND_ASYNC (0x0001) | SND_NODEFAULT (0x0002) | SND_FILENAME (0x00020000)
    DllCall("winmm.dll", "bool", "PlaySoundW", "wstr", $sFile, "ptr", 0, "dword", 0x00020003)
EndFunc

Func _PlayTypingSound($vkCode)
    If Not $g_bTypingSoundEnabled Then Return

    ; Phân loại phím để tránh phát âm thanh cho phím chức năng không mong muốn
    Local $bAllowed = False
    If ($vkCode >= 48 And $vkCode <= 57) Or _ ; Digits 0-9
       ($vkCode >= 65 And $vkCode <= 90) Or _ ; Letters A-Z
       ($vkCode >= 96 And $vkCode <= 105) Or _ ; Numpad digits 0-9
       ($vkCode >= 0xBA And $vkCode <= 0xC0) Or _ ; Punctuation: ;=,-./`
       ($vkCode >= 0xDB And $vkCode <= 0xDE) Or _ ; Punctuation: [\]'
       ($vkCode >= 106 And $vkCode <= 111) Or _ ; Numpad operators: *+,-./ (0x6A-0x6F)
       ($vkCode = 0x08) Or ($vkCode = 0x20) Or ($vkCode = 0x2E) Then ; Backspace, Space, Delete
        $bAllowed = True
    EndIf

    If Not $bAllowed Then Return

    Local $sFile = ""
    Switch $vkCode
        Case 0x08, 0x2E ; Backspace, Delete
            $sFile = $g_sSoundFile_Delete
        Case 0x20 ; Space
            $sFile = $g_sSoundFile_Space
        Case Else
            If $g_sTypingSoundSet = "VDH_keyboard1" Or $g_sTypingSoundSet = "VDH_keyboard2" Then
                $sFile = $g_sTypingSoundDir & "type" & Random(1, 10, 1) & ".wav"
            ElseIf $g_bTypingSoundRandom Then
                $sFile = $g_sTypingSoundDir & "typing_" & Random(1, 5, 1) & ".wav"
            Else
                $sFile = $g_sSoundFile_Typing
            EndIf
    EndSwitch

    _GlobalSoundPlay($sFile, $g_sTypingSoundSet)
EndFunc

Func _ClearToolTip()
    If IsHWnd($hPlayGui) And $g_hStatusLabel <> 0 Then
        GUICtrlSetData($g_hStatusLabel, "")
    EndIf
    AdlibUnRegister("_ClearToolTip")
EndFunc

Func _Show_About_Window()
    Local $gui = GUICreate(_T("About"), 520, 300)
    GUISetBkColor($COLOR_BLUE)
    Local $txtAbout = FileExists(@ScriptDir & "\docs\about.txt") ? FileRead(@ScriptDir & "\docs\about.txt") : "VDH Media Center"
    Local $idEdit = GUICtrlCreateEdit($txtAbout, 10, 10, 400, 280, BitOR($ES_READONLY, $WS_VSCROLL))
    Local $btn_Close = GUICtrlCreateButton(_T("Close"), 420, 10, 80, 35)
    GUICtrlSetState(-1, $GUI_DEFBUTTON)

    ; Thiết lập phím tắt để điều hướng giữa các thành phần
    Local $dummy_tab = GUICtrlCreateDummy()
    Local $aAccel[2][2] = [["{TAB}", $dummy_tab], ["+{TAB}", $dummy_tab]]
    GUISetAccelerators($aAccel, $gui)

    GUISetState(@SW_SHOW, $gui)

    While 1
        Local $msg = _GuiMsg($gui)
        Switch $msg
            Case $GUI_EVENT_CLOSE, $btn_Close
                GUIDelete($gui)
                ExitLoop
            Case $dummy_tab
                ; Chuyển đổi tiêu điểm giữa nút Close và ô nhập liệu
                If ControlGetHandle($gui, "", ControlGetFocus($gui)) = GUICtrlGetHandle($idEdit) Then
                    ControlFocus($gui, "", $btn_Close)
                Else
                    ControlFocus($gui, "", $idEdit)
                EndIf
        EndSwitch
    WEnd
EndFunc

Func _Show_Readme_Window()
    Local $gui = GUICreate(_T("Read Me"), 520, 300)
    GUISetBkColor($COLOR_BLUE)
    Local $txtRead = FileExists(@ScriptDir & "\docs\readme.txt") ? FileRead(@ScriptDir & "\docs\readme.txt") : "Read Me"
    Local $idEdit = GUICtrlCreateEdit($txtRead, 10, 10, 400, 280, BitOR($ES_READONLY, $WS_VSCROLL))
    Local $btn_Close = GUICtrlCreateButton(_T("Close"), 420, 10, 80, 35)
    GUICtrlSetState(-1, $GUI_DEFBUTTON)

    ; Thiết lập phím tắt để điều hướng giữa các thành phần
    Local $dummy_tab = GUICtrlCreateDummy()
    Local $aAccel[2][2] = [["{TAB}", $dummy_tab], ["+{TAB}", $dummy_tab]]
    GUISetAccelerators($aAccel, $gui)

    GUISetState(@SW_SHOW, $gui)

    While 1
        Local $msg = _GuiMsg($gui)
        Switch $msg
            Case $GUI_EVENT_CLOSE, $btn_Close
                GUIDelete($gui)
                ExitLoop
            Case $dummy_tab
                ; Chuyển đổi tiêu điểm giữa nút Close và ô nhập liệu
                If ControlGetHandle($gui, "", ControlGetFocus($gui)) = GUICtrlGetHandle($idEdit) Then
                    ControlFocus($gui, "", $btn_Close)
                Else
                    ControlFocus($gui, "", $idEdit)
                EndIf
        EndSwitch
    WEnd
EndFunc

Func _Show_License_Window()
    ; Tra ve True neu nguoi dung chap nhan, False neu tu choi / dong cua so
    Local $gui = GUICreate(_T("License Agreement"), 520, 300)
    GUISetBkColor($COLOR_BLUE)
    Local $txtLicense = FileExists(@ScriptDir & "\docs\license.txt") ? FileRead(@ScriptDir & "\docs\license.txt") : "License file not found (docs\license.txt)."
    Local $idEdit = GUICtrlCreateEdit($txtLicense, 10, 10, 400, 280, BitOR($ES_READONLY, $WS_VSCROLL))
    Local $btn_Accept = GUICtrlCreateButton(_T("&Accept"), 420, 10, 80, 35)
    Local $btn_Decline = GUICtrlCreateButton(_T("&Decline"), 420, 55, 80, 35)

    ; Enter: kich hoat nut dang duoc focus (Decline -> tu choi, con lai -> chap nhan). Tab / Shift+Tab xoay vong: O van ban -> Accept -> Decline
    Local $dummy_enter = GUICtrlCreateDummy()
    Local $dummy_tab = GUICtrlCreateDummy()
    Local $dummy_shifttab = GUICtrlCreateDummy()
    Local $aAccel[3][2] = [["{ENTER}", $dummy_enter], ["{TAB}", $dummy_tab], ["+{TAB}", $dummy_shifttab]]
    GUISetAccelerators($aAccel, $gui)

    GUISetState(@SW_SHOW, $gui)
    WinActivate($gui)
    ControlFocus($gui, "", $idEdit)

    ; Am thanh cua hop thoai License Agreement (phat nen, khong chan giao dien)
    If Not $g_bMuteAppSounds And FileExists(@ScriptDir & "\sounds\license_agreement.wav") Then _
        DllCall("winmm.dll", "bool", "PlaySoundW", "wstr", @ScriptDir & "\sounds\license_agreement.wav", "ptr", 0, "dword", 0x00020003)

    Local $aOrder[3] = [$idEdit, $btn_Accept, $btn_Decline] ; thu tu Tab
    Local $bAccepted = False
    While 1
        Local $msg = _GuiMsg($gui)
        Switch $msg
            Case $GUI_EVENT_CLOSE, $btn_Decline
                ExitLoop
            Case $btn_Accept
                $bAccepted = True
                ExitLoop
            Case $dummy_enter
                ; Neu dang focus o nut Decline thi Enter = tu choi, khong duoc coi la chap nhan
                If ControlGetHandle($gui, "", ControlGetFocus($gui)) = GUICtrlGetHandle($btn_Decline) Then ExitLoop
                $bAccepted = True
                ExitLoop
            Case $dummy_tab, $dummy_shifttab
                Local $hFocus = ControlGetHandle($gui, "", ControlGetFocus($gui))
                Local $iCur = 0
                For $i = 0 To 2
                    If $hFocus = GUICtrlGetHandle($aOrder[$i]) Then $iCur = $i
                Next
                If $msg = $dummy_tab Then
                    $iCur = Mod($iCur + 1, 3)
                Else
                    $iCur = Mod($iCur + 2, 3)
                EndIf
                ControlFocus($gui, "", $aOrder[$iCur])
        EndSwitch
    WEnd

    ; Dung am thanh license_agreement.wav neu con dang phat roi dong hop thoai
    DllCall("winmm.dll", "int", "PlaySoundW", "ptr", 0, "ptr", 0, "dword", 0)
    GUIDelete($gui)
    Return $bAccepted
EndFunc

Func _Show_Contact_Window()
    Local $gui = GUICreate(_T("Contact"), 300, 200)
    GUISetBkColor($COLOR_BLUE)

    Local $fb = GUICtrlCreateButton(_T("Facebook"), 50, 30, 200, 30)
    Local $email = GUICtrlCreateButton(_T("Email"), 50, 70, 200, 30)

    GUISetState(@SW_SHOW, $gui)

    While 1
        Local $msg = _GuiMsg($gui)
        Switch $msg
            Case $GUI_EVENT_CLOSE
                GUIDelete($gui)
                ExitLoop
            Case $fb
                ShellExecute("https://www.facebook.com/profile.php?id=100083295244149")
            Case $email
                ShellExecute("https://mail.google.com/mail/u/0/?fs=1&tf=cm&source=mailto&to=vodinhhungtnlg@gmail.com")
        EndSwitch
    WEnd
EndFunc
Func _Show_Send_Feedback_Window()
    Local $gui = GUICreate(_T("Send Feedback"), 420, 320, -1, -1, BitOR($WS_CAPTION, $WS_POPUPWINDOW, $WS_VISIBLE))
    GUISetBkColor($COLOR_BLUE, $gui)

    GUICtrlCreateLabel(_T("Title:"), 10, 10, 400, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $idTitle = GUICtrlCreateInput("[Feature]: ", 10, 30, 400, 22)

    GUICtrlCreateLabel(_T("Describe your idea:"), 10, 62, 400, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $idDesc = GUICtrlCreateEdit("", 10, 84, 400, 170, BitOR($ES_WANTRETURN, $ES_AUTOVSCROLL, $WS_VSCROLL))

    Local $btnSend = GUICtrlCreateButton(_T("Send"), 220, 270, 90, 32)
    GUICtrlSetState(-1, $GUI_DEFBUTTON)
    Local $btnCancel = GUICtrlCreateButton(_T("Cancel"), 320, 270, 90, 32)

    _AllowUIPI($gui)
    GUISetState(@SW_SHOW, $gui)
    WinActivate($gui)
    ControlFocus($gui, "", $idTitle)

    While 1
        Local $msg = _GuiMsg($gui)
        Switch $msg
            Case $GUI_EVENT_CLOSE, $btnCancel
                GUIDelete($gui)
                ExitLoop
            Case $btnSend
                Local $sTitle = GUICtrlRead($idTitle)
                Local $sDesc = GUICtrlRead($idDesc)
                If StringStripWS($sDesc, 3) = "" Then
                    MsgBox(48, _T("Send Feedback"), _T("Please describe your idea before sending."))
                    ContinueLoop
                EndIf
                Local $sUrl = "https://github.com/vo-dinh-hung/vdh_media_center/issues/new?template=feature_request.yml" & _
                    "&title=" & _URLEncode($sTitle) & _
                    "&description=" & _URLEncode($sDesc)
                ShellExecute($sUrl)
                GUIDelete($gui)
                ExitLoop
        EndSwitch
    WEnd
EndFunc

Func _GetYoutubeID($url)
    Local $id = ""
    If StringInStr($url, "v=") Then
        $id = StringRegExpReplace($url, ".*v=([^&]*).*", "$1")
    ElseIf StringInStr($url, "youtu.be/") Then
        $id = StringRegExpReplace($url, ".*/([^?]*).*", "$1")
    EndIf
    Return $id
EndFunc

Func _GetYoutubeTitle($url)
    Local $pid = Run(@ComSpec & ' /c "' & $YT_DLP_EXE & ' --encoding utf-8 --get-title --no-playlist --no-check-certificate -4 -- "' & $url & '""', @ScriptDir, @SW_HIDE, $STDOUT_CHILD + $STDERR_CHILD)
    Local $bData = Binary("")
    While ProcessExists($pid)
        $bData &= StdoutRead($pid, False, True)
        GUIGetMsg()
        Sleep(1)
    WEnd
    $bData &= StdoutRead($pid, False, True)
    Return StringStripWS(BinaryToString($bData, 4), 3)
EndFunc

Func _AddHistory($sID, $sTitle, $sType = "video")
    If Not $g_bSaveHistory Then Return ; Người dùng đã tắt lưu lịch sử
    If $sID = "" Or $sTitle = "" Then Return
	If $sType = "" Then $sType = "video"

    ; Prevent duplicates (optional but good for history)
    Local $sContent = ""
	If FileExists($HISTORY_FILE) Then
		Local $hFileRead = FileOpen($HISTORY_FILE, 0 + 256)
		$sContent = FileRead($hFileRead)
		FileClose($hFileRead)
	EndIf
    If StringInStr($sContent, $sID & "|") Then
        _RemoveHistory($sID) ; Remove old entry to move it to the top
    EndIf

    Local $hFile = FileOpen($HISTORY_FILE, 1 + 8 + 256) ; 1=Append, 8=DirCreate, 256=UTF8
    If $hFile = -1 Then Return
    FileWriteLine($hFile, $sID & "|" & $sTitle & "|" & $sType)
    FileClose($hFile)
EndFunc

Func _RemoveHistory($sID)
    Local $sContent = FileRead(FileOpen($HISTORY_FILE, 0 + 256)) ; Read as UTF-8
    Local $aLines = StringSplit(StringStripCR($sContent), @LF)
    Local $sNewContent = ""
    Local $bRemoved = False

    For $i = 1 To $aLines[0]
        If $aLines[$i] = "" Then ContinueLoop
        Local $aParts = StringSplit($aLines[$i], "|")
        If $aParts[0] >= 1 And $aParts[1] = $sID Then
            $bRemoved = True
            ContinueLoop
        EndIf
        $sNewContent &= $aLines[$i] & @CRLF
    Next

    If $bRemoved Then
        Local $hFile = FileOpen($HISTORY_FILE, 2 + 256) ; 2=Write, 256=UTF8
        FileWrite($hFile, $sNewContent)
        FileClose($hFile)
        Return True
    EndIf
    Return False
EndFunc

Func _ClearHistory()
    Local $hFile = FileOpen($HISTORY_FILE, 2 + 256) ; 2=Write, 256=UTF8
    If $hFile <> -1 Then
        FileWrite($hFile, "")
        FileClose($hFile)
        Return True
    EndIf
    Return False
EndFunc

Func _AddFavorite($sID, $sTitle)
    Local $hFile = FileOpen($FAVORITES_FILE, 1 + 8 + 256) ; 1=Append, 8=DirCreate, 256=UTF8
    If $hFile = -1 Then
        MsgBox(16, _T("Error"), _T("Cannot open favorites file."))
        Return
    EndIf
    FileWriteLine($hFile, $sID & "|" & $sTitle)
    FileClose($hFile)
    MsgBox(64, _T("Success"), _T("Added to favorites successfully!"))
EndFunc

Func _RemoveFavorite($sID)
    Local $sContent = FileRead(FileOpen($FAVORITES_FILE, 0 + 256)) ; Read as UTF-8
    Local $aLines = StringSplit(StringStripCR($sContent), @LF)
    Local $sNewContent = ""
    Local $bRemoved = False

    For $i = 1 To $aLines[0]
        If $aLines[$i] = "" Then ContinueLoop
        Local $aParts = StringSplit($aLines[$i], "|")
        If $aParts[0] >= 1 And $aParts[1] = $sID Then
            $bRemoved = True
            ContinueLoop
        EndIf
        $sNewContent &= $aLines[$i] & @CRLF
    Next

    If $bRemoved Then
        Local $hFile = FileOpen($FAVORITES_FILE, 2 + 256) ; 2=Write, 256=UTF8
        FileWrite($hFile, $sNewContent)
        FileClose($hFile)
        Return True
    EndIf
    Return False
EndFunc

Func _ClearFavorites()
    Local $hFile = FileOpen($FAVORITES_FILE, 2 + 256) ; 2=Write, 256=UTF8
    If $hFile <> -1 Then
        FileWrite($hFile, "")
        FileClose($hFile)
        Return True
    EndIf
    Return False
EndFunc

Func _IsFavorite($sID)
    If Not FileExists($FAVORITES_FILE) Then Return False
    Local $sContent = FileRead(FileOpen($FAVORITES_FILE, 0 + 256))
    Return StringInStr($sContent, $sID & "|") > 0
EndFunc


Func _ShowFavorites()

    ; Increased height to 480 to match History window and fit the extra button comfortably
    $hFavoritesGui = GUICreate(_T("Favorite Videos"), 400, 526)
    GUISetBkColor($COLOR_BLUE)
    GUICtrlCreateLabel(_T("Your favorite videos:"), 10, 10, 380, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    GUICtrlSetFont(-1, 10, 800)
    $lst_results = GUICtrlCreateList("", 10, 35, 380, 355, BitOR($LBS_NOTIFY, $WS_VSCROLL, $WS_BORDER))

    Local $btn_clear_fav = GUICtrlCreateButton(_T("Clear all favorites"), 10, 400, 380, 30)
    Local $btn_go_back = GUICtrlCreateButton(_T("go back"), 10, 440, 380, 30)

    Local $dummy_copy = GUICtrlCreateDummy()
    Local $dummy_browser = GUICtrlCreateDummy()
    Local $dummy_channel = GUICtrlCreateDummy()
    Local $hDummyAudioFav = GUICtrlCreateDummy()
    Local $hDummyCommentsFav = GUICtrlCreateDummy()
    Local $hDummyEnterFav = GUICtrlCreateDummy()
    Local $hDummyHomeFav = GUICtrlCreateDummy()
    Local $hDummyEndFav = GUICtrlCreateDummy()
    Local $hDummyEscFav = GUICtrlCreateDummy()
    Local $hDummyAppsFav = GUICtrlCreateDummy() ; DUMMY MỚI CHO MENU CHUỘT PHẢI
    Local $aAccel[11][2] = [ _
        ["^k", $dummy_copy], _
        ["!b", $dummy_browser], _
        ["!g", $dummy_channel], _
        ["^{ENTER}", $hDummyAudioFav], _
        ["^+c", $hDummyCommentsFav], _
        ["{ENTER}", $hDummyEnterFav], _
        ["{HOME}", $hDummyHomeFav], _
        ["{END}", $hDummyEndFav], _
        ["{ESC}", $hDummyEscFav], _
        ["{APPSKEY}", $hDummyAppsFav], _ ; Phím Applications/Context Menu ĐÃ FIX LỖI TÊN PHÍM
        ["+{F10}", $hDummyAppsFav] _  ; Phím Shift+F10
    ]
    GUISetAccelerators($aAccel, $hFavoritesGui)

    GUISetState(@SW_SHOW, $hFavoritesGui)

    _LoadFavorites()
    _GUICtrlListBox_SetCurSel($lst_results, 0)
    ControlFocus($hFavoritesGui, "", $lst_results)

    While 1
        Local $nMsg = _GuiMsg($hFavoritesGui)

        Switch $nMsg
            Case $GUI_EVENT_CLOSE, $btn_go_back
                GUIDelete($hFavoritesGui)
                $hFavoritesGui = 0
                GUISetState(@SW_SHOW, $mainform)
                Return
            Case $hDummyAppsFav
                If ControlGetHandle($hFavoritesGui, "", ControlGetFocus($hFavoritesGui)) = GUICtrlGetHandle($lst_results) Then
                    If _ShowContextMenu(1) = "REFRESH" Then
                        _LoadFavorites()
                        _GUICtrlListBox_SetCurSel($lst_results, 0)
                    EndIf
                EndIf
            Case $hDummyEnterFav
                Local $hFocus = ControlGetHandle($hFavoritesGui, "", ControlGetFocus($hFavoritesGui))
                If $hFocus = GUICtrlGetHandle($lst_results) Then
                    _PlayLoop(_GUICtrlListBox_GetCurSel($lst_results), False) ; Enter = Play Video
                ElseIf $hFocus = GUICtrlGetHandle($btn_clear_fav) Then
                    If MsgBox(36, _T("Confirm"), _T("Are you sure you want to clear all favorites?")) = 6 Then
                        _ClearFavorites()
                        _LoadFavorites()
                    EndIf
                ElseIf $hFocus = GUICtrlGetHandle($btn_go_back) Then
                    GUIDelete($hFavoritesGui)
                    $hFavoritesGui = 0
                    GUISetState(@SW_SHOW, $mainform)
                    Return
                EndIf
            Case $hDummyAudioFav
                If ControlGetHandle($hFavoritesGui, "", ControlGetFocus($hFavoritesGui)) = GUICtrlGetHandle($lst_results) Then
                    _PlayLoop(_GUICtrlListBox_GetCurSel($lst_results), True) ; Ctrl+Enter = Play Audio
                EndIf
            Case $hDummyHomeFav
                _GUICtrlListBox_SetCurSel($lst_results, 0)
            Case $hDummyEndFav
                _GUICtrlListBox_SetCurSel($lst_results, _GUICtrlListBox_GetCount($lst_results) - 1)
            Case $hDummyEscFav
                GUIDelete($hFavoritesGui)
                $hFavoritesGui = 0
                GUISetState(@SW_SHOW, $mainform)
                Return
            Case $btn_clear_fav
                If MsgBox(36, _T("Confirm"), _T("Are you sure you want to clear all favorites?")) = 6 Then
                    _ClearFavorites()
                    _LoadFavorites()
                EndIf
            Case $dummy_copy
                _Action_CopyLink(_GUICtrlListBox_GetCurSel($lst_results))
            Case $dummy_browser
                _Action_OpenBrowser(_GUICtrlListBox_GetCurSel($lst_results))
            Case $dummy_channel
                _Action_GoChannel(_GUICtrlListBox_GetCurSel($lst_results))
        EndSwitch
    WEnd
EndFunc

Func _LoadFavorites()
    _GUICtrlListBox_BeginUpdate($lst_results)
    _GUICtrlListBox_ResetContent($lst_results)
    Global $aSearchIds[1]
    Global $aSearchTitles[1]
    $iTotalLoaded = 0
    $bEndReached = True ; No pagination for favorites yet

    ; Doc ca file 1 lan (nhanh hon FileReadLine tung dong) va dat kich thuoc mang 1 lan
    ; thay vi ReDim sau moi dong (ReDim lap lai lam chay cham khi danh sach dai).
    Local $sContent = ""
    Local $hFile = FileOpen($FAVORITES_FILE, 0 + 256) ; Read as UTF-8
    If $hFile <> -1 Then
        $sContent = FileRead($hFile)
        FileClose($hFile)
    EndIf

    If $sContent <> "" Then
        Local $aLines = StringSplit(StringStripCR($sContent), @LF, 2)
        Local $iMax = UBound($aLines)
        ReDim $aSearchIds[$iMax + 1]
        ReDim $aSearchTitles[$iMax + 1]
        Local $sBatch = ""
        For $i = 0 To $iMax - 1
            If $aLines[$i] = "" Then ContinueLoop
            Local $aParts = StringSplit($aLines[$i], "|")
            If $aParts[0] >= 2 Then
                $iTotalLoaded += 1
                $sBatch &= $iTotalLoaded & ". " & $aParts[2] & "|"
                $aSearchIds[$iTotalLoaded] = $aParts[1]
                $aSearchTitles[$iTotalLoaded] = $aParts[2]
            EndIf
        Next
        ReDim $aSearchIds[$iTotalLoaded + 1]
        ReDim $aSearchTitles[$iTotalLoaded + 1]
        ; Them ca danh sach vao listbox trong 1 lan
        If $sBatch <> "" Then GUICtrlSetData($lst_results, StringTrimRight($sBatch, 1))
    EndIf
    _GUICtrlListBox_EndUpdate($lst_results)
EndFunc

Func _ShowHistory()

    $hHistoryGui = GUICreate(_T("Watch History"), 400, 496)
    GUISetBkColor($COLOR_BLUE)
    GUICtrlCreateLabel(_T("Your watch history:"), 10, 10, 380, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    GUICtrlSetFont(-1, 10, 800)
    $lst_results = GUICtrlCreateList("", 10, 35, 380, 325, BitOR($LBS_NOTIFY, $WS_VSCROLL, $WS_BORDER))

    Local $btn_clear_all = GUICtrlCreateButton(_T("Clear all history"), 10, 370, 380, 30)
    Local $btn_go_back = GUICtrlCreateButton(_T("Go back (Alt+B)"), 10, 410, 380, 30)

    Local $dummy_copy = GUICtrlCreateDummy()
    Local $dummy_browser = GUICtrlCreateDummy()
    Local $dummy_channel = GUICtrlCreateDummy()
    Local $hDummyAudioHist = GUICtrlCreateDummy()
    Local $hDummyCommentsFav = GUICtrlCreateDummy()
    Local $hDummyEnterHist = GUICtrlCreateDummy()
    Local $hDummyHomeHist = GUICtrlCreateDummy()
    Local $hDummyEndHist = GUICtrlCreateDummy()
    Local $hDummyEscHist = GUICtrlCreateDummy()
    Local $hDummyAppsHist = GUICtrlCreateDummy() ; DUMMY MỚI CHO MENU CHUỘT PHẢI
    Local $aAccel[12][2] = [ _
        ["^k", $dummy_copy], _
        ["!b", $btn_go_back], _ ; Alt+B linked directly to button
        ["!g", $dummy_channel], _
        ["^{ENTER}", $hDummyAudioHist], _
        ["^+c", $hDummyCommentsFav], _
        ["{ENTER}", $hDummyEnterHist], _
        ["{HOME}", $hDummyHomeHist], _
        ["{END}", $hDummyEndHist], _
        ["{ESC}", $hDummyEscHist], _
        ["!b", $btn_go_back], _
        ["{APPSKEY}", $hDummyAppsHist], _ ; Phím Applications/Context Menu ĐÃ FIX LỖI TÊN PHÍM
        ["+{F10}", $hDummyAppsHist] _  ; Phím Shift+F10
    ]
    GUISetAccelerators($aAccel, $hHistoryGui)

    GUISetState(@SW_SHOW, $hHistoryGui)

    _LoadHistory()
    _GUICtrlListBox_SetCurSel($lst_results, 0)
    ControlFocus($hHistoryGui, "", $lst_results)

    While 1
        Local $nMsg = _GuiMsg($hHistoryGui)

        ; Handle Enter key for buttons
        If $nMsg = $hDummyEnterHist Then
            Local $hFocus = ControlGetHandle($hHistoryGui, "", ControlGetFocus($hHistoryGui))
            If $hFocus = GUICtrlGetHandle($btn_clear_all) Then
                $nMsg = $btn_clear_all
            ElseIf $hFocus = GUICtrlGetHandle($btn_go_back) Then
                $nMsg = $btn_go_back
            EndIf
        EndIf

        Switch $nMsg
            Case $GUI_EVENT_CLOSE, $btn_go_back, $hDummyEscHist
                GUIDelete($hHistoryGui)
                $hHistoryGui = 0
                GUISetState(@SW_SHOW, $mainform)
                Return
            Case $hDummyAppsHist
                If ControlGetHandle($hHistoryGui, "", ControlGetFocus($hHistoryGui)) = GUICtrlGetHandle($lst_results) Then
                    If _ShowContextMenu(2) = "REFRESH" Then
                        _LoadHistory()
                        _GUICtrlListBox_SetCurSel($lst_results, 0)
                    EndIf
                EndIf
            Case $hDummyEnterHist
                If ControlGetHandle($hHistoryGui, "", ControlGetFocus($hHistoryGui)) = GUICtrlGetHandle($lst_results) Then
                    Local $iSel = _GUICtrlListBox_GetCurSel($lst_results)
                    If $iSel <> -1 Then
                        Local $sItemType = $aSearchTypes[$iSel + 1]
                        If $sItemType = "playlist" Then
                            _ShowPlaylistVideos($aSearchIds[$iSel + 1], $aSearchTitles[$iSel + 1])
                        Else
                            _PlayLoop($iSel, False) ; Video
                        EndIf
                    EndIf
                EndIf
            Case $hDummyAudioHist
                If ControlGetHandle($hHistoryGui, "", ControlGetFocus($hHistoryGui)) = GUICtrlGetHandle($lst_results) Then
                    Local $iSel = _GUICtrlListBox_GetCurSel($lst_results)
                    If $iSel <> -1 Then
                        Local $sItemType = $aSearchTypes[$iSel + 1]
                        If $sItemType = "video" Then
                            _PlayLoop($iSel, True) ; Ctrl+Enter = Play Audio
                        Else
                            _ReportStatus(_T("Cannot play a playlist in audio-only mode directly. Please open the playlist first."))
                        EndIf
                    EndIf
                EndIf
            Case $hDummyHomeHist
                _GUICtrlListBox_SetCurSel($lst_results, 0)
            Case $hDummyEndHist
                _GUICtrlListBox_SetCurSel($lst_results, _GUICtrlListBox_GetCount($lst_results) - 1)
            Case $hDummyEscHist
                GUIDelete($hHistoryGui)
                GUISetState(@SW_SHOW, $mainform)
                Return
            Case $btn_clear_all
                If MsgBox(36, _T("Confirm"), _T("Are you sure you want to clear all history?")) = 6 Then
                    _ClearHistory()
                    _LoadHistory()
                    _GUICtrlListBox_SetCurSel($lst_results, 0)
                    ControlFocus($hHistoryGui, "", $lst_results)
                EndIf
            Case $dummy_copy
                _Action_CopyLink(_GUICtrlListBox_GetCurSel($lst_results))
            Case $dummy_browser
                _Action_OpenBrowser(_GUICtrlListBox_GetCurSel($lst_results))
            Case $dummy_channel
                _Action_GoChannel(_GUICtrlListBox_GetCurSel($lst_results))
        EndSwitch
    WEnd
EndFunc

Func _LoadHistory()
    _GUICtrlListBox_BeginUpdate($lst_results)
    _GUICtrlListBox_ResetContent($lst_results)
    If Not FileExists($HISTORY_FILE) Then
        _GUICtrlListBox_EndUpdate($lst_results)
        Return
    EndIf

    Local $hFile = FileOpen($HISTORY_FILE, 0 + 256) ; Read as UTF-8
    Local $sContent = FileRead($hFile)
    FileClose($hFile)

    If $sContent = "" Then
        _GUICtrlListBox_EndUpdate($lst_results)
        Return
    EndIf

    Local $aHistoryLines = StringSplit(StringStripCR($sContent), @LF)
    Global $aSearchIds[1]
    Global $aSearchTitles[1]
    Global $aSearchTypes[1] ; <-- IMPORTANT
    $iTotalLoaded = 0
    $bEndReached = True

    ; Dat kich thuoc mang 1 lan (thay vi ReDim sau moi dong) va them danh sach vao
    ; listbox trong 1 lan de mo Watch History nhanh, ke ca khi lich su rat dai.
    ReDim $aSearchIds[$aHistoryLines[0] + 1]
    ReDim $aSearchTitles[$aHistoryLines[0] + 1]
    ReDim $aSearchTypes[$aHistoryLines[0] + 1]
    Local $sBatch = ""

    ; Show from newest to oldest
    For $i = $aHistoryLines[0] To 1 Step -1
        Local $sLine = $aHistoryLines[$i]
        If $sLine = "" Then ContinueLoop

        Local $aParts = StringSplit($sLine, "|")
        If $aParts[0] >= 2 Then
            Local $sID = $aParts[1]
            Local $sTitle = $aParts[2]
            Local $sType = ($aParts[0] >= 3) ? $aParts[3] : "video" ; Read type, default to video
            If $sType = "local_audio" Then ContinueLoop ; nhac nghe tu may nam trong Recent Files/Folders, khong con trong Watch History

            $iTotalLoaded += 1
            Local $sDisplayTitle = $iTotalLoaded & ". " & $sTitle
            If $sType = "playlist" Then
                $sDisplayTitle &= " [Playlist]" ; Add a visual indicator
            EndIf
            $sBatch &= $sDisplayTitle & "|"

            $aSearchIds[$iTotalLoaded] = $sID
            $aSearchTitles[$iTotalLoaded] = $sTitle
            $aSearchTypes[$iTotalLoaded] = $sType ; <-- IMPORTANT
        EndIf
    Next

    ReDim $aSearchIds[$iTotalLoaded + 1]
    ReDim $aSearchTitles[$iTotalLoaded + 1]
    ReDim $aSearchTypes[$iTotalLoaded + 1]
    If $sBatch <> "" Then GUICtrlSetData($lst_results, StringTrimRight($sBatch, 1))
    _GUICtrlListBox_EndUpdate($lst_results)

    If $iTotalLoaded = 0 Then
        MsgBox(64, _T("Info"), _T("No history found."))
    EndIf
EndFunc

Func _AutoDetectClipboardLink()
    Local $clip = ClipGet()
    Local $bYT = (StringInStr($clip, "youtube.com") Or StringInStr($clip, "youtu.be"))
    Local $sSC = ""
    If Not $bYT Then
        Local $aSC = StringRegExp($clip, "(?i)(https?://(?:[a-z0-9-]+\.)?(?:soundcloud\.com|snd\.sc)/\S+)", 3)
        If IsArray($aSC) Then $sSC = $aSC[0]
    EndIf
    If Not $bYT And $sSC = "" Then Return

    ; Check if focus is in an edit box (per requirement)
    Local $focus = ControlGetFocus($mainform)
    If StringInStr($focus, "Edit") Then Return

    Local $sSite = $bYT ? "YouTube" : "SoundCloud"
    Local $hAutoGui = GUICreate(_T("Link detected"), 300, 150, -1, -1, BitOR($WS_CAPTION, $WS_POPUP, $WS_SYSMENU), -1, $mainform)
    GUISetBkColor(0xFFFFFF)
    GUICtrlCreateLabel(_TF("A {1} link was found in your clipboard. What would you like to do?", $sSite), 10, 10, 280, 40)

    Local $btn_Play = GUICtrlCreateButton(_T("Play"), 10, 60, 135, 30)
    Local $btn_DL = GUICtrlCreateButton(_T("Download"), 155, 60, 135, 30)
    Local $btn_Cancel = GUICtrlCreateButton(_T("Cancel"), 10, 100, 280, 30)

    GUISetState(@SW_SHOW, $hAutoGui)

    While 1
        Local $nMsg = GUIGetMsg()
        Select
            Case $nMsg = $GUI_EVENT_CLOSE Or $nMsg = $btn_Cancel
                GUIDelete($hAutoGui)
                ExitLoop
            Case $nMsg = $btn_Play
                GUIDelete($hAutoGui)
                If $bYT Then
                    playmedia($clip)
                Else
                    playaudio($sSC) ; SoundCloud has no video: play it as audio
                EndIf
                ExitLoop
            Case $nMsg = $btn_DL
                GUIDelete($hAutoGui)
                If $bYT Then
                    Local $id = _GetYoutubeID($clip)
                    If $id <> "" Then
                        Local $sTitle = _GetYoutubeTitle($clip)
                        _ShowDownloadDialog($id, $sTitle)
                    Else
                        MsgBox(16, _T("Error"), _T("Could not extract video ID from link."))
                    EndIf
                Else
                    ; links of other sites are their own id
                    _ShowDownloadDialog($sSC, _GetYoutubeTitle($sSC))
                EndIf
                ExitLoop
        EndSelect
    WEnd
EndFunc

Func _Check_YTDLP_Update($bSilent = False)

    Local $hCheckGUI = 0
    If Not $bSilent Then
        Local $sCheckingText = _T("Checking for updates yt-dlp...")
        $hCheckGUI = GuiCreate("", 300, 80, -1, -1, BitOR($WS_CAPTION, $WS_POPUP), BitOR($WS_EX_TOPMOST, $WS_EX_TOOLWINDOW))
        GuiSetBkColor(0xFFFFFF, $hCheckGUI)
        Local $lblCheck = GuiCtrlCreateLabel($sCheckingText, 10, 25, 280, 30, $ES_CENTER)
        GuiCtrlSetFont($lblCheck, 10, 400, 0, "Arial")
        GuiSetState(@SW_SHOW, $hCheckGUI)
    EndIf

    If Ping("github.com", 2000) = 0 And Ping("google.com", 2000) = 0 Then
         If Not $bSilent Then
             GuiDelete($hCheckGUI)
             MsgBox(48, _T("Check Update"), _T("No internet connection."))
         EndIf
         Return
    EndIf

    Local $sRepoOwner = "yt-dlp"
    Local $sRepoName = "yt-dlp"
    Local $sApiUrl = "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest"

    Local $oHTTP = ObjCreate("WinHttp.WinHttpRequest.5.1")
    If Not IsObj($oHTTP) Then
        If Not $bSilent Then
            GuiDelete($hCheckGUI)
            MsgBox(16, _T("Error"), _T("Cannot create HTTP Object."))
        EndIf
        Return
    EndIf

    $oHTTP.Open("GET", $sApiUrl, False)
    $oHTTP.SetRequestHeader("User-Agent", "Mozilla/5.0")
    $oHTTP.Send()

    If @error Then
        If Not $bSilent Then
            GuiDelete($hCheckGUI)
            MsgBox(48, _T("Check Update"), _T("Connection failed. Please check your internet."))
        EndIf
        Return
    EndIf

    If $oHTTP.Status <> 200 Then
        If Not $bSilent Then
            GuiDelete($hCheckGUI)
            MsgBox(48, _T("Check Update"), _TF("Cannot connect to update server or no release found.\nStatus Code: {1}", $oHTTP.Status))
        EndIf
        Return
    EndIf

    Local $sResponse = $oHTTP.ResponseText
    If Not $bSilent Then GuiDelete($hCheckGUI)

    Local $aMatch = StringRegExp($sResponse, '"tag_name":\s*"([^"]+)"', 3)

    If IsArray($aMatch) Then
        Local $sLatestVersion = $aMatch[0]
        $sLatestVersion = StringRegExpReplace($sLatestVersion, "[^0-9.]", "")
        Local $sLocalVersion = _Get_YTDLP_LocalVersion()

        If $sLatestVersion <> $sLocalVersion Then
            _AppSoundPlay("sounds/update_yt-dlp.wav")
            Local $sVerInfo = _TF("new version ({1})!\n", $sLatestVersion)
            If $sLocalVersion <> "0" Then
                $sVerInfo &= _TF("Current version: {1}", $sLocalVersion)
            Else
                $sVerInfo &= _T("Current version: Not installed or unknown")
            EndIf

            Local $iMsg = MsgBox(36, _T("Update Available"), _TF("{1}\n\nDo you want to download it now?", $sVerInfo))
            If $iMsg = 6 Then
                If _VLC_Direct_Init() Then
                    If Not $g_bMuteAppSounds Then _VLC_Direct_Play("file:///" & StringReplace(@ScriptDir & "\sounds\updating_yt-dlp.wav", "\", "/"))
                    _VLC_Direct_SetVolume($g_iAppVolume)
                Else
                    _AppPlaySoundW(@ScriptDir & "\sounds\updating_yt-dlp.wav", 0x0009)
                EndIf

                $downloadtext = _T("please wait...")
                $downloadGui = GuiCreate(_T("downloading update..."), 400, 100, -1, -1)
                GuiSetBkColor($COLOR_WHITE)
                GuiCtrlCreateLabel($downloadtext, 40, 40)

                Local $hDummySpaceUpdate = GUICtrlCreateDummy()
                Local $hDummyHUpdate = GUICtrlCreateDummy()
                Local $hDummyPgUpUpdate = GUICtrlCreateDummy()
                Local $hDummyPgDnUpdate = GUICtrlCreateDummy()
                Local $hDummy1Update = GUICtrlCreateDummy()
                Local $hDummy2Update = GUICtrlCreateDummy()
                Local $hDummy3Update = GUICtrlCreateDummy()
                Local $aAccelUpdate[7][2] = [ _
                    ["{SPACE}", $hDummySpaceUpdate], _
                    ["h", $hDummyHUpdate], _
                    ["{PGUP}", $hDummyPgUpUpdate], _
                    ["{PGDN}", $hDummyPgDnUpdate], _
                    ["1", $hDummy1Update], _
                    ["2", $hDummy2Update], _
                    ["3", $hDummy3Update] _
                ]
                GUISetAccelerators($aAccelUpdate, $downloadGui)

                GuiSetState(@SW_SHOW, $downloadGui)
                Local $sDownloadURL = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe"
                DirCreate(@ScriptDir & "\lib")
                Local $sSavePathTemp = @ScriptDir & "\lib\yt-dlp.exe.new"
                Local $sSavePathFinal = @ScriptDir & "\lib\yt-dlp.exe"

                ProgressOn(_T("Downloading Update"), _T("Please wait while downloading..."), "0%")
                $g_sUpdateStatus = _T("downloading")
                $g_iUpdatePct = 0

                Local $hDownload = InetGet($sDownloadURL, $sSavePathTemp, 1, 1)

                Do
                    Local $msg = GUIGetMsg()
                    Select
                        Case $msg = $hDummySpaceUpdate
                            _ReportStatus(_TF("Downloaded {1}%", $g_iUpdatePct))
                        Case $msg = $hDummyHUpdate
                            _ReportStatus($g_sUpdateStatus)
                        Case $msg = $hDummyPgUpUpdate
                            _StepAppVolume(1)
                        Case $msg = $hDummyPgDnUpdate
                            _StepAppVolume(-1)
                        Case $msg = $hDummy1Update
                            _ReportStatus(_TF("File size: {1}", _FormatBytes($g_iUpdateFileSize)))
                        Case $msg = $hDummy2Update
                            _ReportStatus(_TF("Total downloaded: {1}", _FormatBytes($g_iUpdateBytesRead)))
                        Case $msg = $hDummy3Update
                            _ReportStatus(_TF("Total remaining: {1}", _FormatBytes($g_iUpdateFileSize - $g_iUpdateBytesRead)))
                    EndSelect

                    Sleep(10)
                    ; Tự động phát lại nhạc nếu kết thúc (Lặp lại)
                    If _VLC_Direct_GetState() = 6 Then ; 6 = Ended
                        If Not $g_bMuteAppSounds Then _VLC_Direct_Play("file:///" & StringReplace(@ScriptDir & "\sounds\updating_yt-dlp.wav", "\", "/"))
                        _VLC_Direct_SetVolume($g_iAppVolume)
                    EndIf
                    $g_iUpdateBytesRead = InetGetInfo($hDownload, 0)
                    $g_iUpdateFileSize = InetGetInfo($hDownload, 1)

                    If $g_iUpdateFileSize > 0 Then
                        $g_iUpdatePct = Round(($g_iUpdateBytesRead / $g_iUpdateFileSize) * 100)
                        ProgressSet($g_iUpdatePct, _TF("{1}% complete", $g_iUpdatePct))
                    Else
                        ProgressSet(0, _T("Connecting..."))
                    EndIf

                Until InetGetInfo($hDownload, 2)

                Local $bSuccess = InetGetInfo($hDownload, 3)
                Local $iError = InetGetInfo($hDownload, 4)
                InetClose($hDownload)
                _VLC_Direct_Stop()
                DllCall("winmm.dll", "int", "PlaySoundW", "ptr", 0, "ptr", 0, "dword", 0)

                ProgressOff()
                GuiDelete($downloadGui)

                If Not $bSuccess Then
                    MsgBox(16, _T("Error"), _TF("Download failed. Error code: {1}", $iError))
                    FileDelete($sSavePathTemp)
                    Return
                EndIf

                If FileExists($sSavePathTemp) And FileGetSize($sSavePathTemp) > 0 Then
                    ; Close any running yt-dlp.exe processes
                    While ProcessExists("yt-dlp.exe")
                        ProcessClose("yt-dlp.exe")
                        Sleep(50)
                    WEnd

                    ; Wait a bit to ensure file is not locked
                    Sleep(100)

                    FileDelete($sSavePathFinal)
                    If FileMove($sSavePathTemp, $sSavePathFinal, 1) Then
                        ; Bước bổ sung: tải/cập nhật Deno (JS runtime cho yt-dlp)
                        Local $bDenoOk = _Update_Deno()
                        _AppSoundPlay("sounds/updated_yt-dlp.wav")
                        Local $sOkMsg = _T("yt-dlp has been updated successfully!")
                        If $bDenoOk Then $sOkMsg &= @CRLF & _T("Deno (JavaScript runtime) is ready.")
                        MsgBox(64, _T("Success"), $sOkMsg)
        _AppSoundPlay("sounds/restart.wav")
                        If MsgBox(4, _T("Restart Required"), _T("The software needs to restart to apply the update. Restart now?")) = 6 Then
                            ShellExecute(@ScriptFullPath, "/restart")
                            Exit
                        EndIf
                    Else
                        MsgBox(16, _T("Error"), _T("Failed to replace yt-dlp.exe. Please close any programs using it and try again."))
                        FileDelete($sSavePathTemp)
                    EndIf
                EndIf
            EndIf
        Else
            ; yt-dlp đã mới nhất -> kiểm tra Deno; hộp thoại "đã mới nhất" được gộp chung trong _Check_Deno_Update
            _Check_Deno_Update($bSilent, True)
        EndIf
    Else
        If Not $bSilent Then MsgBox(16, _T("Error"), _T("Could not parse version information."))
    EndIf
EndFunc

; Lấy phiên bản deno.exe hiện có trong lib (trả về "0" nếu chưa có)
Func _Get_Deno_LocalVersion()
    If Not FileExists($YT_DENO_PATH) Then Return "0"
    Local $pid = Run('"' & $YT_DENO_PATH & '" --version', @ScriptDir, @SW_HIDE, $STDOUT_CHILD)
    If @error Then Return "0"
    ProcessWaitClose($pid, 10)
    Local $sOut = StdoutRead($pid)
    Local $aVer = StringRegExp($sOut, "deno\s+([0-9]+\.[0-9]+\.[0-9]+)", 1)
    If IsArray($aVer) Then Return $aVer[0]
    Return "0"
EndFunc

; Hỏi GitHub API của denoland/deno: trả về phiên bản mới nhất (vd "2.5.6", "" nếu lỗi)
; và gán vào $sUrl link chính xác của file zip chứa deno.exe (nếu tìm thấy).
Func _Get_Deno_LatestInfo(ByRef $sUrl)
    Local $sArch = "x86_64"
    If @OSArch = "ARM64" Then $sArch = "aarch64"
    Local $sAsset = "deno-" & $sArch & "-pc-windows-msvc.zip"
    $sUrl = "https://github.com/denoland/deno/releases/latest/download/" & $sAsset
    Local $sLatest = ""

    Local $oHTTP = ObjCreate("WinHttp.WinHttpRequest.5.1")
    If IsObj($oHTTP) Then
        $oHTTP.Open("GET", "https://api.github.com/repos/denoland/deno/releases/latest", False)
        $oHTTP.SetRequestHeader("User-Agent", "Mozilla/5.0")
        $oHTTP.Send()
        If Not @error And $oHTTP.Status = 200 Then
            Local $sResp = $oHTTP.ResponseText
            Local $aTag = StringRegExp($sResp, '"tag_name":\s*"v?([^"]+)"', 1)
            If IsArray($aTag) Then $sLatest = $aTag[0]
            Local $aUrl = StringRegExp($sResp, '"browser_download_url":\s*"([^"]*/' & StringReplace($sAsset, ".", "\.") & ')"', 1)
            If IsArray($aUrl) Then $sUrl = $aUrl[0]
        EndIf
    EndIf
    Return $sLatest
EndFunc

; Kiểm tra cập nhật Deno độc lập với yt-dlp (thiếu deno.exe hoặc có bản mới hơn thì hỏi tải)
Func _Check_Deno_Update($bSilent = False, $bYtdlpLatest = False)
    Local $sUrl = ""
    Local $sLatest = _Get_Deno_LatestInfo($sUrl)
    Local $sLocal = _Get_Deno_LocalVersion()
    Local $bMissing = ($sLocal = "0")
    Local $sYtPrefix = ""
    If $bYtdlpLatest Then $sYtPrefix = _T("yt-dlp is up to date.") & @CRLF

    If Not $bMissing Then
        If $sLatest = "" Then
            If Not $bSilent Then MsgBox(48, _T("Check Update"), _TF("{1}Could not check the latest Deno version.", $sYtPrefix))
            Return
        EndIf
        If $sLocal = $sLatest Then
            If Not $bSilent Then
                If $bYtdlpLatest Then
                    MsgBox(64, _T("no update available"), _T("You are using the latest versions from yt-dlp and Deno."))
                Else
                    MsgBox(64, _T("no update available"), _T("You are using the latest version from Deno."))
                EndIf
            EndIf
            Return
        EndIf
    EndIf

    _AppSoundPlay("sounds/update_yt-dlp.wav")
    Local $sMsg
    If $bMissing Then
        $sMsg = _TF("{1}Deno (JavaScript runtime needed by yt-dlp for YouTube) is not installed.", $sYtPrefix)
        If $sLatest <> "" Then $sMsg &= _TF("\nLatest version: {1}", $sLatest)
    Else
        $sMsg = _TF("{1}A new version of Deno ({2}) is available!\nCurrent version: {3}", $sYtPrefix, $sLatest, $sLocal)
    EndIf
    If MsgBox(36, _T("Deno Update"), _TF("{1}\n\nDo you want to download it now?", $sMsg)) <> 6 Then Return

    If _Update_Deno() Then
        _AppSoundPlay("sounds/updated_yt-dlp.wav")
        MsgBox(64, _T("Success"), _T("Deno has been updated successfully!"))
        _AppSoundPlay("sounds/restart.wav")
        If MsgBox(4, _T("Restart Required"), _T("The software needs to restart to apply the update. Restart now?")) = 6 Then
            ShellExecute(@ScriptFullPath, "/restart")
            Exit
        EndIf
    EndIf
EndFunc

; Tải Deno từ https://github.com/denoland/deno/releases
; File .exe nằm BÊN TRONG file zip "deno-<arch>-pc-windows-msvc.zip" của bản phát hành mới nhất,
; nên hàm sẽ tải zip, giải nén rồi đặt deno.exe vào lib\deno.exe.
; Trả về True nếu deno.exe đã sẵn sàng (đã mới nhất hoặc vừa cập nhật), False nếu lỗi.
Func _Update_Deno()
    Local $sUrl = ""
    Local $sLatest = _Get_Deno_LatestInfo($sUrl)

    ; Đã có deno.exe và (đã mới nhất hoặc không kiểm tra được phiên bản) thì bỏ qua
    Local $sLocal = _Get_Deno_LocalVersion()
    If $sLocal <> "0" And ($sLatest = "" Or $sLocal = $sLatest) Then Return True

    DirCreate(@ScriptDir & "\lib")
    Local $sZip = @ScriptDir & "\lib\deno_download.zip"
    Local $sTmpDir = @ScriptDir & "\lib\deno_tmp"
    FileDelete($sZip)
    DirRemove($sTmpDir, 1)

    _ReportStatus(_T("Downloading Deno, please wait"))
    ProgressOn(_T("Downloading Deno"), _T("Please wait while downloading Deno..."), "0%")
    Local $hDl = InetGet($sUrl, $sZip, 1, 1)
    Local $iRead, $iSize, $iPct
    Do
        Sleep(50)
        $iRead = InetGetInfo($hDl, 0)
        $iSize = InetGetInfo($hDl, 1)
        If $iSize > 0 Then
            $iPct = Round(($iRead / $iSize) * 100)
            ProgressSet($iPct, _TF("{1}% complete", $iPct))
        Else
            ProgressSet(0, _T("Connecting..."))
        EndIf
    Until InetGetInfo($hDl, 2)
    Local $bOk = InetGetInfo($hDl, 3)
    Local $iErr = InetGetInfo($hDl, 4)
    InetClose($hDl)
    ProgressOff()

    If Not $bOk Or Not FileExists($sZip) Or FileGetSize($sZip) = 0 Then
        MsgBox(16, _T("Error"), _TF("Failed to download Deno. Error code: {1}", $iErr))
        FileDelete($sZip)
        Return False
    EndIf

    ; Giải nén zip để lấy deno.exe
    _ReportStatus(_T("Extracting Deno"))
    RunWait('powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath ''' & $sZip & ''' -DestinationPath ''' & $sTmpDir & ''' -Force"', @ScriptDir, @SW_HIDE)
    FileDelete($sZip)

    If Not FileExists($sTmpDir & "\deno.exe") Then
        MsgBox(16, _T("Error"), _T("Could not find deno.exe in the downloaded Deno package."))
        DirRemove($sTmpDir, 1)
        Return False
    EndIf

    ; Đóng deno.exe đang chạy (nếu có) để ghi đè được file
    Local $iTry = 0
    While ProcessExists("deno.exe") And $iTry < 40
        ProcessClose("deno.exe")
        Sleep(50)
        $iTry += 1
    WEnd
    Sleep(100)

    FileDelete($YT_DENO_PATH)
    Local $bMoved = FileMove($sTmpDir & "\deno.exe", $YT_DENO_PATH, 1)
    DirRemove($sTmpDir, 1)

    If Not $bMoved Then
        MsgBox(16, _T("Error"), _T("Failed to install deno.exe. Please close any programs using it and try again."))
        Return False
    EndIf
    Return True
EndFunc

Func _CheckGithubUpdate($bSilent = False)

    Local $hCheckGUI = 0
    If Not $bSilent Then
        Local $sCheckingText = _T("Checking for updates...")
        $hCheckGUI = GuiCreate("", 300, 80, -1, -1, BitOR($WS_CAPTION, $WS_POPUP), BitOR($WS_EX_TOPMOST, $WS_EX_TOOLWINDOW))
        GuiSetBkColor(0xFFFFFF, $hCheckGUI)
        Local $lblCheck = GuiCtrlCreateLabel($sCheckingText, 10, 25, 280, 30, $ES_CENTER)
        GuiCtrlSetFont($lblCheck, 10, 400, 0, "Arial")
        GuiSetState(@SW_SHOW, $hCheckGUI)
    EndIf

    If Ping("github.com", 2000) = 0 And Ping("google.com", 2000) = 0 Then
         If Not $bSilent Then
             GuiDelete($hCheckGUI)
             MsgBox(48, _T("Check Update"), _T("No internet connection."))
         EndIf
         Return
    EndIf

    Local $sRepoOwner = "vo-dinh-hung"
    Local $sRepoName = "vdh_media_center"
    Local $sApiUrl = "https://api.github.com/repos/vo-dinh-hung/vdh_media_center/releases/latest"

    Local $oHTTP = ObjCreate("WinHttp.WinHttpRequest.5.1")
    If Not IsObj($oHTTP) Then
        If Not $bSilent Then
            GuiDelete($hCheckGUI)
            MsgBox(16, _T("Error"), _T("Cannot create HTTP Object."))
        EndIf
        Return
    EndIf

    $oHTTP.Open("GET", $sApiUrl, False)
    $oHTTP.SetRequestHeader("User-Agent", "Mozilla/5.0")
    $oHTTP.Send()

    If @error Then
        If Not $bSilent Then
            GuiDelete($hCheckGUI)
            MsgBox(48, _T("Check Update"), _T("Connection failed. Please check your internet."))
        EndIf
        Return
    EndIf

    If $oHTTP.Status <> 200 Then
        If Not $bSilent Then
            GuiDelete($hCheckGUI)
            MsgBox(48, _T("Check Update"), _TF("Cannot connect to update server or no release found.\nStatus Code: {1}", $oHTTP.Status))
        EndIf
        Return
    EndIf

    Local $sResponse = $oHTTP.ResponseText
    If Not $bSilent Then GuiDelete($hCheckGUI)

    Local $aMatch = StringRegExp($sResponse, '"tag_name":\s*"([^"]+)"', 3)

    If IsArray($aMatch) Then
        Local $sLatestVersion = $aMatch[0]
        $sLatestVersion = StringRegExpReplace($sLatestVersion, "[^0-9.]", "")
        Local $sLocalAppVersion = StringRegExpReplace($version, "[^0-9.]", "")

        If $sLatestVersion <> $sLocalAppVersion Then
            _AppSoundPlay("sounds/update.wav")

            ; Extract changelog from body
            Local $aBodyMatch = StringRegExp($sResponse, '"body":\s*"([^"\\]*(?:\\.[^"\\]*)*)"', 3)
            Local $sChangelog = ""
            If IsArray($aBodyMatch) Then
                $sChangelog = _UnescapeJSON($aBodyMatch[0])
                $sChangelog = _StripMarkdown($sChangelog)
            EndIf

            ; Custom Update GUI
            Local $hUpdateGUI = GUICreate(_T("Update Available"), 400, 420)
            GUISetBkColor($COLOR_BLUE)
            GUISetFont(9, 400, 0, "Segoe UI")

            GUICtrlCreateLabel(_TF("new version({1})!", $sLatestVersion), 10, 10, 380, 25)
            GUICtrlSetColor(-1, 0xFFFFFF)
            GUICtrlSetFont(-1, 11, 800)

            GUICtrlCreateLabel(_TF("current version: {1}", $version), 10, 40, 380, 20)
            GUICtrlSetColor(-1, 0xFFFFFF)

            GUICtrlCreateLabel(_TF("Changelog for {1}:", $sLatestVersion), 10, 70, 380, 20)
            GUICtrlSetColor(-1, 0xFFFFFF)

            Local $editChangelog = GUICtrlCreateEdit($sChangelog, 10, 95, 380, 240, BitOR($ES_AUTOVSCROLL, $ES_READONLY, $WS_VSCROLL, $WS_TABSTOP))

            GUICtrlCreateLabel(_T("Do you want to download and install this update now?"), 10, 345, 380, 20)
            GUICtrlSetColor(-1, 0xFFFFFF)
            GUICtrlSetFont(-1, 9, 600)

            Local $btnYes = GUICtrlCreateButton(_T("&Yes, Download Now"), 60, 370, 130, 35)
            Local $btnNo = GUICtrlCreateButton(_T("&No, Later"), 210, 370, 130, 35)

            GUISetState(@SW_SHOW, $hUpdateGUI)

            Local $iUpdateAction = 0 ; 0=None, 1=Yes, 2=No
            While 1
                Local $uMsg = GUIGetMsg()
                If $uMsg = $GUI_EVENT_CLOSE Or $uMsg = $btnNo Then
                    $iUpdateAction = 2
                    ExitLoop
                ElseIf $uMsg = $btnYes Then
                    $iUpdateAction = 1
                    ExitLoop
                EndIf
            WEnd
            GUIDelete($hUpdateGUI)

            If $iUpdateAction = 1 Then
                If _VLC_Direct_Init() Then
                    If Not $g_bMuteAppSounds Then _VLC_Direct_Play("file:///" & StringReplace(@ScriptDir & "\sounds\updating.wav", "\", "/"))
                    _VLC_Direct_SetVolume($g_iAppVolume)
                Else
                    _AppPlaySoundW(@ScriptDir & "\sounds\updating.wav", 0x0009)
                EndIf

                $downloadtext = _T("please wait")
                $downloadGui = GuiCreate(_T("downloading update"), 400, 400, -1, -1)
                GuiSetBkColor($COLOR_WHITE)
                GuiCtrlCreateLabel($downloadtext, 40, 60)

                Local $hDummySpaceUpdate = GUICtrlCreateDummy()
                Local $hDummyHUpdate = GUICtrlCreateDummy()
                Local $hDummyPgUpUpdate = GUICtrlCreateDummy()
                Local $hDummyPgDnUpdate = GUICtrlCreateDummy()
                Local $hDummy1Update = GUICtrlCreateDummy()
                Local $hDummy2Update = GUICtrlCreateDummy()
                Local $hDummy3Update = GUICtrlCreateDummy()
                Local $aAccelUpdate[7][2] = [ _
                    ["{SPACE}", $hDummySpaceUpdate], _
                    ["h", $hDummyHUpdate], _
                    ["{PGUP}", $hDummyPgUpUpdate], _
                    ["{PGDN}", $hDummyPgDnUpdate], _
                    ["1", $hDummy1Update], _
                    ["2", $hDummy2Update], _
                    ["3", $hDummy3Update] _
                ]
                GUISetAccelerators($aAccelUpdate, $downloadGui)

                GuiSetState(@SW_SHOW, $downloadGui)
                Local $sDownloadURL = "https://github.com/vo-dinh-hung/vdh_media_center/releases/latest/download/vdh_media_center.zip"
                Local $sSavePath = @ScriptDir & "\vdh_media_center.zip"

                ProgressOn(_T("Downloading Update"), _T("Please wait while downloading..."), "0%")
                $g_sUpdateStatus = _T("downloading")
                $g_iUpdatePct = 0

                Local $hDownload = InetGet($sDownloadURL, $sSavePath, 1, 1)

                Do
                    Local $msg = GUIGetMsg()
                    Select
                        Case $msg = $hDummySpaceUpdate
                            _ReportStatus(_TF("Downloaded {1}%", $g_iUpdatePct))
                        Case $msg = $hDummyHUpdate
                            _ReportStatus($g_sUpdateStatus)
                        Case $msg = $hDummyPgUpUpdate
                            _StepAppVolume(1)
                        Case $msg = $hDummyPgDnUpdate
                            _StepAppVolume(-1)
                        Case $msg = $hDummy1Update
                            _ReportStatus(_TF("File size: {1}", _FormatBytes($g_iUpdateFileSize)))
                        Case $msg = $hDummy2Update
                            _ReportStatus(_TF("Total downloaded: {1}", _FormatBytes($g_iUpdateBytesRead)))
                        Case $msg = $hDummy3Update
                            _ReportStatus(_TF("Total remaining: {1}", _FormatBytes($g_iUpdateFileSize - $g_iUpdateBytesRead)))
                    EndSelect

                    Sleep(10)
                    ; Tự động phát lại nhạc nếu kết thúc (Lặp lại)
                    If _VLC_Direct_GetState() = 6 Then ; 6 = Ended
                        If Not $g_bMuteAppSounds Then _VLC_Direct_Play("file:///" & StringReplace(@ScriptDir & "\sounds\updating.wav", "\", "/"))
                        _VLC_Direct_SetVolume($g_iAppVolume)
                    EndIf
                    $g_iUpdateBytesRead = InetGetInfo($hDownload, 0)
                    $g_iUpdateFileSize = InetGetInfo($hDownload, 1)

                    If $g_iUpdateFileSize > 0 Then
                        $g_iUpdatePct = Round(($g_iUpdateBytesRead / $g_iUpdateFileSize) * 100)
                        ProgressSet($g_iUpdatePct, _TF("{1}% complete", $g_iUpdatePct))
                    Else
                        ProgressSet(0, _T("Connecting..."))
                    EndIf

                Until InetGetInfo($hDownload, 2)

                Local $bSuccess = InetGetInfo($hDownload, 3)
                Local $iError = InetGetInfo($hDownload, 4)
                InetClose($hDownload)
                _VLC_Direct_Stop()
                DllCall("winmm.dll", "int", "PlaySoundW", "ptr", 0, "ptr", 0, "dword", 0)


                ProgressOff()
                GuiDelete($downloadGui)

                If Not $bSuccess Then
                    MsgBox(16, _T("Error"), _TF("Download failed. Error code: {1}", $iError))
                    FileDelete($sSavePath)
                    Return
                EndIf

                If FileExists($sSavePath) And FileGetSize($sSavePath) > 0 Then
                _AppSoundPlay("sounds/updated.wav")
                MsgBox(64, _T("Success"), _TF("Downloaded successfully!\nFile saved as: {1}", $sSavePath))
Run("unzip.exe")
                ; ShellExecute($sSavePath)
Exit
                EndIf
            EndIf
        Else
            If Not $bSilent Then
                MsgBox(64, _T("no update available"), _TF("You are using the latest version ({1}).", $version))
            EndIf
        EndIf
    Else
        If Not $bSilent Then
            MsgBox(16, _T("Error"), _T("Could not parse version information."))
        EndIf
    EndIf
EndFunc

Func _ShowChangelog()
    Local $sFilePath = "docs\changelog.txt"
    Local $sContent = _T("No changelog found.")

    If FileExists($sFilePath) Then
        $sContent = FileRead($sFilePath)
        $sContent = _StripMarkdown($sContent)
    EndIf

    Local $hChangelogGUI = GuiCreate(_T("Changelog"), 400, 450)
    Local $editChangelog = GUICtrlCreateEdit($sContent, 10, 10, 380, 380, BitOR($ES_AUTOVSCROLL, $ES_READONLY, $WS_VSCROLL, $WS_TABSTOP))
    Local $btnClose = GUICtrlCreateButton(_T("&Close"), 150, 400, 100, 30, $WS_TABSTOP)

    GuiSetState(@SW_SHOW, $hChangelogGUI)

    While 1
        Switch _GuiMsg($hChangelogGUI)
            Case $GUI_EVENT_CLOSE, $btnClose
                GuiDelete($hChangelogGUI)
                ExitLoop
        EndSwitch
    WEnd
EndFunc

Func _UnescapeJSON($sString)
    $sString = StringReplace($sString, '\"', '"')
    $sString = StringReplace($sString, '\\', '\')
    $sString = StringReplace($sString, '\/', '/')
    $sString = StringReplace($sString, '\b', Chr(8))
    $sString = StringReplace($sString, '\f', Chr(12))
    $sString = StringReplace($sString, '\n', @LF)
    $sString = StringReplace($sString, '\r', @CR)
    $sString = StringReplace($sString, '\t', @TAB)

    ; Handle \uXXXX
    Local $aMatch = StringRegExp($sString, "(?i)\\u([0-9a-f]{4})", 3)
    If IsArray($aMatch) Then
        For $i = 0 To UBound($aMatch) - 1
            $sString = StringReplace($sString, "\u" & $aMatch[$i], ChrW(Dec($aMatch[$i])))
        Next
    EndIf

    Return $sString
EndFunc

Func _StripMarkdown($sText)
    ; Remove HTML tags (if any)
    $sText = StringRegExpReplace($sText, "<[^>]*>", "")
    ; Remove bold and italic
    $sText = StringRegExpReplace($sText, "(\*\*|__)(.*?)\1", "$2")
    $sText = StringRegExpReplace($sText, "(\*|_)(.*?)\1", "$2")
    ; Remove headers
    $sText = StringRegExpReplace($sText, "(?m)^#+\s+", "")
    ; Remove links: [text](url) -> text
    $sText = StringRegExpReplace($sText, "\[(.*?)\]\(.*?\)", "$1")
    ; Remove images: ![text](url) -> nothing
    $sText = StringRegExpReplace($sText, "!\[.*?\]\(.*?\)", "")
    ; Remove inline code
    $sText = StringRegExpReplace($sText, "`(.+?)`", "$1")
    ; Remove code blocks
    $sText = StringReplace($sText, "```", "")
    ; Remove blockquotes
    $sText = StringRegExpReplace($sText, "(?m)^>\s+", "")
    ; Remove list markers: -, *, + at the start of lines (with optional indentation)
    $sText = StringRegExpReplace($sText, "(?m)^\s*[\-\*\+]\s+", "")
    ; Remove task lists: - [ ] or - [x]
    $sText = StringRegExpReplace($sText, "(?m)^\s*[\-\*\+]\s+\[[ xX]\]\s+", "")
    ; Remove numbered lists: 1. 2. etc.
    $sText = StringRegExpReplace($sText, "(?m)^\s*\d+\.\s+", "")
    ; Remove horizontal rules: ---, ***, ___
    $sText = StringRegExpReplace($sText, "(?m)^[\-\*_]{3,}\s*$", "")
    Return $sText
EndFunc

Func _Get_YTDLP_LocalVersion()
    If Not FileExists($YT_DLP_PATH) Then Return "0"
    Local $pid = Run('"' & $YT_DLP_PATH & '" --version', @ScriptDir, @SW_HIDE, $STDOUT_CHILD)
    If @error Then Return "0"
    ProcessWaitClose($pid)
    Local $sVer = StdoutRead($pid)
    Return StringRegExpReplace(StringStripWS($sVer, 3), "[^0-9.]", "")
EndFunc

Func _ShowSettings()
    ; Lay danh sach thiet bi am thanh TRUOC khi tao cua so (buoc nay cham, de bi tac vu ngam chen vao giua)
    Local $aAudioDevices = _VLC_GetAudioOutputs()
    $g_hSettingsGui = GUICreate(_T("Settings"), 450, 680, -1, -1, BitOR($WS_CAPTION, $WS_SYSMENU, $WS_POPUP))
    $g_iSettingsHelpCount = 0
    GUISwitch($g_hSettingsGui)
    GUISetBkColor($COLOR_BLUE)
    GUISetFont(9, 400, 0, "Segoe UI")

    $g_hSettingsTab = GUICtrlCreateTab(10, 10, 430, 595)

    $g_hSettingsDummyNext = GUICtrlCreateDummy()
    $g_hSettingsDummyPrev = GUICtrlCreateDummy()
    ; Accelerators are often blocked by child controls, so we also use HotKeySet below.
    Local $hDummyEnterSet = GUICtrlCreateDummy()
    Local $aAccelSettings[3][2] = [["^{TAB}", $g_hSettingsDummyNext], ["^+{TAB}", $g_hSettingsDummyPrev], ["{ENTER}", $hDummyEnterSet]]
    Local $bEnterAccSet = True
    GUISetAccelerators($aAccelSettings, $g_hSettingsGui)

    Local $aTabItems[7]
    _HK_WorkInit()
    ; --- Tab General ---
    $aTabItems[0] = GUICtrlCreateTabItem(_T("General"))
    GUICtrlCreateLabel(_T("General Settings"), 20, 50, 410, 20)
    GUICtrlSetFont(-1, 10, 800)
    GUICtrlSetColor(-1, 0xFFFFFF)

    GUICtrlCreateLabel(_T("Application language(requires restart):"), 30, 80, 150, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $cbo_Language = GUICtrlCreateCombo("", 180, 75, 230, 20, $CBS_DROPDOWNLIST)
    GUICtrlSetTip(-1, _T("Select the display language. After you press OK the application will offer to restart to apply it."))
    _Lang_Scan()
    Local $sLangItems = "", $iLangSel = 0
    For $i = 0 To UBound($g_aLangCodes) - 1
        $sLangItems &= _Lang_DisplayName($i) & "|"
        If $g_aLangCodes[$i] = $g_sLanguage Then $iLangSel = $i
    Next
    GUICtrlSetData($cbo_Language, StringTrimRight($sLangItems, 1))
    _GUICtrlComboBox_SetCurSel($cbo_Language, $iLangSel)

    Local $chk_AutoUpdate = GUICtrlCreateCheckbox(_T("Automatically check for updates on startup"), 30, 110, 380, 20)
    If $g_bAutoUpdate Then GUICtrlSetState(-1, $GUI_CHECKED)
    GUICtrlSetColor(-1, 0xFFFFFF)

    Local $chk_AutoStart = GUICtrlCreateCheckbox(_T("Start program automatically after login"), 30, 140, 380, 20)
    If $g_bAutoStart Then GUICtrlSetState(-1, $GUI_CHECKED)
    GUICtrlSetColor(-1, 0xFFFFFF)

    Local $chk_AutoDetect = GUICtrlCreateCheckbox(_T("Automatically detect YouTube and SoundCloud links in clipboard on launch"), 30, 170, 380, 20)
    If $g_bAutoDetectLink Then GUICtrlSetState(-1, $GUI_CHECKED)
    GUICtrlSetColor(-1, 0xFFFFFF)

    Local $chk_AutoUpdateYTDLP = GUICtrlCreateCheckbox(_T("Automatically check for yt-dlp updates on startup"), 30, 200, 380, 20)
    If $g_bAutoUpdateYTDLP Then GUICtrlSetState(-1, $GUI_CHECKED)
    GUICtrlSetColor(-1, 0xFFFFFF)

    Local $chk_MuteAppSounds = GUICtrlCreateCheckbox(_T("Turn off sound in application"), 30, 230, 380, 20)
    If $g_bMuteAppSounds Then GUICtrlSetState(-1, $GUI_CHECKED)
    GUICtrlSetColor(-1, 0xFFFFFF)

    Local $chk_ShowLogo = GUICtrlCreateCheckbox(_T("Show logo when the application starts"), 30, 260, 380, 20)
    If $g_bShowLogo Then GUICtrlSetState(-1, $GUI_CHECKED)
    GUICtrlSetColor(-1, 0xFFFFFF)

    Local $chk_ResumeLocal = GUICtrlCreateCheckbox(_T("Remember where I stopped in each audio file (Resume)"), 30, 290, 380, 20)
    If $g_bResumeLocal Then GUICtrlSetState(-1, $GUI_CHECKED)
    GUICtrlSetColor(-1, 0xFFFFFF)

    Local $chk_ShowLicenseConfirm = GUICtrlCreateCheckbox(_T("Show license confirmation when the application starts"), 30, 320, 380, 20)
    If $g_bShowLicenseConfirm Then GUICtrlSetState(-1, $GUI_CHECKED)
    GUICtrlSetColor(-1, 0xFFFFFF)

    Local $chk_CheckSubs = GUICtrlCreateCheckbox(_T("Check subscriptions for new content on startup"), 30, 350, 380, 20)
    If $g_bCheckSubsOnStart Then GUICtrlSetState(-1, $GUI_CHECKED)
    GUICtrlSetColor(-1, 0xFFFFFF)

    ; --- Tab Player ---
    $aTabItems[1] = GUICtrlCreateTabItem(_T("Player"))
    GUICtrlCreateLabel(_T("Player Settings"), 20, 50, 410, 20)
    GUICtrlSetFont(-1, 10, 800)
    GUICtrlSetColor(-1, 0xFFFFFF)

    GUICtrlCreateLabel(_T("Audio Output Device:"), 30, 80, 150, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $cbo_OutputDevice = GUICtrlCreateCombo("", 180, 75, 230, 20, $CBS_DROPDOWNLIST)
    GUICtrlSetTip(-1, _T("Select the audio output device. Use the arrow keys to browse the list in alphabetical order"))
    ; Giữ "Default Audio Device" (phần tử đầu tiên) cố định ở đầu danh sách,
    ; các thiết bị còn lại được sắp xếp theo thứ tự bảng chữ cái để dễ duyệt bằng trình đọc màn hình.
    If UBound($aAudioDevices) > 2 Then
        Local $aDevicesToSort[UBound($aAudioDevices) - 1][2]
        For $i = 1 To UBound($aAudioDevices) - 1
            $aDevicesToSort[$i - 1][0] = $aAudioDevices[$i][0]
            $aDevicesToSort[$i - 1][1] = $aAudioDevices[$i][1]
        Next
        _ArraySort($aDevicesToSort, 0, 0, 0, 1)
        For $i = 1 To UBound($aAudioDevices) - 1
            $aAudioDevices[$i][0] = $aDevicesToSort[$i - 1][0]
            $aAudioDevices[$i][1] = $aDevicesToSort[$i - 1][1]
        Next
    EndIf
    Local $sComboData = ""
    Local $iSelectedIdx = 0
    Local $sAudioDeviceIDsList = ""
    For $i = 0 To UBound($aAudioDevices) - 1
        $sAudioDeviceIDsList &= $aAudioDevices[$i][0] & "||^||"
        $sComboData &= $aAudioDevices[$i][1] & "|"
        If $aAudioDevices[$i][0] == $g_sAudioDeviceID Then $iSelectedIdx = $i
    Next
    $sComboData = StringTrimRight($sComboData, 1)
    GUICtrlSetData($cbo_OutputDevice, $sComboData)
    _GUICtrlComboBox_SetCurSel($cbo_OutputDevice, $iSelectedIdx)

    Local $chk_SkipSilence = GUICtrlCreateCheckbox(_T("Skip silence (Recommended only for music)"), 30, 110, 380, 20)
    If $g_bSkipSilence Then GUICtrlSetState(-1, $GUI_CHECKED)
    GUICtrlSetColor(-1, 0xFFFFFF)

    GUICtrlCreateLabel(_T("Seeking Announcement Mode:"), 30, 140, 200, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $cbo_AnnouncementMode = GUICtrlCreateCombo("", 230, 135, 180, 20, $CBS_DROPDOWNLIST)
    GUICtrlSetTip(-1, _T("Select how seeking is announced"))
    GUICtrlSetData(-1, _TL("Silent|Read percentage|Read time"), _T("Silent"))
    _GUICtrlComboBox_SetCurSel($cbo_AnnouncementMode, $g_iAnnouncementMode)

    GUICtrlCreateLabel(_T("After Video Finishes:"), 30, 175, 150, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $cbo_AfterAction = GUICtrlCreateCombo("", 180, 170, 230, 20, $CBS_DROPDOWNLIST)
    GUICtrlSetTip(-1, _T("Select the action to take after the video finishes"))
    GUICtrlSetData(-1, _TL("Close the player|Replay video|Do nothing"), _T("Do nothing"))
    ; Set current selection
    If $g_iAfterVideoAction = 0 Then
        _GUICtrlComboBox_SetCurSel($cbo_AfterAction, 0)
    ElseIf $g_iAfterVideoAction = 1 Then
        _GUICtrlComboBox_SetCurSel($cbo_AfterAction, 1)
    ElseIf $g_iAfterVideoAction = 2 Then
        _GUICtrlComboBox_SetCurSel($cbo_AfterAction, 2)
    EndIf

    GUICtrlCreateLabel(_T("Fast Forward Interval (Seconds):"), 30, 210, 200, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $inp_FFStep = GUICtrlCreateInput(String($g_iFFStep), 230, 205, 50, 20, 0x2000) ; 0x2000 = $ES_NUMBER

    GUICtrlCreateLabel(_T("Rewind Interval (Seconds):"), 30, 240, 200, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $inp_RWStep = GUICtrlCreateInput(String($g_iRWStep), 230, 235, 50, 20, 0x2000) ; 0x2000 = $ES_NUMBER

    Local $chk_ContinueWatching = GUICtrlCreateCheckbox(_T("Continue watching (Resume from last position)"), 30, 270, 380, 20)
    If $g_bContinueWatching Then GUICtrlSetState(-1, $GUI_CHECKED)
    GUICtrlSetColor(-1, 0xFFFFFF)

    Local $chk_SaveHistory = GUICtrlCreateCheckbox(_T("Save watch history"), 30, 300, 380, 20)
    If $g_bSaveHistory Then GUICtrlSetState(-1, $GUI_CHECKED)
    GUICtrlSetColor(-1, 0xFFFFFF)

    Local $chk_SaveSearchHistory = GUICtrlCreateCheckbox(_T("Save search history"), 30, 330, 380, 20)
    If $g_bSaveSearchHistory Then GUICtrlSetState(-1, $GUI_CHECKED)
    GUICtrlSetColor(-1, 0xFFFFFF)

    GUICtrlCreateLabel(_T("Play button action:"), 30, 365, 110, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $cbo_PlayAction = GUICtrlCreateCombo("", 140, 360, 270, 20, $CBS_DROPDOWNLIST)
    GUICtrlSetTip(-1, _T("Select the action of the Play button in the download complete dialog"))
    GUICtrlSetData(-1, _TL("Play with the computer's default player|Play with the application's default player"), _T("Play with the computer's default player"))
    _GUICtrlComboBox_SetCurSel($cbo_PlayAction, $g_iPlayAction)

    GUICtrlCreateLabel(_T("Equalizer:"), 30, 400, 110, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $cbo_Equalizer = GUICtrlCreateCombo("", 140, 395, 270, 20, $CBS_DROPDOWNLIST)
    GUICtrlSetTip(-1, _T("Select an equalizer preset. Choose Off to turn the equalizer off."))
    GUICtrlSetData(-1, _TL("Off|" & _EQ_PresetNames() & "|Custom"))
    _GUICtrlComboBox_SetCurSel($cbo_Equalizer, ($g_iEqPreset = -2) ? 19 : $g_iEqPreset + 1) ; item 0 = Off, item n = preset n-1, last item (19) = Custom

    Local $chk_NormalizeVolume = GUICtrlCreateCheckbox(_T("Normalize volume (keeps the loudness even between tracks)"), 30, 425, 380, 20)
    If $g_bNormalizeVolume Then GUICtrlSetState(-1, $GUI_CHECKED)
    GUICtrlSetColor(-1, 0xFFFFFF)

    GUICtrlCreateLabel(_T("Audio channels:"), 30, 457, 110, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $cbo_StereoMode = GUICtrlCreateCombo("", 140, 452, 270, 20, $CBS_DROPDOWNLIST)
    GUICtrlSetTip(-1, _T("Select how the left and right audio channels are played."))
    GUICtrlSetData(-1, _TL("Stereo (Normal)|Reverse stereo (Swap left and right channels)|Left ear only (Left channel to the left speaker, right speaker silent)|Right ear only (Right channel to the right speaker, left speaker silent)|Mono"))
    _GUICtrlComboBox_SetCurSel($cbo_StereoMode, $g_iStereoMode)

    Local $chk_AutoPan = GUICtrlCreateCheckbox(_T("Auto pan audio (Ctrl+Left / Ctrl+Right are disabled)"), 30, 485, 380, 20)
    If $g_bAutoPan Then GUICtrlSetState(-1, $GUI_CHECKED)
    GUICtrlSetColor(-1, 0xFFFFFF)

    ; Chi hien (va chi chinh duoc) khi Auto pan audio dang duoc check
    Local $lbl_AutoPanPeriod = GUICtrlCreateLabel(_T("Auto pan cycle time (seconds, 1 - 60):"), 30, 517, 250, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $inp_AutoPanPeriod = GUICtrlCreateInput(String($g_iAutoPanPeriod), 290, 512, 50, 20, 0x2000) ; 0x2000 = $ES_NUMBER
    If Not $g_bAutoPan Then
        GUICtrlSetState($lbl_AutoPanPeriod, BitOR($GUI_HIDE, $GUI_DISABLE))
        GUICtrlSetState($inp_AutoPanPeriod, BitOR($GUI_HIDE, $GUI_DISABLE))
    EndIf

    ; Version 3.3: voice enhancement and chapter announcements
    GUICtrlCreateLabel(_T("Voice enhancement:"), 30, 552, 140, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $cbo_Voice = GUICtrlCreateCombo("", 180, 548, 230, 20, $CBS_DROPDOWNLIST)
    GUICtrlSetTip(-1, _T("Makes speech clearer and evens out loud and quiet voices. Good for podcasts and lectures."))
    GUICtrlSetData(-1, _TL("Off|Light|Strong"))
    _GUICtrlComboBox_SetCurSel($cbo_Voice, $g_iVoiceMode)

    Local $chk_AnnounceChapters = GUICtrlCreateCheckbox(_T("Announce the chapter title when a new chapter starts"), 30, 580, 380, 20)
    If $g_bAnnounceChapters Then GUICtrlSetState(-1, $GUI_CHECKED)
    GUICtrlSetColor(-1, 0xFFFFFF)

    ; --- Tab Download ---
    $aTabItems[2] = GUICtrlCreateTabItem(_T("Download"))
    GUICtrlCreateLabel(_T("Download Settings"), 20, 50, 410, 20)
    GUICtrlSetFont(-1, 10, 800)
    GUICtrlSetColor(-1, 0xFFFFFF)

    Local $sTempDLPath = $g_sDownloadPath
    GUICtrlCreateLabel(_T("Download Folder:"), 30, 80, 380, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $inp_DownloadPath = GUICtrlCreateEdit($sTempDLPath, 30, 105, 380, 60, BitOR($ES_READONLY, $WS_TABSTOP))
    _AllowUIPI($inp_DownloadPath) ; Ensure screen reader access
    ; Subclass to prevent manual typing if needed, but standard edit is better for accessibility.
    ; We'll just leave it as standard edit so screen readers can read it easily.

    Local $btn_ChangePath = GUICtrlCreateButton(_T("Change Path"), 30, 175, 180, 30)
    Local $btn_ResetPath = GUICtrlCreateButton(_T("Reset to Default Directory"), 220, 175, 190, 30)

    ; --- Tab Radio ---
    $aTabItems[3] = GUICtrlCreateTabItem(_T("Radio"))
    GUICtrlCreateLabel(_T("Radio Settings"), 20, 50, 410, 20)
    GUICtrlSetFont(-1, 10, 800)
    GUICtrlSetColor(-1, 0xFFFFFF)

    Local $sTempRecPath = $g_sRadioRecPath
    GUICtrlCreateLabel(_T("Recording Folder:"), 30, 80, 380, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $inp_RecPath = GUICtrlCreateEdit($sTempRecPath, 30, 105, 380, 50, BitOR($ES_READONLY, $WS_TABSTOP))
    _AllowUIPI($inp_RecPath)
    Local $btn_RecChange = GUICtrlCreateButton(_T("Change Path"), 30, 163, 180, 28)
    Local $btn_RecReset = GUICtrlCreateButton(_T("Reset to Default Directory"), 220, 163, 190, 28)
    Local $btn_RecOpen = GUICtrlCreateButton(_T("Open Recording Folder"), 30, 197, 380, 28)

    GUICtrlCreateLabel(_T("Recording format:"), 30, 242, 140, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $cbo_RecFormat = GUICtrlCreateCombo("", 180, 237, 230, 20, $CBS_DROPDOWNLIST)
    GUICtrlSetData(-1, _TL("M4A (Audio)|MP3 (Audio)|OGG (Audio)|WAV (Audio)"))
    _GUICtrlComboBox_SetCurSel($cbo_RecFormat, _RadioRec_Idx($g_aRadioRecFormats, $g_sRadioRecFormat))

    GUICtrlCreateLabel(_T("Recording bitrate:"), 30, 277, 140, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $cbo_RecBitrate = GUICtrlCreateCombo("", 180, 272, 230, 20, $CBS_DROPDOWNLIST)
    GUICtrlSetData(-1, _TL("128 kbps|192 kbps|256 kbps|320 kbps"))
    _GUICtrlComboBox_SetCurSel($cbo_RecBitrate, _RadioRec_Idx($g_aRadioRecBitrates, $g_iRadioRecBitrate))
    If $g_sRadioRecFormat = "WAV" Then GUICtrlSetState($cbo_RecBitrate, $GUI_DISABLE)

    GUICtrlCreateLabel(_T("Recording channels:"), 30, 312, 140, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $cbo_RecChannels = GUICtrlCreateCombo("", 180, 307, 230, 20, $CBS_DROPDOWNLIST)
    GUICtrlSetData(-1, _TL("Stereo|Mono"))
    _GUICtrlComboBox_SetCurSel($cbo_RecChannels, ($g_iRadioRecChannels = 1) ? 1 : 0)

    GUICtrlCreateLabel(_T("Sample rate:"), 30, 347, 140, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $cbo_RecRate = GUICtrlCreateCombo("", 180, 342, 230, 20, $CBS_DROPDOWNLIST)
    GUICtrlSetData(-1, _TL("Same as the station|22050 Hz|44100 Hz|48000 Hz"))
    _GUICtrlComboBox_SetCurSel($cbo_RecRate, _RadioRec_Idx($g_aRadioRecRates, $g_iRadioRecRate))

    GUICtrlCreateLabel(_T("Stop recording automatically after (minutes, 0 = never):"), 30, 383, 380, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $inp_RecAutoStop = GUICtrlCreateInput(String($g_iRadioRecAutoStop), 30, 406, 80, 22, $ES_NUMBER)
    _AllowUIPI($inp_RecAutoStop)

    GUICtrlCreateLabel(_T("Recording volume (0-100):"), 30, 442, 380, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $sld_RecVol = GUICtrlCreateSlider(30, 464, 380, 30, BitOR(0x0001, $WS_TABSTOP))
    GUICtrlSetLimit($sld_RecVol, 100, 0)
    GUICtrlSendMsg($sld_RecVol, 0x0417, 0, 5)
    GUICtrlSendMsg($sld_RecVol, 0x0415, 0, 10)
    GUICtrlSetData($sld_RecVol, $g_iRadioRecVolume)

    ; --- Tab Search ---
    $aTabItems[4] = GUICtrlCreateTabItem(_T("Search"))
    GUICtrlCreateLabel(_T("Search Settings"), 20, 50, 410, 20)
    GUICtrlSetFont(-1, 10, 800)
    GUICtrlSetColor(-1, 0xFFFFFF)

    Local $chk_VoiceAutoSearch = GUICtrlCreateCheckbox(_T("Automatically search after voice input"), 30, 80, 380, 20)
    If $g_bVoiceAutoSearch Then GUICtrlSetState(-1, $GUI_CHECKED)
    GUICtrlSetColor(-1, 0xFFFFFF)

    Local $chk_TypingSound = GUICtrlCreateCheckbox(_T("Enable typing sounds in search box"), 30, 110, 380, 20)
    If $g_bTypingSoundEnabled Then GUICtrlSetState(-1, $GUI_CHECKED)
    GUICtrlSetColor(-1, 0xFFFFFF)

    Local $lbl_TypingSoundSet = GUICtrlCreateLabel(_T("select typing sound:"), 30, 140, 150, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $cbo_TypingSoundSet = GUICtrlCreateCombo("", 180, 135, 230, 20, $CBS_DROPDOWNLIST)
    GUICtrlSetTip(-1, _T("Select the typing sound set. The list is in alphabetical order. Use the arrow keys to browse"))
    GUICtrlSetData(-1, "1blueSwitch|2redSwitch|3brownSwitche|iPhone|Samsung_Galaxy|VDH_keyboard1|VDH_keyboard2", $g_sTypingSoundSet)
    ; The list of sounds exists only while typing sounds are on (kept in step by _Settings_SyncTypingSet)
    If Not $g_bTypingSoundEnabled Then
        GUICtrlSetState($lbl_TypingSoundSet, BitOR($GUI_HIDE, $GUI_DISABLE))
        GUICtrlSetState($cbo_TypingSoundSet, BitOR($GUI_HIDE, $GUI_DISABLE))
    EndIf

    ; --- Tab Data ---
    $aTabItems[5] = GUICtrlCreateTabItem(_T("Data"))
    GUICtrlCreateLabel(_T("Configuration Backup & Restore"), 20, 50, 410, 20)
    GUICtrlSetFont(-1, 10, 800)
    GUICtrlSetColor(-1, 0xFFFFFF)

    Local $btn_Backup = GUICtrlCreateButton(_T("Backup Configuration..."), 30, 90, 200, 35)
    Local $btn_Restore = GUICtrlCreateButton(_T("Restore Configuration..."), 30, 140, 200, 35)

    ; --- Tab Shortcuts ---
    $aTabItems[6] = GUICtrlCreateTabItem(_T("Shortcuts"))
    GUICtrlCreateLabel(_T("Keyboard Shortcuts"), 20, 50, 410, 20)
    GUICtrlSetFont(-1, 10, 800)
    GUICtrlSetColor(-1, 0xFFFFFF)
    GUICtrlCreateLabel(_T("Show shortcuts for:"), 30, 80, 140, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $cbo_HKScope = GUICtrlCreateCombo("", 180, 75, 230, 20, $CBS_DROPDOWNLIST)
    GUICtrlSetData(-1, _TL("Main window|Player"), _T("Main window"))
    GUICtrlCreateLabel(_T("Shortcuts (press Enter to change the selected one):"), 30, 110, 380, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $lst_HK = GUICtrlCreateList("", 30, 135, 380, 290, BitOR($LBS_NOTIFY, $WS_VSCROLL, $WS_BORDER))
    Local $btn_HKChange = GUICtrlCreateButton(_T("Change..."), 30, 435, 120, 30)
    Local $btn_HKReset = GUICtrlCreateButton(_T("Reset this one"), 160, 435, 140, 30)
    Local $btn_HKRemove = GUICtrlCreateButton(_T("Remove"), 310, 435, 100, 30)
    Local $btn_HKResetAll = GUICtrlCreateButton(_T("Reset all shortcuts"), 30, 475, 380, 30)
    _HK_FillList($lst_HK, 0)

    GUICtrlCreateTabItem("") ; End Tab Control

    Local $btn_Save = GUICtrlCreateButton(_T("Ok"), 120, 612, 100, 35)
    Local $btn_Cancel = GUICtrlCreateButton(_T("Cancel"), 230, 612, 100, 35)

    ; F1 trong Settings: đọc mô tả của điều khiển đang focus
    _Settings_AddHelp($g_hSettingsTab, "Use the Left and Right Arrow keys, or Ctrl+Tab and Ctrl+Shift+Tab, to switch between the settings tabs. Press Tab to move to the controls of the selected tab.")
    _Settings_AddHelp($cbo_Language, "Chooses the language of the application. A different choice takes effect after the application restarts.")
    _Settings_AddHelp($chk_AutoUpdate, "Checks for a newer version of the application each time it starts.")
    _Settings_AddHelp($chk_AutoStart, "Starts the application automatically each time you sign in to Windows.")
    _Settings_AddHelp($chk_AutoDetect, "Looks for a YouTube or SoundCloud link in the clipboard when the application starts.")
    _Settings_AddHelp($chk_AutoUpdateYTDLP, "Checks for a newer version of yt-dlp, the component that fetches video and audio from websites, each time the application starts.")
    _Settings_AddHelp($chk_MuteAppSounds, "When selected, all sounds of the application from the sounds folder are silenced. Typing sounds are not affected, they are controlled by their own option in the Search tab. Clear this option to hear the sounds again.")
    _Settings_AddHelp($chk_ShowLogo, "When selected, the logo and its sound are played each time the application starts. When cleared, only the door sound is played and the application opens straight away.")
    _Settings_AddHelp($chk_ShowLicenseConfirm, "When selected, the license is confirmed each time the application starts: the door sound is played and you hear that the license is accepted. When cleared, the door sound is not played and the application opens straight away.")
    _Settings_AddHelp($chk_CheckSubs, "When selected, each time the application starts it quietly checks your podcast and YouTube subscriptions. If there are new episodes or videos you hear a sound and a short announcement; if there is nothing new, nothing happens. When cleared, nothing is checked at startup and you check by hand with the Check for new episodes and Check for new videos buttons in My subscriptions.")
    _Settings_AddHelp($cbo_OutputDevice, "Chooses the audio device used by the Player and the Radio. The new device is used as soon as you press OK.")
    _Settings_AddHelp($chk_SkipSilence, "Skips over silent gaps in a track while it plays. Recommended only for music.")
    _Settings_AddHelp($cbo_AnnouncementMode, "Chooses what is announced when you seek: nothing, the position as a percentage, or the position as a time.")
    _Settings_AddHelp($cbo_AfterAction, "Chooses what happens when a video finishes: close the player, replay the video, or do nothing.")
    _Settings_AddHelp($inp_FFStep, "The number of seconds the player jumps forward when you fast forward.")
    _Settings_AddHelp($inp_RWStep, "The number of seconds the player jumps back when you rewind.")
    _Settings_AddHelp($chk_ContinueWatching, "Resumes a video from the point where you stopped watching it last time.")
    _Settings_AddHelp($chk_SaveHistory, "Keeps a list of the videos you have watched in Watch History. Clear this option to stop recording it.")
    _Settings_AddHelp($chk_SaveSearchHistory, "Keeps the searches you make so you can find them again. Clear this option to stop saving them.")
    _Settings_AddHelp($cbo_PlayAction, "Chooses what the Play button in the download complete dialog does: open the file with the default player of the computer, or with the player of this application.")
    _Settings_AddHelp($cbo_Equalizer, "Chooses an equalizer preset that shapes the sound, for example Rock or Classical. Choose Off to turn the equalizer off. The change is applied immediately.")
    _Settings_AddHelp($cbo_StereoMode, "Chooses how the left and right audio channels are played: normal stereo, swapped channels, only the left ear, only the right ear, or mono (both channels mixed together). The change is applied to the music immediately.")
    _Settings_AddHelp($chk_AutoPan, "When selected, the music pans by itself, moving slowly between the left and right ears while it plays, with nothing to press. Ctrl+Left and Ctrl+Right do nothing while this option is on. Clear this option to pan by hand again.")
    _Settings_AddHelp($inp_AutoPanPeriod, "The number of seconds the sound takes to travel from the left ear to the right ear and back. A smaller number pans faster. Allowed values are 1 to 60.")
    _Settings_AddHelp($cbo_Voice, "Makes speech clearer: a compressor evens out loud and quiet voices and an equalizer lifts the speech range. Light is gentle, Strong is more effective for quiet or unclear recordings. The equalizer part is used only when the equalizer above is Off. You can also press Ctrl+Shift+V in the player to switch between Off, Light and Strong.")
    _Settings_AddHelp($chk_AnnounceChapters, "When a video, podcast episode or audio file has chapters, the screen reader announces the title of each new chapter as it begins. Page Up and Page Down move between chapters and H lists them.")
    _Settings_AddHelp($chk_NormalizeVolume, "Evens out the loudness so that quiet and loud tracks sound alike. It takes effect from the next track you play.")
    _Settings_AddHelp($inp_DownloadPath, "Shows the folder where downloaded files are saved. This box is read-only. Use the Change Path button to choose another folder.")
    _Settings_AddHelp($btn_ChangePath, "Opens a window where you choose another folder for downloads.")
    _Settings_AddHelp($btn_ResetPath, "Sets the download folder back to the default download folder in the application folder.")
    _Settings_AddHelp($inp_RecPath, "Shows the folder where radio recordings are saved. This box is read-only. Use the Change Path button to choose another folder.")
    _Settings_AddHelp($btn_RecChange, "Opens a window where you choose another folder for radio recordings.")
    _Settings_AddHelp($btn_RecReset, "Sets the recording folder back to the default radio_recording folder in the application folder.")
    _Settings_AddHelp($btn_RecOpen, "Opens the recording folder in Windows Explorer.")
    _Settings_AddHelp($cbo_RecFormat, "Chooses the audio format of radio recordings. These are the same audio formats as the Download feature.")
    _Settings_AddHelp($cbo_RecBitrate, "Chooses the quality of MP3, M4A and OGG recordings in kilobits per second. A higher number sounds better and makes a bigger file. WAV is not compressed, so it ignores this setting.")
    _Settings_AddHelp($cbo_RecChannels, "Records in stereo (left and right) or in mono (one channel, half the file size).")
    _Settings_AddHelp($cbo_RecRate, "Chooses the sampling rate of the recording. Same as the station keeps the rate the station uses.")
    _Settings_AddHelp($sld_RecVol, "Sets how loud the recordings are, from 0 to 100, on the same scale as the radio volume. 100 is the full volume of the station. Use the left and right arrows to change it by 5, Page Up and Page Down by 10.")
    _Settings_AddHelp($inp_RecAutoStop, "The recording stops by itself after this many minutes. Enter 0 to record until you stop it.")
    _Settings_AddHelp($chk_VoiceAutoSearch, "Starts the search automatically when you finish entering it by voice, so you do not need to press the Search button.")
    _Settings_AddHelp($chk_TypingSound, "Plays a key sound as you type in a search box. When this is selected, a list appears below to choose the sound. When it is cleared the list is hidden.")
    _Settings_AddHelp($cbo_TypingSoundSet, "Chooses the keyboard sound played when you type in the search box. Use the arrow keys to browse the list.")
    _Settings_AddHelp($chk_ResumeLocal, "When selected, an audio file you open from your computer continues from the point where you stopped listening to it last time. Each file remembers its own position.")
    _Settings_AddHelp($cbo_HKScope, "Chooses which shortcuts are listed: those of the main window or those of the player.")
    _Settings_AddHelp($lst_HK, "Lists the actions and their shortcuts. Use the Up and Down arrow keys to choose an action and press Enter to change its shortcut.")
    _Settings_AddHelp($btn_HKChange, "Opens a window where you press the new keys for the selected action, or choose them from a list.")
    _Settings_AddHelp($btn_HKReset, "Sets the selected action back to its original shortcut.")
    _Settings_AddHelp($btn_HKRemove, "Removes the shortcut of the selected action, so the action has no shortcut.")
    _Settings_AddHelp($btn_HKResetAll, "Sets every shortcut of the main window and the player back to the original keys.")
    _Settings_AddHelp($btn_Backup, "Saves a backup copy of your configuration to a location you choose.")
    _Settings_AddHelp($btn_Restore, "Restores your configuration from a backup file you choose.")
    _Settings_AddHelp($btn_Save, "Saves all your changes and closes Settings.")
    _Settings_AddHelp($btn_Cancel, "Closes Settings and discards your changes.")

    GUISetState(@SW_SHOW, $g_hSettingsGui)

    ; Register WM_ACTIVATE to handle hotkeys only when window is active
    GUIRegisterMsg($WM_ACTIVATE, "_Settings_WM_ACTIVATE")

    ; Initial activation
    _Settings_ToggleHotKeys(True)

    While 1
        _SyncEnterAccel($g_hSettingsGui, $aAccelSettings, $lst_HK, $bEnterAccSet)
        _Settings_SyncTypingSet($chk_TypingSound, $lbl_TypingSoundSet, $cbo_TypingSoundSet)
        Local $nMsg = _GuiMsg($g_hSettingsGui)
        Switch $nMsg
            Case $GUI_EVENT_CLOSE, $btn_Cancel
                _Settings_ToggleHotKeys(False)
                GUIRegisterMsg($WM_ACTIVATE, "")
                GUIDelete($g_hSettingsGui)
                Return

            Case $g_hSettingsDummyNext
                Local $iTabCount = _GUICtrlTab_GetItemCount(GUICtrlGetHandle($g_hSettingsTab))
                Local $iCurr = _GUICtrlTab_GetCurSel(GUICtrlGetHandle($g_hSettingsTab))
                Local $iNext = ($iCurr + 1 >= $iTabCount) ? 0 : $iCurr + 1
                GUICtrlSetState($aTabItems[$iNext], $GUI_SHOW)
                ControlFocus($g_hSettingsGui, "", $g_hSettingsTab)

            Case $g_hSettingsDummyPrev
                Local $iTabCount = _GUICtrlTab_GetItemCount(GUICtrlGetHandle($g_hSettingsTab))
                Local $iCurr = _GUICtrlTab_GetCurSel(GUICtrlGetHandle($g_hSettingsTab))
                Local $iPrev = ($iCurr - 1 < 0) ? $iTabCount - 1 : $iCurr - 1
                GUICtrlSetState($aTabItems[$iPrev], $GUI_SHOW)
                ControlFocus($g_hSettingsGui, "", $g_hSettingsTab)

            Case $cbo_HKScope
                _HK_FillList($lst_HK, _GUICtrlComboBox_GetCurSel($cbo_HKScope))

            Case $btn_HKChange, $hDummyEnterSet
                Local $iHKPos = _GUICtrlListBox_GetCurSel($lst_HK)
                If $iHKPos >= 0 Then
                    Local $iHKReg = $g_aHKListIdx[$iHKPos]
                    Local $sHKNew = _HK_EditDialog($iHKReg, $g_hSettingsGui)
                    If $sHKNew <> "" Then _HK_TryAssign($iHKReg, $sHKNew, $g_hSettingsGui)
                    _HK_FillList($lst_HK, _GUICtrlComboBox_GetCurSel($cbo_HKScope), $iHKPos)
                    ControlFocus($g_hSettingsGui, "", $lst_HK)
                EndIf

            Case $btn_HKReset
                Local $iHKPos2 = _GUICtrlListBox_GetCurSel($lst_HK)
                If $iHKPos2 >= 0 Then
                    Local $iHKReg2 = $g_aHKListIdx[$iHKPos2]
                    _HK_TryAssign($iHKReg2, $g_aHK[$iHKReg2][2], $g_hSettingsGui)
                    _HK_FillList($lst_HK, _GUICtrlComboBox_GetCurSel($cbo_HKScope), $iHKPos2)
                EndIf

            Case $btn_HKRemove
                Local $iHKPos3 = _GUICtrlListBox_GetCurSel($lst_HK)
                If $iHKPos3 >= 0 Then
                    $g_aHKWork[$g_aHKListIdx[$iHKPos3]] = "none"
                    _HK_FillList($lst_HK, _GUICtrlComboBox_GetCurSel($cbo_HKScope), $iHKPos3)
                EndIf

            Case $btn_HKResetAll
                If MsgBox(36, _T("Confirm"), _T("Are you sure you want to reset all shortcuts to their original keys?"), 0, $g_hSettingsGui) = 6 Then
                    For $iHKr = 0 To $g_iHKCount - 1
                        $g_aHKWork[$iHKr] = $g_aHK[$iHKr][2]
                    Next
                    _HK_FillList($lst_HK, _GUICtrlComboBox_GetCurSel($cbo_HKScope))
                EndIf

            Case $btn_Backup
                Local $sSavePath = FileSaveDialog(_T("Select backup location"), @DesktopDir, "Zip Archive (*.zip)", 2, "VDH_Config_Backup.zip")
                If Not @error Then
                    If StringRight($sSavePath, 4) <> ".zip" Then $sSavePath &= ".zip"

                    ; Use PowerShell to zip the entire SETTINGS_DIR
                    Local $sPSCmd = 'powershell -Command "Compress-Archive -Path ''' & $SETTINGS_DIR & '\*''' & ' -DestinationPath ''' & $sSavePath & ''' -Force"'
                    GUISetCursor(15, 1, $g_hSettingsGui)
                    Local $iPidZip = Run($sPSCmd, "", @SW_HIDE)
                    While ProcessExists($iPidZip)
                        GUIGetMsg()
                        Sleep(10)
                    WEnd
                    GUISetCursor(2, 0, $g_hSettingsGui)

                    If FileExists($sSavePath) Then
                        MsgBox(64, _T("Backup Completed"), _TF("The configuration backup has been created successfully at:\n{1}", $sSavePath))
                    Else
                        MsgBox(16, _T("Error"), _T("Failed to create backup. Please check if you have write permissions."))
                    EndIf
                EndIf

            Case $btn_Restore
                Local $sOpenPath = FileOpenDialog(_T("Select Backup File"), @DesktopDir, "Zip Archive (*.zip)", 1)
                If Not @error Then
                    _AppSoundPlay("sounds/restart.wav")
                    Local $iConfirm = MsgBox(4, _T("Confirm Restore"), _T("Restoring data will overwrite your current configuration and restart the program. Are you sure you want to proceed?"))
                    If $iConfirm = 6 Then ; Yes
                        ; Use PowerShell to unzip to SETTINGS_DIR
                        Local $sPSCmd = 'powershell -Command "Expand-Archive -Path ''' & $sOpenPath & ''' -DestinationPath ''' & $SETTINGS_DIR & ''' -Force"'
                        GUISetCursor(15, 1, $g_hSettingsGui)
                        Local $iPidUnzip = Run($sPSCmd, "", @SW_HIDE)
                        While ProcessExists($iPidUnzip)
                            GUIGetMsg()
                            Sleep(10)
                        WEnd
                        GUISetCursor(2, 0, $g_hSettingsGui)

                        _AppSoundPlay("sounds/restart.wav")
                        MsgBox(0, _T("Success"), _T("Restore successful! Program will now restart."))
                        ShellExecute(@ScriptFullPath, "/restart")
                        Exit
                    EndIf
                EndIf

            Case $chk_AutoPan
                If GUICtrlRead($chk_AutoPan) = $GUI_CHECKED Then
                    GUICtrlSetState($lbl_AutoPanPeriod, BitOR($GUI_SHOW, $GUI_ENABLE))
                    GUICtrlSetState($inp_AutoPanPeriod, BitOR($GUI_SHOW, $GUI_ENABLE))
                    ; Khong tu dong chuyen focus sang o nhap thoi gian: focus o lai tren checkbox Auto pan
                Else
                    GUICtrlSetState($lbl_AutoPanPeriod, BitOR($GUI_HIDE, $GUI_DISABLE))
                    GUICtrlSetState($inp_AutoPanPeriod, BitOR($GUI_HIDE, $GUI_DISABLE))
                EndIf

            Case $btn_ChangePath
                Local $sNewPath = FileSelectFolder(_T("Select Download Folder"), "", 1, $sTempDLPath, $g_hSettingsGui)
                If Not @error And $sNewPath <> "" Then
                    $sTempDLPath = $sNewPath
                    GUICtrlSetData($inp_DownloadPath, $sTempDLPath)
                EndIf

            Case $btn_ResetPath
                $sTempDLPath = @ScriptDir & "\download"
                If Not FileExists($sTempDLPath) Then DirCreate($sTempDLPath)
                GUICtrlSetData($inp_DownloadPath, $sTempDLPath)

            Case $btn_RecChange
                Local $sNewRecPath = FileSelectFolder(_T("Select Recording Folder"), "", 1, $sTempRecPath, $g_hSettingsGui)
                If Not @error And $sNewRecPath <> "" Then
                    $sTempRecPath = $sNewRecPath
                    GUICtrlSetData($inp_RecPath, $sTempRecPath)
                EndIf

            Case $btn_RecReset
                $sTempRecPath = @ScriptDir & "\radio_recording"
                If Not FileExists($sTempRecPath) Then DirCreate($sTempRecPath)
                GUICtrlSetData($inp_RecPath, $sTempRecPath)

            Case $btn_RecOpen
                If Not FileExists($sTempRecPath) Then DirCreate($sTempRecPath)
                ShellExecute($sTempRecPath)

            Case $cbo_RecFormat
                ; WAV is not compressed: the bitrate does not apply
                If _GUICtrlComboBox_GetCurSel($cbo_RecFormat) = 3 Then
                    GUICtrlSetState($cbo_RecBitrate, $GUI_DISABLE)
                Else
                    GUICtrlSetState($cbo_RecBitrate, $GUI_ENABLE)
                EndIf

            Case $btn_Save
                ; Read checkbox states
                $g_bAutoUpdate = (GUICtrlRead($chk_AutoUpdate) = $GUI_CHECKED)
                $g_bAutoStart = (GUICtrlRead($chk_AutoStart) = $GUI_CHECKED)
                $g_bAutoDetectLink = (GUICtrlRead($chk_AutoDetect) = $GUI_CHECKED)
                $g_bAutoUpdateYTDLP = (GUICtrlRead($chk_AutoUpdateYTDLP) = $GUI_CHECKED)
                $g_bMuteAppSounds = (GUICtrlRead($chk_MuteAppSounds) = $GUI_CHECKED)
                $g_bShowLogo = (GUICtrlRead($chk_ShowLogo) = $GUI_CHECKED)
                $g_bShowLicenseConfirm = (GUICtrlRead($chk_ShowLicenseConfirm) = $GUI_CHECKED)
                $g_bCheckSubsOnStart = (GUICtrlRead($chk_CheckSubs) = $GUI_CHECKED)
                If $g_bMuteAppSounds Then DllCall("winmm.dll", "int", "PlaySoundW", "ptr", 0, "ptr", 0, "dword", 0) ; dừng âm thanh đang phát
                $g_bVoiceAutoSearch = (GUICtrlRead($chk_VoiceAutoSearch) = $GUI_CHECKED)
                $g_bTypingSoundEnabled = (GUICtrlRead($chk_TypingSound) = $GUI_CHECKED)
                $g_sTypingSoundSet = GUICtrlRead($cbo_TypingSoundSet)
                $g_bSkipSilence = (GUICtrlRead($chk_SkipSilence) = $GUI_CHECKED)
                Local $iEqSel = _GUICtrlComboBox_GetCurSel($cbo_Equalizer)
                If $iEqSel = 19 Then
                    $g_iEqPreset = -2 ; Custom curve (set in the Equalizer window)
                Else
                    $g_iEqPreset = $iEqSel - 1
                    If $g_iEqPreset < -1 Or $g_iEqPreset > 17 Then $g_iEqPreset = -1
                EndIf
                $g_bNormalizeVolume = (GUICtrlRead($chk_NormalizeVolume) = $GUI_CHECKED)
                $g_iVoiceMode = _GUICtrlComboBox_GetCurSel($cbo_Voice)
                If $g_iVoiceMode < 0 Or $g_iVoiceMode > 2 Then $g_iVoiceMode = 0
                $g_bAnnounceChapters = (GUICtrlRead($chk_AnnounceChapters) = $GUI_CHECKED)
                _VLC_ApplyEqualizer() ; applies to the track that is playing, if any
                $g_iStereoMode = _GUICtrlComboBox_GetCurSel($cbo_StereoMode)
                If $g_iStereoMode < 0 Or $g_iStereoMode > 4 Then $g_iStereoMode = 0
                _VLC_ApplyStereoMode() ; applies to the track that is playing, if any (re-checked every 0.5s in the player loop)
                Local $bNewAutoPan = (GUICtrlRead($chk_AutoPan) = $GUI_CHECKED)
                If $bNewAutoPan <> $g_bAutoPan Then
                    $g_bAutoPan = $bNewAutoPan
                    ; Bat auto pan: bo pan thu cong ve 0 va bat dau troi tu giua. Tat auto pan: tra am thanh ve giua.
                    $g_iPanStep = 0
                    $g_fPan = 0.0
                    $g_fAutoPanPhase = 0.0
                    $g_fAutoPanPos = 0.0
                    $g_hAutoPanTimer = 0
                EndIf
                If $g_bAutoPan Then
                    Local $iNewPeriod = Int(GUICtrlRead($inp_AutoPanPeriod))
                    If $iNewPeriod < 1 Then $iNewPeriod = 1
                    If $iNewPeriod > 60 Then $iNewPeriod = 60
                    $g_iAutoPanPeriod = $iNewPeriod
                EndIf
                _Pan_Sync(True) ; left ear only / right ear only (and going back to normal) work through the audio session channel levels
                $g_bContinueWatching = (GUICtrlRead($chk_ContinueWatching) = $GUI_CHECKED)
                $g_bResumeLocal = (GUICtrlRead($chk_ResumeLocal) = $GUI_CHECKED)
                $g_bSaveHistory = (GUICtrlRead($chk_SaveHistory) = $GUI_CHECKED)
                $g_bSaveSearchHistory = (GUICtrlRead($chk_SaveSearchHistory) = $GUI_CHECKED)
                $g_iAnnouncementMode = _GUICtrlComboBox_GetCurSel($cbo_AnnouncementMode)
                $g_iAfterVideoAction = _GUICtrlComboBox_GetCurSel($cbo_AfterAction)
                $g_iPlayAction = _GUICtrlComboBox_GetCurSel($cbo_PlayAction)
                If $g_iPlayAction < 0 Or $g_iPlayAction > 1 Then $g_iPlayAction = 0

                $g_iFFStep = Int(GUICtrlRead($inp_FFStep))
                $g_iRWStep = Int(GUICtrlRead($inp_RWStep))
                If $g_iFFStep < 1 Then $g_iFFStep = 1
                If $g_iRWStep < 1 Then $g_iRWStep = 1
                $g_iSeekStep = $g_iFFStep

                Local $iSelOutIdx = _GUICtrlComboBox_GetCurSel($cbo_OutputDevice)
                Local $aIds = StringSplit($sAudioDeviceIDsList, "||^||", 3)
                Local $sNewDeviceID = $g_sAudioDeviceID
                If $iSelOutIdx >= 0 And $iSelOutIdx < UBound($aIds) Then
                    $sNewDeviceID = $aIds[$iSelOutIdx]
                EndIf
                Local $bLangChanged = False
                Local $sNewLang = $g_sLanguage
                Local $iSelLang = _GUICtrlComboBox_GetCurSel($cbo_Language)
                If $iSelLang >= 0 And $iSelLang < UBound($g_aLangCodes) Then
                    If $g_aLangCodes[$iSelLang] <> $g_sLanguage Then
                        $bLangChanged = True
                        $sNewLang = $g_aLangCodes[$iSelLang]
                    EndIf
                EndIf
                Local $bDeviceChanged = False
                If $sNewDeviceID <> $g_sAudioDeviceID Then
                    $bDeviceChanged = True
                    $g_sAudioDeviceID = $sNewDeviceID
                    IniWrite($CONFIG_FILE, "Settings", "AudioDeviceID", $g_sAudioDeviceID)
                EndIf

                ; Save to INI
                IniWrite($CONFIG_FILE, "Settings", "AutoUpdate", $g_bAutoUpdate ? "true" : "false")
                IniWrite($CONFIG_FILE, "Settings", "AutoStart", $g_bAutoStart ? "true" : "false")
                IniWrite($CONFIG_FILE, "Settings", "AutoDetectLink", $g_bAutoDetectLink ? "true" : "false")
                IniWrite($CONFIG_FILE, "Settings", "AutoUpdateYTDLP", $g_bAutoUpdateYTDLP ? "true" : "false")
                IniWrite($CONFIG_FILE, "Settings", "MuteAppSounds", $g_bMuteAppSounds ? "true" : "false")
                IniWrite($CONFIG_FILE, "Settings", "ShowLogo", $g_bShowLogo ? "true" : "false")
                IniWrite($CONFIG_FILE, "Settings", "ShowLicenseConfirm", $g_bShowLicenseConfirm ? "true" : "false")
                IniWrite($CONFIG_FILE, "Settings", "VoiceAutoSearch", $g_bVoiceAutoSearch ? "true" : "false")
                IniWrite($CONFIG_FILE, "Settings", "SkipSilence", $g_bSkipSilence ? "true" : "false")
                IniWrite($CONFIG_FILE, "Settings", "EqualizerPreset", String($g_iEqPreset))
                IniWrite($CONFIG_FILE, "Settings", "NormalizeVolume", $g_bNormalizeVolume ? "true" : "false")
                IniWrite($CONFIG_FILE, "Settings", "StereoMode", String($g_iStereoMode))
                IniWrite($CONFIG_FILE, "Settings", "VoiceEnhance", String($g_iVoiceMode))
                IniWrite($CONFIG_FILE, "Settings", "AnnounceChapters", $g_bAnnounceChapters ? "true" : "false")
                IniWrite($CONFIG_FILE, "Settings", "AutoPan", $g_bAutoPan ? "true" : "false")
                IniWrite($CONFIG_FILE, "Settings", "AutoPanPeriod", String($g_iAutoPanPeriod))
                IniWrite($CONFIG_FILE, "Settings", "ContinueWatching", $g_bContinueWatching ? "true" : "false")
                IniWrite($CONFIG_FILE, "Settings", "ResumeLocal", $g_bResumeLocal ? "true" : "false")
                IniWrite($CONFIG_FILE, "Settings", "SaveHistory", $g_bSaveHistory ? "true" : "false")
                IniWrite($CONFIG_FILE, "Settings", "SaveSearchHistory", $g_bSaveSearchHistory ? "true" : "false")
                IniWrite($CONFIG_FILE, "Settings", "AnnouncementMode", String($g_iAnnouncementMode))
                IniWrite($CONFIG_FILE, "Settings", "AutoPlay", $g_bAutoPlay ? "true" : "false")
                IniWrite($CONFIG_FILE, "Settings", "Repeat", $g_bRepeat ? "true" : "false")
                IniWrite($CONFIG_FILE, "Settings", "AfterVideoAction", String($g_iAfterVideoAction))
                IniWrite($CONFIG_FILE, "Settings", "PlayAction", String($g_iPlayAction))
                IniWrite($CONFIG_FILE, "Settings", "SearchFilter", $g_sSearchFilter)
                If StringStripWS($sTempDLPath, 3) <> "" Then
                    $g_sDownloadPath = $sTempDLPath
                    If Not FileExists($g_sDownloadPath) Then DirCreate($g_sDownloadPath)
                    IniWrite($CONFIG_FILE, "Settings", "DownloadPath", $g_sDownloadPath)
                EndIf
                IniWrite($CONFIG_FILE, "Settings", "FFStep", String($g_iFFStep))
                IniWrite($CONFIG_FILE, "Settings", "RWStep", String($g_iRWStep))
                IniWrite($CONFIG_FILE, "Settings", "CheckSubsOnStart", $g_bCheckSubsOnStart ? "true" : "false")
                IniWrite($CONFIG_FILE, "Settings", "TypingSoundEnabled", $g_bTypingSoundEnabled ? "true" : "false")
                IniWrite($CONFIG_FILE, "Settings", "TypingSoundSet", $g_sTypingSoundSet)
                ; --- Radio recording ---
                Local $iRecSel = _GUICtrlComboBox_GetCurSel($cbo_RecFormat)
                If $iRecSel >= 0 And $iRecSel < UBound($g_aRadioRecFormats) Then $g_sRadioRecFormat = $g_aRadioRecFormats[$iRecSel]
                $iRecSel = _GUICtrlComboBox_GetCurSel($cbo_RecBitrate)
                If $iRecSel >= 0 And $iRecSel < UBound($g_aRadioRecBitrates) Then $g_iRadioRecBitrate = $g_aRadioRecBitrates[$iRecSel]
                $g_iRadioRecChannels = (_GUICtrlComboBox_GetCurSel($cbo_RecChannels) = 1) ? 1 : 2
                $iRecSel = _GUICtrlComboBox_GetCurSel($cbo_RecRate)
                If $iRecSel >= 0 And $iRecSel < UBound($g_aRadioRecRates) Then $g_iRadioRecRate = $g_aRadioRecRates[$iRecSel]
                $g_iRadioRecAutoStop = Int(GUICtrlRead($inp_RecAutoStop))
                If $g_iRadioRecAutoStop < 0 Then $g_iRadioRecAutoStop = 0
                If $g_iRadioRecAutoStop > 1440 Then $g_iRadioRecAutoStop = 1440
                If StringStripWS($sTempRecPath, 3) <> "" Then $g_sRadioRecPath = $sTempRecPath
                If Not FileExists($g_sRadioRecPath) Then DirCreate($g_sRadioRecPath)
                IniWrite($CONFIG_FILE, "Settings", "RadioRecPath", $g_sRadioRecPath)
                IniWrite($CONFIG_FILE, "Settings", "RadioRecFormat", $g_sRadioRecFormat)
                IniWrite($CONFIG_FILE, "Settings", "RadioRecBitrate", String($g_iRadioRecBitrate))
                IniWrite($CONFIG_FILE, "Settings", "RadioRecChannels", String($g_iRadioRecChannels))
                IniWrite($CONFIG_FILE, "Settings", "RadioRecSampleRate", String($g_iRadioRecRate))
                IniWrite($CONFIG_FILE, "Settings", "RadioRecAutoStop", String($g_iRadioRecAutoStop))
                $g_iRadioRecVolume = Int(GUICtrlRead($sld_RecVol))
                If $g_iRadioRecVolume < 0 Then $g_iRadioRecVolume = 0
                If $g_iRadioRecVolume > 100 Then $g_iRadioRecVolume = 100
                IniWrite($CONFIG_FILE, "Settings", "RadioRecVolume", String($g_iRadioRecVolume))
                _ResolveTypingSounds()
                _HK_CommitWork() ; luu phim tat tuy chinh va ap dung ngay cho cua so chinh
                ; Handle Auto-start in Registry
                Local $sRegKey = "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run"
                If $g_bAutoStart Then
                    ; Use @ScriptFullPath and ensure working directory by using a cmd trick or just trust FileChangeDir
                    RegWrite($sRegKey, "VDHMediaCenter", "REG_SZ", '"' & @ScriptFullPath & '"')
                Else
                    RegDelete($sRegKey, "VDHMediaCenter")
                EndIf

                HotKeySet("^{TAB}")
                HotKeySet("^+{TAB}")
                HotKeySet("{F1}")
                GUIDelete($g_hSettingsGui)
                If $bLangChanged Then
                    ; Ask in the CURRENT language. The new language is saved and applied only if the user says Yes.
                    _AppSoundPlay("sounds/restart.wav")
                    Local $iLangBox = MsgBox(4, _T("Restart Required"), _T("To change the display language the application needs to restart. Restart now?"))
                    If $iLangBox = 6 Then
                        $g_sLanguage = $sNewLang
                        IniWrite($CONFIG_FILE, "Settings", "Language", $g_sLanguage)
                        ShellExecute(@ScriptFullPath, "/restart")
                        Exit
                    EndIf
                EndIf
                If $bDeviceChanged Then
                    ; the Player and the Radio share one libvlc instance: recreate it with the new device, no restart needed
                    While $g_iPanSess > 0
                        _Pan_DropSession($g_iPanSess - 1)
                    WEnd
                    If _VLC_Reinit() Then
                        _Pan_Sync(True)
                        _ReportStatus(_T("Audio output device changed. The Player and the Radio now use the new device."))
                    Else
                        _AppSoundPlay("sounds/restart.wav")
                        Local $iMsgBox = MsgBox(4, _T("Restart Required"), _T("Audio output device changed. Do you want to restart the application now to apply the changes?"))
                        If $iMsgBox = 6 Then
                            ShellExecute(@ScriptFullPath, "/restart")
                            Exit
                        EndIf
                    EndIf
                EndIf
                Return
        EndSwitch
    WEnd
EndFunc

; Helper for ComboBox
Func _GUICtrlComboBox_SetCurSel($hWnd, $iIndex)
    Local $hCombo = IsHWnd($hWnd) ? $hWnd : GUICtrlGetHandle($hWnd)
    Return _SendMessage($hCombo, $CB_SETCURSEL, $iIndex, 0)
EndFunc

Func _GUICtrlComboBox_GetCurSel($hWnd)
    Local $hCombo = IsHWnd($hWnd) ? $hWnd : GUICtrlGetHandle($hWnd)
    Return _SendMessage($hCombo, $CB_GETCURSEL, 0, 0)
EndFunc

Func _ShowGoToTime()
    If Not $oVLC_Player Then Return
    Local $fDuration = (_VLC_Direct_GetLength() / 1000)
    If $fDuration <= 0 Then Return

    Local $hGoToTimeGui = GUICreate(_T("Go to Time"), 250, 150, -1, -1, BitOR($WS_CAPTION, $WS_SYSMENU), $WS_EX_TOPMOST, $hPlayGui)
    GUISetBkColor($COLOR_BLUE)

    GUICtrlCreateLabel(_T("Minutes:"), 10, 20, 80, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    GUICtrlSetFont(-1, 10, 800)
    Local $inpMin = GUICtrlCreateInput("", 100, 17, 100, 20, $ES_NUMBER)

    GUICtrlCreateLabel(_T("Seconds:"), 10, 50, 80, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    GUICtrlSetFont(-1, 10, 800)
    Local $inpSec = GUICtrlCreateInput("", 100, 47, 100, 20, $ES_NUMBER)

    Local $btnOK = GUICtrlCreateButton(_T("OK"), 40, 100, 80, 30)
    GUICtrlSetState(-1, $GUI_DEFBUTTON)
    Local $btnCancel = GUICtrlCreateButton(_T("Cancel"), 140, 100, 80, 30)

    Local $hDummyEscGoTo = GUICtrlCreateDummy()
    Local $aAccelGoTo[1][2] = [["{ESC}", $hDummyEscGoTo]]
    GUISetAccelerators($aAccelGoTo, $hGoToTimeGui)

    GUISetState(@SW_SHOW, $hGoToTimeGui)
    _AllowUIPI($hGoToTimeGui)
    _AllowUIPI($inpMin)
    _AllowUIPI($inpSec)

    ; Set initial values once
    Local $iCurPos = Int((_VLC_Direct_GetTime() / 1000))
    GUICtrlSetData($inpMin, Int($iCurPos / 60))
    GUICtrlSetData($inpSec, Mod($iCurPos, 60))

    ControlFocus($hGoToTimeGui, "", $inpMin)
    GUICtrlSendMsg($inpMin, 0x00B1, 0, -1) ; EM_SETSEL

    While 1
        Local $nMsg = GUIGetMsg()
        Switch $nMsg
            Case $GUI_EVENT_CLOSE, $btnCancel, $hDummyEscGoTo
                GUIDelete($hGoToTimeGui)
                Return
            Case $btnOK
                Local $iMin = Int(GUICtrlRead($inpMin))
                Local $iSec = Int(GUICtrlRead($inpSec))
                Local $iTarget = ($iMin * 60) + $iSec
                If $iTarget > $fDuration Then $iTarget = $fDuration
                _VLC_Direct_SetTime($iTarget * 1000)
                _ReportStatus(_TF("Jumped to {1} minutes {2} seconds", $iMin, $iSec))
                GUIDelete($hGoToTimeGui)
                Return
        EndSwitch
        Sleep(1)
    WEnd
EndFunc

Func _Settings_WM_ACTIVATE($hWnd, $iMsg, $iwParam, $ilParam)
    If $hWnd = $g_hSettingsGui Then
        Local $iActive = BitAND($iwParam, 0xFFFF) ; WA_ACTIVE or WA_CLICKACTIVE
        _Settings_ToggleHotKeys($iActive <> 0)
    EndIf
    Return $GUI_RUNDEFMSG
EndFunc

Func _Settings_ToggleHotKeys($bEnable)
    If $bEnable Then
        HotKeySet("^{TAB}", "_Settings_HotKey_Next")
        HotKeySet("^+{TAB}", "_Settings_HotKey_Prev")
        HotKeySet("{F1}", "_Settings_HotKey_F1")
    Else
        HotKeySet("^{TAB}")
        HotKeySet("^+{TAB}")
        HotKeySet("{F1}")
    EndIf
EndFunc

Func _Settings_HotKey_Next()
    If WinActive($g_hSettingsGui) Then
        GUICtrlSendToDummy($g_hSettingsDummyNext)
    EndIf
EndFunc

Func _Settings_HotKey_Prev()
    If WinActive($g_hSettingsGui) Then
        GUICtrlSendToDummy($g_hSettingsDummyPrev)
    EndIf
EndFunc

; Đăng ký mô tả (F1) cho một điều khiển trong Settings
Func _Settings_AddHelp($idCtrl, $sText)
    If $g_iSettingsHelpCount >= UBound($g_aSettingsHelp) Then Return
    Local $hCtrl = GUICtrlGetHandle($idCtrl)
    If Not $hCtrl Then Return
    $g_aSettingsHelp[$g_iSettingsHelpCount][0] = $hCtrl
    $g_aSettingsHelp[$g_iSettingsHelpCount][1] = _T($sText)
    $g_iSettingsHelpCount += 1
EndFunc

; F1 trong Settings: đọc mô tả của điều khiển đang được focus
Func _Settings_HotKey_F1()
    If Not WinActive($g_hSettingsGui) Then Return
    Local $aFocus = DllCall("user32.dll", "hwnd", "GetFocus")
    Local $hFocus = (IsArray($aFocus) ? $aFocus[0] : 0)
    Local $hParent = 0
    If $hFocus Then
        Local $aParent = DllCall("user32.dll", "hwnd", "GetParent", "hwnd", $hFocus)
        If IsArray($aParent) Then $hParent = $aParent[0]
    EndIf
    Local $sHelp = ""
    For $i = 0 To $g_iSettingsHelpCount - 1
        ; Combo box có ô soạn thảo bên trong nên so sánh cả điều khiển cha
        If $hFocus And ($g_aSettingsHelp[$i][0] = $hFocus Or $g_aSettingsHelp[$i][0] = $hParent) Then
            $sHelp = $g_aSettingsHelp[$i][1]
            ExitLoop
        EndIf
    Next
    If $sHelp = "" Then $sHelp = _T("No detailed help is available for this control.")
    _NVDA_Speak($sHelp)
EndFunc

Func _Downloader_WM_ACTIVATE($hWnd, $iMsg, $iwParam, $ilParam)
    If $hWnd = $g_hGuiDL Then
        Local $iActive = BitAND($iwParam, 0xFFFF)
        _Downloader_ToggleHotKeys($iActive <> 0)
    EndIf
    Return $GUI_RUNDEFMSG
EndFunc

Func _Downloader_ToggleHotKeys($bEnable)
    If $bEnable Then
        HotKeySet("^{TAB}", "_Downloader_HotKey_Next")
        HotKeySet("^+{TAB}", "_Downloader_HotKey_Prev")
    Else
        HotKeySet("^{TAB}")
        HotKeySet("^+{TAB}")
    EndIf
EndFunc

Func _Downloader_HotKey_Next()
    If WinActive($g_hGuiDL) Then
        GUICtrlSendToDummy($g_hDummyNextDL)
    EndIf
EndFunc

Func _Downloader_HotKey_Prev()
    If WinActive($g_hGuiDL) Then
        GUICtrlSendToDummy($g_hDummyPrevDL)
    EndIf
EndFunc

Func _ShowPlaylistVideos($sPlaylistID, $sPlaylistTitle)
    ; 1. Hiển thị hộp thoại Loading
    Local $hLoad = GUICreate(_T("Loading"), 300, 80, -1, -1, $WS_POPUP, BitOR($WS_EX_TOPMOST, $WS_EX_TOOLWINDOW))
    GUISetBkColor(0xFFFFFF)
    GUICtrlCreateLabel(_TF("Loading playlist: {1}...", $sPlaylistTitle), 10, 25, 280, 40, $SS_CENTER)
    GUISetState(@SW_SHOW, $hLoad)
    _AppPlaySoundW(@ScriptDir & "\sounds\loading.wav", 0x0009)

    ; 2. Tải danh sách video bằng yt-dlp - Đưa I: xuống cuối để đảm bảo T và D đã có trước khi Add
    Local $sParams = '--flat-playlist --print "T:%(title)s" --print "D:%(duration_string)s" --print "I:%(id)s" --no-warnings --encoding utf-8 -- "' & $sPlaylistID & '"'
    Local $sFullCmd = $YT_DLP_EXE & ' ' & $sParams
    Local $iPID = Run($sFullCmd, @ScriptDir, @SW_HIDE, $STDOUT_CHILD + $STDERR_CHILD)

    Local $bData = Binary("")
    Local $sErr = ""
    While ProcessExists($iPID)
        $bData &= StdoutRead($iPID, False, True)
        $sErr &= StderrRead($iPID)
        GUIGetMsg()
        Sleep(1)
    WEnd
    $bData &= StdoutRead($iPID, False, True)
    $sErr &= StderrRead($iPID)

    Local $sOutput = BinaryToString($bData, 4)
    DllCall("winmm.dll", "int", "PlaySoundW", "ptr", 0, "ptr", 0, "dword", 0)
    GUIDelete($hLoad)
    _AppSoundPlay(@ScriptDir & "\sounds\ok.wav")

    Local $aLines = StringSplit(StringStripCR($sOutput), @LF)
    If $aLines[0] <= 1 And $sOutput == "" Then
        Local $sShowErr = _T("Could not load videos from this playlist.")
        If $sErr <> "" Then $sShowErr &= " " & _TF("Details: {1}", StringLeft(StringStripWS($sErr, 3), 100))
        MsgBox(16, _T("Error"), $sShowErr)
        Return
    EndIf

    ; 3. Tạo GUI danh sách video
    Local $hPlGui = GUICreate(_TF("Playlist Videos: {1}", $sPlaylistTitle), 400, 460)
    GUISetBkColor($COLOR_BLUE)
    GUICtrlCreateLabel(_T("Videos in this playlist:"), 10, 10, 380, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    GUICtrlSetFont(-1, 10, 800)
    Local $lst_pl = GUICtrlCreateList("", 10, 35, 380, 355, BitOR($LBS_NOTIFY, $WS_VSCROLL, $WS_BORDER))
    Local $btn_back = GUICtrlCreateButton(_T("Close Playlist"), 10, 400, 380, 30)

    Local $aPlIds[1], $aPlTitles[1], $aPlTypes[1]
    Local $sCurrentT = "", $sCurrentI = "", $sCurrentD = ""
    Local $iPlCount = 0

    For $i = 1 To $aLines[0]
        Local $sLine = StringStripWS($aLines[$i], 3)
        If $sLine == "" Then ContinueLoop

        If StringLeft($sLine, 2) = "T:" Then
            $sCurrentT = StringTrimLeft($sLine, 2)
        ElseIf StringLeft($sLine, 2) = "I:" Then
            $sCurrentI = StringTrimLeft($sLine, 2)
        ElseIf StringLeft($sLine, 2) = "D:" Then
            $sCurrentD = StringTrimLeft($sLine, 2)
        EndIf

        ; Trigger khi có ID (vì ID in cuối cùng)
        If $sCurrentI <> "" Then
            $iPlCount += 1
            Local $sDisp = $iPlCount & ". " & ($sCurrentT <> "" And $sCurrentT <> "NA" ? $sCurrentT : _T("Unknown Title"))
            If $sCurrentD <> "" And $sCurrentD <> "NA" Then $sDisp &= " [" & $sCurrentD & "]"
            _GUICtrlListBox_AddString($lst_pl, $sDisp)

            ReDim $aPlIds[$iPlCount + 1]
            ReDim $aPlTitles[$iPlCount + 1]
            ReDim $aPlTypes[$iPlCount + 1]

            $aPlIds[$iPlCount] = $sCurrentI
            $aPlTitles[$iPlCount] = $sCurrentT
            $aPlTypes[$iPlCount] = "video"

        EndIf
    Next

    If $iPlCount == 0 Then
        MsgBox(16, _T("Error"), _T("No videos found in this playlist."))
        GUIDelete($hPlGui)
        Return
    EndIf

    _GUICtrlListBox_SetCurSel($lst_pl, 0)
    GUISetState(@SW_SHOW, $hPlGui)
    ControlFocus($hPlGui, "", $lst_pl)

    Local $hDummyEnterPl = GUICtrlCreateDummy()
    Local $hDummyAudioPl = GUICtrlCreateDummy()
    Local $aAccelPl[2][2] = [["{ENTER}", $hDummyEnterPl], ["^{ENTER}", $hDummyAudioPl]]
    GUISetAccelerators($aAccelPl, $hPlGui)
    Local $bEnterAccPl = True

    While 1
        _SyncEnterAccel($hPlGui, $aAccelPl, $lst_pl, $bEnterAccPl)
        Local $nMsg = GUIGetMsg()
        If $nMsg = $hDummyEnterPl Then
            Local $aBtnPl[1] = [$btn_back]
            Local $iBtnPl = _EnterFocusedButton($hPlGui, $aBtnPl)
            If $iBtnPl <> 0 Then $nMsg = $iBtnPl
        EndIf
        Switch $nMsg
            Case $GUI_EVENT_CLOSE, $btn_back
                GUIDelete($hPlGui)
                Return
            Case $hDummyEnterPl, $hDummyAudioPl
                Local $iIndex = _GUICtrlListBox_GetCurSel($lst_pl)
                If $iIndex <> -1 Then
                    Local $bAudio = ($nMsg = $hDummyAudioPl)

                    ; Tạm thời copy các mảng kết quả tìm kiếm để _PlayLoop hoạt động
                    Local $aSavedIds = $aSearchIds
                    Local $aSavedTitles = $aSearchTitles
                    Local $aSavedTypes = $aSearchTypes
                    Local $iSavedTotal = $iTotalLoaded

                    $aSearchIds = $aPlIds
                    $aSearchTitles = $aPlTitles
                    $aSearchTypes = $aPlTypes
                    $iTotalLoaded = $iPlCount

                    _PlayLoop($iIndex, $bAudio)

                    ; Khôi phục lại mảng tìm kiếm gốc
                    $aSearchIds = $aSavedIds
                    $aSearchTitles = $aSavedTitles
                    $aSearchTypes = $aSavedTypes
                    $iTotalLoaded = $iSavedTotal
                EndIf
        EndSwitch
    WEnd
EndFunc

; $iMax > 0: only the latest $iMax videos are listed (used when a subscription is opened)
Func _ShowChannelVideos($sChannelID, $sChannelTitle, $iMax = 0)
    ; 1. Hiển thị hộp thoại Loading video
    Local $hLoad = GUICreate(_T("Loading"), 300, 80, -1, -1, $WS_POPUP, BitOR($WS_EX_TOPMOST, $WS_EX_TOOLWINDOW))
    GUISetBkColor(0xFFFFFF)
    GUICtrlCreateLabel(_TF("Loading all videos from: {1}...", $sChannelTitle), 10, 25, 280, 40, $SS_CENTER)
    GUISetState(@SW_SHOW, $hLoad)
    _AppPlaySoundW(@ScriptDir & "\sounds\loading.wav", 0x0009)

    ; 2. Tải danh sách video bằng yt-dlp từ tab videos của channel
    Local $sUrl = _YTS_ChannelUrl($sChannelID)
    Local $sLimit = ""
    If $iMax > 0 Then $sLimit = ' --playlist-end ' & $iMax

    Local $sParams = '--flat-playlist' & $sLimit & ' --print "T:%(title)s" --print "D:%(duration_string)s" --print "I:%(id)s" --no-warnings --encoding utf-8 -- "' & $sUrl & '"'
    Local $sFullCmd = $YT_DLP_EXE & ' ' & $sParams
    Local $iPID = Run($sFullCmd, @ScriptDir, @SW_HIDE, $STDOUT_CHILD + $STDERR_CHILD)

    Local $bData = Binary("")
    Local $sErr = ""
    While ProcessExists($iPID)
        $bData &= StdoutRead($iPID, False, True)
        $sErr &= StderrRead($iPID)
        GUIGetMsg()
        Sleep(1)
    WEnd
    $bData &= StdoutRead($iPID, False, True)
    $sErr &= StderrRead($iPID)

    Local $sOutput = BinaryToString($bData, 4)
    DllCall("winmm.dll", "int", "PlaySoundW", "ptr", 0, "ptr", 0, "dword", 0)
    GUIDelete($hLoad)
    _AppSoundPlay(@ScriptDir & "\sounds\ok.wav")

    Local $aLines = StringSplit(StringStripCR($sOutput), @LF)
    If $aLines[0] <= 1 And $sOutput == "" Then
        MsgBox(16, _T("Error"), _T("Could not load videos from this channel."))
        Return
    EndIf

    ; 3. Tạo GUI danh sách video
    Local $hChGui = GUICreate(_TF("Channel Videos: {1}", $sChannelTitle), 400, 460)
    GUISetBkColor($COLOR_BLUE)
    GUICtrlCreateLabel(_T("Videos from this channel:"), 10, 10, 380, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    GUICtrlSetFont(-1, 10, 800)
    Local $lst_ch = GUICtrlCreateList("", 10, 35, 380, 355, BitOR($LBS_NOTIFY, $WS_VSCROLL, $WS_BORDER))
    Local $bSub = _YTS_IsSubscribed($sChannelID)
    Local $btn_sub = GUICtrlCreateButton(_T($bSub ? "Un&subscribe (Ctrl+D)" : "&Subscribe (Ctrl+D)"), 10, 400, 185, 30)
    Local $btn_back = GUICtrlCreateButton(_T("Close"), 205, 400, 185, 30)

    Local $aChIds[1], $aChTitles[1], $aChTypes[1], $aChDisp[1]
    Local $sCurrentT = "", $sCurrentI = "", $sCurrentD = ""
    Local $iChCount = 0

    For $i = 1 To $aLines[0]
        Local $sLine = StringStripWS($aLines[$i], 3)
        If $sLine == "" Then ContinueLoop

        If StringLeft($sLine, 2) = "T:" Then
            $sCurrentT = StringTrimLeft($sLine, 2)
        ElseIf StringLeft($sLine, 2) = "I:" Then
            $sCurrentI = StringTrimLeft($sLine, 2)
        ElseIf StringLeft($sLine, 2) = "D:" Then
            $sCurrentD = StringTrimLeft($sLine, 2)
        EndIf

        If $sCurrentI <> "" Then
            $iChCount += 1
            Local $sDisp = $iChCount & ". " & ($sCurrentT <> "" And $sCurrentT <> "NA" ? $sCurrentT : _T("Unknown Title"))
            If $sCurrentD <> "" And $sCurrentD <> "NA" Then $sDisp &= " [" & $sCurrentD & "]"
            _GUICtrlListBox_AddString($lst_ch, $sDisp)

            ReDim $aChIds[$iChCount + 1]
            ReDim $aChTitles[$iChCount + 1]
            ReDim $aChTypes[$iChCount + 1]
            ReDim $aChDisp[$iChCount + 1]

            $aChDisp[$iChCount] = $sDisp
            $aChIds[$iChCount] = $sCurrentI
            $aChTitles[$iChCount] = $sCurrentT
            $aChTypes[$iChCount] = "video"
            $sCurrentI = "" ; Reset for next entry
        EndIf
    Next

    If $iChCount == 0 Then
        MsgBox(16, _T("Error"), _T("No videos found in this channel."))
        GUIDelete($hChGui)
        Return
    EndIf

    ; Subscribed channel: the videos published since the last visit are marked "New", then they count as seen
    If $bSub Then
        Local $sSeenCh = _YTS_GetSeen($sChannelID), $iNewCh = 0
        If $sSeenCh <> "" Then
            $iNewCh = $iChCount
            For $i = 1 To $iChCount
                If $aChIds[$i] = $sSeenCh Then
                    $iNewCh = $i - 1
                    ExitLoop
                EndIf
            Next
        EndIf
        If $iNewCh > 0 Then
            _GUICtrlListBox_ResetContent($lst_ch)
            For $i = 1 To $iChCount
                If $i <= $iNewCh Then
                    _GUICtrlListBox_AddString($lst_ch, StringReplace($aChDisp[$i], $i & ". ", $i & ". " & _T("New") & ": ", 1))
                Else
                    _GUICtrlListBox_AddString($lst_ch, $aChDisp[$i])
                EndIf
            Next
        EndIf
        _YTS_SetSeen($sChannelID, $aChIds[1])
        _Sub_SetNew("yt", $sChannelID, 0)
    EndIf

    _GUICtrlListBox_SetCurSel($lst_ch, 0)
    GUISetState(@SW_SHOW, $hChGui)
    ControlFocus($hChGui, "", $lst_ch)

    Local $hDummyEnterCh = GUICtrlCreateDummy()
    Local $hDummyAudioCh = GUICtrlCreateDummy()
    Local $aAccelCh[3][2] = [["{ENTER}", $hDummyEnterCh], ["^{ENTER}", $hDummyAudioCh], ["^d", $btn_sub]]
    GUISetAccelerators($aAccelCh, $hChGui)
    Local $bEnterAccCh = True

    While 1
        _SyncEnterAccel($hChGui, $aAccelCh, $lst_ch, $bEnterAccCh)
        Local $nMsg = GUIGetMsg()
        If $nMsg = $hDummyEnterCh Then
            Local $aBtnCh[2] = [$btn_back, $btn_sub]
            Local $iBtnCh = _EnterFocusedButton($hChGui, $aBtnCh)
            If $iBtnCh <> 0 Then $nMsg = $iBtnCh
        EndIf
        Switch $nMsg
            Case $GUI_EVENT_CLOSE, $btn_back
                GUIDelete($hChGui)
                Return
            Case $btn_sub
                If $bSub Then
                    If _YTS_Unsubscribe($sChannelID) Then
                        $bSub = False
                        GUICtrlSetData($btn_sub, _T("&Subscribe (Ctrl+D)"))
                        _AppSoundPlay(@ScriptDir & "\sounds\ok.wav")
                        _ReportStatus(_TF("Unsubscribed from {1}", $sChannelTitle))
                    EndIf
                ElseIf _YTS_Subscribe($sChannelID, $sChannelTitle, $aChIds[1]) >= 0 Then
                    $bSub = True
                    GUICtrlSetData($btn_sub, _T("Un&subscribe (Ctrl+D)"))
                    _AppSoundPlay(@ScriptDir & "\sounds\ok.wav")
                    _ReportStatus(_TF("Subscribed to {1}", $sChannelTitle))
                Else
                    _ReportStatus(_T("Could not save the subscription"))
                EndIf
            Case $hDummyEnterCh, $hDummyAudioCh
                Local $iIndex = _GUICtrlListBox_GetCurSel($lst_ch)
                If $iIndex <> -1 Then
                    Local $bAudio = ($nMsg = $hDummyAudioCh)
                    Local $aSavedIds = $aSearchIds
                    Local $aSavedTitles = $aSearchTitles
                    Local $aSavedTypes = $aSearchTypes
                    Local $iSavedTotal = $iTotalLoaded

                    $aSearchIds = $aChIds
                    $aSearchTitles = $aChTitles
                    $aSearchTypes = $aChTypes
                    $iTotalLoaded = $iChCount

                    _PlayLoop($iIndex, $bAudio)

                    $aSearchIds = $aSavedIds
                    $aSearchTitles = $aSavedTitles
                    $aSearchTypes = $aSavedTypes
                    $iTotalLoaded = $iSavedTotal
                EndIf
        EndSwitch
    WEnd
EndFunc

Func _ShowCollections()
    Local $hColGui = GUICreate(_T("Your Collections"), 400, 530)
    GUISetBkColor($COLOR_BLUE)

    GUICtrlCreateLabel(_T("Your Collections:"), 10, 10, 380, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    GUICtrlSetFont(-1, 10, 800)

    Local $lst_col = GUICtrlCreateList("", 10, 35, 380, 350, BitOR($LBS_NOTIFY, $WS_VSCROLL, $WS_BORDER))

    Local $btn_create = GUICtrlCreateButton(_T("&Create New Collection"), 10, 395, 185, 35)
    Local $btn_rename = GUICtrlCreateButton(_T("&Rename"), 205, 395, 185, 35)
    Local $btn_delete = GUICtrlCreateButton(_T("&Delete"), 10, 440, 185, 35)
    Local $btn_download = GUICtrlCreateButton(_T("&Download Collection"), 205, 440, 185, 35)
    Local $btn_shuffle = GUICtrlCreateButton(_T("&Play Shuffle"), 10, 485, 185, 35)
    Local $btn_close = GUICtrlCreateButton(_T("&Close"), 205, 485, 185, 35)

    GUISetState(@SW_SHOW, $hColGui)
    _LoadCollectionsList($lst_col)
    ControlFocus($hColGui, "", $lst_col)

    Local $hDummyEnterCol = GUICtrlCreateDummy()
    Local $hDummyEscCol = GUICtrlCreateDummy()
    Local $aAccelCol[2][2] = [["{ENTER}", $hDummyEnterCol], ["{ESC}", $hDummyEscCol]]
    GUISetAccelerators($aAccelCol, $hColGui)

    While 1
        Local $nMsg = _GuiMsg($hColGui)

        ; Handle Enter key for buttons
        If $nMsg = $hDummyEnterCol Then
            Local $hFocus = ControlGetHandle($hColGui, "", ControlGetFocus($hColGui))
            Switch $hFocus
                Case GUICtrlGetHandle($btn_create)
                    $nMsg = $btn_create
                Case GUICtrlGetHandle($btn_rename)
                    $nMsg = $btn_rename
                Case GUICtrlGetHandle($btn_delete)
                    $nMsg = $btn_delete
                Case GUICtrlGetHandle($btn_download)
                    $nMsg = $btn_download
                Case GUICtrlGetHandle($btn_shuffle)
                    $nMsg = $btn_shuffle
                Case GUICtrlGetHandle($btn_close)
                    $nMsg = $btn_close
                Case GUICtrlGetHandle($lst_col)
                    ; Standard Enter on list behavior handled in main Switch below
                Case Else
                    ContinueLoop
            EndSwitch
        EndIf

        Switch $nMsg
            Case $GUI_EVENT_CLOSE, $btn_close, $hDummyEscCol
                GUIDelete($hColGui)
                GUISetState(@SW_SHOW, $mainform)
                Return

            Case $btn_create
                Local $sName = InputBox(_T("New Collection"), _T("Enter name for the new collection:"), "", "", 300, 130, -1, -1, 0, $hColGui)
                If Not @error And $sName <> "" Then
                    Local $sFile = $COLLECTIONS_DIR & "\" & $sName & ".col"
                    If FileExists($sFile) Then
                        MsgBox(48, _T("Warning"), _T("A collection with this name already exists."))
                    Else
                        Local $hFile = FileOpen($sFile, 2 + 256)
                        FileClose($hFile)
                        _LoadCollectionsList($lst_col, $sName)
                        _NVDA_Speak(_TF("Collection {1} created", $sName))
                    EndIf
                EndIf

            Case $btn_rename
                Local $iSel = _GUICtrlListBox_GetCurSel($lst_col)
                If $iSel = -1 Then
                    MsgBox(48, _T("Warning"), _T("Please select a collection from the list to rename."))
                    ContinueLoop
                EndIf
                Local $sOldNameWithCount = _GUICtrlListBox_GetText($lst_col, $iSel)
                Local $sOldName = StringRegExpReplace($sOldNameWithCount, " \(\d+ videos?\)$", "")
                Local $sNewName = InputBox(_T("Rename Collection"), _TF("Enter new name for '{1}':", $sOldName), $sOldName, "", 300, 130, -1, -1, 0, $hColGui)
                If Not @error And $sNewName <> "" And $sNewName <> $sOldName Then
                    If FileMove($COLLECTIONS_DIR & "\" & $sOldName & ".col", $COLLECTIONS_DIR & "\" & $sNewName & ".col", 1) Then
                        _LoadCollectionsList($lst_col, $sNewName)
                        _NVDA_Speak(_TF("Collection renamed to {1}", $sNewName))
                    Else
                        MsgBox(16, _T("Error"), _T("Could not rename collection. Ensure the name is valid."))
                    EndIf
                EndIf

            Case $btn_delete
                Local $iSel = _GUICtrlListBox_GetCurSel($lst_col)
                If $iSel = -1 Then
                    MsgBox(48, _T("Warning"), _T("Please select a collection from the list to delete."))
                    ContinueLoop
                EndIf
                Local $sNameWithCount = _GUICtrlListBox_GetText($lst_col, $iSel)
                Local $sName = StringRegExpReplace($sNameWithCount, " \(\d+ videos?\)$", "")
                If MsgBox(36, _T("Confirm Delete"), _TF("Are you sure you want to delete the collection '{1}'?", $sName)) = 6 Then
                    FileDelete($COLLECTIONS_DIR & "\" & $sName & ".col")
                    _LoadCollectionsList($lst_col)
                    _NVDA_Speak(_TF("Collection {1} deleted", $sName))
                EndIf

            Case $btn_download
                Local $iSel = _GUICtrlListBox_GetCurSel($lst_col)
                If $iSel = -1 Then
                    MsgBox(48, _T("Warning"), _T("Please select a collection from the list to download."))
                    ContinueLoop
                EndIf
                Local $sNameWithCount = _GUICtrlListBox_GetText($lst_col, $iSel)
                Local $sName = StringRegExpReplace($sNameWithCount, " \(\d+ videos?\)$", "")
                _DownloadCollection($sName)

            Case $btn_shuffle
                Local $iSel = _GUICtrlListBox_GetCurSel($lst_col)
                If $iSel = -1 Then
                    MsgBox(48, _T("Warning"), _T("Please select a collection from the list to shuffle."))
                    ContinueLoop
                EndIf
                Local $sNameWithCount = _GUICtrlListBox_GetText($lst_col, $iSel)
                Local $sName = StringRegExpReplace($sNameWithCount, " \(\d+ videos?\)$", "")
                _PlayShuffleCollection($sName)

            Case $hDummyEnterCol
                ; Standard Enter on list behavior
                Local $iSel = _GUICtrlListBox_GetCurSel($lst_col)
                If $iSel = -1 Then
                    MsgBox(48, _T("Warning"), _T("Please select a collection from the list to open."))
                Else
                    Local $sNameWithCount = _GUICtrlListBox_GetText($lst_col, $iSel)
                    Local $sName = StringRegExpReplace($sNameWithCount, " \(\d+ videos?\)$", "")
                    _ShowCollectionItems($sName)
                    _LoadCollectionsList($lst_col, $sName) ; Refresh list and restore selection
                    ControlFocus($hColGui, "", $lst_col)
                EndIf
        EndSwitch
    WEnd
EndFunc

Func _GetCollectionCount($sName)
    Local $sFile = $COLLECTIONS_DIR & "\" & $sName & ".col"
    Local $hFile = FileOpen($sFile, 0 + 256)
    If $hFile = -1 Then Return 0
    ; Doc ca file 1 lan roi dem dong co dau "|" (nhanh hon doc tung dong)
    Local $sContent = FileRead($hFile)
    FileClose($hFile)
    If $sContent = "" Then Return 0
    Local $aLines = StringSplit(StringStripCR($sContent), @LF, 2)
    Local $iCount = 0
    For $i = 0 To UBound($aLines) - 1
        If StringInStr($aLines[$i], "|") Then $iCount += 1
    Next
    Return $iCount
EndFunc

Func _LoadCollectionsList($hList, $sSelectName = "")
    _GUICtrlListBox_BeginUpdate($hList)
    _GUICtrlListBox_ResetContent($hList)
    Local $hSearch = FileFindFirstFile($COLLECTIONS_DIR & "\*.col")
    Local $iSelectIndex = 0
    If $hSearch <> -1 Then
        Local $iCountIdx = 0
        While 1
            Local $sFile = FileFindNextFile($hSearch)
            If @error Then ExitLoop
            Local $sName = StringReplace($sFile, ".col", "")
            Local $iCount = _GetCollectionCount($sName)
            Local $sUnit = ($iCount <= 1 ? "video" : "videos")
            Local $sDisplayName = $sName & " (" & $iCount & " " & $sUnit & ")"
            _GUICtrlListBox_AddString($hList, $sDisplayName)
            If $sSelectName <> "" And $sName = $sSelectName Then
                $iSelectIndex = $iCountIdx
            EndIf
            $iCountIdx += 1
        WEnd
        FileClose($hSearch)
    EndIf
    _GUICtrlListBox_SetCurSel($hList, $iSelectIndex)
    _GUICtrlListBox_EndUpdate($hList)
EndFunc

Func _ShowCollectionItems($sColName)
    Local $sFile = $COLLECTIONS_DIR & "\" & $sColName & ".col"
    Local $hColItemsGui = GUICreate(_TF("Collection: {1}", $sColName), 400, 480)
    GUISetBkColor($COLOR_BLUE)

    GUICtrlCreateLabel(_T("Videos in this collection:"), 10, 10, 380, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    GUICtrlSetFont(-1, 10, 800)
    Local $lst_items = GUICtrlCreateList("", 10, 35, 380, 355, BitOR($LBS_NOTIFY, $WS_VSCROLL, $WS_BORDER))
    Local $btn_back = GUICtrlCreateButton(_T("&Go Back"), 10, 400, 380, 35)

    GUISetState(@SW_SHOW, $hColItemsGui)

    Local $aColIds[1], $aColTitles[1]
    _LoadCollectionItems($sFile, $lst_items, $aColIds, $aColTitles)
    ControlFocus($hColItemsGui, "", $lst_items)

    Local $hDummyEnter = GUICtrlCreateDummy()
    Local $hDummyAudio = GUICtrlCreateDummy()
    Local $hDummyApps = GUICtrlCreateDummy()
    Local $hDummyEscItems = GUICtrlCreateDummy()
    Local $aAccel[5][2] = [["{ENTER}", $hDummyEnter], ["^{ENTER}", $hDummyAudio], ["{APPSKEY}", $hDummyApps], ["+{F10}", $hDummyApps], ["{ESC}", $hDummyEscItems]]
    GUISetAccelerators($aAccel, $hColItemsGui)
    Local $bEnterAccCI = True

    While 1
        _SyncEnterAccel($hColItemsGui, $aAccel, $lst_items, $bEnterAccCI)
        Local $nMsg = GUIGetMsg()
        If $nMsg = $hDummyEnter Then
            Local $aBtnCI[1] = [$btn_back]
            Local $iBtnCI = _EnterFocusedButton($hColItemsGui, $aBtnCI)
            If $iBtnCI <> 0 Then $nMsg = $iBtnCI
        EndIf
        Switch $nMsg
            Case $GUI_EVENT_CLOSE, $btn_back, $hDummyEscItems
                GUIDelete($hColItemsGui)
                Return

            Case $hDummyEnter, $hDummyAudio
                Local $iSel = _GUICtrlListBox_GetCurSel($lst_items)
                If $iSel <> -1 Then
                    Local $bAudio = ($nMsg = $hDummyAudio)
                    Local $aSavedIds = $aSearchIds
                    Local $aSavedTitles = $aSearchTitles
                    Local $iSavedTotal = $iTotalLoaded

                    $aSearchIds = $aColIds
                    $aSearchTitles = $aColTitles
                    $iTotalLoaded = UBound($aColIds) - 1

                    _PlayLoop($iSel, $bAudio)

                    $aSearchIds = $aSavedIds
                    $aSearchTitles = $aSavedTitles
                    $iTotalLoaded = $iSavedTotal
                EndIf

            Case $hDummyApps
                If ControlGetHandle($hColItemsGui, "", ControlGetFocus($hColItemsGui)) = GUICtrlGetHandle($lst_items) Then
                    _ShowCollectionItemContextMenu($sFile, $hColItemsGui, $lst_items, $aColIds, $aColTitles)
                EndIf
        EndSwitch
    WEnd
EndFunc

Func _ShowCollectionItemContextMenu($sColFile, $hParent, $hList, ByRef $aIds, ByRef $aTitles)
    Local $iSel = _GUICtrlListBox_GetCurSel($hList)
    If $iSel = -1 Then Return

    Local $sID = $aIds[$iSel + 1]
    Local $sTitle = $aTitles[$iSel + 1]

    Local $hMenu = _GUICtrlMenu_CreatePopup()

    _GUICtrlMenu_AddMenuItem($hMenu, _T("&Play..."), 1001)
    _GUICtrlMenu_AddMenuItem($hMenu, _T("Play as &audio..."), 1002)
    _GUICtrlMenu_AddMenuItem($hMenu, _T("&Download..."), 1003)
    _GUICtrlMenu_AddMenuItem($hMenu, _T("Go to &channel..."), 1004)
    _GUICtrlMenu_AddMenuItem($hMenu, _T("Open in &Browser..."), 1005)
    _GUICtrlMenu_AddMenuItem($hMenu, _T("Copy Lin&k..."), 1006)
    _GUICtrlMenu_AddMenuItem($hMenu, _T("View &Lyrics..."), 1009)
    _GUICtrlMenu_AddMenuItem($hMenu, _T("Add to &queue..."), 1013)
    _GUICtrlMenu_AddMenuItem($hMenu, _T("Add to do&wnload queue..."), 1015)

    _GUICtrlMenu_AddMenuItem($hMenu, _T("&Remove from Collection"), 2001)

    Local $hSubMenu_Share = _GUICtrlMenu_CreatePopup()
    _GUICtrlMenu_AddMenuItem($hSubMenu_Share, _T("&Telegram"), 1011)
    _GUICtrlMenu_AddMenuItem($hSubMenu_Share, _T("&Facebook"), 1012)
    _GUICtrlMenu_AddMenuItem($hMenu, _T("&Share"), -1, $hSubMenu_Share)

    Local $bIsAlreadyFav = _IsFavorite($sID)
    _GUICtrlMenu_AddMenuItem($hMenu, _Ternary($bIsAlreadyFav, _T("Remove from Favorite..."), _T("Add to &Favorite...")), 1007)

    Local $iCmd = _GUICtrlMenu_TrackPopupMenu($hMenu, $hParent, MouseGetPos(0), MouseGetPos(1), 1, 1, 2)
    _GUICtrlMenu_DestroyMenu($hMenu)

    If $iCmd <= 0 Then Return

    ; Temp swap globals for actions
    Local $aSavedIds = $aSearchIds
    Local $aSavedTitles = $aSearchTitles
    Local $iSavedTotal = $iTotalLoaded
    $aSearchIds = $aIds
    $aSearchTitles = $aTitles
    $iTotalLoaded = UBound($aIds) - 1

    Switch $iCmd
        Case 1001
            _PlayLoop($iSel, False)
        Case 1002
            _PlayLoop($iSel, True)
        Case 1003
            _ShowDownloadDialog($sID, $sTitle, $hParent)
        Case 1004
            _Action_GoChannel($iSel)
        Case 1005
            _Action_OpenBrowser($iSel)
        Case 1006
            _Action_CopyLink($iSel, $hParent)
        Case 1009
            _ShowSongLyrics($sTitle, $hParent, $sID)
        Case 1013
            If _Queue_Add($sID, $sTitle) Then
                MsgBox(64, _T("Success"), _TF("Added to the play queue successfully! Position: {1}", $g_iQueueCount), 0, $hParent)
            EndIf
        Case 1015
            _DQ_AddNotify($sID, $sTitle, $hParent)
        Case 1007
            If $bIsAlreadyFav Then
                If _RemoveFavorite($sID) Then MsgBox(64, _T("Success"), _T("Removed from favorites successfully!"))
            Else
                _AddFavorite($sID, $sTitle)
            EndIf
        Case 1011 ; Telegram
            _ShowShareLinkDialog("telegram", $sID, $sTitle, $hParent)
        Case 1012 ; Facebook
            _ShowShareLinkDialog("facebook", $sID, $sTitle, $hParent)
        Case 2001 ; Remove from THIS collection
            _RemoveFromCollection($sColFile, $sID)
            _LoadCollectionItems($sColFile, $hList, $aIds, $aTitles)
            _GUICtrlListBox_SetCurSel($hList, $iSel)
    EndSwitch

    $aSearchIds = $aSavedIds
    $aSearchTitles = $aSavedTitles
    $iTotalLoaded = $iSavedTotal
EndFunc

Func _LoadCollectionItems($sFile, $hList, ByRef $aIds, ByRef $aTitles)
    GUICtrlSetData($hList, "")
    Dim $aIds[1]
    Dim $aTitles[1]
    $aIds[0] = 0
    $aTitles[0] = 0
    Local $hFile = FileOpen($sFile, 0 + 256)
    If $hFile = -1 Then Return
    Local $iCount = 0
    While 1
        Local $sLine = FileReadLine($hFile)
        If @error = -1 Then ExitLoop
        Local $aParts = StringSplit($sLine, "|")
        If $aParts[0] >= 2 Then
            $iCount += 1
            ReDim $aIds[$iCount + 1]
            ReDim $aTitles[$iCount + 1]
            $aIds[$iCount] = $aParts[1]
            $aTitles[$iCount] = $aParts[2]
            _GUICtrlListBox_AddString($hList, $iCount & ". " & $aParts[2])
        EndIf
    WEnd
    FileClose($hFile)
    If $iCount > 0 Then
        _GUICtrlListBox_SetCurSel($hList, 0)
    Else
        _GUICtrlListBox_AddString($hList, _T("(Collection is empty)"))
        _GUICtrlListBox_SetCurSel($hList, 0)
    EndIf
EndFunc

Func _RemoveFromCollection($sFile, $sID)
    Local $hFileRead = FileOpen($sFile, 0 + 256)
    Local $sContent = FileRead($hFileRead)
    FileClose($hFileRead)
    Local $aLines = StringSplit(StringStripCR($sContent), @LF)
    Local $sNewContent = ""
    For $i = 1 To $aLines[0]
        If $aLines[$i] = "" Then ContinueLoop
        Local $aParts = StringSplit($aLines[$i], "|")
        If $aParts[0] >= 1 And $aParts[1] = $sID Then ContinueLoop
        $sNewContent &= $aLines[$i] & @CRLF
    Next
    Local $hFileWrite = FileOpen($sFile, 2 + 256)
    If $hFileWrite <> -1 Then
        FileWrite($hFileWrite, $sNewContent)
        FileClose($hFileWrite)
    EndIf
EndFunc

Func _DownloadCollection($sColName)
    Local $sFile = $COLLECTIONS_DIR & "\" & $sColName & ".col"
    Local $hFile = FileOpen($sFile, 0 + 256)
    If $hFile = -1 Then Return

    Local $aLinks = [0]
    While 1
        Local $sLine = FileReadLine($hFile)
        If @error = -1 Then ExitLoop
        Local $aParts = StringSplit($sLine, "|")
        If $aParts[0] >= 1 Then
            _ArrayAdd($aLinks, _VideoLink($aParts[1]))
        EndIf
    WEnd
    FileClose($hFile)

    If UBound($aLinks) <= 1 Then
        MsgBox(48, _T("Info"), _T("Collection is empty."))
        Return
    EndIf

    ; --- Show Format Selection Dialog ---
    Local $hDLGui = GUICreate(_TF("Download Collection: {1}", $sColName), 400, 160, -1, -1, BitOR($WS_CAPTION, $WS_SYSMENU), $WS_EX_TOPMOST)
    GUISetBkColor($COLOR_BLUE)

    GUICtrlCreateLabel(_T("Select Format for entire collection:"), 10, 20, 380, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $cboFormat = GUICtrlCreateCombo("", 10, 45, 180, 20, $CBS_DROPDOWNLIST)
    GUICtrlSetTip(-1, _T("Select the download format. Use the arrow keys to browse the list in alphabetical order"))
    GUICtrlSetData(-1, _TL("M4A (Audio)|MP3 (Audio)|MP4 (Video, Best)|OGG (Audio)|WAV (Audio)|WebM (Video)"), _T("MP4 (Video, Best)"))

    GUICtrlCreateLabel(_T("Select Bitrate:"), 210, 20, 180, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $cboBitrate = GUICtrlCreateCombo("", 210, 45, 180, 20, $CBS_DROPDOWNLIST)
    GUICtrlSetTip(-1, _T("Select the bitrate (kbps). Use the arrow keys to browse from low to high"))
    GUICtrlSetData(-1, _TL("128 kbps|192 kbps|256 kbps|320 kbps"), _T("320 kbps"))

    Local $btn_Start = GUICtrlCreateButton(_T("Start Download"), 10, 100, 255, 40)
    GUICtrlSetState(-1, $GUI_DEFBUTTON)
    Local $btn_Cancel = GUICtrlCreateButton(_T("Cancel"), 275, 100, 115, 40)

    GUISetState(@SW_SHOW, $hDLGui)

    Local $sSelectedFmt = ""
    Local $sSelectedBitrate = ""
    Local $bProceed = False

    While 1
        Local $nMsg = GUIGetMsg()
        If $nMsg = $GUI_EVENT_CLOSE Or $nMsg = $btn_Cancel Then
            GUIDelete($hDLGui)
            Return
        ElseIf $nMsg = $btn_Start Then
            $sSelectedFmt = _TR(GUICtrlRead($cboFormat))
            $sSelectedBitrate = GUICtrlRead($cboBitrate)
            $bProceed = True
            GUIDelete($hDLGui)
            ExitLoop
        EndIf
    WEnd

    If Not $bProceed Then Return

    Local $sFmt = ""
    If StringInStr($sSelectedFmt, "MP3") Then
        $sFmt = "-x --audio-format mp3"
    ElseIf StringInStr($sSelectedFmt, "WAV") Then
        $sFmt = "-x --audio-format wav"
    ElseIf StringInStr($sSelectedFmt, "M4A") Then
        $sFmt = "-x --audio-format m4a"
    ElseIf StringInStr($sSelectedFmt, "OGG") Then
        $sFmt = "-x --audio-format vorbis"
    ElseIf StringInStr($sSelectedFmt, "WebM") Then
        $sFmt = "bestvideo+bestaudio --merge-output-format webm"
    Else
        $sFmt = "-f bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best"
    EndIf

    Local $iKbps = StringRegExpReplace($sSelectedBitrate, "[^0-9]", "")
    If $iKbps <> "" And (StringInStr($sSelectedFmt, "Audio") Or StringInStr($sSelectedFmt, "MP3") Or StringInStr($sSelectedFmt, "WAV") Or StringInStr($sSelectedFmt, "M4A") Or StringInStr($sSelectedFmt, "OGG")) Then
        $sFmt &= " --audio-quality " & $iKbps & "k"
    EndIf

    Local $sFinalDownloadPath = $g_sDownloadPath
    If StringStripWS($sFinalDownloadPath, 3) = "" Then $sFinalDownloadPath = @ScriptDir & "\download"
    If Not FileExists($sFinalDownloadPath) Then DirCreate($sFinalDownloadPath)
    While StringRight($sFinalDownloadPath, 1) = "\" Or StringRight($sFinalDownloadPath, 1) = "/"
        $sFinalDownloadPath = StringTrimRight($sFinalDownloadPath, 1)
    WEnd

    Local $iTotalItems = UBound($aLinks) - 1
    Local $hProgGui = GUICreate(_TF("Downloading Collection: {1}", $sColName), 400, 140, -1, -1, BitOR($WS_CAPTION, $WS_SYSMENU), $WS_EX_TOPMOST)
    GUISetBkColor($COLOR_BLUE)
    Local $lbl_coll_item = GUICtrlCreateLabel("", 10, 15, 380, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $lbl_coll_status = GUICtrlCreateLabel("", 10, 45, 380, 16)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $prog_coll = GUICtrlCreateProgress(10, 65, 380, 20)
    GUISetState(@SW_SHOW, $hProgGui)

    Local $sCollSnapshot = _ListFilesRecursive($sFinalDownloadPath)
    For $i = 1 To $iTotalItems
        _NVDA_Speak(_TF("Downloading item {1} of {2}", $i, $iTotalItems))
        GUICtrlSetData($lbl_coll_item, _TF("Downloading item {1} / {2}", $i, $iTotalItems))
        Local $sCmd = $YT_DLP_EXE & ' --newline ' & $sFmt & ' -P "' & $sFinalDownloadPath & '" --ffmpeg-location "' & @ScriptDir & '\lib" -o "%(title)s.%(ext)s" -- "' & $aLinks[$i] & '"'
        Local $bCollDone = _RunDownloadWithProgress($sCmd, $prog_coll, $lbl_coll_status, $sFinalDownloadPath)
        If Not $bCollDone Then
            GUIDelete($hProgGui)
            Return
        EndIf
    Next
    GUIDelete($hProgGui)
_DLSound_Stop()
_AppSoundPlay(@ScriptDir & "\sounds\download_finish.wav")
    _ShowDownloadCompleteDialog($sFinalDownloadPath, _GetNewDownloadedFiles($sFinalDownloadPath, $sCollSnapshot), _T("Success"), _T("Collection download complete!"))
EndFunc

Func _AddtoCollection($sID, $sTitle)
    Local $hSelectCol = GUICreate(_T("Select Collection"), 300, 350, -1, -1, BitOR($WS_CAPTION, $WS_POPUP, $WS_SYSMENU))
    GUISetBkColor($COLOR_BLUE)
    GUICtrlCreateLabel(_T("Choose a collection:"), 10, 10, 280, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    GUICtrlSetFont(-1, 10, 800)
    Local $lst = GUICtrlCreateList("", 10, 35, 280, 255, BitOR($LBS_NOTIFY, $WS_VSCROLL, $WS_BORDER))
    Local $btn_add = GUICtrlCreateButton(_T("&Add to Collection"), 10, 300, 280, 35)

    _LoadCollectionsList($lst)
    GUISetState(@SW_SHOW, $hSelectCol)
    ControlFocus($hSelectCol, "", $lst)

    Local $hDummyEnterAdd = GUICtrlCreateDummy()
    Local $hDummyEscAdd = GUICtrlCreateDummy()
    Local $aAccelAdd[2][2] = [["{ENTER}", $hDummyEnterAdd], ["{ESC}", $hDummyEscAdd]]
    GUISetAccelerators($aAccelAdd, $hSelectCol)

    While 1
        Local $nMsg = GUIGetMsg()
        If $nMsg = $GUI_EVENT_CLOSE Or $nMsg = $hDummyEscAdd Then
            GUIDelete($hSelectCol)
            Return
        ElseIf $nMsg = $btn_add Or $nMsg = $hDummyEnterAdd Then
            Local $iSel = _GUICtrlListBox_GetCurSel($lst)
            If $iSel <> -1 Then
                Local $sColNameWithCount = _GUICtrlListBox_GetText($lst, $iSel)
                Local $sColName = StringRegExpReplace($sColNameWithCount, " \(\d+ videos?\)$", "")
                Local $sFile = $COLLECTIONS_DIR & "\" & $sColName & ".col"
                Local $hFileRead = FileOpen($sFile, 0 + 256)
                Local $sContent = FileRead($hFileRead)
                FileClose($hFileRead)

                If StringInStr($sContent, $sID & "|") Then
                    MsgBox(48, _T("Info"), _T("This video is already in the collection."))
                Else
                    Local $hFileWrite = FileOpen($sFile, 1 + 256)
                    If $hFileWrite <> -1 Then
                        FileWriteLine($hFileWrite, $sID & "|" & $sTitle)
                        FileClose($hFileWrite)
                        _NVDA_Speak(_TF("Added to collection {1}", $sColName))
                        MsgBox(64, _T("Success"), _T("Added to collection successfully!"))
                    Else
                        MsgBox(16, _T("Error"), _T("Could not open collection file for writing."))
                    EndIf
                EndIf
                GUIDelete($hSelectCol)
                Return
            EndIf
        EndIf
    WEnd
EndFunc

Func _Ternary($bCondition, $vTrue, $vFalse)
    If $bCondition Then Return $vTrue
    Return $vFalse
EndFunc

Func _IsVideoInAnyCollection($sID)
    Local $hSearch = FileFindFirstFile($COLLECTIONS_DIR & "\*.col")
    If $hSearch = -1 Then Return False
    While 1
        Local $sFile = FileFindNextFile($hSearch)
        If @error Then ExitLoop
        Local $hFile = FileOpen($COLLECTIONS_DIR & "\" & $sFile, 0 + 256)
        Local $sContent = FileRead($hFile)
        FileClose($hFile)
        If StringInStr($sContent, $sID & "|") Then
            FileClose($hSearch)
            Return True
        EndIf
    WEnd
    FileClose($hSearch)
    Return False
EndFunc

Func _RemoveFromAllCollectionsDialog($sID)
    Local $aFoundCols[1] = [0]
    Local $hSearch = FileFindFirstFile($COLLECTIONS_DIR & "\*.col")
    If $hSearch <> -1 Then
        While 1
            Local $sFile = FileFindNextFile($hSearch)
            If @error Then ExitLoop
            Local $hFileRead = FileOpen($COLLECTIONS_DIR & "\" & $sFile, 0 + 256)
            Local $sContent = FileRead($hFileRead)
            FileClose($hFileRead)
            If StringInStr($sContent, $sID & "|") Then
                _ArrayAdd($aFoundCols, StringReplace($sFile, ".col", ""))
            EndIf
        WEnd
        FileClose($hSearch)
    EndIf

    If UBound($aFoundCols) <= 1 Then
        MsgBox(64, _T("Info"), _T("This video is not in any collection."))
        Return
    EndIf

    Local $hRemGui = GUICreate(_T("Remove From Collection"), 300, 350, -1, -1, BitOR($WS_CAPTION, $WS_SYSMENU), $WS_EX_TOPMOST)
    GUISetBkColor($COLOR_BLUE)
    GUICtrlCreateLabel(_T("Remove from collection:"), 10, 10, 280, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    GUICtrlSetFont(-1, 10, 800)
    Local $lst = GUICtrlCreateList("", 10, 35, 280, 255, BitOR($LBS_NOTIFY, $WS_VSCROLL, $WS_BORDER))
    For $i = 1 To UBound($aFoundCols) - 1
        _GUICtrlListBox_AddString($lst, $aFoundCols[$i])
    Next
    _GUICtrlListBox_SetCurSel($lst, 0)
    Local $btn_rem = GUICtrlCreateButton(_T("Remove"), 10, 300, 280, 35)
    GUISetState(@SW_SHOW, $hRemGui)

    While 1
        Local $msg = GUIGetMsg()
        If $msg = $GUI_EVENT_CLOSE Then
            GUIDelete($hRemGui)
            Return
        ElseIf $msg = $btn_rem Then
            Local $iSel = _GUICtrlListBox_GetCurSel($lst)
            If $iSel <> -1 Then
                Local $sName = _GUICtrlListBox_GetText($lst, $iSel)
                _RemoveFromCollection($COLLECTIONS_DIR & "\" & $sName & ".col", $sID)
                _NVDA_Speak(_TF("Removed from collection {1}", $sName))
                MsgBox(64, _T("Success"), _T("Removed from collection successfully!"))
                GUIDelete($hRemGui)
                Return
            EndIf
        EndIf
    WEnd
EndFunc

Func _PlayShuffleCollection($sColName)
    Local $sFile = $COLLECTIONS_DIR & "\" & $sColName & ".col"
    Local $aIds[1], $aTitles[1]
    Local $hFile = FileOpen($sFile, 0 + 256)
    If $hFile = -1 Then Return
    Local $iCount = 0
    While 1
        Local $sLine = FileReadLine($hFile)
        If @error = -1 Then ExitLoop
        Local $aParts = StringSplit($sLine, "|")
        If $aParts[0] >= 2 Then
            $iCount += 1
            ReDim $aIds[$iCount + 1]
            ReDim $aTitles[$iCount + 1]
            $aIds[$iCount] = $aParts[1]
            $aTitles[$iCount] = $aParts[2]
        EndIf
    WEnd
    FileClose($hFile)

    If $iCount < 2 Then
        MsgBox(48, _T("Warning"), _T("Collection must have at least 2 videos to shuffle."))
        Return
    EndIf

    ; Shuffle
    Local $aIndex[1]
    _ArrayAdd($aIndex, 0) ; Not used
    For $i = 1 To $iCount
        _ArrayAdd($aIndex, $i)
    Next
    _ArrayDelete($aIndex, 0)
    _ArrayShuffle($aIndex)

    Local $aShuffledIds[1], $aShuffledTitles[1]
    ReDim $aShuffledIds[$iCount + 1]
    ReDim $aShuffledTitles[$iCount + 1]
    For $i = 0 To $iCount - 1
        $aShuffledIds[$i + 1] = $aIds[$aIndex[$i]]
        $aShuffledTitles[$i + 1] = $aTitles[$aIndex[$i]]
    Next

    Local $aSavedIds = $aSearchIds
    Local $aSavedTitles = $aSearchTitles
    Local $iSavedTotal = $iTotalLoaded

    $aSearchIds = $aShuffledIds
    $aSearchTitles = $aShuffledTitles
    $iTotalLoaded = $iCount

    _PlayLoop(0)

    $aSearchIds = $aSavedIds
    $aSearchTitles = $aSavedTitles
    $iTotalLoaded = $iSavedTotal
EndFunc

Func _ShowCollectionContextMenu_Shuffle($hParent, $hList)
    Local $iSel = _GUICtrlListBox_GetCurSel($hList)
    If $iSel = -1 Then Return

    Local $sNameWithCount = _GUICtrlListBox_GetText($hList, $iSel)
    Local $sName = StringRegExpReplace($sNameWithCount, " \(\d+ videos?\)$", "")
    Local $iCount = _GetCollectionCount($sName)

    Local $hMenu = _GUICtrlMenu_CreatePopup()
    _GUICtrlMenu_AddMenuItem($hMenu, _T("Play shuffle"), 3001)

    If $iCount < 2 Then
        _GUICtrlMenu_EnableMenuItem($hMenu, 3001, 1) ; Disable if less than 2
    EndIf

    Local $iCmd = _GUICtrlMenu_TrackPopupMenu($hMenu, $hParent, MouseGetPos(0), MouseGetPos(1), 1, 1, 2)
    _GUICtrlMenu_DestroyMenu($hMenu)

    If $iCmd = 3001 Then
        _PlayShuffleCollection($sName)
    EndIf
EndFunc

; --- Helper functions for Continue Watching feature ---
Func _SavePlaybackPosition($sID, $iMS)
    If $sID = "" Then Return
    IniWrite($PLAYBACK_POSITIONS_FILE, "Positions", $sID, String($iMS))
EndFunc

Func _GetPlaybackPosition($sID)
If $sID = "" Then Return 0
    Return Int(IniRead($PLAYBACK_POSITIONS_FILE, "Positions", $sID, "0"))
EndFunc

; Fixes UIPI isolation issues for windows
Func _AllowUIPI($hWnd)
    If Not IsHWnd($hWnd) Then Return False
    Local $aResult = DllCall("user32.dll", "bool", "ChangeWindowMessageFilterEx", "hwnd", $hWnd, "uint", 0x0049, "dword", 1, "ptr", 0) ; WM_COPYGLOBALDATA
    $aResult = DllCall("user32.dll", "bool", "ChangeWindowMessageFilterEx", "hwnd", $hWnd, "uint", 0x0233, "dword", 1, "ptr", 0) ; WM_DROPFILES
    $aResult = DllCall("user32.dll", "bool", "ChangeWindowMessageFilterEx", "hwnd", $hWnd, "uint", 0x004A, "dword", 1, "ptr", 0) ; WM_COPYDATA
    Return True
EndFunc


; ======================================================================
;  FILE HELPERS, RECENT FILES / FOLDERS, RESUME THEO TUNG FILE NGHE
; ======================================================================
Func _RF_Read($sFile)
    Local $aEmpty[0]
    If Not FileExists($sFile) Then Return $aEmpty
    Local $h = FileOpen($sFile, 256)
    If $h = -1 Then Return $aEmpty
    Local $s = FileRead($h)
    FileClose($h)
    Local $a = StringSplit(StringStripCR($s), @LF, 2)
    Local $aOut[UBound($a)], $n = 0
    For $i = 0 To UBound($a) - 1
        If StringStripWS($a[$i], 3) = "" Then ContinueLoop
        $aOut[$n] = $a[$i]
        $n += 1
    Next
    ReDim $aOut[$n]
    Return $aOut
EndFunc

Func _RF_Write($sFile, $aLines, $iStart = 0)
    Local $s = ""
    For $i = $iStart To UBound($aLines) - 1
        $s &= $aLines[$i] & @CRLF
    Next
    Local $h = FileOpen($sFile, 2 + 8 + 256)
    If $h = -1 Then Return False
    FileWrite($h, $s)
    FileClose($h)
    Return True
EndFunc

Func _Recent_Key($sLine)
    Local $i = StringInStr($sLine, "|")
    If $i > 0 Then $sLine = StringLeft($sLine, $i - 1)
    Return StringLower($sLine)
EndFunc

; Dua mot muc len dau danh sach (bo muc trung), toi da $RECENT_MAX muc
Func _Recent_Push($sFile, $sEntry)
    Local $a = _RF_Read($sFile)
    Local $sKey = _Recent_Key($sEntry)
    Local $aNew[UBound($a) + 1], $n = 0
    $aNew[$n] = $sEntry
    $n += 1
    For $i = 0 To UBound($a) - 1
        If _Recent_Key($a[$i]) = $sKey Then ContinueLoop
        If $n >= $RECENT_MAX Then ExitLoop
        $aNew[$n] = $a[$i]
        $n += 1
    Next
    ReDim $aNew[$n]
    _RF_Write($sFile, $aNew)
EndFunc

Func _Recent_AddFile($sFile)
    If $sFile = "" Then Return
    _Recent_Push($RECENT_FILES_FILE, $sFile)
EndFunc

Func _Recent_FolderLast($sFolder)
    Local $a = _RF_Read($RECENT_FOLDERS_FILE)
    Local $sK = StringLower($sFolder)
    For $i = 0 To UBound($a) - 1
        If _Recent_Key($a[$i]) = $sK Then
            Local $iP = StringInStr($a[$i], "|")
            Return ($iP > 0) ? StringMid($a[$i], $iP + 1) : ""
        EndIf
    Next
    Return ""
EndFunc

; $sLast = bai dang nghe trong thu muc (de lan sau mo lai nghe tiep dung bai do)
Func _Recent_AddFolder($sFolder, $sLast = "")
    If $sFolder = "" Then Return
    If $sLast = "" Then $sLast = _Recent_FolderLast($sFolder)
    _Recent_Push($RECENT_FOLDERS_FILE, $sFolder & "|" & $sLast)
EndFunc

Func _Recent_RemoveAt($sFile, $iIndex)
    Local $a = _RF_Read($sFile)
    If $iIndex < 0 Or $iIndex >= UBound($a) Then Return
    Local $aNew[UBound($a)], $n = 0
    For $i = 0 To UBound($a) - 1
        If $i = $iIndex Then ContinueLoop
        $aNew[$n] = $a[$i]
        $n += 1
    Next
    ReDim $aNew[$n]
    _RF_Write($sFile, $aNew)
EndFunc

; Mot lan duy nhat: chuyen cac bai nghe cuc bo cu trong Watch History sang Recent Files
Func _Recent_MigrateHistory()
    If IniRead($CONFIG_FILE, "Settings", "RecentMigrated", "0") = "1" Then Return
    IniWrite($CONFIG_FILE, "Settings", "RecentMigrated", "1")
    If Not FileExists($HISTORY_FILE) Then Return
    Local $a = _RF_Read($HISTORY_FILE)
    Local $aKeep[UBound($a) + 1], $nKeep = 0
    Local $aFiles[UBound($a) + 1], $nF = 0
    Local $aP
    For $i = 0 To UBound($a) - 1
        $aP = StringSplit($a[$i], "|")
        If $aP[0] >= 3 And $aP[3] = "local_audio" Then
            $aFiles[$nF] = $aP[1]
            $nF += 1
        Else
            $aKeep[$nKeep] = $a[$i]
            $nKeep += 1
        EndIf
    Next
    If $nF = 0 Then Return
    ReDim $aKeep[$nKeep]
    _RF_Write($HISTORY_FILE, $aKeep)
    For $i = 0 To $nF - 1
        If FileExists($aFiles[$i]) Then _Recent_Push($RECENT_FILES_FILE, $aFiles[$i])
    Next
EndFunc

; ---------- Resume theo tung file ----------
Func _LocalPos_Get($sPath)
    If $sPath = "" Then Return 0
    Local $a = _RF_Read($LOCAL_POSITIONS_FILE)
    Local $sK = StringLower($sPath)
    Local $p, $iMs, $iLen
    For $i = UBound($a) - 1 To 0 Step -1
        $p = StringSplit($a[$i], "|", 2)
        If UBound($p) >= 2 And StringLower($p[0]) = $sK Then
            $iMs = Int($p[1])
            $iLen = (UBound($p) >= 3) ? Int($p[2]) : 0
            If $iMs < 3000 Then Return 0
            If $iLen > 0 And $iMs > $iLen - 5000 Then Return 0
            Return $iMs
        EndIf
    Next
    Return 0
EndFunc

Func _LocalPos_Write($sPath, $iMs, $iLen, $bRemoveOnly)
    Local $a = _RF_Read($LOCAL_POSITIONS_FILE)
    Local $sK = StringLower($sPath)
    Local $aOut[UBound($a) + 1], $n = 0, $iBar
    For $i = 0 To UBound($a) - 1
        $iBar = StringInStr($a[$i], "|")
        If $iBar > 0 And StringLower(StringLeft($a[$i], $iBar - 1)) = $sK Then ContinueLoop
        $aOut[$n] = $a[$i]
        $n += 1
    Next
    If Not $bRemoveOnly Then
        $aOut[$n] = $sPath & "|" & Int($iMs) & "|" & Int($iLen)
        $n += 1
    EndIf
    ReDim $aOut[$n]
    Local $iStart = ($n > 500) ? $n - 500 : 0
    _RF_Write($LOCAL_POSITIONS_FILE, $aOut, $iStart)
EndFunc

Func _LocalPos_Save($sPath, $iMs, $iLen)
    If $sPath = "" Or $iMs < 0 Then Return
    _LocalPos_Write($sPath, $iMs, $iLen, False)
EndFunc

Func _LocalPos_Clear($sPath)
    If $sPath = "" Then Return
    _LocalPos_Write($sPath, 0, 0, True)
EndFunc

; ---------- Cua so Recent Files / Recent Folders ----------
Func _ShowRecentFiles()
    _ShowRecentList(False)
EndFunc

Func _ShowRecentFolders()
    _ShowRecentList(True)
EndFunc

Func _Recent_Display($sEntry, $bFolder)
    Local $sPath = $sEntry, $sLast = ""
    If $bFolder Then
        Local $iBar = StringInStr($sEntry, "|")
        If $iBar > 0 Then
            $sPath = StringLeft($sEntry, $iBar - 1)
            $sLast = StringMid($sEntry, $iBar + 1)
        EndIf
    EndIf
    Local $sName = StringRegExpReplace($sPath, "^.*[\\/]", "")
    If $sName = "" Then $sName = $sPath
    Local $sDir = StringRegExpReplace($sPath, "[\\/][^\\/]*$", "")
    Local $sOut = $sName
    If $bFolder Then
        $sOut &= " (" & $sPath & ")"
        If $sLast <> "" Then
            Local $sLastName = StringRegExpReplace(StringRegExpReplace($sLast, "^.*[\\/]", ""), "\.[A-Za-z0-9]+$", "")
            $sOut &= " - " & _TF("Last played: {1}", $sLastName)
        EndIf
    ElseIf $sDir <> $sPath Then
        $sOut &= " (" & $sDir & ")"
    EndIf
    Return StringReplace($sOut, "|", "/")
EndFunc

Func _Recent_Fill($idList, $sFile, $bFolders)
    Local $a = _RF_Read($sFile)
    Local $s = ""
    For $i = 0 To UBound($a) - 1
        $s &= ($i + 1) & ". " & _Recent_Display($a[$i], $bFolders) & "|"
    Next
    GUICtrlSetData($idList, "")
    If $s <> "" Then GUICtrlSetData($idList, StringTrimRight($s, 1))
    Return $a
EndFunc

; Tra ve False neu muc khong con ton tai
Func _Recent_Play($sEntry, $bFolder)
    If $bFolder Then
        Local $iBar = StringInStr($sEntry, "|")
        Local $sFolder = ($iBar > 0) ? StringLeft($sEntry, $iBar - 1) : $sEntry
        Local $sLast = ($iBar > 0) ? StringMid($sEntry, $iBar + 1) : ""
        If Not FileExists($sFolder) Then
            MsgBox(48, _T("Error"), _T("This folder no longer exists."))
            Return False
        EndIf
        _OpenAudioFolder($sFolder, $sLast)
    Else
        If Not FileExists($sEntry) Then
            MsgBox(48, _T("Error"), _T("This file no longer exists."))
            Return False
        EndIf
        _PlayLocalAudioFile($sEntry)
    EndIf
    Return True
EndFunc

Func _ShowRecentList($bFolders)
    Local $sFile = $bFolders ? $RECENT_FOLDERS_FILE : $RECENT_FILES_FILE
    Local $aProbe = _RF_Read($sFile)
    If UBound($aProbe) = 0 Then
        MsgBox(64, _T("Info"), $bFolders ? _T("No recent folders yet.") : _T("No recent files yet."))
        Return
    EndIf

    Local $hGui = GUICreate($bFolders ? _T("Recent Folders") : _T("Recent Files"), 440, 440)
    GUISetBkColor($COLOR_BLUE)
    GUICtrlCreateLabel($bFolders ? _T("Your recent folders (press Enter to play):") : _T("Your recent files (press Enter to play):"), 10, 10, 420, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    GUICtrlSetFont(-1, 10, 800)
    Local $lst = GUICtrlCreateList("", 10, 35, 420, 280, BitOR($LBS_NOTIFY, $WS_VSCROLL, $WS_BORDER))
    Local $btnPlay = GUICtrlCreateButton(_T("Play"), 10, 325, 205, 30)
    Local $btnRemove = GUICtrlCreateButton(_T("Remove selected"), 225, 325, 205, 30)
    Local $btnClear = GUICtrlCreateButton(_T("Clear all"), 10, 365, 205, 30)
    Local $btnClose = GUICtrlCreateButton(_T("Close"), 225, 365, 205, 30)

    Local $hDummyEnter = GUICtrlCreateDummy()
    Local $hDummyDel = GUICtrlCreateDummy()
    Local $hDummyEsc = GUICtrlCreateDummy()
    Local $aAccel[3][2] = [["{ENTER}", $hDummyEnter], ["{DEL}", $hDummyDel], ["{ESC}", $hDummyEsc]]
    GUISetAccelerators($aAccel, $hGui)
    Local $bEnterOn = True

    GUISetState(@SW_SHOW, $hGui)
    _AllowUIPI($hGui)
    Local $aItems = _Recent_Fill($lst, $sFile, $bFolders)
    _GUICtrlListBox_SetCurSel($lst, 0)
    ControlFocus($hGui, "", $lst)

    Local $aBtns[4] = [$btnPlay, $btnRemove, $btnClear, $btnClose]
    Local $nMsg, $iSel, $bListFocus
    While 1
        _SyncEnterAccel($hGui, $aAccel, $lst, $bEnterOn)
        $nMsg = _GuiMsg($hGui)
        $bListFocus = (ControlGetHandle($hGui, "", ControlGetFocus($hGui)) = GUICtrlGetHandle($lst))
        If $nMsg = $hDummyEnter Then
            If $bListFocus Then
                $nMsg = $btnPlay
            Else
                Local $iPressed = _EnterFocusedButton($hGui, $aBtns)
                If $iPressed <> 0 Then $nMsg = $iPressed
            EndIf
        ElseIf $nMsg = $hDummyDel Then
            If $bListFocus Then $nMsg = $btnRemove
        EndIf

        Switch $nMsg
            Case $GUI_EVENT_CLOSE, $btnClose, $hDummyEsc
                GUIDelete($hGui)
                Return

            Case $btnPlay
                $iSel = _GUICtrlListBox_GetCurSel($lst)
                If $iSel >= 0 And $iSel < UBound($aItems) Then
                    If Not _Recent_Play($aItems[$iSel], $bFolders) Then _Recent_RemoveAt($sFile, $iSel)
                    GUISwitch($hGui)
                    $aItems = _Recent_Fill($lst, $sFile, $bFolders)
                    If UBound($aItems) = 0 Then
                        GUIDelete($hGui)
                        Return
                    EndIf
                    _GUICtrlListBox_SetCurSel($lst, 0)
                    ControlFocus($hGui, "", $lst)
                EndIf

            Case $btnRemove
                $iSel = _GUICtrlListBox_GetCurSel($lst)
                If $iSel >= 0 And $iSel < UBound($aItems) Then
                    _Recent_RemoveAt($sFile, $iSel)
                    $aItems = _Recent_Fill($lst, $sFile, $bFolders)
                    If UBound($aItems) = 0 Then
                        GUIDelete($hGui)
                        Return
                    EndIf
                    If $iSel >= UBound($aItems) Then $iSel = UBound($aItems) - 1
                    _GUICtrlListBox_SetCurSel($lst, $iSel)
                    ControlFocus($hGui, "", $lst)
                EndIf

            Case $btnClear
                If MsgBox(36, _T("Confirm"), $bFolders ? _T("Are you sure you want to clear all recent folders?") : _T("Are you sure you want to clear all recent files?")) = 6 Then
                    FileDelete($sFile)
                    GUIDelete($hGui)
                    Return
                EndIf
        EndSwitch
        Sleep(10)
    WEnd
EndFunc

; ======================================================================
;  EQUALIZER TUY CHINH (preamp + 10 bang tan), dung chung cho Radio Player va Player
; ======================================================================
Func _EQ_LoadCustom()
    Local $a = StringSplit(IniRead($CONFIG_FILE, "Settings", "EqualizerCustom", ""), "|", 2)
    If UBound($a) = 11 Then
        $g_fEqPreamp = Number($a[0])
        For $i = 0 To 9
            $g_aEqBands[$i] = Number($a[$i + 1])
        Next
    EndIf
EndFunc

Func _EQ_SaveCustom()
    Local $s = String($g_fEqPreamp)
    For $i = 0 To 9
        $s &= "|" & $g_aEqBands[$i]
    Next
    IniWrite($CONFIG_FILE, "Settings", "EqualizerCustom", $s)
    IniWrite($CONFIG_FILE, "Settings", "EqualizerPreset", String($g_iEqPreset))
EndFunc

; Doc cac gia tri cua mot preset co san cua libvlc vao $g_fEqPreamp / $g_aEqBands (de thanh truot hien dung)
Func _EQ_LoadPreset($iPreset)
    If Not _VLC_Direct_Init() Then Return False
    Local $aEq = DllCall($hVLC_Dll, "ptr:cdecl", "libvlc_audio_equalizer_new_from_preset", "uint", $iPreset)
    If @error Or Not IsArray($aEq) Or Not $aEq[0] Then Return False
    Local $p = $aEq[0]
    Local $aPre = DllCall($hVLC_Dll, "float:cdecl", "libvlc_audio_equalizer_get_preamp", "ptr", $p)
    If Not @error And IsArray($aPre) Then $g_fEqPreamp = Round($aPre[0], 1)
    Local $aAmp
    For $b = 0 To 9
        $aAmp = DllCall($hVLC_Dll, "float:cdecl", "libvlc_audio_equalizer_get_amp_at_index", "ptr", $p, "uint", $b)
        If Not @error And IsArray($aAmp) Then $g_aEqBands[$b] = Round($aAmp[0], 1)
    Next
    DllCall($hVLC_Dll, "none:cdecl", "libvlc_audio_equalizer_release", "ptr", $p)
    Return True
EndFunc

Func _EQ_BandLabel($b)
    Local $aFallback[10] = [60, 170, 310, 600, 1000, 3000, 6000, 12000, 14000, 16000]
    Local $fHz = $aFallback[$b]
    If $hVLC_Dll <> -1 Then
        Local $aF = DllCall($hVLC_Dll, "float:cdecl", "libvlc_audio_equalizer_get_band_frequency", "uint", $b)
        If Not @error And IsArray($aF) And $aF[0] > 0 Then $fHz = $aF[0]
    EndIf
    If $fHz >= 1000 Then Return StringReplace(String(Round($fHz / 1000, 1)), ".0", "") & " kHz"
    Return Round($fHz) & " Hz"
EndFunc

Func _EQ_ValText($fVal)
    Return ($fVal > 0 ? "+" : "") & Round($fVal, 1) & " dB"
EndFunc

Func _ShowEqualizerDialog($hParent = 0)
    If Not _VLC_Direct_Init() Then Return
    Local $iOldPreset = $g_iEqPreset, $fOldPre = $g_fEqPreamp
    Local $aOldBands = $g_aEqBands
    If $g_iEqPreset >= 0 Then _EQ_LoadPreset($g_iEqPreset) ; sliders show the preset's curve

    Local $hGui = GUICreate(_T("Equalizer"), 450, 560, -1, -1, BitOR($WS_CAPTION, $WS_SYSMENU, $WS_POPUP), -1, IsHWnd($hParent) ? $hParent : 0)
    GUISetBkColor($COLOR_BLUE)
    GUICtrlCreateLabel(_T("Preset:"), 10, 14, 90, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $cboPreset = GUICtrlCreateCombo("", 105, 10, 335, 20, $CBS_DROPDOWNLIST)
    GUICtrlSetData(-1, _TL("Off|" & _EQ_PresetNames() & "|Custom"))
    Local $iCustomIdx = 19
    _GUICtrlComboBox_SetCurSel($cboPreset, ($g_iEqPreset = -2) ? $iCustomIdx : $g_iEqPreset + 1)

    ; slider 0 = preamp, 1..10 = bands
    Local $aLbl[11], $aSld[11], $aVal[11], $aLast[11]
    For $k = 0 To 10
        Local $iY = 50 + $k * 36
        GUICtrlCreateLabel(($k = 0) ? _T("Preamp") : _EQ_BandLabel($k - 1), 10, $iY + 4, 90, 20)
        GUICtrlSetColor(-1, 0xFFFFFF)
        $aSld[$k] = GUICtrlCreateSlider(105, $iY, 260, 30, BitOR(0x0001, $WS_TABSTOP))
        GUICtrlSetLimit($aSld[$k], 20, -20)
        GUICtrlSendMsg($aSld[$k], 0x0417, 0, 1) ; TBM_SETLINESIZE
        GUICtrlSendMsg($aSld[$k], 0x0415, 0, 5) ; TBM_SETPAGESIZE
        Local $fV = ($k = 0) ? $g_fEqPreamp : $g_aEqBands[$k - 1]
        GUICtrlSetData($aSld[$k], Round($fV))
        $aLast[$k] = Round($fV)
        $aVal[$k] = GUICtrlCreateLabel(_EQ_ValText($aLast[$k]), 372, $iY + 4, 70, 20)
        GUICtrlSetColor(-1, 0xFFFF00)
    Next

    Local $btnReset = GUICtrlCreateButton(_T("Reset (flat)"), 10, 455, 140, 32)
    Local $btnOK = GUICtrlCreateButton(_T("OK"), 160, 455, 135, 32)
    Local $btnCancel = GUICtrlCreateButton(_T("Cancel"), 305, 455, 135, 32)
    GUICtrlCreateLabel(_T("Use the Left and Right arrow keys on a slider to change it by 1 dB, Page Up and Page Down by 5 dB."), 10, 495, 430, 40)
    GUICtrlSetColor(-1, 0xFFFFFF)

    Local $hDummyEsc = GUICtrlCreateDummy()
    Local $aAccel[1][2] = [["{ESC}", $hDummyEsc]]
    GUISetAccelerators($aAccel, $hGui)
    GUISetState(@SW_SHOW, $hGui)
    _AllowUIPI($hGui)
    ControlFocus($hGui, "", $cboPreset)

    Local $nMsg, $iSel, $iNow, $bChanged
    While 1
        $nMsg = _GuiMsg($hGui)
        Switch $nMsg
            Case $GUI_EVENT_CLOSE, $btnCancel, $hDummyEsc
                $g_iEqPreset = $iOldPreset
                $g_fEqPreamp = $fOldPre
                $g_aEqBands = $aOldBands
                _VLC_ApplyEqualizer()
                GUIDelete($hGui)
                Return False

            Case $btnOK
                _EQ_SaveCustom()
                GUIDelete($hGui)
                Return True

            Case $btnReset
                For $k = 0 To 10
                    GUICtrlSetData($aSld[$k], 0)
                    $aLast[$k] = 0
                    GUICtrlSetData($aVal[$k], _EQ_ValText(0))
                Next
                $g_fEqPreamp = 0
                For $b = 0 To 9
                    $g_aEqBands[$b] = 0
                Next
                $g_iEqPreset = -2
                _GUICtrlComboBox_SetCurSel($cboPreset, $iCustomIdx)
                _VLC_ApplyEqualizer()
                _NVDA_Speak(_T("Equalizer reset"))

            Case $cboPreset
                $iSel = _GUICtrlComboBox_GetCurSel($cboPreset)
                If $iSel = 0 Then
                    $g_iEqPreset = -1
                ElseIf $iSel = $iCustomIdx Then
                    $g_iEqPreset = -2
                Else
                    $g_iEqPreset = $iSel - 1
                    _EQ_LoadPreset($g_iEqPreset)
                    For $k = 0 To 10
                        Local $fPV = ($k = 0) ? $g_fEqPreamp : $g_aEqBands[$k - 1]
                        GUICtrlSetData($aSld[$k], Round($fPV))
                        $aLast[$k] = Round($fPV)
                        GUICtrlSetData($aVal[$k], _EQ_ValText($fPV))
                    Next
                EndIf
                _VLC_ApplyEqualizer()
        EndSwitch

        ; sliders: apply while the user moves them
        $bChanged = False
        For $k = 0 To 10
            $iNow = GUICtrlRead($aSld[$k])
            If $iNow <> $aLast[$k] Then
                $aLast[$k] = $iNow
                If $k = 0 Then
                    $g_fEqPreamp = $iNow
                Else
                    $g_aEqBands[$k - 1] = $iNow
                EndIf
                GUICtrlSetData($aVal[$k], _EQ_ValText($iNow))
                $bChanged = True
            EndIf
        Next
        If $bChanged Then
            ; the curve no longer matches a preset: make sure the other (unchanged) sliders are kept as they are
            For $k = 0 To 10
                If $k = 0 Then
                    $g_fEqPreamp = $aLast[0]
                Else
                    $g_aEqBands[$k - 1] = $aLast[$k]
                EndIf
            Next
            $g_iEqPreset = -2
            _GUICtrlComboBox_SetCurSel($cboPreset, $iCustomIdx)
            _VLC_ApplyEqualizer()
        EndIf
        Sleep(15)
    WEnd
EndFunc

; ======================================================================
;  RADIO PLAYER (danh ba dai radio radio-browser.info: moi quoc gia / ngon ngu)
; ======================================================================
Func _Json_Unescape($s)
    If StringInStr($s, "\") = 0 Then Return $s
    Local $sOut = "", $n = StringLen($s), $i = 1, $c, $d, $iCode
    While $i <= $n
        $c = StringMid($s, $i, 1)
        If $c = "\" And $i < $n Then
            $d = StringMid($s, $i + 1, 1)
            Switch $d
                Case "n", "r", "t"
                    $sOut &= " "
                    $i += 2
                Case "u"
                    $iCode = Dec(StringMid($s, $i + 2, 4))
                    If $iCode > 0 Then $sOut &= ChrW($iCode)
                    $i += 6
                Case Else
                    $sOut &= $d
                    $i += 2
            EndSwitch
            ContinueLoop
        EndIf
        $sOut &= $c
        $i += 1
    WEnd
    Return $sOut
EndFunc

Func _Json_Str($sObj, $sKey)
    Local $a = StringRegExp($sObj, '"' & $sKey & '"\s*:\s*"((?:[^"\\]|\\.)*)"', 1)
    If @error Then Return ""
    Return _Json_Unescape($a[0])
EndFunc

Func _Json_Num($sObj, $sKey)
    Local $a = StringRegExp($sObj, '"' & $sKey & '"\s*:\s*(-?\d+)', 1)
    If @error Then Return 0
    Return Int($a[0])
EndFunc

Func _Radio_ComErr($oErr)
    ; chi de tranh script bi dung khi WinHttp gap loi ket noi
EndFunc

; Tra ve noi dung (UTF-8) hoac "" neu khong ket noi duoc may chu nao
Func _Radio_Get($sPath)
    Local $aServers[6] = [$g_sRadioServer, "all.api.radio-browser.info", "de1.api.radio-browser.info", "de2.api.radio-browser.info", "fi1.api.radio-browser.info", "nl1.api.radio-browser.info"]
    Local $sCustom = IniRead($CONFIG_FILE, "Settings", "RadioServer", "")
    If $sCustom <> "" Then $aServers[0] = $sCustom
    Local $oOldErr = ObjEvent("AutoIt.Error", "_Radio_ComErr")
    Local $oHTTP, $sBody, $sTried = "|"
    For $i = 0 To UBound($aServers) - 1
        If $aServers[$i] = "" Or StringInStr($sTried, "|" & $aServers[$i] & "|") Then ContinueLoop
        $sTried &= $aServers[$i] & "|"
        $oHTTP = ObjCreate("WinHttp.WinHttpRequest.5.1")
        If Not IsObj($oHTTP) Then ExitLoop
        $oHTTP.SetTimeouts(4000, 4000, 8000, 20000)
        $oHTTP.Open("GET", "https://" & $aServers[$i] & $sPath, False)
        $oHTTP.SetRequestHeader("User-Agent", "VDHMediaCenter/" & $version)
        $oHTTP.Send()
        If @error Then ContinueLoop
        If $oHTTP.Status <> 200 Then ContinueLoop
        $sBody = BinaryToString($oHTTP.ResponseBody, 4)
        If StringLen($sBody) > 1 Then
            $g_sRadioServer = $aServers[$i]
            Return $sBody
        EndIf
    Next
    Return ""
EndFunc

; $sKind = "countries" | "languages"  ->  mang [n][3] (ten, ma, so dai), sap xep theo ten; 0 neu loi
Func _Radio_LoadList($sKind)
    Local $sJson = _Radio_Get("/json/" & $sKind & "?hidebroken=true&order=name")
    If $sJson = "" Then Return 0
    Local $aObj = StringRegExp($sJson, '\{[^{}]*\}', 3)
    If @error Then Return 0
    Local $aOut[UBound($aObj)][3], $n = 0
    Local $sName, $sCode, $iCnt
    For $i = 0 To UBound($aObj) - 1
        $sName = StringStripWS(StringReplace(_Json_Str($aObj[$i], "name"), "|", "/"), 7)
        $iCnt = _Json_Num($aObj[$i], "stationcount")
        If $sName = "" Or $iCnt <= 0 Then ContinueLoop
        If $sKind = "countries" Then
            $sCode = _Json_Str($aObj[$i], "iso_3166_1")
            If $sCode = "" Then ContinueLoop
        Else
            $sCode = $sName
        EndIf
        $aOut[$n][0] = $sName
        $aOut[$n][1] = $sCode
        $aOut[$n][2] = $iCnt
        $n += 1
    Next
    If $n = 0 Then Return 0
    ReDim $aOut[$n][3]
    _ArraySort($aOut, 0, 0, 0, 0)
    Return $aOut
EndFunc

; Tra ve mang [n][5] (ten, url, codec, bitrate, tags) hoac 0 neu loi, 1x1 trong neu khong co dai nao
Func _Radio_SearchStations($sKind, $sCode, $sName)
    Local $sPath = "/json/stations/search?hidebroken=true&order=votes&reverse=true&limit=500"
    If $sKind = "countries" Then
        $sPath &= "&countrycode=" & _URLEncode($sCode)
    Else
        $sPath &= "&language=" & _URLEncode(StringLower($sCode)) & "&languageExact=true"
    EndIf
    If $sName <> "" Then $sPath &= "&name=" & _URLEncode($sName)
    Local $sJson = _Radio_Get($sPath)
    If $sJson = "" Then Return 0
    Local $aObj = StringRegExp($sJson, '\{[^{}]*\}', 3)
    Local $iRxErr = @error
    Local $aOut[1][5]
    If $iRxErr Then Return $aOut
    ReDim $aOut[UBound($aObj)][5]
    Local $n = 0, $sNm, $sUrl
    For $i = 0 To UBound($aObj) - 1
        $sNm = StringStripWS(StringReplace(_Json_Str($aObj[$i], "name"), "|", "/"), 7)
        $sUrl = _Json_Str($aObj[$i], "url_resolved")
        If $sUrl = "" Then $sUrl = _Json_Str($aObj[$i], "url")
        If $sNm = "" Or $sUrl = "" Then ContinueLoop
        $aOut[$n][0] = $sNm
        $aOut[$n][1] = $sUrl
        $aOut[$n][2] = _Json_Str($aObj[$i], "codec")
        $aOut[$n][3] = _Json_Num($aObj[$i], "bitrate")
        $aOut[$n][4] = _Json_Str($aObj[$i], "tags")
        $n += 1
    Next
    If $n = 0 Then
        Local $aNone[1][5]
        Return $aNone
    EndIf
    ReDim $aOut[$n][5]
    Return $aOut
EndFunc

Func _Radio_StationLabel($aSt, $i)
    Local $s = $aSt[$i][0]
    Local $sInfo = StringUpper($aSt[$i][2])
    If $aSt[$i][3] > 0 Then $sInfo &= ($sInfo = "" ? "" : " ") & $aSt[$i][3] & " kbps"
    If $sInfo <> "" Then $s &= " (" & $sInfo & ")"
    Return $s
EndFunc

Func _Radio_Loading($sText)
    Local $h = GUICreate(_T("Loading"), 300, 80, -1, -1, $WS_POPUP, BitOR($WS_EX_TOPMOST, $WS_EX_TOOLWINDOW))
    GUICtrlCreateLabel($sText, 10, 25, 280, 30, $SS_CENTER)
    GUISetBkColor(0xFFFFFF, $h)
    GUISetState(@SW_SHOW, $h)
    Return $h
EndFunc

; Nghe thong tin bai dang phat (ICY NowPlaying) tu libvlc
Func _VLC_GetNowPlaying()
    If Not $oVLC_Player Or $hVLC_Dll = -1 Then Return ""
    Local $aM = DllCall($hVLC_Dll, "ptr:cdecl", "libvlc_media_player_get_media", "ptr", $oVLC_Player)
    If @error Or Not IsArray($aM) Or Not $aM[0] Then Return ""
    Local $pMedia = $aM[0]
    Local $sOut = ""
    Local $aT = DllCall($hVLC_Dll, "ptr:cdecl", "libvlc_media_get_meta", "ptr", $pMedia, "int", 12) ; libvlc_meta_NowPlaying
    If Not @error And IsArray($aT) And $aT[0] Then
        Local $aLen = DllCall("kernel32.dll", "int", "lstrlenA", "ptr", $aT[0])
        If Not @error And IsArray($aLen) And $aLen[0] > 0 And $aLen[0] < 4096 Then
            Local $tBytes = DllStructCreate("byte[" & $aLen[0] & "]", $aT[0])
            $sOut = BinaryToString(DllStructGetData($tBytes, 1), 4)
        EndIf
        DllCall($hVLC_Dll, "none:cdecl", "libvlc_free", "ptr", $aT[0])
    EndIf
    DllCall($hVLC_Dll, "none:cdecl", "libvlc_media_release", "ptr", $pMedia)
    Return StringStripWS($sOut, 3)
EndFunc

Func _ShowRadioPlayer()
    If Not _VLC_Direct_Init() Then
        MsgBox(16, _T("Error"), _T("Could not initialize libvlc.dll. Please ensure VLC DLLs are present in the lib folder."))
        Return
    EndIf
    Local $aSel, $sRes
    While True
        $aSel = _Radio_ChooseSource()
        If Not IsArray($aSel) Then ExitLoop
        $sRes = _Radio_StationsWindow($aSel[0], $aSel[1], $aSel[2])
        If $sRes <> "CHANGE" Then ExitLoop
    WEnd
    _RadioRec_Stop()
    _VLC_Direct_Stop()
    _Pan_Reset()
EndFunc

Func _Radio_FillSource($idList, ByRef $aData, ByRef $aShown, $sFilter)
    Local $iN = IsArray($aData) ? UBound($aData) : 0
    Local $aFix[$iN + 1]
    Local $k = 0, $s = ""
    For $i = 0 To $iN - 1
        If $sFilter <> "" And StringInStr($aData[$i][0], $sFilter) = 0 Then ContinueLoop
        $k += 1
        $aFix[$k] = $i
        $s &= $aData[$i][0] & " (" & _TF("{1} stations", $aData[$i][2]) & ")|"
    Next
    $aFix[0] = $k ; element 0 = count, items are $aFix[1..count] (indexes into $aData)
    ReDim $aFix[$k + 1]
    $aShown = $aFix
    GUICtrlSetData($idList, "")
    If $s <> "" Then GUICtrlSetData($idList, StringTrimRight($s, 1))
EndFunc

; Cua so chon quoc gia / ngon ngu. Tra ve [loai, ma, ten] hoac 0 neu nhan Cancel
Func _Radio_ChooseSource()
    Local $sKind = IniRead($CONFIG_FILE, "Settings", "RadioKind", "countries")
    If $sKind <> "languages" Then $sKind = "countries"
    Local $sLastCode = IniRead($CONFIG_FILE, "Settings", "RadioCode", "")

    Local $hLoad = _Radio_Loading(_T("Loading the list of radio stations..."))
    Local $aData = 0
    If $sKind = "countries" Then
        If Not IsArray($g_aRadioCountries) Or UBound($g_aRadioCountries, 0) < 2 Then $g_aRadioCountries = _Radio_LoadList("countries")
        $aData = $g_aRadioCountries
    Else
        If Not IsArray($g_aRadioLanguages) Or UBound($g_aRadioLanguages, 0) < 2 Then $g_aRadioLanguages = _Radio_LoadList("languages")
        $aData = $g_aRadioLanguages
    EndIf
    GUIDelete($hLoad)
    If Not IsArray($aData) Then
        MsgBox(48, _T("Radio Player"), _T("Cannot load the list of radio stations. Please check your internet connection."))
        Return 0
    EndIf

    Local $hGui = GUICreate(_T("Radio Player"), 410, 470)
    GUISetBkColor($COLOR_BLUE)
    GUICtrlCreateLabel(_T("Browse radio stations by:"), 10, 12, 390, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $cboKind = GUICtrlCreateCombo("", 10, 35, 390, 20, $CBS_DROPDOWNLIST)
    GUICtrlSetData(-1, _TL("Country|Language"), ($sKind = "countries") ? _T("Country") : _T("Language"))
    GUICtrlCreateLabel(_T("Type to filter the list:"), 10, 70, 390, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $inpFilter = GUICtrlCreateInput("", 10, 93, 390, 22)
    Local $lblList = GUICtrlCreateLabel(($sKind = "countries") ? _T("Countries (press Enter to choose):") : _T("Languages (press Enter to choose):"), 10, 128, 390, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $lst = GUICtrlCreateList("", 10, 150, 390, 235, BitOR($LBS_NOTIFY, $WS_VSCROLL, $WS_BORDER))
    Local $btnOK = GUICtrlCreateButton(_T("OK"), 90, 400, 100, 32, $BS_DEFPUSHBUTTON)
    Local $btnCancel = GUICtrlCreateButton(_T("Cancel"), 220, 400, 100, 32)

    Local $hDummyEnter = GUICtrlCreateDummy()
    Local $hDummyEsc = GUICtrlCreateDummy()
    Local $aAccel[2][2] = [["{ENTER}", $hDummyEnter], ["{ESC}", $hDummyEsc]]
    GUISetAccelerators($aAccel, $hGui)
    Local $bEnterOn = True

    Local $aShown[1]
    _Radio_FillSource($lst, $aData, $aShown, "")
    ; preselect the last used entry
    Local $iPre = 0
    For $i = 1 To $aShown[0]
        If $aData[$aShown[$i]][1] = $sLastCode Then
            $iPre = $i - 1
            ExitLoop
        EndIf
    Next
    _GUICtrlListBox_SetCurSel($lst, $iPre)
    GUISetState(@SW_SHOW, $hGui)
    _AllowUIPI($hGui)
    _AllowUIPI($inpFilter)
    ControlFocus($hGui, "", $lst)

    Local $sLastFilter = "", $nMsg, $sNow, $iIdx, $iNewKind, $aResult, $aBtns[2] = [$btnOK, $btnCancel]
    While 1
        _SyncEnterAccel($hGui, $aAccel, $lst, $bEnterOn)
        $nMsg = _GuiMsg($hGui)
        If $nMsg = $hDummyEnter Then
            Local $iPressed = _EnterFocusedButton($hGui, $aBtns)
            $nMsg = ($iPressed <> 0) ? $iPressed : $btnOK
        EndIf

        Switch $nMsg
            Case $GUI_EVENT_CLOSE, $btnCancel, $hDummyEsc
                GUIDelete($hGui)
                Return 0

            Case $cboKind
                $iNewKind = _GUICtrlComboBox_GetCurSel($cboKind)
                $sKind = ($iNewKind = 1) ? "languages" : "countries"
                $hLoad = _Radio_Loading(_T("Loading the list of radio stations..."))
                If $sKind = "countries" Then
                    If Not IsArray($g_aRadioCountries) Or UBound($g_aRadioCountries, 0) < 2 Then $g_aRadioCountries = _Radio_LoadList("countries")
                    $aData = $g_aRadioCountries
                Else
                    If Not IsArray($g_aRadioLanguages) Or UBound($g_aRadioLanguages, 0) < 2 Then $g_aRadioLanguages = _Radio_LoadList("languages")
                    $aData = $g_aRadioLanguages
                EndIf
                GUIDelete($hLoad)
                GUISwitch($hGui)
                If Not IsArray($aData) Then
                    MsgBox(48, _T("Radio Player"), _T("Cannot load the list of radio stations. Please check your internet connection."))
                    $sKind = ($sKind = "countries") ? "languages" : "countries"
                    _GUICtrlComboBox_SetCurSel($cboKind, ($sKind = "countries") ? 0 : 1)
                    $aData = ($sKind = "countries") ? $g_aRadioCountries : $g_aRadioLanguages
                EndIf
                GUICtrlSetData($lblList, ($sKind = "countries") ? _T("Countries (press Enter to choose):") : _T("Languages (press Enter to choose):"))
                GUICtrlSetData($inpFilter, "")
                $sLastFilter = ""
                _Radio_FillSource($lst, $aData, $aShown, "")
                _GUICtrlListBox_SetCurSel($lst, 0)

            Case $btnOK
                $iIdx = _GUICtrlListBox_GetCurSel($lst)
                If $iIdx >= 0 And $iIdx < $aShown[0] Then
                    Local $aRow[3]
                    $aRow[0] = $sKind
                    $aRow[1] = $aData[$aShown[$iIdx + 1]][1]
                    $aRow[2] = $aData[$aShown[$iIdx + 1]][0]
                    IniWrite($CONFIG_FILE, "Settings", "RadioKind", $sKind)
                    IniWrite($CONFIG_FILE, "Settings", "RadioCode", $aRow[1])
                    GUIDelete($hGui)
                    Return $aRow
                EndIf
        EndSwitch

        $sNow = GUICtrlRead($inpFilter)
        If $sNow <> $sLastFilter Then
            $sLastFilter = $sNow
            _Radio_FillSource($lst, $aData, $aShown, $sNow)
            _GUICtrlListBox_SetCurSel($lst, 0)
        EndIf
        Sleep(10)
    WEnd
EndFunc

; Safety net: if libvlc still managed to open its own video window (title "VLC (...output)") in THIS process,
; hide it and give the keyboard focus back to the radio window, so volume keys / slider keep working.
Func _Radio_HideVoutWindow($hGui)
    Local $aWin = WinList("[REGEXPTITLE:^VLC \(.*\)$]")
    If Not IsArray($aWin) Then Return
    Local $bHidden = False
    For $i = 1 To $aWin[0][0]
        If $aWin[$i][1] = $hGui Then ContinueLoop
        If WinGetProcess($aWin[$i][1]) <> @AutoItPID Then ContinueLoop
        WinSetState($aWin[$i][1], "", @SW_HIDE)
        $bHidden = True
    Next
    If $bHidden Then WinActivate($hGui)
EndFunc

Func _Radio_SetVolumeUI($idSlider, $iVol)
    If $iVol > 100 Then $iVol = 100
    If $iVol < 0 Then $iVol = 0
    $g_iAppVolume = $iVol
    _VLC_Direct_SetVolume($iVol)
    If $idSlider <> 0 Then GUICtrlSetData($idSlider, $iVol)
EndFunc

; Cua so danh sach dai: tim kiem, phat (Enter), dung, ghi am, yeu thich, chep lien ket, am luong, pan, equalizer, hen gio ngu.
; $bFavMode = True: cua so "Favorite Stations" (danh sach la cac dai yeu thich, khong co o tim kiem va nut doi quoc gia).
; Tra ve "CHANGE" neu nguoi dung muon chon quoc gia/ngon ngu khac, "" neu dong.
Func _Radio_StationsWindow($sKind, $sCode, $sName, $bFavMode = False)
    Local Const $NONE = -9999 ; id of a control that does not exist in this mode (never equals a real message)
    Local $hGui = GUICreate($bFavMode ? $sName : _TF("Radio - {1}", $sName), 480, 640)
    GUISetBkColor($COLOR_BLUE)
    Local $inpSearch = $NONE, $btnSearch = $NONE, $btnFav = $NONE, $btnRemove = $NONE, $btnClearFav = $NONE, $btnChange = $NONE
    If $bFavMode Then
        GUICtrlCreateLabel(_T("Your favorite radio stations:"), 10, 10, 460, 20)
        GUICtrlSetColor(-1, 0xFFFFFF)
    Else
        GUICtrlCreateLabel(_TF("Search stations in {1} (leave empty to show the most popular):", $sName), 10, 10, 460, 20)
        GUICtrlSetColor(-1, 0xFFFFFF)
        $inpSearch = GUICtrlCreateInput("", 10, 32, 360, 22)
        $btnSearch = GUICtrlCreateButton(_T("Search"), 380, 30, 90, 26)
    EndIf
    GUICtrlCreateLabel(_T("Stations (press Enter to play):"), 10, 66, 460, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $lst = GUICtrlCreateList("", 10, 88, 460, 220, BitOR($LBS_NOTIFY, $WS_VSCROLL, $WS_BORDER))
    Local $lblStatus = GUICtrlCreateLabel(_T("Stopped"), 10, 316, 460, 20, $SS_NOPREFIX)
    GUICtrlSetColor(-1, 0xFFFF00)
    GUICtrlSetFont(-1, 10, 800)
    Local $lblNow = GUICtrlCreateLabel("", 10, 338, 460, 36, $SS_NOPREFIX)
    GUICtrlSetColor(-1, 0x00FF00)
    Local $lblRec = GUICtrlCreateLabel("", 10, 376, 460, 20, $SS_NOPREFIX)
    GUICtrlSetColor(-1, 0xFF9090)

    ; manual volume slider (Left/Right = 5, Page Up/Down = 10). The label before it names the slider for screen readers.
    GUICtrlCreateLabel(_T("Volume:"), 10, 414, 70, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $sldVol = GUICtrlCreateSlider(85, 408, 385, 30, BitOR(0x0001, $WS_TABSTOP))
    GUICtrlSetLimit($sldVol, 100, 0)
    GUICtrlSendMsg($sldVol, 0x0417, 0, 5)
    GUICtrlSendMsg($sldVol, 0x0415, 0, 10)
    GUICtrlSetData($sldVol, $g_iAppVolume)

    Local $btnPlay = GUICtrlCreateButton(_T("Play"), 10, 450, 150, 32)
    Local $btnStop = GUICtrlCreateButton(_T("Stop (Alt+S)"), 165, 450, 150, 32)
    Local $btnRec = GUICtrlCreateButton(_T("Record (Ctrl+R)"), 320, 450, 150, 32)
    If $bFavMode Then
        $btnRemove = GUICtrlCreateButton(_T("Remove selected (Delete)"), 10, 490, 150, 32)
    Else
        $btnFav = GUICtrlCreateButton(_T("Add to favorites (Ctrl+D)"), 10, 490, 150, 32)
    EndIf
    Local $btnCopy = GUICtrlCreateButton(_T("Copy link (Alt+K)"), 165, 490, 150, 32)
    Local $btnSleep = GUICtrlCreateButton(_T("Sleep timer (Alt+T)"), 320, 490, 150, 32)
    If $bFavMode Then
        $btnClearFav = GUICtrlCreateButton(_T("Clear all favorites"), 10, 530, 150, 32)
    Else
        $btnChange = GUICtrlCreateButton(_T("Change country (Alt+G)"), 10, 530, 150, 32)
    EndIf
    Local $btnClose = GUICtrlCreateButton(_T("Close"), 165, 530, 150, 32)
    GUICtrlCreateLabel($bFavMode ? _T("Ctrl+Up / Ctrl+Down: volume. Ctrl+Left / Ctrl+Right: pan. Page Up / Page Down: previous / next station. Delete: remove from favorites. Ctrl+R: record. Ctrl+I: now playing. Esc: close.") _
            : _T("Ctrl+Up / Ctrl+Down: volume. Ctrl+Left / Ctrl+Right: pan. Page Up / Page Down: previous / next station. Ctrl+D: add to favorites. Ctrl+R: record. Ctrl+I: now playing. Esc: close."), 10, 572, 460, 60)
    GUICtrlSetColor(-1, 0xFFFFFF)

    Local $hDummyEnter = GUICtrlCreateDummy()
    Local $hDummyEsc = GUICtrlCreateDummy()
    Local $hDummyVolUp = GUICtrlCreateDummy()
    Local $hDummyVolDown = GUICtrlCreateDummy()
    Local $hDummyInfo = GUICtrlCreateDummy()
    Local $hDummyPanL = GUICtrlCreateDummy()
    Local $hDummyPanR = GUICtrlCreateDummy()
    Local $hDummyPgUp = GUICtrlCreateDummy()
    Local $hDummyPgDn = GUICtrlCreateDummy()
    Local $aAcc[16][2], $nAcc = 0
    _Radio_AccAdd($aAcc, $nAcc, "{ENTER}", $hDummyEnter)
    _Radio_AccAdd($aAcc, $nAcc, "{ESC}", $hDummyEsc)
    _Radio_AccAdd($aAcc, $nAcc, "^{UP}", $hDummyVolUp)
    _Radio_AccAdd($aAcc, $nAcc, "^{DOWN}", $hDummyVolDown)
    _Radio_AccAdd($aAcc, $nAcc, "^{LEFT}", $hDummyPanL)
    _Radio_AccAdd($aAcc, $nAcc, "^{RIGHT}", $hDummyPanR)
    _Radio_AccAdd($aAcc, $nAcc, "^i", $hDummyInfo)
    _Radio_AccAdd($aAcc, $nAcc, "^r", $btnRec)
    _Radio_AccAdd($aAcc, $nAcc, "!s", $btnStop)
    _Radio_AccAdd($aAcc, $nAcc, "!k", $btnCopy)
    _Radio_AccAdd($aAcc, $nAcc, "!t", $btnSleep)
    _Radio_AccAdd($aAcc, $nAcc, "^d", $btnFav)
    _Radio_AccAdd($aAcc, $nAcc, "!g", $btnChange)
    _Radio_AccAdd($aAcc, $nAcc, "{DEL}", $btnRemove)
    _Radio_ApplyAccel($hGui, $aAcc, $nAcc, False, $hDummyPgUp, $hDummyPgDn)
    Local $bPagingOn = False, $bWantPaging = False

    Local $aSt = 0 ; stations [n][5]
    Local $iCount = 0, $iPlaying = -1, $iPlayState = 0, $hPollTimer = TimerInit(), $hNowTimer = TimerInit(), $hRecTimer = TimerInit()
    ; $iPlayState: 0 = stopped, 1 = connecting, 2 = playing, 3 = connection lost, waiting before the next reconnect attempt
    Local $sPlayName = "", $sPlayUrl = "", $iRetry = 0, $iRetryDelay = 0, $iMaxRetry = 12, $hRetryTimer = 0, $hBufTimer = 0
    Local $bReconnecting = False, $bSwitching = False, $bQuiet = False, $bDropped = False
    Local $sLastNow = "", $iLastVol = $g_iAppVolume
    Local $aBtns[0]
    _Radio_IdAdd($aBtns, $btnPlay)
    _Radio_IdAdd($aBtns, $btnStop)
    _Radio_IdAdd($aBtns, $btnRec)
    _Radio_IdAdd($aBtns, $btnFav)
    _Radio_IdAdd($aBtns, $btnRemove)
    _Radio_IdAdd($aBtns, $btnCopy)
    _Radio_IdAdd($aBtns, $btnSleep)
    _Radio_IdAdd($aBtns, $btnClearFav)
    _Radio_IdAdd($aBtns, $btnChange)
    _Radio_IdAdd($aBtns, $btnClose)
    Local $nMsg, $iSel, $iV, $iState, $sNow, $hFocus, $sTerm, $aTmp, $iPressed, $iPlayStart = 0
    Local $iTarget, $iStep, $iRes, $sRecFile, $sRecName, $sRecUrl, $sBatch, $hLoad

    GUISetState(@SW_SHOW, $hGui)
    _AllowUIPI($hGui)
    If Not $bFavMode Then _AllowUIPI($inpSearch)

    Local $bDoSearch = Not $bFavMode
    If $bFavMode Then
        _Radio_ReloadFav($lst, $aSt, $iCount, 0)
        GUICtrlSetData($lblStatus, _TF("{1} stations found", $iCount))
        ControlFocus($hGui, "", $lst)
    EndIf

    While 1
        ; first load (most popular stations) and every new search
        If $bDoSearch Then
            $bDoSearch = False
            $sTerm = StringStripWS(GUICtrlRead($inpSearch), 3)
            $hLoad = _Radio_Loading(_T("Loading stations..."))
            $aTmp = _Radio_SearchStations($sKind, $sCode, $sTerm)
            GUIDelete($hLoad)
            GUISwitch($hGui)
            If Not IsArray($aTmp) Then
                MsgBox(48, _T("Radio Player"), _T("Cannot load the list of radio stations. Please check your internet connection."))
            ElseIf $aTmp[0][0] = "" Then
                $aSt = 0
                $iCount = 0
                GUICtrlSetData($lst, "")
                MsgBox(64, _T("Radio Player"), _T("No stations were found."))
            Else
                $aSt = $aTmp
                $iCount = UBound($aSt)
                _Radio_FillStations($lst, $aSt, $iCount)
                _GUICtrlListBox_SetCurSel($lst, 0)
                $iPlaying = -1
                If $iPlayState = 0 Then GUICtrlSetData($lblStatus, _TF("{1} stations found", $iCount))
            EndIf
            ControlFocus($hGui, "", $lst)
        EndIf

        $nMsg = _GuiMsg($hGui)
        If $nMsg = $hDummyEnter Then
            $hFocus = ControlGetHandle($hGui, "", ControlGetFocus($hGui))
            If $hFocus = GUICtrlGetHandle($lst) Then
                $nMsg = $btnPlay
            ElseIf Not $bFavMode And $hFocus = GUICtrlGetHandle($inpSearch) Then
                $nMsg = $btnSearch
            Else
                $iPressed = _EnterFocusedButton($hGui, $aBtns)
                If $iPressed <> 0 Then $nMsg = $iPressed
            EndIf
        EndIf

        ; Page Up / Page Down while listening: previous / next station (wraps around), played at once
        If $nMsg = $hDummyPgUp Or $nMsg = $hDummyPgDn Then
            If $iCount > 1 Then
                $iTarget = $iPlaying
                If $iTarget < 0 Then $iTarget = _GUICtrlListBox_GetCurSel($lst)
                If $iTarget < 0 Then $iTarget = 0
                $iStep = 1
                If $nMsg = $hDummyPgUp Then $iStep = -1
                $iTarget += $iStep
                If $iTarget >= $iCount Then $iTarget = 0
                If $iTarget < 0 Then $iTarget = $iCount - 1
                _GUICtrlListBox_SetCurSel($lst, $iTarget)
                $bSwitching = True
                $nMsg = $btnPlay
            Else
                $nMsg = 0
            EndIf
        EndIf

        Switch $nMsg
            Case $GUI_EVENT_CLOSE, $btnClose, $hDummyEsc
                If _RadioRec_Active() Then
                    $sRecFile = _RadioRec_Stop()
                    If $sRecFile = "@CONVERTING" Then
                        _NVDA_Speak(_T("Converting the recording in the background..."))
                    ElseIf $sRecFile <> "" Then
                        _NVDA_Speak(_TF("Recording saved: {1}", _Radio_FileName($sRecFile)))
                    EndIf
                EndIf
                _VLC_Direct_Stop()
                GUIDelete($hGui)
                Return ""

            Case $btnChange
                If _RadioRec_Active() Then
                    $sRecFile = _RadioRec_Stop()
                    If $sRecFile = "@CONVERTING" Then
                        _NVDA_Speak(_T("Converting the recording in the background..."))
                    ElseIf $sRecFile <> "" Then
                        _NVDA_Speak(_TF("Recording saved: {1}", _Radio_FileName($sRecFile)))
                    EndIf
                EndIf
                GUIDelete($hGui)
                Return "CHANGE"

            Case $btnSearch
                $bDoSearch = True

            Case $btnPlay
                $iSel = _GUICtrlListBox_GetCurSel($lst)
                $bQuiet = $bSwitching
                $bSwitching = False
                If $iSel >= 0 And $iSel < $iCount Then
                    $iPlaying = $iSel
                    $sPlayName = $aSt[$iSel][0]
                    $sPlayUrl = $aSt[$iSel][1]
                    $iPlayState = 1
                    $bReconnecting = False
                    $iRetry = 0
                    $hBufTimer = 0
                    $iPlayStart = TimerInit()
                    $sLastNow = ""
                    GUICtrlSetData($lblNow, "")
                    GUICtrlSetData($lblStatus, _TF("Connecting to {1}...", $sPlayName))
                    If $bQuiet Then
                        _NVDA_Speak($sPlayName) ; Page Up / Page Down: just say the name of the new station
                    Else
                        _NVDA_Speak(_TF("Connecting to {1}...", $sPlayName))
                    EndIf
                    _VLC_Direct_Play($sPlayUrl, True)
                    _VLC_Direct_SetRate(1.0)
                    _VLC_Direct_SetVolume($g_iAppVolume)
                    _Radio_HideVoutWindow($hGui)
                    If Not $bQuiet Then ControlFocus($hGui, "", $lst)
                EndIf

            Case $btnStop
                $iPlayState = 0
                $bReconnecting = False
                _VLC_Direct_Stop()
                $sLastNow = ""
                GUICtrlSetData($lblStatus, _T("Stopped"))
                GUICtrlSetData($lblNow, "")
                _NVDA_Speak(_T("Stopped"))

            Case $btnRec
                If _RadioRec_Active() Then
                    $sRecFile = _RadioRec_Stop()
                    _Radio_RecUpdateUI($btnRec, $lblRec)
                    If $sRecFile = "@CONVERTING" Then
                        GUICtrlSetData($lblRec, _T("Converting the recording..."))
                        _NVDA_Speak(_T("Converting the recording..."))
                    ElseIf $sRecFile = "" Then
                        GUICtrlSetData($lblRec, _T("Nothing was recorded."))
                        _NVDA_Speak(_T("Nothing was recorded."))
                    Else
                        GUICtrlSetData($lblRec, _TF("Recording saved: {1}", $sRecFile))
                        _NVDA_Speak(_TF("Recording saved: {1}", _Radio_FileName($sRecFile)))
                    EndIf
                Else
                    ; record the station that is playing; when nothing is playing, the one selected in the list
                    $sRecName = ""
                    $sRecUrl = ""
                    If $iPlayState > 0 And $sPlayUrl <> "" Then
                        $sRecName = $sPlayName
                        $sRecUrl = $sPlayUrl
                    Else
                        $iSel = _GUICtrlListBox_GetCurSel($lst)
                        If $iSel >= 0 And $iSel < $iCount Then
                            $sRecName = $aSt[$iSel][0]
                            $sRecUrl = $aSt[$iSel][1]
                        EndIf
                    EndIf
                    If $sRecUrl = "" Then
                        _NVDA_Speak(_T("Choose a station to record first."))
                    Else
                        $iRes = _RadioRec_Start($sRecName, $sRecUrl)
                        If $iRes = 1 Then
                            $hRecTimer = TimerInit()
                            _Radio_RecUpdateUI($btnRec, $lblRec)
                            _NVDA_Speak(_TF("Recording started: {1}", $sRecName))
                        ElseIf $iRes = -2 Then
                            _NVDA_Speak(_T("The recording folder cannot be created. Please choose another folder in Settings > Radio."))
                        Else
                            _NVDA_Speak(_T("Could not start the recording."))
                        EndIf
                    EndIf
                EndIf

            Case $btnFav
                ; add the station selected in the list (or the one playing) to the favorites
                $iSel = _GUICtrlListBox_GetCurSel($lst)
                If $iSel < 0 Or $iSel >= $iCount Then $iSel = $iPlaying
                If $iSel >= 0 And $iSel < $iCount Then
                    $iRes = _RadioFav_Add($aSt[$iSel][0], $aSt[$iSel][1], $aSt[$iSel][2], $aSt[$iSel][3])
                    If $iRes = 1 Then
                        _NVDA_Speak(_TF("Added to favorites: {1}", $aSt[$iSel][0]))
                    ElseIf $iRes = 0 Then
                        _NVDA_Speak(_TF("Already in favorites: {1}", $aSt[$iSel][0]))
                    Else
                        _NVDA_Speak(_T("Could not save the favorite station."))
                    EndIf
                EndIf

            Case $btnRemove
                $iSel = _GUICtrlListBox_GetCurSel($lst)
                If $iSel >= 0 And $iSel < $iCount Then
                    $sRecName = $aSt[$iSel][0]
                    If _RadioFav_RemoveAt($iSel) Then
                        $iPlaying = -1
                        _Radio_ReloadFav($lst, $aSt, $iCount, $iSel)
                        If $iPlayState = 0 Then GUICtrlSetData($lblStatus, _TF("{1} stations found", $iCount))
                        _NVDA_Speak(_TF("Removed from favorites: {1}", $sRecName))
                    EndIf
                EndIf
                ControlFocus($hGui, "", $lst)

            Case $btnClearFav
                If $iCount > 0 Then
                    If MsgBox(36, _T("Confirm"), _T("Are you sure you want to remove all favorite stations?"), 0, $hGui) = 6 Then
                        _RadioFav_Clear()
                        $iPlaying = -1
                        _Radio_ReloadFav($lst, $aSt, $iCount, 0)
                        If $iPlayState = 0 Then GUICtrlSetData($lblStatus, _TF("{1} stations found", $iCount))
                        _NVDA_Speak(_T("All favorite stations were removed."))
                    EndIf
                EndIf
                ControlFocus($hGui, "", $lst)

            Case $btnCopy
                $iSel = _GUICtrlListBox_GetCurSel($lst)
                If $iSel >= 0 And $iSel < $iCount Then
                    ClipPut($aSt[$iSel][1])
                    _NVDA_Speak(_T("Link copied to clipboard"))
                ElseIf $sPlayUrl <> "" Then
                    ClipPut($sPlayUrl)
                    _NVDA_Speak(_T("Link copied to clipboard"))
                EndIf

            Case $btnSleep
                _ShowSleepTimerDialog($hGui)
                GUISwitch($hGui)
                ControlFocus($hGui, "", $btnSleep)

            Case $hDummyVolUp
                _Radio_SetVolumeUI($sldVol, GUICtrlRead($sldVol) + 5)
                $iLastVol = $g_iAppVolume
                _NVDA_Speak(_TF("Volume: {1}%", $g_iAppVolume))

            Case $hDummyVolDown
                _Radio_SetVolumeUI($sldVol, GUICtrlRead($sldVol) - 5)
                $iLastVol = $g_iAppVolume
                _NVDA_Speak(_TF("Volume: {1}%", $g_iAppVolume))

            Case $hDummyPanL
                _StepPan(-1)

            Case $hDummyPanR
                _StepPan(1)

            Case $hDummyInfo
                $sNow = _VLC_GetNowPlaying()
                If $iPlayState = 0 Then
                    _NVDA_Speak(_T("Stopped"))
                ElseIf $sNow <> "" Then
                    _NVDA_Speak(_TF("Now playing: {1}", $sNow))
                ElseIf $sPlayName <> "" Then
                    _NVDA_Speak(_TF("Playing: {1}", $sPlayName))
                EndIf
        EndSwitch

        ; slider moved by the user
        $iV = GUICtrlRead($sldVol)
        If $iV <> $iLastVol Then
            $iLastVol = $iV
            $g_iAppVolume = $iV
            _VLC_Direct_SetVolume($iV)
        EndIf

        ; playback state / reconnect / now playing (twice a second)
        If $iPlayState > 0 And TimerDiff($hPollTimer) >= 500 Then
            $hPollTimer = TimerInit()
            _Radio_HideVoutWindow($hGui)
            $iState = _VLC_Direct_GetState()
            _VLC_StereoMode_Retry()
            If $g_iPanStep <> 0 Or $g_bAutoPan Or _StereoModeUsesSession() Then _Pan_Sync()
            Switch $iPlayState
                Case 1 ; connecting (or reconnecting)
                    If $iState = 3 Then
                        $iPlayState = 2
                        $hBufTimer = 0
                        _VLC_Direct_SetVolume($g_iAppVolume)
                        If $bReconnecting Then
                            GUICtrlSetData($lblStatus, _TF("Playing: {1}", $sPlayName))
                            _NVDA_Speak(_TF("Reconnected to {1}", $sPlayName))
                        Else
                            GUICtrlSetData($lblStatus, _TF("Playing: {1}", $sPlayName))
                            _NVDA_Speak(_TF("Playing: {1}", $sPlayName))
                        EndIf
                        $bReconnecting = False
                        $iRetry = 0
                    ElseIf $iState = 7 Or ($iState >= 5 And TimerDiff($iPlayStart) > 4000) Or TimerDiff($iPlayStart) > 30000 Then
                        _VLC_Direct_Stop()
                        If $bReconnecting And $iRetry < $iMaxRetry Then
                            ; this reconnect attempt failed: wait a little longer, then try again
                            $iPlayState = 3
                            $iRetryDelay = 2000 * $iRetry
                            If $iRetryDelay > 10000 Then $iRetryDelay = 10000
                            $hRetryTimer = TimerInit()
                        Else
                            $iPlayState = 0
                            $bReconnecting = False
                            If $iRetry > 0 Then
                                GUICtrlSetData($lblStatus, _T("The connection could not be restored."))
                                _NVDA_Speak(_T("The connection could not be restored."))
                            Else
                                GUICtrlSetData($lblStatus, _T("Cannot play this station."))
                                _NVDA_Speak(_T("Cannot play this station."))
                            EndIf
                        EndIf
                    EndIf

                Case 2 ; playing: watch for a dropped connection
                    $bDropped = False
                    If $iState = 7 Or $iState = 6 Or $iState = 5 Then
                        $bDropped = True
                    ElseIf $iState = 2 Then
                        If $hBufTimer = 0 Then $hBufTimer = TimerInit()
                        If TimerDiff($hBufTimer) > 20000 Then $bDropped = True ; buffering for too long = network is gone
                    Else
                        $hBufTimer = 0
                    EndIf
                    If $bDropped Then
                        $hBufTimer = 0
                        $iRetry = 0
                        $iPlayState = 3
                        $iRetryDelay = 1000
                        $hRetryTimer = TimerInit()
                        GUICtrlSetData($lblStatus, _T("Connection lost. Reconnecting..."))
                        GUICtrlSetData($lblNow, "")
                        $sLastNow = ""
                        _NVDA_Speak(_T("Connection lost. Reconnecting..."))
                    ElseIf TimerDiff($hNowTimer) >= 4000 Then
                        $hNowTimer = TimerInit()
                        $sNow = _VLC_GetNowPlaying()
                        If $sNow <> $sLastNow Then
                            $sLastNow = $sNow
                            GUICtrlSetData($lblNow, ($sNow <> "") ? _TF("Now playing: {1}", $sNow) : "")
                        EndIf
                    EndIf

                Case 3 ; waiting, then reconnect
                    If TimerDiff($hRetryTimer) >= $iRetryDelay Then
                        $iRetry += 1
                        $bReconnecting = True
                        $iPlayState = 1
                        $iPlayStart = TimerInit()
                        GUICtrlSetData($lblStatus, _TF("Reconnecting to {1} (attempt {2} of {3})...", $sPlayName, $iRetry, $iMaxRetry))
                        _VLC_Direct_Play($sPlayUrl, True)
                        _VLC_Direct_SetRate(1.0)
                        _VLC_Direct_SetVolume($g_iAppVolume)
                    EndIf
            EndSwitch
        EndIf

        ; the recording ended by itself (automatic stop time reached, the station ended the stream)
        If TimerDiff($hRecTimer) >= 1000 Then
            $hRecTimer = TimerInit()
            If $g_iRecConvN > 0 Then _RadioRec_ConvPoll($lblRec)
            If _RadioRec_Active() Then
                If Not _RadioRec_Alive() Then
                    $sRecFile = _RadioRec_Stop()
                    _Radio_RecUpdateUI($btnRec, $lblRec)
                    If $sRecFile = "@CONVERTING" Then
                        GUICtrlSetData($lblRec, _T("Converting the recording..."))
                        _NVDA_Speak(_T("Converting the recording..."))
                    ElseIf $sRecFile = "" Then
                        GUICtrlSetData($lblRec, _RadioRec_FailText())
                        _NVDA_Speak(_RadioRec_FailText())
                    Else
                        GUICtrlSetData($lblRec, _TF("Recording saved: {1}", $sRecFile))
                        _NVDA_Speak(_TF("Recording finished: {1}", _Radio_FileName($sRecFile)))
                    EndIf
                EndIf
            EndIf
        EndIf

        _SleepTimer_Tick() ; sleep timer (with the optional fade-out) also works in the radio
        If $g_bAutoPan Then _AutoPan_Tick(_VLC_Direct_GetState())

        ; Page Up / Page Down switch stations only while a station is playing or connecting
        $bWantPaging = ($iPlayState > 0)
        If $bWantPaging <> $bPagingOn Then
            $bPagingOn = $bWantPaging
            _Radio_ApplyAccel($hGui, $aAcc, $nAcc, $bPagingOn, $hDummyPgUp, $hDummyPgDn)
        EndIf
        Sleep(10)
    WEnd
EndFunc

; ======================================================================
;  PHIM TAT TUY CHINH (Settings > Shortcuts)
;  Moi hanh dong co mot ID, phim mac dinh va phim hien tai (luu trong settings.ini muc [Hotkeys]).
;  Gia tri "none" = tat phim. Bang phim tat cua cua so duoc ghep tu danh sach nay.
; ======================================================================
Func _HK_Reg($sId, $sScope, $sDefault, $sLabel, $sTextKey = "")
    Local $i = $g_iHKCount
    $g_aHK[$i][0] = $sId
    $g_aHK[$i][1] = $sScope
    $g_aHK[$i][2] = $sDefault
    $g_aHK[$i][3] = IniRead($CONFIG_FILE, "Hotkeys", $sId, $sDefault)
    If $g_aHK[$i][3] = "" Then $g_aHK[$i][3] = $sDefault
    $g_aHK[$i][4] = $sLabel
    $g_aHK[$i][5] = 0
    $g_aHK[$i][6] = 0
    $g_aHK[$i][7] = $sTextKey
    $g_iHKCount += 1
EndFunc

Func _HK_Index($sId)
    For $i = 0 To $g_iHKCount - 1
        If $g_aHK[$i][0] = $sId Then Return $i
    Next
    Return -1
EndFunc

Func _HK_SetHandle($sId, $h, $idText = 0)
    Local $i = _HK_Index($sId)
    If $i < 0 Then Return
    $g_aHK[$i][5] = $h
    $g_aHK[$i][6] = $idText
EndFunc

Func _HK_Key($sId)
    Local $i = _HK_Index($sId)
    If $i < 0 Then Return ""
    If $g_aHK[$i][3] = "none" Then Return ""
    Return $g_aHK[$i][3]
EndFunc

Func _HK_IsCustom($sId)
    Local $i = _HK_Index($sId)
    If $i < 0 Then Return False
    Return ($g_aHK[$i][3] <> $g_aHK[$i][2])
EndFunc

; Ghep bang phim tat: cac phim co dinh $aFixed + cac phim tuy chinh cua $sScope
Func _HK_BuildTable($sScope, $aFixed)
    Local $iFixed = UBound($aFixed)
    Local $aOut[$g_iHKCount + $iFixed][2], $n = 0
    For $i = 0 To $iFixed - 1
        $aOut[$n][0] = $aFixed[$i][0]
        $aOut[$n][1] = $aFixed[$i][1]
        $n += 1
    Next
    For $i = 0 To $g_iHKCount - 1
        If $g_aHK[$i][1] <> $sScope Then ContinueLoop
        If $g_aHK[$i][3] = "none" Or $g_aHK[$i][5] = 0 Then ContinueLoop
        $aOut[$n][0] = $g_aHK[$i][3]
        $aOut[$n][1] = $g_aHK[$i][5]
        $n += 1
    Next
    ReDim $aOut[$n][2]
    Return $aOut
EndFunc

; Ten phim de doc: "^+t" -> "Ctrl+Shift+T"
Func _HK_Display($sKey)
    If $sKey = "" Or $sKey = "none" Then Return _T("None")
    Local $s = "", $c
    While StringLen($sKey) > 1
        $c = StringLeft($sKey, 1)
        If $c = "^" Then
            $s &= "Ctrl+"
        ElseIf $c = "!" Then
            $s &= "Alt+"
        ElseIf $c = "+" Then
            $s &= "Shift+"
        ElseIf $c = "#" Then
            $s &= "Win+"
        Else
            ExitLoop
        EndIf
        $sKey = StringTrimLeft($sKey, 1)
    WEnd
    If StringLen($sKey) > 2 And StringLeft($sKey, 1) = "{" And StringRight($sKey, 1) = "}" Then
        Local $sName = StringMid($sKey, 2, StringLen($sKey) - 2)
        Switch StringUpper($sName)
            Case "SPACE"
                Return $s & "Space"
            Case "ESC"
                Return $s & "Esc"
            Case "PGUP"
                Return $s & "Page Up"
            Case "PGDN"
                Return $s & "Page Down"
            Case "INS"
                Return $s & "Insert"
            Case "DEL"
                Return $s & "Delete"
            Case "BS"
                Return $s & "Backspace"
            Case "APPSKEY"
                Return $s & "Applications"
        EndSwitch
        If StringRegExp($sName, "^(?i)F\d+$") Then Return $s & StringUpper($sName)
        Return $s & StringUpper(StringLeft($sName, 1)) & StringLower(StringMid($sName, 2))
    EndIf
    If StringLen($sKey) = 3 And StringLeft($sKey, 1) = "{" And StringRight($sKey, 1) = "}" Then $sKey = StringMid($sKey, 2, 1)
    Return $s & StringUpper($sKey)
EndFunc

; Thay phan "(Alt+D)" o cuoi mot dong chu bang phim hien tai (chi khi phim da bi doi)
Func _HK_FixText($sText, $sId)
    If Not _HK_IsCustom($sId) Then Return $sText
    Local $sKey = _HK_Key($sId)
    Local $sBase = StringRegExpReplace($sText, "\s*\([^()]*\)\s*$", "")
    If $sKey = "" Then Return $sBase
    Return $sBase & " (" & _HK_Display($sKey) & ")"
EndFunc

; Ten hanh dong de hien trong danh sach
Func _HK_ActionLabel($i)
    If $g_aHK[$i][7] <> "" Then Return StringRegExpReplace(_T($g_aHK[$i][7]), "\s*\([^()]*\)\s*$", "")
    Return _T($g_aHK[$i][4])
EndFunc

; Dong tro giup trong player: thay phan phim phia truoc dau ": " neu co phim bi doi
Func _HKL($sLineKey, $sIds)
    Local $s = _T($sLineKey)
    Local $aIds = StringSplit($sIds, "|", 2)
    Local $bAny = False
    For $i = 0 To UBound($aIds) - 1
        If _HK_IsCustom($aIds[$i]) Then $bAny = True
    Next
    If Not $bAny Then Return $s
    Local $iPos = StringInStr($s, ": ")
    If $iPos = 0 Then Return $s
    Local $sKeys = "", $sK
    For $i = 0 To UBound($aIds) - 1
        $sK = _HK_Key($aIds[$i])
        If $sK = "" Then ContinueLoop
        $sKeys &= (($sKeys = "") ? "" : " / ") & _HK_Display($sK)
    Next
    If $sKeys = "" Then Return StringMid($s, $iPos + 2)
    Return $sKeys & StringMid($s, $iPos)
EndFunc

; Cap nhat bang phim tat va chu tren cac nut cua cua so chinh
Func _HK_ApplyMain()
    If Not IsHWnd($mainform) Then Return
    Local $a = _HK_BuildTable("main", $g_aHKFixedMain)
    GUISetAccelerators($a, $mainform)
    For $i = 0 To $g_iHKCount - 1
        If $g_aHK[$i][1] = "main" And $g_aHK[$i][6] <> 0 And $g_aHK[$i][7] <> "" Then
            GUICtrlSetData($g_aHK[$i][6], _HK_FixText(_T($g_aHK[$i][7]), $g_aHK[$i][0]))
        EndIf
    Next
EndFunc

Func _HK_IsReserved($sScope, $sKey)
    Local $s = StringLower($sKey)
    If $sScope = "player" Then
        If StringRegExp($s, "^[1-9]$") Or $s = "{appskey}" Or $s = "+{f10}" Then Return True
    Else
        If $s = "{enter}" Or $s = "{esc}" Then Return True
    EndIf
    Return False
EndFunc

; ---------- Ban lam viec cua tab Shortcuts trong Settings ----------
Func _HK_WorkInit()
    For $i = 0 To $g_iHKCount - 1
        $g_aHKWork[$i] = $g_aHK[$i][3]
    Next
EndFunc

Func _HK_CommitWork()
    For $i = 0 To $g_iHKCount - 1
        $g_aHK[$i][3] = $g_aHKWork[$i]
        If $g_aHK[$i][3] = $g_aHK[$i][2] Then
            IniDelete($CONFIG_FILE, "Hotkeys", $g_aHK[$i][0])
        Else
            IniWrite($CONFIG_FILE, "Hotkeys", $g_aHK[$i][0], $g_aHK[$i][3])
        EndIf
    Next
    _HK_ApplyMain()
EndFunc

; Dien danh sach phim tat cua pham vi $iScope (0 = cua so chinh, 1 = player) vao listbox
Func _HK_FillList($idList, $iScope, $iSel = 0)
    Local $sScope = ($iScope = 1) ? "player" : "main"
    Local $s = "", $n = 0
    ReDim $g_aHKListIdx[$g_iHKCount + 1]
    For $i = 0 To $g_iHKCount - 1
        If $g_aHK[$i][1] <> $sScope Then ContinueLoop
        $g_aHKListIdx[$n] = $i
        $n += 1
        $s &= _HK_ActionLabel($i) & ": " & _HK_Display($g_aHKWork[$i]) & "|"
    Next
    GUICtrlSetData($idList, "")
    If $s <> "" Then GUICtrlSetData($idList, StringTrimRight($s, 1))
    If $iSel >= $n Then $iSel = $n - 1
    If $iSel < 0 Then $iSel = 0
    _GUICtrlListBox_SetCurSel($idList, $iSel)
EndFunc

; Gan phim moi cho mot hanh dong (tren ban lam viec); hoi neu trung voi hanh dong khac
Func _HK_TryAssign($iIdx, $sNew, $hParent)
    Local $sScope = $g_aHK[$iIdx][1]
    If $sNew <> "none" And _HK_IsReserved($sScope, $sNew) Then
        MsgBox(48, _T("Shortcuts"), _TF("The shortcut {1} is reserved and cannot be used.", _HK_Display($sNew)), 0, $hParent)
        Return False
    EndIf
    If $sNew <> "none" Then
        For $j = 0 To $g_iHKCount - 1
            If $j = $iIdx Or $g_aHK[$j][1] <> $sScope Then ContinueLoop
            If StringLower($g_aHKWork[$j]) = StringLower($sNew) Then
                If MsgBox(36, _T("Shortcuts"), _TF("The shortcut {1} is already used by ""{2}"". Move it to this action?", _HK_Display($sNew), _HK_ActionLabel($j)), 0, $hParent) <> 6 Then Return False
                $g_aHKWork[$j] = "none"
            EndIf
        Next
    EndIf
    $g_aHKWork[$iIdx] = $sNew
    Return True
EndFunc

; ---------- Bat phim khi nguoi dung nhan to hop phim ----------
Func _HK_VkDown($vk)
    Local $a = DllCall("user32.dll", "short", "GetAsyncKeyState", "int", $vk)
    If @error Or Not IsArray($a) Then Return False
    Return (BitAND($a[0], 0x8000) <> 0)
EndFunc

Func _HK_PressedKey()
    For $vk = 0x08 To 0xDE
        If $vk = 0x10 Or $vk = 0x11 Or $vk = 0x12 Or $vk = 0x14 Or $vk = 0x5B Or $vk = 0x5C Then ContinueLoop
        If $vk >= 0xA0 And $vk <= 0xA5 Then ContinueLoop
        If $vk = 0x90 Or $vk = 0x91 Or $vk = 0x5D Then ContinueLoop
        If _HK_VkDown($vk) Then Return $vk
    Next
    Return 0
EndFunc

Func _HK_VkToToken($vk)
    If $vk >= 0x41 And $vk <= 0x5A Then Return StringLower(Chr($vk))
    If $vk >= 0x30 And $vk <= 0x39 Then Return Chr($vk)
    If $vk >= 0x70 And $vk <= 0x87 Then Return "{F" & ($vk - 0x6F) & "}"
    If $vk >= 0x60 And $vk <= 0x69 Then Return "{NUMPAD" & ($vk - 0x60) & "}"
    Switch $vk
        Case 0x20
            Return "{SPACE}"
        Case 0x25
            Return "{LEFT}"
        Case 0x26
            Return "{UP}"
        Case 0x27
            Return "{RIGHT}"
        Case 0x28
            Return "{DOWN}"
        Case 0x24
            Return "{HOME}"
        Case 0x23
            Return "{END}"
        Case 0x21
            Return "{PGUP}"
        Case 0x22
            Return "{PGDN}"
        Case 0x2D
            Return "{INS}"
        Case 0x2E
            Return "{DEL}"
        Case 0x09
            Return "{TAB}"
        Case 0x0D
            Return "{ENTER}"
        Case 0x08
            Return "{BS}"
        Case 0xBA
            Return ";"
        Case 0xBB
            Return "="
        Case 0xBC
            Return ","
        Case 0xBD
            Return "-"
        Case 0xBE
            Return "."
        Case 0xBF
            Return "/"
        Case 0xC0
            Return "`"
        Case 0xDB
            Return "{[}"
        Case 0xDC
            Return "\"
        Case 0xDD
            Return "{]}"
        Case 0xDE
            Return "'"
    EndSwitch
    Return ""
EndFunc

; Mo hop thoi nho "Bam to hop phim..."; tra ve chuoi phim (vd "^+t") hoac "" neu huy (Esc)
Func _HK_Capture($hParent)
    Local $hGui = GUICreate(_T("Press a shortcut"), 380, 120, -1, -1, BitOR($WS_CAPTION, $WS_SYSMENU, $WS_POPUP), $WS_EX_TOPMOST, $hParent)
    GUISetBkColor($COLOR_BLUE)
    GUICtrlCreateLabel(_T("Press the key combination you want to use now. Press Esc to cancel."), 10, 15, 360, 60)
    GUICtrlSetColor(-1, 0xFFFFFF)
    GUISetState(@SW_SHOW, $hGui)
    _NVDA_Speak(_T("Press the key combination you want to use now. Press Esc to cancel."))
    Local $iT = TimerInit()
    While _HK_PressedKey() <> 0 And TimerDiff($iT) < 3000 ; wait until the key that opened this box is released
        GUIGetMsg()
        Sleep(20)
    WEnd
    Local $sResult = "", $iVk, $sTok, $nMsg
    While True
        $nMsg = GUIGetMsg()
        If $nMsg = $GUI_EVENT_CLOSE Then ExitLoop
        $iVk = _HK_PressedKey()
        If $iVk = 0x1B Then ExitLoop
        If $iVk <> 0 Then
            $sTok = _HK_VkToToken($iVk)
            If $sTok <> "" Then
                $sResult = _HK_Compose(_HK_VkDown(0x11), _HK_VkDown(0x12), _HK_VkDown(0x10), $sTok)
                ExitLoop
            EndIf
        EndIf
        Sleep(15)
    WEnd
    GUIDelete($hGui)
    $iT = TimerInit()
    While _HK_PressedKey() <> 0 And TimerDiff($iT) < 2000
        Sleep(20)
    WEnd
    Return $sResult
EndFunc

Func _HK_Compose($bCtrl, $bAlt, $bShift, $sTok)
    Return ($bCtrl ? "^" : "") & ($bAlt ? "!" : "") & ($bShift ? "+" : "") & $sTok
EndFunc

; Bang cac phim chon thu cong: [n][2] = (ten hien thi, token)
Func _HK_KeyTable()
    Local $aT[120][2], $n = 0
    For $c = 65 To 90
        $aT[$n][0] = Chr($c)
        $aT[$n][1] = StringLower(Chr($c))
        $n += 1
    Next
    For $c = 48 To 57
        $aT[$n][0] = Chr($c)
        $aT[$n][1] = Chr($c)
        $n += 1
    Next
    For $c = 1 To 12
        $aT[$n][0] = "F" & $c
        $aT[$n][1] = "{F" & $c & "}"
        $n += 1
    Next
    Local $aN = ["Left", "Right", "Up", "Down", "Home", "End", "Page Up", "Page Down", "Insert", "Delete", "Space", "Tab", "Enter", "Backspace", "Esc"]
    Local $aK = ["{LEFT}", "{RIGHT}", "{UP}", "{DOWN}", "{HOME}", "{END}", "{PGUP}", "{PGDN}", "{INS}", "{DEL}", "{SPACE}", "{TAB}", "{ENTER}", "{BS}", "{ESC}"]
    For $i = 0 To UBound($aN) - 1
        $aT[$n][0] = $aN[$i]
        $aT[$n][1] = $aK[$i]
        $n += 1
    Next
    Local $aP = [";", "=", ",", "-", ".", "/", "[", "]", "\", "'", "`"]
    Local $aPK = [";", "=", ",", "-", ".", "/", "{[}", "{]}", "\", "'", "`"]
    For $i = 0 To UBound($aP) - 1
        $aT[$n][0] = $aP[$i]
        $aT[$n][1] = $aPK[$i]
        $n += 1
    Next
    ReDim $aT[$n][2]
    Return $aT
EndFunc

; Hop thoai doi phim cho mot hanh dong. Tra ve chuoi phim moi, "none" (go bo) hoac "" (huy)
Func _HK_EditDialog($iIdx, $hParent)
    Local $aKeys = _HK_KeyTable()
    Local $sCur = $g_aHKWork[$iIdx]
    Local $hGui = GUICreate(_T("Change shortcut"), 400, 300, -1, -1, BitOR($WS_CAPTION, $WS_SYSMENU, $WS_POPUP), -1, $hParent)
    GUISetBkColor($COLOR_BLUE)
    GUICtrlCreateLabel(_TF("Action: {1}", _HK_ActionLabel($iIdx)), 10, 12, 380, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    GUICtrlSetFont(-1, 10, 800)
    Local $lblCur = GUICtrlCreateLabel(_TF("Current shortcut: {1}", _HK_Display($sCur)), 10, 38, 380, 20)
    GUICtrlSetColor(-1, 0xFFFF00)
    Local $btnCap = GUICtrlCreateButton(_T("Press keys to set..."), 10, 66, 380, 32)
    GUICtrlCreateLabel(_T("Or choose the keys yourself:"), 10, 108, 380, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $chkCtrl = GUICtrlCreateCheckbox(_T("Ctrl"), 10, 132, 60, 22)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $chkAlt = GUICtrlCreateCheckbox(_T("Alt"), 80, 132, 60, 22)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $chkShift = GUICtrlCreateCheckbox(_T("Shift"), 150, 132, 70, 22)
    GUICtrlSetColor(-1, 0xFFFFFF)
    GUICtrlCreateLabel(_T("Key:"), 230, 135, 40, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $cboKey = GUICtrlCreateCombo("", 270, 130, 120, 20, $CBS_DROPDOWNLIST)
    Local $sKeyList = ""
    For $i = 0 To UBound($aKeys) - 1
        $sKeyList &= $aKeys[$i][0] & "|"
    Next
    GUICtrlSetData($cboKey, StringTrimRight($sKeyList, 1))
    ; preselect from the current shortcut
    Local $sRest = ($sCur = "none") ? "" : $sCur
    While StringLen($sRest) > 1 And StringInStr("^!+", StringLeft($sRest, 1))
        Switch StringLeft($sRest, 1)
            Case "^"
                GUICtrlSetState($chkCtrl, $GUI_CHECKED)
            Case "!"
                GUICtrlSetState($chkAlt, $GUI_CHECKED)
            Case "+"
                GUICtrlSetState($chkShift, $GUI_CHECKED)
        EndSwitch
        $sRest = StringTrimLeft($sRest, 1)
    WEnd
    Local $iKeySel = 0
    For $i = 0 To UBound($aKeys) - 1
        If StringLower($aKeys[$i][1]) = StringLower($sRest) Then
            $iKeySel = $i
            ExitLoop
        EndIf
    Next
    _GUICtrlComboBox_SetCurSel($cboKey, $iKeySel)

    Local $btnOK = GUICtrlCreateButton(_T("OK"), 10, 180, 120, 32, $BS_DEFPUSHBUTTON)
    Local $btnRemove = GUICtrlCreateButton(_T("Remove shortcut"), 140, 180, 120, 32)
    Local $btnCancel = GUICtrlCreateButton(_T("Cancel"), 270, 180, 120, 32)
    GUICtrlCreateLabel(_T("A shortcut with no Ctrl or Alt, such as a single letter, works only when the window has no text box."), 10, 225, 380, 50)
    GUICtrlSetColor(-1, 0xFFFFFF)

    Local $hDummyEsc = GUICtrlCreateDummy()
    Local $aAccel[1][2] = [["{ESC}", $hDummyEsc]]
    GUISetAccelerators($aAccel, $hGui)
    GUISetState(@SW_SHOW, $hGui)
    _AllowUIPI($hGui)
    ControlFocus($hGui, "", $btnCap)

    Local $sResult = "", $nMsg, $sCap, $iSel
    While True
        $nMsg = _GuiMsg($hGui)
        Switch $nMsg
            Case $GUI_EVENT_CLOSE, $btnCancel, $hDummyEsc
                ExitLoop

            Case $btnCap
                $sCap = _HK_Capture($hGui)
                If $sCap <> "" Then
                    $sResult = $sCap
                    ExitLoop
                EndIf
                GUISwitch($hGui)
                ControlFocus($hGui, "", $btnCap)

            Case $btnRemove
                $sResult = "none"
                ExitLoop

            Case $btnOK
                $iSel = _GUICtrlComboBox_GetCurSel($cboKey)
                If $iSel >= 0 Then
                    $sResult = _HK_Compose(GUICtrlRead($chkCtrl) = $GUI_CHECKED, GUICtrlRead($chkAlt) = $GUI_CHECKED, GUICtrlRead($chkShift) = $GUI_CHECKED, $aKeys[$iSel][1])
                    ExitLoop
                EndIf
        EndSwitch
        Sleep(10)
    WEnd
    GUIDelete($hGui)
    Return $sResult
EndFunc

Func _HK_Init()
    _HK_Reg("play_pause", "player", "{SPACE}", "Play / Pause")
    _HK_Reg("seek_back", "player", "{LEFT}", "Rewind")
    _HK_Reg("seek_fwd", "player", "{RIGHT}", "Forward")
    _HK_Reg("seek_back_1m", "player", "!{LEFT}", "Rewind 1 minute")
    _HK_Reg("seek_fwd_1m", "player", "!{RIGHT}", "Forward 1 minute")
    _HK_Reg("vol_up", "player", "{UP}", "Volume up")
    _HK_Reg("vol_down", "player", "{DOWN}", "Volume down")
    _HK_Reg("pan_left", "player", "^{LEFT}", "Pan audio left")
    _HK_Reg("pan_right", "player", "^{RIGHT}", "Pan audio right")
    _HK_Reg("restart", "player", "{HOME}", "Restart from the beginning")
    _HK_Reg("near_end", "player", "{END}", "Jump near the end")
    _HK_Reg("slower", "player", "s", "Slower")
    _HK_Reg("normal_speed", "player", "d", "Normal speed")
    _HK_Reg("faster", "player", "f", "Faster")
    _HK_Reg("step_shorter", "player", "-", "Shorter seek step")
    _HK_Reg("step_longer", "player", "=", "Longer seek step")
    _HK_Reg("show_percent", "player", "p", "Show percentage played")
    _HK_Reg("goto_time", "player", "^g", "Go to a specific time")
    _HK_Reg("lyrics", "player", "^!l", "View lyrics")
    _HK_Reg("copy_title", "player", "c", "Copy the track title")
    _HK_Reg("eq_dialog", "player", "^e", "Open the equalizer")
    _HK_Reg("chapter_next", "player", "{PGDN}", "Next chapter")
    _HK_Reg("chapter_prev", "player", "{PGUP}", "Previous chapter")
    _HK_Reg("chapters", "player", "h", "List of chapters")
    _HK_Reg("voice", "player", "^+v", "Voice enhancement: Off / Light / Strong")
    _HK_Reg("file_info", "player", "i", "Show file information")
    _HK_Reg("next", "player", "n", "Next file / Auto-play on or off")
    _HK_Reg("prev", "player", "b", "Previous file")
    _HK_Reg("first_file", "player", "^{HOME}", "First file")
    _HK_Reg("last_file", "player", "^{END}", "Last file")
    _HK_Reg("elapsed", "player", "^t", "Elapsed time")
    _HK_Reg("total", "player", "^+t", "Total duration")
    _HK_Reg("remaining", "player", "^r", "Remaining time")
    _HK_Reg("repeat", "player", "r", "Turn repeat on or off")
    _HK_Reg("copy_link", "player", "^k", "Copy video link")
    _HK_Reg("copy_link_time", "player", "^c", "Copy video link at the current time")
    _HK_Reg("sel_start", "player", "{[}", "Set selection start")
    _HK_Reg("sel_end", "player", "{]}", "Set selection end")
    _HK_Reg("save_sel", "player", "^s", "Save the selection")
    _HK_Reg("open_browser", "player", "!b", "Open in browser")
    _HK_Reg("goto_channel", "player", "!g", "Go to channel")
    _HK_Reg("description", "player", "^+d", "Video description")
    _HK_Reg("comments", "player", "^+c", "Video comments")
    _HK_Reg("transcript", "player", "^!t", "Video transcript")
    _HK_Reg("queue_add", "player", "^q", "Add to play queue")
    _HK_Reg("queue_open", "player", "^+q", "Open the play queue")
    _HK_Reg("options_menu", "player", "!o", "Open the Options menu")
    _HK_Reg("force_next", "player", "+n", "Next video")
    _HK_Reg("force_prev", "player", "+b", "Previous video")
    _HK_Reg("cinema", "player", "^+e", "Cinema mode")
    _HK_Reg("close_player", "player", "{ESC}", "Close the player")
    _HK_Reg("exit_app", "player", "^w", "Exit the application")
    _HK_Reg("main_download", "main", "!d", "", "Download from link (Alt+D)")
    _HK_Reg("main_play", "main", "!p", "", "Play Video or Music Link (Alt+P)")
    _HK_Reg("main_direct", "main", "!l", "", "Play direct link (Alt+L)")
    _HK_Reg("main_search", "main", "!s", "", "Search Videos and Music (Alt+S)")
    _HK_Reg("main_collections", "main", "!c", "", "Your Collections (Alt+C)")
    _HK_Reg("main_audio", "main", "!u", "", "Listen to Audio File (Alt+U)")
    _HK_Reg("main_recent_files", "main", "!e", "", "Recent Files (Alt+E)")
    _HK_Reg("main_recent_folders", "main", "!o", "", "Recent Folders (Alt+O)")
    _HK_Reg("main_radio", "main", "!r", "", "Radio Player (Alt+R)")
    _HK_Reg("main_radio_fav", "main", "!v", "", "Favorite Stations (Alt+V)")
    _HK_Reg("main_podcasts", "main", "!k", "", "Podcasts (Alt+K)")
    _HK_Reg("main_yt_subs", "main", "!y", "", "YouTube Subscriptions (Alt+Y)")
    _HK_Reg("main_queue", "main", "!q", "", "Play Queue (Alt+Q)")
    _HK_Reg("main_dq", "main", "!z", "", "Download Queue (Alt+Z)")
    _HK_Reg("main_fav", "main", "!f", "", "Favorites (Alt+F)")
    _HK_Reg("main_history", "main", "!w", "", "Watch History (Alt+W)")
    _HK_Reg("main_settings", "main", "^+s", "", "Settings... (Ctrl+Shift+S)")
    _HK_Reg("main_readme", "main", "{F1}", "", "Readme... (F1)")
    _HK_Reg("main_changelog", "main", "{F2}", "View changelog", "")
    _HK_Reg("main_update_app", "main", "^+u", "Check for updates", "")
    _HK_Reg("main_update_ytdlp", "main", "^+y", "Check for yt-dlp updates", "")
    _HK_Reg("main_exit", "main", "^w", "Exit the application", "")
EndFunc

; Gan ID dummy cua player (tao lai moi lan mo cua so player)
Func _HK_SetPlayerHandles()
    _HK_SetHandle("play_pause", $hDummySpace)
    _HK_SetHandle("seek_back", $hDummyLeft)
    _HK_SetHandle("seek_fwd", $hDummyRight)
    _HK_SetHandle("seek_back_1m", $hDummyAltLeft)
    _HK_SetHandle("seek_fwd_1m", $hDummyAltRight)
    _HK_SetHandle("vol_up", $hDummyUp)
    _HK_SetHandle("vol_down", $hDummyDown)
    _HK_SetHandle("pan_left", $hDummyCtrlLeft)
    _HK_SetHandle("pan_right", $hDummyCtrlRight)
    _HK_SetHandle("restart", $hDummyHome)
    _HK_SetHandle("near_end", $hDummyEnd)
    _HK_SetHandle("slower", $hDummyS)
    _HK_SetHandle("normal_speed", $hDummyD)
    _HK_SetHandle("faster", $hDummyF)
    _HK_SetHandle("step_shorter", $hDummyMinus)
    _HK_SetHandle("step_longer", $hDummyEqual)
    _HK_SetHandle("show_percent", $hDummyP)
    _HK_SetHandle("goto_time", $hDummyG)
    _HK_SetHandle("lyrics", $hDummyCtrlAltL)
    _HK_SetHandle("copy_title", $hDummyC)
    _HK_SetHandle("eq_dialog", $hDummyEq)
    _HK_SetHandle("chapter_next", $hDummyChapNext)
    _HK_SetHandle("chapter_prev", $hDummyChapPrev)
    _HK_SetHandle("chapters", $hDummyChapList)
    _HK_SetHandle("voice", $hDummyVoice)
    _HK_SetHandle("file_info", $hDummyI)
    _HK_SetHandle("next", $hDummyN)
    _HK_SetHandle("prev", $hDummyB)
    _HK_SetHandle("first_file", $hDummyCtrlHome)
    _HK_SetHandle("last_file", $hDummyCtrlEnd)
    _HK_SetHandle("elapsed", $hDummyCtrlT)
    _HK_SetHandle("total", $hDummyCtrlShiftT)
    _HK_SetHandle("remaining", $hDummyRemaining)
    _HK_SetHandle("repeat", $hDummyR)
    _HK_SetHandle("copy_link", $hDummyCtrlK)
    _HK_SetHandle("copy_link_time", $hDummyCtrlC)
    _HK_SetHandle("sel_start", $hDummyBracketLeft)
    _HK_SetHandle("sel_end", $hDummyBracketRight)
    _HK_SetHandle("save_sel", $hDummyCtrlS)
    _HK_SetHandle("open_browser", $hDummyAltB)
    _HK_SetHandle("goto_channel", $hDummyAltG)
    _HK_SetHandle("description", $hDummyCtrlShiftD)
    _HK_SetHandle("comments", $hDummyCtrlShiftC)
    _HK_SetHandle("transcript", $hDummyCtrlAltT)
    _HK_SetHandle("queue_add", $hDummyCtrlQ)
    _HK_SetHandle("queue_open", $hDummyCtrlShiftQ)
    _HK_SetHandle("options_menu", $hDummyAltO)
    _HK_SetHandle("force_next", $hDummyShiftN)
    _HK_SetHandle("force_prev", $hDummyShiftB)
    _HK_SetHandle("cinema", $hDummyCtrlShiftE)
    _HK_SetHandle("close_player", $hDummyEsc)
    _HK_SetHandle("exit_app", $hDummyCtrlW)
EndFunc

Func contribute()
    Local $congui = GuiCreate(_T("contribute"), 700, 700)
    GuiSetBkColor($COLOR_RED)
    Local $txtContribute = FileExists(@ScriptDir & "\docs\contribute.txt") ? FileRead(@ScriptDir & "\docs\contribute.txt") : "VDH Media Center"
    Local $sContent = _StripMarkdown($txtContribute)
    Local $conedit = GUICtrlCreateEdit($sContent, 20, 20, 650, 600, BitOR($ES_AUTOVSCROLL, $ES_READONLY, $WS_VSCROLL, $WS_TABSTOP))
    Local $btnClose = GUICtrlCreateButton(_T("&Close"), 300, 630, 100, 30, $WS_TABSTOP)
    GuiSetState(@SW_SHOW, $congui)
    While 1
        Switch _GuiMsg($congui)
            Case $GUI_EVENT_CLOSE, $btnClose
                GuiDelete($congui)
                ExitLoop
        EndSwitch
    WEnd
EndFunc

Func _IsUrlMatchTab($sUrl, $iTab)
    Local $sPattern = ""
    Switch $iTab
        Case 0 ; YouTube
            Return StringInStr($sUrl, "youtube.com") Or StringInStr($sUrl, "youtu.be")
        Case 1 ; Facebook
            Return StringInStr($sUrl, "facebook.com") Or StringInStr($sUrl, "fb.watch")
        Case 2 ; TikTok
            Return StringInStr($sUrl, "tiktok.com")
        Case 3 ; Instagram
            Return StringInStr($sUrl, "instagram.com")
        Case 4 ; SoundCloud
            Return StringInStr($sUrl, "soundcloud.com")
    EndSwitch
    Return False
EndFunc


; ======================================================================
;  VERSION 3.3 - HELPERS FOR LINKS (YouTube id or full link of another site)
; ======================================================================
Func _IsWebLink($s)
    Return StringRegExp($s, "^(?i)https?://")
EndFunc

; SoundCloud links (soundcloud.com, m.soundcloud.com, on.soundcloud.com, snd.sc)
Func _IsSoundCloudLink($s)
    Return StringRegExp($s, "(?i)^https?://([a-z0-9-]+\.)?(soundcloud\.com|snd\.sc)(/|$|\?)")
EndFunc

; "https://soundcloud.com/artist/some-track" -> "https://soundcloud.com/artist" (page of the artist)
Func _SC_ArtistUrl($sUrl)
    Local $a = StringRegExp($sUrl, "(?i)^(https?://(?:[a-z0-9-]+\.)?soundcloud\.com/[^/?#]+)", 3)
    If IsArray($a) Then Return $a[0]
    Return $sUrl
EndFunc

; Seconds -> "m:ss" or "h:mm:ss" (the form SoundCloud understands in #t=)
Func _SC_TimeFragment($iSec)
    $iSec = Int($iSec)
    If $iSec < 0 Then $iSec = 0
    Local $h = Int($iSec / 3600), $m = Int(Mod($iSec, 3600) / 60), $s = Mod($iSec, 60)
    If $h > 0 Then Return $h & ":" & StringFormat("%02d", $m) & ":" & StringFormat("%02d", $s)
    Return $m & ":" & StringFormat("%02d", $s)
EndFunc

; Items from other sites (SoundCloud...) keep their full link as the "id"
Func _VideoLink($sID)
    If _IsWebLink($sID) Then Return $sID
    Return "https://www.youtube.com/watch?v=" & $sID
EndFunc

Func _VideoShortLink($sID)
    If _IsWebLink($sID) Then Return $sID
    Return "https://youtu.be/" & $sID
EndFunc

; ======================================================================
;  CHAPTERS (version 3.3)
;  YouTube and other sites: yt-dlp ("%(chapters)j"). Local files: ffmpeg (-i prints the chapters).
;  Podcasts: chapters file of the feed (Podcasting 2.0) or time stamps in the show notes.
;  Page Up / Page Down = previous / next chapter, H = list of chapters.
; ======================================================================
Func _Chap_Reset()
    If $g_iChapPid <> 0 Then
        If ProcessExists($g_iChapPid) Then ProcessClose($g_iChapPid)
    EndIf
    $g_iChapPid = 0
    $g_iChapMode = 0
    $g_sChapOut = ""
    $g_iChapCount = 0
    $g_iChapCur = -1
    ReDim $g_aChapT[1]
    ReDim $g_aChapN[1]
EndFunc

Func _Chap_Set(ByRef $aT, ByRef $aN, $iCount)
    If $iCount < 1 Then Return
    ReDim $g_aChapT[$iCount]
    ReDim $g_aChapN[$iCount]
    For $i = 0 To $iCount - 1
        $g_aChapT[$i] = $aT[$i]
        $g_aChapN[$i] = $aN[$i]
    Next
    $g_iChapCount = $iCount
    $g_iChapCur = -1
EndFunc

Func _Chap_StartOnline($sID)
    _Chap_Reset()
    If $sID = "" Then Return
    Local $sCmd = @ComSpec & ' /c "' & $YT_DLP_EXE & ' --skip-download --no-playlist --no-warnings --socket-timeout 10 --print "%(chapters)j" -- "' & $sID & '""'
    $g_iChapPid = Run($sCmd, @ScriptDir, @SW_HIDE, $STDOUT_CHILD)
    If $g_iChapPid = 0 Then Return
    $g_iChapMode = 1
    $g_hChapTimer = TimerInit()
EndFunc

Func _Chap_StartFile($sPath)
    _Chap_Reset()
    If $sPath = "" Or Not FileExists($sPath) Then Return
    If Not FileExists($FFMPEG_PATH) Then Return
    $g_iChapPid = Run('"' & $FFMPEG_PATH & '" -hide_banner -i "' & $sPath & '"', @ScriptDir, @SW_HIDE, $STDERR_CHILD)
    If $g_iChapPid = 0 Then Return
    $g_iChapMode = 2
    $g_hChapTimer = TimerInit()
EndFunc

; Reads the output of the background process; when it has finished the chapters are parsed
Func _Chap_Poll()
    If $g_iChapPid = 0 Then Return
    If $g_iChapMode = 2 Then
        $g_sChapOut &= BinaryToString(StderrRead($g_iChapPid, False, True), 4)
    Else
        $g_sChapOut &= BinaryToString(StdoutRead($g_iChapPid, False, True), 4)
    EndIf
    If ProcessExists($g_iChapPid) Then
        If TimerDiff($g_hChapTimer) > 45000 Then
            ProcessClose($g_iChapPid)
            $g_iChapPid = 0
            $g_iChapMode = 0
            $g_sChapOut = ""
        EndIf
        Return
    EndIf
    If $g_iChapMode = 2 Then
        $g_sChapOut &= BinaryToString(StderrRead($g_iChapPid, False, True), 4)
    Else
        $g_sChapOut &= BinaryToString(StdoutRead($g_iChapPid, False, True), 4)
    EndIf
    _Chap_Parse()
    $g_iChapPid = 0
    $g_iChapMode = 0
    $g_sChapOut = ""
    If $g_iChapCount > 0 Then _ReportStatus(_TF("{1} chapters available. Press {2} to list them.", $g_iChapCount, _HK_Display(_HK_Key("chapters"))))
EndFunc

Func _Chap_Parse()
    Local $aT[1], $aN[1], $n = 0, $aObj, $aM, $a, $i
    If $g_iChapMode = 1 Then
        $aObj = StringRegExp($g_sChapOut, '\{[^{}]*\}', 3)
        If @error Or Not IsArray($aObj) Then Return
        ReDim $aT[UBound($aObj)]
        ReDim $aN[UBound($aObj)]
        For $i = 0 To UBound($aObj) - 1
            $a = StringRegExp($aObj[$i], '"start_time"\s*:\s*(-?[0-9.]+)', 1)
            If @error Or Not IsArray($a) Then ContinueLoop
            $aT[$n] = Number($a[0])
            $aN[$n] = StringStripWS(_Json_Str($aObj[$i], "title"), 7)
            If $aN[$n] = "" Then $aN[$n] = _TF("Chapter {1}", $n + 1)
            $n += 1
        Next
    ElseIf $g_iChapMode = 2 Then
        $aM = StringRegExp($g_sChapOut, 'Chapter #\d+:\d+: start ([0-9.]+), end [0-9.]+\r?\n\s*Metadata:\r?\n\s*title\s*:\s*([^\r\n]*)', 3)
        If @error Or Not IsArray($aM) Then Return
        ReDim $aT[Int(UBound($aM) / 2)]
        ReDim $aN[Int(UBound($aM) / 2)]
        For $i = 0 To UBound($aM) - 2 Step 2
            $aT[$n] = Number($aM[$i])
            $aN[$n] = StringStripWS($aM[$i + 1], 7)
            If $aN[$n] = "" Then $aN[$n] = _TF("Chapter {1}", $n + 1)
            $n += 1
        Next
    EndIf
    If $n < 1 Then Return
    ReDim $aT[$n]
    ReDim $aN[$n]
    _Chap_Set($aT, $aN, $n)
EndFunc

; Chapters from lines such as "12:30 Title" in a description / show notes. Returns the number of chapters (0 = none)
Func _Chap_FromText($sText, ByRef $aT, ByRef $aN)
    Local $aL = StringSplit(StringReplace($sText, @CR, ""), @LF, 2)
    Local $nOut = 0, $m, $p, $fT, $fLast = -1, $i, $k
    ReDim $aT[UBound($aL) + 1]
    ReDim $aN[UBound($aL) + 1]
    For $i = 0 To UBound($aL) - 1
        $m = StringRegExp(StringStripWS($aL[$i], 3), '^[\(\[]?((?:\d{1,2}:)?\d{1,2}:\d{2})[\)\]]?\s*[-:.]*\s*(.+)$', 1)
        If @error Or Not IsArray($m) Then ContinueLoop
        $p = StringSplit($m[0], ":", 2)
        $fT = 0
        For $k = 0 To UBound($p) - 1
            $fT = $fT * 60 + Int($p[$k])
        Next
        If $fT <= $fLast Then ContinueLoop
        $fLast = $fT
        $aT[$nOut] = $fT
        $aN[$nOut] = StringStripWS($m[1], 7)
        $nOut += 1
    Next
    If $nOut < 3 Then Return 0
    Return $nOut
EndFunc

Func _Chap_IndexAt($fSec)
    Local $iIdx = -1
    For $i = 0 To $g_iChapCount - 1
        If $g_aChapT[$i] <= $fSec + 0.3 Then
            $iIdx = $i
        Else
            ExitLoop
        EndIf
    Next
    Return $iIdx
EndFunc

Func _Chap_Label($i)
    Return _TF("Chapter {1} of {2}: {3}", $i + 1, $g_iChapCount, $g_aChapN[$i])
EndFunc

Func _Chap_Jump($iIdx)
    If $iIdx < 0 Or $iIdx >= $g_iChapCount Then Return
    _VLC_Direct_SetTime(Int($g_aChapT[$iIdx] * 1000))
    $g_iChapCur = $iIdx
    _ReportStatus(_Chap_Label($iIdx))
EndFunc

Func _Chap_NoneText()
    If $g_iChapPid <> 0 Then Return _T("Chapters are still loading...")
    Return _T("No chapters in this video.")
EndFunc

; $iDir = 1: next chapter. $iDir = -1: start of this chapter (after 3 seconds into it) or the previous chapter
Func _Chap_Step($iDir)
    If $g_iChapCount < 1 Then
        _ReportStatus(_Chap_NoneText())
        Return
    EndIf
    Local $fNow = _VLC_Direct_GetTime() / 1000
    Local $iCur = _Chap_IndexAt($fNow)
    Local $iTarget
    If $iDir > 0 Then
        $iTarget = $iCur + 1
        If $iTarget >= $g_iChapCount Then
            _ReportStatus(_T("This is the last chapter."))
            Return
        EndIf
    Else
        If $iCur >= 0 And $fNow - $g_aChapT[$iCur] > 3 Then
            $iTarget = $iCur
        Else
            $iTarget = $iCur - 1
        EndIf
        If $iTarget < 0 Then $iTarget = 0
    EndIf
    _Chap_Jump($iTarget)
EndFunc

; Called twice a second by the player: loads the chapters and announces a new chapter when it starts
Func _Chap_Tick()
    _Chap_Poll()
    If $g_iChapCount < 1 Or Not $g_bAnnounceChapters Then Return
    If _VLC_Direct_GetState() <> 3 Then Return
    Local $iIdx = _Chap_IndexAt(_VLC_Direct_GetTime() / 1000)
    If $iIdx = $g_iChapCur Then Return
    Local $bFirst = ($g_iChapCur = -1)
    $g_iChapCur = $iIdx
    If $iIdx >= 0 And Not $bFirst Then _ReportStatus(_Chap_Label($iIdx))
EndFunc

Func _ShowChaptersDialog($hParent = 0)
    If $g_iChapCount < 1 Then
        _ReportStatus(_Chap_NoneText())
        Return
    EndIf
    Local $hGui = GUICreate(_T("Chapters"), 420, 350, -1, -1, BitOR($WS_CAPTION, $WS_SYSMENU), $WS_EX_TOPMOST, IsHWnd($hParent) ? $hParent : 0)
    GUISetBkColor($COLOR_BLUE)
    GUICtrlCreateLabel(_T("Chapters (press Enter to jump to the chapter):"), 10, 10, 400, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $lst = GUICtrlCreateList("", 10, 35, 400, 250, BitOR($LBS_NOTIFY, $WS_VSCROLL, $WS_BORDER))
    Local $btnGo = GUICtrlCreateButton(_T("&Jump"), 80, 300, 110, 32, $BS_DEFPUSHBUTTON)
    Local $btnClose = GUICtrlCreateButton(_T("&Close"), 230, 300, 110, 32)
    Local $s = "", $i
    For $i = 0 To $g_iChapCount - 1
        $s &= ($i + 1) & ". " & _FormatTime($g_aChapT[$i]) & "  " & StringReplace($g_aChapN[$i], "|", "/") & "|"
    Next
    GUICtrlSetData($lst, StringTrimRight($s, 1))
    Local $iCur = _Chap_IndexAt(_VLC_Direct_GetTime() / 1000)
    If $iCur < 0 Then $iCur = 0
    _GUICtrlListBox_SetCurSel($lst, $iCur)
    Local $hDummyEsc = GUICtrlCreateDummy()
    Local $aAcc[1][2] = [["{ESC}", $hDummyEsc]]
    GUISetAccelerators($aAcc, $hGui)
    GUISetState(@SW_SHOW, $hGui)
    _AllowUIPI($hGui)
    ControlFocus($hGui, "", $lst)
    Local $nMsg, $iSel = -1
    While 1
        $nMsg = _GuiMsg($hGui)
        Switch $nMsg
            Case $GUI_EVENT_CLOSE, $btnClose, $hDummyEsc
                ExitLoop
            Case $btnGo
                $iSel = _GUICtrlListBox_GetCurSel($lst)
                ExitLoop
        EndSwitch
        Sleep(10)
    WEnd
    GUIDelete($hGui)
    If IsHWnd($hParent) Then
        GUISwitch($hParent)
        WinActivate($hParent)
    EndIf
    If $iSel >= 0 Then _Chap_Jump($iSel)
EndFunc

; ======================================================================
;  VOICE ENHANCEMENT (version 3.3)
;  Light / Strong: VLC "compressor" filter (evens out loud and quiet speech) + an equalizer curve that
;  lifts the speech range (used when the equalizer in Settings is Off). Settings > Player, or Ctrl+Shift+V in the player.
; ======================================================================
Func _Voice_Name($iMode)
    Switch $iMode
        Case 1
            Return _T("Light")
        Case 2
            Return _T("Strong")
    EndSwitch
    Return _T("Off")
EndFunc

Func _Voice_AddMediaOptions($pMedia)
    If $g_iVoiceMode < 1 Then Return
    Local $sThr = "-16", $sRatio = "4", $sGain = "6"
    If $g_iVoiceMode = 2 Then
        $sThr = "-22"
        $sRatio = "8"
        $sGain = "9"
    EndIf
    DllCall($hVLC_Dll, "none:cdecl", "libvlc_media_add_option", "ptr", $pMedia, "str", ":compressor-threshold=" & $sThr)
    DllCall($hVLC_Dll, "none:cdecl", "libvlc_media_add_option", "ptr", $pMedia, "str", ":compressor-ratio=" & $sRatio)
    DllCall($hVLC_Dll, "none:cdecl", "libvlc_media_add_option", "ptr", $pMedia, "str", ":compressor-makeup-gain=" & $sGain)
EndFunc

Func _Voice_FillEq($pEq)
    Local $aBands[10] = [-6, -3, 0, 1, 3, 4, 2, -1, -3, -4]
    If $g_iVoiceMode = 2 Then
        Local $aStrong[10] = [-9, -5, -1, 1, 4, 6, 3, -1, -4, -6]
        $aBands = $aStrong
    EndIf
    DllCall($hVLC_Dll, "int:cdecl", "libvlc_audio_equalizer_set_preamp", "ptr", $pEq, "float", -2)
    For $i = 0 To 9
        DllCall($hVLC_Dll, "int:cdecl", "libvlc_audio_equalizer_set_amp_at_index", "ptr", $pEq, "float", $aBands[$i], "uint", $i)
    Next
EndFunc

Func _Voice_Cycle()
    $g_iVoiceMode += 1
    If $g_iVoiceMode > 2 Then $g_iVoiceMode = 0
    IniWrite($CONFIG_FILE, "Settings", "VoiceEnhance", String($g_iVoiceMode))
    _VLC_ApplyEqualizer()
EndFunc

; The compressor is a media option: reopen the stream at the same position so the change is heard at once
Func _Voice_Restart($sPlayUrl, $bFile)
    Local $iPos = _VLC_Direct_GetTime()
    If $bFile Then
        _VLC_Direct_Play(_PathToFileURI($sPlayUrl))
    Else
        _VLC_Direct_Play($sPlayUrl)
    EndIf
    Sleep(200)
    _VLC_Direct_SetVolume($g_iAppVolume)
    _VLC_Direct_SetRate($g_fPitch)
    Local $i = 0
    While $i < 50
        If _VLC_Direct_GetState() >= 3 Then ExitLoop
        Sleep(100)
        $i += 1
    WEnd
    If $iPos > 0 Then _VLC_Direct_SetTime($iPos)
    _VLC_ApplyEqualizer()
    _VLC_ApplyStereoMode()
EndFunc


; ======================================================================
;  PODCASTS (version 3.3)
;  Main window > Podcasts (Alt+K): search (Apple podcast directory), paste an RSS link, My subscriptions, New episodes.
;  Episodes play in the normal player (speed, seek, Sleep Timer, chapters...) and each episode remembers its position.
; ======================================================================
Func _Pod_Clean($s)
    $s = StringReplace($s, "|", "/")
    $s = StringReplace($s, @CRLF, " ")
    $s = StringReplace($s, @LF, " ")
    $s = StringReplace($s, @CR, " ")
    Return StringStripWS($s, 7)
EndFunc

Func _Xml_Text($s)
    $s = StringRegExpReplace($s, '(?s)<!\[CDATA\[(.*?)\]\]>', '\1')
    $s = StringReplace($s, "&lt;", "<")
    $s = StringReplace($s, "&gt;", ">")
    $s = StringRegExpReplace($s, '(?i)<br\s*/?>|</p>|</li>|</div>', @LF)
    $s = StringRegExpReplace($s, '(?s)<[^>]*>', '')
    $s = StringReplace($s, "&quot;", '"')
    $s = StringReplace($s, "&apos;", "'")
    $s = StringReplace($s, "&nbsp;", " ")
    Local $a = StringRegExp($s, '&#(\d+);', 3), $i
    If IsArray($a) Then
        For $i = 0 To UBound($a) - 1
            $s = StringReplace($s, "&#" & $a[$i] & ";", ChrW(Int($a[$i])))
        Next
    EndIf
    $a = StringRegExp($s, '&#[xX]([0-9A-Fa-f]+);', 3)
    If IsArray($a) Then
        For $i = 0 To UBound($a) - 1
            $s = StringRegExpReplace($s, '&#[xX]' & $a[$i] & ';', ChrW(Dec($a[$i])))
        Next
    EndIf
    $s = StringReplace($s, "&amp;", "&")
    Return $s
EndFunc

Func _Pod_Http($sUrl, $iRecvTimeout = 30000)
    Local $oOldErr = ObjEvent("AutoIt.Error", "_Radio_ComErr")
    Local $oHTTP = ObjCreate("WinHttp.WinHttpRequest.5.1")
    If Not IsObj($oHTTP) Then Return ""
    $oHTTP.SetTimeouts(5000, 5000, 10000, $iRecvTimeout)
    $oHTTP.Open("GET", $sUrl, False)
    $oHTTP.SetRequestHeader("User-Agent", "Mozilla/5.0 VDHMediaCenter/" & $version)
    $oHTTP.Send()
    If @error Then Return ""
    If $oHTTP.Status <> 200 Then Return ""
    Return BinaryToString($oHTTP.ResponseBody, 4)
EndFunc

Func _Pod_ParseDur($s)
    $s = StringStripWS($s, 3)
    If $s = "" Then Return 0
    If StringRegExp($s, '^\d+$') Then Return Int($s)
    Local $p = StringSplit($s, ":", 2), $t = 0, $i
    For $i = 0 To UBound($p) - 1
        $t = $t * 60 + Int($p[$i])
    Next
    Return $t
EndFunc

; Returns [n][9]: 0 title, 1 audio link, 2 date, 3 duration (s), 4 key, 5 chapters file link, 6 show notes, 7 podcast name, 8 feed link. 0 = not a podcast feed
Func _Pod_ParseFeed($sXml, ByRef $sTitle, ByRef $sAuthor)
    $sTitle = ""
    $sAuthor = ""
    If StringLen($sXml) < 20 Then Return 0
    Local $iFirst = StringInStr($sXml, "<item")
    Local $sHead = $sXml
    If $iFirst > 0 Then $sHead = StringLeft($sXml, $iFirst - 1)
    Local $a = StringRegExp($sHead, '(?is)<title[^>]*>(.*?)</title>', 1)
    If IsArray($a) Then $sTitle = _Pod_Clean(_Xml_Text($a[0]))
    $a = StringRegExp($sHead, '(?is)<itunes:author[^>]*>(.*?)</itunes:author>', 1)
    If IsArray($a) Then $sAuthor = _Pod_Clean(_Xml_Text($a[0]))
    Local $aItems = StringRegExp($sXml, '(?is)<item[\s>].*?</item>', 3)
    If @error Or Not IsArray($aItems) Then Return 0
    Local $nMax = UBound($aItems)
    If $nMax > 300 Then $nMax = 300
    Local $aEp[$nMax][9], $n = 0, $i, $k, $sItem, $sKey, $sNotes
    Local $aNames[3] = ["content:encoded", "description", "itunes:summary"]
    For $i = 0 To $nMax - 1
        $sItem = $aItems[$i]
        $a = StringRegExp($sItem, '(?is)<enclosure[^>]*?\burl\s*=\s*["'']([^"'']+)["'']', 1)
        If Not IsArray($a) Then ContinueLoop
        $aEp[$n][1] = StringStripWS(_Xml_Text($a[0]), 3)
        $a = StringRegExp($sItem, '(?is)<title[^>]*>(.*?)</title>', 1)
        If IsArray($a) Then $aEp[$n][0] = _Pod_Clean(_Xml_Text($a[0]))
        If $aEp[$n][0] = "" Then $aEp[$n][0] = _TF("Episode {1}", $n + 1)
        $a = StringRegExp($sItem, '(?is)<pubDate[^>]*>(.*?)</pubDate>', 1)
        If IsArray($a) Then
            $a = StringRegExp($a[0], '(\d{1,2}\s+[A-Za-z]{3}\s+\d{4})', 1)
            If IsArray($a) Then $aEp[$n][2] = $a[0]
        EndIf
        $a = StringRegExp($sItem, '(?is)<itunes:duration[^>]*>(.*?)</itunes:duration>', 1)
        If IsArray($a) Then $aEp[$n][3] = _Pod_ParseDur($a[0])
        $sKey = ""
        $a = StringRegExp($sItem, '(?is)<guid[^>]*>(.*?)</guid>', 1)
        If IsArray($a) Then $sKey = _Pod_Clean(_Xml_Text($a[0]))
        If $sKey = "" Then $sKey = _Pod_Clean($aEp[$n][1])
        $aEp[$n][4] = $sKey
        $a = StringRegExp($sItem, '(?is)<podcast:chapters[^>]*?\burl\s*=\s*["'']([^"'']+)["'']', 1)
        If IsArray($a) Then $aEp[$n][5] = StringStripWS(_Xml_Text($a[0]), 3)
        $sNotes = ""
        For $k = 0 To 2
            $a = StringRegExp($sItem, '(?is)<' & $aNames[$k] & '[^>]*>(.*?)</' & $aNames[$k] & '>', 1)
            If IsArray($a) Then
                If StringLen($a[0]) > StringLen($sNotes) Then $sNotes = $a[0]
            EndIf
        Next
        $aEp[$n][6] = StringLeft(StringStripWS(_Xml_Text($sNotes), 4), 6000)
        $n += 1
    Next
    If $n = 0 Then Return 0
    ReDim $aEp[$n][9]
    Return $aEp
EndFunc

; ---- subscriptions: podcasts.dat, one line per podcast: feed|name|author|key of the newest episode already seen ----
Func _Pod_SubLoad()
    Local $a = _RF_Read($PODCASTS_FILE)
    Local $n = UBound($a)
    If $n = 0 Then Return 0
    Local $aOut[$n][4], $p, $k = 0, $i
    For $i = 0 To $n - 1
        $p = StringSplit($a[$i], "|", 2)
        If UBound($p) < 2 Then ContinueLoop
        $aOut[$k][0] = $p[0]
        $aOut[$k][1] = $p[1]
        $aOut[$k][2] = ""
        $aOut[$k][3] = ""
        If UBound($p) >= 3 Then $aOut[$k][2] = $p[2]
        If UBound($p) >= 4 Then $aOut[$k][3] = $p[3]
        $k += 1
    Next
    If $k = 0 Then Return 0
    ReDim $aOut[$k][4]
    Return $aOut
EndFunc

Func _Pod_SubSave(ByRef $aSub, $n)
    Local $aLines[$n + 1], $k = 0, $i
    For $i = 0 To $n - 1
        $aLines[$k] = $aSub[$i][0] & "|" & $aSub[$i][1] & "|" & $aSub[$i][2] & "|" & $aSub[$i][3]
        $k += 1
    Next
    ReDim $aLines[$k]
    Return _RF_Write($PODCASTS_FILE, $aLines)
EndFunc

Func _Pod_IsSubscribed($sFeed)
    Local $aSub = _Pod_SubLoad()
    If Not IsArray($aSub) Then Return False
    For $i = 0 To UBound($aSub) - 1
        If StringLower($aSub[$i][0]) = StringLower($sFeed) Then Return True
    Next
    Return False
EndFunc

; 1 = subscribed, 0 = already subscribed, -1 = could not save
Func _Pod_Subscribe($sFeed, $sTitle, $sAuthor, $sSeen)
    Local $aSub = _Pod_SubLoad()
    Local $n = 0, $i, $j
    If IsArray($aSub) Then $n = UBound($aSub)
    For $i = 0 To $n - 1
        If StringLower($aSub[$i][0]) = StringLower($sFeed) Then Return 0
    Next
    Local $aNew[$n + 1][4]
    For $i = 0 To $n - 1
        For $j = 0 To 3
            $aNew[$i][$j] = $aSub[$i][$j]
        Next
    Next
    $aNew[$n][0] = $sFeed
    $aNew[$n][1] = _Pod_Clean($sTitle)
    $aNew[$n][2] = _Pod_Clean($sAuthor)
    $aNew[$n][3] = _Pod_Clean($sSeen)
    If _Pod_SubSave($aNew, $n + 1) Then Return 1
    Return -1
EndFunc

Func _Pod_Unsubscribe($sFeed)
    Local $aSub = _Pod_SubLoad()
    If Not IsArray($aSub) Then Return False
    Local $n = UBound($aSub), $k = 0, $i, $j
    Local $aNew[$n][4]
    For $i = 0 To $n - 1
        If StringLower($aSub[$i][0]) = StringLower($sFeed) Then ContinueLoop
        For $j = 0 To 3
            $aNew[$k][$j] = $aSub[$i][$j]
        Next
        $k += 1
    Next
    Return _Pod_SubSave($aNew, $k)
EndFunc

Func _Pod_SetSeen($sFeed, $sKey)
    Local $aSub = _Pod_SubLoad()
    If Not IsArray($aSub) Then Return
    Local $n = UBound($aSub), $bChanged = False, $sK = _Pod_Clean($sKey)
    For $i = 0 To $n - 1
        If StringLower($aSub[$i][0]) = StringLower($sFeed) And $aSub[$i][3] <> $sK Then
            $aSub[$i][3] = $sK
            $bChanged = True
        EndIf
    Next
    If $bChanged Then _Pod_SubSave($aSub, $n)
EndFunc

; Number of episodes newer than the newest one seen before (feeds list the newest episode first)
Func _Pod_NewCount(ByRef $aEp, $iCount, $sSeenKey)
    If $sSeenKey = "" Then Return 0
    Local $sK = StringLower($sSeenKey)
    For $i = 0 To $iCount - 1
        If StringLower($aEp[$i][4]) = $sK Then Return $i
    Next
    Return 0
EndFunc

; ---- played episodes: podcast_played.dat (one key per line) ----
Func _Pod_PlayedSet()
    Local $a = _RF_Read($PODCAST_PLAYED_FILE)
    Local $s = @LF
    For $i = 0 To UBound($a) - 1
        $s &= StringLower($a[$i]) & @LF
    Next
    Return $s
EndFunc

Func _Pod_MarkPlayed($sKey, $bPlayed)
    Local $a = _RF_Read($PODCAST_PLAYED_FILE)
    Local $n = UBound($a), $sK = StringLower($sKey), $i, $k = 0
    Local $aOut[$n + 1]
    For $i = 0 To $n - 1
        If StringLower($a[$i]) = $sK Then ContinueLoop
        $aOut[$k] = $a[$i]
        $k += 1
    Next
    If $bPlayed Then
        $aOut[$k] = $sKey
        $k += 1
    Else
        _LocalPos_Clear("pod:" & $sKey)
    EndIf
    Local $iFrom = 0
    If $k > 3000 Then $iFrom = $k - 3000
    Local $aFinal[$k - $iFrom]
    For $i = $iFrom To $k - 1
        $aFinal[$i - $iFrom] = $aOut[$i]
    Next
    _RF_Write($PODCAST_PLAYED_FILE, $aFinal)
EndFunc

; Saved positions as a dictionary: lower case "pod:key" -> milliseconds (only episodes really started and not finished)
Func _Pod_PosDict()
    Local $oD = ObjCreate("Scripting.Dictionary")
    If Not IsObj($oD) Then Return 0
    Local $a = _RF_Read($LOCAL_POSITIONS_FILE), $p
    For $i = 0 To UBound($a) - 1
        If StringLeft($a[$i], 4) <> "pod:" Then ContinueLoop
        $p = StringSplit($a[$i], "|", 2)
        If UBound($p) < 2 Then ContinueLoop
        If Int($p[1]) >= 3000 Then $oD.Item(StringLower($p[0])) = Int($p[1])
    Next
    Return $oD
EndFunc

Func _Pod_Search($sTerm)
    Local $aNone[1][4]
    Local $sJson = _Pod_Http("https://itunes.apple.com/search?media=podcast&entity=podcast&limit=40&term=" & _URLEncode($sTerm), 20000)
    If $sJson = "" Then Return 0
    Local $aObj = StringRegExp($sJson, '\{[^{}]*\}', 3)
    If @error Or Not IsArray($aObj) Then Return $aNone
    Local $aOut[UBound($aObj)][4], $n = 0, $sFeed, $sName, $i
    For $i = 0 To UBound($aObj) - 1
        $sFeed = _Json_Str($aObj[$i], "feedUrl")
        $sName = _Json_Str($aObj[$i], "collectionName")
        If $sName = "" Then $sName = _Json_Str($aObj[$i], "trackName")
        If $sFeed = "" Or $sName = "" Then ContinueLoop
        $aOut[$n][0] = _Pod_Clean($sName)
        $aOut[$n][1] = _Pod_Clean(_Json_Str($aObj[$i], "artistName"))
        $aOut[$n][2] = $sFeed
        $aOut[$n][3] = _Json_Num($aObj[$i], "trackCount")
        $n += 1
    Next
    If $n = 0 Then Return $aNone
    ReDim $aOut[$n][4]
    Return $aOut
EndFunc

Func _Pod_ShowText($sTitle, $sText, $hParent)
    Local $hGui = GUICreate($sTitle, 500, 400, -1, -1, BitOR($WS_CAPTION, $WS_SYSMENU), $WS_EX_TOPMOST, IsHWnd($hParent) ? $hParent : 0)
    GUISetBkColor($COLOR_BLUE)
    Local $edt = GUICtrlCreateEdit($sText, 10, 10, 480, 340, BitOR($ES_READONLY, $ES_MULTILINE, $WS_VSCROLL, $ES_AUTOVSCROLL))
    Local $btnClose = GUICtrlCreateButton(_T("&Close"), 195, 360, 110, 32, $BS_DEFPUSHBUTTON)
    Local $hDummyEsc = GUICtrlCreateDummy()
    Local $aAcc[1][2] = [["{ESC}", $hDummyEsc]]
    GUISetAccelerators($aAcc, $hGui)
    GUISetState(@SW_SHOW, $hGui)
    _AllowUIPI($hGui)
    ControlFocus($hGui, "", $edt)
    Local $nMsg
    While 1
        $nMsg = _GuiMsg($hGui)
        If $nMsg = $GUI_EVENT_CLOSE Or $nMsg = $btnClose Or $nMsg = $hDummyEsc Then ExitLoop
        Sleep(10)
    WEnd
    GUIDelete($hGui)
    If IsHWnd($hParent) Then
        GUISwitch($hParent)
        WinActivate($hParent)
    EndIf
EndFunc

; Chapters of an episode: chapters file of the feed (Podcasting 2.0 JSON), else time stamps in the show notes
Func _Pod_LoadChapters(ByRef $aEp, $i)
    Local $aT[1], $aN[1], $n = 0, $sJson, $aObj, $k, $m, $sT
    If $aEp[$i][5] <> "" Then
        $sJson = _Pod_Http($aEp[$i][5], 8000)
        If $sJson <> "" Then
            $aObj = StringRegExp($sJson, '\{[^{}]*\}', 3)
            If IsArray($aObj) Then
                ReDim $aT[UBound($aObj)]
                ReDim $aN[UBound($aObj)]
                For $k = 0 To UBound($aObj) - 1
                    $m = StringRegExp($aObj[$k], '"startTime"\s*:\s*(-?[0-9.]+)', 1)
                    If @error Or Not IsArray($m) Then ContinueLoop
                    $sT = _Json_Str($aObj[$k], "title")
                    If $sT = "" Then ContinueLoop
                    $aT[$n] = Number($m[0])
                    $aN[$n] = StringStripWS($sT, 7)
                    $n += 1
                Next
            EndIf
        EndIf
    EndIf
    If $n < 1 Then
        $n = _Chap_FromText($aEp[$i][6], $aT, $aN)
    EndIf
    If $n > 0 Then
        ReDim $aT[$n]
        ReDim $aN[$n]
        _Chap_Set($aT, $aN, $n)
    EndIf
EndFunc

; Plays the episodes of a list one after the other. Shift+N / Shift+B = next / previous episode in the list; N toggles auto-play
Func _Pod_PlayList(ByRef $aEp, $iStart, $iCount)
    Local $i = $iStart, $sAct, $sKey
    While $i >= 0 And $i < $iCount
        $sKey = $aEp[$i][4]
        _Chap_Reset()
        _Pod_LoadChapters($aEp, $i)
        $g_bLocalPlaylistMode = False
        _AppSoundPlay(@ScriptDir & "\sounds\ok.wav")
        $sAct = _PlayInternal($aEp[$i][1], $aEp[$i][0], True, 0, True, "pod:" & $sKey, False, True)
        If $g_bTrackEnded Then _Pod_MarkPlayed($sKey, True)
        If $sAct = "NEXT" Or ($sAct = "FINISHED" And $g_bAutoPlay) Then
            $i += 1
        ElseIf $sAct = "BACK" Then
            $i -= 1
        ElseIf $sAct = "RESTART" Then
            ; same episode again
        Else
            ExitLoop
        EndIf
    WEnd
    _Chap_Reset()
EndFunc

Func _Pod_FillList($lst, ByRef $aEp, $iCount, $iNew, $bShowName)
    Local $sPlayed = _Pod_PlayedSet(), $oPos = _Pod_PosDict(), $s = "", $sLab, $sKey, $bPlayed, $iMs, $i
    For $i = 0 To $iCount - 1
        $sKey = StringLower($aEp[$i][4])
        $bPlayed = (StringInStr($sPlayed, @LF & $sKey & @LF) > 0)
        $sLab = ""
        If $i < $iNew And Not $bPlayed Then $sLab = _T("New") & ": "
        If $bShowName And $aEp[$i][7] <> "" Then $sLab &= $aEp[$i][7] & " - "
        $sLab &= $aEp[$i][0]
        If $aEp[$i][2] <> "" Then $sLab &= ", " & $aEp[$i][2]
        If $aEp[$i][3] > 0 Then $sLab &= ", " & _FormatTime($aEp[$i][3])
        If $bPlayed Then
            $sLab &= ", " & _T("Played")
        ElseIf IsObj($oPos) Then
            If $oPos.Exists("pod:" & $sKey) Then
                $iMs = $oPos.Item("pod:" & $sKey)
                $sLab &= ", " & _TF("Listened to {1}", _FormatTime(Int($iMs / 1000)))
            EndIf
        EndIf
        $s &= StringReplace($sLab, "|", "/") & "|"
    Next
    GUICtrlSetData($lst, "")
    If $s <> "" Then GUICtrlSetData($lst, StringTrimRight($s, 1))
EndFunc

; Episode list window. $sFeed = "" for the combined "New episodes" list.
Func _Pod_EpisodeList(ByRef $aEp, $iCount, $sWinTitle, $sFeed, $sFeedTitle, $sAuthor, $iNew, $bCombined)
    Local $hGui = GUICreate($sWinTitle, 520, 490)
    GUISetBkColor($COLOR_BLUE)
    Local $sHead = $sFeedTitle
    If $sAuthor <> "" Then $sHead &= " - " & $sAuthor
    If $sHead = "" Then $sHead = $sWinTitle
    GUICtrlCreateLabel($sHead, 10, 8, 500, 20, $SS_NOPREFIX)
    GUICtrlSetColor(-1, 0xFFFFFF)
    GUICtrlCreateLabel(_TF("{1} episodes. Press Enter to play.", $iCount), 10, 28, 500, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $lst = GUICtrlCreateList("", 10, 52, 500, 330, BitOR($LBS_NOTIFY, $WS_VSCROLL, $WS_BORDER))
    Local $btnPlay = GUICtrlCreateButton(_T("&Play"), 10, 392, 160, 32, $BS_DEFPUSHBUTTON)
    Local $btnSub = GUICtrlCreateButton(_T("&Subscribe (Ctrl+D)"), 180, 392, 160, 32)
    Local $btnMark = GUICtrlCreateButton(_T("Mark as pla&yed (Ctrl+M)"), 350, 392, 160, 32)
    Local $btnCopy = GUICtrlCreateButton(_T("Copy episode &link (Ctrl+K)"), 10, 432, 160, 32)
    Local $btnNotes = GUICtrlCreateButton(_T("Show &notes (Ctrl+I)"), 180, 432, 160, 32)
    Local $btnClose = GUICtrlCreateButton(_T("&Close"), 350, 432, 160, 32)
    Local $hDummyEsc = GUICtrlCreateDummy()
    Local $aAcc[5][2] = [["{ESC}", $hDummyEsc], ["^d", $btnSub], ["^m", $btnMark], ["^k", $btnCopy], ["^i", $btnNotes]]
    GUISetAccelerators($aAcc, $hGui)
    Local $bSubscribed = False
    If $sFeed = "" Then
        GUICtrlSetState($btnSub, $GUI_DISABLE)
    Else
        $bSubscribed = _Pod_IsSubscribed($sFeed)
        If $bSubscribed Then GUICtrlSetData($btnSub, _T("Un&subscribe (Ctrl+D)"))
    EndIf
    _Pod_FillList($lst, $aEp, $iCount, $iNew, $bCombined)
    If $iCount > 0 Then _GUICtrlListBox_SetCurSel($lst, 0)
    GUISetState(@SW_SHOW, $hGui)
    _AllowUIPI($hGui)
    ControlFocus($hGui, "", $lst)
    If $bSubscribed And $iCount > 0 Then
        _Pod_SetSeen($sFeed, $aEp[0][4])
        _Sub_SetNew("pod", $sFeed, 0)
    EndIf
    Local $nMsg, $iSel, $iRes
    While 1
        $nMsg = _GuiMsg($hGui)
        Switch $nMsg
            Case $GUI_EVENT_CLOSE, $btnClose, $hDummyEsc
                ExitLoop
            Case $btnPlay
                $iSel = _GUICtrlListBox_GetCurSel($lst)
                If $iSel >= 0 And $iSel < $iCount Then
                    _Pod_PlayList($aEp, $iSel, $iCount)
                    GUISwitch($hGui)
                    _Pod_FillList($lst, $aEp, $iCount, $iNew, $bCombined)
                    _GUICtrlListBox_SetCurSel($lst, $iSel)
                    WinActivate($hGui)
                    ControlFocus($hGui, "", $lst)
                EndIf
            Case $btnSub
                If $sFeed <> "" Then
                    If $bSubscribed Then
                        If _Pod_Unsubscribe($sFeed) Then
                            $bSubscribed = False
                            GUICtrlSetData($btnSub, _T("&Subscribe (Ctrl+D)"))
                            _AppSoundPlay(@ScriptDir & "\sounds\ok.wav")
                            _ReportStatus(_T("Unsubscribed"))
                        EndIf
                    Else
                        $iRes = _Pod_Subscribe($sFeed, $sFeedTitle, $sAuthor, $iCount > 0 ? $aEp[0][4] : "")
                        If $iRes >= 0 Then
                            $bSubscribed = True
                            GUICtrlSetData($btnSub, _T("Un&subscribe (Ctrl+D)"))
                            _AppSoundPlay(@ScriptDir & "\sounds\ok.wav")
                            _ReportStatus(_T("Subscribed"))
                        Else
                            _ReportStatus(_T("Could not save the subscription"))
                        EndIf
                    EndIf
                EndIf
            Case $btnMark
                $iSel = _GUICtrlListBox_GetCurSel($lst)
                If $iSel >= 0 And $iSel < $iCount Then
                    If StringInStr(_Pod_PlayedSet(), @LF & StringLower($aEp[$iSel][4]) & @LF) Then
                        _Pod_MarkPlayed($aEp[$iSel][4], False)
                        _ReportStatus(_T("Marked as not played"))
                    Else
                        _Pod_MarkPlayed($aEp[$iSel][4], True)
                        _LocalPos_Clear("pod:" & $aEp[$iSel][4])
                        _ReportStatus(_T("Marked as played"))
                    EndIf
                    _Pod_FillList($lst, $aEp, $iCount, $iNew, $bCombined)
                    _GUICtrlListBox_SetCurSel($lst, $iSel)
                EndIf
            Case $btnCopy
                $iSel = _GUICtrlListBox_GetCurSel($lst)
                If $iSel >= 0 And $iSel < $iCount Then
                    ClipPut($aEp[$iSel][1])
                    _ReportStatus(_T("Link copied to clipboard"))
                EndIf
            Case $btnNotes
                $iSel = _GUICtrlListBox_GetCurSel($lst)
                If $iSel >= 0 And $iSel < $iCount Then
                    If $aEp[$iSel][6] = "" Then
                        _ReportStatus(_T("This episode has no show notes."))
                    Else
                        _Pod_ShowText($aEp[$iSel][0], $aEp[$iSel][6], $hGui)
                        ControlFocus($hGui, "", $lst)
                    EndIf
                EndIf
        EndSwitch
        Sleep(10)
    WEnd
    GUIDelete($hGui)
EndFunc

; Downloads a feed and opens its episode list
Func _Pod_OpenFeed($sFeed, $hParent)
    Local $hLoad = _Radio_Loading(_T("Loading the podcast..."))
    _Snd_LoadStart()
    Local $sXml = _Pod_Http($sFeed, 30000)
    Local $sTitle = "", $sAuthor = ""
    Local $aEp = _Pod_ParseFeed($sXml, $sTitle, $sAuthor)
    GUIDelete($hLoad)
    _Snd_LoadStop()
    If IsHWnd($hParent) Then GUISwitch($hParent)
    If Not IsArray($aEp) Then
        _AppSoundPlay(@ScriptDir & "\sounds\error.wav")
        MsgBox(48, _T("Podcasts"), _T("Cannot read this podcast. Check the link and your internet connection."))
        Return
    EndIf
    _AppSoundPlay(@ScriptDir & "\sounds\ok.wav")
    Local $aSub = _Pod_SubLoad(), $sSeen = "", $iNew = 0, $iCount = UBound($aEp)
    If IsArray($aSub) Then
        For $i = 0 To UBound($aSub) - 1
            If StringLower($aSub[$i][0]) = StringLower($sFeed) Then
                $sSeen = $aSub[$i][3]
                ExitLoop
            EndIf
        Next
    EndIf
    $iNew = _Pod_NewCount($aEp, $iCount, $sSeen)
    If $sTitle = "" Then $sTitle = $sFeed
    _Pod_EpisodeList($aEp, $iCount, $sTitle, $sFeed, $sTitle, $sAuthor, $iNew, False)
    If IsHWnd($hParent) Then
        GUISwitch($hParent)
        WinActivate($hParent)
    EndIf
EndFunc

Func _Pod_ResultsWindow($sTerm, $hParent)
    Local $hLoad = _Radio_Loading(_T("Searching..."))
    _Snd_LoadStart()
    Local $aRes = _Pod_Search($sTerm)
    GUIDelete($hLoad)
    _Snd_LoadStop()
    If IsHWnd($hParent) Then GUISwitch($hParent)
    If Not IsArray($aRes) Then
        _AppSoundPlay(@ScriptDir & "\sounds\no_internet.wav")
        MsgBox(48, _T("Podcasts"), _T("Cannot search podcasts now. Check your internet connection."))
        Return
    EndIf
    If $aRes[0][2] = "" Then
        MsgBox(64, _T("Podcasts"), _T("No podcasts found."))
        Return
    EndIf
    _AppSoundPlay(@ScriptDir & "\sounds\result.wav")
    Local $n = UBound($aRes), $i, $s = ""
    Local $hGui = GUICreate(_T("Podcast results"), 520, 440)
    GUISetBkColor($COLOR_BLUE)
    GUICtrlCreateLabel(_TF("{1} podcasts found. Press Enter to open one.", $n), 10, 10, 500, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $lst = GUICtrlCreateList("", 10, 36, 500, 330, BitOR($LBS_NOTIFY, $WS_VSCROLL, $WS_BORDER))
    Local $btnOpen = GUICtrlCreateButton(_T("&Open"), 100, 382, 140, 34, $BS_DEFPUSHBUTTON)
    Local $btnClose = GUICtrlCreateButton(_T("&Close"), 280, 382, 140, 34)
    For $i = 0 To $n - 1
        $s &= StringReplace($aRes[$i][0] & ", " & $aRes[$i][1] & ", " & _TF("{1} episodes", $aRes[$i][3]), "|", "/") & "|"
    Next
    GUICtrlSetData($lst, StringTrimRight($s, 1))
    _GUICtrlListBox_SetCurSel($lst, 0)
    Local $hDummyEsc = GUICtrlCreateDummy()
    Local $aAcc[1][2] = [["{ESC}", $hDummyEsc]]
    GUISetAccelerators($aAcc, $hGui)
    GUISetState(@SW_SHOW, $hGui)
    _AllowUIPI($hGui)
    ControlFocus($hGui, "", $lst)
    Local $nMsg, $iSel
    While 1
        $nMsg = _GuiMsg($hGui)
        Switch $nMsg
            Case $GUI_EVENT_CLOSE, $btnClose, $hDummyEsc
                ExitLoop
            Case $btnOpen
                $iSel = _GUICtrlListBox_GetCurSel($lst)
                If $iSel >= 0 And $iSel < $n Then
                    _Pod_OpenFeed($aRes[$iSel][2], $hGui)
                    GUISwitch($hGui)
                    WinActivate($hGui)
                    ControlFocus($hGui, "", $lst)
                EndIf
        EndSwitch
        Sleep(10)
    WEnd
    GUIDelete($hGui)
    If IsHWnd($hParent) Then
        GUISwitch($hParent)
        WinActivate($hParent)
    EndIf
EndFunc

; Downloads all subscribed feeds: $aCnt[i] = number of new episodes (-1 = could not be read), $aComb = the new episodes that are not played yet
Func _Pod_FetchAll(ByRef $aSub, ByRef $aCnt, ByRef $aComb, ByRef $nComb)
    Local $nSub = UBound($aSub), $i, $j, $k, $sXml, $sT, $sA, $aEp, $iNew, $iEpN
    Local $sPlayed = _Pod_PlayedSet()
    Local $hLoad = _Radio_Loading(_T("Checking for new episodes..."))
    _Snd_LoadStart()
    For $i = 0 To $nSub - 1
        $aCnt[$i] = -1
        $sXml = _Pod_Http($aSub[$i][0], 15000)
        If $sXml = "" Then ContinueLoop
        $aEp = _Pod_ParseFeed($sXml, $sT, $sA)
        If Not IsArray($aEp) Then ContinueLoop
        $iEpN = UBound($aEp)
        $iNew = _Pod_NewCount($aEp, $iEpN, $aSub[$i][3])
        $aCnt[$i] = $iNew
        _Sub_SetNew("pod", $aSub[$i][0], $iNew)
        If $iNew > 0 Then _Sub_NotifiedSet("pod:" & $aSub[$i][0], $aEp[0][4]) ; already known: not announced again at startup
        For $k = 0 To $iNew - 1
            If $nComb >= UBound($aComb) Then ExitLoop
            If StringInStr($sPlayed, @LF & StringLower($aEp[$k][4]) & @LF) Then ContinueLoop
            For $j = 0 To 6
                $aComb[$nComb][$j] = $aEp[$k][$j]
            Next
            $aComb[$nComb][7] = $aSub[$i][1]
            $aComb[$nComb][8] = $aSub[$i][0]
            $nComb += 1
        Next
    Next
    GUIDelete($hLoad)
    _Snd_LoadStop()
    If $nComb > 0 Then
        _AppSoundPlay(@ScriptDir & "\sounds\new_content.wav")
    Else
        _AppSoundPlay(@ScriptDir & "\sounds\ok.wav")
    EndIf
EndFunc

Func _Pod_NewEpisodes($hParent)
    Local $aSub = _Pod_SubLoad()
    If Not IsArray($aSub) Then
        MsgBox(64, _T("Podcasts"), _T("You have no subscriptions yet. Search for a podcast, open it and press Ctrl+D to subscribe."))
        Return
    EndIf
    Local $aCnt[UBound($aSub)], $aComb[200][9], $nComb = 0
    _Pod_FetchAll($aSub, $aCnt, $aComb, $nComb)
    If IsHWnd($hParent) Then GUISwitch($hParent)
    If $nComb = 0 Then
        MsgBox(64, _T("Podcasts"), _T("There are no new episodes."))
        Return
    EndIf
    _Pod_EpisodeList($aComb, $nComb, _T("New episodes"), "", "", "", $nComb, True)
    If IsHWnd($hParent) Then
        GUISwitch($hParent)
        WinActivate($hParent)
    EndIf
EndFunc

Func _Pod_SubLabel(ByRef $aSub, $i, $iNew)
    Local $s = $aSub[$i][1]
    If $aSub[$i][2] <> "" Then $s &= ", " & $aSub[$i][2]
    If $iNew > 0 Then $s &= ", " & _TF("{1} new", $iNew)
    Return $s
EndFunc

Func _Pod_SubsWindow($hParent)
    Local $aSub = _Pod_SubLoad()
    If Not IsArray($aSub) Then
        MsgBox(64, _T("Podcasts"), _T("You have no subscriptions yet. Search for a podcast, open it and press Ctrl+D to subscribe."))
        Return
    EndIf
    Local $nSub = UBound($aSub), $i, $s
    Local $aCnt[$nSub]
    For $i = 0 To $nSub - 1
        $aCnt[$i] = _Sub_GetNew("pod", $aSub[$i][0])
    Next
    Local $hGui = GUICreate(_T("My subscriptions"), 520, 440)
    GUISetBkColor($COLOR_BLUE)
    Local $lblInfo = GUICtrlCreateLabel(_TF("{1} subscriptions. Press Enter to open one.", $nSub), 10, 10, 500, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $lst = GUICtrlCreateList("", 10, 36, 500, 320, BitOR($LBS_NOTIFY, $WS_VSCROLL, $WS_BORDER))
    Local $btnOpen = GUICtrlCreateButton(_T("&Open"), 10, 372, 120, 34, $BS_DEFPUSHBUTTON)
    Local $btnCheck = GUICtrlCreateButton(_T("Chec&k for new episodes"), 140, 372, 180, 34)
    Local $btnDel = GUICtrlCreateButton(_T("&Unsubscribe (Delete)"), 330, 372, 180, 34)
    Local $btnClose = GUICtrlCreateButton(_T("&Close"), 195, 410, 130, 26)
    Local $hDummyEsc = GUICtrlCreateDummy()
    Local $aAcc[2][2] = [["{ESC}", $hDummyEsc], ["{DEL}", $btnDel]]
    GUISetAccelerators($aAcc, $hGui)
    GUISetState(@SW_SHOW, $hGui)
    _AllowUIPI($hGui)
    Local $iSel, $aComb[200][9], $nComb
    ; the list is filled by _Pod_SubRefresh below
    $s = ""
    For $i = 0 To $nSub - 1
        $s &= StringReplace(_Pod_SubLabel($aSub, $i, $aCnt[$i]), "|", "/") & "|"
    Next
    GUICtrlSetData($lst, StringTrimRight($s, 1))
    _GUICtrlListBox_SetCurSel($lst, 0)
    ControlFocus($hGui, "", $lst)
    Local $nMsg
    While 1
        $nMsg = _GuiMsg($hGui)
        Switch $nMsg
            Case $GUI_EVENT_CLOSE, $btnClose, $hDummyEsc
                ExitLoop
            Case $btnOpen
                $iSel = _GUICtrlListBox_GetCurSel($lst)
                If $iSel >= 0 And $iSel < $nSub Then
                    _Pod_OpenFeed($aSub[$iSel][0], $hGui)
                    GUISwitch($hGui)
                    $aSub = _Pod_SubLoad()
                    If IsArray($aSub) Then
                        If UBound($aSub) = $nSub Then $aCnt[$iSel] = _Sub_GetNew("pod", $aSub[$iSel][0])
                    EndIf
                    WinActivate($hGui)
                    ControlFocus($hGui, "", $lst)
                EndIf
            Case $btnCheck
                $nComb = 0
                _Pod_FetchAll($aSub, $aCnt, $aComb, $nComb)
                GUISwitch($hGui)
                $iSel = _GUICtrlListBox_GetCurSel($lst)
                $s = ""
                For $i = 0 To $nSub - 1
                    $s &= StringReplace(_Pod_SubLabel($aSub, $i, $aCnt[$i]), "|", "/") & "|"
                Next
                GUICtrlSetData($lst, "")
                GUICtrlSetData($lst, StringTrimRight($s, 1))
                If $iSel < 0 Then $iSel = 0
                _GUICtrlListBox_SetCurSel($lst, $iSel)
                WinActivate($hGui)
                ControlFocus($hGui, "", $lst)
                _ReportStatus(_TF("{1} new episodes", $nComb))
            Case $btnDel
                $iSel = _GUICtrlListBox_GetCurSel($lst)
                If $iSel >= 0 And $iSel < $nSub Then
                    If MsgBox(36, _T("Podcasts"), _TF("Unsubscribe from {1}?", $aSub[$iSel][1]), 0, $hGui) = 6 Then
                        _Pod_Unsubscribe($aSub[$iSel][0])
                        ExitLoop
                    EndIf
                EndIf
        EndSwitch
        Sleep(10)
    WEnd
    GUIDelete($hGui)
    If IsHWnd($hParent) Then
        GUISwitch($hParent)
        WinActivate($hParent)
    EndIf
EndFunc

; Main window > Podcasts (Alt+K)
Func _ShowPodcasts()
    Local $hGui = GUICreate(_T("Podcasts"), 420, 200)
    GUISetBkColor($COLOR_BLUE)
    GUICtrlCreateLabel(_T("Search for a podcast, or paste an RSS feed link:"), 10, 12, 400, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $inp = GUICtrlCreateInput("", 10, 36, 400, 22)
    _TypeSnd_Attach($inp) ; typing sounds, like the search box
    Local $btnSearch = GUICtrlCreateButton(_T("&Search"), 10, 72, 190, 34, $BS_DEFPUSHBUTTON)
    Local $btnSubs = GUICtrlCreateButton(_T("My s&ubscriptions"), 220, 72, 190, 34)
    Local $btnNew = GUICtrlCreateButton(_T("&New episodes"), 10, 114, 190, 34)
    Local $btnClose = GUICtrlCreateButton(_T("&Close"), 220, 114, 190, 34)
    Local $hDummyEsc = GUICtrlCreateDummy()
    Local $aAcc[1][2] = [["{ESC}", $hDummyEsc]]
    GUISetAccelerators($aAcc, $hGui)
    GUISetState(@SW_SHOW, $hGui)
    _AllowUIPI($hGui)
    ControlFocus($hGui, "", $inp)
    Local $nMsg, $sTerm
    While 1
        $nMsg = _GuiMsg($hGui)
        Switch $nMsg
            Case $GUI_EVENT_CLOSE, $btnClose, $hDummyEsc
                ExitLoop
            Case $btnSearch
                $sTerm = StringStripWS(GUICtrlRead($inp), 3)
                If $sTerm = "" Then
                    _ReportStatus(_T("Please enter a search term."))
                    ControlFocus($hGui, "", $inp)
                ElseIf _IsWebLink($sTerm) Then
                    _Pod_OpenFeed($sTerm, $hGui)
                    GUISwitch($hGui)
                    WinActivate($hGui)
                    ControlFocus($hGui, "", $inp)
                Else
                    _Pod_ResultsWindow($sTerm, $hGui)
                    GUISwitch($hGui)
                    WinActivate($hGui)
                    ControlFocus($hGui, "", $inp)
                EndIf
            Case $btnSubs
                _Pod_SubsWindow($hGui)
                GUISwitch($hGui)
                WinActivate($hGui)
            Case $btnNew
                _Pod_NewEpisodes($hGui)
                GUISwitch($hGui)
                WinActivate($hGui)
        EndSwitch
        Sleep(10)
    WEnd
    _TypeSnd_Detach()
    GUIDelete($hGui)
EndFunc


; ======================================================================
;  EXTRA SEARCH SOURCES (version 3.3) - Search window > Source
;  SoundCloud: yt-dlp keyword search ("scsearch"). Results use the full link of the item as their id.
; ======================================================================
; "https://soundcloud.com/artist/some-track-name" -> "some track name" (artist returned in $sUp)
Func _Search_TitleFromUrl($sUrl, ByRef $sUp)
    Local $sPath = StringRegExpReplace($sUrl, '^(?i)https?://[^/]+/', '')
    $sPath = StringRegExpReplace($sPath, '[?#].*$', '')
    Local $aSeg = StringSplit($sPath, "/", 2)
    If UBound($aSeg) >= 2 Then
        If $sUp = "" Then $sUp = StringReplace($aSeg[0], "-", " ")
        Return StringReplace($aSeg[UBound($aSeg) - 1], "-", " ")
    EndIf
    Return $sUrl
EndFunc


; ======================================================================
;  SUBSCRIPTIONS (version 3.2)
;  - YouTube channels: subscribe, My subscriptions, check for new videos
;  - Podcasts + YouTube: check for new content when the application starts (new_content.wav)
;  - Sounds for the podcast window, typing sounds in its search box
; ======================================================================

; ---------- sounds ----------
Func _Snd_LoadStart()
    _AppPlaySoundW(@ScriptDir & "\sounds\loading.wav", 0x0009)
EndFunc

Func _Snd_LoadStop()
    DllCall("winmm.dll", "int", "PlaySoundW", "ptr", 0, "ptr", 0, "dword", 0)
EndFunc

; ---------- typing sounds in an input box (same sounds as the search box) ----------
Func _TypeEditProc($hWnd, $iMsg, $wParam, $lParam)
    Local $aRet = DllCall("user32.dll", "lresult", "CallWindowProcW", "ptr", $g_pTypeOld, "hwnd", $hWnd, "uint", $iMsg, "wparam", $wParam, "lparam", $lParam)
    If $iMsg = 0x0100 Then ; WM_KEYDOWN (same behaviour as the search box)
        If BitAND($lParam, 0x40000000) = 0 Then
            If $wParam <> $g_iLastVkCode Or TimerDiff($g_iLastHookTime) > 50 Then
                $g_iLastVkCode = $wParam
                $g_iLastHookTime = TimerInit()
                If $wParam < 0x25 Or $wParam > 0x28 Then _PlayTypingSound($wParam)
            EndIf
        EndIf
    EndIf
    If @error Or Not IsArray($aRet) Then Return 0
    Return $aRet[0]
EndFunc

Func _TypeSnd_Attach($idInput)
    _TypeSnd_Detach()
    $g_hTypeEdit = GUICtrlGetHandle($idInput)
    If Not IsHWnd($g_hTypeEdit) Then Return
    $g_hTypeCb = DllCallbackRegister("_TypeEditProc", "lresult", "hwnd;uint;wparam;lparam")
    Local $aRet = DllCall("user32.dll", "ptr", "SetWindowLong" & (@AutoItX64 ? "Ptr" : "") & "W", "hwnd", $g_hTypeEdit, "int", -4, "ptr", DllCallbackGetPtr($g_hTypeCb))
    If @error Or Not IsArray($aRet) Then
        DllCallbackFree($g_hTypeCb)
        $g_hTypeCb = 0
        Return
    EndIf
    $g_pTypeOld = $aRet[0]
EndFunc

Func _TypeSnd_Detach()
    If $g_hTypeCb = 0 Then Return
    If IsHWnd($g_hTypeEdit) And $g_pTypeOld <> 0 Then
        DllCall("user32.dll", "ptr", "SetWindowLong" & (@AutoItX64 ? "Ptr" : "") & "W", "hwnd", $g_hTypeEdit, "int", -4, "ptr", $g_pTypeOld)
    EndIf
    DllCallbackFree($g_hTypeCb)
    $g_hTypeCb = 0
    $g_pTypeOld = 0
    $g_hTypeEdit = 0
EndFunc

; ---------- Settings: the list of typing sounds exists only while the option is on ----------
Func _Settings_SyncTypingSet($idChk, $idLbl, $idCbo)
    Local Static $hT = 0
    If $hT <> 0 And TimerDiff($hT) < 100 Then Return
    $hT = TimerInit()
    If _GUICtrlTab_GetCurSel(GUICtrlGetHandle($g_hSettingsTab)) <> 4 Then Return ; only on the Search tab
    Local $bWant = (GUICtrlRead($idChk) = $GUI_CHECKED)
    Local $aVis = DllCall("user32.dll", "bool", "IsWindowVisible", "hwnd", GUICtrlGetHandle($idCbo))
    Local $bVis = (Not @error And IsArray($aVis) And $aVis[0] <> 0)
    If $bWant And Not $bVis Then
        GUICtrlSetState($idLbl, BitOR($GUI_SHOW, $GUI_ENABLE))
        GUICtrlSetState($idCbo, BitOR($GUI_SHOW, $GUI_ENABLE))
    ElseIf (Not $bWant) And $bVis Then
        GUICtrlSetState($idLbl, BitOR($GUI_HIDE, $GUI_DISABLE))
        GUICtrlSetState($idCbo, BitOR($GUI_HIDE, $GUI_DISABLE))
    EndIf
EndFunc

; ---------- counters of new items (kept while the application runs) ----------
Func _Sub_GetNew($sType, $sId)
    If Not IsObj($g_oSubNew) Then Return 0
    Local $k = $sType & ":" & StringLower($sId)
    If $g_oSubNew.Exists($k) Then Return $g_oSubNew.Item($k)
    Return 0
EndFunc

Func _Sub_SetNew($sType, $sId, $n)
    If Not IsObj($g_oSubNew) Then $g_oSubNew = ObjCreate("Scripting.Dictionary")
    If Not IsObj($g_oSubNew) Then Return
    $g_oSubNew.Item($sType & ":" & StringLower($sId)) = $n
EndFunc

; ---------- what was already announced (so the same news is not announced at every start) ----------
Func _Sub_NotifiedKey($s)
    Return StringReplace(StringLower($s), "|", "/")
EndFunc

Func _Sub_NotifiedGet($sKey)
    Local $a = _RF_Read($SUB_NOTIFIED_FILE), $i, $p
    $sKey = _Sub_NotifiedKey($sKey)
    For $i = 0 To UBound($a) - 1
        $p = StringSplit($a[$i], "|", 2)
        If UBound($p) >= 2 And $p[0] = $sKey Then Return $p[1]
    Next
    Return ""
EndFunc

Func _Sub_NotifiedSet($sKey, $sVal)
    Local $a = _RF_Read($SUB_NOTIFIED_FILE), $i, $p, $k = 0
    Local $aOut[UBound($a) + 1]
    $sKey = _Sub_NotifiedKey($sKey)
    For $i = 0 To UBound($a) - 1
        $p = StringSplit($a[$i], "|", 2)
        If UBound($p) >= 2 And $p[0] = $sKey Then ContinueLoop
        $aOut[$k] = $a[$i]
        $k += 1
    Next
    $aOut[$k] = $sKey & "|" & _Pod_Clean($sVal)
    $k += 1
    ReDim $aOut[$k]
    _RF_Write($SUB_NOTIFIED_FILE, $aOut)
EndFunc

; ---------- YouTube subscriptions: storage ----------
; "UCxxxx" or "@handle" -> page with the videos of the channel
Func _YTS_ChannelUrl($sChan)
    If StringLeft($sChan, 1) = "@" Then Return "https://www.youtube.com/" & $sChan & "/videos"
    Return "https://www.youtube.com/channel/" & $sChan & "/videos"
EndFunc

; Returns a [n][3] array (channel id, name, id of the newest video already seen) or 0
Func _YTS_Load()
    Local $a = _RF_Read($YT_SUBS_FILE)
    Local $n = UBound($a)
    If $n = 0 Then Return 0
    Local $aOut[$n][3], $p, $k = 0, $i
    For $i = 0 To $n - 1
        $p = StringSplit($a[$i], "|", 2)
        If UBound($p) < 2 Or $p[0] = "" Then ContinueLoop
        $aOut[$k][0] = $p[0]
        $aOut[$k][1] = $p[1]
        $aOut[$k][2] = ""
        If UBound($p) >= 3 Then $aOut[$k][2] = $p[2]
        $k += 1
    Next
    If $k = 0 Then Return 0
    ReDim $aOut[$k][3]
    Return $aOut
EndFunc

Func _YTS_Save(ByRef $aSub)
    Local $n = UBound($aSub), $i
    Local $aLines[$n]
    For $i = 0 To $n - 1
        $aLines[$i] = $aSub[$i][0] & "|" & _Pod_Clean($aSub[$i][1]) & "|" & $aSub[$i][2]
    Next
    _RF_Write($YT_SUBS_FILE, $aLines)
EndFunc

Func _YTS_IsSubscribed($sChan)
    Local $a = _YTS_Load(), $i
    If Not IsArray($a) Then Return False
    For $i = 0 To UBound($a) - 1
        If StringLower($a[$i][0]) = StringLower($sChan) Then Return True
    Next
    Return False
EndFunc

Func _YTS_GetSeen($sChan)
    Local $a = _YTS_Load(), $i
    If Not IsArray($a) Then Return ""
    For $i = 0 To UBound($a) - 1
        If StringLower($a[$i][0]) = StringLower($sChan) Then Return $a[$i][2]
    Next
    Return ""
EndFunc

; Returns 1 = subscribed, 0 = was already subscribed
Func _YTS_Subscribe($sChan, $sName, $sSeen)
    If _YTS_IsSubscribed($sChan) Then Return 0
    If $sName = "" Then $sName = $sChan
    Local $a = _YTS_Load(), $n = 0, $i
    If IsArray($a) Then $n = UBound($a)
    Local $aOut[$n + 1][3]
    For $i = 0 To $n - 1
        $aOut[$i][0] = $a[$i][0]
        $aOut[$i][1] = $a[$i][1]
        $aOut[$i][2] = $a[$i][2]
    Next
    $aOut[$n][0] = $sChan
    $aOut[$n][1] = $sName
    $aOut[$n][2] = $sSeen
    _YTS_Save($aOut)
    Return 1
EndFunc

Func _YTS_Unsubscribe($sChan)
    Local $a = _YTS_Load(), $i, $k = 0
    If Not IsArray($a) Then Return False
    Local $n = UBound($a)
    If $n = 1 Then
        If StringLower($a[0][0]) <> StringLower($sChan) Then Return False
        FileDelete($YT_SUBS_FILE)
        Return True
    EndIf
    Local $aOut[$n][3]
    For $i = 0 To $n - 1
        If StringLower($a[$i][0]) = StringLower($sChan) Then ContinueLoop
        $aOut[$k][0] = $a[$i][0]
        $aOut[$k][1] = $a[$i][1]
        $aOut[$k][2] = $a[$i][2]
        $k += 1
    Next
    If $k = $n Then Return False
    ReDim $aOut[$k][3]
    _YTS_Save($aOut)
    Return True
EndFunc

Func _YTS_SetSeen($sChan, $sKey)
    Local $a = _YTS_Load(), $i
    If Not IsArray($a) Then Return
    For $i = 0 To UBound($a) - 1
        If StringLower($a[$i][0]) = StringLower($sChan) Then
            If $a[$i][2] = $sKey Then Return
            $a[$i][2] = $sKey
            _YTS_Save($a)
            Return
        EndIf
    Next
EndFunc

; ---------- YouTube subscriptions: reading a channel ----------
; Parses the output of yt-dlp (T:title / I:id lines). Returns the number of videos (0-based arrays, newest first)
Func _YTS_Parse($sOut, ByRef $aIds, ByRef $aTitles)
    Local $aLines = StringSplit(StringStripCR($sOut), @LF, 2)
    Local $n = 0, $sT = "", $sLine, $sI, $i
    Local $aI[UBound($aLines) + 1], $aT[UBound($aLines) + 1]
    For $i = 0 To UBound($aLines) - 1
        $sLine = StringStripWS($aLines[$i], 3)
        If StringLeft($sLine, 2) = "T:" Then
            $sT = StringTrimLeft($sLine, 2)
        ElseIf StringLeft($sLine, 2) = "I:" Then
            $sI = StringTrimLeft($sLine, 2)
            If $sI <> "" And $sI <> "NA" Then
                $aI[$n] = $sI
                $aT[$n] = ($sT = "" Or $sT = "NA") ? _T("Unknown Title") : $sT
                $n += 1
            EndIf
            $sT = ""
        EndIf
    Next
    ReDim $aI[$n]
    ReDim $aT[$n]
    $aIds = $aI
    $aTitles = $aT
    Return $n
EndFunc

Func _YTS_CmdFetch($sChan, $iMax)
    Return $YT_DLP_EXE & ' --flat-playlist --playlist-end ' & $iMax & ' --print "T:%(title)s" --print "I:%(id)s" --no-warnings --encoding utf-8 -- "' & _YTS_ChannelUrl($sChan) & '"'
EndFunc

; Latest videos of a channel. Returns the number of videos, or -1 when the channel could not be read.
Func _YTS_Fetch($sChan, $iMax, ByRef $aIds, ByRef $aTitles)
    Local $iPid = Run(_YTS_CmdFetch($sChan, $iMax), @ScriptDir, @SW_HIDE, $STDOUT_CHILD + $STDERR_CHILD)
    If @error Or $iPid = 0 Then Return -1
    Local $bData = Binary(""), $hT = TimerInit()
    While ProcessExists($iPid)
        $bData &= StdoutRead($iPid, False, True)
        StderrRead($iPid)
        GUIGetMsg()
        If TimerDiff($hT) > 60000 Then
            ProcessClose($iPid)
            Return -1
        EndIf
        Sleep(10)
    WEnd
    $bData &= StdoutRead($iPid, False, True)
    Local $n = _YTS_Parse(BinaryToString($bData, 4), $aIds, $aTitles)
    If $n = 0 Then Return -1
    Return $n
EndFunc

; How many videos in the list ($aIds, newest first) are newer than the one already seen
Func _YTS_NewCount(ByRef $aIds, $n, $sSeen)
    If $sSeen = "" Or $n = 0 Then Return 0
    Local $i
    For $i = 0 To $n - 1
        If $aIds[$i] = $sSeen Then Return $i
    Next
    Return $n
EndFunc

; Channel of a video: $sChan = channel id, $sName = channel name. Returns True when found.
Func _YTS_ResolveChannel($sVideoID, ByRef $sChan, ByRef $sName, $hParent = 0)
    Local $hLoad = GUICreate(_T("Working..."), 250, 80, -1, -1, BitOR($WS_POPUP, $WS_BORDER), BitOR($WS_EX_TOPMOST, $WS_EX_TOOLWINDOW), IsHWnd($hParent) ? $hParent : 0)
    GUICtrlCreateLabel(_T("Fetching channel information..."), 10, 25, 230, 40, $SS_CENTER)
    GUISetBkColor(0xFFFFFF, $hLoad)
    GUISetState(@SW_SHOW, $hLoad)
    _Snd_LoadStart()
    Local $iPid = Run($YT_DLP_EXE & ' --print "%(channel_id)s" --print "%(channel,uploader)s" --no-playlist --no-warnings --encoding utf-8 -- "' & _VideoLink($sVideoID) & '"', @ScriptDir, @SW_HIDE, $STDOUT_CHILD + $STDERR_CHILD)
    Local $bData = Binary(""), $hT = TimerInit()
    If $iPid <> 0 Then
        While ProcessExists($iPid)
            $bData &= StdoutRead($iPid, False, True)
            StderrRead($iPid)
            GUIGetMsg()
            If TimerDiff($hT) > 60000 Then
                ProcessClose($iPid)
                ExitLoop
            EndIf
            Sleep(10)
        WEnd
        $bData &= StdoutRead($iPid, False, True)
    EndIf
    _Snd_LoadStop()
    GUIDelete($hLoad)
    Local $aL = StringSplit(StringStripCR(BinaryToString($bData, 4)), @LF, 2)
    If UBound($aL) < 1 Then Return False
    Local $sC = StringStripWS($aL[0], 3)
    If Not StringRegExp($sC, "^UC[\w-]{20,}$") Then Return False
    $sChan = $sC
    $sName = ""
    If UBound($aL) >= 2 Then $sName = StringStripWS($aL[1], 3)
    If $sName = "" Or $sName = "NA" Then $sName = $sC
    Return True
EndFunc

; Subscribe to / unsubscribe from a channel. Returns 1 = subscribed, 0 = unsubscribed, -1 = nothing done.
Func _YTS_ToggleChannel($sChan, $sName, $sSeen, $hParent)
    If _YTS_IsSubscribed($sChan) Then
        If MsgBox(36, _T("YouTube subscriptions"), _TF("You are subscribed to {1}. Do you want to unsubscribe?", $sName), 0, $hParent) = 6 Then
            If _YTS_Unsubscribe($sChan) Then
                _AppSoundPlay(@ScriptDir & "\sounds\ok.wav")
                MsgBox(64, _T("YouTube subscriptions"), _TF("Unsubscribed from {1}", $sName), 0, $hParent)
                Return 0
            EndIf
        EndIf
        Return -1
    EndIf
    If $sSeen = "" Then
        Local $aI[1], $aT[1]
        If _YTS_Fetch($sChan, 1, $aI, $aT) > 0 Then $sSeen = $aI[0]
    EndIf
    If _YTS_Subscribe($sChan, $sName, $sSeen) >= 0 Then
        _AppSoundPlay(@ScriptDir & "\sounds\ok.wav")
        MsgBox(64, _T("YouTube subscriptions"), _TF("Subscribed to {1}", $sName), 0, $hParent)
        Return 1
    EndIf
    Return -1
EndFunc

; From a video (or a channel found in the search results): subscribe to its channel
Func _YTS_SubscribeFromItem($sID, $sTitle, $sType, $hParent = 0)
    Local $sChan = "", $sName = ""
    If $sType = "channel" Then
        $sChan = $sID
        $sName = $sTitle
    ElseIf Not _YTS_ResolveChannel($sID, $sChan, $sName, $hParent) Then
        MsgBox(16, _T("Error"), _T("Cannot get channel URL. The video might be from a deleted channel or restricted."), 0, $hParent)
        Return
    EndIf
    _YTS_ToggleChannel($sChan, $sName, "", $hParent)
EndFunc

; ---------- YouTube subscriptions: check by hand ----------
; Checks every channel. $aCnt[i] = number of new videos (-1 = could not be read). The new videos are collected in
; $aCIds / $aCTitles / $aCChan (channel name) / $nComb; $aNewest[i] = newest video of channel i.
Func _YTS_CheckAll(ByRef $aSub, ByRef $aCnt, ByRef $aCIds, ByRef $aCTitles, ByRef $aCChan, ByRef $nComb, ByRef $aNewest, $hParent = 0)
    Local $nSub = UBound($aSub), $i, $k, $n, $iNew, $aIds[1], $aTit[1]
    $nComb = 0
    Local $hLoad = GUICreate(_T("Loading"), 300, 80, -1, -1, $WS_POPUP, BitOR($WS_EX_TOPMOST, $WS_EX_TOOLWINDOW))
    GUISetBkColor(0xFFFFFF)
    GUICtrlCreateLabel(_T("Checking for new videos..."), 10, 25, 280, 40, $SS_CENTER)
    GUISetState(@SW_SHOW, $hLoad)
    _Snd_LoadStart()
    For $i = 0 To $nSub - 1
        $aCnt[$i] = -1
        $aNewest[$i] = ""
        $n = _YTS_Fetch($aSub[$i][0], 30, $aIds, $aTit)
        If $n < 1 Then ContinueLoop
        $aNewest[$i] = $aIds[0]
        $iNew = _YTS_NewCount($aIds, $n, $aSub[$i][2])
        $aCnt[$i] = $iNew
        _Sub_SetNew("yt", $aSub[$i][0], $iNew)
        If $iNew > 0 Then _Sub_NotifiedSet("yt:" & $aSub[$i][0], $aIds[0]) ; already known: not announced again at startup
        For $k = 0 To $iNew - 1
            If $nComb >= UBound($aCIds) Then ExitLoop
            $aCIds[$nComb] = $aIds[$k]
            $aCTitles[$nComb] = $aTit[$k]
            $aCChan[$nComb] = $aSub[$i][1]
            $nComb += 1
        Next
    Next
    _Snd_LoadStop()
    GUIDelete($hLoad)
    If IsHWnd($hParent) Then GUISwitch($hParent)
    If $nComb > 0 Then
        _AppSoundPlay(@ScriptDir & "\sounds\new_content.wav")
    Else
        _AppSoundPlay(@ScriptDir & "\sounds\ok.wav")
    EndIf
EndFunc

Func _YTS_FillList($lst, ByRef $aSub, ByRef $aCnt)
    _GUICtrlListBox_ResetContent($lst)
    Local $i, $s
    For $i = 0 To UBound($aSub) - 1
        $s = $aSub[$i][1]
        If $aCnt[$i] > 0 Then $s &= " - " & _TF("{1} new", $aCnt[$i])
        _GUICtrlListBox_AddString($lst, $s)
    Next
EndFunc

; List of the new videos of all channels: Enter = play, Ctrl+Enter = play as audio
Func _YTS_NewVideosWindow(ByRef $aCIds, ByRef $aCTitles, ByRef $aCChan, $nComb, $hParent = 0)
    Local $hGui = GUICreate(_T("New videos"), 520, 440)
    GUISetBkColor($COLOR_BLUE)
    GUICtrlCreateLabel(_TF("{1} new videos. Press Enter to play, Ctrl+Enter to play as audio.", $nComb), 10, 10, 500, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $lst = GUICtrlCreateList("", 10, 35, 500, 340, BitOR($LBS_NOTIFY, $WS_VSCROLL, $WS_BORDER))
    Local $btnClose = GUICtrlCreateButton(_T("Close"), 10, 390, 500, 34)
    Local $aIds[$nComb + 1], $aTit[$nComb + 1], $aTyp[$nComb + 1], $i
    For $i = 0 To $nComb - 1
        _GUICtrlListBox_AddString($lst, ($i + 1) & ". " & $aCChan[$i] & " - " & $aCTitles[$i])
        $aIds[$i + 1] = $aCIds[$i]
        $aTit[$i + 1] = $aCTitles[$i]
        $aTyp[$i + 1] = "video"
    Next
    _GUICtrlListBox_SetCurSel($lst, 0)
    GUISetState(@SW_SHOW, $hGui)
    ControlFocus($hGui, "", $lst)
    Local $hEnter = GUICtrlCreateDummy(), $hAudio = GUICtrlCreateDummy()
    Local $aAcc[2][2] = [["{ENTER}", $hEnter], ["^{ENTER}", $hAudio]]
    GUISetAccelerators($aAcc, $hGui)
    Local $bEnterAcc = True
    While 1
        _SyncEnterAccel($hGui, $aAcc, $lst, $bEnterAcc)
        Local $nMsg = GUIGetMsg()
        If $nMsg = $hEnter Then
            Local $aBtn[1] = [$btnClose]
            Local $iBtn = _EnterFocusedButton($hGui, $aBtn)
            If $iBtn <> 0 Then $nMsg = $iBtn
        EndIf
        Switch $nMsg
            Case $GUI_EVENT_CLOSE, $btnClose
                GUIDelete($hGui)
                Return
            Case $hEnter, $hAudio
                Local $iIdx = _GUICtrlListBox_GetCurSel($lst)
                If $iIdx <> -1 Then
                    Local $aSvI = $aSearchIds, $aSvT = $aSearchTitles, $aSvY = $aSearchTypes, $iSvN = $iTotalLoaded
                    $aSearchIds = $aIds
                    $aSearchTitles = $aTit
                    $aSearchTypes = $aTyp
                    $iTotalLoaded = $nComb
                    _PlayLoop($iIdx, ($nMsg = $hAudio))
                    $aSearchIds = $aSvI
                    $aSearchTitles = $aSvT
                    $aSearchTypes = $aSvY
                    $iTotalLoaded = $iSvN
                EndIf
        EndSwitch
    WEnd
EndFunc

; Main window > YouTube Subscriptions
Func _YTS_SubsWindow($hParent = 0)
    Local $aSub = _YTS_Load()
    If Not IsArray($aSub) Then
        MsgBox(64, _T("YouTube subscriptions"), _T("You have no YouTube subscriptions yet. Open a channel and press Ctrl+D, or choose Subscribe to channel in the menu of a video."))
        Return
    EndIf
    Local $nSub = UBound($aSub), $i
    Local $aCnt[$nSub], $aNewest[$nSub]
    For $i = 0 To $nSub - 1
        $aCnt[$i] = _Sub_GetNew("yt", $aSub[$i][0])
        $aNewest[$i] = ""
    Next
    Local $aCIds[300], $aCTitles[300], $aCChan[300], $nComb = 0, $bChecked = False

    Local $hGui = GUICreate(_T("YouTube subscriptions"), 520, 440)
    GUISetBkColor($COLOR_BLUE)
    Local $lbl = GUICtrlCreateLabel(_TF("{1} YouTube channels. Press Enter to open one.", $nSub), 10, 10, 500, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $lst = GUICtrlCreateList("", 10, 35, 500, 300, BitOR($LBS_NOTIFY, $WS_VSCROLL, $WS_BORDER))
    Local $btnOpen = GUICtrlCreateButton(_T("&Open"), 10, 345, 160, 34)
    Local $btnCheck = GUICtrlCreateButton(_T("Chec&k for new videos"), 180, 345, 160, 34)
    Local $btnNew = GUICtrlCreateButton(_T("&New videos"), 350, 345, 160, 34)
    Local $btnUnsub = GUICtrlCreateButton(_T("&Unsubscribe (Delete)"), 10, 390, 245, 34)
    Local $btnClose = GUICtrlCreateButton(_T("&Close"), 265, 390, 245, 34)
    _YTS_FillList($lst, $aSub, $aCnt)
    _GUICtrlListBox_SetCurSel($lst, 0)
    GUISetState(@SW_SHOW, $hGui)
    ControlFocus($hGui, "", $lst)
    Local $hEnter = GUICtrlCreateDummy(), $hDel = GUICtrlCreateDummy()
    Local $aAcc[2][2] = [["{ENTER}", $hEnter], ["{DELETE}", $hDel]]
    GUISetAccelerators($aAcc, $hGui)
    Local $bEnterAcc = True

    While 1
        _SyncEnterAccel($hGui, $aAcc, $lst, $bEnterAcc)
        Local $nMsg = GUIGetMsg()
        If $nMsg = $hEnter Then
            Local $aBtn[5] = [$btnOpen, $btnCheck, $btnNew, $btnUnsub, $btnClose]
            Local $iBtn = _EnterFocusedButton($hGui, $aBtn)
            If $iBtn <> 0 Then $nMsg = $iBtn
        EndIf
        Local $iSel = _GUICtrlListBox_GetCurSel($lst)
        Switch $nMsg
            Case $GUI_EVENT_CLOSE, $btnClose
                ExitLoop
            Case $hEnter, $btnOpen
                If $iSel >= 0 Then
                    _ShowChannelVideos($aSub[$iSel][0], $aSub[$iSel][1], 100)
                    GUISwitch($hGui)
                    $aSub = _YTS_Load()
                    If Not IsArray($aSub) Or UBound($aSub) <> $nSub Then ExitLoop
                    $aCnt[$iSel] = _Sub_GetNew("yt", $aSub[$iSel][0])
                    _YTS_FillList($lst, $aSub, $aCnt)
                    _GUICtrlListBox_SetCurSel($lst, $iSel)
                    WinActivate($hGui)
                EndIf
            Case $btnCheck
                _YTS_CheckAll($aSub, $aCnt, $aCIds, $aCTitles, $aCChan, $nComb, $aNewest, $hGui)
                $bChecked = True
                _YTS_FillList($lst, $aSub, $aCnt)
                _GUICtrlListBox_SetCurSel($lst, Number($iSel > 0 ? $iSel : 0))
                ControlFocus($hGui, "", $lst)
                If $nComb > 0 Then
                    _ReportStatus(_TF("{1} new videos", $nComb))
                Else
                    _ReportStatus(_T("No new videos."))
                EndIf
            Case $btnNew
                If Not $bChecked Then
                    _YTS_CheckAll($aSub, $aCnt, $aCIds, $aCTitles, $aCChan, $nComb, $aNewest, $hGui)
                    $bChecked = True
                EndIf
                If $nComb = 0 Then
                    MsgBox(64, _T("YouTube subscriptions"), _T("No new videos."), 0, $hGui)
                Else
                    _YTS_NewVideosWindow($aCIds, $aCTitles, $aCChan, $nComb, $hGui)
                    GUISwitch($hGui)
                    ; they have been shown: from now on they are no longer new
                    For $i = 0 To $nSub - 1
                        If $aCnt[$i] > 0 And $aNewest[$i] <> "" Then
                            _YTS_SetSeen($aSub[$i][0], $aNewest[$i])
                            _Sub_SetNew("yt", $aSub[$i][0], 0)
                            $aCnt[$i] = 0
                        EndIf
                    Next
                    $aSub = _YTS_Load()
                    $nComb = 0
                    $bChecked = False
                    _YTS_FillList($lst, $aSub, $aCnt)
                    _GUICtrlListBox_SetCurSel($lst, 0)
                    WinActivate($hGui)
                EndIf
                ControlFocus($hGui, "", $lst)
            Case $hDel, $btnUnsub
                If $iSel >= 0 Then
                    If MsgBox(36, _T("YouTube subscriptions"), _TF("Unsubscribe from {1}?", $aSub[$iSel][1]), 0, $hGui) = 6 Then
                        Local $sRemoved = $aSub[$iSel][1]
                        _YTS_Unsubscribe($aSub[$iSel][0])
                        _AppSoundPlay(@ScriptDir & "\sounds\ok.wav")
                        $aSub = _YTS_Load()
                        If Not IsArray($aSub) Then
                            MsgBox(64, _T("YouTube subscriptions"), _TF("Unsubscribed from {1}", $sRemoved), 0, $hGui)
                            ExitLoop
                        EndIf
                        $nSub = UBound($aSub)
                        ReDim $aCnt[$nSub]
                        ReDim $aNewest[$nSub]
                        For $i = 0 To $nSub - 1
                            $aCnt[$i] = _Sub_GetNew("yt", $aSub[$i][0])
                        Next
                        $bChecked = False
                        $nComb = 0
                        GUICtrlSetData($lbl, _TF("{1} YouTube channels. Press Enter to open one.", $nSub))
                        _YTS_FillList($lst, $aSub, $aCnt)
                        _GUICtrlListBox_SetCurSel($lst, 0)
                        _ReportStatus(_TF("Unsubscribed from {1}", $sRemoved))
                    EndIf
                    ControlFocus($hGui, "", $lst)
                EndIf
        EndSwitch
        Sleep(10)
    WEnd
    GUIDelete($hGui)
EndFunc

; ---------- check for new content when the application starts ----------
; Runs in small steps from Adlib so the window stays responsive. Paused while another window (player...) is open.
Func _Sub_StartupCheck()
    If $g_bSubWindowOpen Then Return ; try again later
    AdlibUnRegister("_Sub_StartupCheck")
    Local $aPod = _Pod_SubLoad(), $aYT = _YTS_Load()
    Local $nP = 0, $nY = 0, $i, $k = 0
    If IsArray($aPod) Then $nP = UBound($aPod)
    If IsArray($aYT) Then $nY = UBound($aYT)
    If $nP + $nY = 0 Then Return
    Local $aJobs[$nP + $nY][4]
    For $i = 0 To $nP - 1
        $aJobs[$k][0] = "pod"
        $aJobs[$k][1] = $aPod[$i][0]
        $aJobs[$k][2] = $aPod[$i][3]
        $aJobs[$k][3] = $aPod[$i][1]
        $k += 1
    Next
    For $i = 0 To $nY - 1
        $aJobs[$k][0] = "yt"
        $aJobs[$k][1] = $aYT[$i][0]
        $aJobs[$k][2] = $aYT[$i][2]
        $aJobs[$k][3] = $aYT[$i][1]
        $k += 1
    Next
    $g_aSubJobs = $aJobs
    $g_iSubJobN = $k
    $g_iSubJobI = 0
    $g_iSubPid = 0
    $g_iSubNewPod = 0
    $g_iSubNewYT = 0
    AdlibRegister("_Sub_Tick", 300)
EndFunc

Func _Sub_Tick()
    If $g_bSubWindowOpen Then Return
    If $g_iSubJobI >= $g_iSubJobN Then
        _Sub_Finish()
        Return
    EndIf
    If $g_aSubJobs[$g_iSubJobI][0] = "pod" Then
        _Sub_CheckPodcastJob($g_iSubJobI)
        $g_iSubJobI += 1
        Return
    EndIf
    ; YouTube channel: yt-dlp runs in the background, we only look at it from time to time
    If $g_iSubPid = 0 Then
        $g_iSubPid = Run(_YTS_CmdFetch($g_aSubJobs[$g_iSubJobI][1], 30), @ScriptDir, @SW_HIDE, $STDOUT_CHILD + $STDERR_CHILD)
        If @error Or $g_iSubPid = 0 Then
            $g_iSubPid = 0
            $g_iSubJobI += 1
            Return
        EndIf
        $g_bSubData = Binary("")
        $g_hSubTimer = TimerInit()
        Return
    EndIf
    $g_bSubData &= StdoutRead($g_iSubPid, False, True)
    StderrRead($g_iSubPid)
    If ProcessExists($g_iSubPid) Then
        If TimerDiff($g_hSubTimer) > 60000 Then ; too slow: skip this channel
            ProcessClose($g_iSubPid)
            $g_iSubPid = 0
            $g_iSubJobI += 1
        EndIf
        Return
    EndIf
    $g_bSubData &= StdoutRead($g_iSubPid, False, True)
    $g_iSubPid = 0
    Local $aIds[1], $aTit[1]
    Local $n = _YTS_Parse(BinaryToString($g_bSubData, 4), $aIds, $aTit)
    If $n > 0 Then _Sub_Record("yt", $g_aSubJobs[$g_iSubJobI][1], _YTS_NewCount($aIds, $n, $g_aSubJobs[$g_iSubJobI][2]), $aIds[0])
    $g_iSubJobI += 1
EndFunc

Func _Sub_CheckPodcastJob($i)
    Local $sXml = _Pod_Http($g_aSubJobs[$i][1], 8000)
    If $sXml = "" Then Return
    Local $sT = "", $sA = ""
    Local $aEp = _Pod_ParseFeed($sXml, $sT, $sA)
    If Not IsArray($aEp) Then Return
    Local $iEpN = UBound($aEp)
    Local $iNew = _Pod_NewCount($aEp, $iEpN, $g_aSubJobs[$i][2]), $k, $iUnplayed = 0
    Local $sPlayed = _Pod_PlayedSet()
    For $k = 0 To $iNew - 1
        If Not StringInStr($sPlayed, @LF & StringLower($aEp[$k][4]) & @LF) Then $iUnplayed += 1
    Next
    _Sub_Record("pod", $g_aSubJobs[$i][1], $iUnplayed, $aEp[0][4])
EndFunc

; Remembers what was found; counts it for the announcement only if it was not announced before
Func _Sub_Record($sType, $sId, $iNew, $sNewestKey)
    _Sub_SetNew($sType, $sId, $iNew)
    If $iNew <= 0 Then Return
    Local $sKey = $sType & ":" & $sId
    If _Sub_NotifiedGet($sKey) = _Pod_Clean($sNewestKey) Then Return
    _Sub_NotifiedSet($sKey, $sNewestKey)
    If $sType = "pod" Then
        $g_iSubNewPod += $iNew
    Else
        $g_iSubNewYT += $iNew
    EndIf
EndFunc

Func _Sub_Finish()
    AdlibUnRegister("_Sub_Tick")
    Local $iP = $g_iSubNewPod, $iY = $g_iSubNewYT
    $g_iSubNewPod = 0
    $g_iSubNewYT = 0
    If $iP + $iY = 0 Then Return ; nothing new: no sound, no message
    _AppSoundPlay(@ScriptDir & "\sounds\new_content.wav")
    Local $s
    If $iP > 0 And $iY > 0 Then
        $s = _TF("New content: {1} new podcast episodes and {2} new YouTube videos.", $iP, $iY)
    ElseIf $iP > 0 Then
        $s = _TF("New content: {1} new podcast episodes.", $iP)
    Else
        $s = _TF("New content: {1} new YouTube videos.", $iY)
    EndIf
    _NVDA_Speak($s)
EndFunc
