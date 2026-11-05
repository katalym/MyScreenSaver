unit uSettingsForm;

{ Settings dialog, built in code (no .dfm). Shown for /c or the C key. }

interface

{ Returns True if settings were changed and saved. }
function ShowSettingsDialog: Boolean;

implementation

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.Math, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls,
  Vcl.CheckLst, Vcl.Dialogs, uConfig, uRules, uLang;

type
  TSettingsForm = class(TForm)
  private
    FLangLabel: TLabel;
    FLang: TComboBox;
    FCollLabel: TLabel;
    FColl: TCheckListBox;
    FAddFolder: TButton;
    FAddUrl: TButton;
    FRemove: TButton;
    FSecondsLabel: TLabel;
    FSeconds: TEdit;
    FModeLabel: TLabel;
    FMode: TComboBox;
    FRulesLabel: TLabel;
    FRules: TCheckListBox;
    FDefaultLabel: TLabel;
    FDefault: TComboBox;
    FToleranceLabel: TLabel;
    FTolerance: TEdit;
    FHomeNameLabel: TLabel;
    FHomeName: TEdit;
    FGeoLabel: TLabel;
    FLat: TEdit;
    FLon: TEdit;
    FRadius: TEdit;
    FAuto: TCheckBox;
    FOk: TButton;
    FCancel: TButton;
    FRuleNames: TStringList;
    FItems: array of TMediaCollection;
    FOriginalLanguage: TLanguage;
    function AddLabel(ALeft, ATop: Integer): TLabel;
    function AddEdit(ALeft, ATop, AWidth: Integer): TEdit;
    function AddButton(ALeft, ATop, AWidth: Integer; AClick: TNotifyEvent): TButton;
    procedure ApplyTexts;
    procedure LangChange(Sender: TObject);
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
    property OriginalLanguage: TLanguage read FOriginalLanguage;
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
begin
  CreateNew(AOwner);
  FOriginalLanguage := CurrentLanguage;
  BorderStyle := bsDialog;
  Position := poScreenCenter;
  ClientWidth := 640;
  ClientHeight := 560;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  FRuleNames := TStringList.Create;
  GetRuleNames(FRuleNames);

  FCollLabel := AddLabel(12, 10);
  FLangLabel := AddLabel(330, 10);
  FLang := TComboBox.Create(Self);
  FLang.Parent := Self;
  FLang.Style := csDropDownList;
  FLang.SetBounds(440, 5, 188, 23);
  FLang.Items.Add('Русский (Russian)');
  FLang.Items.Add('English (Английский)');
  FLang.OnChange := LangChange;

  FColl := TCheckListBox.Create(Self);
  FColl.Parent := Self;
  FColl.SetBounds(12, 34, 616, 146);
  FAddFolder := AddButton(12, 186, 150, AddFolderClick);
  FAddUrl := AddButton(170, 186, 230, AddUrlClick);
  FRemove := AddButton(408, 186, 100, RemoveClick);

  FSecondsLabel := AddLabel(12, 228);
  FSeconds := AddEdit(240, 225, 60);

  FModeLabel := AddLabel(12, 258);
  FMode := TComboBox.Create(Self);
  FMode.Parent := Self;
  FMode.Style := csDropDownList;
  FMode.SetBounds(240, 255, 250, 23);

  FRulesLabel := AddLabel(12, 290);
  FRules := TCheckListBox.Create(Self);
  FRules.Parent := Self;
  FRules.SetBounds(12, 310, 616, 70);

  FDefaultLabel := AddLabel(12, 392);
  FDefault := TComboBox.Create(Self);
  FDefault.Parent := Self;
  FDefault.Style := csDropDownList;
  FDefault.SetBounds(240, 389, 250, 23);

  FToleranceLabel := AddLabel(12, 424);
  FTolerance := AddEdit(240, 421, 60);

  FHomeNameLabel := AddLabel(12, 456);
  FHomeName := AddEdit(240, 453, 250);
  FGeoLabel := AddLabel(12, 486);
  FLat := AddEdit(240, 483, 90);
  FLon := AddEdit(336, 483, 90);
  FRadius := AddEdit(432, 483, 58);
  FAuto := TCheckBox.Create(Self);
  FAuto.Parent := Self;
  FAuto.SetBounds(500, 455, 130, 40);
  FAuto.WordWrap := True;

  FOk := AddButton(440, 522, 90, OkClick);
  FOk.Default := True;
  FCancel := AddButton(538, 522, 90, nil);
  FCancel.ModalResult := mrCancel;
  FCancel.Cancel := True;
  Load;
end;

destructor TSettingsForm.Destroy;
begin
  FreeAndNil(FRuleNames);
  inherited;
end;

function TSettingsForm.AddLabel(ALeft, ATop: Integer): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := Self;
  Result.SetBounds(ALeft, ATop, 200, 15);
  Result.AutoSize := True;
end;

function TSettingsForm.AddEdit(ALeft, ATop, AWidth: Integer): TEdit;
begin
  Result := TEdit.Create(Self);
  Result.Parent := Self;
  Result.SetBounds(ALeft, ATop, AWidth, 23);
end;

function TSettingsForm.AddButton(ALeft, ATop, AWidth: Integer; AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := Self;
  Result.SetBounds(ALeft, ATop, AWidth, 27);
  Result.OnClick := AClick;
end;

{ (Re)sets all texts for the current language. }
procedure TSettingsForm.ApplyTexts;
var
  i, vModeIdx, vDefaultIdx: Integer;
  vChecked: array of Boolean;
begin
  Caption := L('MyScreenSaver — настройки', 'MyScreenSaver — settings');
  FLangLabel.Caption := 'Язык / Language:';
  FCollLabel.Caption := L('Медиаколлекции (отмеченные используются):', 'Media collections (checked are used):');
  FAddFolder.Caption := L('Добавить папку...', 'Add folder...');
  FAddUrl.Caption := L('Добавить адрес (UNC/HTTP/FTP)...', 'Add address (UNC/HTTP/FTP)...');
  FRemove.Caption := L('Удалить', 'Remove');
  FSecondsLabel.Caption := L('Время показа одного файла, сек:', 'Display time of one file, sec:');
  FModeLabel.Caption := L('Режим выбора:', 'Selection mode:');
  FRulesLabel.Caption := L('Активные правила (для режима "По правилам"):', 'Active rules (for the "By rules" mode):');
  FDefaultLabel.Caption := L('Правило по умолчанию:', 'Default rule:');
  FToleranceLabel.Caption := L('"В этот день": отклонение, дней (±):', '"On this day": tolerance, days (±):');
  FHomeNameLabel.Caption := L('Текущее место (название):', 'Current place (name):');
  FGeoLabel.Caption := L('Широта / долгота / радиус, км:', 'Latitude / longitude / radius, km:');
  FAuto.Caption := L('Определять место по IP', 'Detect place by IP');
  FOk.Caption := L('Сохранить', 'Save');
  FCancel.Caption := L('Отмена', 'Cancel');

  vModeIdx := FMode.ItemIndex;
  FMode.Items.Clear;
  FMode.Items.Add(L('Полностью случайный', 'Fully random'));
  FMode.Items.Add(L('По правилам', 'By rules'));
  FMode.ItemIndex := vModeIdx;

  SetLength(vChecked, FRules.Items.Count);
  for i := 0 to FRules.Items.Count - 1 do
    vChecked[i] := FRules.Checked[i];
  vDefaultIdx := FDefault.ItemIndex;
  FRules.Items.Clear;
  FDefault.Items.Clear;
  for i := 0 to FRuleNames.Count - 1 do
  begin
    FRules.Items.Add(RuleTitle(FRuleNames[i]));
    FDefault.Items.Add(RuleTitle(FRuleNames[i]));
  end;
  for i := 0 to Min(High(vChecked), FRules.Items.Count - 1) do
    FRules.Checked[i] := vChecked[i];
  FDefault.ItemIndex := vDefaultIdx;
end;

procedure TSettingsForm.LangChange(Sender: TObject);
begin
  // the dialog switches immediately; the choice is saved with "Save"
  SetLanguage(TLanguage(FLang.ItemIndex));
  ApplyTexts;
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
  if InputQuery(L('Добавить адрес', 'Add address'),
    [L('Адрес (\\server\share, http://..., ftp://...)', 'Address (\\server\share, http://..., ftp://...)'),
     L('Пользователь (необязательно)', 'User (optional)'),
     #31 + L('Пароль (необязательно)', 'Password (optional)')], vValues) then
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
  FLang.ItemIndex := Ord(CurrentLanguage);
  vIdx := FRuleNames.IndexOf(Settings.DefaultRule);
  if vIdx < 0 then
    vIdx := 0;
  ApplyTexts;
  FMode.ItemIndex := Ord(Settings.Mode);
  for i := 0 to FRuleNames.Count - 1 do
    FRules.Checked[i] := Settings.ActiveRules.IndexOf(FRuleNames[i]) >= 0;
  FDefault.ItemIndex := vIdx;
  FSeconds.Text := IntToStr(Settings.SlideSeconds);
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
  Settings.Language := TLanguage(FLang.ItemIndex);
  SetLanguage(Settings.Language);
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
    if not Result then
      SetLanguage(vForm.OriginalLanguage);   // cancelled: undo the language preview
  finally
    vForm.Free;
  end;
end;

end.
