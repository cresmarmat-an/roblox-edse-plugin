--!strict
--[[
	Create
	Declarative Instance construction:

	  Create("Frame", {
	      Size = UDim2.fromScale(1, 0.5),
	      Theme = { BackgroundColor3 = "Background" },   -- theme-bound props
	      Events = { MouseEnter = OnEnter },             -- signal handlers
	      Children = { Create("UICorner", { ... }) },
	      Parent = container,                            -- applied last
	  })

	GuiObjects start with BorderSizePixel = 0, since EDSE never uses the
	legacy border.
]]

local Theme = require(script.Parent.Parent.Theme.Theme)

local RESERVED_KEYS = {
	Parent = true,
	Children = true,
	Theme = true,
	Events = true,
}

local function Create(className: string, properties: { [string]: any }?): any
	local instance = Instance.new(className)
	if instance:IsA("GuiObject") then
		instance.BorderSizePixel = 0
	end
	if properties == nil then
		return instance
	end

	for key, value in properties do
		if not RESERVED_KEYS[key] then
			(instance :: any)[key] = value
		end
	end
	if properties.Theme then
		Theme.BindAll(instance, properties.Theme)
	end
	if properties.Events then
		for eventName, handler in properties.Events do
			((instance :: any)[eventName] :: RBXScriptSignal):Connect(handler)
		end
	end
	if properties.Children then
		for _, child in properties.Children do
			child.Parent = instance
		end
	end
	if properties.Parent then
		instance.Parent = properties.Parent
	end
	return instance
end

return Create
