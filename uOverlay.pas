unit uOverlay;

{ The overlay: a small semi-transparent window with text (selected fields of the current photo or video)
  that lies over the image. It is a separate top-level window owned by the viewer (a video is shown in
  a window of Windows Media Player, which a VCL control cannot cover), it never takes the focus and lets
  the mouse pass through to the viewer. }

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.Types, System.Math, Vcl.Controls, Vcl.Forms, Vcl.Graphics, uConfig;

type
  TOverlayWindow = class(TForm)
  private
    FHost: TForm;
    FText: string;
    FKeepOnTop: Boolean;
    FAlign: Integer;      // DT_LEFT, DT_CENTER or DT_RIGHT
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure Paint; override;
  public
    constructor CreateOverlay(AHost: TForm; AKeepOnTop: Boolean);
    { Shows the text at the position, in the font and the size of the settings }
    procedure ShowText(const AText: string);
    { Sizes and places the window again (the host was moved or resized) }
    procedure Refit;
    procedure HideOverlay;
    property Text: string read FText;
  end;

implementation

{$R *.DFM}

const
  Pad = 12;       // between the text and the border of the overlay
  Margin = 24;    // between the overlay and the border of the image

{ TOverlayWindow }

constructor TOverlayWindow.CreateOverlay(AHost: TForm; AKeepOnTop: Boolean);
begin
  FHost := AHost;
  FKeepOnTop := AKeepOnTop;
  CreateNew(AHost);
  BorderStyle := bsNone;
  Color := clBlack;
  AlphaBlend := True;
  AlphaBlendValue := 205;
  Visible := False;
end;

procedure TOverlayWindow.CreateParams(var Params: TCreateParams);
begin
  inherited CreateParams(Params);
  // owned by the viewer (always above it), no taskbar button, no activation, the mouse passes through
  Params.WndParent := FHost.Handle;
  Params.ExStyle := Params.ExStyle or WS_EX_TOOLWINDOW or WS_EX_NOACTIVATE or WS_EX_TRANSPARENT;
end;

procedure TOverlayWindow.ShowText(const AText: string);
var
  vRect: TRect;
  vMaxW, vX, vY, vW, vH, vPos: Integer;
  vOrigin: TPoint;
begin
  FText := AText;
  if (AText = '') or (FHost = nil) or not FHost.Visible or (FHost.WindowState = wsMinimized) then
  begin
    HideOverlay;
    Exit;
  end;
  vPos := Settings.OverlayPosition;
  case vPos mod 3 of
    0: FAlign := DT_LEFT;
    1: FAlign := DT_CENTER;
  else
    FAlign := DT_RIGHT;
  end;

  Canvas.Font.Name := Settings.OverlayFontName;
  Canvas.Font.Size := Settings.OverlayFontSize;
  Canvas.Font.Color := clWhite;
  // the size of the text (long lines wrap)
  vMaxW := Max(100, Integer(Round(FHost.ClientWidth * 0.8)) - 2 * Pad);
  vRect := Rect(0, 0, vMaxW, 0);
  DrawText(Canvas.Handle, PChar(FText), -1, vRect, DT_CALCRECT or DT_WORDBREAK or DT_NOPREFIX);
  vW := vRect.Right - vRect.Left + 2 * Pad;
  vH := vRect.Bottom - vRect.Top + 2 * Pad;

  // the position inside the client area of the viewer (3 x 3 places)
  vOrigin := FHost.ClientToScreen(Point(0, 0));
  case vPos mod 3 of
    0: vX := vOrigin.X + Margin;
    1: vX := vOrigin.X + (FHost.ClientWidth - vW) div 2;
  else
    vX := vOrigin.X + FHost.ClientWidth - vW - Margin;
  end;
  case vPos div 3 of
    0: vY := vOrigin.Y + Margin;
    1: vY := vOrigin.Y + (FHost.ClientHeight - vH) div 2;
  else
    vY := vOrigin.Y + FHost.ClientHeight - vH - Margin;
  end;

  HandleNeeded;
  SetWindowPos(Handle, 0, vX, vY, vW, vH, SWP_NOACTIVATE or SWP_NOZORDER);
  if FKeepOnTop then
    SetWindowPos(Handle, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOACTIVATE or SWP_NOMOVE or SWP_NOSIZE);
  ShowWindow(Handle, SW_SHOWNOACTIVATE);
  Invalidate;
end;

procedure TOverlayWindow.Refit;
begin
  if (FText <> '') and HandleAllocated and IsWindowVisible(Handle) then
    ShowText(FText);
end;

procedure TOverlayWindow.HideOverlay;
begin
  if HandleAllocated then
    ShowWindow(Handle, SW_HIDE);
end;

procedure TOverlayWindow.Paint;
var
  vRect: TRect;
begin
  Canvas.Brush.Color := clBlack;
  Canvas.FillRect(ClientRect);
  Canvas.Font.Name := Settings.OverlayFontName;
  Canvas.Font.Size := Settings.OverlayFontSize;
  Canvas.Font.Color := clWhite;
  SetBkMode(Canvas.Handle, TRANSPARENT);
  vRect := Rect(Pad, Pad, ClientWidth - Pad, ClientHeight - Pad);
  DrawText(Canvas.Handle, PChar(FText), -1, vRect, Cardinal(DT_WORDBREAK or DT_NOPREFIX or FAlign));
end;

end.
