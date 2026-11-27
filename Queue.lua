-- PortalPro - the queue: every buyer you can port gets a number when first listed, and keeps it. Waiting
-- orders stay until they went through, are removed, or are quiet for 2 hours, and they're saved through a
-- reload or restart.
local ADDON, ns = ...
local buyers = ns.buyers
local now = ns.now

local QUIET = 7200   -- a waiting order with no word from the buyer for this long is dropped

-- live fields: worked out again after a load, never saved
local LIVE = { unit = true, nearAtCast = true, kickAt = true, new = true, joinedAt = true, tradeTry = true,
  tradeTries = true, queued = true, doneAt = true }
-- times kept as GetTime(): saved as wall-clock, since GetTime() starts over with the client
local TIMES = { at = true, since = true, invitedAt = true, declinedAt = true }

local function enqueue(b)
  if not b or b.n or b.cantPort then return end
  b.n = ns.DB.nextOrder or 1
  ns.DB.nextOrder = b.n + 1
  b.since = now()
end

local function isWaiting(b)
  return b.n ~= nil and b.state ~= "done" and not b.cantPort
end

local function waitingList()
  local list = {}
  for _, b in pairs(buyers) do if isWaiting(b) then list[#list + 1] = b end end
  table.sort(list, function(a, b) return a.n < b.n end)
  return list
end

-- 1 for the next in line
local function place(b)
  if not isWaiting(b) then return nil end
  local p = 1
  for _, o in pairs(buyers) do if o ~= b and isWaiting(o) and o.n < b.n then p = p + 1 end end
  return p
end

-- waiting by number, then just ported (newest first), then those you can't port (newest first)
local function queueList()
  local list = waitingList()
  local done, rest = {}, {}
  for _, b in pairs(buyers) do
    if not isWaiting(b) then
      if b.state == "done" then done[#done + 1] = b else rest[#rest + 1] = b end
    end
  end
  table.sort(done, function(a, b) return (a.doneAt or 0) > (b.doneAt or 0) end)
  table.sort(rest, function(a, b) return (a.at or 0) > (b.at or 0) end)
  for _, b in ipairs(done) do list[#list + 1] = b end
  for _, b in ipairs(rest) do list[#list + 1] = b end
  return list
end

-- quiet for 2 hours - never while you hold their gold
local function quiet(b, t)
  if not isWaiting(b) or b.state == "paid" or (b.paid or 0) > 0 then return false end
  return t - (b.at or t) > QUIET
end

-- PLAYER_LOGOUT (a reload too): the waiting orders, per character
local function saveQueue()
  if not ns.DB or not ns.myName or ns.myName == "" then return end
  local t, wall = now(), time()
  local list = {}
  for _, b in ipairs(waitingList()) do
    local c = {}
    for k, v in pairs(b) do
      if not LIVE[k] and type(v) ~= "table" and type(v) ~= "function" then
        if TIMES[k] and type(v) == "number" then c[k] = wall - (t - v) else c[k] = v end
      end
    end
    -- what they wrote (wall-clock times already), for the row's tooltip
    if type(b.said) == "table" then
      c.said = {}
      for i, m in ipairs(b.said) do
        c.said[i] = { text = m.text, where = m.where, when = m.when, got = m.got, miss = m.miss }
      end
    end
    list[#list + 1] = c
  end
  ns.DB.queues = ns.DB.queues or {}
  ns.DB.queues[ns.myName] = { saved = wall, list = list }
end

-- at start-up: the saved orders back into the list (once; the save is cleared). Who is in the group comes
-- from the group itself (ns.onRoster).
local function loadQueue()
  local all = ns.DB and ns.DB.queues
  local q = all and ns.myName and all[ns.myName]
  if not q then return end
  all[ns.myName] = nil
  local t, wall = now(), time()
  for _, c in ipairs(q.list or {}) do
    if type(c) == "table" and c.key and c.n and not buyers[c.key] then
      for k in pairs(TIMES) do
        if type(c[k]) == "number" then c[k] = t - (wall - c[k]) end
      end
      if t - (c.at or t) <= QUIET then buyers[c.key] = c end
    end
  end
  if ns.onRoster then ns.onRoster() end
end

ns.enqueue = enqueue
ns.isWaiting = isWaiting
ns.place = place
ns.queueList = queueList
ns.quiet = quiet
ns.saveQueue = saveQueue
ns.loadQueue = loadQueue
