; Copyright (c) Konode. All rights reserved.
; This source code is subject to the terms of the Mozilla Public License, v. 2.0 
; that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

; konote bootstrap
; copies remote nw locally for faster execution

; local and remote paths
localDir = %A_AppData%\konote
remoteDir = K:\

; compare local and remote version from package.json to determine if local update is necessary
localPackage = %localDir%\package_.json
remotePackage = %remoteDir%\package.json

Loop, read, %localPackage%
{
	IfInString, A_LoopReadLine, version
		localVersion := A_LoopReadLine
}

Loop, read, %remotePackage%
{
	IfInString, A_LoopReadLine, version
		remoteVersion := A_LoopReadLine
}

if(remoteVersion = localVersion)
{
	Run, %localDir%\konote.exe %remoteDir%
	ExitApp
} else {
	; show loading dialog
	Gui, +AlwaysOnTop +Disabled -SysMenu +Owner  ; +Owner avoids a taskbar instance.
	Gui, Add, Text,, Optimizing KoNote for first time use... Please wait.
	Gui, Show, NoActivate, KoNote  ; NoActivate avoids deactivating the currently active window.
	
	; copy files locally and run. FileCopy(remote file, local file, overwrite)
	FileCreateDir, %localDir%
	
	ErrorCount := 0
	
	; need to rename package.json otherwise local nw ignores our remote directory
	FileCopy, %remoteDir%\package.json, %localDir%\package_.json, 1
	ErrorCount += ErrorLevel
	FileCopy, %remoteDir%\konote.exe, %localDir%, 1
	ErrorCount += ErrorLevel
	FileCopy, %remoteDir%\nw.pak, %localDir%, 1
	ErrorCount += ErrorLevel
	FileCopy, %remoteDir%\libEGL.dll, %localDir%, 1
	ErrorCount += ErrorLevel
	FileCopy, %remoteDir%\libGLESv2.dll, %localDir%, 1
	ErrorCount += ErrorLevel
	FileCopy, %remoteDir%\icudtl.dat, %localDir%, 1
	ErrorCount += ErrorLevel
	FileCopy, %remoteDir%\ffmpegsumo.dll, %localDir%, 1
	ErrorCount += ErrorLevel
	FileCopy, %remoteDir%\pdf.dll, %localDir%, 1
	ErrorCount += ErrorLevel
	
	if (ErrorCount != 0) {
		; error copying locally; fall back to run remotely
		MsgBox Error copying %ErrorCount% files to local cache: Please wait...
		Run, %remoteDir%\konote.exe
		ExitApp
	} else {
		Run, %localDir%\konote.exe %remoteDir%
		ExitApp
	}
}
