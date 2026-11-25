-- Fake WoW API, enough to drive PortalPro through a sale.
T = { time = 1795000000, calls = {}, timers = {}, prints = {} }
local function call(name, ...) T.calls[#T.calls + 1] = { name, ... } end
function T.called(name)
  local out = {}
  for _, c in ipairs(T.calls) do if c[1] == name then out[#out + 1] = c end end
  return out
end

-- frames
local Frame = {}
Frame.__index = function(t, k)
  local v = rawget(Frame, k)
  if v ~= nil then return v end
  return function() return T.stub() end
end
function T.stub() return setmetatable({ scripts = {}, attrs = {}, shown = true, events = {} }, Frame) end
function Frame:SetScript(k, f) self.scripts[k] = f end
function Frame:GetScript(k) return self.scripts[k] end
function Frame:SetAttribute(k, v) self.attrs[k] = v end
function Frame:GetAttribute(k) return self.attrs[k] end
function Frame:Show() local was = self.shown; self.shown = true; if not was and self.scripts.OnShow then self.scripts.OnShow(self) end end
function Frame:Hide() self.shown = false end
function Frame:IsShown() return self.shown end
function Frame:SetText(t) self.text = t end
function Frame:GetText() return self.text end
function Frame:RegisterEvent(e) self.events[e] = true end
function Frame:RegisterUnitEvent(e) self.events[e] = true end
function Frame:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function CreateFrame(kind, name) local f = T.stub(); if name then _G[name] = f end; T.frames = T.frames or {}; T.frames[#T.frames + 1] = f; return f end
UIParent = T.stub()
DEFAULT_CHAT_FRAME = T.stub()
TradeFrame = T.stub(); TradeFrame.shown = false
GameTooltip = T.stub()
BackdropTemplateMixin = {}

-- game state
T.party = {}         -- party1.. names
T.visible = {}       -- [unit] = bool
T.near = {}          -- [unit] = bool
T.tradeMoney = 0
T.npc = nil
T.restricted = true
T.channels = { { 1, "General - Ironforge", 1 }, { 2, "Trade - City", 2 } }

function GetBuildInfo() return "1.16.1", "1", "Nov 2026", 11601 end
function GetTime() return T.time end
function time(tt) if tt then return os.time(tt) end return math.floor(T.time) end
function date(f, ts) return os.date(f, ts or math.floor(T.time)) end
function print(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end T.prints[#T.prints + 1] = table.concat(t, " ") end
function strtrim(s) return (string.gsub(s, "^%s*(.-)%s*$", "%1")) end
C_Timer = {
  After = function(d, f) T.timers[#T.timers + 1] = f end,
  NewTicker = function(d, f) T.tick = f; return {} end,
}
function T.runTimers() local t = T.timers; T.timers = {}; for _, f in ipairs(t) do f() end end
function IsPlayerSpell(id) return id == 11417 or id == 11418 or id == 11420 end
function GetSpellInfo(id)
  local n = { [11417] = "Portal: Orgrimmar", [11418] = "Portal: Undercity", [11420] = "Portal: Thunder Bluff" }
  return n[id]
end
function GetItemCount(id) return id == 17032 and 12 or 0 end
function UnitName(u)
  if u == "player" then return "Mage" end
  if u == "NPC" then return T.npc end
  local i = string.match(u, "^party(%d)$")
  return i and T.party[tonumber(i)] or nil
end
function GetNumGroupMembers() return #T.party > 0 and #T.party + 1 or 0 end
function IsInGroup() return #T.party > 0 end
function IsInRaid() return false end
function UnitIsGroupLeader() return true end
function UnitIsVisible(u) return T.visible[u] ~= false end
function CheckInteractDistance(u, i) return T.near[u] == true end
function InCombatLockdown() return false end
function GetCVarBool() return false end
function GetTargetTradeMoney() return T.tradeMoney end
function InviteUnit(n) call("InviteUnit", n) end
function UninviteUnit(n) call("UninviteUnit", n) end
function InitiateTrade(u) call("InitiateTrade", u) end
function AcceptTrade() call("AcceptTrade") end
function PlaySound(id) call("PlaySound", id) end
function SendChatMessage(text, kind, lang, target) call("SendChatMessage", text, kind, target) end
function ChatFrame_OpenChat(text) call("OpenChat", text) end
function GetChannelName(i)
  local c = T.channels[i]
  if c then return c[1], c[2] end
  return 0, nil
end
C_ChatInfo = {
  AreOutgoingAddonChatMessagesRestricted = function() return T.restricted end,
  GetChannelInfoFromIdentifier = function(name)
    for _, c in ipairs(T.channels) do if c[2] == name then return { zoneChannelID = c[3] } end end
  end,
}
C_Map = { GetBestMapForUnit = function(u) return u == "player" and 1454 or (T.maps and T.maps[u]) or 1454 end }
SlashCmdList = {}
SOUNDKIT = { READY_CHECK = 8960 }
ERR_TRADE_COMPLETE = "Trade complete."
ERR_ALREADY_IN_GROUP_S = "%s is already in a group."
ERR_DECLINE_GROUP_S = "%s declines your group invitation."
ERR_BAD_PLAYER_NAME_S = "Cannot find player '%s'."
ERR_PLAYER_WRONG_FACTION = "Target is unfriendly."

function T.fire(ev, ...)
  for _, f in ipairs(T.frames) do
    local h = f.scripts.OnEvent
    if h and (f.events[ev] or ev == "ADDON_LOADED" or ev == "PLAYER_LOGIN") then h(f, ev, ...) end
  end
end

UISpecialFrames = {}
tinsert = table.insert
T.merchant = {}
function GetMerchantNumItems() return #T.merchant end
function GetMerchantItemLink(i) return T.merchant[i] and T.merchant[i].link end
function GetMerchantItemInfo(i) local m = T.merchant[i]; return "Rune of Portals", 1, m.price, m.qty end

StaticPopupDialogs = {}
function StaticPopup_Show(which) T.popup = which end

T.class = T.class or "MAGE"
function UnitClass(u) return (T.class == "MAGE" and "Mage" or "Warrior"), T.class, 1 end
function Frame:UnregisterAllEvents() self.events = {} end

function Frame:SetChecked(v) self.checked = v end
function Frame:GetChecked() return self.checked end

-- Forever: other units give first name and surname apart
local function split(n) if not n then return nil end local a, b = string.match(n, "^(%S+) (.+)$"); if a then return a, b end; return n end
function UnitName(u)
  if u == "player" then return "Mage" end
  if u == "NPC" then return split(T.npc) end
  local i = string.match(u, "^party(%d)$")
  return split(i and T.party[tonumber(i)] or nil)
end

function Frame:SetSize(w, h)
  self.w, self.h = w, h
  if self.scripts.OnSizeChanged then self.scripts.OnSizeChanged(self, w, h) end
end
function Frame:GetSize() return self.w or 100, self.h or 100 end
function Frame:SetWidth(w) self.w = w end
function Frame:SetHeight(h) self.h = h end
function Frame:GetWidth() return self.w or 100 end
function Frame:GetHeight() return self.h or 100 end
function Frame:GetFrameLevel() return 1 end
function Frame:StartSizing() T.sizing = self end
T.combat = false
function InCombatLockdown() return T.combat end
