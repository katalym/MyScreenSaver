# MyScreenSaver

[Русский](#русский) · [English](#english)

---

## Русский

Скринсейвер Windows и просмотрщик фото/видео (Delphi 13, VCL, 64 бита, без баз данных).
Интерфейс на русском и английском языках.
Версия **1.1.1.1** (задаётся в `MyScreenSaverVersion.rc`, видна в окне настроек, в заголовке окна и в
свойствах файла).
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

Пробел — пауза · **I** — окно информации о файле · ← — предыдущий (история до 100 000 файлов) · → — следующий ·
Esc — выход.

Окно информации (EXIF, GPS и название места, теги, путь, размер, разрешение…; текст можно выделять и копировать,
двойной щелчок выделяет значение строки) одновременно служит окном действий — под текстом три кнопки:
- **Поделиться...** — открывает по центру окно, в котором на каждое действие своя кнопка: **E-mail** (MAPI, файл во вложении), **Telegram**,
  **WhatsApp**, **Facebook** (файл копируется в буфер обмена и приложение открывается, останется вставить),
  **Копировать изображение** (только для фото), **Копировать полный путь**, **Копировать имя файла**;
- **Удалить** — удалить показанный файл после подтверждения (в корзину; файл на сетевом ресурсе удаляется
  безвозвратно; недоступно для файлов с HTTP/FTP);
- **Закрыть** — закрывает только окно информации (как повторное нажатие **I**), показ продолжается.

### Конфигурация и язык

Окно настроек (`/c` или клавиша **C**) — одна форма с вкладками; над вкладками выбор **языка интерфейса:
Русский (Russian) или English (Английский)** (по умолчанию язык Windows). Кнопка «Сохранить» применяет всё сразу.

- **Медиаколлекции** — коллекции для показа (локальные папки, UNC, HTTP-листинг, FTP; отмеченные используются)
  и исключённые папки / подпапки (файлы в них не показываются; локальные, сетевые и HTTP/FTP-адреса).
- **Типы файлов** — что показывать (флажки «Показывать фото» и «Показывать видео»; хотя бы один всегда отмечен),
  видео без звука (по умолчанию включено: звук выключен), пропуск видео, у которых больше пикселей, чем у экрана
  (по умолчанию включено; проверяется при начале воспроизведения), исключение RAW-файлов (ARW, DNG, CR2, CR3, NEF,
  ORF, RAF, RW2 и др.; по умолчанию включено — RAW показываются, только если флажок снят и в Windows есть кодек).
- **Показ** — слайд-шоу: время показа, переход между слайдами
  и его длительность, активные правила (всегда выбрано хотя бы одно, по умолчанию «случайный файл»), применяемое правило и параметры правил («в этот день», текущее место).
- **Информация** — поля окна информации (клавиша **I**): все встроенные поля (файл, размер, камера, теги XP /
  IPTC / XMP, дата съёмки, GPS, место и т. д.) можно включать и выключать (по умолчанию включены: файл, коллекция,
  расположение, разрешение, длительность, теги XP, теги IPTC/XMP, дата съёмки, GPS, место); «Добавить EXIF-тег...»
  добавляет свой тег по номеру (например `0x010E` описание, `0x013B` автор, `0x9286` комментарий) с необязательным
  названием; такие теги показываются для JPEG после встроенных полей.
- **Наложение** — поля поверх фото и видео: тот же список полей, что и на вкладке «Информация» (включая свои
  EXIF-теги; по умолчанию отмечено только «Файл»), положение (3 × 3 места; по умолчанию снизу справа), шрифт и
  размер в пунктах (по умолчанию Segoe UI, 10) и флажок «Показывать названия полей» (по умолчанию выключен). Текст рисуется на полупрозрачной тёмной плашке отдельным окном, поэтому виден и
  поверх видео; окно информации (клавиша **I**) на время показа скрывает наложение. Название места по GPS
  запрашивается в фоне, наложение обновляется, когда оно получено.

Файл настроек: `%APPDATA%\MyScreenSaver\MyScreenSaver.ini` (INI, UTF-8; ключ `Language=ru|en` в `[General]`).
Пароли коллекций хранятся в INI открытым текстом.

### Кэш сканирования

Результат сканирования (список файлов и их дата/GPS) сохраняется в `%APPDATA%\MyScreenSaver\catalog.cache`.
При запуске он загружается сразу, и показ идёт по правилам без ожидания. Одновременно в фоне папки
пересканируются: новые файлы добавляются, удалённые исчезают (если коллекция доступна). Даты и GPS
читаются в фоне и дописываются в тот же файл, поэтому правила «в этот день» и «по месту» начинают работать
полнее с каждым запуском. Первый запуск без кэша: пока список строится, показываются случайные фото.
Чтобы сбросить кэш, удалите файл.

### Переходы между слайдами (`uSlideView.pas`)

Эффекты: нет, **плавное затухание** (cross-fade), **через чёрное**, **сдвиг**, **шторка**, **случайный**
(для каждой смены свой эффект). По умолчанию — плавное затухание, 800 мс (100–3000 мс; не дольше половины
времени показа слайда). Стрелки ← и → задают направление сдвига и шторки (← — назад), при ручном листании
переход не длиннее 250 мс. Перед видео фото затухает до чёрного, а после видео следующее фото проявляется из
чёрного; смена видео на видео — без перехода (окно Windows Media Player нельзя смешивать с картинкой).
В INI: `Transition=none|fade|black|slide|wipe|random`, `TransitionMs=800`.

### Правила выбора (`uRules.pas`)

`random` (по умолчанию), `onthisday` («в этот день» в прошлые годы, дата из EXIF или файла),
`location` (снято в радиусе от текущего места; место задаётся в настройках или определяется по IP).
Правила по порядку (по очереди, по кругу): `filenameasc`, `filenamedesc` (по имени файла), `fullnameasc`, `fullnamedesc` (по полному имени).
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
Version **1.1.1.1** (set in `MyScreenSaverVersion.rc`, shown in the settings dialog, the window title and the
file properties).
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

Space — pause · **I** — the file information dialog · ← — previous (history up to 100,000 files) · → — next ·
Esc — exit.

The information dialog (EXIF, GPS and place name, tags, path, size, resolution…; the text can be selected and
copied, a double click selects the value of a line) is also the dialog of actions — three buttons under the text:
- **Share...** — opens a dialog in the middle with a separate button for every action: **E-mail** (MAPI, the file is attached), **Telegram**,
  **WhatsApp**, **Facebook** (the file is copied to the clipboard and the application is opened, you only have
  to paste), **Copy image** (photos only), **Copy full path**, **Copy file name**;
- **Delete** — delete the shown file after a confirmation (to the Recycle Bin; a file on a network share is
  deleted permanently; not available for HTTP/FTP files);
- **Close** — closes only the information dialog (like pressing **I** again), the slideshow goes on.

### Configuration and language

Settings dialog (`/c` or key **C**) — one form with tabs; above the tabs the **interface language:
Русский (Russian) or English (Английский)** (the Windows language by default). "Save" applies everything at once.

- **Media collections** — the collections to show (local folders, UNC, HTTP listing, FTP; checked ones are used)
  and the excluded folders / subfolders (files in them are not shown; local, network and HTTP/FTP addresses).
- **File types** — what to show (check boxes "Show photos" and "Show videos"; at least one always stays checked),
  silent videos (on by default: the sound is off), skipping of videos that have more pixels than the screen
  (on by default; checked when a video starts to play), exclusion of RAW files (ARW, DNG, CR2, CR3, NEF, ORF,
  RAF, RW2, etc.; on by default — RAW files are shown only if the box is unchecked and Windows has a codec).
- **Play** — the slideshow: display time, slide transition and its
  duration, active rules (at least one is always selected, "random file" by default), the applied rule and the rule parameters ("on this day", current place).
- **Information** — the fields of the information dialog (key **I**): all built-in fields (file, size, camera,
  XP / IPTC / XMP tags, date taken, GPS, place, etc.) can be switched on and off (on by default: file, collection,
  location, resolution, duration, XP tags, IPTC/XMP tags, date taken, GPS, place); "Add EXIF tag..." adds an own
  tag by its number (for example `0x010E` description, `0x013B` artist, `0x9286` user comment) with an optional
  caption; such tags are shown for JPEG after the built-in fields.
- **Overlay** — fields over the photos and videos: the same list of fields as on the "Information" tab (including
  own EXIF tags; only "File" is checked by default), the position (3 x 3 places; bottom right by default), the
  font and the size in points (Segoe UI, 10 by default) and the check box "Show the field names" (off by default). The text is drawn on a semi-transparent dark plate by a separate
  window, so it is visible over a video as well; the information dialog (key **I**) hides the overlay while it is
  shown. The place name from GPS is requested in the background, the overlay is updated when it has arrived.

Settings file: `%APPDATA%\MyScreenSaver\MyScreenSaver.ini` (INI, UTF-8; key `Language=ru|en` in `[General]`).
Collection passwords are stored in the INI as plain text.

### Scan cache

The scan result (file list and their date/GPS) is saved in `%APPDATA%\MyScreenSaver\catalog.cache`.
It is loaded at start, so playback by rules begins at once. In parallel the folders are rescanned in the
background: new files are added, removed files disappear (if the collection is reachable). Dates and GPS are
read in the background and appended to the same file, so the "on this day" and "by place" rules work more
completely with every start. First start without a cache: random photos are shown while the list is being built.
To reset the cache, delete the file.

### Slide transitions (`uSlideView.pas`)

Effects: none, **cross-fade**, **fade through black**, **slide**, **wipe**, **random** (a different effect
for every change). Cross-fade, 800 ms by default (100–3000 ms; never longer than half of the slide time).
The arrow keys ← and → set the direction of the slide and the wipe (← goes back); when you page by hand the
transition is at most 250 ms. A photo fades to black before a video, and the next photo appears from black
after a video; video to video has no transition (the Windows Media Player window cannot be blended with
a picture). In the INI: `Transition=none|fade|black|slide|wipe|random`, `TransitionMs=800`.

### Selection rules (`uRules.pas`)

`random` (default), `onthisday` ("on this day" in previous years, date from EXIF or the file),
`location` (taken within a radius of the current place; the place is set in the settings or detected by IP).
Sequential rules (one after another, wrapping around): `filenameasc`, `filenamedesc` (by file name), `fullnameasc`, `fullnamedesc` (by full file name).
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
