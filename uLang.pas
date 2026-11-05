unit uLang;

{ User interface language: Russian or English.
  Usage:  L('Русский текст', 'English text') returns the text of the current language. }

interface

type
  TLanguage = (lgRu, lgEn);

function CurrentLanguage: TLanguage;
procedure SetLanguage(ALanguage: TLanguage);
{ 'ru' / 'en' }
function LanguageCode(ALanguage: TLanguage): string;
function LanguageFromCode(const ACode: string; ADefault: TLanguage): TLanguage;
{ Russian if the Windows UI language is Russian, otherwise English }
function DefaultLanguage: TLanguage;
function L(const ARu, AEn: string): string;

implementation

uses
  Winapi.Windows, System.SysUtils;

var
  GLanguage: TLanguage;

function CurrentLanguage: TLanguage;
begin
  Result := GLanguage;
end;

procedure SetLanguage(ALanguage: TLanguage);
begin
  GLanguage := ALanguage;
end;

function LanguageCode(ALanguage: TLanguage): string;
begin
  if ALanguage = lgRu then
    Result := 'ru'
  else
    Result := 'en';
end;

function LanguageFromCode(const ACode: string; ADefault: TLanguage): TLanguage;
begin
  if SameText(Trim(ACode), 'ru') then
    Result := lgRu
  else if SameText(Trim(ACode), 'en') then
    Result := lgEn
  else
    Result := ADefault;
end;

function DefaultLanguage: TLanguage;
begin
  if (GetUserDefaultUILanguage and $3FF) = LANG_RUSSIAN then
    Result := lgRu
  else
    Result := lgEn;
end;

function L(const ARu, AEn: string): string;
begin
  if GLanguage = lgRu then
    Result := ARu
  else
    Result := AEn;
end;

initialization
  GLanguage := DefaultLanguage;

end.
