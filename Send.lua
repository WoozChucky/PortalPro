-- PortalPro - sending: the chat box queue, whispers, party lines, the ad and the thank-you.
local ADDON, ns = ...
local PP = ns.PP
local CITY = ns.CITY
local isSecret = ns.isSecret
local safe = ns.safe
local say = ns.say
local now = ns.now
local shortName = ns.shortName
local money = ns.money
local fill = ns.fill

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
  if ns.DB.partyMode == "box" then toBox("/p " .. text); return end
  if not sendDirect(text, "PARTY") then
    ns.DB.partyMode = "box"
    toBox("/p " .. text)
    return
  end
  if ns.DB.partyMode ~= "direct" then PP.partyCheck = { text = text, at = now() } end
end

function PP.partyEcho(text, sender)
  local c = PP.partyCheck
  if not c or isSecret(text) or isSecret(sender) then return end
  if text == c.text and string.lower(shortName(sender) or "") == string.lower(ns.myName) then
    ns.DB.partyMode, PP.partyCheck = "direct", nil
  end
end

function PP.partyCheckTick()
  local c = PP.partyCheck
  if not c or now() - c.at < 3 then return end
  PP.partyCheck = nil
  ns.DB.partyMode = "box"
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
  return fill(tpl or ns.DB.thanksText or THANKS_DEFAULT, {
    name = b.name, got = money(got), price = money(price),
    city = b.city and CITY[b.city].name or "your city",
    tip = tip > 0 and (" (incl. " .. money(tip) .. " tip - much appreciated!)") or "",
  })
end

local function thanksSample(tpl)
  return thanksText({ name = "Bob", city = "uc" }, ns.DB.price + 1000, 1000, ns.DB.price, ns.DB.price, tpl)
end

local function whisper(b, text)
  if not ns.DB.whisper or restricted() then return false end
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
  for _, c in ipairs(ns.known) do if c ~= here then list[#list + 1] = c end end
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
  for _, c in ipairs(list) do if ns.DB.cityPrice[c.key] and ns.DB.cityPrice[c.key] ~= ns.DB.price then differ = true end end
  tpl = tpl or ((ns.DB.ad and ns.DB.ad ~= "") and ns.DB.ad or AD_DEFAULT)
  return fill(tpl, {
    route = here and (here.short .. " -> " .. cities) or ("to " .. cities),
    here = here and here.short or "",
    cities = cities,
    price = (differ and "from " or "") .. money(ns.DB.price),
  })
end

local function adLeft()
  return math.max(0, (ns.DB.adAt or 0) + ns.DB.adCooldown - time())
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
  ns.DB.adAt = time()
  if ns.refresh then ns.refresh() end
end

ns.restricted = restricted
ns.chatBusy = chatBusy
ns.openBox = openBox
ns.THANKS_DEFAULT = THANKS_DEFAULT
ns.THANKS_TOKENS = THANKS_TOKENS
ns.thanksText = thanksText
ns.thanksSample = thanksSample
ns.whisper = whisper
ns.sellable = sellable
ns.AD_DEFAULT = AD_DEFAULT
ns.AD_TOKENS = AD_TOKENS
ns.adText = adText
ns.adLeft = adLeft
