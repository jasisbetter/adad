--!nonstrict
-- Anim: every UI motion in the game goes through here, so timing, interruption and
-- Reduced Motion are handled in one place. (From the roblox-game-ui skill.)
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

local Anim = {}

Anim.T = { -- the game's whole motion vocabulary: never write a one-off TweenInfo
	Fast = TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), -- press, hover
	Pop = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), -- release, badge
	Open = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), -- arriving
	Close = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), -- leaving
	Move = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), -- A to B on screen
	Fade = TweenInfo.new(0.2, Enum.EasingStyle.Linear),
}

Anim.forceReduced = nil -- set true in a Studio test to see the Reduced Motion version
function Anim.reduced(): boolean
	if Anim.forceReduced ~= nil then
		return Anim.forceReduced
	end
	return GuiService.ReducedMotionEnabled
end

-- Movement, size and rotation. Jumps straight to the end under Reduced Motion.
function Anim.tween(obj, info, goal)
	if Anim.reduced() then
		info = TweenInfo.new(0)
		for prop, value in goal do
			obj[prop] = value
		end
	end
	local t = TweenService:Create(obj, info, goal)
	t:Play()
	return t
end

-- Colour and transparency only. These stay on under Reduced Motion.
function Anim.fade(obj, info, goal)
	local t = TweenService:Create(obj, info, goal)
	t:Play()
	return t
end

-- Call at the start of any animation that has more than one step. The function it returns
-- says whether this run is still the newest one for that object: check it after every wait.
local newest = setmetatable({}, { __mode = "k" })
function Anim.claim(obj)
	local id = (newest[obj] or 0) + 1
	newest[obj] = id
	return function(): boolean
		return newest[obj] == id
	end
end

-- Calls step(alpha) now and then every frame while alpha goes 0 to 1 over `seconds`, then
-- done(). step can return false to stop early. Returns a stop function.
function Anim.run(seconds, step, done)
	if seconds <= 0 then
		if step(1) ~= false and done then
			done()
		end
		return function() end
	end
	if step(0) == false then
		return function() end
	end
	local t0 = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		local a = math.min((os.clock() - t0) / seconds, 1)
		if a >= 1 then
			conn:Disconnect()
		end
		if step(a) == false then
			conn:Disconnect()
		elseif a >= 1 and done then
			done()
		end
	end)
	return function()
		conn:Disconnect()
	end
end

local function scaleOf(obj)
	local s = obj:FindFirstChildOfClass("UIScale")
	if not s then
		s = Instance.new("UIScale")
		s.Parent = obj
	end
	return s
end
Anim.scaleOf = scaleOf

-- Scale punch: bigger at once, then it settles. For "value changed" and "reward landed".
function Anim.pop(obj, amount)
	if Anim.reduced() then
		return
	end
	local s = scaleOf(obj)
	s.Scale = 1 + (amount or 0.15)
	Anim.tween(s, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
end

-- Sideways "no" shake that dies away. For can't afford, locked, wrong code.
local home = setmetatable({}, { __mode = "k" })
function Anim.shake(obj, pixels, seconds)
	if Anim.reduced() then
		return
	end
	home[obj] = home[obj] or obj.Position
	local base, alive = home[obj], Anim.claim(obj)
	pixels = pixels or 8
	Anim.run(seconds or 0.3, function(a)
		if not alive() then
			return false
		end
		obj.Position = base + UDim2.fromOffset(math.sin(a * math.pi * 6) * pixels * (1 - a), 0)
		return true
	end, function()
		home[obj] = nil
	end)
end

-- Calls fn(item, i) for each item a moment apart, so a list arrives as a wave.
function Anim.stagger(items, fn, gap)
	gap = if Anim.reduced() then 0 else math.min(gap or 0.03, 0.4 / math.max(#items, 1))
	for i, item in items do
		task.delay((i - 1) * gap, fn, item, i)
	end
end

-- Counts a number label up or down and always lands on the exact value.
function Anim.count(label, from, to, format, seconds)
	local alive = Anim.claim(label)
	format = format or function(n)
		return tostring(math.floor(n + 0.5))
	end
	Anim.run(if Anim.reduced() then 0 else seconds or 0.6, function(a)
		if not alive() then
			return false
		end
		local e = TweenService:GetValue(a, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
		local text = format(if a >= 1 then to else from + (to - from) * e)
		if label.Text ~= text then
			label.Text = text
		end
		return true
	end)
end

-- Flies an icon along a curve between two points (pixels inside the icon's parent).
-- For coins to the counter. done() runs on arrival: bump the counter there.
function Anim.fly(icon, from: Vector2, to: Vector2, seconds, done)
	local side = (if math.random() < 0.5 then 1 else -1) * (0.15 + math.random() * 0.2)
	local mid = (from + to) / 2 + Vector2.new(to.Y - from.Y, from.X - to.X) * side
	Anim.run(if Anim.reduced() then 0 else seconds or 0.6, function(a)
		local e = TweenService:GetValue(a, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local p = from:Lerp(mid, e):Lerp(mid:Lerp(to, e), e)
		icon.Position = UDim2.fromOffset(p.X, p.Y)
		return true
	end, done)
end

-- Hover and drag that never restart: call it again with a new target at any moment.
local springs = {}
function Anim.springTo(uiScale, target, smoothTime)
	if Anim.reduced() then
		uiScale.Scale = target
		return
	end
	local s = springs[uiScale]
	if not s then
		s = { vel = 0 }
		springs[uiScale] = s
	end
	s.target = target
	if s.conn then
		return
	end
	s.conn = RunService.Heartbeat:Connect(function(dt)
		local value
		value, s.vel = TweenService:SmoothDamp(uiScale.Scale, s.target, s.vel, smoothTime or 0.06, nil, dt)
		if math.abs(value - s.target) < 0.002 and math.abs(s.vel) < 0.02 then
			value = s.target
			s.conn:Disconnect()
			springs[uiScale] = nil
		end
		uiScale.Scale = value
	end)
end

-- Window in: grows 0.85 to 1 with a small overshoot while the dim layer fades in.
-- open and close both claim the window. open returns its claim for the steps that follow.
function Anim.open(window, dim)
	local alive = Anim.claim(window)
	local s = scaleOf(window)
	window.Visible = true
	if not Anim.reduced() then
		s.Scale = 0.85
	end
	Anim.tween(s, Anim.T.Open, { Scale = 1 })
	if window:IsA("CanvasGroup") then
		window.GroupTransparency = 1
		Anim.fade(window, Anim.T.Fade, { GroupTransparency = 0 })
	end
	if dim then
		dim.Visible = true
		Anim.fade(dim, Anim.T.Fade, { BackgroundTransparency = 0.45 })
	end
	return alive
end

-- Window out: faster than in. after() runs only if nothing reopened it meanwhile.
function Anim.close(window, dim, after)
	local alive = Anim.claim(window)
	if dim then
		Anim.fade(dim, Anim.T.Close, { BackgroundTransparency = 1 })
	end
	if window:IsA("CanvasGroup") then
		Anim.fade(window, Anim.T.Close, { GroupTransparency = 1 })
	end
	Anim.tween(scaleOf(window), Anim.T.Close, { Scale = 0.9 }).Completed:Connect(function()
		if not alive() then
			return
		end
		window.Visible = false
		if dim then
			dim.Visible = false
		end
		if after then
			after()
		end
	end)
end

-- Attention loop for the ONE claimable thing on screen: a short wiggle, then a long rest.
-- Returns a stop function. Call it when the thing is claimed.
function Anim.nudge(obj, rest)
	local on = true
	task.spawn(function()
		while on and obj.Parent do
			if not Anim.reduced() then
				Anim.pop(obj, 0.1)
				Anim.run(0.5, function(a)
					obj.Rotation = if on then math.sin(a * math.pi * 5) * 7 * (1 - a) else 0
					return on
				end)
			end
			task.wait(0.5 + (rest or 3))
		end
	end)
	return function()
		on = false
	end
end

-- Steady turn for prize rays and spinners. Cancel the tween it returns when the screen closes.
function Anim.spin(obj, secondsPerTurn)
	if Anim.reduced() then
		return nil
	end
	local info = TweenInfo.new(secondsPerTurn or 12, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1)
	local t = TweenService:Create(obj, info, { Rotation = obj.Rotation + 360 })
	t:Play()
	return t
end

return Anim
