import sys, pathlib
import lupa.lua51 as L
import lupa.lua51 as _lupa   # L is reused for the ledger below

here = pathlib.Path(__file__).parent
addon = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else here.parent
HARNESS = (here / "harness.lua").read_text(encoding="utf-8")

def toc_files():
    """The .lua files the game loads, in the .toc's order."""
    out = []
    for line in (addon / "PortalPro.toc").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#") and line.lower().endswith(".lua"):
            out.append(line.replace("\\", "/"))
    return out
FILES = toc_files()

def runtime(harness=None, pre=""):
    """A fresh game: the fake API, then every file of the .toc sharing one private table, as the game does."""
    lua = _lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(pre + "\n" + (harness if harness is not None else HARNESS))
    lua.execute("T.baseGlobals = {}; for k in pairs(_G) do T.baseGlobals[k] = true end")
    load = lua.eval("function(src, path, ns) local f, e = loadstring(src, path); if not f then error(e) end; f('PortalPro', ns) end")
    ns = lua.table()
    for f in FILES:
        load((addon / f).read_text(encoding="utf-8"), f, ns)
    lua.globals().T.ns = ns
    return lua

lua = runtime()

fails = 0
def check(name, ok, extra=""):
    global fails
    print(("PASS " if ok else "FAIL ") + name + (("  -- " + str(extra)) if extra and not ok else ""))
    if not ok: fails += 1

T = lua.globals().T
PP = lua.globals().PortalPro
fire = T.fire

def called(name):
    return [list(c.values()) for c in T.called(name).values()]

def advance(sec):
    T.time = T.time + sec

fire("ADDON_LOADED", "PortalPro")
fire("PLAYER_LOGIN")
check("login prints ready", any("Ready: 3 portals" in p for p in T.prints.values()), list(T.prints.values()))
check("cast button defaults to a known portal", lua.globals().PortalProCastButton.attrs["spell"] == "Portal: Undercity", lua.globals().PortalProCastButton.attrs["spell"])

# --- detection table
ci = PP._test.channelIntent
clean = PP._test.clean
cases = [
    ("WTB port to darn", True, "darn"),
    ("LF mage port to IF pls", True, "if"),
    ("any mage around for a portal to stormwind?", True, "sw"),
    ("port sw", True, "sw"),
    ("need portal", True, None),
    ("WTS Portals to SW/IF/Darn - 1g, whisper me", False, None),
    ("selling ports to darn, tips welcome", False, None),
    ("anyone selling port to darn?", True, "darn"),
    ("LFM SM cath need mage", False, None),
    ("if anyone wants to group for SM whisper me", False, None),
    ("report this guy for spam", False, None),
    ("LF tank for deadmines", False, None),
    ("can someone port me to Darnassus", True, "darn"),
    ("port to org", True, "org"),
    ("anyone with port to thunder bluff?", True, "tb"),
]
for line, want, city in cases:
    r = ci(clean(line)); ok, c = (r[0], r[1]) if isinstance(r, tuple) else (r, None)
    got_city = c.key if c else None
    check(f"chat '{line}' -> {want},{city}", bool(ok) == want and (not want or got_city == city), (ok, got_city))

wi = PP._test.whisperIntent
for line, want, city in [("inv", True, None), ("inv darn", True, "darn"), ("darn", True, "darn"), ("how much?", "price", None),
                         ("hey whats up", False, None), ("port to if please", True, "if"), ("IF", True, "if")]:
    r = wi(clean(line))
    ok, c = (r[0], r[1]) if isinstance(r, tuple) else (r, None)
    got_city = c.key if c else None
    check(f"whisper '{line}' -> {want},{city}", ok == want and got_city == city, (ok, got_city))

pm = PP._test.parseMoney
for s, v in [("1g50s", 15000), ("1.5g", 15000), ("150s", 15000), ("75c", 75), ("2", 20000), ("1g 50s", 15000), ("abc", None), ("0", 0)]:
    check(f"parseMoney {s}", pm(s) == v, pm(s))
check("money 15075", PP._test.money(15075) == "1g 50s 75c", PP._test.money(15075))

# --- a sale, start to end
fire("CHAT_MSG_CHANNEL", "WTB port to uc pls", "Bob-Forever", "", "2. Trade - City", "", "", 2, 2, "Trade - City")
check("buyer invited from trade chat", ["InviteUnit", "Bob"] in called("InviteUnit"), called("InviteUnit"))
check("sound on new buyer", len(called("PlaySound")) == 1)
check("no whisper on restricted realm", len(called("SendChatMessage")) == 0)

fire("CHAT_MSG_CHANNEL", "WTB port to uc pls", "Bob-Forever", "", "2. Trade - City", "", "", 2, 2, "Trade - City")
check("no second invite within 30 s", len(called("InviteUnit")) == 1)

T.party[1] = "Bob"
fire("GROUP_ROSTER_UPDATE")
check("cast button set to Undercity", lua.globals().PortalProCastButton.attrs["spell"] == "Portal: Undercity", lua.globals().PortalProCastButton.attrs["spell"])

advance(2); T.tick()
check("no trade when out of range", len(called("InitiateTrade")) == 0)
T.near["party1"] = True
T.tick()
check("no trade by itself in range", len(called("InitiateTrade")) == 0, called("InitiateTrade"))
lua.globals().PortalPro.togglePanel(True); T.ns.refresh()
_r = [T.ns.rows[i] for i in range(1, 21) if lua.eval("rawget")(T.ns.rows[i], "buyer") is not None and lua.eval("rawget")(T.ns.rows[i], "buyer").key == "bob"][0]
_r.scripts.OnClick(_r, "LeftButton")
check("trade opened when in range", ["InitiateTrade", "party1"] in called("InitiateTrade"), called("InitiateTrade"))

T.npc = "Bob"; TradeFrame = lua.globals().TradeFrame; TradeFrame.shown = True
fire("TRADE_SHOW")
T.tradeMoney = 2500
fire("TRADE_MONEY_CHANGED")
dock = lua.globals().PortalProDock
st = T.ns.dockState()
check("dock shows with the trade", dock is not None and dock.shown)
check("dock: city and payment", st.city.key == "uc" and st.owed == 5000 and st.got == 2500 and not st.paid, (st.owed, st.got))
check("dock cast matches panel cast", lua.globals().PortalProDockCast.attrs["spell"] == "Portal: Undercity"
      and lua.globals().PortalProDockCast.attrs["spell"] == lua.globals().PortalProCastButton.attrs["spell"])
PP.accept()
check("underpaid: first accept press only warns", len(called("AcceptTrade")) == 0)
T.tradeMoney = 5000
fire("TRADE_MONEY_CHANGED")
check("dock: paid", T.ns.dockState().paid == True)
PP.accept()
check("paid: accept goes through", len(called("AcceptTrade")) == 1)
TradeFrame.shown = False
fire("TRADE_CLOSED")
fire("UI_INFO_MESSAGE", 0, "Trade complete.")
fire("CHAT_MSG_SYSTEM", "Trade complete.")
db = lua.globals().PortalProDB
check("gold counted once", db.totals.income == 5000 and db.totals.trades == 1, (db.totals.income, db.totals.trades))
party = [c for c in called("SendChatMessage") if c[2] == "PARTY"]
check("thank-you sent to party", len(party) == 1 and party[0][1] == "Thank you Bob! Received 50s for the portal to Undercity.", party)
fire("CHAT_MSG_PARTY", party[0][1], "Mage")
check("own party line came back: direct mode", db.partyMode == "direct", db.partyMode)

advance(1)
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 11418)
check("portal counted with rune cost", db.totals.casts == 1 and db.totals.runeCost == 2000, (db.totals.casts, db.totals.runeCost))
advance(1); T.tick()
check("no kick while buyer still here", len(called("UninviteUnit")) == 0)
T.visible["party1"] = False
T.tick(); advance(1.1); T.tick()
check("buyer kicked after going through", ["UninviteUnit", "Bob"] in called("UninviteUnit"), called("UninviteUnit"))
check("served counted, not short", db.totals.served == 1 and db.totals.short == 0, (db.totals.served, db.totals.short))

# --- ad on restricted realm -> chat box
SlashCmdList = lua.globals().SlashCmdList
db.adAt = 0
PP.postAd(); T.runTimers()
oc = called("OpenChat")
oc = [c for c in oc if c[1].startswith("/2")]
check("ad goes into chat box as /2", len(oc) == 1 and oc[0][1].startswith("/2 WTS Portals Org -> UC / TB - 50s each."), oc)
PP.postAd(); T.runTimers()
check("ad cooldown holds", len([c for c in called("OpenChat") if c[1].startswith("/2")]) == 1)

# --- unrestricted realm: ad and whisper go direct
T.restricted = False
advance(61)
PP.postAd()
sc = called("SendChatMessage")
sc = [c for c in sc if c[2] == "CHANNEL"]
check("ad sent direct when allowed", len(sc) == 1 and sc[0][2] == "CHANNEL" and sc[0][3] == 2, sc)
fire("CHAT_MSG_WHISPER", "inv tb", "Ann-Forever")
sc = called("SendChatMessage")
check("whisper buyer invited + replied", ["InviteUnit", "Ann"] in called("InviteUnit") and sc[-1][2] == "WHISPER" and "Thunder Bluff" in sc[-1][1], sc[-1])
fire("CHAT_MSG_WHISPER", "port to darn", "Cid-Forever")
check("city we can't do: no invite", ["InviteUnit", "Cid"] not in called("InviteUnit"))
fire("CHAT_MSG_SYSTEM", "Ann declines your group invitation.")
ann = T.ns.buyers["ann"]
check("decline noted", ann is not None and ann.state == "declined", ann and ann.state)
fire("CHAT_MSG_SYSTEM", "Cannot find player 'Cid'.")
check("unknown player dropped", T.ns.buyers["cid"] is None)

# --- slash commands
SlashCmdList.PORTALPRO("price 2g")
check("/pp price", db.price == 20000)
SlashCmdList.PORTALPRO("price darn 3g")
check("/pp price darn", db.cityPrice["darn"] == 30000)
SlashCmdList.PORTALPRO("test WTB port to darn")
check("/pp test prints", "buyer" in T.prints[len(T.prints)], T.prints[len(T.prints)])
SlashCmdList.PORTALPRO("stats")
SlashCmdList.PORTALPRO("help")
SlashCmdList.PORTALPRO("kick")
check("/pp kick toggles", db.autoKick == False)

# --- ledger: tip, unpaid, late payment, net, vendor price, reset
SlashCmdList.PORTALPRO("price 50s")
T.restricted = True
advance(200)
def sale_trade(name, amount):
    T.npc = name; TradeFrame.shown = True
    fire("TRADE_SHOW"); T.tradeMoney = amount; fire("TRADE_MONEY_CHANGED")
    TradeFrame.shown = False; fire("TRADE_CLOSED"); fire("UI_INFO_MESSAGE", 0, "Trade complete.")
fire("CHAT_MSG_CHANNEL", "WTB port to tb", "Dan-Forever", "", "2. Trade - City", "", "", 2, 2, "Trade - City")
T.party[1] = "Dan"; T.visible["party1"] = True
fire("GROUP_ROSTER_UPDATE")
db.partyMode = None
sale_trade("Dan", 7000)
party = [c for c in called("SendChatMessage") if c[2] == "PARTY"]
check("tip in thank-you", party[-1][1] == "Thank you Dan! Received 70s for the portal to Thunder Bluff (incl. 20s tip - much appreciated!).", party[-1])
advance(3.5); T.tick(); T.runTimers()
boxp = [c for c in called("OpenChat") if c[1].startswith("/p ")]
check("no echo: falls back to chat box", db.partyMode == "box" and len(boxp) == 1 and "Dan" in boxp[0][1], (db.partyMode, boxp))
L = db.ledger; last = L[len(L)]
check("tip recorded (7000 paid on 50s price)", last.k == "trade" and last.g == 7000 and last.tip == 2000, (last.k, last.g, last.tip))
fire("CHAT_MSG_CHANNEL", "port to tb pls", "Eve-Forever", "", "2. Trade - City", "", "", 2, 2, "Trade - City")
T.party[2] = "Eve"; T.visible["party2"] = True
fire("GROUP_ROSTER_UPDATE")
advance(1); fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 11420)
last = db.ledger[len(db.ledger)]
check("cast entry: 2 buyers at the portal", last.k == "cast" and last.b == 2 and last.r == 2000, (last.k, last.b, last.r))
T.visible["party1"] = False; T.visible["party2"] = False
T.tick(); advance(1.1); T.tick()
check("Eve through unpaid", db.totals.unpaid == 1 and db.totals.short == 5000, (db.totals.unpaid, db.totals.short))
nparty = len([c for c in called("SendChatMessage") if c[2] == "PARTY"]) + len([c for c in called("OpenChat") if c[1].startswith("/p ")])
sale_trade("Eve", 5000)
check("no party line for a buyer no longer in group", nparty == len([c for c in called("SendChatMessage") if c[2] == "PARTY"]) + len([c for c in called("OpenChat") if c[1].startswith("/p ")]))
check("Eve paid late: short cleared", db.totals.unpaid == 0 and db.totals.short == 0, (db.totals.unpaid, db.totals.short))
check("income 17000, runes 4000", db.totals.income == 17000 and db.totals.runeCost == 4000 and db.totals.tips == 2000, (db.totals.income, db.totals.runeCost, db.totals.tips))
sale_trade("Stranger", 9000)
check("trade with a non-buyer ignored", db.totals.income == 17000)
T.merchant[1] = lua.table(link="|cffffffff|Hitem:17032::::::::60:::::|h[Rune of Portals]|h|r", price=1800, qty=1)
fire("MERCHANT_SHOW")
check("rune cost read from vendor", db.runeCost == 1800, db.runeCost)
PP.toggleLedger()
lf = lua.globals().PortalProLedger
check("ledger window shows", lf.shown == True)
texts = [lf.rows[i].text or "" for i in range(1, 13)]
check("ledger lists Eve's late payment first", "Eve paid" in texts[0], texts[:3])
check("ledger net all-time tile", "1g 30s" in (lf.tiles[3].value.text or ""), lf.tiles[3].value.text)
SlashCmdList.PORTALPRO("stats")
check("/pp stats prints net", any("net 1g 30s" in p for p in T.prints.values()), list(T.prints.values())[-3:])
SlashCmdList.PORTALPRO("ledger reset")
check("reset asks first", len(db.ledger) > 0)
SlashCmdList.PORTALPRO("ledger reset")
check("reset second time clears", len(db.ledger) == 0 and db.totals.income == 0)
fire("TRADE_SHOW"); T.npc = "Dan"
SlashCmdList.PORTALPRO("price 50s")
fire("CHAT_MSG_CHANNEL", "WTB port to uc", "Fay-Forever", "", "2. Trade - City", "", "", 2, 2, "Trade - City")
T.party[1] = "Fay"; fire("GROUP_ROSTER_UPDATE"); sale_trade("Fay", 3000); T.runTimers(); advance(1.5); T.tick(); T.runTimers()
boxp = [c for c in called("OpenChat") if c[1].startswith("/p ")]
check("box mode: short trade says so", boxp[-1][1] == "/p Fay: received 30s - still 20s short of the 50s price.", boxp[-1])
SlashCmdList.PORTALPRO("thanks Cheers {name}, got {got}!")
check("/pp thanks custom text", db.thanksText == "Cheers {name}, got {got}!" and "Cheers Bob, got 1g" not in T.prints[len(T.prints)] and "Cheers Bob, got 60s!" in T.prints[len(T.prints)], T.prints[len(T.prints)])
SlashCmdList.PORTALPRO("thanks off")
check("/pp thanks off", db.thanks == False)
check("new entry after reset", len(db.ledger) == 1)
lua.globals().StaticPopupDialogs.PORTALPRO_RESET_LEDGER.OnAccept()
check("reset button popup clears ledger", len(db.ledger) == 0 and db.totals.income == 0)
SlashCmdList.PORTALPRO("runecost 18s")
check("/pp runecost", db.runeCost == 1800)

# --- messages window
SlashCmdList.PORTALPRO("thanks reset")
SlashCmdList.PORTALPRO("thanks on")
SlashCmdList.PORTALPRO("messages")
mf = lua.globals().PortalProMessages

_anch = lua.eval("function(o, r) local ps = o and rawget(o, 'points') or {} for _, p in ipairs(ps) do if rawequal(p[2], r) then return true end end return false end")
def anchored_to(obj, rel): return bool(_anch(obj, rel))
check("messages tab: tokens line sits under its preview", anchored_to(mf.ad.tk, mf.ad.pv) and anchored_to(mf.thanks.tk, mf.thanks.pv))
check("messages tab: thank-you editor starts under the ad editor", anchored_to(mf.thanks.label, mf.ad.tk))
check("messages window opens", mf.shown == True)
eb = mf.ad.eb
check("ad box shows the standard template", eb.text == 'WTS Portals {route} - {price} each. Whisper me "inv" + the city!', eb.text)
check("ad preview filled", "WTS Portals Org -> UC / TB - 50s each." in mf.ad.pv.text, mf.ad.pv.text)
eb.text = "Portals {route} only {price}!"; eb.scripts.OnTextChanged(eb)
check("ad preview live", "Portals Org -> UC / TB only 50s!" in mf.ad.pv.text, mf.ad.pv.text)
eb.scripts.OnEditFocusLost(eb)
check("ad saved", db.ad == "Portals {route} only {price}!", db.ad)
db.adAt = 0; T.restricted = True; PP.postAd(); T.runTimers()
check("saved ad is what gets posted", called("OpenChat")[-1][1] == "/2 Portals Org -> UC / TB only 50s!", called("OpenChat")[-1])
eb.text = "junk"; eb.scripts.OnEscapePressed(eb)
check("Escape undoes the edit", eb.text == "Portals {route} only {price}!" and db.ad == "Portals {route} only {price}!", (eb.text, db.ad))
eb.text = "x" * 250 + " {route}"; eb.scripts.OnTextChanged(eb)
check("too long warned", "too long for chat" in mf.ad.pv.text)
eb.text = 'WTS Portals {route} - {price} each. Whisper me "inv" + the city!'; eb.scripts.OnEditFocusLost(eb)
check("back to the standard text clears the custom ad", db.ad is None, db.ad)
eb.text = "   "; eb.scripts.OnEditFocusLost(eb)
check("empty ad = standard", db.ad is None and eb.text.startswith("WTS Portals {route}"))
tb = mf.thanks.eb
check("thanks box shows the standard template", tb.text == "Thank you {name}! Received {got} for the portal to {city}{tip}.", tb.text)
tb.text = "Ty {name}, got {got}{tip}"; tb.scripts.OnTextChanged(tb); tb.scripts.OnEditFocusLost(tb)
check("thanks saved + preview", db.thanksText == "Ty {name}, got {got}{tip}" and "Ty Bob, got 60s (incl. 10s tip" in mf.thanks.pv.text, (db.thanksText, mf.thanks.pv.text))
cb = mf.thanksCheck
check("checkbox shows thanks on", cb.checked == True)
cb.checked = False; cb.scripts.OnClick(cb)
check("checkbox turns thanks off", db.thanks == False)
cb.checked = True; cb.scripts.OnClick(cb)
check("checkbox turns thanks on", db.thanks == True)

# --- resizing: one window, its pages follow its size
pnl = lua.globals().PortalProPanel
pnl.SetSize(pnl, 460, 420); low = pnl.visibleRows
pnl.SetSize(pnl, 460, 640); high = pnl.visibleRows
check("taller window shows more buyer rows", 1 <= low < high, (low, high))
check("top buttons share the width", pnl.ad.w == pnl.accept.w and pnl.ad.w > 100, (pnl.ad.w, pnl.accept.w))
pnl.grip.scripts.OnMouseDown(pnl.grip, "LeftButton"); pnl.grip.scripts.OnMouseUp(pnl.grip)
check("window size saved", db.frames.main.w == 460 and db.frames.main.h == 640, db.frames.main and (db.frames.main.w, db.frames.main.h))
T.combat = True; T.sizing = None
pnl.grip.scripts.OnMouseDown(pnl.grip, "LeftButton")
check("no window resize in combat", T.sizing is None)
T.combat = False
lf = lua.globals().PortalProLedger
pnl.SetSize(pnl, 460, 420); few = lf.visible
pnl.SetSize(pnl, 460, 700); more = lf.visible
check("taller window shows more ledger history", few < more, (few, more))

import lupa.lua51 as LUPA
# --- Forever surnames: "Nx Thearabian" yells, joins, trades, goes through
T.party[1] = None; T.party[2] = None; fire("GROUP_ROSTER_UPDATE")
nInv = len(called("InviteUnit"))
advance(400); T.tick()
fire("CHAT_MSG_YELL", "WTB UC PORTAL", "Nx Thearabian")
check("surname buyer invited by full name", called("InviteUnit")[-1] == ["InviteUnit", "Nx Thearabian"], called("InviteUnit")[-1])
T.party[1] = "Nx Thearabian"; T.visible["party1"] = True; T.near["party1"] = True
fire("GROUP_ROSTER_UPDATE")
check("surname buyer seen in group", lua.eval("PortalPro").castCity.key == "uc")
advance(2); T.tick(); T.ns.refresh()
_r = [T.ns.rows[i] for i in range(1, 21) if lua.eval("rawget")(T.ns.rows[i], "buyer") is not None and lua.eval("rawget")(T.ns.rows[i], "buyer").key == "nx thearabian"][0]
_r.scripts.OnClick(_r, "LeftButton")
check("trade opened with surname buyer", called("InitiateTrade")[-1] == ["InitiateTrade", "party1"])
before = db.totals.income
sale_trade("Nx Thearabian", 5000)
check("surname buyer's payment counted", db.totals.income == before + 5000, (before, db.totals.income))

# --- one window with tabs: Buyers / Messages / Ledger
SL = lua.globals().SlashCmdList.PORTALPRO
pages = {"buyers": lua.globals().PortalProBuyers, "messages": lua.globals().PortalProMessages, "ledger": lua.globals().PortalProLedger}
def shown_pages(): return sorted(k for k, f in pages.items() if f is not None and f.shown)
pnl = lua.globals().PortalProPanel
SL("ledger")
check("/pp ledger shows ledger tab", pnl.shown and shown_pages() == ["ledger"], (pnl.shown, shown_pages()))
SL("messages")
check("tabs: one page at a time", shown_pages() == ["messages"], shown_pages())
SL("messages")
check("/pp messages again hides the window", not pnl.shown)
SL("")
check("/pp shows it on the Buyers tab", pnl.shown and shown_pages() == ["buyers"], shown_pages())

# --- buyer rows: class colour, the city's portal icon
def row_for(key):
    for i in range(1, 21):
        r = T.ns.rows[i]
        if r and r.shown and r.buyer and r.buyer.key == key: return r
T.guids["Player-1-0CD"] = "PRIEST"
T.guids["Player-1-0AB"] = "MAGE"
fire("CHAT_MSG_WHISPER", "inv uc", "Holy Bread", "", "", "", "", 0, 0, "", 0, 7, "Player-1-0AB")
hb = row_for("holy bread")
check("buyer row class colour", hb is not None and "3fc7eb" in (hb.name.text or ""), hb and hb.name.text)
check("buyer row portal icon", hb is not None and hb.icon.icon == "tex:11418", hb and hb.icon.icon)
check("buyer row says city and where", hb is not None and "Undercity" in (hb.sub.text or "") and "whisper" in (hb.sub.text or ""), hb and hb.sub.text)
fire("CHAT_MSG_WHISPER", "inv tb", "Plain Jane")
pj = row_for("plain jane")
check("buyer row without GUID is white", pj is not None and "|cffffffff" in (pj.name.text or ""), pj and pj.name.text)

# --- the ledger dashboard
real = db.ledger
day0 = T.ns.dayStart()
def e(d): return lua.table_from(d)
db.ledger = lua.table(
    e({"t": day0 + 3600, "k": "trade", "n": "A", "c": "uc", "p": 5000, "g": 6000, "tip": 1000}),
    e({"t": day0 + 3700, "k": "cast", "c": "uc", "r": 2000, "b": 1}),
    e({"t": day0 - 2 * 86400, "k": "trade", "n": "B", "c": "tb", "p": 5000, "g": 5000, "tip": 0}),
    e({"t": day0 - 2 * 86400 + 60, "k": "trade", "n": "C", "c": "tb", "p": 5000, "g": 5000, "tip": 0}),
    e({"t": day0 - 9 * 86400, "k": "trade", "n": "D", "c": "org", "p": 5000, "g": 99999, "tip": 0}),
    e({"t": day0 - 3600, "k": "served", "n": "E", "c": "uc", "p": 5000, "g": 0}),
    e({"t": day0 - 1800, "k": "served", "n": "F", "c": "uc", "p": 5000, "g": 2000}),
)
days = T.ns.ledgerDays(7)
got = [(days[i].income, days[i].tips) for i in range(1, 8)]
check("ledgerDays groups by day", got[6] == (6000, 1000) and got[4] == (10000, 0) and sum(x[0] for x in got) == 16000, got)
best = T.ns.bestSellers(3)
names = [(best[i].label, best[i].count, best[i].income) for i in range(1, len(best) + 1)]
check("bestSellers by city", names[0] == ("Orgrimmar", 1, 99999) and names[1] == ("Thunder Bluff", 2, 10000), names)
n, c = T.ns.owing()
check("owing counts short and unpaid", (n, c) == (2, 8000), (n, c))
SL("ledger")
lf = lua.globals().PortalProLedger
check("ledger tab best sellers", "Orgrimmar" in (lf.best[1].text or ""), lf.best[1].text)
check("ledger tab owing line", T.ns.money(8000) in (lf.owing.text or ""), lf.owing.text)
db.ledger = real
SL("")

# --- the dock: only for portal buyers and group members; below EnchantPro's dock; combat
T.npc = "Some Stranger"; TradeFrame.shown = True; T.tradeMoney = 0
fire("TRADE_SHOW")
dock = lua.globals().PortalProDock
check("dock: not for a stranger", not dock.shown and T.ns.dockState() is None)
fire("TRADE_CLOSED")
epdock = lua.eval("CreateFrame('Frame', 'EnchantProDock')")
T.npc = "Holy Bread"
fire("TRADE_SHOW")
same = lua.eval("function(a, b) return a == b end")
check("dock sits below EnchantPro's", dock.shown and dock.point is not None and same(dock.point[2], epdock) and dock.point[1] == "TOPLEFT" and dock.point[3] == "BOTTOMLEFT",
      dock.point and (dock.point[1], dock.point[3]))
lua.globals().EnchantProDock = None
T.combat = True
fire("TRADE_CLOSED")
check("dock in combat waits", dock.shown)
T.combat = False
fire("PLAYER_REGEN_ENABLED")
check("dock hides after combat", not dock.shown)

# --- minimap button, compact bar, new-buyer pop-up
for k in list(T.ns.buyers.keys()): T.ns.buyers[k] = None
T.ns.refresh()
mm = lua.globals().PortalProMinimapButton
toast = lua.globals().PortalProToast
check("badge hidden at 0", mm is not None and not mm.badge.shown)
fire("CHAT_MSG_WHISPER", "inv uc", "Ann Toast")
check("toast on new buyer", toast.shown and "Undercity" in (toast.what.text or "") and "Ann Toast" in (toast.who.text or ""), (toast.shown, toast.what.text))
fire("CHAT_MSG_WHISPER", "inv tb", "Ben Badge")
check("badge counts buyers", mm.badge.shown and mm.badge.text.text == "2", mm.badge.text.text)
fire("CHAT_MSG_WHISPER", "inv uc", "Ann Toast")
check("toast once per buyer", toast.key == "ben badge", toast.key)
advance(7); T.runTimers()
check("toast hides after 6 s", not toast.shown)
SL("compact")
bar = lua.globals().PortalProCompact
check("compact folds", bar.shown and not pnl.shown and "2 in queue" in (bar.text.text or ""), (bar.shown, pnl.shown, bar.text.text))
SL("compact")
check("compact unfolds", not bar.shown and pnl.shown)
SL("minimap")
check("/pp minimap hides the button", not mm.shown)
SL("minimap")
check("/pp minimap shows it again", mm.shown)
T.combat = True
SL("")
check("toggle in combat waits", pnl.shown)
T.combat = False
fire("PLAYER_REGEN_ENABLED")
check("hidden after combat", not pnl.shown)
SL("")
T.combat = True
tb3 = pnl.tabs.buttons[3]
tb3.scripts.OnClick(tb3)
check("tab click in combat waits", shown_pages() == ["buyers"], shown_pages())
T.combat = False
fire("PLAYER_REGEN_ENABLED")
check("tab switches after combat", pnl.shown and shown_pages() == ["ledger"], (pnl.shown, shown_pages()))
PP.showTab("buyers")

# --- saved settings from 0.6.0 (separate windows) load cleanly
lua4 = runtime(pre="PortalProDB = { point = { 'CENTER', 'CENTER', 300, 0 }, shown = true, frames = { ledger = { point = { 'CENTER', 'CENTER', 10, 10 }, w = 430, h = 430 }, messages = { w = 480, h = 250 }, panel = { w = 300, h = 290 } } }")
lua4.globals().T.fire("ADDON_LOADED", "PortalPro"); lua4.globals().T.fire("PLAYER_LOGIN")
check("old window saves load", lua4.globals().PortalProPanel is not None and lua4.globals().PortalProPanel.tabs is not None)

# --- the code: every file in the .toc, small files, no globals beyond its own names, the shared kit in step
import re
on_disk = sorted(q.relative_to(addon).as_posix() for q in addon.rglob("*.lua")
                 if "tests" not in q.relative_to(addon).parts and not q.relative_to(addon).parts[0].startswith("."))
check("toc lists every .lua file", sorted(FILES) == on_disk, (FILES, on_disk))
new_globals = [k for k in lua.eval("function() local t = {} for k in pairs(_G) do if not T.baseGlobals[k] then t[#t + 1] = tostring(k) end end return t end")().values()
               if not re.match(r"^(PortalPro|SLASH_|BINDING_)", k)]
check("no stray globals", not new_globals, new_globals)
sizes = {f: len((addon / f).read_text(encoding="utf-8").splitlines()) for f in FILES}
check("files stay small", all(n < 700 for n in sizes.values()), sizes)
bad_art = [f for f in FILES if re.search(r'Interface\\(?!\\)', (addon / f).read_text(encoding="utf-8"))]
check("art paths keep their backslashes", not bad_art, bad_art)
check("minimap button default angle", db.ui.minimapAngle == 225, db.ui.minimapAngle)
check("compact bar default place", lua.globals().PortalProCompact.point[5] == -118, lua.globals().PortalProCompact.point[5])
sibling = addon.parent / "EnchantPro" / "UI" / "Kit.lua"
if sibling.exists():
    check("kit copies identical", (addon / "UI" / "Kit.lua").exists() and (addon / "UI" / "Kit.lua").read_bytes() == sibling.read_bytes())
else:
    print("SKIP kit copies identical (no EnchantPro next to this addon)")

# --- character without portals (under level 40): buyers listed, nobody invited
lua3 = runtime(HARNESS + "\nfunction IsPlayerSpell() return false end")
T3 = lua3.globals().T
T3.fire("ADDON_LOADED", "PortalPro"); T3.fire("PLAYER_LOGIN")
T3.fire("CHAT_MSG_YELL", "WTB UC PORTAL", "Nx Thearabian")
rows3 = lua3.globals().PortalPro
names3 = [c for c in T3.calls.values() if c[1] == "InviteUnit"]
check("no portals: nobody invited", len(names3) == 0)
check("no portals: buyer still announced", any("Nx Thearabian" in p and "no portal there" in p for p in T3.prints.values()), list(T3.prints.values()))
check("no portals: cast button says level 40", lua3.globals().PortalProCastButton.text == "No portals yet (level 40+)", lua3.globals().PortalProCastButton.text)

# --- not a mage: nothing at all
import lupa.lua51 as LUPA
lua2 = runtime(HARNESS.replace('T.class = T.class or "MAGE"', 'T.class = "WARRIOR"'), pre="T = nil")
T2 = lua2.globals().T
T2.fire("ADDON_LOADED", "PortalPro")
T2.fire("PLAYER_LOGIN")
check("warrior: no panel", lua2.globals().PortalProPanel is None)
check("warrior: no cast button", lua2.globals().PortalProCastButton is None)
check("warrior: no ticker", T2.tick is None)
T2.fire("CHAT_MSG_CHANNEL", "WTB port to uc", "Bob-Forever", "", "2. Trade - City", "", "", 2, 2, "Trade - City")
check("warrior: buyer line ignored", len([c for c in T2.calls.values() if c[1] == "InviteUnit"]) == 0)
check("warrior: silent at login", len(T2.prints) == 0, list(T2.prints.values()))
lua2.globals().SlashCmdList.PORTALPRO("price 2g")
check("warrior: /pp says mage only", "only works on a mage" in T2.prints[len(T2.prints)] and lua2.globals().PortalProDB.price == 5000)
lua2.globals().PortalPro_PostAd(); lua2.globals().PortalPro_TogglePanel(); lua2.globals().PortalPro_AcceptTrade()
check("warrior: keybinds do nothing", len(T2.calls) == 0)


# --- the queue: numbers, order, lifetime, saved, click to trade
import re as _re

def lua_src(v):
    t = LUPA.lua_type(v)
    if t == "table":
        parts = []
        for k, x in v.items():
            key = ("[%d]" % k) if isinstance(k, int) else ("[%r]" % k).replace("'", '"')
            parts.append(key + " = " + lua_src(x))
        return "{ " + ", ".join(parts) + " }"
    if isinstance(v, bool): return "true" if v else "false"
    if isinstance(v, (int, float)): return repr(v)
    if isinstance(v, str): return '"' + v.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'
    return "nil"
def row_of(ns_, key, rawget_):
    for i in range(1, 21):
        r = ns_.rows[i]
        b = rawget_(r, "buyer")
        if b is not None and b.key == key: return r
    return None
lq = runtime()
GQ, TQ = lq.globals(), lq.globals().T
rg = lq.eval("rawget")
TQ.restricted = False
TQ.fire("ADDON_LOADED", "PortalPro"); TQ.fire("PLAYER_LOGIN")
NQ, qbq = TQ.ns, TQ.ns.buyers
def calledq(name): return [list(c.values()) for c in TQ.called(name).values()]
TQ.fire("CHAT_MSG_WHISPER", "inv uc pls", "Ann Zed")
TQ.time = TQ.time + 5
TQ.fire("CHAT_MSG_WHISPER", "inv tb pls", "Ben Yo")
check("queue: numbered in the order they asked", (qbq["ann zed"].n, qbq["ben yo"].n) == (1, 2), (qbq["ann zed"].n, qbq["ben yo"].n))
wl = [c[1] for c in calledq("SendChatMessage") if c[2] == "WHISPER"]
check("reply: the second hears their place", wl and "You're #2 in the queue." in wl[-1] and "in the queue" not in wl[0], wl)
TQ.time = TQ.time + 40
TQ.fire("CHAT_MSG_WHISPER", "inv uc pls", "Ann Zed")
check("queue: asking again keeps the number", qbq["ann zed"].n == 1 and NQ.place(qbq["ann zed"]) == 1)
TQ.time = TQ.time + 6 * 60
TQ.tick()
check("queue: still there after 6 minutes", qbq["ann zed"] is not None and qbq["ben yo"] is not None)
# a group member in range: no trade by itself, a click trades
TQ.party[1] = "Ben Yo"; TQ.fire("GROUP_ROSTER_UPDATE")
TQ.near["party1"] = True
TQ.time = TQ.time + 3
TQ.tick()
check("no trade opens by itself", calledq("InitiateTrade") == [], calledq("InitiateTrade"))
GQ.PortalPro.togglePanel(True)
NQ.refresh()
brow = row_of(NQ, "ben yo", rg)
check("rows: the first in range is marked", brow.marked == True and row_of(NQ, "ann zed", rg).marked == False)
brow.scripts.OnClick(brow, "LeftButton")
check("a click trades with the buyer in range", calledq("InitiateTrade") == [["InitiateTrade", "party1"]], calledq("InitiateTrade"))
TQ.fire("CHAT_MSG_SYSTEM", "Ann Zed declines your group invitation.")
n_inv = len(calledq("InviteUnit"))
arow = row_of(NQ, "ann zed", rg)
arow.scripts.OnClick(arow, "LeftButton")
check("a click on someone not in the group invites", len(calledq("InviteUnit")) == n_inv + 1, calledq("InviteUnit")[-1:])
def rname(i): return _re.sub(r"\|c[0-9a-f]{8}|\|r", "", NQ.rows[i].name.text or "")
check("rows: numbered", rname(1).startswith("#1 Ann Zed") and rname(2).startswith("#2 Ben Yo"), (rname(1), rname(2)))
for i in range(1, 26):
    TQ.fire("CHAT_MSG_CHANNEL", "WTB port to uc", "C%02d Qx" % i, "", "2. Trade - City", "", "", 2, 2, "Trade - City")
NQ.refresh()
pg = GQ.PortalProBuyers
for _ in range(3): pg.scripts.OnMouseWheel(pg, -1)
check("rows: the wheel scrolls the queue", rname(1).startswith("#4 "), rname(1))
check("bar: counts the queue", (GQ.PortalProCompact.text.text or "").startswith("27 in queue · 1 in group"), GQ.PortalProCompact.text.text)
keysq = [NQ.toggles[i].key for i in range(1, len(NQ.toggles) + 1)]
check("no Trade switch any more", "autoTrade" not in keysq, keysq)
# a client restart: GetTime starts over, the wall clock moved on 60 s
wait_before = TQ.time - qbq["ann zed"].since
TQ.fire("PLAYER_LOGOUT")
saved_wall = GQ.time()
lr = runtime(pre="PortalProDB = " + lua_src(GQ.PortalProDB))
GR, TR = lr.globals(), lr.globals().T
TR.time = 100; TR.wallOffset = saved_wall + 60 - 100
TR.fire("ADDON_LOADED", "PortalPro"); TR.fire("PLAYER_LOGIN")
qbr = TR.ns.buyers
okr = qbr["ann zed"] is not None and qbr["ben yo"] is not None
check("restore: the queue is back after a restart", okr and (qbr["ann zed"].n, qbr["ben yo"].n) == (1, 2), okr and (qbr["ann zed"].n, qbr["ben yo"].n))
check("restore: waiting time carries on", okr and abs((TR.time - qbr["ann zed"].since) - (wait_before + 60)) <= 1)
check("restore: not in the group any more", okr and qbr["ben yo"].unit is None)
sdr = okr and TR.ns.buyers["ann zed"] and lr.eval("rawget")(qbr["ann zed"], "said")
check("restore: what they wrote is kept too", bool(sdr) and sdr[1].text == "inv uc pls", sdr and len(sdr))
TR.fire("CHAT_MSG_WHISPER", "inv uc pls", "Dee Dx")
check("restore: numbers carry on", qbr["dee dx"].n == 28, qbr["dee dx"].n)
TR.time = TR.time + 7201
TR.tick()
check("queue: dropped after 2 hours without a word", qbr["ann zed"] is None and qbr["dee dx"] is None)


# --- review fixes: a paid buyer isn't dropped as quiet; a buyer you can't port for leaves
lf = runtime()
GF, TF = lf.globals(), lf.globals().T
TF.fire("ADDON_LOADED", "PortalPro"); TF.fire("PLAYER_LOGIN")
qbf = TF.ns.buyers
TF.fire("CHAT_MSG_WHISPER", "need portal", "Can Not")
TF.fire("CHAT_MSG_WHISPER", "port to darn", "Can Not")
TF.time = TF.time + 6 * 60
TF.tick()
check("a numbered buyer you then can't port for leaves after 5 minutes", qbf["can not"] is None, qbf["can not"] and (qbf["can not"].cantPort, qbf["can not"].n))
TF.fire("CHAT_MSG_WHISPER", "inv uc pls", "Pay Er")
TF.party[1] = "Pay Er"; TF.fire("GROUP_ROSTER_UPDATE")
TF.time = TF.time + 110 * 60
TF.npc = "Pay Er"; GF.TradeFrame.shown = True; TF.tradeMoney = 5000
TF.fire("TRADE_SHOW"); TF.fire("TRADE_MONEY_CHANGED")
TF.fire("UI_INFO_MESSAGE", 0, "Trade complete.")
TF.fire("TRADE_CLOSED"); GF.TradeFrame.shown = False
TF.party[1] = None; TF.fire("GROUP_ROSTER_UPDATE")
TF.time = TF.time + 11 * 60
TF.tick()
check("a buyer who paid isn't dropped as quiet", qbf["pay er"] is not None and (qbf["pay er"].paid or 0) > 0, qbf["pay er"] and qbf["pay er"].paid)


# --- hover a buyer: what they wrote and what it was read as; shift-right-click blocks them for good
lh = runtime()
GH, TH = lh.globals(), lh.globals().T
TH.fire("ADDON_LOADED", "PortalPro"); TH.fire("PLAYER_LOGIN")
qbh, rgh = TH.ns.buyers, lh.eval("rawget")
GH.PortalPro.togglePanel(True)
TH.fire("CHAT_MSG_WHISPER", "inv uc pls", "Ann Zed")
TH.fire("CHAT_MSG_CHANNEL", "need port to darn", "Can Not", "", "2. Trade", "", "", 2, 2, "Trade")
TH.ns.refresh()
def tip_of(key):
    r = row_of(TH.ns, key, rgh)
    GH.GameTooltip.text = None
    if r is not None and r.scripts.OnEnter: r.scripts.OnEnter(r)
    return rgh(GH.GameTooltip, "text") or ""
ta = tip_of("ann zed")
check("hover: the tooltip shows what they wrote and the city it was read as", "inv uc pls" in ta and "Undercity" in ta and "whisper" in ta, ta)
check("hover: lines on separate rows", "\n" in ta, ta)
tc = tip_of("can not")
check("hover: a city you can't port to shows, with where it was said", "need port to darn" in tc and "Trade" in tc and "can't" in tc, tc)
for i in range(1, 8):
    TH.fire("CHAT_MSG_WHISPER", "inv uc pls " + str(i), "Ann Zed")
sdh = rgh(qbh["ann zed"], "said") or []
check("hover: keeps the last 5 lines", len(sdh) == 5 and sdh[5].text == "inv uc pls 7", len(sdh))
ra = row_of(TH.ns, "ann zed", rgh)
TH.shift = True
if ra is not None: ra.scripts.OnClick(ra, "RightButton")
TH.shift = False
blh = rgh(GH.PortalProDB, "blocked")
check("block: shift-right-click takes them off and remembers them", qbh["ann zed"] is None and blh is not None and blh["ann zed"] is not None)
nt = len(TH.calls)
TH.fire("CHAT_MSG_WHISPER", "inv uc pls", "Ann Zed")
check("block: they're never listed again", qbh["ann zed"] is None)
check("block: no invite, no answer", not any(TH.calls[i][1] in ("SendChatMessage", "InviteUnit", "C_PartyInfo.InviteUnit") for i in range(nt + 1, len(TH.calls) + 1)),
      [TH.calls[i][1] for i in range(nt + 1, len(TH.calls) + 1)])
GH.SlashCmdList.PORTALPRO("unblock ann zed")
TH.fire("CHAT_MSG_WHISPER", "inv uc pls", "Ann Zed")
check("block: /pp unblock lets them back", qbh["ann zed"] is not None)
GH.SlashCmdList.PORTALPRO("block Some Body")
TH.fire("CHAT_MSG_WHISPER", "inv uc pls", "Some Body")
check("block: /pp block Name blocks by name", qbh["some body"] is None and GH.PortalProDB.blocked["some body"] is not None)
GH.SlashCmdList.PORTALPRO("block")
TH.ns.refresh()
rc = row_of(TH.ns, "can not", rgh)
if rc is not None: rc.scripts.OnClick(rc, "RightButton")
check("block: a plain right-click only removes", qbh["can not"] is None and GH.PortalProDB.blocked["can not"] is None)


# --- an enchant trade (EnchantPro's) with someone in the group isn't a portal sale
def group_trade(Gx, Tx, who, amount):
    Tx.party[1] = who; Tx.fire("GROUP_ROSTER_UPDATE")
    Tx.npc = who; Gx.TradeFrame.shown = True; Tx.tradeMoney = amount
    Tx.fire("TRADE_SHOW"); Tx.fire("TRADE_MONEY_CHANGED")
    dock = Tx.ns.dockState()
    Tx.fire("UI_INFO_MESSAGE", 0, "Trade complete.")
    Tx.fire("TRADE_CLOSED"); Gx.TradeFrame.shown = False
    return dock
le = runtime()
GE, TE = le.globals(), le.globals().T
TE.fire("ADDON_LOADED", "PortalPro"); TE.fire("PLAYER_LOGIN")
GE.PortalProDB.thanks = True
claimed = le.eval("{}")
GE.EnchantPro = le.eval("function(c) return { claims = function(name) return c[name] == true end } end")(claimed)
claimed["Awar Lock"] = True
n0, c0 = len(GE.PortalProDB.ledger), len(TE.calls)
dock_e = group_trade(GE, TE, "Awar Lock", 500)
party = [TE.calls[i] for i in range(c0 + 1, len(TE.calls) + 1) if TE.calls[i][1] == "SendChatMessage"]
check("enchant trade: not in PortalPro's ledger", len(GE.PortalProDB.ledger) == n0, len(GE.PortalProDB.ledger) - n0)
check("enchant trade: nothing said in party", len(party) == 0, [p[2] for p in party])
check("enchant trade: not listed as a portal buyer", TE.ns.buyers["awar lock"] is None)
check("enchant trade: no portal dock", dock_e is None)
TE.party[1] = None; TE.fire("GROUP_ROSTER_UPDATE")
n1 = len(GE.PortalProDB.ledger)
dock_p = group_trade(GE, TE, "Port Guy", 5000)
check("a group member EnchantPro doesn't know still pays for a portal", len(GE.PortalProDB.ledger) == n1 + 1 and dock_p is not None)
TE.party[1] = "Awar Lock"; TE.fire("GROUP_ROSTER_UPDATE")
TE.npc = "Awar Lock"; GE.TradeFrame.shown = True; TE.tradeMoney = 500
TE.fire("TRADE_SHOW"); TE.fire("TRADE_MONEY_CHANGED")
na = len([1 for i in range(1, len(TE.calls) + 1) if TE.calls[i][1] == "AcceptTrade"])
GE.PortalPro.accept()
nb = len([1 for i in range(1, len(TE.calls) + 1) if TE.calls[i][1] == "AcceptTrade"])
check("enchant trade: PortalPro's accept key accepts without a portal-price warning", nb == na + 1)
TE.fire("TRADE_CLOSED"); GE.TradeFrame.shown = False

print("\n%d failure(s)" % fails)
sys.exit(1 if fails else 0)
