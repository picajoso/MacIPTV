# Revisión de seguridad de MacIPTV 0.2.1

Fecha: 6 de octubre de 2026. Revisión del código presente en el workspace, incluidas las correcciones de 0.2.1/build 8, y del paquete `dist/MacIPTV.app` generado desde ese código.

## Resultado

No se ha encontrado una vía confirmada de ejecución remota de código, acceso remoto general a archivos, escalada de privilegios, instalación de persistencia o envío oculto de datos a un backend del desarrollador. Esto expresa lo observado en esta revisión; no garantiza que no existan otros defectos, especialmente en los componentes del sistema que decodifican vídeo y XML.

Sí hay riesgos de robo de credenciales en conexiones HTTP, peticiones controladas por el proveedor a servicios internos, agotamiento de recursos y falta de aislamiento del proceso. El paquete actual necesita endurecimiento antes de distribuirlo ampliamente.

## Alcance y método

- Lectura de los targets de aplicación y núcleo: importación M3U/Xtream/XMLTV, reproducción, relay HTTP, llavero, diagnósticos, persistencia e interacción con VLC/IINA.
- Inspección de `Package.swift`, empaquetado, Info.plist, firma, entitlements, dependencias enlazadas y contenido del bundle.
- Búsqueda acotada de patrones de claves privadas y tokens comunes en los archivos actualmente versionados; las coincidencias de URLs con credenciales están en fixtures de tests. Esta búsqueda no equivale a un escáner completo de secretos ni revisa todo el historial Git.
- Suite existente: 83 tests, cero fallos. Las pruebas funcionales existentes no son una certificación de seguridad.
- Pruebas propias contra servicios sintéticos que escuchan solo en 127.0.0.1, con credenciales ficticias, descarga limitada a 33 MiB, un único cliente con cabecera incompleta y un archivo marcador en /tmp. No se accedió al llavero ni a servidores/archivos personales. Los servicios de prueba se cancelaron al finalizar.
- El probe usa los objetos compilados de MacIPTVCore. Es un ejecutable CLI y no reproduce las políticas ATS de un bundle; la admisión de HTTP en el paquete se confirma además por su Info.plist y la documentación de Apple.
- No se hizo fuzzing exhaustivo, auditoría de binarios de Apple, interceptación de una red real ni prueba de explotación contra terceros. No se verificó el comportamiento de historial/caché de VLC o IINA.

## S-01 — Medio/alto según exposición: credenciales sin cifrar cuando se usa HTTP

**Evidencia:** `Sources/MacIPTVCore/XtreamAPI.swift:16` antepone `http://` a una dirección sin esquema. Las líneas 54–64 introducen usuario y contraseña en las consultas de lista y guía. `scripts/Info.plist:16` activa globalmente `NSAllowsArbitraryLoads`. Las listas M3U y las URLs de vídeo también pueden contener credenciales o tokens.

**Prueba:** se construyó un endpoint Xtream con host sin esquema y credenciales ficticias. Un servidor HTTP de prueba pudo reconocer ambos valores directamente en la primera línea de la petición TCP, sin descifrado.

**Impacto y condición:** quien pueda observar o modificar esa conexión sin cifrar —por ejemplo mediante un intermediario de red— puede obtener la suscripción o sustituir listas/manifiestos. Usar Wi-Fi no significa por sí solo que cualquier usuario de esa red pueda leer el tráfico: se requiere una posición de observación/intercepción. La URL del proveedor no es una clave SSH, contraseña de macOS ni acceso al llavero completo.

**Corrección recomendada:** usar HTTPS por defecto; pedir una elección explícita para proveedores que solo funcionen por HTTP; impedir redirecciones de HTTPS a HTTP; aplicar una política equivalente a recursos HLS y guías. No eliminar sin más las claves ATS: la app debe conservar un flujo deliberado de compatibilidad y probarlo dentro del bundle. HTTPS sigue validando los certificados con las APIs normales, pero la excepción ATS reduce los requisitos adicionales de transporte.

Fuente: [Apple: NSAllowsArbitraryLoads](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowsarbitraryloads).

## S-02 — Medio: peticiones a servicios internos desde manifiestos no confiables

**Evidencia:** `Sources/MacIPTVCore/HLSRelayRegistry.swift:100` acepta recursos HTTP/HTTPS sin limitar direcciones privadas, loopback o link-local. `Sources/MacIPTVCore/HLSRelay.swift:85` los convierte en peticiones URLSession. No hay delegado que compruebe el destino de cada redirección. `M3UParser.swift:134` tampoco restringe los destinos de canales por ámbito de red; el camino AVPlayer directo debe considerarse en una solución completa.

**Prueba:** el manifiesto de un servidor sintético `localhost:puerto-A` incluyó un segmento `127.0.0.1:puerto-B`. Al solicitar su URL reescrita al relay, este hizo GET al segundo servicio y devolvió su respuesta sintética. Ambos servicios fueron creados específicamente para la prueba. No se escanearon puertos ni se consultaron servicios reales.

**Impacto y condición:** un proveedor malicioso, una lista manipulada o un atacante que sustituya una respuesta HTTP puede provocar peticiones GET desde el equipo a endpoints internos cuando el reproductor solicita los recursos. Un servicio local o de la LAN que confíe en el origen de la petición, no tenga autenticación o permita acciones por GET puede quedar expuesto a ese comportamiento.

**Severidad:** media con la evidencia disponible; sería alta si se identifica un servicio interno explotable o un mecanismo de extracción de sus respuestas.

**Límite importante:** se confirmó la petición y el retorno al cliente local del relay. No se demostró que el proveedor remoto pueda leer la respuesta de un servicio interno, robar archivos arbitrarios o ejecutar comandos. El ataque puede ser ciego y depende de los servicios accesibles y de los permisos de red del sistema.

**Corrección recomendada:** separar la fuente local elegida expresamente por el usuario de recursos aportados por fuentes remotas; bloquear por defecto loopback, redes privadas, link-local y rangos reservados para estos últimos, con excepciones locales explícitas. Comprobar IPv4/IPv6, resolución DNS y redirecciones en cada salto; un filtro textual del hostname no evita DNS rebinding. Admitir CDN públicos legítimos. La ruta loopback generada por la propia app debe seguir funcionando.

Referencia defensiva: [OWASP: SSRF Prevention](https://cheatsheetseries.owasp.org/cheatsheets/Server_Side_Request_Forgery_Prevention_Cheat_Sheet.html).

## S-03 — Medio: límites insuficientes frente a agotamiento de memoria/CPU

**Evidencia:** `Sources/MacIPTVCore/ContentFetcher.swift:33` descarga toda la respuesta en memoria y no impone un tamaño máximo. Las listas y guías se transforman después en strings, canales y programas sin límites de cantidad o longitud. `HLSRelay.swift:95` también descarga el cuerpo completo; el control de 32 MiB de la línea 102 ocurre al finalizar, no mientras llegan los datos. El historial del registro está limitado por revisiones, pero no por cantidad de recursos que una sola lista pueda declarar.

**Prueba:** ContentFetcher aceptó 33 MiB de datos sintéticos. El relay descargó esa misma respuesta antes de devolver 502 por exceso de tamaño. La prueba fue acotada; no se intentó agotar la memoria del ordenador.

**Impacto:** un proveedor malicioso o defectuoso puede provocar consumo elevado de memoria, lentitud o cierre de la app. Los timeouts no limitan los bytes enviados antes de vencer. No se ha demostrado corrupción de memoria ni ejecución de código.

**Corrección recomendada:** descarga incremental con límite durante recepción, cancelación inmediata al superarlo y límites diferentes para lista, guía, manifiesto y segmento; límites de canales, programas, longitud de campos y recursos registrados; presupuestos de concurrencia. No confiar únicamente en Content-Length.

Referencia: [Apple: recepción de datos en memoria con URLSession](https://developer.apple.com/documentation/foundation/fetching-website-data-into-memory).

## S-04 — Bajo, atacante local: conexiones incompletas sin plazo ni cupo

**Evidencia:** `Sources/MacIPTVCore/HLSRelay.swift:63` conserva cada conexión, y las líneas 68–72 esperan una cabecera completa sin deadline. El límite de bytes de cabecera no limita cuánto tiempo permanece abierta. No hay máximo de conexiones aceptadas. El timeout de URLSession solo afecta a peticiones upstream, que todavía no se han iniciado en este caso.

**Prueba:** una conexión local envió únicamente `GET /`. Tras 20 segundos el relay no había respondido ni cerrado la conexión. Se canceló al terminar la prueba.

**Impacto y condición:** otro proceso local que encuentre el puerto puede ocupar conexiones y tareas sin conocer el UUID, porque la autenticación de la ruta ocurre después de leer la cabecera. El relay no está expuesto directamente a otras máquinas: escucha en 127.0.0.1. No se probó un ataque desde navegador; no se afirma que un sitio web remoto pueda mantener estas conexiones arbitrarias.

**Corrección recomendada:** deadline de lectura de cabeceras, máximo de conexiones activas y máximo de descargas simultáneas, cancelando clientes que excedan el presupuesto.

## S-05 — Carencia de endurecimiento: falta de contención y protección de integridad en ejecución

**Evidencia:** `codesign -dvvv` devuelve `flags=0x2(adhoc)`, sin el flag `runtime`; la extracción de entitlements no muestra App Sandbox. `scripts/build-app.sh:14` firma sin `--options runtime` ni entitlements.

**Impacto:** si aparece una vulnerabilidad en la app o en su tratamiento de datos no confiables, el proceso dispone de más acceso a archivos y recursos que una app aislada. La falta de Hardened Runtime reduce defensas contra inyección y manipulación del proceso. Esto no es por sí solo una prueba de robo de datos, una vía de RCE ni una concesión de permisos de administrador. TCC, SIP, permisos de archivos y otras protecciones de macOS siguen aplicándose.

**Corrección recomendada:** activar Hardened Runtime con las mínimas excepciones y adoptar App Sandbox con permisos limitados a red cliente, servidor local y archivos elegidos por el usuario. Para recordar listas locales, diseñar persistencia con bookmarks de ámbito de seguridad en lugar de depender únicamente de una ruta. Verificar los flujos de llavero y VLC/IINA después del cambio.

Fuentes: [Apple: App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox), [Apple: Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime).

## S-06 — Riesgo de distribución, no exploit confirmado: no existe identidad verificable del editor

**Evidencia:** el paquete tiene `Signature=adhoc`, `TeamIdentifier=not set`; el empaquetado no usa Developer ID ni solicita/staplea una notarización. La firma ad hoc del bundle se verifica, pero eso no acredita al editor.

**Impacto y condición:** la firma local detecta modificaciones que invaliden esa firma, pero un tercero puede sustituir el paquete y generar otra firma ad hoc. No se demostró manipulación de este ZIP ni malware en el paquete actual. Para terceros que descarguen la app, falta una cadena de identidad del desarrollador y la comprobación de notarización de Apple.

**Corrección recomendada antes de publicar:** Developer ID, Hardened Runtime, timestamp, notarización y entrega por un canal de distribución autenticado. Publicar hashes en el mismo canal comprometido no sustituye una identidad verificable. La notarización tampoco certifica ausencia de vulnerabilidades.

Fuente: [Apple: notarización antes de distribuir](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## Consideraciones de privacidad adicionales

- `ExternalPlayer.open`, en `ContentView.swift:327`, entrega la URL original completa a VLC/IINA por una acción explícita del usuario. Si lleva credenciales, la app externa las recibe. No se verificó si estas versiones las guardan en historial, logs o caché; es una frontera de confianza y merece una explicación clara en el producto.
- Una lista M3U local puede contener contraseñas en texto. Guardar su ruta en el llavero no cifra ni elimina el archivo original ni sus copias de seguridad. Ese archivo es aportado por el usuario, no creado por la importación.
- El proveedor y los CDN contactados conocen la IP y las peticiones de la sesión; eso forma parte del transporte de vídeo. No se observó telemetría propia del desarrollador.
- Las credenciales descifradas y tokens están en memoria durante el uso. No se auditó la información que puedan retener crash reports o mecanismos de diagnóstico/caché del sistema y reproductores externos.

## Protecciones comprobadas

- Configuración guardada mediante Security/Keychain; no se encontró persistencia de usuario/contraseña de fuente en UserDefaults. Los favoritos y recientes contienen identificadores hash.
- Diagnósticos propios restringidos a eventos, métricas y errores redactados; las pruebas contra descripciones y dominios que contienen secretos pasan. No se leyeron los logs personales existentes.
- ContentFetcher usa URLSession efímero con caché de disco deshabilitada. El relay también usa sesión efímera.
- No hay código que acepte certificados TLS arbitrarios o desactive la validación normal del servidor.
- Relay en 127.0.0.1, puerto dinámico y rutas UUID; una ruta desconocida devolvió 404 sin contactar al destino upstream. No es un proxy de destino arbitrario accesible sin la ruta privada, aunque un manifiesto sí puede registrar destinos internos.
- En la prueba de entidad XML externa, XMLTVParser no incorporó el contenido del archivo marcador. El comportamiento coincide con el valor por defecto de `shouldResolveExternalEntities=false` documentado por Apple. Sería prudente fijar explícitamente la política para que futuros cambios no dependan de ese valor por defecto.
- No se encontró uso de shell, Process, WebView, JavaScript, carga dinámica de plugins ni buffers inseguros en los targets de producción. Las URLs importadas de canales se limitan a HTTP/HTTPS; NSWorkspace abre aplicaciones concretas y no interpola URLs en comandos.
- El bundle inspeccionado contiene el ejecutable, icono, Info.plist y firma; no lleva ayudantes privilegiados, agentes de arranque ni scripts de instalación. Package.swift no declara dependencias externas; las bibliotecas enlazadas inspeccionadas son del sistema Apple.

Referencia XML: [Apple: shouldResolveExternalEntities](https://developer.apple.com/documentation/foundation/xmlparser/shouldresolveexternalentities).

## Revisión independiente

Una segunda revisión de solo lectura no encontró otra filtración concreta en llavero, diagnósticos, XMLTV ni apertura de reproductores externos. Se ajustó la clasificación para distinguir impacto confirmado de escenarios condicionados: peticiones internas no equivalen a exfiltración; conexiones incompletas son un riesgo local; firma ad hoc y ausencia de aislamiento son carencias de endurecimiento/distribución, no exploits por sí solos.

## Orden de remediación

1. HTTPS por defecto y compatibilidad HTTP deliberada; controles de destinos de red y redirecciones.
2. Límites reales durante descargas, lectura de cabeceras y concurrencia.
3. Hardened Runtime y App Sandbox con validación de importación, reproducción y llavero.
4. Firma Developer ID y notarización antes de distribuir; documentación de fronteras de privacidad con archivos locales y reproductores externos.

No se cambiaron las políticas ni el código de producción durante esta revisión. El informe registra riesgos pendientes, no correcciones ya realizadas.


## Remediación aplicada — versión 0.3.0, build 9

El informe anterior describe el código y el paquete previos. Tras la autorización del usuario se aplicaron las siguientes correcciones, sin adquirir Developer ID:

| Hallazgo | Estado y cambio |
| --- | --- |
| S-01, HTTP/credenciales | HTTPS por defecto para Xtream; permiso HTTP explícito por fuente guardado en Keychain. La migración de datos antiguos no concede permiso. Se exige también si una lista HTTPS contiene canales o guía HTTP; recursos HLS HTTP detectados durante reproducción solicitan permiso para la fuente y generación vigentes. Downgrade de redirección HTTPS a HTTP siempre bloqueado. |
| S-02, destinos internos | NetworkPolicy verifica URLs, redirecciones y recursos HLS. Gateway SOCKS5 autenticado, efímero y local resuelve y comprueba todas las IP, conecta a direcciones numéricas verificadas y no permite fallback directo. Excepciones solo para IP literal/puerto exactos, nunca nombres DNS ni alias. TLS permanece entre URLSession y el destino. |
| S-03, consumo de recursos | Descargas limitadas durante recepción, sin acumulación ilimitada ni copias completas por cada fragmento. M3U 8 MiB, guía 64 MiB, manifiesto 512 KiB, segmento 32 MiB, clave 4 KiB. Límites de elementos, líneas y campos en parsers. XMLTV rechaza DTD y entidades externas. Sesión efímera, sin caché de disco ni almacén de credenciales URLSession. |
| S-04, conexiones locales | Límites de clientes, cabecera 16 KiB, deadline de cabecera 5 s, petición 75 s, handshake del gateway 10 s y operaciones de socket con plazos. Abandono de petición cancela su descarga; stop solicita cancelación de sockets locales y remotos antes de arrancar el siguiente relay. DNS libera al solicitante por deadline/cancelación y mantiene como máximo cuatro trabajadores de sistema pendientes. |
| S-05, aislamiento | App Sandbox y Hardened Runtime con firma ad hoc. Permisos mínimos para red y archivos elegidos de solo lectura; bookmarks persistentes. Ensayos del bundle firmado confirman bloqueo de archivo no seleccionado, HTTPS, loopback, reproducción y permiso de lectura sin escritura tras reiniciar. |
| S-06, distribución | Sigue pendiente identidad Developer ID/notarización, por decisión del usuario de no contratarlo. Se entrega firma local verificable y SHA-256 del ZIP. Un atacante que sustituya el ZIP y su checksum sigue sin quedar autenticado por estas medidas. |

Se añadió confirmación antes de enviar la URL original a VLC/IINA. Las listas locales originales siguen siendo archivos aportados por el usuario: no se cifran ni se borran. El reproductor integrado se limita a HLS para que AVFoundation reciba referencias controladas por el relay; otros formatos directos, DRM y content steering se remiten al reproductor externo.

Validación: 120 tests pasan; revisión independiente seguida de correcciones y regresiones; ensayos firmados de aislamiento, archivo/bookmark, HTTPS y recuperación de vídeo público. La interfaz del paquete se comprobó con --demo, sin consultar el llavero personal ni contactar la suscripción real. Véase docs/validation.md para evidencia y límites. No se garantiza ausencia de vulnerabilidades ni compatibilidad de todos los proveedores. getaddrinfo del sistema puede continuar tras cancelar su solicitante, pero sus trabajadores y resultados tardíos quedan acotados. Las herramientas del sistema, TCC, AVFoundation, macOS y reproductores externos conservan sus propias fronteras de confianza.

La firma local gratuita permite estas defensas técnicas. La autenticación del editor y la notarización se rigen por el flujo de distribución de Apple: [Apple, distribuir fuera de Mac App Store](https://help.apple.com/xcode/mac/current/en.lproj/dev033e997ca.html).
