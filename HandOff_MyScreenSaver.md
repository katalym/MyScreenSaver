# Handoff: MyScreenSaver (Delphi 13 screensaver and media viewer)

Date: 2026-11-21

## Goal

Windows screensaver (.scr) and standalone photo/video viewer, built from
`C:\Claude\Screensaver\Требования_к_приложению.md`. Delphi 13, VCL, no database, INI config.

## Location and repository

- Project folder: `A:\git\MyScreenSaver` (was `D:\git\MyScreenSaver`) (everything in the root folder, no src/bin/dcu subfolders - user requirement)
- GitHub: `git@github.com:katalym/MyScreenSaver.git`, branch `main`
- Commits: `72f4ea3` initial, `a867883` info dialog / keywords / shutdown fix, `e8cbac7` ru/en languages + /p preview, `6d34598` preview/info/warnings fixes, `35a6662` photo/video selection + video fit + cache compaction, `a6263ca` configurable info-dialog fields, `c45cbc0` default slide time 4 s (by the user), `4ef98e9` slide transitions, `e0e7fb0` filters / version 1.1.1.1 / taskbar button, `1b2d120` tabbed settings + overlay, `479c0cb` share dialog / look, `9b8a7cb` messages instead of a black screen + Paused badge, `6f877a9` version 2.0.0.1 / one active rule / sequential rules / icon (pushed), `855f12c` Esc closes only the info dialog / new icon / build.bat regenerates the .res / version 2.0.0.2, `3fa8491` version 2.0.0.3: even random order, split caches, info-dialog cache line, `d0dd082` back history over restarts + build number = commit count, `77776f8` version 3.0.0: single instance, Filters tab, full screen, Esc question (pushed), `9cbd720` version 3.0.0.1 set by hand, then (the commit of 2026-11-21, version 3.0.0.2): the key S and the sound badge, the hidden mouse pointer, the Esc pause, the share dialog notes, the Yes/No questions, accelerators, the information dialog as a window of its own and as a form unit, the file renames (the user pushes; I never push)
- `a867883` is pushed to `origin/main` (pushed by the user). Pushing is done by the user only on explicit request.
- `.gitignore` excludes `*.exe`, `*.scr`, `*.dcu`, `*.dcr`, `*.res`, `*.local`, `*.dsk`, `*.~dsk`, `__history/`
  (user decided not to keep binaries in git; releases on GitHub are the suggested way to distribute the .scr)

## Build

`build.bat` (version 3.0.0.2, set BY HAND in `MyScreenSaverVersion.rc`, see "Version number") -> single **64-bit** `MyScreenSaver.exe` plus identical copy `MyScreenSaver.scr` in the project root
(since `855f12c` built with `msbuild MyScreenSaver.dproj` Release/Win64, not dcc64: build.bat deletes `MyScreenSaver.res` first so the icon/manifest/version always come from the dproj; output compiled in `%TEMP%\MyScreenSaver_win64`; a few seconds slower). User wants only one 64-bit exe, no separate 32-bit.
`build.bat` prints "Built" even if the final `copy` fails because a running instance locks the exe - check the
exe timestamp / running processes (`Get-Process MyScreenSaver`) when a change seems to have no effect.
`WMPLib.pas` was generated with `tlibimp` from `wmp.dll` (video playback through Windows Media Player).

## Units

| Unit | Purpose |
|---|---|
| `MyScreenSaver.dpr` | args: `/s` saver, `/c` settings, `/p <hwnd>` preview, none = standalone viewer |
| `MyScreenSaver_Config` | INI settings `%APPDATA%\MyScreenSaver\MyScreenSaver.ini` (collections, slide time, active rule, GeoLanguage) |
| `MyScreenSaver_Media` | catalog, scan thread, quick sampler, metadata indexer, `catalog.cache` (cache 1) and `shown.cache` (cache 2), download cache for HTTP/FTP |
| `MyScreenSaver_Rules` | `TMediaRule` (random, onthisday, location, 4 sequential rules `TSequentialRule`) + `PickMedia` |
| `MyScreenSaver_Exif` | own JPEG EXIF reader: camera, date, GPS, orientation, XPKeywords, IPTC and XMP keywords |
| `MyScreenSaver_Location` | distance, IP location, reverse geocoding (OSM Nominatim) with the persistent `places.cache` (cache 3) |
| `MyScreenSaver_Viewer` | code-built form: slideshow, hotkeys, WMP video, the pointer / sound / pause badges; it creates and drives the information dialog (`FInfoForm`, `TInfoForm`) |
| `MyScreenSaver_InfoDialog` | the information dialog: a REAL designed form (`.pas` + `.dfm` loaded at run time, `Arrange` sizes it, `AutoSize` + `Padding`); see "Information dialog as a form of its own" |
| `MyScreenSaver_SettingsForm` | code-built settings dialog |
| `MyScreenSaver_Preview` | `/p <hwnd>`: form parented to the settings-dialog monitor window, shows one random photo, exits when the parent is gone |
| `MyScreenSaver_Lang` | UI language (ru/en): `L('русский','English')`, `SetLanguage`, default from the Windows UI language |
| `MyScreenSaver_InfoFields` | ids/titles of the built-in fields of the info dialog, `InfoFieldOn` |
| `MyScreenSaver_SlideView` | the photo control: halftone-scaled bitmaps, transitions (AlphaBlend / BitBlt, timer 15 ms) |
| `MyScreenSaver_Version` | `AppVersion` read from the version resource of the exe (source: `MyScreenSaverVersion.rc`, compiled to `MyScreenSaverVersion.res` by `build.bat` with brcc32) |
| `MyScreenSaver_Overlay` | the overlay window: small layered (alpha 205) no-activate click-through top-level window owned by the viewer, text of the selected fields at one of 3x3 places |
| `MyScreenSaver_ShareIcons` | 16x16 icons drawn in code (e-mail, Telegram, WhatsApp, Facebook, copy image/path/name; 8x supersampled, straight alpha, `afDefined`) for the TBitBtn glyphs of the share dialog (TButton.Images does not work: no visual styles manifest) |
| `MyScreenSaver_ShareDialog` | the share dialog (a button per action; as wide as its content; EVERY button has a note (black text) at the right - `ShareHintText(action, disabled)`: e-mail "The file will be attached to the e-mail", Telegram / WhatsApp / Facebook "The file will be copied to the clipboard. Paste it (Ctrl+V) into the ... chat", Copy image "The image will be copied to the clipboard", Copy full path / Copy file name "... will be copied to the clipboard as text" (the user asked for notes first only for social media, then for all). "Copy image" is always shown but DISABLED (`ADisabled` of `ShowShareDialog`) unless a photo is on the screen (`ShareButtonClick`: note "Not available: a video is shown now, not a photo"); with notes the buttons are left aligned, otherwise centered) opened by the Share button of the information dialog |
| `MyScreenSaver_Share` | e-mail via MAPI; Telegram/WhatsApp/Facebook = file to clipboard + open app |

## Implemented features

- Hotkeys: Space pause, S sound of the videos (also in the screensaver), I info, Left/Right history prev/next (the size is a setting, see "Back history" below), P share, Esc exit, C settings (standalone)
- Info dialog (colors since 2026-11-21: the same as the settings and the share dialogs - `clBtnFace` background, black text, black cache line and buttons; a gray frame): centered panel sized to the text with gray border, selectable/copyable text (Ctrl+A, Ctrl+C,
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

- Slide transitions (`MyScreenSaver_SlideView`): none, cross-fade, fade through black, slide, wipe, random; INI `Transition=none|fade|black|slide|wipe|random`,
  `TransitionMs=800` (100..3000); never longer than half of the slide, arrow keys <= 250 ms and set the direction (<- backward);
  photo -> video: the photo fades to black first (`FadeOut` + `OnFadedOut` -> `StartVideo`), video -> photo: appears from black,
  video -> video: cut; all effects verified on screen (frames/brightness sampling); committed and pushed. Next ideas: Ken Burns, soft wipe edge, fade between videos

- Filters (settings button "Filters..."): `SilentVideo` (default ON = the sound is off), `SkipLargeVideos` (default ON: pixels of the video > pixels of the
  monitor, checked when WMP reports state 3 playing because the size is 0 before; the player is hidden+muted until accepted),
  `ExcludeRaw` (default ON; RAW extensions are photos only when not excluded, shown only with a codec), `[Exclude] Count/FolderN`
  (skipped by the scanner, the quick sampler, the cache load and the picker via `ItemAllowed`/`IsExcludedPath`); committed and pushed
- Version 1.1.1.1 (4 numbers; the request said "1.1.1.1.1" - a Windows version resource has only four): shown in the settings title and the window title;
  `VerInfo_IncludeVerInfo` is false in the dproj so the IDE does not add a second version resource

- Settings are ONE form with 4 tabs (`MyScreenSaver_SettingsForm`; the dialogs `uFiltersForm` / `uInfoFieldsForm` are gone): Media collections
  (collections + excluded folders), Filters (formerly "File types": photos/videos, silent, skip large, exclude RAW, exclude subfolders by pattern), Play (time, transition,
  active rule (radio group), rule parameters), Information (fields + own EXIF tags); language combo above the tabs;
  one Save/Cancel for everything; committed and pushed. Open question: the transition and the rule parameters (place/tolerance)
  stayed on the Play tab because they had no other tab

- Overlay (5th tab "Наложение"/"Overlay"): same field list as Information (+ own EXIF tags; `TInfoCustomTag.Overlay`), `[Overlay]` in the INI:
  `Fields=`, `Position=topleft..bottomright`, `FontName`, `FontSize`, `ShowNames`; defaults: only `file`, bottom right, Segoe UI 10 pt, names off; `BuildFieldText(AOverlay)` in the viewer
  serves both the info dialog and the overlay; the place name for the overlay comes from the cache, otherwise a background lookup updates it;
  tested on a photo (with GPS/place) and on a video; committed and pushed

- Information dialog = the dialog of actions: three buttons under the text with Delphi-style accelerators in the captions - "&Share..." (ru "Поделиться... (&S)"), "&Delete" (only enabled for local / network files), "&Close" (the user said: "shortcuts" means `&Share`, not "Share (S)"; Windows may show the underline only while Alt is held), so Alt+S / D / C work through the VCL, and plain S / D / C through `HandleKey`; `HandleKey` handles S / D / C FIRST when `FInfoShown` (no Ctrl / Alt; Ctrl+C still copies the text), so S is not the sound key and C is not the settings key then (Share..., Delete, Close = only closes the dialog like the I key): Share... (opens `MyScreenSaver_ShareDialog`: a separate button per action: E-mail, Telegram, WhatsApp, Facebook,
  Copy image (photos only), Copy full path, Copy file name; centered over the viewer); Delete sits one button width to the right of Share and Delete
  (confirmation, default No; Recycle Bin, network files permanent; only local/network files; forgets the file in the catalog
  (`TMediaCatalog.Remove`) and the history, then goes to the next slide). The `P` shortcut is removed. Tested: share dialog list, copy file name, copy image,
  copy path, delete on temp files; committed and pushed (`479c0cb`)
- LESSON: in Delphi 13 `TBitBtn` is NOT a `TButton` (`Sender as TButton` raises "Invalid class typecast"): use `Sender as TComponent` for `Tag`; click every kind of control after changing its class
- TESTING LESSON 2: SendKeys goes to the FOREGROUND window: if `AppActivate` fails, STOP (my keys once reached the user's own running viewer and probably pressed E-mail in its share dialog)
- TESTING LESSON: never press the e-mail/share buttons in automated tests (MAPI opens the user's mail client: Thunderbird compose window opened once)

- Form units (MyScreenSaver_SettingsForm, MyScreenSaver_Viewer, MyScreenSaver_Preview, MyScreenSaver_Overlay, MyScreenSaver_ShareDialog; NOT MyScreenSaver_InfoDialog, which has a real DFM): `{$R *.DFM}` after `implementation`, a minimal `.dfm` for each (the forms are still built in code:
  `CreateNew`, the dfm is never loaded), `{FormName}` comments in the dpr, `<Form>`/`<FormType>dfm</FormType>` in the dproj; the classes TSettingsForm, TPreviewForm and TShareForm
  were moved from the implementation to the interface section (the IDE designer needs them there); committed and pushed (`479c0cb`)

- Look (commit `479c0cb`): ALL buttons have the default height 25 (TBitBtn and TButton); the info text font is configurable (Information tab: font + size, `[Info] FontName/FontSize`, default Consolas 11);
  the field lists (Information, Overlay) have 3 columns (`TCheckListBox.Columns`, they fill down the columns first; the Information list fills the tab, the Overlay list has 9 rows);
  both lists of the Media tab are 120 px, the settings form is 660 x 512 (no empty space at the bottom)
- LESSON: `GetFormImage` of a multi-column list box does not show the columns: take screenshots with `PrintWindow(hwnd, dc, 2)` of the window found by `EnumWindows` for the process id

- Messages (`MyScreenSaver_Viewer`): a centered message instead of a black screen: "No media collections are defined" (no ENABLED collection, `HasEnabledCollection`),
  "No media files available" (collections/exclusions give no items), "Loading the file list..."; Space shows the `FPauseBar` badge ("Paused") at the bottom
  (a TPanel, so it is above the WMP video window; hidden on resume, prev/next, info dialog)
- Rules (v2.0.0.1): the selection mode (Fully random / By rules) and the "Default rule" setting are REMOVED. Play tab = a 2-column `TRadioGroup`
  "Active rule" (one rule, default `random`); INI `[General] ActiveRules=` keeps one name (an old `Mode=random` maps to `random`, several names -> the first);
  if the chosen rule finds nothing, the picker falls back to random. New rules `filenameasc`, `filenamedesc`, `fullnameasc`, `fullnamedesc`
  (`TSequentialRule.PickNext`: one pass over the catalog, smallest item after the previous one, wraps around; position lives only while the app runs; case-insensitive,
  ties by full path). Not verified on screen by me: the radio group layout (height 118, 7 rules) and the sequential play
- Main icon `MyScreenSaver_Icon.ico`; `MyScreenSaver.res` (icon + manifest) is now committed, `MyScreenSaverVersion.res` is not (build.bat rebuilds it)

- Esc: with the information dialog open Esc only closes it (`HandleKey`: `if FInfoShown then HideInfo else Close`); the settings, share and delete dialogs were already protected by `FBusy`
  (the user's report about the settings dialog was not reproduced by reading the code; ask for the mode and focus if it still happens)
- Icon: `MyScreenSaver_Icon.ico` is embedded through the generated `MyScreenSaver.res`; the old dcc64-only build.bat never refreshed it (the .ico has an old file date), see build above.
  Version: see "Version number" below

## Caches (all in `%APPDATA%\MyScreenSaver\`, text files, append-only, the last line of a key wins)

- `catalog.cache` (cache 1, `CatalogCacheVersion = 4` in `MyScreenSaver_Media`): line 1 `Version<TAB>4<TAB>photos=N<TAB>videos=N<TAB>hasdate=N<TAB>hasgps=N`, line 2 the column names
  (`Record File Kind HasDate Date HasGPS Lat Lon`), then ONE line per file: `F | location | kind | has-date | date | has-GPS | lat | lon`.
  A new file is first written as `F | location | kind` only (not indexed); the indexer appends the full line. The file is rewritten (one line per file, new summary) at the end of every scan
  and after the indexer has finished. A file without the `Version` line or with another number is DELETED, the scan builds a new one and a message box is shown (`OnCatalogCacheReset` ->
  `TViewerForm.CacheResetNotice`, shown by a 0.5 s timer when the window is visible: showing it straight from the scan thread's Queue gave an access violation in `TControlScrollBar.CalcAutoRange`
  at the first start). Change the version number whenever the format changes
- `shown.cache` (cache 2): `location<TAB>count`, how many times a file was shown. A file is counted (`MarkShown`, `TViewerForm.MarkCurrentShown`) when it was shown COMPLETELY (photo: no transition running,
  video: visible) and the slideshow switches to another file; once per file shown (`FCurrentMarked`). Loaded in the scan thread (`LoadShownCache`), compacted by `CompactShownCache`
- `places.cache` (cache 3, own version 1 in `MyScreenSaver_Location`): `Version<TAB>1`, columns `Lat Lon PlaceEn PlaceRu`, one line per place with coordinates of 4 decimals (not per file). `ReverseGeocode` /
  `TryGetCachedGeocode` use it through the memory cache; every new answer is appended; a file of another version is deleted silently
- "Clear shown" deletes `shown.cache`; "Clear all" deletes `catalog.cache` and `shown.cache` (not `places.cache`: places are slow to get back, about 1 request per second)

## Version number (set by hand since 2026-11-15)

- The user's decision (after three automatic schemes: commit count, days since 2026-11-01, a counter per commit with code changes - all REMOVED): the version is set BY HAND every time, "forget any automation".
  It is 3.0.0.2 now (3.0.0.1 before the sound key S and the hiding of the mouse pointer). Edit `MyScreenSaverVersion.rc` (4 places: `FILEVERSION`, `PRODUCTVERSION`, the strings `FileVersion` and `ProductVersion`); `build.bat` only compiles it with brcc32.
  The generated `MyScreenSaverBuild.inc` and the version code of `build.bat` are gone; `release_to_github.bat` reads `FileVersion` from the .rc
- `brcc32` 5.40 GARBLES a version string whose length with the closing zero is odd, i.e. a string with an EVEN number of characters (the exe showed `2.0.0.15:InternalName`): write such a string with an
  explicit zero at the end, e.g. `"3.0.0.10\0"` (the comment in the .rc says so). Strings like `3.0.0.1` or `3.0.0.100` are fine
- NO PowerShell in `build.bat`: the user runs it under FAR Manager and a `powershell.exe` call (an earlier version of mine) changed his console
- `build.bat` and every .bat must keep CRLF line endings (a `sed -i` converted `build.bat` to LF once; LF breaks labels in cmd)

## Yes / No questions and the accelerators of the settings dialog

- `AskYesNo(text, title, defaultYes)` (`MyScreenSaver_Viewer`, replaces `Application.MessageBox`): `CreateMessageDialog` with the buttons renamed to "&Yes" / "&No" (ru "Да (&Y)" / "Нет (&N)"), Alt+Y / Alt+N and plain Y / N (`TAskKeys.KeyDown`),
  centered on the main form. Used for the Esc question (default Yes, `ConfirmExit`), the delete question and the "Clear all" question (default No). The plain info boxes (cache reset notice, errors) are still `MessageBox`
- Settings dialog buttons have `&` accelerators, the letters are unique on every tab (hidden tabs do not react). English: &Save, &Cancel; Media collections: Add &folders, Add &address, &Remove, &Exclude folders,
  Exclude a&ddress, Re&move; Information: Add EXIF &tag, Remove &own tag. Russian uses letters of the words (&Сохранить, &Отмена, Добавить &папки, Добавить &адрес, &Удалить, &Исключить, Исключить а&дрес, Уда&лить,
  Добавить EXIF-&тег, Удалить с&вой тег) because the captions are long. The info dialog buttons use "(&S)" style in Russian (letters S, D, C)
- `ShowAccelerators(form)` (`MyScreenSaver_SettingsForm`) sends `WM_CHANGEUISTATE` (UIS_CLEAR, HIDEACCEL + HIDEFOCUS) so the underlined letters are ALWAYS visible (Windows hides them until Alt is pressed): used for the settings dialog, the Yes / No question and the viewer form (info dialog buttons). Save / Cancel are `&Save` / `&Cancel` («&Сохранить» / «&Отмена»; Enter = Save is the default button, Esc = Cancel)
- Not tested on screen by me

## Mouse pointer in the standalone viewer

- `FPointerTimer` (100 ms, standalone mode only) compares `GetCursorPos` with the last position: moved -> `HidePointer(False)`; a dialog is open (`FBusy` or `FInfoShown`) -> visible (the 1 s restarts when it
  closes); no move for 1 s -> `HidePointer(True)`. `HidePointer` uses `ShowCursor` (a counter: every hide is paired with a show, `FPointerHidden`; shown again in the destructor). `ShowCursor(False)` hides the pointer over
  ALL windows of the thread (the WMP video window too, which `Screen.Cursor` / `Cursor` would not reach); that is why the timer polls instead of waiting for WM_MOUSEMOVE (a system MessageBox has its own message loop,
  but TTimer messages still arrive there). The screensaver mode is unchanged (always hidden, `crNone`). Not tested on screen by me

## Sound of the videos: the key S and the "Sound is off" badge

- Key S (the `.exe` AND the screensaver mode: S does not end the screensaver, every other key does; the user asked for it on 2026-11-23) = `TViewerForm.ToggleSound`: flips `Settings.SilentVideo` (the setting "Play videos silently", default ON) and saves it (`Settings.Save`,
  like F11), mutes / unmutes the running video (`FPlayer.settings.mute`; not while `FWaitingOpen`: that stays muted until the size check passes) and, only when NO video is on the screen, shows a 2-second notice ("Sound for playing videos is turned off" / "... turned on",
  `FSoundNotice` + `FSoundTimer`); with a video playing there is no notice: the badge below is the state (the user wants it shown all the time the video plays muted and hidden once the sound is on)
- `FSoundBar` (a TPanel like `FPauseBar`, so it is above the WMP window): `UpdateSoundBar` shows "Sound is off" at the bottom centre while the current file is a VISIBLE video (`FCurrentShown`) and
  `Settings.SilentVideo` is on, or the notice text; hidden with the information dialog; stands above the "Paused" badge when both are shown. Called from `CommitCurrent`, `StartVideo`, `CheckVideoSize`,
  `SetPauseBar`, `HideInfo`, `Resize`, `ToggleSound`; `ShowMessage` hides it. Not tested on screen by me

## Standalone viewer: full screen and Esc

- Setting `[General] FullScreen` (default 0 = as before: a maximized window with a caption): Play tab, check box next to "Back (←), files". `TViewerForm.SetFullScreen` (standalone mode only) removes
  `WS_CAPTION or WS_THICKFRAME` with `SetWindowLongPtr` and sizes the window to its monitor (`SWP_FRAMECHANGED`), WITHOUT recreating the window (a `BorderStyle` change would recreate it and the WMP
  control); the old placement is kept in `FSavedPlacement` (`GetWindowPlacement`, a maximized window is restored first) and is set back when the full screen is switched off. Applied at `DoShow` and after the
  settings dialog; the key F11 switches it and saves the choice (`Settings.Save`). In the screensaver mode F11 is just a key that ends it
- Esc in the standalone viewer asks "Close the application?" (`ConfirmExit`: `MB_YESNO or MB_DEFBUTTON1`, `FBusy` is set so the keys go to the box; while the question is open the slideshow stands still: `FPaused` is set, the timer is off and a video is paused; "No" resumes (a photo gets its full time again, a video continues), a slideshow paused by the user stays paused); Esc with the information dialog open still closes only
  the dialog; in the screensaver mode Esc closes at once. The window's own close button closes at once (not asked for). Not tested on screen by me

## Single instance and the Filters tab

- One viewer / screensaver at a time: `MyScreenSaver.dpr` creates the named mutex `Local\MyScreenSaver_Viewer` (kept until the process ends) after the `/c` and `/p` branches. If it already exists
  the new process ends at once; a second STANDALONE start first brings the first window (`FindWindow('TViewerForm')`) to the front. So the `.scr` that Windows starts while the user watches the
  slideshow in the `.exe` does nothing. `/c` (settings) and `/p` (preview) are NOT blocked. Not tested on screen by me (a test would open a full-screen window on the user's desktop)
- The settings tab "File types" is now "Filters" / "Фильтры" (`FTabTypes`): what to show, videos, photos (RAW) and the new group "Exclude subfolders by pattern" (`FGbPattern` + `FPatterns` memo):
  regular expressions, one per line, modelled on `grbExcludeFolders` / `memExcludeFoldersMask` of `A:\git\FoldersToPiwigoSyncr` (there: `TRegEx.Create(s, [roIgnoreCase]).Match(folder name)`)
- INI `[Exclude] PatternCount`, `Pattern1…` (`Settings.ExcludePatterns`). Defaults `^dng$` and `^panoramas$` (set in the constructor; replaced by the INI list only when `PatternCount` exists in the INI, so an empty saved list stays empty). `MyScreenSaver_Media.IsExcludedByPattern(path, AIsFolder)`: finds the collection root of the path (longest match), takes the folders BELOW the root
  (for a file path without the file name) and matches each folder NAME with the compiled patterns (`PatternRegexes`: cached, rebuilt when the pattern text changed, a wrong pattern is ignored;
  HTTP/FTP names are URL-decoded). Used in `ItemAllowed`, in `LoadCatalogCache` and at the 4 places where the scanner decides whether to enter a folder, so excluded folders are not scanned and
  disappear from the cache at the next scan. Saving the settings rescans (`OpenSettings`), as for the excluded folder list
- Not verified on screen/with data by me: the Filters tab layout (the pattern group is at top 260, height 112), the patterns on real folders

## File names and the information dialog as a form of its own (2026-11-21)

- ALL units and forms are named `MyScreenSaver_<Name>.pas` / `.dfm` (the user's decision, first `MyScreenSaver_u<Name>`, then without the `u`): `MyScreenSaver_Config`, `_Exif`, `_InfoDialog`, `_InfoFields`, `_Lang`,
  `_Location`, `_Media`, `_Overlay`, `_Preview`, `_Rules`, `_SettingsForm`, `_Share`, `_ShareDialog`, `_ShareIcons`, `_SlideView`, `_Version`, `_Viewer` (`WMPLib.pas`, `MyScreenSaver_Icon.ico`, `MyScreenSaverVersion.rc` unchanged).
  A unit name must equal its file name, so the `unit` line, every `uses`, `MyScreenSaver.dpr` (`... in '...pas'`) and `MyScreenSaver.dproj` (`DCCReference`) were changed too (a regex with word boundaries over pas / dpr / dproj).
  Renamed with `git mv`; `ShareDialog.pas` changed so much that git shows it as delete + add (`R049`, below the 50% of the default detection; `git diff -M40%` shows it as a rename)
- The information dialog is `TInfoForm` in `MyScreenSaver_InfoDialog.pas` + `.dfm` (the user: "a form added to the project as a separate unit pas and dfm, not generated at run time"): controls `memText`, `bvlText`,
  `lblCache`, `btnOpenCache` / `btnClearShown` / `btnClearAll` (TSpeedButton), `bvlButtons`, `btnShare` / `btnDelete` / `btnClose`; a window of its own (`BorderStyle = bsDialog`, a caption to drag it by),
  `PopupParent` = the viewer, `fsStayOnTop` in the screensaver mode, colors = the settings / share dialogs. The viewer only creates it (`TInfoForm.Create(Self)`), points its own fields (`FInfoText`, `FShareBtn`, ...) at the
  form's controls, sets the events and the language texts, and calls `Arrange(text, maxWidth)` (`ShowInfoPanel`); it remembers the position (`FInfoPos`) for the next opening; the keys of the dialog window are accepted in
  `AppMessage` (the hwnd filter); the X button = Close (`InfoFormClose`); the share dialog opens over it
- AutoSize (the user asked for it): the form has `AutoSize = True` and `Padding` 16 / 16 / 16 / 12, the cache label has `AutoSize`. `TButton` / `TSpeedButton` have NO published `AutoSize` (the DFM failed to load: "Property
  AutoSize does not exist"), so their widths are measured from the captions; the memo cannot size itself to its text, so its height is computed from the lines. Learned: with `AutoSize` the form moves its
  `alNone` controls so that the bounding box starts at 0 (+ Padding): the positions in `Arrange` start at 0 and the margins are the `Padding`. A throwaway console program (compile the unit, `Create`, `Arrange`, print the sizes, never `Show`)
  checks that a DFM loads and gives numbers without opening a window on the user's desktop (it was in the scratchpad)

## Back history (v2.0.0.x, `d0dd082`)

- Setting `[General] HistorySize` (default 100, 0..100000, 0 = no back history): Play tab, row "Back (←), files" under the slide transition (the rest of the tab moved down by 32). The in-memory
  `FHistory` keeps `HistorySize + 1` files
- `history.cache` (cache 4, own version 1 in `MyScreenSaver_Media`): `Version<TAB>1`, column line `File`, then one path per line, the oldest first. A file is appended when it is shown for the FIRST time
  (`FAppendHistory` is set in `GoNext` after `PickMedia` and used in `CommitCurrent`; going back appends nothing). `LoadHistoryLocations(N)` returns the last N and cuts the file when it has many more lines
- `TViewerForm.RestoreHistory` (called at the start of `GoNext` / `GoPrev`, once, when the catalog is `Ready`): looks the paths up in the catalog (`TMediaCatalog.TryGetItem`), skips what is gone or no longer
  `ItemAllowed`, inserts them in front of `FHistory`; with an empty history `FHistPos` is set to `Count` ("one past the last"), so the first "back" shows the last restored file and "next" picks a new one
- "Clear all" does not delete `history.cache`. Not verified on screen by me: back after a restart, size 0, the Play tab layout

## Random order and the I key (v2.0.0.3)

- Even random order: `TRandomRule` picks only files whose count in `shown.cache` is not above the "level" (`ShownLevel`, in memory); when none is left `MinShownTimes` finds the smallest count and
  raises the level. "On this day" / "Near the current place" prefer files within the level and then show their matches again (`TryRule`, `TryPick(AAllowShown)`) before falling back to random.
  The sequential rules ignore the counters
- I key during a photo transition: `TSlideView.CancelTransition` stops the fade and the old photo stays (the old `TPicture` is kept in `FOld`); `BackToPrevious` makes the old file the current one
  and moves the history position, so the cancelled photo is shown again after the dialog; a transition from black is finished (`Settle` semantics); a video that is not visible yet
  (`FPendingVideo` / `FWaitingOpen`) ignores the key. `FCurrentItem`/`FCurrentPath` are set only when a file is really being shown (`CommitCurrent`)
- Information dialog: two separator lines (`FSepText`, `FSepButtons`: a lowered `TBevel`, shape `bsTopLine`): between the information about the file and the cache line, and between the cache line and the buttons. A line with the cache state under the text (files, metadata, shown files, cache size, updating / up to date) and the flat `TSpeedButton`s "Open Cache" (opens the folder),
  "Clear shown", "Clear all" (asks first; stops the scan, deletes the caches, scans again)
- Not verified on screen by me: all of the above (the user was to check the transition cancel, the counters, the notice at the first start, places after a restart)

## Fixed along the way (lessons)

- `build.bat` and the running exe: the user often has the app running; the exe is then locked and only the .scr is updated: check `Get-Process MyScreenSaver` and ask the user to close it, never kill it
- Scripted edits: write the Python edit script to a file (Write tool) and run it; a long bash heredoc with quotes failed once

- The IDE (Win64 config) regenerates `MyScreenSaver.res` with its OWN version info (1.0.0.0, wins over `MyScreenSaverVersion.res`: "Duplicate resource" hint) and a PerMonitorV2 DPI manifest
  (the settings form was then clipped on a scaled display). Fix in the dproj: `VerInfo_IncludeVerInfo=false` and `AppDPIAwarenessMode=none` for the Win64 configs; regenerate the .res with
  `msbuild MyScreenSaver.dproj /t:Build /p:Config=Release /p:Platform=Win64 /p:DCC_ExeOutput=%TEMP%\x /p:DCC_DcuOutput=%TEMP%\x` (after `rsvars.bat`); check `(Get-Item MyScreenSaver.exe).VersionInfo.FileVersion`
- `sed -i` (Git Bash) converts CRLF files to LF (it happened to `build.bat` and `ShareDialog.pas`): never use it on pas / bat / dproj; use a Python script (read bytes, keep the line ending). A `rm` with a variable glob (`rm -f "$S"/*.dcu`) is blocked by a safety check: use explicit paths. Line endings are mixed: `MyScreenSaver_SettingsForm.pas`/`MyScreenSaver_Rules.pas` are CRLF, `MyScreenSaver_Config.pas`/`MyScreenSaver_Viewer.pas`/dproj are LF; in scripted edits detect them first (bash `grep -c $'\r'` is unreliable here)
- A running MyScreenSaver.exe (e.g. the user's settings window) locks the exe: `build.bat` still prints "Built" but only the .scr is updated

- UI freeze at the first slide change: rules read EXIF of hundreds of files in the UI thread -> now cached, indexed in background
- Crash on exit during indexing (TDictionary freed by unit finalization while threads ran) -> `StopScan` waits for all threads
- Do NOT call `Start` after `inherited Create(False)` in a TThread (EThread "Cannot call Start on a running or suspended thread")
- Labels in the settings dialog were cut: label width was fixed

## Open items / notes

- `/p` preview implemented (`MyScreenSaver_Preview.pas`): one random photo in the small monitor
- Ideas: Ken Burns effect, soft wipe edge, fade between videos
- Rules needing date/GPS ignore HTTP/FTP files; FTP not used by the quick sampler
- `lr:hierarchicalSubject` (Lightroom hierarchical tags) is not read
- Passwords of collections are stored in the INI in plain text
- Testing UI by `SendKeys` is unreliable because the user works on the same machine; ask the user to verify visually
- The latest changes (selectable info text, double click, keywords line) were tested on screen by the user: OK
