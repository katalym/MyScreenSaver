unit uSettingsForm;

{ Settings dialog, built in code (no .dfm). Shown for /c or the C key. }

interface

{ Returns True if settings were changed and saved. }
function ShowSettingsDialog: Boolean;

implementation

uses
  Winapi.Windows, System.SysUtils, System.Classes, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls,
  Vcl.CheckLst, Vcl.Dialogs, uConfig, uRules;

type
  TSettingsForm = class(TForm)
  private
    FColl: TCheckListBox;
    FSeconds: TEdit;
    FMode: TComboBox;
    FRules: TCheckListBox;
    FDefault: TComboBox;
    FTolerance: TEdit;
    FHomeName: TEdit;
    FLat: TEdit;
    FLon: TEdit;
    FRadius: TEdit;
    FAuto: TCheckBox;
    FRuleNames: TStringList;
    FItems: array of TMediaCollection;
    function AddLabel(const ACaption: string; ALeft, ATop: Integer): TLabel;
    function AddEdit(ALeft, ATop, AWidth: Integer): TEdit;
    function AddButton(const ACaption: string; ALeft, ATop, AWidth: Integer;
      AClick: TNotifyEvent): TButton;
    procedure AddFolderClick(Sender: TObject);
    procedure AddUrlClick(Sender: TObject);
    procedure RemoveClick(Sender: TObject);
    procedure OkClick(Sender: TObject);
    procedure RefreshColl;
    procedure AppendColl(const ALocation: string; const AUser, APassword: string);
    procedure Load;
    procedure Apply;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

function F2S(AValue: Double): string;
begin
  Result := FloatToStr(AValue, TFormatSettings.Invariant);
end;

function S2F(const AText: string; ADefault: Double): Double;
begin
  Result := StrToFloatDef(StringReplace(Trim(AText), ',', '.', []), ADefault, TFormatSettings.Invariant);
end;

{ TSettingsForm }

constructor TSettingsForm.Create(AOwner: TComponent);
var
  i: Integer;
begin
  CreateNew(AOwner);
  Caption := 'MyScreenSaver — настройки';
  BorderStyle := bsDialog;
  Position := poScreenCenter;
  ClientWidth := 640;
  ClientHeight := 560;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  FRuleNames := TStringList.Create;
  GetRuleNames(FRuleNames);

  AddLabel('Медиаколлекции (отмеченные используются):', 12, 10);
  FColl := TCheckListBox.Create(Self);
  FColl.Parent := Self;
  FColl.SetBounds(12, 30, 616, 150);
  AddButton('Добавить папку...', 12, 186, 150, AddFolderClick);
  AddButton('Добавить адрес (UNC/HTTP/FTP)...', 170, 186, 230, AddUrlClick);
  AddButton('Удалить', 408, 186, 100, RemoveClick);

  AddLabel('Время показа одного файла, сек:', 12, 228);
  FSeconds := AddEdit(240, 225, 60);

  AddLabel('Режим выбора:', 12, 258);
  FMode := TComboBox.Create(Self);
  FMode.Parent := Self;
  FMode.Style := csDropDownList;
  FMode.SetBounds(240, 255, 250, 23);
  FMode.Items.Add('Полностью случайный');
  FMode.Items.Add('По правилам');

  AddLabel('Активные правила (для режима "По правилам"):', 12, 290);
  FRules := TCheckListBox.Create(Self);
  FRules.Parent := Self;
  FRules.SetBounds(12, 310, 616, 70);
  for i := 0 to FRuleNames.Count - 1 do
    FRules.Items.Add(RuleTitle(FRuleNames[i]));

  AddLabel('Правило по умолчанию:', 12, 392);
  FDefault := TComboBox.Create(Self);
  FDefault.Parent := Self;
  FDefault.Style := csDropDownList;
  FDefault.SetBounds(240, 389, 250, 23);
  for i := 0 to FRuleNames.Count - 1 do
    FDefault.Items.Add(RuleTitle(FRuleNames[i]));

  AddLabel('"В этот день": отклонение, дней (±):', 12, 424);
  FTolerance := AddEdit(240, 421, 60);

  AddLabel('Текущее место (название):', 12, 456);
  FHomeName := AddEdit(240, 453, 250);
  AddLabel('Широта / долгота / радиус, км:', 12, 486);
  FLat := AddEdit(240, 483, 90);
  FLon := AddEdit(336, 483, 90);
  FRadius := AddEdit(432, 483, 58);
  FAuto := TCheckBox.Create(Self);
  FAuto.Parent := Self;
  FAuto.SetBounds(500, 455, 130, 40);
  FAuto.Caption := 'Определять место по IP';
  FAuto.WordWrap := True;

  AddButton('Сохранить', 440, 522, 90, OkClick).Default := True;
  with AddButton('Отмена', 538, 522, 90, nil) do
  begin
    ModalResult := mrCancel;
    Cancel := True;
  end;
  Load;
end;

destructor TSettingsForm.Destroy;
begin
  FreeAndNil(FRuleNames);
  inherited;
end;

function TSettingsForm.AddLabel(const ACaption: string; ALeft, ATop: Integer): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := Self;
  Result.SetBounds(ALeft, ATop, 200, 15);
  Result.AutoSize := True;
  Result.Caption := ACaption;
end;

function TSettingsForm.AddEdit(ALeft, ATop, AWidth: Integer): TEdit;
begin
  Result := TEdit.Create(Self);
  Result.Parent := Self;
  Result.SetBounds(ALeft, ATop, AWidth, 23);
end;

function TSettingsForm.AddButton(const ACaption: string; ALeft, ATop, AWidth: Integer;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := Self;
  Result.Caption := ACaption;
  Result.SetBounds(ALeft, ATop, AWidth, 27);
  Result.OnClick := AClick;
end;

procedure TSettingsForm.RefreshColl;
var
  i: Integer;
begin
  FColl.Items.BeginUpdate;
  try
    FColl.Items.Clear;
    for i := 0 to High(FItems) do
    begin
      FColl.Items.Add(FItems[i].Location);
      FColl.Checked[i] := FItems[i].Enabled;
    end;
  finally
    FColl.Items.EndUpdate;
  end;
end;

procedure TSettingsForm.AppendColl(const ALocation, AUser, APassword: string);
var
  vColl: TMediaCollection;
begin
  vColl := Default(TMediaCollection);
  vColl.Location := ALocation;
  vColl.Name := ExtractFileName(ExcludeTrailingPathDelimiter(ALocation));
  if vColl.Name = '' then
    vColl.Name := ALocation;
  vColl.User := AUser;
  vColl.Password := APassword;
  vColl.Enabled := True;
  SetLength(FItems, Length(FItems) + 1);
  FItems[High(FItems)] := vColl;
  RefreshColl;
end;

procedure TSettingsForm.AddFolderClick(Sender: TObject);
var
  vDlg: TFileOpenDialog;
begin
  vDlg := TFileOpenDialog.Create(Self);
  try
    vDlg.Options := vDlg.Options + [fdoPickFolders];
    if vDlg.Execute then
      AppendColl(vDlg.FileName, '', '');
  finally
    vDlg.Free;
  end;
end;

procedure TSettingsForm.AddUrlClick(Sender: TObject);
var
  vValues: array of string;
begin
  SetLength(vValues, 3);
  if InputQuery('Добавить адрес',
    ['Адрес (\\server\share, http://..., ftp://...)', 'Пользователь (необязательно)',
     #31'Пароль (необязательно)'], vValues) then
    if Trim(vValues[0]) <> '' then
      AppendColl(Trim(vValues[0]), vValues[1], vValues[2]);
end;

procedure TSettingsForm.RemoveClick(Sender: TObject);
var
  i, vIdx: Integer;
begin
  vIdx := FColl.ItemIndex;
  if vIdx < 0 then
    Exit;
  for i := 0 to High(FItems) do
    FItems[i].Enabled := FColl.Checked[i];
  for i := vIdx to High(FItems) - 1 do
    FItems[i] := FItems[i + 1];
  SetLength(FItems, Length(FItems) - 1);
  RefreshColl;
end;

procedure TSettingsForm.Load;
var
  i, vIdx: Integer;
begin
  SetLength(FItems, Settings.Collections.Count);
  for i := 0 to Settings.Collections.Count - 1 do
    FItems[i] := Settings.Collections[i];
  RefreshColl;
  FSeconds.Text := IntToStr(Settings.SlideSeconds);
  FMode.ItemIndex := Ord(Settings.Mode);
  for i := 0 to FRuleNames.Count - 1 do
    FRules.Checked[i] := Settings.ActiveRules.IndexOf(FRuleNames[i]) >= 0;
  vIdx := FRuleNames.IndexOf(Settings.DefaultRule);
  if vIdx < 0 then
    vIdx := 0;
  FDefault.ItemIndex := vIdx;
  FTolerance.Text := IntToStr(Settings.DayTolerance);
  FHomeName.Text := Settings.HomeName;
  FLat.Text := F2S(Settings.HomeLat);
  FLon.Text := F2S(Settings.HomeLon);
  FRadius.Text := F2S(Settings.HomeRadiusKm);
  FAuto.Checked := Settings.AutoLocate;
end;

procedure TSettingsForm.Apply;
var
  i: Integer;
begin
  Settings.Collections.Clear;
  for i := 0 to High(FItems) do
  begin
    FItems[i].Enabled := FColl.Checked[i];
    Settings.Collections.Add(FItems[i]);
  end;
  Settings.SlideSeconds := StrToIntDef(FSeconds.Text, 10);
  if Settings.SlideSeconds < 1 then
    Settings.SlideSeconds := 1;
  Settings.Mode := TSelectionMode(FMode.ItemIndex);
  Settings.ActiveRules.Clear;
  for i := 0 to FRuleNames.Count - 1 do
    if FRules.Checked[i] then
      Settings.ActiveRules.Add(FRuleNames[i]);
  Settings.DefaultRule := FRuleNames[FDefault.ItemIndex];
  Settings.DayTolerance := StrToIntDef(FTolerance.Text, 0);
  Settings.HomeName := FHomeName.Text;
  Settings.HomeLat := S2F(FLat.Text, 0);
  Settings.HomeLon := S2F(FLon.Text, 0);
  Settings.HomeRadiusKm := S2F(FRadius.Text, 50);
  Settings.AutoLocate := FAuto.Checked;
  Settings.Save;
end;

procedure TSettingsForm.OkClick(Sender: TObject);
begin
  Apply;
  ModalResult := mrOk;
end;

function ShowSettingsDialog: Boolean;
var
  vForm: TSettingsForm;
begin
  vForm := TSettingsForm.Create(nil);
  try
    Result := vForm.ShowModal = mrOk;
  finally
    vForm.Free;
  end;
end;

end.
