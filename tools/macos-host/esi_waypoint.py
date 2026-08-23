#!/usr/bin/env python3
"""Set the EVE client's autopilot destination through ESI, the official API.

The bot has never been able to originate a destination. Every route it has set
came from the mission tracker's own travel buttons, so once a mission ends there
is nothing left to click -- which is how a remote hand-in strands it in space
with an agent that will only say "please drop by". `POST /ui/autopilot/waypoint/`
is the missing half: it tells the logged-in client to set a destination by id,
and the bot's existing travel logic flies it from there.

Usage:
    python3 esi_waypoint.py auth                      # once per character, opens a browser
    python3 esi_waypoint.py auth --manual             # same, but log in on another device
    python3 esi_waypoint.py characters                # which characters are authorised
    python3 esi_waypoint.py forget "Gal Bistot"       # drop one character's token
    python3 esi_waypoint.py resolve "Jita IV - Moon 4 - Caldari Navy Assembly Plant"
    python3 esi_waypoint.py set --name "Amarr VI (Zorast) - Moon 2 - Theology Council Tribunal"
    python3 esi_waypoint.py set --id 60008494 --keep-other-waypoints
    python3 esi_waypoint.py set --id 60008494 --character "Joan d'Arkonor"

Setup, once:
    * developers.eveonline.com -> Create New Application
    * type "Authentication & API Access", scopes -- see `SCOPES` below for the
      exact current set and why each one is there
    * callback exactly `http://localhost:8635/callback`
    * python3 esi_waypoint.py client-id <the client id>   (kept in the Keychain)
      or export ESI_CLIENT_ID=<the client id> to override it for one run

A character authorised before `SCOPES` last changed does not carry the new
scopes -- ESI answers a call it cannot cover with 403 rather than degrading
silently. Run `auth` again for that character to pick them up; nothing about
an existing refresh token is otherwise disturbed.

Also importable. `botlab_host.py` calls `set_destination` in-process for the
`SetAutopilotDestinationRequest` volatile-process request, so every function
below that can fail raises `EsiError` rather than calling `sys.exit`, and the
CLI at the foot is the only thing that turns one into an exit code. A caller
inside the host loop gets a value it can branch on; nothing has to parse this
file's stdout.

Secrets. The PKCE flow means no client secret exists at all, so the only
sensitive artifact is the refresh token, and it goes straight into the macOS
Keychain -- never a file in the repo, never an argument, never printed. Nothing
here echoes a token, deliberately: this runs in a terminal whose scrollback ends
up in bug reports, and the host's own log is tee'd to a file.

**One token per character, keyed by the character's name.** `/ui/autopilot/
waypoint/` acts on whichever character the *token* belongs to, and saxrat run 14
spent a whole session parked because the stored token authorised `Gal Bistot`
while the bot flew `Joan d'Arkonor` -- the host logging a destination set while
the client's route panel read `No Destination` throughout. That was detected and
refused (see `set_destination`); it is now *resolved*, by holding a token per
character and picking the one the client is flying.

The name is the key because the name is the only join available: the client
titles its window `EVE - <character>`, which is what this host knows a running
client by. The character id travels beside it in a small non-secret index so
that logs and `characters` can be unambiguous, but nothing looks a token up by
id.

**Ambiguity refuses; it never guesses.** Four cases, and only the last is new
behaviour for a working single-character setup:

  * the client's character is known and a token is stored for it -- use it;
  * known, and no token stored for it -- refuse, naming the character;
  * not readable, and exactly one token stored -- use it, which is what every
    single-character install has always done;
  * not readable, and more than one token stored -- **refuse**, naming them.
    Picking one would be run 14 again, and a refusal an operator can read is
    recoverable where a route set on the wrong character is not.

The game client must be running and logged in. This endpoint drives that
client's UI; it does not move the ship by itself.
"""
import argparse
import base64
import hashlib
import http.server
import json
import os
import secrets
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import webbrowser

LOGIN_HOST = "https://login.eveonline.com"
ESI_HOST = "https://esi.evetech.net/latest"

# esi-ui.write_waypoint.v1: the original and only scope this ever needed for
#   `set`/`set_destination` itself.
# esi-search.search_structures.v1: lets `resolve_name` find a player-owned
#   structure's *id* by name through the authenticated character search,
#   which is the only ESI endpoint that ever sees one -- the public
#   `/universe/ids/` bulk lookup this file already used never includes a
#   private structure, docked there or not.
# esi-universe.read_structures.v1: a *second*, separate scope the search
#   result alone does not cover -- `/characters/{id}/search/` answers with
#   ids only, and confirming a candidate's own name (so the right one is
#   picked, the way `resolve_name` already does for `/universe/ids/`'s
#   results) needs `/universe/structures/{id}/`, which CCP gates on this
#   scope rather than the search one. Found live: the search call succeeded
#   and returned a real id while the structure-info call answered 401 "Token
#   is not valid for any required scope: esi-universe.read_structures.v1" --
#   the two are genuinely independent grants. See
#   `_resolve_via_character_search`.
# esi-wallet.read_character_wallet.v1: not read by anything in this file yet;
#   added while re-authorising anyway rather than asking for a second consent
#   screen later.
# A token issued before this line changed does not carry the new scopes, and
# ESI answers a call it cannot cover with 401/403 rather than silently
# degrading -- run 'esi_waypoint.py auth' again to pick them up.
SCOPES = ("esi-ui.write_waypoint.v1 esi-search.search_structures.v1 "
          "esi-universe.read_structures.v1 esi-wallet.read_character_wallet.v1")
CALLBACK_PORT = 8635
CALLBACK_PATH = "/callback"
REDIRECT_URI = f"http://localhost:{CALLBACK_PORT}{CALLBACK_PATH}"

KEYCHAIN_SERVICE = "eve-esi-refresh"
KEYCHAIN_ACCOUNT = os.environ.get("USER") or os.environ.get("USERNAME") or "eve"

# One entry per character, and the character's name is in the *service* rather
# than in the account. That is not a stylistic choice: the Keychain keys on
# (service, account) while the Windows Credential Manager keys on the target
# alone and carries the account as informational `UserName`, so varying the
# account would give two characters one entry on Windows -- silently, one
# overwriting the other. Varying the service works identically on both stores
# and needed no change to `credential_store.py`.
KEYCHAIN_CHARACTER_SERVICE_PREFIX = KEYCHAIN_SERVICE + ":"

# Names and ids of the characters that have a token, and nothing else. Neither
# is a secret -- a character name is on the client's own title bar -- but it
# lives in the credential store rather than in a file so that there is one
# mechanism to reason about, one place to revoke, and no path, ACL or rotation
# story to decide. Nothing is ever *read* out of it that a token depends on: a
# lookup by name goes straight to that character's entry, so an index that has
# lost a row still leaves that character's token usable when the client names
# it. What the index decides is only what `characters` can list and how many
# tokens the ambiguity rule believes exist, and both of those fail closed.
KEYCHAIN_CHARACTER_INDEX_SERVICE = "eve-esi-characters"

# Windows keeps these in the Credential Manager instead, which is that
# platform's Keychain: encrypted at rest under the user's own login, and
# enumerable and revocable by them (`cmdkey /list`). Same four operations behind
# the same four function names, so nothing below this point knows which store it
# is talking to -- see tools/windows-host/credential_store.py.
IS_WINDOWS = sys.platform == "win32"
_cred_store = None
if IS_WINDOWS:
    _WINDOWS_HOST_DIR = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "windows-host"
    )
    if _WINDOWS_HOST_DIR not in sys.path:
        sys.path.insert(0, _WINDOWS_HOST_DIR)
    import credential_store as _cred_store  # noqa: E402

# The client id lives beside the refresh token rather than in the repo or a
# shell profile. It is not a secret -- PKCE issues no client secret, and this
# one is useless without the login it authorises -- but it does identify a
# specific developer application on a specific account, which is not something
# to commit to a fork or leave in shell history.
KEYCHAIN_CLIENT_ID_SERVICE = "eve-esi-client-id"

# CCP asks that every caller identify itself so they can get in touch before
# blocking a misbehaving client rather than after.
USER_AGENT = "macos-host-eve-bot (personal, non-commercial)"

# The budget for a whole operation, not for one request. A per-request timeout
# bounds nothing useful here: resolving an NPC station that `/universe/ids/`
# misses costs one round trip per station in the system, so a dozen requests
# that each answer just inside their own timeout still add up past any tick the
# host has to spare. Fifteen seconds is about one memory read's worth. Running
# out is a failure the caller branches on, not something to wait through.
DEFAULT_BUDGET_SECONDS = 15.0

# The ceiling on any single request, applied under whatever the budget has left.
PER_REQUEST_TIMEOUT_SECONDS = 30.0


class EsiError(Exception):
    """A failure whose message is safe to log.

    Every message here is built from a status code, a name, or our own wording.
    In particular the token endpoint's error body is never included: that is the
    one response that can quote a request's own parameters back, and a request
    to it carries the refresh token. Callers print these straight into a log
    that is tee'd to a file and pasted into transcripts.
    """


class Deadline:
    """A wall-clock budget shared across the several requests one call makes."""

    def __init__(self, budget_seconds=DEFAULT_BUDGET_SECONDS):
        self.expires_at = time.monotonic() + budget_seconds

    def remaining(self):
        return self.expires_at - time.monotonic()

    def timeout_for(self, what):
        left = self.remaining()
        if left <= 0:
            raise EsiError(f"ESI took too long ({what})")
        return min(left, PER_REQUEST_TIMEOUT_SECONDS)


# Ids never change, so both of these live for the life of the process. Speed is
# not the only point: the enumerate-a-system fallback is the path most likely to
# exhaust the budget, and memoising each station it looks at means an attempt
# that ran out of time gets further next time instead of starting over.
_ID_BY_NAME = {}      # lowercased name -> (id, kind)
_UNIVERSE_GET = {}    # GET path -> decoded payload


def client_id():
    """The application's client id: the environment first, then the Keychain.

    The environment still wins, so a one-off run against a different application
    needs no state change. Falling back to the Keychain is what stops the id
    being something to remember and re-export on every invocation.
    """
    value = os.environ.get("ESI_CLIENT_ID")
    if not value:
        value = keychain_load_client_id()
    if not value:
        raise EsiError("no client id -- set ESI_CLIENT_ID, or store one once "
                       "with `esi_waypoint.py client-id <id>`. See the setup "
                       "notes at the top of this file.")
    return value.strip()


def keychain_store_client_id(value):
    credential_store_write(KEYCHAIN_CLIENT_ID_SERVICE, value)


def keychain_load_client_id():
    return credential_store_read(KEYCHAIN_CLIENT_ID_SERVICE)


# ---------------------------------------------------------------------------
# The credential store: the refresh token's only home
#
# Three operations over one (service, account) pair, so that everything above
# this point talks about *what* is stored rather than about which platform's
# store it is in. The account is always this login's; the service is what
# distinguishes one character's token from another's -- see
# `KEYCHAIN_CHARACTER_SERVICE_PREFIX` for why it is that way round.
# ---------------------------------------------------------------------------
def credential_store_write(service, value):
    if IS_WINDOWS:
        return _cred_store.store(service, KEYCHAIN_ACCOUNT, value)
    subprocess.run(
        ["security", "add-generic-password", "-U",
         "-a", KEYCHAIN_ACCOUNT, "-s", service, "-w", value],
        check=True,
    )


def credential_store_read(service):
    if IS_WINDOWS:
        return _cred_store.load(service, KEYCHAIN_ACCOUNT)
    result = subprocess.run(
        ["security", "find-generic-password",
         "-a", KEYCHAIN_ACCOUNT, "-s", service, "-w"],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        return None
    return result.stdout.strip() or None


def credential_store_delete(service):
    """Remove one entry. `True` if there was one to remove."""
    if IS_WINDOWS:
        return bool(_cred_store.delete(service))
    result = subprocess.run(
        ["security", "delete-generic-password",
         "-a", KEYCHAIN_ACCOUNT, "-s", service],
        capture_output=True, text=True,
    )
    return result.returncode == 0


def keychain_store(token):
    """Write the *legacy*, un-attributed token: the pre-multi-character slot.

    Nothing but the migration writes here any more. It is kept because an
    install that predates this file's per-character store has its one token
    here, and because the migration has to write the rotated token back to it
    before it knows whose it is -- see `ensure_legacy_token_migrated`.
    """
    credential_store_write(KEYCHAIN_SERVICE, token)


def keychain_load():
    """The legacy, un-attributed token, or `None`."""
    return credential_store_read(KEYCHAIN_SERVICE)


# ---------------------------------------------------------------------------
# One token per character
# ---------------------------------------------------------------------------
def character_key(name):
    """The comparison form of a character's name.

    Trimmed and lower-cased, exactly as `set_destination`'s mismatch guard has
    always compared the client's window title against the token's character --
    one normalisation, so a name that matched the guard cannot fail to find its
    own token.
    """
    return (name or "").strip().lower()


def character_service(name):
    return KEYCHAIN_CHARACTER_SERVICE_PREFIX + character_key(name)


def store_refresh_token(character, token):
    """File a refresh token under one character, or under the legacy slot.

    `character` is `None` only for the legacy slot. Every caller that reads a
    token passes the same value back here when CCP rotates it, so a rotation
    cannot land under a different character than the one it came from.
    """
    if character is None:
        keychain_store(token)
    else:
        credential_store_write(character_service(character), token)


def refresh_token_for(character):
    """This character's stored refresh token, or `None`. `None` = legacy slot."""
    if character is None:
        return keychain_load()
    if not character_key(character):
        return None
    return credential_store_read(character_service(character))


def _index_entries():
    """The raw index, as a list of `{"name", "id"}`. Never raises."""
    raw = credential_store_read(KEYCHAIN_CHARACTER_INDEX_SERVICE)
    if not raw:
        return []
    try:
        decoded = json.loads(raw)
    except ValueError:
        return []
    if not isinstance(decoded, list):
        return []
    entries = []
    for entry in decoded:
        if isinstance(entry, dict) and character_key(entry.get("name")):
            entries.append({"name": str(entry.get("name")).strip(),
                            "id": entry.get("id")})
    return entries


def stored_characters():
    """Every character this machine holds a usable token for.

    Filtered against the tokens themselves rather than reported straight out of
    the index, so an index row whose token has been forgotten cannot make the
    ambiguity rule believe in a choice that is not there. Sorted by name, so the
    "exactly one" case and the message listing several are both stable.
    """
    seen = set()
    found = []
    for entry in _index_entries():
        key = character_key(entry["name"])
        if key in seen or not refresh_token_for(entry["name"]):
            continue
        seen.add(key)
        found.append(entry)
    return sorted(found, key=lambda entry: character_key(entry["name"]))


def describe_stored_characters():
    """Names and ids for a message. Never a token, nor any part of one."""
    known = stored_characters()
    if not known:
        return "none"
    return ", ".join(
        "%s (id %s)" % (entry["name"], entry["id"]) if entry["id"] is not None
        else entry["name"]
        for entry in known)


def remember_character(name, character_id):
    """Record a character in the index, replacing any earlier row for it."""
    key = character_key(name)
    entries = [entry for entry in _index_entries() if character_key(entry["name"]) != key]
    entries.append({"name": (name or "").strip(), "id": character_id})
    entries.sort(key=lambda entry: character_key(entry["name"]))
    credential_store_write(KEYCHAIN_CHARACTER_INDEX_SERVICE, json.dumps(entries))


def forget_character(name):
    """Drop one character's token and its index row. `True` if there was one."""
    had_token = bool(refresh_token_for(name))
    credential_store_delete(character_service(name))
    key = character_key(name)
    entries = [entry for entry in _index_entries() if character_key(entry["name"]) != key]
    credential_store_write(KEYCHAIN_CHARACTER_INDEX_SERVICE, json.dumps(entries))
    _token_character.pop(key, None)
    return had_token


# ---------------------------------------------------------------------------
# HTTP
# ---------------------------------------------------------------------------
def post_form(url, fields, deadline=None):
    """POST a form and return the decoded body.

    Failures raise `EsiError` carrying the status code alone. This is the call
    that carries the refresh token, so its error body -- which quotes the
    request back on at least some CCP errors -- never reaches the message.
    """
    deadline = deadline or Deadline()
    body = urllib.parse.urlencode(fields).encode()
    request = urllib.request.Request(url, data=body, method="POST")
    request.add_header("Content-Type", "application/x-www-form-urlencoded")
    request.add_header("Host", urllib.parse.urlparse(url).netloc)
    request.add_header("User-Agent", USER_AGENT)
    try:
        with urllib.request.urlopen(request, timeout=deadline.timeout_for(url)) as response:
            return json.loads(response.read())
    # `from None` drops the chained original. Not tidiness: the suppressed
    # exception keeps the frame that called urlopen alive, and that frame's
    # locals hold the encoded form body -- the refresh token among them. Nothing
    # here prints locals today, and nothing should have to stay true for this to
    # be safe.
    except urllib.error.HTTPError as error:
        raise EsiError(f"login.eveonline.com refused the token request ({error.code})") from None
    except urllib.error.URLError as error:
        raise EsiError(f"could not reach login.eveonline.com ({error.reason})") from None
    except OSError as error:
        raise EsiError(f"could not reach login.eveonline.com ({error})") from None


def esi(method, path, token=None, params=None, body=None, deadline=None):
    """Call ESI and return `(status, payload)`.

    An HTTP error is a status like any other -- callers here read the code to
    tell a scope problem from a missing client. Only a request that never got an
    answer raises, since there is no status to report and no point retrying
    inside one bounded call.
    """
    deadline = deadline or Deadline()
    url = f"{ESI_HOST}{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, method=method)
    request.add_header("User-Agent", USER_AGENT)
    if data is not None:
        request.add_header("Content-Type", "application/json")
    if token:
        request.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(request, timeout=deadline.timeout_for(path)) as response:
            raw = response.read()
            return response.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as error:
        raw = error.read()
        try:
            detail = json.loads(raw)
        except Exception:
            detail = raw.decode("utf-8", "replace")
        return error.code, detail
    except urllib.error.URLError as error:
        raise EsiError(f"could not reach ESI ({error.reason})")
    except OSError as error:
        raise EsiError(f"could not reach ESI ({error})")


# ---------------------------------------------------------------------------
# OAuth 2.0 with PKCE
# ---------------------------------------------------------------------------
def pkce_pair():
    verifier = secrets.token_urlsafe(32)
    digest = hashlib.sha256(verifier.encode()).digest()
    challenge = base64.urlsafe_b64encode(digest).decode().rstrip("=")
    return verifier, challenge


class _CallbackHandler(http.server.BaseHTTPRequestHandler):
    captured = {}

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path != CALLBACK_PATH:
            self.send_response(404)
            self.end_headers()
            return
        _CallbackHandler.captured = dict(urllib.parse.parse_qsl(parsed.query))
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.end_headers()
        self.wfile.write(b"Authorized. You can close this tab and return to the terminal.")

    def log_message(self, *_):
        pass  # the default handler writes the full query string, code included


def authorize_manual():
    """Authorize when the browser is on another device.

    `authorize` opens a browser here and catches the redirect on this machine's
    localhost. Log in on a phone instead and that redirect resolves to the
    *phone's* localhost, where nothing is listening, so the final hop just fails
    to load -- but the URL in the address bar still carries the code. This prints
    the authorize URL, takes that failed URL back, and finishes the exchange
    here.

    The code_verifier never leaves this process, so the half that proves the
    request is ours stays local no matter which device did the logging in. The
    code itself is single-use and short-lived.
    """
    verifier, challenge = pkce_pair()
    state = secrets.token_urlsafe(16)
    query = urllib.parse.urlencode({
        "response_type": "code",
        "redirect_uri": REDIRECT_URI,
        "client_id": client_id(),
        "scope": SCOPES,
        "state": state,
        "code_challenge": challenge,
        "code_challenge_method": "S256",
    })
    url = f"{LOGIN_HOST}/v2/oauth/authorize/?{query}"

    print("Open this on the other device and log in:\n")
    print(url)
    print("\nThe page it lands on will fail to load -- that is expected, the "
          "redirect points at this machine. Copy its full address and paste it "
          "here.\n")
    pasted = input("callback URL: ").strip()

    captured = dict(urllib.parse.parse_qsl(urllib.parse.urlparse(pasted).query))
    if captured.get("state") != state:
        sys.exit("state mismatch -- refusing the response. Start again.")
    if "code" not in captured:
        sys.exit(f"no authorization code in that URL: {sorted(captured)}")

    tokens = post_form(f"{LOGIN_HOST}/v2/oauth/token", {
        "grant_type": "authorization_code",
        "code": captured["code"],
        "client_id": client_id(),
        "code_verifier": verifier,
    })
    return finish_authorization(tokens)


def finish_authorization(tokens):
    """Store a freshly authorized token under the character it belongs to.

    The character is asked of CCP rather than of the operator, so `auth` can
    say which character it just stored and cannot file one under a name
    somebody typed wrong. It replaces that character's token and leaves every
    other character's alone, which is what makes `auth` runnable once per
    character rather than once per machine.

    The verify is the one place the whole design pays for a round trip, and it
    is the right place: it happens once per character ever, against a browser
    login that has just cost far more than a round trip, and it is what lets
    every later `set` pick a token by name with no network call at all.

    Nothing token-shaped is printed. The character's name and id are on the
    client's own title bar and in its character sheet.
    """
    name, character_id = character_from_access_token(tokens["access_token"])
    if not character_key(name):
        # A token nobody can attribute must not be filed under a guessed name,
        # and throwing it away would waste the login. The legacy slot is where
        # the migration looks, so parking it there costs nothing and is picked
        # up on the next run -- but only if that slot is empty, since
        # overwriting it would destroy a token this run cannot prove it has
        # re-stored anywhere.
        if not keychain_load():
            keychain_store(tokens["refresh_token"])
            raise EsiError("authorized, but CCP did not name the character, so "
                           "the token was parked unattributed and will be filed "
                           "on the next run. Run 'characters' to check.")
        raise EsiError("authorized, but CCP did not name the character, so "
                       "there is nowhere to file this token. Nothing was "
                       "changed; run 'auth' again.")
    store_refresh_token(name, tokens["refresh_token"])
    remember_character(name, character_id)
    _token_character[character_key(name)] = (name, character_id)
    print(f"authorized {name} (id {character_id}); refresh token stored in the "
          f"Keychain as {character_service(name)!r} (not printed).")
    print(f"characters with a stored token: {describe_stored_characters()}")
    return tokens["access_token"]


def authorize():
    verifier, challenge = pkce_pair()
    state = secrets.token_urlsafe(16)
    query = urllib.parse.urlencode({
        "response_type": "code",
        "redirect_uri": REDIRECT_URI,
        "client_id": client_id(),
        "scope": SCOPES,
        "state": state,
        "code_challenge": challenge,
        "code_challenge_method": "S256",
    })
    url = f"{LOGIN_HOST}/v2/oauth/authorize/?{query}"

    server = http.server.HTTPServer(("localhost", CALLBACK_PORT), _CallbackHandler)
    thread = threading.Thread(target=server.handle_request, daemon=True)
    thread.start()

    print(f"opening the EVE login page; if it does not open, visit:\n  {url}\n")
    webbrowser.open(url)
    thread.join(timeout=300)
    server.server_close()

    captured = _CallbackHandler.captured
    if not captured:
        sys.exit("timed out waiting for the callback -- nothing arrived on port "
                 f"{CALLBACK_PORT}.")
    if captured.get("state") != state:
        sys.exit("state mismatch on the callback -- refusing the response.")
    if "code" not in captured:
        sys.exit(f"no authorization code in the callback: {captured}")

    tokens = post_form(f"{LOGIN_HOST}/v2/oauth/token", {
        "grant_type": "authorization_code",
        "code": captured["code"],
        "client_id": client_id(),
        "code_verifier": verifier,
    })
    return finish_authorization(tokens)


def access_token(character=None, deadline=None):
    """A fresh access token, from the stored refresh token.

    Access tokens last 20 minutes, so there is no point caching one between
    invocations -- refreshing every run is simpler and cheap. The refresh token
    is read out of the Keychain here and handed straight to `post_form`; it is
    never returned, stored in an attribute or put in a message.

    `character` names whose token to use; `None` is the legacy, un-attributed
    slot, which only the migration still reads. **CCP rotates refresh tokens**,
    so the replacement is written back under the same `character` this call
    read -- a rotation filed under a different name would swap two characters'
    tokens, and both would go on looking stored.
    """
    refresh = refresh_token_for(character)
    if not refresh:
        raise EsiError("no stored refresh token -- run 'esi_waypoint.py auth' first")
    try:
        tokens = post_form(f"{LOGIN_HOST}/v2/oauth/token", {
            "grant_type": "refresh_token",
            "refresh_token": refresh,
            "client_id": client_id(),
        }, deadline=deadline)
    except EsiError as error:
        raise EsiError(f"{error} -- re-run 'auth'. A revoked or rotated token "
                       "cannot be repaired here.")
    # CCP rotates refresh tokens: the old one stops working once used. Back
    # under `character`, never under whatever the last caller happened to ask
    # for -- see the doc comment.
    if tokens.get("refresh_token"):
        store_refresh_token(character, tokens["refresh_token"])
    return tokens["access_token"]


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------
def _universe_get(path, deadline):
    """A memoised GET of static universe data. `None` if ESI would not answer."""
    if path in _UNIVERSE_GET:
        return _UNIVERSE_GET[path]
    status, payload = esi("GET", path, deadline=deadline)
    if status != 200:
        return None
    _UNIVERSE_GET[path] = payload
    return payload


def resolve_name(name, deadline=None, character=None):
    """The id of a station, structure or system, by name. Raises `EsiError`.

    Returns `(id, kind)` where kind is one of the `/universe/ids/` bucket
    names, or `"structures"` when the answer came from
    `_resolve_via_character_search` instead.

    `character` is optional and, when given, is who the character-search
    fallback authenticates as -- see that function for why it has to be a
    specific character rather than any stored token. Every call site that has
    already chosen a character (`set_destination`, and the CLI's own
    pre-resolve) passes it; a caller that has not chosen one yet simply gets
    the old behaviour, unable to see a player-owned structure at all.
    """
    deadline = deadline or Deadline()
    cached = _ID_BY_NAME.get(name.lower())
    if cached:
        return cached

    status, payload = esi("POST", "/universe/ids/", body=[name], deadline=deadline)
    if status != 200:
        raise EsiError(f"name lookup failed ({status}): {payload}")
    for key in ("stations", "structures", "systems"):
        for entry in (payload or {}).get(key) or []:
            if entry.get("name", "").lower() == name.lower():
                return _remember(name, entry["id"], key)
    for key in ("stations", "structures", "systems"):
        entries = (payload or {}).get(key) or []
        if entries:
            return _remember(name, entries[0]["id"], key)

    # /universe/ids/ does not index every NPC station: the agent's own
    # "Amarr VI (Zorast) - Moon 2 - Theology Council Tribunal" comes back empty
    # from it while resolving perfectly through the system's station list.
    # NPC station names begin with their system's name, so that first token is
    # enough to find the system and enumerate what is docked in it.
    found = _resolve_via_system(name, deadline)
    if found:
        return _remember(name, found[0], found[1])

    # A player-owned structure is invisible to everything above -- the public
    # bulk lookup and the system enumeration both only ever see NPC-owned
    # space. This is the one path that can actually find one, and only for a
    # character with docking access to it.
    if character:
        structure_id = _resolve_via_character_search(name, character, deadline)
        if structure_id:
            return _remember(name, structure_id, "structures")

    raise EsiError(f"nothing named {name!r} was found. Structures in "
                   "player-owned space often need the character to have docked "
                   "there before ESI will resolve them.")


def _remember(name, found_id, kind):
    _ID_BY_NAME[name.lower()] = (found_id, kind)
    return found_id, kind


def _resolve_via_system(name, deadline):
    system_name = name.split()[0] if name.split() else ""
    if not system_name:
        return None
    status, payload = esi("POST", "/universe/ids/", body=[system_name], deadline=deadline)
    if status != 200:
        return None
    systems = (payload or {}).get("systems") or []
    if not systems:
        return None

    system = _universe_get(f"/universe/systems/{systems[0]['id']}/", deadline)
    if system is None:
        return None
    for station_id in system.get("stations") or []:
        station = _universe_get(f"/universe/stations/{station_id}/", deadline)
        if station and station.get("name", "").lower() == name.lower():
            return station_id, "stations"
    return None


def _resolve_via_character_search(name, character, deadline):
    """A player-owned structure's id, via the authenticated character-search
    endpoint, or `None`.

    This is the endpoint `resolve_name`'s own error message has always
    promised without anything here actually calling it: `/universe/ids/` is a
    public bulk lookup and never includes a private Upwell structure,
    regardless of whether this character has docked there. Only
    `GET /characters/{character_id}/search/` does, and only for a character
    with docking access to it -- which is also why `/universe/structures/
    {structure_id}/` below needs the same character's token: CCP restricts
    both to avoid leaking a private structure's name and location to a
    character who has never been there.

    `strict=False` casts a slightly wider net than an exact match up front
    (the search endpoint tokenises rather than matching the full string), and
    each candidate id is then checked against its own `/universe/structures/`
    name for an exact match -- the same discipline `resolve_name` already
    applies to `/universe/ids/`'s results, so a structure whose name merely
    contains a shared word cannot be picked by accident.

    **A 401/403 raises rather than being read as "no match".** The two calls
    here each gate on their own scope (`esi-search.search_structures.v1` and
    `esi-universe.read_structures.v1`), and a token missing one answers 401 --
    which, folded into "found nothing", would have looked identical to this
    character genuinely having no docking access. That distinction cost real
    debugging time once already: the search call succeeded and returned a
    real id while the structure-info call was silently swallowing a 401.
    """
    _, character_id = token_character(character, deadline)
    token = access_token(character=character, deadline=deadline)
    status, payload = esi(
        "GET",
        f"/characters/{character_id}/search/",
        token=token,
        params={"categories": "structure", "search": name, "strict": "false"},
        deadline=deadline,
    )
    if status in (401, 403):
        raise EsiError(f"character search for {name!r} failed ({status}): {payload} -- "
                       "the token is missing a required scope. Run 'esi_waypoint.py auth' "
                       "again after checking SCOPES in this file matches what the app "
                       "registration at developers.eveonline.com allows.")
    if status != 200:
        return None
    for structure_id in (payload or {}).get("structure") or []:
        status, structure = esi(
            "GET",
            f"/universe/structures/{structure_id}/",
            token=token,
            deadline=deadline,
        )
        if status in (401, 403):
            raise EsiError(f"structure lookup for id {structure_id} failed ({status}): "
                           f"{structure} -- the token is missing a required scope. Run "
                           "'esi_waypoint.py auth' again after checking SCOPES in this "
                           "file matches what the app registration at "
                           "developers.eveonline.com allows.")
        if status == 200 and structure and structure.get("name", "").lower() == name.lower():
            return structure_id
    return None


def set_waypoint(destination_id, clear_other=True, add_to_beginning=False,
                 deadline=None, character=None):
    """Point one character's client autopilot at `destination_id`.

    Returns `destination_id` on success and raises `EsiError` on every failure,
    including the ones ESI reports as a perfectly ordinary HTTP response. There
    is no return value that means "probably fine": a caller that does not handle
    the failure gets an exception, not a route it never set.

    `character` decides whose autopilot this is, because the token decides and
    `character` is what picks the token. `None` reads the legacy slot, which is
    what the CLI's `--id` path did before there was more than one token.
    """
    deadline = deadline or Deadline()
    status, payload = esi(
        "POST", "/ui/autopilot/waypoint/",
        token=access_token(character=character, deadline=deadline),
        params={
            "destination_id": destination_id,
            "clear_other_waypoints": str(clear_other).lower(),
            "add_to_beginning": str(add_to_beginning).lower(),
        },
        deadline=deadline,
    )
    if status in (200, 204):
        return destination_id
    if status == 403:
        raise EsiError(f"refused ({status}): {payload} -- a 403 here is usually "
                       "the scope: the token needs esi-ui.write_waypoint.v1. "
                       "Re-run 'auth' if the app's scopes changed.")
    raise EsiError(f"failed ({status}): {payload} -- this endpoint drives the "
                   "logged-in client's UI, so it fails if no client is running "
                   "for this character.")


# Keyed by `character_key`, with `""` for the legacy slot. **Keyed** rather
# than a single pair, which is what it was while there was one token: an
# unkeyed cache filled by the first character answers every later question
# about a different character with the first one's name, which is the
# wrong-character failure this whole change exists to end, arriving through the
# one function whose job is to say who a token belongs to.
_token_character = {}


def character_from_access_token(access, deadline=None):
    """The character an access token authorises, as `(name, id)`.

    Nothing token-shaped is returned or logged -- the access token goes straight
    to the verify endpoint and only the character comes back out.
    """
    deadline = deadline or Deadline()
    request = urllib.request.Request(f"{LOGIN_HOST}/oauth/verify")
    request.add_header("User-Agent", USER_AGENT)
    request.add_header("Authorization", "Bearer " + access)
    try:
        with urllib.request.urlopen(
                request, timeout=deadline.timeout_for("verify")) as response:
            payload = json.loads(response.read())
    except (urllib.error.URLError, ValueError) as failure:
        raise EsiError("could not read the token's character: %s" % failure)
    return (payload.get("CharacterName"), payload.get("CharacterID"))


def token_character(character=None, deadline=None):
    """The character a stored refresh token authorises, as `(name, id)`.

    Memoised for the life of the process **per character**: a token's character
    cannot change, and `authorize` is what replaces a token.

    Not on the path a `set` takes any more -- a token filed under a character is
    a token CCP has already named, so picking one by name needs no verify. This
    is the migration's and the CLI's way of asking, and it is where the cost of
    asking belongs.
    """
    key = character_key(character)
    if key not in _token_character:
        deadline = deadline or Deadline()
        _token_character[key] = character_from_access_token(
            access_token(character=character, deadline=deadline), deadline)
    return _token_character[key]


_legacy_migration_checked = False


def ensure_legacy_token_migrated(deadline=None):
    """File a pre-multi-character token under its own character, once.

    An install that predates this store has one token in the legacy slot and no
    index row, so nothing here can name it and every lookup by character misses.
    Rather than making the operator re-authorise, the first call that needs a
    token exchanges it, asks CCP whose it is, re-files it and drops the old
    entry. Returns the character's name if it migrated one, else `None`.

    **The order is what makes an interruption survivable, and the reason is that
    CCP rotates refresh tokens**: the moment the exchange succeeds the old value
    is dead, so the replacement is written back to the legacy slot *first* --
    exactly what `access_token` has always done -- and only then copied to the
    character's entry and only then is the legacy entry removed. Killed between
    any two of those, the next run finds a live token in the legacy slot, does
    the whole thing again, and overwrites the character's entry with the newer
    value. The cost of an interruption is one extra rotation; nothing is ever
    deleted that has not been proved re-stored.

    A failure is caught rather than raised, and nothing is deleted on one, so a
    revoked legacy token cannot stop a machine that has per-character tokens
    from using them. It says so on stderr, once.
    """
    global _legacy_migration_checked
    if _legacy_migration_checked:
        return None
    legacy = keychain_load()
    if not legacy:
        _legacy_migration_checked = True
        return None
    deadline = deadline or Deadline()
    try:
        tokens = post_form(f"{LOGIN_HOST}/v2/oauth/token", {
            "grant_type": "refresh_token",
            "refresh_token": legacy,
            "client_id": client_id(),
        }, deadline=deadline)
        rotated = tokens.get("refresh_token") or legacy
        keychain_store(rotated)
        name, character_id = character_from_access_token(
            tokens["access_token"], deadline)
        if not character_key(name):
            raise EsiError("CCP did not name the character")
        store_refresh_token(name, rotated)
        remember_character(name, character_id)
        _token_character[character_key(name)] = (name, character_id)
        credential_store_delete(KEYCHAIN_SERVICE)
    except (EsiError, KeyError) as failure:
        _legacy_migration_checked = True
        print("# ESI: a refresh token from before the per-character store is "
              "still here and could not be filed under its character (%s). It "
              "was left where it is; nothing was deleted. Run "
              "'esi_waypoint.py auth' to re-authorise that character."
              % failure, file=sys.stderr)
        return None
    _legacy_migration_checked = True
    print("# ESI: filed the refresh token from before the per-character store "
          "under %r; no action needed. 'esi_waypoint.py characters' lists it."
          % name, file=sys.stderr)
    return name


def character_to_route(expected_character, deadline=None):
    """Which character's token to use, or an `EsiError` saying why none.

    The four cases in this file's own header, in order, and the only one that
    is a change for a working single-character install is the last.

    The budget is asked about before anything else, because this step can do
    real work (the migration) and because an expired budget has to be reported
    as an expiry rather than as whatever the store happened to say about a
    question there was no time to act on.
    """
    if deadline is not None:
        deadline.timeout_for("choosing which character to route")
    ensure_legacy_token_migrated(deadline)

    if expected_character and character_key(expected_character):
        wanted = expected_character.strip()
        if refresh_token_for(wanted):
            return wanted
        raise EsiError(
            "no stored ESI token authorises %r, and that is the character this "
            "client is flying -- so setting a destination here would route some "
            "other character and this one would never see it. Run "
            "'esi_waypoint.py auth' and pick %r at the character step. "
            "Authorised now: %s"
            % (wanted, wanted, describe_stored_characters()))

    known = stored_characters()
    if not known:
        raise EsiError("no stored refresh token -- run 'esi_waypoint.py auth' first")
    if len(known) == 1:
        return known[0]["name"]
    raise EsiError(
        "this host cannot tell which character the client is flying and %d are "
        "authorised (%s), so choosing one would be a guess -- and a route set on "
        "the wrong character reports success and is never seen, which is the "
        "failure this refuses to risk. Pass --character, or check that the "
        "client's window title names its pilot."
        % (len(known), describe_stored_characters()))


def character_from_window_title(title):
    """The character a client window title names, or `None`.

    The client titles its window `EVE - <character>`, so the name is whatever
    follows the first separator. Anything else answers `None`, which callers
    read as "cannot tell which character" -- never as "any character will do";
    see `character_to_route`, where that is what decides between using the one
    stored token and refusing to pick between several.
    """
    if not title:
        return None
    for separator in (" - ", " – "):
        if separator in title:
            candidate = title.split(separator, 1)[1].strip()
            return candidate or None
    return None


def set_destination(name=None, destination_id=None, clear_other=True,
                    add_to_beginning=False, budget_seconds=DEFAULT_BUDGET_SECONDS,
                    expected_character=None, character=None):
    """Resolve a name if needed and set the destination, under one budget.

    The single entry point for callers outside this file. Returns the id that
    was set; raises `EsiError` with a loggable reason for every other outcome,
    expiry included.

    **`expected_character` is what picks the token, and it exists because this
    endpoint fails silently in the worst available direction.**
    `/ui/autopilot/waypoint/` acts on whichever character the *token* belongs
    to, not on the client the bot is flying, so a token for the wrong character
    reports success and sets a route the bot will never see.

    That is not hypothetical. saxrat run 14 was parked for its whole session:
    the host logged `# ESI: destination 'Hamse' set (30003547)` while the token
    belonged to `Gal Bistot` and the bot flew `Joan d'Arkonor`, whose route panel
    read `No Destination` throughout. The bot then spent 3,932 readings latched
    on `ROUTE SETTING GIVEN UP -- this host does not set destinations`, which
    was the one conclusion the evidence beside it ruled out.

    It used to be a *guard*: one token, verified once, and a refusal when the
    two names disagreed. It is a *selection* now -- there is a token per
    character, so the client's own name picks one, and the case that used to
    refuse is the case that now works. What still refuses is a character with no
    token, and the ambiguous case: the title unreadable with more than one token
    stored, where any choice would be run 14 again.

    **`None` no longer means "proceed regardless".** A caller that cannot name
    the client's character still gets exactly today's behaviour on a machine
    holding one token, which is every install that predates this. On a machine
    holding several it refuses and names them, which is a behaviour change and
    the point of the change.

    `character` overrides the whole of that, for an operator who knows better
    than the window title. Nothing in the host passes it.

    **Cost: no round trip was added.** The old guard's verify is gone from this
    path -- a token filed under a character is one CCP has already named -- so a
    `set` that picks by name spends one credential-store read more and one HTTP
    request fewer than it used to. The migration is the exception, once per
    install ever, and after it a single credential-store read says there is
    nothing to migrate.
    """
    if (name is None) == (destination_id is None):
        raise EsiError("set_destination needs exactly one of name, destination_id")
    deadline = Deadline(budget_seconds)

    chosen = character if character and character_key(character) \
        else character_to_route(expected_character, deadline=deadline)

    if destination_id is None:
        destination_id, _ = resolve_name(name, deadline=deadline, character=chosen)
    return set_waypoint(destination_id, clear_other=clear_other,
                        add_to_beginning=add_to_beginning, deadline=deadline,
                        character=chosen)


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    id_cmd = sub.add_parser("client-id", help="store the application's client id in the Keychain")
    id_cmd.add_argument("value", help="the client id from developers.eveonline.com")

    auth_cmd = sub.add_parser(
        "auth", help="browser authorization (PKCE), once per character")
    auth_cmd.add_argument("--manual", action="store_true",
                          help="print the URL and take the pasted redirect back, for logging "
                               "in on another device (the callback points at this machine's "
                               "localhost, which a phone cannot reach)")

    sub.add_parser("characters",
                   help="list the characters with a stored token (names and ids only)")

    forget = sub.add_parser("forget", help="drop one character's stored token")
    forget.add_argument("character", help="the character's name, as the client writes it")

    resolve = sub.add_parser("resolve", help="look up a station/system id by name")
    resolve.add_argument("name")
    resolve.add_argument("--character", default=None,
                         help="try the authenticated character-search fallback as this "
                              "character too, for a player-owned structure the public "
                              "lookup cannot see -- needed only where more than one "
                              "character is authorised")

    setter = sub.add_parser("set", help="set the client's autopilot destination")
    target = setter.add_mutually_exclusive_group(required=True)
    target.add_argument("--id", type=int, help="destination id")
    target.add_argument("--name", help="station or system name, resolved first")
    setter.add_argument("--keep-other-waypoints", action="store_true",
                        help="add to the route instead of replacing it")
    setter.add_argument("--add-to-beginning", action="store_true")
    setter.add_argument("--character", default=None,
                        help="route this character rather than letting the stored set "
                             "decide; needed only where more than one is authorised and "
                             "no client window title says which is flying")
    setter.add_argument("--budget", type=float, default=DEFAULT_BUDGET_SECONDS,
                        help="seconds for the whole resolve-and-set, not per request "
                             f"(default {DEFAULT_BUDGET_SECONDS:g})")

    args = parser.parse_args()

    if args.command == "client-id":
        keychain_store_client_id(args.value.strip())
        print(f"client id stored in the Keychain as {KEYCHAIN_CLIENT_ID_SERVICE!r}")
        return 0

    if args.command == "auth":
        if args.manual:
            authorize_manual()
            return 0
        authorize()
        return 0

    if args.command == "characters":
        # Files a pre-multi-character token under its character while it is
        # here, so the listing answers about the store as it will be rather
        # than as it was.
        ensure_legacy_token_migrated()
        known = stored_characters()
        if not known:
            print("no characters authorised -- run 'esi_waypoint.py auth'")
            return 0
        for entry in known:
            # Names and ids. Never a token, never its length, never a fragment.
            print(f"{entry['name']}\t{entry['id'] if entry['id'] is not None else '-'}")
        return 0

    if args.command == "forget":
        if forget_character(args.character):
            print(f"forgot {args.character.strip()!r}; still authorised: "
                  f"{describe_stored_characters()}")
        else:
            print(f"no stored token for {args.character.strip()!r}; authorised: "
                  f"{describe_stored_characters()}")
        return 0

    if args.command == "resolve":
        found_id, kind = resolve_name(args.name, character=args.character)
        print(f"{found_id}  ({kind[:-1]})")
        return 0

    deadline = Deadline(args.budget)
    destination = args.id
    if destination is None:
        destination, kind = resolve_name(args.name, deadline=deadline, character=args.character)
        print(f"# {args.name!r} -> {destination} ({kind[:-1]})")
    # Through `set_destination` rather than straight to `set_waypoint`, so the
    # CLI and the host cannot disagree about which character a destination goes
    # to. The name is already resolved, so this costs nothing extra.
    set_destination(destination_id=destination,
                    clear_other=not args.keep_other_waypoints,
                    add_to_beginning=args.add_to_beginning,
                    budget_seconds=max(deadline.remaining(), 0.0),
                    character=args.character)
    print(f"destination set to {destination}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except EsiError as failure:
        sys.exit(str(failure))
