# Handoff: MyScreenSaver (Delphi 13 screensaver and media viewer)

Date: 2026-11-12

## Goal

Windows screensaver (.scr) and standalone photo/video viewer, built from
`C:\Claude\Screensaver\Требования_к_приложению.md`. Delphi 13, VCL, no database, INI config.

## Location and repository

- Project folder: `A:\git\MyScreenSaver` (was `D:\git\MyScreenSaver`) (everything in the root folder, no src/bin/dcu subfolders - user requirement)
- GitHub: `git@github.com:katalym/MyScreenSaver.git`, branch `main`
- Commits: `72f4ea3` initial, `a867883` info dialog / keywords / shutdown fix, `e8cbac7` ru/en languages + /p preview, `6d34598` preview/info/warnings fixes, `35a6662` photo/video selection + video fit + cache compaction, `a6263ca` configurable info-dialog fields, `c45cbc0` default slide time 4 s (by the user), `4ef98e9` slide transitions, `e0e7fb0` filters / version 1.1.1.1 / taskbar button, `1b2d120` tabbed settings + overlay, `479c0cb` share dialog / look, `9b8a7cb` messages instead of a black screen + Paused badge, `6f877a9` version 2.0.0.1 / one active rule / sequential rules / icon (pushed), `855f12c` Esc closes only the info dialog / new icon / build.bat regenerates the .res / version 2.0.0.2, then (uncommitted when this was written, version 2.0.0.3) even random order, split caches, info-dialog cache line
- `a867883` is pushed to `origin/main` (pushed by the user). Pushing is done by the user only on explicit request.
- `.gitignore` excludes `*.exe`, `*.scr`, `*.dcu`, `*.dcr`, `*.res`, `*.local`, `*.dsk`, `*.~dsk`, `__history/`
  (user decided not to keep binaries in git; releases on GitHub are the suggested way to distribute the .scr)

## Build

`build.bat` (version 2.0.0.3 now) -> single **64-bit** `MyScreenSaver.exe` plus identical copy `MyScreenSaver.scr` in the project root
(since `855f12c` built with `msbuild MyScreenSaver.dproj` Release/Win64, not dcc64: build.bat deletes `MyScreenSaver.res` first so the icon/manifest/version always come from the dproj; output compiled in `%TEMP%\MyScreenSaver_win64`; a few seconds slower). User wants only one 64-bit exe, no separate 32-bit.
`build.bat` prints "Built" even if the final `copy` fails because a running instance locks the exe - check the
exe timestamp / running processes (`Get-Process MyScreenSaver`) when a change seems to have no effect.
`WMPLib.pas` was generated with `tlibimp` from `wmp.dll` (video playback through Windows Media Player).

## Units

| Unit | Purpose |
|---|---|
| `MyScreenSaver.dpr` | args: `/s` saver, `/c` settings, `/p <hwnd>` preview, none = standalone viewer |
| `uConfig` | INI settings `%APPDATA%\MyScreenSaver\MyScreenSaver.ini` (collections, slide time, active rule, GeoLanguage) |
| `uMedia` | catalog, scan thread, quick sampler, metadata indexer, `catalog.cache` (cache 1) and `shown.cache` (cache 2), download cache for HTTP/FTP |
| `uRules` | `TMediaRule` (random, onthisday, location, 4 sequential rules `TSequentialRule`) + `PickMedia` |
| `uExif` | own JPEG EXIF reader: camera, date, GPS, orientation, XPKeywords, IPTC and XMP keywords |
| `uLocation` | distance, IP location, reverse geocoding (OSM Nominatim) with the persistent `places.cache` (cache 3) |
| `uViewer` | code-built form: slideshow, hotkeys, info dialog (Share/Delete/Close), WMP video |
| `uSettingsForm` | code-built settings dialog |
| `uPreview` | `/p <hwnd>`: form parented to the settings-dialog monitor window, shows one random photo, exits when the parent is gone |
| `uLang` | UI language (ru/en): `L('русский','English')`, `SetLanguage`, default from the Windows UI language |
| `uInfoFields` | ids/titles of the built-in fields of the info dialog, `InfoFieldOn` |
| `uSlideView` | the photo control: halftone-scaled bitmaps, transitions (AlphaBlend / BitBlt, timer 15 ms) |
| `uVersion` | `AppVersion` read from the version resource of the exe (source: `MyScreenSaverVersion.rc`, compiled to the committed `MyScreenSaverVersion.res` by `build.bat` with brcc32) |
| `uOverlay` | the overlay window: small layered (alpha 205) no-activate click-through top-level window owned by the viewer, text of the selected fields at one of 3x3 places |
| `uShareIcons` | 16x16 icons drawn in code (e-mail, Telegram, WhatsApp, Facebook, copy image/path/name; 8x supersampled, straight alpha, `afDefined`) for the TBitBtn glyphs of the share dialog (TButton.Images does not work: no visual styles manifest) |
| `uShareDialog` | the share dialog (a button per action; as wide as its content, buttons centered) opened by the Share button of the information dialog |
| `uShare` | e-mail via MAPI; Telegram/WhatsApp/Facebook = file to clipboard + open app |

## Implemented features

- Hotkeys: Space pause, I info, Left/Right history prev/next (up to 100000), P share, Esc exit, C settings (standalone)
- Info dialog: centered panel sized to the text with gray border, selectable/copyable text (Ctrl+A, Ctrl+C,
  double click selects the value of a line without its caption), mouse stays active in saver mode while it is open;
  shows EXIF, GPS plus human-readable place (reverse geocoding), XP tags and IPTC/XMP tags
- Quick start: while the list is not ready, `TQuickSampler` picks random photos by random folder descent
- Persistent cache `%APPDATA%\MyScreenSaver\catalog.cache` (see "Caches" below; before version 4 it had `F` and `M` lines);
  loaded at start so rules work at once; background rescan adds new files and drops removed ones (only for reachable
  collections); `TMetaIndexer` fills date/GPS in the background (about 150 files/s on the user's 121k photos)
- Rules use only cached metadata (never touch the disk in the UI thread)

- Two UI languages (Russian/English): combo in the settings dialog (switches the dialog at once, saved with Save;
  cancel reverts), INI key `Language=ru|en` in `[General]`, README has Russian and English parts

- Media types: two check boxes in the settings (Show photos / Show videos, at least one always checked),
  INI `MediaTypes=photos|videos|both` in `[General]`; picker and quick sampler filter by it (`KindAllowed`);
  video is scaled to the window keeping the aspect ratio (`FitVideo`); video playback tested with a generated
  uncompressed AVI (no real video files in the user's collection)
- Catalog cache is compacted on load when it has duplicates or entries of removed collections (was 149 MB, now 14 MB)

- Info dialog fields are configurable: `[Info] Fields=` (absent = default set: file, collection, location, resolution, duration, tagsxp, tagsiptc, datetaken, gps, place) and `CustomN=0x9286|Caption|1` in the INI;
  own tags are read by `ReadExifTagTexts` (IFD0, Exif IFD, GPS IFD; ascii/short/long/rational/bytes, XP tags are UTF-16)
- Files written with the Write tool have NO UTF-8 BOM -> Delphi reads Cyrillic as ANSI (mojibake); add the BOM (all .pas have it)

- Slide transitions (`uSlideView`): none, cross-fade, fade through black, slide, wipe, random; INI `Transition=none|fade|black|slide|wipe|random`,
  `TransitionMs=800` (100..3000); never longer than half of the slide, arrow keys <= 250 ms and set the direction (<- backward);
  photo -> video: the photo fades to black first (`FadeOut` + `OnFadedOut` -> `StartVideo`), video -> photo: appears from black,
  video -> video: cut; all effects verified on screen (frames/brightness sampling); committed and pushed. Next ideas: Ken Burns, soft wipe edge, fade between videos

- Filters (settings button "Filters..."): `SilentVideo` (default ON = the sound is off), `SkipLargeVideos` (default ON: pixels of the video > pixels of the
  monitor, checked when WMP reports state 3 playing because the size is 0 before; the player is hidden+muted until accepted),
  `ExcludeRaw` (default ON; RAW extensions are photos only when not excluded, shown only with a codec), `[Exclude] Count/FolderN`
  (skipped by the scanner, the quick sampler, the cache load and the picker via `ItemAllowed`/`IsExcludedPath`); committed and pushed
- Version 1.1.1.1 (4 numbers; the request said "1.1.1.1.1" - a Windows version resource has only four): shown in the settings title and the window title;
  `VerInfo_IncludeVerInfo` is false in the dproj so the IDE does not add a second version resource

- Settings are ONE form with 4 tabs (`uSettingsForm`; the dialogs `uFiltersForm` / `uInfoFieldsForm` are gone): Media collections
  (collections + excluded folders), File types (photos/videos, silent, skip large, exclude RAW), Play (time, transition,
  active rule (radio group), rule parameters), Information (fields + own EXIF tags); language combo above the tabs;
  one Save/Cancel for everything; committed and pushed. Open question: the transition and the rule parameters (place/tolerance)
  stayed on the Play tab because they had no other tab

- Overlay (5th tab "Наложение"/"Overlay"): same field list as Information (+ own EXIF tags; `TInfoCustomTag.Overlay`), `[Overlay]` in the INI:
  `Fields=`, `Position=topleft..bottomright`, `FontName`, `FontSize`, `ShowNames`; defaults: only `file`, bottom right, Segoe UI 10 pt, names off; `BuildFieldText(AOverlay)` in the viewer
  serves both the info dialog and the overlay; the place name for the overlay comes from the cache, otherwise a background lookup updates it;
  tested on a photo (with GPS/place) and on a video; committed and pushed

- Information dialog = the dialog of actions: three buttons under the text (Share..., Delete, Close = only closes the dialog like the I key): Share... (opens `uShareDialog`: a separate button per action: E-mail, Telegram, WhatsApp, Facebook,
  Copy image (photos only), Copy full path, Copy file name; centered over the viewer); Delete sits one button width to the right of Share and Delete
  (confirmation, default No; Recycle Bin, network files permanent; only local/network files; forgets the file in the catalog
  (`TMediaCatalog.Remove`) and the history, then goes to the next slide). The `P` shortcut is removed. Tested: share dialog list, copy file name, copy image,
  copy path, delete on temp files; committed and pushed (`479c0cb`)
- LESSON: in Delphi 13 `TBitBtn` is NOT a `TButton` (`Sender as TButton` raises "Invalid class typecast"): use `Sender as TComponent` for `Tag`; click every kind of control after changing its class
- TESTING LESSON 2: SendKeys goes to the FOREGROUND window: if `AppActivate` fails, STOP (my keys once reached the user's own running viewer and probably pressed E-mail in its share dialog)
- TESTING LESSON: never press the e-mail/share buttons in automated tests (MAPI opens the user's mail client: Thunderbird compose window opened once)

- Form units (uSettingsForm, uViewer, uPreview, uOverlay, uShareDialog): `{$R *.DFM}` after `implementation`, a minimal `.dfm` for each (the forms are still built in code:
  `CreateNew`, the dfm is never loaded), `{FormName}` comments in the dpr, `<Form>`/`<FormType>dfm</FormType>` in the dproj; the classes TSettingsForm, TPreviewForm and TShareForm
  were moved from the implementation to the interface section (the IDE designer needs them there); committed and pushed (`479c0cb`)

- Look (commit `479c0cb`): ALL buttons have the default height 25 (TBitBtn and TButton); the info text font is configurable (Information tab: font + size, `[Info] FontName/FontSize`, default Consolas 11);
  the field lists (Information, Overlay) have 3 columns (`TCheckListBox.Columns`, they fill down the columns first; the Information list fills the tab, the Overlay list has 9 rows);
  both lists of the Media tab are 120 px, the settings form is 660 x 512 (no empty space at the bottom)
- LESSON: `GetFormImage` of a multi-column list box does not show the columns: take screenshots with `PrintWindow(hwnd, dc, 2)` of the window found by `EnumWindows` for the process id

- Messages (`uViewer`): a centered message instead of a black screen: "No media collections are defined" (no ENABLED collection, `HasEnabledCollection`),
  "No media files available" (collections/exclusions give no items), "Loading the file list..."; Space shows the `FPauseBar` badge ("Paused") at the bottom
  (a TPanel, so it is above the WMP video window; hidden on resume, prev/next, info dialog)
- Rules (v2.0.0.1): the selection mode (Fully random / By rules) and the "Default rule" setting are REMOVED. Play tab = a 2-column `TRadioGroup`
  "Active rule" (one rule, default `random`); INI `[General] ActiveRules=` keeps one name (an old `Mode=random` maps to `random`, several names -> the first);
  if the chosen rule finds nothing, the picker falls back to random. New rules `filenameasc`, `filenamedesc`, `fullnameasc`, `fullnamedesc`
  (`TSequentialRule.PickNext`: one pass over the catalog, smallest item after the previous one, wraps around; position lives only while the app runs; case-insensitive,
  ties by full path). Not verified on screen by me: the radio group layout (height 118, 7 rules) and the sequential play
- Version 2.0.0.1 in `MyScreenSaverVersion.rc`; main icon `MyScreenSaver_Icon.ico`; `MyScreenSaver.res` (icon + manifest) is now committed, `MyScreenSaverVersion.res` is not (build.bat rebuilds it)

- Esc: with the information dialog open Esc only closes it (`HandleKey`: `if FInfoShown then HideInfo else Close`); the settings, share and delete dialogs were already protected by `FBusy`
  (the user's report about the settings dialog was not reproduced by reading the code; ask for the mode and focus if it still happens)
- Icon: `MyScreenSaver_Icon.ico` is embedded through the generated `MyScreenSaver.res`; the old dcc64-only build.bat never refreshed it (the .ico has an old file date), see build above.
  To change the version: edit `MyScreenSaverVersion.rc` (4 places: FILEVERSION, PRODUCTVERSION, two strings)

## Caches (all in `%APPDATA%\MyScreenSaver\`, text files, append-only, the last line of a key wins)

- `catalog.cache` (cache 1, `CatalogCacheVersion = 4` in `uMedia`): line 1 `Version<TAB>4<TAB>photos=N<TAB>videos=N<TAB>hasdate=N<TAB>hasgps=N`, line 2 the column names
  (`Record File Kind HasDate Date HasGPS Lat Lon`), then ONE line per file: `F | location | kind | has-date | date | has-GPS | lat | lon`.
  A new file is first written as `F | location | kind` only (not indexed); the indexer appends the full line. The file is rewritten (one line per file, new summary) at the end of every scan
  and after the indexer has finished. A file without the `Version` line or with another number is DELETED, the scan builds a new one and a message box is shown (`OnCatalogCacheReset` ->
  `TViewerForm.CacheResetNotice`, shown by a 0.5 s timer when the window is visible: showing it straight from the scan thread's Queue gave an access violation in `TControlScrollBar.CalcAutoRange`
  at the first start). Change the version number whenever the format changes
- `shown.cache` (cache 2): `location<TAB>count`, how many times a file was shown. A file is counted (`MarkShown`, `TViewerForm.MarkCurrentShown`) when it was shown COMPLETELY (photo: no transition running,
  video: visible) and the slideshow switches to another file; once per file shown (`FCurrentMarked`). Loaded in the scan thread (`LoadShownCache`), compacted by `CompactShownCache`
- `places.cache` (cache 3, own version 1 in `uLocation`): `Version<TAB>1`, columns `Lat Lon PlaceEn PlaceRu`, one line per place with coordinates of 4 decimals (not per file). `ReverseGeocode` /
  `TryGetCachedGeocode` use it through the memory cache; every new answer is appended; a file of another version is deleted silently
- "Clear shown" deletes `shown.cache`; "Clear all" deletes `catalog.cache` and `shown.cache` (not `places.cache`: places are slow to get back, about 1 request per second)

## Random order and the I key (v2.0.0.3)

- Even random order: `TRandomRule` picks only files whose count in `shown.cache` is not above the "level" (`ShownLevel`, in memory); when none is left `MinShownTimes` finds the smallest count and
  raises the level. "On this day" / "Near the current place" prefer files within the level and then show their matches again (`TryRule`, `TryPick(AAllowShown)`) before falling back to random.
  The sequential rules ignore the counters
- I key during a photo transition: `TSlideView.CancelTransition` stops the fade and the old photo stays (the old `TPicture` is kept in `FOld`); `BackToPrevious` makes the old file the current one
  and moves the history position, so the cancelled photo is shown again after the dialog; a transition from black is finished (`Settle` semantics); a video that is not visible yet
  (`FPendingVideo` / `FWaitingOpen`) ignores the key. `FCurrentItem`/`FCurrentPath` are set only when a file is really being shown (`CommitCurrent`)
- Information dialog: a line with the cache state under the text (files, metadata, shown files, cache size, updating / up to date) and the flat `TSpeedButton`s "Open Cache" (opens the folder),
  "Clear shown", "Clear all" (asks first; stops the scan, deletes the caches, scans again)
- Not verified on screen by me: all of the above (the user was to check the transition cancel, the counters, the notice at the first start, places after a restart)

## Fixed along the way (lessons)

- `build.bat` and the running exe: the user often has the app running; the exe is then locked and only the .scr is updated: check `Get-Process MyScreenSaver` and ask the user to close it, never kill it
- Scripted edits: write the Python edit script to a file (Write tool) and run it; a long bash heredoc with quotes failed once

- The IDE (Win64 config) regenerates `MyScreenSaver.res` with its OWN version info (1.0.0.0, wins over `MyScreenSaverVersion.res`: "Duplicate resource" hint) and a PerMonitorV2 DPI manifest
  (the settings form was then clipped on a scaled display). Fix in the dproj: `VerInfo_IncludeVerInfo=false` and `AppDPIAwarenessMode=none` for the Win64 configs; regenerate the .res with
  `msbuild MyScreenSaver.dproj /t:Build /p:Config=Release /p:Platform=Win64 /p:DCC_ExeOutput=%TEMP%\x /p:DCC_DcuOutput=%TEMP%\x` (after `rsvars.bat`); check `(Get-Item MyScreenSaver.exe).VersionInfo.FileVersion`
- Line endings are mixed: `uSettingsForm.pas`/`uRules.pas` are CRLF, `uConfig.pas`/`uViewer.pas`/dproj are LF; in scripted edits detect them first (bash `grep -c $'\r'` is unreliable here)
- A running MyScreenSaver.exe (e.g. the user's settings window) locks the exe: `build.bat` still prints "Built" but only the .scr is updated

- UI freeze at the first slide change: rules read EXIF of hundreds of files in the UI thread -> now cached, indexed in background
- Crash on exit during indexing (TDictionary freed by unit finalization while threads ran) -> `StopScan` waits for all threads
- Do NOT call `Start` after `inherited Create(False)` in a TThread (EThread "Cannot call Start on a running or suspended thread")
- Labels in the settings dialog were cut: label width was fixed

## Open items / notes

- `/p` preview implemented (`uPreview.pas`): one random photo in the small monitor
- Ideas: Ken Burns effect, soft wipe edge, fade between videos
- Rules needing date/GPS ignore HTTP/FTP files; FTP not used by the quick sampler
- `lr:hierarchicalSubject` (Lightroom hierarchical tags) is not read
- Passwords of collections are stored in the INI in plain text
- Testing UI by `SendKeys` is unreliable because the user works on the same machine; ask the user to verify visually
- The latest changes (selectable info text, double click, keywords line) were tested on screen by the user: OK
