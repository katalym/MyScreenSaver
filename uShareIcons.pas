unit uShareIcons;

{ Icons of the share buttons: e-mail, Telegram, WhatsApp, Facebook, copy image / full path / file name.
  They are drawn by the program in a 96 x 96 design space: every icon is painted 8 times bigger than it is
  shown and reduced, which gives smooth edges and a transparent background. The marks of the services are
  simplified drawings in their colors, not the official logos. }

interface

uses
  Vcl.Graphics;

const
  IconEmail = 0;
  IconTelegram = 1;
  IconWhatsApp = 2;
  IconFacebook = 3;
  IconCopyImage = 4;
  IconCopyPath = 5;
  IconCopyName = 6;
  IconSize = 16;

{ A new 16 x 16 bitmap (32-bit, with alpha) with the icon (IconEmail...) or an empty one for any other number;
  the caller frees it. For TBitBtn.Glyph. }
function CreateShareIcon(AIcon: Integer): TBitmap;

implementation

uses
  Winapi.Windows, System.SysUtils, System.Types;

const
  Big = 8;                       // the drawing is 8 times bigger than the icon
  Design = 96;                   // the size of the design space the coordinates below are given in
  KeyColor = clFuchsia;          // the transparent background of the big drawing

var
  GK: Double;                    // design space -> pixels of the big drawing

function V(AValue: Integer): Integer;
begin
  Result := Integer(Round(AValue * GK));
end;

function P(X, Y: Integer): TPoint;
begin
  Result := Point(V(X), V(Y));
end;

function NewDrawing: Vcl.Graphics.TBitmap;
var
  vSide: Integer;
begin
  vSide := IconSize * Big;
  GK := vSide / Design;
  Result := Vcl.Graphics.TBitmap.Create;
  Result.PixelFormat := pf24bit;
  Result.SetSize(vSide, vSide);
  Result.Canvas.Brush.Color := KeyColor;
  Result.Canvas.Pen.Color := KeyColor;
  Result.Canvas.FillRect(Rect(0, 0, vSide, vSide));
end;

procedure Disc(AC: TCanvas; AColor: TColor);
begin
  AC.Brush.Color := AColor;
  AC.Pen.Color := AColor;
  AC.Pen.Width := 1;
  AC.Ellipse(V(2), V(2), V(94), V(94));
end;

procedure Fill(AC: TCanvas; AColor: TColor);
begin
  AC.Brush.Style := bsSolid;
  AC.Brush.Color := AColor;
  AC.Pen.Color := AColor;
  AC.Pen.Width := 1;
end;

procedure Line(AC: TCanvas; AColor: TColor; AWidth: Integer);
begin
  AC.Pen.Style := psSolid;
  AC.Pen.Color := AColor;
  AC.Pen.Width := V(AWidth);
end;

procedure DrawEmail(AC: TCanvas);
begin
  Fill(AC, $A67F5B);               // #5B7FA6
  AC.RoundRect(V(4), V(18), V(92), V(78), V(12), V(12));
  Line(AC, clWhite, 6);
  AC.MoveTo(V(10), V(27));
  AC.LineTo(V(48), V(55));
  AC.LineTo(V(86), V(27));
end;

procedure DrawTelegram(AC: TCanvas);
begin
  Disc(AC, $EEAB2A);               // #2AABEE
  Fill(AC, clWhite);
  // the paper plane
  AC.Polygon([P(20, 47), P(76, 24), P(65, 72), P(47, 58), P(38, 70), P(36, 55)]);
  Line(AC, $EEAB2A, 3);
  AC.MoveTo(V(36), V(55));
  AC.LineTo(V(68), V(33));
end;

procedure DrawWhatsApp(AC: TCanvas);
begin
  Disc(AC, $66D325);               // #25D366
  AC.Brush.Style := bsClear;
  Line(AC, clWhite, 7);
  AC.Ellipse(V(21), V(19), V(77), V(75));      // the bubble
  Fill(AC, clWhite);
  AC.Polygon([P(22, 62), P(14, 84), P(38, 74)]);   // the tail
  Line(AC, clWhite, 9);                            // the handset
  AC.MoveTo(V(36), V(38));
  AC.LineTo(V(46), V(54));
  AC.LineTo(V(60), V(60));
end;

procedure DrawFacebook(AC: TCanvas);
var
  vRect: TRect;
begin
  Disc(AC, $F27718);               // #1877F2
  AC.Font.Name := 'Arial';
  AC.Font.Style := [fsBold];
  AC.Font.Height := -V(92);
  AC.Font.Color := clWhite;
  AC.Brush.Style := bsClear;
  vRect := Rect(V(14), V(6), V(102), V(102));
  DrawText(AC.Handle, 'f', 1, vRect, DT_CENTER or DT_SINGLELINE or DT_NOPREFIX);
end;

procedure DrawCopyImage(AC: TCanvas);
begin
  Fill(AC, $BF6B8E);               // #8E6BBF
  AC.RoundRect(V(6), V(14), V(90), V(82), V(14), V(14));
  Fill(AC, clWhite);
  AC.Ellipse(V(60), V(24), V(78), V(42));      // the sun
  AC.Polygon([P(12, 74), P(34, 44), P(50, 64), P(60, 54), P(84, 74)]);   // the mountains
end;

procedure DrawCopyPath(AC: TCanvas);
begin
  Fill(AC, $3BA9F2);               // #F2A93B: the folder
  AC.Polygon([P(6, 22), P(36, 22), P(44, 33), P(90, 33), P(90, 78), P(6, 78)]);
  Fill(AC, $66C5F7);               // the lighter front
  AC.Polygon([P(6, 44), P(90, 44), P(90, 78), P(6, 78)]);
end;

procedure DrawCopyName(AC: TCanvas);
begin
  Fill(AC, $8B7D60);               // #607D8B: the page
  AC.Polygon([P(20, 6), P(58, 6), P(78, 26), P(78, 90), P(20, 90)]);
  Fill(AC, $C4BEB0);               // the folded corner
  AC.Polygon([P(58, 6), P(78, 26), P(58, 26)]);
  Line(AC, clWhite, 5);            // the text
  AC.MoveTo(V(30), V(46));
  AC.LineTo(V(68), V(46));
  AC.MoveTo(V(30), V(60));
  AC.LineTo(V(68), V(60));
  AC.MoveTo(V(30), V(74));
  AC.LineTo(V(54), V(74));
end;

{ Reduces the drawing 8 times: the alpha is the share of the covered pixels, the color is the average
  color of the covered ones (not premultiplied). }
function Reduce(ADrawing: Vcl.Graphics.TBitmap): Vcl.Graphics.TBitmap;
var
  x, y, sx, sy, vCover, vR, vG, vB: Integer;
  vSrc: PByte;
  vDst: PRGBQuad;
begin
  Result := Vcl.Graphics.TBitmap.Create;
  Result.PixelFormat := pf32bit;
  Result.AlphaFormat := afDefined;
  Result.SetSize(IconSize, IconSize);
  for y := 0 to IconSize - 1 do
  begin
    vDst := Result.ScanLine[y];
    for x := 0 to IconSize - 1 do
    begin
      vCover := 0;
      vR := 0;
      vG := 0;
      vB := 0;
      for sy := 0 to Big - 1 do
      begin
        vSrc := ADrawing.ScanLine[y * Big + sy];
        Inc(vSrc, x * Big * 3);
        for sx := 0 to Big - 1 do
        begin
          // 24-bit pixels are stored as B, G, R; the key color (fuchsia) is R = 255, G = 0, B = 255
          if not ((vSrc[0] = 255) and (vSrc[1] = 0) and (vSrc[2] = 255)) then
          begin
            Inc(vCover);
            Inc(vB, vSrc[0]);
            Inc(vG, vSrc[1]);
            Inc(vR, vSrc[2]);
          end;
          Inc(vSrc, 3);
        end;
      end;
      if vCover > 0 then
      begin
        vDst^.rgbBlue := Byte(vB div vCover);
        vDst^.rgbGreen := Byte(vG div vCover);
        vDst^.rgbRed := Byte(vR div vCover);
      end
      else
      begin
        vDst^.rgbBlue := 0;
        vDst^.rgbGreen := 0;
        vDst^.rgbRed := 0;
      end;
      vDst^.rgbReserved := Byte((vCover * 255) div (Big * Big));
      Inc(vDst);
    end;
  end;
end;

function CreateShareIcon(AIcon: Integer): Vcl.Graphics.TBitmap;
var
  vDrawing: Vcl.Graphics.TBitmap;
begin
  vDrawing := NewDrawing;
  try
    case AIcon of
      IconEmail: DrawEmail(vDrawing.Canvas);
      IconTelegram: DrawTelegram(vDrawing.Canvas);
      IconWhatsApp: DrawWhatsApp(vDrawing.Canvas);
      IconFacebook: DrawFacebook(vDrawing.Canvas);
      IconCopyImage: DrawCopyImage(vDrawing.Canvas);
      IconCopyPath: DrawCopyPath(vDrawing.Canvas);
      IconCopyName: DrawCopyName(vDrawing.Canvas);
    end;   // any other number: an empty (transparent) icon
    Result := Reduce(vDrawing);
  finally
    vDrawing.Free;
  end;
end;

end.
