unit uExif;

{ Minimal EXIF reader for JPEG files (no external dependencies). }

interface

type
  TExifInfo = record
    Valid: Boolean;
    Make: string;
    Model: string;
    Lens: string;
    XPKeywords: string;   // EXIF XPKeywords (Windows "Tags")
    Keywords: string;     // IPTC Keywords + XMP dc:subject
    HasDate: Boolean;
    DateTaken: TDateTime;
    Exposure: string;
    FNumber: string;
    ISO: string;
    FocalLength: string;
    Width: Integer;
    Height: Integer;
    Orientation: Integer;
    HasGps: Boolean;
    Lat: Double;
    Lon: Double;
  end;

function ReadExif(const AFileName: string): TExifInfo;

implementation

uses
  System.SysUtils, System.Classes, System.Math, System.RegularExpressions;

type
  TTiffReader = class
  private
    FData: TBytes;
    FBase: Integer;
    FBig: Boolean;
    function U8(AOff: Integer): Integer;
    function U16(AOff: Integer): Integer;
    function U32(AOff: Integer): Cardinal;
    function TypeSize(AType: Integer): Integer;
    function ValueOffset(AEntry: Integer): Integer;
    function FindEntry(AIfd: Integer; ATag: Integer): Integer;
    function AsciiTag(AIfd, ATag: Integer): string;
    function RationalAt(AValOff: Integer; AIndex: Integer): Double;
    function RationalTag(AIfd, ATag: Integer): Double;
    function IntTag(AIfd, ATag: Integer): Integer;
    function UnicodeTag(AIfd, ATag: Integer): string;
    function GpsCoord(AIfd, ATagRef, ATagVal: Integer; out AValue: Double): Boolean;
    procedure Parse(var AInfo: TExifInfo);
  public
    constructor Create(const AData: TBytes; ABase: Integer);
    procedure Fill(var AInfo: TExifInfo);
  end;

function ParseExifDate(const S: string; out ADate: TDateTime): Boolean;
var
  vY, vM, vD, vH, vN, vS: Integer;
  vDate, vTime: TDateTime;
begin
  Result := False;
  if Length(S) < 19 then
    Exit;
  vY := StrToIntDef(Copy(S, 1, 4), 0);
  vM := StrToIntDef(Copy(S, 6, 2), 0);
  vD := StrToIntDef(Copy(S, 9, 2), 0);
  vH := StrToIntDef(Copy(S, 12, 2), 0);
  vN := StrToIntDef(Copy(S, 15, 2), 0);
  vS := StrToIntDef(Copy(S, 18, 2), 0);
  if (vY < 1) or (vY > 9999) or (vM < 1) or (vM > 12) or (vD < 1) or (vD > 31) then
    Exit;
  if not TryEncodeDate(Word(vY), Word(vM), Word(vD), vDate) then
    Exit;
  if not TryEncodeTime(Word(vH and 31), Word(vN and 63), Word(vS and 63), 0, vTime) then
    vTime := 0;
  ADate := vDate + vTime;
  Result := True;
end;

{ TTiffReader }

constructor TTiffReader.Create(const AData: TBytes; ABase: Integer);
begin
  inherited Create;
  FData := AData;
  FBase := ABase;
  FBig := False;
end;

function TTiffReader.U8(AOff: Integer): Integer;
begin
  if (FBase + AOff < 0) or (FBase + AOff >= Length(FData)) then
    Result := 0
  else
    Result := FData[FBase + AOff];
end;

function TTiffReader.U16(AOff: Integer): Integer;
begin
  if FBig then
    Result := (U8(AOff) shl 8) or U8(AOff + 1)
  else
    Result := (U8(AOff + 1) shl 8) or U8(AOff);
end;

function TTiffReader.U32(AOff: Integer): Cardinal;
begin
  if FBig then
    Result := (Cardinal(U16(AOff)) shl 16) or Cardinal(U16(AOff + 2))
  else
    Result := (Cardinal(U16(AOff + 2)) shl 16) or Cardinal(U16(AOff));
end;

function TTiffReader.TypeSize(AType: Integer): Integer;
begin
  case AType of
    1, 2, 6, 7: Result := 1;
    3, 8: Result := 2;
    4, 9, 11: Result := 4;
    5, 10, 12: Result := 8;
  else
    Result := 1;
  end;
end;

function TTiffReader.ValueOffset(AEntry: Integer): Integer;
var
  vSize: Int64;
begin
  vSize := Int64(TypeSize(U16(AEntry + 2))) * U32(AEntry + 4);
  if vSize <= 4 then
    Result := AEntry + 8
  else
    Result := Integer(U32(AEntry + 8));
end;

function TTiffReader.FindEntry(AIfd, ATag: Integer): Integer;
var
  vCount, i: Integer;
begin
  Result := -1;
  if AIfd <= 0 then
    Exit;
  vCount := U16(AIfd);
  if vCount > 500 then
    Exit;
  for i := 0 to vCount - 1 do
    if U16(AIfd + 2 + i * 12) = ATag then
      Exit(AIfd + 2 + i * 12);
end;

function TTiffReader.AsciiTag(AIfd, ATag: Integer): string;
var
  vEntry, vOff, vLen, i: Integer;
  vBytes: TBytes;
begin
  Result := '';
  vEntry := FindEntry(AIfd, ATag);
  if vEntry < 0 then
    Exit;
  vLen := Integer(U32(vEntry + 4));
  if (vLen <= 0) or (vLen > 4096) then
    Exit;
  vOff := ValueOffset(vEntry);
  SetLength(vBytes, vLen);
  for i := 0 to vLen - 1 do
    vBytes[i] := Byte(U8(vOff + i));
  Result := Trim(TEncoding.ANSI.GetString(vBytes).TrimRight([#0]));
end;

function TTiffReader.RationalAt(AValOff, AIndex: Integer): Double;
var
  vNum, vDen: Cardinal;
begin
  vNum := U32(AValOff + AIndex * 8);
  vDen := U32(AValOff + AIndex * 8 + 4);
  if vDen = 0 then
    Result := 0
  else
    Result := vNum / vDen;
end;

function TTiffReader.RationalTag(AIfd, ATag: Integer): Double;
var
  vEntry: Integer;
begin
  Result := 0;
  vEntry := FindEntry(AIfd, ATag);
  if vEntry >= 0 then
    Result := RationalAt(ValueOffset(vEntry), 0);
end;

function TTiffReader.IntTag(AIfd, ATag: Integer): Integer;
var
  vEntry: Integer;
begin
  Result := 0;
  vEntry := FindEntry(AIfd, ATag);
  if vEntry < 0 then
    Exit;
  if U16(vEntry + 2) = 3 then
    Result := U16(vEntry + 8)
  else
    Result := Integer(U32(vEntry + 8));
end;

function TTiffReader.UnicodeTag(AIfd, ATag: Integer): string;
var
  vEntry, vOff, vLen, i: Integer;
  vBytes: TBytes;
begin
  Result := '';
  vEntry := FindEntry(AIfd, ATag);
  if vEntry < 0 then
    Exit;
  vLen := Integer(U32(vEntry + 4));
  if (vLen <= 1) or (vLen > 65536) then
    Exit;
  vOff := ValueOffset(vEntry);
  SetLength(vBytes, vLen);
  for i := 0 to vLen - 1 do
    vBytes[i] := Byte(U8(vOff + i));
  Result := Trim(TEncoding.Unicode.GetString(vBytes).TrimRight([#0]));
end;

function TTiffReader.GpsCoord(AIfd, ATagRef, ATagVal: Integer; out AValue: Double): Boolean;
var
  vEntry, vOff: Integer;
  vRef: string;
begin
  Result := False;
  AValue := 0;
  vEntry := FindEntry(AIfd, ATagVal);
  if vEntry < 0 then
    Exit;
  vOff := ValueOffset(vEntry);
  AValue := RationalAt(vOff, 0) + RationalAt(vOff, 1) / 60 + RationalAt(vOff, 2) / 3600;
  vRef := AsciiTag(AIfd, ATagRef);
  if (vRef = 'S') or (vRef = 'W') then
    AValue := -AValue;
  Result := True;
end;

procedure TTiffReader.Parse(var AInfo: TExifInfo);
var
  vIfd0, vExif, vGps: Integer;
  vEntry: Integer;
  vS: string;
  vExp: Double;
  vLat, vLon: Double;
begin
  vIfd0 := Integer(U32(4));
  AInfo.Make := AsciiTag(vIfd0, $010F);
  AInfo.Model := AsciiTag(vIfd0, $0110);
  AInfo.Orientation := IntTag(vIfd0, $0112);
  AInfo.XPKeywords := UnicodeTag(vIfd0, $9C9E);
  vS := AsciiTag(vIfd0, $0132);
  if ParseExifDate(vS, AInfo.DateTaken) then
    AInfo.HasDate := True;

  vEntry := FindEntry(vIfd0, $8769);
  if vEntry >= 0 then
  begin
    vExif := Integer(U32(vEntry + 8));
    vS := AsciiTag(vExif, $9003);
    if ParseExifDate(vS, AInfo.DateTaken) then
      AInfo.HasDate := True;
    vExp := RationalTag(vExif, $829A);
    if vExp > 0 then
    begin
      if vExp < 1 then
        AInfo.Exposure := Format('1/%d с', [Round(1 / vExp)])
      else
        AInfo.Exposure := FormatFloat('0.#', vExp) + ' с';
    end;
    vExp := RationalTag(vExif, $829D);
    if vExp > 0 then
      AInfo.FNumber := 'f/' + FormatFloat('0.#', vExp);
    if IntTag(vExif, $8827) > 0 then
      AInfo.ISO := IntToStr(IntTag(vExif, $8827));
    vExp := RationalTag(vExif, $920A);
    if vExp > 0 then
      AInfo.FocalLength := FormatFloat('0.#', vExp) + ' мм';
    AInfo.Width := IntTag(vExif, $A002);
    AInfo.Height := IntTag(vExif, $A003);
    AInfo.Lens := AsciiTag(vExif, $A434);
  end;

  vEntry := FindEntry(vIfd0, $8825);
  if vEntry >= 0 then
  begin
    vGps := Integer(U32(vEntry + 8));
    if GpsCoord(vGps, 1, 2, vLat) and GpsCoord(vGps, 3, 4, vLon) then
      if not ((vLat = 0) and (vLon = 0)) then
      begin
        AInfo.HasGps := True;
        AInfo.Lat := vLat;
        AInfo.Lon := vLon;
      end;
  end;
  AInfo.Valid := True;
end;

procedure TTiffReader.Fill(var AInfo: TExifInfo);
begin
  if (U8(0) = Ord('I')) and (U8(1) = Ord('I')) then
    FBig := False
  else if (U8(0) = Ord('M')) and (U8(1) = Ord('M')) then
    FBig := True
  else
    Exit;
  if U16(2) <> 42 then
    Exit;
  Parse(AInfo);
end;

{ ---- keywords: IPTC (APP13) and XMP (APP1) ---- }

function DecodeText(const ABytes: TBytes): string;
begin
  if Length(ABytes) = 0 then
    Exit('');
  Result := TEncoding.UTF8.GetString(ABytes);
  if Result.Contains(#$FFFD) then
    Result := TEncoding.ANSI.GetString(ABytes);
end;

procedure AddKeyword(var AList: string; const AWord: string);
var
  vPart: string;
  vWord: string;
begin
  vWord := Trim(AWord);
  if vWord = '' then
    Exit;
  for vPart in AList.Split([';']) do
    if SameText(Trim(vPart), vWord) then
      Exit;
  if AList <> '' then
    AList := AList + '; ';
  AList := AList + vWord;
end;

procedure ParseIptcRecords(const AData: TBytes; AStart, AEnd: Integer; var AKeywords: string);
var
  q, vRec, vSet, vLen: Integer;
  vBytes: TBytes;
begin
  q := AStart;
  while q + 5 <= AEnd do
  begin
    if AData[q] <> $1C then
      Break;
    vRec := AData[q + 1];
    vSet := AData[q + 2];
    vLen := (AData[q + 3] shl 8) or AData[q + 4];
    if (vLen and $8000) <> 0 then
      Break;
    if q + 5 + vLen > AEnd then
      Break;
    if (vRec = 2) and (vSet = 25) then
    begin
      SetLength(vBytes, vLen);
      if vLen > 0 then
        Move(AData[q + 5], vBytes[0], vLen);
      AddKeyword(AKeywords, DecodeText(vBytes));
    end;
    Inc(q, 5 + vLen);
  end;
end;

{ AStart..AEnd: Photoshop image resource blocks ("8BIM") of an APP13 segment }
procedure ParseIptc(const AData: TBytes; AStart, AEnd: Integer; var AKeywords: string);
var
  p, vId, vNameLen, vDataPos, vSize: Integer;
begin
  p := AStart;
  while p + 12 <= AEnd do
  begin
    if not ((AData[p] = Ord('8')) and (AData[p + 1] = Ord('B')) and
      (AData[p + 2] = Ord('I')) and (AData[p + 3] = Ord('M'))) then
      Break;
    vId := (AData[p + 4] shl 8) or AData[p + 5];
    vNameLen := AData[p + 6];
    vDataPos := p + 7 + vNameLen;
    if ((1 + vNameLen) mod 2) = 1 then
      Inc(vDataPos);
    if vDataPos + 4 > AEnd then
      Break;
    vSize := (AData[vDataPos] shl 24) or (AData[vDataPos + 1] shl 16) or
      (AData[vDataPos + 2] shl 8) or AData[vDataPos + 3];
    Inc(vDataPos, 4);
    if (vSize < 0) or (vDataPos + vSize > AEnd) then
      Break;
    if vId = $0404 then
      ParseIptcRecords(AData, vDataPos, vDataPos + vSize, AKeywords);
    p := vDataPos + vSize;
    if Odd(vSize) then
      Inc(p);
  end;
end;

function XmlUnescape(const S: string): string;
begin
  Result := S.Replace('&lt;', '<').Replace('&gt;', '>').Replace('&quot;', '"')
    .Replace('&apos;', Chr(39)).Replace('&amp;', '&');
end;

procedure ParseXmp(const AData: TBytes; AStart, AEnd: Integer; var AKeywords: string);
var
  vBytes: TBytes;
  vXml: string;
  vBag, vItem: TMatch;
begin
  if AEnd <= AStart then
    Exit;
  SetLength(vBytes, AEnd - AStart);
  Move(AData[AStart], vBytes[0], Length(vBytes));
  vXml := TEncoding.UTF8.GetString(vBytes);
  vBag := TRegEx.Match(vXml, '<dc:subject>(.*?)</dc:subject>', [roSingleLine]);
  if not vBag.Success then
    Exit;
  for vItem in TRegEx.Matches(vBag.Groups[1].Value, '<rdf:li[^>]*>(.*?)</rdf:li>', [roSingleLine]) do
    AddKeyword(AKeywords, XmlUnescape(vItem.Groups[1].Value));
end;

function ReadExif(const AFileName: string): TExifInfo;
var
  vStream: TFileStream;
  vData: TBytes;
  vSize, vPos, vLen, vMarker: Integer;
  vReader: TTiffReader;
  vKeywords: string;
begin
  Result := Default(TExifInfo);
  vKeywords := '';
  try
    vStream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
    try
      vSize := Integer(Min(vStream.Size, 256 * 1024));
      SetLength(vData, vSize);
      if vSize > 0 then
        vStream.ReadBuffer(vData[0], vSize);
    finally
      vStream.Free;
    end;
    if (vSize < 4) or (vData[0] <> $FF) or (vData[1] <> $D8) then
      Exit;
    vPos := 2;
    while vPos + 4 < vSize do
    begin
      if vData[vPos] <> $FF then
        Break;
      vMarker := vData[vPos + 1];
      if (vMarker = $DA) or (vMarker = $D9) then
        Break;
      vLen := (vData[vPos + 2] shl 8) or vData[vPos + 3];
      if (vMarker = $E1) and (vPos + 10 < vSize) and
        (vData[vPos + 4] = Ord('E')) and (vData[vPos + 5] = Ord('x')) and
        (vData[vPos + 6] = Ord('i')) and (vData[vPos + 7] = Ord('f')) then
      begin
        vReader := TTiffReader.Create(vData, vPos + 10);
        try
          vReader.Fill(Result);
        finally
          vReader.Free;
        end;
      end
      else if (vMarker = $E1) and (vPos + 4 + 29 < vSize) and
        (TEncoding.ASCII.GetString(vData, vPos + 4, 28) = 'http://ns.adobe.com/xap/1.0/') then
        ParseXmp(vData, vPos + 4 + 29, Min(vPos + 2 + vLen, vSize), vKeywords)
      else if (vMarker = $ED) and (vPos + 4 + 14 < vSize) and
        (TEncoding.ASCII.GetString(vData, vPos + 4, 13) = 'Photoshop 3.0') then
        ParseIptc(vData, vPos + 4 + 14, Min(vPos + 2 + vLen, vSize), vKeywords);
      Inc(vPos, 2 + vLen);
    end;
    Result.Keywords := vKeywords;
    if (vKeywords <> '') or (Result.XPKeywords <> '') then
      Result.Valid := True;
  except
    Result := Default(TExifInfo);
  end;
end;

end.
