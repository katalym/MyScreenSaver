unit uSlideView;

{ The slide: shows a photo scaled to the window (letterboxed) and changes photos with a transition
  effect. The photo is scaled once per slide with the halftone mode, a transition only mixes two
  ready bitmaps, so it stays smooth on plain GDI.
  Effects: cross-fade, fade through black, slide, wipe. }

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, System.Math, Vcl.Controls,
  Vcl.Graphics, Vcl.ExtCtrls, Vcl.Clipbrd, uConfig;

type
  { forward: the next photo (new one comes from the right / the wipe goes to the right);
    backward: the previous photo }
  TSlideDirection = (sdForward, sdBackward);

  TSlideView = class(TCustomControl)
  private
    FPicture: TPicture;           // the photo (original size)
    FOld: TPicture;               // the photo that is being replaced (kept during a transition, see CancelTransition)
    FFromBlack: Boolean;          // the running transition starts from black: there is no old photo to go back to
    FCurrent: TBitmap;            // the shown photo scaled to the window
    FNext: TBitmap;               // the incoming photo during a transition
    FFrame: TBitmap;              // composed frame
    FHasCurrent: Boolean;
    FFading: Boolean;
    FFadingOut: Boolean;          // the photo fades to black and is removed (before a video)
    FKind: TTransitionEffect;     // the running effect
    FDirection: TSlideDirection;
    FStart: UInt64;
    FDuration: Cardinal;
    FTimer: TTimer;
    FOnFadedOut: TNotifyEvent;
    procedure TimerTick(Sender: TObject);
    procedure BuildScaled(ATarget: TBitmap);
    procedure BuildBlack(ATarget: TBitmap);
    procedure SwapBitmaps;
    procedure EndFade;
    procedure StartFade(AKind: TTransitionEffect; ADirection: TSlideDirection; ADurationMs: Integer);
    function Progress: Double;
    procedure Blend(ASource: TBitmap; AAlpha: Integer);
    procedure WMEraseBkgnd(var Msg: TWMEraseBkgnd); message WM_ERASEBKGND;
  protected
    procedure Paint; override;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Replaces the photo. With a previous photo the effect is used, without one (the first photo,
      after a video) the new photo appears from black. }
    procedure ShowPicture(APicture: TPicture; AEffect: TTransitionEffect; ADurationMs: Integer;
      ADirection: TSlideDirection);
    { The photo fades to black, then OnFadedOut is called (at once if there is nothing to fade). }
    procedure FadeOut(ADurationMs: Integer);
    { Shows nothing (black); a running transition is dropped without OnFadedOut }
    procedure Clear;
    function HasPicture: Boolean;
    { Finishes a running transition at once: the incoming photo is fully shown (not a fade to black) }
    procedure Settle;
    { True while a transition between two photos runs (the new photo is not completely shown yet) }
    function Fading: Boolean;
    { Stops a running photo-to-photo transition and goes back to the old photo (True). A transition that starts
      from black (after a video / the first photo) is finished instead (False). }
    function CancelTransition: Boolean;
    { Puts the photo (original size) on the clipboard as an image }
    function CopyPictureToClipboard: Boolean;
    function PictureWidth: Integer;
    function PictureHeight: Integer;
    property OnFadedOut: TNotifyEvent read FOnFadedOut write FOnFadedOut;
  end;

implementation

{ TSlideView }

constructor TSlideView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  FPicture := TPicture.Create;
  FOld := TPicture.Create;
  FCurrent := TBitmap.Create;
  FNext := TBitmap.Create;
  FFrame := TBitmap.Create;
  FCurrent.PixelFormat := pf24bit;
  FNext.PixelFormat := pf24bit;
  FFrame.PixelFormat := pf24bit;
  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := 15;
  FTimer.OnTimer := TimerTick;
end;

destructor TSlideView.Destroy;
begin
  FreeAndNil(FFrame);
  FreeAndNil(FNext);
  FreeAndNil(FCurrent);
  FreeAndNil(FOld);
  FreeAndNil(FPicture);
  inherited;
end;

procedure TSlideView.WMEraseBkgnd(var Msg: TWMEraseBkgnd);
begin
  Msg.Result := 1;   // everything is painted in Paint, no flicker
end;

function TSlideView.Fading: Boolean;
begin
  Result := FFading;
end;

procedure TSlideView.Settle;
begin
  if FFading and not FFadingOut then
    EndFade;
end;

function TSlideView.CancelTransition: Boolean;
var
  vTmp: TPicture;
begin
  Result := False;
  if not FFading or FFadingOut then
    Exit;
  if FFromBlack then
  begin
    EndFade;
    Exit;
  end;
  FTimer.Enabled := False;
  FFading := False;
  vTmp := FPicture;     // the old photo (FCurrent still holds its scaled bitmap) comes back
  FPicture := FOld;
  FOld := vTmp;
  FOld.Assign(nil);
  Invalidate;
  Result := True;
end;

function TSlideView.HasPicture: Boolean;
begin
  Result := FHasCurrent and (FPicture.Width > 0);
end;

function TSlideView.CopyPictureToClipboard: Boolean;
var
  vBmp: TBitmap;
begin
  Result := False;
  if (FPicture.Graphic = nil) or (FPicture.Width <= 0) or (FPicture.Height <= 0) then
    Exit;
  vBmp := TBitmap.Create;
  try
    vBmp.PixelFormat := pf24bit;
    vBmp.SetSize(FPicture.Width, FPicture.Height);
    vBmp.Canvas.Draw(0, 0, FPicture.Graphic);
    Clipboard.Assign(vBmp);
    Result := True;
  finally
    vBmp.Free;
  end;
end;

function TSlideView.PictureWidth: Integer;
begin
  Result := FPicture.Width;
end;

function TSlideView.PictureHeight: Integer;
begin
  Result := FPicture.Height;
end;

procedure TSlideView.BuildBlack(ATarget: TBitmap);
begin
  ATarget.PixelFormat := pf24bit;
  ATarget.SetSize(Max(1, ClientWidth), Max(1, ClientHeight));
  ATarget.Canvas.Brush.Color := clBlack;
  ATarget.Canvas.FillRect(Rect(0, 0, ATarget.Width, ATarget.Height));
end;

{ Draws the photo into ATarget (the size of the window): proportional, centered, black borders. }
procedure TSlideView.BuildScaled(ATarget: TBitmap);
var
  vSrc: TBitmap;
  vW, vH, vX, vY: Integer;
  vScale: Double;
begin
  BuildBlack(ATarget);
  if (FPicture.Graphic = nil) or FPicture.Graphic.Empty or (FPicture.Width <= 0) or (FPicture.Height <= 0) then
    Exit;
  vSrc := TBitmap.Create;
  try
    vSrc.PixelFormat := pf24bit;
    vSrc.SetSize(FPicture.Width, FPicture.Height);
    vSrc.Canvas.Draw(0, 0, FPicture.Graphic);
    vScale := Min(ATarget.Width / vSrc.Width, ATarget.Height / vSrc.Height);
    vW := Max(1, Integer(Round(vSrc.Width * vScale)));
    vH := Max(1, Integer(Round(vSrc.Height * vScale)));
    vX := (ATarget.Width - vW) div 2;
    vY := (ATarget.Height - vH) div 2;
    SetStretchBltMode(ATarget.Canvas.Handle, HALFTONE);
    SetBrushOrgEx(ATarget.Canvas.Handle, 0, 0, nil);
    StretchBlt(ATarget.Canvas.Handle, vX, vY, vW, vH, vSrc.Canvas.Handle, 0, 0,
      vSrc.Width, vSrc.Height, SRCCOPY);
  finally
    vSrc.Free;
  end;
end;

procedure TSlideView.SwapBitmaps;
var
  vTmp: TBitmap;
begin
  vTmp := FCurrent;
  FCurrent := FNext;
  FNext := vTmp;
end;

{ Finishes the transition at once: the incoming picture becomes the shown one. }
procedure TSlideView.EndFade;
var
  vWasOut: Boolean;
begin
  FTimer.Enabled := False;
  if not FFading then
    Exit;
  vWasOut := FFadingOut;
  FFading := False;
  FFadingOut := False;
  FOld.Assign(nil);
  SwapBitmaps;
  if vWasOut then
  begin
    FHasCurrent := False;      // black: no photo any more
    FPicture.Assign(nil);
  end
  else
    FHasCurrent := True;
  Invalidate;
  if vWasOut and Assigned(FOnFadedOut) then
    FOnFadedOut(Self);
end;

procedure TSlideView.StartFade(AKind: TTransitionEffect; ADirection: TSlideDirection; ADurationMs: Integer);
begin
  FFrame.SetSize(FNext.Width, FNext.Height);
  FKind := AKind;
  FDirection := ADirection;
  FDuration := Cardinal(ADurationMs);
  FStart := GetTickCount64;
  FFading := True;
  FTimer.Enabled := True;
end;

procedure TSlideView.ShowPicture(APicture: TPicture; AEffect: TTransitionEffect; ADurationMs: Integer;
  ADirection: TSlideDirection);
var
  vKind: TTransitionEffect;
  vAnimate: Boolean;
  vOld: TPicture;
begin
  EndFade;
  vOld := FOld;
  FOld := FPicture;     // the replaced photo is kept while the transition runs
  FPicture := vOld;
  FPicture.Assign(APicture);
  FFromBlack := False;
  BuildScaled(FNext);
  vKind := AEffect;
  if vKind = teRandom then
    vKind := teFade;
  vAnimate := (vKind <> teNone) and (ADurationMs > 0) and Visible;
  if vAnimate and not FHasCurrent then
  begin
    // the first photo or the one after a video: it appears from black
    BuildBlack(FCurrent);
    FHasCurrent := True;
    FFromBlack := True;
    vKind := teFade;
  end;
  if vAnimate and FHasCurrent and (FCurrent.Width = FNext.Width) and (FCurrent.Height = FNext.Height) then
    StartFade(vKind, ADirection, ADurationMs)
  else
  begin
    SwapBitmaps;
    FHasCurrent := True;
    FOld.Assign(nil);
  end;
  Invalidate;
end;

procedure TSlideView.FadeOut(ADurationMs: Integer);
begin
  EndFade;
  if (ADurationMs <= 0) or not FHasCurrent or not Visible then
  begin
    FHasCurrent := False;
    FPicture.Assign(nil);
    Invalidate;
    if Assigned(FOnFadedOut) then
      FOnFadedOut(Self);
    Exit;
  end;
  BuildBlack(FNext);
  FFadingOut := True;
  StartFade(teFade, sdForward, ADurationMs);
  Invalidate;
end;

procedure TSlideView.Clear;
begin
  FTimer.Enabled := False;
  FFading := False;
  FFadingOut := False;
  FHasCurrent := False;
  FPicture.Assign(nil);
  FOld.Assign(nil);
  Invalidate;
end;

{ 0..1 with a smooth start and end }
function TSlideView.Progress: Double;
var
  t: Double;
begin
  if FDuration = 0 then
    Exit(1);
  t := Min(1.0, (GetTickCount64 - FStart) / FDuration);
  Result := t * t * (3 - 2 * t);
end;

procedure TSlideView.TimerTick(Sender: TObject);
begin
  if (GetTickCount64 - FStart) >= FDuration then
    EndFade
  else
    Invalidate;
end;

procedure TSlideView.Resize;
begin
  inherited;
  if FPicture = nil then
    Exit;
  // the scaled bitmaps depend on the window size: a running transition is dropped
  FTimer.Enabled := False;
  if FFading then
  begin
    FFading := False;
    FOld.Assign(nil);
    if FFadingOut then
    begin
      FFadingOut := False;
      FHasCurrent := False;
      FPicture.Assign(nil);
      Invalidate;
      if Assigned(FOnFadedOut) then
        FOnFadedOut(Self);
      Exit;
    end;
  end;
  if (ClientWidth > 0) and (ClientHeight > 0) and (FHasCurrent or (FPicture.Width > 0)) then
  begin
    BuildScaled(FCurrent);
    FHasCurrent := FPicture.Width > 0;
  end;
  Invalidate;
end;

{ Mixes ASource into the frame with the given opacity (0..255). }
procedure TSlideView.Blend(ASource: TBitmap; AAlpha: Integer);
var
  vBlend: TBlendFunction;
begin
  vBlend.BlendOp := AC_SRC_OVER;
  vBlend.BlendFlags := 0;
  vBlend.SourceConstantAlpha := Byte(Max(0, Min(255, AAlpha)));
  vBlend.AlphaFormat := 0;
  AlphaBlend(FFrame.Canvas.Handle, 0, 0, FFrame.Width, FFrame.Height, ASource.Canvas.Handle, 0, 0,
    ASource.Width, ASource.Height, vBlend);
end;

procedure TSlideView.Paint;
var
  vW, vH, vOff: Integer;
  e: Double;
begin
  vW := ClientWidth;
  vH := ClientHeight;
  if FFading and (FFrame.Width = vW) and (FFrame.Height = vH) and
    (FCurrent.Width = vW) and (FNext.Width = vW) then
  begin
    e := Progress;
    case FKind of
      teFadeBlack:
        begin
          // first half: the old photo fades to black, second half: the new one appears
          FFrame.Canvas.Brush.Color := clBlack;
          FFrame.Canvas.FillRect(Rect(0, 0, vW, vH));
          if e < 0.5 then
            Blend(FCurrent, Integer(Round(255 * (1 - 2 * e))))
          else
            Blend(FNext, Integer(Round(255 * (2 * e - 1))));
        end;
      teSlide:
        begin
          vOff := Integer(Round(vW * e));
          if FDirection = sdForward then
          begin
            // the old photo goes left, the new one comes from the right
            BitBlt(FFrame.Canvas.Handle, 0, 0, vW - vOff, vH, FCurrent.Canvas.Handle, vOff, 0, SRCCOPY);
            BitBlt(FFrame.Canvas.Handle, vW - vOff, 0, vOff, vH, FNext.Canvas.Handle, 0, 0, SRCCOPY);
          end
          else
          begin
            BitBlt(FFrame.Canvas.Handle, vOff, 0, vW - vOff, vH, FCurrent.Canvas.Handle, 0, 0, SRCCOPY);
            BitBlt(FFrame.Canvas.Handle, 0, 0, vOff, vH, FNext.Canvas.Handle, vW - vOff, 0, SRCCOPY);
          end;
        end;
      teWipe:
        begin
          vOff := Integer(Round(vW * e));
          BitBlt(FFrame.Canvas.Handle, 0, 0, vW, vH, FCurrent.Canvas.Handle, 0, 0, SRCCOPY);
          if FDirection = sdForward then
            BitBlt(FFrame.Canvas.Handle, 0, 0, vOff, vH, FNext.Canvas.Handle, 0, 0, SRCCOPY)
          else
            BitBlt(FFrame.Canvas.Handle, vW - vOff, 0, vOff, vH, FNext.Canvas.Handle, vW - vOff, 0, SRCCOPY);
        end;
    else
      // cross-fade
      BitBlt(FFrame.Canvas.Handle, 0, 0, vW, vH, FCurrent.Canvas.Handle, 0, 0, SRCCOPY);
      Blend(FNext, Integer(Round(255 * e)));
    end;
    BitBlt(Canvas.Handle, 0, 0, vW, vH, FFrame.Canvas.Handle, 0, 0, SRCCOPY);
  end
  else if FHasCurrent and (FCurrent.Width = vW) and (FCurrent.Height = vH) then
    BitBlt(Canvas.Handle, 0, 0, vW, vH, FCurrent.Canvas.Handle, 0, 0, SRCCOPY)
  else
  begin
    Canvas.Brush.Color := clBlack;
    Canvas.FillRect(Rect(0, 0, vW, vH));
  end;
end;

end.
