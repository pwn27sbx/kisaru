# kisaru — folders and private mode

Feature: `folders-private-mode`. Branch: `feat/folders-private-mode` (from `i18n-es`).
Test runner: `node --test` (plus `python3` for the CLI). Scope: manga, novels and anime.
Source plan: `~/Documents/MisokuVault/QS NovelMangaReader/2026-11-05-carpetas-modo-privado/README.md`
(the owner decisions at its end override the sections above).

## Specs

- **S1 (folders model).** A library entry may carry an optional `folder` id. Old entries without it
  mean "no folder" and stay valid. Folders live in `organizer.json` next to the libraries, per kind:
  `{ manga: { folders: [{id, name, hidden}] }, novel: {...}, anime: {...} }`. Writes are atomic; a
  broken file is not overwritten: keep the last good folders, set a load-failed flag and block saves.
- **S2 (folder CRUD).** Create, rename and delete folders. Deleting a folder moves its titles to no
  folder and never deletes a title. Deleting a hidden folder asks for confirmation and the message
  states that its titles become visible.
- **S3 (visible view, fail closed).** `services/library_view.js` returns the visible entries, the
  visible count and the visible folders from entries, folders, the active folder and the lock state.
  While locked, or before organizer data loads, an entry whose `folder` is unknown or unresolved is
  hidden. Hidden folders and their titles exist only while unlocked. Counts always mean all visible
  titles; the status line also names the active folder.
- **S4 (folder row).** The Library tab shows a row under the header with `Todas`, each folder and
  `+`. It starts on the shared gutter (`Gutter.left` / `Gutter.right`). While unlocked a folder can
  be renamed, hidden or deleted and a padlock button locks at once and returns to `Todas`, with no
  message. Without a configured secret no hidden option and no padlock are shown; folder controls
  are never visible while locked.
- **S5 (assign a title).** A folder is assigned to a title from `DetailView` only; no card carries a
  context action.
- **S6 (secret file and CLI).** The secret lives in `$DATA/kisaru/privacy.json`, mode 0600, never in
  `organizer.json`. Record:
  `{"v":1,"salt":"<32 hex>","tag":"<1 hex>","n":131072,"r":8,"p":1,"dk":"<64 hex>"}`. `word` is
  `fold()` plus trim, UTF-8 (lowercase, NFD, strip U+0300-036F, trim). `dk = scrypt(word, salt,
  n, r, p, maxmem=2**28, dklen=32)`. `tag` is the first hex digit of MD5 over `salt + word`.
  `kisaru privado` prompts with no echo and no argument; it refuses words under 8 characters and
  replaces an existing word only after a confirmation. `scripts/privado.py --check <path>` reads at
  most 1024 bytes of stdin, prints nothing, exits 0 on match, 1 on no match, 2 on any error, and is
  stdlib only. `privado` stays out of `kisaru --help`.
- **S7 (unlock).** In Library, the whole trimmed, folded query equals the secret word: the field
  clears, no message, no giveaway animation. Browse in all three panels pre-checks the tag: a tag
  miss sends the search as usual, a hit holds it; exit 1 sends it, while a match, exit 2 or a timeout
  sends nothing and treats it as no query, so the word never reaches a source. The word never enters
  argv, a URL, HTTP or a log. A missing or broken file means no secret is configured and the mode
  stays locked. A generation counter discards stale results and a 2 s watchdog kills the check.
- **S8 (lock triggers).** Locking happens on closing, minimizing or switching the panel, on process
  start, when the word is typed again, and with the padlock button. There is no idle lock. One hook
  in `shell.qml` plus one singleton; no per-panel lock calls.
- **S9 (locked leaves no trace).** While locked a hidden title leaves no trace in grid, list, empty
  state, tab counts, status line, library search, `isInLibrary` display or last-read progress in
  Detail. Browse and catalogue search stay public: a hidden title opened from there shows as not
  saved.
- **S10 (progress).** `updateLastRead` / `updateLastWatched` are a no-op for a hidden entry while
  locked. Saving a hidden title from Browse while locked simulates the save: it shows as saved for
  that session, writes no data, and shows as not saved again after a reload. Progress on hidden
  titles keeps saving while unlocked. Saving it again must neither duplicate nor erase its progress
  or folder.
- **S11 (no trace in logs).** The library logs at `Manga.qml` 175/181/197, `Novel.qml` 243/249/265
  and the anime equivalents no longer print a title, id or chapter number.
- **S12 (paths).** `organizerPath(dataHome)` and `privacyPath(dataHome)` live in `app_paths.js`,
  always under `DATA_DIR`, never the legacy folder.
- **S13 (UI rules and docs).** UI strings go through `I18n.t` with es and en tables; sizes and
  durations use `Style.*`; controls use `Style.cornerRadius`; the row uses `Gutter.left/right`;
  files import `qs.services`. README documents folders and private mode.
- **S14 (verification).** RED first through the public functions. `node --test` stays green,
  including the existing library, search, i18n, lint and `tabCounts` tests, with anime no longer
  raw. Live check: restart kisaru, confirm the process start time is newer than the commit, check
  the hidden list, counts and status line in both view modes, measure the new row's alignment in
  pixels and run with old library files. Never touch the owner's real library data; use a sandbox
  and a test word only there, and never print, log or commit a secret word.

## Tasks

| ID | Spec | Route | Status | Evidence |
|----|------|-------|--------|----------|
| T1 | S1,S3,S12 | inline | done | `66b118d` — `library_view.js`, `lock_state.js`, `privacy.js`, path tests |
| T2 | S6 | inline | done | `66b118d` — `scripts/privado.py`, CLI + fold parity tests |
| T3 | S1,S2 | inline | done | `d4bb6ca` + `60098b6` — `Organizer.qml`, CRUD wiring |
| T4 | S6,S7,S8 | inline | done | `d4bb6ca` — `Privacy.qml`, `shell.qml` hook |
| T5 | S3,S4,S9 | inline | done | `60098b6` — three `LibraryView.qml`, `FolderRow.qml`, `FolderPrompt.qml` |
| T6 | S5,S9,S10 | inline | done | `60098b6` — three `DetailView.qml`, service accessors |
| T7 | S9,S11 | inline | done | `d4bb6ca` — services: visibility, progress guard, log scrub |
| T8 | S7,S8 | inline | done | `60098b6` — panels: debounce, secret hook, lock reset, counts/status |
| T9 | S13 | inline | done | `60098b6` — i18n tables; README in the closing commit |
| T10 | S14 | inline | done | `node --test` 217 pass + live check (grid and list) |

## Log

- **L1 (owner request, verbatim).** "hacer para kisaru un modo de privacidad de mangas (ocultarlo)
  idea que en algun espacio si se dibuja algo con el puntero se desbloquee o una zona especifica
  secreta donde escribir un texto que no se vea lo active y carpetas para orgnizar las lecturas" /
  "me basta con ocultarla de la interfaz". Agreed: folders first, secret word typed in the existing
  search field; hiding is interface-level only, no encryption.
- **L2 (decision).** Folders are available without a secret; hidden folders, hidden controls and the
  padlock exist only when a secret is configured, and only while unlocked. One padlock locks all
  three kinds.
- **L3 (decision).** The visible list is computed once per panel by `library_view.js`; services expose
  `visibleEntries`, `visibleCount`, `visibleEntryId` and `visibleEntry`, while the raw
  `isInLibrary` / `getLibraryEntry` / `libraryEntryId` stay untouched for writes.
- **L4 (plan conflict, resolved).** Amendment 16 names `Muñeca` for the fold-parity test, while
  amendment 21 refuses words under 8 folded characters and `Muñeca` is 6. The setup minimum stays
  as written; the parity test writes a valid record for `Muñeca` directly and runs the real
  `privado.py --check`, then verifies the same record with `services/privacy.js`. The short-word
  refusal is tested on its own.
- **L5 (RED first).** The view, lock and privacy tests failed before the modules existed; the CLI
  tests drove the real helper from the start. The final `node --test` run is recorded in T10.
- **L6 (live check).** Sandbox at `/var/tmp/kisaru-live` (`XDG_DATA_HOME`/`XDG_CONFIG_HOME`), old-format library
  files, one visible old entry, one folder entry and one hidden entry per kind, folders in `organizer.json`,
  and a test word created with `scripts/privado.py`. The owner's libraries were never opened for writing.
  Manga: locked Library showed 2 titles, the hidden folder absent, badge 2 and "2 en la biblioteca"; typing
  the test word cleared the field and showed the hidden folder, title and badge 3; selecting the hidden
  folder gave "3 en la biblioteca · Privado"; the padlock returned to Todas and 2. The same held in list
  mode after a restart. Anime (1 visible, hidden folder absent, "1 en la biblioteca · SUB") and novel
  (1 visible) load in the sandbox. No QML errors in the app log.
- **L7 (measured misalignment, fixed).** The first render put the folder row's box at x=7 while the grid
  cards and the header brand's ink start at x=12: exactly `Gutter.ink` (5 px). The row now uses
  `Gutter.left + Gutter.ink` / `Gutter.right + Gutter.ink`; re-measured at x=12 for the chip row, the
  first card and the brand, in both view modes.
- **L8 (final process).** The owner's app is restarted from the real tree after the last commit:
  commit `9407cca` at 2026-11-04 19:54:49 -05:00, process start 19:54:55 -05:00 (newer by 6 s). The real
  library file still has its 2026-11-02 mtime; no secret exists yet (`privacy.json` and `organizer.json`
  absent), so the real app starts with folders but no private mode, as it should. No QML errors.
- **L9 (review, refuted blocker fixed).** The four lenses were admitted and the refuter confirmed one
  real defect: `Organizer.onLoadFailed` treated an unreadable existing file as a missing one, so the
  next folder write could replace it. The handler now distinguishes `FileViewError.FileNotFound`
  (fresh install) from every other error (keep the last good folders, raise `loadFailed`, block saves).
  The wiring test pins both branches.
## v2: folders as cards (owner feedback, 2026-11-05)

The owner rejected the chip row and the folder picker. This section overrides the folder-row
parts of S1-S4; everything else (private mode, locking, progress, logs, paths) stands.

- **S15 (root).** The Library root is the title grid: folders first, then the titles with no
  folder, then a dashed `Nueva carpeta` card. A folder is a card of exactly a title card's size,
  with a 2x2 mosaic of up to four inner covers (one fills, two split, three use a large left
  cover and two stacked, none shows a folder glyph), its name and its title count below.
- **S16 (folder view).** Opening a folder shows its titles with a back arrow; rename, hide/show
  and delete live inside. Delete keeps the old rules. The hide/show control is kept inside
  because the chip row that used to own it is gone.
- **S17 (list mode).** A folder is a row with a mini collage, the same height as a title row.
- **S18 (search).** A non-empty query returns matching visible titles across every folder, and
  leaves the open folder (the result is library-wide, never folder-scoped).
- **S19 (padlock).** The padlock is a header action, shown only while unlocked.
- **S20 (Detail).** The folder control is a button styled like the other Detail buttons, labelled
  `Carpeta: …`; it opens the real folder list plus `Nueva carpeta`, which creates and assigns in
  place.
- **S21 (collage safety).** Hidden folders and their collages exist only while unlocked; the
  collage is built from the visible list, so a hidden title's cover is never painted while locked.

## v2 log

- **L10 (owner feedback, verbatim).** "mejor como una carpeta como si fuese un manga de ese tamaño
  pero que use de portada un collage de las portadas que tiene dentro". Approved redesign in all
  three panels: no chip row, folder cards, folder view with back/rename/delete, dashed create
  card, header padlock, list mini collage, global search, hidden safety, Detail button with a real
  folder list.
- **L11 (RED first).** `tests/folder_cards.test.js` pins 0/1/2/3/4+ covers, empty covers skipped,
  root order (folders in organizer order, then folderless titles), hidden folder and covers gone
  while locked, and search across folders with accent folding.
- **L12 (deviation).** The owner named rename and delete inside the folder; hide/show is also
  inside, otherwise the private mode would lose its only way to mark a folder hidden. Search from
  inside a folder returns to the root before showing library-wide results.
- **L13 (live check, sandbox).** `XDG_DATA_HOME`/`XDG_CONFIG_HOME` under `/var/tmp/kisaru-live`,
  six folders with generated local covers (5, hidden 1, 2, 3, 0 and 1 titles), one folderless
  title, old-format entries and a test word; the real library was never read for writing.
  Grid: root order, counts, hidden folder absent, dashed create card, folder view with back and
  actions. List: folder rows with mini collages, title row and create row. Pixel measurements:
  folder card **169x341** vs title card **169x341** (same 178 px cell, 5 px card margin, left box
  at x=12); list thumbnails all **62 px tall** with the same **73 px row pitch** (the theme's
  scaled 48x68 / 80). The keyboard was being stolen by the live desktop, so the typed search and
  unlock were not repeated live; both are covered by the RED tests and the earlier live pass.
- **L14 (false alarm).** Two screenshots showed skeleton rows or a missing panel right after a
  file save: Quickshell's hot reload recreated the view while the library was re-reading. With a
  clean start the same clicks render the folder view; no QML error was logged.
- **L15 (v2 review).** The v2 delta alone was reviewed (the full branch exceeded the native reviewer
  budget). Four lenses admitted; the refuter confirmed one blocker: a folder opened while unlocked
  kept its toolbar after a lock and `_toggleHidden` had no lock guard. Fixed in `c0b6561`: the folder
  view and its hide/rename/delete depend on `!Privacy.locked`, the actions refuse while locked and
  the status line never names a folder then. The targeted validator approved the correction; the
  acknowledgement burned authority. Advisory findings left as later work: the three LibraryView /
  DetailView copies have drifted (a shared component would be better), an empty folder shows a blank
  area, `folder.new` and `folder.create` duplicate the same label, and a few picker metrics are
  literals.
- **L16 (regression found live: visible folders could not open while locked).** `c0b6561` put the
  lock in front of every folder (`folderOpen`, `activeFolderName`, rename/delete and the lock
  reset), so with the default locked state no folder opened, and with no secret configured the
  mode stays locked for good. `fc83ffa` gates only a hidden or unresolved folder while locked:
  `services/library_view.js::lockedOut` returns true for a hidden folder, an unknown id, or any
  folder before the organizer loads while locked; a visible folder opens with no secret and while
  locked. A lock keeps a visible folder open and sends a hidden one back to the root. Hide/show
  remains limited to unlocked with a secret. RED tests cover visible-locked, hidden-locked,
  unresolved fail-closed and unlocked; the wiring test pins `lockedOut`, the `activeFolderLockedOut`
  gate, the guards and the reset, and no longer pins the old all-folder gate.
- **L17 (other lock sites).** Re-read every `Privacy.locked` site added by `c0b6561`: the hidden
  folder list and collage, progress guard, simulated save, Detail picker filter, panel title reset
  and padlock visibility are all hidden-only or unlocked-only and were not wrongly gating a visible
  folder.
- **L18 (live check).** Sandbox with `organizer.json`, two library entries and **no
  `privacy.json`**; the app starts locked. Clicking the visible folder opened it: back arrow,
  “Visible”, “2 títulos”, rename/delete present, no padlock and no hide control. Nothing was
  typed; no secret exists. Real library untouched.
- **L19 (review).** The fix was reviewed with risk, reliability and readability lenses; approved
  with advisories only, acknowledgement burned. Advisories left as later work: `_renameFolder`
  and `_confirmDelete` guard on the open folder rather than the `folderId` argument (same at every
  call site today), the lock policy is expressed in the helper plus per-view properties plus the
  hide/show guard, the test message for hide/show is inverted, and the two
  `visible: !activeFolderLockedOut` controls are pinned by one match.
- **L20 (caret).** The caret bar was always at `-width - gap`, which is right only
  at position 0; with text it landed on the last letter. `services/caret.js::barX`
  keeps the negative offset at position 0 and returns 0 otherwise; the delegate
  stays zero-width and the empty-field margin is untouched. Live on the panel:
  at Home the bar is x=1382–1383 with the first glyph at 1387–1389 (3 px gap);
  in the middle it is 1406–1407 between `c` (ends 1404) and `d` (starts 1408),
  1 px each side; at the end 1426–1427 after `f` (ends 1424), 1 px. The text
  origin is x=1387 in all three, unchanged.
- **L21 (privacy.json created late).** Sandbox starts with no `privacy.json`
  (the log shows the read failure). Creating it with `scripts/privado.py` while
  the app runs and typing the word in the Library search unlocks without a
  restart: the padlock appears, the badge goes 2→3 and the hidden folder
  appears. Replacing the word through the CLI locks the app (badge 2, folder
  gone), and the new word unlocks it again. **No fix was needed:** the FileView
  watch sees the file created or replaced after startup.
- **L22 (card status contrast).** The unstarted status was `on_surface_variant`
  (theme muted, ~1.3:1) plus `opacity: 0.45` in the grid strip and `0.5` in the
  list row. One shared token, `Colors.card_secondary` = mix(muted, on_surface,
  0.9), now feeds the progress strips, list datum/progress, folder counts and
  CoverCard's author/meta lines; muted chrome and inactive tabs keep the theme
  role. Live measurements: grid status **4.76:1** on the light cover and
  **4.89:1** on the dark one (band #3a4144), title **6.63:1** on both, folder
  count **5.57:1**; list trailing status **5.84:1**. The title stays strongest.
- **L23 (review).** Readability and reliability lenses; approved with advisories
  only, acknowledgement burned. Advisories: the 0.9 blend is repeated in the
  palette, the contrast helper and a test regex; the contrast module header says
  "hex in, ratio out" although two functions return hex; the active-label
  opacity weights (0.85/0.9) are unnamed; the CoverCard token test does not also
  pin the absence of an opacity.
## v3: simplified hide flow (owner, 2026-11-05 evening)

Overrides the lock/padlock interaction. The owner's words: enter the manga or folder,
press an icon or switch to hide, it disappears from Library; type the secret word in the
search and it shows; simple.

- **S22 (title hidden field).** A title carries an optional `hidden` boolean. While
  locked it leaves the visible shelf on its own, even inside a visible folder: grid,
  list, empty state, counts, status, search and folder collages. Unlocked it returns with
  the rest. Services expose `setHidden`; `isHiddenLibraryEntry` and the progress guard
  cover the title flag as well as the folder flag.
- **S23 (hide switch).** A clear labelled `Ocultar` switch (eye + text + track) sits in a
  title's Detail and inside a folder, visible whenever a word is configured, including
  while locked. Pressing it while locked hides the item at once and returns to the
  Library; while unlocked it hides, locks and returns. Turning it off on a hidden item
  while unlocked un-hides it and stays.
- **S24 (show and lock triggers).** Typing the word in the Library search shows hidden
  items. Lock triggers: pressing Ocultar, closing, minimizing or switching the panel,
  typing the word again, process start.
- **S25 (removed).** The padlock button and the hidden-item mini icon on cover cards are
  gone. The labelled rename/delete actions stay.
- **S26 (30-word measurement).** 30 random sandbox words of 8–16 characters (mixed case,
  accents, trailing spaces), human 80 ms/char and fast 8 ms/char, each written as the
  secret and typed on the real panel. Result: **30/30 human, 30/30 fast (100%)**, with
  tag-hit prefixes present (some words had 1–3). The reported race is not reproducible;
  no Privacy change was made.
- **L24 (live).** The labelled Ocultar switch is visible and readable in the Detail. A
  real click on it hid the title, returned to the root and the count fell 2→1; the
  sandbox library entry then carried `hidden: true`. The owner's fullscreen terminal and
  the virtual-pointer reset made the remaining show/folder clicks unreliable in this
  session; the hidden-title visibility, folder hide and show rules are covered by the
  pure tests (`library_view`, `folder_cards`) and the wiring tests.
- **L25 (review).** Risk, readability and reliability lenses; **approved**, acknowledgement
  burned. The reliability lens opened one blocker (the hide/show click path is not
  behaviour-tested); the refuter refuted it, so it is not open. Advisories left as later
  work: the hide handlers and the folder header are copied in three views, `setHidden`
  names both a title and a folder write, `HideSwitch` and `FolderAction` repeat the same
  control chrome, `folder.hide` labels a title switch too, the service write has no
  privacy gate of its own (the QML handlers gate), and `privacy.lock` is now an unused
  i18n key.
- **L26 (measurement).** 30 random sandbox words of 8–16 characters at human (80 ms) and
  fast (8 ms) speed: **30/30 and 30/30, 100%**, with tag-hit prefixes present (some words
  1–3). The reported unlock failure was wrong (the owner's later evidence showed the word
  unlocks); no Privacy change was made.
- **L27 (tab lock).** Leaving the Library tab hides everything again. The rule lives
  once in `services/panels.js::locksOnTabChange` and one shared hook in
  `components/PanelHeader.qml` (the only tab cell the three panels use), so no panel
  carries its own copy. A return to Library does not unlock, and opening or closing a
  title stays inside the Library stack without changing the tab, so it never locks. A
  hidden title open in Detail follows the existing lock behaviour and returns to the
  Library stack. Pinned in `tests/panels.test.js` and `tests/panel_wiring.test.js`.
- **L28 (toolbar polish).** The folder toolbar is one line: back arrow, name, title count;
  on the right the shared HideSwitch (`Ocultar` when shown, `Oculta` when hidden) and a
  borderless three-dot menu. The separate hidden tag and the bordered switch box are
  gone; Rename and Delete live in the menu (Delete keeps `Colors.error` and its
  confirmation). The switch is one shared component, also used in a title's Detail. The
  menu labels and action order come from `services/toolbar.js`, tested with the switch
  state. Row alignment uses `Gutter.left + Gutter.ink` / `Gutter.right + Gutter.ink`;
  measured on the real folder view: row box x=13..537 in the 550-wide panel (the grid
  cards' box starts at x=12), name x≈41, count ends ≈397, switch ≈424..500, menu
  ≈511..537, all vertically centred in the 40 px row; switch label `on_surface`
  (6.63:1) and dots `card_secondary` (≥4.5:1).
- **L29 (tab lock + toolbar review).** Risk, readability and reliability lenses;
  **approved**, acknowledgement burned. Both reliability blockers (no click-level
  tab-lock/menu tests) were refuted. Advisories left as later work:
  `locksOnTabChange` fails open on a non-numeric previous tab, the menu action
  dispatch is repeated in the three views, the Library tab index is a literal 1,
  the overflow menu does not dismiss on an outside click, and the new toolbar
  assertions overlap between test files. Live: the one-line folder toolbar was
  inspected in the sandbox (back, name, count, state switch, three dots; no box,
  no hidden tag); the row box measured x=13..537 in the 550 panel against cards at
  x=12. The switch/menu real clicks could not be completed reliably because the
  virtual-pointer device resets outside the panel and the owner's fullscreen
  window intermittently sits above the layer; both behaviours are covered by the
  pure and wiring tests.
