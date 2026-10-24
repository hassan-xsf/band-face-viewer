# Band Viewer server: serves the viewer and lists every .face in faces/
# The page polls the list, so new or rebuilt faces show up (and
# reload) on their own.
# Usage: python serve.py [some.face ...]   (given files are copied into faces/)
import http.server
import json
import shutil
import sys
import time
import webbrowser
from pathlib import Path
from urllib.parse import unquote, quote

HERE = Path(__file__).resolve().parent
DIRS = {"faces": HERE / "faces"}
PORT = 8770


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **k):
        super().__init__(*a, directory=str(HERE), **k)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def send_body(self, body, ctype):
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = unquote(self.path.split("?", 1)[0])
        if path == "/api/faces":
            items = []
            for d, root in DIRS.items():
                for p in sorted(root.glob("*.face")) if root.is_dir() else []:
                    st = p.stat()
                    if time.time() - st.st_mtime < 1:  # still being copied/compiled
                        continue
                    items.append({"dir": d, "name": p.name, "size": st.st_size, "mtime": st.st_mtime,
                                  "url": f"f/{d}/{quote(p.name)}"})
            return self.send_body(json.dumps(items).encode(), "application/json")
        if path.startswith("/f/"):
            _, _, d, name = path.split("/", 3)
            root = DIRS.get(d)
            p = (root / name).resolve() if root else None
            if not p or p.parent != root.resolve() or not p.is_file():  # no path tricks
                return self.send_error(404)
            return self.send_body(p.read_bytes(), "application/octet-stream")
        return super().do_GET()

    def log_message(self, *a):
        pass


def main():
    DIRS["faces"].mkdir(exist_ok=True)
    first = None
    for arg in sys.argv[1:]:
        src = Path(arg)
        if src.suffix.lower() == ".face" and src.is_file():
            shutil.copy2(src, DIRS["faces"] / src.name)
            first = first or src.name
    url = f"http://127.0.0.1:{PORT}/" + (f"#faces/{quote(first)}" if first else "")
    try:
        server = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    except OSError:  # already running: just open the page
        webbrowser.open(url)
        return
    print(f"Band Viewer on {url}  (Ctrl+C to stop)")
    print(f"Drop .face files into {DIRS['faces']}")
    webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
