unit uViewer;

{ Full-screen / windowed media viewer. Built in code (no .dfm). }

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, System.Generics.Collections,
  Vcl.Controls, Vcl.Forms, Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.Graphics, Vcl.Menus, Vcl.Imaging.pngimage,
  WMPLib, uConfig, uMedia;

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
    FImage: TImage;
    FVideoHost: TPanel;
    FPlayer: TWindowsMediaPlayer;
    FStatus: TLabel;
    FInfo: TMemo;
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
    procedure PlayerError(Sender: TObject);
    procedure GoNext;
    procedure GoPrev;
    procedure ShowCurrent;
    procedure ShowPhoto(const APath: string; const AItem: TMediaItem);
    procedure ShowVideo(const APath: string);
    procedure ShowMessage(const AText: string);
    procedure ArmTimer;
    procedure TogglePause;
    procedure ToggleInfo;
    procedure HideInfo;
    function BuildInfo: string;
    procedure DoShare;
    procedure ShareClick(Sender: TObject);
    procedure OpenSettings;
    procedure CreateBlankForms;
    procedure LoadOrientedImage(const APath: string; AOrientation: Integer);
  protected
    procedure DoShow; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  GViewerMode: TViewerMode = vmStandalone;

implementation

uses
  System.IOUtils, System.DateUtils, System.StrUtils, System.Math, Vcl.Imaging.jpeg, Vcl.Imaging.GIFImg,
  Winapi.Wincodec, uLocation, uRules, uExif, uShare, uSettingsForm;

const
  HistoryLimit = 100000;
  MaxFailures = 25;

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
  Caption := 'MyScreenSaver';

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

  FImage := TImage.Create(Self);
  FImage.Parent := Self;
  FImage.Align := alClient;
  FImage.Center := True;
  FImage.Proportional := True;
  FImage.Stretch := True;

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

  FInfo := TMemo.Create(Self);
  FInfo.Parent := Self;
  FInfo.ReadOnly := True;
  FInfo.BorderStyle := bsNone;
  FInfo.Color := $202020;
  FInfo.Font.Color := clWhite;
  FInfo.Font.Name := 'Consolas';
  FInfo.Font.Size := 13;
  FInfo.ScrollBars := ssVertical;
  FInfo.Visible := False;
  FInfo.SetBounds(40, 40, 760, 520);

  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.OnTimer := TimerTick;

  Application.OnMessage := AppMessage;
  StartScan;
end;

destructor TViewerForm.Destroy;
begin
  Application.OnMessage := nil;
  // The process is ending: the scan thread is only asked to stop (no blocking wait).
  if FScan <> nil then
    FScan.Terminate;
  if FQuick <> nil then
    FQuick.Terminate;
  if FIndexer <> nil then
    FIndexer.Terminate;
  FreeAndNil(FBlankForms);
  FreeAndNil(FHistory);
  inherited;
end;

procedure TViewerForm.DoShow;
begin
  inherited;
  GetCursorPos(FStartPt);
  if FMode = vmScreenSaver then
    CreateBlankForms;
  if not FTimer.Enabled then
  begin
    ShowMessage('Загрузка списка файлов...');
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
        Handled := HandleKey(Msg.wParam, (Msg.lParam and $40000000) <> 0);
      end;
    WM_LBUTTONDOWN, WM_RBUTTONDOWN, WM_MBUTTONDOWN:
      if FMode = vmScreenSaver then
        Close;
    WM_MOUSEMOVE:
      if FMode = vmScreenSaver then
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
      GoPrev;
    VK_RIGHT:
      GoNext;
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
  FTimer.Enabled := False;
  GoNext;
end;

procedure TViewerForm.ArmTimer;
begin
  FTimer.Enabled := False;
  if FPaused or FInfoShown then
    Exit;
  FTimer.Interval := Max(1, Settings.SlideSeconds) * 1000;
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
      ShowMessage('Загрузка списка файлов...')
    else if Settings.Collections.Count = 0 then
      ShowMessage('Нет медиаколлекций. Настройте приложение (клавиша C).')
    else
      ShowMessage('Медиафайлы не найдены.');
    FTimer.Interval := IfThen(FCatalog.Scanning, 200, 1500);
    FTimer.Enabled := True;
    Exit;
  end;
  FHistory.Add(vItem);
  if FHistory.Count > HistoryLimit then
    FHistory.DeleteRange(0, FHistory.Count - HistoryLimit);
  FHistPos := FHistory.Count - 1;
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
  FImage.Picture.Assign(nil);
  FStatus.Caption := AText;
  FStatus.Visible := True;
  FStatus.BringToFront;
end;

procedure TViewerForm.ShowCurrent;
var
  vItem: TMediaItem;
  vPath: string;
begin
  vItem := FHistory[FHistPos];
  FCurrentItem := vItem;
  FHasCurrent := True;
  FTimer.Enabled := False;
  FPlayer.controls.stop;
  Screen.Cursor := IfThen(FMode = vmScreenSaver, crNone, crHourGlass);
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
    FTimer.Interval := IfThen(FFailures > MaxFailures, 3000, 10);
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
    FTimer.Interval := IfThen(FFailures > MaxFailures, 3000, 10);
    FTimer.Enabled := True;
  end;
end;

procedure TViewerForm.LoadOrientedImage(const APath: string; AOrientation: Integer);
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
    FImage.Picture.Assign(vWic);
  finally
    vWic.Free;
  end;
end;

procedure TViewerForm.ShowPhoto(const APath: string; const AItem: TMediaItem);
var
  vOrient: Integer;
begin
  vOrient := 0;
  if MatchText(LowerCase(ExtractFileExt(APath)), ['.jpg', '.jpeg', '.jfif']) then
    vOrient := ReadExif(APath).Orientation;
  LoadOrientedImage(APath, vOrient);
  FVideoHost.Visible := False;
  FImage.Visible := True;
  ArmTimer;
end;

procedure TViewerForm.ShowVideo(const APath: string);
begin
  FImage.Picture.Assign(nil);
  FVideoHost.Visible := True;
  FPlayer.URL := APath;
  FPlayer.controls.play;
  // the next file is chosen when playback ends; the timer is a safety net
  FTimer.Enabled := False;
  FTimer.Interval := 6 * 60 * 60 * 1000;
  FTimer.Enabled := not (FPaused or FInfoShown);
end;

procedure TViewerForm.PlayerStateChange(ASender: TObject; ANewState: Integer);
begin
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
    FStatus.Caption := 'Пауза';
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
  FInfo.Text := BuildInfo;
  FInfo.Width := Min(900, ClientWidth - 80);
  FInfo.Height := Min(600, ClientHeight - 80);
  FInfo.Visible := True;
  FInfo.BringToFront;
end;

procedure TViewerForm.HideInfo;
begin
  if not FInfoShown then
    Exit;
  FInfoShown := False;
  FInfo.Visible := False;
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

  procedure Add(const ACaption, AValue: string);
  begin
    if AValue <> '' then
      vSl.Add(Format('%-18s %s', [ACaption + ':', AValue]));
  end;

begin
  vSl := TStringList.Create;
  try
    Add('Файл', FCurrentItem.DisplayName);
    Add('Коллекция', FCurrentItem.Collection);
    Add('Расположение', FCurrentItem.Location);
    if (FCurrentPath <> '') and FileExists(FCurrentPath) then
    begin
      vSize := TFile.GetSize(FCurrentPath);
      Add('Размер', Format('%s (%d байт)', [FormatFloat('#,##0.0', vSize / 1048576) + ' МБ', vSize]));
      Add('Дата создания', DateTimeToStr(TFile.GetCreationTime(FCurrentPath)));
      Add('Дата изменения', DateTimeToStr(TFile.GetLastWriteTime(FCurrentPath)));
    end;
    if FCurrentItem.Kind = mkPhoto then
    begin
      Add('Тип', 'Фотография');
      if FImage.Picture.Width > 0 then
        Add('Разрешение', Format('%d x %d', [FImage.Picture.Width, FImage.Picture.Height]));
      vExif := ReadExif(FCurrentPath);
      if vExif.Valid then
      begin
        vSl.Add('');
        vSl.Add('--- EXIF ---');
        Add('Производитель', vExif.Make);
        Add('Камера', vExif.Model);
        Add('Объектив', vExif.Lens);
        if vExif.HasDate then
          Add('Дата съёмки', DateTimeToStr(vExif.DateTaken));
        Add('Выдержка', vExif.Exposure);
        Add('Диафрагма', vExif.FNumber);
        Add('ISO', vExif.ISO);
        Add('Фокусное', vExif.FocalLength);
        if vExif.HasGps then
        begin
          Add('GPS', Format('%.6f, %.6f', [vExif.Lat, vExif.Lon],
            TFormatSettings.Invariant));
          Screen.Cursor := crHourGlass;
          try
            vPlace := ReverseGeocode(vExif.Lat, vExif.Lon, Settings.GeoLanguage);
          finally
            Screen.Cursor := IfThen(FMode = vmScreenSaver, crNone, crDefault);
          end;
          if vPlace <> '' then
            Add('Место', vPlace)
          else
            Add('Место', '(не удалось определить — нет интернета?)');
        end;
      end;
    end
    else
    begin
      Add('Тип', 'Видео');
      if FPlayer.currentMedia <> nil then
      begin
        Add('Длительность', FPlayer.currentMedia.durationString);
        if FPlayer.currentMedia.imageSourceWidth > 0 then
          Add('Разрешение', Format('%d x %d', [FPlayer.currentMedia.imageSourceWidth,
            FPlayer.currentMedia.imageSourceHeight]));
      end;
      vMeta := GetMediaMeta(FCurrentItem);
      if vMeta.HasDate then
        Add('Дата (файл)', DateTimeToStr(vMeta.Date));
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
      vItem.Caption := ShareTargetTitles[vTarget];
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
      Application.MessageBox(PChar(E.Message), 'Поделиться', MB_OK or MB_ICONWARNING);
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
