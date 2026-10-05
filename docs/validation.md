# Validación de MacIPTV 0.1

Validación realizada el 4 de octubre de 2026 en un Mac Apple Silicon con macOS 27, Swift 6.2.3 y Xcode. El destino mínimo es macOS 14; no se ha ejecutado en un equipo con esa versión ni en Intel.

## Núcleo e integración

- Suite independiente del núcleo: 42 pruebas, 0 fallos. Incluye atributos M3U con comas/BOM, entradas inválidas, duplicados por grupo, identificadores estables, UTF-8/Windows-1252/Latin-1, XMLTV y zonas horarias, rechazo seguro de dígitos Unicode, codificación de credenciales y prefijos de ruta Xtream.
- Integración HTTP con un proveedor sintético local: M3U y Xtream importan tres canales; XMLTV encuentra el programa actual por ID; lista vacía rechazada; guía defectuosa produce aviso y conserva canales; el error HTTP oculta el token de la URL. Todos PASS.
- Favoritos en demostración: filtro correcto y UserDefaults de favoritos guardados intacto. PASS.
- AVPlayer decodifica un fotograma HLS público de Apple de 960 × 540. PASS.

## Interfaz nativa

Se comprobó en la aplicación empaquetada: bienvenida, formulario M3U/archivo/Xtream, demo de tres canales, filtro de grupo, búsqueda sin resultados, guía temporal, selección de canal, importación local con XMLTV y rechazo de lista vacía conservando la fuente previa. Entrada y salida de pantalla completa mediante ⌘F: PASS.

La primera implementación con SwiftUI VideoPlayer produjo un fallo del runtime al iniciar vídeo. Se sustituyó por AVPlayerView de AppKit. La versión corregida reprodujo vídeo real visible durante más de 14 segundos y mostró controles nativos.

## Revisiones de robustez

- Importaciones canceladas o tardías no sustituyen una fuente posterior.
- Guardado de fuente antes de activar sus canales; SecItemUpdate y creación solo si no existe, sin borrar antes.
- URL de errores y barra de estado reducida a origen; sesión de descarga efímera sin caché en disco.
- Demo conserva la suscripción guardada y sus favoritos.
- Guía respeta grupos y búsqueda y comparte eje horario entre encabezado y filas.

## Comprobación final

- `swift test --disable-sandbox` sobre el proyecto completo final: 42 pruebas, 0 fallos.
- `bash scripts/build-app.sh`: compilación release sin errores ni avisos de código, icono, firma ad hoc verificada y archivo ZIP creados.
- App final abierta: guardar M3U/XMLTV en el Llavero, cerrar, relanzar y recuperar tres canales con programas actuales: PASS.
- Acceso a Security serializado en un actor fuera del hilo principal; LAContext con interactionNotAllowed evita autenticación interactiva bloqueante. Los errores conservan la fuente existente.
- Seleccionar «Cine de prueba» muestra un canal; pulsar «Todos los canales» restaura tres: PASS en la app final.
- Reproducción del paquete final: controles AVPlayerView con estado play activo y duración cargada. La implementación es la misma que produjo el fotograma visible validado antes.
- Smoke del estado final: favoritos, regreso a Todos tras filtrar y favoritos demo sin escritura persistente: tres PASS.
- La fuente sintética se retiró mediante «Quitar fuente», regresando a la bienvenida.
- Consulta posterior del Llavero: entrada sintética inexistente. Servidor HTTP de pruebas detenido. La app quedó abierta en demo, sin fuente persistente.

## Límites

No se han utilizado credenciales ni canales del proveedor real del usuario. El fixture usa URLs públicas y datos ficticios y no prueba autenticación contra un servicio comercial. HLS compatible con AVKit se reproduce integrado; otros códecs o emisiones TS pueden necesitar VLC/IINA. Grabación, VOD, catch-up y DRM quedan fuera de esta versión.

El paquete lleva firma local ad hoc, sin notarización. No es un lanzamiento publicado en la App Store.

## Delegación

La implementación de aplicación y núcleo se delegó al modelo solicitado, llamacpp/qwen3.8-flash-next. El orquestador preparó especificación, plan, empaquetado, documentación y verificaciones independientes, y devolvió al worker los defectos observados. Un revisor Qwen independiente revisó el núcleo. Tras la implementación de Qwen, el orquestador aplicó directamente los dos últimos ajustes de acceso al Llavero y pulsación de filas laterales para cerrar la entrega sin más espera.

# Actualización 0.1.1: proveedor real

El usuario informó de fallo Xtream y error al reproducir M3U con canales TS. Se investigó con el ejemplo suministrado, manteniendo URLs y credenciales únicamente en memoria de procesos de prueba mediante entrada sin eco. No se copiaron al proyecto ni a los logs.

## Evidencia y causa

- No había eventos históricos útiles de MacIPTV en unified log. La versión anterior descartaba los errores técnicos de red y AVPlayer.
- El mismo stream TS: HTTP 403 con perfil genérico MacIPTV; HTTP 200 con bytes MPEG-TS con perfiles VLC y TiviMate.
- AVPlayer con TS no reprodujo el canal. Con su variante HLS y el perfil HTTP VLC decodificó un fotograma 1920 × 1080.
- Endpoint Xtream HLS: lista de 6.415 canales, todas sus URLs HLS. Descargar la lista con perfil MacIPTV da HTTP 200; perfil VLC da HTTP 403. Los perfiles de lista y vídeo deben estar separados.
- El servidor, usuario y contraseña del ejemplo permiten importar la lista. No se ha recuperado el error técnico original del formulario ni comprobado que allí se escribiera exactamente el mismo servidor.
- Se reprodujo otro defecto concreto: `http//servidor` se interpretaba como host `http` y no se rechazaba. Ahora se exige un esquema bien escrito o un host sin esquema. No se asume que ese fuera el texto exacto introducido por el usuario.

## Correcciones

- AVURLAsset usa la API pública AVURLAssetHTTPUserAgentKey con el perfil de vídeo comprobado.
- PlaybackPolicy convierte solamente rutas Xtream conocidas `/live/usuario/clave/ID.ts` a HLS; conserva origen, prefijo, credenciales codificadas y consulta. Las URLs originales de Channel y sus IDs no se modifican.
- ContentFetcher mantiene el perfil de descarga comprobado independientemente del perfil del reproductor.
- Una observación de Channel sustituye las dos observaciones id/URL para evitar aperturas dobles al seleccionar un canal.
- Los errores exponen únicamente dominio de una lista blanca, código y categoría. Log local acotado a 200 entradas en `~/Library/Logs/MacIPTV/diagnostics.log`, accesible en el menú de la app; no contiene URLs ni descripciones arbitrarias.
- El arranque mantiene acceso al llavero sin autenticación interactiva. El botón explícito «Autorizar llavero» permite solicitar acceso en segundo plano si macOS lo requiere tras una recompilación. Guardar o quitar fuente permite la autenticación correspondiente a esa acción del usuario.

## Verificación final

- Suite completa: 56 tests, 0 fallos. Incluye redacción de secretos/cadenas anidadas/ciclos, resolución TS→HLS y rechazo de esquemas mal escritos.
- Probe con SourceImporter y PlaybackPolicy finales: importa 6.415 canales y decodifica un fotograma real 1920 × 1080.
- El primer probe combinado no obtuvo fotograma porque ejecutaba su bucle síncrono dentro de una tarea MainActor. Al separar el bucle de reproducción de la tarea de importación, la comprobación pasa. La prueba aislada previa también decodificó el mismo canal.
- Paquete 0.1.1 release compilado y firmado localmente. Arranque nativo verificado; recupera la lista local que el usuario tenía guardada.
- No se borró la fuente ni se cambiaron las credenciales guardadas del usuario.

La compatibilidad TS→HLS requiere que el proveedor sirva esa variante. No implica soporte universal de TS directo ni de todos los canales de la suscripción.

# Actualización 0.1.2: ATS en el paquete

El log real y la captura del usuario muestran NSURLErrorDomain -1022 al importar Xtream HTTP. La configuración incluía NSAllowsArbitraryLoads=true junto a NSAllowsArbitraryLoadsForMedia=true. En macOS moderno, la presencia de la segunda clave hace que se ignore la primera: AVKit puede cargar medios, pero URLSession bloquea la lista HTTP.

Se reprodujo con un ejecutable dentro de un paquete .app firmado y con el Info.plist anterior: una petición a http://example.com devuelve -1022. Sin NSAllowsArbitraryLoadsForMedia, la misma petición en el mismo paquete devuelve HTTP 200. Esta prueba incluye las políticas del bundle; los probes CLI anteriores sin Info.plist no las ejercitaban.

Se mantiene NSAllowsArbitraryLoads=true para admitir proveedores configurables que utilizan HTTP tanto en listas como en medios. HTTPS sigue usando validación de certificados. La fuente y las credenciales guardadas no se modificaron.

Se añadió una prueba de regresión de la configuración: falló con la combinación anterior y pasa con la corrección. Suite completa final: 57 tests, 0 fallos. Info.plist válido. Versión 0.1.2 empaquetada y firmada localmente.

Prueba adicional con el importador final dentro de un paquete SourceProbe.app firmado que usa la misma configuración ATS de 0.1.2: importa los 6.415 canales del proveedor real y decodifica un fotograma 1920 × 1080. Credenciales introducidas mediante entrada privada sin eco, sin guardarlas en archivos ni en la configuración del usuario. Se cerró el aviso modal pendiente de la app anterior y se reinició MacIPTV para aplicar la política nueva.

# Actualización 0.1.3: cierre al cambiar de canal

El informe MacIPTV-2026-10-04-183330.ips corresponde a 0.1.2 y registra EXC_BREAKPOINT/SIGTRAP en el hilo principal. La traza pasa por AVKit, SwiftUICore Binding.init(get:set:) y NSHostingView.layout. Esto apunta a los controles internos de AVKit; no hay un error de red contemporáneo en el diagnóstico de la app.

PlayerView ya no utiliza AVPlayerView ni importa AVKit. Mantiene una sola superficie NSView con AVPlayerLayer y el mismo AVPlayer al sustituir canales, con controles propios de pausa, silencio, volumen y pantalla completa. Conserva las protecciones de generación y observaciones del elemento activo.

Verificación: compilación release y firma local correctas; paquete 0.1.3 (build 4), ZIP íntegro; 57 tests con cero fallos. scripts/check-channel-switches.swift realiza 20 sustituciones consecutivas de AVPlayerItem usando HLS público y decodifica después un fotograma de 1920 × 1080. Esta prueba ejercita AVFoundation y la capa persistente, no toda la interfaz SwiftUI.

La app final importó el proveedor guardado y mostró vídeo real con los controles propios. Se completó un cambio mediante automatización nativa; se detuvo esa automatización al detectar interacción del usuario. Una captura posterior confirmó vídeo visible en otro canal y pantalla completa. No se afirma que esta prueba limitada descarte todos los posibles cierres futuros.

# Actualización 0.1.4: recuperación de emisiones detenidas

El diagnóstico del 4 de octubre entre las 18:40 y 18:41 (hora local) registra varios fallos NSURLErrorDomain=-1008 con CoreMediaErrorDomain=-16849. No se atribuye el código a un defecto concreto del proveedor: el registro previo no identifica qué segmento o actualización HLS falla. La app anterior observaba solo AVPlayerItem.status y no recuperaba un elemento fallido ni vigilaba un elemento readyToPlay que dejaba de avanzar.

Se observa ahora el avance del tiempo con reloj monotónico y se escuchan las notificaciones de bloqueo, final y fallo al final de la emisión. Tras 15 segundos sin avance, o un fallo/final explícito, se desconecta el elemento anterior y se reintenta con esperas de 2, 4 y 8 segundos. La pausa voluntaria inhibe la recuperación. Solo un minuto de progreso continuo restablece los tres intentos; los cortes repetidos tras unos segundos no crean un bucle infinito. Cambiar de canal, reintentar manualmente o cerrar la vista cancela las tareas anteriores; tanto KVO como las notificaciones validan la generación y el elemento activo.

PlaybackRecoveryTests añade cinco casos de regresión: congelación, pausa/reanudación, presupuesto finito con conexiones breves, recuperación del presupuesto tras progreso sostenido y corte de la ventana sana por falta de datos. Suite completa: 62 tests, cero fallos.

scripts/recovery-smoke.swift compila junto al PlayerView de producción y los objetos de MacIPTVCore. Aloja la vista SwiftUI en una ventana invisible con HLS público de Apple, espera más de tres segundos de avance e induce una congelación pausando AVPlayer sin cambiar el estado de pausa voluntaria. Resultado observado: se sustituye el elemento detenido y la reproducción vuelve a avanzar más de tres segundos. El diagnóstico registra started → stalled → reconnecting → started → recovered. No lee el llavero ni sustituye la fuente del usuario.

El paquete release 0.1.4 (build 5) está firmado localmente y el ZIP es íntegro. La prueba del proveedor real durante varios minutos queda pendiente: el control nativo informó que el Mac estaba bloqueado. La reconexión está verificada, pero no se afirma haber corregido la causa externa de los errores HLS.

# Actualización 0.1.5: causa de los cortes de unos 30 segundos

Investigación del 5 de octubre de 2026. Los logs de 0.1.4 muestran varias conexiones de 31–32 segundos, seguidas de CoreMedia -12660, un evento de fin/fallo y reconexión. El fallo precede al watchdog; no lo provoca el límite de reintentos. La notificación de fallo al final contiene un error que la implementación anterior no conservaba: NSURLErrorDomain=-1102 con CoreMediaErrorDomain=-12660. El registro de AVPlayer identifica HTTP 403 Forbidden.

## Comparación controlada con el proveedor

Se utilizó la fuente del llavero sin imprimir ni persistir credenciales. Cada ensayo se ejecutó por separado, sin otro canal activo en la app. Los probes temporales quedaron fuera del repositorio. Solo se emitieron códigos, tiempos, contadores y alias temporales.

| Ensayo | Resultado |
| --- | --- |
| AVPlayer aislado con URL de entrada y perfil VLC, sin lógica de MacIPTV | Vídeo hasta ~32 segundos; HTTP 403, posición detenida. La petición fallida también devolvió 403 al comprobarla por HTTP. |
| Descarga periódica de la lista HLS resuelta con URLSession | HTTP 200 durante un minuto; secuencia avanza, cinco segmentos de 10 segundos, sin ENDLIST. |
| AVPlayer con dirección final tras redirección | Nuevo corte; no basta resolver la redirección. |
| AVPlayer con renovación paralela cada 5 segundos | La lista sigue con HTTP 200, pero la reproducción se corta; tampoco basta un heartbeat. |
| Relay local de diagnóstico que conserva las URIs cambiantes | Listas y segmentos HTTP 200, pero AVPlayer se detiene con CoreMedia -12312. Corregir solo los rechazos HTTP no basta. |
| Comparación de manifestaciones sucesivas | Para una misma secuencia cambian las URLs autorizadas completas. El nombre del segmento permanece estable; al desplazarse la ventana, los segmentos comunes se mueven exactamente lo declarado por MEDIA-SEQUENCE. |
| Relay de diagnóstico con identidades locales estables y destinos autorizados actualizados | 180 segundos de vídeo continuo, nuevos segmentos y fotogramas, cero bloqueos. |
| PlayerView de producción + HLSRelay Swift | 180 segundos continuos, 179 fotogramas nuevos comprobados, avance de ~180 segundos y el mismo AVPlayerItem, sin reconexiones. |

## Causa y corrección

El servidor renueva las URLs firmadas de segmentos que siguen siendo los mismos. AVPlayer espera que un número de secuencia siga identificando la misma URI entre renovaciones. RFC 8216, sección 6.3.4, recomienda detener la reproducción si esa correspondencia cambia: https://www.rfc-editor.org/rfc/rfc8216.html#section-6.3.4 . La salida HLS observada no mantiene esa propiedad. El contenido sí continúa disponible; no se ha observado un límite de reproducción de 30 segundos ni un corte de conectividad general.

La ventana inicial tiene cinco segmentos de diez segundos y AVPlayer empieza cerca del directo, aproximadamente en el segundo 20 de esa ventana. Quedan unos 30 segundos iniciales que puede consumir antes de necesitar continuar con las URIs renovadas. Esto explica la periodicidad del fallo. La incompatibilidad estaba en usar directamente esa salida HLS del proveedor, sin adaptar su renovación de tokens; aumentar reintentos no la resolvía.

HLSRelay utiliza Network y URLSession, solo en 127.0.0.1 con puerto dinámico y prefijo UUID. HLSRelayRegistry asigna una URL local estable por lista y número de secuencia y actualiza en memoria el destino autorizado cuando vuelve a descargar el manifiesto. Resuelve las URLs relativas contra la respuesta final y adapta atributos URI de recursos referenciados. Reutiliza la sesión final del proveedor. No hay Python ni servicio remoto en la app y no se transcodifica el vídeo. Se conserva HTTPS con validación normal y el perfil HTTP de vídeo comprobado.

La adaptación se activa únicamente en rutas Xtream HLS reconocidas, conservando las credenciales percent-encoded al detectar la ruta. El HLS ordinario y la demo mantienen el camino directo. Las conexiones y el estado del relay se cancelan antes de abrir la siguiente fuente, y se retiran al cerrar la vista. El registro limita el historial de destinos y nunca los persiste.

## Diagnóstico y verificación final

PlaybackSnapshot registra cada cinco segundos y en los eventos relevantes: sesión aleatoria, tiempo transcurrido, posición, duración finita o unknown, rate, estado de elemento/transporte, motivo de espera, búfer disponible, ventana buscable, peticiones de medios, bytes, bitrate, bloqueos y fotogramas descartados. El relay registra tipo de recurso, HTTP, bytes, tiempo y resumen numérico del manifiesto. Los comentarios de error se clasifican en valores fijos; no se imprimen textos libres, URIs, tokens, nombres de canales o credenciales.

Suite completa: 79 tests, cero fallos. Nuevas regresiones de tokens cambiantes con identidad estable, desplazamiento de ventana, recursos relativos/URI entre comillas, separación de listas, privacidad del resumen y reconocimiento de rutas con credenciales codificadas. El parser HLS trata CRLF/BOM. Compilación release de 0.1.5 (build 6) y firma ad hoc verificadas; ZIP íntegro.

El paquete final se abrió con la fuente guardada y el canal de la captura. Tras más de dos minutos seguía con rate=1, transport=playing, nuevas peticiones HTTP 200 y cero bloqueos.

La prueba prolongada valida el canal utilizado y la adaptación de esta salida HLS. No garantiza disponibilidad del proveedor, compatibilidad de todos sus códecs ni reproducción continua indefinida. Los logs y credenciales de los probes no se publican.
