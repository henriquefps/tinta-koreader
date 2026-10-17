# Crash ao tocar no sino da barra de status (14:52)

```
frontend/ui/uimanager.lua:1405: attempt to index field 'dimen' (a nil value)
  widgetInvert <- iconbutton.lua:124 <- inputcontainer.lua:266 <- widgetcontainer x6 <- uimanager.lua:896 (top_widget:handleEvent)
```

Aconteceu uma vez, não reproduzido. O KOReader reiniciou. Esta nota diz o que a pilha prova, o que é hipótese,
o que foi mudado e como confirmar com o log do aparelho.

## O que a pilha prova

- `uimanager.lua:896` é `top_widget:handleEvent(event)`: o toque foi entregue à **janela do topo** da pilha do
  `UIManager`, e essa janela tem um `IconButton` seis níveis abaixo (`widgetcontainer` x6 → `inputcontainer:266`
  → `IconButton:onTapIconButton`). A Tinta não usa `IconButton`. Logo, **a janela do topo não era a da Tinta**
  (era o `FileManager`, cuja `TitleBar` tem `IconButton`s, o leitor, ou um `InputDialog`, que também tem
  `TitleBar`).
- `UIManager:sendEvent` só repassa o evento para janelas abaixo do topo quando elas têm `active_widgets` ou
  `is_always_active` (`uimanager.lua:911-935`). O `FileManager` não é nenhum dos dois. Então o `FileManager` só
  recebe um toque quando ele **é** o topo: a Tinta já tinha saído da pilha (ou o toque chegou antes de ele
  entrar).
- O `IconButton` só ganha `dimen` ao ser pintado (`IconButton:paintTo`). Se os botões foram criados e nenhuma
  pintura passou por eles, `self.dimen` é `nil` e `widgetInvert` quebra, como na pilha.
- O sino fica no canto superior direito da barra de status da Tinta; o ícone da direita da `TitleBar` do
  `FileManager` fica no mesmo canto. Um toque no que o usuário ainda via (a Tinta na tela e-ink) cai nesse ícone.

## Causa provável (hipótese, não reproduzida)

`Host:set_rotation` mandava `UIManager:broadcastEvent(SetRotationMode)`. O `FileManager:onSetRotationMode`
responde com `FileManager:rotate`, que é `reinit`: **reconstrói a tela inteira, `TitleBar` e `IconButton`s
novos, com `dimen = nil`** (`filemanager.lua:71-77` e `:794`). Isso acontecia:

1. ao abrir a Tinta em paisagem (o `FileManager` é reconstruído por baixo; como a Tinta cobre a tela inteira, o
   `UIManager` não pinta janelas abaixo de uma janela `covers_fullscreen`, então os botões novos **nunca** são
   pintados enquanto a Tinta está aberto);
2. a cada "Girar";
3. ao fechar, em `UIManager:nextTick(restoreRotation)`, **depois** de a janela da Tinta já ter saído da pilha.

No caso 3 o `FileManager` vira o topo, com widgets recém-criados e sem pintura, enquanto o e-ink ainda mostra o
Tinta por alguns instantes (refresh completo). Qualquer toque nessa janela (um segundo toque em "Sair", um
toque no sino que o usuário ainda via) é entregue ao `FileManager` e quebra em `widgetInvert`. No caso 1/2 o
dano fica latente: o primeiro toque depois do fechamento, antes do primeiro repaint, quebra do mesmo jeito.
Com o leitor aberto por baixo, a mesma mensagem faria o `ReaderView` refazer o layout do documento duas vezes.

## O que foi mudado

- `ui/host.lua`, `set_rotation`: só o framebuffer gira (`Screen:setRotationMode`). **Não há mais broadcast de
  `SetRotationMode`**: o `FileManager`/leitor nunca são reconstruídos pela Tinta, então a árvore de widgets
  deles continua válida (pintada) quando voltam ao topo. A Tinta monta os próprios widgets com
  `Screen:getWidth()/getHeight()`.
- `Host:close` restaura a rotação **antes** de fechar a janela, com a Tinta ainda no topo e cobrindo a tela;
  só depois faz `UIManager:close`. `onWindowClosed` também restaura (fechamento por outro caminho) e pede
  `setDirty("all", "full")`, nunca deixa a restauração para um tick posterior.
- `ui/shield.lua`: depois do fechamento, uma janela invisível engole os toques por ~0,8 s (o e-ink ainda mostra
  a Tinta e a tela de baixo está se redesenhando). Isso também evita que um toque na Tinta "fantasma" abra um
  livro ou um menu do `FileManager`.
- No repouso: a tela de descanso do KOReader não é mais desenhada por cima (`intoScreenSaver` embrulhado), a
  janela da Tinta continua sendo a única janela durante todo o repouso, e o campo de texto (`InputDialog`,
  que tem `TitleBar`) é fechado antes de dormir e antes de girar.
- Testes: `tests/tinta_ui_smoke.lua` confere que nenhum `SetRotationMode` é enviado, que a rotação volta antes
  de a janela sair, que o escudo existe e some, e que `preventScreenSaver` volta ao valor do KOReader.

## O que ainda não está provado

Sem o log do aparelho não dá para saber qual dos três casos foi. O build de depuração atual escreve no
`koreader/crash.log` as linhas `Tinta DEBUG gesture ... tinta_top=` e `Tinta DEBUG window closed`:

- `window closed` poucos segundos antes do crash (e `tinta_top=false` no gesto): era o caso 3, a correção acima
  cobre.
- Nenhum `window closed` e `tinta_top=false`: outra janela estava no topo (um `InputDialog` ou uma
  `InfoMessage` do KOReader, por exemplo a "Tinta: ..." de erro ao abrir). Aí a causa é outra e precisa ser
  procurada nessa janela; mande as linhas.
- `tinta_top=true`: o evento não poderia ter chegado ao `FileManager` pelo `UIManager`; reabrir a investigação.

O teste no aparelho (rotação, fechar em paisagem, tocar rápido depois de fechar) está em
`docs/tinta-etapa3-teste-no-aparelho.md`.

## Recorrência às 19:22:52 (build de depuração) e proteção

O crash voltou com o build de depuração, antes da etapa 3 ser instalada. As linhas `Tinta DEBUG` mostram dois
toques rápidos no canto superior esquerdo (127,21 e 99,25: hora e sino da barra de status), os dois com
`tinta_top= true` e 2 janelas na pilha, e logo depois o mesmo erro (`uimanager.lua:1405` ← `iconbutton.lua:124`
← `uimanager.lua:896`, isto é, `top_widget:handleEvent`). Nenhuma linha `window closed`. Isso **contradiz** a
hipótese acima (FileManager no topo depois de fechar): a Tinta estava aberto e no topo. O código da Tinta e
das apps não usa `IconButton`, `TitleBar` nem `Button` do KOReader. A origem do botão ainda não é conhecida.

Um detalhe que encaixa: um `IconButton` nunca pintado tem `dimen` sem posição (`IconButton:update` usa
`image:getSize()`), então a área de toque dele fica na origem da tela, o canto superior esquerdo, onde ficam a
hora e o sino da Tinta.

Proteção (`ui/host.lua`, `guardIconButton`): ao abrir a Tinta pela primeira vez, `IconButton.onTapIconButton` e
`onHoldIconButton` do KOReader são envolvidos. Se o botão nunca foi pintado (`image.dimen` ou `dimen.x` nil), o
toque é ignorado em vez de derrubar o KOReader, e o `crash.log` recebe
`Tinta guard: unpainted IconButton ... icon= ... stack= ...` com a pilha de janelas e o traceback. Quando essa
linha aparecer, ela diz de quem é o botão.

## Causa encontrada (2026-10-16, 21:33)

Registro temporário no `Host:input` mostrou a pilha logo depois de abrir uma caixa de texto (Timer → Outro):
`KOReader[FS] > Duração em minutos > Tinta[FS]`. A caixa entrou **embaixo** da Tinta. A janela da Tinta tinha
um método `Window:toast(text)`. `UIManager:show` (`uimanager.lua:156-170`) trata como toast qualquer janela com
`.toast` verdadeiro e a mantém acima de tudo o que é mostrado depois; e `UIManager:sendEvent` não para nos toasts,
entregando o toque à primeira janela não-toast, a caixa invisível. Resultado: `InputDialog`, teclado e outros
diálogos do KOReader abriam sob a Tinta sem nunca serem pintados, os toques iam para eles, e um toque num
`IconButton`/`Button` deles (a `TitleBar` fica no canto superior esquerdo, onde estão a hora e o sino) quebrava em
`widgetInvert` (`dimen` nil). Correção: o método virou `Window:showToast`; o teste de fumaça verifica que a janela
não tem `.toast` nem `.modal`. A proteção `guardIconButton` continua como rede de segurança.
