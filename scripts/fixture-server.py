"""Local provider fixture for manual import/error/guide checks. No credentials required."""
from http.server import BaseHTTPRequestHandler, HTTPServer
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path in ("/playlist.m3u", "/get.php"):
            data = (ROOT / "Examples/demo.m3u").read_bytes()
            mime = "audio/x-mpegurl"
        elif path in ("/guide.xml", "/xmltv.php"):
            now = datetime.now(timezone.utc).replace(minute=0, second=0, microsecond=0)
            programmes = []
            for channel in ("demo.nature", "demo.news", "demo.cinema"):
                for hour in range(-1, 6):
                    start = now + timedelta(hours=hour)
                    stop = start + timedelta(hours=1)
                    programmes.append(
                        f'<programme channel="{channel}" start="{start:%Y%m%d%H%M%S %z}" stop="{stop:%Y%m%d%H%M%S %z}">'
                        f'<title>Programa demo {hour + 2}</title><desc>Programación ficticia para validar XMLTV.</desc></programme>'
                    )
            data = ('<?xml version="1.0" encoding="UTF-8"?><tv>' + ''.join(programmes) + '</tv>').encode()
            mime = "application/xml"
        elif path == "/empty.m3u":
            data, mime = b"#EXTM3U\n", "audio/x-mpegurl"
        elif path == "/invalid.xml":
            data, mime = b"<tv><programme>", "application/xml"
        else:
            self.send_response(503)
            self.end_headers()
            self.wfile.write(b"Fixture unavailable")
            return
        self.send_response(200)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


print("Fixture: http://127.0.0.1:18768/playlist.m3u; XMLTV: /guide.xml", flush=True)
HTTPServer(("127.0.0.1", 18768), Handler).serve_forever()
