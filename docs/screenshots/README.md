# Screenshots

Images for the public README, made from [`../tinta-prototipo.html`](../tinta-prototipo.html): the HTML prototype
(in English, with the same texts as the system's English strings) showing the apps the public Tinta ships
(Notifications, System, Battery, Clock, Sleep, Timer, Note, Countdown) and, in `your-apps.png`, the three sample apps,
with made-up content. PNG, grayscale (16 levels), 600×800 portrait or 800×600 landscape (KT3 screen).

| File | Shows |
| --- | --- |
| `inicio.png` | Home with eight widgets (portrait) |
| `inicio-paisagem.png` | The same Home, landscape |
| `central.png` | Notification center |
| `apps.png` | Apps launcher (Menu → Apps) |
| `repouso.png` | Sleep page: status strip, widgets, footer |
| `sistema-repouso.png` | System → Sleep settings |
| `organizador.png` | Home organizer |
| `relogio-estilos.png` | Clock style picker (analog selected) |
| `timer.png` | Timer screen (pomodoro selected) |
| `your-apps.png` | Home with the three sample apps, each tagged "sample": Weather (`apps/_exemplo_clima`, a web service), Home server (`apps/_exemplo_json`, your own server, made-up host `nas.lan`) and Counter (`apps/_modelo`, a local app) |

(The file names of the first nine are kept from earlier versions of the README; the content is English.)

## Regenerate

The maintainers regenerate every image with a script that drives a browser and ImageMagick (`magick`); it lives in the
private repository and is not published here, but the steps are simple and the prototype's URL parameters are all it uses.

The prototype takes URL parameters (`?view=…&land=1&style=…&samples=1&shot=1`; `shot=1` shows only the screen at real
pixels) and uses a fixed clock (Friday, October 16, 14:32), so the images come out the same every time. To do it by hand: open
`docs/tinta-prototipo.html` with the parameters of the image you want in a browser, set the viewport to 600×800 (or 800×600
for landscape), take a screenshot, and convert to 16-level grayscale with ImageMagick if you want the same size on disk.
To explore the prototype interactively, open it without parameters (it loads Noto Sans from Google Fonts). The sample apps'
screens are `?view=clima`, `?view=servidor` and `?view=modelo`.
