unit uInfoFieldsForm;

{ Dialog: which fields the information dialog (key I) shows, plus own EXIF tags. }

interface

{ Returns True if the choice was saved. }
function ShowInfoFieldsDialog: Boolean;

implementation

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.Types, System.Generics.Collections, Vcl.Controls, Vcl.Forms,
  Vcl.StdCtrls, Vcl.CheckLst, Vcl.Dialogs, uConfig, uLang, uInfoFields;

type
  TInfoFieldsForm = class(TForm)
  private
    FHint: TLabel;
    FList: TCheckListBox;
    FAdd: TButton;
    FRemove: TButton;
    FExamples: TLabel;
    FOk: TButton;
    FCancel: TButton;
    FIds: TArray<string>;
    FCustom: TList<TInfoCustomTag>;
    function AddButton(const ACaption: string; ALeft, ATop, AWidth: Integer; AClick: TNotifyEvent): TButton;
    procedure FillList;
    procedure ListMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure AddClick(Sender: TObject);
    procedure RemoveClick(Sender: TObject);
    procedure OkClick(Sender: TObject);
    procedure SyncCustomFlags;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

function CustomTitle(const ATag: TInfoCustomTag): string;
var
  vCaption: string;
begin
  vCaption := ATag.Caption;
  if vCaption = '' then
    vCaption := L('(свой EXIF-тег)', '(own EXIF tag)');
  Result := Format('0x%.4X — %s', [ATag.Tag, vCaption]);
end;

{ TInfoFieldsForm }

constructor TInfoFieldsForm.Create(AOwner: TComponent);
var
  i: Integer;
begin
  CreateNew(AOwner);
  Caption := L('Поля окна информации (I)', 'Information dialog fields (I)');
  BorderStyle := bsDialog;
  Position := poScreenCenter;
  ClientWidth := 560;
  ClientHeight := 548;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  FIds := InfoFieldIds;
  FCustom := TList<TInfoCustomTag>.Create;
  for i := 0 to Integer(Settings.CustomTags.Count) - 1 do
    FCustom.Add(Settings.CustomTags[i]);

  FHint := TLabel.Create(Self);
  FHint.Parent := Self;
  FHint.SetBounds(12, 10, 536, 15);
  FHint.Caption := L('Отмеченные поля показываются в окне информации (клавиша I):',
    'Checked fields are shown in the information dialog (key I):');

  FList := TCheckListBox.Create(Self);
  FList.Parent := Self;
  FList.SetBounds(12, 32, 536, 370);
  FList.ShowHint := True;
  FList.OnMouseMove := ListMouseMove;

  FAdd := AddButton(L('Добавить EXIF-тег...', 'Add EXIF tag...'), 12, 410, 190, AddClick);
  FRemove := AddButton(L('Удалить свой тег', 'Remove own tag'), 210, 410, 160, RemoveClick);

  FExamples := TLabel.Create(Self);
  FExamples.Parent := Self;
  FExamples.AutoSize := False;
  FExamples.WordWrap := True;
  FExamples.SetBounds(12, 446, 536, 48);
  FExamples.Caption := L(
    'Свой тег задаётся номером (0x010E описание, 0x013B автор, 0x0131 программа, 0x8298 авторские права, ' +
    '0x9286 комментарий, 0x9C9B XP-заголовок, 0x9C9C XP-комментарий).',
    'An own tag is given by its number (0x010E description, 0x013B artist, 0x0131 software, ' +
    '0x8298 copyright, 0x9286 user comment, 0x9C9B XP title, 0x9C9C XP comment).');

  FOk := AddButton(L('Сохранить', 'Save'), 360, 508, 90, OkClick);
  FOk.Default := True;
  FCancel := AddButton(L('Отмена', 'Cancel'), 458, 508, 90, nil);
  FCancel.ModalResult := mrCancel;
  FCancel.Cancel := True;
  FillList;
end;

destructor TInfoFieldsForm.Destroy;
begin
  FreeAndNil(FCustom);
  inherited;
end;

function TInfoFieldsForm.AddButton(const ACaption: string; ALeft, ATop, AWidth: Integer;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := Self;
  Result.Caption := ACaption;
  Result.SetBounds(ALeft, ATop, AWidth, 27);
  Result.OnClick := AClick;
end;

{ Hint of the field under the mouse (explanations are not part of the field titles). }
procedure TInfoFieldsForm.ListMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  vIdx: Integer;
  vHint: string;
begin
  vIdx := FList.ItemAtPos(Point(X, Y), True);
  if (vIdx >= 0) and (vIdx < Integer(Length(FIds))) then
    vHint := InfoFieldHint(FIds[vIdx])
  else
    vHint := '';
  if vHint <> FList.Hint then
  begin
    Application.CancelHint;
    FList.Hint := vHint;
  end;
  FList.ShowHint := vHint <> '';
end;

procedure TInfoFieldsForm.FillList;
var
  i, vBuiltin: Integer;
begin
  vBuiltin := Integer(Length(FIds));
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for i := 0 to vBuiltin - 1 do
    begin
      FList.Items.Add(InfoFieldTitle(FIds[i]));
      FList.Checked[i] := InfoFieldOn(FIds[i]);
    end;
    for i := 0 to Integer(FCustom.Count) - 1 do
    begin
      FList.Items.Add(CustomTitle(FCustom[i]));
      FList.Checked[vBuiltin + i] := FCustom[i].Enabled;
    end;
  finally
    FList.Items.EndUpdate;
  end;
end;

{ remembers the check marks of the own tags before the list is rebuilt }
procedure TInfoFieldsForm.SyncCustomFlags;
var
  i, vBuiltin: Integer;
  vTag: TInfoCustomTag;
begin
  vBuiltin := Integer(Length(FIds));
  for i := 0 to Integer(FCustom.Count) - 1 do
  begin
    vTag := FCustom[i];
    vTag.Enabled := FList.Checked[vBuiltin + i];
    FCustom[i] := vTag;
  end;
end;

procedure TInfoFieldsForm.AddClick(Sender: TObject);
var
  vValues: array of string;
  vTag: TInfoCustomTag;
  vNumber: Integer;
  vChecked: array of Boolean;
  i: Integer;
begin
  SetLength(vValues, 2);
  if not InputQuery(L('Добавить EXIF-тег', 'Add EXIF tag'),
    [L('Номер тега (например 0x9286 или 37510)', 'Tag number (for example 0x9286 or 37510)'),
     L('Название (необязательно)', 'Caption (optional)')], vValues) then
    Exit;
  if not ParseTagNumber(vValues[0], vNumber) then
  begin
    Application.MessageBox(PChar(L('Неверный номер тега.', 'Invalid tag number.')),
      PChar(Caption), MB_OK or MB_ICONWARNING);
    Exit;
  end;
  // keep the check marks of the built-in fields while the list is rebuilt
  SetLength(vChecked, Length(FIds));
  for i := 0 to Integer(High(FIds)) do
    vChecked[i] := FList.Checked[i];
  SyncCustomFlags;
  vTag.Tag := vNumber;
  vTag.Caption := Trim(StringReplace(vValues[1], '|', ' ', [rfReplaceAll]));
  vTag.Enabled := True;
  FCustom.Add(vTag);
  FillList;
  for i := 0 to Integer(High(FIds)) do
    FList.Checked[i] := vChecked[i];
  FList.ItemIndex := FList.Items.Count - 1;
end;

procedure TInfoFieldsForm.RemoveClick(Sender: TObject);
var
  vIdx, i: Integer;
  vChecked: array of Boolean;
begin
  vIdx := FList.ItemIndex - Integer(Length(FIds));
  if (vIdx < 0) or (vIdx >= FCustom.Count) then
  begin
    MessageBeep(MB_ICONASTERISK);   // only own tags can be removed; built-in fields are switched off
    Exit;
  end;
  SetLength(vChecked, Length(FIds));
  for i := 0 to Integer(High(FIds)) do
    vChecked[i] := FList.Checked[i];
  SyncCustomFlags;
  FCustom.Delete(vIdx);
  FillList;
  for i := 0 to Integer(High(FIds)) do
    FList.Checked[i] := vChecked[i];
end;

procedure TInfoFieldsForm.OkClick(Sender: TObject);
var
  i: Integer;
begin
  SyncCustomFlags;
  Settings.InfoFields.Clear;
  for i := 0 to Integer(High(FIds)) do
    if FList.Checked[i] then
      Settings.InfoFields.Add(FIds[i]);
  Settings.InfoFieldsConfigured := True;
  Settings.CustomTags.Clear;
  for i := 0 to Integer(FCustom.Count) - 1 do
    Settings.CustomTags.Add(FCustom[i]);
  Settings.Save;
  ModalResult := mrOk;
end;

function ShowInfoFieldsDialog: Boolean;
var
  vForm: TInfoFieldsForm;
begin
  vForm := TInfoFieldsForm.Create(nil);
  try
    Result := vForm.ShowModal = mrOk;
  finally
    vForm.Free;
  end;
end;

end.
