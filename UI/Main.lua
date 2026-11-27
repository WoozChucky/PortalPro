-- PortalPro - the main window: Buyers / Messages / Ledger tabs.
local ADDON, ns = ...
local PP = ns.PP
local RUNE_OF_PORTALS = ns.RUNE_OF_PORTALS
local CITY = ns.CITY
local PANEL_MAX_ROWS = ns.PANEL_MAX_ROWS
local buyers = ns.buyers
local rows = ns.rows
local toggles = ns.toggles
local isSecret = ns.isSecret
local safe = ns.safe
local say = ns.say
local now = ns.now
local money = ns.money
local runes = ns.runes
local priceFor = ns.priceFor
local restricted = ns.restricted
local adLeft = ns.adLeft
local invite = ns.invite
local ledgerSum = ns.ledgerSum
local net = ns.net
local dayStart = ns.dayStart
local cycleCity = ns.cycleCity
local tradeBuyer = ns.tradeBuyer
local openTrade = ns.openTrade
local Kit = ns.Kit
local button = Kit.button
local tooltip = Kit.tooltip

local ICON = "Interface\\Icons\\Spell_Arcane_PortalOrgrimmar"
local TAB = { buyers = 1, messages = 2, ledger = 3 }
local ROW_H, ROW_STEP, ROWS_TOP = 28, 30, 122

local STATE_TEXT = {
  asked = "|cffffd200asked|r", invited = "|cff7fd4ffinvited|r", group = "|cffffffffin group|r",
  paid = "|cff40ff40PAID|r", done = "|cff808080ported|r", left = "|cff808080left|r",
  busy = "|cffff8040in a group|r", declined = "|cffff4040declined|r",
}
-- a group member close enough to trade
local function inRange(b)
  return b.unit ~= nil and safe(CheckInteractDistance, b.unit, 2) == true
end

local function onOff(v) return v and "|cff40ff40ON|r" or "|cff808080OFF|r" end

-- the portal spell's icon for a city (the one you know, else the first)
local function cityIcon(c)
  if not c then return nil end
  local id = c.spell or (c.spells and c.spells[1])
  if not id then return nil end
  if C_Spell and C_Spell.GetSpellTexture then return safe(C_Spell.GetSpellTexture, id) end
  return safe(GetSpellTexture, id)
end
ns.cityIcon = cityIcon

local function age(t)
  local s = math.max(0, now() - (t or now()))
  if s < 60 then return "now" end
  if s < 3600 then return math.floor(s / 60) .. "m" end
  return math.floor(s / 3600) .. "h"
end

-- "Trade - City" -> "Trade"
local function sourceText(b)
  local w = b.where or b.src or ""
  return (string.match(w, "^(.-)%s+%-%s+") or w)
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
        if each ~= ns.DB.runeCost then
          ns.DB.runeCost = each
          say("Rune of Portals costs " .. money(each) .. " here - the ledger counts that from now on.")
          PP.ledgerRefresh()
        end
      end
      return
    end
  end
end

-- the Buyers tab -----------------------------------------------------------------------------

local function buildBuyers(page)
  local panel = ns.panel
  panel.info = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.info:SetPoint("TOPLEFT", 2, 0)
  panel.info:SetPoint("RIGHT", -2, 0)
  panel.info:SetJustifyH("LEFT")

  panel.ad = button(page, 136, 22, "Post ad")
  panel.ad:SetPoint("TOPLEFT", 0, -16)
  panel.ad:SetScript("OnClick", function() PP.postAd() end)
  panel.accept = button(page, 136, 22, "Accept trade")
  panel.accept:SetPoint("TOPRIGHT", 0, -16)
  panel.accept:SetScript("OnClick", function() PP.accept() end)

  local prev = button(page, 24, 36, "<")
  prev:SetPoint("TOPLEFT", 0, -44)
  prev:SetScript("OnClick", function() cycleCity(-1) end)
  local nextB = button(page, 24, 36, ">")
  nextB:SetPoint("TOPRIGHT", 0, -44)
  nextB:SetScript("OnClick", function() cycleCity(1) end)
  panel.castIcon = Kit.icon(page, 36)
  panel.castIcon:SetPoint("LEFT", prev, "RIGHT", 4, 0)

  -- the one secure button: casting a spell needs the player's own click or key
  ns.castBtn = CreateFrame("Button", "PortalProCastButton", page, "UIPanelButtonTemplate,SecureActionButtonTemplate")
  ns.castBtn:SetPoint("TOPLEFT", panel.castIcon, "TOPRIGHT", 4, 0)
  ns.castBtn:SetPoint("BOTTOMRIGHT", nextB, "BOTTOMLEFT", -4, 0)
  local down = safe(GetCVarBool, "ActionButtonUseKeyDown")
  ns.castBtn:RegisterForClicks(down and "AnyDown" or "AnyUp")
  ns.castBtn:SetAttribute("type", "spell")

  panel.status = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.status:SetPoint("TOPLEFT", 2, -86)
  panel.status:SetPoint("RIGHT", -2, 0)
  panel.status:SetJustifyH("LEFT")

  local head = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  head:SetPoint("TOPLEFT", 2, -106)
  head:SetText("BUYERS  |cff808080click: trade (in range) / invite - right-click: remove (shift: block)|r")

  for i = 1, PANEL_MAX_ROWS do
    local r = Kit.row(page, ROW_H)
    r:SetPoint("TOPLEFT", 0, -ROWS_TOP - (i - 1) * ROW_STEP)
    r:SetPoint("RIGHT", 0, 0)
    r:SetScript("OnClick", function(self, mouse)
      local b = self.buyer
      if not b then return end
      if mouse == "RightButton" and IsShiftKeyDown() then
        ns.block(b.name)
      elseif mouse == "RightButton" then
        buyers[b.key] = nil
      elseif b.unit then
        if not inRange(b) then say(b.name .. " isn't in trade range yet.")
        elseif b.state ~= "paid" and b.state ~= "done" then openTrade(b) end
      else
        b.declinedAt = nil
        invite(b)
      end
      ns.refresh()
    end)
    -- hover: what they wrote and what it was read as
    r:SetScript("OnEnter", function(self)
      if not self.buyer then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(Kit.saidTip(self.buyer), 1, 1, 1, 1, true)
      GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = r
  end
  ns.scroll = Kit.scroller(page, function() ns.refresh() end)
  ns.scroll.text:SetPoint("TOPRIGHT", -2, -106)

  local defs = { { "listen", "Listen" }, { "inviteAsks", "Invite" }, { "autoKick", "Kick" } }
  local tips = {
    listen = "Look for buyers in Trade, General, LFG, say and yell.",
    inviteAsks = "Invite people who ask for a portal in public chat (whispers are always invited).",
    autoKick = "Kick buyers from the group once they went through the portal.",
  }
  for i, d in ipairs(defs) do
    local key = d[1]
    local t = Kit.toggle(page, 68, 22, d[2], function() return ns.DB[key] end, function(v)
      ns.DB[key] = v
      ns.refresh()
    end)
    t.key = key
    tooltip(t, tips[key])
    toggles[i] = t
  end

  function page.onLayout(w, h)
    local half = math.floor((w - 4) / 2)
    panel.ad:SetWidth(half)
    panel.accept:SetWidth(half)
    local tw = math.floor((w - (#toggles - 1) * 4) / #toggles)
    for i, t in ipairs(toggles) do
      t:SetWidth(tw)
      t:ClearAllPoints()
      t:SetPoint("BOTTOMLEFT", (i - 1) * (tw + 4), 0)
    end
    panel.visibleRows = math.max(1, math.min(PANEL_MAX_ROWS, math.floor((h - ROWS_TOP - 26) / ROW_STEP)))
  end
end

-- the window ---------------------------------------------------------------------------------

local function buildPanel()
  local panel = Kit.window("PortalProPanel", "PortalPro", ICON, 460, 440, ns.frameSave("main"))
  ns.panel = panel
  panel.visibleRows = 6
  panel.close:SetScript("OnClick", function() PP.togglePanel(false) end)
  panel.tabs = Kit.tabs(panel, { "Buyers", "Messages", "Ledger" }, function() ns.refresh() end,
    { "PortalProBuyers", "PortalProMessages", "PortalProLedger" },
    function(i)
      PP.pending = { show = true, tab = i }
      say("The tab switches when combat ends.")
    end)
  local pages = panel.tabs.pages
  buildBuyers(pages[1])
  ns.buildMessages(pages[2])
  ns.buildLedger(pages[3])
  panel.tabs:Select(1)

  Kit.makeResizable(panel, ns.frameSave("main"), 420, 400, 1000, 900, function(w, h)
    local cw, ch = w - 28, h - 76
    for _, page in ipairs(pages) do if page.onLayout then page.onLayout(cw, ch) end end
    if ns.refresh then ns.refresh() end
  end, true)

  if not ns.DB.shown then panel:Hide() end
end

ns.refresh = function()
  if ns.updateExtras then ns.updateExtras() end
  local panel = ns.panel
  if not panel or not panel:IsShown() then return end
  local today = net(ledgerSum(dayStart()))
  local r = runes()
  panel.info:SetText(string.format("Runes: %s   Today net: %s   Price: %s",
    r < 5 and ("|cffff4040" .. r .. "|r") or tostring(r),
    (today < 0 and "|cffff4040-" or "|cff40ff40") .. money(math.abs(today)) .. "|r", money(ns.DB.price)))

  local left = adLeft()
  panel.ad:SetText(left > 0 and string.format("Post ad (%d:%02d)", math.floor(left / 60), left % 60) or "Post ad")

  local tf = _G.TradeFrame
  if tf and tf:IsShown() then panel.accept:Enable() else panel.accept:Disable() end
  panel.castIcon:SetIcon(PP.castCity and cityIcon(PP.castCity) or ICON)

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

  -- the queue: waiting in order, then just ported, then cities you have no portal to
  local list = ns.queueList()
  local visible = panel.visibleRows or 6
  ns.scroll:Set(#list, visible)
  local nextUp
  for _, b in ipairs(list) do
    if ns.isWaiting(b) and b.state ~= "paid" and inRange(b) then nextUp = b; break end
  end
  for i, row in ipairs(rows) do
    local b = i <= visible and list[ns.scroll.offset + i] or nil
    row.buyer = b
    if b then
      local c = b.city and CITY[b.city]
      local p = ns.place(b)
      row.name:SetText((p and ("|cffffd200#" .. p .. "|r ") or "") .. "|cff" .. Kit.classHex(b.class) .. b.name .. "|r")
      row.sub:SetText((c and c.name or "?") .. "  |cff808080" .. sourceText(b) .. " - " .. age(b.since or b.at) .. "|r")
      row:SetMark(b == nextUp)
      row.icon:SetIcon(cityIcon(c))
      row:SetNear(b.unit ~= nil and b.state ~= "done")
      row.right:SetText(b.cantPort and "|cff808080no portal|r"
        or ((STATE_TEXT[b.state] or b.state) .. (b.queued and " |cffa0a0a0(waits)|r" or "")))
      row:SetAlpha(b.cantPort and 0.6 or 1)
      row:Show()
    else
      row:Hide()
    end
  end
  for _, t in ipairs(toggles) do t:Refresh() end
end

-- showing and hiding: the window holds the secure Cast button, so it can't change in combat;
-- what was asked then happens when combat ends
function PP.togglePanel(show)
  local panel = ns.panel
  if not panel then return end
  local opening = show == nil and not panel:IsShown()
  if show == nil then show = not panel:IsShown() end
  if InCombatLockdown() then
    PP.pending = { show = show, tab = opening and 1 or nil }
    say("The window " .. (show and "opens" or "closes") .. " when combat ends.")
    return
  end
  if show and ns.DB.ui and ns.DB.ui.compact then PP.setCompact(false); return end   -- unfold the bar
  if opening then panel.tabs:Select(1) end
  if show then panel:Show() else panel:Hide() end
  ns.DB.shown = show
  ns.refresh()
end

-- the window on one tab; toggle = a second ask for the tab already showing closes the window
function PP.showTab(key, toggle)
  local panel = ns.panel
  local i = TAB[key]
  if not panel or not i then return end
  if InCombatLockdown() then
    PP.pending = { show = true, tab = i }
    say("The window opens when combat ends.")
    return
  end
  if toggle and panel:IsShown() and panel.tabs.current == i then PP.togglePanel(false); return end
  panel.tabs:Select(i)
  if not panel:IsShown() then PP.togglePanel(true) end
end

function PP.afterCombat()
  local p = PP.pending
  if not p then return end
  PP.pending = nil
  if p.tab then ns.panel.tabs:Select(p.tab) end
  PP.togglePanel(p.show)
end

function PP.toggleLedger() PP.showTab("ledger", true) end
function PP.toggleMessages() PP.showTab("messages", true) end

ns.onOff = onOff
ns.readRuneCost = readRuneCost
ns.buildPanel = buildPanel
