unit uPreview;

{ Preview mode (/p <hwnd>): Windows shows the screensaver in the small monitor of the
  "Screen Saver Settings" dialog. We show one random photo there. }

interface

uses
  Winapi.Windows;

procedure RunPreview(AParentWnd: HWND);

implementation

uses
  System.SysUtils, System.Classes, System.Math, Vcl.Controls, Vcl.Forms, Vcl.ExtCtrls, Vcl.Graphics,
  uConfig, uMedia, uViewer;

type
  TPreviewForm = class(TForm)
  private
    FPicture: TPicture;       // the photo
    FScaled: TBitmap;         // the photo scaled to the window (high quality)
    FTimer: TTimer;
    FCatalog: TMediaCatalog;
    FSampler: TQuickSampler;
    FLoaded: Boolean;
    FTicks: Integer;
    procedure TimerTick(Sender: TObject);
    procedure FitToParent;
    procedure Rebuild;
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  GParentWnd: HWND;

constructor TPreviewForm.Create(AOwner: TComponent);
begin
  CreateNew(AOwner);
  Scaled := False;
  BorderStyle := bsNone;
  Color := clBlack;
  ParentWindow := GParentWnd;
  FPicture := TPicture.Create;
  FScaled := TBitmap.Create;
  FitToParent;
  FCatalog := TMediaCatalog.Create;
  FSampler := TQuickSampler.Create(FCatalog);
  FTimer := TTimer.Create(Self);
  FTimer.Interval := 200;
  FTimer.OnTimer := TimerTick;
end;

destructor TPreviewForm.Destroy;
begin
  FSampler.Terminate;
  FSampler.WaitFor;
  FreeAndNil(FSampler);
  FreeAndNil(FCatalog);
  FreeAndNil(FScaled);
  FreeAndNil(FPicture);
  inherited;
end;

{ Makes the window exactly as big as the client area of the preview window of Windows. }
procedure TPreviewForm.FitToParent;
var
  vRect: TRect;
  vW, vH: Integer;
begin
  Winapi.Windows.GetClientRect(GParentWnd, vRect);
  vW := vRect.Right - vRect.Left;
  vH := vRect.Bottom - vRect.Top;
  if (vW <= 0) or (vH <= 0) then
    Exit;
  if (Width <> vW) or (Height <> vH) or (FScaled.Width <> vW) or (FScaled.Height <> vH) then
  begin
    SetWindowPos(Handle, 0, 0, 0, vW, vH, SWP_NOZORDER or SWP_NOACTIVATE or SWP_SHOWWINDOW);
    Rebuild;
    Invalidate;
  end;
end;

{ Scales the photo to the window with the halftone mode (no noise on strong reduction). }
procedure TPreviewForm.Rebuild;
var
  vSrc: TBitmap;
  vW, vH, vX, vY: Integer;
  vScale: Double;
begin
  FScaled.PixelFormat := pf24bit;
  FScaled.SetSize(Max(1, ClientWidth), Max(1, ClientHeight));
  FScaled.Canvas.Brush.Color := clBlack;
  FScaled.Canvas.FillRect(Rect(0, 0, FScaled.Width, FScaled.Height));
  if (FPicture.Graphic = nil) or FPicture.Graphic.Empty then
    Exit;
  vSrc := TBitmap.Create;
  try
    vSrc.PixelFormat := pf24bit;
    vSrc.SetSize(FPicture.Width, FPicture.Height);
    vSrc.Canvas.Draw(0, 0, FPicture.Graphic);
    vScale := Min(FScaled.Width / vSrc.Width, FScaled.Height / vSrc.Height);
    vW := Max(1, Integer(Round(vSrc.Width * vScale)));
    vH := Max(1, Integer(Round(vSrc.Height * vScale)));
    vX := (FScaled.Width - vW) div 2;
    vY := (FScaled.Height - vH) div 2;
    SetStretchBltMode(FScaled.Canvas.Handle, HALFTONE);
    SetBrushOrgEx(FScaled.Canvas.Handle, 0, 0, nil);
    StretchBlt(FScaled.Canvas.Handle, vX, vY, vW, vH, vSrc.Canvas.Handle, 0, 0,
      vSrc.Width, vSrc.Height, SRCCOPY);
  finally
    vSrc.Free;
  end;
end;

procedure TPreviewForm.Paint;
begin
  Canvas.Draw(0, 0, FScaled);
end;

procedure TPreviewForm.TimerTick(Sender: TObject);
var
  vItem: TMediaItem;
begin
  Inc(FTicks);
  // the settings dialog was closed: the parent window is gone
  if not IsWindow(GParentWnd) then
  begin
    Application.Terminate;
    Exit;
  end;
  FitToParent;
  if FLoaded or (FTicks > 50) then   // one photo, or give up after ~10 s
    Exit;
  if FCatalog.PopQuick(vItem) then
  begin
    FLoaded := True;
    FCatalog.Ready := True;          // stops the sampler
    try
      LoadPhotoPicture(FPicture, vItem.Location);
    except
      FPicture.Assign(nil);
    end;
    Rebuild;
    Invalidate;
  end;
end;

procedure RunPreview(AParentWnd: HWND);
var
  vForm: TPreviewForm;
begin
  if not IsWindow(AParentWnd) then
    Exit;
  GParentWnd := AParentWnd;
  Application.MainFormOnTaskbar := False;
  Application.CreateForm(TPreviewForm, vForm);
  Application.Run;
end;

end.
