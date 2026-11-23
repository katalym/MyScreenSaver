unit MyScreenSaver_InfoDialog;

{ The information dialog of the viewer (the key I): a window of its own with a caption, it can be moved to
  another monitor. The controls are designed in MyScreenSaver_InfoDialog.dfm; the viewer gives them the texts and the events
  and calls Arrange, which sizes the window to its content. }

interface

uses
  System.Classes, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Buttons;

type
  TInfoForm = class(TForm)
    memText: TMemo;
    bvlText: TBevel;
    lblCache: TLabel;
    btnOpenCache: TSpeedButton;
    btnClearShown: TSpeedButton;
    btnClearAll: TSpeedButton;
    bvlButtons: TBevel;
    btnShare: TButton;
    btnDelete: TButton;
    btnClose: TButton;
  public
    { Puts the text into the memo and sizes the window to its content (the captions and the fonts of the controls
      are set before). AMaxTextWidth: the widest the text may be, longer lines wrap. }
    procedure Arrange(const AText: string; AMaxTextWidth: Integer);
  end;

implementation

{$R *.DFM}

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Math, System.Types, Vcl.Graphics, Vcl.Menus;

procedure TInfoForm.Arrange(const AText: string; AMaxTextWidth: Integer);
const
  Pad = 0;         // the margins are the Padding of the form (AutoSize adds them)
  BtnGap = 4;       // between the buttons of the cache line
var
  vSl: TStringList;
  vMaxW, vHeight, vLineH, i, vContentW, vY, vOpenW, vShownW, vAllW, vShareW, vDeleteW, vCloseW: Integer;
  vRect: TRect;
begin
  // the memo cannot size itself to its text: its height comes from the lines (long ones wrap)
  Canvas.Font.Assign(memText.Font);
  vLineH := Canvas.TextHeight('Wg');
  vSl := TStringList.Create;
  try
    vSl.Text := AText.TrimRight;
    vMaxW := 0;
    for i := 0 to vSl.Count - 1 do
      vMaxW := Max(vMaxW, Canvas.TextWidth(vSl[i]));
    vMaxW := Min(vMaxW + 6, AMaxTextWidth);
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
  // the form and the label size themselves (AutoSize); the buttons have no AutoSize: their width is measured
  // from the captions (the & of a shortcut is not drawn)
  Canvas.Font.Assign(btnShare.Font);
  vShareW := Canvas.TextWidth(StripHotkey(btnShare.Caption)) + 44;
  vDeleteW := Canvas.TextWidth(StripHotkey(btnDelete.Caption)) + 44;
  vCloseW := Canvas.TextWidth(StripHotkey(btnClose.Caption)) + 44;
  Canvas.Font.Assign(btnOpenCache.Font);
  vOpenW := Canvas.TextWidth(btnOpenCache.Caption) + 20;
  vShownW := Canvas.TextWidth(btnClearShown.Caption) + 20;
  vAllW := Canvas.TextWidth(btnClearAll.Caption) + 20;
  vContentW := Max(Max(vMaxW, vShareW + 2 * vDeleteW + vCloseW + 48),
    lblCache.Width + 24 + vOpenW + vShownW + vAllW + 2 * BtnGap);

  memText.Text := AText.TrimRight;
  memText.SetBounds(Pad, Pad, vContentW, vHeight + 4);
  memText.HandleNeeded;
  memText.Perform(EM_SETMARGINS, EC_LEFTMARGIN or EC_RIGHTMARGIN, 0);
  bvlText.SetBounds(Pad, Pad + vHeight + 4 + 10, vContentW, 2);   // the information about the file | the cache
  lblCache.Left := Pad;
  lblCache.Top := bvlText.Top + 2 + 12;
  btnClearAll.SetBounds(Pad + vContentW - vAllW, lblCache.Top - 3, vAllW, lblCache.Height + 6);
  btnClearShown.SetBounds(btnClearAll.Left - BtnGap - vShownW, btnClearAll.Top, vShownW, btnClearAll.Height);
  btnOpenCache.SetBounds(btnClearShown.Left - BtnGap - vOpenW, btnClearAll.Top, vOpenW, btnClearAll.Height);
  bvlButtons.SetBounds(Pad, lblCache.Top + lblCache.Height + 12, vContentW, 2);   // the cache | the buttons
  vY := bvlButtons.Top + 2 + 14;
  btnShare.SetBounds(Pad, vY, vShareW, btnShare.Height);
  btnDelete.SetBounds(Pad + vShareW + vDeleteW, vY, vDeleteW, btnDelete.Height);   // a gap of its own width after Share
  btnClose.SetBounds(Pad + vContentW - vCloseW, vY, vCloseW, btnClose.Height);   // Close: the right edge
  AdjustSize;   // AutoSize of the form: it is as big as its controls (and Padding)
  memText.SelStart := 0;
  memText.SelLength := 0;
end;

end.
