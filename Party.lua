-- PortalPro - the group: finding units, inviting and kicking.
local ADDON, ns = ...
local buyers = ns.buyers
local isSecret = ns.isSecret
local safe = ns.safe
local say = ns.say
local now = ns.now

-- ---------------------------------------------------------------------------------------
-- group

local function surnameSeparator()
  local c = Constants and Constants.CharacterNameSeparatorConsts
  local sep = c and c.CHARACTERNAME_SURNAME_SEPARATOR
  if type(sep) == "string" and sep ~= "" then return sep end
  return " "
end

-- Forever names have a surname: "Nx Thearabian". Chat senders carry the whole name, but UnitName gives other
-- units' two parts separately (the player's own comes whole in the first return) - this puts them together.
local function fullName(unit)
  local ok, first, surname = pcall(UnitName, unit)
  if not ok or isSecret(first) or type(first) ~= "string" or first == "" then return nil end
  if not isSecret(surname) and type(surname) == "string" and surname ~= ""
     and not string.find(first, surname, 1, true) then
    return first .. surnameSeparator() .. surname
  end
  return first
end

local function unitFor(name)
  if not name then return nil end
  local lname = string.lower(name)
  local prefix, n = "party", 4
  if IsInRaid and IsInRaid() then prefix, n = "raid", 40 end
  for i = 1, n do
    local unit = prefix .. i
    local un = fullName(unit)
    if un and string.lower(un) == lname then return unit end
  end
  return nil
end

local function members()
  return safe(GetNumGroupMembers) or 0
end

local function isLeader()
  if not (IsInGroup and IsInGroup()) then return true end
  return safe(UnitIsGroupLeader, "player") == true
end

local function pendingInvites()
  local n, t = 0, now()
  for _, b in pairs(buyers) do
    if b.state == "invited" and t - (b.invitedAt or 0) < 60 then n = n + 1 end
  end
  return n
end

local function freeSlots()
  if IsInRaid and IsInRaid() then return 0 end
  return 5 - math.max(1, members()) - pendingInvites()
end

local function inviteName(b) return b.name end   -- Forever: plain names, no realm

local function invite(b)
  if not isLeader() then b.queued = true; return false end
  if freeSlots() <= 0 then
    if not b.queued then say(b.name .. " waits for a free spot in the group.") end
    b.queued = true
    return false
  end
  local f = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
  pcall(f, inviteName(b))
  b.queued, b.state, b.invitedAt = nil, "invited", now()
  return true
end

local function uninvite(b)
  local f = (C_PartyInfo and C_PartyInfo.UninviteUnit) or UninviteUnit
  pcall(f, inviteName(b))
end

ns.fullName = fullName
ns.unitFor = unitFor
ns.isLeader = isLeader
ns.freeSlots = freeSlots
ns.invite = invite
ns.uninvite = uninvite
