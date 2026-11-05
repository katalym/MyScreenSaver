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

  TSelectionMode = (smRandom, smRules);

  TAppSettings = class
  public
    Collections: TList<TMediaCollection>;
    SlideSeconds: Integer;
    Mode: TSelectionMode;
    ActiveRules: TStringList;
    DefaultRule: string;
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

implementation

uses
  System.IniFiles, System.IOUtils;

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
  SlideSeconds := 10;
  Mode := smRandom;
  DefaultRule := 'random';
  DayTolerance := 0;
  HomeRadiusKm := 50;
  AutoLocate := False;
  Language := DefaultLanguage;
  SetLanguage(Language);
end;

destructor TAppSettings.Destroy;
begin
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
begin
  if not FileExists(ConfigPath) then
    Exit;
  vIni := TMemIniFile.Create(ConfigPath, TEncoding.UTF8);
  try
    SlideSeconds := vIni.ReadInteger('General', 'SlideSeconds', SlideSeconds);
    if SlideSeconds < 1 then
      SlideSeconds := 1;
    if SameText(vIni.ReadString('General', 'Mode', 'random'), 'rules') then
      Mode := smRules
    else
      Mode := smRandom;
    DefaultRule := vIni.ReadString('General', 'DefaultRule', DefaultRule);
    ActiveRules.CommaText := vIni.ReadString('General', 'ActiveRules', '');

    DayTolerance := vIni.ReadInteger('Rules', 'DayTolerance', DayTolerance);
    HomeName := vIni.ReadString('Rules', 'HomeName', '');
    HomeLat := ReadFloat(vIni, 'Rules', 'HomeLat', 0);
    HomeLon := ReadFloat(vIni, 'Rules', 'HomeLon', 0);
    HomeRadiusKm := ReadFloat(vIni, 'Rules', 'HomeRadiusKm', HomeRadiusKm);
    AutoLocate := vIni.ReadBool('Rules', 'AutoLocate', False);
    Language := LanguageFromCode(vIni.ReadString('General', 'Language', ''), DefaultLanguage);
    SetLanguage(Language);

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
    if Mode = smRules then
      vIni.WriteString('General', 'Mode', 'rules')
    else
      vIni.WriteString('General', 'Mode', 'random');
    vIni.WriteString('General', 'DefaultRule', DefaultRule);
    vIni.WriteString('General', 'Language', LanguageCode(Language));
    vIni.WriteString('General', 'ActiveRules', ActiveRules.CommaText);

    vIni.WriteInteger('Rules', 'DayTolerance', DayTolerance);
    vIni.WriteString('Rules', 'HomeName', HomeName);
    vIni.WriteString('Rules', 'HomeLat', FloatToStr(HomeLat, TFormatSettings.Invariant));
    vIni.WriteString('Rules', 'HomeLon', FloatToStr(HomeLon, TFormatSettings.Invariant));
    vIni.WriteString('Rules', 'HomeRadiusKm', FloatToStr(HomeRadiusKm, TFormatSettings.Invariant));
    vIni.WriteBool('Rules', 'AutoLocate', AutoLocate);

    vIni.WriteInteger('Collections', 'Count', Collections.Count);
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
