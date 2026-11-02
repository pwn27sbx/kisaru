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

## El nombre interno sigue siendo `qs-novelmangareader`

El proyecto se llama **kisaru**, pero por dentro conserva el nombre heredado, y esto es a
propósito:

| Qué | Valor |
|---|---|
| Carpeta de configuración | `~/.config/qs-novelmangareader` |
| Comando | `qs-novelmangareader` |
| Destinos IPC | `animePlayer`, `mangaReader`, `novelReader` |
| Widget de barra | `pwnsxb.novelmangareader` |
| Datos | `~/.local/share/quickshell*` |

Renombrar todo eso es una migración aparte —configuración, comando en el `PATH`, widget y
bibliotecas de lectura— y no se hace de tapadillo: mientras no ocurra, lo que leas aquí usa los
nombres de la tabla.

## Requisitos

- **Omarchy 4.0** con su shell de Quickshell. Es una dependencia dura: el repo enlaza
  `Commons/` y `Ui/` a `/usr/share/omarchy/shell/{Commons,Ui}`, así que no funciona sin
  Omarchy instalado. La app avisa en el log si la versión de Omarchy cambia de línea (ver
  *Omarchy* abajo).
- `qs` (Quickshell) — el que trae Omarchy —, `python3` y `mpv`.
- Fuentes: Noto Sans y una Nerd Font (para los iconos).

## Instalar

```sh
git clone https://github.com/pwn27sbx/kisaru ~/.config/qs-novelmangareader
~/.config/qs-novelmangareader/install.sh
```

Vive en su propia carpeta, `~/.config/qs-novelmangareader`, fuera de
`~/.config/quickshell`, así que corre junto a tu propia configuración de Quickshell (o sin
ninguna) sin tocarla.

`install.sh` hace todo:

- instala lo que los lectores necesitan con tu gestor de paquetes: Quickshell, Python, mpv,
  Noto Sans y curl (pacman en Arch; apt en Debian/Ubuntu y dnf en Fedora, que no empaquetan
  Quickshell, así que te dice dónde conseguirlo)
- descarga la fuente Symbols Nerd Font en `~/.local/share/fonts` si no tienes ninguna Nerd
  Font
- enlaza la carpeta a `~/.config/qs-novelmangareader` si la clonaste en otro sitio
- pone el comando `qs-novelmangareader` en tu `PATH`: en `~/.local/bin` si está en él; si
  no, (tras preguntar) en `/usr/local/bin`, para que funcione en cualquier shell y en los
  atajos del compositor desde el primer momento
- crea un venv con `flask`, `requests` y `curl_cffi` en
  `~/.local/share/qs-novelmangareader/venv` para los backends

Opciones: `--no-deps` (omite paquetes y fuentes), `--no-venv`, `--copy` (copia la carpeta
en vez de enlazarla), `--yes` (no pregunta).

Arranca al iniciar sesión con `qs-novelmangareader` (queda callado hasta que abres un panel).

## Comandos y atajos

```sh
qs-novelmangareader           # arráncalo
qs-novelmangareader anime     # abre/cierra el reproductor de anime
qs-novelmangareader manga     # abre/cierra el lector de manga
qs-novelmangareader novel     # abre/cierra el lector de novelas
qs-novelmangareader stop      # ciérralo
qs-novelmangareader log       # su registro
```

Por debajo es `qs -p ~/.config/qs-novelmangareader …`, con los destinos IPC `animePlayer`,
`mangaReader` y `novelReader` (cada uno con `toggle`).

Hyprland:

```ini
exec-once = qs-novelmangareader
bind = SUPER ALT, A, exec, qs-novelmangareader anime
bind = SUPER ALT, M, exec, qs-novelmangareader manga
bind = SUPER ALT, N, exec, qs-novelmangareader novel
```

Sway:

```
exec qs-novelmangareader
bindsym $mod+Alt+a exec qs-novelmangareader anime
bindsym $mod+Alt+m exec qs-novelmangareader manga
bindsym $mod+Alt+n exec qs-novelmangareader novel
```

El botón de minimizar del header oculta el panel pero guarda tu lugar; el siguiente toggle
lo devuelve como lo dejaste.

## Idioma: UI y contenido son independientes

| Qué | Variable | Precedencia / valor por defecto |
|---|---|---|
| **UI** (textos de los paneles) | `QS_LANG` | `QS_LANG` → `settings.json` del app → `LANG` → `en` |
| **Contenido** (subtítulos, capítulos) | `QS_CONTENT_LANG` | lista ordenada separada por comas; por defecto `es` |

El toggle **EN/ES** del panel escribe `<config>/qs-novelmangareader/settings.json` y
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
`<config>/qs-novelmangareader/settings.json`:

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

## Fuentes por panel

- **Anime:** hianime primero; si el stream no trae pista de subtítulos en español, cae a
  [JKAnime](https://jkanime.net) por título (subtítulos en español, hardsub). Si **ambas**
  vuelven vacías, se pregunta a [`ani-cli-mx`](https://github.com/Gildedboy/ani-cli-mx)
  (`ani-cli-mx --debug …`), que aporta sus propias fuentes en español (AnimeAV1 y compañía).
  `QS_ANIME_CLI` acepta la ruta del binario, o `off` para desactivar ese respaldo.
- **Manga / manhwa:** cadena **MangaDex → InManga → zonatmo.net → zonatmo.org →
  ManhwaWeb**, de modo que un título que falta en una fuente se busca en la siguiente. Las
  dos de ZonaTMO son backends independientes (una API JSON y el sitio HTML) que se respaldan
  entre sí; una fuente con el dominio caído se omite sin romper el panel.
  **[ManhwaWeb](https://manhwaweb.com)** aporta su propio catálogo de manhwas en español
  (contenido +18), que no está en las demás fuentes; va al final porque es el último recurso.
  Se puede forzar una fuente con `QS_MANGA_SOURCE`: `mangadex`, `inmanga`,
  `zonatmo` (zonatmo.net), `zonatmo_org` (zonatmo.org), `manhwaweb` y `weebcentral` (inglés,
  sin capítulos en español) fijan esa fuente; `auto` (por defecto) elige por el idioma de
  contenido: español → la cadena, cualquier otro → WeebCentral.
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

El widget `pwnsxb.novelmangareader` vive en `omarchy/pwnsxb.novelmangareader/` y tiene su
propio README con la instalación (copiar o enlazar a `~/.config/omarchy/plugins/`) y cómo
añadirlo a la barra.

## Omarchy

La app se escribe contra **una línea de Omarchy: `4.0`**. Al arrancar ejecuta
`omarchy version` y, si el mayor/menor no coincide (o es un checkout `dev`), escribe **un**
aviso en el log; **no bloquea**: los paneles siguen abriendo.

```sh
qs-novelmangareader log | grep -i omarchy
```

El camino de actualización (actualizar, reiniciar shell y app, leer el log, correr las
suites y subir `supported` a propósito) está documentado en el README del widget, sección
*Updating Omarchy*.

## Tus datos

- Bibliotecas y progreso de lectura: `~/.local/share/quickshell/{anime,manga}_library.json`,
  `~/.local/share/quickshell/new_novel_library.json`
- Descargas y cachés: `~/.local/share/quickshell-manga`, `~/.local/share/quickshell-novel`

Son las mismas rutas que usa el rice completo, así que moverse entre los dos conserva tu
biblioteca.

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
