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
  PMediaMeta = ^TMediaMeta;

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
    function TryGetItem(const ALocation: string; out AItem: TMediaItem): Boolean;
    procedure Remove(const ALocation: string);
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
    FPhotosOnly: Boolean;
    function Wanted(AKind: TMediaKind): Boolean;
    function RandomLocal(const AColl: TMediaCollection; out AItem: TMediaItem): Boolean;
    function RandomHttp(const AColl: TMediaCollection; out AItem: TMediaItem): Boolean;
    function RandomItem(out AItem: TMediaItem): Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(ACatalog: TMediaCatalog);
    { the preview can only show photos }
    property PhotosOnly: Boolean read FPhotosOnly write FPhotosOnly;
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
{ True if the kind is wanted by the setting "photos / videos / both". }
function KindAllowed(AKind: TMediaKind): Boolean;
{ True if the path is inside one of the excluded folders (settings). }
function IsExcludedPath(const APath: string): Boolean;
{ Kind, excluded folders and RAW files together: may the item be shown? }
function ItemAllowed(const AItem: TMediaItem): Boolean;
{ Returns a local file path for the item; downloads remote files into the cache. }
function EnsureLocalFile(const AItem: TMediaItem): string;
function GetMediaMeta(const AItem: TMediaItem): TMediaMeta;
{ Cached metadata only (no file access). False if the file is not indexed yet. }
function TryGetCachedMeta(const AItem: TMediaItem; out AMeta: TMediaMeta): Boolean;
{ Optional IP-based location detection in a background thread. }
procedure StartLocationDetection;
procedure CleanCache;

const
  { Version of the format of catalog.cache (the first line of the file). A file without it, or with another
    number, is deleted and built again. }
  CatalogCacheVersion = 4;

var
  { Called (in the main thread) when the catalog cache was deleted because of its version. }
  OnCatalogCacheReset: TProc;

type
  TCacheStatus = record
    Files: Integer;        // files of the catalog
    WithMeta: Integer;     // files whose date/GPS are indexed
    Shown: Integer;        // files that were shown at least once
    Scanning: Boolean;     // the folders are being scanned
    FileBytes: Int64;      // size of the cache file
  end;

{ Cache 4 (history.cache): the files that were shown, the oldest first, for the key "back" after a restart. }
function LoadHistoryLocations(AMax: Integer): TArray<string>;   // the last AMax files
procedure AppendHistoryLocation(const ALocation: string);

{ Cache 2 (shown.cache): how many times each file was shown. }
function ShownTimes(const ALocation: string): Integer;
function IsShown(const ALocation: string): Boolean;
procedure MarkShown(const ALocation: string);   // the counter + 1
{ The counters are deleted: nothing was shown. }
procedure ResetShown;
function ShownCount: Integer;                   // files that were shown at least once
{ The random order shows the files whose counter is not above this level first (see uRules). }
function ShownLevel: Integer;
procedure SetShownLevel(ALevel: Integer);
{ Deletes both caches and the cached data (file list, date/GPS, places, shown counters).
  The scan threads must not run. }
procedure ClearCacheData;
function GetCacheStatus(ACatalog: TMediaCatalog): TCacheStatus;

implementation

uses
  System.IOUtils, System.Math, System.StrUtils, System.Hash, System.NetEncoding, System.RegularExpressions, System.DateUtils,
  System.Threading, System.Net.HttpClient, System.Net.URLClient, IdFTP, IdFTPList, IdFTPCommon, uExif, uLocation;

const
  PhotoExts: array[0..9] of string =
    ('.jpg', '.jpeg', '.png', '.bmp', '.gif', '.tif', '.tiff', '.heic', '.webp', '.jfif');
  VideoExts: array[0..7] of string =
    ('.mp4', '.avi', '.wmv', '.mov', '.mkv', '.mpg', '.mpeg', '.m4v');
  RawExts: array[0..24] of string =
    ('.arw', '.dng', '.cr2', '.cr3', '.crw', '.nef', '.nrw', '.orf', '.raf', '.rw2', '.rwl', '.pef', '.srw',
     '.srf', '.sr2', '.raw', '.3fr', '.erf', '.kdc', '.dcr', '.mrw', '.x3f', '.mef', '.mos', '.iiq');
  MaxDepth = 6;

var
  GMetaLock: TCriticalSection;
  GMetaCache: TDictionary<string, TMediaMeta>;
  GShownLock: TCriticalSection;
  GShownFileLock: TCriticalSection;
  GShown: TDictionary<string, Integer>;
  GShownLevel: Integer;
  GShownBloated: Boolean;      // shown.cache has many more lines than files: it is rewritten

function IsRawExt(const AExt: string): Boolean;
var
  s: string;
begin
  for s in RawExts do
    if s = AExt then
      Exit(True);
  Result := False;
end;

function MediaKindOfFile(const AName: string; out AKind: TMediaKind): Boolean;
var
  vExt, s: string;
  vName: string;
begin
  vName := AName;
  if Pos('?', vName) > 0 then
    vName := Copy(vName, 1, Pos('?', vName) - 1);
  vExt := LowerCase(ExtractFileExt(vName));
  if IsRawExt(vExt) then
  begin
    // RAW files are photos only if they are not excluded (they need a codec of Windows to be shown)
    Result := not Settings.ExcludeRaw;
    if Result then
      AKind := mkPhoto;
    Exit;
  end;
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

function KindAllowed(AKind: TMediaKind): Boolean;
begin
  case Settings.MediaTypes of
    mtPhotos: Result := AKind = mkPhoto;
    mtVideos: Result := AKind = mkVideo;
  else
    Result := True;
  end;
end;

function IsExcludedPath(const APath: string): Boolean;
var
  i: Integer;
  vPath, vFolder: string;
begin
  Result := False;
  if Settings.ExcludedFolders.Count = 0 then
    Exit;
  vPath := APath.TrimRight(['\', '/']);
  i := 0;
  while i < Settings.ExcludedFolders.Count do
  begin
    vFolder := Trim(Settings.ExcludedFolders[i]).TrimRight(['\', '/']);
    Inc(i);
    if vFolder = '' then
      Continue;
    if SameText(vPath, vFolder) or vPath.StartsWith(vFolder + '\', True) or
      vPath.StartsWith(vFolder + '/', True) then
      Exit(True);
  end;
end;

function ItemAllowed(const AItem: TMediaItem): Boolean;
begin
  Result := KindAllowed(AItem.Kind) and not IsExcludedPath(AItem.Location);
  if Result and Settings.ExcludeRaw and IsRawExt(LowerCase(ExtractFileExt(AItem.Location))) then
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

procedure TMediaCatalog.Remove(const ALocation: string);
var
  vIdx, i: Integer;
begin
  FLock.Enter;
  try
    if FIndex.TryGetValue(ALocation, vIdx) then
    begin
      FItems.Delete(vIdx);
      FIndex.Remove(ALocation);
      for i := vIdx to Integer(FItems.Count) - 1 do   // the items after it have moved
        FIndex[FItems[i].Location] := i;
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

function TMediaCatalog.TryGetItem(const ALocation: string; out AItem: TMediaItem): Boolean;
var
  vIdx: Integer;
begin
  FLock.Enter;
  try
    Result := FIndex.TryGetValue(ALocation, vIdx);
    if Result then
      AItem := FItems[vIdx];
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
  Cache 1, catalog.cache. The first line is the header with the version and the summary:
  Version<TAB>number<TAB>photos=N<TAB>videos=N<TAB>hasdate=N<TAB>hasgps=N
  the second line has the names of the columns, then follows one record per file (the last line of a file wins):
  F<TAB>location<TAB>kind<TAB>has-date<TAB>date<TAB>has-GPS<TAB>lat<TAB>lon
  (the place names are in places.cache, see uLocation)
  A new file is first written as F<TAB>location<TAB>kind only (not indexed yet); the indexer adds the rest. }

var
  GCacheLock: TCriticalSection;

function CatalogCachePath: string;
begin
  Result := TPath.Combine(ExtractFilePath(TAppSettings.ConfigPath), 'catalog.cache');
end;

function HeaderLine(APhotos, AVideos, AWithDate, AWithGps: Integer): string;
begin
  Result := Format('Version'#9'%d'#9'photos=%d'#9'videos=%d'#9'hasdate=%d'#9'hasgps=%d',
    [CatalogCacheVersion, APhotos, AVideos, AWithDate, AWithGps]);
end;

{ The second line of the file: the names of the columns of the records. }
function ColumnsLine: string;
begin
  Result := 'Record'#9'File'#9'Kind'#9'HasDate'#9'Date'#9'HasGPS'#9'Lat'#9'Lon';
end;

{ The record of a file: without AMeta (nil) only the file and its kind. }
function FileCacheLine(const AItem: TMediaItem; AMeta: PMediaMeta = nil): string;
begin
  Result := 'F'#9 + AItem.Location + #9 + IfThen(AItem.Kind = mkVideo, '1', '0');
  if AMeta <> nil then
    Result := Result + Format(#9'%d'#9'%s'#9'%d'#9'%s'#9'%s',
      [Ord(AMeta.HasDate), FloatToStr(AMeta.Date, TFormatSettings.Invariant),
       Ord(AMeta.HasGps), FloatToStr(AMeta.Lat, TFormatSettings.Invariant),
       FloatToStr(AMeta.Lon, TFormatSettings.Invariant)]);
end;

procedure AppendCacheLines(ALines: TStrings);
var
  vWriter: TStreamWriter;
  i: Integer;
  vNew: Boolean;
begin
  if ALines.Count = 0 then
    Exit;
  GCacheLock.Enter;
  try
    try
      vNew := not FileExists(CatalogCachePath);
      vWriter := TStreamWriter.Create(CatalogCachePath, True, TEncoding.UTF8);
      try
        if vNew then
        begin
          vWriter.WriteLine(HeaderLine(0, 0, 0, 0));   // a file always starts with its header
          vWriter.WriteLine(ColumnsLine);
        end;
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
  vPhotos, vVideos, vWithDate, vWithGps: Integer;
begin
  vItems := ACatalog.Snapshot;
  vTmp := CatalogCachePath + '.tmp';
  vPhotos := 0;
  vVideos := 0;
  vWithDate := 0;
  vWithGps := 0;
  for vItem in vItems do
  begin
    if vItem.Kind = mkVideo then
      Inc(vVideos)
    else
      Inc(vPhotos);
    if TryGetCachedMeta(vItem, vMeta) then
    begin
      if vMeta.HasDate then
        Inc(vWithDate);
      if vMeta.HasGps then
        Inc(vWithGps);
    end;
  end;
  GCacheLock.Enter;
  try
    try
      vWriter := TStreamWriter.Create(vTmp, False, TEncoding.UTF8);
      try
        vWriter.WriteLine(HeaderLine(vPhotos, vVideos, vWithDate, vWithGps));
        vWriter.WriteLine(ColumnsLine);
        for vItem in vItems do
        begin
          if TryGetCachedMeta(vItem, vMeta) then
            vWriter.WriteLine(FileCacheLine(vItem, @vMeta))
          else
            vWriter.WriteLine(FileCacheLine(vItem));
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

{ Loads the previous scan result: the catalog becomes usable immediately.
  Returns True if the file has duplicates / stale entries and should be rewritten (compacted). }
function LoadCatalogCache(ACatalog: TMediaCatalog): Boolean;
var
  vReader: TStreamReader;
  vLine: string;
  vParts: TArray<string>;
  vItems: TList<TMediaItem>;
  vColls: TArray<TMediaCollection>;
  vMeta: TMediaMeta;
  vKind: TMediaKind;
  i, vCollIdx, vFileLines, vSkipped: Integer;
  vBadVersion: Boolean;
begin
  Result := False;
  vFileLines := 0;
  vSkipped := 0;
  vBadVersion := False;
  if not FileExists(CatalogCachePath) then
    Exit;
  vColls := Settings.Collections.ToArray;
  vItems := TList<TMediaItem>.Create;
  try
    try
      vReader := TStreamReader.Create(CatalogCachePath, TEncoding.UTF8);
      try
        // the first line is the header: a file without it, or of another version, is not read
        if vReader.EndOfStream then
          vLine := ''
        else
          vLine := vReader.ReadLine;
        vParts := vLine.Split([#9]);
        vBadVersion := not ((Length(vParts) >= 2) and (vParts[0] = 'Version') and (vParts[1] = IntToStr(CatalogCacheVersion)));
        while not vBadVersion and not vReader.EndOfStream do
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
            Inc(vFileLines);
            if IsExcludedPath(vParts[1]) or
              (Settings.ExcludeRaw and IsRawExt(LowerCase(ExtractFileExt(vParts[1])))) then
            begin
              Inc(vSkipped);   // a newly excluded folder / RAW files: the file is rewritten without them
              Continue;
            end;
            if vCollIdx < 0 then
            begin
              Inc(vSkipped);
              Continue;
            end;
            if vParts[2] = '1' then
              vKind := mkVideo
            else
              vKind := mkPhoto;
            vItems.Add(MakeItem(vColls[vCollIdx], vParts[1], vKind));
            if Length(vParts) >= 8 then
            begin
              vMeta := Default(TMediaMeta);
              vMeta.HasDate := vParts[3] = '1';
              vMeta.Date := StrToFloatDef(vParts[4], 0, TFormatSettings.Invariant);
              vMeta.HasGps := vParts[5] = '1';
              vMeta.Lat := StrToFloatDef(vParts[6], 0, TFormatSettings.Invariant);
              vMeta.Lon := StrToFloatDef(vParts[7], 0, TFormatSettings.Invariant);
              PutMetaCache(vParts[1], vMeta);
            end;
          end;
        end;
      finally
        vReader.Free;
      end;
    except
    end;
    if vBadVersion then
    begin
      // the old cache is deleted, the scan builds a new one; the user is told in the main thread
      GCacheLock.Enter;
      try
        try
          TFile.Delete(CatalogCachePath);
        except
        end;
      finally
        GCacheLock.Leave;
      end;
      TThread.Queue(nil,
        procedure
        begin
          if Assigned(OnCatalogCacheReset) then
            OnCatalogCacheReset();
        end);
      Exit(True);
    end;
    ACatalog.AddRange(vItems);
    if ACatalog.Count > 0 then
      ACatalog.Ready := True;
    // many more F lines than distinct files, or entries of removed collections
    Result := (vSkipped > 0) or (vFileLines > ACatalog.Count + ACatalog.Count div 4);
  finally
    vItems.Free;
  end;
end;

{ ---- cache 2: how many times a file was shown (shown.cache: file TAB count, the last line of a file wins) ---- }

function ShownCachePath: string;
begin
  Result := TPath.Combine(ExtractFilePath(TAppSettings.ConfigPath), 'shown.cache');
end;

function ShownTimes(const ALocation: string): Integer;
begin
  GShownLock.Enter;
  try
    if not GShown.TryGetValue(ALocation, Result) then
      Result := 0;
  finally
    GShownLock.Leave;
  end;
end;

function IsShown(const ALocation: string): Boolean;
begin
  Result := ShownTimes(ALocation) > 0;
end;

function ShownCount: Integer;
begin
  GShownLock.Enter;
  try
    Result := GShown.Count;
  finally
    GShownLock.Leave;
  end;
end;

function ShownLevel: Integer;
begin
  Result := GShownLevel;
end;

procedure SetShownLevel(ALevel: Integer);
begin
  GShownLevel := ALevel;
end;

procedure AppendShownLine(const ALine: string);
var
  vWriter: TStreamWriter;
begin
  GShownFileLock.Enter;
  try
    try
      vWriter := TStreamWriter.Create(ShownCachePath, True, TEncoding.UTF8);
      try
        vWriter.WriteLine(ALine);
      finally
        vWriter.Free;
      end;
    except
    end;
  finally
    GShownFileLock.Leave;
  end;
end;

procedure MarkShown(const ALocation: string);
var
  vCount: Integer;
begin
  GShownLock.Enter;
  try
    if not GShown.TryGetValue(ALocation, vCount) then
      vCount := 0;
    Inc(vCount);
    GShown.AddOrSetValue(ALocation, vCount);
  finally
    GShownLock.Leave;
  end;
  AppendShownLine(ALocation + #9 + IntToStr(vCount));
end;

{ Nothing counts as shown any more: the counters are deleted. }
procedure ResetShown;
begin
  GShownLock.Enter;
  try
    GShown.Clear;
  finally
    GShownLock.Leave;
  end;
  GShownLevel := 0;
  GShownFileLock.Enter;
  try
    try
      if FileExists(ShownCachePath) then
        TFile.Delete(ShownCachePath);
    except
    end;
  finally
    GShownFileLock.Leave;
  end;
end;

procedure ClearCacheData;
begin
  ResetShown;
  GMetaLock.Enter;
  try
    GMetaCache.Clear;
  finally
    GMetaLock.Leave;
  end;
  GCacheLock.Enter;
  try
    try
      if FileExists(CatalogCachePath) then
        TFile.Delete(CatalogCachePath);
    except
    end;
  finally
    GCacheLock.Leave;
  end;
end;

{ Reads shown.cache. }
procedure LoadShownCache;
var
  vParts: TArray<string>;
  vLine: string;
  vLines, vCount: Integer;
begin
  vLines := 0;
  GShownBloated := False;
  if not FileExists(ShownCachePath) then
    Exit;
  try
    for vLine in TFile.ReadAllLines(ShownCachePath, TEncoding.UTF8) do
    begin
      vParts := vLine.Split([#9]);
      if Length(vParts) < 2 then
        Continue;
      Inc(vLines);
      vCount := StrToIntDef(vParts[1], 0);
      GShownLock.Enter;
      try
        if vCount > 0 then
          GShown.AddOrSetValue(vParts[0], vCount);
      finally
        GShownLock.Leave;
      end;
    end;
  except
  end;
  GShownBloated := vLines > ShownCount + ShownCount div 4 + 100;
end;

{ The register of an older version (shown.log) becomes counters of 1. }
procedure ImportLegacyShown;
var
  vPath, vLine: string;
begin
  vPath := TPath.Combine(ExtractFilePath(TAppSettings.ConfigPath), 'shown.log');
  if not FileExists(vPath) then
    Exit;
  try
    for vLine in TFile.ReadAllLines(vPath, TEncoding.UTF8) do
      if (vLine <> '') and not IsShown(vLine) then
        MarkShown(vLine);
    TFile.Delete(vPath);
  except
  end;
end;

{ Rewrites shown.cache with one line per file of the catalog (counters of files that are gone are dropped). }
procedure CompactShownCache(ACatalog: TMediaCatalog);
var
  vItem: TMediaItem;
  vCount: Integer;
  vNew: TDictionary<string, Integer>;
  vPair: TPair<string, Integer>;
  vWriter: TStreamWriter;
  vTmp: string;
begin
  vNew := TDictionary<string, Integer>.Create(TIStringComparer.Ordinal);
  try
    for vItem in ACatalog.Snapshot do
    begin
      vCount := ShownTimes(vItem.Location);
      if vCount > 0 then
        vNew.AddOrSetValue(vItem.Location, vCount);
    end;
    vTmp := ShownCachePath + '.tmp';
    GShownFileLock.Enter;
    try
      try
        if vNew.Count = 0 then
        begin
          if FileExists(ShownCachePath) then
            TFile.Delete(ShownCachePath);
        end
        else
        begin
          vWriter := TStreamWriter.Create(vTmp, False, TEncoding.UTF8);
          try
            for vPair in vNew do
              vWriter.WriteLine(vPair.Key + #9 + IntToStr(vPair.Value));
          finally
            vWriter.Free;
          end;
          TFile.Copy(vTmp, ShownCachePath, True);
          TFile.Delete(vTmp);
        end;
      except
      end;
    finally
      GShownFileLock.Leave;
    end;
    GShownLock.Enter;
    try
      GShown.Clear;
      for vPair in vNew do
        GShown.Add(vPair.Key, vPair.Value);
    finally
      GShownLock.Leave;
    end;
  finally
    vNew.Free;
  end;
end;

{ ---- cache 4: the files that were shown, for the key "back" (history.cache) ----
  Version<TAB>1
  File                                   (the names of the columns)
  then one line per shown file, the oldest first (a file can be there several times) }

const
  HistoryCacheVersion = 1;

var
  GHistoryLock: TCriticalSection;

function HistoryCachePath: string;
begin
  Result := TPath.Combine(ExtractFilePath(TAppSettings.ConfigPath), 'history.cache');
end;

function HistoryHeader: string;
begin
  Result := 'Version'#9 + IntToStr(HistoryCacheVersion) + #13#10 + 'File';
end;

procedure AppendHistoryLocation(const ALocation: string);
var
  vWriter: TStreamWriter;
  vNew: Boolean;
begin
  if ALocation = '' then
    Exit;
  GHistoryLock.Enter;
  try
    try
      vNew := not FileExists(HistoryCachePath);
      vWriter := TStreamWriter.Create(HistoryCachePath, True, TEncoding.UTF8);
      try
        if vNew then
          vWriter.WriteLine(HistoryHeader);
        vWriter.WriteLine(ALocation);
      finally
        vWriter.Free;
      end;
    except
    end;
  finally
    GHistoryLock.Leave;
  end;
end;

{ The last AMax files; the file is rewritten when it has many more lines than that. A file of another
  version is deleted. }
function LoadHistoryLocations(AMax: Integer): TArray<string>;
var
  vLines: TArray<string>;
  vParts: TArray<string>;
  vWriter: TStreamWriter;
  vFrom, i: Integer;
begin
  Result := nil;
  if AMax <= 0 then
    Exit;
  GHistoryLock.Enter;
  try
    try
      if not FileExists(HistoryCachePath) then
        Exit;
      vLines := TFile.ReadAllLines(HistoryCachePath, TEncoding.UTF8);
      vParts := nil;
      if Length(vLines) > 0 then
        vParts := vLines[0].Split([#9]);
      if (Length(vParts) < 2) or (vParts[0] <> 'Version') or (vParts[1] <> IntToStr(HistoryCacheVersion)) then
      begin
        TFile.Delete(HistoryCachePath);
        Exit;
      end;
      vFrom := Max(2, Length(vLines) - AMax);
      SetLength(Result, Length(vLines) - vFrom);
      for i := vFrom to High(vLines) do
        Result[i - vFrom] := vLines[i];
      if vFrom > 2 + AMax then
      begin
        // many more lines than needed: only the last ones are kept
        vWriter := TStreamWriter.Create(HistoryCachePath, False, TEncoding.UTF8);
        try
          vWriter.WriteLine(HistoryHeader);
          for i := 0 to High(Result) do
            vWriter.WriteLine(Result[i]);
        finally
          vWriter.Free;
        end;
      end;
    except
    end;
  finally
    GHistoryLock.Leave;
  end;
end;

function GetCacheStatus(ACatalog: TMediaCatalog): TCacheStatus;
begin
  Result := Default(TCacheStatus);
  Result.Files := ACatalog.Count;
  Result.Scanning := ACatalog.Scanning;
  Result.Shown := ShownCount;
  if GMetaCache <> nil then
  begin
    GMetaLock.Enter;
    try
      Result.WithMeta := GMetaCache.Count;
    finally
      GMetaLock.Leave;
    end;
  end;
  try
    if FileExists(CatalogCachePath) then
      Result.FileBytes := TFile.GetSize(CatalogCachePath);
  except
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

function TQuickSampler.Wanted(AKind: TMediaKind): Boolean;
begin
  if FPhotosOnly then
    Result := AKind = mkPhoto
  else
    Result := KindAllowed(AKind);
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
            begin
              if not IsExcludedPath(vPath + vSr.Name) then
                vDirs.Add(vSr.Name);
            end
          else if MediaKindOfFile(vSr.Name, vKind) and Wanted(vKind) then
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
        MediaKindOfFile(vFiles[vPick], vKind);
        AItem := MakeItem(AColl, vPath + vFiles[vPick], vKind);
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
        if MediaKindOfFile(vFiles[i], vKind) and Wanted(vKind) then
          vPhotos.Add(vFiles[i]);
      vTotal := vDirs.Count + vPhotos.Count;
      if vTotal = 0 then
        Exit;
      vPick := Random(vTotal);
      if vPick < vPhotos.Count then
      begin
        MediaKindOfFile(vPhotos[vPick], vKind);
        AItem := MakeItem(AColl, vPhotos[vPick], vKind);
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
  if IsExcludedPath(ADir) then
    Exit;
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
        if not IsExcludedPath(vFull) then
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
        if not IsExcludedPath('ftp://' + vUri.Host + vBasePath + vDirs[i]) then
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
  vRemoved: Integer;
begin
  FCatalog.Scanning := True;
  try
   try
    FSeen := TDictionary<string, Boolean>.Create(TIStringComparer.Ordinal);
    FReachable := TDictionary<string, Boolean>.Create(TIStringComparer.Ordinal);
    FPending := TStringList.Create;
    // 1. the previous scan result is usable at once
    LoadShownCache;
    LoadCatalogCache(FCatalog);
    ImportLegacyShown;
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
    begin
      vRemoved := FCatalog.RetainOnly(FSeen, FReachable);
      RewriteCatalogCache(FCatalog);   // one line per file and the header with the summary
      if (vRemoved > 0) or GShownBloated then
        CompactShownCache(FCatalog);
    end;
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
  vIndexed: Boolean;
begin
  vLines := TStringList.Create;
  vIndexed := False;
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
            vLines.Add(FileCacheLine(vBatch[k], @vMeta));
        AppendCacheLines(vLines);
        vIndexed := True;
      end
      else if i >= FCatalog.Count then
      begin
        if FCatalog.Scanning then
          Sleep(200)
        else
          Break;
      end;
    end;
    // everything is indexed: the header of the cache gets the new summary
    if vIndexed and not Terminated then
      RewriteCatalogCache(FCatalog);
  finally
    vLines.Free;
  end;
end;

initialization
  GMetaLock := TCriticalSection.Create;
  GCacheLock := TCriticalSection.Create;
  GMetaCache := TDictionary<string, TMediaMeta>.Create;
  GShownLock := TCriticalSection.Create;
  GShown := TDictionary<string, Integer>.Create(TIStringComparer.Ordinal);
  GShownFileLock := TCriticalSection.Create;
  GHistoryLock := TCriticalSection.Create;

finalization
  FreeAndNil(GShown);
  FreeAndNil(GShownFileLock);
  FreeAndNil(GHistoryLock);
  FreeAndNil(GShownLock);
  FreeAndNil(GCacheLock);
  FreeAndNil(GMetaCache);
  FreeAndNil(GMetaLock);

end.
