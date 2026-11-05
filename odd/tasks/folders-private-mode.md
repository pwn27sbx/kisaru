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
