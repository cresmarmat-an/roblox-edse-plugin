--!strict
--[[
	Motion
	Shared timing so every animation in EDSE feels like one system:
	short, ease-out, interruptible (a new tween on the same property
	replaces the running one). Nothing animates on keyboard-driven or
	high-frequency actions such as typing or scrolling.
]]

local TweenService = game:GetService("TweenService")

local Motion = {}

-- Hover and press feedback: must feel instant.
Motion.FAST = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- Things that move: thumbs, knobs, panels.
Motion.BASE = TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
-- Entrances that need a moment to be noticed (toasts, dialogs).
Motion.ENTER = TweenInfo.new(0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
-- Exits are quicker than entrances so dismissals never feel sluggish.
Motion.EXIT = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

Motion.PRESSED_SCALE = 0.97

function Motion.Tween(instance: Instance, info: TweenInfo, goals: { [string]: any }): Tween
	local tween = TweenService:Create(instance, info, goals)
	tween:Play()
	return tween
end

return Motion
