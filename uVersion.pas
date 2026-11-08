unit uVersion;

{ Version of the application: it is stored once, in MyScreenSaverVersion.rc (compiled into the exe). }

interface

{ 'major.minor.release.build' from the version resource of the running exe, '' if there is none }
function AppVersion: string;

implementation

uses
  Winapi.Windows, System.SysUtils;

function AppVersion: string;
var
  vFile: string;
  vHandle, vSize: DWORD;
  vBuffer: TBytes;
  vInfo: PVSFixedFileInfo;
  vLen: UINT;
begin
  Result := '';
  vFile := ParamStr(0);
  vSize := GetFileVersionInfoSize(PChar(vFile), vHandle);
  if vSize = 0 then
    Exit;
  SetLength(vBuffer, vSize);
  if GetFileVersionInfo(PChar(vFile), 0, vSize, vBuffer) and
    VerQueryValue(vBuffer, '\', Pointer(vInfo), vLen) and (vLen > 0) then
    Result := Format('%d.%d.%d.%d', [HiWord(vInfo^.dwFileVersionMS), LoWord(vInfo^.dwFileVersionMS),
      HiWord(vInfo^.dwFileVersionLS), LoWord(vInfo^.dwFileVersionLS)]);
end;

end.
