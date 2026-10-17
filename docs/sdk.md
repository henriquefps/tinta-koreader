# SDK da Tinta: como escrever uma app

> **English summary.** A Tinta app is a folder `tinta.koplugin/apps/<id>/` with an `init.lua` that returns a
> manifest table (id, name, sizes, settings, notifications, …) plus Lua functions: `refresh(ctx, done)`,
> `widget(ctx, size, box)`, `screens.<name>(ctx, args, box)` and a few optional hooks. The Tinta hands every
> function a `ctx` (cache, data, settings, notify, net, open, confirm, choose, toast, input, redraw, back, wake_at, i18n,
> `ui` kit). Every call into an app is protected (`pcall`): an app that throws gets an error widget or screen, never
> a crash. Draw only through `ctx.ui` and the scaled theme (`T.px(n)`, `T.FONT_*`): no raw pixel numbers, black and
> white, no animations, text that fits its box. Keep logic in a pure `logic.lua` (no `require`), put texts in
> `strings.lua` (pt + en), and never read the store in loops (it lives on a slow filesystem on the Kindle). Test with
> `tests/apprunner.lua` + `tests/uistub.lua`. **Start with `scripts/nova-app.sh <id> "<Name>"`**, which copies the
> reference app `apps/_modelo` (a local app); `apps/_exemplo_json` is the example for an app that talks to **your home server**
> and `apps/_exemplo_clima` the one for an app that uses a **web service** (the public Open-Meteo API); both are tested with a fake `ctx.net`. Apps run inside the KOReader process with full access: permissions in the manifest
> inform, they do not enforce. API version today: `api = 1`, Tinta `0.1`.

Este guia vale para a **API de apps 1** (`core/version.lua`: `API_VERSION = 1`, `TINTA_VERSION = "0.1"`). A
especificação completa está em [`arquitetura.md`](arquitetura.md) (seções 5 e 6); a lista de tudo o que a interface
chama no núcleo, em [`../tinta.koplugin/ui/CORE_CALLS.md`](../tinta.koplugin/ui/CORE_CALLS.md); a API do núcleo, em
[`../tinta.koplugin/core/README.md`](../tinta.koplugin/core/README.md).

## 1. Começar em um minuto

```sh
scripts/nova-app.sh clima "Clima"        # cria tinta.koplugin/apps/clima a partir de apps/_modelo
luajit tinta.koplugin/apps/clima/tests/run.lua
SMOKE_APP=clima luajit tests/tinta_ui_smoke.lua       # carrega a app no smoke headless e abre widget e tela
```

O script valida o id (`[a-z0-9_]+`, sem `_` no começo, ainda não usado), copia a app de referência, troca o id e o nome,
(o `scripts/test-all.sh` acha a suíte `apps/*/tests/run.lua` sozinho). Depois é editar `init.lua`, `logic.lua`, `view.lua` e `strings.lua`.
Para ver a app no aparelho: `scripts/deploy.sh` e reiniciar o KOReader.

## 2. Estrutura de pastas

```
tinta.koplugin/apps/<id>/
  init.lua        manifesto + ligação com o ctx (devolve a tabela do manifesto)
  logic.lua       regras puras: sem require, sem KOReader, sem ctx, sem relógio (o chamador passa `now`)
  view.lua        desenho: monta widgets e telas só com ctx.ui
  strings.lua     textos { pt = {…}, en = {…} } (sem require)
  tests/          run.lua + test_*.lua (usa tests/apprunner.lua)
```

Regras:

- O nome da pasta é o `id` do manifesto, `[a-z0-9_]+`. A Tinta carrega `apps/<id>/init.lua` de toda pasta que casa.
- **Pastas que começam com `_` só carregam com a configuração `dev_apps` ligada** (desenvolvimento; o smoke liga). É por isso
  que `apps/_modelo`, `_test_ok` e `_test_fail` não aparecem para o usuário. O id de uma app de verdade não começa com `_`.
- **R-A1:** `logic.lua` e `strings.lua` (e tudo em `core/`) ficam puros: nenhum `require` de módulo do KOReader nem
  do plugin. O teste da app confere isso. Só `init.lua` e `view.lua` tocam `ctx`.
- **Dois lugares para apps** (mesmas regras nos dois: manifesto, `api`/`min_tinta`, ligar/desligar, remover, ids `[a-z0-9_]+`):
  1. `tinta.koplugin/apps/<id>/`: as que vêm com o plugin. Um deploy do plugin troca a pasta inteira.
  2. `<pasta de dados do KOReader>/tinta-apps/<id>/init.lua` (no Kindle, `koreader/tinta-apps/<id>/`): apps externas, do
     usuário, que **sobrevivem à atualização do plugin**. Instale com `scripts/deploy.sh --app caminho/apps/minha_app --ssh <ip>`
     (ou por USB). Remover uma app externa apaga só dentro de `tinta-apps/`.
  - A pasta `apps/` do plugin carrega primeiro. Uma app externa com o **mesmo id** de uma que vem no plugin é recusada, com uma
    linha no log (`apps: external app refused, a bundled app has the same id`); a do plugin continua valendo.
  - O código da app é o mesmo nos dois lugares: `require("apps/<id>/logic")` também resolve para as externas (a Tinta
    registra um carregador para `apps/<id>/...` apontando para `tinta-apps/<id>/...`, só para os ids que ela carregou).
  - Uma app externa copiada para `tinta.koplugin/apps/` (ou o contrário) funciona sem mudar uma linha.
- Módulos da app se carregam por `require("apps/<id>/logic")`. **Não dê a um módulo o nome de um módulo do KOReader**
  (o do KOReader ganha): `ui/geometry`, `ui/font`, `ui/size`, `ui/event` e `device/input` estão tomados. Prefixar com
  `apps/<id>/` resolve.
- Uma app pode ter mais arquivos (por exemplo `api.lua` para a conversa com o servidor, `rules.lua` para regras de notificação, `icons/`); o que muda é só o que `init.lua` devolve.

## 3. O manifesto (`init.lua`)

`init.lua` devolve uma tabela. O núcleo valida (`Registry.validate`) e **rejeita** o manifesto inválido com um log, sem
derrubar a Tinta.

| Campo | Obrigatório | O que é |
|---|---|---|
| `id` | sim | `[a-z0-9_]+`, único, igual ao nome da pasta |
| `name` | sim | nome mostrado (texto de reserva). Para dois idiomas use também `names` |
| `names` | não | `{ pt = "…", en = "…" }`, nome por idioma |
| `short` | não | rótulo curto para o mapa do organizador |
| `description` | não | uma linha (subtítulo no launcher, R-O10) |
| `version` | recomendado | versão do **esquema dos dados** da app. Quando sobe, o núcleo chama `migrate(ctx, from, to)` se existir; senão apaga o cache da app (R-D2) |
| `api` | recomendado | versão da API de apps para a qual a app foi escrita (inteiro ≥ 1; sem o campo vale 1). Maior que a da Tinta: a app **não carrega** e aparece em Sistema → Apps como "precisa de uma versão mais nova da Tinta" (R-M1) |
| `min_tinta` | não | `"x.y"`, versão mínima da Tinta (comparação numérica por parte: `"0.10"` > `"0.9"`). `min_portal` (o nome de antes da Tinta) continua valendo |
| `sizes` | sim | tamanhos de widget que a app desenha, de `1x1`, `2x2`, `2x4`, `4x2`, `4x4`. **O primeiro é o padrão** |
| `default_layout` | não | onde a app entra nos layouts padrão: `{ home = { size = "4x2", order = 10 }, sleep = { ... } }`. `order` menor vem antes (as apps incluídas contam 100, 200, ...); só vale quando o usuário ainda não salvou o layout |
| `widget` | sim | `function(ctx, size, box)`, devolve o widget (seção 6) |
| `net` | não | `true` quando atualizar precisa de Wi-Fi: a Tinta só liga o Wi-Fi quando alguma app de rede está no prazo (R-P1) |
| `source` | não | `{ id, name, url_key? }`: o servidor da app, para a tela Conexões (avisos "caiu"/"voltou"). `url_key` é a configuração com a URL (padrão `"url"`) |
| `defaults` | não | `{ interval = 60, window = nil }`: intervalo de atualização em segundos (`0` = manual) e janela `{ from = "07:30", to = "18:30", weekdays = true }`. O usuário muda em Sistema → Atualizações (R-C4) |
| `in_window` | não | `function(ctx, now) -> bool`: decide a janela de atualização no lugar de `window` (para regras como dias úteis) |
| `settings` | não | lista de campos editáveis (seção 4) |
| `notifications` | não | lista `{ type, label }` dos tipos que a app emite; o usuário escolhe alta / normal / desligada por tipo (Sistema → Notificações) |
| `strings` | não | `{ pt = {…}, en = {…} }`: dá o `ctx.i18n` (seção 9) |
| `system` | não | `true` marca app informativa de sistema (não pode ser removida) |
| `sensitive` | não | `true`: o widget da app começa **oculto na página de repouso** (visível com o aparelho dormindo): a página mostra só uma moldura com o nome (R-V1). O usuário muda em Sistema → Apps → (app) → "Mostrar na página de repouso". Use em apps com dados pessoais (a Nota usa) |

Funções do ciclo de vida, todas opcionais exceto `widget`:

| Função | Quando é chamada |
|---|---|
| `init(ctx)` | uma vez, ao abrir a Tinta (e ao reativar a app). Leia aqui do banco o que precisar manter em memória |
| `refresh(ctx, done)` | atualização de dados (seção 7). Sem `refresh`, a app não tem atualização (Notificações, Sistema) |
| `widget(ctx, size, box)` | ao desenhar o Início e a página de repouso |
| `screens = { main = fn, … }` | telas cheias; `main` abre ao tocar no widget (seção 8) |
| `on_route(ctx, route)` | abrir uma rota vinda de uma notificação, no lugar do padrão (tela `route[1]`) |
| `attention(ctx) -> bool` | `true` quando a app precisa do usuário: o widget aparece invertido (branco sobre preto) |
| `footer(ctx, narrow) -> left, right` | rodapé próprio (apps de sistema); o padrão é "idade · intervalo" |
| `background(ctx, now, kind)` | **gancho barato**, chamado a cada minuto com a Tinta aberto e ao redor do repouso (`kind`: `nil`, `"sleep"`, `"sched"`, `"button"`, `"plain"`). Não pode consultar o banco, as configurações, `ctx.cache` nem `ctx.data` a cada chamada. A Bateria usa para o log |
| `migrate(ctx, from, to)` | quando `version` sobe (R-D2) |
| `import_legacy(ctx)` | importa uma vez os dados de um plugin antigo (R-B5); só para quem migra de outro plugin |

> `net`, `window` e `interval` descrevem o que a app **faz**; a Tinta decide **quando**. A app nunca liga ou
> desliga o Wi-Fi (R-P1) nem agenda nada por conta própria.

## 4. Configurações (`settings`)

Cada campo gera uma linha em **Sistema → Apps → (app)**, com validação (R-C1, R-C3):

```lua
settings = {
    { key = "url",   label = "Servidor",  type = "url",    default = "http://192.0.2.10:9999" },
    { key = "token", label = "Token",     type = "token" },
    { key = "limit", label = "Limite",    type = "number", default = 5, min = 1, max = 100 },
    { key = "at",    label = "Horário",   type = "time",   default = "07:30" },
    { key = "mode",  label = "Modo",      type = "choice", default = "a",
      choices = { { value = "a", label = "modo A" }, { value = "b", label = "modo B" } } },
    { key = "flag",  label = "Opção",     type = "bool",   default = false },
}
```

| Tipo | Valor | Notas |
|---|---|---|
| `url` | texto | `http://` ou `https://` + host; a barra final é removida |
| `token` | texto | **nunca é mostrado** (a tela diz "definido" / "não definido"); a caixa abre vazia e vazio mantém o atual (R-C2). Fica fora de exportações, diagnóstico e logs |
| `number` | número | respeita `min` e `max` |
| `time` | `"HH:MM"` | |
| `choice` | um `value` de `choices` | |
| `bool` | `true`/`false` | |

Extras: `hint` (texto de ajuda) e `validate = function(v) -> true | valor_normalizado | nil, motivo` (validação própria, depois da do
tipo). Na app: `ctx.settings:get(k)` (cai no padrão) e `ctx.settings:set(k, v)` (validado). O valor pode chegar como texto ou float:
normalize na `logic.lua` (`Logic.limit(v)` no modelo) e **não leia a configuração dentro de laços**.

## 5. O `ctx`

O núcleo e a interface entregam um `ctx` a cada app, o mesmo em todas as funções dela.

| Campo | O que faz |
|---|---|
| `ctx.now()` | relógio (segundos Unix). Use este, não `os.time()`, na lógica: os testes passam um falso |
| `ctx.cache:get()` → `valor, buscado_em, versão` · `ctx.cache:put(tbl)` | último dado bom, persistido para aparecer sem rede. Apagado quando `version` sobe sem `migrate` |
| `ctx.data:get(k)` · `ctx.data:set(k, v)` | dados persistentes da app (valores Lua serializáveis em JSON) |
| `ctx.settings:get(k)` · `:set(k, v)` | configurações (seção 4) |
| `ctx.notify(n)` | emite notificação (seção 10). Devolve o id, ou `nil, "dup" \| "off" \| "invalid" \| "first_read"` |
| `ctx.net.get_json(url, opts)` · `ctx.net.post_json(url, body, opts)` · `ctx.net.connected()` | HTTP síncrono com timeout (8 s), limite de bytes (256 KiB) e JSON. `opts = { token, timeout, max_bytes, headers }`. Devolve a `tabela` ou `nil, tipo, detalhe` (`unreachable`, `unauthorized`, `forbidden`, `not_found`, `http`, `too_large`, `bad_json`, `server_failed`). `server_failed` é um 502 cujo corpo JSON traz `error` (texto) e, opcionalmente, `detail`: o detalhe vem como uma linha, com no máximo 120 caracteres. O token é tirado de todo detalhe. Pode ser `nil` (testes, falha ao carregar): confira |
| `ctx.open(tela, args)` | abre outra tela **da própria app** |
| `ctx.confirm(título, texto, rótulo_ok, fn)` | diálogo de confirmação padrão; `fn` roda só no OK |
| `ctx.choose(título, opções, atual, on_pick)` | popup de escolha (abaixo): uma linha por opção, a atual marcada; tocar numa opção chama `on_pick(valor)` e fecha |
| `ctx.toast(texto)` | aviso curto |
| `ctx.input(título, valor, dica, on_save, opts)` | teclado do KOReader. `on_save(texto)` devolve `true`, ou `false, mensagem` para manter aberto. `opts = { number, multiline, password }`. **Não abra um segundo `input` dentro de `on_save`** (a Tinta fecha o diálogo depois que `on_save` volta) |
| `ctx.redraw()` | redesenha a tela atual (depois de mudar dados) |
| `ctx.back()` | volta uma tela |
| `ctx.wake_at(ts)` | pede a Tinta acordado no instante `ts` (Unix), também do repouso (traz o despertar do RTC para essa hora); `nil` cancela. Um pedido por app, só em memória: peça de novo em `init`. Serve para alarmes (Timer, Contagem) |
| `ctx.i18n.t(chave, ...)` · `ctx.i18n.lang()` | tradução da app (seção 9) |
| `ctx.log(msg)` | log da app (vai ao log da Tinta com o id; nunca registre token ou resposta crua) |
| `ctx.state` | `{ last_ok, last_err, err_text, busy, fail_streak, exc_streak, disabled }`, mantido pelo núcleo (somente leitura) |
| `ctx.ui` | os componentes de interface (seção 6) |

Cada app só vê o próprio escopo no banco (configurações, dados, cache): não há acesso ao de outra app.

## 6. Widgets, tamanhos e o tema escalado

### Tamanhos

A grade tem 6 × 8 células em retrato (8 × 6 em paisagem). Tamanhos válidos: `1x1`, `2x2`, `2x4`, `4x2`, `4x4`
(colunas × linhas). `widget(ctx, size, box)` recebe `box = { w, h, cols, rows, size, inv, big }`:

- `w`, `h`: pixels **desta tela**, já calculados. **O widget não pode passar dessas medidas** (R-W1); texto que não cabe é cortado
  com "…".
- `inv`: `true` quando a app pede atenção; desenhe branco sobre preto (`ctx.ui.fg(box.inv)` / `ctx.ui.bg(box.inv)`).
- `cols`, `rows`: o tamanho em células; `big`: widget grande (4×4).
- A Tinta desenha a **moldura** (borda, inversão, borda tracejada quando o último refresh falhou, rodapé padrão R-W4); a app
  desenha só o **miolo**.
- Conteúdo mínimo (R-W3): 1×1 = ícone ou número curto; 2×2 = nome, linha principal, linha secundária; maiores, o que a app quiser.

O jeito mais simples é `ctx.ui.basic(box, spec)`, que empilha o que cabe:

```lua
ctx.ui.basic(box, {
    title = "Clima", primary = "23 °C", secondary = "sol",
    lines = { { "mínima", "18" }, { "máxima", "27" } },   -- { esquerda, direita }
    -- 1x1: number = "23", short = "Clima", icon = widget
})
```

### O tema escalado

Toda medida da Tinta é projetada para uma tela de 600 × 800 e **multiplicada por uma escala `T.s`** em outras telas (a área de
conteúdo 3:4 é centralizada; sobra borda branca). No KT3 a escala é 1 e nada muda. Por isso:

- **Nunca escreva um número de pixel.** Use o tema, `local T = ctx.ui.theme`:
  - medidas prontas: `T.GAP`, `T.MARGIN`, `T.BORDER`, `T.BTN_H`, `T.ROW_H`, `T.HEADER_H`, `T.PAGER_H`…;
  - fontes: `T.FONT_MIN` (20), `T.FONT_BODY` (22), `T.FONT_TITLE`, `T.FONT_PRIMARY`, `T.FONT_STAT`, `T.FONT_HUGE`…;
  - `T.px(n)`: px de projeto → px da tela; `T.px1(n)`: o mesmo, no mínimo 1 px (traços); `T.fpx(n)`: tamanho de fonte;
  - `T.s`: a escala, para quem desenha formas (gráfico, mostrador).
- **Leia `T.X` na hora de usar, nunca guarde em variável no topo do arquivo:** os valores mudam quando a tela gira.
- Só preto e branco (o único cinza é a trilha fina dos anéis), **sem animações** (R-A3). Alvos de toque ≥ 64 px de projeto.

### Componentes de `ctx.ui`

| Função | Para quê |
|---|---|
| `ui.basic(box, spec)` | miolo padrão de widget |
| `ui.text(str, size, bold, max_w, fg?)` | uma linha, cortada com "…" em `max_w` |
| `ui.textbox(str, size, w, h?, bold?, fg?, align?)` | texto em várias linhas |
| `ui.vstack(children, gap, align)` · `ui.hstack(children, gap, align)` | empilha na vertical ou horizontal |
| `ui.box{ w, h, align, valign, child, border?, pad_x?, pad_y?, on_tap? }` | caixa de tamanho fixo (o jeito seguro de posicionar) |
| `ui.space(w, h)` · `ui.fill(w, h, inv)` | espaço vazio · retângulo cheio |
| `ui.button{ label, w, h?, on_tap, inv?, disabled?, sub? }` · `ui.button_row({ {rótulo, fn, inv=…}, … }, w)` | botões (≥ 64 px de projeto) |
| `ui.row{ w, h, title, sub, right, inv, dim, on_tap, on_hold }` | linha de lista |
| `ui.rows(box, rows, opts)` | lista paginada de linhas (duas colunas em paisagem; aceita `{ section = "…" }` e `{ note = {…} }`) |
| `ui.paged(box, itens, build, opts)` | lista paginada de qualquer coisa (**nada rola**: páginas com pager) |
| `ui.pager`, `ui.header` | rodapé de páginas e cabeçalho de tela |
| `ui.choose(título, opções, atual, on_pick)` | o mesmo que `ctx.choose` (popup de escolha) |
| `ui.icons.wifi / bell / gear / battery` | ícones desenhados |
| `ui.draw`, `ui.fg(inv)`, `ui.bg(inv)` | primitivas e cores |
| `ui.content_box()` | a caixa da área de conteúdo da tela |
| `ui.theme` | o tema (`T`) |

### Popup de escolha (`ctx.choose`)

Toda linha de configuração com **várias opções** (um intervalo, um modo, um idioma) abre um popup em vez de ciclar a cada
toque: com 4 ou 6 opções, ciclar é lento e é fácil passar do ponto. O popup é desenhado pela própria Tinta (como o
diálogo de confirmação, não é um widget do KOReader) e funciona em retrato, paisagem e em todos os tamanhos de tela.

```lua
on_tap = function()
    ctx.choose(L("mode"), {
        { value = "a", label = L("mode_a"), sub = L("mode_a_sub") },   -- sub é opcional
        { value = "b", label = L("mode_b") },
    }, ctx.settings:get("mode"), function(v)
        ctx.settings:set("mode", v)
        ctx.redraw()
    end)
end
```

- `opções`: valores soltos (o rótulo é o próprio valor) ou tabelas `{ value, label?, sub? }`. Lista vazia: nada abre.
- `atual`: o valor que fica **marcado** (linha invertida com "●"); o popup abre na página dessa opção.
- **Tocar numa opção** chama `on_pick(valor)` (protegido, como todo callback) e fecha. **Tocar fora**, "Voltar" da barra
  de navegação, o gesto de voltar e a tecla Voltar **cancelam** sem chamar nada. O popup só guarda a escolha quando você
  salva em `on_pick`; depois dela a tela é redesenhada (chame `ctx.redraw()` só se `on_pick` mudar algo além do que o
  popup já redesenha).
- Quando as opções não cabem na tela, o popup vira **páginas** com o pager (‹ N/M ›); nada rola.
- Use `ctx.choose` só para escolher entre opções. **Botões de widget** (como os botões do widget 4×2 do Repouso)
  continuam ciclando num toque: não dá para abrir um popup dentro de um widget pequeno. Duas opções que são um
  liga/desliga continuam sendo `bool` (um toque alterna).
- Campos `choice` do manifesto (seção 4) e a linha "Intervalo" da tela da app em Sistema → Apps já usam o popup sozinhos:
  você não escreve nada.
- Nos testes, `T.ctx()` guarda a chamada em `ctx.chosen = { title, options, current, pick }`; chame `ctx.chosen.pick(valor)`
  para simular a escolha.

**Cuidados de desenho que já custaram caro:**

1. **R-L1:** nunca chame `getSize()` numa `VerticalGroup`/`HorizontalGroup` que ainda vai receber filhos (o KOReader
   guarda o tamanho antigo). Meça os filhos antes de empilhar, ou use `ui.box` com tamanho explícito.
2. **Nunca dê a um widget mostrado com `UIManager:show` um campo ou método chamado `toast`, `modal` ou `invisible`:** o
   `UIManager` trata `.toast` verdadeiro como aviso e esconde o diálogo de entrada (já derrubou o KOReader). O smoke confere.
3. O texto tem de caber na caixa: o smoke e o `uistub` acusam pintura fora da caixa.

## 7. `refresh(ctx, done)`: o contrato e o isolamento de erros

```lua
refresh = function(ctx, done)
    local data, kind = ctx.net.get_json(url, { token = ctx.settings:get("token") })
    if not data then return done(false, kind) end      -- falha de REDE: done(false, motivo)
    ctx.cache:put({ temp = data.temp, at = ctx.now() })
    done(true)
end
```

- Chame `done(ok, err)` **uma vez** (só a primeira conta). Pode ser assíncrono; sem `done` por 120 s a Tinta destrava e conta falha.
- `done(true)`: marca `last_ok`. `done(false, err)`: **falha de rede/servidor** (R-U6): marca `last_err`, e o widget ganha borda
  tracejada com a idade do último dado bom (R-S5). Guarde com `ctx.cache:put` só dado bom.
- **Exceção** em `refresh` é erro da app, não de rede (R-E4): três seguidas desligam a atualização automática daquela app até
  um "Atualizar" manual; o cabeçalho diz "erro na app". Nada disso fecha a Tinta.
- **Uma atualização por vez por app** (R-U8): um pedido durante uma execução entra na fila.
- **Primeira leitura da sessão (8.6):** o que a app emite antes de seu primeiro `refresh` bem-sucedido terminar é só **registrado**
  (para não avisar tudo de uma vez ao abrir). Quem precisa avisar já no primeiro `refresh` chama `done(true)` **antes** de
  `ctx.notify`.
- **Isolamento (R-E1..R-E3):** toda chamada a uma função da app (`init`, `refresh`, `widget`, telas, `on_route`, `attention`,
  callbacks de botão e de `confirm`) é protegida. Widget que falha vira "Nome · erro na app" no mesmo tamanho; tela que falha vira
  tela de erro com Voltar; callback que falha vira toast "Erro na app X". O erro vai ao log com app, função e a primeira
  linha do traceback. Não use `pcall` por hábito: deixe o erro subir.
- Quem agenda é a Tinta (intervalo, janela, horário de silêncio, Wi-Fi), não a app. App de rede é pulada sem Wi-Fi.

## 8. Telas e rotas

```lua
screens = {
    main = function(ctx, args, box)           -- abre ao tocar no widget
        return { body = widget, title = "…" } -- ou só o widget
    end,
    detail = function(ctx, args, box) … end,  -- aberta por ctx.open("detail", { n = 1 })
}
```

- `box = { w, h, landscape }` é a área do corpo, abaixo do cabeçalho que a Tinta desenha (6.4). `ctx.ui.content_box()` dá o mesmo.
- Uma tela devolve um widget, ou `{ body, title?, meta?, emphasis?, no_header? }`.
- `ctx.open(nome, args)` empilha outra tela da app; `ctx.back()` volta. A tela é reconstruída a cada desenho: **leia o estado
  na hora** e chame `ctx.redraw()` depois de mudar dados.
- **Rotas de notificação:** `route = { "detail", { n = 7 } }` na notificação abre a pilha Início → `screens.detail` com
  `args = { n = 7 }`; sem `route`, abre `main`. `on_route(ctx, route)`, se existir, assume a abertura.
- Nada rola: listas usam `ui.paged`/`ui.rows` (páginas com pager).

## 9. Textos e i18n

`strings.lua` devolve `{ pt = {…}, en = {…} }` e o manifesto declara `strings = Strings`. Na app, `ctx.i18n.t("chave", ...)` segue o
idioma da Tinta, cai em `pt`, depois na própria chave, e nunca dá erro. Valem os formatos de `string.format` (`"%d min"`).

- As duas tabelas têm as **mesmas chaves e os mesmos especificadores**, sem texto vazio. Confira no teste:
  `I18n.check_tables(Strings)` devolve a lista de problemas (veja `apps/_modelo/tests/test_strings.lua`).
- Os rótulos de `settings` e `notifications` no manifesto ficam em `pt` (`Strings.pt.set_limit`); o nome por idioma vai em `names`.
- Não monte frases juntando pedaços: uma chave por frase, com `%s`/`%d`.

## 10. Notificações

```lua
ctx.notify{ key = "limit:" .. n, type = "limit", title = "…", body = "…", prio = "alta", route = { "main" } }
```

- `key` (obrigatório) deduplica por (app, key), lida ou não (R-T1): use algo estável por evento (`"down:" .. dia`), não a hora.
- `type` é um dos declarados em `manifest.notifications`; o usuário escolhe alta / normal / desligada por tipo (R-T2).
  A prioridade vira o banner da tela e o resumo da página de repouso.
- A Tinta guarda até 200: as lidas saem primeiro (R-T4). Notificação nunca leva dado secreto.

## 11. Desempenho: nada de banco em laço

O banco SQLite fica num sistema de arquivos FUSE lento no Kindle. Regras:

1. **Não consulte `store`, `ctx.settings`, `ctx.cache` nem `ctx.data` em laços nem em verificações por minuto.** Leia uma vez (em `init`
   ou no começo da função), guarde numa variável local do módulo e escreva de volta (como o Timer: lê o estado em `init`, grava ao mudar).
2. `widget` e `screens` rodam a cada desenho: **uma** leitura de cache por chamada, nunca uma por item da lista.
3. `background` é chamado a cada minuto: sem banco; o que precisar vem da memória.
4. Uma atualização usa uma transação do núcleo (R-B2); não abra outras.
5. Não guarde a resposta bruta dos servidores: decodifique só os campos de que precisa (R-A4).

## 12. Testes

Rode a suíte da app com `luajit tinta.koplugin/apps/<id>/tests/run.lua` na raiz do repositório (`QUIET=1` mostra só as falhas e o total).
`scripts/test-all.sh` roda todas.

```lua
-- tests/run.lua
local here = (arg and arg[0] or ""):match("^(.*)/[^/]*$") or "."
package.path = here .. "/../../../tests/?.lua;" .. package.path
require("apprunner").run("meuapp", here, { "logic", "app", "strings", "view" })
```

- **`tests/apprunner.lua`** carrega `tests/test_<nome>.lua` e passa `T`: `T.check(nome, cond)`, `T.eq(nome, obtido, esperado)`,
  `T.L(chave, …)` (textos pt, como `ctx.i18n.t`), `T.plugin`, `T.here` e `T.ctx{ now?, settings? }`, um `ctx` falso com
  `data`, `settings`, `notify` (guarda em `ctx.notes`), `wake_at` (`ctx.wakes`), `redraw`, `toast` (`ctx.toasts`), `confirm`
  (`ctx.confirmed`), `choose` (`ctx.chosen`), `input` (`ctx.inputs`), `open`, `back` e `log`. Faltam `cache` e `ui`: ponha o que a app usa (veja
  `apps/_modelo/tests/test_app.lua`).
- **`tests/uistub.lua`**: `local H = require("uistub").install()` instala widgets de mentira (texto de largura fixa) para o `ui/kit`
  **de verdade** montar, pintar e medir widgets e telas sem KOReader. `H.cell(size, "portrait"|"landscape", inv)` dá a `box` de um
  tamanho; `H.widget(T, nome, fn, box)` e `H.screen(T, nome, fn, caixa)` conferem que monta, pinta e **fica dentro da caixa**
  (R-W1); `H.has(texto)` procura o texto pintado. Chame `install()` **uma vez por processo** (o `ui/kit` guarda os primeiros widgets
  que carregou; veja `MODELO_H` nos testes do modelo).
- O que testar: `logic.lua` a fundo (puro); o manifesto (`Registry.validate`, `Registry.compat`, cada `default` com
  `Settings.validate`); `refresh` (chama `done` uma vez, grava o que deve, emite a notificação certa, declarada no manifesto);
  widgets em todos os tamanhos, retrato, paisagem e invertido; as duas línguas; R-A1.
- **Smoke headless:** `SMOKE_APP=<id> luajit tests/tinta_ui_smoke.lua` carrega a Tinta inteiro (`dev_apps` ligado) sobre o `core/`
  real, registra a app, desenha o widget em cada tamanho no Início, abre a tela principal e roda um `refresh`. O smoke principal
  (`luajit tests/tinta_ui_smoke.lua`) é fixado nas apps do repositório (hashes do KT3): uma app nova muda as páginas do launcher,
  por isso `scripts/nova-app.sh` põe o id da app nova em `tests/fixtures/smoke-skip-apps.txt` (o smoke principal não a carrega) e ela roda no modo `SMOKE_APP`.
- Tela de verdade e fontes de verdade só se vê no aparelho: o stub não mede letra de verdade.

## 13. Segurança

- **As apps rodam no mesmo processo do KOReader, com acesso total** (arquivos, rede, o aparelho). O campo `net` e as permissões do
  manifesto **informam, não impedem**. Instale e distribua apps apenas de quem você confia; leia o código de uma app de terceiros.
- Tokens e segredos: campo `type = "token"`; nunca em `ctx.log`, toast, notificação, tela ou arquivo. `ctx.net` tira o token dos
  detalhes de erro, mas **a app não deve** repeti-lo em mensagem nenhuma. Não registre URL com credencial.
- Guarde só os campos de que precisa; não guarde a resposta crua do servidor (R-A4).
- A página de repouso fica visível com o aparelho dormindo: marque `sensitive = true` na app que mostra dados pessoais (o widget
  começa oculto ali, seção 3) e não confie só nisso.
- Servidores de apps de exemplo sem autenticação devem ficar **só na rede local**.
- Remover uma app apaga a pasta dela e tudo que o banco guarda (R-M3); `apps/_modelo` e o resto de `_*` não carregam fora de `dev_apps`.

## 14. Checklist antes de publicar uma app

- [ ] `id` `[a-z0-9_]+`, sem `_` no começo; `api` e (se usa algo novo) `min_tinta` declarados.
- [ ] `sizes` com o tamanho padrão primeiro; o widget cabe em todos, em retrato, paisagem e invertido (testado com `uistub`).
- [ ] Nenhum número de pixel: só `T.*`, `T.px`, `T.fpx`; nada de cor além de preto e branco; sem animação.
- [ ] `logic.lua` e `strings.lua` sem `require`; `strings` pt e en com as mesmas chaves.
- [ ] `refresh` chama `done` uma vez; falha de rede é `done(false, motivo)`; nenhum segredo em log, toast ou notificação.
- [ ] Nenhuma leitura de banco/configuração/cache em laço; `background` (se houver) é barato.
- [ ] Notificações com `key` estável e `type` declarado; `route` abre uma tela que existe.
- [ ] `scripts/test-all.sh` verde, e `SMOKE_APP=<id> luajit tests/tinta_ui_smoke.lua` verde.

## 15. Segundo exemplo: uma app que fala com o seu servidor (`apps/_exemplo_json`)

A `_modelo` é local (um contador); a `_exemplo_clima` (seção 16) usa um serviço público da web. A **`_exemplo_json`** mostra o padrão mais comum das apps de verdade: **buscar um JSON num
servidor configurável**, guardar só o que se usa, mostrar num widget e numa tela e **avisar quando o valor passa de um limite**.
Como a `_modelo`, a pasta começa com `_` e só carrega com `dev_apps` ligado; para partir dela, copie a pasta e troque o id
dentro dos arquivos (o `nova-app.sh` copia a `_modelo`).

O servidor responde algo como (qualquer servidor serve):

```json
{ "value": 42, "label": "Fila", "unit": "itens" }
```

| Arquivo | O que mostra |
|---|---|
| `init.lua` | manifesto com `net = true`, `source` (para a tela Conexões), `settings` `url` / `token` / `threshold`, o tipo de notificação `over`; `refresh` com `ctx.net.get_json` |
| `logic.lua` | `Logic.parse` (guarda só `value`, `label`, `unit`; recusa o formato errado sem lançar erro), `Logic.crossed` (regra do aviso: **só ao cruzar o limite para cima**, não a cada leitura acima dele), `Logic.view` |
| `view.lua` | widget 2×2 e 4×2 com `ui.basic`; tela com o valor grande e o botão "Rearmar aviso" (`ctx.confirm`) |
| `tests/` | **`ctx.net` falso**: `ctx.net.get_json` devolve respostas combinadas (`tabela` ou `nil, tipo, detalhe`), sem rede nenhuma |

O que copiar para as suas apps:

- **`refresh` de rede:** confira `ctx.net` (pode ser `nil`); `local body, kind = ctx.net.get_json(url, { token = … })`;
  falha de rede vira `done(false, kind)`; resposta no formato errado também (`Logic.parse` devolve `nil, "bad_shape"`); só então
  `ctx.cache:put` e `done(true)`. Nada de segredo na notificação ou no log.
- **Aviso sem repetição:** guarde em `ctx.data` se o último valor já estava acima (`over`) e emita com `key = "over:" .. n`
  só na transição de abaixo para acima. O botão da tela limpa a marca.
- **Testar sem rede:** monte um `ctx` com `T.ctx{ settings = … }`, ponha `ctx.net = { get_json = function(url, opts) … end }` e
  um `ctx.cache` simples (veja `tests/test_app.lua`). Cubra cada `kind` de falha, o formato errado, `ctx.net == nil` e a regra do
  limite. Rode: `luajit tinta.koplugin/apps/_exemplo_json/tests/run.lua` e `SMOKE_APP=_exemplo_json luajit tests/tinta_ui_smoke.lua`.

## 16. Terceiro exemplo: uma app que usa um serviço da web (`apps/_exemplo_clima`)

Os três exemplos cobrem os três tipos de app: a **`_modelo`** é **local** (sem rede: timers, notas, contadores), a
**`_exemplo_json`** fala com **o seu servidor** (um endereço que você configura, com token opcional) e a **`_exemplo_clima`**
usa um **serviço público da web**, a API [Open-Meteo](https://open-meteo.com) (sem chave de API e sem conta): tempo agora e nas
próximas horas, e um aviso de "chuva nas próximas horas". Como as outras, a pasta começa com `_` (só carrega com `dev_apps`, fora
do zip de release).

| Arquivo | O que mostra |
|---|---|
| `init.lua` | manifesto com `net = true`, `defaults = { interval = 1800 }` (a cada 30 min), `settings` `lat` / `lon` (`number` com `min`/`max`) e `units` (`choice`), o tipo de notificação `rain`; `refresh` com `ctx.net.get_json` |
| `logic.lua` | `Logic.url` (monta o pedido com os valores validados), `Logic.parse` (guarda só a temperatura atual e as próximas 24 horas; recusa o formato errado sem lançar erro), `Logic.rain_ahead` (a regra do aviso), `Logic.day_key`, `Logic.view` |
| `view.lua` | widgets 2×2 e 4×2 com `ui.basic`; tela com a temperatura grande e a lista das próximas horas (`ui.rows`) |
| `tests/` | `ctx.net` falso que devolve o JSON gravado em `tests/sample.json` (e cada tipo de falha); regra da chuva e do aviso por dia; widgets e tela em todos os tamanhos |

O que copiar para as suas apps:

- **Um serviço público sem chave:** o endereço vem do código (`Logic.HOST`), os parâmetros vêm das `settings` já validadas
  (`Logic.url` volta ao padrão se o valor for inválido). Se o serviço pedir chave, use um campo `type = "token"` e passe
  `{ token = … }` a `ctx.net.get_json`: nunca no log, na notificação ou na tela.
- **Pedir o que o serviço já resolve:** o pedido usa `timezone=auto` e `timeformat=unixtime`, então a resposta traz horários Unix e
  o fuso do lugar (`utc_offset_seconds`), e a `logic.lua` não precisa interpretar datas.
- **Cache e `done`:** guarde só o que se mostra (`ctx.cache:put`), chame `done(true)` e só depois `ctx.notify` (a primeira leitura
  da sessão só arma os avisos, seção 7). O widget e a tela fazem **uma** leitura de cache por chamada.
- **Aviso uma vez por dia:** `key = "rain:" .. Logic.day_key(now, offset)`. A Tinta descarta uma chave repetida (seção 10), então
  atualizar a cada 30 min não repete o aviso naquele dia, e o dia seguinte tem outra chave.
- **Testar sem rede:** como na `_exemplo_json`, `ctx.net = { get_json = function(url, opts) … end }` devolve o JSON gravado ou
  `nil, tipo, detalhe`; confira a URL pedida, cada tipo de falha e a regra. Rode:
  `luajit tinta.koplugin/apps/_exemplo_clima/tests/run.lua` e `SMOKE_APP=_exemplo_clima luajit tests/tinta_ui_smoke.lua`.
