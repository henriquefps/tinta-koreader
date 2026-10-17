# Tinta: arquitetura e regras

Plugin do KOReader que transforma um e-reader (Kindle, Kobo ou outro aparelho com KOReader) num painel com várias apps:
tela inicial com widgets, notificações, atualização agendada por app e modo repouso. Este documento descreve a arquitetura
e as regras que o código segue; é a referência para quem contribui. O protótipo navegável é
[`tinta-prototipo.html`](tinta-prototipo.html): abra no navegador; o que ele mostra é o comportamento esperado, e onde o
protótipo e este texto divergirem, vale este texto. Guia de quem escreve apps: [`sdk.md`](sdk.md). Visão geral e decisões da
plataforma: [`plataforma.md`](plataforma.md).

> **English summary.** Architecture and rules of Tinta, a KOReader plugin: a widget home screen, notifications, per-app
> scheduled refresh and a sleep page. Every rule has an id (`R-…`) that code comments and reviews cite; "spec 6.1" in a
> code comment means section 6.1 of this file. Core logic (`core/`) is pure Lua testable with `luajit`; the KOReader-facing
> code lives in `ui/` and `device/`; apps are folders under `tinta.koplugin/apps/<id>/` with a manifest contract
> (section 5). Black and white only, no animation, every measure through the scaled theme (`T.px`).

## 1. Como usar este documento

- Cada regra tem um número (`R-…`) para ser citado em revisão e em comentários de código. Os comentários que dizem
  "spec 6.1" ou "7.5" falam das seções deste arquivo.
- A seção 2 junta o aparelho de referência e as lições. As seções 3 a 15 descrevem o que o código faz.
- O que é preciso saber para escrever uma app está no [SDK](sdk.md); aqui estão as regras gerais por trás dele.

## 2. Contexto técnico

### 2.2 O aparelho de referência

- **Kindle Basic 2 (KT3, 8ª geração, 2016)**: tela 600 × 800, 167 ppi, e-ink, touch, **sem luz frontal**, Wi-Fi só 2,4 GHz,
  com jailbreak e KOReader (testado com a v2025.04). É o único aparelho testado em mãos; a tela de 600 × 800 é a escala 1 do
  projeto (seção 6.1). Com o KOReader aberto, o USB não monta o aparelho.
- **Bateria do KT3:** 907 mAh; 1 % ≈ 9 mAh. Medidor em `/sys/class/power_supply/bd7181x_bat/` (`voltage_now`,
  `current_now`, `charge_now`, `charge_full`, `temp`, `capacity`, `status`). Suspenso, o KT3 gasta alguns mA; com a Tinta
  aberta e o Wi-Fi ligado, algumas dezenas de mA.
- **SQLite:** o binding `lua-ljsqlite3` que o próprio KOReader usa (`require("lua-ljsqlite3/init")`).
- **Por aparelho (backends, 11.1).** A Tinta escolhe um backend uma vez, ao abrir, pelo `Device` do KOReader
  (`Device:isKindle()`, `isKobo()`, senão genérico). Só o KT3 foi testado em aparelho; o resto é derivado das fontes do
  KOReader e testado só com simulações.

  | | Kindle (KT3, testado) | Kobo (experimental, sem teste em aparelho) | Outros (genérico, sem teste) |
  |---|---|---|---|
  | Suspender | `powerd` por `lipc` (`preventScreenSaver` 0 + `powerButton`, R-P9) | o próprio KOReader (`UIManager:suspend` → `Kobo:suspend`, `/sys/power/state`) | o próprio KOReader (`Device:canSuspend()`) |
  | Despertar por relógio | `rtcWakeup` repetido a cada 2 s (R-P10); modo awake-usb com cabo | `Device.wakeup_mgr:addTask(s, cb)` em `/dev/rtc0` (`dodgy_rtc` em i.MX5 vira cadeia de alarmes) | não há |
  | Botão de energia | `OutOfSS` / estado `active` do `powerd` | `Device:resume` (evento Power/Resume) | `Device:resume` |
  | Bateria | medidor `bd7181x`: %, mV, mA, **mAh**, °C | `KoboPowerD`: %, carregando (sem mAh) | `powerd` do KOReader: %, carregando |
  | Estimativa (Bateria) | mAh | % (sem mAh) | % |
  | Plugado | `status`/`charging` do medidor ou `isCharging()` | `powerd:isCharging()` (inclui "cheio no cabo") | `powerd:isCharging()` |
  | Limite do Wi-Fi no despertar | 30 s | 60 s (parâmetro do backend) | 30 s |
  | USB | com o KOReader aberto não monta | o KOReader pode oferecer o USBMS; a Tinta não mexe nos eventos | — |


- **Logs no aparelho:** `koreader/crash.log` (saída do KOReader). O único crash conhecido de interface veio de chamar
  `getSize()` num `HorizontalGroup` e depois acrescentar filhos (R-L1).
- **Deploy:** USB ou SSH com `scripts/deploy.sh` (15.4).

### 2.3 Lições que valem para a implementação

- **R-L1.** Nunca chamar `getSize()` num `HorizontalGroup`/`VerticalGroup` que ainda vai receber filhos: o
  KOReader guarda o layout em cache e o filho novo fica sem posição (crash ao desenhar). Somar larguras à mão.
- **R-L2.** Os testes rodam sem KOReader. Tudo que é lógica fica em módulos puros, testados com `luajit`; a
  interface só é validada no aparelho (ou no emulador `kodev`, ver 15.3).
- **R-L3.** Ler o medidor por arquivo (`/sys/...`), não por processo, para medir sem aumentar o consumo.
- **R-L4.** Comparar consumo sempre na mesma faixa de bateria; a porcentagem cai mais rápido abaixo de ~65 %.

## 3. Escopo

**Entra tudo o que o protótipo mostra** (lista completa no Apêndice A), com as apps que vêm no plugin: Bateria, Relógio,
Repouso, Timer, Nota rápida, Contagem regressiva, Notificações e Sistema. Apps de terceiros se instalam em
`koreader/tinta-apps/` (seção 5 e 15.4).

**Não entra:** índice de apps, apps declarativas por HTTP, atualização da própria plataforma.

O núcleo e as apps se separam por um contrato (seção 5), para que apps novas não exijam mexer no núcleo.

## 4. Arquitetura

### 4.1 Pastas

```
tinta/
  tinta.koplugin/              o plugin
    _meta.lua
    main.lua                    entrada: menu do KOReader, ação de gesto, abre/fecha a Tinta
    core/                       núcleo (puro, sem require de módulos do KOReader, exceto onde indicado)
      registry.lua              registro de apps, chamadas protegidas, estado de erro por app
      layout.lua                encaixe dos widgets na grade (pack), páginas
      scheduler.lua             quando atualizar cada app (intervalo, horário, silêncio, agrupamento)
      notify.lua                API de notificações, deduplicação, preferências, não lidas
      store.lua                 acesso ao SQLite (interface pequena) e migrações
      settings.lua              configurações globais e por app sobre o store
      power.lua                 regras do repouso e da agenda (puro); o lado do aparelho fica em device/
      i18n.lua                  textos pt/en do núcleo
      format.lua                hm, ago, every, eta, truncar UTF-8
    device/                     tudo que fala com o aparelho (KOReader ou /sys); fino, sem lógica
      battery.lua               leitura do medidor
      net.lua                   HTTP com timeout e limite de tamanho; estado do Wi-Fi; ligar/desligar
      sleep.lua                 suspend e despertar pelo relógio 
    ui/                         componentes de tela (KOReader)
      theme.lua                 medidas e fontes (seção 6.1)
      statusbar.lua, navbar.lua, appheader.lua, widgetframe.lua, row.lua, button.lua, pager.lua
      dialog.lua, toast.lua, banner.lua, sheet.lua (menus)
      screen.lua                janela principal: pilha de telas, gestos, refresh e-ink
      home.lua, central.lua, organizer.lua, sleepscreen.lua
    apps/
      bateria/, relogio/, repouso/, timer/, nota/, contagem/   apps que vêm no plugin
      notificacoes/             widget e central (app do sistema)
      sistema/                  telas de Sistema
      _modelo/, _exemplo_json/  apps de referência do SDK (só carregam com dev_apps)
  tests/                        smokes headless da interface (luajit)
  scripts/deploy.sh             USB e SSH
  docs/                         esta especificação e o protótipo
```

Apps de usuário ficam fora do plugin, em `koreader/tinta-apps/<id>/`, e sobrevivem à atualização do plugin (R-M4).

### 4.2 Regras gerais

- **R-A1.** Módulos em `core/` e a lógica de cada app (`apps/*/logic.lua`) não fazem `require` de módulos do
  KOReader: recebem relógio, leituras e dependências por parâmetro, como um módulo de lógica de plugin comum.
- **R-A2.** Toda chamada do núcleo para uma app passa por `registry.call(app_id, fn, ...)` (ver 5.4).
- **R-A3.** Só preto e branco na tela; o único cinza é a trilha fina dos anéis . Sem animações.
- **R-A4.** Nenhum log, tela ou arquivo mostra tokens. Respostas dos servidores são decodificadas só nos campos
  necessários (uma app guarda o mínimo: descarta perfis, coordenadas, tokens de terceiros e tudo o que não desenha).

## 5. Contrato das apps

### 5.1 Manifesto

Cada app é um módulo `apps/<id>/init.lua` que devolve uma tabela:

```lua
return {
  id = "minhaapp",                   -- [a-z0-9_]+, único
  name = "Minha app",                -- nome mostrado
  short = "Minha",                   -- rótulo curto (mapa do organizador)
  version = 1,                       -- versão do esquema de dados da app (migrações, 5.6)
  api = 1,                           -- versão da API de apps da Tinta para a qual a app foi escrita (R-M1); sem o campo vale 1
  min_tinta = "0.1",                 -- opcional: versão mínima da Tinta ("x.y"); mais nova que a da Tinta = a app não carrega (R-M1)
                                     -- (min_portal, o nome de antes, continua aceito)
  sizes = { "4x4", "4x2", "2x2", "1x1" },   -- tamanhos de widget suportados; o primeiro é o padrão
  net = true,                        -- usa rede (precisa de Wi-Fi para atualizar)
  sensitive = false,                 -- opcional: true = o widget começa OCULTO na página de repouso (R-V1); a Nota declara true
  source = { id = "minhaapp", name = "meu-servidor" },  -- servidor, para a tela Conexões (nil se não usa rede)
  defaults = {                       -- configurações e seus padrões (5.5)
    interval = 60,                   -- segundos; 0 = manual
    window = nil,                    -- { from = "07:30", to = "18:30", weekdays = true } ou nil
  },
  settings = { ... },                -- campos editáveis (5.5)
  notifications = { ... },           -- tipos de notificação que a app pode emitir (8.6), para a tela de preferências

  -- ciclo de vida (todos opcionais exceto refresh e widget)
  init = function(ctx) end,                       -- uma vez, ao abrir a Tinta
  refresh = function(ctx, done) end,              -- busca dados; chama done(ok, err) (assíncrono permitido)
  widget = function(ctx, size, box) end,          -- devolve o widget KOReader para o tamanho pedido
  screens = { main = function(ctx, args) end, ... },   -- telas em tela cheia; "main" abre ao tocar no widget
  on_route = function(ctx, route) end,            -- abre uma rota vinda de uma notificação (8.4)
  attention = function(ctx) end,                  -- true quando a app precisa do usuário (widget invertido)
}
```

**Versões e gestão de apps (onda B da plataforma).**

- **R-M1.** A Tinta declara `TINTA_VERSION` ("x.y") e `API_VERSION` (inteiro) num só lugar, `core/version.lua`.
  `api` é a versão da API de apps (campos do manifesto, `ctx`, telas) para a qual a app foi escrita; só sobe quando uma
  app antiga poderia quebrar. Uma app **não carrega** (o registro não a registra: sem `init`, `refresh`, `background`,
  widget nem notificações) quando `api` > `API_VERSION` ou `min_portal` > `TINTA_VERSION` (comparação numérica por
  parte: "0.10" > "0.9"). Ela não derruba nada: aparece em Sistema → Apps como "precisa de uma versão mais nova do
  Tinta" (com o que pede e o que esta Tinta tem) e o registro guarda o manifesto só para a listagem. Esse teste vem
  **antes** da validação do resto do manifesto (um manifesto futuro pode ter outro formato). Apps sem `api` valem
  `api = 1` (todas as atuais declaram `api = 1` explicitamente); `api` tem de ser inteiro ≥ 1 e `min_portal`, "x.y",
  senão o manifesto é rejeitado como qualquer outro inválido.
- **R-M2.** Ativar/desativar (10.5): a lista de ids desativados é uma configuração da Tinta (`disabled_apps`),
  lida uma vez e mantida em memória. Uma app desativada **não é registrada** ao abrir: sem `init`, `refresh`,
  `background`, notificações, sem widget no Início nem no repouso. Os layouts guardados **continuam com o id**, então ao
  reativar a app volta ao lugar dela. Notificações e Sistema nunca se desativam nem se removem.
- **R-M3.** Remover (10.5): só apps que não são de sistema (`system = true` no manifesto, nem Notificações/Sistema). Apaga
  `apps/<id>/` da pasta do plugin (recursivo; `core/appfiles.lua` com o sistema de arquivos injetado, R-A1) e limpa tudo
  o que o banco guarda da app: configurações (escopo), `app_data`, cache, estado, notificações e as marcas de versão e
  importação; tira o id dos layouts. Guardas: o id tem de casar `[a-z0-9_]+` (então `../x`, `a/b`, `.` e vazio são
  recusados antes de montar o caminho); o caminho é sempre `<pasta apps do plugin>/<id>`; um link simbólico nunca é
  seguido (a pasta da app como link é recusada; um link dentro dela é só desfeito); se algum arquivo não puder ser
  apagado, para com o motivo e **não** mexe no banco nem na lista.
- **R-M4.** Atualizar o plugin copiando a pasta inteira traz de volta as apps removidas. Para evitar isso, o id removido
  entra na configuração `removed_apps` e `loadApps` **pula** essas pastas (nem faz `require`). Sistema → Apps mostra
  "Apps removidas (N)" enquanto a lista não está vazia; tocar nela esvazia a lista e as pastas que existirem
  voltam a carregar na próxima abertura da Tinta. Quem distribui o plugin deve atualizar sobrescrevendo a pasta
  (a lista fica no banco, não na pasta, e sobrevive).

### 5.2 Contexto (`ctx`) que o núcleo entrega à app

| Campo | O que é |
|---|---|
| `ctx.now()` | relógio (injetado; os testes passam um falso) |
| `ctx.settings:get(k)` / `:set(k, v)` | configurações da app (5.5) |
| `ctx.data:get(k)` / `:set(k, v)` | dados persistentes da app no banco (5.6), valores Lua serializáveis |
| `ctx.cache` | último dado bom (`ctx.cache:get()` / `:put(tbl)`), persistido para aparecer sem rede |
| `ctx.net.get_json(url, opts)` / `post_json` | HTTP com timeout, limite de bytes e decodificação JSON |
| `ctx.notify(n)` | emitir notificação (8.1) |
| `ctx.open(screen, args)` | abrir uma tela da própria app |
| `ctx.confirm(title, text, ok_label, fn)` | confirmação padrão (6.9) |
| `ctx.choose(title, options, current, on_pick)` | popup de escolha (6.10); também `ctx.ui.choose` |
| `ctx.toast(text)` | aviso curto |
| `ctx.input(title, value, hint, on_save, opts)` | teclado do KOReader; `on_save(text)` → `true` \| `false, mensagem` (11.7) |
| `ctx.wake_at(ts)` | pede a Tinta acordado em `ts`, inclusive do repouso; `nil` cancela (11.7) |
| `ctx.redraw()` / `ctx.back()` | redesenha a tela atual / volta uma tela |
| `ctx.ui` | componentes da seção 6 |
| `ctx.i18n` | idioma atual e função de tradução da app |
| `ctx.log(msg)` | log da app (vai para o log da Tinta com o id da app) |
| `ctx.state` | `{ last_ok, last_err, err_text, busy }` mantido pelo núcleo |

### 5.3 Widgets

- **R-W1.** A app desenha o widget em qualquer tamanho que declarou. `box` traz a largura e a altura em pixels
  já calculadas pela grade (6.3). O widget não pode passar dessas medidas: texto que não cabe é cortado com "…".
- **R-W2.** O núcleo desenha a moldura (borda, inversão quando `attention`, borda tracejada quando o último
  refresh falhou, ver R-S5) e o rodapé padrão (R-W4). A app desenha só o miolo.
- **R-W3.** Conteúdo mínimo por tamanho: 1×1 = ícone e um número curto opcional; 2×2 = nome, linha principal,
  linha secundária, rodapé; maiores = o que a app quiser, como no protótipo.
- **R-W4.** Rodapé padrão: em widgets de 4 colunas, "idade · intervalo" (`há 3 min · a cada 1 min`), "sem
  resposta · idade", "idade · volta 07:30" (fora do horário) ou "atualizando…". Em widgets de 2 colunas, só a
  informação mais importante, nesta ordem: atualizando, sem resposta, volta HH:MM, idade.

### 5.4 Isolamento de erros

- **R-E1.** `registry.call` usa `pcall` (ou `xpcall` com traceback) em toda chamada de app: `init`, `refresh`,
  `widget`, telas, `on_route`, `attention`, e nos callbacks que a app entrega ao núcleo.
- **R-E2.** Se `widget` falha, o núcleo desenha um widget padrão "Nome · erro na app" no mesmo tamanho. Se uma
  tela falha, mostra uma tela de erro com Voltar. A Tinta nunca fecha por erro de app.
- **R-E3.** Erros vão para o log da Tinta com app, função e a primeira linha do traceback.
- **R-E4.** Três falhas seguidas de `refresh` por exceção (não por rede) desativam a atualização automática da
  app até o próximo `Atualizar` manual; o cabeçalho mostra "erro na app".

### 5.5 Configurações

- **R-C1.** Cada app declara campos em `settings`: `{ key, label, type = "url"|"token"|"number"|"time"|"choice"|"bool", default, min, max, choices }`.
  A tela "Sistema → Apps → <app>" é gerada a partir disso (entrada de texto do KOReader para url, token, número
  e hora).
- **R-C2.** Campo `token`: nunca mostrado; a tela exibe "definido" / "não definido" e a caixa abre vazia (vazio
  mantém o atual), como o plugin atual.
- **R-C3.** Validação no `logic.lua` da app (os validadores dos plugins atuais servem: URL, intervalo, hora,
  fuso).
- **R-C4.** Intervalo e horário de atualização (`interval`, `window`) são configurações de todas as apps, com
  padrão no manifesto e mudança em Sistema → Atualizações e no menu da app.

### 5.6 Dados da app

- **R-D1.** `ctx.data` e `ctx.cache` são separados por app no banco (tabela com coluna `app`).
- **R-D2.** Quando `version` do manifesto sobe, o núcleo chama `migrate(ctx, from, to)` se existir; se não
  existir, apaga o cache da app (o cache sempre pode ser refeito).

## 6. Interface

### 6.1 Medidas e escala (projeto de 600 × 800; KT3 = escala 1)

As medidas abaixo são o **projeto**, em px de uma tela de 600 × 800 (retrato) ou 800 × 600 (paisagem): é a tela
real do KT3 (167 ppi), onde cada medida vale exatamente o que está na tabela. Em qualquer outra tela a Tinta
multiplica **todas** as medidas por uma única escala (R-Z1) e centraliza a área 3:4 (R-Z2). Todo px citado
nas seções 6 a 12 (alturas, bordas, 64 px de toque, 120 × 6 do traço…) é medida de projeto.

| Item | Medida de projeto |
|---|---|
| Barra de status | 48 px de altura, borda inferior de 2 px |
| Barra de navegação | 72 px, 4 botões iguais, divisórias de 2 px |
| Margem e espaço entre blocos | 8 px |
| Texto mínimo | 20 px; corpo 22 px; relógio 26 px (negrito) |
| Linha principal de widget | 26 px negrito (32 px nos 4×4); nome do widget 22 px negrito |
| Números grandes | 44 px (blocos de estatística), 72 px (porcentagem da Bateria) |
| Alvos de toque | ≥ 64 px de altura (linhas, botões); toda a área do widget é tocável |
| Bordas | 2 px; seleção e não lida 4 px; diálogos 3 px; cantos de 4 px |
| Grade de widgets | 6 colunas × 8 linhas em retrato, 8 × 6 em paisagem, espaço de 8 px |
| Aviso no topo | logo abaixo da barra de status, 8 px das bordas |
| Ícones | Wi-Fi 30 × 26, sino 24 × 26, engrenagem 30, casa 26 × 24, menu 24 × 20, bateria 34 × 18 + ponta 4 |

Fonte: a `cfont` do KOReader (Noto Sans). As medidas ficam em `ui/theme.lua` (tabela `BASE`); nenhum número solto
nas telas: o que não tem nome no tema usa `T.px(n)` (medida de projeto → px da tela).

**Escala (R-Z1 a R-Z8)**

- **R-Z1.** Uma só escala `s = min(W / 600, H / 800)` em retrato e `min(W / 800, H / 600)` em paisagem
  (W × H = tela real). Toda medida do projeto vira `round(medida × s)`, com estas exceções:
  tamanhos de fonte arredondam **para baixo** (`T.fpx`: um texto que cabe no KT3 continua cabendo; o épsilon mantém
  os produtos exatos); bordas, divisórias, cantos e traços finos ficam com **pelo menos 1 px**; não escalam o nome
  da fonte, a contagem de colunas/linhas da grade, `NAV_BUTTONS`, itens por página, tempos (`TOAST_MS`,
  `HOLD_MS`…) nem `FULL_EVERY`. Gestos (zonas de borda, 80 px de deslize, 12 px de tolerância do toque
  longo) escalam como o resto.
- **R-Z2.** **Caixa de conteúdo:** a área 3:4 (4:3 em paisagem) de `round(600 × s) × round(800 × s)`, centralizada
  na tela, em `(T.ox, T.oy)`. O que sobra da tela (letterbox) é **branco** e não faz parte da Tinta: nada é
  desenhado nem tocável ali. Numa tela 3:4 a caixa é a tela inteira; no KT3 é idêntica à tela. A janela pinta a
  caixa em `(ox, oy)` e as quatro faixas brancas em volta (nenhuma pintura extra quando não há faixa).
- **R-Z3.** `ui/theme` calcula `s` e a caixa em **um só lugar** (`T.configure(W, H)`, chamado por
  `ui/geom.regions` a cada montagem de tela, de graça quando a tela não mudou) e reescreve no próprio `T` as
  medidas escaladas (`T.SB_H`, `T.FONT_BODY`…); `T.s`, `T.ox`, `T.oy`, `T.BW`, `T.BH` ficam disponíveis. Todo
  código lê `T.X` **na hora de usar**, nunca guarda o valor no carregamento do módulo. `ui/geom`, as telas e as apps
  trabalham em coordenadas **relativas à caixa**; só `Window:paintTo` conhece o deslocamento.
- **R-Z4.** Apps e `ui/*` não têm número de pixel solto (só o tema tem números): usam `T.*`, `T.px`/`T.px1`/`T.fpx` ou `T.s`.
  Decisões de layout por limiar (`largura ≥ 300`, `diâmetro ≥ 100`) também escalam, para que a *estrutura* da
  tela seja a mesma em todas as escalas. Lógica pura (`core/`, `apps/*/logic*.lua`) não usa pixel (R-A1).
- **R-Z5.** Desenhos por máscara (`ui/shapes`: Wi-Fi, sino, casa, menu; traços do gráfico da Bateria; mostrador e
  ponteiros do Relógio; anéis e quadrados de uma app) recebem a escala `k = T.s` e a aplicam a traços, raios e
  deslocamentos internos; `k = 1` (padrão) gera exatamente a máscara do KT3. Os ícones PNG de uma app (36 e 48 px)
  usam o maior arquivo ≤ tamanho pedido e o `ImageWidget` do KOReader os redimensiona (MuPDF, ou vizinho mais
  próximo com `legacy_image_scaling`); no KT3 (36 px) o arquivo é exibido como está.
- **R-Z6.** Gestos: o toque só vale em caixas desenhadas (a faixa branca não toca em nada). Um deslize que
  **começa** na faixa conta como começando na borda da caixa (o dedo parte da borda física da tela). As zonas
  de borda são medidas a partir da caixa.
- **R-Z7.** Alvos de toque: botões, linhas e paginador têm altura `T.TOUCH = round(64 × s)`; o teste exige
  `≥ floor(64 × s)` em toda tela suportada e que o menor alvo de cada tela seja o do KT3 vezes `s`.
- **R-X1.** Tamanho do texto (Sistema → Tela e navegação, configuração `text_size`: `normal` | `grande`). Um fator
  (`normal` = 1,0, `grande` = 1,15, `Settings.TEXT_FACTORS`) multiplica **só** os tamanhos de fonte do tema, **depois**
  da escala da tela: `fonte = floor(base × s × fator)` (`T.set_text_factor`, mesmo mecanismo de `T.s`; todo texto
  lê `T.FONT_*` na hora de desenhar). As caixas que guardam linhas de texto (linha de lista `ROW_H`, botão `BTN_H`,
  item de menu `SHEET_ITEM_H`, rodapé de widget `WIDGET_FOOTER_H`, seção e nota das listas) crescem pelo mesmo fator, para
  o texto maior continuar dentro da linha; barras, margens, bordas, grade e alvos de toque não mudam. Com `normal` todos os
  valores são exatamente os de antes (KT3 idêntico). O texto que não cabe continua sendo cortado com "…" (R-W1).
- **R-X2.** Teste: o fumaça inteiro roda com texto grande em seis tamanhos de tela (`SMOKE_TEXT=large`), e o cenário
  `tests/tinta_ui_firstrun.lua` confere que todo texto de todo widget do Início fica dentro da caixa do widget, em
  normal e em grande.
- **R-Z8.** Testes: (a) o fumaça (`tests/tinta_ui_smoke.lua` e o de cada app que tenha um) grava um hash FNV
  dos desenhos de cada passo (retângulos, bordas, textos com posição e tamanho) e, em 600 × 800, compara com
  `tests/fixtures/kt3-trace*.txt`: **identidade de pixels no KT3**; (b)
  `tests/tinta_ui_scales.lua` roda os dois fumaças em 600 × 800, 758 × 1024 (não 3:4), 1072 × 1448,
  1264 × 1680, 1404 × 1872 e 1860 × 2480, em retrato e paisagem: toda caixa dentro da tela, só branco fora da
  caixa de conteúdo, nenhum texto cortado além do que o KT3 já corta (+6 %), alvos de toque ≥ KT3 × `s`; e em 1200 × 1600
  e 1800 × 2400 (múltiplos exatos, fonte de teste linear) cada desenho de cada passo é o do KT3 vezes 2 e 3
  (até 2k px de arredondamento); (c) `tests/tinta_ui_test.lua`: tema, caixa, regiões, grade e sobreposições em
  dez tamanhos nos dois sentidos, máscaras e escala dos gestos.

### 6.2 Barra de status

- **R-S1.** Da esquerda para a direita: relógio (HH:MM), sino com o número de não lidas (o número em caixa
  preta; sem número quando zero), espaço, Wi-Fi, bateria (`82% · ~17h`, com `⚡` antes quando carregando, e o
  desenho da bateria).
- **R-S2.** Toques: relógio → atualizar a app aberta (no Início, todas as visíveis); sino → central; Wi-Fi →
  central; bateria → app Bateria.
- **R-S3.** Wi-Fi com três estados: conectado (arcos cheios), conectando (arcos tracejados e "…"), desligado
  (arcos riscados).
- **R-S4.** Em repouso, a barra mostra só "Repouso · atualizado HH:MM · próxima HH:MM" e a bateria (11.4).
- **R-S5.** Estado de dado velho por app: o último refresh falhou e há dado anterior → widget com borda
  tracejada, cabeçalho "sem resposta · último dado há N min".

### 6.3 Barra de navegação e gestos

- **R-N1.** Botões: ⌂ Início, ‹ Voltar, ↻ Atualizar, ☰ Menu. Início fica desabilitado no Início, exceto quando
  a página atual não é a primeira (aí volta para a primeira). Voltar fica desabilitado sem tela anterior.
- **R-N2.** Modos: "barra + gestos" (padrão) e "só gestos". Em "só gestos" a barra some e fica um traço de
  120 × 6 px centrado a 8 px da borda de baixo.
- **R-N3.** Gestos (um dedo; valem nos dois modos):

| Gesto | Ação |
|---|---|
| Começar a até 50 px da borda de baixo e subir mais de 80 px | Início |
| Começar a até 50 px da borda esquerda e ir para a direita mais de 80 px | Voltar (fecha menu ou diálogo antes) |
| Começar a até 60 px da borda de cima e descer mais de 80 px | Central de notificações |
| No Início, deslizar na horizontal mais de 80 px (menos de 60 px na vertical), fora das bordas | Página seguinte / anterior |
| Segurar um widget por 650 ms sem mover mais de 12 px | Organizador, com esse widget selecionado |

- **R-N4.** A Tinta registra uma ação no Dispatcher do KOReader ("Tinta") para abrir por gesto ou perfil,
  como outros plugins fazem.
- **R-N5.** Pilha de telas: abrir uma tela empilha; Voltar desempilha; Início limpa a pilha. Abrir uma
  notificação substitui a pilha por Início → rota da notificação.

### 6.4 Cabeçalho de app

Nome da app (26 px negrito) à esquerda; à direita, o mesmo texto do rodapé de 4 colunas (R-W4), ou
"pausado até HH:MM" fora do horário, ou "erro na app" (R-E4). Borda inferior de 2 px.

### 6.5 Menu (folha de baixo)

Abre por ☰ Menu, por cima do conteúdo e acima da barra de navegação. Itens de 60 px:

- **Apps** é sempre o primeiro item, em qualquer tela: abre o lançador (7.4).
- Na tela de uma app: "Atualizar <app> agora", "Intervalo desta app: <valor>" (abre o popup de escolha, 6.10, com os
  valores de R-U1), e depois os itens comuns.
- No Início: "Organizar o início", e depois os comuns.
- Comuns: "Atualizar todas as apps", "Central de notificações", "Abrir Sistema", "Dormir agora". A folha cabe 7
  itens em paisagem com a barra de navegação; na tela de uma app com atualização o "Apps" faria o "Dormir agora"
  sair, então ali a "Central de notificações" não aparece no Menu (continua no sino, no gesto do topo e em
  Apps → Notificações).

Tocar fora da folha fecha. Voltar fecha.

### 6.6 Paginação

Lista que não cabe vira páginas com `‹  N/M  ›` (botões de 64 px). Nunca rolagem.

### 6.7 Refresh do e-ink

- **R-R1.** Trocar de tela (empilhar, voltar, Início, trocar de página, girar): refresh completo.
- **R-R2.** Atualização de dados na mesma tela, aviso no topo, menu e diálogo: refresh parcial; um completo a
  cada 10 parciais (como o plugin atual, `FULL_EVERY = 10`).

### 6.8 Orientação

Retrato ou paisagem, global (Sistema → Tela e navegação e atalho na central). Girar recalcula a grade e o
encaixe; o layout salvo é o mesmo nos dois (ordem e tamanhos), só o encaixe muda. Ao fechar a Tinta, a rotação
anterior do KOReader é restaurada (como o plugin atual), **antes** de a janela fechar, e só o framebuffer gira:
a Tinta não envia `SetRotationMode` (o `FileManager` reconstruiria a barra de título por baixo, com
`IconButton` ainda sem `dimen`, e o leitor refaria o layout do documento). Depois de fechar, uma janela invisível
engole os toques por ~0,8 s, enquanto o e-ink ainda mostra a Tinta e a tela de baixo se redesenha. Detalhes em
`docs/investigacao-crash-sino.md`.

### 6.9 Confirmação e avisos

- **R-K1.** Toda ação que escreve num servidor pede confirmação: diálogo com título, texto e
  "Cancelar" / "<ação>".
- **R-K2.** Avisos curtos ("Atualizado", "Sem Wi-Fi: mostrando o último dado", "Servidor sem resposta: mantive o
  último dado") em caixa preta acima da barra de navegação, por 2,6 s.

### 6.10 Popup de escolha

- **R-K4.** Toda linha de configuração com várias opções (intervalos, idioma, modo de "Dormir sozinho", "Depois de",
  "Atualizar a tela", tamanho do texto, navegação, preferência de aviso, campos `choice` das apps, estilo do relógio…)
  abre um popup em vez de ciclar a cada toque. Só os **botões de widget** (o 4×2 do Repouso) e os liga/desliga (`bool`,
  orientação, Estado) continuam num toque.
- Desenho: caixa centrada entre a barra de status e a barra de navegação (a largura do diálogo, 6.9), borda de 3 px,
  título do campo e **uma linha de 64 px por opção** (`ui/row`); a opção atual vai **invertida e com "●"**. O fundo
  (`backdrop`) pega todo toque fora da caixa, inclusive os da barra de navegação. Preto e branco, sem animação, medidas
  em `T.px`, como as outras camadas (`ui/picker.lua`, camada própria do `Window`, não um widget do KOReader).
- Comportamento: tocar numa opção grava (callback `on_pick(valor)`, protegido, R-E1) e fecha; tocar fora, "Voltar" da
  barra, o gesto de voltar e a tecla Voltar cancelam sem gravar. O popup abre na página da opção atual. Quando as
  opções não cabem (paisagem, textos grandes, listas longas) ele vira **páginas** com o pager (‹ N/M ›), nunca rola.
- Variante que **fica aberta** (`keep_open`, com um botão de fechar "Pronto"): cada toque grava e a lista é
  reconstruída (a lista de opções pode ser uma função). Usada em "Ocultos (N)" do organizador (R-O4).
- Lógica pura em `ui/picklogic.lua` (normalizar opções, marca da atual, linhas por página, página inicial, fatias),
  testada em `tests/tinta_ui_test.lua`. API: `Window:pick{ title, options, current, on_pick, owner?, keep_open?,
  done_label?, empty? }`, `Host:pickSetting(...)` (configurações da Tinta), `ctx.choose` e `ctx.ui.choose` (apps).

## 7. Início, widgets e organizador

### 7.1 Encaixe

- **R-G1.** O layout é uma lista ordenada de `{ app, size, hidden }`. Não existe posição livre.
- **R-G2.** Algoritmo (puro, `core/layout.lua`): para cada item visível, na ordem, colocar na primeira página
  onde caiba, na primeira posição livre varrendo linhas de cima para baixo e colunas da esquerda para a direita.
  Tamanho maior que a grade é limitado à grade. Resultado: lista de páginas com `{ app, size, x, y, w, h }`.
  Ver `pack()` no protótipo.
- **R-G3.** Testes do encaixe: layout padrão em retrato e paisagem (posições exatas), item que não cabe vai
  para a página seguinte, preenchimento de buracos por itens menores posteriores, lista vazia = uma página vazia.
- **R-G4.** Tamanho das células: `largura = (área − 7 × 8 ou 5 × 8) / colunas`, idem altura; o widget de
  `w × h` células mede `w × célula + (w − 1) × 8` px.

### 7.2 Layout padrão

O padrão está em `core/layout.lua` (`M.DEFAULT`): as apps do layout padrão que não estão instaladas são ignoradas.
O assistente de primeiro uso (7.5) deixa o usuário escolher.

### 7.3 Organizador

- **R-O1.** Abas "Início" e "Repouso", cada uma editando o próprio layout.
- **R-O2.** Mapa de uma página (mesma grade, em escala, blocos com o nome curto e o tamanho); tocar num bloco
  seleciona. Abre na página do widget selecionado. Com mais de uma página há um paginador "‹ N/M ›" sob o mapa
  que percorre TODAS as páginas do layout sem perder a seleção (a linha de informação diz "Nome · tamanho · pág. N"
  e o cabeçalho "página N/M"); qualquer mudança volta a seguir a seleção. Na aba "Repouso" o cabeçalho avisa que
  só a página 1 vai para o repouso.
- **R-O3.** Botões: "↑ Antes" e "↓ Depois" (trocam a ordem entre os visíveis, na lista inteira: o widget
  atravessa as quebras de página e o mapa o acompanha), "Tamanho ▸" (cicla os tamanhos
  da app; é um botão de ação sobre o widget, não uma configuração), "Ocultar" (Início) ou "Tirar" (Repouso), "Pronto" (volta).
  Em paisagem "↑ Antes" e "↓ Depois" dividem uma linha da coluna lateral para caber o botão de R-O4.
- **R-O4.** Um botão **"Ocultos (N)"** (em inglês "Hidden (N)"; desligado com N = 0), nas duas abas, abre o popup de
  escolha (6.10) com as apps ocultas e as que não estão naquela página (no Repouso, sem o Sistema). Tocar numa traz de
  volta, no primeiro tamanho declarado e no fim da lista, mostra o aviso "<app> adicionada" e **mantém o popup aberto**
  (a lista se atualiza) para trazer várias; "Pronto" fecha.
- **R-O5.** Ocultar Sistema é permitido; ele continua acessível pelo Menu e pela central (aviso "Sistema
  continua no Menu").
- **R-O6.** O layout é salvo no banco a cada mudança.
- **R-O7.** Aba "Repouso": ação "Copiar do Início", com confirmação ("Copiar do Início?"), porque substitui o
  layout do repouso. Copia apps, tamanhos e ordem dos widgets da **página 1** do Início (o que se vê ali; o
  Sistema fica de fora, como sempre no repouso). Escolhida a página 1 (e não "tudo que couber") porque é
  exatamente o que o repouso mostra. Não há opção "manter igual ao Início" (fica para depois).

### 7.4 Lançador (Menu → Apps)

Sem o lançador, uma app tirada do Início não tinha como abrir (Sistema → Apps só configura).

- **R-O8.** Tela "Apps", rota `launcher` (empilha sobre a tela atual; Voltar volta de onde veio). Abre por
  Menu → Apps; com o lançador já aberto, o item só fecha o Menu. Não há 4º botão na barra de navegação.
- **R-O9.** Lista **todas** as apps registradas, em ordem alfabética pelo nome exibido no idioma atual (sem
  distinguir maiúsculas nem acentos; empate pelo id): as ocultas, as que nunca foram ao Início e as de sistema
  (Notificações, Sistema). As apps `_test_*` só existem quando `dev_apps` está ligado, a mesma regra do resto da UI.
- **R-O10.** Cada linha: nome, subtítulo curto (o `description` do manifesto, quando a app declara um; sem consulta
  ao banco por linha) e, à direita, a marca "no Início" (está no layout do Início e visível) ou "oculta" (está no
  layout, escondida); sem marca quando nunca foi adicionada. Paginada como as outras listas (6.6), em duas colunas
  em paisagem (10.5). O layout do Início é lido uma vez por desenho.
- **R-O11.** Toque abre a tela principal da app, o mesmo caminho do toque no widget (`openApp`); Voltar volta à lista.
- **R-O12.** Segurar uma linha adiciona a app ao Início (traz a oculta de volta no lugar; a ausente entra no fim
  com o primeiro tamanho declarado) e mostra o aviso "<app> adicionada ao Início"; se já está no Início, o aviso
  é "<app> já está no Início" e nada muda. Sem confirmação (não escreve em servidor, R-K1).
- **R-O13.** Apps desativadas (R-M2) aparecem na lista como linha **apagada** (borda tracejada e peso normal, sem
  cinza, R-A3), subtítulo "desativada" e à direita "Ativar"; tocar reativa na hora (aviso "<app> ativada") e
  segurar não faz nada. Apps que precisam de uma versão mais nova (R-M1) não aparecem aqui, só em Sistema → Apps.
- Puro e testado em `ui/launchlogic.lua` (ordem, marcas, adicionar); a tela é `ui/launcher.lua`.

### 7.5 Primeiro uso

- **R-F1.** Instalação nova = abrir a Tinta **sem estado salvo**: nenhum layout (Início ou repouso), nenhuma marca
  `first_run_done`, nenhuma marca `app_version:<id>` ou `legacy_imported:<id>` das apps que existem na pasta, nenhuma
  configuração da Tinta salva (fora `idle_mode`, que o núcleo grava ao criar o banco). Qualquer um desses sinais
  conta como "já usado": **uma instalação existente (o KT3 do usuário) nunca vê o assistente**. A verificação roda uma
  vez por abertura, **antes** de as apps serem registradas (registrar grava `app_version:`), em `core/firstrun.lua`
  (puro). Ao detectar, grava `first_run_pending`: se o assistente for interrompido (a Tinta fechado no meio), ele volta
  na abertura seguinte mesmo que a primeira já tenha gravado as marcas das apps, até haver um layout salvo ou
  `first_run_done`. Um retorno de `import_legacy` não conta (a app devolve vazio quando não há nada a importar).
- **R-F2.** O assistente é uma rota `{ kind = "wizard" }` sobre o Início, com 4 telas, cada uma com **Pular tudo**,
  **Anterior** (da 2ª em diante) e **Próximo** (na última, **Concluir**): 1) Bem-vindo + idioma pt/en (aplica na hora);
  2) Wi-Fi: estado e botão Ligar/Desligar pelo `NetworkMgr` do host (o mesmo toque da barra de status); 3) Apps: lista
  de marcação (paginada) das apps que vão para o Início, com as do layout padrão marcadas; Sistema e Notificações
  ficam sempre e não aparecem; apps que usam um servidor pedem o endereço depois, em Sistema → Apps (a tela diz isso);
  4) Repouso: "Dormir sozinho" e "Atualizar a tela" (as mesmas configurações da 10.5, aplicadas ao tocar).
- **R-F3.** **Concluir** grava o layout do Início (a ordem do padrão, as apps marcadas e as que o padrão tem e o usuário não
  escolhe, depois as extras marcadas, no primeiro tamanho que declaram) e o do repouso (as marcadas que o padrão do
  repouso tem, mais Notificações 4×2), com tamanhos que cada app declara (`ui/wizlogic.lua`, puro). **Pular tudo** não
  grava layout (vale o padrão, 7.2). Das duas formas grava `first_run_done` e o assistente nunca mais aparece; sair por
  qualquer outro caminho (botão Início, gesto de voltar) conta como pular.
- **R-F4.** Os testes (`tests/tinta_ui_firstrun.lua`, `tinta.koplugin/tests/test_firstrun.lua`): o assistente não
  aparece com nenhum dos sinais de instalação existente; aparece na nova; percorre as quatro telas e grava um layout
  válido; Pular tudo não grava layout; fechar no meio faz voltar; nunca reaparece. O fumaça com apps de teste
  (`dev_apps`) e o das apps abrem com `first_run = false` (sem assistente).

## 8. Notificações

### 8.1 API

```lua
ctx.notify{
  key = "attn:9f8e7d6c5b4a",     -- identidade do evento; a mesma key não gera outra notificação
  title = "Projeto precisa de você",
  body = "claude pediu confirmação",
  prio = "alta",                  -- "alta" | "normal"
  route = { "project", { id = "9f8e…" } },   -- tela de destino dentro da app (opcional)
  type = "attention",             -- um dos tipos declarados no manifesto (8.6)
}
```

### 8.2 Regras do núcleo

- **R-T1.** Deduplicação por `(app, key)`: se já existe uma notificação com a mesma key (lida ou não), não cria
  outra. A app escolhe a key de forma que o evento "volte" quando fizer sentido (ex.: incluir o horário da
  ocorrência).
- **R-T2.** Preferência por app: "alta" (respeita a prioridade da app), "normal" (rebaixa alta para normal),
  "desligada" (descarta e registra no log). Padrão: alta para todas.
- **R-T3.** Guardar no banco: id, app, key, type, title, body, prio, route (JSON), criada em, lida em.
- **R-T4.** Limite: as 200 mais recentes; ao passar, apaga as lidas mais antigas primeiro.
- **R-T5.** Aviso no topo: ao chegar uma notificação com a Tinta acordado e a opção ligada, caixa preta logo
  abaixo da barra de status com "App · HH:MM" e o título, por 5 s. Tocar abre a notificação. Uma nova substitui
  a anterior.
- **R-T6.** Sino da barra: número de não lidas.

### 8.3 Central

- **R-T7.** Abre pelo gesto de cima, pelo sino, pelo Wi-Fi da barra, pelo widget Notificações e pelo Menu.
- **R-T8.** Topo: quatro atalhos de 72 px — Wi-Fi (invertido quando ligado), Repouso (entra agora), Girar,
  Sistema.
- **R-T9.** Lista mais recente primeiro, 4 por página em retrato e 2 em paisagem: "App · alta" e hora, título,
  texto. Não lida = borda de 4 px; alta e não lida = invertida.
- **R-T10.** Rodapé: "Marcar todas como lidas" e "Limpar" (apaga todas, com confirmação).

### 8.4 Abrir uma notificação

Marca como lida, monta a pilha Início → tela de destino (`app.screens[route[1]]` com `route[2]`) e faz refresh
completo. Sem `route`, abre a tela `main` da app.

### 8.5 No repouso

- **R-T11.** Opção "Na tela de repouso": "só alta" (padrão), "todas", "nenhuma". As que se encaixam e estão não
  lidas aparecem numa faixa preta no topo da página de repouso, que deixa claro que são notificações NÃO LIDAS
  guardadas (não o estado dos widgets): "1 não lida: <título>" ou "N não lidas · <título da mais recente>",
  desenhada no despertar seguinte.
- **R-V1.** Privacidade no repouso (o aparelho dormindo fica à vista): cada app tem a opção "Mostrar na página de repouso:
  sim / oculto" (Sistema → Apps → <app>), tratada pelo **núcleo** (configuração `sleep_show` do escopo da app:
  `shown` | `hidden`). Padrão `shown`; uma app com `sensitive = true` no manifesto (como a Nota) tem padrão `hidden`.
  Um widget oculto **não é chamado**: a página de repouso desenha só uma moldura neutra com o **nome** da app (sem
  inversão, sem borda tracejada, sem rodapé: nada do estado dela aparece).
- **R-V2.** Instalações que já existiam (ao abrir pela primeira vez uma versão com esta opção) mantêm o que a página de
  repouso mostrava: toda app `sensitive` sem escolha salva é gravada como `shown` uma vez (marca `sleep_privacy_init`),
  então os pixels do repouso não mudam. Uma instalação nova usa os padrões do manifesto.
- **R-V3.** Sistema → Repouso: "Títulos na tela de repouso" (`sleep_titles`: `mostrar` | `esconder`). Esconder faz a
  faixa preta dizer só "1 não lida" / "N não lidas" (sem título), e o widget de Notificações vira moldura neutra no
  repouso (ele lista títulos).
- **R-T12.** Os rodapés dos widgets na página de repouso nunca mostram o intervalo acordado ("a cada 30 s"),
  que é falso dormindo: mostram "atualizado HH:MM" (a última atualização do repouso) ou nada.

### 8.6 Regras das apps que vêm no plugin

| App | Evento | key | Prioridade |
|---|---|---|---|
| Bateria | Abaixo de 20 % descarregando (uma vez por descarga) | `low:<início da descarga>` | alta |
| Bateria | 100 % carregando (uma vez por carga) | `full:<início da carga>` | normal |
| Sistema | Servidor sem resposta em 2 atualizações seguidas | `down:<source>:<hora da 2ª falha>` | alta |
| Sistema | Servidor voltou depois de estar "sem resposta" | `up:<source>:<hora>` | normal |

A primeira leitura depois de abrir a Tinta só registra o estado; não notifica (evita notificar tudo o que já
estava pendente). Comparações usam o cache persistido da leitura anterior.

## 9. Atualizações

- **R-U1.** Intervalos possíveis: 30 s, 1 min, 5 min, 15 min, 30 min, 1 h, manual. Cada app declara o seu padrão
  (`defaults.interval`); a Bateria usa 1 min (local, sem rede).
- **R-U2.** Horário por app (`window`): fora dele não há atualização automática; o rodapé mostra "volta HH:MM".
  Quando a regra depende de algo que só a app sabe (dias úteis, feriados), a app pode ter uma função
  `in_window(now)` própria.
- **R-U3.** Silêncio noturno global (padrão ligado, 23:00–07:00): sem atualização automática de apps de rede.
- **R-U4.** Agendador (puro): a cada 5 s com a Tinta acordado, as apps visíveis no Início que venceram
  (`last + interval ≤ now`) e estão no horário são atualizadas; junto vão as que venceriam nos próximos 2 min.
  Todas as de rede do lote compartilham uma conexão de Wi-Fi (11.2).
- **R-U5.** Sem Wi-Fi: as apps de rede não atualizam e mantêm o último dado; manual mostra "Sem Wi-Fi:
  mostrando o último dado". Apps locais atualizam normalmente.
- **R-U6.** Falha de rede de uma app: mantém o último dado, marca o estado de falha (R-S5) e conta para a regra
  de servidor do Sistema (8.6).
- **R-U7.** Atualização manual (Atualizar, relógio, menu) ignora intervalo, horário e silêncio.
- **R-U8.** Um refresh em andamento por app; o seguinte espera.

## 10. Telas das apps

### 10.3 Bateria

App local, sem rede:

- Tela: porcentagem grande, desenho da bateria, estimativa (`~5 d restantes · 7 mA em média` ou
  `⚡ carregando · ~40min até 100%`), **duas linhas rotuladas** abaixo (descarregando): `no ritmo atual ~5 d` (ritmo
  real, dormindo incluído) e `acordado com Wi-Fi ~14 h` (só trechos acordados; em paisagem as duas ficam numa
  linha), gráfico da descarga recente (eixos em % e hora, como o protótipo, com
  dados do log), blocos: corrente média, capacidade cheia, temperatura, número de amostras.
- Log: uma linha por mudança de porcentagem ou de carga,
  mais uma a cada 10 min, colunas `unix_time,percent,charging,wifi,mv,ma,mah,temp_c`, corte em 2800 → 2000
  linhas (~100 KB no máximo). (O log pode migrar para o banco no futuro.)
- **Log em segundo plano (independe da tela).** Com a Tinta aberto, o log é gravado a cada 60 s **qualquer que
  seja a tela** (outro app, lançador, organizador, outra página da Home) e com o Bateria fora da Home e da página
  de repouso: o app declara no manifesto `background(ctx, now, kind)`, e o `tick` do host chama essa função de
  todo app que a declara (11.8). A regra é a mesma (`should_log`: mudou o % ou a carga, ou 10 min; mesmo corte),
  então o refresh do widget/tela no mesmo minuto não grava de novo (deduplica pela última amostra). O hook só
  grava a leitura: estimativa, cache e notificações continuam no refresh. **Tinta fechado: nada é gravado** (como
  antes).
- **Coluna `ev` (9ª, acrescentada ao fim).** `unix_time,percent,charging,wifi,mv,ma,mah,temp_c,ev`. Ausente nas
  linhas normais (8 colunas, iguais às de antes); linhas antigas e a importação do log do plugin velho continuam
  valendo (o cabeçalho antigo é reescrito uma vez, sem mexer nas linhas). Valores: `1` = última amostra antes de
  suspender (ao entrar em repouso), `2` = última amostra de um despertar programado, antes de voltar a dormir,
  `3` = primeira amostra depois do despertar pelo botão. Linhas com `ev` são gravadas mesmo sem mudança de %
  (o marcador é o ponto), exceto duas iguais no mesmo segundo.
- **Uma linha por despertar.** O refresh do Bateria (sem marcador) e o hook (`ev` 2) caem no mesmo segundo num
  despertar programado. `Store:sample` com `ev` troca no lugar (reescreve a última linha do arquivo) a amostra sem
  marcador gravada até `DEDUP_S` (5 s) antes com o mesmo estado de carga; uma amostra sem marcador logo depois de
  uma marcada é descartada. Amostras com marcadores diferentes, ou separadas por mais de 5 s (a de 60 s e a entrada
  em repouso), continuam linhas distintas. Uma linha antiga que não pode ser trocada (arquivo de 4 colunas) é
  acrescentada normalmente.
- Estimativa e trechos: o "trecho sem lacuna" (`logic.segments`) agora **também corta depois de uma amostra `ev` 1
  ou 2**, porque despertares de 15 min deixam buracos menores que `GAP_MAX` (25 min) e o consumo suspenso
  (~1 %/h) passaria por consumo acordado. Um trecho que termina num marcador de suspensão nunca é "ao vivo" nem
  entra na corrente média; logo depois de acordar a estimativa usa o último trecho acordado ("salvo") até haver
  dados novos.
- Estimativa **acordado** (`logic.estimate`): a do plugin atual (regressão sobre o trecho sem lacuna; trecho
  anterior calibra), com troca para o contador de carga (`charge_now`, mAh) quando disponível (senão a estimativa
  usa a porcentagem). Responde "quanto dura com a tela e o Wi-Fi ligados" (~55 mA no KT3), não o que o usuário vive.
- Estimativa **no ritmo atual** (`logic.estimate_mix`, só descarregando): a carga perdida (mAh quando o medidor
  expõe; senão %) sobre o **tempo real**, dormindo incluído, desde a última carga, olhando no máximo
  `MIX_WINDOW` (24 h) para trás; o resto da carga dividido por esse ritmo. A janela começa depois da última linha
  carregando ou da última subida da carga (recarga que o log não viu, reinício do medidor) e só vale com
  `MIX_MIN_SPAN` (3 h) e queda mínima (`MIX_MIN_MAH` 15 mAh, ou `MIX_MIN_PCT` 3 % sem mAh); senão cai na estimativa
  acordado. Limite de `MIX_MAX_ETA` (90 dias).
- **Qual aparece onde.** O número principal (`cache.eta`: barra de status via `Host.battery_eta`, widgets,
  página de repouso, notificação de bateria baixa, primeira linha da tela) é o ritmo atual quando existe, senão o
  acordado. A tela mostra as duas, rotuladas. O cache guarda `eta`, `eta_mix`, `eta_awake`, `ma_mix` e `mix_basis`;
  a corrente média usa a do ritmo atual quando ele é o principal. Durações a partir de 48 h saem em dias (`~5 d` /
  `~5 days`, `eta_days`), as outras em `~4h20` / `~12h` / `~25min`.
- Widgets: 2×2, 4×2 (com gráfico pequeno), 1×1 (porcentagem). No 1×1 (~78 px úteis) o número é só "NN%"
  (fonte menor em "100%"), sem o glifo ⚡ (que estourava a largura e mostrava "…"); carregando é indicado por
  um "+" ao lado do desenho da bateria. Nos outros tamanhos o ⚡ continua no número.
- Notificações: 8.6.

### 10.4 Notificações (app do sistema)

Widget 2×2 ("N novas", título da mais recente), 4×2 (2 mais recentes), 4×4 (5 mais recentes). Tocar abre a
central. Sem refresh próprio.

### 10.5 Sistema

Telas (em paisagem, as listas viram duas colunas):

| Tela | Conteúdo |
|---|---|
| Sistema | Wi-Fi (ligar/desligar), Organizar, Notificações, Atualizações, Repouso, Conexões, Tela e navegação, Apps (configurações de cada app, 5.5; ativar, desativar e remover, R-M1..R-M4), Dados, Sair para o KOReader |
| Notificações | preferência por app (alta/normal/desligada) com os tipos de evento; aviso no topo (ligado/desligado); na tela de repouso (só alta/todas/nenhuma) |
| Atualizações | por app: intervalo (toque abre o popup de escolha, 6.10), próxima atualização, horário; silêncio noturno |
| Repouso | **Quando dormir:** "Dormir sozinho" (modo: sempre / só na bateria / nunca; padrão "só na bateria"; toque abre o popup, 6.10; sub "com ou sem o cabo ligado", "não dorme com o cabo ligado" ou "não dorme sozinho"), "Depois de" (N min sem tocar na tela: 2 / 5 / 10 / 15; toque abre o popup; **some** com o modo "nunca") e "Dormir agora" (o botão de energia acorda). **Enquanto dorme:** "Atualizar a tela" (liga o Wi-Fi, atualiza e volta a dormir: a cada 15 min / 30 min / 1 h / 2 h / pelo horário / nunca; toque abre o popup) e "O que aparece na tela" (N widgets, abre o organizador na aba Repouso). Só com "pelo horário", abaixo de "Atualizar a tela", entra um texto recuado e não tocável com as faixas fixas (11.4). |
| Conexões | por servidor: nome, endereço, "ok há N · latência" ou "sem resposta desde HH:MM · último ok há N" (invertido); Wi-Fi com o IP do Kindle |
| Tela e navegação | navegação (barra + gestos / só gestos), orientação, refresh completo a cada 10 |
| Apps | **todas** as apps: carregadas (nome, nº de configurações), desativadas e as que precisam de uma Tinta mais novo (linha tracejada); "Apps removidas (N)" quando houver. Tocar abre a tela da app: **Estado** "Ativada / Desativada" (toque alterna; Notificações e Sistema: "app do sistema: não pode ser desativada"), intervalo e configurações (5.5) quando carregada, e **Remover app** (confirmação "Remover <app>?"; some nas apps de sistema); app que precisa de versão mais nova mostra o que pede ("pede a API N; esta Tinta tem a API M" / "pede a Tinta X ou mais novo; este é o Y") em vez do Estado. Regras em R-M1..R-M4. |
| Dados | tamanho do banco, contagens (notificações, amostras), "Log da Tinta" (abre a tela de log: últimas linhas, paginado), "Exportar diagnóstico", "Backup das configurações" e "Restaurar backup" (abre a lista de backups) |

**Dados: diagnóstico e backup (onda B).** Três ações, todas escrevem ou leem em `koreader/` e nunca levam segredos (14).
- **Exportar diagnóstico** grava `tinta-diagnostico-AAAAMMDD-HHMM.txt` (menos de 256 KB): versão da Tinta, versão da API
  (1 enquanto o registro não declara uma), versão do KOReader (git-rev), modelo e backend do aparelho, tamanho, dpi e escala
  da tela, apps com versão e estado (ligada/desligada), configurações (cada segredo aparece como `<redacted>`), o log da Tinta
  (últimas 500 linhas), as últimas 100 de `tinta-power.log`, as últimas 200 de `tinta-battery.csv` e as últimas 200 linhas de
  `crash.log` que citam "Tinta" ou um traceback. Cada linha de texto ainda passa por `Settings.redact_text` (credenciais em URL,
  `token=`, `password=`, Bearer/Basic). Se passar do limite, as linhas mais antigas de cada seção saem ("N older lines left out").
  O aviso mostra o nome do arquivo.
- **Backup das configurações** grava `tinta-backup-AAAAMMDD-HHMM.json`: `format`, `format_version` (1), versões, os layouts
  `home` e `sleep` (só os que o usuário salvou), as configurações da Tinta e, por app, `version` e `settings`. Ficam de fora:
  campos do tipo token, chaves com token/password/secret/api_key no nome, URLs com `usuário:senha@`, dados das apps, cache e
  notificações.
- **Restaurar backup** lista `tinta-backup-*.json` de `koreader/` (o mais novo primeiro, com a data do nome); tocar em um pede
  confirmação. O arquivo é validado (JSON, `format`, `format_version` não maior que a da Tinta, tipos); as configurações entram
  pelos mesmos setters validados do resto da Tinta (`set_tinta`, `set_field`, `set_interval`...): chave desconhecida é ignorada,
  valor inválido é pulado e contado ("Restaurado · N aplicados, M inválidos pulados"). O backup de uma app com `version` maior
  que a instalada é pulado. Os tokens atuais nunca são tocados. Layouts: itens inválidos saem; um layout todo inválido não
  apaga o atual. Depois o idioma, a orientação e as telas são refeitos a partir das configurações.

**Repouso.** A tela antiga misturava duas opções que decidiam a mesma coisa ("Acordar
para atualizar" e "Agenda por horário", e a agenda anulava a primeira em silêncio), a agenda parecia mandar o
Kindle dormir, "Entrar sozinho" não dizia entrar em quê e as três faixas pareciam linhas tocáveis. Agora há
uma só opção, `wake` (configuração da Tinta): `900`, `1800`, `3600` ou `7200` (segundos entre despertares),
`"schedule"` (padrão: as faixas de 11.4) ou `"never"`. As chaves antigas `wake_every` e `sleep_schedule` migram
uma vez ao abrir (agenda ligada → `"schedule"`; senão o intervalo mais próximo; 0/desligado → `"never"`).
Rótulos (pt): QUANDO DORMIR · Dormir sozinho "sempre / só na bateria / nunca" · Depois de "sem tocar na tela" · Dormir agora "o botão de
energia acorda" · ENQUANTO DORME · Atualizar a tela "liga o Wi-Fi, atualiza e volta a dormir" · O que aparece na
tela "N widgets · editar no organizador". A linha de Repouso na tela Sistema mostra "dorme sozinho: N min ·
atualiza: <opção>" ("nunca" no lugar de N min com o modo "nunca").

**Dormir sozinho (modo).** Configuração da Tinta `idle_mode`: `"always"` (sempre), `"battery"` (padrão, "só na
bateria": não dorme sozinho com o Kindle ligado ao USB/carregador) ou `"never"`; os minutos são a configuração
separada `idle_sleep` (2, 5, 10 ou 15; padrão 5; sem 0: "nunca" é o modo). Migração, uma vez ao abrir: `idle_sleep`
antigo 0 → modo `"never"` e minutos de volta ao padrão 5; qualquer outro valor antigo → modo `"always"` com aquele
valor (o usuário o escolheu antes de existir a opção); nunca salvo → padrões. O modo é gravado explicitamente na
primeira vez, então a migração não roda de novo. O antigo "modo expediente" (configuração `expediente`) foi
removido, e o valor guardado é apagado na mesma migração; "só na bateria" cobre o uso na mesa.

Sistema e as apps Relógio e Repouso (10.6, 10.7) não têm `refresh` periódico; o widget 1×1 do Sistema é só o ícone, o 2×2 mostra o estado do Wi-Fi.

### 10.6 Relógio (app do sistema)

Só widget (sem rede, sem intervalo): a hora é redesenhada a cada minuto pelo tick do núcleo. Configuração da
app "Estilo" (Sistema → Apps → Relógio, ou tocando no widget):

| Estilo | Conteúdo |
|---|---|
| Digital grande | HH:MM no maior tamanho que cabe |
| Digital com data | HH:MM e a data por extenso: "sexta, 16 de outubro" (en: "Friday, October 16"); em widgets estreitos (2×2, 2×4) o dia da semana e "16 de outubro" em duas linhas |
| Analógico | mostrador preto e branco (anel, 12 marcas, ponteiros de hora e minuto, sem serrilhado suavizado), desenhado com `ui/shapes`; 4×2: mostrador à esquerda e HH:MM à direita; 2×4 e 4×4: mostrador em cima e HH:MM embaixo; 2×2: só o mostrador |
| Mínimo | HH:MM; com o aparelho em repouso, abaixo "próximo despertar HH:MM" (ou "<dia> HH:MM" se não for hoje; "sem despertar agendado") |

Tamanhos: 2×2, 4×2, 4×4, 2×4 e 1×1; o 1×1 é sempre HH:MM, qualquer que seja o estilo. Serve como widget da
página de repouso. Tocar abre a tela do Relógio: pré-visualização (4×2) do estilo atual e a lista de estilos
(toque escolhe; o escolhido fica invertido). Sem notificações.

### 10.7 Repouso (app do sistema)

Widget para controlar o sono sem abrir o Sistema; muda as mesmas configurações da Tinta que Sistema → Repouso
(`idle_mode`, `idle_sleep`), sem estado próprio. Sem rede, sem intervalo, sem notificações.

- **2×2:** título, "sozinho: sempre / bateria / nunca" e "depois de: N min" ("–" com o modo nunca). Sem botões
  dentro: tocar abre a tela com as ações (Dormir sozinho, Depois de, Dormir agora), iguais às linhas de
  Sistema → Repouso (o "Depois de" some com o modo nunca).
- **4×2:** três botões de 64 px: o primeiro mostra os minutos e cicla 2/5/10/15 (mostra "–" e não faz nada com o
  modo nunca); o segundo é o modo e cicla sempre / bateria / nunca (invertido = dorme sozinho); "Dormir" dorme
  agora. Os botões são o alvo mais interno; tocar fora deles (título) abre a tela.
- **1×1:** um botão "Dormir agora"; pede confirmação antes (um toque perdido num 1×1 não apaga a tela).

### 10.6 Timer

App local, sem rede (`apps/timer`). Contagem regressiva com pomodoro:

- Presets: `25/5` (pomodoro: foco de 25 min e pausa de 5, ajustáveis nas configurações), 15, 10, 5 min e **Outro…**
  (teclado numérico, 1 a 600 min, o último valor fica salvo). A tela mostra o preset escolhido (invertido),
  **Iniciar**; em andamento mostra **Pausar** / **Retomar** e **Zerar**. Resolução de **minuto**: o tempo restante
  aparece como `12 min`, `1 h 05`, `< 1 min`; nada se redesenha por segundo (o relógio de 1 min da Tinta basta).
- Estado em `ctx.data` (`state`: modo, tipo foco/pausa, `end_at` absoluto ou `left` quando pausado) e lido uma vez
  no `init`: fechar e abrir a Tinta não perde o timer; se o fim passou com a Tinta fechado, a primeira atualização
  depois de abrir avisa (a primeira leitura da sessão só arma as notificações, 8.6, então o aviso vem da segunda,
  que o host dispara em 1 s porque o pedido de despertar já está no passado).
- Ao terminar: notificação **"Tempo esgotado"** (`ctx.notify`, prio **alta**, chave `timer:<end_at>`; a preferência
  alta/normal/desligada é a do Sistema → Notificações, 8.2, e o banner a mostra) e, no pomodoro com
  "Pausa automática após o foco" ligada (padrão), a pausa começa na hora (outra notificação ao fim dela).
- **Dormindo**: o timer pede `ctx.wake_at(end_at)` (11.7). O aparelho acorda por RTC nesse horário se ele vier antes
  do próximo despertar da agenda; no despertar o timer roda no lote, notifica e a página de repouso é redesenhada
  com a faixa de notificações (R-T11, conforme "Mostrar no repouso").
- Widgets: 2×2 e 4×2 (nome, tempo restante, `até HH:MM` ou `pausado`; em repouso `pomodoro 25/5`), 1×1 (minutos
  restantes ou ▶). Toque abre a tela.
- Configurações (manifesto, validadas, 5.5): foco (1–180), pausa (1–60), pausa automática, último tempo
  personalizado (1–600). Intervalo de atualização padrão 5 min (só rede de segurança; o fim é pontual pelo pedido de
  despertar).
- Notificações: `done` ("tempo esgotado").

### 10.7 Nota rápida

App local, sem rede (`apps/nota`): um post-it digitado com o teclado do KOReader (`ctx.input`, 11.7/CORE_CALLS).

- Uma nota na v1 (até 500 caracteres por padrão; configurável de 50 a 2000). O texto fica em `ctx.data` (`text`),
  lido uma vez no `init`, e **nunca** vai para o log nem para notificação.
- Widgets 2×2, 4×2, 2×4 e 4×4: título "Nota" e o texto quebrado em linhas, cortado com "…" ao fim da caixa (R-W1);
  vazio mostra "toque para escrever". Toque abre a tela.
- Tela: o texto num quadro (toque também edita), contagem de caracteres, **Editar** (ou **Escrever**) e **Limpar**
  (com confirmação 6.9). O editor é multilinha; texto acima do máximo é recusado com a contagem, sem perder o que
  foi digitado.
- Configurações: tamanho máximo, "Letra maior".

### 10.8 Contagem regressiva

App local, sem rede (`apps/contagem`): "faltam N dias para <nome>" até uma data.

- Até **3** contagens (nome de até 40 caracteres + data `AAAA-MM-DD`, validada: mês, dia e ano bissexto). Depois da
  data mostra `há N dias`; no dia, `hoje`. Os dias contam o **calendário local** (só a data local de `now` é lida;
  sem aritmética de fuso nem de horário de verão), puro e testado em virada de mês, de ano, ano bissexto e UTC-3.
- Tela: uma linha por contagem (`faltam 70 dias para Férias`, data ao lado), toque edita; **Nova** abre o editor
  (Nome, Data, **Salvar**, **Apagar** com confirmação). Os campos usam `ctx.input` e recusam entrada inválida com o
  motivo no aviso.
- Widgets: 2×2 e 4×2 (a contagem mais próxima, ou a mais recente se todas passaram; o 4×2 lista as outras),
  1×1 (só N; `hoje`; `-N` depois da data).
- Notificação no dia (`hoje`, prio alta, uma vez por contagem: a chave leva a data), ligada por "Avisar no dia".
  A atualização é de hora em hora; `done(true)` vem antes do aviso para a primeira da sessão já estar armada.
- Dados: lista em `ctx.data` (`items`), lida uma vez no `init`.

## 11. Energia e repouso

Esta seção tem quatro partes: **comum** (11.1 a 11.4, 11.7, 11.8: regras valem em qualquer aparelho), **Kindle**
(11.5: o que foi medido no KT3), **Kobo (experimental)** (11.9) e **outros aparelhos** (11.10).

### 11.1 Princípio (comum)

- **R-P1.** Só o núcleo liga e desliga o Wi-Fi, suspende o aparelho e programa o despertar (`device/net.lua`,
  `device/sleep.lua`). Apps pedem dados; nunca mexem na energia.
- **R-P1a. Backends.** Tudo o que depende do aparelho fica atrás de um backend pequeno em `device/backends/`
  (`kindle.lua`, `kobo.lua`, `generic.lua`, mais `gauge.lua` e `driven.lua` de apoio), escolhido uma vez no
  `Sleep.attach` / na primeira leitura de bateria por `device/backends.lua` a partir do `Device` do KOReader (um
  `Device` sem `isKindle`, que só existe em simulações, vale Kindle). `device/sleep.lua` guarda o que é comum (página
  de repouso, Wi-Fi, lote do despertar, botão, log, API `attach/detach/enter/active/earliest`) e delega o resto ao
  backend: `attach`, `detach`, `stop`, `suspend`, `state`, `restore`, `retarget`, `batch_done`, `charge`,
  `can_wake`, `wifi_timeout`. `device/battery.lua` é uma fachada (`read`, `plugged`, `parse`, `DIR`, `FILES`) sobre
  `battery_read` / `battery_plugged` do backend. O código do Kindle foi **movido**, não reescrito: as suítes
  `sleep` e `bateria` passam sem alteração contra ele. Aparelho sem despertar por relógio (`can_wake = false`) não
  tem alvo de despertar (a página mostra "próxima: nunca").

### 11.2 Wi-Fi

- **R-P2.** Com a Tinta acordado, o Wi-Fi segue o que o usuário escolheu (ligado/desligado).
- **R-P3.** No despertar do repouso: liga o Wi-Fi, espera a conexão (limite de 30 s, ou o do backend se for maior:
  60 s no Kobo), atualiza o lote, desliga o
  Wi-Fi, redesenha, dorme. Se a conexão não vier, redesenha com o dado velho e dorme.

### 11.3 Modo repouso

- **R-P4.** Entradas: "Dormir agora" (Sistema, central, menu) e o automático depois de N minutos sem toque na
  tela (padrão 5; com um campo de texto aberto não conta, o teclado não é toque). O modo `idle_mode` (10.5) decide
  se o automático dispara: "sempre" (com ou sem cabo), "só na bateria" (padrão: só com o Kindle **fora** do USB/
  carregador) ou "nunca". "Plugado" é lido sem processo extra (`device/battery.lua`, `plugged`): os arquivos
  `status`/`charging` do medidor (`Charging` ou `Full` contam, então bateria cheia no cabo continua plugada) ou o
  `isCharging()` do KOReader (propriedade lipc do powerd, a mesma dos eventos Charging/NotCharging); qualquer um
  dizendo "sim" basta, e uma leitura que falha vale "não plugado". Limite: um carregador que alimenta o Kindle sem
  que nenhuma das duas fontes o perceba conta como bateria. A verificação é a mesma do tick de 5 s: o estado
  plugado só é consultado depois que o tempo de inatividade venceu, e só no modo "só na bateria". "Dormir agora" nunca é bloqueado. A agenda por horário
  **não** faz o Kindle dormir: só decide de quanto em quanto tempo ele acorda para atualizar (11.4).
- **R-P5.** Ao entrar: fecha menus, diálogos e campos de texto, desenha a página de repouso (layout "Repouso",
  sem interação, sem barra de navegação, rodapé "Em repouso. Aperte o botão de energia para usar a Tinta.",
  barra de status "Repouso · atualizado HH:MM · próxima HH:MM"), faz refresh completo, espera ~2 s para o
  e-ink terminar, desliga o Wi-Fi, aplica R-P9, programa o despertar (R-P10) e suspende. A tela de descanso do
  próprio KOReader nunca é desenhada por cima (`intoScreenSaver` fica embrulhado enquanto a Tinta dorme).
- **R-P6.** Despertar pelo relógio: liga o Wi-Fi (só se alguma app da página de repouso precisa de rede), espera
  a conexão (30 s), atualiza as apps da página de repouso (`Scheduler.wake`: horário e silêncio da app valem,
  intervalo não), desliga o Wi-Fi, redesenha a página (refresh completo) e deixa o `powerd` suspender de novo
  sozinho; a Tinta pede o próximo despertar no próximo `readyToSuspend` (R-P10). Não acende interação.
- **R-P7.** Botão de energia: acorda para uso normal, na tela em que estava antes do repouso (a pilha de telas
  não é mexida), com `preventScreenSaver` de volta a 1 (R-P9), o Wi-Fi como estava antes de dormir (R-P2) e o
  relógio de inatividade zerado.
- **R-P8.** Toque em repouso não faz nada (o touch está desligado em suspend; a janela também ignora).
- **R-P13.** Se o `powerd` continuar `active` 25 s depois do botão por software (carregando no USB, `lipc`
  indisponível), a Tinta desiste: volta ao uso normal em vez de ficar numa página de repouso que ignora toques.

### 11.4 Atualizar a tela durante o repouso

A opção "Atualizar a tela" (`wake`) decide de quanto em quanto tempo o aparelho acorda para atualizar:

| Opção | Despertar |
|---|---|
| a cada 15 min / 30 min / 1 h / 2 h (`900`/`1800`/`3600`/`7200`) | `agora + N`, a qualquer hora |
| pelo horário (`"schedule"`, padrão) | conforme as faixas abaixo |
| nunca (`"never"`) | não acorda para atualizar (só o botão e o despertar diário do `powerd`) |

Faixas de "pelo horário" (fixas na v1; não há tela para editar):

| Faixa | Despertar |
|---|---|
| Dias úteis 07:30–18:30 | a cada 30 min |
| 18:30–23:00 | a cada 60 min |
| 23:00–07:30 | não acorda (tela fixa) |

Fora de dias úteis, o horário de 07:30–18:30 usa 60 min. Um despertar que cairia numa faixa que não acorda
vira o primeiro minuto da próxima faixa que acorda (a noite é um sono só). Na tela, esse texto só aparece com
"pelo horário", recuado, menor e não tocável, com "(horários fixos nesta versão)".

Modo de medição (teste no aparelho): se existir o arquivo `koreader/tinta-wake-test` com um número de segundos
(mínimo 60), todo despertar programado passa a ser a cada N segundos, em qualquer opção. A Tinta anota cada
entrada em repouso e cada despertar, com `charge_now`, em `koreader/tinta-power.log`).

### 11.5 Kindle: suspender e despertar no KT3 (testado no KT3)

Código em `device/backends/kindle.lua` (movido de `device/sleep.lua` e `device/battery.lua`, sem mudança de comportamento).

**Funciona**, com cuidados. Resultado do teste: o aparelho suspendeu, acordou sozinho 90 s depois pelo relógio e
voltou para a tela normal. Como o KOReader faz isso no Kindle: `WakeupMgr` com um RTC simulado
(`frontend/device/kindle/mockrtc.lua`); o alarme de verdade é pedido ao `powerd` pela propriedade `rtcWakeup`
(`frontend/device/kindle/powerd.lua`, `setRtcWakeup`), que só é aceita no estado `readyToSuspend`. Só é ativado
em aparelho sem anúncios (`supportsScreensaver`); o KT3 do usuário não tem anúncios.

Sequência do `powerd` (log em `/var/log/messages`): `active` → botão → `screenSaver` (~60 s) → `readyToSuspend`
(o evento traz 10 s, mas durou 50–54 s nos testes) → `handle_suspend: setting rtc wakeup time` → suspenso.

- **R-P9. Bloqueio de tela de descanso.** O aparelho estava com `preventScreenSaver=1` (é o que o plugin
  "Keep alive" do KOReader faz). Com ele, `powerButton` não faz nada e o aparelho nunca suspende. Para entrar em
  repouso, o núcleo faz `lipc-set-prop com.lab126.powerd preventScreenSaver 0` e depois aperta o botão por
  software (`lipc-set-prop -i com.lab126.powerd powerButton 1`, o mesmo que `powerd:toggleSuspend()`). Ao voltar
  ao uso normal, restaura o valor que estava antes (ler com `lipc-get-prop com.lab126.powerd preventScreenSaver`).
  Com a Tinta aberto e acordado, a Tinta mantém `preventScreenSaver=1` para o Kindle não dormir sozinho
  (o "acordado" de R-P2 é decisão da Tinta, não do `powerd`).
- **R-P10. Pedir o despertar mais de uma vez.** Pedir `rtcWakeup` só uma vez, no início de `readyToSuspend`, foi
  **ignorado** no primeiro teste: o `powerd` programou o despertar diário dele (06:10). Pedir de novo a cada 2 s
  enquanto o estado for `readyToSuspend`, sempre com os segundos que faltam até o mesmo horário alvo, funcionou.
  O despertar veio ~6 s antes do alvo (o `powerd` usou o último pedido). O `WakeupMgr` do KOReader só pede uma
  vez (`KindlePowerD:readyToSuspend`), então a Tinta faz os pedidos repetidos ele mesmo em `device/sleep.lua`
  (com `UIManager:scheduleIn`, ou `lipc` direto), sem depender só do `WakeupMgr`.
- **R-P11. Depois do despertar** o `powerd` fica em `screenSaver` e volta a suspender sozinho. O KOReader
  recebe `WakeupFromSuspend` e, 15 s depois, `checkUnexpectedWakeup` distingue despertar programado (estado ainda
  `screenSaver`/`suspended`) de botão (estado `active`). O motivo também aparece em `/var/log/messages`
  (`POWERD_WAKEUP_REASON_POWER_BUTTON` no botão). Para R-P6: no despertar programado, a Tinta atualiza e redesenha
  a página de repouso enquanto o `powerd` está em `screenSaver`, pede o próximo despertar no próximo
  `readyToSuspend` (R-P10) e não muda o estado. Para R-P7: no despertar pelo botão, restaura R-P9 e volta à tela.
- **R-P12. O `powerd` acorda o aparelho todo dia às 06:10** (motivo dele, "unscheduled wakeup" no `crash.log`).
  A Tinta trata isso como despertar não programado: se estiver em repouso, só volta a dormir.
- **Ainda não testado no aparelho:** Wi-Fi ligar e conectar dentro do despertar programado (R-P3), com o
  framework em `screenSaver`; e o comportamento com o KOReader aberto em "no framework". Teste os dois
  primeiro. Se o Wi-Fi não conectar no despertar, o repouso vira "suspender com a página desenhada": sem
  atualização automática; os dados atualizam quando o botão acordar o aparelho, e a agenda some da interface.


### 11.8 Amostras da bateria ao dormir e acordar

- **R-P13.** Os pontos de `device/sleep.lua` chamam `Host:background(kind)`, que chama o `background(ctx, now, kind)`
  de cada app que o declara (hoje só o Bateria), com o Bateria estando ou não na página de repouso: ao entrar em
  repouso, logo depois de `beforeSleep` e antes do Wi-Fi desligar/suspender (`kind = "sleep"`); ao fim de cada
  despertar programado, depois do lote e do Wi-Fi desligado, antes de voltar a dormir (`"sched"`; no modo
  awake-usb, que não suspende, uma amostra forçada sem marcador); e no despertar pelo botão, antes de voltar à tela
  (`"button"`). Uma amostra por ponto (e uma linha por despertar: o refresh do mesmo instante é absorvido, 10.3); uma falha no hook nunca impede dormir ou acordar. Despertares não
  programados (R-P12) não gravam. As linhas saem marcadas (`ev`, 10.3) para reconhecer os trechos suspensos no CSV.
- Tinta fechado: nada (a Tinta não roda).

### 11.7 Pedido de despertar (`ctx.wake_at`)

Uma app pode pedir que a Tinta esteja acordado numa hora (o Timer, no fim da contagem): `ctx.wake_at(ts)`;
`ctx.wake_at(nil)` cancela. Um pedido por app (pedir de novo substitui) e vale uma vez.

- **Acordado**: o host agenda um timer do `UIManager` para o pedido mais próximo; ao disparar atualiza a app
  (`refresh`, como atualização automática) e consome o pedido.
- **Dormindo**: `device/sleep.lua` calcula o alvo do RTC como **o menor entre o despertar da agenda (11.4) e o
  pedido mais próximo** (`Host:nextWakeRequest(from)`; também vale com "Atualizar a tela: nunca" e no modo de
  medição). A bomba do R-P10 segue pedindo `rtcWakeup` com os segundos que faltam para esse alvo fixo. No despertar
  o `wakePlan` inclui no lote as apps com pedido vencido (folga de 30 s para o arredondamento do RTC), mesmo fora do
  layout do repouso ou em horário silencioso, consome o pedido, e o alvo seguinte volta a ser o da agenda (ou o
  próximo pedido). Wi-Fi só sobe se alguma app do lote usa rede.
- **Cabo USB (sem suspensão)**: com o cabo ligado o powerd fica em `screenSaver` e nunca chega a `readyToSuspend`
  (medido: 22 min sem suspender nem despertar por RTC). Depois de 90 s em `screenSaver`
  (`Sleep.USB_WAIT_S`) o `device/sleep.lua` passa ao modo **awake-usb** (`sleep mode=awake-usb` no
  `tinta-power.log`): o mesmo alvo (agenda ou pedido, o que vier antes) é servido por um timer do `UIManager`, que roda
  o mesmo lote (Wi-Fi, atualizar as apps do repouso, redesenhar a página com a faixa, Wi-Fi desligado) sem
  suspender. Se o powerd chegar a `readyToSuspend` (cabo removido), volta a bomba de RTC (`sleep mode=rtc`).
  O botão de energia continua acordando a Tinta.
- Os pedidos vivem na memória do host (`device/wakereq.lua`, puro): fechar a Tinta os apaga, e cada app refaz o
  seu no `init` a partir dos dados que persistiu (o Timer relê `end_at`).
- Também na mesma leva ao `ctx`: `ctx.input(title, value, hint, on_save, opts)` (teclado do KOReader; `on_save(text)`
  devolve `true` ou `false, mensagem`; `opts.number`, `opts.multiline`), `ctx.redraw()` e `ctx.back()`.

### 11.9 Kobo (experimental, sem teste em aparelho)

**Nada desta parte foi testado em um Kobo** (o usuário não tem um). Foi escrita a partir das fontes do KOReader
v2025.04 (`frontend/device/kobo/device.lua`, `powerd.lua`, `frontend/device/wakeupmgr.lua`,
`plugins/autosuspend.koplugin`, `frontend/device/generic/device.lua`) e exercitada só contra simulações delas
(`tests/test_sleep_driven.lua`). Código em `device/backends/kobo.lua` + `driven.lua`. O Kindle não é afetado.

Diferença central: no Kindle a Tinta faz o trabalho do `powerd`; no Kobo **quem suspende é o KOReader** e a Tinta só
o conduz.

- **R-K1. Suspender.** A Tinta desenha a página de repouso, espera `SETTLE_S`, desliga o Wi-Fi e chama
  `UIManager:suspend()`. Enquanto dorme, `Screensaver:setup` e `show` só ligam `Device.screen_saver_mode` (o que o
  modo "desativado" da tela de descanso faz), então a página não é coberta. O resto é do KOReader: `Kobo:suspend`,
  `state-extended`, `/sys/power/state`, o guarda de despertar inesperado.
- **R-K2. Despertar por relógio.** `Device.wakeup_mgr:addTask(segundos, cb)` com o alvo (agenda ou pedido, 11.7), sobre
  o RTC real `/dev/rtc0`. Em aparelhos `dodgy_rtc` (i.MX5), o `WakeupMgr` encadeia alarmes para alvos além de
  65535 s; a Tinta só chama `addTask` e `removeTasks(nil, cb)`. O alvo é pedido de novo a cada mudança (`retarget`). Depois do alarme, o
  `Kobo:checkUnexpectedWakeup` (15 s depois) roda o `cb` e agenda a suspensão em 30 s; a Tinta espera 1 s, **retira
  essa suspensão** (`UIManager:unschedule(Device.suspend)`) e roda o lote (R-P6); ao fim, `Device:rescheduleSuspend()`
  suspende de novo e o novo alarme já foi pedido. Nunca há suspensão dupla nem suspensão no meio do lote.
- **R-K3. Botão e capa.** O botão de energia e a capa (`SleepCover`) chegam ao KOReader como `Power`/`Suspend`
  (acordado) e `Resume` (dormindo). Acordado, a Tinta intercepta `Device:onPowerEvent` e dorme à moda da Tinta
  (página de repouso, alvo); se a Tinta recusar, o KOReader segue o caminho normal. Dormindo, `Device:resume`
  embrulhado é o "despertar pelo botão" (R-P7); o despertar por relógio nunca chama `resume`.
- **R-K4. Autosuspend.** Com a Tinta aberto, `PluginShare.pause_auto_suspend = true` (valor anterior restaurado ao
  fechar). Sem isso o plugin `autosuspend` suspenderia o aparelho com a tela de descanso do KOReader por cima, sem
  alvo de despertar (suspensão dupla). Efeito colateral: o desligamento automático do plugin também fica em pausa
  enquanto a Tinta está aberto.
- **R-K5. USB.** A Tinta não mexe nos eventos `UsbPlugIn`/`UsbPlugOut`/`Charging`/`NotCharging`. Acordado, o KOReader
  pode mostrar o pedido de USBMS por cima da Tinta; o modo "só na bateria" (R-P4) não dorme com o cabo (o
  `powerd:isCharging()` do Kobo vale "plugado", inclusive cheio no cabo). Dormindo, o plug acorda o kernel e o KOReader
  manda `Suspend` de novo (a Tinta deixa passar). No MTK o KOReader recusa suspender plugado (o próprio
  `Kobo:suspend` adia); a Tinta não tem o modo awake-usb do Kindle nesse aparelho.
- **R-K6. Bateria.** `KoboPowerD` (`capacity`, `status`): só % e carregando. O contador de carga do sysfs **não é
  lido** (o nó muda entre kernels: `mc13892_bat`, `bd71827_bat`, `battery`), então a estimativa do Bateria usa o %
  (sem mAh). Wi-Fi pelo `NetworkMgr` (`enableWifi`/`disableWifi`/`isConnected`); o limite do despertar é
  60 s (parâmetro do backend), pois ligar e obter IP num Kobo demora mais.
- **A verificar quando houver um Kobo:** cada item acima. Riscos: o intercept de `onPowerEvent` brigar com um plugin
  de gestos que também o use; `wakeupAction(30)` falhar por jitter do RTC (a Tinta então só vê um despertar
  inesperado e o KOReader volta a dormir; o lote daquele ciclo se perde); a retirada da suspensão do KOReader em
  `unschedule(Device.suspend)` depender de a referência ser a mesma função (é, na v2025.04).

### 11.10 Outros aparelhos (genérico, sem teste)

Qualquer aparelho que não seja Kindle nem Kobo (emulador, Android, Cervantes, PocketBook...). `device/backends/generic.lua`:

- **Sem despertar por relógio.** Repouso = desenhar a página de repouso e deixar o KOReader suspender (mesmo
  caminho de R-K1 e R-K3, sem `WakeupMgr`). Não há alvo: a página mostra "próxima: nunca" e só o botão de energia
  acorda a Tinta. O autosuspend fica em pausa como no Kobo (R-K4).
- **Aparelho que não suspende** (`Device:canSuspend()` falso, como o emulador): a Tinta desiste e volta à tela
  (como R-P13).
- **Bateria:** `powerd` do KOReader (`getCapacity`, `isCharging`), estimativa pelo %. "Plugado": `isCharging()`.

## 12. Banco de dados

SQLite em `koreader/tinta.sqlite3` (pasta de dados do KOReader, `DataStorage:getDataDir()`).

```sql
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);                 -- schema_version, criado em
CREATE TABLE settings (scope TEXT, key TEXT, value TEXT, PRIMARY KEY (scope, key));   -- scope = 'portal' ou id da app; value em JSON
CREATE TABLE layout (page TEXT, pos INTEGER, app TEXT, size TEXT, hidden INTEGER, PRIMARY KEY (page, pos));  -- page = 'home' | 'sleep'
CREATE TABLE app_data (app TEXT, key TEXT, value TEXT, PRIMARY KEY (app, key));
CREATE TABLE app_cache (app TEXT PRIMARY KEY, value TEXT, fetched_at INTEGER, version INTEGER);
CREATE TABLE app_state (app TEXT PRIMARY KEY, last_ok INTEGER, last_err INTEGER, err_text TEXT, fail_streak INTEGER);
CREATE TABLE notifications (
  id INTEGER PRIMARY KEY, app TEXT, key TEXT, type TEXT, title TEXT, body TEXT, prio TEXT, route TEXT,
  created_at INTEGER, read_at INTEGER, UNIQUE (app, key));
CREATE TABLE log (id INTEGER PRIMARY KEY, at INTEGER, app TEXT, level TEXT, msg TEXT);   -- só as 500 últimas
```

- **R-B1.** `store.lua` expõe uma interface pequena (`get/set` por escopo, layout, notificações, cache, estado,
  log) e esconde o SQL. Os testes usam uma implementação em memória com a mesma interface.
- **R-B2.** Escritas em transação por ciclo de atualização (não uma por linha), para gastar menos flash.
- **R-B3.** Migrações numeradas em `store.lua`; `meta.schema_version` diz a atual.
- **R-B4.** Banco corrompido ou ilegível: renomeia para `tinta.sqlite3.bad-<data>`, cria um novo e avisa no log;
  a Tinta abre com o layout padrão.
- **R-B5.** Na primeira abertura, uma app pode importar dados de um plugin antigo (`import_legacy`, uma vez; o núcleo
  guarda a marca `legacy_imported:<id>`).

## 13. Idioma

pt e en, padrão pt (o plugin atual usa en por padrão; a Tinta muda para pt). Núcleo e cada app têm as próprias
tabelas de texto; o teste de i18n do plugin atual (mesmas chaves e mesmos especificadores nos dois idiomas) vale
para todas.

## 14. Segurança e privacidade

- R-A4 (tokens e campos descartados).
- Exportações (10.5, Dados): o diagnóstico e o backup nunca levam tokens, senhas nem URLs com credenciais (campos do tipo
  token, chaves com token/password/secret/api_key no nome, `esquema://usuário:senha@`); o backup também não leva dados das
  apps, cache nem notificações. O log da Tinta, o de energia, o de bateria e o `crash.log` passam por `Settings.redact_text`.
  Os arquivos ficam em `koreader/` e só saem do aparelho quando o usuário os copia.
- Servidores locais de apps costumam não ter autenticação: a Tinta nunca grava a resposta bruta, só os campos usados.
- Página de repouso: o conteúdo de apps sensíveis (como a Nota) não é desenhado por padrão e os títulos das
  notificações podem ser escondidos (8.5, R-V1..R-V3).
- Apps são código Lua que roda no processo do KOReader, com acesso total: instale só apps de quem você confia (sdk.md, seção 13).

## 15. Testes, verificação e deploy

### 15.1 Testes automáticos

- Sem framework: scripts Lua rodados com `luajit` (`scripts/test-all.sh` roda tudo).
- Obrigatórios: `layout` (R-G3), `scheduler` (intervalo, horário, silêncio, agrupamento, manual, sem Wi-Fi),
  `notify` (deduplicação, preferências, limite, não lidas, primeira leitura não notifica), `store` (em memória e
  migrações), `power` (agenda, próximo despertar), `format`, `i18n`, e a lógica de cada app (cada app tem a sua suíte em `apps/<id>/tests/`).
- Interface: só verificação de sintaxe (`luajit -bl`) dos módulos de `ui/` e `main.lua`, como hoje.

### 15.2 Verificação no aparelho (checklist por entrega)

Abrir pelo menu e pelo gesto; todas as telas em retrato e paisagem; Wi-Fi ligado e desligado; servidor desligado
(sem resposta e de volta); notificação de cada app; organizador nas duas abas; repouso (entrar, despertar,
botão de energia); `crash.log` sem erro ao final.

### 15.3 Emulador

O KOReader tem emulador para desktop (`kodev`). Montar é opcional, mas permite ver a interface sem o aparelho.

### 15.4 Deploy

- **Dois lugares para apps (R-M4).** `tinta.koplugin/apps/<id>/` (vêm com o plugin) e
  `<pasta de dados do KOReader>/tinta-apps/<id>/init.lua` (externas; sobrevivem ao deploy do plugin, que troca a pasta
  inteira). Mesmas regras: manifesto, `api`/`min_tinta`, ligar/desligar, remover (apaga só dentro da pasta de onde a app
  foi carregada), ids `[a-z0-9_]+`. Id igual ao de uma app do plugin: a externa é recusada com uma linha no log. Para as
  externas, `core/extapps` instala um carregador de `require("apps/<id>/...")` que aponta para `tinta-apps/<id>/...`.
  `scripts/deploy.sh --app <pasta> [--ssh <ip>]` copia uma pasta de app para `koreader/tinta-apps/<id>/`.
- **Renomeação Portal → Tinta (migração única).** Ao abrir, antes de abrir o banco: se `tinta.sqlite3` não existe e
  `portal.sqlite3` existe, ele é renomeado (junto com `portal-battery.csv` e `portal-power.log`, e os arquivos
  `-journal/-wal/-shm` do banco); nunca por cima de um arquivo novo; uma linha no log
  (`Tinta: renamed from Portal: ...`). Nada mais é apagado. Backups `portal-backup-*.json` (formato `portal-backup`) ainda
  são lidos na restauração.
- **Dois plugins não rodam juntos.** Se `plugins/portal.koplugin` ainda existe ao lado de `plugins/tinta.koplugin`, a Tinta
  **não se registra** (log: `Tinta: plugins/portal.koplugin is still installed; Tinta stays off until it is deleted`) e o
  Portal antigo segue sozinho. Para trocar: instale `tinta.koplugin`, apague `koreader/plugins/portal.koplugin` (pelo USB
  ou por SSH) e reinicie o KOReader.

- USB: `scripts/deploy.sh` copia `tinta.koplugin/` para `<montagem>/koreader/plugins/` (rsync, sem `tests/` e
  arquivos ocultos).
- SSH: `scripts/deploy.sh --ssh <ip>` com `tar` sobre SSH (`tar cf - | ssh ... 'tar xf - -C ...'`; o Kindle
  não tem rsync) e
  `scripts/pull-logs.sh --ssh <ip>` para trazer `crash.log`, o log de bateria e o banco. Com SSH, o KOReader não
  precisa ser fechado para copiar, mas precisa ser reiniciado para carregar o plugin novo.

## Apêndice A. Features do protótipo (todas entram na v1)

Barra de status: 1 relógio (toque atualiza); 2 sino com não lidas; 3 Wi-Fi em três estados; 4 bateria com
estimativa e ⚡ (toque abre Bateria); 5 "atualizado às · próxima às" em repouso.

Navegação: 6 barra Início/Voltar/Atualizar/Menu; 7 modo só gestos com traço; 8 gestos de borda (baixo → Início,
esquerda → Voltar, cima → central); 9 deslizar no meio do Início troca de página; 10 segurar widget →
organizador; 11 Início volta para a primeira página; 12 menu da app.

Início e widgets: 13 grade 6×8 / 8×6; 14 tamanhos 1×1, 2×2, 2×4, 4×2, 4×4 por app; 15 encaixe automático e
reorganização ao girar; 16 páginas; 17 widget invertido quando a app precisa de você; 18 borda tracejada com
dado velho; 19 rodapé com idade/intervalo/estado, curto nos estreitos.

Organizador: 20 abas Início e Repouso; 21 mapa da página; 22 Antes/Depois/Tamanho/Ocultar/Pronto; 23 apps
ocultas ou para adicionar.

Notificações: 24 API `notify`; 25 deduplicação por key; 26 aviso no topo por 5 s; 27 central com atalhos e
lista; 28 marcar todas como lidas e limpar; 29 abrir leva à tela certa; 30 preferência por app; 31 aviso no topo
e repouso configuráveis; 32 widget Notificações.

Regras: 33 e 34 (de apps externas); 35 Bateria (abaixo de 20 %, carga completa); 36 Sistema (servidor fora e de volta).

Atualizações: 37 intervalo por app; 38 horário por app; 39 silêncio noturno; 40 agrupamento em uma conexão; 41
sem Wi-Fi ou servidor fora mantém o último dado; 42 cabeçalho com estado.

Repouso: 43 página de repouso montável; 44 intervalo de despertar; 45 entrada automática; 46 agenda por horário;
47 notificações altas na tela de repouso; 48 botão de energia acorda.

Sistema: 49 Wi-Fi; 50 Conexões; 51 Tela e navegação; 52 Dados; 53 Sair para o KOReader.

Apps: 54 e 55 (apps externas de exemplo); 56 Bateria.

Gerais: 58 confirmação antes de escrever; 59 avisos curtos; 60 retrato e paisagem; 61 refresh completo ao trocar
de tela.
