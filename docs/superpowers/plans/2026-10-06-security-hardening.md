# MacIPTV: endurecimiento de seguridad sin Developer ID

Objetivo autorizado: corregir los riesgos del informe del 6 de octubre manteniendo proveedores HTTP con consentimiento explícito. Firma ad hoc gratuita; no se intentará notarizar ni desactivar Gatekeeper.

## Diseño e interfaces

- NetworkPolicy: HTTPS por defecto, autorización HTTP por fuente, excepciones locales limitadas a endpoints expresamente elegidos. IPv4/IPv6 y DNS sin destinos internos implícitos. Cada conexión upstream pasa por un gateway SOCKS5 autenticado en loopback que resuelve, valida y conecta a la IP comprobada; URLSession conserva TLS y SNI originales. Sin fallback de proxy. Esto evita la carrera de comprobar DNS y volver a resolverlo al conectar.
- SecureHTTPClient: URLSession efímera con límites durante recepción, redirecciones verificadas, timeout y cancelación. Importación y relay utilizan la misma política. Límites de bytes diferenciados.
- Todo vídeo integrado HLS pasa por el relay; sin camino AVPlayer directo que eluda la política de subrecursos. Límites de conexiones, lectura de cabeceras, recursos y descargas; rechazo de protocolos no HTTP(S) en manifiestos.
- Persistencia: SavedSource contiene fuente, consentimientos y bookmark de archivo. Lectura compatible con configuración antigua del llavero, sin consentimiento HTTP implícito. La fuente previa permanece ante errores. Archivos elegidos con NSOpenPanel usan bookmarks solo lectura.
- Interfaz: elección HTTP explícita y consentimiento recuperable al abrir una fuente anterior HTTP; servidores locales solo por endpoint explícito. Aviso antes de pasar URL con credenciales a otro reproductor. No se muestran secretos.
- Bundle: App Sandbox (red cliente/servidor y archivos elegidos solo lectura/bookmarks), Hardened Runtime sin excepciones, firma ad hoc y hash SHA-256 del ZIP. Documentar límites de identidad/notarización.

## Ejecución y validación

1. Pruebas de regresión previas: HTTPS por defecto, rechazo HTTP sin consentimiento, límites, redes internas IPv4/IPv6, redirecciones, DNS conectado a IP validada y accesos locales explícitos.
2. Gateway seguro y cliente de descarga; pruebas sintéticas locales y petición HTTPS pública sin credenciales para conservar validación TLS.
3. Límites de parsers/XMLTV y entidades externas (tarea independiente).
4. Relay completo y reproducción con política; comprobar cabeceras incompletas/cupos y un stream HLS público mediante PlayerView.
5. SavedSource, bookmarks y consentimientos; comprobar decodificación heredada sin leer llavero personal y estado demo.
6. Empaquetar 0.3.0, comprobar entitlements/runtime, arranque de bundle con fixture (sin fuente personal), aislamiento de archivos y acceso a bookmark tras relanzar.
7. Suite completa, revisión independiente, documentación del resultado y limitaciones. No commits/push ni cambios a credenciales del usuario.
