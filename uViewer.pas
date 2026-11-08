unit uViewer;

{ Full-screen / windowed media viewer. Built in code (no .dfm). }

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, System.Generics.Collections,
  Vcl.Controls, Vcl.Forms, Vcl.Clipbrd, Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.Graphics, Vcl.Menus, Vcl.Imaging.pngimage,
  WMPLib, uConfig, uMedia, uSlideView;

type
  TViewerMode = (vmStandalone, vmScreenSaver);

  TViewerForm = class(TForm)
  private
    FMode: TViewerMode;
    FCatalog: TMediaCatalog;
    FScan: TScanThread;
    FQuick: TQuickSampler;
    FIndexer: TMetaIndexer;
    FHistory: TList<TMediaItem>;
    FHistPos: Integer;
    FView: TSlideView;           // the photo with transitions
    FUserNav: Boolean;           // the move was made by the user (arrow keys): short transition
    FGoingBack: Boolean;         // the user goes to the previous slide
    FPendingVideo: string;       // a video waits until the photo has faded to black
    FWaitingOpen: Boolean;       // a video is opened and its size is checked before it plays
    FSkips: Integer;             // videos skipped in a row because they are too large
    FVideoHost: TPanel;
    FPlayer: TWindowsMediaPlayer;
    FStatus: TLabel;
    FInfoPanel: TPanel;      // gray frame
    FInfoInner: TPanel;      // dark background of the text
    FInfoText: TMemo;        // read-only: text can be selected and copied
    FTimer: TTimer;
    FPaused: Boolean;
    FInfoShown: Boolean;
    FBusy: Boolean;
    FFailures: Integer;
    FCurrentPath: string;
    FCurrentItem: TMediaItem;
    FHasCurrent: Boolean;
    FStartPt: TPoint;
    FBlankForms: TList<TForm>;
    procedure StartScan;
    procedure StopScan;
    procedure AppMessage(var Msg: TMsg; var Handled: Boolean);
    function HandleKey(AKey: Word; ARepeat: Boolean): Boolean;
    procedure TimerTick(Sender: TObject);
    procedure PlayerStateChange(ASender: TObject; ANewState: Integer);
    procedure CheckVideoSize;
    procedure FitVideo;
    procedure PlayerError(Sender: TObject);
    procedure GoNext;
    procedure GoPrev;
    procedure ShowCurrent;
    procedure ShowPhoto(const APath: string; const AItem: TMediaItem);
    procedure ShowVideo(const APath: string);
    procedure StartVideo(const APath: string);
    procedure VideoFadedOut(Sender: TObject);
    function TransitionLength: Integer;
    procedure ShowMessage(const AText: string);
    procedure ArmTimer;
    procedure TogglePause;
    procedure ToggleInfo;
    procedure HideInfo;
    procedure ShowInfoPanel(const AText: string);
    procedure InfoDblClick(Sender: TObject);
    function BuildInfo: string;
    procedure DoShare;
    procedure ShareClick(Sender: TObject);
    procedure OpenSettings;
    procedure CreateBlankForms;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure DoShow; override;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  GViewerMode: TViewerMode = vmStandalone;

{ Loads a photo into a TPicture applying the EXIF orientation. }
procedure LoadPhotoPicture(APicture: TPicture; const APath: string);

implementation

uses
  System.IOUtils, System.DateUtils, System.StrUtils, System.Math, Vcl.Imaging.jpeg, Vcl.Imaging.GIFImg,
  Winapi.Wincodec, uVersion, uLang, uInfoFields, uLocation, uRules, uExif, uShare, uSettingsForm;

const
  HistoryLimit = 100000;
  MaxFailures = 25;

procedure LoadOrientedPicture(APicture: TPicture; const APath: string; AOrientation: Integer);
var
  vWic: TWICImage;
  vFactory: IWICImagingFactory;
  vRot: IWICBitmapFlipRotator;
  vBmp: IWICBitmap;
  vOpt: WICBitmapTransformOptions;
begin
  vWic := TWICImage.Create;
  try
    vWic.LoadFromFile(APath);
    case AOrientation of
      3: vOpt := WICBitmapTransformRotate180;
      6: vOpt := WICBitmapTransformRotate90;
      8: vOpt := WICBitmapTransformRotate270;
    else
      vOpt := WICBitmapTransformRotate0;
    end;
    if vOpt <> WICBitmapTransformRotate0 then
    begin
      vFactory := vWic.ImagingFactory;
      vFactory.CreateBitmapFlipRotator(vRot);
      vRot.Initialize(vWic.Handle, vOpt);
      vFactory.CreateBitmapFromSource(vRot, WICBitmapCacheOnLoad, vBmp);
      vWic.Handle := vBmp;
    end;
    APicture.Assign(vWic);
  finally
    vWic.Free;
  end;
end;

procedure LoadPhotoPicture(APicture: TPicture; const APath: string);
var
  vOrient: Integer;
begin
  vOrient := 0;
  if MatchText(LowerCase(ExtractFileExt(APath)), ['.jpg', '.jpeg', '.jfif']) then
    vOrient := ReadExif(APath).Orientation;
  LoadOrientedPicture(APicture, APath, vOrient);
end;

{ TViewerForm }

constructor TViewerForm.Create(AOwner: TComponent);
begin
  CreateNew(AOwner);
  FMode := GViewerMode;
  FHistory := TList<TMediaItem>.Create;
  FHistPos := -1;
  FBlankForms := TList<TForm>.Create;
  Color := clBlack;
  KeyPreview := True;
  Caption := Trim('MyScreenSaver ' + AppVersion);

  if FMode = vmScreenSaver then
  begin
    BorderStyle := bsNone;
    FormStyle := fsStayOnTop;
    Position := poDesigned;
    BoundsRect := Screen.PrimaryMonitor.BoundsRect;
    Screen.Cursor := crNone;
    Cursor := crNone;
  end
  else
  begin
    BorderStyle := bsSizeable;
    Position := poScreenCenter;
    Width := 1100;
    Height := 750;
    WindowState := wsMaximized;
  end;

  FView := TSlideView.Create(Self);
  FView.Parent := Self;
  FView.Align := alClient;
  FView.OnFadedOut := VideoFadedOut;

  FVideoHost := TPanel.Create(Self);
  FVideoHost.Parent := Self;
  FVideoHost.Align := alClient;
  FVideoHost.BevelOuter := bvNone;
  FVideoHost.Color := clBlack;
  FVideoHost.ParentBackground := False;
  FVideoHost.Visible := False;

  FPlayer := TWindowsMediaPlayer.Create(Self);
  FPlayer.Parent := FVideoHost;
  FPlayer.Align := alClient;
  FPlayer.OnPlayStateChange := PlayerStateChange;
  FPlayer.OnError := PlayerError;
  FPlayer.uiMode := 'none';
  FPlayer.enableContextMenu := False;
  FPlayer.settings.autoStart := True;

  FStatus := TLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.Font.Size := 20;
  FStatus.Font.Color := clSilver;
  FStatus.Transparent := True;
  FStatus.AutoSize := True;
  FStatus.Left := 24;
  FStatus.Top := 24;
  FStatus.Visible := False;

  FInfoPanel := TPanel.Create(Self);
  FInfoPanel.Parent := Self;
  FInfoPanel.BevelOuter := bvNone;
  FInfoPanel.ParentBackground := False;
  FInfoPanel.Color := clGray;
  FInfoPanel.Visible := False;
  FInfoInner := TPanel.Create(Self);
  FInfoInner.Parent := FInfoPanel;
  FInfoInner.BevelOuter := bvNone;
  FInfoInner.ParentBackground := False;
  FInfoInner.Color := $202020;
  FInfoText := TMemo.Create(Self);
  FInfoText.Parent := FInfoInner;
  FInfoText.BorderStyle := bsNone;
  FInfoText.ReadOnly := True;
  FInfoText.ScrollBars := ssNone;
  FInfoText.Color := $202020;
  FInfoText.Font.Color := clWhite;
  FInfoText.Font.Name := 'Consolas';
  FInfoText.Font.Size := 13;
  FInfoText.Cursor := crIBeam;
  FInfoText.WordWrap := True;
  FInfoText.OnDblClick := InfoDblClick;

  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.OnTimer := TimerTick;

  Application.OnMessage := AppMessage;
  StartScan;
end;

destructor TViewerForm.Destroy;
begin
  Application.OnMessage := nil;
  // stop the background threads before the unit finalization frees their shared data
  StopScan;
  FreeAndNil(FBlankForms);
  FreeAndNil(FHistory);
  inherited;
end;

{ The standalone viewer must have its own button in the taskbar. The window handle is created while the
  form is being built, before it is the main form of the application, so VCL makes the window an owned
  one without a button: it is made a normal top-level window here. (The screensaver has no button.) }
procedure TViewerForm.CreateParams(var Params: TCreateParams);
begin
  inherited CreateParams(Params);
  if FMode = vmStandalone then
  begin
    Params.WndParent := 0;
    Params.ExStyle := Params.ExStyle or WS_EX_APPWINDOW;
  end;
end;

procedure TViewerForm.DoShow;
begin
  inherited;
  GetCursorPos(FStartPt);
  if FMode = vmScreenSaver then
    CreateBlankForms;
  if not FTimer.Enabled then
  begin
    ShowMessage(L('Загрузка списка файлов...', 'Loading the file list...'));
    FTimer.Interval := 300;
    FTimer.Enabled := True;
    FHasCurrent := False;
  end;
end;

procedure TViewerForm.CreateBlankForms;
var
  i: Integer;
  vForm: TForm;
begin
  for i := 0 to Screen.MonitorCount - 1 do
  begin
    if Screen.Monitors[i] = Screen.PrimaryMonitor then
      Continue;
    vForm := TForm.CreateNew(Self);
    vForm.BorderStyle := bsNone;
    vForm.FormStyle := fsStayOnTop;
    vForm.Color := clBlack;
    vForm.Position := poDesigned;
    vForm.BoundsRect := Screen.Monitors[i].BoundsRect;
    vForm.Cursor := crNone;
    vForm.Show;
    FBlankForms.Add(vForm);
  end;
end;

procedure TViewerForm.StartScan;
begin
  FCatalog := TMediaCatalog.Create;
  FScan := TScanThread.Create(FCatalog);
  FQuick := TQuickSampler.Create(FCatalog);
  FIndexer := TMetaIndexer.Create(FCatalog);
  StartLocationDetection;
end;

procedure TViewerForm.StopScan;
begin
  // ask all threads to stop first, then wait for them
  if FIndexer <> nil then
    FIndexer.Terminate;
  if FQuick <> nil then
    FQuick.Terminate;
  if FScan <> nil then
    FScan.Terminate;
  if FIndexer <> nil then
  begin
    FIndexer.Terminate;
    FIndexer.WaitFor;
    FreeAndNil(FIndexer);
  end;
  if FQuick <> nil then
  begin
    FQuick.Terminate;
    FQuick.WaitFor;
    FreeAndNil(FQuick);
  end;
  if FScan <> nil then
  begin
    FScan.Terminate;
    FScan.WaitFor;
    FreeAndNil(FScan);
  end;
  FreeAndNil(FCatalog);
end;

{ ---- input ---- }

procedure TViewerForm.AppMessage(var Msg: TMsg; var Handled: Boolean);
var
  vPt: TPoint;
begin
  if FBusy then
    Exit;
  if FMode = vmStandalone then
    if (Msg.hwnd <> Handle) and not IsChild(Handle, Msg.hwnd) then
      Exit;

  case Msg.message of
    WM_KEYDOWN:
      begin
        // Ctrl+A / Ctrl+C work on the info text (without a selection Ctrl+C copies everything)
        if FInfoShown and (GetKeyState(VK_CONTROL) < 0) then
        begin
          if Msg.wParam = Ord('A') then
          begin
            FInfoText.SelectAll;
            Handled := True;
            Exit;
          end;
          if (Msg.wParam = Ord('C')) or (Msg.wParam = VK_INSERT) then
          begin
            if FInfoText.SelLength > 0 then
              FInfoText.CopyToClipboard
            else
              Clipboard.AsText := FInfoText.Text;
            Handled := True;
            Exit;
          end;
        end;
        Handled := HandleKey(Word(Msg.wParam), (Msg.lParam and $40000000) <> 0);
      end;
    WM_LBUTTONDOWN, WM_RBUTTONDOWN, WM_MBUTTONDOWN:
      if (FMode = vmScreenSaver) and not FInfoShown then
        Close;
    WM_MOUSEMOVE:
      if (FMode = vmScreenSaver) and not FInfoShown then
      begin
        GetCursorPos(vPt);
        if (Abs(vPt.X - FStartPt.X) > 8) or (Abs(vPt.Y - FStartPt.Y) > 8) then
          Close;
      end;
  end;
end;

function TViewerForm.HandleKey(AKey: Word; ARepeat: Boolean): Boolean;
begin
  Result := True;
  case AKey of
    VK_ESCAPE:
      Close;
    VK_SPACE:
      if not ARepeat then
        TogglePause;
    Ord('I'):
      if not ARepeat then
        ToggleInfo;
    Ord('P'):
      if not ARepeat then
        DoShare;
    Ord('C'):
      if (FMode = vmStandalone) and not ARepeat then
        OpenSettings
      else
        Result := FMode = vmStandalone;
    VK_LEFT:
      begin
        FUserNav := True;
        FGoingBack := True;
        GoPrev;
      end;
    VK_RIGHT:
      begin
        FUserNav := True;
        GoNext;
      end;
    VK_SHIFT, VK_CONTROL, VK_MENU:
      Result := False;
  else
    if FMode = vmScreenSaver then
      Close
    else
      Result := False;
  end;
end;

{ ---- navigation ---- }

procedure TViewerForm.TimerTick(Sender: TObject);
begin
  FUserNav := False;
  FTimer.Enabled := False;
  GoNext;
end;

procedure TViewerForm.ArmTimer;
begin
  FTimer.Enabled := False;
  if FPaused or FInfoShown then
    Exit;
  FTimer.Interval := Cardinal(Max(1, Settings.SlideSeconds) * 1000);
  FTimer.Enabled := True;
end;

procedure TViewerForm.GoNext;
var
  vItem: TMediaItem;
begin
  HideInfo;
  FPaused := False;
  FStatus.Visible := False;
  if FHistPos < FHistory.Count - 1 then
  begin
    Inc(FHistPos);
    ShowCurrent;
    Exit;
  end;
  if not PickMedia(FCatalog, vItem) then
  begin
    if FCatalog.Scanning then
      ShowMessage(L('Загрузка списка файлов...', 'Loading the file list...'))
    else if Settings.Collections.Count = 0 then
      ShowMessage(L('Нет медиаколлекций. Настройте приложение (клавиша C).', 'No media collections. Configure the application (key C).'))
    else
      ShowMessage(L('Медиафайлы не найдены.', 'No media files found.'));
    FTimer.Interval := Cardinal(IfThen(FCatalog.Scanning, 200, 1500));
    FTimer.Enabled := True;
    Exit;
  end;
  FHistory.Add(vItem);
  if FHistory.Count > HistoryLimit then
    FHistory.DeleteRange(0, FHistory.Count - HistoryLimit);
  FHistPos := Integer(FHistory.Count) - 1;
  ShowCurrent;
end;

procedure TViewerForm.GoPrev;
begin
  if FHistPos <= 0 then
    Exit;
  HideInfo;
  FPaused := False;
  FStatus.Visible := False;
  Dec(FHistPos);
  ShowCurrent;
end;

procedure TViewerForm.ShowMessage(const AText: string);
begin
  FPlayer.controls.stop;
  FVideoHost.Visible := False;
  FPendingVideo := '';
  FView.Clear;
  FStatus.Caption := AText;
  FStatus.Visible := True;
  FStatus.BringToFront;
end;

procedure TViewerForm.ShowCurrent;
var
  vItem: TMediaItem;
  vPath: string;
begin
  FPendingVideo := '';
  FWaitingOpen := False;
  vItem := FHistory[FHistPos];
  FCurrentItem := vItem;
  FHasCurrent := True;
  FTimer.Enabled := False;
  FPlayer.controls.stop;
  Screen.Cursor := TCursor(IfThen(FMode = vmScreenSaver, crNone, crHourGlass));
  try
    vPath := EnsureLocalFile(vItem);
  finally
    if FMode = vmStandalone then
      Screen.Cursor := crDefault;
  end;
  FCurrentPath := vPath;
  if (vPath = '') or not FileExists(vPath) then
  begin
    Inc(FFailures);
    FHistory.Delete(FHistPos);
    Dec(FHistPos);
    FTimer.Interval := Cardinal(IfThen(FFailures > MaxFailures, 3000, 10));
    FTimer.Enabled := True;
    Exit;
  end;
  try
    if vItem.Kind = mkPhoto then
      ShowPhoto(vPath, vItem)
    else
      ShowVideo(vPath);
    FFailures := 0;
  except
    Inc(FFailures);
    FHistory.Delete(FHistPos);
    Dec(FHistPos);
    FTimer.Interval := Cardinal(IfThen(FFailures > MaxFailures, 3000, 10));
    FTimer.Enabled := True;
  end;
end;

procedure TViewerForm.ShowPhoto(const APath: string; const AItem: TMediaItem);
var
  vOrient, vMs: Integer;
  vPic: TPicture;
  vEffect: TTransitionEffect;
  vDir: TSlideDirection;
begin
  vOrient := 0;
  if MatchText(LowerCase(ExtractFileExt(APath)), ['.jpg', '.jpeg', '.jfif']) then
    vOrient := ReadExif(APath).Orientation;
  FSkips := 0;
  vMs := TransitionLength;
  vEffect := Settings.Transition;
  if vEffect = teRandom then
    vEffect := TTransitionEffect(Ord(teFade) + Random(4));   // cross-fade, black, slide or wipe
  if FGoingBack then
    vDir := sdBackward
  else
    vDir := sdForward;
  FGoingBack := False;
  vPic := TPicture.Create;
  try
    LoadOrientedPicture(vPic, APath, vOrient);
    FVideoHost.Visible := False;
    FView.Visible := True;
    FView.ShowPicture(vPic, vEffect, vMs, vDir);
  finally
    vPic.Free;
  end;
  ArmTimer;
end;

{ A transition is never longer than half of the slide; the arrow keys use a short one. }
function TViewerForm.TransitionLength: Integer;
begin
  Result := Min(Settings.TransitionMs, Settings.SlideSeconds * 500);
  if FUserNav then
    Result := Min(Result, 250);
end;

{ A photo fades to black before the video starts (the video window cannot be blended). }
procedure TViewerForm.ShowVideo(const APath: string);
begin
  if (Settings.Transition <> teNone) and FView.Visible and FView.HasPicture and not FVideoHost.Visible then
  begin
    FPendingVideo := APath;
    FView.FadeOut(TransitionLength div 2);
  end
  else
    StartVideo(APath);
end;

procedure TViewerForm.VideoFadedOut(Sender: TObject);
var
  vPath: string;
begin
  if FPendingVideo = '' then
    Exit;   // the slide was changed meanwhile
  vPath := FPendingVideo;
  FPendingVideo := '';
  StartVideo(vPath);
end;

procedure TViewerForm.StartVideo(const APath: string);
begin
  FView.Clear;
  FVideoHost.Visible := True;
  // With the size check the video starts hidden and muted; its size is known only when it plays
  // (see CheckVideoSize): a too large video is stopped and skipped, the others become visible.
  FWaitingOpen := Settings.SkipLargeVideos;
  FPlayer.Visible := not FWaitingOpen;
  FPlayer.settings.mute := FWaitingOpen or Settings.SilentVideo;
  FPlayer.settings.autoStart := True;
  FPlayer.URL := APath;
  FPlayer.controls.play;
  // the next file is chosen when playback ends; the timer is a safety net
  FTimer.Enabled := False;
  FTimer.Interval := 6 * 60 * 60 * 1000;
  FTimer.Enabled := not (FPaused or FInfoShown);
end;

{ Scales the video to the window keeping the aspect ratio (WMP shows it in its native size otherwise). }
procedure TViewerForm.FitVideo;
var
  vW, vH, vDispW, vDispH: Integer;
  vScale: Double;
begin
  if (FPlayer = nil) or (FVideoHost = nil) or not FVideoHost.Visible then
    Exit;
  if FPlayer.currentMedia = nil then
    Exit;
  vW := FPlayer.currentMedia.imageSourceWidth;
  vH := FPlayer.currentMedia.imageSourceHeight;
  if (vW <= 0) or (vH <= 0) then
    Exit;
  vScale := Min(FVideoHost.ClientWidth / vW, FVideoHost.ClientHeight / vH);
  vDispW := Max(1, Integer(Round(vW * vScale)));
  vDispH := Max(1, Integer(Round(vH * vScale)));
  FPlayer.Align := alNone;
  FPlayer.stretchToFit := True;
  FPlayer.SetBounds((FVideoHost.ClientWidth - vDispW) div 2, (FVideoHost.ClientHeight - vDispH) div 2,
    vDispW, vDispH);
end;

procedure TViewerForm.Resize;
begin
  inherited;
  FitVideo;
end;

{ The video plays (its size is known now): a video with more pixels than the screen is stopped and
  skipped, the others become visible and get their sound. }
procedure TViewerForm.CheckVideoSize;
var
  vW, vH: Integer;
begin
  if not FWaitingOpen then
    Exit;
  FWaitingOpen := False;
  if FPlayer.currentMedia <> nil then
  begin
    vW := FPlayer.currentMedia.imageSourceWidth;
    vH := FPlayer.currentMedia.imageSourceHeight;
    if (vW > 0) and (vH > 0) and (Int64(vW) * vH > Int64(Monitor.Width) * Monitor.Height) then
    begin
      FPlayer.controls.stop;
      Inc(FSkips);
      if (FHistPos >= 0) and (FHistPos < FHistory.Count) then
      begin
        FHistory.Delete(FHistPos);
        Dec(FHistPos);
      end;
      FTimer.Enabled := False;
      FTimer.Interval := Cardinal(IfThen(FSkips > MaxFailures, 3000, 20));
      FTimer.Enabled := True;
      Exit;
    end;
  end;
  FSkips := 0;
  FPlayer.settings.mute := Settings.SilentVideo;
  FPlayer.Visible := True;
  FitVideo;
end;

procedure TViewerForm.PlayerStateChange(ASender: TObject; ANewState: Integer);
begin
  // 3 = wmppsPlaying: the size of the video is known
  if ANewState = 3 then
  begin
    CheckVideoSize;
    FitVideo;
  end;
  // 8 = wmppsMediaEnded
  if (ANewState = 8) and not FPaused and not FInfoShown then
  begin
    FTimer.Enabled := False;
    FTimer.Interval := 50;
    FTimer.Enabled := True;
  end;
end;

procedure TViewerForm.PlayerError(Sender: TObject);
begin
  if FHasCurrent then
  begin
    FTimer.Enabled := False;
    FTimer.Interval := 50;
    FTimer.Enabled := True;
  end;
end;

{ ---- pause / info / share ---- }

procedure TViewerForm.TogglePause;
begin
  if FInfoShown then
  begin
    HideInfo;
    Exit;
  end;
  FPaused := not FPaused;
  if FPaused then
  begin
    FTimer.Enabled := False;
    if FCurrentItem.Kind = mkVideo then
      FPlayer.controls.pause;
    FStatus.Caption := L('Пауза', 'Paused');
    FStatus.Visible := True;
    FStatus.BringToFront;
  end
  else
  begin
    FStatus.Visible := False;
    if FCurrentItem.Kind = mkVideo then
    begin
      FPlayer.controls.play;
      FTimer.Interval := 6 * 60 * 60 * 1000;
      FTimer.Enabled := True;
    end
    else
      ArmTimer;
  end;
end;

procedure TViewerForm.ToggleInfo;
begin
  if FInfoShown then
  begin
    HideInfo;
    Exit;
  end;
  if not FHasCurrent then
    Exit;
  FInfoShown := True;
  FTimer.Enabled := False;
  if FCurrentItem.Kind = mkVideo then
    FPlayer.controls.pause;
  FStatus.Visible := False;
  ShowInfoPanel(BuildInfo);
end;

{ Double click selects the value of the clicked line (everything after the "Caption:" part). }
procedure TViewerForm.InfoDblClick(Sender: TObject);
var
  vPt: TPoint;
  vIdx, vCum, vLen, vLine, vColon, vVal, i: Integer;
  vText: string;
begin
  vPt := FInfoText.ScreenToClient(Mouse.CursorPos);
  vIdx := LoWord(FInfoText.Perform(EM_CHARFROMPOS, 0, MakeLong(Word(vPt.X), Word(vPt.Y))));
  vCum := 0;
  vLine := -1;
  for i := 0 to FInfoText.Lines.Count - 1 do
  begin
    vLen := Length(FInfoText.Lines[i]);
    if vIdx <= vCum + vLen then
    begin
      vLine := i;
      Break;
    end;
    vCum := vCum + vLen + 2;   // CRLF
  end;
  if vLine < 0 then
    Exit;
  vText := FInfoText.Lines[vLine];
  if Trim(vText) = '' then
    Exit;
  vColon := Pos(':', vText);
  vVal := 1;
  if vColon > 0 then
  begin
    vVal := vColon + 1;
    while (vVal <= Length(vText)) and (vText[vVal] = ' ') do
      Inc(vVal);
  end;
  FInfoText.SelStart := vCum + vVal - 1;
  FInfoText.SelLength := Length(TrimRight(vText)) - (vVal - 1);
end;

{ Shows the info text in a panel exactly as big as the text, centered on the screen. }
procedure TViewerForm.ShowInfoPanel(const AText: string);
const
  Pad = 28;
  Border = 2;
var
  vSl: TStringList;
  vMaxW, vCap, vHeight, vLineH, i: Integer;
  vRect: TRect;
begin
  Canvas.Font.Assign(FInfoText.Font);
  vLineH := Canvas.TextHeight('Wg');
  vSl := TStringList.Create;
  try
    vSl.Text := AText.TrimRight;
    vMaxW := 0;
    for i := 0 to vSl.Count - 1 do
      vMaxW := Max(vMaxW, Canvas.TextWidth(vSl[i]));
    vCap := ClientWidth - 2 * Pad - 80;
    vMaxW := Min(vMaxW + 6, vCap);
    // height from the text itself (long lines wrap): independent of the state of the memo window
    vHeight := 0;
    for i := 0 to vSl.Count - 1 do
    begin
      if vSl[i] = '' then
        Inc(vHeight, vLineH)
      else
      begin
        vRect := Rect(0, 0, vMaxW, 0);
        DrawText(Canvas.Handle, PChar(vSl[i]), -1, vRect,
          DT_CALCRECT or DT_WORDBREAK or DT_NOPREFIX or DT_EXPANDTABS);
        Inc(vHeight, Max(vLineH, vRect.Bottom));
      end;
    end;
  finally
    vSl.Free;
  end;
  FInfoText.Text := AText.TrimRight;
  FInfoText.SetBounds(Pad, Pad, vMaxW, vHeight + 4);
  FInfoText.HandleNeeded;
  FInfoText.Perform(EM_SETMARGINS, EC_LEFTMARGIN or EC_RIGHTMARGIN, 0);
  FInfoInner.SetBounds(Border, Border, FInfoText.Width + 2 * Pad, FInfoText.Height + 2 * Pad);
  FInfoPanel.SetBounds(0, 0, FInfoInner.Width + 2 * Border, FInfoInner.Height + 2 * Border);
  FInfoPanel.Left := (ClientWidth - FInfoPanel.Width) div 2;
  FInfoPanel.Top := (ClientHeight - FInfoPanel.Height) div 2;
  FInfoPanel.Visible := True;
  FInfoPanel.BringToFront;
  if FMode = vmScreenSaver then
    Screen.Cursor := crDefault;   // the mouse is needed to select text
  FInfoText.SelStart := 0;
  FInfoText.SelLength := 0;
  if FInfoText.CanFocus then
    FInfoText.SetFocus;
end;

procedure TViewerForm.HideInfo;
begin
  if not FInfoShown then
    Exit;
  FInfoShown := False;
  FInfoPanel.Visible := False;
  if FMode = vmScreenSaver then
  begin
    Screen.Cursor := crNone;
    GetCursorPos(FStartPt);
  end;
  if CanFocus then
    SetFocus;
  FPaused := False;
  if FCurrentItem.Kind = mkVideo then
  begin
    FPlayer.controls.play;
    FTimer.Interval := 6 * 60 * 60 * 1000;
    FTimer.Enabled := True;
  end
  else
    ArmTimer;
end;

function TViewerForm.BuildInfo: string;
var
  vSl: TStringList;
  vExif: TExifInfo;
  vSize: Int64;
  vMeta: TMediaMeta;
  vPlace: string;
  vExifHeader: Boolean;
  vTags: TArray<Integer>;
  vTexts: TArray<string>;
  vCustom: TArray<TInfoCustomTag>;
  i, vK: Integer;

  procedure AddLine(const ACaption, AValue: string);
  begin
    if AValue <> '' then
      vSl.Add(Format('%-18s %s', [ACaption + ':', AValue]));
  end;

  { a built-in field, only if it is switched on in the settings }
  procedure Add(const AId, AValue: string);
  begin
    if InfoFieldOn(AId) then
      AddLine(InfoFieldTitle(AId), AValue);
  end;

  { the same for the EXIF block; its header is printed before the first line }
  procedure AddExif(const AId, AValue: string);
  begin
    if (AValue = '') or not InfoFieldOn(AId) then
      Exit;
    if not vExifHeader then
    begin
      vSl.Add('');
      vSl.Add('--- EXIF ---');
      vExifHeader := True;
    end;
    AddLine(InfoFieldTitle(AId), AValue);
  end;

begin
  vSl := TStringList.Create;
  try
    vExifHeader := False;
    Add('file', FCurrentItem.DisplayName);
    Add('collection', FCurrentItem.Collection);
    Add('location', FCurrentItem.Location);
    if (FCurrentPath <> '') and FileExists(FCurrentPath) then
    begin
      vSize := TFile.GetSize(FCurrentPath);
      Add('size', Format('%s (%d %s)', [FormatFloat('#,##0.0', vSize / 1048576) + L(' МБ', ' MB'), vSize, L('байт', 'bytes')]));
      Add('created', DateTimeToStr(TFile.GetCreationTime(FCurrentPath)));
      Add('modified', DateTimeToStr(TFile.GetLastWriteTime(FCurrentPath)));
    end;
    if FCurrentItem.Kind = mkPhoto then
    begin
      Add('type', L('Фотография', 'Photo'));
      if FView.PictureWidth > 0 then
        Add('resolution', Format('%d x %d', [FView.PictureWidth, FView.PictureHeight]));
      vExif := ReadExif(FCurrentPath);
      if vExif.Valid then
      begin
        AddExif('make', vExif.Make);
        AddExif('camera', vExif.Model);
        AddExif('lens', vExif.Lens);
        AddExif('tagsxp', vExif.XPKeywords);
        if not SameText(vExif.Keywords, vExif.XPKeywords) then
          AddExif('tagsiptc', vExif.Keywords);
        if vExif.HasDate then
          AddExif('datetaken', DateTimeToStr(vExif.DateTaken));
        AddExif('exposure', vExif.Exposure);
        AddExif('aperture', vExif.FNumber);
        AddExif('iso', vExif.ISO);
        AddExif('focal', vExif.FocalLength);
        if vExif.HasGps then
        begin
          AddExif('gps', Format('%.6f, %.6f', [vExif.Lat, vExif.Lon], TFormatSettings.Invariant));
          if InfoFieldOn('place') then
          begin
            Screen.Cursor := crHourGlass;
            try
              vPlace := ReverseGeocode(vExif.Lat, vExif.Lon, LanguageCode(CurrentLanguage));
            finally
              Screen.Cursor := TCursor(IfThen(FMode = vmScreenSaver, crNone, crDefault));
            end;
            if vPlace = '' then
              vPlace := L('(не удалось определить — нет интернета?)', '(could not be determined — no internet?)');
            AddExif('place', vPlace);
          end;
        end;
      end;
      // own EXIF tags chosen in the settings
      vCustom := Settings.CustomTags.ToArray;
      SetLength(vTags, 0);
      for i := 0 to Integer(High(vCustom)) do
        if vCustom[i].Enabled then
        begin
          SetLength(vTags, Length(vTags) + 1);
          vTags[High(vTags)] := vCustom[i].Tag;
        end;
      if Length(vTags) > 0 then
      begin
        vTexts := ReadExifTagTexts(FCurrentPath, vTags);
        i := 0;
        for vK := 0 to Integer(High(vCustom)) do
          if vCustom[vK].Enabled then
          begin
            if vTexts[i] <> '' then
            begin
              if not vExifHeader then
              begin
                vSl.Add('');
                vSl.Add('--- EXIF ---');
                vExifHeader := True;
              end;
              if vCustom[vK].Caption <> '' then
                AddLine(vCustom[vK].Caption, vTexts[i])
              else
                AddLine(Format('0x%.4X', [vCustom[vK].Tag]), vTexts[i]);
            end;
            Inc(i);
          end;
      end;
    end
    else
    begin
      Add('type', L('Видео', 'Video'));
      if FPlayer.currentMedia <> nil then
      begin
        Add('duration', FPlayer.currentMedia.durationString);
        if FPlayer.currentMedia.imageSourceWidth > 0 then
          Add('resolution', Format('%d x %d', [FPlayer.currentMedia.imageSourceWidth,
            FPlayer.currentMedia.imageSourceHeight]));
      end;
      vMeta := GetMediaMeta(FCurrentItem);
      if vMeta.HasDate then
        Add('datefile', DateTimeToStr(vMeta.Date));
    end;
    Result := vSl.Text;
  finally
    vSl.Free;
  end;
end;

procedure TViewerForm.DoShare;
var
  vMenu: TPopupMenu;
  vTarget: TShareTarget;
  vItem: TMenuItem;
  vPt: TPoint;
begin
  if not FHasCurrent or (FCurrentPath = '') then
    Exit;
  // pause while the share menu is open
  if not FPaused and not FInfoShown then
    TogglePause;
  FBusy := True;
  vMenu := TPopupMenu.Create(Self);
  try
    for vTarget := Low(TShareTarget) to High(TShareTarget) do
    begin
      vItem := TMenuItem.Create(vMenu);
      vItem.Caption := ShareTargetTitle(vTarget);
      vItem.Tag := Ord(vTarget);
      vItem.OnClick := ShareClick;
      vMenu.Items.Add(vItem);
    end;
    Screen.Cursor := crDefault;
    GetCursorPos(vPt);
    vMenu.Popup(vPt.X, vPt.Y);
    Application.ProcessMessages;
  finally
    FBusy := False;
    vMenu.Free;
    if FMode = vmScreenSaver then
      Screen.Cursor := crNone;
    GetCursorPos(FStartPt);
  end;
end;

procedure TViewerForm.ShareClick(Sender: TObject);
begin
  try
    ShareFile(TShareTarget((Sender as TMenuItem).Tag), FCurrentPath);
  except
    on E: Exception do
      Application.MessageBox(PChar(E.Message), PChar(L('Поделиться', 'Share')), MB_OK or MB_ICONWARNING);
  end;
end;

procedure TViewerForm.OpenSettings;
begin
  FBusy := True;
  try
    FTimer.Enabled := False;
    if ShowSettingsDialog then
    begin
      StopScan;
      StartScan;
    end;
  finally
    FBusy := False;
  end;
  if FHasCurrent then
    ArmTimer
  else
  begin
    FTimer.Interval := 300;
    FTimer.Enabled := True;
  end;
end;

end.
