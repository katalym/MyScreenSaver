unit uLocation;

{ Geo helpers: distance and optional IP-based location detection. }

interface

function DistanceKm(ALat1, ALon1, ALat2, ALon2: Double): Double;
{ Optional (disabled by default): approximate location by public IP. }
function TryDetectLocationByIP(out ALat, ALon: Double): Boolean;

{ Human-friendly place name for coordinates (OpenStreetMap Nominatim, cached in memory and in the file
  places.cache next to the INI: one line per place of 4 decimals, with the name in English and in Russian):
  attraction/park/lake, road, city, state, country. Empty string if unavailable. }
function ReverseGeocode(ALat, ALon: Double; const ALanguage: string): string;
{ The place name only if it is already in the cache of ReverseGeocode (no internet access). }
function TryGetCachedGeocode(ALat, ALon: Double; const ALanguage: string; out APlace: string): Boolean;

implementation

uses
  System.SysUtils, System.Math, System.JSON, System.Net.HttpClient, System.Classes,
  System.SyncObjs, System.Generics.Collections, System.IOUtils, uConfig;

const
  PlacesCacheVersion = 1;   // version of the format of places.cache (the first line of the file)

var
  GGeoLock: TCriticalSection;
  GGeoCache: TDictionary<string, string>;
  GPlacesLoaded: Boolean;

{ ---- places.cache ----
  Version<TAB>1
  Lat<TAB>Lon<TAB>PlaceEn<TAB>PlaceRu            (the names of the columns)
  then one line per place, the last line of a place wins; Lat / Lon have 4 decimals }

function PlacesPath: string;
begin
  Result := TPath.Combine(ExtractFilePath(TAppSettings.ConfigPath), 'places.cache');
end;

function PlaceKey(ALat, ALon: Double; const ALanguage: string): string;
begin
  Result := Format('%.4f,%.4f,%s', [ALat, ALon, ALanguage], TFormatSettings.Invariant);
end;

function PlacesHeader: string;
begin
  Result := 'Version'#9 + IntToStr(PlacesCacheVersion) + #13#10 + 'Lat'#9'Lon'#9'PlaceEn'#9'PlaceRu';
end;

{ Reads places.cache into the memory cache (once). A file of another version is deleted. Called with
  GGeoLock taken. }
procedure LoadPlaces;
var
  vLines: TArray<string>;
  vParts: TArray<string>;
  i: Integer;
begin
  if GPlacesLoaded then
    Exit;
  GPlacesLoaded := True;
  if not FileExists(PlacesPath) then
    Exit;
  begin
    try
      vLines := TFile.ReadAllLines(PlacesPath, TEncoding.UTF8);
      vParts := nil;
      if Length(vLines) > 0 then
        vParts := vLines[0].Split([#9]);
      if (Length(vParts) < 2) or (vParts[0] <> 'Version') or (vParts[1] <> IntToStr(PlacesCacheVersion)) then
      begin
        TFile.Delete(PlacesPath);   // another format: the places are looked up again when needed
        Exit;
      end;
      for i := 2 to High(vLines) do
      begin
        vParts := vLines[i].Split([#9]);
        if Length(vParts) < 4 then
          Continue;
        if vParts[2] <> '' then
          GGeoCache.AddOrSetValue(vParts[0] + ',' + vParts[1] + ',en', vParts[2]);
        if vParts[3] <> '' then
          GGeoCache.AddOrSetValue(vParts[0] + ',' + vParts[1] + ',ru', vParts[3]);
      end;
    except
    end;
  end;
end;

{ Appends the place of the coordinates (both names that are known) to places.cache. Called with GGeoLock taken. }
procedure SavePlace(ALat, ALon: Double);
var
  vEn, vRu: string;
  vWriter: TStreamWriter;
  vNew: Boolean;
begin
  if not GGeoCache.TryGetValue(PlaceKey(ALat, ALon, 'en'), vEn) then
    vEn := '';
  if not GGeoCache.TryGetValue(PlaceKey(ALat, ALon, 'ru'), vRu) then
    vRu := '';
  try
    vNew := not FileExists(PlacesPath);
    vWriter := TStreamWriter.Create(PlacesPath, True, TEncoding.UTF8);
    try
      if vNew then
        vWriter.WriteLine(PlacesHeader);
      vWriter.WriteLine(Format('%.4f'#9'%.4f'#9'%s'#9'%s', [ALat, ALon, vEn, vRu], TFormatSettings.Invariant));
    finally
      vWriter.Free;
    end;
  except
    // the cache file is only a convenience
  end;
end;

function AddrValue(AAddr: TJSONObject; const AKeys: array of string): string;
var
  vKey: string;
begin
  Result := '';
  if AAddr = nil then
    Exit;
  for vKey in AKeys do
    if AAddr.TryGetValue<string>(vKey, Result) and (Result <> '') then
      Exit;
  Result := '';
end;

procedure AddPart(AParts: TStrings; const APart: string);
begin
  if (APart <> '') and (AParts.IndexOf(APart) < 0) then
    AParts.Add(APart);
end;

function TryGetCachedGeocode(ALat, ALon: Double; const ALanguage: string; out APlace: string): Boolean;
var
  vKey: string;
begin
  vKey := PlaceKey(ALat, ALon, ALanguage);
  GGeoLock.Enter;
  try
    LoadPlaces;
    Result := GGeoCache.TryGetValue(vKey, APlace);
  finally
    GGeoLock.Leave;
  end;
end;

function ReverseGeocode(ALat, ALon: Double; const ALanguage: string): string;
var
  vKey, vUrl, vName, vLang: string;
  vClient: THTTPClient;
  vVal: TJSONValue;
  vAddr: TJSONObject;
  vParts: TStringList;
begin
  vKey := PlaceKey(ALat, ALon, ALanguage);
  GGeoLock.Enter;
  try
    LoadPlaces;
    if GGeoCache.TryGetValue(vKey, Result) then
      Exit;
  finally
    GGeoLock.Leave;
  end;
  Result := '';
  vLang := ALanguage;
  if vLang = '' then
    vLang := 'en';
  vUrl := Format('https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=18' +
    '&addressdetails=1&accept-language=%s&lat=%.6f&lon=%.6f',
    [vLang, ALat, ALon], TFormatSettings.Invariant);
  vClient := THTTPClient.Create;
  try
    vClient.ConnectionTimeout := 3000;
    vClient.ResponseTimeout := 4000;
    vClient.UserAgent := 'MyScreenSaver/1.0 (photo viewer)';
    try
      vVal := TJSONObject.ParseJSONValue(vClient.Get(vUrl).ContentAsString);
    except
      Exit;   // offline: not cached, can be retried
    end;
  finally
    vClient.Free;
  end;
  try
    if vVal is TJSONObject then
    begin
      vParts := TStringList.Create;
      try
        vAddr := nil;
        TJSONObject(vVal).TryGetValue<TJSONObject>('address', vAddr);
        // named place: attraction, park, lake, building...
        if not TJSONObject(vVal).TryGetValue<string>('name', vName) then
          vName := '';
        AddPart(vParts, vName);
        AddPart(vParts, AddrValue(vAddr, ['road', 'pedestrian', 'path', 'footway']));
        AddPart(vParts, AddrValue(vAddr, ['city', 'town', 'village', 'hamlet', 'suburb', 'county']));
        AddPart(vParts, AddrValue(vAddr, ['state', 'region']));
        AddPart(vParts, AddrValue(vAddr, ['country']));
        vParts.Delimiter := ',';
        vParts.StrictDelimiter := True;
        Result := StringReplace(vParts.DelimitedText, ',', ', ', [rfReplaceAll]);
      finally
        vParts.Free;
      end;
    end;
  finally
    vVal.Free;
  end;
  if Result <> '' then
  begin
    GGeoLock.Enter;
    try
      GGeoCache.AddOrSetValue(vKey, Result);
      SavePlace(ALat, ALon);
    finally
      GGeoLock.Leave;
    end;
  end;
end;

function DistanceKm(ALat1, ALon1, ALat2, ALon2: Double): Double;
const
  EarthR = 6371.0;
var
  vDLat, vDLon, a: Double;
begin
  vDLat := DegToRad(ALat2 - ALat1);
  vDLon := DegToRad(ALon2 - ALon1);
  a := Sqr(Sin(vDLat / 2)) + Cos(DegToRad(ALat1)) * Cos(DegToRad(ALat2)) * Sqr(Sin(vDLon / 2));
  Result := 2 * EarthR * ArcTan2(Sqrt(a), Sqrt(1 - a));
end;

function TryDetectLocationByIP(out ALat, ALon: Double): Boolean;
var
  vClient: THTTPClient;
  vVal: TJSONValue;
begin
  Result := False;
  ALat := 0;
  ALon := 0;
  vClient := THTTPClient.Create;
  try
    vClient.ConnectionTimeout := 5000;
    vClient.ResponseTimeout := 5000;
    try
      vVal := TJSONObject.ParseJSONValue(vClient.Get('https://ipapi.co/json/').ContentAsString);
    except
      Exit;
    end;
    try
      if vVal is TJSONObject then
        Result := TJSONObject(vVal).TryGetValue<Double>('latitude', ALat) and
          TJSONObject(vVal).TryGetValue<Double>('longitude', ALon);
    finally
      vVal.Free;
    end;
  finally
    vClient.Free;
  end;
end;

initialization
  GGeoLock := TCriticalSection.Create;
  GGeoCache := TDictionary<string, string>.Create;

finalization
  FreeAndNil(GGeoCache);
  FreeAndNil(GGeoLock);

end.
