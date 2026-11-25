-- PortalPro - buyers: answering what they ask, and the portal the group needs.
local ADDON, ns = ...
local buyers = ns.buyers
local isSecret = ns.isSecret
local say = ns.say
local now = ns.now
local shortName = ns.shortName
local money = ns.money
local priceFor = ns.priceFor
local playSound = ns.playSound
local clean = ns.clean
local channelIntent = ns.channelIntent
local whisperIntent = ns.whisperIntent
local whisper = ns.whisper
local unitFor = ns.unitFor
local invite = ns.invite

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

-- someone asked for a portal (src = "whisper", "chat" or "say"); guid: the chat event's sender GUID, for the class colour
local function request(sender, text, src, where, guid)
  if isSecret(sender) or isSecret(text) or type(sender) ~= "string" or type(text) ~= "string" then return end
  local name = shortName(sender)
  if not name or string.lower(name) == string.lower(ns.myName) then return end
  local lower = clean(text)
  local intent, city
  if src == "whisper" then intent, city = whisperIntent(lower) else intent, city = channelIntent(lower) end
  if not intent then return end

  if intent == "price" then
    local b = buyers[string.lower(name)] or { name = name, full = sender }
    whisper(b, "Portals: " .. money(ns.DB.price) .. " each. Whisper \"inv\" + the city and I'll invite you.")
    return
  end
  -- a city this character has no portal to (or no portals at all yet): listed, greyed, never invited
  local cantPort = (city and not city.spell) or #ns.known == 0
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
  if not b.class and type(guid) == "string" and not isSecret(guid) and guid ~= "" then
    local ok, _, cls = pcall(GetPlayerInfoByGUID, guid)
    if ok and type(cls) == "string" then b.class = cls end
  end

  if b.new then
    b.new = nil
    playSound()
    if ns.onNewBuyer then ns.onNewBuyer(b) end
    say((cantPort and "|cff808080Buyer|r " or "|cff40ff40Buyer|r ") .. name .. " - " .. cityLine(city) .. " (" .. (where or src) .. ")"
      .. (cantPort and " - |cff808080you have no portal there, not invited.|r" or "."))
  end
  if cantPort then
    if ns.refresh then ns.refresh() end
    return
  end

  local wantInvite = (src == "whisper" and ns.DB.autoInvite) or (src ~= "whisper" and ns.DB.inviteAsks)
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
  if ns.refresh then ns.refresh() end
end

ns.buyerFor = buyerFor
ns.cityLine = cityLine
ns.request = request
