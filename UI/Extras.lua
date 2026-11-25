-- PortalPro - the minimap button, the compact bar and the new-buyer pop-up (widgets from UI/Kit.lua).
local ADDON, ns = ...
local PP = ns.PP
local CITY = ns.CITY
local buyers = ns.buyers
local say = ns.say
local Kit = ns.Kit

local ICON = "Interface\\Icons\\Spell_Arcane_PortalOrgrimmar"
local WAITING = { asked = true, invited = true, group = true, paid = true }
local mm, bar, toast

local function ui()
  ns.DB.ui = ns.DB.ui or {}
  return ns.DB.ui
end

-- buyers waiting for a portal you have, and how many of them are in your group
local function waiting()
  local n, inGroup = 0, 0
  for _, b in pairs(buyers) do
    if not b.cantPort and WAITING[b.state] then
      n = n + 1
      if b.state == "group" or b.state == "paid" then inGroup = inGroup + 1 end
    end
  end
  return n, inGroup
end
ns.waitingBuyers = waiting

function PP.toggleMinimap()
  local hidden = not ui().minimapHidden
  if mm then mm:SetHidden(hidden) else ui().minimapHidden = hidden end
  say("Minimap button " .. (hidden and "hidden - /pp minimap brings it back." or "shown."))
end

-- fold the window to the bar, or back. The window holds the Cast button, so this waits for combat to end.
function PP.setCompact(on)
  if InCombatLockdown() then
    say("The window " .. (on and "folds" or "opens") .. " when combat ends.")
    PP.pendingCompact = on
    return
  end
  ui().compact = on and true or false
  if on then
    if ns.panel then ns.panel:Hide() end
    bar:Show()
  else
    bar:Hide()
    if ns.panel then ns.panel:Show(); ns.DB.shown = true end
  end
  ns.refresh()
end

function PP.extrasAfterCombat()
  if PP.pendingCompact ~= nil then
    local on = PP.pendingCompact
    PP.pendingCompact = nil
    PP.setCompact(on)
  end
end

-- a buyer just showed up (Buyers.lua). Cities you have no portal to don't pop up.
function ns.onNewBuyer(b)
  if not toast or b.cantPort then return end
  local c = b.city and CITY[b.city]
  toast:Pop(b.key, c and ns.cityIcon(c) or ICON,
    "|cff" .. Kit.classHex(b.class) .. b.name .. "|r wants a portal",
    (c and c.name or "a city") .. "  |cff808080" .. (b.where or b.src or "") .. "|r")
end

-- the badge and the bar's line, whether the window is open or not (ns.refresh calls this)
function ns.updateExtras()
  local n, inGroup = waiting()
  if mm then mm:SetBadge(n) end
  if bar then bar.text:SetText(n .. " buyers · " .. inGroup .. " in group") end
end

function ns.buildExtras()
  mm = Kit.minimapButton("PortalProMinimapButton", ICON, ui(), function(mouse)
    if mouse == "RightButton" then PP.postAd() else PP.togglePanel() end
  end, function()
    local n, inGroup = waiting()
    return "PortalPro\n|cffffffff" .. n .. " buyers, " .. inGroup .. " in group|r\n"
      .. "|cff808080Click: window - Right-click: post the ad - Drag: move|r"
  end, 225)
  bar = Kit.compactBar("PortalProCompact", ICON, ns.frameSave("compact"), "Post ad",
    function() PP.postAd() end, function() PP.setCompact(false) end, -118)
  toast = Kit.toast("PortalProToast", 6, function() PP.showTab("buyers") end)
  if ui().compact then
    if ns.panel then ns.panel:Hide() end
    bar:Show()
  end
  ns.updateExtras()
end
