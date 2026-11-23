unit MyScreenSaver_ShareDialog;

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
    constructor CreateShare(AHost: TForm; const AFileName: string; AActions, ADisabled: TShareActions);
  end;

function ShareActionTitle(AAction: TShareAction): string;

{ Shows the dialog over AHost with the given actions (ADisabled: the ones that are shown but cannot be chosen now);
  True if one was chosen (AChosen). }
function ShowShareDialog(AHost: TForm; const AFileName: string; AActions, ADisabled: TShareActions;
  out AChosen: TShareAction): Boolean;

implementation

{$R *.DFM}

uses
  Winapi.Windows, System.SysUtils, System.Math, System.Classes, Vcl.Controls, Vcl.Buttons, Vcl.Graphics, MyScreenSaver_Lang, MyScreenSaver_Share, MyScreenSaver_ShareIcons;


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

{ The note to the right of the button of an action: what it does. Telegram, WhatsApp and Facebook cannot be given a
  file, so the file is copied to the clipboard and the user has to paste it. ADisabled: why it cannot be chosen. }
function ShareHintText(AAction: TShareAction; ADisabled: Boolean): string;
begin
  case AAction of
    saEmail:
      Result := L('Файл будет вложен в письмо (откроется ваша почтовая программа).',
        'The file will be attached to the e-mail (your mail program opens).');
    saTelegram:
      Result := L('Файл будет скопирован в буфер обмена. Вставьте его (Ctrl+V) в чат Telegram.',
        'The file will be copied to the clipboard. Paste it (Ctrl+V) into the Telegram chat.');
    saWhatsApp:
      Result := L('Файл будет скопирован в буфер обмена. Вставьте его (Ctrl+V) в чат WhatsApp.',
        'The file will be copied to the clipboard. Paste it (Ctrl+V) into the WhatsApp chat.');
    saFacebook:
      Result := L('Файл будет скопирован в буфер обмена. Вставьте его (Ctrl+V) в сообщение Facebook.',
        'The file will be copied to the clipboard. Paste it (Ctrl+V) into the Facebook message.');
    saCopyImage:
      if ADisabled then
        Result := L('Недоступно: сейчас показывается видео, а не фото.', 'Not available: a video is shown now, not a photo.')
      else
        Result := L('Изображение будет скопировано в буфер обмена.', 'The image will be copied to the clipboard.');
    saCopyPath:
      Result := L('Полный путь к файлу будет скопирован в буфер обмена как текст.',
        'The full path of the file will be copied to the clipboard as text.');
    saCopyName:
      Result := L('Имя файла (без папки) будет скопировано в буфер обмена как текст.',
        'The file name (without the folder) will be copied to the clipboard as text.');
  else
    Result := '';
  end;
end;

{ TShareForm }

constructor TShareForm.CreateShare(AHost: TForm; const AFileName: string; AActions, ADisabled: TShareActions);
const
  MaxNameW = 640; // the longest file name shown in full; a longer one is cut in the middle
  BtnW = 170;     // about half of the width the buttons had
  BtnGap = 8;
  SidePad = 16;
  HintGap = 12;   // between a button and its note
var
  vAction: TShareAction;
  vBtn: TBitBtn;
  vHint: TLabel;
  vIcon: Vcl.Graphics.TBitmap;
  vIconNo, vTop, vLeft, vHintW: Integer;
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
  // the dialog is as wide as its content: the file name (in full), or a button with the widest note, with equal margins
  vHintW := 0;
  Canvas.Font.Assign(Font);
  Canvas.Font.Size := 9;   // the size of the notes
  for vAction := Low(TShareAction) to High(TShareAction) do
    if vAction in AActions then
      vHintW := Max(vHintW, Canvas.TextWidth(ShareHintText(vAction, vAction in ADisabled)));
  Canvas.Font.Assign(Font);
  if vHintW > 0 then
    ClientWidth := Max(BtnW + HintGap + vHintW, Min(MaxNameW, Canvas.TextWidth(AFileName) + 4)) + 2 * SidePad
  else
    ClientWidth := Max(BtnW, Min(MaxNameW, Canvas.TextWidth(AFileName) + 4)) + 2 * SidePad;
  // with notes the buttons are in a column at the left (the notes are at their right), otherwise they are centered
  if vHintW > 0 then
    vLeft := SidePad
  else
    vLeft := (ClientWidth - BtnW) div 2;

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
      vBtn.Enabled := not (vAction in ADisabled);
      vBtn.SetBounds(vLeft, vTop, BtnW, vBtn.Height);   // the default height
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
      if ShareHintText(vAction, vAction in ADisabled) <> '' then
      begin
        vHint := TLabel.Create(Self);
        vHint.Parent := Self;
        vHint.Font.Size := 9;
        vHint.Font.Color := clBlack;
        vHint.Caption := ShareHintText(vAction, vAction in ADisabled);
        vHint.Left := vLeft + BtnW + HintGap;
        vHint.Top := vBtn.Top + (vBtn.Height - vHint.Height) div 2;
      end;
      if (ActiveControl = nil) and vBtn.Enabled then
        ActiveControl := vBtn;
      Inc(vTop, vBtn.Height + BtnGap);
    end;

  FCancel := TButton.Create(Self);
  FCancel.Parent := Self;
  FCancel.Caption := L('Отмена', 'Cancel');
  FCancel.ModalResult := mrCancel;
  FCancel.Cancel := True;
  FCancel.SetBounds(vLeft, vTop + 6, BtnW, FCancel.Height);   // the default height
  ClientHeight := FCancel.Top + FCancel.Height + 16;
end;

procedure TShareForm.ActionClick(Sender: TObject);
begin
  FChosen := TShareAction((Sender as TComponent).Tag);   // the buttons are TBitBtn: not a TButton
  FHasChosen := True;
  ModalResult := mrOk;
end;

function ShowShareDialog(AHost: TForm; const AFileName: string; AActions, ADisabled: TShareActions;
  out AChosen: TShareAction): Boolean;
var
  vForm: TShareForm;
begin
  AChosen := saCopyPath;
  vForm := TShareForm.CreateShare(AHost, AFileName, AActions, ADisabled);
  try
    Result := (vForm.ShowModal = mrOk) and vForm.FHasChosen;
    if Result then
      AChosen := vForm.FChosen;
  finally
    vForm.Free;
  end;
end;

end.
