-- Substance
-- Tools/Fossil.lua
-- Plinko Labs

local ParticleFossil = require(script.Parent.Parent.Particle.Fossil)

return {
	Start = ParticleFossil.Start,
	Stop = ParticleFossil.Stop,
	Replay = ParticleFossil.Replay,
	Export = ParticleFossil.Export,
	Clear = ParticleFossil.Clear,
}
