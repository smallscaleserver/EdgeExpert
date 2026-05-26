"""
Fingerprint-based auto-login for public Open WebUI.
No tokens, no passwords, no manual login.

On every request nginx calls GET /check — valid JWT cookie → 200, else → 401.
On 401 nginx redirects browser to GET /login (fingerprint HTML page).
JS collects UA + Timezone + Screen, POSTs to /do-login.
If fingerprint known → sign in.  If new → auto-create account → sign in.
JWT cookie is set and browser navigates to /.
"""

import datetime
import hashlib
import json
import os
import secrets

import httpx
import jwt as pyjwt
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import HTMLResponse, JSONResponse, Response

app = FastAPI()

DEVICES_FILE     = os.environ.get("DEVICES_FILE",     "/data/devices.json")
ADMIN_CREDS_FILE = os.environ.get("ADMIN_CREDS_FILE", "/data/.admin-creds")
WEBUI_URL        = os.environ.get("WEBUI_INTERNAL_URL", "http://edge-open-webui-public:8080")
WEBUI_SECRET_KEY = os.environ.get("WEBUI_SECRET_KEY", "")
COOKIE_MAX_AGE   = 60 * 60 * 24 * 30  # 30 days

# ---------------------------------------------------------------------------

def _load(path: str) -> dict:
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return {}


def _save(path: str, data: dict) -> None:
    with open(path, "w") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")


def _fingerprint(ua: str, tz: str, screen: str) -> str:
    return hashlib.sha256(f"{ua}|{tz}|{screen}".encode()).hexdigest()[:16]


def _now() -> str:
    return datetime.datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC")

# ---------------------------------------------------------------------------
# JWT validation (local — fast, no network call on every request)
# ---------------------------------------------------------------------------

def _jwt_valid(token: str) -> bool:
    if not token or not WEBUI_SECRET_KEY:
        return False
    try:
        pyjwt.decode(
            token,
            WEBUI_SECRET_KEY,
            algorithms=["HS256"],
            options={"verify_exp": False},
        )
        return True
    except Exception:
        return False

# ---------------------------------------------------------------------------
# Open WebUI API helpers
# ---------------------------------------------------------------------------

async def _signup(name: str, email: str, password: str) -> str | None:
    async with httpx.AsyncClient(timeout=10.0) as c:
        r = await c.post(
            f"{WEBUI_URL}/api/v1/auths/signup",
            json={"name": name, "email": email, "password": password},
        )
        if r.status_code == 200:
            return r.json().get("token")
    return None


async def _signin(email: str, password: str) -> str | None:
    async with httpx.AsyncClient(timeout=10.0) as c:
        r = await c.post(
            f"{WEBUI_URL}/api/v1/auths/signin",
            json={"email": email, "password": password},
        )
        if r.status_code == 200:
            return r.json().get("token")
    return None


async def _admin_create_user(name: str, email: str, password: str) -> bool:
    """Create user via admin API when signup endpoint is disabled."""
    creds = _load(ADMIN_CREDS_FILE)
    if not creds:
        return False
    admin_jwt = await _signin(creds["email"], creds["password"])
    if not admin_jwt:
        return False
    async with httpx.AsyncClient(timeout=10.0) as c:
        r = await c.post(
            f"{WEBUI_URL}/api/v1/users/add",
            json={"name": name, "email": email, "password": password, "role": "user"},
            headers={"Authorization": f"Bearer {admin_jwt}"},
        )
        return r.status_code == 200


async def _ensure_admin() -> None:
    """Create admin account on first run (first Open WebUI signup = admin)."""
    if _load(ADMIN_CREDS_FILE):
        return
    email    = "admin@public-webui.local"
    password = secrets.token_hex(16)
    token    = await _signup("Admin", email, password)
    if token:
        _save(ADMIN_CREDS_FILE, {"email": email, "password": password})
        os.chmod(ADMIN_CREDS_FILE, 0o600)

# ---------------------------------------------------------------------------
# Fingerprint HTML (shown while auto-login happens — user sees this ~1 second)
# ---------------------------------------------------------------------------

_LOGIN_HTML = """<!DOCTYPE html>
<html lang="th">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>กำลังเชื่อมต่อ…</title>
  <style>
    body{font-family:sans-serif;display:flex;align-items:center;justify-content:center;
         min-height:100vh;margin:0;background:#f5f5f5;color:#444}
    .box{text-align:center;padding:2em}
    .spinner{width:40px;height:40px;border:4px solid #ddd;border-top-color:#555;
             border-radius:50%;animation:spin .8s linear infinite;margin:0 auto 1em}
    @keyframes spin{to{transform:rotate(360deg)}}
  </style>
</head>
<body>
  <div class="box">
    <div class="spinner"></div>
    <p>กำลังเชื่อมต่อ กรุณารอสักครู่…</p>
  </div>
  <script>
    (async () => {
      const fp = {
        tz:     Intl.DateTimeFormat().resolvedOptions().timeZone || "unknown",
        screen: (screen.width||0)+"x"+(screen.height||0)+"@"+(screen.colorDepth||0)
      };
      try {
        const r = await fetch("/do-login", {
          method: "POST",
          credentials: "same-origin",
          headers: {"Content-Type": "application/json"},
          body: JSON.stringify(fp)
        });
        const d = await r.json();
        if (d.redirect) { window.location.replace(d.redirect); return; }
        document.querySelector("p").textContent = "❌ " + (d.error || "เกิดข้อผิดพลาด");
        document.querySelector(".spinner").style.display = "none";
      } catch(e) {
        document.querySelector("p").textContent = "❌ ไม่สามารถเชื่อมต่อ: " + e;
        document.querySelector(".spinner").style.display = "none";
      }
    })();
  </script>
</body>
</html>"""

# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@app.get("/check")
async def check(request: Request) -> Response:
    """Called by nginx auth_request on every proxied request."""
    token = request.cookies.get("token", "")
    if _jwt_valid(token):
        return Response(status_code=200)
    raise HTTPException(status_code=401)


@app.get("/login")
async def login_page() -> HTMLResponse:
    return HTMLResponse(_LOGIN_HTML)


@app.post("/do-login")
async def do_login(request: Request) -> JSONResponse:
    body: dict = {}
    try:
        body = await request.json()
    except Exception:
        pass

    ua     = request.headers.get("user-agent", "unknown")
    tz     = body.get("tz",     "unknown")
    screen = body.get("screen", "unknown")
    fp     = _fingerprint(ua, tz, screen)

    devices = _load(DEVICES_FILE)

    if fp in devices:
        device = devices[fp]
        if not device.get("enabled", True):
            return JSONResponse({"error": "การเข้าถึงถูกปิดใช้งาน กรุณาติดต่อผู้ดูแล"}, status_code=403)
        jwt_token = await _signin(device["email"], device["password"])
        if not jwt_token:
            return JSONResponse({"error": "signin failed — contact admin"}, status_code=502)
    else:
        # New device — auto-create account
        await _ensure_admin()
        email    = f"fp-{fp}@public-webui.local"
        password = secrets.token_hex(16)

        jwt_token = await _signup(f"user-{fp[:6]}", email, password)
        if not jwt_token:
            # signup closed → use admin API
            ok = await _admin_create_user(f"user-{fp[:6]}", email, password)
            if not ok:
                return JSONResponse({"error": "cannot create account — contact admin"}, status_code=502)
            jwt_token = await _signin(email, password)
            if not jwt_token:
                return JSONResponse({"error": "signin after creation failed"}, status_code=502)

        devices[fp] = {
            "email":       email,
            "password":    password,
            "enabled":     True,
            "first_seen":  _now(),
        }

    devices[fp].update({
        "last_seen": _now(),
        "device": {"user_agent": ua, "timezone": tz, "screen": screen},
    })
    _save(DEVICES_FILE, devices)

    response = JSONResponse({"redirect": "/"})
    response.set_cookie(
        "token", jwt_token,
        max_age=COOKIE_MAX_AGE,
        httponly=True,
        samesite="lax",
        path="/",
    )
    return response


@app.get("/health")
async def health() -> dict:
    return {"ok": True}
