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
Local $iWaitMax = 0
If $CmdLine[0] > 0 Then
    For $i = 1 To $CmdLine[0]
        If $CmdLine[$i] = "/restart" Then
            $iWaitMax = 30 ; Wait up to 3 seconds for old instance to exit
            ExitLoop
        EndIf
    Next
EndIf

Local $iWaitCount = 0
While _Singleton("VDHMediaCenterApp", 1) = 0
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
    
    $hVLC_Dll = DllOpen($sDll)
    
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

Func _VLC_GetAudioOutputs()
    Local $aResult[1][2] = [["", "Default Audio Device"]]
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

Func _VLC_Direct_Play($sUrl)
    If Not _VLC_Direct_Init() Then Return
    
    Local $iState = _VLC_Direct_GetState()
    If $iState > 0 And $iState < 5 Then
        DllCall($hVLC_Dll, "none:cdecl", "libvlc_media_player_stop", "ptr", $oVLC_Player)
    EndIf
    
    Local $aRet = DllCall($hVLC_Dll, "ptr:cdecl", "libvlc_media_new_location", "ptr", $oVLC_Inst, "str", $sUrl)
    Local $pMedia = $aRet[0]
    If Not $pMedia Then Return
    
    DllCall($hVLC_Dll, "none:cdecl", "libvlc_media_player_set_media", "ptr", $oVLC_Player, "ptr", $pMedia)
    
    DllCall($hVLC_Dll, "none:cdecl", "libvlc_media_release", "ptr", $pMedia)
    
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
    _ReportStatus("Volume: " & $g_iAppVolume & "%")
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

Global $version = "2.6"
Global $YT_DLP_PATH = @ScriptDir & "\lib\yt-dlp.exe"

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


Global $mainform
Global $cbo_dl_format, $btn_start_dl, $openbtn, $paste
Global $linkedit, $play_btn, $online_play_btn
Global $btn_Menu_Audio
Global $g_sSupportedAudioExts = ".mp3;.m4a;.wav;.ogg;.flac;.aac;.wma;.opus;.mp4;"
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
Global $menu_item_download = -1, $menu_item_channel = -1, $menu_item_browser = -1, $menu_item_copy = -1, $menu_item_desc = -1, $menu_item_comments = -1, $menu_item_fav = -1, $menu_item_goto = -1, $menu_share_telegram = -1, $menu_share_facebook = -1, $menu_item_sleeptimer = -1, $menu_item_fileinfo = -1
Global $menu_item_add_col = -1, $menu_item_remove_col = -1
Global $g_fSelectionStart = -1, $g_fSelectionEnd = -1
Global $g_fPitch = 1.0
Global $g_bCinemaMode = False
Global $g_iOriginalX, $g_iOriginalY, $g_iOriginalW, $g_iOriginalH
Global $hDummySpace, $hDummyEnter, $hDummyN, $hDummyUp, $hDummyDown, $hDummyLeft, $hDummyRight, $hDummyAltO
Global $hDummyCtrlLeft, $hDummyCtrlRight, $hDummyCtrlT, $hDummyCtrlShiftT, $hDummyHome, $hDummyEnd
Global $hDummyI
Global $hDummy1, $hDummy2, $hDummy3, $hDummy4, $hDummy5, $hDummy6, $hDummy7, $hDummy8, $hDummy9, $hDummyP
Global $hDummyR, $hDummyRemaining, $hDummyShiftN, $hDummyShiftB, $hDummyCtrlW, $hDummyMinus, $hDummyEqual, $hDummyS, $hDummyD, $hDummyF, $hDummyCtrlShiftE, $hDummyEsc, $hDummyG, $hDummyApps, $hDummyBracketLeft, $hDummyBracketRight, $hDummyCtrlS, $hDummyCtrlK, $hDummyCtrlC, $hDummyCtrlShiftC, $hDummyCtrlShiftD, $hDummyAltB, $hDummyAltG
Global $hDummyB ; "b" key: previous track (only active while a folder playlist is loaded)
Global $hDummyCtrlHome, $hDummyCtrlEnd ; Ctrl+Home/Ctrl+End: first/last track (folder playlist only)
Global $g_aLocalPlaylist[1] = [""]
Global $g_iLocalPlaylistCount = 0
Global $g_bLocalPlaylistMode = False ; True only while playing a folder-loaded playlist (enables n/b navigation)
Global $g_sLastReportedText = "", $g_iLastReportedTime = 0
Global $g_sCurrentVideoTitle = ""
Global $g_sSearchFilter = "No Filter"
Global $g_hSettingsGui, $g_hSettingsTab, $g_hSettingsDummyNext, $g_hSettingsDummyPrev
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
Global $g_bAutoDetectLink = IniRead($CONFIG_FILE, "Settings", "AutoDetectLink", "true") == "true"
Global $g_bVoiceAutoSearch = IniRead($CONFIG_FILE, "Settings", "VoiceAutoSearch", "true") == "true"
Global $g_bAutoPlay = IniRead($CONFIG_FILE, "Settings", "AutoPlay", "false") == "true"
Global $g_bRepeat = IniRead($CONFIG_FILE, "Settings", "Repeat", "false") == "true"
Global $g_sSearchFilter = IniRead($CONFIG_FILE, "Settings", "SearchFilter", "No Filter")
Global $g_sDownloadPath = IniRead($CONFIG_FILE, "Settings", "DownloadPath", @ScriptDir & "\download")
If StringStripWS($g_sDownloadPath, 3) = "" Then $g_sDownloadPath = @ScriptDir & "\download"
Global $PLAYBACK_POSITIONS_FILE = $SETTINGS_DIR & "\playback_positions.dat"
Global $g_bContinueWatching = IniRead($CONFIG_FILE, "Settings", "ContinueWatching", "true") == "true"
$g_iFFStep = Int(IniRead($CONFIG_FILE, "Settings", "FFStep", "5"))
$g_iRWStep = Int(IniRead($CONFIG_FILE, "Settings", "RWStep", "5"))
$g_iSeekStep = $g_iFFStep

If Not FileExists($g_sDownloadPath) Then DirCreate($g_sDownloadPath)

If Not FileExists($YT_DLP_PATH) Then
    MsgBox(16, "Error", "The file lib\yt-dlp.exe does not exist!" & @CRLF & "Please double-check the lib folder.")
EndIf

; --- Yeu cau chap nhan giay phep (chi hien o lan chay dau tien) ---
If IniRead($CONFIG_FILE, "License", "Accepted", "false") <> "true" Then
    If Not _Show_License_Window() Then Exit
    IniWrite($CONFIG_FILE, "License", "Accepted", "true")
EndIf

$lding=GUICreate("loading",300,300)
GUISetBkColor($COLOR_BLUE)
GuiCtrlCreateLabel("Welcome to VDH Productions", 10, 25)
GUICtrlSetColor(-1, 0xFFFFFF)
GUISetState()

Global $sVLC_Path = @ScriptDir & "\lib\VLC"
If @AutoItX64 Then $sVLC_Path = @ScriptDir & "\lib\VLC64"
_VLC_Direct_Init()

SoundPlay(@ScriptDir & "\sounds\start.wav")
Local $hStartTimer = TimerInit()
While TimerDiff($hStartTimer) < 500
    GUIGetMsg()
    Sleep(3000)
WEnd
GUIDelete($lding)

$mainform = GUICreate("VDHMediaCenter version" & $version, 300, 355)
GUISetBkColor($COLOR_BLUE)
GUISetFont(9, 400, 0, "Segoe UI")

Local $sGreeting = "Good Evening"
If @HOUR >= 0 And @HOUR < 12 Then
    $sGreeting = "Good morning"
ElseIf @HOUR >= 12 And @HOUR < 18 Then
    $sGreeting = "Good afternoon"
ElseIf @HOUR >= 18 And @HOUR < 22 Then
    $sGreeting = "Good evening"
Else
    $sGreeting = "Good night"
EndIf
$label = GUICtrlCreateLabel($sGreeting & " and warm welcome to VDHMediaCenter application.", 10, 10, 280, 50, BitOR($SS_LEFT, $WS_TABSTOP))
GUICtrlSetFont(-1, 14, 800)
GUICtrlSetColor(-1, 0xFFFFFF)

Global $btn_Menu_DL = GUICtrlCreateButton("Download from link (Alt+D)", 50, 60, 200, 40)
Global $btn_Menu_PL = GUICtrlCreateButton("Play YouTube link (Alt+P)", 50, 105, 200, 40)
Global $btn_Menu_Direct = GUICtrlCreateButton("Play direct link (Alt+L)", 50, 150, 200, 40)
Global $btn_Menu_SC = GUICtrlCreateButton("Search on YouTube (Alt+S)", 50, 195, 200, 40)
Global $btn_Menu_CL = GUICtrlCreateButton("Your Collections (Alt+C)", 50, 240, 200, 40)
Global $btn_Menu_Audio = GUICtrlCreateButton("Listen to Audio File (Alt+U)", 50, 285, 200, 40)
Global $btn_Menu_FV = GUICtrlCreateButton("Favorites (Alt+F)", 10, 330, 100, 30)
Global $btn_Menu_WS = GUICtrlCreateButton("Watch History (Alt+W)", 120, 330, 150, 30)

Global $menu_main = GUICtrlCreateMenu("Preferences")
Global $menu_settings = GUICtrlCreateMenuItem("Settings... (Ctrl+Shift+S)", $menu_main)
Global $menu_exit = GUICtrlCreateMenuItem("Exit...", $menu_main)

Global $menu_help = GUICtrlCreateMenu("Help")
Global $menu_about = GUICtrlCreateMenuItem("About...", $menu_help)
Global $menu_website = GUICtrlCreateMenuItem("Visit &Website...", $menu_help)
Global $menu_readme = GUICtrlCreateMenuItem("Readme...", $menu_help)
Global $menu_contact = GUICtrlCreateMenuItem("Contact...", $menu_help)
Global $menu_update_ytdlp = GUICtrlCreateMenuItem("Checked for updates &yt_dlp...", $menu_help)
Global $menu_Update_app = GUICtrlCreateMenuItem("Checked for &Updates...", $menu_help)
Global $menuChangelog = GuiCtrlCreateMenuItem("view changelog...", $menu_help)
Global $menuContribute = GuiCtrlCreateMenuItem("con&tribute...", $menu_help)
Global $menuSendFeedback = GuiCtrlCreateMenuItem("Send &feedback...", $menu_help)

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

    ; Vo hieu hoa + an giao dien chinh de no khong the nhan phim/chuot nua
    If IsHWnd($mainform) Then
        GUISetState(@SW_DISABLE, $mainform)
        GUISetState(@SW_HIDE, $mainform)
    EndIf

    Call($sFunc)

    ; Tra lai giao dien chinh
    If IsHWnd($mainform) Then
        GUISetState(@SW_ENABLE, $mainform)
        GUISetState(@SW_SHOW, $mainform)
        WinActivate($mainform)
        ControlFocus($mainform, "", $label)
    EndIf

    $g_bSubWindowOpen = False
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


Func _ShowDirectLinkPlayer()
    Local $hDirectGui = GUICreate("Direct Link Player", 400, 150, -1, -1, BitOR($WS_CAPTION, $WS_POPUPWINDOW, $WS_VISIBLE))
    GUISetBkColor($COLOR_BLUE, $hDirectGui)

    GUICtrlCreateLabel("Enter Direct URL:", 10, 20, 380, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $inpUrl = GUICtrlCreateInput("", 10, 45, 380, 20)

    Local $btnOk = GUICtrlCreateButton("OK", 80, 80, 100, 30, $GUI_DEFBUTTON)
    Local $btnCancel = GUICtrlCreateButton("Cancel", 200, 80, 100, 30)

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
                    MsgBox(16, "Error", "Please enter the Direct URL!")
                Else
                    GUIDelete($hDirectGui)
                    
                    ; Create loading dialog
                    Local $hLoading = GUICreate("Loading", 250, 80, -1, -1, BitOR($WS_POPUP, $WS_BORDER), BitOR($WS_EX_TOPMOST, $WS_EX_TOOLWINDOW))
                    GUICtrlCreateLabel("Loading stream, please wait...", 10, 25, 230, 30, $SS_CENTER)
                    GUISetBkColor(0xFFFFFF, $hLoading)
                    GUISetState(@SW_SHOW, $hLoading)
                    ; Thông báo cho NVDA
                    _NVDA_Speak("Loading stream, please wait.")
                    
                    ; Phát loading.wav (không chặn) và ok.wav
                    SoundPlay(@ScriptDir & "\sounds\loading.wav") 
                    SoundPlay(@ScriptDir & "\sounds\ok.wav")
                    
                    ; Giảm trì hoãn để phản hồi nhanh hơn
                    Sleep(200)
                    
                    _PlayInternal($sUrl, "Direct Link Player", False, $hLoading, False, "")
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

Local $aAccel[16][2] = [ _
    ["^+u", $hDummyUpdateApp], _
    ["^+y", $hDummyUpdateYTDLP], _
    ["{F1}", $hDummyReadme], _
    ["!d", $btn_Menu_DL], _
    ["!p", $btn_Menu_PL], _
    ["!l", $btn_Menu_Direct], _
    ["!s", $btn_Menu_SC], _
    ["!c", $btn_Menu_CL], _
    ["!u", $btn_Menu_Audio], _
    ["!f", $btn_Menu_FV], _
    ["!w", $btn_Menu_WS], _
    ["{F2}", $hDummyChangelog], _
    ["^w", $menu_exit], _
    ["{ESC}", $hDummyEscMain], _
    ["^+s", $hDummySettings], _
    ["{ENTER}", $hDummyEnterMain] _
]
GUISetAccelerators($aAccel, $mainform)

If $g_bAutoDetectLink Then _AutoDetectClipboardLink()
_AddDefenderExclusion()

; Auto update check if enabled (app update and/or yt-dlp update)
If $g_bAutoUpdate Or $g_bAutoUpdateYTDLP Then
    AdlibRegister("_CheckUpdatesSilently", 5000) ; Wait 5s after start to not bother user immediately
EndIf

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
        EndSwitch
    EndIf

    Switch $msg
        Case $GUI_EVENT_CLOSE, $menu_exit
            SoundPlay(@ScriptDir & "\sounds\exit.wav", 1)
            ProcessClose("comments.exe")
            ProcessClose("description.exe")
            _VLC_Cleanup()
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
        Case $menu_readme
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

; Chạy lệnh tải xuống (yt-dlp) với cửa sổ console ẩn.
; Không đọc luồng xuất qua pipe (tránh rủi ro treo tiến trình nếu bộ đệm đầy),
; thay vào đó hiển thị thanh tiến trình dạng "đang chạy" kèm thời gian đã trôi qua.
; Trả về True nếu tải xong, False nếu người dùng huỷ (đóng cửa sổ).
Func _RunDownloadWithProgress($sCmd, $idProgress = -1, $idLabel = -1)
    Local $iPid = Run($sCmd, @ScriptDir, @SW_HIDE)
    Local $iStart = TimerInit()
    Local $iFakePct = 0

    If $idProgress <> -1 Then GUICtrlSetData($idProgress, 0)
    If $idLabel <> -1 Then GUICtrlSetData($idLabel, "Đang tải xuống...")

    While ProcessExists($iPid)
        $iFakePct += 2
        If $iFakePct > 100 Then $iFakePct = 0
        If $idProgress <> -1 Then GUICtrlSetData($idProgress, $iFakePct)
        If $idLabel <> -1 Then
            Local $iElapsed = Int(TimerDiff($iStart) / 1000)
            GUICtrlSetData($idLabel, "Đang tải xuống... (" & $iElapsed & "s)")
        EndIf

        If GUIGetMsg() = $GUI_EVENT_CLOSE Then
            ProcessClose($iPid)
            Return False
        EndIf
        Sleep(150)
    WEnd

    If $idProgress <> -1 Then GUICtrlSetData($idProgress, 100)
    If $idLabel <> -1 Then GUICtrlSetData($idLabel, "Hoàn tất!")
    Return True
EndFunc

Func _ShowDownloader()
    GUISetState(@SW_HIDE, $mainform)
    $g_hGuiDL = GUICreate("Video Downloader", 400, 420)
    GUISetBkColor($COLOR_BLUE)

    $g_hTabDL = GUICtrlCreateTab(10, 10, 380, 40)
    Local $aTabNames[5] = ["YouTube", "Facebook", "TikTok", "Instagram", "SoundCloud"]
    Local $aTabItems[5]
    Local $g_aInpLinks[5]
    For $i = 0 To 4
        $aTabItems[$i] = GUICtrlCreateTabItem($aTabNames[$i])
        GUICtrlCreateLabel("Enter the " & $aTabNames[$i] & " URL link here:", 10, 60, 380, 20)
        GUICtrlSetColor(-1, 0xFFFFFF)
        $g_aInpLinks[$i] = GUICtrlCreateInput("", 10, 85, 380, 20)
        GUICtrlSetTip(-1, "Enter the " & $aTabNames[$i] & " track/video URL here")
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

    $paste = GUICtrlCreateButton("Paste Link (Alt+P)", 320, 115, 70, 20)

    GUICtrlCreateLabel("Select Format :", 10, 115, 180, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    $cbo_dl_format = GUICtrlCreateCombo("", 10, 140, 180, 20, $CBS_DROPDOWNLIST)
    GUICtrlSetTip(-1, "Chọn định dạng tải xuống, dùng phím mũi tên để duyệt danh sách theo thứ tự bảng chữ cái")
    GUICtrlSetData(-1, "M4A (Audio)|MP3 (Audio)|MP4 (Video, Best)|OGG (Audio)|WAV (Audio)|WebM (Video)", "MP4 (Video, Best)")

    GUICtrlCreateLabel("Select Bitrate:", 210, 115, 180, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    $cbo_dl_bitrate = GUICtrlCreateCombo("", 210, 140, 180, 20, $CBS_DROPDOWNLIST)
    GUICtrlSetTip(-1, "Chọn tốc độ bit (kbps), dùng phím mũi tên để duyệt từ thấp đến cao")
    GUICtrlSetData(-1, "128 kbps|192 kbps|256 kbps|320 kbps", "320 kbps")

    Local $chk_custom_name = GUICtrlCreateCheckbox("Choose custom output filename composition", 10, 170, 380, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $cbo_name_type = GUICtrlCreateCombo("", 10, 195, 380, 20, $CBS_DROPDOWNLIST)
    GUICtrlSetTip(-1, "Chọn kiểu đặt tên tệp, dùng phím mũi tên để duyệt danh sách theo thứ tự bảng chữ cái")
    GUICtrlSetData(-1, "No numbering|No numbering and create subdirectory|Numbering|Numbering and create subdirectory", "No numbering")
    GUICtrlSetState(-1, $GUI_DISABLE)

    $btn_start_dl = GUICtrlCreateButton("Download (Alt+D)", 10, 230, 380, 40)
    $openbtn = GUICtrlCreateButton("Open Download Folder (Alt+O)", 10, 280, 380, 30)
    Local $btn_close = GUICtrlCreateButton("Close", 10, 320, 380, 30)

    Local $lbl_dl_status = GUICtrlCreateLabel("", 10, 355, 380, 16)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $prog_dl = GUICtrlCreateProgress(10, 375, 380, 20)

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
                    MsgBox(16, "Error", "Please enter the URL!")
                Else
                    If Not _IsUrlMatchTab($url, $iCurTab) Then
                        Local $sTabName = _GUICtrlTab_GetItemText(GUICtrlGetHandle($g_hTabDL), $iCurTab)
                        MsgBox(16, "Error", "The current link is not supported in the " & $sTabName & " tab. Please switch to the correct tab or use a valid link.")
                        ContinueLoop
                    EndIf

                    Local $sTxt = GUICtrlRead($cbo_dl_format)
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
                        Local $sNameSel = GUICtrlRead($cbo_name_type)
                        If $sNameSel = "No numbering and create subdirectory" Then
                            $sOutTemplate = "%(title)s/%(title)s.%(ext)s"
                        ElseIf $sNameSel = "Numbering" Then
                            $sOutTemplate = "%(playlist_index)s - %(title)s.%(ext)s"
                        ElseIf $sNameSel = "Numbering and create subdirectory" Then
                            $sOutTemplate = "%(playlist_title)s/%(playlist_index)s - %(title)s.%(ext)s"
                        EndIf
                    EndIf

                    GUICtrlSetState($btn_start_dl, $GUI_DISABLE)
                    Local $sFinalDownloadPath = $g_sDownloadPath
                    If StringStripWS($sFinalDownloadPath, 3) = "" Then $sFinalDownloadPath = @ScriptDir & "\download"
                    If Not FileExists($sFinalDownloadPath) Then DirCreate($sFinalDownloadPath)
                    While StringRight($sFinalDownloadPath, 1) = "\" Or StringRight($sFinalDownloadPath, 1) = "/"
                        $sFinalDownloadPath = StringTrimRight($sFinalDownloadPath, 1)
                    WEnd
                    Local $sCmd = $YT_DLP_EXE & ' ' & $sFmt & ' ' & $sExtraArgs & ' -P "' & $sFinalDownloadPath & '" --ffmpeg-location "' & @ScriptDir & '\lib" -o "' & $sOutTemplate & '" -- "' & $url & '"'
                    Local $bDLDone = _RunDownloadWithProgress($sCmd, $prog_dl, $lbl_dl_status)
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
SoundPlay(@ScriptDir & "\sounds\download_finish.wav")
                    MsgBox(64, "Info", "Download Complete!")
                EndIf
        EndSwitch
    WEnd
EndFunc

Func _ShowPlayer()
    GUISetState(@SW_HIDE, $mainform)
    Local $hGuiPL = GUICreate("YouTube Player", 400, 290)
    GUISetBkColor($COLOR_BLUE)

    GUICtrlCreateLabel("Enter the video link you want to play:", 10, 20, 380, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    $linkedit = GUICtrlCreateInput("", 10, 50, 380, 20)

    $play_btn = GUICtrlCreateButton("Play (Default Player) (Alt+P)", 50, 80, 300, 35)
    $audio_play_btn = GUICtrlCreateButton("Play as Audio (Alt+A)", 50, 125, 300, 35)
    $online_play_btn = GUICtrlCreateButton("Play in Browser (Alt+B)", 50, 170, 300, 35)
    Local $btn_close_PL = GUICtrlCreateButton("Close", 50, 215, 300, 35)

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
                    MsgBox(16, "Error", "Please enter the video link!")
                Else
                    playmedia($input_text)
                EndIf

            Case $audio_play_btn
                Local $input_text = GUICtrlRead($linkedit)
                If $input_text = "" Then
                    MsgBox(16, "Error", "Please enter the video link!")
                Else
                    playaudio($input_text)
                EndIf

            Case $online_play_btn
                Local $input_text = GUICtrlRead($linkedit)
                If $input_text = "" Then
                    MsgBox(16, "Error", "Please enter the video link!")
                Else
                    online_play($input_text)
                EndIf
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
    GUISetState(@SW_HIDE, $mainform)
    $hCurrentSubGui = GUICreate("Search", 400, 160)
    GUISetBkColor($COLOR_BLUE)

    GUICtrlCreateLabel("Enter keyword to search:", 10, 15, 80, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    $inp_search = GUICtrlCreateInput("", 100, 12, 210, 20)
    
    ; Subclass search input for typing sounds
    Local $hEdit = GUICtrlGetHandle($inp_search)
    $g_hSearchEditCallback = DllCallbackRegister("_SearchEditProc", "lresult", "hwnd;uint;wparam;lparam")
    Local $aRet = DllCall("user32.dll", "ptr", "SetWindowLong" & (@AutoItX64 ? "Ptr" : "") & "W", "hwnd", $hEdit, "int", -4, "ptr", DllCallbackGetPtr($g_hSearchEditCallback)) ; -4 = GWL_WNDPROC
    $g_pOldSearchEditProc = $aRet[0]

    GUICtrlCreateLabel("Filter:", 10, 50, 80, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $cbo_filter = GUICtrlCreateCombo("", 100, 47, 210, 20, $CBS_DROPDOWNLIST)
    GUICtrlSetTip(-1, "Chọn bộ lọc tìm kiếm, dùng phím mũi tên để duyệt danh sách theo thứ tự bảng chữ cái")
    GUICtrlSetData(-1, "4K|Channels|lives|Most viewed|No Filter|Playlist|Rating|Shorts|This Month|This Week|upload date|Video", $g_sSearchFilter)

    $btn_search_go = GUICtrlCreateButton("Search (Alt+S)", 320, 10, 70, 25)
    GUICtrlSetState(-1, $GUI_DEFBUTTON)

    Local $btn_voice_search = GUICtrlCreateButton("Voice search (Alt+V)", 320, 47, 70, 25)

    $btn_search_hist = GUICtrlCreateButton("Search History (Alt+H)", 100, 90, 210, 30)

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
                    SoundPlay(@ScriptDir & "\sounds\start_voice_search.wav")
                    Local $pid = Run('"' & $VOICE_SEARCH_EXE_PATH & '"', @ScriptDir & "\lib", @SW_HIDE, $STDOUT_CHILD + $STDERR_CHILD)
                    If @error Then
                        MsgBox(16, "Error", "Failed to start voice_search.exe. Error code: " & @error)
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
                    SoundPlay(@ScriptDir & "\sounds\stop_voice_search.wav")

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
                            SoundPlay(@ScriptDir & "\sounds\error.wav")
                        ElseIf StringInStr($sError, "check your microphone") Then
                            SoundPlay(@ScriptDir & "\sounds\error.wav")
                        ElseIf StringInStr($sError, "listening timed out") Then
                            SoundPlay(@ScriptDir & "\sounds\error.wav")
                        ElseIf StringInStr($sError, "internet") Or StringInStr($sError, "network") Or StringInStr($sError, "connection") Then
                            SoundPlay(@ScriptDir & "\sounds\no_internet.wav")
                        EndIf
                    ElseIf $sResult <> "" Then
                        GUICtrlSetData($inp_search, $sResult)
                        ; ControlFocus($hCurrentSubGui, "", $inp_search)
                        
                        If $g_bVoiceAutoSearch Then
                            $sCurrentKeyword = $sResult
                            $g_sSearchFilter = GUICtrlRead($cbo_filter)
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
                        SoundPlay(@ScriptDir & "\sounds\error.wav")
                    EndIf
                    GUICtrlSetState($btn_voice_search, $GUI_ENABLE)
                Else
                    MsgBox(16, "Error", "voice_search.exe not found in lib folder!")
                EndIf

            Case $btn_search_go
                $sCurrentKeyword = GUICtrlRead($inp_search)
                $g_sSearchFilter = GUICtrlRead($cbo_filter)
                IniWrite($CONFIG_FILE, "Settings", "SearchFilter", $g_sSearchFilter)
                If $sCurrentKeyword = "" Then
                    MsgBox(16, "Error", "Please enter a keyword to search!")
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
    GUISetState(@SW_HIDE, $hCurrentSubGui)

    $hSearchHistoryGui = GUICreate("Search History", 350, 466)
    GUISetBkColor($COLOR_BLUE)

    GUICtrlCreateLabel("Your search history:", 10, 10, 330, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    GUICtrlSetFont(-1, 10, 800)
    Local $lst_hist = GUICtrlCreateList("", 10, 35, 330, 325, BitOR($LBS_NOTIFY, $WS_VSCROLL, $WS_BORDER))

    Local $btn_remove = GUICtrlCreateButton("Delete From History", 10, 370, 160, 30)
    Local $btn_clear = GUICtrlCreateButton("Clear All History", 180, 370, 160, 30)
    Local $btn_back = GUICtrlCreateButton("Go Back", 10, 410, 330, 30)

    GUISetState(@SW_SHOW, $hSearchHistoryGui)

    _LoadSearchHistoryList($lst_hist)
    _GUICtrlListBox_SetCurSel($lst_hist, 0)
    ControlFocus($hSearchHistoryGui, "", $lst_hist)

    Local $hDummyEnterSearchHist = GUICtrlCreateDummy()
    Local $aAccelSearchHist[1][2] = [["{ENTER}", $hDummyEnterSearchHist]]
    GUISetAccelerators($aAccelSearchHist, $hSearchHistoryGui)

    While 1
        Local $nMsg = _GuiMsg($hSearchHistoryGui)

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
                If MsgBox(36, "Confirm", "Are you sure you want to delete all search history?") = 6 Then
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
    GUISetState(@SW_HIDE, $hCurrentSubGui)

    $hResultsGui = GUICreate("Search Results", 400, 472)
    GUISetBkColor($COLOR_BLUE)
    GUICtrlCreateLabel("Search results:", 10, 10, 380, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    GUICtrlSetFont(-1, 10, 800)
    $lst_results = GUICtrlCreateList("", 10, 35, 380, 355, BitOR($LBS_NOTIFY, $WS_VSCROLL, $WS_BORDER))
    Local $btn_return_main = GUICtrlCreateButton("return to main window", 10, 400, 380, 30)

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
        If $g_sSearchFilter <> "No Filter" Then $sLoadingText &= " (" & $g_sSearchFilter & ")"
        $hWaitGui = GUICreate("Searching", 250, 80, -1, -1, BitOR($WS_POPUP, $WS_BORDER), BitOR($WS_EX_TOPMOST, $WS_EX_TOOLWINDOW), $hResultsGui)
        GUICtrlCreateLabel($sLoadingText & "...", 10, 25, 230, 20, $SS_CENTER)
        GUISetBkColor(0xFFFFFF, $hWaitGui)
        GUISetState(@SW_SHOW, $hWaitGui)
        GUISetCursor(15, 1)
        DllCall("winmm.dll", "int", "PlaySoundW", "wstr", @ScriptDir & "\sounds\loading.wav", "ptr", 0, "dword", 0x0009)
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

            If IsArray($sIdMatch) And IsArray($sTitleMatch) Then
                $sCurrentId = $sIdMatch[0]
                $sCurrentTitle = _UnescapeJSON($sTitleMatch[0])

                $sCurrentDur = ""
                If IsArray($sDurMatch) Then $sCurrentDur = $sDurMatch[0]
                $sCurrentUp = ""
                If IsArray($sUploaderMatch) Then $sCurrentUp = _UnescapeJSON($sUploaderMatch[0])
                $sCurrentViews = ""
                If IsArray($sViewMatch) Then $sCurrentViews = $sViewMatch[0]
                $sCurrentDate = ""
                If IsArray($sDateMatch) Then $sCurrentDate = $sDateMatch[0]
                $sCurrentType = $sDefaultType
                If IsArray($sTypeMatch) Then $sCurrentType = $sTypeMatch[0]
                
                If IsArray($sFollowerMatch) Then
                    $sCurrentFollowers = $sFollowerMatch[0]
                Else
                    $sCurrentFollowers = ""
                EndIf

                $sCurrentLive = ""
                If $sLiveMatch Then $sCurrentLive = "True"
                ; Tự động nhận diện Playlist/Channel dựa trên ID nếu các cách trên thất bại
                If $sCurrentType <> "playlist" And $sCurrentType <> "channel" Then
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
         MsgBox(16, "Search", "No results found for: " & $sKeyword)
    ElseIf Not $bAppend Then
        DllCall("winmm.dll", "int", "PlaySoundW", "ptr", 0, "ptr", 0, "dword", 0)
        SoundPlay(@ScriptDir & "\sounds\result.wav")
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

    _GUICtrlMenu_AddMenuItem($hMenu, "Play...", 1001)
    _GUICtrlMenu_AddMenuItem($hMenu, "Play as &audio...", 1002)
    _GUICtrlMenu_AddMenuItem($hMenu, "Download...", 1003)
    _GUICtrlMenu_AddMenuItem($hMenu, "Go to channel...", 1004)
    _GUICtrlMenu_AddMenuItem($hMenu, "Open in Browser...", 1005)
    _GUICtrlMenu_AddMenuItem($hMenu, "Copy &Link...", 1006)

    Local $bIsInCollection = _IsVideoInAnyCollection($sID)
    _GUICtrlMenu_AddMenuItem($hMenu, _Ternary($bIsInCollection, "Remove from &Collection...", "Add to &Collection..."), 1008)

    Local $hSubMenu_Share = _GUICtrlMenu_CreatePopup()
    _GUICtrlMenu_AddMenuItem($hSubMenu_Share, "&Telegram", 1011)
    _GUICtrlMenu_AddMenuItem($hSubMenu_Share, "&Facebook", 1012)
    _GUICtrlMenu_AddMenuItem($hMenu, "&Share", -1, $hSubMenu_Share)

    Local $bIsAlreadyFav = _IsFavorite($sID)

    Local $sFavText
    If $bIsFavContext = 1 Then
        $sFavText = "&Remove from Favorite..."
    ElseIf $bIsFavContext = 2 Then
        $sFavText = "Delete from &History..."
    Else
        $sFavText = _Ternary($bIsAlreadyFav, "Remove from Favorite...", "Add to &Favorite...")
    EndIf
    _GUICtrlMenu_AddMenuItem($hMenu, $sFavText, 1007)

    Local $hActiveGui = WinGetHandle("[ACTIVE]")
    Local $iCmd = _GUICtrlMenu_TrackPopupMenu($hMenu, $hActiveGui, MouseGetPos(0), MouseGetPos(1), 1, 1, 2)

    _GUICtrlMenu_DestroyMenu($hMenu)

    Switch $iCmd
        Case 1007
            If $bIsFavContext = 1 Or ($bIsFavContext = 0 And $bIsAlreadyFav) Then
                If _RemoveFavorite($sID) Then
                    MsgBox(64, "Success", "Removed from favorites successfully!")
                    Return "REFRESH"
                EndIf
            ElseIf $bIsFavContext = 2 Then
                If _RemoveHistory($sID) Then
                    MsgBox(64, "Success", "Removed from history successfully!")
                    Return "REFRESH"
                EndIf
            Else
                _AddFavorite($sID, $sTitle)
            EndIf
        Case 1001
            _PlayLoop($iIndex, False) ; Video
        Case 1002
            _PlayLoop($iIndex, True) ; Audio
        Case 1003
            _ShowDownloadDialog($aSearchIds[$iIndex + 1], $sTitle)
        Case 1004
            _Action_GoChannel($iIndex)
        Case 1005
            _Action_OpenBrowser($iIndex)
        Case 1006
            _Action_CopyLink($iIndex)
        Case 1008
            If _IsVideoInAnyCollection($sID) Then
                _RemoveFromAllCollectionsDialog($sID)
            Else
                _AddtoCollection($sID, $sTitle)
            EndIf
        Case 1011 ; Telegram
            ShellExecute("https://t.me/share/url?url=" & _URLEncode("https://www.youtube.com/watch?v=" & $sID) & "&text=" & _URLEncode($sTitle))
        Case 1012 ; Facebook
            ShellExecute("https://www.facebook.com/sharer/sharer.php?u=" & _URLEncode("https://www.youtube.com/watch?v=" & $sID))
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

Func _Action_CopyLink($iIndex)
    If $iIndex < 0 Or $iIndex >= UBound($aSearchIds) - 1 Then Return
    Local $sUrl = "https://www.youtube.com/watch?v=" & $aSearchIds[$iIndex + 1]
    ClipPut($sUrl)
    MsgBox(64, "Info", "Link copied to clipboard!")
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
    ShellExecute("https://www.youtube.com/watch?v=" & $aSearchIds[$iIndex + 1])
EndFunc

Func _Action_ShowDescription($iIndex)
    If $iIndex < 0 Or $iIndex >= UBound($aSearchIds) - 1 Then Return
    Local $sID = $aSearchIds[$iIndex + 1]

    If Not FileExists($DESC_EXE_PATH) Then
        MsgBox(16, "Error", "description.exe not found in lib folder!")
        Return
    EndIf

    Local $hWait = GUICreate("Loading...", 250, 80, -1, -1, BitOR($WS_POPUP, $WS_BORDER), BitOR($WS_EX_TOPMOST, $WS_EX_TOOLWINDOW), $hResultsGui)
    GUICtrlCreateLabel("Fetching Description from YouTube...", 10, 25, 230, 20, $SS_CENTER)
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
        MsgBox(64, "Info", "No description available for this video.")
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
        MsgBox(16, "Error", "comments.exe not found in lib folder!")
        Return
    EndIf

    ; Directly run comments.exe with the YouTube URL.
    ; comments.exe already handles fetching comments internally.
    Local $sUrl = "https://www.youtube.com/watch?v=" & $sID
    Run('"' & $COMMENTS_EXE_PATH & '" "' & $sUrl & '"')
EndFunc

Func _Action_GoChannel($iIndex)
    If $iIndex < 0 Or $iIndex >= UBound($aSearchIds) - 1 Then Return
    Local $sID = $aSearchIds[$iIndex + 1]

    Local $hLoading = GUICreate("Working...", 250, 80, -1, -1, BitOR($WS_POPUP, $WS_BORDER), BitOR($WS_EX_TOPMOST, $WS_EX_TOOLWINDOW), $hResultsGui)
    GUICtrlCreateLabel("Fetching channel information...", 10, 25, 230, 20, $SS_CENTER)
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
        MsgBox(16, "Error", "Cannot get channel URL. The video might be from a deleted channel or restricted.")
    EndIf
EndFunc

Func _PlayLoop($iCurrentIndex, $bAudioOnly = False)
    While 1
        If $iCurrentIndex < 0 Or $iCurrentIndex >= ($iTotalLoaded) Then ExitLoop

        Local $sID = $aSearchIds[$iCurrentIndex + 1]
        Local $sTitle = $aSearchTitles[$iCurrentIndex + 1]

		Local $sType = "video"
		If UBound($aSearchTypes) > $iCurrentIndex + 1 Then
			If $aSearchTypes[$iCurrentIndex + 1] <> "" Then $sType = $aSearchTypes[$iCurrentIndex + 1]
		EndIf
        _AddHistory($sID, $sTitle, $sType) ; Save to history when playing

        Local $hLoading = 0
        If IsHWnd($hPlayGui) Then
            GUICtrlSetData($g_lblPlayerInfo, "Loading: " & $sTitle)
            GUICtrlSetData($g_hStatusLabel, "Fetching URL...")
        Else
            ; Show a small loading popup ONLY if player isn't open yet
            $hLoading = GUICreate("Playing", 250, 80, -1, -1, BitOR($WS_POPUP, $WS_BORDER), BitOR($WS_EX_TOPMOST, $WS_EX_TOOLWINDOW), $hResultsGui)
            GUICtrlCreateLabel("playing...", 10, 15, 230, 40, $SS_CENTER)
            GUISetBkColor(0xFFFFFF, $hLoading)
            GUISetState(@SW_SHOW, $hLoading)
            WinActivate($hLoading)
        Sleep(1)
        EndIf

        DllCall("winmm.dll", "int", "PlaySoundW", "wstr", @ScriptDir & "\sounds\loading.wav", "ptr", 0, "dword", 0x0009)
        Local $sFormat = _Ternary($bAudioOnly, "bestaudio/best", "best[ext=mp4]/best")

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

        $sUrl = StringStripWS($sUrl, 3)
        DllCall("winmm.dll", "int", "PlaySoundW", "ptr", 0, "ptr", 0, "dword", 0)

        If $bCancel = True Then
            If IsHWnd($hLoading) Then GUIDelete($hLoading)
            ExitLoop
        ElseIf $bCancel = "NEXT" Then
            If IsHWnd($hLoading) Then GUIDelete($hLoading)
            $iCurrentIndex += 1
            ContinueLoop
        ElseIf $bCancel = "BACK" Then
            If IsHWnd($hLoading) Then GUIDelete($hLoading)
            $iCurrentIndex -= 1
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
            Local $sErrMsg = "Error 153: YouTube blocked the link extraction request."
            If StringInStr($sErr, "sign in") Or StringInStr($sErr, "confirm you are not a bot") Then
                $sErrMsg &= " YouTube requires user verification."
            ElseIf StringInStr($sErr, "age restricted") Then
                $sErrMsg &= " Video is age-restricted."
            Else
                $sErrMsg &= " (Warning: YouTube is scanning for bots, please try again in a few minutes)."
            EndIf
            _NVDA_Speak($sErrMsg)
            MsgBox(16, "Error", $sErrMsg & @CRLF & @CRLF & "Tip: Try opening another video or restart your modem to change IP.")
            ExitLoop
        EndIf

        SoundPlay(@ScriptDir & "\sounds\ok.wav")
        Local $sAction = _PlayInternal($sUrl, $sTitle, $bAudioOnly, $hLoading, True, $sID) ; True = Allow AutoPlay toggle

        If $sAction = "NEXT" Or ($sAction = "FINISHED" And $g_bAutoPlay) Then
            $iCurrentIndex += 1
        ElseIf $sAction = "BACK" Then
            $iCurrentIndex -= 1
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

Func _ShowDownloadDialog($sID, $sTitle)
    Local $sUrl = "https://www.youtube.com/watch?v=" & $sID
    Local $hDLGui = GUICreate("Download Options", 400, 250, -1, -1, -1, -1)
    GUISetBkColor($COLOR_BLUE)

    GUICtrlCreateLabel("Select Format :", 10, 20, 180, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $cboFormat = GUICtrlCreateCombo("", 10, 45, 180, 20, $CBS_DROPDOWNLIST)
    GUICtrlSetTip(-1, "Chọn định dạng tải xuống, dùng phím mũi tên để duyệt danh sách theo thứ tự bảng chữ cái")
    GUICtrlSetData(-1, "M4A (Audio)|MP3 (Audio)|MP4 (Video, Best)|OGG (Audio)|WAV (Audio)|WebM (Video)", "MP4 (Video, Best)")

    GUICtrlCreateLabel("Select Bitrate:", 210, 20, 180, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $cbo_dl_bitrate_local = GUICtrlCreateCombo("", 210, 45, 180, 20, $CBS_DROPDOWNLIST)
    GUICtrlSetTip(-1, "Chọn tốc độ bit (kbps), dùng phím mũi tên để duyệt từ thấp đến cao")
    GUICtrlSetData(-1, "128 kbps|192 kbps|256 kbps|320 kbps", "320 kbps")

    Local $chk_custom_name = GUICtrlCreateCheckbox("Choose custom output filename composition", 10, 80, 380, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $cbo_name_type = GUICtrlCreateCombo("", 10, 105, 380, 20, $CBS_DROPDOWNLIST)
    GUICtrlSetTip(-1, "Chọn kiểu đặt tên tệp, dùng phím mũi tên để duyệt danh sách theo thứ tự bảng chữ cái")
    GUICtrlSetData(-1, "No numbering|No numbering and create subdirectory|Numbering|Numbering and create subdirectory", "No numbering")
    GUICtrlSetState(-1, $GUI_DISABLE)

    Local $btn_DownloadNow = GUICtrlCreateButton("Download (Alt+D)", 10, 140, 380, 40)

    Local $lbl_dlnow_status = GUICtrlCreateLabel("", 10, 190, 380, 16)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $prog_dlnow = GUICtrlCreateProgress(10, 210, 380, 20)

    Local $hDummyEscDLNow = GUICtrlCreateDummy()
    Local $aAccelDLNow[2][2] = [["!d", $btn_DownloadNow], ["{ESC}", $hDummyEscDLNow]]
    GUISetAccelerators($aAccelDLNow, $hDLGui)

    GUISetState(@SW_SHOW, $hDLGui)

    While 1
        Local $nMsg = _GuiMsg($hDLGui)
        If $nMsg = $GUI_EVENT_CLOSE Or $nMsg = $hDummyEscDLNow Then
            GUIDelete($hDLGui)
            ExitLoop
        ElseIf $nMsg = $chk_custom_name Then
            If GUICtrlRead($chk_custom_name) = $GUI_CHECKED Then
                GUICtrlSetState($cbo_name_type, $GUI_ENABLE)
            Else
                GUICtrlSetState($cbo_name_type, $GUI_DISABLE)
            EndIf
        ElseIf $nMsg = $btn_DownloadNow Then
            Local $sTxt = GUICtrlRead($cboFormat)
            Local $sBitrate = GUICtrlRead($cbo_dl_bitrate_local)
            
            Local $sOutTemplate = "%(title)s.%(ext)s"
            If GUICtrlRead($chk_custom_name) = $GUI_CHECKED Then
                Local $sNameSel = GUICtrlRead($cbo_name_type)
                If $sNameSel = "No numbering and create subdirectory" Then
                    $sOutTemplate = "%(title)s/%(title)s.%(ext)s"
                ElseIf $sNameSel = "Numbering" Then
                    $sOutTemplate = "%(playlist_index)s - %(title)s.%(ext)s"
                ElseIf $sNameSel = "Numbering and create subdirectory" Then
                    $sOutTemplate = "%(playlist_title)s/%(playlist_index)s - %(title)s.%(ext)s"
                EndIf
            EndIf

            GUICtrlSetState($btn_DownloadNow, $GUI_DISABLE)
            GUICtrlSetState($cboFormat, $GUI_DISABLE)
            GUICtrlSetState($cbo_dl_bitrate_local, $GUI_DISABLE)
            GUICtrlSetState($chk_custom_name, $GUI_DISABLE)
            GUICtrlSetState($cbo_name_type, $GUI_DISABLE)

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
            Local $sCmd = $YT_DLP_EXE & ' ' & $sFmt & ' -P "' & $sFinalDownloadPath & '" --ffmpeg-location "' & @ScriptDir & '\lib" -o "' & $sOutTemplate & '" -- "' & $sUrl & '"'
            Local $bDLNowDone = _RunDownloadWithProgress($sCmd, $prog_dlnow, $lbl_dlnow_status)
            GUIDelete($hDLGui)
            If Not $bDLNowDone Then Return
SoundPlay(@ScriptDir & "\sounds\download_finish.wav")
            MsgBox(64, "Info", "Download Complete!")
            ExitLoop
        EndIf
    WEnd
EndFunc

Func playmedia($url)
    ; Update existing player info or show status if GUI exists
    Local $hLoading = 0
    If IsHWnd($hPlayGui) Then
        GUICtrlSetData($g_lblPlayerInfo, "Loading video...")
        GUICtrlSetData($g_hStatusLabel, "Fetching stream URL...")
    Else
        $hLoading = GUICreate("Playing", 250, 80, -1, -1, BitOR($WS_POPUP, $WS_BORDER), BitOR($WS_EX_TOPMOST, $WS_EX_TOOLWINDOW))
        GUICtrlCreateLabel("Loading, please wait...", 10, 25, 230, 30, $SS_CENTER)
        GUISetBkColor(0xFFFFFF, $hLoading)
        GUISetState(@SW_SHOW, $hLoading)
        Sleep(1)
    EndIf

    DllCall("winmm.dll", "int", "PlaySoundW", "wstr", @ScriptDir & "\sounds\loading.wav", "ptr", 0, "dword", 0x0009)
    Local $sCmd = @ComSpec & ' /c "' & $YT_DLP_EXE & ' -g -f "best" --no-playlist --no-check-certificate --no-warnings --no-mtime --socket-timeout 5 --geo-bypass --encoding utf-8 -4 -- "' & $url & '""'
    Local $pid = Run($sCmd, @ScriptDir, @SW_HIDE, $STDOUT_CHILD + $STDERR_CHILD)
    Local $dlink = "", $sErr = ""
    Local $bCancel = False
    While ProcessExists($pid)
        $dlink &= StdoutRead($pid)
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
    $dlink &= StdoutRead($pid)
    $dlink = StringStripWS($dlink, 3)
    DllCall("winmm.dll", "int", "PlaySoundW", "ptr", 0, "ptr", 0, "dword", 0)

    If $bCancel Then
        If $hLoading <> 0 Then GUIDelete($hLoading)
        Return
    EndIf

    If $dlink <> "" Then
        SoundPlay(@ScriptDir & "\sounds\ok.wav")
        Local $id = _GetYoutubeID($url)
        Local $sTitle = _GetYoutubeTitle($url)
        If $sTitle = "" Then $sTitle = "YouTube Video"
        _AddHistory($id, $sTitle)
        _PlayInternal($dlink, $sTitle, False, $hLoading, False, $id)
    Else
        If $hLoading <> 0 Then GUIDelete($hLoading)
        Local $sErrMsg = "Cannot get video stream from this link."
        If $sErr <> "" Then $sErrMsg &= " Details: " & StringLeft(StringStripWS($sErr, 3), 100)
        MsgBox(16, "Error", $sErrMsg)
    EndIf
EndFunc

Func playaudio($url)
    ; Update existing player info or show status if GUI exists
    Local $hLoading = 0
    If IsHWnd($hPlayGui) Then
        GUICtrlSetData($g_lblPlayerInfo, "Loading audio...")
        GUICtrlSetData($g_hStatusLabel, "Fetching stream URL...")
    Else
        $hLoading = GUICreate("Playing", 250, 80, -1, -1, BitOR($WS_POPUP, $WS_BORDER), BitOR($WS_EX_TOPMOST, $WS_EX_TOOLWINDOW))
        GUICtrlCreateLabel("Loading, please wait...", 10, 25, 230, 30, $SS_CENTER)
        GUISetBkColor(0xFFFFFF, $hLoading)
        GUISetState(@SW_SHOW, $hLoading)
        Sleep(1)
    EndIf

    DllCall("winmm.dll", "int", "PlaySoundW", "wstr", @ScriptDir & "\sounds\loading.wav", "ptr", 0, "dword", 0x0009)
    Local $sCmd = @ComSpec & ' /c "' & $YT_DLP_EXE & ' -g -f "bestaudio" --no-playlist --no-check-certificate --no-warnings --no-mtime --socket-timeout 5 --geo-bypass --encoding utf-8 -4 -- "' & $url & '""'
    Local $pid = Run($sCmd, @ScriptDir, @SW_HIDE, $STDOUT_CHILD + $STDERR_CHILD)
    Local $dlink = "", $sErr = ""
    Local $bCancel = False
    While ProcessExists($pid)
        $dlink &= StdoutRead($pid)
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
    $dlink &= StdoutRead($pid)
    $dlink = StringStripWS($dlink, 3)
    DllCall("winmm.dll", "int", "PlaySoundW", "ptr", 0, "ptr", 0, "dword", 0)

    If $bCancel Then
        If $hLoading <> 0 Then GUIDelete($hLoading)
        Return
    EndIf

    If $dlink <> "" Then
        SoundPlay(@ScriptDir & "\sounds\ok.wav")
        Local $id = _GetYoutubeID($url)
        Local $sTitle = _GetYoutubeTitle($url)
        If $sTitle = "" Then $sTitle = "YouTube Audio"
        _AddHistory($id, $sTitle)
        _PlayInternal($dlink, "YouTube Audio Player", True, $hLoading, False, $id)
    Else
        If $hLoading <> 0 Then GUIDelete($hLoading)
        Local $sErrMsg = "Cannot get audio stream from this link."
        If $sErr <> "" Then $sErrMsg &= " Details: " & StringLeft(StringStripWS($sErr, 3), 100)
        MsgBox(16, "Error", $sErrMsg)
    EndIf
EndFunc

Func _ListenToAudioFile()
    Local $hChooseGui = GUICreate("Listen to Audio", 380, 210, -1, -1, BitOR($WS_CAPTION, $WS_SYSMENU))
    GUISetBkColor($COLOR_BLUE)

    GUICtrlCreateLabel("Choose how you want to load audio:", 10, 15, 360, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)

    Local $btn_AddFile = GUICtrlCreateButton("Add File... (Alt+F)", 40, 50, 300, 40)
    Local $btn_AddFolder = GUICtrlCreateButton("Add Folder... (Alt+D)", 40, 100, 300, 40)
    Local $btn_CloseChoose = GUICtrlCreateButton("Close", 40, 155, 300, 35)

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
    Local $sFile = FileOpenDialog("Select an audio file to listen to", @MyDocumentsDir, $sFilter, 1)
    If @error Then Return ; user cancelled the dialog

    ; Defensive validation, in case the user typed a filename with an unsupported extension
    Local $aExtMatch = StringRegExp($sFile, "\.([A-Za-z0-9]+)$", 3)
    Local $sExt = (UBound($aExtMatch) > 0) ? StringLower($aExtMatch[0]) : ""
    If Not StringInStr($g_sSupportedAudioExts, "." & $sExt & ";") Then
        MsgBox(16, "Unsupported Format", "This audio format is not supported." & @CRLF & "Supported formats: MP3, M4A, WAV, OGG, FLAC, AAC, WMA, OPUS, MP4.")
        Return
    EndIf

    ; Get file name (without path/extension) to use as the track title
    Local $aNameMatch = StringRegExp($sFile, "([^\\\/]+)$", 3)
    Local $sTitle = (UBound($aNameMatch) > 0) ? $aNameMatch[0] : $sFile
    $sTitle = StringRegExpReplace($sTitle, "\.[A-Za-z0-9]+$", "")

    _AddHistory($sFile, $sTitle, "local_audio")

    ; Single file loaded directly - n/b navigation must stay OFF
    $g_bLocalPlaylistMode = False

    Local $hLoading = 0
    If Not IsHWnd($hPlayGui) Then
        $hLoading = GUICreate("Playing", 250, 80, -1, -1, BitOR($WS_POPUP, $WS_BORDER), BitOR($WS_EX_TOPMOST, $WS_EX_TOOLWINDOW))
        GUICtrlCreateLabel("Loading audio file, please wait...", 10, 25, 230, 30, $SS_CENTER)
        GUISetBkColor(0xFFFFFF, $hLoading)
        GUISetState(@SW_SHOW, $hLoading)
        DllCall("winmm.dll", "int", "PlaySoundW", "wstr", @ScriptDir & "\sounds\loading.wav", "ptr", 0, "dword", 0x0009)
        Sleep(200)
    Else
        GUICtrlSetData($g_lblPlayerInfo, "Loading audio file...")
        GUICtrlSetData($g_hStatusLabel, "Loading " & $sTitle & "...")
    EndIf

    _PlayInternal($sFile, $sTitle, True, $hLoading, False, $sFile, True)
EndFunc

; "Add Folder": scan a folder for supported audio files and start a playlist.
; While this playlist is playing, "n" = next file, "b" = previous file.
Func _AddAudioFolder()
    Local $sFolder = FileSelectFolder("Select a folder containing audio files", @MyDocumentsDir)
    If @error Then Return ; user cancelled the dialog

    ReDim $g_aLocalPlaylist[1]
    $g_iLocalPlaylistCount = 0

    Local $sSearch = FileFindFirstFile($sFolder & "\*.*")
    If $sSearch = -1 Then
        MsgBox(48, "Empty Folder", "No files were found in the selected folder.")
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
        MsgBox(48, "No Audio Files", "No supported audio files were found in this folder." & @CRLF & "Supported formats: MP3, M4A, WAV, OGG, FLAC, AAC, WMA, OPUS, MP4.")
        Return
    EndIf

    _ArraySort($g_aLocalPlaylist)

    $g_bLocalPlaylistMode = True
    _PlayLocalFolder(0)
EndFunc

; Drives playback through a folder-loaded playlist. Pressing "n" inside the
; player moves to the next file, "b" moves to the previous one; the track
; also auto-advances to the next file when one finishes (unless Repeat is on).
Func _PlayLocalFolder($iIndex)
    While 1
        If $iIndex < 0 Then
            ; Before the first track (pressed 'b' at the first track) - wrap around to the last track
            _ReportStatus("Back to the last track")
            $iIndex = $g_iLocalPlaylistCount - 1
        ElseIf $iIndex >= $g_iLocalPlaylistCount Then
            ; Past the last track - wrap around and play the first track again
            _ReportStatus("Back to the first track")
            $iIndex = 0
        EndIf

        Local $sFile = $g_aLocalPlaylist[$iIndex]
        Local $aNameMatch = StringRegExp($sFile, "([^\\\/]+)$", 3)
        Local $sTitle = (UBound($aNameMatch) > 0) ? $aNameMatch[0] : $sFile
        $sTitle = StringRegExpReplace($sTitle, "\.[A-Za-z0-9]+$", "")

        _AddHistory($sFile, $sTitle, "local_audio")

        Local $hLoading = 0
        If Not IsHWnd($hPlayGui) Then
            $hLoading = GUICreate("Playing", 250, 80, -1, -1, BitOR($WS_POPUP, $WS_BORDER), BitOR($WS_EX_TOPMOST, $WS_EX_TOOLWINDOW))
            GUICtrlCreateLabel("Loading audio file, please wait...", 10, 25, 230, 30, $SS_CENTER)
            GUISetBkColor(0xFFFFFF, $hLoading)
            GUISetState(@SW_SHOW, $hLoading)
            DllCall("winmm.dll", "int", "PlaySoundW", "wstr", @ScriptDir & "\sounds\loading.wav", "ptr", 0, "dword", 0x0009)
            Sleep(200)
        Else
            GUICtrlSetData($g_lblPlayerInfo, "Loading audio file...")
            GUICtrlSetData($g_hStatusLabel, "Loading " & $sTitle & "...")
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

Func _PlayInternal($sUrl, $sTitle, $bAudioOnly = False, $hLoading = 0, $allowAutoPlayToggle = False, $sID = "", $bLocalFile = False)
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
            $hLoading = GUICreate("Playing", 250, 80, -1, -1, BitOR($WS_POPUP, $WS_BORDER), BitOR($WS_EX_TOPMOST, $WS_EX_TOOLWINDOW), $hPlayGui)
            GUICtrlCreateLabel("Loading stream, please wait...", 10, 25, 230, 30, $SS_CENTER)
            GUISetBkColor(0xFFFFFF, $hLoading)
            GUISetState(@SW_SHOW, $hLoading)
            
            ; Phát âm thanh loading
            DllCall("winmm.dll", "int", "PlaySoundW", "wstr", @ScriptDir & "\sounds\loading.wav", "ptr", 0, "dword", 0x0009)
        EndIf

        GUISetBkColor(0x000000, $hPlayGui)
        GUISwitch($hPlayGui)

        ; Tạo Menu Bar - Không dùng biến Local để tránh nhầm lẫn, dùng biến Global đã khai báo
        ; (Local audio files: no Options menu bar for this feature)
        If Not $bLocalFile Then
            Local $hMenu_Options = GUICtrlCreateMenu("&Options")
            $menu_item_download = GUICtrlCreateMenuItem("&Download...", $hMenu_Options)
            $menu_item_channel = GUICtrlCreateMenuItem("Go to &Channel...", $hMenu_Options)
            $menu_item_browser = GUICtrlCreateMenuItem("Open in &Browser...", $hMenu_Options)
            $menu_item_copy = GUICtrlCreateMenuItem("Copy &Link...", $hMenu_Options)

            Local $hMenu_Share = GUICtrlCreateMenu("&Share", $hMenu_Options)
            $menu_share_telegram = GUICtrlCreateMenuItem("&Telegram", $hMenu_Share)
            $menu_share_facebook = GUICtrlCreateMenuItem("&Facebook", $hMenu_Share)

            $menu_item_desc = GUICtrlCreateMenuItem("&Video Description...", $hMenu_Options)
            $menu_item_comments = GUICtrlCreateMenuItem("Video Com&ments...", $hMenu_Options)

            Local $sFavText = _Ternary(_IsFavorite($sID), "&Remove from Favorite...", "Add to &Favorite...")
            $menu_item_fav = GUICtrlCreateMenuItem($sFavText, $hMenu_Options)

            If _IsVideoInAnyCollection($sID) Then
                $menu_item_remove_col = GUICtrlCreateMenuItem("&Remove from Collection", $hMenu_Options)
                $menu_item_add_col = -1
            Else
                $menu_item_add_col = GUICtrlCreateMenuItem("&Add to Collection...", $hMenu_Options)
                $menu_item_remove_col = -1
            EndIf

            $menu_item_goto = GUICtrlCreateMenuItem("Go to &Time... (Ctrl+G)", $hMenu_Options)
            $menu_item_fileinfo = -1 ; File Information removed from the online listening interface

            ; NEW FEATURE Tính năng Sleep Timer vào Menu
            GUICtrlCreateMenuItem("", $hMenu_Options) ; Separator
            $menu_item_sleeptimer = GUICtrlCreateMenuItem("S&leep Timer...", $hMenu_Options)

            ; Vẽ lại thanh menu để đảm bảo hiển thị
            _GUICtrlMenu_DrawMenuBar($hPlayGui)
        Else
            $menu_item_download = -1
            $menu_item_channel = -1
            $menu_item_browser = -1
            $menu_item_copy = -1
            $menu_share_telegram = -1
            $menu_share_facebook = -1
            $menu_item_desc = -1
            $menu_item_comments = -1
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
            MsgBox(16, "Error", "Could not initialize libvlc.dll. Please ensure VLC DLLs are present in the lib folder.")
            GUIDelete($hPlayGui)
            $hPlayGui = 0
            Return ""
        EndIf

        ; Tạo một cửa sổ con giả để VLC có thể render nếu cần (nhưng không dùng ActiveX)
        $oVLCCtrl = GUICtrlCreateLabel("", 0, 0, $iWidth, $iHeight) 
        Local $hVlcContainer = GUICtrlGetHandle($oVLCCtrl)
        DllCall($hVLC_Dll, "none:cdecl", "libvlc_media_player_set_hwnd", "ptr", $oVLC_Player, "hwnd", $hVlcContainer)

        ; Text strip under the video area: title, state/position, last action, repeat/auto
        $g_lblPlayerInfo = GUICtrlCreateLabel("Playing: " & $sTitle, 10, $iHeight + 4, $iWidth - 20, 40, $SS_NOPREFIX)
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

        $g_lblRepeat = GUICtrlCreateLabel("Repeat: OFF", $iWidth - 170, $iHeight + 70, 80, 18)
        GUICtrlSetColor(-1, 0xFFFF00)
        GUICtrlSetState(-1, $GUI_HIDE) ; Ẩn dòng "Repeat: OFF/ON" theo yêu cầu

        $g_lblAuto = GUICtrlCreateLabel("Auto: ON", $iWidth - 80, $iHeight + 70, 70, 18)
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

        ; Ctrl+Home / Ctrl+End: jump to first/last track (folder playlist only)
        $hDummyCtrlHome = GUICtrlCreateDummy()
        $hDummyCtrlEnd = GUICtrlCreateDummy()

        Local $aAccelPlay[51][2] = [ _
            ["{SPACE}", $hDummySpace], _
            ["n", $hDummyN], _ ; Next
            ["b", $hDummyB], _ ; Previous (folder playlist only)
            ["r", $hDummyR], _ ; Repeat
            ["^r", $hDummyRemaining], _ ; Remaining time
            ["+n", $hDummyShiftN], _ ; Force Next
            ["+b", $hDummyShiftB], _ ; Force Back
            ["{UP}", $hDummyUp], _
            ["{DOWN}", $hDummyDown], _
            ["{LEFT}", $hDummyLeft], _
            ["{RIGHT}", $hDummyRight], _
            ["^{LEFT}", $hDummyCtrlLeft], _
            ["^{RIGHT}", $hDummyCtrlRight], _
            ["^t", $hDummyCtrlT], _
            ["^+t", $hDummyCtrlShiftT], _
            ["{HOME}", $hDummyHome], _
            ["{END}", $hDummyEnd], _
            ["1", $hDummy1], _
            ["2", $hDummy2], _
            ["3", $hDummy3], _
            ["4", $hDummy4], _
            ["5", $hDummy5], _
            ["6", $hDummy6], _
            ["7", $hDummy7], _
            ["8", $hDummy8], _
            ["9", $hDummy9], _
            ["p", $hDummyP], _
            ["^w", $hDummyCtrlW], _
            ["-", $hDummyMinus], _
            ["=", $hDummyEqual], _
            ["s", $hDummyS], _
            ["d", $hDummyD], _
            ["f", $hDummyF], _
            ["^+e", $hDummyCtrlShiftE], _
            ["{ESC}", $hDummyEsc], _
            ["^g", $hDummyG], _
            ["!b", $hDummyAltB], _
            ["!g", $hDummyAltG], _
            ["!o", $hDummyAltO], _ ; Alt+O được kích hoạt
            ["{[}", $hDummyBracketLeft], _
            ["{]}", $hDummyBracketRight], _
            ["^s", $hDummyCtrlS], _
            ["^k", $hDummyCtrlK], _
            ["^c", $hDummyCtrlC], _
            ["^+c", $hDummyCtrlShiftC], _
            ["^+d", $hDummyCtrlShiftD], _
            ["{APPSKEY}", $hDummyApps], _  ; Bắt phím Menu chuột phải và ném vào hư không
            ["+{F10}", $hDummyApps], _     ; Bắt phím Shift+F10 và ném vào hư không
            ["i", $hDummyI], _             ; Show file information
            ["^{HOME}", $hDummyCtrlHome], _ ; First File (folder playlist only)
            ["^{END}", $hDummyCtrlEnd] _    ; Last File (folder playlist only)
        ]
        GUISetAccelerators($aAccelPlay, $hPlayGui)
    Else
        $g_sCurrentVideoTitle = $sTitle
        WinSetTitle($hPlayGui, "", $sTitle)
        GUICtrlSetData($g_lblPlayerInfo, "Playing: " & $sTitle)
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
    If $bLocalFile Then
        _VLC_Direct_Play(_PathToFileURI($sUrl))
    Else
        _VLC_Direct_Play($sUrl)
    EndIf
    If $hLoading = 0 Then
        GUICtrlSetData($g_hStatusLabel, "Loading stream...")
        DllCall("winmm.dll", "int", "PlaySoundW", "wstr", @ScriptDir & "\sounds\loading.wav", "ptr", 0, "dword", 0x0009) ; SND_FILENAME | SND_ASYNC
    EndIf

    ; Give some time for stream to initialize to prevent early interruption
    Sleep(200)    
    _VLC_Direct_SetVolume($g_iAppVolume)
    _VLC_Direct_SetRate($g_fPitch)

    ; --- Logic Tiếp tục xem (Continue Watching) ---
    If $g_bContinueWatching Then
        Local $iSavedTime = _GetPlaybackPosition($sID)
        If $iSavedTime > 0 Then
            Local $iWaitCount = 0
            While $iWaitCount < 50
                If _VLC_Direct_GetState() >= 3 Then ExitLoop ; 3=Playing, 4=Paused
                Sleep(100)
                $iWaitCount += 1
            WEnd
            _VLC_Direct_SetTime($iSavedTime)
            _ReportStatus("Continuing from " & _FormatTime($iSavedTime / 1000))
        EndIf
    EndIf
    ; -------------------------------------------

    If (Not $allowAutoPlayToggle) Or (Not $g_bAutoPlay) Then GUICtrlSetState($g_lblAuto, $GUI_HIDE)
    If $allowAutoPlayToggle And $g_bAutoPlay Then
        GUICtrlSetState($g_lblAuto, $GUI_SHOW)
        GUICtrlSetData($g_lblAuto, "Auto: ON")
    EndIf
    If $allowAutoPlayToggle And Not $g_bAutoPlay Then
        GUICtrlSetState($g_lblAuto, $GUI_SHOW)
        GUICtrlSetData($g_lblAuto, "Auto: OFF")
    EndIf

    If Not $g_bRepeat Then GUICtrlSetData($g_lblRepeat, "Repeat: OFF")
    If $g_bRepeat Then GUICtrlSetData($g_lblRepeat, "Repeat: ON")

    Local $sAction = ""
    Local $bLoaded = False
    Local $iLoadStartTime = TimerInit()
    Local $hInfoTimer = 0 ; drives the on-screen state/position line

    While 1
        Local $nMsg = GUIGetMsg()

        ; NEW FEATURE Logic kiểm tra hẹn giờ tắt nhạc (Sleep Timer) tắt và thoát toàn phần mềm
        If $g_iSleepTimerDuration > 0 And TimerDiff($g_hSleepTimerInit) >= $g_iSleepTimerDuration Then
            _ReportStatus("Sleep timer reached. Exiting application.")
            Sleep(1500) ; Đợi một chút để NVDA đọc thông báo
            SoundPlay(@ScriptDir & "\sounds\exit.wav", 1)
            ProcessClose("comments.exe")
            ProcessClose("description.exe")
            Exit
        EndIf

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
                    _ReportStatus("This file is already on your device.")
                Else
                    _ShowDownloadDialog($sID, $sTitle)
                EndIf
            Case $menu_item_channel, $hDummyAltG
                ; Removed for local audio files (Listen to Audio File interface)
                If Not $bLocalFile Then
                Local $hLoadingTmp = GUICreate("Working...", 250, 80, -1, -1, BitOR($WS_POPUP, $WS_BORDER), BitOR($WS_EX_TOPMOST, $WS_EX_TOOLWINDOW), $hPlayGui)
                GUICtrlCreateLabel("Fetching channel information...", 10, 25, 230, 20, $SS_CENTER)
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
                    MsgBox(16, "Error", "Cannot get channel URL.")
                EndIf
                EndIf
            Case $menu_item_browser, $hDummyAltB
                ; Removed for local audio files (Listen to Audio File interface)
                If Not $bLocalFile Then
                    ShellExecute("https://www.youtube.com/watch?v=" & $sID)
                EndIf
            Case $menu_item_copy
                If $bLocalFile Then
                    ClipPut($sUrl)
                    MsgBox(64, "Info", "File path copied to clipboard!")
                Else
                    ClipPut("https://www.youtube.com/watch?v=" & $sID)
                    MsgBox(64, "Info", "Link copied to clipboard!")
                EndIf
            Case $menu_share_telegram
                If $bLocalFile Then
                    _ReportStatus("Not available for local audio files.")
                Else
                    ShellExecute("https://t.me/share/url?url=" & _URLEncode("https://www.youtube.com/watch?v=" & $sID) & "&text=" & _URLEncode($sTitle))
                EndIf
            Case $menu_share_facebook
                If $bLocalFile Then
                    _ReportStatus("Not available for local audio files.")
                Else
                    ShellExecute("https://www.facebook.com/sharer/sharer.php?u=" & _URLEncode("https://www.youtube.com/watch?v=" & $sID))
                EndIf
            Case $menu_item_desc, $hDummyCtrlShiftD
                ; Removed for local audio files (Listen to Audio File interface)
                If Not $bLocalFile Then
                Local $hWaitDesc = GUICreate("Loading...", 250, 80, -1, -1, BitOR($WS_POPUP, $WS_BORDER), BitOR($WS_EX_TOPMOST, $WS_EX_TOOLWINDOW), $hPlayGui)
                GUICtrlCreateLabel("Fetching Description...", 10, 25, 230, 20, $SS_CENTER)
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
                    MsgBox(64, "Info", "No description available.")
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
                    _ReportStatus("Not available for local audio files.")
                Else
                    Run('"' & $COMMENTS_EXE_PATH & '" "https://www.youtube.com/watch?v=' & $sID & '"')
                EndIf
            Case $menu_item_fav
                If _IsFavorite($sID) Then
                    If _RemoveFavorite($sID) Then
                        GUICtrlSetData($menu_item_fav, "Add to &Favorite...")
                        _ReportStatus("Removed from favorites")
                    EndIf
                Else
                    _AddFavorite($sID, $sTitle)
                    GUICtrlSetData($menu_item_fav, "Remove from &Favorite...")
                    _ReportStatus("Added to favorites")
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
                    Local $sFileNameI = (UBound($aNameI) > 0) ? $aNameI[0] : $sTitle
                    Local $iStateI = _VLC_Direct_GetState()
                    Local $sPlayStateI = ($iStateI = 3) ? "playing" : "paused"
                    Local $sInfoMsg = $sFileNameI & " ;  " & _FormatTimeSpoken($fCurI) & " of " & _FormatTimeSpoken($fLenI) & ";  " & $sPlayStateI & ";"
                    _ReportStatus($sInfoMsg)
                EndIf

            Case $hDummyAltO
                ; Gửi lệnh WM_SYSCOMMAND (0x0112) và SC_KEYMENU (0xF100) trực tiếp tới Windows 
                ; để mở Menu một cách chuẩn xác 100% không bị dội phím gây văng phần mềm.
                DllCall("user32.dll", "lresult", "PostMessage", "hwnd", $hPlayGui, "uint", 0x0112, "wparam", 0xF100, "lparam", 79)

            Case $hDummyCtrlK
                ; Removed for local audio files (Listen to Audio File interface)
                If Not $bLocalFile Then
                    ClipPut("https://www.youtube.com/watch?v=" & $sID)
                    _ReportStatus("Link copied to clipboard")
                EndIf

            Case $hDummyCtrlC
                If $bLocalFile Then
                    _ReportStatus("Not available for local audio files.")
                    ContinueLoop
                EndIf
                Local $sCleanID = StringStripWS($sID, 3)
                Local $sFinalLink = ""
                Local $fPos = (_VLC_Direct_GetTime() / 1000)

                ; Nếu chưa đặt điểm [ thì tự động lấy thời gian hiện tại
                Local $iStart = _Ternary(($g_fSelectionStart <> -1), Int($g_fSelectionStart), Int($fPos))

                If $g_fSelectionEnd <> -1 Then
                    Local $iEnd = Int($g_fSelectionEnd)
                    ; Đảo ngược nếu điểm kết thúc nhỏ hơn điểm bắt đầu
                    If $iEnd < $iStart Then
                        Local $tmp = $iStart
                        $iStart = $iEnd
                        $iEnd = $tmp
                    EndIf
                    ; Tạo link đoạn (Range). Sử dụng link embed để trình duyệt tự động dừng ở điểm kết thúc.
                    $sFinalLink = "https://www.youtube.com/embed/" & $sCleanID & "?start=" & $iStart & "&end=" & $iEnd & "&autoplay=1"
                    _ReportStatus("Range link (Embed) copied: " & _FormatTime($iStart) & " to " & _FormatTime($iEnd))
                Else
                    ; Nếu không có điểm kết thúc, tạo link tại mốc thời gian bắt đầu
                    $sFinalLink = "https://www.youtube.com/watch?v=" & $sCleanID & "&t=" & $iStart & "s"
                    If $g_fSelectionStart <> -1 Then
                        _ReportStatus("Link from start point copied: " & _FormatTime($iStart))
                    Else
                        _ReportStatus("Current time link copied: " & _FormatTime($iStart))
                    EndIf
                EndIf

                ClipPut($sFinalLink)

            Case $hDummyCtrlShiftC
                If Not $bLocalFile Then
                    Run('"' & $COMMENTS_EXE_PATH & '" "https://www.youtube.com/watch?v=' & $sID & '"')
                EndIf

            Case $hDummyBracketLeft
                ; Removed for local audio files (Listen to Audio File interface)
                If Not $bLocalFile Then
                    ; Lấy vị trí hiện tại
                    Local $fPos = (_VLC_Direct_GetTime() / 1000)
                    $g_fSelectionStart = $fPos
                    _ReportStatus("Start selection: " & _FormatTime($g_fSelectionStart))
                EndIf

            Case $hDummyBracketRight
                ; Removed for local audio files (Listen to Audio File interface)
                If Not $bLocalFile Then
                    Local $fPos = (_VLC_Direct_GetTime() / 1000)
                    $g_fSelectionEnd = $fPos
                    _ReportStatus("End selection: " & _FormatTime($g_fSelectionEnd))
                EndIf

            Case $hDummyCtrlS
                ; Removed for local audio files (Listen to Audio File interface)
                If Not $bLocalFile Then
                    If $g_fSelectionStart = -1 Or $g_fSelectionEnd = -1 Then
                        _ReportStatus("Please set both start and end selection points.")
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
                    _ReportStatus("play")
                ElseIf $ps = 3 Then
                    _VLC_Direct_Pause()
                    _ReportStatus("pause")
                Else
                    _VLC_Direct_Pause()
                    _ReportStatus("play")
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
                        _ReportStatus("Cinema Mode Enabled")
                    Else
                        GUISetStyle(BitOR($WS_CAPTION, $WS_SYSMENU, $WS_POPUP, $WS_SIZEBOX, $WS_VISIBLE), -1, $hPlayGui)
                        WinMove($hPlayGui, "", $g_iOriginalX, $g_iOriginalY, $g_iOriginalW, $g_iOriginalH)
                        GUICtrlSetPos($oVLCCtrl, 0, 0, $iWidth, $iHeight)
                        GUICtrlSetState($g_lblPlayerInfo, $GUI_SHOW)
                        GUICtrlSetState($g_lblTimeInfo, $GUI_SHOW)
                        If $g_lblHint <> 0 Then GUICtrlSetState($g_lblHint, $GUI_SHOW)
                        _ReportStatus("Cinema Mode Disabled")
                    EndIf
                EndIf

            Case $hDummyN
                If $g_bLocalPlaylistMode Then
                    $sAction = "NEXT"
                    ExitLoop
                ElseIf $allowAutoPlayToggle Then
                    $g_bAutoPlay = Not $g_bAutoPlay
                    GUICtrlSetData($g_lblAuto, _Ternary($g_bAutoPlay, "Auto: ON", "Auto: OFF"))
                    _ReportStatus(_Ternary($g_bAutoPlay, "Auto Play Next Track ON", "Auto Play Next Track OFF"))
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
                    GUICtrlSetData($g_lblRepeat, _Ternary($g_bRepeat, "Repeat: ON", "Repeat: OFF"))
                    _ReportStatus(_Ternary($g_bRepeat, "Repeat ON", "Repeat OFF"))
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
                        _ReportStatus("Remaining time: " & _FormatTime($iRemaining))
                    EndIf
                EndIf

            Case $hDummyShiftN
                ; Disabled for local audio files (Listen to Audio File interface).
                ; Previously this fired even when $bLocalFile = True, and since
                ; _AddSingleAudioFile() ignores the "NEXT" return value, pressing
                ; Shift+N while listening to a single local file silently closed
                ; the player instead of doing nothing.
                If Not $bLocalFile Then
                    $sAction = "NEXT"
                    ExitLoop
                EndIf

            Case $hDummyShiftB
                ; Disabled for local audio files (Listen to Audio File interface).
                ; Same issue as Shift+N above - closed the player unexpectedly.
                If Not $bLocalFile Then
                    $sAction = "BACK"
                    ExitLoop
                EndIf

            Case $hDummyHome
                _VLC_Direct_SetTime(0)
                _ReportStatus("Restart from beginning")

            Case $hDummyEnd
                Local $fDuration = (_VLC_Direct_GetLength() / 1000)
                If $fDuration > 0 Then
                    _VLC_Direct_SetTime(($fDuration - 20) * 1000)
                    _ReportStatus("Near end")
                Else
                    $sAction = "STOP"
                    ExitLoop
                EndIf

            Case $hDummyCtrlW
                SoundPlay(@ScriptDir & "\sounds\exit.wav", 1)
                ProcessClose("comments.exe")
                ProcessClose("description.exe")
                Exit

            Case $hDummyMinus
                If $g_iFFStep > 1 Then $g_iFFStep -= 1
                If $g_iRWStep > 1 Then $g_iRWStep -= 1
                $g_iSeekStep = $g_iFFStep
                IniWrite($CONFIG_FILE, "Settings", "FFStep", $g_iFFStep)
                IniWrite($CONFIG_FILE, "Settings", "RWStep", $g_iRWStep)
                _ReportStatus("Seek Step: Forward " & $g_iFFStep & "s, Backward " & $g_iRWStep & "s")

            Case $hDummyEqual
                $g_iFFStep += 1
                $g_iRWStep += 1
                $g_iSeekStep = $g_iFFStep
                IniWrite($CONFIG_FILE, "Settings", "FFStep", $g_iFFStep)
                IniWrite($CONFIG_FILE, "Settings", "RWStep", $g_iRWStep)
                _ReportStatus("Seek Step: Forward " & $g_iFFStep & "s, Backward " & $g_iRWStep & "s")

            Case $hDummyUp
                _StepAppVolume(1)

            Case $hDummyDown
                _StepAppVolume(-1)

            Case $hDummyS
                $g_fPitch = Round($g_fPitch - 0.1, 1)
                If $g_fPitch < 0.1 Then $g_fPitch = 0.1
                _VLC_Direct_SetRate($g_fPitch)
                _ReportStatus("Speed: " & $g_fPitch & "x")

            Case $hDummyD
                $g_fPitch = 1.0
                _VLC_Direct_SetRate($g_fPitch)
                _ReportStatus("Speed: 1.0x (Normal)")

            Case $hDummyF
                $g_fPitch = Round($g_fPitch + 0.1, 1)
                If $g_fPitch > 5.0 Then $g_fPitch = 5.0
                _VLC_Direct_SetRate($g_fPitch)
                _ReportStatus("Speed: " & $g_fPitch & "x")

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

            Case $hDummyEsc
                $sAction = "CLOSE"
                ExitLoop

            Case $hDummyG
                _ShowGoToTime()

            Case $hDummyCtrlT
                ; Removed for local audio files (Listen to Audio File interface)
                If Not $bLocalFile Then
                    Local $sElapsed = _FormatTime(_VLC_Direct_GetTime() / 1000)
                    _ReportStatus("Elapsed Time: " & $sElapsed)
                EndIf

            Case $hDummyCtrlShiftT
                ; Removed for local audio files (Listen to Audio File interface)
                If Not $bLocalFile Then
                    Local $sTotal = _FormatTime(_VLC_Direct_GetLength() / 1000)
                    _ReportStatus("Total Duration: " & $sTotal)
                EndIf
        EndSwitch
        EndIf

        ; --- Playback state checks: run on EVERY loop tick (even when idle,
        ; i.e. $nMsg = 0), so the loading dialog closes and end-of-track is
        ; detected promptly without needing a keypress first ---
        ; Refresh the on-screen state / position line (twice a second, redraws only when the text changed)
        If TimerDiff($hInfoTimer) >= 500 Then
            $hInfoTimer = TimerInit()
            _UpdatePlayerTimeLabel()
        EndIf

        Local $iCurState = _VLC_Direct_GetState()
        If $iCurState = 2 Then ; Buffering
            If GUICtrlRead($g_hStatusLabel) <> "Buffering..." Then GUICtrlSetData($g_hStatusLabel, "Buffering...")
        ElseIf $iCurState = 3 And GUICtrlRead($g_hStatusLabel) = "Buffering..." Then
            GUICtrlSetData($g_hStatusLabel, "Playing")
        EndIf

        If Not $bLoaded And ($iCurState = 3 Or $iCurState = 5 Or $iCurState = 6 Or $iCurState = 7 Or TimerDiff($iLoadStartTime) > 30000) Then
            If $hLoading <> 0 Then GUIDelete($hLoading)
            $hLoading = 0
            $bLoaded = True
            DllCall("winmm.dll", "int", "PlaySoundW", "ptr", 0, "ptr", 0, "dword", 0) ; Stop loading sound
            If $iCurState = 3 Then GUICtrlSetData($g_hStatusLabel, "Playing")
        EndIf

        Local $iState = $iCurState
        If ($iState = 6 Or $iState = 5 Or $iState = 7) And $bLoaded Then
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
    If $g_bContinueWatching Then
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
            $sState = "Loading"
        Case 3
            $sState = "Playing"
        Case 4
            $sState = "Paused"
        Case 5
            $sState = "Stopped"
        Case 6
            $sState = "Ended"
        Case 7
            $sState = "Error"
        Case Else
            $sState = "Ready"
    EndSwitch
    Local $fCurT = _VLC_Direct_GetTime() / 1000
    Local $fLenT = _VLC_Direct_GetLength() / 1000
    If $fCurT < 0 Then $fCurT = 0
    Local $sTimeTxt = _FormatTime($fCurT)
    If $fLenT > 0 Then $sTimeTxt &= " / " & _FormatTime($fLenT)
    Local $sInfoTxt = $sState & "     " & $sTimeTxt & "     Volume: " & $g_iAppVolume & "%     Speed: " & StringFormat("%.1f", $g_fPitch) & "x"
    If $sInfoTxt = $g_sLastTimeInfo Then Return
    $g_sLastTimeInfo = $sInfoTxt
    GUICtrlSetData($g_lblTimeInfo, $sInfoTxt)
EndFunc

; Lines of the on-screen keyboard guide shown in the audio player window
Func _GetPlayerHelpLines($bLocalFile, $bAllowAutoPlayToggle)
    Local $sHelp = "Space: Play / Pause" & @LF & _
        "Left / Right: Rewind / Forward" & @LF & _
        "Up / Down: Volume up / down" & @LF & _
        "Home / End: Restart / Jump near the end" & @LF & _
        "1 - 9: Jump to 10% - 90% of the track" & @LF & _
        "S / D / F: Slower / Normal / Faster" & @LF & _
        "- / =: Shorter / Longer seek step" & @LF & _
        "P: Show percentage played" & @LF & _
        "Ctrl+G: Go to a specific time" & @LF
    If $bLocalFile Then
        $sHelp &= "I: Show file information" & @LF
        If $g_bLocalPlaylistMode Then
            $sHelp &= "N / B: Next / Previous file" & @LF & _
                "Ctrl+Home / Ctrl+End: First / Last file" & @LF
        EndIf
    Else
        $sHelp &= "Ctrl+T: Elapsed time" & @LF & _
            "Ctrl+Shift+T: Total duration" & @LF & _
            "Ctrl+R: Remaining time" & @LF & _
            "R: Turn repeat on / off" & @LF & _
            "Ctrl+K: Copy video link" & @LF & _
            "Ctrl+C: Copy link at the current time" & @LF & _
            "[ and ]: Set selection start / end" & @LF & _
            "Ctrl+S: Save the selection" & @LF & _
            "Alt+B: Open in browser" & @LF & _
            "Alt+G: Go to channel" & @LF & _
            "Ctrl+Shift+D: Video description" & @LF & _
            "Ctrl+Shift+C: Video comments" & @LF & _
            "Alt+O: Open the Options menu" & @LF
        If $bAllowAutoPlayToggle Then
            $sHelp &= "N: Auto-play next on / off" & @LF & _
                "Shift+N / Shift+B: Next / Previous video" & @LF
        EndIf
    EndIf
    $sHelp &= "Esc: Close the player" & @LF & "Ctrl+W: Exit the application"
    Return StringSplit($sHelp, @LF, 2) ; 2 = no count element, 0-based array
EndFunc

; NEW FEATURE Hàm GUI riêng cho tính năng Sleep Timer
Func _ShowSleepTimerDialog()
    Local $hSleepGui = GUICreate("Sleep Timer", 300, 130, -1, -1, BitOR($WS_CAPTION, $WS_SYSMENU), $WS_EX_TOPMOST, $hPlayGui)
    GUISetBkColor($COLOR_BLUE)

    GUICtrlCreateLabel("Enter time to exit the app (0 min & 0 sec to disable):", 10, 15, 280, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)

    GUICtrlCreateLabel("Minutes:", 20, 45, 60, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $inpMin = GUICtrlCreateInput("0", 80, 42, 60, 20, $ES_NUMBER)

    GUICtrlCreateLabel("Seconds:", 160, 45, 60, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $inpSec = GUICtrlCreateInput("0", 220, 42, 60, 20, $ES_NUMBER)

    Local $btnSet = GUICtrlCreateButton("Set Timer", 20, 80, 120, 30)
    GUICtrlSetState(-1, $GUI_DEFBUTTON)
    Local $btnCancel = GUICtrlCreateButton("Cancel", 160, 80, 120, 30)

    Local $hDummyEsc = GUICtrlCreateDummy()
    Local $aAccel[1][2] = [["{ESC}", $hDummyEsc]]
    GUISetAccelerators($aAccel, $hSleepGui)

    GUISetState(@SW_SHOW, $hSleepGui)
    _AllowUIPI($hSleepGui)
    _AllowUIPI($inpMin)
    _AllowUIPI($inpSec)
    ControlFocus($hSleepGui, "", $inpMin)
    GUICtrlSendMsg($inpMin, 0x00B1, 0, -1) ; Bôi đen text bên trong

    While 1
        Local $nMsg = GUIGetMsg()
        Switch $nMsg
            Case $GUI_EVENT_CLOSE, $btnCancel, $hDummyEsc
                GUIDelete($hSleepGui)
                Return
            Case $btnSet
                Local $iMins = Int(GUICtrlRead($inpMin))
                Local $iSecs = Int(GUICtrlRead($inpSec))
                Local $iTotalSecs = ($iMins * 60) + $iSecs
                If $iTotalSecs > 0 Then
                    $g_iSleepTimerDuration = $iTotalSecs * 1000
                    $g_hSleepTimerInit = TimerInit()
                    _ReportStatus("Sleep timer set for " & $iMins & " minutes and " & $iSecs & " seconds. App will close after this.")
                Else
                    $g_iSleepTimerDuration = 0
                    _ReportStatus("Sleep timer disabled.")
                EndIf
                GUIDelete($hSleepGui)
                Return
        EndSwitch
    WEnd
EndFunc

Func _SaveSelection($sUrl, $sTitle)
    Local $fStart = $g_fSelectionStart
    Local $fEnd = $g_fSelectionEnd

    If $fStart = -1 Or $fEnd = -1 Then
        _ReportStatus("Error: Please set both start [ and end ] points.")
        Return
    EndIf

    If $fStart > $fEnd Then
        Local $tmp = $fStart
        $fStart = $fEnd
        $fEnd = $tmp
        _ReportStatus("Start/End swapped to match timeline.")
    EndIf

    Local $fDuration = $fEnd - $fStart
    If $fDuration <= 0 Then
        _ReportStatus("Invalid selection duration.")
        Return
    EndIf

    Local $sSafeTitle = StringRegExpReplace($sTitle, '[\\/:*?"<>|]', '_')

    ; Redesigned Save Selection: Use FileSaveDialog to let user choose name, type and path
    Local $sFilter = "Video MP4 (*.mp4)|Video WebM (*.webm)|MP3 Audio (*.mp3)|M4A Audio (*.m4a)|WAV Audio (*.wav)|FLAC Audio (*.flac)|Ogg Audio (*.ogg)|All Files (*.*)"
    Local $sInitialDir = $g_sDownloadPath
    If StringStripWS($sInitialDir, 3) = "" Or Not FileExists($sInitialDir) Then $sInitialDir = @ScriptDir & "\download"
    If Not FileExists($sInitialDir) Then DirCreate($sInitialDir)

    Local $sFilePath = FileSaveDialog("Save selection as...", $sInitialDir, $sFilter, 18, $sSafeTitle & ".mp4", $hPlayGui)
    If @error Then
        _ReportStatus("Save cancelled.")
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

    _ReportStatus("Saving selection... Please wait.")

    Local $sFFmpeg = @ScriptDir & "\lib\ffmpeg.exe"
    If Not FileExists($sFFmpeg) Then
        MsgBox(16, "Error", "ffmpeg.exe not found in lib folder!")
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
        _ReportStatus("Selection saved successfully.")
        MsgBox(64, "Success", "Selection saved successfully as:" & @CRLF & $sFilePath, 0, $hPlayGui)
    Else
        _ReportStatus("Failed to save selection.")
        MsgBox(16, "Error", "Failed to save selection. This can happen if the YouTube stream link expired or ffmpeg was blocked.", 0, $hPlayGui)
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
        $sResult &= $iHour & _Ternary($iHour = 1, " hour", " hours") & "  "
    EndIf
    If $iHour > 0 Or $iMin > 0 Then
        $sResult &= $iMin & _Ternary($iMin = 1, " minute", " minutes") & "  "
    EndIf
    $sResult &= $iSec & _Ternary($iSec = 1, " second", " seconds")
    Return $sResult
EndFunc

Func _FormatBytes($iBytes)
    Local $aUnits = ["Bytes", "KB", "MB", "GB", "TB"]
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

Func _ReportStatus($sText)
    If $sText == "" Then Return

    Local $sLow = StringLower($sText)
    Local $isTime = StringRegExp($sText, "^\d+:\d+(:\d+)?$")
    Local $isVolume = StringInStr($sLow, "volume")
    Local $isPercent = StringRegExp($sText, "^\d+%$")
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

Func _GlobalSoundPlay($sFile, $sSoundSet)
    If $sFile = "" Then Return

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
    Local $gui = GUICreate("About", 520, 300)
    GUISetBkColor($COLOR_BLUE)
    Local $txtAbout = FileExists(@ScriptDir & "\docs\about.txt") ? FileRead(@ScriptDir & "\docs\about.txt") : "VDH Media Center"
    Local $idEdit = GUICtrlCreateEdit($txtAbout, 10, 10, 400, 280, BitOR($ES_READONLY, $WS_VSCROLL))
    Local $btn_Close = GUICtrlCreateButton("Close", 420, 10, 80, 35)
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
    Local $gui = GUICreate("Read Me", 520, 300)
    GUISetBkColor($COLOR_BLUE)
    Local $txtRead = FileExists(@ScriptDir & "\docs\readme.txt") ? FileRead(@ScriptDir & "\docs\readme.txt") : "Read Me"
    Local $idEdit = GUICtrlCreateEdit($txtRead, 10, 10, 400, 280, BitOR($ES_READONLY, $WS_VSCROLL))
    Local $btn_Close = GUICtrlCreateButton("Close", 420, 10, 80, 35)
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
    Local $gui = GUICreate("License Agreement", 520, 300)
    GUISetBkColor($COLOR_BLUE)
    Local $txtLicense = FileExists(@ScriptDir & "\docs\license.txt") ? FileRead(@ScriptDir & "\docs\license.txt") : "License file not found (docs\license.txt)."
    Local $idEdit = GUICtrlCreateEdit($txtLicense, 10, 10, 400, 280, BitOR($ES_READONLY, $WS_VSCROLL))
    Local $btn_Accept = GUICtrlCreateButton("&Accept", 420, 10, 80, 35)
    Local $btn_Decline = GUICtrlCreateButton("&Decline", 420, 55, 80, 35)

    ; Thiết lập phím tắt Tab / Shift+Tab để xoay vòng: Ô văn bản -> Accept -> Decline
    Local $dummy_tab = GUICtrlCreateDummy()
    Local $dummy_shifttab = GUICtrlCreateDummy()
    Local $aAccel[2][2] = [["{TAB}", $dummy_tab], ["+{TAB}", $dummy_shifttab]]
    GUISetAccelerators($aAccel, $gui)

    GUISetState(@SW_SHOW, $gui)
    WinActivate($gui)
    ControlFocus($gui, "", $idEdit)

    Local $aOrder[3] = [$idEdit, $btn_Accept, $btn_Decline] ; thứ tự Tab
    Local $bAccepted = False
    While 1
        Local $msg = _GuiMsg($gui)
        Switch $msg
            Case $GUI_EVENT_CLOSE, $btn_Decline
                ExitLoop
            Case $btn_Accept
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

    GUIDelete($gui)
    Return $bAccepted
EndFunc

Func _Show_Contact_Window()
    Local $gui = GUICreate("Contact", 300, 200)
    GUISetBkColor($COLOR_BLUE)

    Local $fb = GUICtrlCreateButton("Facebook", 50, 30, 200, 30)
    Local $email = GUICtrlCreateButton("Email", 50, 70, 200, 30)

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
    Local $gui = GUICreate("Send Feedback", 420, 320, -1, -1, BitOR($WS_CAPTION, $WS_POPUPWINDOW, $WS_VISIBLE))
    GUISetBkColor($COLOR_BLUE, $gui)

    GUICtrlCreateLabel("Title:", 10, 10, 400, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $idTitle = GUICtrlCreateInput("[Feature]: ", 10, 30, 400, 22)

    GUICtrlCreateLabel("Describe your idea:", 10, 62, 400, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $idDesc = GUICtrlCreateEdit("", 10, 84, 400, 170, BitOR($ES_WANTRETURN, $ES_AUTOVSCROLL, $WS_VSCROLL))

    Local $btnSend = GUICtrlCreateButton("Send", 220, 270, 90, 32)
    GUICtrlSetState(-1, $GUI_DEFBUTTON)
    Local $btnCancel = GUICtrlCreateButton("Cancel", 320, 270, 90, 32)

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
                    MsgBox(48, "Send Feedback", "Please describe your idea before sending.")
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
        MsgBox(16, "Error", "Cannot open favorites file.")
        Return
    EndIf
    FileWriteLine($hFile, $sID & "|" & $sTitle)
    FileClose($hFile)
    MsgBox(64, "Success", "Added to favorites successfully!")
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
    GUISetState(@SW_HIDE, $mainform)

    ; Increased height to 480 to match History window and fit the extra button comfortably
    $hFavoritesGui = GUICreate("Favorite Videos", 400, 526)
    GUISetBkColor($COLOR_BLUE)
    GUICtrlCreateLabel("Your favorite videos:", 10, 10, 380, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    GUICtrlSetFont(-1, 10, 800)
    $lst_results = GUICtrlCreateList("", 10, 35, 380, 355, BitOR($LBS_NOTIFY, $WS_VSCROLL, $WS_BORDER))

    Local $btn_clear_fav = GUICtrlCreateButton("Clear all favorites", 10, 400, 380, 30)
    Local $btn_go_back = GUICtrlCreateButton("go back", 10, 440, 380, 30)

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
                    If MsgBox(36, "Confirm", "Are you sure you want to clear all favorites?") = 6 Then
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
                If MsgBox(36, "Confirm", "Are you sure you want to clear all favorites?") = 6 Then
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
    GUICtrlSetData($lst_results, "")
    Local $hFile = FileOpen($FAVORITES_FILE, 0 + 256) ; Read as UTF-8
    Global $aSearchIds[1]
    Global $aSearchTitles[1]
    $iTotalLoaded = 0
    $bEndReached = True ; No pagination for favorites yet

    If $hFile <> -1 Then
        While 1
            Local $sLine = FileReadLine($hFile)
            If @error = -1 Then ExitLoop
            Local $aParts = StringSplit($sLine, "|")
            If $aParts[0] >= 2 Then
                Local $sID = $aParts[1]
                Local $sTitle = $aParts[2]
                $iTotalLoaded += 1
                _GUICtrlListBox_AddString($lst_results, $iTotalLoaded & ". " & $sTitle)
                ReDim $aSearchIds[$iTotalLoaded + 1]
                ReDim $aSearchTitles[$iTotalLoaded + 1]
                $aSearchIds[$iTotalLoaded] = $sID
                $aSearchTitles[$iTotalLoaded] = $sTitle
            EndIf
        WEnd
        FileClose($hFile)
    EndIf


EndFunc

Func _ShowHistory()
    GUISetState(@SW_HIDE, $mainform)

    $hHistoryGui = GUICreate("Watch History", 400, 496)
    GUISetBkColor($COLOR_BLUE)
    GUICtrlCreateLabel("Your watch history:", 10, 10, 380, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    GUICtrlSetFont(-1, 10, 800)
    $lst_results = GUICtrlCreateList("", 10, 35, 380, 325, BitOR($LBS_NOTIFY, $WS_VSCROLL, $WS_BORDER))

    Local $btn_clear_all = GUICtrlCreateButton("Clear all history", 10, 370, 380, 30)
    Local $btn_go_back = GUICtrlCreateButton("Go back (Alt+B)", 10, 410, 380, 30)

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
                            _ReportStatus("Cannot play a playlist in audio-only mode directly. Please open the playlist first.")
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
                If MsgBox(36, "Confirm", "Are you sure you want to clear all history?") = 6 Then
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
	GUICtrlSetData($lst_results, "")
	If Not FileExists($HISTORY_FILE) Then Return

	Local $hFile = FileOpen($HISTORY_FILE, 0 + 256) ; Read as UTF-8
	Local $sContent = FileRead($hFile)
	FileClose($hFile)

	If $sContent = "" Then
		Return
	EndIf

	Local $aHistoryLines = StringSplit(StringStripCR($sContent), @LF)
	Global $aSearchIds[1]
	Global $aSearchTitles[1]
	Global $aSearchTypes[1] ; <-- IMPORTANT
	$iTotalLoaded = 0
	$bEndReached = True

	; Show from newest to oldest
	For $i = $aHistoryLines[0] To 1 Step -1
		Local $sLine = $aHistoryLines[$i]
		If $sLine = "" Then ContinueLoop

		Local $aParts = StringSplit($sLine, "|")
		If $aParts[0] >= 2 Then
			Local $sID = $aParts[1]
			Local $sTitle = $aParts[2]
			Local $sType = ($aParts[0] >= 3) ? $aParts[3] : "video" ; Read type, default to video

			$iTotalLoaded += 1
			Local $sDisplayTitle = $iTotalLoaded & ". " & $sTitle
			If $sType = "playlist" Then
				$sDisplayTitle &= " [Playlist]" ; Add a visual indicator
			EndIf
			_GUICtrlListBox_AddString($lst_results, $sDisplayTitle)

			ReDim $aSearchIds[$iTotalLoaded + 1]
			ReDim $aSearchTitles[$iTotalLoaded + 1]
			ReDim $aSearchTypes[$iTotalLoaded + 1] ; <-- IMPORTANT
			$aSearchIds[$iTotalLoaded] = $sID
			$aSearchTitles[$iTotalLoaded] = $sTitle
			$aSearchTypes[$iTotalLoaded] = $sType ; <-- IMPORTANT
		EndIf
	Next

	If $iTotalLoaded = 0 Then
		MsgBox(64, "Info", "No history found.")
	EndIf
EndFunc

Func _AutoDetectClipboardLink()
    Local $clip = ClipGet()
    If Not (StringInStr($clip, "youtube.com") Or StringInStr($clip, "youtu.be")) Then Return

    ; Check if focus is in an edit box (per requirement)
    Local $focus = ControlGetFocus($mainform)
    If StringInStr($focus, "Edit") Then Return

    Local $hAutoGui = GUICreate("Link detected", 300, 150, -1, -1, BitOR($WS_CAPTION, $WS_POPUP, $WS_SYSMENU), -1, $mainform)
    GUISetBkColor(0xFFFFFF)
    GUICtrlCreateLabel("A YouTube link was found in your clipboard. What would you like to do?", 10, 10, 280, 40)

    Local $btn_Play = GUICtrlCreateButton("Play", 10, 60, 135, 30)
    Local $btn_DL = GUICtrlCreateButton("Download", 155, 60, 135, 30)
    Local $btn_Cancel = GUICtrlCreateButton("Cancel", 10, 100, 280, 30)

    GUISetState(@SW_SHOW, $hAutoGui)

    While 1
        Local $nMsg = GUIGetMsg()
        Select
            Case $nMsg = $GUI_EVENT_CLOSE Or $nMsg = $btn_Cancel
                GUIDelete($hAutoGui)
                ExitLoop
            Case $nMsg = $btn_Play
                GUIDelete($hAutoGui)
                playmedia($clip)
                ExitLoop
            Case $nMsg = $btn_DL
                GUIDelete($hAutoGui)
                Local $id = _GetYoutubeID($clip)
                If $id <> "" Then
                    Local $sTitle = _GetYoutubeTitle($clip)
                    _ShowDownloadDialog($id, $sTitle)
                Else
                    MsgBox(16, "Error", "Could not extract video ID from link.")
                EndIf
                ExitLoop
        EndSelect
    WEnd
EndFunc

Func _Check_YTDLP_Update($bSilent = False)

    Local $hCheckGUI = 0
    If Not $bSilent Then
        Local $sCheckingText = "Checking for updates yt-dlp..."
        $hCheckGUI = GuiCreate("", 300, 80, -1, -1, BitOR($WS_CAPTION, $WS_POPUP), BitOR($WS_EX_TOPMOST, $WS_EX_TOOLWINDOW))
        GuiSetBkColor(0xFFFFFF, $hCheckGUI)
        Local $lblCheck = GuiCtrlCreateLabel($sCheckingText, 10, 25, 280, 30, $ES_CENTER)
        GuiCtrlSetFont($lblCheck, 10, 400, 0, "Arial")
        GuiSetState(@SW_SHOW, $hCheckGUI)
    EndIf

    If Ping("github.com", 2000) = 0 And Ping("google.com", 2000) = 0 Then
         If Not $bSilent Then
             GuiDelete($hCheckGUI)
             MsgBox(48, "Check Update", "No internet connection.")
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
            MsgBox(16, "Error", "Cannot create HTTP Object.")
        EndIf
        Return
    EndIf

    $oHTTP.Open("GET", $sApiUrl, False)
    $oHTTP.SetRequestHeader("User-Agent", "Mozilla/5.0")
    $oHTTP.Send()

    If @error Then
        If Not $bSilent Then
            GuiDelete($hCheckGUI)
            MsgBox(48, "Check Update", "Connection failed. Please check your internet.")
        EndIf
        Return
    EndIf

    If $oHTTP.Status <> 200 Then
        If Not $bSilent Then
            GuiDelete($hCheckGUI)
            MsgBox(48, "Check Update", "Cannot connect to update server or no release found." & @CRLF & "Status Code: " & $oHTTP.Status)
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
            SoundPlay("sounds/update_yt-dlp.wav")
            Local $sVerInfo = "new version (" & $sLatestVersion & ")!" & @CRLF
            If $sLocalVersion <> "0" Then
                $sVerInfo &= "Current version: " & $sLocalVersion
            Else
                $sVerInfo &= "Current version: Not installed or unknown"
            EndIf

            Local $iMsg = MsgBox(36, "Update Available", $sVerInfo & @CRLF & @CRLF & _
                                     "Do you want to download it now?")
            If $iMsg = 6 Then
                If _VLC_Direct_Init() Then
                    _VLC_Direct_Play("file:///" & StringReplace(@ScriptDir & "\sounds\updating_yt-dlp.wav", "\", "/"))
                    _VLC_Direct_SetVolume($g_iAppVolume)
                Else
                    DllCall("winmm.dll", "int", "PlaySoundW", "wstr", @ScriptDir & "\sounds\updating_yt-dlp.wav", "ptr", 0, "dword", 0x0009)
                EndIf

                $downloadtext = "please wait..."
                $downloadGui = GuiCreate("downloading update...", 400, 100, -1, -1)
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

                ProgressOn("Downloading Update", "Please wait while downloading...", "0%")
                $g_sUpdateStatus = "downloading"
                $g_iUpdatePct = 0

                Local $hDownload = InetGet($sDownloadURL, $sSavePathTemp, 1, 1)

                Do
                    Local $msg = GUIGetMsg()
                    Select
                        Case $msg = $hDummySpaceUpdate
                            _ReportStatus("Downloaded " & $g_iUpdatePct & "%")
                        Case $msg = $hDummyHUpdate
                            _ReportStatus($g_sUpdateStatus)
                        Case $msg = $hDummyPgUpUpdate
                            _StepAppVolume(1)
                        Case $msg = $hDummyPgDnUpdate
                            _StepAppVolume(-1)
                        Case $msg = $hDummy1Update
                            _ReportStatus("File size: " & _FormatBytes($g_iUpdateFileSize))
                        Case $msg = $hDummy2Update
                            _ReportStatus("Total downloaded: " & _FormatBytes($g_iUpdateBytesRead))
                        Case $msg = $hDummy3Update
                            _ReportStatus("Total remaining: " & _FormatBytes($g_iUpdateFileSize - $g_iUpdateBytesRead))
                    EndSelect
                    
                    Sleep(10)
                    ; Tự động phát lại nhạc nếu kết thúc (Lặp lại)
                    If _VLC_Direct_GetState() = 6 Then ; 6 = Ended
                        _VLC_Direct_Play("file:///" & StringReplace(@ScriptDir & "\sounds\updating_yt-dlp.wav", "\", "/"))
                        _VLC_Direct_SetVolume($g_iAppVolume)
                    EndIf
                    $g_iUpdateBytesRead = InetGetInfo($hDownload, 0)
                    $g_iUpdateFileSize = InetGetInfo($hDownload, 1)

                    If $g_iUpdateFileSize > 0 Then
                        $g_iUpdatePct = Round(($g_iUpdateBytesRead / $g_iUpdateFileSize) * 100)
                        ProgressSet($g_iUpdatePct, $g_iUpdatePct & "% complete")
                    Else
                        ProgressSet(0, "Connecting...")
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
                    MsgBox(16, "Error", "Download failed. Error code: " & $iError)
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
            SoundPlay("sounds/updated_yt-dlp.wav")
                        MsgBox(64, "Success", "yt-dlp has been updated successfully!")
        SoundPlay("sounds/restart.wav")
                        If MsgBox(4, "Restart Required", "The software needs to restart to apply the update. Restart now?") = 6 Then
                            ShellExecute(@ScriptFullPath, "/restart")
                            Exit
                        EndIf
                    Else
                        MsgBox(16, "Error", "Failed to replace yt-dlp.exe. Please close any programs using it and try again.")
                        FileDelete($sSavePathTemp)
                    EndIf
                EndIf
            EndIf
        Else
            If Not $bSilent Then MsgBox(64, "no update available", "You are using the latest version from yt-dlp.")
        EndIf
    Else
        If Not $bSilent Then MsgBox(16, "Error", "Could not parse version information.")
    EndIf
EndFunc

Func _CheckGithubUpdate($bSilent = False)

    Local $hCheckGUI = 0
    If Not $bSilent Then
        Local $sCheckingText = "Checking for updates..."
        $hCheckGUI = GuiCreate("", 300, 80, -1, -1, BitOR($WS_CAPTION, $WS_POPUP), BitOR($WS_EX_TOPMOST, $WS_EX_TOOLWINDOW))
        GuiSetBkColor(0xFFFFFF, $hCheckGUI)
        Local $lblCheck = GuiCtrlCreateLabel($sCheckingText, 10, 25, 280, 30, $ES_CENTER)
        GuiCtrlSetFont($lblCheck, 10, 400, 0, "Arial")
        GuiSetState(@SW_SHOW, $hCheckGUI)
    EndIf

    If Ping("github.com", 2000) = 0 And Ping("google.com", 2000) = 0 Then
         If Not $bSilent Then
             GuiDelete($hCheckGUI)
             MsgBox(48, "Check Update", "No internet connection.")
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
            MsgBox(16, "Error", "Cannot create HTTP Object.")
        EndIf
        Return
    EndIf

    $oHTTP.Open("GET", $sApiUrl, False)
    $oHTTP.SetRequestHeader("User-Agent", "Mozilla/5.0")
    $oHTTP.Send()

    If @error Then
        If Not $bSilent Then
            GuiDelete($hCheckGUI)
            MsgBox(48, "Check Update", "Connection failed. Please check your internet.")
        EndIf
        Return
    EndIf

    If $oHTTP.Status <> 200 Then
        If Not $bSilent Then
            GuiDelete($hCheckGUI)
            MsgBox(48, "Check Update", "Cannot connect to update server or no release found." & @CRLF & "Status Code: " & $oHTTP.Status)
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
            SoundPlay("sounds/update.wav")
            
            ; Extract changelog from body
            Local $aBodyMatch = StringRegExp($sResponse, '"body":\s*"([^"\\]*(?:\\.[^"\\]*)*)"', 3)
            Local $sChangelog = ""
            If IsArray($aBodyMatch) Then
                $sChangelog = _UnescapeJSON($aBodyMatch[0])
                $sChangelog = _StripMarkdown($sChangelog)
            EndIf

            ; Custom Update GUI
            Local $hUpdateGUI = GUICreate("Update Available", 400, 420)
            GUISetBkColor($COLOR_BLUE)
            GUISetFont(9, 400, 0, "Segoe UI")

            GUICtrlCreateLabel("new version(" & $sLatestVersion & ")!", 10, 10, 380, 25)
            GUICtrlSetColor(-1, 0xFFFFFF)
            GUICtrlSetFont(-1, 11, 800)

            GUICtrlCreateLabel("current version: " & $version, 10, 40, 380, 20)
            GUICtrlSetColor(-1, 0xFFFFFF)

            GUICtrlCreateLabel("Changelog for " & $sLatestVersion & ":", 10, 70, 380, 20)
            GUICtrlSetColor(-1, 0xFFFFFF)

            Local $editChangelog = GUICtrlCreateEdit($sChangelog, 10, 95, 380, 240, BitOR($ES_AUTOVSCROLL, $ES_READONLY, $WS_VSCROLL, $WS_TABSTOP))
            
            GUICtrlCreateLabel("Do you want to download and install this update now?", 10, 345, 380, 20)
            GUICtrlSetColor(-1, 0xFFFFFF)
            GUICtrlSetFont(-1, 9, 600)

            Local $btnYes = GUICtrlCreateButton("&Yes, Download Now", 60, 370, 130, 35)
            Local $btnNo = GUICtrlCreateButton("&No, Later", 210, 370, 130, 35)

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
                    _VLC_Direct_Play("file:///" & StringReplace(@ScriptDir & "\sounds\updating.wav", "\", "/"))
                    _VLC_Direct_SetVolume($g_iAppVolume)
                Else
                    DllCall("winmm.dll", "int", "PlaySoundW", "wstr", @ScriptDir & "\sounds\updating.wav", "ptr", 0, "dword", 0x0009)
                EndIf

                $downloadtext = "please wait"
                $downloadGui = GuiCreate("downloading update", 400, 400, -1, -1)
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

                ProgressOn("Downloading Update", "Please wait while downloading...", "0%")
                $g_sUpdateStatus = "downloading"
                $g_iUpdatePct = 0

                Local $hDownload = InetGet($sDownloadURL, $sSavePath, 1, 1)

                Do
                    Local $msg = GUIGetMsg()
                    Select
                        Case $msg = $hDummySpaceUpdate
                            _ReportStatus("Downloaded " & $g_iUpdatePct & "%")
                        Case $msg = $hDummyHUpdate
                            _ReportStatus($g_sUpdateStatus)
                        Case $msg = $hDummyPgUpUpdate
                            _StepAppVolume(1)
                        Case $msg = $hDummyPgDnUpdate
                            _StepAppVolume(-1)
                        Case $msg = $hDummy1Update
                            _ReportStatus("File size: " & _FormatBytes($g_iUpdateFileSize))
                        Case $msg = $hDummy2Update
                            _ReportStatus("Total downloaded: " & _FormatBytes($g_iUpdateBytesRead))
                        Case $msg = $hDummy3Update
                            _ReportStatus("Total remaining: " & _FormatBytes($g_iUpdateFileSize - $g_iUpdateBytesRead))
                    EndSelect

                    Sleep(10)
                    ; Tự động phát lại nhạc nếu kết thúc (Lặp lại)
                    If _VLC_Direct_GetState() = 6 Then ; 6 = Ended
                        _VLC_Direct_Play("file:///" & StringReplace(@ScriptDir & "\sounds\updating.wav", "\", "/"))
                        _VLC_Direct_SetVolume($g_iAppVolume)
                    EndIf
                    $g_iUpdateBytesRead = InetGetInfo($hDownload, 0)
                    $g_iUpdateFileSize = InetGetInfo($hDownload, 1)

                    If $g_iUpdateFileSize > 0 Then
                        $g_iUpdatePct = Round(($g_iUpdateBytesRead / $g_iUpdateFileSize) * 100)
                        ProgressSet($g_iUpdatePct, $g_iUpdatePct & "% complete")
                    Else
                        ProgressSet(0, "Connecting...")
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
                    MsgBox(16, "Error", "Download failed. Error code: " & $iError)
                    FileDelete($sSavePath)
                    Return
                EndIf

                If FileExists($sSavePath) And FileGetSize($sSavePath) > 0 Then
                SoundPlay("sounds/updated.wav")
                MsgBox(64, "Success", "Downloaded successfully!" & @CRLF & "File saved as: " & $sSavePath)
Run("unzip.exe")
                ; ShellExecute($sSavePath)
Exit
                EndIf
            EndIf
        Else
            If Not $bSilent Then
                MsgBox(64, "no update available", "You are using the latest version (" & $version & ").")
            EndIf
        EndIf
    Else
        If Not $bSilent Then
            MsgBox(16, "Error", "Could not parse version information.")
        EndIf
    EndIf
EndFunc

Func _ShowChangelog()
    Local $sFilePath = "docs\changelog.txt"
    Local $sContent = "No changelog found."

    If FileExists($sFilePath) Then
        $sContent = FileRead($sFilePath)
        $sContent = _StripMarkdown($sContent)
    EndIf

    Local $hChangelogGUI = GuiCreate("Changelog", 400, 450)
    Local $editChangelog = GUICtrlCreateEdit($sContent, 10, 10, 380, 380, BitOR($ES_AUTOVSCROLL, $ES_READONLY, $WS_VSCROLL, $WS_TABSTOP))
    Local $btnClose = GUICtrlCreateButton("&Close", 150, 400, 100, 30, $WS_TABSTOP)

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
    $g_hSettingsGui = GUICreate("Settings", 450, 450, -1, -1, BitOR($WS_CAPTION, $WS_SYSMENU, $WS_POPUP))
    GUISetBkColor($COLOR_BLUE)
    GUISetFont(9, 400, 0, "Segoe UI")

    $g_hSettingsTab = GUICtrlCreateTab(10, 10, 430, 350)

    $g_hSettingsDummyNext = GUICtrlCreateDummy()
    $g_hSettingsDummyPrev = GUICtrlCreateDummy()
    ; Accelerators are often blocked by child controls, so we also use HotKeySet below.
    Local $aAccelSettings[2][2] = [["^{TAB}", $g_hSettingsDummyNext], ["^+{TAB}", $g_hSettingsDummyPrev]]
    GUISetAccelerators($aAccelSettings, $g_hSettingsGui)

    Local $aTabItems[5]
    ; --- Tab General ---
    $aTabItems[0] = GUICtrlCreateTabItem("General")
    GUICtrlCreateLabel("General Settings", 20, 50, 410, 20)
    GUICtrlSetFont(-1, 10, 800)
    GUICtrlSetColor(-1, 0xFFFFFF)

    Local $chk_AutoUpdate = GUICtrlCreateCheckbox("Automatically check for updates on startup", 30, 80, 380, 20)
    If $g_bAutoUpdate Then GUICtrlSetState(-1, $GUI_CHECKED)
    GUICtrlSetColor(-1, 0xFFFFFF)

    Local $chk_AutoStart = GUICtrlCreateCheckbox("Start program automatically after login", 30, 110, 380, 20)
    If $g_bAutoStart Then GUICtrlSetState(-1, $GUI_CHECKED)
    GUICtrlSetColor(-1, 0xFFFFFF)

    Local $chk_AutoDetect = GUICtrlCreateCheckbox("Automatically detect YouTube links in clipboard on launch", 30, 140, 380, 20)
    If $g_bAutoDetectLink Then GUICtrlSetState(-1, $GUI_CHECKED)
    GUICtrlSetColor(-1, 0xFFFFFF)

    Local $chk_AutoUpdateYTDLP = GUICtrlCreateCheckbox("Automatically check for yt-dlp updates on startup", 30, 170, 380, 20)
    If $g_bAutoUpdateYTDLP Then GUICtrlSetState(-1, $GUI_CHECKED)
    GUICtrlSetColor(-1, 0xFFFFFF)

    ; --- Tab Player ---
    $aTabItems[1] = GUICtrlCreateTabItem("Player")
    GUICtrlCreateLabel("Player Settings", 20, 50, 410, 20)
    GUICtrlSetFont(-1, 10, 800)
    GUICtrlSetColor(-1, 0xFFFFFF)

    GUICtrlCreateLabel("Audio Output Device:", 30, 80, 150, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $cbo_OutputDevice = GUICtrlCreateCombo("", 180, 75, 230, 20, $CBS_DROPDOWNLIST)
    GUICtrlSetTip(-1, "Chọn thiết bị xuất âm thanh, dùng phím mũi tên để duyệt danh sách theo thứ tự bảng chữ cái")
    Local $aAudioDevices = _VLC_GetAudioOutputs()
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

    Local $chk_SkipSilence = GUICtrlCreateCheckbox("Skip silence (Recommended only for music)", 30, 110, 380, 20)
    If $g_bSkipSilence Then GUICtrlSetState(-1, $GUI_CHECKED)
    GUICtrlSetColor(-1, 0xFFFFFF)

    GUICtrlCreateLabel("Seeking Announcement Mode:", 30, 140, 200, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $cbo_AnnouncementMode = GUICtrlCreateCombo("", 230, 135, 180, 20, $CBS_DROPDOWNLIST)
    GUICtrlSetTip(-1, "Chọn cách thông báo khi tua video")
    GUICtrlSetData(-1, "Silent|Read percentage|Read time", "Silent")
    _GUICtrlComboBox_SetCurSel($cbo_AnnouncementMode, $g_iAnnouncementMode)

    GUICtrlCreateLabel("After Video Finishes:", 30, 175, 150, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $cbo_AfterAction = GUICtrlCreateCombo("", 180, 170, 230, 20, $CBS_DROPDOWNLIST)
    GUICtrlSetTip(-1, "Chọn hành động sau khi video kết thúc")
    GUICtrlSetData(-1, "Close the player|Replay video|Do nothing", "Do nothing")
    ; Set current selection
    If $g_iAfterVideoAction = 0 Then
        _GUICtrlComboBox_SetCurSel($cbo_AfterAction, 0)
    ElseIf $g_iAfterVideoAction = 1 Then
        _GUICtrlComboBox_SetCurSel($cbo_AfterAction, 1)
    ElseIf $g_iAfterVideoAction = 2 Then
        _GUICtrlComboBox_SetCurSel($cbo_AfterAction, 2)
    EndIf

    GUICtrlCreateLabel("Fast Forward Interval (Seconds):", 30, 210, 200, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $inp_FFStep = GUICtrlCreateInput(String($g_iFFStep), 230, 205, 50, 20, 0x2000) ; 0x2000 = $ES_NUMBER

    GUICtrlCreateLabel("Rewind Interval (Seconds):", 30, 240, 200, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $inp_RWStep = GUICtrlCreateInput(String($g_iRWStep), 230, 235, 50, 20, 0x2000) ; 0x2000 = $ES_NUMBER

    Local $chk_ContinueWatching = GUICtrlCreateCheckbox("Continue watching (Resume from last position)", 30, 270, 380, 20)
    If $g_bContinueWatching Then GUICtrlSetState(-1, $GUI_CHECKED)
    GUICtrlSetColor(-1, 0xFFFFFF)

    Local $chk_SaveHistory = GUICtrlCreateCheckbox("Save watch history", 30, 300, 380, 20)
    If $g_bSaveHistory Then GUICtrlSetState(-1, $GUI_CHECKED)
    GUICtrlSetColor(-1, 0xFFFFFF)

    Local $chk_SaveSearchHistory = GUICtrlCreateCheckbox("Save search history", 30, 330, 380, 20)
    If $g_bSaveSearchHistory Then GUICtrlSetState(-1, $GUI_CHECKED)
    GUICtrlSetColor(-1, 0xFFFFFF)

    ; --- Tab Download ---
    $aTabItems[2] = GUICtrlCreateTabItem("Download")
    GUICtrlCreateLabel("Download Settings", 20, 50, 410, 20)
    GUICtrlSetFont(-1, 10, 800)
    GUICtrlSetColor(-1, 0xFFFFFF)

    Local $sTempDLPath = $g_sDownloadPath
    GUICtrlCreateLabel("Download Folder:", 30, 80, 380, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $inp_DownloadPath = GUICtrlCreateEdit($sTempDLPath, 30, 105, 380, 60, BitOR($ES_READONLY, $WS_TABSTOP))
    _AllowUIPI($inp_DownloadPath) ; Ensure screen reader access
    ; Subclass to prevent manual typing if needed, but standard edit is better for accessibility.
    ; We'll just leave it as standard edit so screen readers can read it easily.

    Local $btn_ChangePath = GUICtrlCreateButton("Change Path", 30, 175, 180, 30)
    Local $btn_ResetPath = GUICtrlCreateButton("Reset to Default Directory", 220, 175, 190, 30)

    ; --- Tab Search ---
    $aTabItems[3] = GUICtrlCreateTabItem("Search")
    GUICtrlCreateLabel("Search Settings", 20, 50, 410, 20)
    GUICtrlSetFont(-1, 10, 800)
    GUICtrlSetColor(-1, 0xFFFFFF)

    Local $chk_VoiceAutoSearch = GUICtrlCreateCheckbox("Automatically search after voice input", 30, 80, 380, 20)
    If $g_bVoiceAutoSearch Then GUICtrlSetState(-1, $GUI_CHECKED)
    GUICtrlSetColor(-1, 0xFFFFFF)

    Local $chk_TypingSound = GUICtrlCreateCheckbox("Enable typing sounds in search box", 30, 110, 380, 20)
    If $g_bTypingSoundEnabled Then GUICtrlSetState(-1, $GUI_CHECKED)
    GUICtrlSetColor(-1, 0xFFFFFF)

    GUICtrlCreateLabel("select typing sound:", 30, 140, 150, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $cbo_TypingSoundSet = GUICtrlCreateCombo("", 180, 135, 230, 20, $CBS_DROPDOWNLIST)
    GUICtrlSetTip(-1, "Chọn bộ âm thanh gõ phím, danh sách đã theo thứ tự bảng chữ cái, dùng phím mũi tên để duyệt")
    GUICtrlSetData(-1, "1blueSwitch|2redSwitch|3brownSwitche|iPhone|Samsung_Galaxy|VDH_keyboard1|VDH_keyboard2", $g_sTypingSoundSet)

    ; --- Tab Data ---
    $aTabItems[4] = GUICtrlCreateTabItem("Data")
    GUICtrlCreateLabel("Configuration Backup & Restore", 20, 50, 410, 20)
    GUICtrlSetFont(-1, 10, 800)
    GUICtrlSetColor(-1, 0xFFFFFF)

    Local $btn_Backup = GUICtrlCreateButton("Backup Configuration...", 30, 90, 200, 35)
    Local $btn_Restore = GUICtrlCreateButton("Restore Configuration...", 30, 140, 200, 35)

    GUICtrlCreateTabItem("") ; End Tab Control

    Local $btn_Save = GUICtrlCreateButton("Ok", 120, 380, 100, 35)
    Local $btn_Cancel = GUICtrlCreateButton("Cancel", 230, 380, 100, 35)

    GUISetState(@SW_SHOW, $g_hSettingsGui)

    ; Register WM_ACTIVATE to handle hotkeys only when window is active
    GUIRegisterMsg($WM_ACTIVATE, "_Settings_WM_ACTIVATE")

    ; Initial activation
    _Settings_ToggleHotKeys(True)

    While 1
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

            Case $btn_Backup
                Local $sSavePath = FileSaveDialog("Select backup location", @DesktopDir, "Zip Archive (*.zip)", 2, "VDH_Config_Backup.zip")
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
                        MsgBox(64, "Backup Completed", "The configuration backup has been created successfully at:" & @CRLF & $sSavePath)
                    Else
                        MsgBox(16, "Error", "Failed to create backup. Please check if you have write permissions.")
                    EndIf
                EndIf

            Case $btn_Restore
                Local $sOpenPath = FileOpenDialog("Select Backup File", @DesktopDir, "Zip Archive (*.zip)", 1)
                If Not @error Then
                    SoundPlay("sounds/restart.wav")
                    Local $iConfirm = MsgBox(4, "Confirm Restore", "Restoring data will overwrite your current configuration and restart the program. Are you sure you want to proceed?")
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

                        SoundPlay("sounds/restart.wav")
                        MsgBox(0, "Success", "Restore successful! Program will now restart.")
                        ShellExecute(@ScriptFullPath, "/restart")
                        Exit
                    EndIf
                EndIf

            Case $btn_ChangePath
                Local $sNewPath = FileSelectFolder("Select Download Folder", "", 1, $sTempDLPath, $g_hSettingsGui)
                If Not @error And $sNewPath <> "" Then
                    $sTempDLPath = $sNewPath
                    GUICtrlSetData($inp_DownloadPath, $sTempDLPath)
                EndIf

            Case $btn_ResetPath
                $sTempDLPath = @ScriptDir & "\download"
                If Not FileExists($sTempDLPath) Then DirCreate($sTempDLPath)
                GUICtrlSetData($inp_DownloadPath, $sTempDLPath)

            Case $btn_Save
                ; Read checkbox states
                $g_bAutoUpdate = (GUICtrlRead($chk_AutoUpdate) = $GUI_CHECKED)
                $g_bAutoStart = (GUICtrlRead($chk_AutoStart) = $GUI_CHECKED)
                $g_bAutoDetectLink = (GUICtrlRead($chk_AutoDetect) = $GUI_CHECKED)
                $g_bAutoUpdateYTDLP = (GUICtrlRead($chk_AutoUpdateYTDLP) = $GUI_CHECKED)
                $g_bVoiceAutoSearch = (GUICtrlRead($chk_VoiceAutoSearch) = $GUI_CHECKED)
                $g_bTypingSoundEnabled = (GUICtrlRead($chk_TypingSound) = $GUI_CHECKED)
                $g_sTypingSoundSet = GUICtrlRead($cbo_TypingSoundSet)
                $g_bSkipSilence = (GUICtrlRead($chk_SkipSilence) = $GUI_CHECKED)
                $g_bContinueWatching = (GUICtrlRead($chk_ContinueWatching) = $GUI_CHECKED)
                $g_bSaveHistory = (GUICtrlRead($chk_SaveHistory) = $GUI_CHECKED)
                $g_bSaveSearchHistory = (GUICtrlRead($chk_SaveSearchHistory) = $GUI_CHECKED)
                $g_iAnnouncementMode = _GUICtrlComboBox_GetCurSel($cbo_AnnouncementMode)
                $g_iAfterVideoAction = _GUICtrlComboBox_GetCurSel($cbo_AfterAction)

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
                IniWrite($CONFIG_FILE, "Settings", "VoiceAutoSearch", $g_bVoiceAutoSearch ? "true" : "false")
                IniWrite($CONFIG_FILE, "Settings", "SkipSilence", $g_bSkipSilence ? "true" : "false")
                IniWrite($CONFIG_FILE, "Settings", "ContinueWatching", $g_bContinueWatching ? "true" : "false")
                IniWrite($CONFIG_FILE, "Settings", "SaveHistory", $g_bSaveHistory ? "true" : "false")
                IniWrite($CONFIG_FILE, "Settings", "SaveSearchHistory", $g_bSaveSearchHistory ? "true" : "false")
                IniWrite($CONFIG_FILE, "Settings", "AnnouncementMode", String($g_iAnnouncementMode))
                IniWrite($CONFIG_FILE, "Settings", "AutoPlay", $g_bAutoPlay ? "true" : "false")
                IniWrite($CONFIG_FILE, "Settings", "Repeat", $g_bRepeat ? "true" : "false")
                IniWrite($CONFIG_FILE, "Settings", "AfterVideoAction", String($g_iAfterVideoAction))
                IniWrite($CONFIG_FILE, "Settings", "SearchFilter", $g_sSearchFilter)
                If StringStripWS($sTempDLPath, 3) <> "" Then
                    $g_sDownloadPath = $sTempDLPath
                    If Not FileExists($g_sDownloadPath) Then DirCreate($g_sDownloadPath)
                    IniWrite($CONFIG_FILE, "Settings", "DownloadPath", $g_sDownloadPath)
                EndIf
                IniWrite($CONFIG_FILE, "Settings", "FFStep", String($g_iFFStep))
                IniWrite($CONFIG_FILE, "Settings", "RWStep", String($g_iRWStep))
                IniWrite($CONFIG_FILE, "Settings", "TypingSoundEnabled", $g_bTypingSoundEnabled ? "true" : "false")
                IniWrite($CONFIG_FILE, "Settings", "TypingSoundSet", $g_sTypingSoundSet)
                _ResolveTypingSounds()
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
                GUIDelete($g_hSettingsGui)
                If $bDeviceChanged Then
                    SoundPlay("sounds/restart.wav")
                    Local $iMsgBox = MsgBox(4, "Restart Required", "Audio output device changed. Do you want to restart the application now to apply the changes?")
                    If $iMsgBox = 6 Then
                        ShellExecute(@ScriptFullPath, "/restart")
                        Exit
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

    Local $hGoToTimeGui = GUICreate("Go to Time", 250, 150, -1, -1, BitOR($WS_CAPTION, $WS_SYSMENU), $WS_EX_TOPMOST, $hPlayGui)
    GUISetBkColor($COLOR_BLUE)

    GUICtrlCreateLabel("Minutes:", 10, 20, 80, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    GUICtrlSetFont(-1, 10, 800)
    Local $inpMin = GUICtrlCreateInput("", 100, 17, 100, 20, $ES_NUMBER)

    GUICtrlCreateLabel("Seconds:", 10, 50, 80, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    GUICtrlSetFont(-1, 10, 800)
    Local $inpSec = GUICtrlCreateInput("", 100, 47, 100, 20, $ES_NUMBER)

    Local $btnOK = GUICtrlCreateButton("OK", 40, 100, 80, 30)
    GUICtrlSetState(-1, $GUI_DEFBUTTON)
    Local $btnCancel = GUICtrlCreateButton("Cancel", 140, 100, 80, 30)

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
                _ReportStatus("Jumped to " & $iMin & " minutes " & $iSec & " seconds")
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
    Else
        HotKeySet("^{TAB}")
        HotKeySet("^+{TAB}")
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
    Local $hLoad = GUICreate("Loading", 300, 80, -1, -1, $WS_POPUP, BitOR($WS_EX_TOPMOST, $WS_EX_TOOLWINDOW))
    GUISetBkColor(0xFFFFFF)
    GUICtrlCreateLabel("Loading playlist: " & $sPlaylistTitle & "...", 10, 25, 280, 40, $SS_CENTER)
    GUISetState(@SW_SHOW, $hLoad)
    DllCall("winmm.dll", "int", "PlaySoundW", "wstr", @ScriptDir & "\sounds\loading.wav", "ptr", 0, "dword", 0x0009)

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
    SoundPlay(@ScriptDir & "\sounds\ok.wav")

    Local $aLines = StringSplit(StringStripCR($sOutput), @LF)
    If $aLines[0] <= 1 And $sOutput == "" Then
        Local $sShowErr = "Could not load videos from this playlist."
        If $sErr <> "" Then $sShowErr &= " Details: " & StringLeft(StringStripWS($sErr, 3), 100)
        MsgBox(16, "Error", $sShowErr)
        Return
    EndIf

    ; 3. Tạo GUI danh sách video
    Local $hPlGui = GUICreate("Playlist Videos: " & $sPlaylistTitle, 400, 460)
    GUISetBkColor($COLOR_BLUE)
    GUICtrlCreateLabel("Videos in this playlist:", 10, 10, 380, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    GUICtrlSetFont(-1, 10, 800)
    Local $lst_pl = GUICtrlCreateList("", 10, 35, 380, 355, BitOR($LBS_NOTIFY, $WS_VSCROLL, $WS_BORDER))
    Local $btn_back = GUICtrlCreateButton("Close Playlist", 10, 400, 380, 30)

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
            Local $sDisp = $iPlCount & ". " & ($sCurrentT <> "" And $sCurrentT <> "NA" ? $sCurrentT : "Unknown Title")
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
        MsgBox(16, "Error", "No videos found in this playlist.")
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

    While 1
        Local $nMsg = GUIGetMsg()
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

Func _ShowChannelVideos($sChannelID, $sChannelTitle)
    ; 1. Hiển thị hộp thoại Loading video
    Local $hLoad = GUICreate("Loading", 300, 80, -1, -1, $WS_POPUP, BitOR($WS_EX_TOPMOST, $WS_EX_TOOLWINDOW))
    GUISetBkColor(0xFFFFFF)
    GUICtrlCreateLabel("Loading all videos from: " & $sChannelTitle & "...", 10, 25, 280, 40, $SS_CENTER)
    GUISetState(@SW_SHOW, $hLoad)
    DllCall("winmm.dll", "int", "PlaySoundW", "wstr", @ScriptDir & "\sounds\loading.wav", "ptr", 0, "dword", 0x0009)

    ; 2. Tải danh sách video bằng yt-dlp từ tab videos của channel
    Local $sUrl = "https://www.youtube.com/channel/" & $sChannelID & "/videos"
    If StringLeft($sChannelID, 1) = "@" Then $sUrl = "https://www.youtube.com/" & $sChannelID & "/videos"

    Local $sParams = '--flat-playlist --print "T:%(title)s" --print "D:%(duration_string)s" --print "I:%(id)s" --no-warnings --encoding utf-8 -- "' & $sUrl & '"'
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
    SoundPlay(@ScriptDir & "\sounds\ok.wav")

    Local $aLines = StringSplit(StringStripCR($sOutput), @LF)
    If $aLines[0] <= 1 And $sOutput == "" Then
        MsgBox(16, "Error", "Could not load videos from this channel.")
        Return
    EndIf

    ; 3. Tạo GUI danh sách video
    Local $hChGui = GUICreate("Channel Videos: " & $sChannelTitle, 400, 460)
    GUISetBkColor($COLOR_BLUE)
    GUICtrlCreateLabel("Videos from this channel:", 10, 10, 380, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    GUICtrlSetFont(-1, 10, 800)
    Local $lst_ch = GUICtrlCreateList("", 10, 35, 380, 355, BitOR($LBS_NOTIFY, $WS_VSCROLL, $WS_BORDER))
    Local $btn_back = GUICtrlCreateButton("Close", 10, 400, 380, 30)

    Local $aChIds[1], $aChTitles[1], $aChTypes[1]
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
            Local $sDisp = $iChCount & ". " & ($sCurrentT <> "" And $sCurrentT <> "NA" ? $sCurrentT : "Unknown Title")
            If $sCurrentD <> "" And $sCurrentD <> "NA" Then $sDisp &= " [" & $sCurrentD & "]"
            _GUICtrlListBox_AddString($lst_ch, $sDisp)

            ReDim $aChIds[$iChCount + 1]
            ReDim $aChTitles[$iChCount + 1]
            ReDim $aChTypes[$iChCount + 1]

            $aChIds[$iChCount] = $sCurrentI
            $aChTitles[$iChCount] = $sCurrentT
            $aChTypes[$iChCount] = "video"
            $sCurrentI = "" ; Reset for next entry
        EndIf
    Next

    If $iChCount == 0 Then
        MsgBox(16, "Error", "No videos found in this channel.")
        GUIDelete($hChGui)
        Return
    EndIf

    _GUICtrlListBox_SetCurSel($lst_ch, 0)
    GUISetState(@SW_SHOW, $hChGui)
    ControlFocus($hChGui, "", $lst_ch)

    Local $hDummyEnterCh = GUICtrlCreateDummy()
    Local $hDummyAudioCh = GUICtrlCreateDummy()
    Local $aAccelCh[2][2] = [["{ENTER}", $hDummyEnterCh], ["^{ENTER}", $hDummyAudioCh]]
    GUISetAccelerators($aAccelCh, $hChGui)

    While 1
        Local $nMsg = GUIGetMsg()
        Switch $nMsg
            Case $GUI_EVENT_CLOSE, $btn_back
                GUIDelete($hChGui)
                Return
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
    GUISetState(@SW_HIDE, $mainform)
    Local $hColGui = GUICreate("Your Collections", 400, 530)
    GUISetBkColor($COLOR_BLUE)

    GUICtrlCreateLabel("Your Collections:", 10, 10, 380, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    GUICtrlSetFont(-1, 10, 800)

    Local $lst_col = GUICtrlCreateList("", 10, 35, 380, 350, BitOR($LBS_NOTIFY, $WS_VSCROLL, $WS_BORDER))
    
    Local $btn_create = GUICtrlCreateButton("&Create New Collection", 10, 395, 185, 35)
    Local $btn_rename = GUICtrlCreateButton("&Rename", 205, 395, 185, 35)
    Local $btn_delete = GUICtrlCreateButton("&Delete", 10, 440, 185, 35)
    Local $btn_download = GUICtrlCreateButton("&Download Collection", 205, 440, 185, 35)
    Local $btn_shuffle = GUICtrlCreateButton("&Play Shuffle", 10, 485, 185, 35)
    Local $btn_close = GUICtrlCreateButton("&Close", 205, 485, 185, 35)

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
                Local $sName = InputBox("New Collection", "Enter name for the new collection:", "", "", 300, 130, -1, -1, 0, $hColGui)
                If Not @error And $sName <> "" Then
                    Local $sFile = $COLLECTIONS_DIR & "\" & $sName & ".col"
                    If FileExists($sFile) Then
                        MsgBox(48, "Warning", "A collection with this name already exists.")
                    Else
                        Local $hFile = FileOpen($sFile, 2 + 256)
                        FileClose($hFile)
                        _LoadCollectionsList($lst_col, $sName)
                        _NVDA_Speak("Collection " & $sName & " created")
                    EndIf
                EndIf

            Case $btn_rename
                Local $iSel = _GUICtrlListBox_GetCurSel($lst_col)
                If $iSel = -1 Then
                    MsgBox(48, "Warning", "Please select a collection from the list to rename.")
                    ContinueLoop
                EndIf
                Local $sOldNameWithCount = _GUICtrlListBox_GetText($lst_col, $iSel)
                Local $sOldName = StringRegExpReplace($sOldNameWithCount, " \(\d+ videos?\)$", "")
                Local $sNewName = InputBox("Rename Collection", "Enter new name for '" & $sOldName & "':", $sOldName, "", 300, 130, -1, -1, 0, $hColGui)
                If Not @error And $sNewName <> "" And $sNewName <> $sOldName Then
                    If FileMove($COLLECTIONS_DIR & "\" & $sOldName & ".col", $COLLECTIONS_DIR & "\" & $sNewName & ".col", 1) Then
                        _LoadCollectionsList($lst_col, $sNewName)
                        _NVDA_Speak("Collection renamed to " & $sNewName)
                    Else
                        MsgBox(16, "Error", "Could not rename collection. Ensure the name is valid.")
                    EndIf
                EndIf

            Case $btn_delete
                Local $iSel = _GUICtrlListBox_GetCurSel($lst_col)
                If $iSel = -1 Then
                    MsgBox(48, "Warning", "Please select a collection from the list to delete.")
                    ContinueLoop
                EndIf
                Local $sNameWithCount = _GUICtrlListBox_GetText($lst_col, $iSel)
                Local $sName = StringRegExpReplace($sNameWithCount, " \(\d+ videos?\)$", "")
                If MsgBox(36, "Confirm Delete", "Are you sure you want to delete the collection '" & $sName & "'?") = 6 Then
                    FileDelete($COLLECTIONS_DIR & "\" & $sName & ".col")
                    _LoadCollectionsList($lst_col)
                    _NVDA_Speak("Collection " & $sName & " deleted")
                EndIf

            Case $btn_download
                Local $iSel = _GUICtrlListBox_GetCurSel($lst_col)
                If $iSel = -1 Then
                    MsgBox(48, "Warning", "Please select a collection from the list to download.")
                    ContinueLoop
                EndIf
                Local $sNameWithCount = _GUICtrlListBox_GetText($lst_col, $iSel)
                Local $sName = StringRegExpReplace($sNameWithCount, " \(\d+ videos?\)$", "")
                _DownloadCollection($sName)

            Case $btn_shuffle
                Local $iSel = _GUICtrlListBox_GetCurSel($lst_col)
                If $iSel = -1 Then
                    MsgBox(48, "Warning", "Please select a collection from the list to shuffle.")
                    ContinueLoop
                EndIf
                Local $sNameWithCount = _GUICtrlListBox_GetText($lst_col, $iSel)
                Local $sName = StringRegExpReplace($sNameWithCount, " \(\d+ videos?\)$", "")
                _PlayShuffleCollection($sName)

            Case $hDummyEnterCol
                ; Standard Enter on list behavior
                Local $iSel = _GUICtrlListBox_GetCurSel($lst_col)
                If $iSel = -1 Then
                    MsgBox(48, "Warning", "Please select a collection from the list to open.")
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
    If Not FileExists($sFile) Then Return 0
    Local $hFile = FileOpen($sFile, 0 + 256)
    If $hFile = -1 Then Return 0
    Local $iCount = 0
    While 1
        Local $sLine = FileReadLine($hFile)
        If @error = -1 Then ExitLoop
        If StringInStr($sLine, "|") Then $iCount += 1
    WEnd
    FileClose($hFile)
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
    Local $hColItemsGui = GUICreate("Collection: " & $sColName, 400, 480)
    GUISetBkColor($COLOR_BLUE)

    GUICtrlCreateLabel("Videos in this collection:", 10, 10, 380, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    GUICtrlSetFont(-1, 10, 800)
    Local $lst_items = GUICtrlCreateList("", 10, 35, 380, 355, BitOR($LBS_NOTIFY, $WS_VSCROLL, $WS_BORDER))
    Local $btn_back = GUICtrlCreateButton("&Go Back", 10, 400, 380, 35)

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

    While 1
        Local $nMsg = GUIGetMsg()
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

    _GUICtrlMenu_AddMenuItem($hMenu, "Play...", 1001)
    _GUICtrlMenu_AddMenuItem($hMenu, "Play as &audio...", 1002)
    _GUICtrlMenu_AddMenuItem($hMenu, "Download...", 1003)
    _GUICtrlMenu_AddMenuItem($hMenu, "Go to channel...", 1004)
    _GUICtrlMenu_AddMenuItem($hMenu, "Open in Browser...", 1005)
    _GUICtrlMenu_AddMenuItem($hMenu, "Copy &Link...", 1006)
    
    _GUICtrlMenu_AddMenuItem($hMenu, "Remove from Collection", 2001)

    Local $hSubMenu_Share = _GUICtrlMenu_CreatePopup()
    _GUICtrlMenu_AddMenuItem($hSubMenu_Share, "&Telegram", 1011)
    _GUICtrlMenu_AddMenuItem($hSubMenu_Share, "&Facebook", 1012)
    _GUICtrlMenu_AddMenuItem($hMenu, "&Share", -1, $hSubMenu_Share)

    Local $bIsAlreadyFav = _IsFavorite($sID)
    _GUICtrlMenu_AddMenuItem($hMenu, _Ternary($bIsAlreadyFav, "Remove from Favorite...", "Add to &Favorite..."), 1007)

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
            _ShowDownloadDialog($sID, $sTitle)
        Case 1004
            _Action_GoChannel($iSel)
        Case 1005
            _Action_OpenBrowser($iSel)
        Case 1006
            _Action_CopyLink($iSel)
        Case 1007
            If $bIsAlreadyFav Then
                If _RemoveFavorite($sID) Then MsgBox(64, "Success", "Removed from favorites successfully!")
            Else
                _AddFavorite($sID, $sTitle)
            EndIf
        Case 1011 ; Telegram
            ShellExecute("https://t.me/share/url?url=" & _URLEncode("https://www.youtube.com/watch?v=" & $sID) & "&text=" & _URLEncode($sTitle))
        Case 1012 ; Facebook
            ShellExecute("https://www.facebook.com/sharer/sharer.php?u=" & _URLEncode("https://www.youtube.com/watch?v=" & $sID))
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
        _GUICtrlListBox_AddString($hList, "(Collection is empty)")
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
            _ArrayAdd($aLinks, "https://www.youtube.com/watch?v=" & $aParts[1])
        EndIf
    WEnd
    FileClose($hFile)
    
    If UBound($aLinks) <= 1 Then
        MsgBox(48, "Info", "Collection is empty.")
        Return
    EndIf

    ; --- Show Format Selection Dialog ---
    Local $hDLGui = GUICreate("Download Collection: " & $sColName, 400, 200, -1, -1, BitOR($WS_CAPTION, $WS_SYSMENU), $WS_EX_TOPMOST)
    GUISetBkColor($COLOR_BLUE)

    GUICtrlCreateLabel("Select Format for entire collection:", 10, 20, 380, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $cboFormat = GUICtrlCreateCombo("", 10, 45, 180, 20, $CBS_DROPDOWNLIST)
    GUICtrlSetTip(-1, "Chọn định dạng tải xuống, dùng phím mũi tên để duyệt danh sách theo thứ tự bảng chữ cái")
    GUICtrlSetData(-1, "M4A (Audio)|MP3 (Audio)|MP4 (Video, Best)|OGG (Audio)|WAV (Audio)|WebM (Video)", "MP4 (Video, Best)")

    GUICtrlCreateLabel("Select Bitrate:", 210, 20, 180, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $cboBitrate = GUICtrlCreateCombo("", 210, 45, 180, 20, $CBS_DROPDOWNLIST)
    GUICtrlSetTip(-1, "Chọn tốc độ bit (kbps), dùng phím mũi tên để duyệt từ thấp đến cao")
    GUICtrlSetData(-1, "128 kbps|192 kbps|256 kbps|320 kbps", "320 kbps")

    Local $btn_Start = GUICtrlCreateButton("Start Download", 10, 100, 380, 40)
    GUICtrlSetState(-1, $GUI_DEFBUTTON)
    Local $btn_Cancel = GUICtrlCreateButton("Cancel", 10, 150, 380, 30)

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
            $sSelectedFmt = GUICtrlRead($cboFormat)
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
    Local $hProgGui = GUICreate("Downloading Collection: " & $sColName, 400, 140, -1, -1, BitOR($WS_CAPTION, $WS_SYSMENU), $WS_EX_TOPMOST)
    GUISetBkColor($COLOR_BLUE)
    Local $lbl_coll_item = GUICtrlCreateLabel("", 10, 15, 380, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $lbl_coll_status = GUICtrlCreateLabel("", 10, 45, 380, 16)
    GUICtrlSetColor(-1, 0xFFFFFF)
    Local $prog_coll = GUICtrlCreateProgress(10, 65, 380, 20)
    GUISetState(@SW_SHOW, $hProgGui)

    For $i = 1 To $iTotalItems
        _NVDA_Speak("Downloading item " & $i & " of " & $iTotalItems)
        GUICtrlSetData($lbl_coll_item, "Đang tải mục " & $i & " / " & $iTotalItems)
        Local $sCmd = $YT_DLP_EXE & ' ' & $sFmt & ' -P "' & $sFinalDownloadPath & '" --ffmpeg-location "' & @ScriptDir & '\lib" -o "%(title)s.%(ext)s" -- "' & $aLinks[$i] & '"'
        Local $bCollDone = _RunDownloadWithProgress($sCmd, $prog_coll, $lbl_coll_status)
        If Not $bCollDone Then
            GUIDelete($hProgGui)
            Return
        EndIf
    Next
    GUIDelete($hProgGui)
SoundPlay(@ScriptDir & "\sounds\download_finish.wav")
    MsgBox(64, "Success", "Collection download complete!")
EndFunc

Func _AddtoCollection($sID, $sTitle)
    Local $hSelectCol = GUICreate("Select Collection", 300, 350, -1, -1, BitOR($WS_CAPTION, $WS_POPUP, $WS_SYSMENU))
    GUISetBkColor($COLOR_BLUE)
    GUICtrlCreateLabel("Choose a collection:", 10, 10, 280, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    GUICtrlSetFont(-1, 10, 800)
    Local $lst = GUICtrlCreateList("", 10, 35, 280, 255, BitOR($LBS_NOTIFY, $WS_VSCROLL, $WS_BORDER))
    Local $btn_add = GUICtrlCreateButton("&Add to Collection", 10, 300, 280, 35)
    
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
                    MsgBox(48, "Info", "This video is already in the collection.")
                Else
                    Local $hFileWrite = FileOpen($sFile, 1 + 256)
                    If $hFileWrite <> -1 Then
                        FileWriteLine($hFileWrite, $sID & "|" & $sTitle)
                        FileClose($hFileWrite)
                        _NVDA_Speak("Added to collection " & $sColName)
                        MsgBox(64, "Success", "Added to collection successfully!")
                    Else
                        MsgBox(16, "Error", "Could not open collection file for writing.")
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
        MsgBox(64, "Info", "This video is not in any collection.")
        Return
    EndIf

    Local $hRemGui = GUICreate("Remove From Collection", 300, 350, -1, -1, BitOR($WS_CAPTION, $WS_SYSMENU), $WS_EX_TOPMOST)
    GUISetBkColor($COLOR_BLUE)
    GUICtrlCreateLabel("Remove from collection:", 10, 10, 280, 20)
    GUICtrlSetColor(-1, 0xFFFFFF)
    GUICtrlSetFont(-1, 10, 800)
    Local $lst = GUICtrlCreateList("", 10, 35, 280, 255, BitOR($LBS_NOTIFY, $WS_VSCROLL, $WS_BORDER))
    For $i = 1 To UBound($aFoundCols) - 1
        _GUICtrlListBox_AddString($lst, $aFoundCols[$i])
    Next
    _GUICtrlListBox_SetCurSel($lst, 0)
    Local $btn_rem = GUICtrlCreateButton("Remove", 10, 300, 280, 35)
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
                _NVDA_Speak("Removed from collection " & $sName)
                MsgBox(64, "Success", "Removed from collection successfully!")
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
        MsgBox(48, "Warning", "Collection must have at least 2 videos to shuffle.")
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
    _GUICtrlMenu_AddMenuItem($hMenu, "Play shuffle", 3001)
    
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

Func contribute()
    Local $congui = GuiCreate("contribute", 700, 700)
    GuiSetBkColor($COLOR_RED)
    Local $txtContribute = FileExists(@ScriptDir & "\docs\contribute.txt") ? FileRead(@ScriptDir & "\docs\contribute.txt") : "VDH Media Center"
    Local $sContent = _StripMarkdown($txtContribute)
    Local $conedit = GUICtrlCreateEdit($sContent, 20, 20, 650, 600, BitOR($ES_AUTOVSCROLL, $ES_READONLY, $WS_VSCROLL, $WS_TABSTOP))
    Local $btnClose = GUICtrlCreateButton("&Close", 300, 630, 100, 30, $WS_TABSTOP)
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
