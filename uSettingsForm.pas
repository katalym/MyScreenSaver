unit uSettingsForm;

{ The settings dialog: one form with tabs, built in code (no .dfm). Shown for /c or the C key.
  Tabs: media collections (+ excluded folders), file types (+ sound), play (slideshow), information,
  overlay (fields shown over the photo / video). }

interface

{ Returns True if the settings were changed and saved. }
function ShowSettingsDialog: Boolean;

implementation

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.Types, System.Math, System.Generics.Collections,
  Vcl.Controls, Vcl.Forms, Vcl.Graphics, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.CheckLst, Vcl.Dialogs,
  uConfig, uRules, uLang, uInfoFields, uVersion;

type
  TSettingsForm = class(TForm)
  private
    FLangLabel: TLabel;
    FLang: TComboBox;
    FPages: TPageControl;
    FTabColl: TTabSheet;
    FTabTypes: TTabSheet;
    FTabPlay: TTabSheet;
    FTabInfo: TTabSheet;
    FTabOverlay: TTabSheet;
    FOk: TButton;
    FCancel: TButton;
    // media collections
    FCollLabel: TLabel;
    FColl: TCheckListBox;
    FCollAddFolder: TButton;
    FCollAddUrl: TButton;
    FCollRemove: TButton;
    FExclLabel: TLabel;
    FExcl: TListBox;
    FExclAddFolder: TButton;
    FExclAddUrl: TButton;
    FExclRemove: TButton;
    // file types
    FGbShow: TGroupBox;
    FShowPhotos: TCheckBox;
    FShowVideos: TCheckBox;
    FGbVideo: TGroupBox;
    FSilent: TCheckBox;
    FSkipLarge: TCheckBox;
    FGbPhoto: TGroupBox;
    FNoRaw: TCheckBox;
    // play
    FSecondsLabel: TLabel;
    FSeconds: TEdit;
    FModeLabel: TLabel;
    FMode: TComboBox;
    FTransLabel: TLabel;
    FTransition: TComboBox;
    FTransMsLabel: TLabel;
    FTransMs: TEdit;
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
    // information dialog fields
    FInfoHint: TLabel;
    FFields: TCheckListBox;
    FFieldAdd: TButton;
    FFieldRemove: TButton;
    FFieldExamples: TLabel;
    // overlay
    FOverlayHint: TLabel;
    FOverlayFields: TCheckListBox;
    FOverlayPosLabel: TLabel;
    FOverlayPos: TComboBox;
    FOverlayFontLabel: TLabel;
    FOverlayFont: TComboBox;
    FOverlaySizeLabel: TLabel;
    FOverlaySize: TEdit;
    FOverlayNames: TCheckBox;
    FOverlayPanel: TPanel;
    FOverlaySample: TLabel;
    // data
    FRuleNames: TStringList;
    FItems: array of TMediaCollection;
    FFieldIds: TArray<string>;
    FCustom: TList<TInfoCustomTag>;
    FOriginalLanguage: TLanguage;
    function NewLabel(AParent: TWinControl; ALeft, ATop: Integer): TLabel;
    function NewEdit(AParent: TWinControl; ALeft, ATop, AWidth: Integer): TEdit;
    function NewCombo(AParent: TWinControl; ALeft, ATop, AWidth: Integer): TComboBox;
    function NewButton(AParent: TWinControl; ALeft, ATop, AWidth: Integer; AClick: TNotifyEvent): TButton;
    function NewCheck(AParent: TWinControl; ALeft, ATop, AWidth: Integer): TCheckBox;
    function NewGroup(AParent: TWinControl; ATop, AHeight: Integer): TGroupBox;
    procedure BuildCollectionsTab;
    procedure BuildTypesTab;
    procedure BuildPlayTab;
    procedure BuildInfoTab;
    procedure BuildOverlayTab;
    procedure ApplyTexts;
    procedure LangChange(Sender: TObject);
    procedure MediaClick(Sender: TObject);
    procedure OverlayFontChange(Sender: TObject);
    procedure AddCollFolderClick(Sender: TObject);
    procedure AddCollUrlClick(Sender: TObject);
    procedure RemoveCollClick(Sender: TObject);
    procedure AddExclFolderClick(Sender: TObject);
    procedure AddExclUrlClick(Sender: TObject);
    procedure RemoveExclClick(Sender: TObject);
    procedure AddFieldClick(Sender: TObject);
    procedure RemoveFieldClick(Sender: TObject);
    procedure FieldsMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure OkClick(Sender: TObject);
    procedure RefreshColl;
    procedure AppendColl(const ALocation, AUser, APassword: string);
    procedure AddExcluded(const APath: string);
    function PickFolders(APaths: TStrings): Boolean;
    function SnapshotList(AList: TCheckListBox): TArray<Boolean>;
    procedure RebuildList(AList: TCheckListBox; const AChecked: TArray<Boolean>; AOverlay, ADefault: Boolean);
    procedure RebuildFieldLists(const AInfoChecked, AOverlayChecked: TArray<Boolean>);
    procedure LoadValues;
    procedure ApplyValues;
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

function CustomTitle(const ATag: TInfoCustomTag): string;
var
  vCaption: string;
begin
  vCaption := ATag.Caption;
  if vCaption = '' then
    vCaption := L('(свой EXIF-тег)', '(own EXIF tag)');
  Result := Format('0x%.4X — %s', [ATag.Tag, vCaption]);
end;

{ TSettingsForm }

constructor TSettingsForm.Create(AOwner: TComponent);
begin
  CreateNew(AOwner);
  FOriginalLanguage := CurrentLanguage;
  BorderStyle := bsDialog;
  Position := poScreenCenter;
  ClientWidth := 660;
  ClientHeight := 612;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  FRuleNames := TStringList.Create;
  GetRuleNames(FRuleNames);
  FFieldIds := InfoFieldIds;
  FCustom := TList<TInfoCustomTag>.Create;

  FLangLabel := NewLabel(Self, 380, 14);
  FLang := NewCombo(Self, 480, 10, 172);
  FLang.Items.Add('Русский (Russian)');
  FLang.Items.Add('English (Английский)');
  FLang.OnChange := LangChange;

  FPages := TPageControl.Create(Self);
  FPages.Parent := Self;
  FPages.SetBounds(8, 42, 644, 520);
  FTabColl := TTabSheet.Create(Self);
  FTabColl.PageControl := FPages;
  FTabTypes := TTabSheet.Create(Self);
  FTabTypes.PageControl := FPages;
  FTabPlay := TTabSheet.Create(Self);
  FTabPlay.PageControl := FPages;
  FTabInfo := TTabSheet.Create(Self);
  FTabInfo.PageControl := FPages;
  FTabOverlay := TTabSheet.Create(Self);
  FTabOverlay.PageControl := FPages;
  BuildCollectionsTab;
  BuildTypesTab;
  BuildPlayTab;
  BuildInfoTab;
  BuildOverlayTab;

  FOk := NewButton(Self, 460, 574, 90, OkClick);
  FOk.Default := True;
  FCancel := NewButton(Self, 558, 574, 90, nil);
  FCancel.ModalResult := mrCancel;
  FCancel.Cancel := True;
  LoadValues;
end;

destructor TSettingsForm.Destroy;
begin
  FreeAndNil(FCustom);
  FreeAndNil(FRuleNames);
  inherited;
end;

{ ---- control factories ---- }

function TSettingsForm.NewLabel(AParent: TWinControl; ALeft, ATop: Integer): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(ALeft, ATop, 200, 15);
  Result.AutoSize := True;
end;

function TSettingsForm.NewEdit(AParent: TWinControl; ALeft, ATop, AWidth: Integer): TEdit;
begin
  Result := TEdit.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(ALeft, ATop, AWidth, 23);
end;

function TSettingsForm.NewCombo(AParent: TWinControl; ALeft, ATop, AWidth: Integer): TComboBox;
begin
  Result := TComboBox.Create(Self);
  Result.Parent := AParent;
  Result.Style := csDropDownList;
  Result.SetBounds(ALeft, ATop, AWidth, 23);
end;

function TSettingsForm.NewButton(AParent: TWinControl; ALeft, ATop, AWidth: Integer;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(ALeft, ATop, AWidth, 27);
  Result.OnClick := AClick;
end;

function TSettingsForm.NewCheck(AParent: TWinControl; ALeft, ATop, AWidth: Integer): TCheckBox;
begin
  Result := TCheckBox.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(ALeft, ATop, AWidth, 19);
end;

function TSettingsForm.NewGroup(AParent: TWinControl; ATop, AHeight: Integer): TGroupBox;
begin
  Result := TGroupBox.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(12, ATop, 612, AHeight);
end;

{ ---- tabs ---- }

procedure TSettingsForm.BuildCollectionsTab;
begin
  FCollLabel := NewLabel(FTabColl, 12, 10);
  FColl := TCheckListBox.Create(Self);
  FColl.Parent := FTabColl;
  FColl.SetBounds(12, 30, 612, 150);
  FCollAddFolder := NewButton(FTabColl, 12, 186, 150, AddCollFolderClick);
  FCollAddUrl := NewButton(FTabColl, 170, 186, 240, AddCollUrlClick);
  FCollRemove := NewButton(FTabColl, 418, 186, 100, RemoveCollClick);

  FExclLabel := NewLabel(FTabColl, 12, 236);
  FExcl := TListBox.Create(Self);
  FExcl.Parent := FTabColl;
  FExcl.SetBounds(12, 256, 612, 150);
  FExclAddFolder := NewButton(FTabColl, 12, 412, 150, AddExclFolderClick);
  FExclAddUrl := NewButton(FTabColl, 170, 412, 260, AddExclUrlClick);
  FExclRemove := NewButton(FTabColl, 438, 412, 100, RemoveExclClick);
end;

procedure TSettingsForm.BuildTypesTab;
begin
  FGbShow := NewGroup(FTabTypes, 12, 62);
  FShowPhotos := NewCheck(FGbShow, 16, 26, 280);
  FShowPhotos.OnClick := MediaClick;
  FShowVideos := NewCheck(FGbShow, 310, 26, 280);
  FShowVideos.OnClick := MediaClick;

  FGbVideo := NewGroup(FTabTypes, 86, 92);
  FSilent := NewCheck(FGbVideo, 16, 26, 580);
  FSkipLarge := NewCheck(FGbVideo, 16, 56, 580);
  FSkipLarge.ShowHint := True;

  FGbPhoto := NewGroup(FTabTypes, 190, 62);
  FNoRaw := NewCheck(FGbPhoto, 16, 26, 580);
  FNoRaw.ShowHint := True;
end;

procedure TSettingsForm.BuildPlayTab;
begin
  FSecondsLabel := NewLabel(FTabPlay, 12, 16);
  FSeconds := NewEdit(FTabPlay, 240, 13, 60);

  FModeLabel := NewLabel(FTabPlay, 12, 48);
  FMode := NewCombo(FTabPlay, 240, 45, 250);

  FTransLabel := NewLabel(FTabPlay, 12, 80);
  FTransition := NewCombo(FTabPlay, 240, 77, 165);
  FTransMsLabel := NewLabel(FTabPlay, 420, 80);
  FTransMs := NewEdit(FTabPlay, 540, 77, 60);

  FRulesLabel := NewLabel(FTabPlay, 12, 116);
  FRules := TCheckListBox.Create(Self);
  FRules.Parent := FTabPlay;
  FRules.SetBounds(12, 136, 612, 70);

  FDefaultLabel := NewLabel(FTabPlay, 12, 224);
  FDefault := NewCombo(FTabPlay, 240, 221, 250);

  FToleranceLabel := NewLabel(FTabPlay, 12, 258);
  FTolerance := NewEdit(FTabPlay, 240, 255, 60);

  FHomeNameLabel := NewLabel(FTabPlay, 12, 290);
  FHomeName := NewEdit(FTabPlay, 240, 287, 250);
  FGeoLabel := NewLabel(FTabPlay, 12, 322);
  FLat := NewEdit(FTabPlay, 240, 319, 90);
  FLon := NewEdit(FTabPlay, 336, 319, 90);
  FRadius := NewEdit(FTabPlay, 432, 319, 58);
  FAuto := NewCheck(FTabPlay, 500, 289, 128);
  FAuto.Height := 40;
  FAuto.WordWrap := True;
end;

procedure TSettingsForm.BuildInfoTab;
begin
  FInfoHint := NewLabel(FTabInfo, 12, 10);
  FFields := TCheckListBox.Create(Self);
  FFields.Parent := FTabInfo;
  FFields.SetBounds(12, 32, 612, 340);
  FFields.ShowHint := True;
  FFields.OnMouseMove := FieldsMouseMove;
  FFieldAdd := NewButton(FTabInfo, 12, 380, 200, AddFieldClick);
  FFieldRemove := NewButton(FTabInfo, 220, 380, 170, RemoveFieldClick);
  FFieldExamples := NewLabel(FTabInfo, 12, 418);
  FFieldExamples.AutoSize := False;
  FFieldExamples.WordWrap := True;
  FFieldExamples.SetBounds(12, 418, 612, 48);
end;

procedure TSettingsForm.BuildOverlayTab;
var
  vFonts: TStringList;
begin
  FOverlayHint := NewLabel(FTabOverlay, 12, 10);
  FOverlayFields := TCheckListBox.Create(Self);
  FOverlayFields.Parent := FTabOverlay;
  FOverlayFields.SetBounds(12, 32, 612, 250);
  FOverlayFields.ShowHint := True;
  FOverlayFields.OnMouseMove := FieldsMouseMove;

  FOverlayPosLabel := NewLabel(FTabOverlay, 12, 300);
  FOverlayPos := NewCombo(FTabOverlay, 100, 297, 220);
  FOverlayFontLabel := NewLabel(FTabOverlay, 12, 334);
  FOverlayFont := NewCombo(FTabOverlay, 100, 331, 250);
  vFonts := TStringList.Create;
  try
    vFonts.Assign(Screen.Fonts);
    vFonts.Sort;
    FOverlayFont.Items.Assign(vFonts);
  finally
    vFonts.Free;
  end;
  FOverlayFont.OnChange := OverlayFontChange;
  FOverlaySizeLabel := NewLabel(FTabOverlay, 370, 334);
  FOverlaySize := NewEdit(FTabOverlay, 450, 331, 44);
  FOverlaySize.OnChange := OverlayFontChange;
  FOverlayNames := NewCheck(FTabOverlay, 12, 368, 600);

  FOverlayPanel := TPanel.Create(Self);
  FOverlayPanel.Parent := FTabOverlay;
  FOverlayPanel.SetBounds(12, 400, 612, 76);
  FOverlayPanel.BevelOuter := bvLowered;
  FOverlayPanel.ParentBackground := False;
  FOverlayPanel.Color := clBlack;
  FOverlaySample := NewLabel(FOverlayPanel, 14, 14);
  FOverlaySample.Font.Color := clWhite;
  FOverlaySample.Transparent := True;
end;

{ (Re)sets all texts for the current language. }
procedure TSettingsForm.ApplyTexts;
var
  i, vModeIdx, vDefaultIdx, vTransIdx, vPosIdx: Integer;
  vChecked: array of Boolean;
begin
  Caption := Trim('MyScreenSaver ' + AppVersion) + L(' — настройки', ' — settings');
  FLangLabel.Caption := 'Язык / Language:';
  FOk.Caption := L('Сохранить', 'Save');
  FCancel.Caption := L('Отмена', 'Cancel');
  FTabColl.Caption := L('Медиаколлекции', 'Media collections');
  FTabTypes.Caption := L('Типы файлов', 'File types');
  FTabPlay.Caption := L('Показ', 'Play');
  FTabInfo.Caption := L('Информация', 'Information');
  FTabOverlay.Caption := L('Наложение', 'Overlay');

  // media collections
  FCollLabel.Caption := L('Медиаколлекции (отмеченные используются):', 'Media collections (checked are used):');
  FCollAddFolder.Caption := L('Добавить папки...', 'Add folders...');
  FCollAddUrl.Caption := L('Добавить адрес (UNC/HTTP/FTP)...', 'Add address (UNC/HTTP/FTP)...');
  FCollRemove.Caption := L('Удалить', 'Remove');
  FExclLabel.Caption := L('Исключённые папки и подпапки (файлы в них не показываются):',
    'Excluded folders and subfolders (files in them are not shown):');
  FExclAddFolder.Caption := L('Исключить папки...', 'Exclude folders...');
  FExclAddUrl.Caption := L('Исключить адрес (UNC/HTTP/FTP)...', 'Exclude address (UNC/HTTP/FTP)...');
  FExclRemove.Caption := L('Удалить', 'Remove');

  // file types
  FGbShow.Caption := L('Что показывать', 'What to show');
  FShowPhotos.Caption := L('Показывать фото', 'Show photos');
  FShowVideos.Caption := L('Показывать видео', 'Show videos');
  FGbVideo.Caption := L('Видео', 'Videos');
  FSilent.Caption := L('Воспроизводить видео без звука', 'Play videos silently (no sound)');
  FSkipLarge.Caption := L('Пропускать видео, разрешение которого больше разрешения экрана',
    'Skip videos whose resolution exceeds the screen resolution');
  FSkipLarge.Hint := L('Сравнивается число пикселей (ширина × высота) видео и экрана',
    'The number of pixels (width x height) of the video and of the screen is compared');
  FGbPhoto.Caption := L('Фото', 'Photos');
  FNoRaw.Caption := L('Исключить RAW-файлы (ARW, DNG, CR2, CR3, NEF, ORF, RAF, RW2 и др.)',
    'Exclude RAW files (ARW, DNG, CR2, CR3, NEF, ORF, RAF, RW2, etc.)');
  FNoRaw.Hint := L('Если снять флажок, RAW-файлы показываются, когда в Windows установлен их кодек',
    'If unchecked, RAW files are shown when their codec is installed in Windows');

  // play
  FSecondsLabel.Caption := L('Время показа одного файла, сек:', 'Display time of one file, sec:');
  FModeLabel.Caption := L('Режим выбора:', 'Selection mode:');
  FTransLabel.Caption := L('Переход между слайдами:', 'Slide transition:');
  FTransMsLabel.Caption := L('Длительность, мс:', 'Duration, ms:');
  FRulesLabel.Caption := L('Активные правила (для режима "По правилам"):', 'Active rules (for the "By rules" mode):');
  FDefaultLabel.Caption := L('Правило по умолчанию:', 'Default rule:');
  FToleranceLabel.Caption := L('"В этот день": отклонение, дней (±):', '"On this day": tolerance, days (±):');
  FHomeNameLabel.Caption := L('Текущее место (название):', 'Current place (name):');
  FGeoLabel.Caption := L('Широта / долгота / радиус, км:', 'Latitude / longitude / radius, km:');
  FAuto.Caption := L('Определять место по IP', 'Detect place by IP');

  vModeIdx := FMode.ItemIndex;
  FMode.Items.Clear;
  FMode.Items.Add(L('Полностью случайный', 'Fully random'));
  FMode.Items.Add(L('По правилам', 'By rules'));
  FMode.ItemIndex := vModeIdx;

  vTransIdx := FTransition.ItemIndex;
  FTransition.Items.Clear;
  FTransition.Items.Add(L('Нет', 'None'));
  FTransition.Items.Add(L('Плавное затухание', 'Cross-fade'));
  FTransition.Items.Add(L('Через чёрное', 'Fade through black'));
  FTransition.Items.Add(L('Сдвиг', 'Slide'));
  FTransition.Items.Add(L('Шторка', 'Wipe'));
  FTransition.Items.Add(L('Случайный', 'Random'));
  FTransition.ItemIndex := vTransIdx;

  SetLength(vChecked, FRules.Items.Count);
  for i := 0 to Integer(FRules.Items.Count) - 1 do
    vChecked[i] := FRules.Checked[i];
  vDefaultIdx := FDefault.ItemIndex;
  FRules.Items.Clear;
  FDefault.Items.Clear;
  for i := 0 to Integer(FRuleNames.Count) - 1 do
  begin
    FRules.Items.Add(RuleTitle(FRuleNames[i]));
    FDefault.Items.Add(RuleTitle(FRuleNames[i]));
  end;
  for i := 0 to Min(Integer(High(vChecked)), Integer(FRules.Items.Count) - 1) do
    FRules.Checked[i] := vChecked[i];
  FDefault.ItemIndex := vDefaultIdx;

  // information
  FInfoHint.Caption := L('Отмеченные поля показываются в окне информации (клавиша I):',
    'Checked fields are shown in the information dialog (key I):');
  FFieldAdd.Caption := L('Добавить EXIF-тег...', 'Add EXIF tag...');
  FFieldRemove.Caption := L('Удалить свой тег', 'Remove own tag');
  FFieldExamples.Caption := L(
    'Свой тег задаётся номером (0x010E описание, 0x013B автор, 0x0131 программа, 0x8298 авторские права, ' +
    '0x9286 комментарий, 0x9C9B XP-заголовок, 0x9C9C XP-комментарий). Свои теги видны и на вкладке "Наложение".',
    'An own tag is given by its number (0x010E description, 0x013B artist, 0x0131 software, ' +
    '0x8298 copyright, 0x9286 user comment, 0x9C9B XP title, 0x9C9C XP comment). Own tags are also listed ' +
    'on the "Overlay" tab.');

  // overlay
  FOverlayHint.Caption := L('Отмеченные поля показываются поверх фото и видео:',
    'Checked fields are shown over the photos and videos:');
  FOverlayPosLabel.Caption := L('Положение:', 'Position:');
  FOverlayFontLabel.Caption := L('Шрифт:', 'Font:');
  FOverlaySizeLabel.Caption := L('Размер, пт:', 'Size, pt:');
  FOverlayNames.Caption := L('Показывать названия полей («Название: значение»)', 'Show the field names ("Name: value")');
  FOverlaySample.Caption := L('Пример: 2021-12-09 · Торонто', 'Sample: 2021-12-09 · Toronto');
  vPosIdx := FOverlayPos.ItemIndex;
  FOverlayPos.Items.Clear;
  FOverlayPos.Items.Add(L('Сверху слева', 'Top left'));
  FOverlayPos.Items.Add(L('Сверху по центру', 'Top center'));
  FOverlayPos.Items.Add(L('Сверху справа', 'Top right'));
  FOverlayPos.Items.Add(L('Посередине слева', 'Middle left'));
  FOverlayPos.Items.Add(L('По центру', 'Center'));
  FOverlayPos.Items.Add(L('Посередине справа', 'Middle right'));
  FOverlayPos.Items.Add(L('Снизу слева', 'Bottom left'));
  FOverlayPos.Items.Add(L('Снизу по центру', 'Bottom center'));
  FOverlayPos.Items.Add(L('Снизу справа', 'Bottom right'));
  FOverlayPos.ItemIndex := vPosIdx;

  if FFields.Items.Count > 0 then
    RebuildFieldLists(SnapshotList(FFields), SnapshotList(FOverlayFields));
end;

procedure TSettingsForm.LangChange(Sender: TObject);
begin
  // the dialog switches immediately; the choice is saved with "Save"
  SetLanguage(TLanguage(FLang.ItemIndex));
  ApplyTexts;
end;

{ At least one of "photos" / "videos" must always stay checked. }
procedure TSettingsForm.MediaClick(Sender: TObject);
begin
  if not FShowPhotos.Checked and not FShowVideos.Checked then
    (Sender as TCheckBox).Checked := True;
end;

{ The sample shows the chosen font and size (a large size is shown smaller to fit). }
procedure TSettingsForm.OverlayFontChange(Sender: TObject);
begin
  if FOverlayFont.ItemIndex >= 0 then
    FOverlaySample.Font.Name := FOverlayFont.Text;
  FOverlaySample.Font.Size := Max(8, Min(24, StrToIntDef(FOverlaySize.Text, 10)));
end;

{ ---- collections and excluded folders ---- }

{ The folder dialog of Windows with the multiple selection: any number of folders can be chosen at once. }
function TSettingsForm.PickFolders(APaths: TStrings): Boolean;
var
  vDlg: TFileOpenDialog;
begin
  vDlg := TFileOpenDialog.Create(Self);
  try
    vDlg.Options := vDlg.Options + [fdoPickFolders, fdoAllowMultiSelect];
    Result := vDlg.Execute;
    if Result then
      APaths.Assign(vDlg.Files);
  finally
    vDlg.Free;
  end;
end;

procedure TSettingsForm.RefreshColl;
var
  i: Integer;
begin
  FColl.Items.BeginUpdate;
  try
    FColl.Items.Clear;
    for i := 0 to Integer(High(FItems)) do
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
  i: Integer;
begin
  // keep the check marks of the collections that are already in the list
  for i := 0 to Integer(High(FItems)) do
    FItems[i].Enabled := FColl.Checked[i];
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

procedure TSettingsForm.AddCollFolderClick(Sender: TObject);
var
  vPaths: TStringList;
  i: Integer;
begin
  vPaths := TStringList.Create;
  try
    if PickFolders(vPaths) then
      for i := 0 to Integer(vPaths.Count) - 1 do
        if Trim(vPaths[i]) <> '' then
          AppendColl(vPaths[i], '', '');
  finally
    vPaths.Free;
  end;
end;

procedure TSettingsForm.AddCollUrlClick(Sender: TObject);
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

procedure TSettingsForm.RemoveCollClick(Sender: TObject);
var
  i, vIdx: Integer;
begin
  vIdx := FColl.ItemIndex;
  if vIdx < 0 then
    Exit;
  for i := 0 to Integer(High(FItems)) do
    FItems[i].Enabled := FColl.Checked[i];
  for i := vIdx to Integer(High(FItems)) - 1 do
    FItems[i] := FItems[i + 1];
  SetLength(FItems, Length(FItems) - 1);
  RefreshColl;
end;

procedure TSettingsForm.AddExcluded(const APath: string);
var
  vPath: string;
begin
  vPath := Trim(APath);
  if (vPath <> '') and (FExcl.Items.IndexOf(vPath) < 0) then
    FExcl.Items.Add(vPath);
end;

procedure TSettingsForm.AddExclFolderClick(Sender: TObject);
var
  vPaths: TStringList;
  i: Integer;
begin
  vPaths := TStringList.Create;
  try
    if PickFolders(vPaths) then
      for i := 0 to Integer(vPaths.Count) - 1 do
        AddExcluded(vPaths[i]);
  finally
    vPaths.Free;
  end;
end;

procedure TSettingsForm.AddExclUrlClick(Sender: TObject);
var
  vValue: string;
begin
  vValue := '';
  if InputQuery(L('Исключить папку', 'Exclude a folder'),
    L('Адрес (\\server\share\folder, http://..., ftp://...)', 'Address (\\server\share\folder, http://..., ftp://...)'),
    vValue) then
    AddExcluded(vValue);
end;

procedure TSettingsForm.RemoveExclClick(Sender: TObject);
begin
  if FExcl.ItemIndex >= 0 then
    FExcl.Items.Delete(FExcl.ItemIndex);
end;

{ ---- the field lists of the "Information" and the "Overlay" tabs (the same fields, own check marks) ---- }

{ Check marks of all items (built-in fields first, then own tags). }
function TSettingsForm.SnapshotList(AList: TCheckListBox): TArray<Boolean>;
var
  i: Integer;
begin
  SetLength(Result, AList.Items.Count);
  for i := 0 to Integer(AList.Items.Count) - 1 do
    Result[i] := AList.Checked[i];
end;

{ Rebuilds one list in the current language; AChecked gives the marks, for the missing ones ADefault is used.
  The marks of the own tags are kept in FCustom (Enabled: information, Overlay: overlay). }
procedure TSettingsForm.RebuildList(AList: TCheckListBox; const AChecked: TArray<Boolean>; AOverlay, ADefault: Boolean);
var
  i, vBuiltin, vTop: Integer;
  vOn: Boolean;
  vTag: TInfoCustomTag;
begin
  vBuiltin := Integer(Length(FFieldIds));
  vTop := AList.TopIndex;
  AList.Items.BeginUpdate;
  try
    AList.Items.Clear;
    for i := 0 to vBuiltin - 1 do
      AList.Items.Add(InfoFieldTitle(FFieldIds[i]));
    for i := 0 to Integer(FCustom.Count) - 1 do
      AList.Items.Add(CustomTitle(FCustom[i]));
    for i := 0 to Integer(AList.Items.Count) - 1 do
    begin
      if i < Integer(Length(AChecked)) then
        vOn := AChecked[i]
      else
        vOn := ADefault;
      AList.Checked[i] := vOn;
      if i >= vBuiltin then
      begin
        vTag := FCustom[i - vBuiltin];
        if AOverlay then
          vTag.Overlay := vOn
        else
          vTag.Enabled := vOn;
        FCustom[i - vBuiltin] := vTag;
      end;
    end;
  finally
    AList.Items.EndUpdate;
  end;
  if (vTop >= 0) and (vTop < AList.Items.Count) then
    AList.TopIndex := vTop;
end;

procedure TSettingsForm.RebuildFieldLists(const AInfoChecked, AOverlayChecked: TArray<Boolean>);
begin
  RebuildList(FFields, AInfoChecked, False, True);           // a new own tag is shown in the information dialog
  RebuildList(FOverlayFields, AOverlayChecked, True, False); // and is not shown over the image until it is checked
end;

procedure TSettingsForm.AddFieldClick(Sender: TObject);
var
  vValues: array of string;
  vTag: TInfoCustomTag;
  vNumber: Integer;
  vInfo, vOverlay: TArray<Boolean>;
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
  vInfo := SnapshotList(FFields);
  vOverlay := SnapshotList(FOverlayFields);
  vTag.Tag := vNumber;
  vTag.Caption := Trim(StringReplace(vValues[1], '|', ' ', [rfReplaceAll]));
  vTag.Enabled := True;
  vTag.Overlay := False;
  FCustom.Add(vTag);
  RebuildFieldLists(vInfo, vOverlay);
  FFields.ItemIndex := FFields.Items.Count - 1;
end;

procedure TSettingsForm.RemoveFieldClick(Sender: TObject);
var
  vIdx, vBuiltin: Integer;
  vInfo, vOverlay: TArray<Boolean>;
begin
  vBuiltin := Integer(Length(FFieldIds));
  vIdx := FFields.ItemIndex - vBuiltin;
  if (vIdx < 0) or (vIdx >= Integer(FCustom.Count)) then
  begin
    MessageBeep(MB_ICONASTERISK);   // only own tags can be removed; built-in fields are switched off
    Exit;
  end;
  vInfo := SnapshotList(FFields);
  vOverlay := SnapshotList(FOverlayFields);
  Delete(vInfo, vBuiltin + vIdx, 1);
  Delete(vOverlay, vBuiltin + vIdx, 1);
  FCustom.Delete(vIdx);
  RebuildFieldLists(vInfo, vOverlay);
end;

{ Hint of the field under the mouse (explanations are not part of the field titles). }
procedure TSettingsForm.FieldsMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  vList: TCheckListBox;
  vIdx: Integer;
  vHint: string;
begin
  vList := Sender as TCheckListBox;
  vIdx := vList.ItemAtPos(Point(X, Y), True);
  if (vIdx >= 0) and (vIdx < Integer(Length(FFieldIds))) then
    vHint := InfoFieldHint(FFieldIds[vIdx])
  else
    vHint := '';
  if vHint <> vList.Hint then
  begin
    Application.CancelHint;
    vList.Hint := vHint;
  end;
  vList.ShowHint := vHint <> '';
end;

{ ---- values ---- }

procedure TSettingsForm.LoadValues;
var
  i, vIdx: Integer;
  vInfo, vOverlay: TArray<Boolean>;
begin
  // collections
  SetLength(FItems, Settings.Collections.Count);
  for i := 0 to Integer(Settings.Collections.Count) - 1 do
    FItems[i] := Settings.Collections[i];
  RefreshColl;
  FExcl.Items.Clear;
  for i := 0 to Integer(Settings.ExcludedFolders.Count) - 1 do
    FExcl.Items.Add(Settings.ExcludedFolders[i]);

  // own EXIF tags (the marks of the field lists are set below)
  FCustom.Clear;
  for i := 0 to Integer(Settings.CustomTags.Count) - 1 do
    FCustom.Add(Settings.CustomTags[i]);

  FLang.ItemIndex := Ord(CurrentLanguage);
  vIdx := FRuleNames.IndexOf(Settings.DefaultRule);
  if vIdx < 0 then
    vIdx := 0;
  ApplyTexts;
  FMode.ItemIndex := Ord(Settings.Mode);
  FTransition.ItemIndex := Ord(Settings.Transition);
  FTransMs.Text := IntToStr(Settings.TransitionMs);
  FShowPhotos.Checked := Settings.MediaTypes in [mtPhotos, mtBoth];
  FShowVideos.Checked := Settings.MediaTypes in [mtVideos, mtBoth];
  FSilent.Checked := Settings.SilentVideo;
  FSkipLarge.Checked := Settings.SkipLargeVideos;
  FNoRaw.Checked := Settings.ExcludeRaw;
  for i := 0 to Integer(FRuleNames.Count) - 1 do
    FRules.Checked[i] := Settings.ActiveRules.IndexOf(FRuleNames[i]) >= 0;
  FDefault.ItemIndex := vIdx;
  FSeconds.Text := IntToStr(Settings.SlideSeconds);
  FTolerance.Text := IntToStr(Settings.DayTolerance);
  FHomeName.Text := Settings.HomeName;
  FLat.Text := F2S(Settings.HomeLat);
  FLon.Text := F2S(Settings.HomeLon);
  FRadius.Text := F2S(Settings.HomeRadiusKm);
  FAuto.Checked := Settings.AutoLocate;

  // overlay
  FOverlayPos.ItemIndex := Max(0, Min(8, Settings.OverlayPosition));
  FOverlayFont.ItemIndex := FOverlayFont.Items.IndexOf(Settings.OverlayFontName);
  if FOverlayFont.ItemIndex < 0 then
    FOverlayFont.ItemIndex := FOverlayFont.Items.IndexOf('Segoe UI');
  FOverlaySize.Text := IntToStr(Settings.OverlayFontSize);
  FOverlayNames.Checked := Settings.OverlayShowNames;
  OverlayFontChange(nil);

  // marks of the field lists
  SetLength(vInfo, Length(FFieldIds) + Integer(FCustom.Count));
  SetLength(vOverlay, Length(vInfo));
  for i := 0 to Integer(Length(FFieldIds)) - 1 do
  begin
    vInfo[i] := InfoFieldOn(FFieldIds[i]);
    vOverlay[i] := OverlayFieldOn(FFieldIds[i]);
  end;
  for i := 0 to Integer(FCustom.Count) - 1 do
  begin
    vInfo[Integer(Length(FFieldIds)) + i] := FCustom[i].Enabled;
    vOverlay[Integer(Length(FFieldIds)) + i] := FCustom[i].Overlay;
  end;
  RebuildFieldLists(vInfo, vOverlay);
end;

procedure TSettingsForm.ApplyValues;
var
  i: Integer;
begin
  Settings.Language := TLanguage(FLang.ItemIndex);
  SetLanguage(Settings.Language);

  // collections
  Settings.Collections.Clear;
  for i := 0 to Integer(High(FItems)) do
  begin
    FItems[i].Enabled := FColl.Checked[i];
    Settings.Collections.Add(FItems[i]);
  end;
  Settings.ExcludedFolders.Assign(FExcl.Items);

  // file types
  if FShowPhotos.Checked and FShowVideos.Checked then
    Settings.MediaTypes := mtBoth
  else if FShowVideos.Checked then
    Settings.MediaTypes := mtVideos
  else
    Settings.MediaTypes := mtPhotos;
  Settings.SilentVideo := FSilent.Checked;
  Settings.SkipLargeVideos := FSkipLarge.Checked;
  Settings.ExcludeRaw := FNoRaw.Checked;

  // play
  Settings.SlideSeconds := Max(1, StrToIntDef(FSeconds.Text, 10));
  Settings.Mode := TSelectionMode(FMode.ItemIndex);
  Settings.Transition := TTransitionEffect(FTransition.ItemIndex);
  Settings.TransitionMs := Max(100, Min(3000, StrToIntDef(FTransMs.Text, 800)));
  Settings.ActiveRules.Clear;
  for i := 0 to Integer(FRuleNames.Count) - 1 do
    if FRules.Checked[i] then
      Settings.ActiveRules.Add(FRuleNames[i]);
  Settings.DefaultRule := FRuleNames[FDefault.ItemIndex];
  Settings.DayTolerance := StrToIntDef(FTolerance.Text, 0);
  Settings.HomeName := FHomeName.Text;
  Settings.HomeLat := S2F(FLat.Text, 0);
  Settings.HomeLon := S2F(FLon.Text, 0);
  Settings.HomeRadiusKm := S2F(FRadius.Text, 50);
  Settings.AutoLocate := FAuto.Checked;

  // information dialog fields and overlay fields (the marks of the own tags: FCustom)
  Settings.InfoFields.Clear;
  Settings.OverlayFields.Clear;
  for i := 0 to Integer(Length(FFieldIds)) - 1 do
  begin
    if FFields.Checked[i] then
      Settings.InfoFields.Add(FFieldIds[i]);
    if FOverlayFields.Checked[i] then
      Settings.OverlayFields.Add(FFieldIds[i]);
  end;
  Settings.InfoFieldsConfigured := True;
  Settings.CustomTags.Clear;
  for i := 0 to Integer(FCustom.Count) - 1 do
    Settings.CustomTags.Add(FCustom[i]);

  // overlay look
  Settings.OverlayPosition := Max(0, FOverlayPos.ItemIndex);
  if FOverlayFont.ItemIndex >= 0 then
    Settings.OverlayFontName := FOverlayFont.Text;
  Settings.OverlayFontSize := Max(8, Min(96, StrToIntDef(FOverlaySize.Text, 10)));
  Settings.OverlayShowNames := FOverlayNames.Checked;

  Settings.Save;
end;

procedure TSettingsForm.OkClick(Sender: TObject);
begin
  ApplyValues;
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
