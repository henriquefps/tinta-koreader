# Screenshots

Images for the public README, made from [`../tinta-prototipo.html`](../tinta-prototipo.html): the HTML prototype
adjusted to show only the apps the public Tinta ships (Notificações, Sistema, Bateria, Relógio, Repouso, Timer,
Nota, Contagem) with made-up content. PNG, grayscale (16 levels), 600×800 portrait or 800×600 landscape (KT3 screen).

| File | Shows |
| --- | --- |
| `inicio.png` | Home with eight widgets (portrait) |
| `inicio-paisagem.png` | The same Home, landscape |
| `central.png` | Notification centre |
| `apps.png` | Apps launcher (Menu → Apps) |
| `repouso.png` | Sleep page: status strip, widgets, footer |
| `sistema-repouso.png` | Sistema → Repouso settings |
| `organizador.png` | Home organizer |
| `relogio-estilos.png` | Relógio style picker (analog selected) |
| `timer.png` | Timer screen (pomodoro selected) |

## Regenerate

The prototype takes URL parameters (`?view=…&land=1&style=…&shot=1`; `shot=1` shows only the screen at real pixels) and
uses a fixed clock (Friday, 16 October, 14:32), so the images come out the same every time. Open
`docs/tinta-prototipo.html` with the parameters of the image you want in a browser, set the viewport to 600×800 (or 800×600
for landscape) and take a screenshot; convert to 16-level grayscale with ImageMagick if you want the same size on disk.
To explore the prototype interactively, open it without parameters (it loads Noto Sans from Google Fonts).
