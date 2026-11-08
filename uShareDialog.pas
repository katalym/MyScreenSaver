unit uShareDialog;

{ The share dialog: a small dialog in the middle of the viewer with a separate button for every action
  for the shown file: e-mail, Telegram, WhatsApp, Facebook, copy the image / the full path / the file name. }

interface

uses
  Vcl.Forms, Vcl.StdCtrls;

type
  TShareAction = (saEmail, saTelegram, saWhatsApp, saFacebook, saCopyImage, saCopyPath, saCopyName);
  TShareActions = set of TShareAction;

  TShareForm = class(TForm)
  private
    FName: TLabel;
    FCancel: TButton;
    FChosen: TShareAction;
    FHasChosen: Boolean;
    procedure ActionClick(Sender: TObject);
  public
    constructor CreateShare(AHost: TForm; const AFileName: string; AActions: TShareActions);
  end;

function ShareActionTitle(AAction: TShareAction): string;

{ Shows the dialog over AHost with the given actions; True if one was chosen (AChosen). }
function ShowShareDialog(AHost: TForm; const AFileName: string; AActions: TShareActions;
  out AChosen: TShareAction): Boolean;

implementation

{$R *.DFM}

uses
  Winapi.Windows, System.SysUtils, System.Math, System.Classes, Vcl.Controls, Vcl.Buttons, Vcl.Graphics, uLang, uShare, uShareIcons;


function ShareActionTitle(AAction: TShareAction): string;
begin
  case AAction of
    saEmail: Result := ShareTargetTitle(stEmail);
    saTelegram: Result := ShareTargetTitle(stTelegram);
    saWhatsApp: Result := ShareTargetTitle(stWhatsApp);
    saFacebook: Result := ShareTargetTitle(stFacebook);
    saCopyImage: Result := L('Копировать изображение', 'Copy image');
    saCopyPath: Result := L('Копировать полный путь', 'Copy full path');
  else
    Result := L('Копировать имя файла', 'Copy file name');
  end;
end;

{ TShareForm }

constructor TShareForm.CreateShare(AHost: TForm; const AFileName: string; AActions: TShareActions);
const
  MaxNameW = 640; // the longest file name shown in full; a longer one is cut in the middle
  BtnW = 170;     // about half of the width the buttons had
  BtnGap = 8;
  SidePad = 16;
var
  vAction: TShareAction;
  vBtn: TBitBtn;
  vIcon: Vcl.Graphics.TBitmap;
  vIconNo, vTop: Integer;
begin
  CreateNew(AHost);
  Caption := L('Поделиться', 'Share');
  BorderStyle := bsDialog;
  Position := poOwnerFormCenter;
  PopupParent := AHost;
  if (AHost <> nil) and (AHost.FormStyle = fsStayOnTop) then
    FormStyle := fsStayOnTop;   // above the full-screen screensaver
  Font.Name := 'Segoe UI';
  Font.Size := 10;
  // the dialog is as wide as its content: the file name (in full) or a button, with equal margins
  ClientWidth := Max(BtnW, Min(MaxNameW, Canvas.TextWidth(AFileName) + 4)) + 2 * SidePad;

  FName := TLabel.Create(Self);
  FName.Parent := Self;
  FName.AutoSize := False;
  FName.Alignment := taCenter;
  FName.EllipsisPosition := epPathEllipsis;
  FName.SetBounds(SidePad, 14, ClientWidth - 2 * SidePad, 18);
  FName.Caption := AFileName;

  // a separate button for every action; the buttons are centered in the dialog, the icon and the caption
  // are left aligned inside every button
  vTop := 44;
  for vAction := Low(TShareAction) to High(TShareAction) do
    if vAction in AActions then
    begin
      vBtn := TBitBtn.Create(Self);
      vBtn.Parent := Self;
      vBtn.Caption := ShareActionTitle(vAction);
      vBtn.Tag := Ord(vAction);
      vBtn.OnClick := ActionClick;
      vBtn.SetBounds((ClientWidth - BtnW) div 2, vTop, BtnW, vBtn.Height);   // the default height
      case vAction of
        saEmail: vIconNo := IconEmail;
        saTelegram: vIconNo := IconTelegram;
        saWhatsApp: vIconNo := IconWhatsApp;
        saFacebook: vIconNo := IconFacebook;
        saCopyImage: vIconNo := IconCopyImage;
        saCopyPath: vIconNo := IconCopyPath;
      else
        vIconNo := IconCopyName;
      end;
      vIcon := CreateShareIcon(vIconNo);
      try
        vBtn.Glyph.Assign(vIcon);
      finally
        vIcon.Free;
      end;
      vBtn.Layout := blGlyphLeft;
      vBtn.Margin := 8;        // the icon is at the left edge, the caption follows it
      vBtn.Spacing := 8;
      if ActiveControl = nil then
        ActiveControl := vBtn;
      Inc(vTop, vBtn.Height + BtnGap);
    end;

  FCancel := TButton.Create(Self);
  FCancel.Parent := Self;
  FCancel.Caption := L('Отмена', 'Cancel');
  FCancel.ModalResult := mrCancel;
  FCancel.Cancel := True;
  FCancel.SetBounds((ClientWidth - BtnW) div 2, vTop + 6, BtnW, FCancel.Height);   // the default height
  ClientHeight := FCancel.Top + FCancel.Height + 16;
end;

procedure TShareForm.ActionClick(Sender: TObject);
begin
  FChosen := TShareAction((Sender as TComponent).Tag);   // the buttons are TBitBtn: not a TButton
  FHasChosen := True;
  ModalResult := mrOk;
end;

function ShowShareDialog(AHost: TForm; const AFileName: string; AActions: TShareActions;
  out AChosen: TShareAction): Boolean;
var
  vForm: TShareForm;
begin
  AChosen := saCopyPath;
  vForm := TShareForm.CreateShare(AHost, AFileName, AActions);
  try
    Result := (vForm.ShowModal = mrOk) and vForm.FHasChosen;
    if Result then
      AChosen := vForm.FChosen;
  finally
    vForm.Free;
  end;
end;

end.
