# Check list — every round closes with all of these

The suites and the lints catch what code can catch. The last two lines are the
ones that only a live run proves, and they are here because one of them was
lost for a whole round without a single test going red.

## Static

- [ ] `node --test` — all green.
- [ ] `python3 -m unittest discover -s tests -p "test_*.py"` — OK.
- [ ] `/usr/lib/qt6/bin/qmllint -I . shell.qml` — no new warnings (the baseline
      is written down in the round's report).
- [ ] `node tools/lint-style.js` — OK (no raw colours, radii or durations).
- [ ] `node tools/lint-i18n.js` — OK.

## Live, with the panel running (`qs -p ~/.config/qs-novelmangareader`)

- [ ] **Idle fade:** with the pointer off the panel it drops to
      `Panels.IDLE_OPACITY` (0.15, what is behind it shows through); with the
      pointer over it, it returns to 1. Check it by eye *and* by capture — the
      numbers are in the round's report.
- [ ] The screen or row the round touched still does what the brief asked: open
      it with real data and photograph it.

## Read the log, not just the screenshot

- [ ] Grep the round's own log for new WARN/ERROR lines before closing:
      `grep -aE "WARN|ERROR" <log> | sort | uniq -c | sort -rn`.
      A wall of `Unsupported image format` means the art CDN is answering with
      a bot challenge; a grid of placeholders looks like a layout bug and is
      not one. Missing art is never "the capture is fine".

## Two rules learned the hard way

- **Never edit `IDLE_OPACITY` (or any other runtime constant) to take a
  capture.** `services/panels.js` is imported as a JS module, and Quickshell
  does not re-evaluate it when the file changes: a shell started while the file
  said `1.0` keeps `1.0` after the file is restored, and the fade stays gone
  until the shell is restarted. To photograph the panel while the pointer is
  away, park the pointer instead of touching the value.
- **After any temporary edit to the live config, restart the shell** before
  claiming the behaviour is back, and check it live — not only on disk.
