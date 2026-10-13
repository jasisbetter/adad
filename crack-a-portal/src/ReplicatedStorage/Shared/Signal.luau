--!strict
-- Signal: a tiny typed event. Handlers run in the order they were connected, each in its
-- own thread with pcall, so a handler that errors or yields never stops the others.

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	Wait: (self: Signal<T...>) -> T...,
	DisconnectAll: (self: Signal<T...>) -> (),
}

-- Internal shapes (a doubly linked list keeps order and allows disconnect during Fire).
type Node = {
	Connected: boolean,
	_fn: (...any) -> (),
	_signal: Impl?,
	_next: Node?,
	_prev: Node?,
	_once: boolean,
	Disconnect: (self: Node) -> (),
}

type Impl = {
	_head: Node?,
	_tail: Node?,
}

local Signal = {}

local ConnectionMeta = {}
ConnectionMeta.__index = ConnectionMeta

local function unlink(node: Node)
	local signal = node._signal
	if not signal then
		return
	end
	node._signal = nil
	if node._prev then
		(node._prev :: Node)._next = node._next
	else
		signal._head = node._next
	end
	if node._next then
		(node._next :: Node)._prev = node._prev
	else
		signal._tail = node._prev
	end
	-- _next is kept so a Fire walking the list can step past a removed node
end

function ConnectionMeta.Disconnect(self: Node)
	if not self.Connected then
		return
	end
	self.Connected = false
	unlink(self)
end

-- Runs one handler; hoisted so Fire allocates no closures.
local function runHandler(fn: (...any) -> (), ...: any)
	local ok, err = pcall(fn, ...)
	if not ok then
		warn(`[Signal] handler error: {err}`)
	end
end

local SignalMeta = {}
SignalMeta.__index = SignalMeta

local function connect(self: Impl, fn: (...any) -> (), once: boolean): Node
	local node: Node = setmetatable({
		Connected = true,
		_fn = fn,
		_signal = self,
		_next = nil,
		_prev = self._tail,
		_once = once,
	}, ConnectionMeta) :: any
	if self._tail then
		(self._tail :: Node)._next = node
	else
		self._head = node
	end
	self._tail = node
	return node
end

function SignalMeta.Connect(self: Impl, fn: (...any) -> ()): Node
	return connect(self, fn, false)
end

function SignalMeta.Once(self: Impl, fn: (...any) -> ()): Node
	return connect(self, fn, true)
end

function SignalMeta.Fire(self: Impl, ...: any)
	local node = self._head
	while node do
		local nextNode = node._next
		if node.Connected then
			if node._once then
				node.Connected = false
				unlink(node)
			end
			task.spawn(runHandler, node._fn, ...)
		end
		node = nextNode
	end
end

function SignalMeta.Wait(self: Impl): ...any
	local thread = coroutine.running()
	connect(self, function(...: any)
		task.spawn(thread, ...)
	end, true)
	return coroutine.yield()
end

function SignalMeta.DisconnectAll(self: Impl)
	local node = self._head
	while node do
		node.Connected = false
		node._signal = nil
		node = node._next
	end
	self._head = nil
	self._tail = nil
end

function Signal.new<T...>(): Signal<T...>
	local impl: Impl = { _head = nil, _tail = nil }
	return setmetatable(impl, SignalMeta) :: any
end

return Signal
