unit uViewer;

{ Full-screen / windowed media viewer. Built in code (no .dfm). }

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, System.Generics.Collections,
  Vcl.Controls, Vcl.Forms, Vcl.Clipbrd, Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.Buttons, Vcl.Graphics, Vcl.Menus, Vcl.Imaging.pngimage,
  WMPLib, uConfig, uMedia, uSlideView, uOverlay, uShareDialog;

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
    FOverlay: TOverlayWindow;    // selected fields over the photo / video
    FUserNav: Boolean;           // the move was made by the user (arrow keys): short transition
    FGoingBack: Boolean;         // the user goes to the previous slide
    FPendingVideo: string;       // a video waits until the photo has faded to black
    FWaitingOpen: Boolean;       // a video is opened and its size is checked before it plays
    FSkips: Integer;             // videos skipped in a row because they are too large
    FVideoHost: TPanel;
    FPlayer: TWindowsMediaPlayer;
    FStatus: TLabel;         // centered message (no collections / no files / loading)
    FPauseBar: TPanel;       // "Paused" badge at the bottom, above the video window too
    FInfoPanel: TPanel;      // gray frame
    FInfoInner: TPanel;      // dark background of the text
    FShareBtn: TButton;      // opens the share dialog
    FDeleteBtn: TButton;     // deletes the file
    FCloseBtn: TButton;      // closes the information dialog
    FInfoText: TMemo;        // read-only: text can be selected and copied
    FCacheLabel: TLabel;     // state of the cache, below the text and above the buttons
    FOpenCacheBtn: TSpeedButton;   // the buttons at the right end of the cache line (speed buttons: no tab stop)
    FClearShownBtn: TSpeedButton;
    FClearAllBtn: TSpeedButton;
    FTimer: TTimer;
    FNoticeTimer: TTimer;    // shows the "cache was cleared" message when the window is ready
    FPaused: Boolean;
    FInfoShown: Boolean;
    FBusy: Boolean;
    FFailures: Integer;
    FCurrentPath: string;
    FCurrentItem: TMediaItem;
    FPrevItem: TMediaItem;       // the file shown before FCurrentItem (the photo that is fading out)
    FPrevPath: string;
    FCurrentMarked: Boolean;     // its counter in shown.cache was already increased
    FCurrentShown: Boolean;      // the current file was shown completely (a video: it is visible)
    FHasCurrent: Boolean;
    FStartPt: TPoint;
    FBlankForms: TList<TForm>;
    procedure StartScan;
    procedure CacheResetNotice;
    procedure NoticeTimerTick(Sender: TObject);
    procedure StopScan;
    procedure AppMessage(var Msg: TMsg; var Handled: Boolean);
    function HandleKey(AKey: Word; ARepeat: Boolean): Boolean;
    procedure TimerTick(Sender: TObject);
    procedure PlayerStateChange(ASender: TObject; ANewState: Integer);
    function CheckVideoSize: Boolean;
    function BuildFieldText(AOverlay: Boolean): string;
    function OverlayConfigured: Boolean;
    procedure UpdateOverlay;
    procedure StartPlaceLookup(ALat, ALon: Double; const AItem: TMediaItem);
    function CachedPlace(const AItem: TMediaItem; ALat, ALon: Double; out APlace: string): Boolean;
    procedure WMMove(var Msg: TWMMove); message WM_MOVE;
    procedure FitVideo;
    procedure PlayerError(Sender: TObject);
    procedure GoNext;
    procedure GoPrev;
    procedure ShowCurrent;
    procedure CommitCurrent(const AItem: TMediaItem; const APath: string);
    procedure BackToPrevious;
    procedure MarkCurrentShown;
    procedure ShowPhoto(const APath: string; const AItem: TMediaItem);
    procedure ShowVideo(const APath: string);
    procedure StartVideo(const APath: string);
    procedure VideoFadedOut(Sender: TObject);
    function TransitionLength: Integer;
    procedure ShowMessage(const AText: string);
    procedure ArmTimer;
    procedure CenterStatus;
    procedure SetPauseBar(AVisible: Boolean);
    function HasEnabledCollection: Boolean;
    procedure TogglePause;
    procedure ToggleInfo;
    procedure HideInfo;
    procedure ShowInfoPanel(const AText: string);
    procedure InfoDblClick(Sender: TObject);
    function BuildInfo: string;
    procedure CreateInfoButtons;
    function CacheStateText: string;
    function NewCacheButton(AOnClick: TNotifyEvent): TSpeedButton;
    procedure OpenCacheClick(Sender: TObject);
    procedure ClearShownClick(Sender: TObject);
    procedure ClearAllClick(Sender: TObject);
    procedure ShareButtonClick(Sender: TObject);
    procedure DeleteButtonClick(Sender: TObject);
    procedure CloseButtonClick(Sender: TObject);
    procedure PerformShareAction(AAction: TShareAction);
    procedure DeleteCurrentFile;
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

{$R *.DFM}

uses
  System.IOUtils, System.DateUtils, System.StrUtils, System.Math, Vcl.Imaging.jpeg, Vcl.Imaging.GIFImg,
  Winapi.Wincodec, Winapi.ShellAPI, uVersion, uLang, uInfoFields, uLocation, uRules, uExif, uShare, uSettingsForm;

var
  GViewer: TViewerForm;   // for the callbacks of background threads (never a dangling Self)

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
  GViewer := Self;
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
  FStatus.Font.Size := 24;
  FStatus.Font.Color := clSilver;
  FStatus.Transparent := True;
  FStatus.AutoSize := True;
  FStatus.Visible := False;

  FPauseBar := TPanel.Create(Self);
  FPauseBar.Parent := Self;
  FPauseBar.BevelOuter := bvNone;
  FPauseBar.ParentBackground := False;
  FPauseBar.Color := $303030;
  FPauseBar.Font.Size := 16;
  FPauseBar.Font.Color := clWhite;
  FPauseBar.Height := 48;
  FPauseBar.Visible := False;

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
  FInfoText.Font.Size := 11;
  FInfoText.Cursor := crIBeam;
  FInfoText.WordWrap := True;
  FInfoText.OnDblClick := InfoDblClick;
  FCacheLabel := TLabel.Create(Self);
  FCacheLabel.Parent := FInfoInner;
  FCacheLabel.Font.Name := 'Segoe UI';
  FCacheLabel.Font.Size := 9;
  FCacheLabel.Font.Color := clSilver;
  FCacheLabel.AutoSize := False;
  FCacheLabel.Transparent := True;
  FOpenCacheBtn := NewCacheButton(OpenCacheClick);
  FClearShownBtn := NewCacheButton(ClearShownClick);
  FClearAllBtn := NewCacheButton(ClearAllClick);
  CreateInfoButtons;

  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.OnTimer := TimerTick;
  FNoticeTimer := TTimer.Create(Self);
  FNoticeTimer.Enabled := False;
  FNoticeTimer.Interval := 500;
  FNoticeTimer.OnTimer := NoticeTimerTick;

  Application.OnMessage := AppMessage;
  OnCatalogCacheReset := CacheResetNotice;
  StartScan;
end;

destructor TViewerForm.Destroy;
begin
  GViewer := nil;
  OnCatalogCacheReset := nil;
  FreeAndNil(FOverlay);
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

{ The cache had no version or another one: it was deleted and is built again. The message box is centered
  over the viewer window (the whole screen). }
procedure TViewerForm.CacheResetNotice;
begin
  // not at once: the scan thread reports it while the window may still be under construction
  FNoticeTimer.Enabled := True;
end;

procedure TViewerForm.NoticeTimerTick(Sender: TObject);
begin
  if not Showing or FBusy then
    Exit;   // try again later
  FNoticeTimer.Enabled := False;
  FBusy := True;
  try
    Application.MessageBox(PChar(L('Формат кэша каталога изменился (нет номера версии или другая версия).' + #13#10 +
      'Кэш очищен и будет создан заново: папки сканируются снова, это может занять время.',
      'The format of the catalog cache has changed (no version number or another version).' + #13#10 +
      'The cache was cleared and is being rebuilt: the folders are scanned again, this may take a while.')),
      PChar(L('Кэш', 'Cache')), MB_OK or MB_ICONINFORMATION);
  finally
    FBusy := False;
  end;
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
      if FInfoShown then
        HideInfo   // Esc closes the information dialog only
      else
        Close;
    VK_SPACE:
      if not ARepeat then
        TogglePause;
    Ord('I'):
      if not ARepeat then
        ToggleInfo;
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

{ The file on the screen goes to the register of the shown files when it was shown completely (the photo is
  not fading in any more, the video is visible) and the slideshow switches to another file. }
procedure TViewerForm.MarkCurrentShown;
begin
  if FHasCurrent and FCurrentShown and not FCurrentMarked and (FPendingVideo = '') and not FView.Fading then
  begin
    MarkShown(FCurrentItem.Location);
    FCurrentMarked := True;
  end;
end;

procedure TViewerForm.GoNext;
var
  vItem: TMediaItem;
begin
  MarkCurrentShown;
  HideInfo;
  FPaused := False;
  SetPauseBar(False);
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
    else if not HasEnabledCollection then
      ShowMessage(L('Медиаколлекции не определены', 'No media collections are defined'))
    else
      ShowMessage(L('Нет доступных медиафайлов', 'No media files available'));
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
  MarkCurrentShown;
  HideInfo;
  FPaused := False;
  SetPauseBar(False);
  FStatus.Visible := False;
  Dec(FHistPos);
  ShowCurrent;
end;

procedure TViewerForm.ShowMessage(const AText: string);
begin
  if FOverlay <> nil then
    FOverlay.HideOverlay;
  FPlayer.controls.stop;
  FVideoHost.Visible := False;
  FPendingVideo := '';
  FView.Clear;
  FStatus.Caption := AText;
  CenterStatus;
  FStatus.Visible := True;
  FStatus.BringToFront;
end;

procedure TViewerForm.CenterStatus;
begin
  FStatus.Left := (ClientWidth - FStatus.Width) div 2;
  FStatus.Top := (ClientHeight - FStatus.Height) div 2;
end;

procedure TViewerForm.SetPauseBar(AVisible: Boolean);
begin
  if AVisible then
  begin
    FPauseBar.Caption := L('Пауза', 'Paused');
    FPauseBar.Width := 220;
    FPauseBar.Left := (ClientWidth - FPauseBar.Width) div 2;
    FPauseBar.Top := ClientHeight - FPauseBar.Height - 40;
    FPauseBar.Visible := True;
    FPauseBar.BringToFront;
  end
  else
    FPauseBar.Visible := False;
end;

function TViewerForm.HasEnabledCollection: Boolean;
var
  vColl: TMediaCollection;
begin
  Result := False;
  for vColl in Settings.Collections do
    if vColl.Enabled then
      Exit(True);
end;

procedure TViewerForm.ShowCurrent;
var
  vItem: TMediaItem;
  vPath: string;
begin
  FPendingVideo := '';
  FWaitingOpen := False;
  vItem := FHistory[FHistPos];
  FTimer.Enabled := False;
  FPlayer.controls.stop;
  Screen.Cursor := TCursor(IfThen(FMode = vmScreenSaver, crNone, crHourGlass));
  try
    vPath := EnsureLocalFile(vItem);
  finally
    if FMode = vmStandalone then
      Screen.Cursor := crDefault;
  end;
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
    begin
      CommitCurrent(vItem, vPath);
      ShowVideo(vPath);
    end;
    FFailures := 0;
  except
    Inc(FFailures);
    FHistory.Delete(FHistPos);
    Dec(FHistPos);
    FTimer.Interval := Cardinal(IfThen(FFailures > MaxFailures, 3000, 10));
    FTimer.Enabled := True;
  end;
end;

{ FCurrentItem / FCurrentPath always describe what is on the screen (the information dialog, the share
  and delete actions and the overlay use them): they are set only when the file is really being shown. }
procedure TViewerForm.CommitCurrent(const AItem: TMediaItem; const APath: string);
begin
  FPrevItem := FCurrentItem;
  FPrevPath := FCurrentPath;
  FCurrentItem := AItem;
  FCurrentPath := APath;
  FHasCurrent := True;
  FCurrentMarked := False;
  FCurrentShown := AItem.Kind = mkPhoto;   // a video counts when it becomes visible (StartVideo / CheckVideoSize)
end;

{ The running transition was cancelled: the old photo is on the screen again. It is the current file, and the
  history position goes back to it, so the cancelled one is shown again when the slideshow goes on. }
procedure TViewerForm.BackToPrevious;
var
  d: Integer;

  function Found(AIdx: Integer): Boolean;
  begin
    Result := (AIdx >= 0) and (AIdx < Integer(FHistory.Count)) and
      SameText(FHistory[AIdx].Location, FCurrentItem.Location);
    if Result then
      FHistPos := AIdx;
  end;

begin
  FCurrentItem := FPrevItem;
  FCurrentPath := FPrevPath;
  FCurrentShown := True;
  FCurrentMarked := True;   // it was counted when the slideshow left it
  for d := 0 to Integer(FHistory.Count) do
    if Found(FHistPos - d) or Found(FHistPos + d) then
      Exit;
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
    CommitCurrent(AItem, APath);
    FView.ShowPicture(vPic, vEffect, vMs, vDir);
  finally
    vPic.Free;
  end;
  ArmTimer;
  UpdateOverlay;
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
  if FOverlay <> nil then
    FOverlay.HideOverlay;   // it is shown again when the video plays
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
  FCurrentShown := not FWaitingOpen;
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
  if FStatus <> nil then
    CenterStatus;
  if (FPauseBar <> nil) and FPauseBar.Visible then
    SetPauseBar(True);
  if FOverlay <> nil then
    FOverlay.Refit;
end;

{ The video plays (its size is known now): a video with more pixels than the screen is stopped and
  skipped, the others become visible and get their sound. }
function TViewerForm.CheckVideoSize: Boolean;
var
  vW, vH: Integer;
begin
  Result := True;
  if not FWaitingOpen then
    Exit;
  FWaitingOpen := False;
  if FPlayer.currentMedia <> nil then
  begin
    vW := FPlayer.currentMedia.imageSourceWidth;
    vH := FPlayer.currentMedia.imageSourceHeight;
    if (vW > 0) and (vH > 0) and (Int64(vW) * vH > Int64(Monitor.Width) * Monitor.Height) then
    begin
      Result := False;   // too large: skipped
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
  FCurrentShown := True;
  FPlayer.settings.mute := Settings.SilentVideo;
  FPlayer.Visible := True;
  FitVideo;
end;

procedure TViewerForm.PlayerStateChange(ASender: TObject; ANewState: Integer);
begin
  // 3 = wmppsPlaying: the size of the video is known
  if ANewState = 3 then
    if CheckVideoSize then
    begin
      FitVideo;
      UpdateOverlay;   // the duration and the size of the video are known now
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
    SetPauseBar(True);
  end
  else
  begin
    SetPauseBar(False);
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
  // a video that is not visible yet (fading in from the previous photo / size check) is not "on the screen"
  if (FPendingVideo <> '') or FWaitingOpen then
    Exit;
  // a photo that is still fading in is not on the screen yet: the transition is cancelled, the information
  // is shown for the photo that is fading out (a transition from black is finished instead)
  if FView.CancelTransition then
    BackToPrevious;
  FInfoShown := True;
  if FOverlay <> nil then
    FOverlay.HideOverlay;
  FTimer.Enabled := False;
  if FCurrentItem.Kind = mkVideo then
    FPlayer.controls.pause;
  FStatus.Visible := False;
  SetPauseBar(False);
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
  BtnH = 25;   // the default height of the buttons
var
  vSl: TStringList;
  vMaxW, vCap, vHeight, vLineH, i, vBtnW, vDelW, vCloseW, vContentW, vY, vCacheW, vOpenW, vShownW, vAllW, vBtnGap: Integer;
  vRect: TRect;
begin
  FInfoText.Font.Name := Settings.InfoFontName;   // configurable
  FInfoText.Font.Size := Settings.InfoFontSize;
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
  // three buttons below the text: Share (the share dialog with the actions), Delete (only for the files
  // of this computer or of the network) and Close at the right edge
  FShareBtn.Caption := L('Поделиться...', 'Share...');
  FDeleteBtn.Caption := L('Удалить', 'Delete');
  FDeleteBtn.Enabled := FCurrentItem.SourceKind in [skLocal, skNetwork];
  FCloseBtn.Caption := L('Закрыть', 'Close');
  Canvas.Font.Assign(FShareBtn.Font);
  vBtnW := Canvas.TextWidth(FShareBtn.Caption) + 44;
  vDelW := Canvas.TextWidth(FDeleteBtn.Caption) + 44;
  vCloseW := Canvas.TextWidth(FCloseBtn.Caption) + 44;
  FCacheLabel.Caption := CacheStateText;
  FOpenCacheBtn.Caption := L('Открыть кэш', 'Open Cache');
  FClearShownBtn.Caption := L('Сбросить показанные', 'Clear shown');
  FClearAllBtn.Caption := L('Очистить всё', 'Clear all');
  Canvas.Font.Assign(FCacheLabel.Font);
  vCacheW := Canvas.TextWidth(FCacheLabel.Caption);
  vBtnGap := 4;
  vOpenW := Canvas.TextWidth(FOpenCacheBtn.Caption) + 20;
  vShownW := Canvas.TextWidth(FClearShownBtn.Caption) + 20;
  vAllW := Canvas.TextWidth(FClearAllBtn.Caption) + 20;
  vContentW := Max(Max(vMaxW, vBtnW + 2 * vDelW + vCloseW + 48),
    vCacheW + 24 + vOpenW + vShownW + vAllW + 2 * vBtnGap);

  FInfoText.Text := AText.TrimRight;
  FInfoText.SetBounds(Pad, Pad, vContentW, vHeight + 4);
  FInfoText.HandleNeeded;
  FInfoText.Perform(EM_SETMARGINS, EC_LEFTMARGIN or EC_RIGHTMARGIN, 0);
  FCacheLabel.SetBounds(Pad, Pad + vHeight + 4 + 12, vCacheW + 4, Canvas.TextHeight('Wg') + 2);
  FClearAllBtn.SetBounds(Pad + vContentW - vAllW, FCacheLabel.Top - 3, vAllW, FCacheLabel.Height + 6);
  FClearShownBtn.SetBounds(FClearAllBtn.Left - vBtnGap - vShownW, FClearAllBtn.Top, vShownW, FClearAllBtn.Height);
  FOpenCacheBtn.SetBounds(FClearShownBtn.Left - vBtnGap - vOpenW, FClearAllBtn.Top, vOpenW, FClearAllBtn.Height);
  vY := FCacheLabel.Top + FCacheLabel.Height + 14;
  FShareBtn.SetBounds(Pad, vY, vBtnW, BtnH);
  FDeleteBtn.SetBounds(Pad + vBtnW + vDelW, vY, vDelW, BtnH);   // a gap of its own width after Share
  FCloseBtn.SetBounds(Pad + vContentW - vCloseW, vY, vCloseW, BtnH);   // Close: the right edge
  FInfoInner.SetBounds(Border, Border, vContentW + 2 * Pad, vY + BtnH + Pad);
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
  UpdateOverlay;
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

{ The text of the selected fields of the current file: for the information dialog (AOverlay = False) or for
  the overlay over the image (AOverlay = True). }
function TViewerForm.BuildFieldText(AOverlay: Boolean): string;
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

  function FieldOn(const AId: string): Boolean;
  begin
    if AOverlay then
      Result := OverlayFieldOn(AId)
    else
      Result := InfoFieldOn(AId);
  end;

  function CustomOn(const ATag: TInfoCustomTag): Boolean;
  begin
    if AOverlay then
      Result := ATag.Overlay
    else
      Result := ATag.Enabled;
  end;

  procedure AddLine(const ACaption, AValue: string);
  begin
    if AValue = '' then
      Exit;
    if AOverlay then
    begin
      if Settings.OverlayShowNames then
        vSl.Add(ACaption + ': ' + AValue)
      else
        vSl.Add(AValue);
    end
    else
      vSl.Add(Format('%-18s %s', [ACaption + ':', AValue]));
  end;

  { a built-in field, only if it is switched on in the settings }
  procedure Add(const AId, AValue: string);
  begin
    if FieldOn(AId) then
      AddLine(InfoFieldTitle(AId), AValue);
  end;

  { the same for the EXIF block; in the information dialog its header is printed before the first line }
  procedure AddExif(const AId, AValue: string);
  begin
    if (AValue = '') or not FieldOn(AId) then
      Exit;
    if not AOverlay and not vExifHeader then
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
          if FieldOn('place') then
          begin
            if AOverlay then
            begin
              // the overlay never waits for the internet: the name is taken from the cache, or it is
              // requested in the background and the overlay is updated when it has arrived
              if CachedPlace(FCurrentItem, vExif.Lat, vExif.Lon, vPlace) then
                AddExif('place', vPlace)
              else
                StartPlaceLookup(vExif.Lat, vExif.Lon, FCurrentItem);
            end
            else
            begin
              if not CachedPlace(FCurrentItem, vExif.Lat, vExif.Lon, vPlace) then
              begin
                Screen.Cursor := crHourGlass;
                try
                  vPlace := ReverseGeocode(vExif.Lat, vExif.Lon, LanguageCode(CurrentLanguage));
                finally
                  Screen.Cursor := TCursor(IfThen(FMode = vmScreenSaver, crNone, crDefault));
                end;
              end;
              if vPlace = '' then
                vPlace := L('(не удалось определить — нет интернета?)', '(could not be determined — no internet?)');
              AddExif('place', vPlace);
            end;
          end;
        end;
      end;
      // own EXIF tags chosen in the settings
      vCustom := Settings.CustomTags.ToArray;
      SetLength(vTags, 0);
      for i := 0 to Integer(High(vCustom)) do
        if CustomOn(vCustom[i]) then
        begin
          SetLength(vTags, Length(vTags) + 1);
          vTags[High(vTags)] := vCustom[i].Tag;
        end;
      if Length(vTags) > 0 then
      begin
        vTexts := ReadExifTagTexts(FCurrentPath, vTags);
        i := 0;
        for vK := 0 to Integer(High(vCustom)) do
          if CustomOn(vCustom[vK]) then
          begin
            if vTexts[i] <> '' then
            begin
              if not AOverlay and not vExifHeader then
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

function TViewerForm.BuildInfo: string;
begin
  Result := BuildFieldText(False);
end;

function TViewerForm.OverlayConfigured: Boolean;
var
  vTag: TInfoCustomTag;
begin
  Result := Settings.OverlayFields.Count > 0;
  if not Result then
    for vTag in Settings.CustomTags do
      if vTag.Overlay then
        Exit(True);
end;

{ Shows (or hides) the overlay for the current file. }
procedure TViewerForm.UpdateOverlay;
var
  vText: string;
begin
  if FHasCurrent and not FInfoShown and OverlayConfigured then
    vText := Trim(BuildFieldText(True))
  else
    vText := '';
  if vText = '' then
  begin
    if FOverlay <> nil then
      FOverlay.HideOverlay;
    Exit;
  end;
  if FOverlay = nil then
    FOverlay := TOverlayWindow.CreateOverlay(Self, FMode = vmScreenSaver);
  FOverlay.ShowText(vText);
end;

{ The place name for the overlay is requested in the background; the overlay is updated when it arrives. }
{ The place name from the places cache (places.cache, loaded in memory). No internet access. }
function TViewerForm.CachedPlace(const AItem: TMediaItem; ALat, ALon: Double; out APlace: string): Boolean;
begin
  Result := TryGetCachedGeocode(ALat, ALon, LanguageCode(CurrentLanguage), APlace);
end;

procedure TViewerForm.StartPlaceLookup(ALat, ALon: Double; const AItem: TMediaItem);
var
  vLang: string;
begin
  vLang := LanguageCode(CurrentLanguage);
  TThread.CreateAnonymousThread(
    procedure
    var
      vPlace: string;
    begin
      vPlace := ReverseGeocode(ALat, ALon, vLang);   // fills the cache
      TThread.Queue(nil,
        procedure
        begin
          if (GViewer <> nil) and GViewer.FHasCurrent and (GViewer.FCurrentItem.Location = AItem.Location) then
            GViewer.UpdateOverlay;
        end);
    end).Start;
end;

procedure TViewerForm.WMMove(var Msg: TWMMove);
begin
  inherited;
  if FOverlay <> nil then
    FOverlay.Refit;
end;

{ One line: the catalog cache (files, indexed date/GPS, shown register, file size, scan state). }
function TViewerForm.CacheStateText: string;
var
  vSt: TCacheStatus;
begin
  vSt := GetCacheStatus(FCatalog);
  Result := Format(L('Кэш: файлов %.0n, метаданные %.0n, показано %.0n, %.1f МБ, %s',
    'Cache: %.0n files, metadata %.0n, shown %.0n, %.1f MB, %s'),
    [vSt.Files * 1.0, vSt.WithMeta * 1.0, vSt.Shown * 1.0, vSt.FileBytes / (1024 * 1024),
     IfThen(vSt.Scanning, L('идёт обновление', 'updating'), L('актуален', 'up to date'))]);
end;

{ A flat speed button: it is not a window, so it never takes the focus and has no tab stop. }
function TViewerForm.NewCacheButton(AOnClick: TNotifyEvent): TSpeedButton;
begin
  Result := TSpeedButton.Create(Self);
  Result.Parent := FInfoInner;
  Result.Flat := True;
  Result.Font.Name := 'Segoe UI';
  Result.Font.Size := 9;
  Result.Font.Color := $F0B060;
  Result.OnClick := AOnClick;
end;

{ Opens the folder with the cache files in Explorer. }
procedure TViewerForm.OpenCacheClick(Sender: TObject);
begin
  ShellExecute(0, 'open', PChar(ExtractFilePath(TAppSettings.ConfigPath)), nil, nil, SW_SHOWNORMAL);
end;

{ A new round of the random order: no file counts as shown. }
procedure TViewerForm.ClearShownClick(Sender: TObject);
begin
  ResetShown;
  FCacheLabel.Caption := CacheStateText;
end;

{ Deletes the whole cache (file list, date/GPS, shown register) and scans the folders again. }
procedure TViewerForm.ClearAllClick(Sender: TObject);
begin
  FBusy := True;
  try
    if Application.MessageBox(PChar(L('Очистить весь кэш (список файлов, дата и GPS, показанные) и просканировать ' +
      'папки заново?', 'Clear the whole cache (file list, date and GPS, shown files) and scan the folders again?')),
      PChar(L('Кэш', 'Cache')), MB_YESNO or MB_ICONQUESTION or MB_DEFBUTTON2) <> IDYES then
      Exit;
  finally
    FBusy := False;
  end;
  StopScan;
  ClearCacheData;
  StartScan;
  FCacheLabel.Caption := CacheStateText;
end;

procedure TViewerForm.CreateInfoButtons;
begin
  FShareBtn := TButton.Create(Self);
  FShareBtn.Parent := FInfoInner;
  FShareBtn.Font.Name := 'Segoe UI';
  FShareBtn.Font.Size := 10;
  FShareBtn.OnClick := ShareButtonClick;
  FDeleteBtn := TButton.Create(Self);
  FDeleteBtn.Parent := FInfoInner;
  FDeleteBtn.Font.Name := 'Segoe UI';
  FDeleteBtn.Font.Size := 10;
  FDeleteBtn.OnClick := DeleteButtonClick;
  FCloseBtn := TButton.Create(Self);
  FCloseBtn.Parent := FInfoInner;
  FCloseBtn.Font.Name := 'Segoe UI';
  FCloseBtn.Font.Size := 10;
  FCloseBtn.OnClick := CloseButtonClick;
end;

{ The only button of the information dialog: the share dialog with the actions that are possible for the file. }
procedure TViewerForm.ShareButtonClick(Sender: TObject);
var
  vActions: TShareActions;
  vAction: TShareAction;
  vChosen: Boolean;
begin
  vActions := [];
  if (FCurrentPath <> '') and FileExists(FCurrentPath) then
    vActions := vActions + [saEmail, saTelegram, saWhatsApp, saFacebook];
  if (FCurrentItem.Kind = mkPhoto) and FView.HasPicture then
    Include(vActions, saCopyImage);
  vActions := vActions + [saCopyPath, saCopyName];
  FBusy := True;
  try
    vChosen := ShowShareDialog(Self, FCurrentItem.DisplayName, vActions, vAction);
  finally
    FBusy := False;
  end;
  if vChosen then
    PerformShareAction(vAction);
  // the keyboard stays on the text, so Space / I / arrows work as before
  if FInfoShown and FInfoText.CanFocus then
    FInfoText.SetFocus;
end;

procedure TViewerForm.DeleteButtonClick(Sender: TObject);
begin
  DeleteCurrentFile;
  if FInfoShown and FInfoText.CanFocus then   // cancelled: the keyboard stays on the text
    FInfoText.SetFocus;
end;

procedure TViewerForm.CloseButtonClick(Sender: TObject);
begin
  HideInfo;   // the same as the I key: the slideshow goes on
end;

procedure TViewerForm.PerformShareAction(AAction: TShareAction);
begin
  case AAction of
    saEmail, saTelegram, saWhatsApp, saFacebook:
      begin
        FBusy := True;
        try
          try
            ShareFile(TShareTarget(Ord(AAction)), FCurrentPath);
          except
            on E: Exception do
              Application.MessageBox(PChar(E.Message), PChar(L('Поделиться', 'Share')), MB_OK or MB_ICONWARNING);
          end;
        finally
          FBusy := False;
        end;
      end;
    saCopyImage:
      if not FView.CopyPictureToClipboard then
        MessageBeep(MB_ICONASTERISK);
    saCopyPath:
      Clipboard.AsText := FCurrentItem.Location;
    saCopyName:
      Clipboard.AsText := FCurrentItem.DisplayName;
  end;
end;

{ Deletes the shown file (to the Recycle Bin; a file on a network share is deleted for good) and goes on. }
procedure TViewerForm.DeleteCurrentFile;
var
  vItem: TMediaItem;
  vMsg, vBuf: string;
  vOp: TSHFileOpStruct;
  i: Integer;
begin
  if not FHasCurrent or not (FCurrentItem.SourceKind in [skLocal, skNetwork]) then
    Exit;
  vItem := FCurrentItem;
  if vItem.SourceKind = skNetwork then
    vMsg := L('Файл будет удалён без возможности восстановления.', 'The file will be deleted permanently.')
  else
    vMsg := L('Файл будет перемещён в корзину.', 'The file will be moved to the Recycle Bin.');
  FBusy := True;
  try
    if Application.MessageBox(PChar(L('Удалить файл?', 'Delete the file?') + #13#10#13#10 + vItem.Location +
      #13#10#13#10 + vMsg), PChar(L('Удаление', 'Delete')), MB_YESNO or MB_ICONQUESTION or MB_DEFBUTTON2) <> IDYES then
      Exit;
  finally
    FBusy := False;
  end;
  if vItem.Kind = mkVideo then
  begin
    FPlayer.controls.stop;   // release the file
    FPlayer.URL := '';
  end;
  vBuf := vItem.Location + #0;   // the list of the files ends with a double zero
  FillChar(vOp, SizeOf(vOp), 0);
  vOp.Wnd := Handle;
  vOp.wFunc := FO_DELETE;
  vOp.pFrom := PChar(vBuf);
  vOp.fFlags := FOF_ALLOWUNDO or FOF_NOCONFIRMATION or FOF_SILENT or FOF_NOERRORUI;
  if (SHFileOperation(vOp) <> 0) or vOp.fAnyOperationsAborted or FileExists(vItem.Location) then
  begin
    FBusy := True;
    try
      Application.MessageBox(PChar(L('Не удалось удалить файл.', 'The file could not be deleted.')),
        PChar(L('Удаление', 'Delete')), MB_OK or MB_ICONWARNING);
    finally
      FBusy := False;
    end;
    Exit;
  end;
  // forget the file: the catalog and the history (it can be there several times)
  FCatalog.Remove(vItem.Location);
  for i := Integer(FHistory.Count) - 1 downto 0 do
    if SameText(FHistory[i].Location, vItem.Location) then
    begin
      FHistory.Delete(i);
      if i <= FHistPos then
        Dec(FHistPos);
    end;
  HideInfo;
  GoNext;
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
