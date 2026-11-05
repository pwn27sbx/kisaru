# kisaru

**Anime, manga y novelas en tres paneles laterales de [Quickshell](https://quickshell.org).**
Abres el que quieras con un atajo, se desliza sobre el escritorio y lo vuelves a cerrar; cada
panel trae su propio backend Python local que consulta los sitios de origen y solo escucha en
`127.0.0.1`.

- **Anime** — explorar, buscar y biblioteca; los episodios se reproducen en `mpv`, con
  subtítulos en español cuando la fuente los tiene.
- **Manga** — explorar, buscar, favoritos, descargar capítulos y leerlos en el panel.
- **Novelas** — explorar, buscar, biblioteca, y leer en el panel o a pantalla completa.

Fuera del panel no hay ventana principal: el shell corre callado hasta que pides un panel, y
se integra con el tema, la tipografía y los componentes de Omarchy en vez de traer su propia
copia.

## De dónde viene

kisaru nace como fork de
**[dhrruvsharma/qs-novelmangareader](https://github.com/dhrruvsharma/qs-novelmangareader)**
(GPL-3.0), separado el **2026-10-07** sobre el commit
[`c3ebeca`](https://github.com/dhrruvsharma/qs-novelmangareader/commit/c3ebeca). Desde
entonces el proyecto siguió por su cuenta: interfaz en español, adopción de Omarchy, fuentes de
contenido en español, ajustes y una capa de componentes compartidos.

La licencia sigue siendo **GPL-3.0**: el `LICENSE` original queda intacto, los avisos de
copyright del código original se conservan, y `NOTICE` recoge el aviso de modificaciones que
pide la GPL-3.0 §5a junto con el rango de commits del fork. Los errores del código original se
reportan al upstream, no aquí.

## Los nombres

| Qué | Valor |
|---|---|
| Carpeta de configuración | `~/.config/kisaru` (enlace a este repo) |
| Comando | `kisaru` |
| Venv de los backends | `~/.local/share/kisaru/venv` |
| Datos (bibliotecas, descargas) | `~/.local/share/kisaru/` |
| Cachés (portadas, capítulos) | `~/.cache/kisaru/` |
| Secretos del canary | `~/.config/kisaru-canary/canary.env` (modo `600`, fuera del repo) |
| Destinos IPC | `animePlayer`, `mangaReader`, `novelReader` |
| Widget de barra | `pwnsxb.kisaru` |

Los destinos IPC conservan sus nombres originales a propósito: los usan el comando y el widget,
y renombrarlos rompería a cualquiera que los llame por IPC.

El proyecto se llamó `qs-novelmangareader` hasta la migración de noviembre de 2026. Los datos,
la configuración y la caché de esa época siguen leyéndose mientras solo existan en su sitio
viejo; el plan de migración (`2026-11-01-kisaru-rename-migration-plan.md`, decisión D4) fija
cuándo se borran, y exige que el checklist pase dos veces y que el canary haya corrido al menos
una vez con la ruta nueva.

## Requisitos

- **Omarchy 4.0** con su shell de Quickshell. Es una dependencia dura: el repo enlaza
  `Commons/` y `Ui/` a `/usr/share/omarchy/shell/{Commons,Ui}`, así que no funciona sin
  Omarchy instalado. La app avisa en el log si la versión de Omarchy cambia de línea (ver
  *Omarchy* abajo).
- `qs` (Quickshell) — el que trae Omarchy —, `python3` y `mpv`.
- Fuentes: Noto Sans y una Nerd Font (para los iconos).

## Instalar

```sh
git clone https://github.com/pwn27sbx/kisaru ~/.config/kisaru
~/.config/kisaru/install.sh
```

Vive en su propia carpeta, `~/.config/kisaru`, fuera de
`~/.config/quickshell`, así que corre junto a tu propia configuración de Quickshell (o sin
ninguna) sin tocarla.

`install.sh` hace todo:

- instala lo que los lectores necesitan con tu gestor de paquetes: Quickshell, Python, mpv,
  Noto Sans y curl (pacman en Arch; apt en Debian/Ubuntu y dnf en Fedora, que no empaquetan
  Quickshell, así que te dice dónde conseguirlo)
- descarga la fuente Symbols Nerd Font en `~/.local/share/fonts` si no tienes ninguna Nerd
  Font
- enlaza la carpeta a `~/.config/kisaru` si la clonaste en otro sitio
- pone el comando `kisaru` en tu `PATH`: en `~/.local/bin` si está en él; si
  no, (tras preguntar) en `/usr/local/bin`, para que funcione en cualquier shell y en los
  atajos del compositor desde el primer momento
- crea un venv con `flask`, `requests` y `curl_cffi` en
  `~/.local/share/kisaru/venv` para los backends

Opciones: `--no-deps` (omite paquetes y fuentes), `--no-venv`, `--copy` (copia la carpeta
en vez de enlazarla), `--yes` (no pregunta).

Arranca al iniciar sesión con `kisaru` (queda callado hasta que abres un panel).

## Comandos y atajos

```sh
kisaru           # arráncalo
kisaru anime     # abre/cierra el reproductor de anime
kisaru manga     # abre/cierra el lector de manga
kisaru novel     # abre/cierra el lector de novelas
kisaru stop      # ciérralo
kisaru log       # su registro
```

Por debajo es `qs -p ~/.config/kisaru …`, con los destinos IPC `animePlayer`,
`mangaReader` y `novelReader` (cada uno con `toggle`).

Hyprland:

```ini
exec-once = kisaru
bind = SUPER ALT, A, exec, kisaru anime
bind = SUPER ALT, M, exec, kisaru manga
bind = SUPER ALT, N, exec, kisaru novel
```

Sway:

```
exec kisaru
bindsym $mod+Alt+a exec kisaru anime
bindsym $mod+Alt+m exec kisaru manga
bindsym $mod+Alt+n exec kisaru novel
```

El botón de minimizar del header oculta el panel pero guarda tu lugar; el siguiente toggle
lo devuelve como lo dejaste.

## Idioma: UI y contenido son independientes

| Qué | Variable | Precedencia / valor por defecto |
|---|---|---|
| **UI** (textos de los paneles) | `QS_LANG` | `QS_LANG` → `settings.json` del app → `LANG` → `en` |
| **Contenido** (subtítulos, capítulos) | `QS_CONTENT_LANG` | lista ordenada separada por comas; por defecto `es` |

El toggle **EN/ES** del panel escribe `<config>/kisaru/settings.json` y
cambia la UI **en vivo**. `QS_LANG` manda sobre el archivo, y no se escribe nunca en el
código: el wrapper pasa el entorno tal cual. Así puedes leer contenido en español con la
UI en inglés, o al revés.

## Ajustes (el engranaje del panel)

El botón **`󰒓`** del header, en cualquiera de los tres paneles, abre la vista de ajustes:

- **Velocidad de scroll** — cuánto avanza una muesca de rueda en el lector: de **0,5 a 5**
  en pasos de **0,1**, por defecto `2`. Se aplica **en vivo**; en el panel de anime no
  aparece, porque no tiene lector. El slider se maneja con ratón o rueda.
- **Interfaz en español** — el mismo cambio que el chip `EN`, pero explicado y persistente.
  Si tienes `QS_LANG` en el entorno, esa variable manda y la fila lo dice (se ve atenuada).
- **Audio (SUB/DUB)** — solo en anime: subtítulos o doblaje, se aplica en vivo y se guarda.

Se cierra con la flecha de volver o `Esc`. Todo se guarda en
`<config>/kisaru/settings.json`:

```json
{
  "language": "es",
  "scrollFactor": 2,
  "viewMode": "grid",
  "viewMode.manga": "list"
}
```

Un solo escritor mantiene ese archivo (`services/UiPrefs.qml`): cambiar una clave nunca
borra las demás.

## Carpetas y modo privado

La Biblioteca muestra las carpetas como tarjetas del mismo tamaño que un título, con un
mosaico de sus portadas, y después los títulos que no tienen carpeta. La tarjeta con
borde discontinuo **Nueva carpeta** crea una. Dentro de una carpeta, la flecha vuelve a
la raíz y la misma línea muestra el nombre, el número de títulos, el interruptor
**Ocultar/Oculta** y un menú de tres puntos con **Renombrar** y **Borrar**. Borrar una carpeta **nunca borra
títulos**.

Con una palabra secreta configurada aparece un interruptor **Ocultar** en la ficha de
cada título y dentro de cada carpeta. Dentro de una carpeta, al pulsarlo la carpeta
desaparece de la Biblioteca y vuelve a la raíz. En la ficha de un título hace otra cosa:
el título queda oculto y la ficha **sigue abierta** con el interruptor en **Oculta**, para
poder guardarlo en una carpeta oculta ahí mismo — la lista de carpetas muestra también
las ocultas, porque ese título ya lo está, y no pide la palabra. El título desaparece de
la Biblioteca al salir de la ficha (volver, cerrar, minimizar, cambiar de panel o de
pestaña), y ahí se bloquea. Escribir la palabra en el buscador de la Biblioteca
los muestra otra vez; dentro del título o de la carpeta, apagar el interruptor
**Ocultar** los deja visibles. Un título oculto dentro de una carpeta visible desaparece
solo él, sin ocultar la carpeta.

```sh
kisaru privado       # pide la palabra dos veces, sin eco y sin argumentos
```

La palabra no queda en el historial del shell ni en la interfaz. Se guarda como
`privacy.json` (modo `0600`) con sal y una clave scrypt; la app solo guarda una etiqueta
de un dígito para decidir si una búsqueda merece una comprobación. Mientras está
bloqueado, un título o una carpeta ocultos **no existen** para la interfaz: no aparecen
en la cuadrícula, la lista, el estado vacío, los contadores, la línea de estado, la
búsqueda ni los mosaicos de las carpetas. Se desbloquea escribiendo la palabra (sin
mensaje) y se vuelve a bloquear al cerrar, minimizar o cambiar de panel, al pulsar
**Ocultar** dentro de una carpeta, al salir de la ficha de un título oculto, al
escribirla otra vez y al arrancar la app. `kisaru privado` también sirve
para reemplazarla, tras confirmar.

Esto oculta la interfaz, **no cifra nada**: los títulos siguen en texto plano en los
archivos de la biblioteca. No hay bloqueo por inactividad.

## Fuentes por panel

- **Anime:** hianime primero; si el stream no trae pista de subtítulos en español, cae a
  [JKAnime](https://jkanime.net) por título (subtítulos en español, hardsub). Si **ambas**
  vuelven vacías, se pregunta a [`ani-cli-mx`](https://github.com/Gildedboy/ani-cli-mx)
  (`ani-cli-mx --debug …`), que aporta sus propias fuentes en español (AnimeAV1 y compañía).
  `QS_ANIME_CLI` acepta la ruta del binario, o `off` para desactivar ese respaldo.
- **Manga / manhwa:** cadena **MangaDex → InManga → zonatmo.net → zonatmo.org →
  ManhwaWeb → MangaFire**, de modo que un título que falta en una fuente se busca en la
  siguiente. Las dos de ZonaTMO son backends independientes (una API JSON y el sitio HTML)
  que se respaldan entre sí; una fuente con el dominio caído se omite sin romper el panel.
  **[ManhwaWeb](https://manhwaweb.com)** aporta su propio catálogo de manhwas en español
  (contenido +18), que no está en las demás fuentes; va al final porque es el último recurso.
  **[MangaFire](https://mangafire.to)** es el último recurso: catálogo amplio y multi-idioma,
  del que se leen los capítulos `es-la` (con `es` como respaldo cuando no hay `es-la`). Su
  API exige una firma `vrf` que el backend calcula por sí mismo, así que no necesita navegador.
  **Una búsqueda pregunta a todas las fuentes a la vez** y une lo que devuelven: se quitan
  duplicados por título normalizado (las variantes deliberadas, como «sin censura», quedan
  como entradas aparte) y se ordena por lo que escribiste, ignorando acentos y mayúsculas
  —primero el título exacto, después el mismo título sin calificativos de edición—. Cada
  fuente tiene un límite de 6 s (`QS_MANGA_SEARCH_TIMEOUT`): una fuente lenta o caída se
  omite y no frena la búsqueda. Los ids conservan el prefijo de su fuente, así que el
  detalle y los capítulos se resuelven contra la fuente correcta. Al paginar se pide el
  mismo `offset` a cada fuente, la página siguiente empieza donde acaba la ventana más
  grande que devolvió alguna y `hasMore` es verdadero si a alguna le quedan resultados (el
  deduplicado es por página, así que un título puede reaparecer más abajo). Explorar el
  catálogo y «Últimos» no cambian: siguen usando la primera fuente que responde.
  Se puede forzar una fuente con `QS_MANGA_SOURCE`: `mangadex`, `inmanga`,
  `zonatmo` (zonatmo.net), `zonatmo_org` (zonatmo.org), `manhwaweb`, `mangafire` y
  `weebcentral` (inglés, sin capítulos en español) fijan esa fuente; `auto` (por defecto)
  elige por el idioma de contenido: español → la cadena, cualquier otro → WeebCentral.
- **Novelas:** [SkyNovels](https://skynovels.net) en español; si el idioma de contenido no
  es español, FreeWebNovel (inglés).

Cuando ninguna fuente tiene capítulos en español, el lector lo dice claramente —nombrando
las fuentes que revisó— en vez de mostrar contenido como si fuera español. Si no hay
capítulos en español para un manga concreto, se muestra en inglés **con un aviso
prominente** en el detalle.

## Cómo se ve

Los tres paneles comparten una sola capa de componentes (`components/`, `services/`): un
header con pestañas y contadores, buscador, chips de filtro, tarjeta de portada y fila de
lista, y un esqueleto de carga que dibuja la forma exacta de lo que va a llegar. La retícula
es de tres columnas en las tres vistas, y cada panel recuerda su propio modo (cuadrícula o
lista) en `settings.json`.

La paleta sale del tema de Omarchy (`qs.Commons.Color`, respaldado por
`~/.local/state/omarchy/current/theme/colors.toml`). No hay copia propia ni archivo de
paleta que mantener: cambiar el tema de Omarchy cambia la app. `app/Colors.qml` solo traduce
los nombres de rol que usan las vistas a los colores del sistema.
`extras/matugen/quickshell.json.hbs` es legado de antes de adoptar Omarchy y ya no se usa.

## Widget de barra de Omarchy

El widget `pwnsxb.kisaru` vive en `omarchy/pwnsxb.kisaru/` y tiene su
propio README con la instalación (copiar o enlazar a `~/.config/omarchy/plugins/`) y cómo
añadirlo a la barra.

## Omarchy

La app se escribe contra **una línea de Omarchy: `4.0`**. Al arrancar ejecuta
`omarchy version` y, si el mayor/menor no coincide (o es un checkout `dev`), escribe **un**
aviso en el log; **no bloquea**: los paneles siguen abriendo.

```sh
kisaru log | grep -i omarchy
```

El camino de actualización (actualizar, reiniciar shell y app, leer el log, correr las
suites y subir `supported` a propósito) está documentado en el README del widget, sección
*Updating Omarchy*.

## Tus datos

- Bibliotecas y progreso de lectura: `~/.local/share/kisaru/{anime,manga}_library.json`,
  `~/.local/share/kisaru/new_novel_library.json`
- Carpetas: `~/.local/share/kisaru/organizer.json`
- Palabra del modo privado: `~/.local/share/kisaru/privacy.json` (modo `0600`)
- Descargas y cachés: `~/.local/share/kisaru/downloads`, `~/.cache/kisaru/`

Las versiones anteriores vivían en `~/.local/share/quickshell*`; la regla de compatibilidad
está arriba, en «Los nombres», y la migración las copia a `~/.local/share/kisaru/`.

## Desarrollo y pruebas

```sh
node --test                  # i18n, lint de estilo y de i18n, CLI, componentes, backends
node tools/lint-i18n.js      # literales en inglés sin I18n.t
node tools/lint-style.js     # números crudos de radio/espaciado/tipografía
python3 -m unittest discover -s tests -p "test_*.py"   # backends (fixtures, sin red)
```

Las pruebas de los backends usan fixtures grabadas y `HOME`/`XDG_DATA_HOME` temporales:
**nunca** apuntan a `~/.local/share/quickshell*` reales. Las pruebas en vivo contra los
sitios están detrás de variables de entorno opcionales (`INMANGA_LIVE_TESTS=1`).

Los scripts sueltos —`scripts/source_canary.py`, `scripts/error_report.py`— son
herramientas de diagnóstico contra las fuentes; no hacen falta para usar la app.

## Créditos

- Proyecto original: **qs-novelmangareader** de
  [dhrruvsharma](https://github.com/dhrruvsharma/qs-novelmangareader) (GPL-3.0), del que este
  repo parte.
- Los sitios de origen y sus APIs son de sus dueños; kisaru solo los consulta desde tu
  máquina.
- Los paneles usan el shell, el tema y los componentes de
  [Omarchy](https://github.com/basecamp/omarchy).

## Licencia

GPL-3.0-or-later, la misma del proyecto del que viene. `LICENSE` se conserva tal cual y
`NOTICE` contiene el aviso de modificaciones del fork.
