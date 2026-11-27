-- Shared widget kit: Blizzard-style windows, tabs, rows, tiles, bars and steps.
-- The same file is in EnchantPro and PortalPro: change both copies together (a test checks they match).
-- It knows nothing about either addon: callers hand in the table where a window keeps its place and size.
local ADDON, ns = ...

local Kit = { VERSION = 1 }
ns.Kit = Kit

local GOLD = { 1, 0.82, 0 }
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

-- CreateFrame with the first template this client has; nil template = plain frame
local function create(kind, name, parent, templates)
  for _, t in ipairs(templates) do
    local ok, f = pcall(CreateFrame, kind, name, parent, t)
    if ok and f then return f, t end
  end
  return CreateFrame(kind, name, parent), nil
end
Kit.create = create

function Kit.backdrop(f, alpha, gold)
  if not f.SetBackdrop then return end
  if gold then
    f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32,
      insets = { left = 11, right = 12, top = 12, bottom = 11 } })
  else
    f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 14,
      insets = { left = 4, right = 4, top = 4, bottom = 4 } })
  end
  f:SetBackdropColor(0, 0, 0, alpha or 0.9)
end

function Kit.button(parent, w, h, text, template)
  local b = CreateFrame("Button", nil, parent, template or "UIPanelButtonTemplate")
  b:SetSize(w, h)
  b:SetText(text)
  return b
end

function Kit.tooltip(widget, text)
  widget:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(type(text) == "function" and text(self) or text, 1, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- A buyer's last lines, kept for their row's tooltip: b.said = { { text, where, when = time(), got, miss } },
-- oldest first. got: what the line was read as; miss: something named that you can't do.
function Kit.noteSaid(b, text, where, got, miss)
  b.said = b.said or {}
  table.insert(b.said, { text = text, where = where, when = time(), got = got, miss = miss })
  while #b.said > 5 do table.remove(b.said, 1) end
end

-- the tooltip: what they wrote and what each line was read as, then how to remove or block them
function Kit.saidTip(b)
  local lines = { "|cffffd100" .. (b.name or "?") .. ((type(b.said) == "table" and #b.said > 0) and " wrote:|r" or "|r") }
  for _, m in ipairs(type(b.said) == "table" and b.said or {}) do
    local secs = math.max(0, time() - (m.when or time()))
    local ago = secs < 60 and "now" or secs < 3600 and (math.floor(secs / 60) .. "m") or (math.floor(secs / 3600) .. "h")
    local w = string.match(m.where or "", "^(.-)%s+%-%s+") or m.where or ""
    lines[#lines + 1] = "|cff808080[" .. w .. ", " .. ago .. "]|r " .. tostring(m.text or "")
      .. (m.got and ("  |cff40ff40-> " .. m.got .. "|r")
        or m.miss and ("  |cffff4040-> " .. m.miss .. " (you can't)|r")
        or "  |cff808080-> nothing named|r")
  end
  lines[#lines + 1] = "|cff808080Right-click: remove.  Shift-right-click: block - never listed again.|r"
  return table.concat(lines, "\n")
end

function Kit.toggleShown(f) if f then if f:IsShown() then f:Hide() else f:Show() end end end

-- an on/off button: green label when on, grey when off. get() reads the setting, set(v) stores it.
function Kit.toggle(parent, w, h, text, get, set)
  local b = Kit.button(parent, w, h, text)
  function b:Refresh() self:SetText((get() and "|cff40ff40" or "|cff808080") .. text .. "|r") end
  b:SetScript("OnClick", function(self) set(not get()); self:Refresh() end)
  b:Refresh()
  return b
end

-- the window keeps its place in saved.point
function Kit.keepPlace(frame, saved, default)
  frame:ClearAllPoints()
  local p = saved.point
  if p then frame:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else frame:SetPoint(unpack(default)) end
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local a, _, rp, x, y = self:GetPoint()
    saved.point = { a, rp, x, y }
  end)
end

-- resized by the grip in the bottom-right corner; size kept in saved.w / saved.h.
-- secure: the frame holds secure buttons, so it can't be resized in combat.
function Kit.makeResizable(frame, saved, minW, minH, maxW, maxH, onSize, secure)
  frame:SetResizable(true)
  if frame.SetResizeBounds then
    frame:SetResizeBounds(minW, minH, maxW, maxH)
  else
    if frame.SetMinResize then frame:SetMinResize(minW, minH) end
    if frame.SetMaxResize then frame:SetMaxResize(maxW, maxH) end
  end
  if saved.w and saved.h then
    frame:SetSize(math.max(minW, math.min(maxW, saved.w)), math.max(minH, math.min(maxH, saved.h)))
  end
  local grip = CreateFrame("Button", nil, frame)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -3, 3)
  grip:SetFrameLevel(frame:GetFrameLevel() + 10)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function(_, mouse)
    if mouse ~= "LeftButton" then return end
    if secure and InCombatLockdown() then
      if UIErrorsFrame then UIErrorsFrame:AddMessage("Can't resize that in combat.", 1, 0.1, 0.1) end
      return
    end
    frame.sizing = true
    frame:StartSizing("BOTTOMRIGHT")
  end)
  grip:SetScript("OnMouseUp", function()
    if not frame.sizing then return end
    frame.sizing = nil
    frame:StopMovingOrSizing()
    local w, h = frame:GetSize()
    saved.w, saved.h = math.floor(w + 0.5), math.floor(h + 0.5)
  end)
  frame.grip = grip
  frame:SetScript("OnSizeChanged", function(_, w, h) onSize(w, h) end)
  onSize(frame:GetSize())
end

function Kit.setPortrait(frame, icon)
  if not frame.portrait then return end
  if SetPortraitToTexture then SetPortraitToTexture(frame.portrait, icon) else frame.portrait:SetTexture(icon) end
end

-- A Blizzard window: gold frame, round portrait top-left, title, close button. frame.content is the area to fill.
-- Uses ButtonFrameTemplate / PortraitFrameTemplate where the client has them, else a gold dialog border.
function Kit.window(name, title, icon, w, h, saved)
  local f, t = create("Frame", name, UIParent, { "ButtonFrameTemplate", "PortraitFrameTemplate" })
  if not t then
    f = CreateFrame("Frame", name, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    Kit.backdrop(f, 0.95, true)
    f.portrait = f:CreateTexture(nil, "OVERLAY")
    f.portrait:SetSize(58, 58)
    f.portrait:SetPoint("TOPLEFT", -6, 8)
    local ring = f:CreateTexture(nil, "OVERLAY", nil, 1)
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    ring:SetSize(100, 100)
    ring:SetPoint("TOPLEFT", f.portrait, "TOPLEFT", -6, 6)
    f.titleText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.titleText:SetPoint("TOP", 0, -16)
    f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.close:SetPoint("TOPRIGHT", -4, -4)
  else
    -- the template's parts, read raw: a part this client's template lacks is nil, and gets made here
    local pc, tc = rawget(f, "PortraitContainer"), rawget(f, "TitleContainer")
    local portrait = rawget(f, "portrait") or (pc and rawget(pc, "portrait"))
    local title = rawget(f, "TitleText") or (tc and rawget(tc, "TitleText"))
    local close = rawget(f, "CloseButton")
    if not close then
      close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
      close:SetPoint("TOPRIGHT", -4, -4)
    end
    if not title then
      title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      title:SetPoint("TOP", 0, -6)
    end
    f.portrait, f.titleText, f.close = portrait, title, close
    if t == "ButtonFrameTemplate" and ButtonFrameTemplate_HideButtonBar then pcall(ButtonFrameTemplate_HideButtonBar, f) end
  end
  f:SetSize(w, h)
  f:SetFrameStrata("MEDIUM")
  f:SetToplevel(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) if not InCombatLockdown() then self:StartMoving() end end)
  Kit.keepPlace(f, saved, { "CENTER", UIParent, "CENTER", 0, 0 })
  if f.titleText then f.titleText:SetText(title) end
  Kit.setPortrait(f, icon)
  f.content = CreateFrame("Frame", nil, f)
  if rawget(f, "Inset") and t then
    f.content:SetPoint("TOPLEFT", f.Inset, "TOPLEFT", 6, -6)
    f.content:SetPoint("BOTTOMRIGHT", f.Inset, "BOTTOMRIGHT", -6, 6)
  else
    f.content:SetPoint("TOPLEFT", 14, -62)
    f.content:SetPoint("BOTTOMRIGHT", -14, 14)
  end
  return f
end

-- Tabs along the bottom edge, one page (a frame filling frame.content) per tab.
-- names: optional global names for the pages.
-- onBlocked(i): a tab clicked in combat calls this instead of switching (for pages that hold secure buttons).
function Kit.tabs(frame, labels, onSelect, names, onBlocked)
  local tabs = { buttons = {}, pages = {}, current = nil }
  local base = (frame.GetName and frame:GetName()) or "KitWindow"
  local prev
  for i, label in ipairs(labels) do
    local b, t = create("Button", base .. "Tab" .. i, frame, { "CharacterFrameTabButtonTemplate", "PanelTabButtonTemplate" })
    if not t then
      b = Kit.button(frame, 80, 22, label)
    end
    b:SetText(label)
    b:SetID(i)
    if t and PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, b, 0) end
    if prev then
      b:SetPoint("LEFT", prev, "RIGHT", t and -16 or 2, 0)
    else
      b:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 12, t and 2 or -2)
    end
    b:SetScript("OnClick", function()
      if onBlocked and InCombatLockdown() then onBlocked(i); return end
      tabs:Select(i)
    end)
    tabs.buttons[i] = b
    local page = CreateFrame("Frame", names and names[i] or nil, frame.content)
    page:SetAllPoints(frame.content)
    page:Hide()
    tabs.pages[i] = page
    prev = b
  end
  frame.Tabs = tabs.buttons
  frame.numTabs = #labels
  if PanelTemplates_SetNumTabs then pcall(PanelTemplates_SetNumTabs, frame, #labels) end

  function tabs:Select(i)
    for k, page in ipairs(self.pages) do
      if k == i then page:Show() else page:Hide() end
      local b = self.buttons[k]
      if b.LockHighlight then if k == i then b:LockHighlight() else b:UnlockHighlight() end end
    end
    self.current = i
    if PanelTemplates_SetTab then pcall(PanelTemplates_SetTab, frame, i) end
    if onSelect then onSelect(i) end
  end
  return tabs
end

-- a square icon with a dark edge; SetIcon(nil) shows the question mark
function Kit.icon(parent, size)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(size, size)
  f.edge = f:CreateTexture(nil, "BACKGROUND")
  f.edge:SetAllPoints()
  f.edge:SetColorTexture(0, 0, 0, 1)
  f.tex = f:CreateTexture(nil, "ARTWORK")
  f.tex:SetPoint("TOPLEFT", 1, -1)
  f.tex:SetPoint("BOTTOMRIGHT", -1, 1)
  f.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  function f:SetIcon(tex)
    self.icon = tex or QUESTION
    self.tex:SetTexture(self.icon)
  end
  f:SetIcon(nil)
  return f
end

-- a list row: in-range dot, icon, name with a small line under it, text on the right
function Kit.row(parent, h)
  local r = CreateFrame("Button", nil, parent)
  r:SetHeight(h)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  r.dot = r:CreateTexture(nil, "ARTWORK")
  r.dot:SetSize(7, 7)
  r.dot:SetPoint("LEFT", 2, 0)
  r.icon = Kit.icon(r, h - 4)
  r.icon:SetPoint("LEFT", 13, 0)
  r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 6, 1)
  r.name:SetJustifyH("LEFT")
  r.sub = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  r.sub:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 6, -1)
  r.sub:SetJustifyH("LEFT")
  r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.right:SetPoint("RIGHT", -4, 0)
  r.right:SetJustifyH("RIGHT")
  function r:SetNear(near)
    self.near = near and true or false
    if near then self.dot:SetColorTexture(0.25, 1, 0.25, 1) else self.dot:SetColorTexture(0.4, 0.4, 0.4, 1) end
  end
  r:SetNear(false)
  -- a soft gold band: "this one next"
  r.mark = r:CreateTexture(nil, "BACKGROUND")
  r.mark:SetAllPoints()
  r.mark:SetColorTexture(1, 0.82, 0, 0.12)
  function r:SetMark(on)
    self.marked = on and true or false
    if on then self.mark:Show() else self.mark:Hide() end
  end
  r:SetMark(false)
  return r
end

-- mouse-wheel scrolling for a list of rows drawn by the caller: sc.offset is the first item shown (0-based).
-- sc:Set(total, visible) keeps the offset in range and fills sc.text ("2 more above / 5 more below");
-- the wheel moves one row and calls onScroll().
function Kit.scroller(parent, onScroll)
  local sc = { offset = 0, total = 0, visible = 0 }
  sc.text = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  function sc:Set(total, visible)
    self.total, self.visible = total, visible
    local max = math.max(0, total - visible)
    self.offset = math.max(0, math.min(self.offset, max))
    local above, below = self.offset, math.max(0, total - visible - self.offset)
    local parts = {}
    if above > 0 then parts[#parts + 1] = "|TInterface\\Buttons\\Arrow-Up-Up:12|t " .. above .. " more" end
    if below > 0 then parts[#parts + 1] = below .. " more |TInterface\\Buttons\\Arrow-Down-Up:12|t" end
    self.text:SetText(table.concat(parts, "    "))
  end
  parent:EnableMouseWheel(true)
  parent:SetScript("OnMouseWheel", function(_, delta)
    local max = math.max(0, sc.total - sc.visible)
    local o = math.max(0, math.min(max, sc.offset - (delta > 0 and 1 or -1)))
    if o ~= sc.offset then
      sc.offset = o
      if onScroll then onScroll() end
    end
  end)
  return sc
end

-- a number with a label over it and a small line under it
function Kit.tile(parent, label)
  local t = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  Kit.backdrop(t, 0.5)
  t:SetHeight(52)
  t.label = t:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  t.label:SetPoint("TOPLEFT", 8, -7)
  t.label:SetText(label)
  t.value = t:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  t.value:SetPoint("TOPLEFT", 8, -20)
  t.sub = t:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  t.sub:SetPoint("TOPLEFT", 8, -38)
  t.sub:SetPoint("RIGHT", -6, 0)
  t.sub:SetJustifyH("LEFT")
  function t:Set(value, sub)
    self.value:SetText(value)
    self.sub:SetText(sub or "")
  end
  return t
end

-- n stacked bars side by side: Set({ { main, extra, label }, ... }), heights relative to the biggest
function Kit.bars(parent, n)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(90)
  f.items = {}
  for i = 1, n do
    local it = {}
    it.main = f:CreateTexture(nil, "ARTWORK")
    it.main:SetColorTexture(GOLD[1] * 0.75, GOLD[2] * 0.75, 0, 0.9)
    it.extra = f:CreateTexture(nil, "ARTWORK")
    it.extra:SetColorTexture(GOLD[1], GOLD[2] + 0.1, 0.4, 1)
    it.label = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    it.frac = 0
    f.items[i] = it
  end
  function f:Layout()
    local w = self:GetWidth()
    local bw = math.max(4, (w - (n - 1) * 6) / n)
    for i, it in ipairs(self.items) do
      local x = (i - 1) * (bw + 6)
      it.main:ClearAllPoints()
      it.main:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", x, 14)
      it.main:SetWidth(bw)
      it.extra:ClearAllPoints()
      it.extra:SetPoint("BOTTOMLEFT", it.main, "TOPLEFT", 0, 0)
      it.extra:SetWidth(bw)
      it.label:ClearAllPoints()
      it.label:SetPoint("BOTTOM", self, "BOTTOMLEFT", x + bw / 2, 0)
    end
  end
  function f:Set(list)
    local top = 0
    for i = 1, n do
      local v = list[i]
      if v then top = math.max(top, (v[1] or 0) + (v[2] or 0)) end
    end
    local H = math.max(1, self:GetHeight() - 16)
    for i, it in ipairs(self.items) do
      local v = list[i] or {}
      local a, b = v[1] or 0, v[2] or 0
      it.frac = top > 0 and (a + b) / top or 0
      if a > 0 then it.main:SetHeight(H * a / top); it.main:Show() else it.main:SetHeight(0.01); it.main:Hide() end
      if b > 0 then it.extra:SetHeight(H * b / top); it.extra:Show() else it.extra:Hide() end
      it.label:SetText(v[3] or "")
    end
    self:Layout()
  end
  f:SetScript("OnSizeChanged", function(self) self:Layout() end)
  return f
end

-- a thin bar filled to frac (0..1)
function Kit.progress(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(10)
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints()
  f.bg:SetColorTexture(0.15, 0.15, 0.15, 0.9)
  f.fill = f:CreateTexture(nil, "ARTWORK")
  f.fill:SetPoint("TOPLEFT")
  f.fill:SetPoint("BOTTOMLEFT")
  f.frac = 0
  function f:Set(frac, r, g, b)
    frac = math.max(0, math.min(1, tonumber(frac) or 0))
    self.frac = frac
    self.fill:SetColorTexture(r or 0.25, g or 0.85, b or 0.25, 1)
    self.fill:SetWidth(math.max(0.01, self:GetWidth() * frac))
    if frac > 0 then self.fill:Show() else self.fill:Hide() end
  end
  f:SetScript("OnSizeChanged", function(self) self:Set(self.frac) end)
  return f
end

-- numbered steps joined by lines: Set(done, current) - done ones get a tick, the current one glows.
-- done: how many from the first are done, or a list of true/false per step
function Kit.steps(parent, labels)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(34)
  f.nodes = {}
  local n = #labels
  for i, label in ipairs(labels) do
    local node = {}
    node.circle = f:CreateTexture(nil, "ARTWORK")
    node.circle:SetSize(18, 18)
    node.num = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    node.num:SetPoint("CENTER", node.circle, "CENTER", 0, 0)
    node.label = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    node.label:SetPoint("TOP", node.circle, "BOTTOM", 0, -1)
    node.label:SetText(label)
    if i > 1 then
      node.line = f:CreateTexture(nil, "BACKGROUND")
      node.line:SetHeight(2)
    end
    f.nodes[i] = node
  end
  function f:Layout()
    local w = self:GetWidth()
    local step = n > 1 and (w - 30) / (n - 1) or 0
    for i, node in ipairs(self.nodes) do
      node.circle:ClearAllPoints()
      node.circle:SetPoint("TOPLEFT", self, "TOPLEFT", 6 + (i - 1) * step, 0)
      if node.line then
        node.line:ClearAllPoints()
        node.line:SetPoint("LEFT", self.nodes[i - 1].circle, "RIGHT", 1, 0)
        node.line:SetPoint("RIGHT", node.circle, "LEFT", -1, 0)
      end
    end
  end
  function f:Set(done, current)
    self.done, self.current = done, current
    for i, node in ipairs(self.nodes) do
      local isDone
      if type(done) == "table" then isDone = done[i] and true or false else isDone = i <= done end
      node.done = isDone
      if isDone then
        node.circle:SetColorTexture(0.2, 0.55, 0.2, 1)
        node.num:SetText("|cffffffff+|r")
        node.label:SetTextColor(0.6, 0.9, 0.6)
      elseif i == current then
        node.circle:SetColorTexture(GOLD[1], GOLD[2], 0, 1)
        node.num:SetText("|cff000000" .. i .. "|r")
        node.label:SetTextColor(GOLD[1], GOLD[2], 0)
      else
        node.circle:SetColorTexture(0.25, 0.25, 0.25, 1)
        node.num:SetText("|cffaaaaaa" .. i .. "|r")
        node.label:SetTextColor(0.5, 0.5, 0.5)
      end
      if node.line then
        if isDone then node.line:SetColorTexture(0.3, 0.8, 0.3, 1) else node.line:SetColorTexture(0.3, 0.3, 0.3, 1) end
      end
    end
  end
  f:SetScript("OnSizeChanged", function(self) self:Layout() end)
  f:Set(0, 1)
  return f
end

-- a slow glow, for the button to press next
function Kit.pulse(frame, on)
  if not rawget(frame, "kitPulse") then
    local ag = frame:CreateAnimationGroup()
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.5)
    a:SetDuration(0.7)
    ag:SetLooping("BOUNCE")
    frame.kitPulse = ag
  end
  frame.pulsing = on and true or false
  if on then frame.kitPulse:Play() else frame.kitPulse:Stop(); frame:SetAlpha(1) end
end

-- "rrggbb" of a class colour (class file such as "MAGE"); white when unknown
function Kit.classHex(classFile)
  local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
  if not c then return "ffffff" end
  if type(c.colorStr) == "string" and #c.colorStr == 8 then return string.lower(string.sub(c.colorStr, 3)) end
  return string.format("%02x%02x%02x", math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5))
end

-- a round minimap button with a red count badge. saved keeps .minimapAngle (degrees) and .minimapHidden.
-- onClick(mouse) gets "LeftButton" / "RightButton"; tip() returns the tooltip text.
-- angle: where it starts (degrees), so two addons' buttons don't sit on each other.
function Kit.minimapButton(name, icon, saved, onClick, tip, angle)
  if saved.minimapAngle == nil then saved.minimapAngle = angle or 200 end
  local mm = CreateFrame("Button", name, Minimap)
  mm:SetSize(31, 31)
  mm:SetFrameStrata("MEDIUM")
  mm:SetFrameLevel(8)
  mm:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  mm:RegisterForDrag("LeftButton")
  mm:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  local bg = mm:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetSize(20, 20)
  bg:SetPoint("TOPLEFT", 7, -5)
  local tex = mm:CreateTexture(nil, "ARTWORK")
  tex:SetTexture(icon)
  tex:SetSize(17, 17)
  tex:SetPoint("TOPLEFT", 7, -6)
  local border = mm:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")

  mm.badge = CreateFrame("Frame", nil, mm)
  mm.badge:SetSize(16, 14)
  mm.badge:SetPoint("TOPRIGHT", 4, 2)
  local bbg = mm.badge:CreateTexture(nil, "ARTWORK")
  bbg:SetAllPoints()
  bbg:SetColorTexture(0.8, 0.05, 0.05, 1)
  mm.badge.text = mm.badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  mm.badge.text:SetPoint("CENTER", 0, 0)
  mm.badge:Hide()

  function mm:Place()
    local a = math.rad(saved.minimapAngle)
    self:ClearAllPoints()
    self:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * 80, math.sin(a) * 80)
  end
  function mm:SetBadge(n)
    if n and n > 0 then self.badge.text:SetText(tostring(n)); self.badge:Show() else self.badge:Hide() end
  end
  function mm:SetHidden(hidden)
    saved.minimapHidden = hidden and true or false
    if hidden then self:Hide() else self:Show() end
  end
  mm:SetScript("OnClick", function(_, mouse) onClick(mouse) end)
  mm:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function(me)
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local s = Minimap:GetEffectiveScale()
      saved.minimapAngle = math.deg(math.atan2(cy / s - my, cx / s - mx))
      me:Place()
    end)
  end)
  mm:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  if tip then Kit.tooltip(mm, tip) end
  mm:Place()
  if saved.minimapHidden then mm:Hide() end
  return mm
end

-- a one-line bar: icon, a line of text (bar.text), a button (bar.button) and "+" (expand). Kept in place by saved;
-- y: how far below the top of the screen it starts.
function Kit.compactBar(name, icon, saved, buttonText, onButton, onExpand, y)
  local bar = CreateFrame("Frame", name, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  bar:SetSize(300, 34)
  bar:SetFrameStrata("MEDIUM")
  Kit.backdrop(bar, 0.9)
  bar:SetMovable(true)
  bar:SetClampedToScreen(true)
  bar:EnableMouse(true)
  bar:RegisterForDrag("LeftButton")
  bar:SetScript("OnDragStart", bar.StartMoving)
  Kit.keepPlace(bar, saved, { "TOP", UIParent, "TOP", 0, y or -80 })
  local ic = Kit.icon(bar, 22)
  ic:SetPoint("LEFT", 6, 0)
  ic:SetIcon(icon)
  bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  bar.text:SetPoint("LEFT", ic, "RIGHT", 6, 0)
  local expand = Kit.button(bar, 24, 22, "+")
  expand:SetPoint("RIGHT", -6, 0)
  expand:SetScript("OnClick", function() onExpand() end)
  Kit.tooltip(expand, "Back to the full window.")
  bar.expand = expand
  bar.button = Kit.button(bar, 70, 22, buttonText)
  bar.button:SetPoint("RIGHT", expand, "LEFT", -2, 0)
  bar.button:SetScript("OnClick", function() onButton() end)
  bar:Hide()
  return bar
end

-- a pop-up near the top of the screen that hides itself after `seconds`; clicking it calls onClick.
-- toast:Pop(key, icon, who, what) shows it; toast.key is the last one popped.
function Kit.toast(name, seconds, onClick)
  local toast = CreateFrame("Frame", name, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  toast:SetSize(280, 48)
  toast:SetPoint("TOP", UIParent, "TOP", 0, -140)
  toast:SetFrameStrata("HIGH")
  Kit.backdrop(toast, 0.92)
  toast.icon = Kit.icon(toast, 32)
  toast.icon:SetPoint("LEFT", 8, 0)
  toast.who = toast:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  toast.who:SetPoint("TOPLEFT", toast.icon, "TOPRIGHT", 8, 0)
  toast.who:SetPoint("RIGHT", -8, 0)
  toast.who:SetJustifyH("LEFT")
  toast.what = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  toast.what:SetPoint("BOTTOMLEFT", toast.icon, "BOTTOMRIGHT", 8, 0)
  toast.what:SetPoint("RIGHT", -8, 0)
  toast.what:SetJustifyH("LEFT")
  toast:EnableMouse(true)
  toast:SetScript("OnMouseUp", function(self) self:Hide(); if onClick then onClick(self.key) end end)
  function toast:Pop(key, icon, who, what)
    self.key = key
    self.icon:SetIcon(icon)
    self.who:SetText(who)
    self.what:SetText(what)
    self:Show()
    local token = {}
    self.token = token
    C_Timer.After(seconds, function() if self.token == token then self:Hide() end end)
  end
  toast:Hide()
  return toast
end
