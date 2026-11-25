-- PortalPro - the ledger: trades, portals cast, and the totals.
local ADDON, ns = ...
local PP = ns.PP
local say = ns.say
local now = ns.now
local money = ns.money
local priceFor = ns.priceFor

-- ---------------------------------------------------------------------------------------
-- ledger: every trade with a buyer, every portal cast (one rune each), every buyer who went through.
-- An entry: { t = time(), k = kind, n = name, c = city key, p = asking price, g = gold, tip, r = rune cost, b = buyers }
--   k = "trade"  - gold a buyer handed over (g), of which tip is above what was still owed
--   k = "cast"   - a portal: one rune at r, b buyers stood at it
--   k = "served" - a buyer went through: asked p, paid g in all (short = p - g when g < p)
-- DB.totals keeps the all-time sums, so trimming old entries loses nothing.

local LEDGER_MAX = 2000
local DEFAULT_RUNE_COST = 2000   -- 20s at the reagent vendor (less with reputation; read from the vendor when you visit one)

local function newTotals()
  return { income = 0, tips = 0, trades = 0, casts = 0, runeCost = 0, served = 0, short = 0, unpaid = 0 }
end

local function addTo(T, e)
  if e.k == "trade" then
    T.income, T.tips, T.trades = T.income + e.g, T.tips + (e.tip or 0), T.trades + 1
  elseif e.k == "cast" then
    T.casts, T.runeCost = T.casts + 1, T.runeCost + e.r
  elseif e.k == "served" then
    T.served = T.served + 1
    if e.g < e.p then
      T.short = T.short + (e.p - e.g)
      if e.g == 0 then T.unpaid = T.unpaid + 1 end
    end
  end
end

local function ledgerAdd(e)
  e.t = e.t or time()
  local L = ns.DB.ledger
  L[#L + 1] = e
  while #L > LEDGER_MAX do table.remove(L, 1) end
  addTo(ns.DB.totals, e)
  if PP.ledgerRefresh then PP.ledgerRefresh() end
end

-- the sums of the entries from `since` on (a time()), or all time
local function ledgerSum(since)
  if not since then return ns.DB.totals end
  local T = newTotals()
  for _, e in ipairs(ns.DB.ledger) do if e.t >= since then addTo(T, e) end end
  return T
end

local function net(T) return T.income - T.runeCost end

-- a buyer paid after going through: their "served" entry gets the gold, and the all-time short with it
local function servedPaidLate(name, got)
  local L = ns.DB.ledger
  for i = #L, 1, -1 do
    local e = L[i]
    if e.k == "served" and e.n == name then
      local T = ns.DB.totals
      if e.g < e.p then
        T.short = T.short - (e.p - e.g)
        if e.g == 0 then T.unpaid = T.unpaid - 1 end
      end
      e.g = e.g + got
      if e.g < e.p then
        T.short = T.short + (e.p - e.g)
        if e.g == 0 then T.unpaid = T.unpaid + 1 end
      end
      return
    end
  end
end

local function dayStart()
  local d = date("*t")
  d.hour, d.min, d.sec = 0, 0, 0
  return time(d)
end

local function markDone(b)
  if b.state == "done" then return end
  b.state, b.doneAt = "done", now()
  local p, g = priceFor(b.city), b.paid or 0
  ledgerAdd({ k = "served", n = b.name, c = b.city, p = p, g = g })
  if g < p then
    say(b.name .. (g == 0 and " went through without paying." or (" went through " .. money(p - g) .. " short.")))
  end
end

-- the last n days, oldest first: { day = start of that day, income, tips }
local function ledgerDays(n)
  local today = dayStart()
  local out = {}
  for i = 1, n do out[i] = { day = today - (n - i) * 86400, income = 0, tips = 0 } end
  local first = out[1].day
  for _, e in ipairs(ns.DB.ledger) do
    if e.k == "trade" and e.t and e.t >= first then
      local d = out[math.min(n, math.floor((e.t - first) / 86400) + 1)]
      d.income = d.income + (e.g or 0)
      d.tips = d.tips + (e.tip or 0)
    end
  end
  return out
end

-- the cities that brought in most (gold traded for them), up to k: { key, label, count, income }
local function bestSellers(k)
  local by, list = {}, {}
  for _, e in ipairs(ns.DB.ledger) do
    if e.k == "trade" and e.c and ns.CITY[e.c] then
      local s = by[e.c]
      if not s then s = { key = e.c, label = ns.CITY[e.c].name, count = 0, income = 0 }; by[e.c] = s; list[#list + 1] = s end
      s.count = s.count + 1
      s.income = s.income + (e.g or 0)
    end
  end
  table.sort(list, function(a, b) if a.income ~= b.income then return a.income > b.income end return a.count > b.count end)
  while #list > k do table.remove(list) end
  return list
end

-- buyers who went through short or unpaid: how many, and how much is missing
local function owing()
  local n, c = 0, 0
  for _, e in ipairs(ns.DB.ledger) do
    if e.k == "served" and e.p and (e.g or 0) < e.p then n, c = n + 1, c + (e.p - (e.g or 0)) end
  end
  return n, c
end

ns.ledgerDays = ledgerDays
ns.bestSellers = bestSellers
ns.owing = owing
ns.DEFAULT_RUNE_COST = DEFAULT_RUNE_COST
ns.newTotals = newTotals
ns.ledgerAdd = ledgerAdd
ns.ledgerSum = ledgerSum
ns.net = net
ns.servedPaidLate = servedPaidLate
ns.dayStart = dayStart
ns.markDone = markDone
