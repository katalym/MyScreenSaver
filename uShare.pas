unit uShare;

{ Sharing of the current media file: e-mail (MAPI with attachment) and messengers / social
  networks (the file is put on the clipboard and the messenger is opened - paste it there). }

interface

uses
  Vcl.Forms;

type
  TShareTarget = (stEmail, stTelegram, stWhatsApp, stFacebook, stClipboard);

function ShareTargetTitle(ATarget: TShareTarget): string;

procedure ShareFile(ATarget: TShareTarget; const AFileName: string);

implementation

uses
  Winapi.Windows, Winapi.ShellAPI, Winapi.ShlObj, Winapi.Messages, System.SysUtils, Vcl.Clipbrd, uLang;

type
  TMapiFileDesc = record
    ulReserved: Cardinal;
    flFlags: Cardinal;
    nPosition: Cardinal;
    lpszPathName: PAnsiChar;
    lpszFileName: PAnsiChar;
    lpFileType: Pointer;
  end;
  PMapiFileDesc = ^TMapiFileDesc;

  TMapiMessage = record
    ulReserved: Cardinal;
    lpszSubject: PAnsiChar;
    lpszNoteText: PAnsiChar;
    lpszMessageType: PAnsiChar;
    lpszDateReceived: PAnsiChar;
    lpszConversationID: PAnsiChar;
    flFlags: Cardinal;
    lpOriginator: Pointer;
    nRecipCount: Cardinal;
    lpRecips: Pointer;
    nFileCount: Cardinal;
    lpFiles: PMapiFileDesc;
  end;

  TMAPISendMailProc = function(ASession: NativeUInt; AUIParam: NativeUInt;
    var AMessage: TMapiMessage; AFlags: Cardinal; AReserved: Cardinal): Cardinal; stdcall;

const
  MAPI_LOGON_UI = $00000001;
  MAPI_DIALOG = $00000008;

function ShareTargetTitle(ATarget: TShareTarget): string;
begin
  case ATarget of
    stEmail: Result := L('Электронная почта', 'E-mail');
    stTelegram: Result := 'Telegram';
    stWhatsApp: Result := 'WhatsApp';
    stFacebook: Result := 'Facebook';
  else
    Result := L('Только скопировать файл', 'Only copy the file');
  end;
end;

procedure CopyFileToClipboard(const AFileName: string);
var
  vSize: Integer;
  vMem: HGLOBAL;
  vPtr: PDropFiles;
  vPath: PChar;
begin
  vSize := SizeOf(TDropFiles) + (Length(AFileName) + 2) * SizeOf(Char);
  vMem := GlobalAlloc(GMEM_MOVEABLE or GMEM_ZEROINIT, vSize);
  if vMem = 0 then
    Exit;
  vPtr := GlobalLock(vMem);
  try
    vPtr^.pFiles := SizeOf(TDropFiles);
    vPtr^.fWide := True;
    vPath := PChar(PByte(vPtr) + SizeOf(TDropFiles));
    Move(PChar(AFileName)^, vPath^, Length(AFileName) * SizeOf(Char));
  finally
    GlobalUnlock(vMem);
  end;
  if OpenClipboard(0) then
  try
    EmptyClipboard;
    if SetClipboardData(CF_HDROP, vMem) = 0 then
      GlobalFree(vMem);
  finally
    CloseClipboard;
  end
  else
    GlobalFree(vMem);
end;

procedure SendByMapi(const AFileName: string);
var
  vLib: HMODULE;
  vProc: TMAPISendMailProc;
  vMsg: TMapiMessage;
  vFile: TMapiFileDesc;
  vPath, vName, vSubject: AnsiString;
begin
  vLib := LoadLibrary('mapi32.dll');
  if vLib = 0 then
    raise Exception.Create(L('MAPI не доступен: почтовый клиент не установлен.', 'MAPI is not available: no mail client is installed.'));
  try
    vProc := GetProcAddress(vLib, 'MAPISendMail');
    if not Assigned(vProc) then
      raise Exception.Create(L('MAPI не доступен.', 'MAPI is not available.'));
    vPath := AnsiString(AFileName);
    vName := AnsiString(ExtractFileName(AFileName));
    vSubject := vName;
    FillChar(vFile, SizeOf(vFile), 0);
    vFile.lpszPathName := PAnsiChar(vPath);
    vFile.lpszFileName := PAnsiChar(vName);
    FillChar(vMsg, SizeOf(vMsg), 0);
    vMsg.lpszSubject := PAnsiChar(vSubject);
    vMsg.nFileCount := 1;
    vMsg.lpFiles := @vFile;
    vProc(0, 0, vMsg, MAPI_LOGON_UI or MAPI_DIALOG, 0);
  finally
    FreeLibrary(vLib);
  end;
end;

procedure OpenUrl(const AUrl: string);
begin
  ShellExecute(0, 'open', PChar(AUrl), nil, nil, SW_SHOWNORMAL);
end;

procedure ShareFile(ATarget: TShareTarget; const AFileName: string);
begin
  if (AFileName = '') or not FileExists(AFileName) then
    Exit;
  case ATarget of
    stEmail:
      SendByMapi(AFileName);
    stTelegram:
      begin
        CopyFileToClipboard(AFileName);
        OpenUrl('tg://');
      end;
    stWhatsApp:
      begin
        CopyFileToClipboard(AFileName);
        OpenUrl('whatsapp://');
      end;
    stFacebook:
      begin
        CopyFileToClipboard(AFileName);
        OpenUrl('https://www.facebook.com/');
      end;
    stClipboard:
      CopyFileToClipboard(AFileName);
  end;
end;

end.
