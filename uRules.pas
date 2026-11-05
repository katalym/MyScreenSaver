unit uRules;

{ Selection rules and the picker. To add a rule: descend from TMediaRule, implement it and
  register it in the initialization section. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, uConfig, uMedia;

type
  TMediaRule = class abstract
  public
    function Name: string; virtual; abstract;
    function Title: string; virtual; abstract;
    { True if the rule needs date/GPS metadata (then remote items cannot be tested). }
    function NeedsMeta: Boolean; virtual;
    function Accepts(const AMeta: TMediaMeta): Boolean; virtual; abstract;
  end;

function RuleByName(const AName: string): TMediaRule;
procedure GetRuleNames(AList: TStrings);
function RuleTitle(const AName: string): string;

{ Picks the next media item according to the settings. False if nothing is available. }
function PickMedia(ACatalog: TMediaCatalog; out AItem: TMediaItem): Boolean;

implementation

uses
  System.DateUtils, uLocation, uLang;

type
  TRandomRule = class(TMediaRule)
  public
    function Name: string; override;
    function Title: string; override;
    function NeedsMeta: Boolean; override;
    function Accepts(const AMeta: TMediaMeta): Boolean; override;
  end;

  { photos/videos taken on the same day (and month) in previous years }
  TOnThisDayRule = class(TMediaRule)
  public
    function Name: string; override;
    function Title: string; override;
    function Accepts(const AMeta: TMediaMeta): Boolean; override;
  end;

  { photos taken near the current location (home place or auto-detected) }
  TNearLocationRule = class(TMediaRule)
  public
    function Name: string; override;
    function Title: string; override;
    function Accepts(const AMeta: TMediaMeta): Boolean; override;
  end;

var
  GRules: TObjectList<TMediaRule>;

function TMediaRule.NeedsMeta: Boolean;
begin
  Result := True;
end;

{ TRandomRule }

function TRandomRule.Name: string;
begin
  Result := 'random';
end;

function TRandomRule.Title: string;
begin
  Result := L('Случайный файл', 'Random file');
end;

function TRandomRule.NeedsMeta: Boolean;
begin
  Result := False;
end;

function TRandomRule.Accepts(const AMeta: TMediaMeta): Boolean;
begin
  Result := True;
end;

{ TOnThisDayRule }

function TOnThisDayRule.Name: string;
begin
  Result := 'onthisday';
end;

function TOnThisDayRule.Title: string;
begin
  Result := L('В этот день в прошлые годы', 'On this day in previous years');
end;

function TOnThisDayRule.Accepts(const AMeta: TMediaMeta): Boolean;
var
  vToday, vSame: TDateTime;
  vDay: Word;
begin
  Result := False;
  if not AMeta.HasDate then
    Exit;
  vToday := Date;
  if YearOf(AMeta.Date) >= YearOf(vToday) then
    Exit;
  vDay := DayOf(AMeta.Date);
  if not TryEncodeDate(YearOf(vToday), MonthOf(AMeta.Date), vDay, vSame) then
    vSame := EncodeDate(YearOf(vToday), MonthOf(AMeta.Date), 28);
  Result := Abs(Trunc(vSame) - Trunc(vToday)) <= Settings.DayTolerance;
end;

{ TNearLocationRule }

function TNearLocationRule.Name: string;
begin
  Result := 'location';
end;

function TNearLocationRule.Title: string;
begin
  Result := L('Снято рядом с текущим местом', 'Taken near the current place');
end;

function TNearLocationRule.Accepts(const AMeta: TMediaMeta): Boolean;
var
  vLat, vLon: Double;
begin
  Result := False;
  if not AMeta.HasGps then
    Exit;
  if Settings.CurValid then
  begin
    vLat := Settings.CurLat;
    vLon := Settings.CurLon;
  end
  else if (Settings.HomeLat <> 0) or (Settings.HomeLon <> 0) then
  begin
    vLat := Settings.HomeLat;
    vLon := Settings.HomeLon;
  end
  else
    Exit;
  Result := DistanceKm(vLat, vLon, AMeta.Lat, AMeta.Lon) <= Settings.HomeRadiusKm;
end;

{ registry }

function RuleByName(const AName: string): TMediaRule;
var
  vRule: TMediaRule;
begin
  for vRule in GRules do
    if SameText(vRule.Name, AName) then
      Exit(vRule);
  Result := GRules[0];
end;

procedure GetRuleNames(AList: TStrings);
var
  vRule: TMediaRule;
begin
  AList.Clear;
  for vRule in GRules do
    AList.Add(vRule.Name);
end;

function RuleTitle(const AName: string): string;
begin
  Result := RuleByName(AName).Title;
end;

{ picker }

function TryRule(ACatalog: TMediaCatalog; ARule: TMediaRule; out AItem: TMediaItem): Boolean;
const
  MaxTries = 30000;
var
  vCount, i, vStart: Integer;
  vItem: TMediaItem;
  vMeta: TMediaMeta;

  function Accept: Boolean;
  begin
    Result := False;
    if not KindAllowed(vItem.Kind) then
      Exit;
    if ARule.NeedsMeta then
    begin
      if vItem.SourceKind in [skHttp, skFtp] then
        Exit;
      // cached metadata only: the picker must never read files (it runs in the UI thread)
      if not TryGetCachedMeta(vItem, vMeta) then
        Exit;
      if not ARule.Accepts(vMeta) then
        Exit;
    end;
    Result := True;
  end;

begin
  Result := False;
  vCount := ACatalog.Count;
  if vCount = 0 then
    Exit;
  for i := 1 to MaxTries do
  begin
    vItem := ACatalog.Get(Random(vCount));
    if Accept then
    begin
      AItem := vItem;
      Exit(True);
    end;
  end;
  // rare matches (e.g. only a few videos among many photos): one pass over everything
  vStart := Random(vCount);
  for i := 0 to vCount - 1 do
  begin
    vItem := ACatalog.Get((vStart + i) mod vCount);
    if Accept then
    begin
      AItem := vItem;
      Exit(True);
    end;
  end;
end;

function PickMedia(ACatalog: TMediaCatalog; out AItem: TMediaItem): Boolean;
var
  vName: string;
begin
  Result := False;
  // Quick start: until the list is usable (cache loaded / scan done) show random photos only
  if not ACatalog.Ready then
  begin
    if ACatalog.PopQuick(AItem) then
      Exit(True);
    Exit(TryRule(ACatalog, RuleByName('random'), AItem));
  end;
  if ACatalog.Count = 0 then
    Exit;
  if (Settings.Mode = smRules) and (Settings.ActiveRules.Count > 0) then
  begin
    vName := Settings.ActiveRules[Random(Settings.ActiveRules.Count)];
    if TryRule(ACatalog, RuleByName(vName), AItem) then
      Exit(True);
    if TryRule(ACatalog, RuleByName(Settings.DefaultRule), AItem) then
      Exit(True);
  end;
  Result := TryRule(ACatalog, RuleByName('random'), AItem);
end;

initialization
  Randomize;
  GRules := TObjectList<TMediaRule>.Create(True);
  GRules.Add(TRandomRule.Create);
  GRules.Add(TOnThisDayRule.Create);
  GRules.Add(TNearLocationRule.Create);

finalization
  FreeAndNil(GRules);

end.
