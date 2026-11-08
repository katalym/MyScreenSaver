unit uLocation;

{ Geo helpers: distance and optional IP-based location detection. }

interface

function DistanceKm(ALat1, ALon1, ALat2, ALon2: Double): Double;
{ Optional (disabled by default): approximate location by public IP. }
function TryDetectLocationByIP(out ALat, ALon: Double): Boolean;

{ Human-friendly place name for coordinates (OpenStreetMap Nominatim, cached):
  attraction/park/lake, road, city, state, country. Empty string if unavailable. }
function ReverseGeocode(ALat, ALon: Double; const ALanguage: string): string;
{ The place name only if it is already in the cache of ReverseGeocode (no internet access). }
function TryGetCachedGeocode(ALat, ALon: Double; const ALanguage: string; out APlace: string): Boolean;

implementation

uses
  System.SysUtils, System.Math, System.JSON, System.Net.HttpClient, System.Classes,
  System.SyncObjs, System.Generics.Collections;

var
  GGeoLock: TCriticalSection;
  GGeoCache: TDictionary<string, string>;

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
  vKey := Format('%.4f,%.4f,%s', [ALat, ALon, ALanguage], TFormatSettings.Invariant);
  GGeoLock.Enter;
  try
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
  vKey := Format('%.4f,%.4f,%s', [ALat, ALon, ALanguage], TFormatSettings.Invariant);
  GGeoLock.Enter;
  try
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
