unit uFiltersForm;

{ Dialog "Filters": silent videos, skipping of large videos, RAW files and excluded folders. }

interface

{ Returns True if the choice was saved. }
function ShowFiltersDialog: Boolean;

implementation

uses
  Winapi.Windows, System.SysUtils, System.Classes, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.Dialogs,
  uConfig, uLang;

type
  TFiltersForm = class(TForm)
  private
    FSilent: TCheckBox;
    FSkipLarge: TCheckBox;
    FNoRaw: TCheckBox;
    FFoldersLabel: TLabel;
    FFolders: TListBox;
    FAddFolder: TButton;
    FAddUrl: TButton;
    FRemove: TButton;
    FOk: TButton;
    FCancel: TButton;
    function AddCheck(const ACaption, AHint: string; ATop: Integer): TCheckBox;
    function AddButton(const ACaption: string; ALeft, ATop, AWidth: Integer; AClick: TNotifyEvent): TButton;
    procedure AddFolderClick(Sender: TObject);
    procedure AddUrlClick(Sender: TObject);
    procedure RemoveClick(Sender: TObject);
    procedure OkClick(Sender: TObject);
    procedure AddFolderPath(const APath: string);
  public
    constructor Create(AOwner: TComponent); override;
  end;

{ TFiltersForm }

constructor TFiltersForm.Create(AOwner: TComponent);
var
  i: Integer;
begin
  CreateNew(AOwner);
  Caption := L('Фильтры и воспроизведение', 'Filters and playback');
  BorderStyle := bsDialog;
  Position := poScreenCenter;
  ClientWidth := 560;
  ClientHeight := 450;
  Font.Name := 'Segoe UI';
  Font.Size := 9;

  FSilent := AddCheck(L('Воспроизводить видео без звука', 'Play videos silently (no sound)'),
    L('Звук видео выключен', 'The sound of videos is switched off'), 14);
  FSkipLarge := AddCheck(L('Пропускать видео, разрешение которого больше разрешения экрана',
    'Skip videos whose resolution exceeds the screen resolution'),
    L('Сравнивается число пикселей (ширина × высота) видео и экрана',
      'The number of pixels (width x height) of the video and of the screen is compared'), 42);
  FNoRaw := AddCheck(L('Исключить RAW-файлы (ARW, DNG, CR2, CR3, NEF, ORF, RAF, RW2 и др.)',
    'Exclude RAW files (ARW, DNG, CR2, CR3, NEF, ORF, RAF, RW2, etc.)'),
    L('Если снять флажок, RAW-файлы показываются, когда в Windows установлен их кодек',
      'If unchecked, RAW files are shown when their codec is installed in Windows'), 70);

  FFoldersLabel := TLabel.Create(Self);
  FFoldersLabel.Parent := Self;
  FFoldersLabel.SetBounds(16, 108, 528, 15);
  FFoldersLabel.Caption := L('Исключённые папки (файлы в них, включая подпапки, не показываются):',
    'Excluded folders (files in them, including subfolders, are not shown):');

  FFolders := TListBox.Create(Self);
  FFolders.Parent := Self;
  FFolders.SetBounds(16, 130, 528, 220);
  for i := 0 to Settings.ExcludedFolders.Count - 1 do
    FFolders.Items.Add(Settings.ExcludedFolders[i]);

  FAddFolder := AddButton(L('Добавить папку...', 'Add folder...'), 16, 358, 150, AddFolderClick);
  FAddUrl := AddButton(L('Добавить адрес...', 'Add address...'), 174, 358, 150, AddUrlClick);
  FRemove := AddButton(L('Удалить', 'Remove'), 332, 358, 100, RemoveClick);

  FOk := AddButton(L('Сохранить', 'Save'), 352, 408, 90, OkClick);
  FOk.Default := True;
  FCancel := AddButton(L('Отмена', 'Cancel'), 450, 408, 90, nil);
  FCancel.ModalResult := mrCancel;
  FCancel.Cancel := True;

  FSilent.Checked := Settings.SilentVideo;
  FSkipLarge.Checked := Settings.SkipLargeVideos;
  FNoRaw.Checked := Settings.ExcludeRaw;
end;

function TFiltersForm.AddCheck(const ACaption, AHint: string; ATop: Integer): TCheckBox;
begin
  Result := TCheckBox.Create(Self);
  Result.Parent := Self;
  Result.SetBounds(16, ATop, 528, 19);
  Result.Caption := ACaption;
  Result.Hint := AHint;
  Result.ShowHint := True;
end;

function TFiltersForm.AddButton(const ACaption: string; ALeft, ATop, AWidth: Integer;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := Self;
  Result.Caption := ACaption;
  Result.SetBounds(ALeft, ATop, AWidth, 27);
  Result.OnClick := AClick;
end;

procedure TFiltersForm.AddFolderPath(const APath: string);
var
  vPath: string;
begin
  vPath := Trim(APath);
  if vPath = '' then
    Exit;
  if FFolders.Items.IndexOf(vPath) < 0 then
    FFolders.Items.Add(vPath);
end;

procedure TFiltersForm.AddFolderClick(Sender: TObject);
var
  vDlg: TFileOpenDialog;
begin
  vDlg := TFileOpenDialog.Create(Self);
  try
    vDlg.Options := vDlg.Options + [fdoPickFolders];
    if vDlg.Execute then
      AddFolderPath(vDlg.FileName);
  finally
    vDlg.Free;
  end;
end;

procedure TFiltersForm.AddUrlClick(Sender: TObject);
var
  vValue: string;
begin
  vValue := '';
  if InputQuery(L('Исключить папку', 'Exclude a folder'),
    L('Адрес (\\server\share\folder, http://..., ftp://...)', 'Address (\\server\share\folder, http://..., ftp://...)'),
    vValue) then
    AddFolderPath(vValue);
end;

procedure TFiltersForm.RemoveClick(Sender: TObject);
begin
  if FFolders.ItemIndex >= 0 then
    FFolders.Items.Delete(FFolders.ItemIndex);
end;

procedure TFiltersForm.OkClick(Sender: TObject);
begin
  Settings.SilentVideo := FSilent.Checked;
  Settings.SkipLargeVideos := FSkipLarge.Checked;
  Settings.ExcludeRaw := FNoRaw.Checked;
  Settings.ExcludedFolders.Assign(FFolders.Items);
  Settings.Save;
  ModalResult := mrOk;
end;

function ShowFiltersDialog: Boolean;
var
  vForm: TFiltersForm;
begin
  vForm := TFiltersForm.Create(nil);
  try
    Result := vForm.ShowModal = mrOk;
  finally
    vForm.Free;
  end;
end;

end.
