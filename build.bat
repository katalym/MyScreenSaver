@echo off
rem Builds MyScreenSaver.exe and MyScreenSaver.scr (Delphi 13, Win64) in this folder
setlocal
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
pushd "%~dp0"
set OUT=%TEMP%\MyScreenSaver_win64
if not exist "%OUT%" mkdir "%OUT%"
dcc64 -B -Q -W -H -CG -E"%OUT%" -N0"%OUT%" -U"%BDS%\lib\win64\release" -NSSystem;Winapi;Vcl;Vcl.Imaging;Data;System.Win MyScreenSaver.dpr
set ERR=%ERRORLEVEL%
if %ERR% neq 0 (popd & exit /b %ERR%)
copy /y "%OUT%\MyScreenSaver.exe" MyScreenSaver.exe >nul
copy /y "%OUT%\MyScreenSaver.exe" MyScreenSaver.scr >nul
popd
echo Built MyScreenSaver.exe and MyScreenSaver.scr (Win64)