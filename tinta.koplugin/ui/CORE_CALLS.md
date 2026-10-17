# ui/ → core/: every call

`ui/core.lua` is the only file in `ui/`, `main.lua` and `apps/` that requires `core/`. Everything else calls
the wrappers in that file (through `ui/host.lua`). This list is checked against `core/README.md` of the
core-logic branch (commit `aa8992d`). **Every call is in that README except the ones marked ⚠.**
If core/ changes a name, edit `ui/core.lua` only.

Notation: `c` is the table `ui/core.open` returns: `c.store`, `c.settings`, `c.notify` and `c.registry`.

## Construction (`ui/core.open`, when the Tinta opens)

| Module | Call | Arguments | Returns | Used for |
|---|---|---|---|---|
| store | `Store.open(path, { now })` | `koreader/tinta.sqlite3` | `store, info` | R-B4. `info.recovered/fallback/error` goes to the log |
| store | `Store.memory()` | | store | fallback when `Store.open` throws |
| settings | `Settings.new{ store }` | | S | |
| notify | `Notify.new{ store, now, log, pref = fn(app) → S:notify_pref(app), on_new = fn(n) }` | | center | `on_new` shows the banner (R-T5) and redraws the bell |
| notify | `c.notify:begin_session()` | | | 8.6: the first reading after opening only records state |
| registry | `Registry.new{ now, log, store, notify, is_disabled = fn(id) → S:is_disabled(id) }` | | reg | `is_disabled`: R-M2 |
| store | `c.store:close()` | | | when the Tinta closes |

The log callback core gets is `log(level, app, msg)`. ui/host keeps its own log in the order
`(app, level, msg)`; the adapter converts between the two.

## Apps and ctx

| Call | Arguments | Returns | Notes |
|---|---|---|---|
| `c.registry:register(manifest)` | manifest from `apps/<id>/init.lua` | `true` \| `nil, reason` | rejected apps are logged by core. `reason` `"api"` / `"min_portal"` (needs a newer Tinta, R-M1) or `"disabled"` (R-M2) means the app is parked, not rejected |
| `c.settings:register_app(manifest)` | | | defaults and fields (5.5) |
| `Registry.make_ctx(id, { registry, store, settings, notify, now, log })` | | ctx | ui then adds `ctx.ui` (ui/kit), `ctx.net` (`device/net` when it exists, else nil), `ctx.open(screen, args)`, `ctx.confirm(title, text, ok_label, fn)` and `ctx.toast(text)` |
| `c.registry:check_version(id, ctx)` | | action | R-D2, after register |
| `c.registry:ids()` / `:list()` / `:get(id)` / `:ctx(id)` / `:has(id, "init")` | | | |
| `c.registry:call(id, "import_legacy", ctx)` + `c.store:meta_get/meta_set("legacy_imported:<id>")` | | | at open, before `init` (`ui/core.import_legacy`, R-B5, 16.4): once per app with `manifest.import_legacy`; the key is set unless the call throws or returns `false` |
| `c.registry:call(id, "init", ctx)` | | | at open, for apps that have `init` |
| `c.registry:call(id, name, ctx, ...)` | `name` ∈ `widget`, `attention`, `footer`, `on_route`, `screens.<name>` | `true, ...` \| `false, err` | R-A2/R-E1. The UI draws the R-E2 fallbacks itself (error widget, error screen with Voltar) |
| `c.registry:call_fn(id, fn, "callback", ...)` | an app callback (button, confirm "OK") | `true, ...` \| `false, err` | R-E1/R-E3. On failure the window shows a toast "Erro na app X" |
| `c.registry:refresh(id, ctx, { manual, on_done = fn(id, ok, err, kind) })` | | `true` \| `false, reason` | R-U8, R-E4, R-U7. `kind = "exception"` is an app error; `"done"`/`"timeout"` with `ok = false` is a network failure (R-U6, Sistema rule) |
| `c.registry:state(id)` | | `{ last_ok, last_err, err_text, busy, fail_streak, exc_streak, disabled }` | Conexões, Atualizações |
| ⚠ `Registry.first_frame(traceback)` | | string \| nil | R-E3 for errors outside `registry:call` (render, tick). It is `M.first_frame` in registry.lua, but not in the README |

### Manage apps (5.1, 10.5, R-M1..R-M4: `ui/core.lua`)

| Wrapper | Calls | Used for |
|---|---|---|
| `C.inactive_list(c)`, `C.inactive(c, id)` | `c.registry:inactive_list()` / `:inactive_get(id)` | launcher (disabled rows), Sistema → Apps (disabled and needs-newer apps) |
| `C.TINTA_VERSION`, `C.API_VERSION`, `C.is_protected(id)` | `Registry.TINTA_VERSION` / `.API_VERSION` / `.PROTECTED` | Sistema → Apps texts, no switch for notificacoes / sistema |
| `C.is_disabled(c, id)`, `C.set_disabled(c, id, off)` | `c.settings:is_disabled` / `:set_disabled`, `c.registry:unload(id)` when turning off | ativada / desativada. Turning on: the host registers the parked manifest again (`C.register`), then `C.sort_apps(c, cmp)` (`c.registry:sort_order`), `C.import_legacy(c)`, `C.init_app(c, id)` |
| `C.remove_app(c, id, fs, apps_dir)` | `Appfiles.remove`, `c.registry:forget`, `c.store:purge_app`, `c.store:layout_get/layout_set` for `home` and `sleep`, `c.settings:add_removed` | Remover app. `fs` is the device file system (lfs) built by `ui/host`; `true` \| `nil, reason` |
| `C.removed_ids(c)`, `C.clear_removed(c)` | `c.settings:removed_ids` / `:clear_removed` | `Host:loadApps` skips these folders; "Apps removidas" in Sistema → Apps |

Not used: `reg:widget` and `reg:screen`. The UI calls `reg:call` and draws the fallbacks itself, because screens
get a third argument (see "Contract extensions"). Also not used: `reg:wrap` (`call_fn` instead).

## Layout

| Call | Arguments | Returns | Notes |
|---|---|---|---|
| `Layout.pack(items, cols, rows)` | visible items only, sizes already valid for the app | pages of `{ app, size, x, y, w, h }`, 0-based cells | R-G2. `ui/geom.tile_rect` turns cells into px (R-G4) |
| `Layout.default(page)` | `"home"` \| `"sleep"` | list | when nothing is saved (7.2) |
| `c.store:layout_get(page)` / `c.store:layout_set(page, list)` | | | R-O6, on every organizer change |

The organizer list operations live in `ui/orglogic.lua` (pure, tested), not in `Layout.move/hide/...`. The
reason: items of apps that are not registered yet (for example apps still being ported) stay in the saved list
but are skipped by "↑ Antes / ↓ Depois", so the buttons never swap with an invisible item and the layout
survives until those apps arrive. `Layout.normalize` would drop them.

## Scheduler and state texts

| Call | Arguments | Returns | Notes |
|---|---|---|---|
| `c.registry:sched_entries(ids, c.settings)` | the apps visible on Home | entries | |
| `Scheduler.pick(entries, now, { wifi, quiet = S:tinta("quiet") })` | | ids | the 5 s tick (R-U4) |
| `Scheduler.manual(entries, { wifi })` | | `ids, skipped_network_ids` | Atualizar, the clock, the menu (R-U7). "Sem Wi-Fi" toast when everything was skipped (R-U5) |
| `c.registry:sched_entry(id, c.settings)` + `Scheduler.status(entry, now, { quiet })` | | `{ kind, last_ok, interval, resume }` | footer, header, dashed border (`kind == "failed"` with `last_ok`, R-S5) |
| `Scheduler.next_run(entry, now, { quiet })` | | timestamp \| nil | Sistema → Atualizações |
| `Format.footer(status, narrow, now)` | | `{ left, right? }` | R-W4 |
| `Format.header(status, now)` | | string | 6.4. Bold when `kind` is busy, error or failed |
| `Format.hm(ts)`, `Format.ago(ts, now)`, `Format.every(sec)` | | strings | |

## Settings

| Call | Used for |
|---|---|
| `S:tinta(key)`, `S:set_tinta(key, v)`, `S:cycle_tinta(key)` | `lang`, `landscape`, `nav`, `full_every`, `wifi`, `quiet` (table), `banner`, `sleep_shows`, `wake` (seconds, `"schedule"` or `"never"`), `idle_mode` (`"always"`/`"battery"` (default)/`"never"`), `idle_sleep` (2/5/10/15 min); `ui/core.idle_due(c, last_touch, now, plugged)` passes both to `Power.idle_due`, `plugged` being a boolean or a function only called when needed (`Host:plugged()`, via `device/battery.plugged`) |
| `Settings.CHOICES.notify_pref` | cycling alta → normal → desligada |
| `S:get(id, key)`, `S:set_field(id, key, v)`, `S:display(id, key, T)` | Sistema → Apps → <app> (R-C1..R-C3; tokens are never shown, R-C2) |
| `S:interval(id)`, `S:cycle_interval(id)`, `S:window(id)` | menu "Intervalo desta app", Sistema → Atualizações (R-C4) |
| `S:notify_pref(id)`, `S:set_notify_pref(id, v)` | Sistema → Notificações (R-T2) |
| `S:sleep_visible(id)`, `S:set_sleep_visible(id, v)` (`ui/core.sleep_visible`, `set_sleep_visible`) | the per-app "Mostrar na página de repouso" (R-V1); the sleep page draws a neutral placeholder for a hidden app |
| `S:tinta("sleep_titles")`, `S:tinta("text_size")`, `Settings.text_factor(v)` (`ui/core.text_factor`) | Sistema → Repouso "Títulos na tela de repouso" (R-V3); Sistema → Tela "Tamanho do texto" → `T.set_text_factor` (R-X1) |
| `ui/core.first_run_needed(c, ids)`, `first_run_done(c, at)`, `privacy_init(c, fresh)` | first-use wizard (R-F1..R-F3) and the one-time grandfathering of `sensitive` apps on existing installs (R-V2); `first_run_needed` runs before the apps register |

⚠ The UI also reads the Tinta key `dev_apps` (default false since stage 4), which is not in `Settings.TINTA_DEFAULTS`. When `S:tinta` returns
nil, `ui/host` uses `true`. It loads `apps/_test_*`. Turn it off (or add it to `TINTA_DEFAULTS` as `false`)
before stage 4.

## Notifications

| Call | Used for |
|---|---|
| `c.notify:page(page_1based, per)` | the central, 4 per page in portrait and 2 in landscape (R-T9). ui keeps pages 0-based and converts |
| `c.notify:list{ limit }`, `:count()`, `:unread_count()` | Notificações widget, the bell (R-T6), "N no total" |
| `c.notify:mark_all_read()`, `:clear()` | central footer. `clear` only after the confirmation dialog (R-T10) |
| `c.notify:open(id)` | 8.4. Then the stack becomes Home → `app.screens[screen]` (or `main`). The app's `on_route(ctx, route)` wins when it exists |
| `c.notify.banner_lines(n, app_name)` | R-T5 (called with a dot: it is not a method) |
| `c.notify:sleep_summary(S:tinta("sleep_shows"), S:tinta("sleep_titles") == "hide")` | the black strip of the sleep page (R-T11); the second argument hides the titles (R-V3) |
| `c.notify:emit(app, n)` | only the smoke test and stage-3 code. Apps use `ctx.notify` |
| `c.notify:source_result({ id, name, host }, ok, latency_ms)` | after each network refresh of an app with `manifest.source` (8.6 Sistema rule). `host` comes from the app setting `manifest.source.url_key` (default `"url"`) |
| `c.notify:source_state(id)` | Sistema → Conexões |

## Store, log and data

| Call | Used for |
|---|---|
| `c.store:transaction(fn)` | R-B2: the synchronous part of each refresh cycle |
| `c.store:log(at, app, level, msg)` | the Tinta log (the host forwards every core and UI log line except `debug`) |
| `c.store:log_list{ offset, limit }` | Sistema → Dados (paged) |
| `c.store:stats()` → `{ notifications, log, size_bytes }` | Sistema → Dados and the Sistema main screen |
| `I18n.set_lang(lang)` | together with `ui/strings.set_lang` when the language changes |

## Contract extensions the UI relies on (not in spec 5 or the core README)

- **Screens** are called as `screens.<name>(ctx, args, box)`. `box = { w, h, landscape }` is the body area under
  the app header (`ctx.ui.content_box()` returns the same). A screen returns a widget, or
  `{ body, title?, meta?, emphasis?, no_header? }`. The window draws the app header (6.4) unless `no_header`.
- **Widgets** get `box = { w, h, inv, size, cols, rows, big }`. With `inv` (attention) the app draws white on black.
  `ctx.ui.basic(box, spec)` builds the standard inside (R-W3).
- **Screen size (spec 6.1, R-Z1..R-Z8):** `box`, every `ctx.ui.theme` measure (`T.SB_H`, `T.FONT_BODY`, `T.GAP`…) and every
  size the apps compute are in px of *this* screen: the theme scales the 600x800 design by `T.s` and centres a 3:4
  content box (the Tinta draws only inside it). Apps never write a pixel number: they use `T.*`, `T.px(n)` (design px
  to screen px), `T.px1(n)` (at least 1 px, strokes), `T.fpx(n)` (font sizes, rounded down) or `T.s` (to give
  `ui/shapes`, the chart or the dial their stroke scale). Read `T.X` at call time, never cache it at load: the
  values change when the screen rotates.
- **Optional manifest fields:** `names = { pt, en }` (display name per language; `name` stays the string core
  validates), `footer(ctx, narrow) -> left, right` (system apps), `system = true` (informative),
  `source.url_key`, `notifications[i] = { type, label }` (labels for Sistema → Notificações), and
  `settings[i].hint`.
- **Optional manifest functions for the host:** `import_legacy(ctx)` (one-time import of the old plugins' data,
  see above) and `battery_eta(ctx, { pct, charging }) -> "~17h" | nil` (Bateria; `Host:hookBattery` turns it into
  `Host.battery_eta`, called through `c.registry:call`).
- **Background hook:** `background(ctx, now, kind)` (Bateria's log). `ui/core.background_ids(c)` lists the apps that
  declare it (once, after loading); `ui/core.background(c, ids, now, kind)` calls each through
  `c.registry:call` (protected, one failing app never stops the others). `Host:tick` calls it every
  `Host.BACKGROUND_S` (60 s) on any screen while the Tinta is open (`kind = nil`); `device/sleep.lua` calls
  `Host:background(kind)` with `"sleep"` (entering sleep), `"sched"` (end of a scheduled wake-up), `"button"` (button
  wake) and `"plain"` (forced, unmarked: awake-usb wake-ups); marked calls ignore the 60 s throttle. It must be
  cheap and must not query the store, settings, `ctx.cache` or `ctx.data` per call. `core/registry` validates it
  as an optional function.
- **Sleep (stage 3):** `ui/core` wraps `core/power`: `next_wakeup(c, now)`, `rtc_seconds`, `classify_wakeup`,
  `idle_due`, `sleep_bar`, `wake_plan(c, ids, now)` (`Scheduler.wake` over the sleep-page apps: ids, needs_net),
  and the constants `RTC_REPEAT`, `WIFI_TIMEOUT`. `device/sleep.lua` reaches them only through `ui/host`
  (`Host:wakeTarget`, `rtcSeconds`, `classifyWakeup`, `wakePlan`, `wifiTimeout`) and never requires `core/`.
- **ui/host hooks for later stages (now filled by `device/sleep.lua`):** `Host.battery_eta = fn({ pct, charging }) -> "~17h"` (Bateria, stage 2),
  `Host.enter_sleep = fn()`, `Host.sleeping`, `Host.sleep_info = { text | at, next }` (power, stage 3; the
  sleep page `ui/sleepscreen.lua` and the status bar text R-S4 are drawn already), and `Host.last_touch` (idle
  timer, R-P4).
- **ctx additions (timer / nota / contagem wave):** `ctx.input(title, value, hint, on_save, opts)` (`Host:input`, the
  KOReader keyboard; `on_save(text)` returns `true`, or `false, message` to keep it open; `opts.number`,
  `opts.multiline`, `opts.password`), `ctx.redraw()` (`Host:redraw`), `ctx.back()` (`Window:back`) and
  `ctx.wake_at(ts | nil)` (`Host:wakeRequest`). None of them touches `core/`. Do not open a second input from an
  `on_save`: the host closes the dialog it opened after `on_save` returns.
- **Wake requests (spec 11.7):** `Host:wakeRequest(id, ts)` keeps one request per app in `device/wakereq.lua` (pure) and
  arms a UIManager timer while awake (`Host:armWakeTimer`: refreshes the due apps with reason "auto" and consumes
  them). Asleep, `device/sleep.lua` asks `Host:nextWakeRequest(from)` and the RTC target is
  `Sleep.earliest(schedule target, request)`; `Host:wakePlan(t)` adds the apps whose request is due (within
  `Wakereq.SLACK` = 30 s) to the wake-up batch and consumes them. `Host:afterWake` re-arms the timer. Requests live
  in memory (`Host.wake_reqs`) and die with the Tinta; apps re-request in `init`.
- **First reading of a session (8.6):** `core/notify` drops (and remembers, for the session) what an app emits before
  its first successful refresh finished. Apps that must notify on their first refresh call `done(true)` first and emit
  after it (Contagem), or let the first refresh only arm (Timer).
- **Module names:** KOReader adds the plugin folder to the end of `package.path`. A plugin module must not
  share a name with a KOReader `frontend/` module, because KOReader's wins. Today none of `ui/*`, `core/*`,
  `device/{battery,net,sleep}` or `apps/*` does. Check this before adding files: for example, `ui/geometry`,
  `ui/font`, `ui/size`, `ui/event` and `device/input` are taken.

## Sistema → Dados: diagnostic and backup (wave B)

| Call | Arguments | Returns | Notes |
|---|---|---|---|
| `ui/core.redacted_scope(c, scope)` → `c.settings:redacted_scope(scope)` | `"portal"` \| app id | `{ key = value }` with every secret as `"<redacted>"` | diagnostic |
| `ui/core.backup_env(c)` | | `{ settings, layout_get, layout_set, valid_size }` | `apps/sistema/backup` builds and applies through it |
| `c.settings:export_scope(scope)` / `:import_scope(scope, tbl)` | | table without secrets / `{ applied, skipped, ignored }` | import goes through the validated setters; secrets are never read or written |
| `Settings.secret_key`, `url_has_credentials`, `redact_text` | | | pure helpers shared by both |
| `ui/core.api_version()` | | `Registry.API_VERSION or 1` | |
