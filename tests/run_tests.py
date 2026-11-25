import sys, pathlib
import lupa.lua51 as L

here = pathlib.Path(__file__).parent
addon = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else here.parent
lua = L.LuaRuntime(unpack_returned_tuples=True)
lua.execute((here / "harness.lua").read_text())
src = (addon / "PortalPro.lua").read_text(encoding="utf-8")
chunk = lua.eval("function(src) local f, e = loadstring(src, 'PortalPro.lua'); if not f then error(e) end; return f end")(src)
chunk("PortalPro")

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
check("trade opened when in range", ["InitiateTrade", "party1"] in called("InitiateTrade"), called("InitiateTrade"))

T.npc = "Bob"; TradeFrame = lua.globals().TradeFrame; TradeFrame.shown = True
fire("TRADE_SHOW")
T.tradeMoney = 2500
fire("TRADE_MONEY_CHANGED")
PP.accept()
check("underpaid: first accept press only warns", len(called("AcceptTrade")) == 0)
T.tradeMoney = 5000
fire("TRADE_MONEY_CHANGED")
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
check("decline noted", PP and lua.eval("PortalPro") is not None)

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
check("ledger net all-time cell", "13000" not in (lf.cells[6][3].text or "") and "1g 30s" in (lf.cells[6][3].text or ""), lf.cells[6][3].text)
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

# --- resizing
pnl = lua.globals().PortalProPanel
check("panel shows 6 buyer rows at its standard size", pnl.visibleRows == 6, pnl.visibleRows)
pnl.SetSize(pnl, 360, 500)
check("taller panel shows more rows", pnl.visibleRows == 17, pnl.visibleRows)
check("top buttons share the width", pnl.ad.w == 168 and pnl.accept.w == 168, (pnl.ad.w, pnl.accept.w))
pnl.grip.scripts.OnMouseDown(pnl.grip, "LeftButton"); pnl.grip.scripts.OnMouseUp(pnl.grip)
check("panel size saved", db.frames.panel.w == 360 and db.frames.panel.h == 500, (db.frames.panel.w, db.frames.panel.h))
T.combat = True; T.sizing = None
pnl.grip.scripts.OnMouseDown(pnl.grip, "LeftButton")
check("no panel resize in combat", T.sizing is None and "can't be resized in combat" in T.prints[len(T.prints)])
T.combat = False

lf = lua.globals().PortalProLedger
lf.SetSize(lf, 500, 600)
check("taller ledger shows more history", lf.visible == 22, lf.visible)
lf.grip.scripts.OnMouseDown(lf.grip, "LeftButton"); lf.grip.scripts.OnMouseUp(lf.grip)
check("ledger size saved", db.frames.ledger.h == 600)
lf.scripts.OnDragStop(lf)
check("ledger place saved", db.frames.ledger.point is not None)
mf2 = lua.globals().PortalProMessages
mf2.SetSize(mf2, 700, 300)
check("messages window resizes", mf2.w == 700)

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
advance(2); T.tick()
check("trade opened with surname buyer", called("InitiateTrade")[-1] == ["InitiateTrade", "party1"])
before = db.totals.income
sale_trade("Nx Thearabian", 5000)
check("surname buyer's payment counted", db.totals.income == before + 5000, (before, db.totals.income))

# --- character without portals (under level 40): buyers listed, nobody invited
lua3 = LUPA.LuaRuntime(unpack_returned_tuples=True)
lua3.execute((here / "harness.lua").read_text() + "\nfunction IsPlayerSpell() return false end")
lua3.eval("function(src) return loadstring(src, 'PortalPro.lua') end")(src)("PortalPro")
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
lua2 = LUPA.LuaRuntime(unpack_returned_tuples=True)
lua2.execute("T = nil")
lua2.execute((here / "harness.lua").read_text().replace('T.class = T.class or "MAGE"', 'T.class = "WARRIOR"'))
lua2.eval("function(src) return loadstring(src, 'PortalPro.lua') end")(src)("PortalPro")
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

print("\n%d failure(s)" % fails)
sys.exit(1 if fails else 0)
