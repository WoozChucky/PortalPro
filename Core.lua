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

local ADDON, ns = ...

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
  autoKick = true,      -- kick buyers once they went through the portal
  thanks = true,        -- a line in party chat after every paid trade: who paid what
  sound = true,
  shown = true,
  queues = {},          -- [character] = the waiting orders, saved at logout / reload
  nextOrder = 1,        -- the next queue number
}


local PANEL_MAX_ROWS = 20  -- buyer rows the panel can show when made tall
local buyers = {}       -- [lower-case short name] = buyer
ns.myName = ""
ns.panel = nil
ns.castBtn = nil
local rows = {}
local toggles = {}


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
ns.known = {}
local function scanSpells()
  ns.known = {}
  for _, c in ipairs(CITIES) do
    c.spell = nil
    for _, id in ipairs(c.spells) do
      if knows(id) then c.spell = id; break end
    end
    if c.spell then ns.known[#ns.known + 1] = c end
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
  return (cityKey and ns.DB.cityPrice[cityKey]) or ns.DB.price
end

local function playSound()
  if not ns.DB.sound then return end
  local id = (SOUNDKIT and SOUNDKIT.READY_CHECK) or 8960
  pcall(PlaySound, id, "Master")
end

ns.PP = PP
ns.RUNE_OF_PORTALS = RUNE_OF_PORTALS
ns.CITIES = CITIES
ns.CITY = CITY
ns.CITY_BY_SPELL = CITY_BY_SPELL
ns.DEFAULTS = DEFAULTS
ns.PANEL_MAX_ROWS = PANEL_MAX_ROWS
ns.buyers = buyers
ns.rows = rows
ns.toggles = toggles
ns.isSecret = isSecret
ns.safe = safe
ns.say = say
ns.now = now
ns.shortName = shortName
ns.money = money
ns.fill = fill
ns.parseMoney = parseMoney
ns.spellName = spellName
ns.scanSpells = scanSpells
ns.runes = runes
ns.priceFor = priceFor
ns.playSound = playSound
