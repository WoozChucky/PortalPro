-- PortalPro - the tick, start-up, events, key bindings and slash commands.
local ADDON, ns = ...
local PP = ns.PP
local CITY = ns.CITY
local CITY_BY_SPELL = ns.CITY_BY_SPELL
local DEFAULTS = ns.DEFAULTS
local buyers = ns.buyers
local isSecret = ns.isSecret
local safe = ns.safe
local say = ns.say
local now = ns.now
local shortName = ns.shortName
local money = ns.money
local parseMoney = ns.parseMoney
local scanSpells = ns.scanSpells
local runes = ns.runes
local priceFor = ns.priceFor
local clean = ns.clean
local findCity = ns.findCity
local channelIntent = ns.channelIntent
local whisperIntent = ns.whisperIntent
local chatBusy = ns.chatBusy
local openBox = ns.openBox
local thanksSample = ns.thanksSample
local adText = ns.adText
local fullName = ns.fullName
local unitFor = ns.unitFor
local isLeader = ns.isLeader
local freeSlots = ns.freeSlots
local invite = ns.invite
local uninvite = ns.uninvite
local DEFAULT_RUNE_COST = ns.DEFAULT_RUNE_COST
local newTotals = ns.newTotals
local ledgerAdd = ns.ledgerAdd
local ledgerSum = ns.ledgerSum
local net = ns.net
local dayStart = ns.dayStart
local markDone = ns.markDone
local cityLine = ns.cityLine
local request = ns.request
local updateCast = ns.updateCast
local partnerName = ns.partnerName
local targetMoney = ns.targetMoney
local updateOverlay = ns.updateOverlay
local tradeDone = ns.tradeDone
local openTrade = ns.openTrade
local onOff = ns.onOff
local readRuneCost = ns.readRuneCost
local buildPanel = ns.buildPanel

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
  if not ns.DB then return end
  local t = now()

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
          if ns.DB.autoKick then uninvite(b) end
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

  -- drop old lines: waiting orders quiet for 2 hours, ported (2 min), a city you have no portal to (5 min)
  for key, b in pairs(buyers) do
    if not b.unit then
      if (b.state == "done" and t - (b.doneAt or 0) > 120)
         or ns.quiet(b, t)
         or (not ns.isWaiting(b) and b.state ~= "done" and t - b.at > 300) then
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
  if ns.refresh then ns.refresh() end
end

-- ---------------------------------------------------------------------------------------
-- events

-- the game's own message text as a pattern with the name captured ("%s declines ..." -> "(.+) declines ...")
local function toPattern(s)
  if type(s) ~= "string" then return nil end
  s = string.gsub(s, "([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
  s = string.gsub(s, "%%s", "(.+)")
  s = string.gsub(s, "%%d", "%%d+")
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
      if ns.refresh then ns.refresh() end
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
  if ns.refresh then ns.refresh() end
end

ns.onRoster = onRoster

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
  ledgerAdd({ k = "cast", c = c.key, r = ns.DB.runeCost, b = n })
  local r = runes() - 1
  if r < 5 then say("|cffff4040Only " .. math.max(r, 0) .. " Rune of Portals left.|r") end
end

local function initDB()
  PortalProDB = PortalProDB or {}
  ns.DB = PortalProDB
  for k, v in pairs(DEFAULTS) do
    if ns.DB[k] == nil then ns.DB[k] = type(v) == "table" and {} or v end
  end
  -- 0.2.0: the default price went from 1g to 50s; a price still at the old default follows
  if not ns.DB.v2 then
    if ns.DB.price == 10000 then ns.DB.price = 5000 end
    ns.DB.v2 = true
  end
  ns.DB.stats = nil   -- 0.3.0: the ledger replaces the old counters
  ns.DB.ledger = ns.DB.ledger or {}
  ns.DB.totals = ns.DB.totals or newTotals()
  for k, v in pairs(newTotals()) do if ns.DB.totals[k] == nil then ns.DB.totals[k] = v end end
  ns.DB.runeCost = ns.DB.runeCost or DEFAULT_RUNE_COST

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
listen("PLAYER_LOGOUT")

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

f:SetScript("OnEvent", function(_, ev, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12)
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
    ns.myName = fullName("player") or ""
    scanSpells()
    buildPanel()
    ns.buildDock()
    ns.buildExtras()
    ns.loadQueue()
    registerAll()
    updateCast()
    C_Timer.NewTicker(0.5, tick)
    if #ns.known == 0 then
      say("No portal spells on this character yet (mages learn them at level 40). Buyers are still listed, but nobody is invited. /pp help")
    else
      say("Ready: " .. #ns.known .. " portals, " .. runes() .. " runes, price " .. money(ns.DB.price) .. ". /pp help")
    end
  elseif ev == "PLAYER_LOGOUT" then
    if not PP.off then ns.saveQueue() end
  elseif ev == "CHAT_MSG_CHANNEL" then
    if ns.DB.listen then
      local where = (not isSecret(a9) and type(a9) == "string" and a9) or (not isSecret(a4) and type(a4) == "string" and a4) or "chat"
      request(a2, a1, "chat", where, a12)
    end
  elseif ev == "CHAT_MSG_SAY" or ev == "CHAT_MSG_YELL" then
    if ns.DB.listen then request(a2, a1, "say", ev == "CHAT_MSG_SAY" and "say" or "yell", a12) end
  elseif ev == "CHAT_MSG_WHISPER" then
    request(a2, a1, "whisper", "whisper", a12)
  elseif ev == "CHAT_MSG_PARTY" or ev == "CHAT_MSG_PARTY_LEADER" then
    PP.partyEcho(a1, a2)
  elseif ev == "GROUP_ROSTER_UPDATE" then
    onRoster()
  elseif ev == "TRADE_SHOW" then
    PP.trade = { name = partnerName(), money = targetMoney() }
    updateOverlay(); ns.refresh()
  elseif ev == "TRADE_MONEY_CHANGED" or ev == "TRADE_ACCEPT_UPDATE" then
    if PP.trade then PP.trade.money = targetMoney() end
    updateOverlay(); ns.refresh()
  elseif ev == "TRADE_CLOSED" then
    if PP.trade then PP.lastTrade = PP.trade end
    PP.trade = nil
    updateOverlay(); ns.refresh()
  elseif ev == "UI_INFO_MESSAGE" then
    -- (type, text) in newer clients, (text) in older ones
    if a1 == ERR_TRADE_COMPLETE or a2 == ERR_TRADE_COMPLETE then tradeDone() end
  elseif ev == "CHAT_MSG_SYSTEM" then
    onSystem(a1)
  elseif ev == "UNIT_SPELLCAST_SUCCEEDED" then
    if a1 == "player" and not isSecret(a3) and type(a3) == "number" then onCast(a3) end
  elseif ev == "PLAYER_REGEN_ENABLED" then
    if PP.castDirty then updateCast() end
    PP.afterCombat()
    PP.dockAfterCombat()
    PP.extrasAfterCombat()
  elseif ev == "SPELLS_CHANGED" or ev == "LEARNED_SPELL_IN_TAB" then
    scanSpells(); updateCast()
  elseif ev == "BAG_UPDATE_DELAYED" then
    ns.refresh()
  elseif ev == "MERCHANT_SHOW" or ev == "MERCHANT_UPDATE" then
    readRuneCost()
  elseif ev == "ADDON_ACTION_BLOCKED" or ev == "ADDON_ACTION_FORBIDDEN" then
    if a1 == ADDON then
      local fn = tostring(a2)
      if string.find(fn, "InitiateTrade", 1, true) or string.find(fn, "UNKNOWN", 1, true) then
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
  "/pp listen | invite | whisperinv | whisper | kick | sound - turn one on / off",
  "/pp ledger - the ledger window.  /pp stats - today / 7 days / all time in chat",
  "/pp runecost 18s - what a Rune of Portals costs you (read at the vendor by itself)",
  "/pp ledger reset - delete the ledger (asks twice)",
  "/pp test <line> - would this chat line count as a buyer?",
  "/pp compact - fold the window to one line (again: back) - /pp minimap - hide or show the minimap button",
  "Keys: Game Menu > Key Bindings > PortalPro (Post ad, Cast portal, Accept trade).",
}

local SWITCHES = { listen = "listen", invite = "inviteAsks", whisperinv = "autoInvite", whisper = "whisper",
  kick = "autoKick", sound = "sound" }

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
      if string.lower(b) == "off" then ns.DB.cityPrice[city.key] = nil; say(city.name .. ": normal price."); updateCast(); ns.refresh(); return end
      local c = parseMoney(b)
      if not c then say("Write the price like 1g50s."); return end
      ns.DB.cityPrice[city.key] = c
      say(city.name .. ": " .. money(c) .. ".")
    else
      local c = parseMoney(rest)
      if not c then say("Price now " .. money(ns.DB.price) .. ". Write it like /pp price 1g50s."); return end
      ns.DB.price = c
      say("Price: " .. money(c) .. (c == 0 and " (tips)" or "") .. ".")
    end
    ns.refresh()
  elseif cmd == "ad" then
    if rest == "" then say("Ad: " .. adText())
    elseif string.lower(rest) == "reset" then ns.DB.ad = nil; say("Ad: " .. adText())
    else ns.DB.ad = rest; say("Ad: " .. adText()) end
  elseif cmd == "cd" then
    local n = tonumber(rest)
    if not n or n < 15 then say("Seconds between ads, 15 or more."); return end
    ns.DB.adCooldown = math.floor(n)
    say("Ads every " .. ns.DB.adCooldown .. " s at most.")
    ns.refresh()
  elseif cmd == "thanks" then
    local r = string.lower(rest)
    if rest == "" then
      ns.DB.thanks = not ns.DB.thanks
    elseif r == "reset" then
      ns.DB.thanksText = nil
    elseif r == "on" or r == "off" then
      ns.DB.thanks = r == "on"
    else
      ns.DB.thanksText = rest
    end
    say("Thank-you in party " .. onOff(ns.DB.thanks) .. ": " .. thanksSample())
  elseif cmd == "compact" then
    PP.setCompact(not (ns.DB.ui and ns.DB.ui.compact))
  elseif cmd == "minimap" then
    PP.toggleMinimap()
  elseif cmd == "messages" or cmd == "msg" then
    PP.toggleMessages()
  elseif SWITCHES[cmd] then
    local k = SWITCHES[cmd]
    ns.DB[k] = not ns.DB[k]
    say(cmd .. ": " .. onOff(ns.DB[k]))
    ns.refresh()
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
    if not c or c <= 0 then say("Rune of Portals: " .. money(ns.DB.runeCost) .. " each. Set it like /pp runecost 18s."); return end
    ns.DB.runeCost = c
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
