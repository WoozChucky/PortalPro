-- PortalPro - sell mage portals with as little clicking as the game allows.
--
-- What the game lets an addon do, and so what this one does:
--   * read chat (Trade, General, LFG, say, yell, whispers)  -> finds buyers by itself
--   * invite and kick group members                          -> invites buyers, kicks them once through the portal
--   * open a trade with a group member in range              -> opens trade by itself (falls back to a click if the game says no)
--   * read the gold in the trade window                      -> shows PAID / NOT PAID
--   * post in public chat: only from a key press or click    -> "Post ad" button / key; on WoW Forever realms the
--     game refuses any line an addon sends, so the ad goes into the chat box and your Enter sends it
--   * cast a spell: only from a key press or click           -> one Cast button / key that always holds the right portal
--   * accept a trade: only from a key press or click         -> Accept button / key
-- Whisper replies to buyers go out by themselves only on a realm that allows addon chat (the live Forever realms
-- don't, the beta ones did); otherwise the invite is the reply.
-- WoW Forever only.

local ADDON = ...

local PP = {}
_G.PortalPro = PP

local RUNE_OF_PORTALS = 17032

-- Every portal of Classic. words: how players write the city (lower case, whole words).
-- "if" is also an English word, so Ironforge is matched on "to if", "if port" and the like only.
-- Horde first: the order is the ad's and the Cast button's fallback. map: the city's zone map, so the ad and the
-- Cast button skip the city you stand in.
local CITIES = {
  { key = "org",   name = "Orgrimmar",     short = "Org",  map = 1454, spells = { 11417 }, words = { "org", "orgrimmar", "orgri", "orgrimar", "og", "orgi" } },
  { key = "uc",    name = "Undercity",     short = "UC",   map = 1458, spells = { 11418 }, words = { "uc", "undercity", "under city" } },
  { key = "tb",    name = "Thunder Bluff", short = "TB",   map = 1456, spells = { 11420 }, words = { "tb", "thunder bluff", "thunderbluff", "thunder" } },
  { key = "sw",    name = "Stormwind",     short = "SW",   map = 1453, spells = { 10059 }, words = { "sw", "stormwind", "storm wind", "stormw", "storm" } },
  { key = "if",    name = "Ironforge",     short = "IF",   map = 1455, spells = { 11416 }, words = { "ironforge", "iron forge", "ironf" },
    patterns = { "to if%f[%W]", "%f[%w]if port", "port if%f[%W]", "port to if$", "%f[%w]if pls", "%f[%w]if plz", "for if%f[%W]", "^if$" } },
  { key = "darn",  name = "Darnassus",     short = "Darn", map = 1457, spells = { 11419 }, words = { "darn", "darna", "darnassus", "darnasus", "darnas", "darnasuss", "darnassuss" } },
}
local CITY = {}          -- [key] = city
local CITY_BY_SPELL = {} -- [spell id] = city
for _, c in ipairs(CITIES) do
  CITY[c.key] = c
  for _, id in ipairs(c.spells) do CITY_BY_SPELL[id] = c end
end

local DEFAULTS = {
  price = 5000,         -- copper: 50s
  cityPrice = {},       -- [city key] = copper
  adCooldown = 60,      -- seconds between ads
  listen = true,        -- look for buyers in public chat
  inviteAsks = true,    -- invite people who ask in public chat
  autoInvite = true,    -- invite people who whisper "inv", "port", a city
  whisper = true,       -- whisper replies (only where the realm allows addon chat)
  autoTrade = true,     -- open trade with buyers in range
  autoKick = true,      -- kick buyers once they went through the portal
  thanks = true,        -- a line in party chat after every paid trade: who paid what
  sound = true,
  shown = true,
}

local DB
local PANEL_MAX_ROWS = 20  -- buyer rows the panel can show when made tall
local buyers = {}       -- [lower-case short name] = buyer
local myName = ""
local panel, castBtn, rows, toggles = nil, nil, {}, {}
local refresh            -- forward

-- ---------------------------------------------------------------------------------------
-- helpers

local function isSecret(v)
  if type(issecretvalue) ~= "function" then return false end
  local ok, s = pcall(issecretvalue, v)
  return ok and s == true
end

-- a plain value from a call, or nil when it failed or the game hides it
local function safe(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, v = pcall(f, ...)
  if not ok or isSecret(v) then return nil end
  return v
end

local function say(msg) print("|cffb070ffPortalPro|r: " .. msg) end
local function now() return GetTime() end

local function shortName(n)
  if type(n) ~= "string" then return nil end
  return string.match(n, "^([^%-]+)")
end

local function money(c)
  c = math.floor(c or 0)
  local g, s, k = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  local out = {}
  if g > 0 then out[#out + 1] = g .. "g" end
  if s > 0 then out[#out + 1] = s .. "s" end
  if k > 0 or #out == 0 then out[#out + 1] = k .. "c" end
  return table.concat(out, " ")
end

-- {key} in a template -> vals[key]; an unknown {key} stays as written
local function fill(tpl, vals)
  return (string.gsub(tpl, "{(%a+)}", function(k) return vals[k] end))
end

-- "1g50s", "1.5g", "150s", "75c", "2" (gold)
local function parseMoney(s)
  s = string.gsub(string.lower(s or ""), "%s", "")
  if s == "" then return nil end
  if string.match(s, "^%d+%.?%d*$") then return math.floor(tonumber(s) * 10000 + 0.5) end
  local rest = string.gsub(s, "%d+%.?%d*[gsc]", "")
  if rest ~= "" then return nil end
  local total = 0
  for n, u in string.gmatch(s, "(%d+%.?%d*)([gsc])") do
    total = total + tonumber(n) * (u == "g" and 10000 or u == "s" and 100 or 1)
  end
  return math.floor(total + 0.5)
end

local function spellName(id)
  if C_Spell and C_Spell.GetSpellName then
    local n = safe(C_Spell.GetSpellName, id)
    if type(n) == "string" then return n end
  end
  if GetSpellInfo then
    local n = safe(GetSpellInfo, id)
    if type(n) == "string" then return n end
  end
  return nil
end

local function knows(id)
  if safe(IsPlayerSpell, id) == true then return true end
  if safe(IsSpellKnown, id) == true then return true end
  return false
end

-- which portals this character has: city.spell = the known spell id, or nil
local known = {}
local function scanSpells()
  known = {}
  for _, c in ipairs(CITIES) do
    c.spell = nil
    for _, id in ipairs(c.spells) do
      if knows(id) then c.spell = id; break end
    end
    if c.spell then known[#known + 1] = c end
  end
end

-- the capital you stand in, or nil
function PP.hereCity()
  local m = C_Map and C_Map.GetBestMapForUnit and safe(C_Map.GetBestMapForUnit, "player")
  if not m then return nil end
  for _, c in ipairs(CITIES) do if c.map == m then return c end end
  return nil
end

local function runes()
  local f = (C_Item and C_Item.GetItemCount) or GetItemCount
  return safe(f, RUNE_OF_PORTALS) or 0
end

local function priceFor(cityKey)
  return (cityKey and DB.cityPrice[cityKey]) or DB.price
end

local function playSound()
  if not DB.sound then return end
  local id = (SOUNDKIT and SOUNDKIT.READY_CHECK) or 8960
  pcall(PlaySound, id, "Master")
end

-- ---------------------------------------------------------------------------------------
-- reading chat

local function clean(text)
  text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
  text = string.gsub(text, "|r", "")
  text = string.gsub(text, "|H.-|h(.-)|h", "%1")
  text = string.lower(text)
  text = string.gsub(text, "[%c]", " ")
  return text
end

local function wordPattern(w)
  return "%f[%w]" .. string.gsub(w, " ", "%%s*") .. "%f[%W]"
end

-- the first city named in a (cleaned) line: the city table, or nil
local function findCity(lower)
  local best, bestAt
  for _, c in ipairs(CITIES) do
    for _, w in ipairs(c.words) do
      local at = string.find(lower, wordPattern(w))
      if at and (not bestAt or at < bestAt) then best, bestAt = c, at end
    end
    for _, p in ipairs(c.patterns or {}) do
      local at = string.find(lower, p)
      if at and (not bestAt or at < bestAt) then best, bestAt = c, at end
    end
  end
  return best
end

local function has(lower, w) return string.find(lower, wordPattern(w)) ~= nil end
local function hasPort(lower)
  -- port, ports, portal, portals, porting - not report, support, important
  return string.find(lower, "%f[%w]port") ~= nil or has(lower, "teleport") or has(lower, "tele")
end

local BUY_CUES = { "wtb", "lf", "lfm", "need", "needed", "anyone", "any", "anybody", "someone", "looking", "buy", "buying",
  "pls", "plz", "please", "who", "can", "could" }
local SELL_CUES = { "wts", "selling", "sell", "tips", "tip", "whisper me", "w me", "/w", "pst", "msg me", "inv for", "cheap" }

-- A line in public chat: a buyer? Returns true, city (or nil) when it is.
local function channelIntent(lower)
  local port = hasPort(lower)
  local mage = has(lower, "mage") or has(lower, "mages")
  local city = findCity(lower)
  if not port and not (mage and city) then return false end
  if has(lower, "wts") then return false end
  local buy = string.find(lower, "?", 1, true) ~= nil
  for _, w in ipairs(BUY_CUES) do if buy then break end; buy = has(lower, w) end
  if buy then return true, city end
  for _, w in ipairs(SELL_CUES) do
    if string.find(lower, w, 1, true) then return false end
  end
  return true, city   -- "port to darn", "darn port" - nobody sells like that
end

-- A whisper: "buy" (true, city), "price" (a question about the price), or false.
local function whisperIntent(lower)
  local city = findCity(lower)
  -- a short whisper ("inv if", "if pls") with a bare "if" means Ironforge
  if not city and has(lower, "if") then
    local words = 0
    for _ in string.gmatch(lower, "%S+") do words = words + 1 end
    if words <= 3 then city = CITY["if"] end
  end
  if string.find(lower, "%f[%w]inv") or hasPort(lower) or has(lower, "wtb") or city then return true, city end
  if has(lower, "how much") or has(lower, "price") or has(lower, "cost") or has(lower, "costs") then return "price" end
  return false
end

-- ---------------------------------------------------------------------------------------
-- sending chat

-- WoW Forever's live realms refuse every chat line an addon posts (a realm setting the game reports)
local function restricted()
  local f = C_ChatInfo and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted
  return safe(f) == true
end

local function sendDirect(text, kind, target)
  local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
  local ok = pcall(send, text, kind, nil, target)
  return ok
end

-- Lines for the chat box wait here while you are typing something of your own; the tick opens the next one.
PP.boxQueue = {}

local function chatBusy()
  local box
  if ChatFrameUtil and ChatFrameUtil.GetActiveWindow then box = safe(ChatFrameUtil.GetActiveWindow) end
  if type(box) ~= "table" then box = DEFAULT_CHAT_FRAME and rawget(DEFAULT_CHAT_FRAME, "editBox") end
  if type(box) ~= "table" then box = rawget(_G, "ChatFrame1EditBox") end
  if type(box) ~= "table" or type(box.HasFocus) ~= "function" then return false end
  return safe(box.HasFocus, box) == true
end

local function openBox(line)
  local open = (ChatFrameUtil and ChatFrameUtil.OpenChat) or ChatFrame_OpenChat
  if type(open) ~= "function" then say("Type this in chat: " .. line); return end
  PP.boxAt = now()
  -- a frame later: a slash command runs inside the box's own send, which empties the box right after
  C_Timer.After(0, function() pcall(open, line, DEFAULT_CHAT_FRAME) end)
end

local function toBox(line)
  if chatBusy() or #PP.boxQueue > 0 then
    PP.boxQueue[#PP.boxQueue + 1] = line
    return
  end
  openBox(line)
end

-- Party chat. Whether this realm lets an addon talk in party is found out once: the first line goes straight
-- out and must come back as our own party line within 3 s ("direct"); if it doesn't, it and every later one go
-- into the chat box for your Enter ("box"). DB.partyMode keeps the answer.
function PP.partySay(text)
  if DB.partyMode == "box" then toBox("/p " .. text); return end
  if not sendDirect(text, "PARTY") then
    DB.partyMode = "box"
    toBox("/p " .. text)
    return
  end
  if DB.partyMode ~= "direct" then PP.partyCheck = { text = text, at = now() } end
end

function PP.partyEcho(text, sender)
  local c = PP.partyCheck
  if not c or isSecret(text) or isSecret(sender) then return end
  if text == c.text and string.lower(shortName(sender) or "") == string.lower(myName) then
    DB.partyMode, PP.partyCheck = "direct", nil
  end
end

function PP.partyCheckTick()
  local c = PP.partyCheck
  if not c or now() - c.at < 3 then return end
  PP.partyCheck = nil
  DB.partyMode = "box"
  say("This realm doesn't let addons talk in party - thank-yous go into your chat box now; Enter sends them.")
  toBox("/p " .. c.text)
end

local THANKS_DEFAULT = "Thank you {name}! Received {got} for the portal to {city}{tip}."
local THANKS_TOKENS = "{name} Bob   {got} 60s   {city} Undercity   {tip} (incl. 10s tip - much appreciated!)   {price} 50s"

-- the party line after a trade (tpl: a template to try, default your own): a trade that falls short says so instead
local function thanksText(b, got, tip, owed, price, tpl)
  if got < owed then
    return b.name .. ": received " .. money(got) .. " - still " .. money(owed - got) .. " short of the " .. money(price) .. " price."
  end
  return fill(tpl or DB.thanksText or THANKS_DEFAULT, {
    name = b.name, got = money(got), price = money(price),
    city = b.city and CITY[b.city].name or "your city",
    tip = tip > 0 and (" (incl. " .. money(tip) .. " tip - much appreciated!)") or "",
  })
end

local function thanksSample(tpl)
  return thanksText({ name = "Bob", city = "uc" }, DB.price + 1000, 1000, DB.price, DB.price, tpl)
end

local function whisper(b, text)
  if not DB.whisper or restricted() then return false end
  return sendDirect(text, "WHISPER", b.full)
end

-- Trade's channel number (zone channel 2), else General (1); never by name, names are translated
local function adChannel()
  local info = C_ChatInfo and C_ChatInfo.GetChannelInfoFromIdentifier
  local general, trade
  for i = 1, 20 do
    local ok, id, name = pcall(GetChannelName, i)
    if ok and not isSecret(id) and type(id) == "number" and id > 0 and not isSecret(name) and type(name) == "string" then
      local c = type(info) == "function" and safe(info, name) or nil
      local z = type(c) == "table" and not isSecret(c.zoneChannelID) and c.zoneChannelID or nil
      local lname = string.lower(name)
      if z == 2 or (not z and string.find(lname, "^trade")) then trade = trade or { id, name } end
      if z == 1 or (not z and string.find(lname, "^general")) then general = general or { id, name } end
    end
  end
  local pick = trade or general
  if pick then return pick[1], pick[2] end
  return nil
end

-- the portals worth selling here: every known one but the city you stand in
local function sellable()
  local here = PP.hereCity and PP.hereCity()
  local list = {}
  for _, c in ipairs(known) do if c ~= here then list[#list + 1] = c end end
  return list, here
end

local AD_DEFAULT = "WTS Portals {route} - {price} each. Whisper me \"inv\" + the city!"
local AD_TOKENS = "{route} Org -> UC / TB (or: to Org / UC / TB)   {here} Org   {cities} UC / TB   {price} 50s"

-- the ad from a template (default: your own, else AD_DEFAULT)
local function adText(tpl)
  local list, here = sellable()
  local names = {}
  for _, c in ipairs(list) do names[#names + 1] = c.short end
  local cities = #names > 0 and table.concat(names, " / ") or "Org / UC / TB"
  local differ = false
  for _, c in ipairs(list) do if DB.cityPrice[c.key] and DB.cityPrice[c.key] ~= DB.price then differ = true end end
  tpl = tpl or ((DB.ad and DB.ad ~= "") and DB.ad or AD_DEFAULT)
  return fill(tpl, {
    route = here and (here.short .. " -> " .. cities) or ("to " .. cities),
    here = here and here.short or "",
    cities = cities,
    price = (differ and "from " or "") .. money(DB.price),
  })
end

local function adLeft()
  return math.max(0, (DB.adAt or 0) + DB.adCooldown - time())
end

function PP.postAd()
  local left = adLeft()
  if left > 0 then say("Next ad in " .. left .. " s."); return end
  local id, name = adChannel()
  if not id then say("You are not in Trade or General chat here."); return end
  local text = adText()
  if restricted() then
    toBox("/" .. id .. " " .. text)
    say("The ad is in the chat box (" .. name .. ") - press Enter to post it.")
  elseif not sendDirect(text, "CHANNEL", id) then
    say("The ad did not go out.")
    return
  end
  DB.adAt = time()
  if refresh then refresh() end
end

-- ---------------------------------------------------------------------------------------
-- group

local function surnameSeparator()
  local c = Constants and Constants.CharacterNameSeparatorConsts
  local sep = c and c.CHARACTERNAME_SURNAME_SEPARATOR
  if type(sep) == "string" and sep ~= "" then return sep end
  return " "
end

-- Forever names have a surname: "Nx Thearabian". Chat senders carry the whole name, but UnitName gives other
-- units' two parts separately (the player's own comes whole in the first return) - this puts them together.
local function fullName(unit)
  local ok, first, surname = pcall(UnitName, unit)
  if not ok or isSecret(first) or type(first) ~= "string" or first == "" then return nil end
  if not isSecret(surname) and type(surname) == "string" and surname ~= ""
     and not string.find(first, surname, 1, true) then
    return first .. surnameSeparator() .. surname
  end
  return first
end

local function unitFor(name)
  if not name then return nil end
  local lname = string.lower(name)
  local prefix, n = "party", 4
  if IsInRaid and IsInRaid() then prefix, n = "raid", 40 end
  for i = 1, n do
    local unit = prefix .. i
    local un = fullName(unit)
    if un and string.lower(un) == lname then return unit end
  end
  return nil
end

local function members()
  return safe(GetNumGroupMembers) or 0
end

local function isLeader()
  if not (IsInGroup and IsInGroup()) then return true end
  return safe(UnitIsGroupLeader, "player") == true
end

local function pendingInvites()
  local n, t = 0, now()
  for _, b in pairs(buyers) do
    if b.state == "invited" and t - (b.invitedAt or 0) < 60 then n = n + 1 end
  end
  return n
end

local function freeSlots()
  if IsInRaid and IsInRaid() then return 0 end
  return 5 - math.max(1, members()) - pendingInvites()
end

local function inviteName(b) return b.name end   -- Forever: plain names, no realm

local function invite(b)
  if not isLeader() then b.queued = true; return false end
  if freeSlots() <= 0 then
    if not b.queued then say(b.name .. " waits for a free spot in the group.") end
    b.queued = true
    return false
  end
  local f = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
  pcall(f, inviteName(b))
  b.queued, b.state, b.invitedAt = nil, "invited", now()
  return true
end

local function uninvite(b)
  local f = (C_PartyInfo and C_PartyInfo.UninviteUnit) or UninviteUnit
  pcall(f, inviteName(b))
end

-- ---------------------------------------------------------------------------------------
-- ledger: every trade with a buyer, every portal cast (one rune each), every buyer who went through.
-- An entry: { t = time(), k = kind, n = name, c = city key, p = asking price, g = gold, tip, r = rune cost, b = buyers }
--   k = "trade"  - gold a buyer handed over (g), of which tip is above what was still owed
--   k = "cast"   - a portal: one rune at r, b buyers stood at it
--   k = "served" - a buyer went through: asked p, paid g in all (short = p - g when g < p)
-- DB.totals keeps the all-time sums, so trimming old entries loses nothing.

local LEDGER_MAX = 2000
local DEFAULT_RUNE_COST = 2000   -- 20s at the reagent vendor (less with reputation; read from the vendor when you visit one)

local function newTotals()
  return { income = 0, tips = 0, trades = 0, casts = 0, runeCost = 0, served = 0, short = 0, unpaid = 0 }
end

local function addTo(T, e)
  if e.k == "trade" then
    T.income, T.tips, T.trades = T.income + e.g, T.tips + (e.tip or 0), T.trades + 1
  elseif e.k == "cast" then
    T.casts, T.runeCost = T.casts + 1, T.runeCost + e.r
  elseif e.k == "served" then
    T.served = T.served + 1
    if e.g < e.p then
      T.short = T.short + (e.p - e.g)
      if e.g == 0 then T.unpaid = T.unpaid + 1 end
    end
  end
end

local function ledgerAdd(e)
  e.t = e.t or time()
  local L = DB.ledger
  L[#L + 1] = e
  while #L > LEDGER_MAX do table.remove(L, 1) end
  addTo(DB.totals, e)
  if PP.ledgerRefresh then PP.ledgerRefresh() end
end

-- the sums of the entries from `since` on (a time()), or all time
local function ledgerSum(since)
  if not since then return DB.totals end
  local T = newTotals()
  for _, e in ipairs(DB.ledger) do if e.t >= since then addTo(T, e) end end
  return T
end

local function net(T) return T.income - T.runeCost end

-- a buyer paid after going through: their "served" entry gets the gold, and the all-time short with it
local function servedPaidLate(name, got)
  local L = DB.ledger
  for i = #L, 1, -1 do
    local e = L[i]
    if e.k == "served" and e.n == name then
      local T = DB.totals
      if e.g < e.p then
        T.short = T.short - (e.p - e.g)
        if e.g == 0 then T.unpaid = T.unpaid - 1 end
      end
      e.g = e.g + got
      if e.g < e.p then
        T.short = T.short + (e.p - e.g)
        if e.g == 0 then T.unpaid = T.unpaid + 1 end
      end
      return
    end
  end
end

local function dayStart()
  local d = date("*t")
  d.hour, d.min, d.sec = 0, 0, 0
  return time(d)
end

local function markDone(b)
  if b.state == "done" then return end
  b.state, b.doneAt = "done", now()
  local p, g = priceFor(b.city), b.paid or 0
  ledgerAdd({ k = "served", n = b.name, c = b.city, p = p, g = g })
  if g < p then
    say(b.name .. (g == 0 and " went through without paying." or (" went through " .. money(p - g) .. " short.")))
  end
end

-- ---------------------------------------------------------------------------------------
-- buyers

local function buyerFor(sender)
  local name = shortName(sender)
  if not name or name == "" then return nil end
  local key = string.lower(name)
  local b = buyers[key]
  if not b then
    b = { key = key, name = name, full = sender, state = "asked", at = now() }
    buyers[key] = b
    b.new = true
  end
  if sender and string.find(sender, "-", 1, true) then b.full = sender end
  return b
end

local function cityLine(c) return c and c.name or "a city" end

-- someone asked for a portal (src = "whisper", "chat" or "say")
local function request(sender, text, src, where)
  if isSecret(sender) or isSecret(text) or type(sender) ~= "string" or type(text) ~= "string" then return end
  local name = shortName(sender)
  if not name or string.lower(name) == string.lower(myName) then return end
  local lower = clean(text)
  local intent, city
  if src == "whisper" then intent, city = whisperIntent(lower) else intent, city = channelIntent(lower) end
  if not intent then return end

  if intent == "price" then
    local b = buyers[string.lower(name)] or { name = name, full = sender }
    whisper(b, "Portals: " .. money(DB.price) .. " each. Whisper \"inv\" + the city and I'll invite you.")
    return
  end
  -- a city this character has no portal to (or no portals at all yet): listed, greyed, never invited
  local cantPort = (city and not city.spell) or #known == 0
  if cantPort and src == "whisper" then
    whisper({ full = sender }, "Sorry, I can't make a portal to " .. cityLine(city) .. ".")
  end

  local b = buyerFor(sender)
  b.cantPort = cantPort or nil
  local t = now()
  if b.state == "done" and t - (b.doneAt or 0) < 120 then return end
  if b.state == "done" then b.state, b.paid, b.tradeTries = "asked", nil, 0 end
  local cityChanged = city and b.city ~= city.key
  if city then b.city = city.key end
  b.at, b.src, b.where = t, src, where

  if b.new then
    b.new = nil
    playSound()
    say((cantPort and "|cff808080Buyer|r " or "|cff40ff40Buyer|r ") .. name .. " - " .. cityLine(city) .. " (" .. (where or src) .. ")"
      .. (cantPort and " - |cff808080you have no portal there, not invited.|r" or "."))
  end
  if cantPort then
    if refresh then refresh() end
    return
  end

  local wantInvite = (src == "whisper" and DB.autoInvite) or (src ~= "whisper" and DB.inviteAsks)
  local declinedLately = b.declinedAt and t - b.declinedAt < 300 and src ~= "whisper"
  local inGroup = unitFor(b.name) ~= nil
  local invitedNow = false
  if wantInvite and not inGroup and not declinedLately
     and (b.state ~= "invited" or t - (b.invitedAt or 0) > 30) then
    invitedNow = invite(b)
  end

  if (invitedNow or cityChanged) and not b.replied then
    local price = money(priceFor(b.city))
    local line
    if city then
      line = "Portal to " .. city.name .. ": " .. price .. "." .. (invitedNow and " Invite sent - join and I'll open trade." or "")
    else
      line = "Portals " .. price .. "." .. (invitedNow and " Invite sent - tell me the city!" or " Which city?")
    end
    if whisper(b, line) then b.replied = true end
  end
  if refresh then refresh() end
end

-- ---------------------------------------------------------------------------------------
-- the cast button: always the portal the group needs

local function planCity()
  if PP.manualAt and now() - PP.manualAt < 20 and DB.manualCity and CITY[DB.manualCity] and CITY[DB.manualCity].spell then
    return CITY[DB.manualCity], 0
  end
  local score, count = {}, {}
  for _, b in pairs(buyers) do
    if b.unit and b.city and (b.state == "group" or b.state == "paid") and CITY[b.city].spell then
      score[b.city] = (score[b.city] or 0) + (b.state == "paid" and 100 or 1)
      count[b.city] = (count[b.city] or 0) + 1
    end
  end
  local best
  for k, s in pairs(score) do if not best or s > score[best] then best = k end end
  if best then return CITY[best], count[best] end
  if DB.manualCity and CITY[DB.manualCity] and CITY[DB.manualCity].spell then return CITY[DB.manualCity], 0 end
  local list = sellable()
  return list[1] or known[1], 0
end

local function updateCast()
  if not castBtn then return end
  if InCombatLockdown() then PP.castDirty = true; return end
  PP.castDirty = nil
  local c, n = planCity()
  local spell = c and spellName(c.spell)
  castBtn:SetAttribute("type", "spell")
  castBtn:SetAttribute("spell", spell)
  if spell then
    castBtn:SetText(spell .. (n and n > 0 and ("  (" .. n .. ")") or ""))
    castBtn:Enable()
  else
    castBtn:SetText(#known == 0 and "No portals yet (level 40+)" or "No portal spells known")
  end
  PP.castCity = c
end

local function cycleCity(step)
  if #known == 0 then return end
  local cur = PP.castCity
  local idx = 1
  for i, c in ipairs(known) do if c == cur then idx = i end end
  idx = (idx - 1 + step) % #known + 1
  DB.manualCity, PP.manualAt = known[idx].key, now()
  updateCast()
end

-- ---------------------------------------------------------------------------------------
-- trade

local overlay
local function partnerName()
  local n = fullName("NPC")
  if n then return n end
  local fs = _G.TradeFrameRecipientNameText
  if fs and fs.GetText then
    n = safe(fs.GetText, fs)
    if type(n) == "string" then return n end
  end
  return nil
end

local function targetMoney()
  return safe(GetTargetTradeMoney) or 0
end

local function tradeBuyer()
  local t = PP.trade
  return t and t.name and buyers[string.lower(t.name)] or nil
end

local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t"
local CROSS = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14|t"

local function updateOverlay()
  if not overlay then
    local tf = _G.TradeFrame
    if not tf then return end
    overlay = tf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    overlay:SetPoint("BOTTOM", tf, "TOP", 0, 4)
  end
  local t = PP.trade
  if not t then overlay:SetText(""); return end
  local b = tradeBuyer()
  local want = priceFor(b and b.city)
  local got = t.money or 0
  local who = (t.name or "?") .. (b and b.city and (" -> " .. CITY[b.city].name) or "")
  if want <= 0 then
    overlay:SetText("|cffb070ffPortalPro|r  " .. who .. "  tip: " .. money(got))
  elseif got >= want then
    overlay:SetText("|cffb070ffPortalPro|r  " .. who .. "  " .. CHECK .. " |cff40ff40PAID " .. money(got) .. "|r")
  else
    overlay:SetText("|cffb070ffPortalPro|r  " .. who .. "  " .. CROSS .. " |cffff4040" .. money(got) .. " of " .. money(want) .. "|r")
  end
end

local function tradeDone()
  local t = PP.trade or PP.lastTrade
  if not t or t.counted then return end
  t.counted = true
  local got = t.money or 0
  if got <= 0 then return end
  -- only buyers count: a trade with someone who is neither on the list nor in the group is not a portal sale
  local b = t.name and buyers[string.lower(t.name)]
  if not b and t.name and unitFor(t.name) then
    b = buyerFor(t.name); b.new = nil; b.state = "group"; b.unit = unitFor(t.name)
  end
  if not b then return end
  local price, before = priceFor(b.city), b.paid or 0
  local owed = math.max(0, price - before)
  local tip = math.max(0, got - owed)
  b.paid = before + got
  if b.state == "done" then servedPaidLate(b.name, got) else b.state = "paid" end
  ledgerAdd({ k = "trade", n = b.name, c = b.city, p = price, g = got, tip = tip })
  if DB.thanks and unitFor(b.name) then PP.partySay(thanksText(b, got, tip, owed, price)) end
  say("|cff40ff40+" .. money(got) .. "|r from " .. b.name .. (tip > 0 and (" (" .. money(tip) .. " tip)") or "")
    .. (got < owed and (" - |cffff4040" .. money(owed - got) .. " short|r") or "")
    .. (b.city and b.state ~= "done" and (" - cast " .. CITY[b.city].name .. "!") or "."))
  updateCast()
  if refresh then refresh() end
end

function PP.accept()
  local tf = _G.TradeFrame
  if not (tf and tf:IsShown()) then return end
  local b = tradeBuyer()
  local want, got = priceFor(b and b.city), PP.trade and PP.trade.money or 0
  if want > 0 and got < want and not (PP.acceptArmed and now() - PP.acceptArmed < 3) then
    PP.acceptArmed = now()
    say("Only " .. money(got) .. " of " .. money(want) .. " in the trade - press again to accept anyway.")
    return
  end
  PP.acceptArmed = nil
  pcall(AcceptTrade)
end

local function openTrade(b)
  if not b.unit then return end
  local ok = pcall(InitiateTrade, b.unit)
  b.tradeTry, b.tradeTries = now(), (b.tradeTries or 0) + 1
  return ok
end

-- ---------------------------------------------------------------------------------------
-- the half-second tick: open trades, watch the portal, invite the queue, tidy the list

local function visible(unit)
  local v = safe(UnitIsVisible, unit)
  return v == true
end

local function mapOf(unit)
  return C_Map and C_Map.GetBestMapForUnit and safe(C_Map.GetBestMapForUnit, unit) or nil
end

local function tick()
  if not DB then return end
  local t = now()

  -- open trade with a buyer who joined, is near and has not paid
  local tf = _G.TradeFrame
  if DB.autoTrade and not PP.tradeBlocked and not PP.trade and not (tf and tf:IsShown()) and not InCombatLockdown() then
    for _, b in pairs(buyers) do
      if b.unit and b.state == "group" and priceFor(b.city) > 0 and (b.tradeTries or 0) < 3
         and t - (b.tradeTry or 0) > 8 and t - (b.joinedAt or t) > 1.5 then
        local near = safe(CheckInteractDistance, b.unit, 2)
        if near then openTrade(b); break end
      end
    end
  end

  -- after a portal: buyers who were near and are gone took it
  if PP.portalAt and t - PP.portalAt < 90 then
    local myMap = mapOf("player")
    for _, b in pairs(buyers) do
      if b.unit and b.nearAtCast and (b.state == "group" or b.state == "paid") then
        local m = mapOf(b.unit)
        local gone = not visible(b.unit) or (m and myMap and m ~= myMap)
        if gone and not b.kickAt then b.kickAt = t + 1 end
        if b.kickAt and t >= b.kickAt then
          if not b.city then b.city = PP.portalCity end
          markDone(b)
          if DB.autoKick then uninvite(b) end
        end
      end
    end
  end

  -- invite whoever waits for a spot
  if freeSlots() > 0 and isLeader() then
    for _, b in pairs(buyers) do
      if b.queued and freeSlots() > 0 then invite(b) end
    end
  end

  -- drop old lines: asked and never came (5 min), invited and never joined (2 min), done (2 min)
  for key, b in pairs(buyers) do
    if not b.unit then
      if (b.state == "done" and t - (b.doneAt or 0) > 120)
         or (b.state == "invited" and t - (b.invitedAt or 0) > 120)
         or ((b.state == "asked" or b.state == "left" or b.state == "busy" or b.state == "declined") and t - b.at > 300) then
        buyers[key] = nil
      end
    end
  end

  -- party chat: did the addon's line come back? the next line waiting for the chat box
  PP.partyCheckTick()
  if #PP.boxQueue > 0 and t - (PP.boxAt or 0) > 1 and not chatBusy() then
    openBox(table.remove(PP.boxQueue, 1))
  end

  if PP.castDirty and not InCombatLockdown() then updateCast() end
  if refresh then refresh() end
end

-- ---------------------------------------------------------------------------------------
-- the panel

local STATE_TEXT = {
  asked = "|cffffd200asked|r", invited = "|cff7fd4ffinvited|r", group = "|cffffffffin group|r",
  paid = "|cff40ff40PAID|r", done = "|cff808080ported|r", left = "|cff808080left|r",
  busy = "|cffff8040in a group|r", declined = "|cffff4040declined|r",
}
local STATE_ORDER = { paid = 1, group = 2, invited = 3, asked = 4, busy = 5, declined = 6, left = 7, done = 8 }

local function sortedBuyers()
  local list = {}
  for _, b in pairs(buyers) do list[#list + 1] = b end
  table.sort(list, function(a, b)
    local oa, ob = STATE_ORDER[a.state] or 9, STATE_ORDER[b.state] or 9
    if oa ~= ob then return oa < ob end
    return a.at > b.at
  end)
  return list
end

local function onOff(v) return v and "|cff40ff40ON|r" or "|cff808080OFF|r" end

local function savePoint()
  local p, _, rp, x, y = panel:GetPoint()
  DB.point = { p, rp, x, y }
end

local function button(parent, w, h, text, template)
  local b = CreateFrame("Button", nil, parent, template or "UIPanelButtonTemplate")
  b:SetSize(w, h)
  b:SetText(text)
  return b
end

-- A window you can resize by the grip in its bottom-right corner, between min and max. The size (and, for the
-- windows that ask for it, the place) is kept in DB.frames[key]. onSize(w, h) lays the contents out again.
-- secure: the window holds a secure button, so the game forbids resizing it in combat.
local function makeResizable(frame, key, minW, minH, maxW, maxH, onSize, secure)
  DB.frames = DB.frames or {}
  frame:SetResizable(true)
  if frame.SetResizeBounds then
    frame:SetResizeBounds(minW, minH, maxW, maxH)
  else
    if frame.SetMinResize then frame:SetMinResize(minW, minH) end
    if frame.SetMaxResize then frame:SetMaxResize(maxW, maxH) end
  end

  local saved = DB.frames[key]
  if saved and saved.w and saved.h then
    frame:SetSize(math.max(minW, math.min(maxW, saved.w)), math.max(minH, math.min(maxH, saved.h)))
  end

  local grip = CreateFrame("Button", nil, frame)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -3, 3)
  grip:SetFrameLevel(frame:GetFrameLevel() + 10)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function(_, mouse)
    if mouse ~= "LeftButton" then return end
    if secure and InCombatLockdown() then say("The panel can't be resized in combat."); return end
    frame.sizing = true
    frame:StartSizing("BOTTOMRIGHT")
  end)
  grip:SetScript("OnMouseUp", function()
    if not frame.sizing then return end
    frame.sizing = nil
    frame:StopMovingOrSizing()
    local w, h = frame:GetSize()
    DB.frames[key] = DB.frames[key] or {}
    DB.frames[key].w, DB.frames[key].h = math.floor(w + 0.5), math.floor(h + 0.5)
  end)
  frame.grip = grip

  frame:SetScript("OnSizeChanged", function(_, w, h) onSize(w, h) end)
  onSize(frame:GetSize())
end

-- where a window was left (the panel has its own DB.point)
local function keepPlace(frame, key, default)
  DB.frames = DB.frames or {}
  local p = DB.frames[key] and DB.frames[key].point
  frame:ClearAllPoints()
  if p then frame:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else frame:SetPoint(unpack(default)) end
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local a, _, rp, x, y = self:GetPoint()
    DB.frames[key] = DB.frames[key] or {}
    DB.frames[key].point = { a, rp, x, y }
  end)
end

-- ---------------------------------------------------------------------------------------
-- the ledger window

local ledgerFrame
local LEDGER_MAX_ROWS = 50   -- history rows the ledger can show when made tall
local SUM_ROWS = {
  { "Income",          function(T) return money(T.income) end },
  { "  of it tips",    function(T) return "|cff40ff40" .. money(T.tips) .. "|r" end },
  { "Short / unpaid",  function(T) return T.short > 0 and ("|cffff4040" .. money(T.short) .. "|r" .. (T.unpaid > 0 and (" (" .. T.unpaid .. ")") or "")) or "-" end },
  { "Portals (runes)", function(T) return tostring(T.casts) end },
  { "Rune cost",       function(T) return T.runeCost > 0 and ("|cffff8040-" .. money(T.runeCost) .. "|r") or "-" end },
  { "Net profit",      function(T) local n = net(T); return (n < 0 and "|cffff4040-" or "|cff40ff40") .. money(math.abs(n)) .. "|r" end },
  { "Buyers through",  function(T) return tostring(T.served) end },
  { "Net per portal",  function(T) if T.casts == 0 then return "-" end; local n = math.floor(net(T) / T.casts); return (n < 0 and "-" or "") .. money(math.abs(n)) end },
}

local function cityShort(k) return k and CITY[k] and CITY[k].short or "?" end

local function entryText(e)
  local txt
  if e.k == "trade" then
    txt = (e.n or "?") .. " paid |cffffffff" .. money(e.g) .. "|r for " .. cityShort(e.c)
      .. ((e.tip or 0) > 0 and (" |cff40ff40(+" .. money(e.tip) .. " tip)|r") or "")
  elseif e.k == "cast" then
    txt = "Portal " .. cityShort(e.c) .. " - rune |cffff8040-" .. money(e.r) .. "|r"
      .. ((e.b or 0) > 0 and ("  |cffa0a0a0" .. e.b .. " at it|r") or "")
  elseif e.k == "served" then
    if e.g >= e.p then
      txt = "|cff808080" .. (e.n or "?") .. " through to " .. cityShort(e.c) .. "|r"
    elseif e.g == 0 then
      txt = (e.n or "?") .. " through to " .. cityShort(e.c) .. " |cffff4040unpaid (" .. money(e.p) .. ")|r"
    else
      txt = (e.n or "?") .. " through to " .. cityShort(e.c) .. " |cffff4040" .. money(e.p - e.g) .. " short|r"
    end
  else
    txt = tostring(e.k)
  end
  return "|cffa0a0a0" .. date("%m-%d %H:%M", e.t) .. "|r  " .. txt
end

function PP.ledgerRefresh()
  local lf = ledgerFrame
  if not lf or not lf:IsShown() then return end
  local sums = { ledgerSum(dayStart()), ledgerSum(time() - 7 * 86400), ledgerSum(nil) }
  for r, def in ipairs(SUM_ROWS) do
    for c = 1, 3 do lf.cells[r][c]:SetText(def[2](sums[c])) end
  end
  lf.rune:SetText("Rune of Portals: |cffffffff" .. money(DB.runeCost) .. "|r each  |cff808080(read at the vendor - /pp runecost 18s to set)|r")
  local L = DB.ledger
  local shown = lf.visible or 12
  lf.offset = math.max(0, math.min(lf.offset or 0, #L - shown))
  for i = 1, LEDGER_MAX_ROWS do
    local e = i <= shown and L[#L - lf.offset - i + 1] or nil
    lf.rows[i]:SetText(e and entryText(e) or "")
  end
  lf.empty:SetText(#L == 0 and "Nothing yet - trades, portals and buyers land here." or "")
end

local function buildLedger()
  local lf = CreateFrame("Frame", "PortalProLedger", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  ledgerFrame = lf
  lf:SetSize(430, 430)
  lf:SetFrameStrata("DIALOG")
  if lf.SetBackdrop then
    lf:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 14,
      insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    lf:SetBackdropColor(0, 0, 0, 0.92)
  end
  lf:SetMovable(true)
  lf:SetClampedToScreen(true)
  lf:EnableMouse(true)
  lf:RegisterForDrag("LeftButton")
  lf:SetScript("OnDragStart", lf.StartMoving)
  keepPlace(lf, "ledger", { "CENTER" })
  lf:Hide()
  tinsert(UISpecialFrames, "PortalProLedger")   -- Escape closes it

  local title = lf:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 12, -10)
  title:SetText("|cffb070ffPortalPro|r ledger")
  local close = CreateFrame("Button", nil, lf, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 0, 0)

  local reset = button(lf, 60, 18, "Reset")
  reset:SetPoint("RIGHT", close, "LEFT", -2, 0)
  reset:SetScript("OnClick", function() StaticPopup_Show("PORTALPRO_RESET_LEDGER") end)
  reset:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Delete the whole ledger (asks first).", 1, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  reset:SetScript("OnLeave", function() GameTooltip:Hide() end)

  local cols = { "Today", "7 days", "All time" }
  for c, name in ipairs(cols) do
    local h = lf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h:SetPoint("TOPRIGHT", lf, "TOPRIGHT", -14 - (3 - c) * 80, -38)
    h:SetText(name)
  end
  lf.cells = {}
  for r, def in ipairs(SUM_ROWS) do
    local y = -54 - (r - 1) * 16
    local label = lf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", 14, y)
    label:SetText(def[1])
    lf.cells[r] = {}
    for c = 1, 3 do
      local fs = lf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      fs:SetPoint("TOPRIGHT", lf, "TOPRIGHT", -14 - (3 - c) * 80, y)
      fs:SetJustifyH("RIGHT")
      lf.cells[r][c] = fs
    end
  end

  lf.rune = lf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  lf.rune:SetPoint("TOPLEFT", 14, -54 - #SUM_ROWS * 16 - 6)

  local head = lf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  head:SetPoint("TOPLEFT", 14, -54 - #SUM_ROWS * 16 - 28)
  head:SetText("HISTORY  |cff808080newest first - scroll for more|r")

  lf.rows = {}
  for i = 1, LEDGER_MAX_ROWS do
    local fs = lf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", 14, -54 - #SUM_ROWS * 16 - 44 - (i - 1) * 16)
    fs:SetPoint("RIGHT", -14, 0)
    fs:SetJustifyH("LEFT")
    lf.rows[i] = fs
  end
  lf.empty = lf:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  lf.empty:SetPoint("TOPLEFT", lf.rows[1], "TOPLEFT")

  lf:EnableMouseWheel(true)
  lf:SetScript("OnMouseWheel", function(self, delta)
    self.offset = (self.offset or 0) - delta * 3
    PP.ledgerRefresh()
  end)
  lf:SetScript("OnShow", function(self) self.offset = 0; PP.ledgerRefresh() end)

  local top = 54 + #SUM_ROWS * 16 + 44
  makeResizable(lf, "ledger", 430, 330, 1000, 1000, function(_, h)
    lf.visible = math.max(1, math.min(LEDGER_MAX_ROWS, math.floor((h - top - 22) / 16)))
    PP.ledgerRefresh()
  end)
end

function PP.resetLedger()
  DB.ledger, DB.totals = {}, newTotals()
  say("Ledger cleared.")
  PP.ledgerRefresh()
  if refresh then refresh() end
end

StaticPopupDialogs.PORTALPRO_RESET_LEDGER = {
  text = "Delete the whole PortalPro ledger?\nThis cannot be undone.",
  button1 = YES or "Yes",
  button2 = NO or "No",
  OnAccept = function() PP.resetLedger() end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

function PP.toggleLedger()
  if not ledgerFrame then return end
  if ledgerFrame:IsShown() then ledgerFrame:Hide() else ledgerFrame:Show() end
end

-- ---------------------------------------------------------------------------------------
-- the messages window: the ad and the party thank-you, edited in place.
-- Enter or clicking away saves, Escape puts back what was saved, Default goes back to the standard text.

local msgFrame
local MSG_WIDTH = 480

local function setChecked(cb, v) if cb.SetChecked then cb:SetChecked(v and true or false) end end

-- one editor: label, Default button, the box, a live preview and the tokens it knows
local function addEditor(parent, y, def)
  local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("TOPLEFT", 14, y)
  label:SetText(def.label)

  local reset = button(parent, 70, 20, "Default")
  reset:SetPoint("TOPRIGHT", -14, y + 3)

  local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  eb:SetHeight(20)
  eb:SetPoint("TOPLEFT", 22, y - 18)
  eb:SetPoint("RIGHT", parent, "RIGHT", -18, 0)
  eb:SetAutoFocus(false)
  eb:SetMaxLetters(255)

  local pv = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  pv:SetPoint("TOPLEFT", 16, y - 42)
  pv:SetPoint("RIGHT", parent, "RIGHT", -16, 0)
  pv:SetJustifyH("LEFT")

  local tk = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  tk:SetPoint("TOPLEFT", 16, y - 70)
  tk:SetPoint("RIGHT", parent, "RIGHT", -16, 0)
  tk:SetJustifyH("LEFT")
  tk:SetText(def.tokens)

  local ed = { eb = eb, pv = pv }
  function ed.update()
    local raw = eb:GetText()
    local text = def.preview(type(raw) == "string" and raw or "")
    local over = string.len(text) > 255
    pv:SetText("|cff808080Preview:|r " .. text
      .. (over and ("  |cffff4040too long for chat: " .. string.len(text) .. " / 255|r") or ""))
  end
  function ed.load()
    eb:SetText(def.get() or def.default)
    if eb.SetCursorPosition then eb:SetCursorPosition(0) end
    ed.update()
  end
  function ed.save()
    local t = strtrim(eb:GetText() or "")
    local new = t
    if t == "" or t == def.default then new = nil end
    if new ~= def.get() then
      def.set(new)
      say(def.label .. (new and " saved." or " back to the standard text."))
    end
    ed.load()
  end
  eb:SetScript("OnTextChanged", function() ed.update() end)
  eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)          -- losing focus saves
  eb:SetScript("OnEditFocusLost", function() ed.save() end)
  eb:SetScript("OnEscapePressed", function(self) ed.load(); self:ClearFocus() end)
  reset:SetScript("OnClick", function() eb:SetText(def.default); ed.save() end)
  return ed
end

local function buildMessages()
  local mf = CreateFrame("Frame", "PortalProMessages", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  msgFrame = mf
  mf:SetSize(MSG_WIDTH, 250)
  mf:SetFrameStrata("DIALOG")
  if mf.SetBackdrop then
    mf:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 14,
      insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    mf:SetBackdropColor(0, 0, 0, 0.92)
  end
  mf:SetMovable(true)
  mf:SetClampedToScreen(true)
  mf:EnableMouse(true)
  mf:RegisterForDrag("LeftButton")
  mf:SetScript("OnDragStart", mf.StartMoving)
  keepPlace(mf, "messages", { "CENTER", UIParent, "CENTER", 0, 120 })
  mf:Hide()
  tinsert(UISpecialFrames, "PortalProMessages")

  local title = mf:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 12, -10)
  title:SetText("|cffb070ffPortalPro|r messages")
  local close = CreateFrame("Button", nil, mf, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 0, 0)
  local hint = mf:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("TOPRIGHT", -36, -16)
  hint:SetText("Enter saves - Escape undoes")

  mf.ad = addEditor(mf, -44, {
    label = "Trade ad", default = AD_DEFAULT, tokens = AD_TOKENS,
    get = function() return (DB.ad and DB.ad ~= "") and DB.ad or nil end,
    set = function(v) DB.ad = v end,
    preview = function(t) return adText(t ~= "" and t or AD_DEFAULT) end,
  })

  mf.thanks = addEditor(mf, -140, {
    label = "Party thank-you", default = THANKS_DEFAULT, tokens = THANKS_TOKENS
      .. "\n|cff808080A trade that falls short always says how much is missing instead.|r",
    get = function() return DB.thanksText end,
    set = function(v) DB.thanksText = v end,
    preview = function(t) return thanksSample(t ~= "" and t or THANKS_DEFAULT) end,
  })

  local cb = CreateFrame("CheckButton", nil, mf, "UICheckButtonTemplate")
  cb:SetSize(22, 22)
  cb:SetPoint("TOPLEFT", 140, -136)
  local cbText = mf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  cbText:SetPoint("LEFT", cb, "RIGHT", 2, 0)
  cbText:SetText("post it in party after every paid trade")
  cb:SetScript("OnClick", function(self)
    DB.thanks = self:GetChecked() and true or false
  end)
  mf.thanksCheck = cb

  makeResizable(mf, "messages", MSG_WIDTH, 250, 1000, 400, function()
    mf.ad.update(); mf.thanks.update()
  end)

  mf:SetScript("OnShow", function(self)
    self.ad.load(); self.thanks.load()
    setChecked(self.thanksCheck, DB.thanks)
  end)
end

function PP.toggleMessages()
  if not msgFrame then return end
  if msgFrame:IsShown() then msgFrame:Hide() else msgFrame:Show() end
end

-- the vendor's price for Rune of Portals (reputation discounts included)
local function readRuneCost()
  local n = safe(GetMerchantNumItems) or 0
  for i = 1, n do
    local link = safe(GetMerchantItemLink, i)
    local id = type(link) == "string" and tonumber(string.match(link, "item:(%d+)"))
    if id == RUNE_OF_PORTALS then
      local ok, _, _, price, quantity = pcall(GetMerchantItemInfo, i)
      if ok and type(price) == "number" and not isSecret(price) and price > 0 then
        local each = math.floor(price / math.max(1, (type(quantity) == "number" and not isSecret(quantity)) and quantity or 1) + 0.5)
        if each ~= DB.runeCost then
          DB.runeCost = each
          say("Rune of Portals costs " .. money(each) .. " here - the ledger counts that from now on.")
          PP.ledgerRefresh()
        end
      end
      return
    end
  end
end

local function buildPanel()
  panel = CreateFrame("Frame", "PortalProPanel", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  panel:SetSize(300, 290)
  panel:SetFrameStrata("MEDIUM")
  if panel.SetBackdrop then
    panel:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 14,
      insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    panel:SetBackdropColor(0, 0, 0, 0.85)
  end
  if DB.point then
    panel:SetPoint(DB.point[1], UIParent, DB.point[2], DB.point[3], DB.point[4])
  else
    panel:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
  end
  panel:SetMovable(true)
  panel:SetClampedToScreen(true)
  panel:EnableMouse(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", function(self) if not InCombatLockdown() then self:StartMoving() end end)
  panel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePoint() end)

  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 12, -10)
  title:SetText("|cffb070ffPortalPro|r")

  local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 0, 0)
  close:SetScript("OnClick", function() PP.togglePanel(false) end)

  local ledgerB = button(panel, 60, 18, "Ledger")
  ledgerB:SetPoint("RIGHT", close, "LEFT", -2, 0)
  ledgerB:SetScript("OnClick", function() PP.toggleLedger() end)

  local msgB = button(panel, 72, 18, "Messages")
  msgB:SetPoint("RIGHT", ledgerB, "LEFT", -2, 0)
  msgB:SetScript("OnClick", function() PP.toggleMessages() end)

  panel.info = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.info:SetPoint("TOPLEFT", 12, -32)
  panel.info:SetPoint("RIGHT", -12, 0)
  panel.info:SetJustifyH("LEFT")

  panel.ad = button(panel, 136, 22, "Post ad")
  panel.ad:SetPoint("TOPLEFT", 10, -50)
  panel.ad:SetScript("OnClick", function() PP.postAd() end)

  panel.accept = button(panel, 136, 22, "Accept trade")
  panel.accept:SetPoint("TOPRIGHT", -10, -50)
  panel.accept:SetScript("OnClick", function() PP.accept() end)

  local prev = button(panel, 24, 28, "<")
  prev:SetPoint("TOPLEFT", 10, -78)
  prev:SetScript("OnClick", function() cycleCity(-1) end)
  local nextB = button(panel, 24, 28, ">")
  nextB:SetPoint("TOPRIGHT", -10, -78)
  nextB:SetScript("OnClick", function() cycleCity(1) end)

  -- the one secure button: casting a spell needs the player's own click or key
  castBtn = CreateFrame("Button", "PortalProCastButton", panel, "UIPanelButtonTemplate,SecureActionButtonTemplate")
  castBtn:SetPoint("TOPLEFT", prev, "TOPRIGHT", 2, 0)
  castBtn:SetPoint("BOTTOMRIGHT", nextB, "BOTTOMLEFT", -2, 0)
  local down = safe(GetCVarBool, "ActionButtonUseKeyDown")
  castBtn:RegisterForClicks(down and "AnyDown" or "AnyUp")
  castBtn:SetAttribute("type", "spell")

  panel.status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.status:SetPoint("TOPLEFT", 12, -112)
  panel.status:SetPoint("RIGHT", -12, 0)
  panel.status:SetJustifyH("LEFT")

  local head = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  head:SetPoint("TOPLEFT", 12, -130)
  head:SetText("BUYERS  |cff808080click: invite / trade - right-click: remove|r")

  for i = 1, PANEL_MAX_ROWS do
    local r = CreateFrame("Button", nil, panel)
    r:SetHeight(18)
    r:SetPoint("TOPLEFT", 12, -146 - (i - 1) * 18)
    r:SetPoint("RIGHT", -12, 0)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    r.left = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.left:SetPoint("LEFT", 2, 0)
    r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.right:SetPoint("RIGHT", -2, 0)
    r:SetScript("OnClick", function(self, mouse)
      local b = self.buyer
      if not b then return end
      if mouse == "RightButton" then
        buyers[b.key] = nil
      elseif b.unit then
        if b.state ~= "paid" and b.state ~= "done" then openTrade(b) end
      else
        b.declinedAt = nil
        invite(b)
      end
      refresh()
    end)
    rows[i] = r
  end

  local defs = {
    { "listen", "Listen" }, { "inviteAsks", "Invite" }, { "autoTrade", "Trade" }, { "autoKick", "Kick" },
  }
  for i, d in ipairs(defs) do
    local t = button(panel, 68, 20, d[2])
    t:SetPoint("BOTTOMLEFT", 10 + (i - 1) * 70, 10)
    t.key, t.label = d[1], d[2]
    t:SetScript("OnClick", function(self)
      DB[self.key] = not DB[self.key]
      if self.key == "autoTrade" then PP.tradeBlocked = nil end
      refresh()
    end)
    t:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      local tips = {
        listen = "Look for buyers in Trade, General, LFG, say and yell.",
        inviteAsks = "Invite people who ask for a portal in public chat (whispers are always invited).",
        autoTrade = "Open trade with buyers in the group who are in range and have not paid.",
        autoKick = "Kick buyers from the group once they went through the portal.",
      }
      GameTooltip:SetText(tips[self.key], 1, 1, 1, 1, true)
      GameTooltip:Show()
    end)
    t:SetScript("OnLeave", function() GameTooltip:Hide() end)
    toggles[i] = t
  end

  -- resizing: the two top buttons and the four switches share the width, the buyer list gets the height
  makeResizable(panel, "panel", 300, 290, 700, 800, function(w, h)
    local half = math.floor((w - 24) / 2)
    panel.ad:SetWidth(half)
    panel.accept:SetWidth(half)
    local tw = math.floor((w - 20 - 20 - 3 * 2) / #toggles)
    for i, t in ipairs(toggles) do
      t:SetWidth(tw)
      t:ClearAllPoints()
      t:SetPoint("BOTTOMLEFT", 10 + (i - 1) * (tw + 2), 10)
    end
    panel.visibleRows = math.max(1, math.min(PANEL_MAX_ROWS, math.floor((h - 146 - 36) / 18)))
    if refresh then refresh() end
  end, true)

  if not DB.shown then panel:Hide() end
end

refresh = function()
  if not panel or not panel:IsShown() then return end
  local today = net(ledgerSum(dayStart()))
  local r = runes()
  panel.info:SetText(string.format("Runes: %s   Today net: %s   Price: %s",
    r < 5 and ("|cffff4040" .. r .. "|r") or tostring(r),
    (today < 0 and "|cffff4040-" or "|cff40ff40") .. money(math.abs(today)) .. "|r", money(DB.price)))

  local left = adLeft()
  panel.ad:SetText(left > 0 and string.format("Post ad (%d:%02d)", math.floor(left / 60), left % 60) or "Post ad")

  local tf = _G.TradeFrame
  if tf and tf:IsShown() then panel.accept:Enable() else panel.accept:Disable() end

  local status
  if PP.trade then
    local b = tradeBuyer()
    local want, got = priceFor(b and b.city), PP.trade.money or 0
    status = "Trade with " .. (PP.trade.name or "?") .. ": "
      .. ((want <= 0 or got >= want) and ("|cff40ff40" .. money(got) .. " - accept|r") or ("|cffff4040" .. money(got) .. " of " .. money(want) .. "|r"))
  elseif PP.portalAt and now() - PP.portalAt < 60 then
    status = "Portal to " .. (PP.portalCity and CITY[PP.portalCity].name or "?") .. " is up - " .. (60 - math.floor(now() - PP.portalAt)) .. " s left."
  elseif restricted() then
    status = "|cff808080This realm blocks addon chat: ads go into the chat box, Enter sends.|r"
  else
    status = ""
  end
  panel.status:SetText(status)

  local list = sortedBuyers()
  for i, row in ipairs(rows) do
    local b = i <= (panel.visibleRows or 6) and list[i] or nil
    row.buyer = b
    if b then
      row.left:SetText(b.name .. "  |cffa0a0a0" .. (b.city and CITY[b.city].name or "?") .. "|r")
      row.right:SetText(b.cantPort and "|cff808080no portal|r"
        or ((STATE_TEXT[b.state] or b.state) .. (b.queued and " |cffa0a0a0(waits)|r" or "")))
      row:Show()
    else
      row:Hide()
    end
  end

  for _, t in ipairs(toggles) do t:SetText(t.label .. " " .. onOff(DB[t.key])) end
end

function PP.togglePanel(show)
  if not panel then return end
  if InCombatLockdown() then say("The panel can't be shown or hidden in combat."); return end
  if show == nil then show = not panel:IsShown() end
  if show then panel:Show() else panel:Hide() end
  DB.shown = show
  refresh()
end

-- ---------------------------------------------------------------------------------------
-- events

-- the game's own message text as a pattern with the name captured ("%s declines ..." -> "(.+) declines ...")
local function toPattern(s)
  if type(s) ~= "string" then return nil end
  s = string.gsub(s, "([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
  s = string.gsub(s, "%%%%s", "(.+)")
  s = string.gsub(s, "%%%%d", "%%d+")
  return "^" .. s .. "$"
end

local SYSTEM = {}

local function onSystem(text)
  if isSecret(text) or type(text) ~= "string" then return end
  if text == ERR_TRADE_COMPLETE then tradeDone(); return end
  for _, s in ipairs(SYSTEM) do
    local name = s.pattern and string.match(text, s.pattern)
    if name then
      local b = buyers[string.lower(shortName(name) or "")]
      if b then s.run(b) end
      if refresh then refresh() end
      return
    end
  end
end

local function onRoster()
  local t = now()
  for _, b in pairs(buyers) do
    local unit = unitFor(b.name)
    if unit then
      b.unit = unit
      if b.state ~= "group" and b.state ~= "paid" and b.state ~= "done" then
        b.state, b.joinedAt, b.queued = "group", t, nil
      end
    else
      b.unit = nil
      if b.state == "group" or b.state == "paid" then
        if PP.portalAt and t - PP.portalAt < 90 and (not b.city or b.city == PP.portalCity) then
          if not b.city then b.city = PP.portalCity end
          markDone(b)
        else
          b.state = "left"
        end
      end
    end
  end
  updateCast()
  if refresh then refresh() end
end

local function onCast(spellID)
  local c = CITY_BY_SPELL[spellID]
  if not c then return end
  PP.portalAt, PP.portalCity = now(), c.key
  local n = 0
  for _, b in pairs(buyers) do
    if b.unit and (b.state == "group" or b.state == "paid") and (not b.city or b.city == c.key) then
      b.nearAtCast, b.kickAt = visible(b.unit), nil
      if b.nearAtCast then n = n + 1 end
    else
      b.nearAtCast = nil
    end
  end
  ledgerAdd({ k = "cast", c = c.key, r = DB.runeCost, b = n })
  local r = runes() - 1
  if r < 5 then say("|cffff4040Only " .. math.max(r, 0) .. " Rune of Portals left.|r") end
end

local function initDB()
  PortalProDB = PortalProDB or {}
  DB = PortalProDB
  for k, v in pairs(DEFAULTS) do
    if DB[k] == nil then DB[k] = type(v) == "table" and {} or v end
  end
  -- 0.2.0: the default price went from 1g to 50s; a price still at the old default follows
  if not DB.v2 then
    if DB.price == 10000 then DB.price = 5000 end
    DB.v2 = true
  end
  DB.stats = nil   -- 0.3.0: the ledger replaces the old counters
  DB.ledger = DB.ledger or {}
  DB.totals = DB.totals or newTotals()
  for k, v in pairs(newTotals()) do if DB.totals[k] == nil then DB.totals[k] = v end end
  DB.runeCost = DB.runeCost or DEFAULT_RUNE_COST

  SYSTEM = {
    { pattern = toPattern(ERR_ALREADY_IN_GROUP_S), run = function(b) b.state = "busy" end },
    { pattern = toPattern(ERR_DECLINE_GROUP_S), run = function(b) b.state, b.declinedAt = "declined", now() end },
    { pattern = toPattern(ERR_BAD_PLAYER_NAME_S), run = function(b) buyers[b.key] = nil end },
    { pattern = toPattern(ERR_PLAYER_WRONG_FACTION), run = function(b) buyers[b.key] = nil end },
  }
end

local f = CreateFrame("Frame")
local function listen(ev) pcall(f.RegisterEvent, f, ev) end
listen("ADDON_LOADED")
listen("PLAYER_LOGIN")

local function registerAll()
  for _, ev in ipairs({ "CHAT_MSG_CHANNEL", "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_WHISPER", "GROUP_ROSTER_UPDATE",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "TRADE_SHOW", "TRADE_CLOSED", "TRADE_MONEY_CHANGED", "TRADE_ACCEPT_UPDATE", "UI_INFO_MESSAGE", "CHAT_MSG_SYSTEM",
    "PLAYER_REGEN_ENABLED", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "BAG_UPDATE_DELAYED", "MERCHANT_SHOW", "MERCHANT_UPDATE",
    "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
    listen(ev)
  end
  if f.RegisterUnitEvent then pcall(f.RegisterUnitEvent, f, "UNIT_SPELLCAST_SUCCEEDED", "player") else listen("UNIT_SPELLCAST_SUCCEEDED") end
end

f:SetScript("OnEvent", function(_, ev, a1, a2, a3, a4, a5, a6, a7, a8, a9)
  if ev == "ADDON_LOADED" then
    if a1 == ADDON then initDB() end
  elseif ev == "PLAYER_LOGIN" then
    -- mages only: on any other class nothing is built, heard or run (the saved ledger is left as it is)
    local ok, _, classFile = pcall(UnitClass, "player")
    if not ok or isSecret(classFile) or classFile ~= "MAGE" then
      PP.off = true
      f:UnregisterAllEvents()
      return
    end
    myName = fullName("player") or ""
    scanSpells()
    buildPanel()
    buildLedger()
    buildMessages()
    registerAll()
    updateCast()
    C_Timer.NewTicker(0.5, tick)
    if #known == 0 then
      say("No portal spells on this character yet (mages learn them at level 40). Buyers are still listed, but nobody is invited. /pp help")
    else
      say("Ready: " .. #known .. " portals, " .. runes() .. " runes, price " .. money(DB.price) .. ". /pp help")
    end
  elseif ev == "CHAT_MSG_CHANNEL" then
    if DB.listen then
      local where = (not isSecret(a9) and type(a9) == "string" and a9) or (not isSecret(a4) and type(a4) == "string" and a4) or "chat"
      request(a2, a1, "chat", where)
    end
  elseif ev == "CHAT_MSG_SAY" or ev == "CHAT_MSG_YELL" then
    if DB.listen then request(a2, a1, "say", ev == "CHAT_MSG_SAY" and "say" or "yell") end
  elseif ev == "CHAT_MSG_WHISPER" then
    request(a2, a1, "whisper", "whisper")
  elseif ev == "CHAT_MSG_PARTY" or ev == "CHAT_MSG_PARTY_LEADER" then
    PP.partyEcho(a1, a2)
  elseif ev == "GROUP_ROSTER_UPDATE" then
    onRoster()
  elseif ev == "TRADE_SHOW" then
    PP.trade = { name = partnerName(), money = targetMoney() }
    updateOverlay(); refresh()
  elseif ev == "TRADE_MONEY_CHANGED" or ev == "TRADE_ACCEPT_UPDATE" then
    if PP.trade then PP.trade.money = targetMoney() end
    updateOverlay(); refresh()
  elseif ev == "TRADE_CLOSED" then
    if PP.trade then PP.lastTrade = PP.trade end
    PP.trade = nil
    updateOverlay(); refresh()
  elseif ev == "UI_INFO_MESSAGE" then
    -- (type, text) in newer clients, (text) in older ones
    if a1 == ERR_TRADE_COMPLETE or a2 == ERR_TRADE_COMPLETE then tradeDone() end
  elseif ev == "CHAT_MSG_SYSTEM" then
    onSystem(a1)
  elseif ev == "UNIT_SPELLCAST_SUCCEEDED" then
    if a1 == "player" and not isSecret(a3) and type(a3) == "number" then onCast(a3) end
  elseif ev == "PLAYER_REGEN_ENABLED" then
    if PP.castDirty then updateCast() end
  elseif ev == "SPELLS_CHANGED" or ev == "LEARNED_SPELL_IN_TAB" then
    scanSpells(); updateCast()
  elseif ev == "BAG_UPDATE_DELAYED" then
    refresh()
  elseif ev == "MERCHANT_SHOW" or ev == "MERCHANT_UPDATE" then
    readRuneCost()
  elseif ev == "ADDON_ACTION_BLOCKED" or ev == "ADDON_ACTION_FORBIDDEN" then
    if a1 == ADDON then
      local fn = tostring(a2)
      if string.find(fn, "InitiateTrade", 1, true) or string.find(fn, "UNKNOWN", 1, true) then
        PP.tradeBlocked = true
        say("The game does not let addons open trade by themselves here - click the buyer's line to open it.")
      else
        say("The game blocked " .. fn .. ". Tell the author.")
      end
    end
  end
end)

-- ---------------------------------------------------------------------------------------
-- keys and slash commands

BINDING_HEADER_PORTALPRO = "PortalPro"
BINDING_NAME_PORTALPRO_AD = "Post ad"
_G["BINDING_NAME_CLICK PortalProCastButton:LeftButton"] = "Cast portal"
BINDING_NAME_PORTALPRO_ACCEPT = "Accept trade"
BINDING_NAME_PORTALPRO_PANEL = "Show / hide panel"

function PortalPro_PostAd() if not PP.off then PP.postAd() end end
function PortalPro_AcceptTrade() if not PP.off then PP.accept() end end
function PortalPro_TogglePanel() if not PP.off then PP.togglePanel() end end

local HELP = {
  "/pp - show / hide the panel",
  "/pp price 1g50s - price for every portal (0 = tips)",
  "/pp price darn 2g - price for one city (/pp price darn off - back to the normal price)",
  "/pp messages - edit the ad and the party thank-you in a window (or the Messages button)",
  "/pp ad <text> - your own ad; {route}, {here}, {cities} and {price} fill in. /pp ad reset - the standard ad",
  "/pp cd 90 - seconds between ads",
  "/pp thanks - party thank-you after a trade on / off.  /pp thanks <text> - your own; {name} {got} {city} {tip} {price} fill in.  /pp thanks reset",
  "/pp listen | invite | whisperinv | whisper | trade | kick | sound - turn one on / off",
  "/pp ledger - the ledger window.  /pp stats - today / 7 days / all time in chat",
  "/pp runecost 18s - what a Rune of Portals costs you (read at the vendor by itself)",
  "/pp ledger reset - delete the ledger (asks twice)",
  "/pp test <line> - would this chat line count as a buyer?",
  "Keys: Game Menu > Key Bindings > PortalPro (Post ad, Cast portal, Accept trade).",
}

local SWITCHES = { listen = "listen", invite = "inviteAsks", whisperinv = "autoInvite", whisper = "whisper",
  trade = "autoTrade", kick = "autoKick", sound = "sound" }

SLASH_PORTALPRO1 = "/pp"
SLASH_PORTALPRO2 = "/portalpro"
SlashCmdList.PORTALPRO = function(msg)
  if PP.off then say("PortalPro only works on a mage."); return end
  msg = strtrim(msg or "")
  local cmd, rest = string.match(msg, "^(%S*)%s*(.-)$")
  cmd = string.lower(cmd or "")
  if cmd == "" then
    PP.togglePanel()
  elseif cmd == "help" then
    for _, l in ipairs(HELP) do say(l) end
  elseif cmd == "price" then
    local a, b = string.match(rest, "^(%S+)%s*(.-)$")
    local city = a and (CITY[string.lower(a)] or findCity(string.lower(a)))
    if city and b ~= "" then
      if string.lower(b) == "off" then DB.cityPrice[city.key] = nil; say(city.name .. ": normal price."); updateCast(); refresh(); return end
      local c = parseMoney(b)
      if not c then say("Write the price like 1g50s."); return end
      DB.cityPrice[city.key] = c
      say(city.name .. ": " .. money(c) .. ".")
    else
      local c = parseMoney(rest)
      if not c then say("Price now " .. money(DB.price) .. ". Write it like /pp price 1g50s."); return end
      DB.price = c
      say("Price: " .. money(c) .. (c == 0 and " (tips)" or "") .. ".")
    end
    refresh()
  elseif cmd == "ad" then
    if rest == "" then say("Ad: " .. adText())
    elseif string.lower(rest) == "reset" then DB.ad = nil; say("Ad: " .. adText())
    else DB.ad = rest; say("Ad: " .. adText()) end
  elseif cmd == "cd" then
    local n = tonumber(rest)
    if not n or n < 15 then say("Seconds between ads, 15 or more."); return end
    DB.adCooldown = math.floor(n)
    say("Ads every " .. DB.adCooldown .. " s at most.")
    refresh()
  elseif cmd == "thanks" then
    local r = string.lower(rest)
    if rest == "" then
      DB.thanks = not DB.thanks
    elseif r == "reset" then
      DB.thanksText = nil
    elseif r == "on" or r == "off" then
      DB.thanks = r == "on"
    else
      DB.thanksText = rest
    end
    say("Thank-you in party " .. onOff(DB.thanks) .. ": " .. thanksSample())
  elseif cmd == "messages" or cmd == "msg" then
    PP.toggleMessages()
  elseif SWITCHES[cmd] then
    local k = SWITCHES[cmd]
    DB[k] = not DB[k]
    if k == "autoTrade" then PP.tradeBlocked = nil end
    say(cmd .. ": " .. onOff(DB[k]))
    refresh()
  elseif cmd == "ledger" or cmd == "stats" then
    if string.lower(rest) == "reset" then
      if not (PP.resetArmed and now() - PP.resetArmed < 10) then
        PP.resetArmed = now()
        say("|cffff4040This deletes the whole ledger.|r Type /pp ledger reset again within 10 s to do it.")
        return
      end
      PP.resetArmed = nil
      PP.resetLedger()
      return
    end
    if cmd == "ledger" then PP.toggleLedger(); return end
    for _, p in ipairs({ { "Today", ledgerSum(dayStart()) }, { "7 days", ledgerSum(time() - 7 * 86400) }, { "All time", ledgerSum(nil) } }) do
      local T = p[2]
      say(string.format("%s: net %s%s = %s in (%s tips) - %s for %d runes. %d buyers through, %s short.",
        p[1], net(T) < 0 and "-" or "", money(math.abs(net(T))), money(T.income), money(T.tips),
        money(T.runeCost), T.casts, T.served, money(T.short)))
    end
  elseif cmd == "runecost" then
    local c = parseMoney(rest)
    if not c or c <= 0 then say("Rune of Portals: " .. money(DB.runeCost) .. " each. Set it like /pp runecost 18s."); return end
    DB.runeCost = c
    say("Rune of Portals: " .. money(c) .. " each, from now on.")
    PP.ledgerRefresh()
  elseif cmd == "test" then
    local lower = clean(rest)
    local ok, city = channelIntent(lower)
    local wok, wcity = whisperIntent(lower)
    say("In chat: " .. (ok and ("|cff40ff40buyer|r, " .. cityLine(city)) or "|cff808080not a buyer|r")
      .. ".  As a whisper: " .. (wok == "price" and "price question" or wok and ("|cff40ff40buyer|r, " .. cityLine(wcity)) or "|cff808080ignored|r") .. ".")
  else
    say("Unknown command. /pp help")
  end
end

-- for the offline tests
PP._test = { channelIntent = channelIntent, whisperIntent = whisperIntent, findCity = findCity, clean = clean,
  parseMoney = parseMoney, money = money, toPattern = toPattern }
