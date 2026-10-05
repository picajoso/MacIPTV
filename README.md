# MacIPTV

Aplicación nativa para macOS 14 o posterior, con navegación de canales inspirada en TiviMate. Proyecto para usar tu propia suscripción IPTV.

## Compilar y abrir

Necesitas las herramientas Swift de Xcode. Desde esta carpeta:

```sh
swift test --disable-sandbox
bash scripts/build-app.sh
open dist/MacIPTV.app
```

La aplicación queda en `dist/MacIPTV.app`. Puedes copiarla a Aplicaciones. La compilación local tiene firma ad hoc, sin notarización de Apple.

El paquete incluido se ha compilado para Apple Silicon. Para un Mac Intel, compila el proyecto en ese equipo.

## Conectar tu proveedor

Introduce los datos dentro de la aplicación. No hace falta compartir contraseñas en el chat ni guardarlas en este proyecto.

- **M3U:** URL de la lista o archivo local; URL XMLTV opcional para la programación.
- **Xtream:** dirección del servidor con puerto si procede, usuario y contraseña.

Puedes probar la interfaz con el modo demostración, que utiliza programación ficticia y un vídeo de prueba público de Apple. La compatibilidad de una suscripción real requiere comprobar sus canales.

## Reproducción

El reproductor integrado usa AVFoundation con una superficie AVPlayerLayer y controles propios. Desde 0.1.1, reconoce las URLs MPEG-TS de Xtream (`/live/usuario/clave/ID.ts`) y solicita su variante HLS (`.m3u8`) para reproducirlas dentro de la app. Usa un perfil HTTP compatible con VLC para servidores que rechazan agentes genéricos. Desde 0.1.5, un adaptador HLS nativo local mantiene estable la identidad de cada segmento y actualiza sus tokens cuando el proveedor renueva las URLs. El adaptador solo escucha en 127.0.0.1, usa rutas opacas y mantiene las URLs autorizadas en memoria. No requiere Python ni un servicio externo. La lista y la URL original se conservan. Servidores sin variante HLS y otros códecs pueden necesitar VLC/IINA. La guía aparece cuando XMLTV entrega identificadores coincidentes.

Esta versión se centra en televisión en directo, grupos, búsqueda, favoritos y guía. No incluye grabación, catálogo VOD, catch-up ni DRM.

## Novedades de 0.2.0

Recientes conserva los últimos 20 canales, sin duplicados. El botón «Canal anterior» alterna entre los dos últimos canales seleccionados. Favoritos conserva su orden: clic derecho en un favorito y «Subir favorito» o «Bajar favorito». El historial y el orden se guardan localmente como identificadores; la demo no modifica las preferencias de la suscripción.

## Controles

Selecciona un grupo y pulsa un canal para reproducirlo. La estrella añade o quita favoritos. El botón Guía muestra la programación del grupo seleccionado; pulsa una fila para ver ese canal. La barra inferior del reproductor permite pausar, silenciar, ajustar el volumen y activar la pantalla completa. Se oculta tras tres segundos sin mover el puntero; vuelve al moverlo y permanece visible durante la pausa o el búfer. Al cambiar de canal aparece brevemente su nombre y programa actual.

- `⌥⌘↓` / `⌥⌘↑`: canal siguiente / previo en la lista visible.
- `⌥⌘←`: volver al canal anterior.
- `⌘F`: pantalla completa.
- `⌘R`: actualizar la fuente guardada.
- `⌘,`: configuración del proveedor.
- Flechas arriba/abajo con el reproductor enfocado: cambiar de canal.

## Privacidad

La configuración que contiene credenciales se guarda en el Llavero de macOS. Las conexiones van directamente a tu proveedor; no hay un servicio intermediario ni telemetría propia. Las conexiones HTTP que algunos proveedores exigen no cifran el transporte; utiliza HTTPS cuando tu proveedor lo admita.

Al recompilar con firma ad hoc, macOS puede considerar que la aplicación ha cambiado y denegar el acceso a una fuente guardada anteriormente. El arranque no abre diálogos de autenticación ni bloquea la ventana. Si aparece ese error, pulsa «Autorizar llavero» y responde al diálogo de macOS. La consulta se realiza en segundo plano. Para el uso diario, conserva el mismo paquete de la aplicación.

## Diagnóstico

La versión 0.1.5 corrige los cortes repetidos de unos 30 segundos causados por URLs de segmentos HLS con tokens que cambian entre renovaciones. Conserva el diagnóstico detallado y la recuperación de 0.1.4, que detecta las emisiones detenidas y realiza hasta tres reconexiones automáticas, con esperas de 2, 4 y 8 segundos. Un vídeo que no avanza durante 15 segundos activa la recuperación; pausar voluntariamente no reconecta. Tras un minuto de reproducción continua se restablece el límite. Incluye los controles propios de 0.1.3 y la corrección ATS para listas HTTP. Al actualizar, cierra y vuelve a abrir la app.

Los errores muestran dominio, código y categoría de red/reproducción. El diagnóstico también registra cada cinco segundos el avance, el búfer y las métricas del reproductor, junto con códigos HTTP, duración y secuencia de las listas HLS. El menú «… → Abrir diagnostico» abre `~/Library/Logs/MacIPTV/diagnostics.log`. El archivo mantiene las últimas 200 entradas y no contiene URLs, rutas de canales, credenciales ni descripciones arbitrarias del servidor.

La dirección Xtream debe escribirse con `http://` o `https://`, incluyendo los dos puntos, o como un nombre de servidor sin esquema. Las variantes mal escritas como `http//` se rechazan antes de conectar.

## Desarrollo

[CLAUDE.md](CLAUDE.md) describe la arquitectura, las decisiones de implementación, la evolución de las versiones y el trabajo pendiente. [docs/validation.md](docs/validation.md) conserva las comprobaciones realizadas y sus límites.
