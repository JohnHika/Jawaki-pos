import base64, hashlib, hmac, json, struct, sys, time, urllib.request, urllib.error

BASE = "http://localhost:3100/api/v1/platform-admin"
OWNER = ("qa-owner@aca.test", "QaOwner-Passw0rd!x")
results = []


def call(method, path, body=None, token=None, headers=None):
    req = urllib.request.Request(BASE + path, method=method)
    req.add_header("content-type", "application/json")
    req.add_header("x-aca-device", "QA harness")
    if token:
        req.add_header("authorization", f"Bearer {token}")
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    data = json.dumps(body).encode() if body is not None else None
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, data=data, timeout=60) as r:
                raw = r.read().decode()
                return r.status, (json.loads(raw) if raw else None)
        except urllib.error.HTTPError as e:
            raw = e.read().decode()
            try:
                parsed = json.loads(raw)
            except Exception:
                parsed = raw
            if e.code == 429 and attempt < 3:
                # API rate limiter (10 logins/min) - wait out the 60s window
                print("   .. rate limited, waiting 62s", flush=True)
                time.sleep(62)
                continue
            return e.code, parsed


def check(name, cond, detail=""):
    results.append((name, bool(cond)))
    print(("PASS " if cond else "FAIL ") + name + (f"  -> {detail}" if not cond else ""))


def totp(secret_b32, at=None):
    key = base64.b32decode(secret_b32 + "=" * (-len(secret_b32) % 8))
    counter = int((at or time.time()) // 30)
    h = hmac.new(key, struct.pack(">Q", counter), hashlib.sha1).digest()
    o = h[-1] & 0xF
    code = (struct.unpack(">I", h[o:o + 4])[0] & 0x7FFFFFFF) % 10**6
    return f"{code:06d}"


# --- owner login (seeded from env on boot)
s, owner = call("POST", "/auth/login", {"email": OWNER[0], "password": OWNER[1]})
check("owner can sign in", s == 200 and owner.get("accessToken"), (s, owner))
tok = owner["accessToken"]
check("login response has role + permissions, no secrets", owner["admin"]["role"] == "OWNER" and "team.manage" in owner["admin"]["permissions"] and "passwordHash" not in json.dumps(owner))

s, me = call("GET", "/auth/me", token=tok)
check("/auth/me works", s == 200 and me["email"] == OWNER[0], (s, me))

# --- unauthenticated & tenant tokens are rejected
check("no token -> 401", call("GET", "/overview")[0] == 401)
check("garbage token -> 401", call("GET", "/overview", token="abc.def.ghi")[0] == 401)

# --- overview reads LIVE rows from the database
s, ov = call("GET", "/overview", token=tok)
check("overview 200", s == 200, (s, ov))
check("overview counts fixture tenants", ov["tenants"]["total"] >= 3, ov.get("tenants"))
check("overview revenue monthly has 6 buckets", len(ov["revenue"]["monthly"]) == 6)
check("overview shows pending claim + needs-attention", ov["billing"]["pendingClaims"] >= 1 and len(ov["needsAttention"]) >= 1, ov["billing"])
check("overview fleet counts the device", ov["fleet"]["devices"] >= 1)

s, tl = call("GET", "/tenants?search=fixture", token=tok)
check("tenant search", s == 200 and tl["total"] == 3, (s, tl.get("total") if isinstance(tl, dict) else tl))
tid = {t["name"]: t["id"] for t in tl["items"]}
mart, pharm = tid["QA Fixture Mart"], tid["QA Fixture Pharmacy"]
s, td = call("GET", f"/tenants/{mart}", token=tok)
check("tenant detail has isActive + counts", s == 200 and td["isActive"] is True and td["counts"]["users"] == 2, (s, td))
s, tu = call("GET", f"/tenants/{mart}/users", token=tok)
check("tenant users listed", s == 200 and tu["total"] == 2)
s, dv = call("GET", f"/tenants/{mart}/devices", token=tok)
check("tenant devices listed", s == 200 and dv["total"] == 1 and dv["items"][0]["appVersion"] == "1.0.74")
s, cl = call("GET", "/claims", token=tok)
check("claims listed", s == 200 and cl["total"] >= 1 and cl["items"][0]["mpesaCode"] == "QA1MPESA01", (s, cl))
s, inv = call("GET", "/invoices?status=PENDING", token=tok)
check("invoices filter", s == 200 and inv["total"] >= 1)

# --- team: create staff of each role
staff = {}
for role in ["SECURITY", "FINANCE", "SUPPORT", "VIEWER", "ADMIN"]:
    s, r = call("POST", "/team", {"email": f"{role.lower()}@aca.test", "name": f"QA {role.title()}", "role": role}, token=tok)
    check(f"owner creates {role}", s == 201 and r.get("temporaryPassword"), (s, r))
    staff[role] = r
s, dup = call("POST", "/team", {"email": "viewer@aca.test", "name": "Dup", "role": "VIEWER"}, token=tok)
check("duplicate email -> 409", s == 409)
s, bad = call("POST", "/team", {"email": "x@aca.test", "name": "X", "role": "GOD"}, token=tok)
check("invalid role -> 400", s == 400)

# --- forced password change gate
sec_pw = staff["SECURITY"]["temporaryPassword"]
s, sl = call("POST", "/auth/login", {"email": "security@aca.test", "password": sec_pw})
check("staff signs in with temp password", s == 200 and sl["admin"]["mustChangePassword"] is True, (s, sl))
stok = sl["accessToken"]
s, r = call("GET", "/overview", token=stok)
check("forced change blocks the dashboard (403 PASSWORD_CHANGE_REQUIRED)", s == 403 and r.get("code") == "PASSWORD_CHANGE_REQUIRED", (s, r))
s, r = call("POST", "/auth/change-password", {"currentPassword": sec_pw, "newPassword": "weak"}, token=stok)
check("weak password rejected", s == 400, (s, r))
NEWPW = "Sec-Team-Passw0rd!9"
s, r = call("POST", "/auth/change-password", {"currentPassword": sec_pw, "newPassword": NEWPW}, token=stok)
check("password changed", s == 200, (s, r))
s, r = call("GET", "/overview", token=stok)
check("dashboard opens after change", s == 200, (s, r))

# --- RBAC enforcement over HTTP
s, r = call("POST", "/team", {"email": "z@aca.test", "name": "Z", "role": "VIEWER"}, token=stok)
check("SECURITY cannot manage team (403)", s == 403 and r.get("code") == "MISSING_PERMISSION", (s, r))
s, r = call("POST", f"/tenants/{mart}/extend", {"days": 3}, token=stok)
check("SECURITY cannot extend subscriptions (403)", s == 403)
s, r = call("GET", "/security/overview", token=stok)
check("SECURITY can read the security centre", s == 200, (s, r))
s, r = call("GET", "/audit?pageSize=5", token=stok)
check("SECURITY can read the audit trail", s == 200 and r["total"] > 0)

def login_change(role, newpw):
    tmp = staff[role]["temporaryPassword"]
    s, l = call("POST", "/auth/login", {"email": f"{role.lower()}@aca.test", "password": tmp})
    t = l["accessToken"]
    call("POST", "/auth/change-password", {"currentPassword": tmp, "newPassword": newpw}, token=t)
    return t

ftok = login_change("FINANCE", "Fin-Team-Passw0rd!9")
vtok = login_change("VIEWER", "View-Team-Passw0rd!9")
sutok = login_change("SUPPORT", "Supp-Team-Passw0rd!9")
atok = login_change("ADMIN", "Admin-Team-Passw0rd!9")

check("FINANCE can read invoices", call("GET", "/invoices", token=ftok)[0] == 200)
check("FINANCE can issue credit", call("POST", f"/tenants/{mart}/credit", {"amountKes": 100, "reason": "QA goodwill"}, token=ftok)[0] == 200)
check("FINANCE cannot suspend a company", call("POST", f"/tenants/{mart}/suspend", token=ftok)[0] == 403)
check("FINANCE cannot read security centre", call("GET", "/security/overview", token=ftok)[0] == 403)
check("VIEWER can read tenants", call("GET", "/tenants", token=vtok)[0] == 200)
check("VIEWER cannot add notes", call("POST", f"/tenants/{mart}/notes", {"body": "x"}, token=vtok)[0] == 403)
check("VIEWER cannot mark invoices paid", call("POST", "/invoices/00000000-0000-0000-0000-000000000000/mark-paid", {}, token=vtok)[0] == 403)
s, n = call("POST", f"/tenants/{mart}/notes", {"body": "QA note: prefers calls after 5pm", "pinned": True}, token=sutok)
check("SUPPORT can add a note", s == 201 and n["pinned"] is True, (s, n))
check("SUPPORT can read notes", call("GET", f"/tenants/{mart}/notes", token=sutok)[1]["items"][0]["authorEmail"] == "support@aca.test")
check("SUPPORT can extend a subscription", call("POST", f"/tenants/{mart}/extend", {"days": 2}, token=sutok)[0] == 200)
check("SUPPORT cannot deactivate tenant users", call("POST", f"/tenants/{mart}/users/{tu['items'][0]['id']}/deactivate", token=sutok)[0] == 403)
check("ADMIN can list team", call("GET", "/team", token=atok)[0] == 200)
s, r = call("POST", "/team", {"email": "a2@aca.test", "name": "A2", "role": "ADMIN"}, token=atok)
check("ADMIN cannot create another ADMIN (403)", s == 403, (s, r))
s, r = call("POST", "/team", {"email": "o2@aca.test", "name": "O2", "role": "OWNER"}, token=atok)
check("ADMIN cannot create an OWNER (403)", s == 403)

# --- security tools on a tenant
victim = tu["items"][1]["id"]
s, r = call("POST", f"/tenants/{mart}/users/{victim}/deactivate", token=stok)
check("SECURITY deactivates a tenant user", s == 200 and r["isActive"] is False, (s, r))
s, r = call("POST", f"/tenants/{mart}/users/{victim}/activate", token=stok)
check("SECURITY reactivates the tenant user", s == 200 and r["isActive"] is True)
s, r = call("POST", f"/tenants/{mart}/force-logout", token=stok)
check("SECURITY forces tenant logout", s == 200)
s, r = call("POST", f"/tenants/{pharm}/lockout", {"reason": "QA drill"}, token=stok)
check("SECURITY locks a company out", s == 200 and r["isActive"] is False, (s, r))
s, td2 = call("GET", f"/tenants/{pharm}", token=tok)
check("tenant detail reflects lockout", td2["isActive"] is False)
s, r = call("POST", f"/tenants/{pharm}/lockout/lift", {}, token=stok)
check("SECURITY lifts the lockout", s == 200 and r["isActive"] is True)

# --- own-account protections
s, r = call("PATCH", f"/team/{me['id']}", {"role": "VIEWER"}, token=tok)
check("owner cannot demote themselves (403)", s == 403)
s, r = call("PATCH", f"/team/{me['id']}", {"status": "DISABLED"}, token=tok)
check("owner cannot disable themselves (403)", s == 403)

# --- 2FA flow on the finance account
s, r = call("POST", "/auth/2fa/setup", token=ftok)
check("2FA setup returns secret + otpauth uri", s == 200 and r["otpauthUri"].startswith("otpauth://totp/"), (s, r))
secret = r["secret"]
s, r = call("POST", "/auth/2fa/enable", {"code": "000000"}, token=ftok)
check("2FA enable rejects a wrong code", s == 400)
s, r = call("POST", "/auth/2fa/enable", {"code": totp(secret)}, token=ftok)
check("2FA enable with a correct code returns 8 backup codes", s == 200 and len(r["backupCodes"]) == 8, (s, r))
backup = r["backupCodes"][0]
s, r = call("POST", "/auth/login", {"email": "finance@aca.test", "password": "Fin-Team-Passw0rd!9"})
check("login now asks for the second factor", s == 200 and r == {"requiresTwoFactor": True}, (s, r))
s, r = call("POST", "/auth/login", {"email": "finance@aca.test", "password": "Fin-Team-Passw0rd!9", "otp": totp(secret)})
check("login succeeds with a valid code", s == 200 and r.get("accessToken"), (s, r))
s, r = call("POST", "/auth/login", {"email": "finance@aca.test", "password": "Fin-Team-Passw0rd!9", "otp": backup})
check("login succeeds with a backup code", s == 200 and r.get("accessToken"), (s, r))
s, r = call("POST", "/auth/login", {"email": "finance@aca.test", "password": "Fin-Team-Passw0rd!9", "otp": backup})
check("a backup code cannot be reused", s == 401, (s, r))

# --- refresh rotation + replay detection
s, lg = call("POST", "/auth/login", {"email": OWNER[0], "password": OWNER[1]})
rt1 = lg["refreshToken"]
s, r2 = call("POST", "/auth/refresh", {"refreshToken": rt1})
check("refresh rotates tokens", s == 200 and r2["refreshToken"] != rt1, (s, r2))
check("rotated access token works", call("GET", "/auth/me", token=r2["accessToken"])[0] == 200)
time.sleep(16)  # outside the benign-race grace window
s, r = call("POST", "/auth/refresh", {"refreshToken": rt1})
check("replaying the retired token is refused", s == 401)
check("...and the whole session is revoked (new token dead too)", call("POST", "/auth/refresh", {"refreshToken": r2["refreshToken"]})[0] == 401)
check("...and its access token no longer works", call("GET", "/auth/me", token=r2["accessToken"])[0] == 401)

# --- lockout after 5 bad passwords (use a dedicated account)
s, r = call("POST", "/team", {"email": "locky@aca.test", "name": "Locky", "role": "VIEWER"}, token=tok)
for i in range(5):
    s, r = call("POST", "/auth/login", {"email": "locky@aca.test", "password": "definitely-wrong-1A!"})
s, r = call("POST", "/auth/login", {"email": "locky@aca.test", "password": "definitely-wrong-1A!"})
check("6th attempt is locked out (423)", s == 423 and r.get("code") == "ACCOUNT_LOCKED", (s, r))
s, lteam = call("GET", "/team", token=tok)
locky = [x for x in lteam["items"] if x["email"] == "locky@aca.test"][0]
check("team list shows the account as locked", locky["locked"] is True)
s, r = call("POST", f"/team/{locky['id']}/unlock", token=stok)
check("SECURITY unlocks the account", s == 200, (s, r))

# --- disable a staff member -> instant cut-off
s, r = call("PATCH", f"/team/{[x for x in lteam['items'] if x['email']=='viewer@aca.test'][0]['id']}", {"status": "DISABLED"}, token=atok)
check("ADMIN disables a viewer", s == 200, (s, r))
check("disabled staff token stops working immediately", call("GET", "/tenants", token=vtok)[0] == 401)

# --- audit trail is attributed
s, au = call("GET", "/audit?pageSize=100", token=tok)
actions = {a["action"] for a in au["items"]}
for a in ["AUTH_LOGIN_SUCCESS", "AUTH_LOGIN_FAILED", "AUTH_ACCOUNT_LOCKED", "TEAM_STAFF_CREATED", "TENANT_FORCE_LOGOUT",
          "TENANT_LOCKED_OUT", "BILLING_CREDIT_ISSUED", "AUTH_2FA_ENABLED", "AUTH_REFRESH_TOKEN_REUSE", "TEAM_STAFF_DISABLED", "TENANT_EXTENDED"]:
    check(f"audit contains {a}", a in actions)
credit = [a for a in au["items"] if a["action"] == "BILLING_CREDIT_ISSUED"][0]
check("audit entry is attributed to the actor with IP", credit["actorEmail"] == "finance@aca.test" and credit["ipAddress"], credit)
s, so = call("GET", "/security/overview", token=tok)
check("security overview reflects the activity", s == 200 and so["failedLogins24h"] >= 6 and so["critical7d"] >= 2 and so["staff"]["twoFactorCoveragePercent"] >= 0, so if s != 200 else {k: so[k] for k in ["failedLogins24h", "critical7d", "activeSessions"]})

# --- logout
s, lg2 = call("POST", "/auth/login", {"email": OWNER[0], "password": OWNER[1]})
call("POST", "/auth/logout", token=lg2["accessToken"])
check("logout kills the session", call("GET", "/auth/me", token=lg2["accessToken"])[0] == 401)

failed = [n for n, ok in results if not ok]
print(f"\n{len(results) - len(failed)}/{len(results)} checks passed")
if failed:
    print("FAILED:", failed)
    sys.exit(1)
