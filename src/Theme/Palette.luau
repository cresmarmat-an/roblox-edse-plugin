--!strict
--[[
	Palette
	Color tokens for the two glassmorphism themes.

	Glass layers, back to front:
	  Background + soft radial glows (Glow1..3)
	  Panel glass    - cards and bars       (PanelTint at PanelOpacity)
	  Control glass  - buttons, thumbs      (ControlTint at ControlOpacity)
	  Inset          - inputs, tracks       (Inset at InsetOpacity, InsetBorder edge)
	  Floating glass - dialogs, popovers    (FloatingTint at FloatingOpacity)

	Every text and icon color is checked for WCAG contrast against the
	worst-case composite of these layers (a glow directly behind a panel):
	body text >= 4.5:1, primary text >= 7:1. Opacities are 0..1.
]]

export type Palette = {
	Name: "Light" | "Dark",

	Background: Color3,
	Glow1: Color3,
	Glow2: Color3,
	Glow3: Color3,
	GlowOpacity: number,

	PanelTint: Color3,
	PanelOpacity: number,
	-- How much of the panel's opacity fades out toward its bottom edge.
	PanelSheen: number,
	PanelShadowOpacity: number,
	ControlTint: Color3,
	ControlOpacity: number,
	FloatingTint: Color3,
	FloatingOpacity: number,

	Border: Color3,
	BorderOpacity: number,
	-- Fraction of the border's opacity kept along the bottom edge (top-lit glass).
	BorderFade: number,
	Inset: Color3,
	InsetOpacity: number,
	InsetBorder: Color3,
	InsetBorderOpacity: number,
	Shadow: Color3,
	ShadowOpacity: number,

	TextPrimary: Color3,
	TextSecondary: Color3,
	TextMuted: Color3,
	TextOnAccent: Color3,
	Icon: Color3,

	Accent: Color3,
	AccentHigh: Color3,
	AccentLow: Color3,
	Danger: Color3,
	Success: Color3,
	Warning: Color3,

	Selection: Color3,
	SelectionOpacity: number,
	Hover: Color3,
	HoverOpacity: number,
	Divider: Color3,
	DividerOpacity: number,
	Scrollbar: Color3,
	Scrim: Color3,
	ScrimOpacity: number,
	TooltipBackground: Color3,
	TooltipText: Color3,

	SyntaxKey: Color3,
	SyntaxString: Color3,
	SyntaxNumber: Color3,
	SyntaxBoolean: Color3,
	SyntaxNull: Color3,
	SyntaxPunctuation: Color3,
}

local Palette = {}

Palette.Dark = {
	Name = "Dark",

	Background = Color3.fromRGB(10, 13, 22),
	Glow1 = Color3.fromRGB(112, 92, 255),
	Glow2 = Color3.fromRGB(34, 190, 238),
	Glow3 = Color3.fromRGB(236, 96, 190),
	GlowOpacity = 0.2,

	PanelTint = Color3.fromRGB(22, 27, 42),
	PanelOpacity = 0.62,
	PanelSheen = 0.2,
	PanelShadowOpacity = 0,
	ControlTint = Color3.fromRGB(255, 255, 255),
	ControlOpacity = 0.07,
	FloatingTint = Color3.fromRGB(24, 29, 45),
	FloatingOpacity = 0.97,

	Border = Color3.fromRGB(255, 255, 255),
	BorderOpacity = 0.16,
	BorderFade = 0.4,
	Inset = Color3.fromRGB(0, 0, 0),
	InsetOpacity = 0.32,
	InsetBorder = Color3.fromRGB(255, 255, 255),
	InsetBorderOpacity = 0.2,
	Shadow = Color3.fromRGB(0, 0, 0),
	ShadowOpacity = 0.3,

	TextPrimary = Color3.fromRGB(241, 244, 250),
	TextSecondary = Color3.fromRGB(192, 199, 214),
	TextMuted = Color3.fromRGB(166, 175, 193),
	TextOnAccent = Color3.fromRGB(255, 255, 255),
	Icon = Color3.fromRGB(205, 211, 224),

	Accent = Color3.fromRGB(178, 170, 255),
	AccentHigh = Color3.fromRGB(124, 108, 250),
	AccentLow = Color3.fromRGB(94, 76, 230),
	Danger = Color3.fromRGB(255, 145, 154),
	Success = Color3.fromRGB(88, 226, 150),
	Warning = Color3.fromRGB(252, 196, 90),

	Selection = Color3.fromRGB(140, 124, 255),
	SelectionOpacity = 0.2,
	Hover = Color3.fromRGB(255, 255, 255),
	HoverOpacity = 0.07,
	Divider = Color3.fromRGB(255, 255, 255),
	DividerOpacity = 0.14,
	Scrollbar = Color3.fromRGB(110, 118, 138),
	Scrim = Color3.fromRGB(4, 6, 12),
	ScrimOpacity = 0.55,
	TooltipBackground = Color3.fromRGB(241, 244, 250),
	TooltipText = Color3.fromRGB(15, 20, 32),

	SyntaxKey = Color3.fromRGB(241, 244, 250),
	SyntaxString = Color3.fromRGB(134, 239, 172),
	SyntaxNumber = Color3.fromRGB(253, 186, 116),
	SyntaxBoolean = Color3.fromRGB(196, 181, 253),
	SyntaxNull = Color3.fromRGB(166, 175, 193),
	SyntaxPunctuation = Color3.fromRGB(166, 175, 193),
} :: Palette

Palette.Light = {
	Name = "Light",

	Background = Color3.fromRGB(224, 229, 239),
	Glow1 = Color3.fromRGB(139, 123, 255),
	Glow2 = Color3.fromRGB(92, 205, 245),
	Glow3 = Color3.fromRGB(245, 150, 210),
	GlowOpacity = 0.24,

	PanelTint = Color3.fromRGB(255, 255, 255),
	PanelOpacity = 0.8,
	PanelSheen = 0.1,
	PanelShadowOpacity = 0.06,
	ControlTint = Color3.fromRGB(255, 255, 255),
	ControlOpacity = 0.85,
	FloatingTint = Color3.fromRGB(255, 255, 255),
	FloatingOpacity = 0.97,

	Border = Color3.fromRGB(15, 23, 42),
	BorderOpacity = 0.22,
	BorderFade = 1,
	Inset = Color3.fromRGB(15, 23, 42),
	InsetOpacity = 0.05,
	InsetBorder = Color3.fromRGB(15, 23, 42),
	InsetBorderOpacity = 0.3,
	Shadow = Color3.fromRGB(15, 23, 42),
	ShadowOpacity = 0.12,

	TextPrimary = Color3.fromRGB(15, 23, 42),
	TextSecondary = Color3.fromRGB(51, 65, 85),
	TextMuted = Color3.fromRGB(71, 85, 105),
	TextOnAccent = Color3.fromRGB(255, 255, 255),
	Icon = Color3.fromRGB(51, 65, 85),

	Accent = Color3.fromRGB(67, 56, 202),
	AccentHigh = Color3.fromRGB(99, 89, 238),
	AccentLow = Color3.fromRGB(67, 56, 202),
	Danger = Color3.fromRGB(168, 22, 22),
	Success = Color3.fromRGB(18, 98, 46),
	Warning = Color3.fromRGB(138, 62, 6),

	Selection = Color3.fromRGB(79, 70, 229),
	SelectionOpacity = 0.14,
	Hover = Color3.fromRGB(15, 23, 42),
	HoverOpacity = 0.06,
	Divider = Color3.fromRGB(15, 23, 42),
	DividerOpacity = 0.14,
	Scrollbar = Color3.fromRGB(130, 143, 165),
	Scrim = Color3.fromRGB(15, 23, 42),
	ScrimOpacity = 0.3,
	TooltipBackground = Color3.fromRGB(15, 23, 42),
	TooltipText = Color3.fromRGB(248, 250, 252),

	SyntaxKey = Color3.fromRGB(15, 23, 42),
	SyntaxString = Color3.fromRGB(18, 98, 46),
	SyntaxNumber = Color3.fromRGB(152, 48, 8),
	SyntaxBoolean = Color3.fromRGB(109, 40, 217),
	SyntaxNull = Color3.fromRGB(71, 85, 105),
	SyntaxPunctuation = Color3.fromRGB(71, 85, 105),
} :: Palette

return Palette
