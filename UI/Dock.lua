-- PortalPro - the trade dock: a panel beside the trade window with the city, the payment and a Cast button.
local ADDON, ns = ...
local PP = ns.PP
local safe = ns.safe
local money = ns.money
local Kit = ns.Kit

local dock

local function build()
  local tf = _G.TradeFrame
  if dock or not tf then return end
  dock = CreateFrame("Frame", "PortalProDock", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  dock:SetSize(240, 170)
  dock:SetFrameStrata("HIGH")
  Kit.backdrop(dock, 0.95, true)

  dock.cityIcon = Kit.icon(dock, 32)
  dock.cityIcon:SetPoint("TOPLEFT", 16, -16)
  dock.title = dock:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  dock.title:SetPoint("TOPLEFT", dock.cityIcon, "TOPRIGHT", 8, 0)
  dock.title:SetPoint("RIGHT", -16, 0)
  dock.title:SetJustifyH("LEFT")
  dock.sub = dock:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  dock.sub:SetPoint("BOTTOMLEFT", dock.cityIcon, "BOTTOMRIGHT", 8, 0)
  dock.sub:SetPoint("RIGHT", -16, 0)
  dock.sub:SetJustifyH("LEFT")

  local payHead = dock:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  payHead:SetPoint("TOPLEFT", 16, -58)
  payHead:SetText("PAYMENT")
  dock.pay = Kit.progress(dock)
  dock.pay:SetPoint("TOPLEFT", 16, -72)
  dock.pay:SetPoint("RIGHT", -16, 0)
  dock.pay:SetWidth(208)
  dock.payText = dock:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  dock.payText:SetPoint("TOPLEFT", 16, -86)
  dock.payText:SetPoint("RIGHT", -16, 0)
  dock.payText:SetJustifyH("LEFT")

  -- its own secure Cast button: the same spell as the panel's (updateCast sets both)
  ns.dockCast = CreateFrame("Button", "PortalProDockCast", dock, "UIPanelButtonTemplate,SecureActionButtonTemplate")
  ns.dockCast:SetPoint("BOTTOMLEFT", 16, 16)
  ns.dockCast:SetPoint("BOTTOMRIGHT", -16, 16)
  ns.dockCast:SetHeight(36)
  local down = safe(GetCVarBool, "ActionButtonUseKeyDown")
  ns.dockCast:RegisterForClicks(down and "AnyDown" or "AnyUp")
  ns.dockCast:SetAttribute("type", "spell")
  ns.dockCast:SetText("Cast")
  dock:Hide()
end

-- beside the trade window, or below EnchantPro's dock when that one is up (a mage enchanter runs both)
local function place()
  if InCombatLockdown() then return end
  local ep = _G.EnchantProDock
  dock:ClearAllPoints()
  if ep and ep.IsShown and ep:IsShown() then
    dock:SetPoint("TOPLEFT", ep, "BOTTOMLEFT", 0, -2)
  else
    dock:SetPoint("TOPLEFT", _G.TradeFrame, "TOPRIGHT", 2, 0)
  end
end

local function setShown(show)
  if not dock then return end
  if show then place() end
  if dock:IsShown() == show then return end
  if InCombatLockdown() then PP.dockDirty = true; return end   -- it holds a secure button
  if show then dock:Show() else dock:Hide() end
end

-- fill the dock from the trade; shown while a trade is open
local function updateDock()
  build()
  if not dock then return end
  local s = ns.dockState()
  if not s then setShown(false); return end
  local c = s.city
  dock.title:SetText(c and ("Portal to " .. c.name) or "|cffff4040No portal|r")
  dock.cityIcon:SetIcon(ns.cityIcon and ns.cityIcon(c) or nil)
  dock.sub:SetText(s.buyer and s.buyer.name or ((PP.trade and PP.trade.name or "?") .. " |cff808080(not a buyer)|r"))
  if s.owed > 0 then
    if s.paid then dock.pay:Set(1) else dock.pay:Set(s.got / s.owed, 0.9, 0.25, 0.25) end
    dock.payText:SetText(money(s.got) .. " of " .. money(s.owed)
      .. (s.paid and ("  |cff40ff40PAID|r" .. (s.got > s.owed and (" +" .. money(s.got - s.owed) .. " tip") or "")) or ""))
  else
    dock.pay:Set(s.got > 0 and 1 or 0)
    dock.payText:SetText(money(s.got) .. " in trade")
  end
  if ns.dockCast then Kit.pulse(ns.dockCast, s.paid and s.buyer ~= nil) end
  setShown(true)
end

function PP.dockAfterCombat()
  if PP.dockDirty then PP.dockDirty = nil; updateDock() end
end

ns.buildDock = build
ns.updateDock = updateDock
