unit uMedia;

{ Media catalog: scanning of local/network/HTTP/FTP collections, local cache for remote files,
  metadata (date, GPS) with in-memory cache. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.Generics.Defaults, System.SyncObjs, uConfig;

type
  TMediaKind = (mkPhoto, mkVideo);

  TMediaItem = record
    Location: string;       // full path or URL
    Collection: string;
    SourceKind: TSourceKind;
    Kind: TMediaKind;
    User: string;
    Password: string;
    function DisplayName: string;
  end;

  TMediaMeta = record
    HasDate: Boolean;
    Date: TDateTime;
    HasGps: Boolean;
    Lat: Double;
    Lon: Double;
  end;

  TMediaCatalog = class
  private
    FLock: TCriticalSection;
    FItems: TList<TMediaItem>;
    FScanning: Boolean;
    FQuick: TList<TMediaItem>;
    FIndex: TDictionary<string, Integer>;
    FReady: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const AItem: TMediaItem);
    function Count: Integer;
    function Get(AIndex: Integer): TMediaItem;
    { quick start: random photos found without a full scan }
    procedure PushQuick(const AItem: TMediaItem);
    function PopQuick(out AItem: TMediaItem): Boolean;
    function QuickCount: Integer;
    function Contains(const ALocation: string): Boolean;
    procedure AddRange(AItems: TList<TMediaItem>);
    function Snapshot: TArray<TMediaItem>;
    { Drops items that were not seen by the last scan (only for collections that were reachable).
      Returns the number of removed items. }
    function RetainOnly(ASeen, AReachable: TDictionary<string, Boolean>): Integer;
    { True until the full scan has finished }
    property Scanning: Boolean read FScanning write FScanning;
    { True when the list is usable for rule-based picking: loaded from the cache file or fully scanned }
    property Ready: Boolean read FReady write FReady;
  end;

  { Background indexer: reads date/GPS of every local file once and keeps them in a cache file
    (%APPDATA%\MyScreenSaver\meta.cache), so rules never have to touch the disk while picking. }
  TMetaIndexer = class(TThread)
  private
    FCatalog: TMediaCatalog;
  protected
    procedure Execute; override;
  public
    constructor Create(ACatalog: TMediaCatalog);
  end;

  { Finds random photos by random descent through the folders, so the first picture can be shown
    right away while TScanThread is still building the full list. }
  TQuickSampler = class(TThread)
  private
    FCatalog: TMediaCatalog;
    function RandomLocal(const AColl: TMediaCollection; out AItem: TMediaItem): Boolean;
    function RandomHttp(const AColl: TMediaCollection; out AItem: TMediaItem): Boolean;
    function RandomItem(out AItem: TMediaItem): Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(ACatalog: TMediaCatalog);
  end;

  TScanThread = class(TThread)
  private
    FCatalog: TMediaCatalog;
    FSeen: TDictionary<string, Boolean>;
    FReachable: TDictionary<string, Boolean>;
    FPending: TStringList;
    procedure FlushPending;
    procedure ScanLocal(const AColl: TMediaCollection; const ADir: string);
    procedure ScanHttp(const AColl: TMediaCollection; const AUrl: string; ADepth: Integer);
    procedure ScanFtp(const AColl: TMediaCollection);
    procedure AddFile(const AColl: TMediaCollection; const ALocation: string);
  protected
    procedure Execute; override;
  public
    constructor Create(ACatalog: TMediaCatalog);
    destructor Destroy; override;
  end;

function MediaKindOfFile(const AName: string; out AKind: TMediaKind): Boolean;
{ Returns a local file path for the item; downloads remote files into the cache. }
function EnsureLocalFile(const AItem: TMediaItem): string;
function GetMediaMeta(const AItem: TMediaItem): TMediaMeta;
{ Cached metadata only (no file access). False if the file is not indexed yet. }
function TryGetCachedMeta(const AItem: TMediaItem; out AMeta: TMediaMeta): Boolean;
{ Optional IP-based location detection in a background thread. }
procedure StartLocationDetection;
procedure CleanCache;

implementation

uses
  System.IOUtils, System.Math, System.StrUtils, System.Hash, System.NetEncoding, System.RegularExpressions, System.DateUtils,
  System.Threading, System.Net.HttpClient, System.Net.URLClient, IdFTP, IdFTPList, IdFTPCommon, uExif, uLocation;

const
  PhotoExts: array[0..9] of string =
    ('.jpg', '.jpeg', '.png', '.bmp', '.gif', '.tif', '.tiff', '.heic', '.webp', '.jfif');
  VideoExts: array[0..7] of string =
    ('.mp4', '.avi', '.wmv', '.mov', '.mkv', '.mpg', '.mpeg', '.m4v');
  MaxDepth = 6;

var
  GMetaLock: TCriticalSection;
  GMetaCache: TDictionary<string, TMediaMeta>;

function MediaKindOfFile(const AName: string; out AKind: TMediaKind): Boolean;
var
  vExt, s: string;
  vName: string;
begin
  vName := AName;
  if Pos('?', vName) > 0 then
    vName := Copy(vName, 1, Pos('?', vName) - 1);
  vExt := LowerCase(ExtractFileExt(vName));
  Result := True;
  for s in PhotoExts do
    if s = vExt then
    begin
      AKind := mkPhoto;
      Exit;
    end;
  for s in VideoExts do
    if s = vExt then
    begin
      AKind := mkVideo;
      Exit;
    end;
  Result := False;
end;

{ TMediaItem }

function TMediaItem.DisplayName: string;
begin
  if SourceKind in [skHttp, skFtp] then
    Result := TNetEncoding.URL.Decode(Location.Substring(Location.LastIndexOf('/') + 1))
  else
    Result := ExtractFileName(Location);
end;

{ TMediaCatalog }

constructor TMediaCatalog.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FItems := TList<TMediaItem>.Create;
  FQuick := TList<TMediaItem>.Create;
  FIndex := TDictionary<string, Integer>.Create(TIStringComparer.Ordinal);
  FScanning := True;
end;

procedure TMediaCatalog.PushQuick(const AItem: TMediaItem);
begin
  FLock.Enter;
  try
    FQuick.Add(AItem);
  finally
    FLock.Leave;
  end;
end;

function TMediaCatalog.PopQuick(out AItem: TMediaItem): Boolean;
begin
  FLock.Enter;
  try
    Result := FQuick.Count > 0;
    if Result then
    begin
      AItem := FQuick[0];
      FQuick.Delete(0);
    end;
  finally
    FLock.Leave;
  end;
end;

function TMediaCatalog.QuickCount: Integer;
begin
  FLock.Enter;
  try
    Result := Integer(FQuick.Count);
  finally
    FLock.Leave;
  end;
end;

destructor TMediaCatalog.Destroy;
begin
  FreeAndNil(FIndex);
  FreeAndNil(FQuick);
  FreeAndNil(FItems);
  FreeAndNil(FLock);
  inherited;
end;

procedure TMediaCatalog.Add(const AItem: TMediaItem);
begin
  FLock.Enter;
  try
    if not FIndex.ContainsKey(AItem.Location) then
    begin
      FIndex.Add(AItem.Location, Integer(FItems.Count));
      FItems.Add(AItem);
    end;
  finally
    FLock.Leave;
  end;
end;

function TMediaCatalog.Contains(const ALocation: string): Boolean;
begin
  FLock.Enter;
  try
    Result := FIndex.ContainsKey(ALocation);
  finally
    FLock.Leave;
  end;
end;

procedure TMediaCatalog.AddRange(AItems: TList<TMediaItem>);
var
  vItem: TMediaItem;
begin
  FLock.Enter;
  try
    for vItem in AItems do
      if not FIndex.ContainsKey(vItem.Location) then
      begin
        FIndex.Add(vItem.Location, Integer(FItems.Count));
        FItems.Add(vItem);
      end;
  finally
    FLock.Leave;
  end;
end;

function TMediaCatalog.Snapshot: TArray<TMediaItem>;
begin
  FLock.Enter;
  try
    Result := FItems.ToArray;
  finally
    FLock.Leave;
  end;
end;

function TMediaCatalog.RetainOnly(ASeen, AReachable: TDictionary<string, Boolean>): Integer;
var
  vKept: TList<TMediaItem>;
  vItem: TMediaItem;
begin
  Result := 0;
  vKept := TList<TMediaItem>.Create;
  FLock.Enter;
  try
    for vItem in FItems do
      if ASeen.ContainsKey(vItem.Location) or not AReachable.ContainsKey(vItem.Collection) then
        vKept.Add(vItem)
      else
        Inc(Result);
    if Result > 0 then
    begin
      FItems.Clear;
      FIndex.Clear;
      for vItem in vKept do
      begin
        FIndex.Add(vItem.Location, Integer(FItems.Count));
        FItems.Add(vItem);
      end;
    end;
  finally
    FLock.Leave;
    vKept.Free;
  end;
end;

function TMediaCatalog.Count: Integer;
begin
  FLock.Enter;
  try
    Result := Integer(FItems.Count);
  finally
    FLock.Leave;
  end;
end;

function TMediaCatalog.Get(AIndex: Integer): TMediaItem;
begin
  FLock.Enter;
  try
    Result := FItems[AIndex];
  finally
    FLock.Leave;
  end;
end;

function MakeItem(const AColl: TMediaCollection; const ALocation: string;
  AKind: TMediaKind): TMediaItem; forward;

procedure ListHttpDir(const AColl: TMediaCollection; const AUrl: string;
  ADirs, AFiles: TStrings); forward;

{ ---- persistent catalog cache (text file, append-only log) ----
  F<TAB>location<TAB>kind      a media file of a configured collection
  M<TAB>location<TAB>...       its metadata (date, GPS); a later line overrides an earlier one }

var
  GCacheLock: TCriticalSection;

function CatalogCachePath: string;
begin
  Result := TPath.Combine(ExtractFilePath(TAppSettings.ConfigPath), 'catalog.cache');
end;

function MetaCacheLine(const ALocation: string; const AMeta: TMediaMeta): string;
begin
  Result := Format('M'#9'%s'#9'%d'#9'%s'#9'%d'#9'%s'#9'%s',
    [ALocation, Ord(AMeta.HasDate), FloatToStr(AMeta.Date, TFormatSettings.Invariant),
     Ord(AMeta.HasGps), FloatToStr(AMeta.Lat, TFormatSettings.Invariant),
     FloatToStr(AMeta.Lon, TFormatSettings.Invariant)]);
end;

function FileCacheLine(const AItem: TMediaItem): string;
begin
  Result := 'F'#9 + AItem.Location + #9 + IfThen(AItem.Kind = mkVideo, '1', '0');
end;

procedure AppendCacheLines(ALines: TStrings);
var
  vWriter: TStreamWriter;
  i: Integer;
begin
  if ALines.Count = 0 then
    Exit;
  GCacheLock.Enter;
  try
    try
      vWriter := TStreamWriter.Create(CatalogCachePath, True, TEncoding.UTF8);
      try
        for i := 0 to ALines.Count - 1 do
          vWriter.WriteLine(ALines[i]);
      finally
        vWriter.Free;
      end;
    except
    end;
  finally
    GCacheLock.Leave;
  end;
end;

{ Rewrites the whole file (compaction after files disappeared). }
procedure RewriteCatalogCache(ACatalog: TMediaCatalog);
var
  vItems: TArray<TMediaItem>;
  vItem: TMediaItem;
  vMeta: TMediaMeta;
  vWriter: TStreamWriter;
  vTmp: string;
begin
  vItems := ACatalog.Snapshot;
  vTmp := CatalogCachePath + '.tmp';
  GCacheLock.Enter;
  try
    try
      vWriter := TStreamWriter.Create(vTmp, False, TEncoding.UTF8);
      try
        for vItem in vItems do
        begin
          vWriter.WriteLine(FileCacheLine(vItem));
          if TryGetCachedMeta(vItem, vMeta) then
            vWriter.WriteLine(MetaCacheLine(vItem.Location, vMeta));
        end;
      finally
        vWriter.Free;
      end;
      TFile.Copy(vTmp, CatalogCachePath, True);
      TFile.Delete(vTmp);
    except
    end;
  finally
    GCacheLock.Leave;
  end;
end;

procedure PutMetaCache(const ALocation: string; const AMeta: TMediaMeta);
begin
  if GMetaCache = nil then
    Exit;
  GMetaLock.Enter;
  try
    GMetaCache.AddOrSetValue(ALocation, AMeta);
  finally
    GMetaLock.Leave;
  end;
end;

{ Loads the previous scan result: the catalog becomes usable immediately. }
procedure LoadCatalogCache(ACatalog: TMediaCatalog);
var
  vReader: TStreamReader;
  vLine: string;
  vParts: TArray<string>;
  vItems: TList<TMediaItem>;
  vColls: TArray<TMediaCollection>;
  vMeta: TMediaMeta;
  vKind: TMediaKind;
  i, vCollIdx: Integer;
begin
  if not FileExists(CatalogCachePath) then
    Exit;
  vColls := Settings.Collections.ToArray;
  vItems := TList<TMediaItem>.Create;
  try
    try
      vReader := TStreamReader.Create(CatalogCachePath, TEncoding.UTF8);
      try
        while not vReader.EndOfStream do
        begin
          vLine := vReader.ReadLine;
          vParts := vLine.Split([#9]);
          if Length(vParts) < 3 then
            Continue;
          if vParts[0] = 'F' then
          begin
            vCollIdx := -1;
            for i := 0 to Integer(High(vColls)) do
              if vColls[i].Enabled and vParts[1].StartsWith(vColls[i].Location, True) then
              begin
                vCollIdx := i;
                Break;
              end;
            if vCollIdx < 0 then
              Continue;
            if vParts[2] = '1' then
              vKind := mkVideo
            else
              vKind := mkPhoto;
            vItems.Add(MakeItem(vColls[vCollIdx], vParts[1], vKind));
          end
          else if (vParts[0] = 'M') and (Length(vParts) >= 7) then
          begin
            vMeta := Default(TMediaMeta);
            vMeta.HasDate := vParts[2] = '1';
            vMeta.Date := StrToFloatDef(vParts[3], 0, TFormatSettings.Invariant);
            vMeta.HasGps := vParts[4] = '1';
            vMeta.Lat := StrToFloatDef(vParts[5], 0, TFormatSettings.Invariant);
            vMeta.Lon := StrToFloatDef(vParts[6], 0, TFormatSettings.Invariant);
            PutMetaCache(vParts[1], vMeta);
          end;
        end;
      finally
        vReader.Free;
      end;
    except
    end;
    ACatalog.AddRange(vItems);
    if ACatalog.Count > 0 then
      ACatalog.Ready := True;
  finally
    vItems.Free;
  end;
end;

{ TQuickSampler }

constructor TQuickSampler.Create(ACatalog: TMediaCatalog);
begin
  inherited Create(False);
  FreeOnTerminate := False;
  FCatalog := ACatalog;
end;

function MakeItem(const AColl: TMediaCollection; const ALocation: string;
  AKind: TMediaKind): TMediaItem;
begin
  Result.Location := ALocation;
  Result.Collection := AColl.Name;
  Result.SourceKind := AColl.Kind;
  Result.Kind := AKind;
  Result.User := AColl.User;
  Result.Password := AColl.Password;
end;

function TQuickSampler.RandomLocal(const AColl: TMediaCollection; out AItem: TMediaItem): Boolean;
var
  vPath: string;
  vDepth: Integer;
  vSr: TSearchRec;
  vDirs, vFiles: TStringList;
  vKind: TMediaKind;
  vTotal, vPick: Integer;
begin
  Result := False;
  vPath := IncludeTrailingPathDelimiter(AColl.Location);
  vDirs := TStringList.Create;
  vFiles := TStringList.Create;
  try
    for vDepth := 0 to 15 do
    begin
      if Terminated then
        Exit;
      vDirs.Clear;
      vFiles.Clear;
      if FindFirst(vPath + '*', faAnyFile, vSr) = 0 then
      try
        repeat
          if (vSr.Name = '.') or (vSr.Name = '..') then
            Continue;
          if (vSr.Attr and faDirectory) <> 0 then
            vDirs.Add(vSr.Name)
          else if MediaKindOfFile(vSr.Name, vKind) and (vKind = mkPhoto) then
            vFiles.Add(vSr.Name);
        until FindNext(vSr) <> 0;
      finally
        FindClose(vSr);
      end;
      vTotal := vDirs.Count + vFiles.Count;
      if vTotal = 0 then
        Exit;
      vPick := Random(vTotal);
      if vPick < vFiles.Count then
      begin
        AItem := MakeItem(AColl, vPath + vFiles[vPick], mkPhoto);
        Exit(True);
      end;
      vPath := vPath + vDirs[vPick - vFiles.Count] + PathDelim;
    end;
  finally
    vDirs.Free;
    vFiles.Free;
  end;
end;

function TQuickSampler.RandomHttp(const AColl: TMediaCollection; out AItem: TMediaItem): Boolean;
var
  vUrl: string;
  vDepth, vTotal, vPick: Integer;
  vDirs, vFiles, vPhotos: TStringList;
  vKind: TMediaKind;
  i: Integer;
begin
  Result := False;
  vUrl := AColl.Location;
  if not vUrl.EndsWith('/') then
    vUrl := vUrl + '/';
  vDirs := TStringList.Create;
  vFiles := TStringList.Create;
  vPhotos := TStringList.Create;
  try
    for vDepth := 0 to 8 do
    begin
      if Terminated then
        Exit;
      vDirs.Clear;
      vFiles.Clear;
      vPhotos.Clear;
      ListHttpDir(AColl, vUrl, vDirs, vFiles);
      for i := 0 to vFiles.Count - 1 do
        if MediaKindOfFile(vFiles[i], vKind) and (vKind = mkPhoto) then
          vPhotos.Add(vFiles[i]);
      vTotal := vDirs.Count + vPhotos.Count;
      if vTotal = 0 then
        Exit;
      vPick := Random(vTotal);
      if vPick < vPhotos.Count then
      begin
        AItem := MakeItem(AColl, vPhotos[vPick], mkPhoto);
        Exit(True);
      end;
      vUrl := vDirs[vPick - vPhotos.Count];
    end;
  finally
    vDirs.Free;
    vFiles.Free;
    vPhotos.Free;
  end;
end;

function TQuickSampler.RandomItem(out AItem: TMediaItem): Boolean;
var
  vList: TArray<TMediaCollection>;
  vUsable: TList<TMediaCollection>;
  vColl: TMediaCollection;
begin
  Result := False;
  vList := Settings.Collections.ToArray;
  vUsable := TList<TMediaCollection>.Create;
  try
    for vColl in vList do
      if vColl.Enabled and (vColl.Kind <> skFtp) then
        vUsable.Add(vColl);
    if vUsable.Count = 0 then
      Exit;
    vColl := vUsable[Random(Integer(vUsable.Count))];
  finally
    vUsable.Free;
  end;
  try
    if vColl.Kind in [skLocal, skNetwork] then
    begin
      if DirectoryExists(vColl.Location) then
        Result := RandomLocal(vColl, AItem);
    end
    else
      Result := RandomHttp(vColl, AItem);
  except
    Result := False;
  end;
end;

procedure TQuickSampler.Execute;
const
  QueueSize = 3;
var
  vItem: TMediaItem;
begin
  while not Terminated and not FCatalog.Ready do
  begin
    if FCatalog.QuickCount >= QueueSize then
    begin
      Sleep(100);
      Continue;
    end;
    if RandomItem(vItem) then
      FCatalog.PushQuick(vItem)
    else
      Sleep(300);
  end;
end;

{ TScanThread }

constructor TScanThread.Create(ACatalog: TMediaCatalog);
begin
  inherited Create(False);
  FreeOnTerminate := False;
  FCatalog := ACatalog;
end;

destructor TScanThread.Destroy;
begin
  FreeAndNil(FSeen);
  FreeAndNil(FReachable);
  FreeAndNil(FPending);
  inherited;
end;

procedure TScanThread.FlushPending;
begin
  AppendCacheLines(FPending);
  FPending.Clear;
end;

procedure TScanThread.AddFile(const AColl: TMediaCollection; const ALocation: string);
var
  vKind: TMediaKind;
  vItem: TMediaItem;
begin
  if not MediaKindOfFile(ALocation, vKind) then
    Exit;
  FSeen.AddOrSetValue(ALocation, True);
  FReachable.AddOrSetValue(AColl.Name, True);
  if FCatalog.Contains(ALocation) then
    Exit;
  vItem := MakeItem(AColl, ALocation, vKind);
  FCatalog.Add(vItem);
  FPending.Add(FileCacheLine(vItem));
  if FPending.Count >= 500 then
    FlushPending;
end;

procedure TScanThread.ScanLocal(const AColl: TMediaCollection; const ADir: string);
var
  vSr: TSearchRec;
  vDir: string;
begin
  vDir := IncludeTrailingPathDelimiter(ADir);
  if FindFirst(vDir + '*', faAnyFile, vSr) = 0 then
  try
    repeat
      if Terminated then
        Exit;
      if (vSr.Name = '.') or (vSr.Name = '..') then
        Continue;
      if (vSr.Attr and faDirectory) <> 0 then
        ScanLocal(AColl, vDir + vSr.Name)
      else
        AddFile(AColl, vDir + vSr.Name);
    until FindNext(vSr) <> 0;
  finally
    FindClose(vSr);
  end;
end;

{ Lists one HTTP directory page: sub-directory URLs and media file URLs (inside the collection). }
procedure ListHttpDir(const AColl: TMediaCollection; const AUrl: string; ADirs, AFiles: TStrings);
var
  vClient: THTTPClient;
  vHtml, vHref, vFull: string;
  vMatch: TMatch;
  vBase: TURI;
  vKind: TMediaKind;
begin
  vClient := THTTPClient.Create;
  try
    vClient.ConnectionTimeout := 5000;
    vClient.ResponseTimeout := 10000;
    if AColl.User <> '' then
      vClient.CustomHeaders['Authorization'] :=
        'Basic ' + TNetEncoding.Base64String.Encode(AColl.User + ':' + AColl.Password);
    try
      vHtml := vClient.Get(AUrl).ContentAsString;
    except
      Exit;
    end;
  finally
    vClient.Free;
  end;
  vBase := TURI.Create(AUrl);
  for vMatch in TRegEx.Matches(vHtml, 'href\s*=\s*["'']([^"'']+)["'']', [roIgnoreCase]) do
  begin
    vHref := vMatch.Groups[1].Value;
    if (vHref = '') or CharInSet(vHref[1], ['?', '#']) or vHref.StartsWith('../') or
      vHref.StartsWith('mailto:') or (vHref = '/') then
      Continue;
    if vHref.StartsWith('http://', True) or vHref.StartsWith('https://', True) then
      vFull := vHref
    else if vHref.StartsWith('/') then
      vFull := vBase.Scheme + '://' + vBase.Host +
        IfThen(vBase.Port > 0, ':' + IntToStr(vBase.Port), '') + vHref
    else
      vFull := IncludeTrailingPathDelimiter(AUrl).Replace('\', '/') + vHref;
    if not vFull.StartsWith(AColl.Location, True) then
      Continue;
    if vFull.EndsWith('/') then
    begin
      if vFull.Length > AUrl.Length then
        ADirs.Add(vFull);
    end
    else if MediaKindOfFile(vFull, vKind) then
      AFiles.Add(vFull);
  end;
end;

procedure TScanThread.ScanHttp(const AColl: TMediaCollection; const AUrl: string; ADepth: Integer);
var
  vDirs, vFiles: TStringList;
  i: Integer;
begin
  if (ADepth > MaxDepth) or Terminated then
    Exit;
  vDirs := TStringList.Create;
  vFiles := TStringList.Create;
  try
    ListHttpDir(AColl, AUrl, vDirs, vFiles);
    for i := 0 to vFiles.Count - 1 do
      AddFile(AColl, vFiles[i]);
    for i := 0 to vDirs.Count - 1 do
      ScanHttp(AColl, vDirs[i], ADepth + 1);
  finally
    vDirs.Free;
    vFiles.Free;
  end;
end;

procedure TScanThread.ScanFtp(const AColl: TMediaCollection);
var
  vFtp: TIdFTP;
  vUri: TURI;
  vRoot: string;

  procedure Walk(const APath: string; ADepth: Integer);
  var
    i: Integer;
    vNames: TStringList;
    vDirs: TStringList;
    vItem: TIdFTPListItem;
    vKind: TMediaKind;
    vBasePath: string;
  begin
    if (ADepth > MaxDepth) or Terminated then
      Exit;
    vNames := TStringList.Create;
    vDirs := TStringList.Create;
    try
      vFtp.ChangeDir(APath);
      vFtp.List;
      for i := 0 to vFtp.DirectoryListing.Count - 1 do
      begin
        vItem := vFtp.DirectoryListing[i];
        if (vItem.FileName = '.') or (vItem.FileName = '..') then
          Continue;
        if vItem.ItemType = ditDirectory then
          vDirs.Add(vItem.FileName)
        else
          vNames.Add(vItem.FileName);
      end;
      vBasePath := APath;
      if not vBasePath.EndsWith('/') then
        vBasePath := vBasePath + '/';
      for i := 0 to vNames.Count - 1 do
        if MediaKindOfFile(vNames[i], vKind) then
          AddFile(AColl, 'ftp://' + vUri.Host + vBasePath + TNetEncoding.URL.Encode(vNames[i]));
      for i := 0 to vDirs.Count - 1 do
        Walk(vBasePath + vDirs[i], ADepth + 1);
    finally
      vNames.Free;
      vDirs.Free;
    end;
  end;

begin
  vUri := TURI.Create(AColl.Location);
  vRoot := vUri.Path;
  if vRoot = '' then
    vRoot := '/';
  vFtp := TIdFTP.Create(nil);
  try
    vFtp.Host := vUri.Host;
    if vUri.Port > 0 then
      vFtp.Port := Word(vUri.Port);
    vFtp.Passive := True;
    if AColl.User <> '' then
    begin
      vFtp.Username := AColl.User;
      vFtp.Password := AColl.Password;
    end
    else
    begin
      vFtp.Username := 'anonymous';
      vFtp.Password := 'myscreensaver@localhost';
    end;
    vFtp.ConnectTimeout := 10000;
    vFtp.ReadTimeout := 20000;
    try
      vFtp.Connect;
      Walk(vRoot, 0);
    except
      // unreachable server: skip this collection
    end;
    if vFtp.Connected then
      try
        vFtp.Disconnect;
      except
      end;
  finally
    vFtp.Free;
  end;
end;

procedure TScanThread.Execute;
var
  vColl: TMediaCollection;
  vList: TArray<TMediaCollection>;
begin
  FCatalog.Scanning := True;
  try
   try
    FSeen := TDictionary<string, Boolean>.Create(TIStringComparer.Ordinal);
    FReachable := TDictionary<string, Boolean>.Create(TIStringComparer.Ordinal);
    FPending := TStringList.Create;
    // 1. the previous scan result is usable at once
    LoadCatalogCache(FCatalog);
    // 2. refresh in the background: add new files, forget the removed ones
    vList := Settings.Collections.ToArray;
    for vColl in vList do
    begin
      if Terminated then
        Break;
      if not vColl.Enabled then
        Continue;
      try
        case vColl.Kind of
          skLocal, skNetwork:
            if DirectoryExists(vColl.Location) then
              ScanLocal(vColl, vColl.Location);
          skHttp:
            ScanHttp(vColl, vColl.Location, 0);
          skFtp:
            ScanFtp(vColl);
        end;
      except
        // ignore a failing collection
      end;
    end;
    FlushPending;
    if not Terminated then
      if FCatalog.RetainOnly(FSeen, FReachable) > 0 then
        RewriteCatalogCache(FCatalog);
  except
    // a failing scan must not crash the application
   end;
  finally
    FCatalog.Ready := True;
    FCatalog.Scanning := False;
  end;
end;

{ cache / metadata }

function CacheDir: string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'MyScreenSaver\cache');
  ForceDirectories(Result);
end;

procedure CleanCache;
var
  vFile: string;
begin
  try
    for vFile in TDirectory.GetFiles(CacheDir) do
      if TFile.GetLastWriteTime(vFile) < IncDay(Now, -1) then
        TFile.Delete(vFile);
  except
  end;
end;

function DownloadHttp(const AItem: TMediaItem; const ADest: string): Boolean;
var
  vClient: THTTPClient;
  vStream: TFileStream;
begin
  vClient := THTTPClient.Create;
  try
    if AItem.User <> '' then
      vClient.CustomHeaders['Authorization'] :=
        'Basic ' + TNetEncoding.Base64String.Encode(AItem.User + ':' + AItem.Password);
    vStream := TFileStream.Create(ADest, fmCreate);
    try
      Result := vClient.Get(AItem.Location, vStream).StatusCode = 200;
    finally
      vStream.Free;
    end;
  finally
    vClient.Free;
  end;
  if not Result then
    DeleteFile(ADest);
end;

function DownloadFtp(const AItem: TMediaItem; const ADest: string): Boolean;
var
  vFtp: TIdFTP;
  vUri: TURI;
begin
  vUri := TURI.Create(AItem.Location);
  vFtp := TIdFTP.Create(nil);
  try
    vFtp.Host := vUri.Host;
    if vUri.Port > 0 then
      vFtp.Port := Word(vUri.Port);
    vFtp.Passive := True;
    if AItem.User <> '' then
    begin
      vFtp.Username := AItem.User;
      vFtp.Password := AItem.Password;
    end
    else
    begin
      vFtp.Username := 'anonymous';
      vFtp.Password := 'myscreensaver@localhost';
    end;
    vFtp.ConnectTimeout := 10000;
    vFtp.ReadTimeout := 60000;
    vFtp.TransferType := ftBinary;
    try
      vFtp.Connect;
      vFtp.Get(TNetEncoding.URL.Decode(vUri.Path), ADest, True);
      Result := True;
    except
      Result := False;
    end;
    if vFtp.Connected then
      try
        vFtp.Disconnect;
      except
      end;
  finally
    vFtp.Free;
  end;
end;

function EnsureLocalFile(const AItem: TMediaItem): string;
var
  vExt: string;
  vOk: Boolean;
begin
  if not (AItem.SourceKind in [skHttp, skFtp]) then
    Exit(AItem.Location);
  vExt := ExtractFileExt(AItem.DisplayName);
  Result := TPath.Combine(CacheDir, THashMD5.GetHashString(AItem.Location) + vExt);
  if FileExists(Result) then
    Exit;
  if AItem.SourceKind = skHttp then
    vOk := DownloadHttp(AItem, Result)
  else
    vOk := DownloadFtp(AItem, Result);
  if not vOk then
    Result := '';
end;

function TryGetCachedMeta(const AItem: TMediaItem; out AMeta: TMediaMeta): Boolean;
begin
  Result := False;
  if GMetaCache = nil then
    Exit;
  GMetaLock.Enter;
  try
    Result := GMetaCache.TryGetValue(AItem.Location, AMeta);
  finally
    GMetaLock.Leave;
  end;
end;

procedure StartLocationDetection;
begin
  if not Settings.AutoLocate then
    Exit;
  TThread.CreateAnonymousThread(
    procedure
    var
      vLat, vLon: Double;
    begin
      if TryDetectLocationByIP(vLat, vLon) then
      begin
        Settings.CurLat := vLat;
        Settings.CurLon := vLon;
        Settings.CurValid := True;
      end;
    end).Start;
end;

function GetMediaMeta(const AItem: TMediaItem): TMediaMeta;
var
  vPath: string;
  vExif: TExifInfo;
  vDate: TDateTime;
begin
  if TryGetCachedMeta(AItem, Result) then
    Exit;
  Result := Default(TMediaMeta);
  // remote files are not downloaded just to evaluate rules
  if not (AItem.SourceKind in [skHttp, skFtp]) then
  begin
    vPath := AItem.Location;
    if AItem.Kind = mkPhoto then
    begin
      vExif := ReadExif(vPath);
      if vExif.HasDate then
      begin
        Result.HasDate := True;
        Result.Date := vExif.DateTaken;
      end;
      if vExif.HasGps then
      begin
        Result.HasGps := True;
        Result.Lat := vExif.Lat;
        Result.Lon := vExif.Lon;
      end;
    end;
    if not Result.HasDate then
      try
        vDate := TFile.GetLastWriteTime(vPath);
        if TFile.GetCreationTime(vPath) < vDate then
          vDate := TFile.GetCreationTime(vPath);
        Result.HasDate := True;
        Result.Date := vDate;
      except
      end;
  end;
  if GMetaCache = nil then
    Exit;
  GMetaLock.Enter;
  try
    GMetaCache.AddOrSetValue(AItem.Location, Result);
  finally
    GMetaLock.Leave;
  end;
end;

{ TMetaIndexer }

constructor TMetaIndexer.Create(ACatalog: TMediaCatalog);
begin
  inherited Create(False);
  FreeOnTerminate := False;
  FCatalog := ACatalog;
end;

procedure TMetaIndexer.Execute;
const
  BatchSize = 64;
var
  i, k, vCount: Integer;
  vItem: TMediaItem;
  vMeta: TMediaMeta;
  vBatch: TArray<TMediaItem>;
  vLines: TStringList;
begin
  vLines := TStringList.Create;
  try
    SetLength(vBatch, BatchSize);
    i := 0;
    while not Terminated do
    begin
      vCount := 0;
      while (vCount < BatchSize) and (i < FCatalog.Count) do
      begin
        vItem := FCatalog.Get(i);
        Inc(i);
        if not (vItem.SourceKind in [skHttp, skFtp]) then
          if not TryGetCachedMeta(vItem, vMeta) then
          begin
            vBatch[vCount] := vItem;
            Inc(vCount);
          end;
      end;
      if vCount > 0 then
      begin
        // index the batch on several cores, then append it to the cache file
        TParallel.For(0, vCount - 1,
          procedure(AIndex: Integer)
          begin
            GetMediaMeta(vBatch[AIndex]);
          end);
        vLines.Clear;
        for k := 0 to vCount - 1 do
          if TryGetCachedMeta(vBatch[k], vMeta) then
            vLines.Add(MetaCacheLine(vBatch[k].Location, vMeta));
        AppendCacheLines(vLines);
      end
      else if i >= FCatalog.Count then
      begin
        if FCatalog.Scanning then
          Sleep(200)
        else
          Break;
      end;
    end;
  finally
    vLines.Free;
  end;
end;

initialization
  GMetaLock := TCriticalSection.Create;
  GCacheLock := TCriticalSection.Create;
  GMetaCache := TDictionary<string, TMediaMeta>.Create;

finalization
  FreeAndNil(GCacheLock);
  FreeAndNil(GMetaCache);
  FreeAndNil(GMetaLock);

end.
