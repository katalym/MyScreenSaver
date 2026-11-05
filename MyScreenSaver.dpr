program MyScreenSaver;

{ Windows screensaver (.scr) and standalone media viewer.
  Command line:  /s  - run as screensaver
                 /c  - settings dialog
                 /p  - preview (not supported, exits)
                 (none) - standalone viewer }

uses
  Winapi.Windows,
  System.SysUtils,
  Vcl.Forms,
  uExif in 'uExif.pas',
  uLang in 'uLang.pas',
  uConfig in 'uConfig.pas',
  uLocation in 'uLocation.pas',
  uMedia in 'uMedia.pas',
  uRules in 'uRules.pas',
  uShare in 'uShare.pas',
  uSettingsForm in 'uSettingsForm.pas',
  uViewer in 'uViewer.pas',
  uPreview in 'uPreview.pas',
  WMPLib in 'WMPLib.pas';

var
  vArg: string;
  vHandle: Int64;
  ViewerForm: TViewerForm;

begin
  vArg := LowerCase(Copy(ParamStr(1), 1, 2));
  Settings;   // load the settings (and the language) before any UI text is created
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Title := 'MyScreenSaver';
  if (vArg = '/c') or (vArg = '-c') then
  begin
    ShowSettingsDialog;
    Exit;
  end;
  if (vArg = '/p') or (vArg = '-p') then
  begin
    // "/p <hwnd>" or "/p:<hwnd>"
    vHandle := StrToInt64Def(Trim(Copy(ParamStr(1), 4, MaxInt)), 0);
    if vHandle = 0 then
      vHandle := StrToInt64Def(ParamStr(2), 0);
    RunPreview(HWND(vHandle));
    Exit;
  end;
  if (vArg = '/s') or (vArg = '-s') then
    GViewerMode := vmScreenSaver
  else
    GViewerMode := vmStandalone;
  CleanCache;
  Application.CreateForm(TViewerForm, ViewerForm);
  Application.Run;
end.
