@echo off
rem Builds MyScreenSaver.exe and MyScreenSaver.scr (Delphi 13, Win64) in this folder
setlocal
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
pushd "%~dp0"
set OUT=%TEMP%\MyScreenSaver_win64
rem the version resource: MyScreenSaverVersion.rc -> MyScreenSaverVersion.res (the .res is committed too,
rem so the Delphi IDE can build without a resource compiler)
brcc32 -fo MyScreenSaverVersion.res MyScreenSaverVersion.rc
if errorlevel 1 (popd & exit /b 1)
if not exist "%OUT%" mkdir "%OUT%"
rem MyScreenSaver.res (main icon, manifest) is generated from the dproj; dcc64 alone never refreshes it, so the
rem stale one is deleted and msbuild makes a new one and builds the exe
del MyScreenSaver.res 2>nul
msbuild MyScreenSaver.dproj /t:Build /p:Config=Release /p:Platform=Win64 /p:DCC_ExeOutput="%OUT%" /p:DCC_DcuOutput="%OUT%" /v:m /nologo
set ERR=%ERRORLEVEL%
if %ERR% neq 0 (popd & exit /b %ERR%)
copy /y "%OUT%\MyScreenSaver.exe" MyScreenSaver.exe >nul
copy /y "%OUT%\MyScreenSaver.exe" MyScreenSaver.scr >nul
popd
echo Built MyScreenSaver.exe and MyScreenSaver.scr (Win64)