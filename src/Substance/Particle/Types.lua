-- Substance
-- Particle/Types.lua
-- Plinko Labs

export type EventType = "Lazy" | "Strict" | "Solve"
export type Authority = "Server" | "Client"

export type Shape = {[string]: any}
export type Constraints = {[string]: (any) -> boolean}

export type Subscription = {
	Cancel: (self: Subscription) -> (),
}

export type AtomHandle = {
	Name: string,
	Shape: Shape?,
	Isotope: (self: AtomHandle, constraints: Constraints) -> AtomHandle,
	Compose: (self: AtomHandle, channelName: string, eventType: EventType) -> AtomHandle,
	Post: (self: AtomHandle, payload: any, target: Player?) -> any,
	Subscribe: (self: AtomHandle, handler: (any, Player?) -> any) -> Subscription,
	Entangle: (self: AtomHandle, owner: Authority) -> AtomHandle,
	Set: (self: AtomHandle, value: any) -> (),
	Get: (self: AtomHandle) -> any,
}

export type MoleculeHandle = {
	Name: string,
}

export type Channel = {
	Name: string,
	Shape: Shape?,
	Constraints: Constraints?,
	EventType: EventType?,
	Subscribers: {(any, Player?) -> any},
	IsMolecule: boolean,
	AtomNames: {string}?,
}

return {}
