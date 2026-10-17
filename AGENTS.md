# AGENTS.md

Guide for contributors and AI coding agents working on **Tinta**. Read it before changing code. User docs are in
[`README.md`](README.md); the numbered rules (`R-…`) cited in code comments are in
[`docs/arquitetura.md`](docs/arquitetura.md); how to write an app is in [`docs/sdk.md`](docs/sdk.md) (Portuguese, with an
English summary). Code, identifiers and code comments are in English; the UI text is Portuguese with English translations.

## What Tinta is

A [KOReader](https://koreader.rocks) plugin (`tinta.koplugin`, AGPL-3.0) that turns an e-ink reader into an app dashboard:
a home grid of widgets, notifications, per-app scheduled refresh over a single Wi-Fi connection, and a sleep page that stays
on screen while the device sleeps and wakes on the RTC to refresh. Lua (LuaJIT, KOReader's runtime). Tested on a Kindle
Basic 2 (KT3, 600×800); Kobo is experimental; other devices get a generic backend with no scheduled wake-up.

## Repository layout

```
tinta.koplugin/            the plugin (what gets installed into koreader/plugins/)
  main.lua, _meta.lua      KOReader entry: menu item, gesture action, opens/closes Tinta
  core/                    PURE Lua (no KOReader requires): registry, scheduler, layout, notify, store, settings, power,
                           i18n, format, json, firstrun, migrate, extapps, version. Rules R-A1.. live here.  API: core/README.md
  device/                  everything that talks to the device: battery, net (HTTP/Wi-Fi), sleep, wakereq
    backends/              one module per device family: kindle, kobo, generic (+ gauge.lua, driven.lua helpers)
  ui/                      screens and components (KOReader widgets): theme, host, home, organizer, central, wizard, kit, ...
  apps/<id>/               one folder per app: init.lua (manifest + wiring), logic.lua (pure), view.lua, strings.lua, tests/
                           apps/_modelo and apps/_exemplo_json are the SDK references (load only with dev_apps)
  tests/                   suites of core/device, plus apprunner.lua and uistub.lua (helpers for app tests)
tests/                     headless UI smokes (tinta_ui_*.lua), scale test, KT3 pixel baseline in tests/fixtures/
scripts/                   test-all.sh, nova-app.sh (new app), deploy.sh (USB/SSH), pull-logs.sh, build-release.sh
docs/                      sdk.md, arquitetura.md, plataforma.md, tinta-prototipo.html (the visual spec), screenshots/
.github/                   CI (tests), release workflow, issue templates
```

Apps installed by users live **outside** the plugin, in `koreader/tinta-apps/<id>/` on the device (same code, same rules;
they survive plugin updates). An external app with the id of a bundled one is refused.

## Build and test

There is no build step: the plugin is plain Lua. You need **LuaJIT** (`luajit`) on the `PATH`.

```sh
scripts/test-all.sh                       # every suite; exit status 0 = all green (run from anywhere)
luajit tinta.koplugin/tests/run.lua       # core/device suites (QUIET=1 prints only failures and the total)
luajit tinta.koplugin/apps/<id>/tests/run.lua    # one app
SMOKE_APP=<id> luajit tests/tinta_ui_smoke.lua   # load one app (also dev apps) in the headless UI smoke
KOREADER_REF=<koreader sources> scripts/test-all.sh   # optional: also run the store tests on KOReader's real SQLite binding
```

`KOREADER_REF` is optional; without it the SQLite suite is skipped and everything else runs (this is what CI does).
`scripts/test-all.sh` finds `tinta.koplugin/apps/*/tests/run.lua` by itself, so a new app needs no edit there.

What the suites cover: pure logic (`core/`, `apps/*/logic.lua`); the UI built over stubbed KOReader widgets
(`tests/tinta_ui_smoke.lua` drives every screen, overlay, gesture, rotation and notification, and fails on any Lua error and
on any paint outside the screen); the first-run wizard and privacy (`tests/tinta_ui_firstrun.lua`); apps outside the plugin
folder (`tests/tinta_ui_external.lua`); six screen sizes and proportionality (`tests/tinta_ui_scales.lua`).

### The KT3 pixel baseline

The default smoke hashes what every step draws (fake fixed-width font, frozen clock) and compares it with a recorded list:
`tests/fixtures/kt3-trace-public.txt` (**pixel identity on the KT3**: a change that moves a pixel on 600×800 fails the
"KT3 pixel identity" checks). If a change is *meant* to alter the drawing (new widget, new text, new default layout):

1. run the whole smoke and make sure everything else passes, and read the failing step names: they must be exactly the
   steps you meant to change;
2. record the new baseline: `SMOKE_TRACE_OUT=/tmp/new.txt QUIET=1 luajit tests/tinta_ui_smoke.lua` and copy it over
   `tests/fixtures/kt3-trace-public.txt`;
3. say in the PR which steps changed and why. Never re-record to silence an unexplained failure.

Adding an app in `tinta.koplugin/apps/` moves the launcher pages the smoke is pinned to, so new apps are listed in
`tests/fixtures/smoke-skip-apps.txt` (`scripts/nova-app.sh` does it) and tested with `SMOKE_APP=<id>`.

## Writing an app

```sh
scripts/nova-app.sh weather "Weather"     # copies apps/_modelo to apps/weather and renames it
```

Then edit `init.lua` (manifest + `refresh(ctx, done)` + `widget(ctx, size, box)` + `screens`), `logic.lua`, `view.lua` and
`strings.lua`. Read [`docs/sdk.md`](docs/sdk.md): manifest fields, the `ctx` API, widget sizes, the scaled theme,
notifications, performance rules, the publishing checklist. `apps/_exemplo_json` is the pattern for an app that fetches a
JSON from a URL through `ctx.net` (tested with a fake `ctx.net`).

## Hard rules (a PR that breaks one will not be merged)

1. **No store queries in loops.** Never read `store`, `ctx.settings`, `ctx.cache` or `ctx.data` inside a loop or an
   every-minute check: the database sits on a slow filesystem on the Kindle. Read once, keep it in a local variable, write
   back on change. A widget or screen makes **one** cache read per call.
2. **Never name a field or method of a window/dialog `toast`, `modal` or `invisible`.** `UIManager` treats a truthy `.toast`
   as a notice and hides the input dialog (this has crashed KOReader). The smoke checks it.
3. **Never call `getSize()` on a `VerticalGroup`/`HorizontalGroup` that still gets children** (R-L1): KOReader caches the old
   size and the new child has no position. Measure the children first or use `ui.box` with an explicit size.
4. **Pure `core/` and `logic.lua`.** No `require` of KOReader or plugin modules in `core/`, `apps/*/logic.lua` and
   `apps/*/strings.lua` (R-A1): clock, readings and dependencies come in by parameter. A test checks it.
5. **Black and white only**, no animations (R-A3). The only grey is the thin ring track.
6. **`T.px` for every measure.** No raw pixel numbers outside `ui/theme.lua`: use `T.px(n)`, `T.px1(n)`, `T.fpx(n)`, `T.FONT_*`,
   `T.GAP`, `T.s`, read at use time (they change when the screen rotates) and never cached at file top level (R-Z4).
   Touch targets ≥ 64 design px.
7. **Tokens are never shown.** Fields of `type = "token"` are masked, and tokens/passwords/credentialed URLs never reach
   logs, toasts, notifications, screens, diagnostics or backups (R-A4, `Settings.redact_text`). Keep only the fields an app
   uses, never the raw server response.
8. **Only the core touches Wi-Fi, suspend and the wake-up** (R-P1). Apps declare `net = true` and are called when due.
9. **Every call into an app is protected** (R-E1..E3, `registry.call`); do not add `pcall` habits inside apps, let errors rise.
10. **Tests are required.** New logic comes with tests; new apps come with a full suite (logic, app/manifest, strings, view);
    a bug fix comes with the test that would have caught it. `scripts/test-all.sh` must be green.
11. **Texts in `strings.lua`, pt and en with the same keys and format specifiers**; no sentence built from fragments.
12. **Do not change the KT3 pixels unintentionally** (see the baseline section above).

## Device backends

`device/backends.lua` picks one backend per process from KOReader's `Device` (`isKindle()` → `kindle`, `isKobo()` → `kobo`,
otherwise `generic`). A backend module exposes:

- `B.name`, `B.can_wake` (can Tinta wake the device by the clock?);
- `B.battery_read(opts)` and `B.battery_plugged(opts)` (what `device/battery.lua` calls);
- `B.sleep(env)` → a controller (what `device/sleep.lua` drives; see its header).

To add one: create `device/backends/<name>.lua` (start from `generic.lua`, which delegates to KOReader's own suspend and
power device through `driven.lua`/`gauge.lua`), add its detection to `M.name` in `device/backends.lua`, extend
`tinta.koplugin/tests/test_backends.lua` (selection + battery facade) and the sleep suites with fakes of the device, and
document it in `docs/arquitetura.md` 11.x and in the README table as **untested on hardware** until someone runs it on a
real device. Only the KT3 has been verified on hardware: do not claim support you have not tested.

## Where external apps live

On the device: `<KOReader data dir>/tinta-apps/<id>/init.lua` (on a Kindle: `koreader/tinta-apps/<id>/`). Install with
`scripts/deploy.sh --app path/to/<id> --ssh <ip>` (or copy by USB). The plugin's own `apps/` folder loads first; removing an
external app deletes only inside `tinta-apps/`. Their `require("apps/<id>/...")` resolves through `core/extapps.lua`.

## Release

`scripts/build-release.sh` builds `dist/tinta-<version>.zip` containing `tinta.koplugin/` without `tests/` and without the dev
apps (`_modelo`, `_exemplo_json`, `_test_*`). Pushing a tag `v*` runs `.github/workflows/release.yml`, which builds the same
zip and attaches it to the GitHub release. The version shown by Tinta is in `tinta.koplugin/core/version.lua`.

## PR checklist

- [ ] `scripts/test-all.sh` is green (say so, with the counts, in the PR).
- [ ] New or changed behaviour has tests; a new app has a complete suite and a `SMOKE_APP` run.
- [ ] None of the hard rules above is broken; no raw pixel numbers; pt and en strings match.
- [ ] If the drawing changed on purpose, the KT3 baseline was re-recorded and the changed steps are explained.
- [ ] No secrets, tokens, real addresses or personal data in code, tests, docs or fixtures (use `192.0.2.x` for example IPs
      and `contact@hfps.dev`/`noreply` for e-mails).
- [ ] Docs updated if a rule, the SDK or a user-visible behaviour changed (`docs/sdk.md`, `docs/arquitetura.md`, README).
- [ ] Code comments in English, matching the density and style of the file you edited; SPDX header on new files
      (`-- SPDX-License-Identifier: AGPL-3.0-or-later`).
