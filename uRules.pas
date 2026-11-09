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
  System.DateUtils, System.StrUtils, uLocation, uLang;

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

  { plays the files in the order of the file name (or of the full path), one after another;
    the position is kept while the application runs and wraps around at the end }
  TSequentialRule = class(TMediaRule)
  private
    FFullName: Boolean;
    FDescending: Boolean;
    FHasLast: Boolean;
    FLast: TMediaItem;
    function Compare(const A, B: TMediaItem): Integer;
  public
    constructor Create(AFullName, ADescending: Boolean);
    function Name: string; override;
    function Title: string; override;
    function NeedsMeta: Boolean; override;
    function Accepts(const AMeta: TMediaMeta): Boolean; override;
    function PickNext(ACatalog: TMediaCatalog; out AItem: TMediaItem): Boolean;
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

{ TSequentialRule }

constructor TSequentialRule.Create(AFullName, ADescending: Boolean);
begin
  inherited Create;
  FFullName := AFullName;
  FDescending := ADescending;
end;

function TSequentialRule.Name: string;
begin
  Result := IfThen(FFullName, 'fullname', 'filename') + IfThen(FDescending, 'desc', 'asc');
end;

function TSequentialRule.Title: string;
begin
  if FFullName then
    Result := IfThen(FDescending, L('По полному имени файла, по убыванию', 'By full file name, descending'),
      L('По полному имени файла, по возрастанию', 'By full file name, ascending'))
  else
    Result := IfThen(FDescending, L('По имени файла, по убыванию', 'By file name, descending'),
      L('По имени файла, по возрастанию', 'By file name, ascending'));
end;

function TSequentialRule.NeedsMeta: Boolean;
begin
  Result := False;
end;

function TSequentialRule.Accepts(const AMeta: TMediaMeta): Boolean;
begin
  Result := True;
end;

{ Order of the rule (the direction is already applied). }
function TSequentialRule.Compare(const A, B: TMediaItem): Integer;
begin
  if FFullName then
    Result := CompareText(A.Location, B.Location)
  else
  begin
    Result := CompareText(A.DisplayName, B.DisplayName);
    if Result = 0 then
      Result := CompareText(A.Location, B.Location);
  end;
  if FDescending then
    Result := -Result;
end;

{ One pass: the smallest item after the previous one, otherwise (the end is reached) the smallest of all. }
function TSequentialRule.PickNext(ACatalog: TMediaCatalog; out AItem: TMediaItem): Boolean;
var
  i: Integer;
  vItem, vAfter, vFirst: TMediaItem;
  vHasAfter, vHasFirst: Boolean;
begin
  vHasAfter := False;
  vHasFirst := False;
  for i := 0 to ACatalog.Count - 1 do
  begin
    vItem := ACatalog.Get(i);
    if not ItemAllowed(vItem) then
      Continue;
    if not vHasFirst or (Compare(vItem, vFirst) < 0) then
    begin
      vFirst := vItem;
      vHasFirst := True;
    end;
    if FHasLast and (Compare(vItem, FLast) > 0) and (not vHasAfter or (Compare(vItem, vAfter) < 0)) then
    begin
      vAfter := vItem;
      vHasAfter := True;
    end;
  end;
  Result := vHasFirst;
  if not Result then
    Exit;
  if vHasAfter then
    AItem := vAfter
  else
    AItem := vFirst;
  FLast := AItem;
  FHasLast := True;
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
    if not ItemAllowed(vItem) then
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
  if ARule is TSequentialRule then
    Exit(TSequentialRule(ARule).PickNext(ACatalog, AItem));
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
  if Settings.ActiveRules.Count > 0 then
  begin
    vName := Settings.ActiveRules[Random(Settings.ActiveRules.Count)];
    if TryRule(ACatalog, RuleByName(vName), AItem) then
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
  GRules.Add(TSequentialRule.Create(False, False));
  GRules.Add(TSequentialRule.Create(False, True));
  GRules.Add(TSequentialRule.Create(True, False));
  GRules.Add(TSequentialRule.Create(True, True));

finalization
  FreeAndNil(GRules);

end.
