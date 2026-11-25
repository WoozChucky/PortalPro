-- PortalPro - the cast button and the trade.
local ADDON, ns = ...
local PP = ns.PP
local CITY = ns.CITY
local buyers = ns.buyers
local safe = ns.safe
local say = ns.say
local now = ns.now
local money = ns.money
local spellName = ns.spellName
local priceFor = ns.priceFor
local thanksText = ns.thanksText
local sellable = ns.sellable
local fullName = ns.fullName
local unitFor = ns.unitFor
local ledgerAdd = ns.ledgerAdd
local servedPaidLate = ns.servedPaidLate
local buyerFor = ns.buyerFor

-- ---------------------------------------------------------------------------------------
-- the cast button: always the portal the group needs

local function planCity()
  if PP.manualAt and now() - PP.manualAt < 20 and ns.DB.manualCity and CITY[ns.DB.manualCity] and CITY[ns.DB.manualCity].spell then
    return CITY[ns.DB.manualCity], 0
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
  if ns.DB.manualCity and CITY[ns.DB.manualCity] and CITY[ns.DB.manualCity].spell then return CITY[ns.DB.manualCity], 0 end
  local list = sellable()
  return list[1] or ns.known[1], 0
end

local function updateCast()
  if not ns.castBtn then return end
  if InCombatLockdown() then PP.castDirty = true; return end
  PP.castDirty = nil
  local c, n = planCity()
  local spell = c and spellName(c.spell)
  ns.castBtn:SetAttribute("type", "spell")
  ns.castBtn:SetAttribute("spell", spell)
  if ns.dockCast then
    ns.dockCast:SetAttribute("type", "spell")
    ns.dockCast:SetAttribute("spell", spell)
    ns.dockCast:SetText(spell or "No portal")
  end
  if spell then
    ns.castBtn:SetText(spell .. (n and n > 0 and ("  (" .. n .. ")") or ""))
    ns.castBtn:Enable()
  else
    ns.castBtn:SetText(#ns.known == 0 and "No portals yet (level 40+)" or "No portal spells known")
  end
  PP.castCity = c
end

local function cycleCity(step)
  if #ns.known == 0 then return end
  local cur = PP.castCity
  local idx = 1
  for i, c in ipairs(ns.known) do if c == cur then idx = i end end
  idx = (idx - 1 + step) % #ns.known + 1
  ns.DB.manualCity, PP.manualAt = ns.known[idx].key, now()
  updateCast()
end

-- ---------------------------------------------------------------------------------------
-- trade

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

-- where the trade stands, for the trade dock. nil without a trade, and for someone who is neither a buyer nor
-- in the group (EnchantPro's dock covers strangers).
function ns.dockState()
  local t = PP.trade
  if not t then return nil end
  local b = tradeBuyer()
  if not b and not (t.name and unitFor(t.name)) then return nil end
  local city = (b and b.city and CITY[b.city]) or PP.castCity
  local owed = math.max(0, priceFor(b and b.city) - (b and b.paid or 0))
  local got = t.money or 0
  return { buyer = b, city = city, owed = owed, got = got, paid = got >= owed }
end

-- the trade dock shows the trade (UI/Dock.lua)
local function updateOverlay()
  if ns.updateDock then ns.updateDock() end
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
  if ns.DB.thanks and unitFor(b.name) then PP.partySay(thanksText(b, got, tip, owed, price)) end
  say("|cff40ff40+" .. money(got) .. "|r from " .. b.name .. (tip > 0 and (" (" .. money(tip) .. " tip)") or "")
    .. (got < owed and (" - |cffff4040" .. money(owed - got) .. " short|r") or "")
    .. (b.city and b.state ~= "done" and (" - cast " .. CITY[b.city].name .. "!") or "."))
  updateCast()
  if ns.refresh then ns.refresh() end
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

ns.updateCast = updateCast
ns.cycleCity = cycleCity
ns.partnerName = partnerName
ns.targetMoney = targetMoney
ns.tradeBuyer = tradeBuyer
ns.updateOverlay = updateOverlay
ns.tradeDone = tradeDone
ns.openTrade = openTrade
