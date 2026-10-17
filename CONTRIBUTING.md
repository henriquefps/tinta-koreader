# Contributing / Contribuindo

Thank you for helping. Tinta is a KOReader plugin written in Lua; the repository guide for humans and AI agents is
[`AGENTS.md`](AGENTS.md) (layout, hard rules, PR checklist) — read it first.

## English

**Tests.** You need `luajit`. Run `scripts/test-all.sh` before every pull request; it must be green. New logic needs tests, a
new app needs a complete suite (`scripts/nova-app.sh <id> "<Name>"` starts from one), and a bug fix needs the test that would
have caught it. `KOREADER_REF=<koreader sources> scripts/test-all.sh` also runs the SQLite store tests (optional).

**Testing on a device.** The headless smokes do not replace the device (fonts are fake, e-ink refresh is not real). If you
change drawing, sleep/wake, Wi-Fi or a device backend, try it on a real device: `scripts/deploy.sh` (USB) or
`scripts/deploy.sh --ssh <ip>`, restart KOReader, walk through the screens in portrait and landscape, put it to sleep and wake
it by the power button and by the schedule, and look at `koreader/crash.log`. Say in the PR which device and KOReader version
you used. Only the Kindle Basic 2 (KT3) is verified; mark anything else as untested.

**Reporting bugs.** Open an issue with the template and attach the diagnostic exported by **System → Data → Export
diagnostic** (it removes tokens, passwords and credentialed URLs — open it and check anyway), plus the device model, the
KOReader version and the Tinta version. `scripts/pull-logs.sh` fetches `crash.log`, the power log and the database over SSH or
USB (the database holds app settings and tokens: do not attach it).

**Code style.** Match the file you are editing: comment density, naming, idiom. Code and comments in English; UI text in
`strings.lua` in Portuguese and English with the same keys. No raw pixel numbers (use `T.px`/`T.FONT_*`), black and white only,
no animations, no store reads in loops — the full list is in `AGENTS.md`. New files start with
`-- SPDX-License-Identifier: AGPL-3.0-or-later`. By contributing you agree your work is licensed under the AGPL-3.0.

**Pull requests.** Small and focused; describe what changed and why, how you tested it (commands and counts, device if any),
and, if the drawing changed on purpose, which steps of the KT3 baseline moved.

## Português

**Testes.** Precisa de `luajit`. Rode `scripts/test-all.sh` antes de cada pull request; tem de estar verde. Lógica nova tem
testes, app nova tem suíte completa (`scripts/nova-app.sh <id> "<Nome>"` já cria uma) e correção de bug traz o teste que
a pegaria. `KOREADER_REF=<fontes do KOReader> scripts/test-all.sh` roda também os testes do SQLite (opcional).

**Teste no aparelho.** Os smokes headless não substituem o aparelho (fontes falsas, refresh e-ink de mentira). Se mexer em
desenho, repouso/despertar, Wi-Fi ou num backend, teste num aparelho de verdade: `scripts/deploy.sh` (USB) ou
`scripts/deploy.sh --ssh <ip>`, reinicie o KOReader, percorra as telas em retrato e paisagem, durma e acorde pelo botão e
pela agenda, e olhe o `koreader/crash.log`. Diga no PR qual aparelho e qual KOReader. Só o Kindle Basic 2 (KT3) está
verificado; marque o resto como não testado.

**Reportar bugs.** Abra uma issue com o modelo e anexe o diagnóstico exportado em **Sistema → Dados** (ele remove tokens,
senhas e URLs com credenciais — confira mesmo assim), o modelo do aparelho e as versões do KOReader e da Tinta.
`scripts/pull-logs.sh` traz `crash.log`, o log de energia e o banco (o banco tem as configurações e tokens: não anexe).

**Estilo.** Siga o arquivo que está editando. Código e comentários em inglês; textos da interface em `strings.lua`, em
português e inglês com as mesmas chaves. Sem número de pixel solto (`T.px`/`T.FONT_*`), só preto e branco, sem animações, sem
leitura do banco em laços — a lista completa está no `AGENTS.md`. Arquivos novos começam com
`-- SPDX-License-Identifier: AGPL-3.0-or-later`. Ao contribuir, você concorda que seu trabalho use a AGPL-3.0.
