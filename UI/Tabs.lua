-- PortalPro - the Ledger and Messages tabs.
local ADDON, ns = ...
local PP = ns.PP
local CITY = ns.CITY
local say = ns.say
local money = ns.money
local THANKS_DEFAULT = ns.THANKS_DEFAULT
local THANKS_TOKENS = ns.THANKS_TOKENS
local thanksSample = ns.thanksSample
local AD_DEFAULT = ns.AD_DEFAULT
local AD_TOKENS = ns.AD_TOKENS
local adText = ns.adText
local newTotals = ns.newTotals
local ledgerSum = ns.ledgerSum
local net = ns.net
local dayStart = ns.dayStart
local Kit = ns.Kit
local button = Kit.button
local tooltip = Kit.tooltip

-- where a window keeps its place and size: DB.frames[key]
local function frameSave(key)
  ns.DB.frames = ns.DB.frames or {}
  ns.DB.frames[key] = ns.DB.frames[key] or {}
  return ns.DB.frames[key]
end
ns.frameSave = frameSave

-- ---------------------------------------------------------------------------------------
-- the Ledger tab: today / 7 days / all time, a 7-day chart, best cities, who owes, then the history

local ledgerFrame
local LEDGER_MAX_ROWS = 50   -- history rows the ledger can show when made tall
local HISTORY_TOP = 252

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

local function signed(c) return (c < 0 and "|cffff4040-" or "|cff40ff40") .. money(math.abs(c)) .. "|r" end

local function tileSub(T)
  return T.casts .. " portals - " .. money(T.tips) .. " tips"
    .. (T.runeCost > 0 and (" - runes " .. money(T.runeCost)) or "")
end

function PP.ledgerRefresh()
  local lf = ledgerFrame
  if not lf or not lf:IsShown() then return end
  local sums = { ledgerSum(dayStart()), ledgerSum(time() - 7 * 86400), ledgerSum(nil) }
  for i, T in ipairs(sums) do lf.tiles[i]:Set(signed(net(T)), tileSub(T)) end

  local days = ns.ledgerDays(7)
  local bars = {}
  for i, d in ipairs(days) do
    bars[i] = { d.income - d.tips, d.tips, i == #days and "Today" or date("%a", d.day) }
  end
  lf.bars:Set(bars)

  local best = ns.bestSellers(3)
  for i = 1, 3 do
    local s = best[i]
    lf.best[i]:SetText(s and (s.label .. "  |cffa0a0a0" .. s.count .. "x|r  |cffffffff" .. money(s.income) .. "|r") or "")
    lf.bestIcons[i]:SetIcon(s and ns.cityIcon and ns.cityIcon(CITY[s.key]) or nil)
    if s then lf.bestIcons[i]:Show() else lf.bestIcons[i]:Hide() end
  end
  local n, c = ns.owing()
  lf.owing:SetText(n > 0 and ("|cffff4040" .. n .. " owe you " .. money(c) .. "|r") or "|cff808080Nobody owes you.|r")
  lf.rune:SetText("Rune of Portals: |cffffffff" .. money(ns.DB.runeCost) .. "|r each  |cff808080(read at the vendor - /pp runecost 18s to set)|r")

  local L = ns.DB.ledger
  local shown = lf.visible or 12
  lf.offset = math.max(0, math.min(lf.offset or 0, #L - shown))
  for i = 1, LEDGER_MAX_ROWS do
    local e = i <= shown and L[#L - lf.offset - i + 1] or nil
    lf.rows[i]:SetText(e and entryText(e) or "")
  end
  lf.empty:SetText(#L == 0 and "Nothing yet - trades, portals and buyers land here." or "")
end

local function buildLedger(lf)
  ledgerFrame = lf
  lf.offset = 0
  lf.tiles = {}
  for i, name in ipairs({ "Today", "7 days", "All time" }) do lf.tiles[i] = Kit.tile(lf, name) end
  lf.bars = Kit.bars(lf, 7)
  lf.bars:SetPoint("TOPLEFT", 4, -60)
  lf.bars:SetPoint("RIGHT", -4, 0)
  lf.bars:SetHeight(82)

  local bestHead = lf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  bestHead:SetPoint("TOPLEFT", 4, -150)
  bestHead:SetText("BEST CITIES")
  lf.owing = lf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  lf.owing:SetPoint("TOPRIGHT", -4, -150)
  lf.best, lf.bestIcons = {}, {}
  for i = 1, 3 do
    local ic = Kit.icon(lf, 16)
    ic:SetPoint("TOPLEFT", 4, -166 - (i - 1) * 18)
    local fs = lf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", ic, "RIGHT", 6, 0)
    fs:SetJustifyH("LEFT")
    lf.bestIcons[i], lf.best[i] = ic, fs
  end
  lf.rune = lf:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  lf.rune:SetPoint("TOPLEFT", 4, -224)

  local head = lf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  head:SetPoint("TOPLEFT", 4, -HISTORY_TOP + 16)
  head:SetText("HISTORY  |cff808080newest first - scroll for more|r")
  local reset = button(lf, 60, 18, "Reset")
  reset:SetPoint("TOPRIGHT", -4, -HISTORY_TOP + 19)
  reset:SetScript("OnClick", function() StaticPopup_Show("PORTALPRO_RESET_LEDGER") end)
  tooltip(reset, "Delete the whole ledger (asks first).")

  lf.rows = {}
  for i = 1, LEDGER_MAX_ROWS do
    local fs = lf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", 4, -HISTORY_TOP - (i - 1) * 16)
    fs:SetPoint("RIGHT", -4, 0)
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
  function lf.onLayout(w, h)
    local tw = math.floor((w - 8 - 2 * 6) / 3)
    for i, t in ipairs(lf.tiles) do
      t:SetWidth(tw)
      t:ClearAllPoints()
      t:SetPoint("TOPLEFT", 4 + (i - 1) * (tw + 6), 0)
    end
    lf.visible = math.max(1, math.min(LEDGER_MAX_ROWS, math.floor((h - HISTORY_TOP) / 16)))
    PP.ledgerRefresh()
  end
end

function PP.resetLedger()
  ns.DB.ledger, ns.DB.totals = {}, newTotals()
  say("Ledger cleared.")
  PP.ledgerRefresh()
  if ns.refresh then ns.refresh() end
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

-- ---------------------------------------------------------------------------------------
-- the Messages tab: the ad and the party thank-you, edited in place.
-- Enter or clicking away saves, Escape puts back what was saved, Default goes back to the standard text.

local function setChecked(cb, v) if cb.SetChecked then cb:SetChecked(v and true or false) end end

-- one editor: label, Default button, the box, a live preview and the tokens it knows
-- each part hangs from the one above, so a preview or tokens line that wraps pushes the rest down.
-- above: the editor before this one (nil for the first)
local function addEditor(parent, above, def)
  local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  if above then label:SetPoint("TOPLEFT", above.tk, "BOTTOMLEFT", -2, -12)
  else label:SetPoint("TOPLEFT", 4, -4) end
  label:SetText(def.label)

  local reset = button(parent, 70, 20, "Default")

  local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  eb:SetHeight(20)
  eb:SetPoint("TOPLEFT", label, "TOPLEFT", 8, -18)
  reset:SetPoint("BOTTOMRIGHT", eb, "TOPRIGHT", 4, 1)
  eb:SetPoint("RIGHT", parent, "RIGHT", -8, 0)
  eb:SetAutoFocus(false)
  eb:SetMaxLetters(255)

  local pv = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  pv:SetPoint("TOPLEFT", label, "TOPLEFT", 2, -42)
  pv:SetPoint("RIGHT", parent, "RIGHT", -6, 0)
  pv:SetJustifyH("LEFT")

  local tk = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  tk:SetPoint("TOPLEFT", pv, "BOTTOMLEFT", 0, -3)
  tk:SetPoint("RIGHT", parent, "RIGHT", -6, 0)
  tk:SetJustifyH("LEFT")
  tk:SetText(def.tokens)

  local ed = { eb = eb, pv = pv, tk = tk, label = label }
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

local function buildMessages(mf)
  local hint = mf:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("BOTTOMRIGHT", -4, 0)
  hint:SetText("Enter saves - Escape undoes")

  mf.ad = addEditor(mf, nil, {
    label = "Trade ad", default = AD_DEFAULT, tokens = AD_TOKENS,
    get = function() return (ns.DB.ad and ns.DB.ad ~= "") and ns.DB.ad or nil end,
    set = function(v) ns.DB.ad = v end,
    preview = function(t) return adText(t ~= "" and t or AD_DEFAULT) end,
  })

  mf.thanks = addEditor(mf, mf.ad, {
    label = "Party thank-you", default = THANKS_DEFAULT, tokens = THANKS_TOKENS
      .. "\n|cff808080A trade that falls short always says how much is missing instead.|r",
    get = function() return ns.DB.thanksText end,
    set = function(v) ns.DB.thanksText = v end,
    preview = function(t) return thanksSample(t ~= "" and t or THANKS_DEFAULT) end,
  })

  local cb = CreateFrame("CheckButton", nil, mf, "UICheckButtonTemplate")
  cb:SetSize(22, 22)
  cb:SetPoint("TOPLEFT", mf.thanks.label, "TOPLEFT", 126, 4)
  local cbText = mf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  cbText:SetPoint("LEFT", cb, "RIGHT", 2, 0)
  cbText:SetText("post it in party after every paid trade")
  cb:SetScript("OnClick", function(self)
    ns.DB.thanks = self:GetChecked() and true or false
  end)
  mf.thanksCheck = cb

  function mf.onLayout() mf.ad.update(); mf.thanks.update() end
  mf:SetScript("OnShow", function(self)
    self.ad.load(); self.thanks.load()
    setChecked(self.thanksCheck, ns.DB.thanks)
  end)
end

ns.buildLedger = buildLedger
ns.buildMessages = buildMessages
