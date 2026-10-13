--!strict
-- Receipts: processed purchase receipt ids kept in the saved profile, so ProcessReceipt is
-- idempotent (a purchase is never granted twice). Pure: no services.

local Receipts = {}

Receipts.MAX = 100

export type Holder = { receipts: { [string]: number } }

export type ApplyResult = "granted" | "already" | "failed"

function Receipts.has(profile: Holder, id: string): boolean
	return profile.receipts ~= nil and profile.receipts[id] ~= nil
end

-- Keeps only the newest `max` entries (by time; ties broken by id so the result is stable).
function Receipts.trim(receipts: { [string]: number }, max: number?)
	local limit = max or Receipts.MAX
	local count = 0
	for _ in receipts do
		count += 1
	end
	if count <= limit then
		return
	end
	local list: { { id: string, at: number } } = {}
	for id, at in receipts do
		table.insert(list, { id = id, at = at })
	end
	table.sort(list, function(a, b)
		if a.at ~= b.at then
			return a.at > b.at
		end
		return a.id > b.id
	end)
	for i = limit + 1, #list do
		receipts[list[i].id] = nil
	end
end

function Receipts.record(profile: Holder, id: string, now: number)
	if profile.receipts == nil then
		profile.receipts = {}
	end
	profile.receipts[id] = now
	Receipts.trim(profile.receipts)
end

-- Runs grant() once per receipt id. "already" = recorded before (grant not run);
-- "failed" = grant returned false or errored (not recorded, Roblox retries later).
function Receipts.apply(profile: Holder, id: string, now: number, grant: () -> boolean): ApplyResult
	if Receipts.has(profile, id) then
		return "already"
	end
	local ok, granted = pcall(grant)
	if not ok then
		warn(`[Receipts] grant for {id} errored: {granted}`)
		return "failed"
	end
	if granted ~= true then
		return "failed"
	end
	Receipts.record(profile, id, now)
	return "granted"
end

return Receipts
