unit uConfig;

{ Application settings stored in an INI file (no database). }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, uLang;

type
  TSourceKind = (skLocal, skNetwork, skHttp, skFtp);

  TMediaCollection = record
    Name: string;
    Location: string;
    User: string;
    Password: string;
    Enabled: Boolean;
    function Kind: TSourceKind;
  end;

  { effect between two slides }
  TTransitionEffect = (teNone, teFade, teFadeBlack, teSlide, teWipe, teRandom);

  { what to show: photos only, videos only, both }
  TMediaTypes = (mtPhotos, mtVideos, mtBoth);

  { an own EXIF tag shown in the information dialog }
  TInfoCustomTag = record
    Tag: Integer;
    Caption: string;
    Enabled: Boolean;         // shown in the information dialog
    Overlay: Boolean;         // shown over the photo / video
  end;

  TAppSettings = class
  public
    Collections: TList<TMediaCollection>;
    SlideSeconds: Integer;
    MediaTypes: TMediaTypes;
    Transition: TTransitionEffect;
    TransitionMs: Integer;           // duration of the transition, milliseconds
    SilentVideo: Boolean;            // play videos without sound (default: yes)
    SkipLargeVideos: Boolean;        // skip videos with more pixels than the screen has
    ExcludeRaw: Boolean;             // do not show RAW files (ARW, DNG, ...)
    ExcludedFolders: TStringList;    // folders (with subfolders) that are not shown
    ActiveRules: TStringList;
    InfoFields: TStringList;          // enabled built-in fields of the information dialog (key I)
    InfoFieldsConfigured: Boolean;    // False: all fields are shown (default)
    CustomTags: TList<TInfoCustomTag>;
    OverlayFields: TStringList;       // built-in fields shown over the photo / video (own tags: CustomTags[].Overlay)
    OverlayPosition: Integer;         // 0..8: 3 x 3 places, row by row from the top left
    InfoFontName: string;             // the font of the text of the information window (key I)
    InfoFontSize: Integer;            // points
    OverlayFontName: string;
    OverlayFontSize: Integer;         // points
    OverlayShowNames: Boolean;        // "Caption: value" instead of the value only
    DayTolerance: Integer;       // "on this day": +/- days
    HomeName: string;
    HomeLat: Double;
    HomeLon: Double;
    HomeRadiusKm: Double;
    AutoLocate: Boolean;         // detect location by IP (off by default)
    Language: TLanguage;         // user interface language (also used for place names)
    // runtime location (set by auto-detection)
    CurLat: Double;
    CurLon: Double;
    CurValid: Boolean;
    constructor Create;
    destructor Destroy; override;
    class function ConfigPath: string;
    procedure Load;
    procedure Save;
  end;

function Settings: TAppSettings;
{ '0x9286', '$9286' or '37510' -> tag number }
function ParseTagNumber(const AText: string; out ATag: Integer): Boolean;

implementation

uses
  System.IniFiles, System.IOUtils, System.Math;

const
  { names of the effects in the INI file, in the order of TTransitionEffect }
  TransitionNames: array[TTransitionEffect] of string = ('none', 'fade', 'black', 'slide', 'wipe', 'random');

  { places of the overlay, row by row from the top left }
  OverlayPositionNames: array[0..8] of string =
    ('topleft', 'topcenter', 'topright', 'middleleft', 'center', 'middleright', 'bottomleft', 'bottomcenter',
     'bottomright');

var
  GSettings: TAppSettings;

function Settings: TAppSettings;
begin
  if GSettings = nil then
  begin
    GSettings := TAppSettings.Create;
    GSettings.Load;
  end;
  Result := GSettings;
end;

function ParseTagNumber(const AText: string; out ATag: Integer): Boolean;
var
  vText: string;
begin
  vText := Trim(AText);
  if vText.StartsWith('0x', True) then
    vText := '$' + vText.Substring(2);
  Result := TryStrToInt(vText, ATag) and (ATag > 0) and (ATag <= $FFFF);
end;

function ReadFloat(AIni: TMemIniFile; const ASection, AKey: string; ADefault: Double): Double;
begin
  Result := StrToFloatDef(AIni.ReadString(ASection, AKey, ''), ADefault, TFormatSettings.Invariant);
end;

{ TMediaCollection }

function TMediaCollection.Kind: TSourceKind;
var
  vLoc: string;
begin
  vLoc := LowerCase(Trim(Location));
  if vLoc.StartsWith('http://') or vLoc.StartsWith('https://') then
    Result := skHttp
  else if vLoc.StartsWith('ftp://') then
    Result := skFtp
  else if vLoc.StartsWith('\\') then
    Result := skNetwork
  else
    Result := skLocal;
end;

{ TAppSettings }

constructor TAppSettings.Create;
begin
  inherited Create;
  Collections := TList<TMediaCollection>.Create;
  ActiveRules := TStringList.Create;
  InfoFields := TStringList.Create;
  ExcludedFolders := TStringList.Create;
  OverlayFields := TStringList.Create;
  CustomTags := TList<TInfoCustomTag>.Create;
  SlideSeconds := 4;
  ActiveRules.Add('random');
  MediaTypes := mtBoth;
  Transition := teFade;
  TransitionMs := 800;
  SilentVideo := True;
  SkipLargeVideos := True;
  ExcludeRaw := True;
  OverlayFields.Add('file');   // by default the file name is shown over the image, bottom right
  OverlayPosition := 8;
  InfoFontName := 'Consolas';
  InfoFontSize := 11;
  OverlayFontName := 'Segoe UI';
  OverlayFontSize := 10;
  OverlayShowNames := False;
  DayTolerance := 0;
  HomeRadiusKm := 50;
  AutoLocate := False;
  Language := DefaultLanguage;
  SetLanguage(Language);
end;

destructor TAppSettings.Destroy;
begin
  FreeAndNil(OverlayFields);
  FreeAndNil(ExcludedFolders);
  FreeAndNil(CustomTags);
  FreeAndNil(InfoFields);
  FreeAndNil(ActiveRules);
  FreeAndNil(Collections);
  inherited;
end;

class function TAppSettings.ConfigPath: string;
begin
  Result := TPath.Combine(TPath.GetHomePath, 'MyScreenSaver');
  ForceDirectories(Result);
  Result := TPath.Combine(Result, 'MyScreenSaver.ini');
end;

procedure TAppSettings.Load;
var
  vIni: TMemIniFile;
  vColl: TMediaCollection;
  vCount, i: Integer;
  vSec: string;
  vParts: TArray<string>;
  vTag: TInfoCustomTag;
  vNumber: Integer;
  vName: string;
  vEffect: TTransitionEffect;
begin
  if not FileExists(ConfigPath) then
    Exit;
  vIni := TMemIniFile.Create(ConfigPath, TEncoding.UTF8);
  try
    SlideSeconds := vIni.ReadInteger('General', 'SlideSeconds', SlideSeconds);
    if SlideSeconds < 1 then
      SlideSeconds := 1;
    vName := LowerCase(vIni.ReadString('General', 'Transition', 'fade'));
    Transition := teFade;
    for vEffect := Low(TTransitionEffect) to High(TTransitionEffect) do
      if vName = TransitionNames[vEffect] then
        Transition := vEffect;
    TransitionMs := Max(100, Min(3000, vIni.ReadInteger('General', 'TransitionMs', 800)));
    SilentVideo := vIni.ReadBool('General', 'SilentVideo', True);
    SkipLargeVideos := vIni.ReadBool('General', 'SkipLargeVideos', True);
    ExcludeRaw := vIni.ReadBool('General', 'ExcludeRaw', True);
    ExcludedFolders.Clear;
    vCount := vIni.ReadInteger('Exclude', 'Count', 0);
    for i := 1 to vCount do
      if vIni.ReadString('Exclude', 'Folder' + IntToStr(i), '') <> '' then
        ExcludedFolders.Add(vIni.ReadString('Exclude', 'Folder' + IntToStr(i), ''));
    if vIni.ValueExists('Overlay', 'Fields') then
      OverlayFields.CommaText := vIni.ReadString('Overlay', 'Fields', '');
    vName := LowerCase(vIni.ReadString('Overlay', 'Position', 'bottomright'));
    OverlayPosition := 8;
    for i := 0 to High(OverlayPositionNames) do
      if vName = OverlayPositionNames[i] then
        OverlayPosition := i;
    InfoFontName := vIni.ReadString('Info', 'FontName', InfoFontName);
    InfoFontSize := Max(8, Min(48, vIni.ReadInteger('Info', 'FontSize', InfoFontSize)));
    OverlayFontName := vIni.ReadString('Overlay', 'FontName', OverlayFontName);
    OverlayFontSize := Max(8, Min(96, vIni.ReadInteger('Overlay', 'FontSize', 10)));
    OverlayShowNames := vIni.ReadBool('Overlay', 'ShowNames', False);
    if SameText(vIni.ReadString('General', 'MediaTypes', 'both'), 'photos') then
      MediaTypes := mtPhotos
    else if SameText(vIni.ReadString('General', 'MediaTypes', 'both'), 'videos') then
      MediaTypes := mtVideos
    else
      MediaTypes := mtBoth;
    ActiveRules.CommaText := vIni.ReadString('General', 'ActiveRules', 'random');
    // the removed "Mode=random" setting of old files meant: no rules, only random files
    if SameText(vIni.ReadString('General', 'Mode', 'rules'), 'random') then
      ActiveRules.CommaText := 'random';
    while ActiveRules.Count > 1 do
      ActiveRules.Delete(ActiveRules.Count - 1);   // only one rule is active
    if ActiveRules.Count = 0 then
      ActiveRules.Add('random');

    DayTolerance := vIni.ReadInteger('Rules', 'DayTolerance', DayTolerance);
    HomeName := vIni.ReadString('Rules', 'HomeName', '');
    HomeLat := ReadFloat(vIni, 'Rules', 'HomeLat', 0);
    HomeLon := ReadFloat(vIni, 'Rules', 'HomeLon', 0);
    HomeRadiusKm := ReadFloat(vIni, 'Rules', 'HomeRadiusKm', HomeRadiusKm);
    AutoLocate := vIni.ReadBool('Rules', 'AutoLocate', False);
    Language := LanguageFromCode(vIni.ReadString('General', 'Language', ''), DefaultLanguage);
    SetLanguage(Language);

    InfoFieldsConfigured := vIni.ValueExists('Info', 'Fields');
    InfoFields.Clear;
    if InfoFieldsConfigured then
      InfoFields.CommaText := vIni.ReadString('Info', 'Fields', '');
    CustomTags.Clear;
    vCount := vIni.ReadInteger('Info', 'CustomCount', 0);
    for i := 1 to vCount do
    begin
      // Custom1=0x9286|Caption|1
      vParts := vIni.ReadString('Info', 'Custom' + IntToStr(i), '').Split(['|']);
      if (Length(vParts) >= 1) and ParseTagNumber(vParts[0], vNumber) then
      begin
        vTag.Tag := vNumber;
        if Length(vParts) >= 2 then
          vTag.Caption := vParts[1]
        else
          vTag.Caption := '';
        vTag.Enabled := (Length(vParts) < 3) or (vParts[2] <> '0');
        vTag.Overlay := (Length(vParts) >= 4) and (vParts[3] = '1');
        CustomTags.Add(vTag);
      end;
    end;

    Collections.Clear;
    vCount := vIni.ReadInteger('Collections', 'Count', 0);
    for i := 1 to vCount do
    begin
      vSec := 'Collection' + IntToStr(i);
      vColl := Default(TMediaCollection);
      vColl.Name := vIni.ReadString(vSec, 'Name', '');
      vColl.Location := vIni.ReadString(vSec, 'Location', '');
      vColl.User := vIni.ReadString(vSec, 'User', '');
      vColl.Password := vIni.ReadString(vSec, 'Password', '');
      vColl.Enabled := vIni.ReadBool(vSec, 'Enabled', True);
      if vColl.Location <> '' then
        Collections.Add(vColl);
    end;
  finally
    vIni.Free;
  end;
end;

procedure TAppSettings.Save;
var
  vIni: TMemIniFile;
  vColl: TMediaCollection;
  i: Integer;
  vSec: string;
begin
  if FileExists(ConfigPath) then
    TFile.Delete(ConfigPath);
  vIni := TMemIniFile.Create(ConfigPath, TEncoding.UTF8);
  try
    vIni.WriteInteger('General', 'SlideSeconds', SlideSeconds);
    vIni.WriteString('General', 'Transition', TransitionNames[Transition]);
    vIni.WriteInteger('General', 'TransitionMs', TransitionMs);
    vIni.WriteBool('General', 'SilentVideo', SilentVideo);
    vIni.WriteBool('General', 'SkipLargeVideos', SkipLargeVideos);
    vIni.WriteBool('General', 'ExcludeRaw', ExcludeRaw);
    vIni.WriteInteger('Exclude', 'Count', Integer(ExcludedFolders.Count));
    for i := 0 to Integer(ExcludedFolders.Count) - 1 do
      vIni.WriteString('Exclude', 'Folder' + IntToStr(i + 1), ExcludedFolders[i]);
    vIni.WriteString('Overlay', 'Fields', OverlayFields.CommaText);
    vIni.WriteString('Overlay', 'Position', OverlayPositionNames[Max(0, Min(8, OverlayPosition))]);
    vIni.WriteString('Info', 'FontName', InfoFontName);
    vIni.WriteInteger('Info', 'FontSize', InfoFontSize);
    vIni.WriteString('Overlay', 'FontName', OverlayFontName);
    vIni.WriteInteger('Overlay', 'FontSize', OverlayFontSize);
    vIni.WriteBool('Overlay', 'ShowNames', OverlayShowNames);
    case MediaTypes of
      mtPhotos: vIni.WriteString('General', 'MediaTypes', 'photos');
      mtVideos: vIni.WriteString('General', 'MediaTypes', 'videos');
    else
      vIni.WriteString('General', 'MediaTypes', 'both');
    end;
    vIni.WriteString('General', 'Language', LanguageCode(Language));
    vIni.WriteString('General', 'ActiveRules', ActiveRules.CommaText);

    vIni.WriteInteger('Rules', 'DayTolerance', DayTolerance);
    vIni.WriteString('Rules', 'HomeName', HomeName);
    vIni.WriteString('Rules', 'HomeLat', FloatToStr(HomeLat, TFormatSettings.Invariant));
    vIni.WriteString('Rules', 'HomeLon', FloatToStr(HomeLon, TFormatSettings.Invariant));
    vIni.WriteString('Rules', 'HomeRadiusKm', FloatToStr(HomeRadiusKm, TFormatSettings.Invariant));
    vIni.WriteBool('Rules', 'AutoLocate', AutoLocate);

    if InfoFieldsConfigured then
      vIni.WriteString('Info', 'Fields', InfoFields.CommaText);
    vIni.WriteInteger('Info', 'CustomCount', Integer(CustomTags.Count));
    for i := 0 to Integer(CustomTags.Count) - 1 do
      vIni.WriteString('Info', 'Custom' + IntToStr(i + 1),
        Format('0x%.4X|%s|%d|%d', [CustomTags[i].Tag, CustomTags[i].Caption, Ord(CustomTags[i].Enabled),
          Ord(CustomTags[i].Overlay)]));

    vIni.WriteInteger('Collections', 'Count', Integer(Collections.Count));
    i := 0;
    for vColl in Collections do
    begin
      Inc(i);
      vSec := 'Collection' + IntToStr(i);
      vIni.WriteString(vSec, 'Name', vColl.Name);
      vIni.WriteString(vSec, 'Location', vColl.Location);
      vIni.WriteString(vSec, 'User', vColl.User);
      vIni.WriteString(vSec, 'Password', vColl.Password);
      vIni.WriteBool(vSec, 'Enabled', vColl.Enabled);
    end;
    vIni.UpdateFile;
  finally
    vIni.Free;
  end;
end;

initialization

finalization
  FreeAndNil(GSettings);

end.
