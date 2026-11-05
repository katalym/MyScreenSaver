# MyScreenSaver

[Русский](#русский) · [English](#english)

---

## Русский

Скринсейвер Windows и просмотрщик фото/видео (Delphi 13, VCL, 64 бита, без баз данных).
Интерфейс на русском и английском языках.
Требования: `C:\Claude\Screensaver\Требования_к_приложению.md`.

### Сборка

```
build.bat
```

Результат в этой же папке: `MyScreenSaver.exe` (отдельная программа) и `MyScreenSaver.scr` (скринсейвер).
Чтобы установить скринсейвер: ПКМ на `.scr` → «Установить».

### Режимы запуска

| Параметр | Режим |
|---|---|
| `/s` | скринсейвер (выход по движению мыши, клику или любой «чужой» клавише) |
| `/c` | окно настроек |
| `/p <hwnd>` | предпросмотр в маленьком мониторе окна «Параметры экранной заставки»: одно случайное фото |
| без параметров | отдельный просмотрщик (клавиша **C** — настройки, **Esc** — выход) |

### Горячие клавиши

Пробел — пауза · **I** — информация о файле (EXIF, GPS и название места, теги, путь, размер, разрешение…;
текст можно выделять и копировать, двойной щелчок выделяет значение строки) · ← — предыдущий
(история до 100 000 файлов) · → — следующий · **P** — поделиться (почта через MAPI; Telegram/WhatsApp/Facebook —
файл копируется в буфер обмена и приложение открывается, останется вставить) · Esc — выход.

### Конфигурация и язык

Окно настроек (`/c` или клавиша **C**): коллекции (локальные, UNC, HTTP-листинг, FTP), время показа, режим
(полностью случайный / по правилам), что показывать (флажки «Показывать фото» и «Показывать видео»; если
отмечены оба, показываются оба типа; хотя бы один флажок всегда отмечен), правила, **язык интерфейса: Русский (Russian) или English (Английский)**.
По умолчанию язык берётся из языка Windows.

Кнопка **«Поля окна информации (I)...»**: какие поля показывает окно информации (клавиша **I**) — все
встроенные поля (файл, размер, камера, теги XP / IPTC / XMP, дата съёмки, GPS, место и т. д.) можно
включать и выключать. По умолчанию включены: файл, коллекция, расположение, разрешение, длительность,
теги XP, теги IPTC/XMP, дата съёмки, GPS, место. Кнопка «Добавить EXIF-тег...» добавляет свой тег по номеру (например
`0x010E` описание, `0x013B` автор, `0x9286` комментарий) с необязательным названием; такие теги
показываются для JPEG после встроенных полей. В INI: раздел `[Info]` (`Fields=...`, `CustomN=0x9286|Название|1`).

Файл настроек: `%APPDATA%\MyScreenSaver\MyScreenSaver.ini` (INI, UTF-8; ключ `Language=ru|en` в `[General]`).
Пароли коллекций хранятся в INI открытым текстом.

### Кэш сканирования

Результат сканирования (список файлов и их дата/GPS) сохраняется в `%APPDATA%\MyScreenSaver\catalog.cache`.
При запуске он загружается сразу, и показ идёт по правилам без ожидания. Одновременно в фоне папки
пересканируются: новые файлы добавляются, удалённые исчезают (если коллекция доступна). Даты и GPS
читаются в фоне и дописываются в тот же файл, поэтому правила «в этот день» и «по месту» начинают работать
полнее с каждым запуском. Первый запуск без кэша: пока список строится, показываются случайные фото.
Чтобы сбросить кэш, удалите файл.

### Правила выбора (`uRules.pas`)

`random` (по умолчанию), `onthisday` («в этот день» в прошлые годы, дата из EXIF или файла),
`location` (снято в радиусе от текущего места; место задаётся в настройках или определяется по IP).
Новое правило — наследник `TMediaRule` + регистрация в `initialization`.

### Языки (`uLang.pas`)

Все тексты интерфейса задаются парой `L('русский', 'English')`. Название места в информации о файле
запрашивается (OpenStreetMap Nominatim) на выбранном языке.

### Ограничения

- Правила, которым нужны дата/GPS, применяются только к локальным и сетевым (UNC) файлам;
  файлы с HTTP/FTP участвуют в случайном режиме (скачиваются в кэш `%TEMP%\MyScreenSaver\cache`).
- HTTP-коллекция — это страница со списком файлов (autoindex); FTP — через Indy.
- Видео воспроизводится через Windows Media Player (`WMPLib.pas`, сгенерирован `tlibimp` из `wmp.dll`).
- Поворот фото учитывается только для JPEG с EXIF Orientation 3/6/8.
- Теги читаются только из JPEG (EXIF XPKeywords, IPTC, XMP `dc:subject`).

---

## English

Windows screensaver and photo/video viewer (Delphi 13, VCL, 64-bit, no database).
The user interface is available in Russian and English.
Requirements: `C:\Claude\Screensaver\Требования_к_приложению.md` (Russian).

### Build

```
build.bat
```

The result is in the same folder: `MyScreenSaver.exe` (standalone program) and `MyScreenSaver.scr` (screensaver).
To install the screensaver: right-click the `.scr` → "Install".

### Run modes

| Parameter | Mode |
|---|---|
| `/s` | screensaver (exits on mouse move, click or any "foreign" key) |
| `/c` | settings dialog |
| `/p <hwnd>` | preview in the small monitor of the "Screen Saver Settings" dialog: one random photo |
| none | standalone viewer (key **C** — settings, **Esc** — exit) |

### Hotkeys

Space — pause · **I** — file information (EXIF, GPS and place name, tags, path, size, resolution…;
the text can be selected and copied, a double click selects the value of a line) · ← — previous
(history up to 100,000 files) · → — next · **P** — share (e-mail via MAPI; Telegram/WhatsApp/Facebook —
the file is copied to the clipboard and the application is opened, you only have to paste) · Esc — exit.

### Configuration and language

Settings dialog (`/c` or key **C**): collections (local, UNC, HTTP listing, FTP), display time, selection mode
(fully random / by rules), what to show (check boxes "Show photos" and "Show videos"; if both are checked,
both types are shown; at least one box always stays checked), rules, **interface language: Русский (Russian) or English (Английский)**.
By default the language follows the Windows language.

The **"Information dialog fields (I)..."** button: which fields the information dialog (key **I**) shows —
all built-in fields (file, size, camera, XP / IPTC / XMP tags, date taken, GPS, place, etc.) can be
switched on and off. On by default: file, collection, location, resolution, duration, XP tags, IPTC/XMP tags,
date taken, GPS, place. "Add EXIF tag..." adds an own tag by its number (for example
`0x010E` description, `0x013B` artist, `0x9286` user comment) with an optional caption; such tags are shown
for JPEG after the built-in fields. In the INI: section `[Info]` (`Fields=...`, `CustomN=0x9286|Caption|1`).

Settings file: `%APPDATA%\MyScreenSaver\MyScreenSaver.ini` (INI, UTF-8; key `Language=ru|en` in `[General]`).
Collection passwords are stored in the INI as plain text.

### Scan cache

The scan result (file list and their date/GPS) is saved in `%APPDATA%\MyScreenSaver\catalog.cache`.
It is loaded at start, so playback by rules begins at once. In parallel the folders are rescanned in the
background: new files are added, removed files disappear (if the collection is reachable). Dates and GPS are
read in the background and appended to the same file, so the "on this day" and "by place" rules work more
completely with every start. First start without a cache: random photos are shown while the list is being built.
To reset the cache, delete the file.

### Selection rules (`uRules.pas`)

`random` (default), `onthisday` ("on this day" in previous years, date from EXIF or the file),
`location` (taken within a radius of the current place; the place is set in the settings or detected by IP).
A new rule is a descendant of `TMediaRule` plus a registration in `initialization`.

### Languages (`uLang.pas`)

All interface texts are given as a pair `L('русский', 'English')`. The place name in the file information
is requested (OpenStreetMap Nominatim) in the selected language.

### Limitations

- Rules that need date/GPS apply only to local and network (UNC) files; HTTP/FTP files take part in the
  random mode (they are downloaded to the cache `%TEMP%\MyScreenSaver\cache`).
- An HTTP collection is a page with a file list (autoindex); FTP uses Indy.
- Video is played with Windows Media Player (`WMPLib.pas`, generated by `tlibimp` from `wmp.dll`).
- Photo rotation is applied only to JPEG with EXIF Orientation 3/6/8.
- Tags are read from JPEG only (EXIF XPKeywords, IPTC, XMP `dc:subject`).
