# Tinta core: interface

Pure Lua modules (R-A1): no `require` of KOReader modules. Clock, store, log and callbacks are injected.
Require them as `require("core/<name>")`; KOReader puts the plugin folder on `package.path`, and the tests do the same.
Spec: `docs/arquitetura.md` (rule numbers `R-…` below).

Tests: `luajit tinta.koplugin/tests/run.lua [suite ...]` from the repo root (`QUIET=1` prints only
failures and the total). The SQLite suite runs against KOReader's real binding when
`KOREADER_REF=<dir with common/lua-ljsqlite3>` is set (default `../.koreader-ref` from the plugin). Otherwise it is skipped.

Conventions:
- Times are Unix seconds. Functions that need local time take an optional `date` function with the
  signature of `os.date` (default `os.date`). The tests pass a UTC one (`Format.utc_date`).
- Logging callbacks are `log(level, app_id_or_nil, msg)`, with level `debug | info | warn | error`.
- "Returns ok, … | nil/false, reason": these functions never throw for bad input.

## registry.lua: apps, protected calls, refresh runs (5, R-E*, R-U8, R-D2)

| Function | What it does |
|---|---|
| `Registry.validate(manifest)` | `true` or `nil, reason`. Requires `id` (`[a-z0-9_]+`), `name`, `sizes` (from `Layout.SIZES`) and `widget`. `refresh` is optional: an app without it has no refresh (Notificações, Sistema). `background`, when present, must be a function (host hook called every minute while the Tinta is open and around suspends; see ui/CORE_CALLS.md). |
| `Registry.new{ now, log, store?, notify?, busy_timeout?, is_disabled? }` | Creates a registry. With `store`, app state is saved and restored. With `notify`, the app is armed after its first good refresh. `is_disabled(id)` says whether the user turned an app off (R-M2). |
| `reg:register(manifest)` | `true` or `nil, reason`. Rejections are logged and never throw. An app that needs a newer Tinta (R-M1) or is turned off (R-M2) is **not registered**: `nil, "api" \| "min_portal" \| "disabled"` (checked before the rest of validation; `Registry.PROTECTED` apps ignore `is_disabled`). The manifest is parked for `reg:inactive_list()`. |
| `Registry.compat(manifest)` | R-M1: `true`, or `false, "api" \| "min_portal"`. No `api` = 1. Pure; uses `TINTA_VERSION` / `API_VERSION` from `core/version.lua` (also `Registry.TINTA_VERSION`, `Registry.API_VERSION`). `validate` also checks `api` (integer ≥ 1) and `min_portal` ("x.y"). |
| `Registry.PROTECTED` | `{ notificacoes = true, sistema = true }`: cannot be turned off or removed. |
| `reg:inactive_list()`, `reg:inactive_get(id)` | Apps that are not loaded, in the order they were seen: `{ id, name, names, why = "disabled" \| "api" \| "min_portal", system, protected, api, min_portal, description, manifest }`. |
| `reg:unload(id)` | Turns a loaded app into a parked ("disabled") one at runtime; `false` for unknown or protected ids. State and ctx are dropped. |
| `reg:forget(id)` | Drops an app completely (loaded or parked); used by remove. `reg:sort_order(cmp)` re-sorts the registration order after a late register. |
| `reg:get(id)`, `reg:ids()`, `reg:list()` | Look up manifests, in registration order. |
| `reg:call(id, name_or_fn, ...)` | R-A2/R-E1. `name` is a manifest path (`"init"`, `"screens.main"`, `"on_route"`) or a function. Returns `true, results…` or `false, err`. A missing function gives `false, "missing"` and is not logged. Errors are logged as `"<fn>: <msg> · <first frame>"` with the app id (R-E3). |
| `reg:has(id, name)` | Whether the app defines that function. |
| `reg:wrap(id, fn, label)` | Wraps a callback the app gave the core (confirm, button), so it can be called safely. Errors are logged and the wrapper returns `nil`. |
| `reg:call_fn(id, fn, label, ...)` | Same as `call`, for a bare function. |
| `reg:widget(id, ctx, size, box, fallback)` | R-E2. Returns `widget, true`. On an error or a `nil` result it returns `fallback(manifest, size, box, err), false`. Text for the fallback: `reg:error_text(id)` ("Nome · erro na app"). |
| `reg:screen(id, name, ctx, args, fallback)` | R-E2. Returns `screen, true`, or `fallback(manifest, name, err), false` (the error screen with Voltar). |
| `reg:attention(id, ctx)` | Boolean. `false` if the function is missing or fails. |
| `reg:refresh(id, ctx, { manual?, on_done? })` | Runs `refresh(ctx, done)`. Returns `true`, or `false, "unknown" \| "no_refresh" \| "busy" \| "disabled"`. More below. |
| `reg:state(id)` | The `ctx.state` table: `{ last_ok, last_err, err_text, busy, fail_streak, exc_streak, disabled }`. |
| `reg:set_ctx(id, ctx)`, `reg:ctx(id)` | Store and read the app's ctx. `make_ctx` sets it. |
| `reg:sched_entry(id, settings)`, `reg:sched_entries(ids?, settings)` | Entries for the scheduler. Interval and window come from `settings`. `manifest.in_window(ctx, now)`, if present, decides the window (R-U2, e.g. working days). |
| `reg:check_version(id, ctx)` | R-D2. Compares `manifest.version` with the stored one. Returns `"new" \| "same" \| "migrated" \| "cache_cleared"`. |
| `Registry.make_ctx(id, { registry, store, settings, notify, now, log })` | The core part of ctx (5.2): `now`, `settings`, `data`, `cache` (`:get()` returns `value, fetched_at, version`; `:put(tbl)`), `notify`, `state`, `log`, `i18n` (from `manifest.strings = { pt = {}, en = {} }`). ui/main adds `open`, `confirm`, `toast`, `ui` and `net`. |

How `reg:refresh` behaves:

- **One run per app (R-U8).** A request while a run is busy is queued and runs after `done`. A run that never calls `done` stops blocking after `busy_timeout` (120 s) and counts as a failure.
- **`done(ok, err)`.**
  - `ok`: sets `last_ok` and resets `fail_streak`.
  - Not `ok`: a network failure (R-U6). Sets `last_err` and `err_text` and increments `fail_streak`.
  - Only the first call per run counts.
- **Exceptions (R-E4).** An exception in `refresh` counts toward `exc_streak`. Three in a row set `disabled`, which turns auto refresh off. `{ manual = true }` clears it (R-U7).
- **`on_done(id, ok, err, kind)`.** `kind` is `"done" | "exception" | "timeout"`.

## version.lua, appfiles.lua: versions and removing an app's folder (R-M1, R-M3)

| Function | What it does |
|---|---|
| `Version.TINTA_VERSION` ("0.1"), `Version.API_VERSION` (1) | The two versions the Tinta declares, in one place. Raise `API_VERSION` only when an app written for the old one could break. |
| `Version.parse("x.y")`, `Version.compare(a, b)` | Numeric parts (`"0.10"` > `"0.9"`); `nil` for a non-version. `compare` returns -1, 0, 1. |
| `Appfiles.valid_id(id)`, `Appfiles.path_of(apps_dir, id)` | `[a-z0-9_]+` only; `path_of` gives `apps_dir/id` or `nil, reason`. |
| `Appfiles.remove(fs, apps_dir, id)` | Deletes `apps_dir/<id>/` recursively. `fs = { dir, link, is_dir, remove, rmdir }` is injected (the host passes lfs). Returns `true, entries` or `nil, "bad id" \| "no apps dir" \| "is a link" \| "not a folder" \| <fs error>`. Never leaves `apps_dir/<id>`: symbolic links are unlinked, not followed; a failing delete stops and reports. |

## layout.lua: grid, packing, organizer, paging (6.1, 7, 6.6)

A layout is an ordered list of `{ app, size = "WxH", hidden? }` (R-G1). Packed positions are **0-based cells**: `x` is the column, `y` is the row.

| Function | What it does |
|---|---|
| `Layout.SIZES`, `Layout.GAP` (8), `Layout.DEFAULT.home/.sleep`, `Layout.default(page)` | Constants and the default layouts (7.2). `default` returns a copy. |
| `Layout.grid_dims(landscape)` | Returns `cols, rows`: 6, 8 in portrait and 8, 6 in landscape. |
| `Layout.parse_size("4x2")`, `Layout.valid_size(s)` | Parse a size into `4, 2`. Check whether a size is allowed. |
| `Layout.pack(list, cols, rows)` | R-G2. Returns pages, each a list of `{ app, size, x, y, w, h }`. Hidden items and bad sizes are skipped. Oversized items are clamped to the grid. An empty layout gives `{ {} }`. |
| `Layout.find_page(pages, app)` | The 1-based page index holding `app`, or `nil`. |
| `Layout.cell_size(area_w, area_h, cols, rows, gap?)` | R-G4. Cell width and height in px, floored. |
| `Layout.box(item, cell_w, cell_h, gap?)` | Pixel box `{ x, y, w, h }` of a packed item, relative to the grid origin. |
| `Layout.visible_apps(list)` | Ids in order, without repeats. These are what the scheduler refreshes (R-U4). |
| `Layout.normalize(list, apps_by_id)` | Drops unknown and repeated apps. Replaces undeclared sizes with the app's first size. |
| `Layout.move(list, app, ±1)`, `cycle_size(list, app, sizes)`, `hide`, `remove`, `show(list, app, default_size)`, `outside(list, all_ids)` | Organizer operations (R-O3/R-O4). Each returns `new_list, changed` and never modifies the input. |
| `Layout.paginate(n, per_page, page)` | Returns `page, pages, first, last` (1-based). There is always at least one page. |

## scheduler.lua: when to refresh (9)

An app entry is `{ id, interval, net, window, last_ok, last_err, last?, busy, disabled }`. `interval` is in seconds: `0` means manual and `nil` means no refresh. Get entries from `reg:sched_entries`.

| Function | What it does |
|---|---|
| `Scheduler.INTERVALS`, `valid_interval(v)`, `cycle_interval(v)` | R-U1. The cycle is 30 s → … → 1 h → manual → 30 s. |
| `Scheduler.TICK` (5), `BATCH_AHEAD` (120), `QUIET_DEFAULT` | R-U4 and R-U3 constants. |
| `Scheduler.in_window(window, now, date?)` | R-U2. `{ from, to, weekdays?, in_window? }`. Both ends are inclusive. `from > to` wraps past midnight. |
| `Scheduler.quiet_now(quiet, now, date?)` | R-U3. `{ enabled, from, to }`. The end is exclusive. |
| `Scheduler.failed(entry)` | R-S5. True when `last_err` is newer than `last_ok`. |
| `Scheduler.pick(entries, now, { wifi?, quiet?, date?, ahead? })` | R-U4. Returns `ids, n_network`: what is due, plus what falls due in the next 2 min. It is empty when nothing is due. Skips busy and disabled entries, entries outside their window, network apps during quiet hours, and network apps without Wi-Fi (R-U5). |
| `Scheduler.manual(entries, { wifi? })` | R-U7. Returns `ids, skipped_network_ids`. Ignores interval, window, quiet hours and the R-E4 lock. Network apps are skipped without Wi-Fi; that is when to show the "Sem Wi-Fi" toast. |
| `Scheduler.wake(entries, now, opts)` | R-P6. Sleep-page batch: ignores the interval but respects the window and quiet hours. Manual-only apps stay out. |
| `Scheduler.next_run(entry, now, opts)` | Timestamp of the next auto refresh, or `nil`. Used by Sistema → Atualizações. |
| `Scheduler.status(entry, now, opts)` | `{ kind, last_ok, interval, resume? }`. `kind` is `none \| busy \| error \| failed \| paused \| ok`. `paused` covers out-of-window and, for network apps, quiet hours. `resume` is "HH:MM". |

## notify.lua: notifications (8)

| Function | What it does |
|---|---|
| `Notify.new{ store, now, pref = fn(app), log, on_new = fn(n), first_read_gate = true, armed = {"sistema"}, max = 200 }` | Creates the notification center. |
| `c:emit(app, { key, title, body?, prio?, route?, type? })` | Returns the id, or `nil, "invalid" \| "off" \| "dup" \| "first_read"`. Covers R-T1 dedup by (app, key), read or not; R-T2 preferences `alta` / `normal` (lowers alta) / `desligada` (dropped and logged); and the R-T4 limit, where read notifications are dropped oldest first, then unread. Calls `on_new` for the R-T5 banner. |
| `c:emitter(app)` | Returns `ctx.notify`. |
| `c:begin_session()`, `c:arm(app)`, `c:is_armed(app)` | 8.6: until an app is armed, its notifications only record their key and are not shown. The registry arms an app after its first good refresh. `begin_session` disarms all apps; call it when the Tinta opens. |
| `c:unread_count()` (R-T6), `c:count()`, `c:get(id)`, `c:list{offset, limit, unread}` | Counts and reads. Lists are newest first. |
| `c:page(page, per_page)` | R-T9. Returns `items, page, pages`. Use 4 per page in portrait and 2 in landscape. |
| `c:mark_read(id)`, `c:mark_all_read()`, `c:clear()` | R-T10. The UI confirms before `clear`. |
| `c:open(id)` | 8.4. Marks the notification read and returns `{ id, app, screen, args }`. `screen` is `route[1]`, or `"main"` when there is no route. |
| `c:sleep_summary(mode, hide_titles?)` | R-T11. `mode` is `alta`, `todas` or `nenhuma`. Returns `nil` or `{ count, latest, text }`. With `hide_titles` (R-V3) the text is only the count ("1 não lida"). |
| `c.banner_lines(n, app_name, date?)` | R-T5. Returns `"App · HH:MM", title`. |
| `c:source_result({ id, name, host }, ok, latency_ms?)` | 8.6 Sistema rules. Emits `down:<src>:<t>` (alta) on the 2nd failure in a row, and `up:<src>:<t>` (normal) on the first success after that. |
| `c:source_state(id)` | Data for the Conexões screen: `{ fail_streak, down, down_since, last_ok, last_err, latency }`. |

## store.lua: persistence (12, R-B*)

| Function | What it does |
|---|---|
| `Store.memory(opts?)` | In-memory backend for tests, and the fallback when the database fails. |
| `Store.sqlite(path, { now?, sq3?, rename?, remove?, migrations? })` / `Store.open` | Returns `store, info`. `info` is `{ recovered, bad_path, fallback, error }`. The binding `lua-ljsqlite3/init` is required lazily. A corrupt or unreadable file is renamed `path.bad-YYYYMMDD-HHMMSS`, a new database is created and the log notes it (R-B4). A failing **migration** leaves the file alone and returns a memory store (`info.fallback`). Without the binding, it returns a memory store. |
| `Store.MIGRATIONS`, `Store.pending(v, migs)`, `Store.latest_version(migs)` | R-B3. Each migration is `{ version, sql, memory? }`. `meta.schema_version` holds the current version. |

Store methods (the same on both backends; values are round-tripped through JSON):

- `s:get(scope, key)`, `s:set(scope, key, v)`, `s:all(scope)`. `scope` is `"portal"` or an app id. Setting `nil` deletes.
- `s:layout_get(page)` returns `nil` when never saved. `s:layout_set(page, list)`. `page` is `home` or `sleep`.
- `s:data_get(app, k)`, `s:data_set(app, k, v)`, `s:data_clear(app)`.
- `s:purge_app(app)` (R-M3, remove): the app's settings scope, data, cache, state, notifications and its `app_version:` / `legacy_imported:` meta marks, in both backends (the SQLite read memo too). Layouts are the caller's.
- `s:cache_get(app)` returns `value, fetched_at, version`. `s:cache_put(app, v, at, version)`, `s:cache_clear(app)`.
- `s:state_get(app)`, `s:state_set(app, st)`. Only `last_ok`, `last_err`, `err_text` and `fail_streak` are persisted.
- `s:notif_add(n)` returns the id, or `nil, "dup"`. Also `notif_find(app, key)`, `notif_get(id)`, `notif_list{offset, limit, unread}`, `notif_count()`, `notif_unread_count()`, `notif_mark_read(id, at)`, `notif_mark_all_read(at)`, `notif_clear()` and `notif_trim(max)`.
- `s:log(at, app, level, msg)` keeps the last 500. `s:log_list{offset, limit}` (newest first), `s:log_count()`.
- `s:meta_get(k)`, `s:meta_set(k, v)`, `s:schema_version()`.
- `s:transaction(fn, ...)` returns `true, results…` or `false, err`. Nesting is allowed. R-B2: wrap one refresh cycle in a single transaction.
- `s:stats()` returns `{ notifications, log, size_bytes }`. `s:close()`.

## settings.lua: settings (5.5, 9, 10.5)

| Function | What it does |
|---|---|
| `Settings.TINTA_DEFAULTS`, `Settings.CHOICES` | Tinta settings: `lang`, `landscape`, `nav` (`bar` or `gestures`), `full_every`, `wifi`, `quiet`, `banner`, `sleep_shows`, `wake` (`900`/`1800`/`3600`/`7200` s, `"schedule"` or `"never"`; default `"schedule"`), `idle_mode` (`always`/`battery`/`never`; default `battery`), `idle_sleep` (2/5/10/15 min). `Settings.new` moves the old `wake_every` + `sleep_schedule` keys to `wake` once (`Settings.migrate_wake`) and the old `idle_sleep` (0 = never) to `idle_mode` once (`Settings.migrate_idle`), deleting the removed `expediente`. |
| `Settings.new{ store, tinta_defaults? }` | Creates the settings object. |
| `S:is_disabled(id)`, `S:disabled_ids()`, `S:set_disabled(id, off)` | R-M2. Tinta setting `disabled_apps` (sorted list of ids), memoized: no store read per call. `set_disabled` refuses `Registry.PROTECTED` apps (`nil, "protected"`) and bad ids (`nil, "id"`). |
| `S:is_removed(id)`, `S:removed_ids()`, `S:add_removed(id)`, `S:clear_removed()` | R-M4. Tinta setting `removed_apps`: ids whose folder `loadApps` skips, so copying the whole plugin folder again does not bring a removed app back. |
| `S:register_app(manifest)` | Reads defaults from `manifest.defaults` and from each field's `default` in `manifest.settings`. The notification preference defaults to `alta`. |
| `S:get(scope, key)` | Falls back to the default. |
| `S:set(scope, key, v)` | Raw write; `nil` resets to the default. |
| `S:set_field(scope, key, v)` | Write with validation (R-C1/R-C3). Returns `true, value` or `nil, reason`. An empty token keeps the current one (R-C2). |
| `Settings.validate(field, value)` | Field types: `url`, `token`, `number` (min, max), `time`, `choice`, `bool`, plus the field's own `validate(v)`. |
| `S:token_status(scope, key)`, `S:display(scope, key, T?)` | Tokens are never shown: they display as "definido" or "não definido". |
| `S:scope(id)` | Returns `ctx.settings`, with `:get(k)`, `:set(k, v)` (validated) and `.fields()`. |
| `S:interval(app)`, `S:set_interval(app, v)`, `S:cycle_interval(app)`, `S:window(app)` | Interval and window settings (R-C4). |
| `S:notify_pref(app)`, `S:set_notify_pref(app, v)` | Notification preference (R-T2). |
| `S:tinta(key)`, `S:set_tinta(key, v)`, `S:cycle_tinta(key)` | Read, write and cycle Tinta settings. Added with the first-use work: `sleep_titles` (`show` default \| `hide`, R-V3) and `text_size` (`normal` default \| `large`; `Settings.text_factor(v)` gives 1.0 / 1.15, R-X1). |
| `S:sleep_visible(id)`, `S:set_sleep_visible(id, visible)` | R-V1: the per-app scope key `sleep_show` (`shown` \| `hidden`). `register_app` defaults it to `hidden` when `manifest.sensitive == true`, else `shown`. |
| `FirstRun.needed(store, ids)`, `FirstRun.mark_pending(store)`, `FirstRun.mark_done(store, at)` | `core/firstrun.lua`, R-F1: is this a fresh install (no layout, no `first_run_done`, no `app_version:` / `legacy_imported:` mark of the app folders `ids`, no saved Tinta setting but the seeded `idle_mode`)? Call before the apps register. `first_run_pending` keeps it true until `first_run_done` or a saved layout. Pure. |

## power.lua: sleep rules (11)

| Function | What it does |
|---|---|
| `Power.SCHEDULE`, `WAKE`, `IDLE`, `RTC_REPEAT` (2 s), `WAKE_TOLERANCE` (120 s), `WIFI_TIMEOUT` (30 s) | Constants. |
| `Power.band(now, bands?, date?)` | The band in force at `now`. |
| `Power.wake_interval(now, { wake?, bands?, date? })` | Minutes until the next wake, or `nil` (night band, or `wake = "never"`). `wake` is the Tinta setting: a number of seconds, `"schedule"` (default) or `"never"`. Bands: working days 30, the rest of the day 60, 18:30–23:00 60, 23:00–07:30 none. |
| `Power.next_wakeup(now, opts)` | Timestamp of the next wake, or `nil`. A number of seconds = `now + n` at any hour; `"never"` = `nil`; `"schedule"`: a wake that would land in the night band moves to the first minute that wakes again. |
| `Power.rtc_seconds(target, now)` | R-P10. Re-request with this value every 2 s while powerd is in `readyToSuspend`. |
| `Power.idle_due(last_touch, now, idle_min, mode, plugged)` | R-P4: `mode` `always`/`battery`/`never`; `plugged` is a boolean or a function called only in mode `battery` once the idle time is due. |
| `Power.classify_wakeup{ powerd_state, target, now, reason?, tolerance? }` | R-P11/R-P12. Returns `"button" \| "scheduled" \| "unscheduled"`. |
| `Power.sleep_bar(updated_at, next_at, date?)` | R-S4 status bar text. |

## i18n.lua: texts (13)

| Function | What it does |
|---|---|
| `I18n.DEFAULT_LANG` (`"pt"`), `I18n.STRINGS`, `I18n.LANGS` | The language default and string tables. |
| `I18n.set_lang(l)`, `I18n.get_lang()`, `I18n.normalize_lang(l)` | Set and read the language. |
| `I18n.t(key, ...)` | Translate. Falls back to pt, then to the key. Never throws. |
| `I18n.new{ pt = {}, en = {} }` | App translator (`.t`, `.lang()`) that follows the Tinta language. Missing keys fall back to the core. |
| `I18n.extend{ pt = {}, en = {} }` | ui/ adds its own keys. Existing keys are never replaced. |
| `I18n.check_tables(strings)` | The section 13 check (same keys, same specifiers, no empty strings) for app tests. |

## format.lua: text helpers

| Function | What it does |
|---|---|
| `hm(ts, date?)`, `minute_of_day(ts, date?)`, `parse_hm("07:30")`, `hm_from_minutes(m)`, `utc_date` | Clock time helpers. |
| `ago(ts, now)` | "agora", "há 3 min", "há 2 h", "há 3 d". |
| `every(sec)` | "a cada 1 min" or "manual". |
| `eta(hours)` | "~25min", "~4h20", "~12h". |
| `battery(pct, charging, eta)` | R-S1. "⚡ 82% · ~40min". |
| `utf8_len(s)`, `utf8_head(s, n)`, `truncate(s, max)` | R-W1. `truncate` ends a cut string with "…". |
| `window_text(window)` | "dias úteis 07:30–18:30". |
| `footer(status, narrow, now)` | R-W4. Returns a list of 1–2 strings. `status` comes from `Scheduler.status`. |
| `header(status, now)` | 6.4, R-S5, R-E4. App header text. |

## json.lua

`JSON.encode(v)` throws on functions, cycles, NaN and infinity. `JSON.decode(s)` returns `v` or `nil, err` and never throws.
The core needs its own JSON because it cannot use KOReader's rapidjson (R-A1).
