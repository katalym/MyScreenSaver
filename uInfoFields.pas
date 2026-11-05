unit uInfoFields;

{ Fields of the information dialog (key I): which ones are shown is configurable. }

interface

{ Ids of the built-in fields in the order of the dialog }
function InfoFieldIds: TArray<string>;
function InfoFieldTitle(const AId: string): string;
{ Explanation shown as a hint in the settings; '' if the field needs none }
function InfoFieldHint(const AId: string): string;
{ True if the field is switched on (until the user changes the choice: the default set) }
function InfoFieldOn(const AId: string): Boolean;

implementation

uses
  System.SysUtils, uConfig, uLang;

function InfoFieldIds: TArray<string>;
begin
  Result := ['file', 'collection', 'location', 'size', 'created', 'modified', 'type', 'resolution',
    'duration', 'datefile', 'make', 'camera', 'lens', 'tagsxp', 'tagsiptc', 'datetaken', 'exposure',
    'aperture', 'iso', 'focal', 'gps', 'place'];
end;

function InfoFieldTitle(const AId: string): string;
begin
  if AId = 'file' then
    Result := L('Файл', 'File')
  else if AId = 'collection' then
    Result := L('Коллекция', 'Collection')
  else if AId = 'location' then
    Result := L('Расположение', 'Location')
  else if AId = 'size' then
    Result := L('Размер', 'Size')
  else if AId = 'created' then
    Result := L('Дата создания', 'Created')
  else if AId = 'modified' then
    Result := L('Дата изменения', 'Modified')
  else if AId = 'type' then
    Result := L('Тип', 'Type')
  else if AId = 'resolution' then
    Result := L('Разрешение', 'Resolution')
  else if AId = 'duration' then
    Result := L('Длительность', 'Duration')
  else if AId = 'datefile' then
    Result := L('Дата (файл)', 'Date (file)')
  else if AId = 'make' then
    Result := L('Производитель', 'Make')
  else if AId = 'camera' then
    Result := L('Камера', 'Camera')
  else if AId = 'lens' then
    Result := L('Объектив', 'Lens')
  else if AId = 'tagsxp' then
    Result := L('Теги (XP)', 'Tags (XP)')
  else if AId = 'tagsiptc' then
    Result := L('Теги (IPTC/XMP)', 'Tags (IPTC/XMP)')
  else if AId = 'datetaken' then
    Result := L('Дата съёмки', 'Date taken')
  else if AId = 'exposure' then
    Result := L('Выдержка', 'Exposure')
  else if AId = 'aperture' then
    Result := L('Диафрагма', 'Aperture')
  else if AId = 'iso' then
    Result := 'ISO'
  else if AId = 'focal' then
    Result := L('Фокусное расстояние', 'Focal length')
  else if AId = 'gps' then
    Result := 'GPS'
  else if AId = 'place' then
    Result := L('Место', 'Place')
  else
    Result := AId;
end;

function InfoFieldHint(const AId: string): string;
begin
  if AId = 'place' then
    Result := L('Определяется по GPS-координатам, нужен интернет', 'Detected from the GPS coordinates, needs the internet')
  else if AId = 'duration' then
    Result := L('Только для видео', 'Videos only')
  else if AId = 'datefile' then
    Result := L('Только для видео: дата файла', 'Videos only: the date of the file')
  else if AId = 'tagsxp' then
    Result := L('Свойство «Теги» файла в Проводнике Windows (EXIF XPKeywords)', 'The "Tags" property of the file in Windows Explorer (EXIF XPKeywords)')
  else if AId = 'tagsiptc' then
    Result := L('Ключевые слова IPTC и XMP (Lightroom, Photoshop и др.)', 'IPTC and XMP keywords (Lightroom, Photoshop, etc.)')
  else
    Result := '';
end;

{ The fields that are on by default }
function DefaultInfoFields: TArray<string>;
begin
  Result := ['file', 'collection', 'location', 'resolution', 'duration', 'tagsxp', 'tagsiptc',
    'datetaken', 'gps', 'place'];
end;

function InfoFieldOn(const AId: string): Boolean;
var
  vId: string;
begin
  if Settings.InfoFieldsConfigured then
    Exit(Settings.InfoFields.IndexOf(AId) >= 0);
  Result := False;
  for vId in DefaultInfoFields do
    if vId = AId then
      Exit(True);
end;

end.
