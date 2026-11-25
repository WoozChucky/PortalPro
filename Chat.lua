-- PortalPro - reading chat: who wants a portal, and to where.
local ADDON, ns = ...
local CITIES = ns.CITIES
local CITY = ns.CITY

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

ns.clean = clean
ns.findCity = findCity
ns.channelIntent = channelIntent
ns.whisperIntent = whisperIntent
