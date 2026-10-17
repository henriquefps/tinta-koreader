# Plano: Tinta como plataforma distribuível

Estado (2026-10-17). A v1 da Tinta
(tudo o que o protótipo mostra) está implementada e roda no KT3; o que segue é transformá-la numa plataforma open
source que outras pessoas instalam e para a qual criam apps. Arquitetura e regras: [`arquitetura.md`](arquitetura.md); guia das apps: [`sdk.md`](sdk.md).
Protótipo: [`tinta-prototipo.html`](tinta-prototipo.html).

## Ideia

Um plugin do KOReader que vira uma Tinta com várias apps: tela inicial com widgets, notificações, repouso com
despertar pelo relógio. A base fica pronta e cada pessoa monta as próprias apps. É uma plataforma sobre o
KOReader, não um sistema operacional: o KOReader já resolve tela e-ink, toque, Wi-Fi e suspend em vários aparelhos.

## Decisões tomadas

- **Tinta no KOReader**, não um app novo nem o modo appliance.
- **Código aberto**, em `github.com/henriquefps/tinta-koreader`.
- **Licença: AGPL-3.0**, a mesma do KOReader (texto em `LICENSE`). Cabeçalhos por arquivo ficam para a onda C.
- **Aparelhos:** todo aparelho de toque que roda KOReader. Backends de aparelho `kindle`, `kobo` e `generic`.
  Kindle (KT3) é o único testado; **Kobo é experimental** (sem hardware para testar); `generic` não tem despertar.
- **Escala:** a interface é desenhada para 600×800 e escalonada pela razão `s = min(L/600, A/800)`, com
  letterbox quando a proporção difere. No KT3 `s = 1`: nenhum pixel muda.
- **Regra absoluta:** nada muda no KT3 (mesmos pixels, mesmo repouso e despertar, mesma estimativa de bateria).
- **Apps que vêm no plugin:** Bateria, Relógio, Repouso, Notificações, Timer, Contagem, Nota e Sistema. Quem quiser mais
  instala em `koreader/tinta-apps/`.
- **Navegação:** barra de baixo e gestos. **Atualizações:** intervalo por app, numa só conexão Wi-Fi.
- **Banco SQLite** para notificações, último dado de cada app, layout, configurações.
- **Segurança:** apps em Lua rodam no mesmo processo, com acesso total; permissões no manifesto informam, não
  impedem. Está documentado no README.
- **Despertar pelo relógio no KT3:** funciona (ver 11.5 de `arquitetura.md`). **Bateria em repouso:** ~4–5 mA suspenso,
  ~1 mAh por despertar programado, ~48 mA acordado com Wi-Fi.

## Os 15 itens e o estado de cada um

Legenda: **feito**, **fora** (não será feito agora).

| # | Item | Estado |
|---|---|---|
| 1 | Isolamento de erros (`pcall`, "app com erro", desligar após falhas repetidas) | **feito**: R-E1 a R-E4, `core/registry.lua` |
| 2 | Modelo de app (SDK) com API versionada: manifesto, ciclo de vida, API estável | **feito**: manifesto, `api` e `min_tinta` (arquitetura, seção 5; [`sdk.md`](sdk.md)) |
| 3 | Configuração gerada pela Tinta a partir do que a app declara, com segredos ocultos | **feito**: `settings` no manifesto gera Sistema → Apps → (app); tokens nunca aparecem (R-C2) |
| 4 | Instalar, ativar, desativar e remover apps | **feito**: copiar a pasta (USB/SSH) para `koreader/tinta-apps/`; ativar, desativar e remover em Sistema → Apps. Índice público de apps: **fora** |
| 5 | Dados por app no SQLite, com migração de esquema | **feito** (R-B1 a R-B4, `migrate` por app, R-D2) |
| 6 | Gerente de energia central (só a Tinta liga/desliga Wi-Fi, suspende, programa o despertar) | **feito** (R-P1, `device/sleep.lua`, `device/net.lua`, `core/power.lua`) |
| 7 | Abstração de aparelho: tamanhos pela densidade/ratio, descobrir o que o aparelho tem, degradar | **feito**: escala `s = min(L/600, A/800)` + letterbox; backends `kindle`/`kobo`/`generic` (Kobo experimental) |
| 8 | Apps declarativas (HTTP → JSON, sem código no aparelho) | **fora** por enquanto (as apps de exemplo `_exemplo_json` (seu servidor) e `_exemplo_clima` (serviço da web) mostram o padrão em Lua) |
| 9 | Ferramentas para quem cria apps: gerador, testes, docs, apps de referência | **feito**: `scripts/nova-app.sh`, `tests/apprunner.lua`, `tests/uistub.lua`, `apps/_modelo`, `apps/_exemplo_json`, `apps/_exemplo_clima`, [`sdk.md`](sdk.md) |
| 10 | Primeiro uso: assistente com Wi-Fi e escolha das apps | **feito** (arquitetura, 7.5) |
| 11 | Diagnóstico: log por app e exportação | **feito**: Sistema → Dados exporta o diagnóstico (log, versões, aparelho; sem segredos) |
| 12 | Backup da configuração num arquivo copiável | **feito**: Sistema → Dados |
| 13 | Atualização da plataforma (avisar; depois automática) | **fora**: nem aviso nem atualização automática por enquanto |
| 14 | Privacidade na tela de repouso: esconder widgets sensíveis | **feito** (R-V1 a R-V3) |
| 15 | Idioma e tamanho de letra | **feito**: pt/en (`core/i18n`) e tamanho de letra (R-X) |

O trabalho foi feito em três ondas (A: escala, aparelhos e licença; B: gerenciar apps, diagnóstico, backup, primeiro uso,
privacidade e tamanho de letra; C: SDK, app modelo, gerador e cabeçalhos de licença). Todas estão concluídas.

## O que fica de fora

- **Índice público de apps** (item 4, segunda parte).
- **Atualização da plataforma**, nem aviso nem automática (item 13).
- Apps declarativas (item 8) e instalação de apps de fora sem confiar no código (sandbox): não há plano.

## Decisões em aberto

- **Nome:** `tinta.koplugin`, "Tinta" por padrão.
- **Kobo:** só sai de "experimental" depois de alguém testar em hardware.
- **Relógio:** quem acerta a hora do Kindle no modo "no framework" (apps que dependem da hora certa precisam disso).
- **Repositórios:** núcleo da Tinta separado das apps de referência (depois da onda C).
- **Widget 1×1:** com ~90 × 76 px só cabe ícone e um número.

## Referências

- Arquitetura: [`arquitetura.md`](arquitetura.md); interface do núcleo: `tinta.koplugin/core/README.md`.
- SSH no Kindle: o KOReader tem servidor SSH embutido (porta 2222); permite deploy e leitura de logs sem cabo.
