# MacIPTV: contexto del proyecto

Este archivo sirve de guía para Claude Code y otros colaboradores. Describe el estado real del código, su evolución y las precauciones necesarias para mantenerlo. Actualízalo cuando cambien la arquitectura, los comandos o las limitaciones.

## Qué es

MacIPTV es una aplicación nativa para macOS 14 o posterior, con interfaz en español e interacción inspirada en TiviMate para Android. Permite ver televisión en directo usando la suscripción IPTV del usuario. No incluye una suscripción, canales comerciales ni credenciales de un proveedor.

La ventana tiene tres zonas: grupos/favoritos, lista de canales con búsqueda y reproductor con programa actual. Los dos paneles laterales se pueden ocultar de forma independiente. Admite listas M3U remotas o locales, proveedores Xtream y programación XMLTV. Incluye favoritos persistentes, guía temporal, pantalla completa, pausa, silencio y volumen. El modo demo usa canales y programación ficticios con un vídeo HLS público de Apple.

Quedan fuera del alcance actual: grabación, catálogo VOD, catch-up, DRM y reproducción simultánea de varios canales. La compatibilidad con todos los proveedores o códecs no está garantizada.

## Cómo se creó

El desarrollo comenzó el 4 de octubre de 2026 a petición del propietario: una alternativa nativa de macOS con un flujo similar al de TiviMate. Se trabajó desde Codex con un orquestador y subagentes de programación `llamacpp/qwen3.8-flash-next`, el modelo solicitado por el usuario. La primera implementación del núcleo y la interfaz se delegó a ese modelo; el orquestador realizó especificación, integración, empaquetado, revisión y comprobaciones independientes, además de correcciones directas posteriores. La implementación fue iterativa, a partir de pruebas automáticas, comprobaciones de la interfaz y fallos comunicados por el usuario.

Los documentos originales están en `docs/superpowers/specs/2026-10-04-maciptv-design.md` y `docs/superpowers/plans/2026-10-04-maciptv.md`. Son documentos históricos: algunas decisiones, como usar controles de AVKit, fueron sustituidas. Para el estado vigente, consulta el código, este archivo y las secciones más recientes de `docs/validation.md`.

No había un repositorio Git local durante las versiones 0.1–0.1.4. El historial inicial de GitHub parte del código consolidado de 0.1.4; las versiones anteriores están documentadas, pero no son commits o etiquetas históricas recuperables.

## Arquitectura

Swift Package Manager, sin dependencias externas declaradas. Se usa el compilador Swift 6 con modo de lenguaje Swift 5 para los targets. El empaquetado genera una aplicación AppKit/SwiftUI con App Sandbox, Hardened Runtime y firma local ad hoc gratuita.

| Ruta | Responsabilidad |
| --- | --- |
| `Sources/MacIPTV/` | Aplicación, estado observable, ventanas y vistas SwiftUI/AppKit. |
| `Sources/MacIPTV/AppStore.swift` | Importación, fuente activa, favoritos, demo y coordinación del llavero. |
| `Sources/MacIPTV/PlayerView.swift` | AVPlayer, superficie persistente AVPlayerLayer y controles propios; recuperación de emisiones. |
| `Sources/MacIPTVCore/` | Modelos, parsers, red, URLs Xtream, llavero, diagnósticos y políticas de reproducción. |
| `Sources/MacIPTV/Theme.swift` | Colores adaptables, fuente Archivo, iconos Lucide y carga de recursos empaquetados. |
| `Sources/MacIPTV/SettingsView.swift` | Gestión de fuentes, reproducción, apariencia y opciones avanzadas. |
| `Sources/MacIPTVCore/ChannelCache.swift` | Instantáneas cifradas de canales por fuente para restaurar el arranque. |
| `Sources/MacIPTVCore/HLSRelay.swift` | Adaptador HTTP nativo limitado a loopback con URLs privadas solo en memoria. |
| `Sources/MacIPTVCore/HLSRelayRegistry.swift` | Identidades locales estables por lista y secuencia; destinos autorizados actualizados. |
| `Sources/MacIPTVCore/NetworkPolicy.swift` | Consentimiento HTTP por fuente y comprobación de destinos y redirecciones; excepciones solo IP/puerto. |
| `Sources/MacIPTVCore/SecureHTTPClient.swift` | Sesiones efímeras y descargas limitadas durante la recepción. |
| `Sources/MacIPTVCore/NetworkGateway.swift` | SOCKS5 local autenticado, conexión a IP comprobadas y cierre de sockets. |
| `Sources/MacIPTVCore/DNSResolver.swift` | Plazos y cancelación del solicitante; máximo global de cuatro workers de resolución. |
| `Sources/MacIPTVCore/SavedSource.swift` | Fuente, permisos de red y bookmark de solo lectura persistidos en el llavero; migración sin consentimientos implícitos. |
| `Tests/MacIPTVCoreTests/` | Pruebas del núcleo independientes de la interfaz. |
| `Examples/demo.m3u` | Lista ficticia con un recurso público. |
| `scripts/` | Empaquetado, icono, proveedor sintético y pruebas de integración/reproducción. |
| `docs/validation.md` | Evidencia de comprobaciones y límites por versión. |

La importación Xtream solicita `get.php` con `type=m3u_plus` y `output=m3u8`, y obtiene XMLTV mediante `xmltv.php`. Aunque existe un constructor de `player_api.php`, la importación actual utiliza la lista M3U; no implementa un catálogo completo de esa API.

M3U y XMLTV se analizan en el núcleo. Los canales tienen identificadores estables para mantener favoritos. Una guía opcional defectuosa no invalida una lista usable. AppStore protege las operaciones asíncronas con cancelación y generaciones: una respuesta antigua no puede sustituir una fuente más reciente. Los fallos de importación deben conservar la fuente y los canales válidos anteriores.

## Reproducción: decisiones importantes

- Se usa AVFoundation con un AVPlayerLayer alojado en NSView. No se usan SwiftUI VideoPlayer ni los controles internos de AVPlayerView, que provocaron cierres en el entorno probado.
- PlaybackPolicy transforma solamente rutas Xtream conocidas `/live/usuario/clave/ID.ts` a su equivalente `.m3u8`. Conserva prefijos, parámetros y credenciales codificadas. La URL original y el ID del canal permanecen intactos. Se requiere que el proveedor sirva la variante HLS; no es soporte general de MPEG-TS directo.
- Desde 0.1.5 se adapta el HLS mediante HLSRelay. Las URLs de un mismo segmento rotaban sus tokens en cada renovación; AVPlayer interrumpía la reproducción al cambiar las URIs para una misma secuencia. El relay mantiene una identidad local por lista/secuencia y actualiza el destino autorizado. Escucha solo en 127.0.0.1 con un puerto dinámico y rutas UUID; no es un proxy abierto. Desde 0.3.0, toda reproducción integrada, incluido HLS público y demo, pasa por el relay y el transporte protegido. No requiere Python, VLC ni un backend remoto. URLSession es efímero, sin caché en disco, y conserva la validación HTTPS. El reproductor integrado requiere HLS; MP4 directo, DRM y content steering necesitan un reproductor externo.
- Las listas usan `MacIPTV/1.0` y el vídeo `VLC/3.0.21 LibVLC/3.0.21`. Estos perfiles se verificaron por separado: el proveedor probado rechazaba el agente de vídeo para listas y el agente de listas para vídeo. No los unifiques sin una prueba real.
- Info.plist mantiene `NSAllowsArbitraryLoads=true` para proveedores HTTP configurables; NetworkPolicy exige consentimiento explícito por fuente antes de usar HTTP y bloquea redirecciones HTTPS→HTTP. Xtream sin esquema usa HTTPS. No añadas `NSAllowsArbitraryLoadsForMedia` junto a esa clave: esa combinación provocó el bloqueo ATS de URLSession. HTTPS mantiene la validación de certificados.
- PlaybackRecovery detecta 15 segundos sin avance usando un reloj monotónico. Los errores y el fin de emisión también activan recuperación. Se desconecta el elemento anterior antes de reconectar; hay hasta tres intentos con esperas de 2, 4 y 8 segundos. Un minuto de progreso continuo restablece el presupuesto. La pausa voluntaria no debe reconectar.
- Al cambiar de canal o cerrar la vista se cancelan tareas y observadores. Los callbacks validan tanto la generación como el elemento activo. Evita abrir dos conexiones por un único cambio de canal.

## Privacidad y persistencia

La configuración del proveedor se guarda en el Llavero mediante KeychainSourceStore y un actor KeychainSourceRepository. Las llamadas síncronas de Security se realizan fuera del hilo principal. El arranque consulta sin autenticación interactiva; el usuario puede solicitarla mediante «Autorizar llavero». Guardar actualiza antes de intentar crear una entrada; no borra primero una fuente válida.

SavedSource conserva también el consentimiento HTTP, las excepciones de IP/puerto y el bookmark del archivo elegido por NSOpenPanel. Las fuentes antiguas no reciben consentimiento HTTP automático; una lista local antigua puede necesitar seleccionarse de nuevo con «Elegir». Los bookmarks solo conceden lectura. Antes de transferir una URL a VLC/IINA se muestra un aviso: puede contener credenciales, y las conexiones del reproductor externo no pasan por las protecciones de MacIPTV.

Los favoritos usan UserDefaults. El modo demo no debe sobrescribir la fuente ni los favoritos persistentes. Las conexiones van directamente al proveedor; no hay backend intermediario ni telemetría propia.

DiagnosticLog conserva un máximo de 200 entradas en `~/Library/Logs/MacIPTV/diagnostics.log`. Solo admite eventos fijos, resúmenes de error redactados y métricas numéricas/tipadas del reproductor y de las peticiones HLS. Nunca registres URLs de reproducción, listas del proveedor, usuarios, contraseñas ni descripciones arbitrarias de errores: pueden contener secretos. ErrorDiagnostics restringe los dominios, conserva códigos numéricos y controla errores anidados y ciclos.

Con App Sandbox, Library y UserDefaults se resuelven dentro del container de la aplicación; usa «Abrir diagnostico» para localizar el log efectivo. No presupongas que la ruta anterior fuera del container sigue siendo la utilizada.

No subas configuración personal, listas reales, capturas del usuario, logs, llavero ni credenciales al repositorio. Los datos de autenticación usados en tests son ficticios. `.build/`, `dist/`, logs y cachés quedan excluidos por `.gitignore`.

## Compilar y comprobar

En macOS con las herramientas de Xcode instaladas, desde la raíz:

```sh
swift test --disable-sandbox
bash scripts/build-app.sh
open dist/MacIPTV.app
```

El script genera `dist/MacIPTV.app`, `dist/MacIPTV.zip` y su checksum `dist/MacIPTV.zip.sha256`, configura las cachés del compilador, crea el icono y verifica la firma ad hoc con runtime y `scripts/MacIPTV.entitlements`. La versión y el número de compilación se definen en `scripts/Info.plist`. Los artefactos se generan localmente y no se incluyen en Git. No se requiere Developer ID para estas protecciones; la firma local y el checksum no acreditan la identidad del editor ni sustituyen notarización.

Si el entorno restringe las cachés predeterminadas:

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-cache" \
swift test --disable-sandbox
```

Para comprobar vídeo público sin una suscripción:

```sh
swift scripts/check-stream.swift
swift scripts/check-channel-switches.swift
```

La prueba de recuperación utiliza PlayerView de producción en una ventana invisible. Después de compilar los tests, en el entorno Apple Silicon documentado:

```sh
swiftc -target arm64-apple-macosx14.0 -swift-version 5 -module-cache-path "$PWD/.build/clang-cache" \
  -I .build/arm64-apple-macosx/debug/Modules \
  Sources/MacIPTV/PlayerView.swift scripts/recovery-smoke.swift \
  .build/arm64-apple-macosx/debug/MacIPTVCore.build/*.swift.o \
  -o /tmp/maciptv-recovery-smoke
/tmp/maciptv-recovery-smoke
```

Las rutas de objetos cambian en Intel. `scripts/fixture-server.py` ofrece un proveedor sintético local para las pruebas de importación; `scripts/import-smoke/` y `scripts/store-smoke/` son harnesses auxiliares, no targets ejecutables declarados en Package.swift.

Una prueba CLI sin firma no verifica App Sandbox. Para comprobar aislamiento y permisos, empaqueta los ensayos `scripts/security-sandbox-smoke.swift` y `scripts/security-bookmark-smoke.swift` con los entitlements y runtime de producción y un bundle ID de prueba, sin consultar la fuente personal. Sus rutas de archivo sintético deben adaptarse al checkout usado. Los resultados y límites están en `docs/validation.md` y `docs/security-review-2026-10-06.md`.

## Evolución de versiones

Las versiones 0.1–0.1.4 se desarrollaron el 4 de octubre de 2026; 0.1.5, el 5 de octubre. Son iteraciones locales con firma ad hoc, no lanzamientos notarizados o publicados en la App Store.

| Versión | Evolución y evidencia |
| --- | --- |
| **0.1** | Primera app: M3U/Xtream, XMLTV, grupos, búsqueda, favoritos, demo y empaquetado. Se sustituyó SwiftUI VideoPlayer por AVPlayerView tras un cierre del runtime. Se corrigieron pulsaciones de filas, cancelación y acceso al llavero. 42 tests y comprobaciones de importación/interfaz/vídeo público. |
| **0.1.1** | Diagnóstico de fallos con el proveedor real. Separación de perfiles HTTP para listas y vídeo, transformación de TS Xtream a HLS, validación de esquemas mal escritos y diagnóstico seguro. Importación de miles de canales y fotograma real 1920 × 1080. 56 tests. |
| **0.1.2** | Corrección del error ATS `-1022` al importar Xtream HTTP: eliminación de la combinación conflictiva de claves de Info.plist. Verificación con peticiones dentro de un bundle firmado, no solo desde CLI. 57 tests. |
| **0.1.3** | El cierre al cambiar de canal apuntaba a Binding de SwiftUI dentro de los controles AVKit. Se sustituyeron por controles propios y una superficie AVPlayerLayer persistente. 57 tests; prueba de 20 cambios de elemento con fotograma posterior 1080p y vídeo visible en la app. |
| **0.1.4** | El usuario informó de vídeo detenido tras unos segundos; el diagnóstico mostraba `-1008`/CoreMedia `-16849`. Se añadió vigilancia del avance, eventos de reproducción y recuperación automática acotada. 62 tests y prueba con PlayerView real que congela el elemento, verifica su sustitución y la reanudación. |
| **0.1.5** | Investigación del corte de ~30 segundos con AVPlayer aislado, redirección resuelta, renovación paralela y relay de diagnóstico. Se identificaron URIs que cambian para la misma secuencia de segmentos. Se incorporó un adaptador Swift local que mantiene identidades estables y renueva los destinos autorizados; diagnóstico periódico y por petición HTTP. La evidencia final de reproducción continua está en `docs/validation.md`. |
| **0.2.0** | Zapping por teclado, canal anterior, recientes, favoritos ordenables y controles que se ocultan automáticamente. |
| **0.2.1** | Conservación de variantes activas, rangos de bytes explícitos, reescritura transaccional y actualización periódica del programa actual. 83 tests y regresión visual con programación sintética. |
| **0.3.0** | Transporte protegido, permisos por fuente, límites de recursos, rechazo de entidades XML, sandbox/runtime y archivos de solo lectura. 120 tests; comprobaciones firmadas de aislamiento, bookmarks, HTTPS y recuperación de vídeo público. |

## Estado y trabajo pendiente

La versión del bundle sigue siendo **0.3.0, build 9**; los cambios del 15 de octubre descritos abajo todavía no incrementan esa numeración. La validación histórica de 0.3.0 registró 120 tests pasando, incluidas las regresiones de seguridad, diagnóstico HLS, identidad estable de segmentos, credenciales codificadas, conservación de variantes activas y rangos de bytes explícitos. En la validación de 0.1.5, PlayerView de producción reprodujo el canal real durante 180 segundos sin sustituir el elemento, con 179 fotogramas nuevos comprobados. El registro está en `docs/validation.md`. El entorno de validación fue Apple Silicon, macOS 27, Swift 6.2.3 y Xcode. macOS 14 e Intel son destinos previstos, pero no se han ejecutado allí estas comprobaciones.

El corte periódico de 0.1.4 se ha reproducido y se ha identificado la incompatibilidad de las URIs de segmentos HLS renovadas. La reproducción continua con el proveedor y el adaptador se documenta en la validación de 0.1.5. Esto no implica compatibilidad universal ni una garantía frente a futuros cortes de red o del proveedor.

La firma es ad hoc, sin notarización ni distribución universal. Una recompilación puede cambiar la identidad que macOS reconoce para el llavero; conserva el flujo explícito de autorización.

Al mantener el proyecto: reproduce los fallos antes de cambiar el reproductor, añade pruebas de regresión relevantes, verifica los bundles para cambios de ATS/firma y distingue entre resultados del núcleo, pruebas de reproducción e interacción nativa. No presentes una comprobación breve como garantía de reproducción continua.


### Versión 0.2.0 — navegación y controles

Añade menú Canales con atajos ⌥⌘↑/↓ y ⌥⌘←, botón de canal anterior, lista Recientes de hasta 20 identificadores únicos y favoritos ordenables mediante menú contextual. AppStore conserva el historial y el orden en UserDefaults; el modo demo opera en memoria. La lista de recientes mantiene una instantánea durante el zapping para evitar que su reordenación cambie el siguiente destino. PlayerView incorpora ocultación de controles sin sustituir AVPlayer ni cambiar HLSRelay, PlaybackRecovery o la conexión de vídeo. La implementación se coordinó con un subagente llamacpp/qwen3.8-flash-next para los controles.

### Versión 0.2.1 — correcciones de relay y programa actual

Cada actualización de una lista variante renueva su registro y su destino resuelto; no necesita que vuelva a descargarse la lista maestra para conservar la ruta local. Los segmentos antiguos siguen caducando. Una reescritura rechazada no cambia el registro: las mutaciones se confirman solo al completar el manifiesto. Antes de reescribir las URLs de segmentos, HLSRelayRegistry convierte los desplazamientos implícitos de EXT-X-BYTERANGE en explícitos y rechaza los que no tienen un rango anterior válido del mismo recurso o desbordan Int.

ChannelListView y el panel de programa actual usan TimelineView cada 30 segundos, pasando su fecha a AppStore.nowPlaying. Esa actualización no recrea el reproductor. scripts/programme-refresh-smoke.swift comprueba ambos títulos mediante OCR del renderizado de una ventana invisible, con programación ficticia y sin conexión a proveedores ni acceso al llavero. Su cabecera contiene el comando de compilación.


### Versión 0.3.0 — seguridad

NetworkPolicy/SecureHTTPClient/NetworkGateway canalizan todas las descargas a través de un gateway SOCKS5 local autenticado con destinos IP comprobados y sin fallback directo. DNSResolver acota las llamadas de sistema y libera solicitantes cancelados. Toda reproducción nativa utiliza HLSRelay; no reintroducir AVURLAsset remoto sin mantener controles sobre todas las peticiones. Permisos HTTP y excepciones IP/puerto pertenecen a SavedSource, junto con el bookmark read-only, guardados en Keychain. Una URL del proveedor nunca concede permisos. Callbacks de consentimiento llevan sourceID y generación para descartar avisos antiguos. Los parsers y descargas tienen límites explícitos; DTD/entidades XML y sintaxis URI HLS ambigua se rechazan.

scripts/build-app.sh firma gratuitamente con entitlements y --options runtime; no necesita Developer ID. Distribución no notarizada y sin identidad verificable del editor, decisión deliberada del usuario. La validación firmada, límites y riesgos residuales figuran en docs/security-review-2026-10-06.md y docs/validation.md.


## Actualización del 15 de octubre de 2026 — interfaz, arranque y reproducción

### Interfaz nativa y recursos

El rediseño se implementa en SwiftUI con integración AppKit para la ventana, el arrastre del divisor y la superficie AVPlayerLayer. No es una interfaz web. Se incorporan los recursos facilitados en el paquete de diseño: tipografía Archivo y símbolos Lucide, con sus licencias en `Resources/Fonts/OFL.txt` y `Resources/Icons/LICENSE.txt`. SwiftPM copia ambos directorios y `build-app.sh` incluye `MacIPTV_MacIPTV.bundle` en el bundle final. `Theme.swift` resuelve primero los recursos de la app empaquetada y después `Bundle.module`.

La cabecera roja integra búsqueda y pestañas Directo/Guía. Hay vistas específicas de lista de canales, detalle de programa, confirmaciones y ajustes; apariencia del sistema, clara u oscura. La guía muestra una cuadrícula temporal con navegación de días y botón Ahora. El reproductor incluye Ahora/Después, navegación de canales y programación posterior. Los indicadores de recordatorio se conservan solo en memoria: no hay todavía notificaciones del sistema ni programación persistente de avisos.

La gestión de fuentes permite mantener un catálogo en el Llavero, activar o eliminar entradas y conservar navegación/favoritos por fuente. `KeychainSourceStore.Catalog` migra desde la entrada antigua sin borrarla antes de guardar la nueva. Se incorporan ajustes para reanudar el último canal, reproductor externo y tiempo de ocultación de controles.

### Tamaño de la previsualización

El divisor horizontal entre vídeo y Ahora/Después se puede arrastrar en Directo con cero, uno o dos paneles laterales visibles. Su control aparece al pasar el puntero por la zona o mientras se arrastra. No debe quedar un botón permanentemente visible.

La previsualización utiliza siempre ajuste proporcional (`resizeAspect`) y un rectángulo explícito que sigue el tamaño disponible. El modo rellenar se limita a pantalla completa y puede recortar allí. `PlayerSurface` deja que AppKit gestione la capa raíz y aloja AVPlayerLayer como subcapa; en `layout()` actualiza su frame a `bounds` sin animaciones implícitas. No volver a alternar automáticamente entre ajustar y rellenar según la altura: produjo recortes y saltos durante el arrastre.

El ajuste conserva el fotograma completo y aprovecha una dimensión del área disponible. Puede haber bandas por diferencia de proporciones; las bandas negras ya codificadas por el emisor también forman parte del fotograma y no se eliminan automáticamente.

### Restauración rápida y guía en segundo plano

`Channel` es Codable. `ChannelCache` guarda instantáneas de canales por UUID de fuente en Caches, bajo `es.maciptv/channel-snapshots`. Como las URLs pueden contener credenciales, el archivo usa AES-GCM con clave de 256 bits en el Llavero; los permisos del directorio/archivo son 0700/0600. No es una caché de vídeo ni de fotogramas. Una huella SHA-256 de `SavedSource` impide reutilizarla si cambian configuración, permisos de red o bookmark. Al eliminar una fuente se elimina su instantánea.

Al restaurar una fuente existente, AppStore intenta publicar primero sus canales cacheados y reanudar el último canal si está habilitado. Después actualiza la lista y la guía. `SourceImporter.importSource` ofrece `onChannelsLoaded`: se ejecuta tras analizar y validar la lista, antes de descargar XMLTV. La espera de la guía ya no bloquea la publicación de canales ni el inicio de reproducción. Cancelación y generación protegen también estos callbacks. Una instantánea no debe podar favoritos ni anunciar una actualización reciente ficticia. Si el Llavero o la caché no están disponibles, se conserva la ruta normal de importación.

### Entrega progresiva HLS y diagnóstico de arranque

Al comparar el código con AndroIPTV se confirmó que ambas apps convierten rutas Xtream TS conocidas a HLS, pero el relay de Mac esperaba a descargar cada segmento completo. Ahora los recursos de tipo segmento solicitados por GET usan `SecureHTTPClient.stream`: entregan bloques de 32 KiB mediante AsyncBytes y respuesta HTTP local chunked, con contrapresión. Manifiestos, claves y HEAD mantienen el recorrido acotado anterior. Se conservan el gateway de IP comprobadas, validación de redirecciones, límite de ocho saltos, límites de bytes, concurrencia y cancelación al cerrar la conexión. Si falla una transmisión ya iniciada se cierra el socket; no se añade una segunda respuesta HTTP al cuerpo.

Al recibir readyToPlay se llama a `playImmediately(atRate: 1)` si no hay pausa voluntaria. Se conserva la espera automática de AVPlayer para interrupciones posteriores. No hay una espera fija de diez segundos programada antes de reproducir. Las esperas de recuperación de 2/4/8 segundos y los plazos de red tienen otras funciones y no deben confundirse con esa congelación inicial.

El diagnóstico incluye transiciones de transporte y, durante los primeros 15 ticks, muestreo con AVPlayerItemVideoOutput: `videoTime` registra la marca de presentación de un fotograma nuevo, o unknown si aún no se ha obtenido. Se registra el estado cada segundo al principio y después cada cinco. Solo se guardan métricas; no imágenes ni URLs. La medición observó casos con reloj avanzando alrededor de los dos segundos y fotogramas nuevos bastante después, aunque ya había datos suficientes. Esto no identifica por sí solo una causa universal de decodificación/sincronización. No se dejó el experimento de recrear AVPlayer en cada cambio de canal.

Tras probar esta versión, el propietario confirmó que el inicio va mucho mejor y parece resuelto; algún canal todavía puede tardar. Es una validación manual del conjunto de cambios, no una garantía de inicio instantáneo ni una atribución demostrada a una única modificación. Una recompilación con firma ad hoc puede volver a requerir autorización del Llavero; no borrar fuentes para resolverlo.

### Comprobaciones de esta actualización

Se añaden pruebas de caché cifrada, correspondencia con la fuente, persistencia y borrado, publicación de canales antes de la guía, migración del catálogo y entrega progresiva. Los fixtures retienen la segunda mitad de una respuesta hasta verificar que ya llegó la primera; se comprueba tanto el cliente HTTP como el relay completo. También se verifican límites de tamaño y bloqueo de redirecciones a servicios locales no autorizados.

La suite completa ejecutada el 15 de octubre terminó con **126 tests y cero fallos**. La compilación de producción y la verificación de firma terminaron correctamente. Las pruebas de sockets locales deben ejecutarse con permisos que permitan escuchar en loopback: un fallo Operation not permitted del sandbox del agente no demuestra un fallo de la app. Los artefactos `dist/` y los datos personales siguen excluidos de Git.
