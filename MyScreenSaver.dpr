program MyScreenSaver;

{ Windows screensaver (.scr) and standalone media viewer.
  Command line:  /s  - run as screensaver
                 /c  - settings dialog
                 /p <hwnd> - preview in the small window of the settings dialog (one random photo)
                 (none) - standalone viewer }

uses
  Winapi.Windows,
  System.SysUtils,
  Vcl.Forms,
  MyScreenSaver_Exif in 'MyScreenSaver_Exif.pas',
  MyScreenSaver_Version in 'MyScreenSaver_Version.pas',
  MyScreenSaver_Lang in 'MyScreenSaver_Lang.pas',
  MyScreenSaver_Config in 'MyScreenSaver_Config.pas',
  MyScreenSaver_Location in 'MyScreenSaver_Location.pas',
  MyScreenSaver_Media in 'MyScreenSaver_Media.pas',
  MyScreenSaver_Rules in 'MyScreenSaver_Rules.pas',
  MyScreenSaver_Share in 'MyScreenSaver_Share.pas',
  MyScreenSaver_ShareDialog in 'MyScreenSaver_ShareDialog.pas' {ShareForm},
  MyScreenSaver_ShareIcons in 'MyScreenSaver_ShareIcons.pas',
  MyScreenSaver_InfoFields in 'MyScreenSaver_InfoFields.pas',
  MyScreenSaver_SettingsForm in 'MyScreenSaver_SettingsForm.pas' {SettingsForm},
  MyScreenSaver_InfoDialog in 'MyScreenSaver_InfoDialog.pas' {InfoForm},
  MyScreenSaver_Overlay in 'MyScreenSaver_Overlay.pas' {OverlayWindow},
  MyScreenSaver_SlideView in 'MyScreenSaver_SlideView.pas',
  MyScreenSaver_Viewer in 'MyScreenSaver_Viewer.pas' {ViewerForm},
  MyScreenSaver_Preview in 'MyScreenSaver_Preview.pas' {PreviewForm},
  WMPLib in 'WMPLib.pas';

{$R 'MyScreenSaverVersion.res' 'MyScreenSaverVersion.rc'}   // version resource, built from MyScreenSaverVersion.rc
{$R *.res}

var
  vArg: string;
  vHandle: Int64;
  vWnd: HWND;
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
  // Only one viewer / screensaver at a time (the settings dialog and the preview may run next to it). The
  // mutex lives as long as the process: Windows starts the screensaver while the viewer is open -> it just ends.
  CreateMutex(nil, False, 'Local\MyScreenSaver_Viewer');
  if GetLastError = ERROR_ALREADY_EXISTS then
  begin
    if GViewerMode = vmStandalone then
    begin
      vWnd := FindWindow('TViewerForm', nil);   // a second start of the viewer shows the first one
      if vWnd <> 0 then
      begin
        if IsIconic(vWnd) then
          ShowWindow(vWnd, SW_RESTORE);
        SetForegroundWindow(vWnd);
      end;
    end;
    Exit;
  end;
  CleanCache;
  Application.CreateForm(TViewerForm, ViewerForm);
  Application.Run;
end.
