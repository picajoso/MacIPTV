# MacIPTV: contexto del proyecto

Este archivo sirve de guía para Claude Code y otros colaboradores. Describe el estado real del código, su evolución y las precauciones necesarias para mantenerlo. Actualízalo cuando cambien la arquitectura, los comandos o las limitaciones.

## Qué es

MacIPTV es una aplicación nativa para macOS 14 o posterior, con interfaz en español e interacción inspirada en TiviMate para Android. Permite ver televisión en directo usando la suscripción IPTV del usuario. No incluye una suscripción, canales comerciales ni credenciales de un proveedor.

La ventana tiene tres zonas: grupos/favoritos y búsqueda, lista de canales y reproductor con programa actual. Admite listas M3U remotas o locales, proveedores Xtream y programación XMLTV. Incluye favoritos persistentes, guía temporal, pantalla completa, pausa, silencio y volumen. El modo demo usa canales y programación ficticios con un vídeo HLS público de Apple.

Quedan fuera del alcance actual: grabación, catálogo VOD, catch-up, DRM y reproducción simultánea de varios canales. La compatibilidad con todos los proveedores o códecs no está garantizada.

## Cómo se creó

El desarrollo comenzó el 4 de octubre de 2026 a petición del propietario: una alternativa nativa de macOS con un flujo similar al de TiviMate. Se trabajó desde Codex con un orquestador y subagentes de programación `llamacpp/qwen3.8-flash-next`, el modelo solicitado por el usuario. La primera implementación del núcleo y la interfaz se delegó a ese modelo; el orquestador realizó especificación, integración, empaquetado, revisión y comprobaciones independientes, además de correcciones directas posteriores. La implementación fue iterativa, a partir de pruebas automáticas, comprobaciones de la interfaz y fallos comunicados por el usuario.

Los documentos originales están en `docs/superpowers/specs/2026-10-04-maciptv-design.md` y `docs/superpowers/plans/2026-10-04-maciptv.md`. Son documentos históricos: algunas decisiones, como usar controles de AVKit, fueron sustituidas. Para el estado vigente, consulta el código, este archivo y las secciones más recientes de `docs/validation.md`.

No había un repositorio Git local durante las versiones 0.1–0.1.4. El historial inicial de GitHub parte del código consolidado de 0.1.4; las versiones anteriores están documentadas, pero no son commits o etiquetas históricas recuperables.

## Arquitectura

Swift Package Manager, sin dependencias externas declaradas. Se usa el compilador Swift 6 con modo de lenguaje Swift 5 para los targets. El empaquetado genera una aplicación AppKit/SwiftUI con firma local ad hoc.

| Ruta | Responsabilidad |
| --- | --- |
| `Sources/MacIPTV/` | Aplicación, estado observable, ventanas y vistas SwiftUI/AppKit. |
| `Sources/MacIPTV/AppStore.swift` | Importación, fuente activa, favoritos, demo y coordinación del llavero. |
| `Sources/MacIPTV/PlayerView.swift` | AVPlayer, superficie persistente AVPlayerLayer y controles propios; recuperación de emisiones. |
| `Sources/MacIPTVCore/` | Modelos, parsers, red, URLs Xtream, llavero, diagnósticos y políticas de reproducción. |
| `Sources/MacIPTVCore/HLSRelay.swift` | Adaptador HTTP nativo limitado a loopback con URLs privadas solo en memoria. |
| `Sources/MacIPTVCore/HLSRelayRegistry.swift` | Identidades locales estables por lista y secuencia; destinos autorizados actualizados. |
| `Tests/MacIPTVCoreTests/` | Pruebas del núcleo independientes de la interfaz. |
| `Examples/demo.m3u` | Lista ficticia con un recurso público. |
| `scripts/` | Empaquetado, icono, proveedor sintético y pruebas de integración/reproducción. |
| `docs/validation.md` | Evidencia de comprobaciones y límites por versión. |

La importación Xtream solicita `get.php` con `type=m3u_plus` y `output=m3u8`, y obtiene XMLTV mediante `xmltv.php`. Aunque existe un constructor de `player_api.php`, la importación actual utiliza la lista M3U; no implementa un catálogo completo de esa API.

M3U y XMLTV se analizan en el núcleo. Los canales tienen identificadores estables para mantener favoritos. Una guía opcional defectuosa no invalida una lista usable. AppStore protege las operaciones asíncronas con cancelación y generaciones: una respuesta antigua no puede sustituir una fuente más reciente. Los fallos de importación deben conservar la fuente y los canales válidos anteriores.

## Reproducción: decisiones importantes

- Se usa AVFoundation con un AVPlayerLayer alojado en NSView. No se usan SwiftUI VideoPlayer ni los controles internos de AVPlayerView, que provocaron cierres en el entorno probado.
- PlaybackPolicy transforma solamente rutas Xtream conocidas `/live/usuario/clave/ID.ts` a su equivalente `.m3u8`. Conserva prefijos, parámetros y credenciales codificadas. La URL original y el ID del canal permanecen intactos. Se requiere que el proveedor sirva la variante HLS; no es soporte general de MPEG-TS directo.
- Desde 0.1.5 se adapta el HLS de las rutas Xtream conocidas mediante HLSRelay. Las URLs de un mismo segmento rotaban sus tokens en cada renovación; AVPlayer interrumpía la reproducción al cambiar las URIs para una misma secuencia. El relay mantiene una identidad local por lista/secuencia y actualiza el destino autorizado. Escucha solo en 127.0.0.1 con un puerto dinámico y rutas UUID; no es un proxy abierto. No requiere Python, VLC ni un backend remoto. URLSession es efímero, sin caché en disco, y conserva la validación HTTPS. El HLS ordinario y la demo siguen con AVPlayer directo.
- Las listas usan `MacIPTV/1.0` y el vídeo `VLC/3.0.21 LibVLC/3.0.21`. Estos perfiles se verificaron por separado: el proveedor probado rechazaba el agente de vídeo para listas y el agente de listas para vídeo. No los unifiques sin una prueba real.
- Info.plist mantiene `NSAllowsArbitraryLoads=true` para proveedores HTTP configurables. No añadas `NSAllowsArbitraryLoadsForMedia` junto a esa clave: esa combinación provocó el bloqueo ATS de URLSession. HTTPS mantiene la validación de certificados.
- PlaybackRecovery detecta 15 segundos sin avance usando un reloj monotónico. Los errores y el fin de emisión también activan recuperación. Se desconecta el elemento anterior antes de reconectar; hay hasta tres intentos con esperas de 2, 4 y 8 segundos. Un minuto de progreso continuo restablece el presupuesto. La pausa voluntaria no debe reconectar.
- Al cambiar de canal o cerrar la vista se cancelan tareas y observadores. Los callbacks validan tanto la generación como el elemento activo. Evita abrir dos conexiones por un único cambio de canal.

## Privacidad y persistencia

La configuración del proveedor se guarda en el Llavero mediante KeychainSourceStore y un actor KeychainSourceRepository. Las llamadas síncronas de Security se realizan fuera del hilo principal. El arranque consulta sin autenticación interactiva; el usuario puede solicitarla mediante «Autorizar llavero». Guardar actualiza antes de intentar crear una entrada; no borra primero una fuente válida.

Los favoritos usan UserDefaults. El modo demo no debe sobrescribir la fuente ni los favoritos persistentes. Las conexiones van directamente al proveedor; no hay backend intermediario ni telemetría propia.

DiagnosticLog conserva un máximo de 200 entradas en `~/Library/Logs/MacIPTV/diagnostics.log`. Solo admite eventos fijos, resúmenes de error redactados y métricas numéricas/tipadas del reproductor y de las peticiones HLS. Nunca registres URLs de reproducción, listas del proveedor, usuarios, contraseñas ni descripciones arbitrarias de errores: pueden contener secretos. ErrorDiagnostics restringe los dominios, conserva códigos numéricos y controla errores anidados y ciclos.

No subas configuración personal, listas reales, capturas del usuario, logs, llavero ni credenciales al repositorio. Los datos de autenticación usados en tests son ficticios. `.build/`, `dist/`, logs y cachés quedan excluidos por `.gitignore`.

## Compilar y comprobar

En macOS con las herramientas de Xcode instaladas, desde la raíz:

```sh
swift test --disable-sandbox
bash scripts/build-app.sh
open dist/MacIPTV.app
```

El script genera `dist/MacIPTV.app` y `dist/MacIPTV.zip`, configura las cachés del compilador, crea el icono y verifica la firma ad hoc. La versión y el número de compilación se definen en `scripts/Info.plist`. Los artefactos se generan localmente y no se incluyen en Git.

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
swiftc -swift-version 5 -module-cache-path "$PWD/.build/clang-cache" \
  -I .build/arm64-apple-macosx/debug/Modules \
  Sources/MacIPTV/PlayerView.swift scripts/recovery-smoke.swift \
  .build/arm64-apple-macosx/debug/MacIPTVCore.build/*.swift.o \
  -o /tmp/maciptv-recovery-smoke
/tmp/maciptv-recovery-smoke
```

Las rutas de objetos cambian en Intel. `scripts/fixture-server.py` ofrece un proveedor sintético local para las pruebas de importación; `scripts/import-smoke/` y `scripts/store-smoke/` son harnesses auxiliares, no targets ejecutables declarados en Package.swift.

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

## Estado y trabajo pendiente

La versión vigente es **0.1.5, build 6**. La suite completa tiene 79 tests pasando, incluidas las regresiones de diagnóstico HLS, identidad estable de segmentos y credenciales codificadas. PlayerView de producción reprodujo el canal real durante 180 segundos sin sustituir el elemento, con 179 fotogramas nuevos comprobados. El registro está en `docs/validation.md`. El entorno de validación fue Apple Silicon, macOS 27, Swift 6.2.3 y Xcode. macOS 14 e Intel son destinos previstos, pero no se han ejecutado allí estas comprobaciones.

El corte periódico de 0.1.4 se ha reproducido y se ha identificado la incompatibilidad de las URIs de segmentos HLS renovadas. La reproducción continua con el proveedor y el adaptador se documenta en la validación de 0.1.5. Esto no implica compatibilidad universal ni una garantía frente a futuros cortes de red o del proveedor.

La firma es ad hoc, sin notarización ni distribución universal. Una recompilación puede cambiar la identidad que macOS reconoce para el llavero; conserva el flujo explícito de autorización.

Al mantener el proyecto: reproduce los fallos antes de cambiar el reproductor, añade pruebas de regresión relevantes, verifica los bundles para cambios de ATS/firma y distingue entre resultados del núcleo, pruebas de reproducción e interacción nativa. No presentes una comprobación breve como garantía de reproducción continua.
