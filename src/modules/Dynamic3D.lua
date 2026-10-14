-- /* src/modules/Dynamic3D.lua */
-- Dynamic 3D tilt perspective rendering for WindUI frames

local cloneref = (cloneref or clonereference or function(instance)
	return instance
end)

local RunService = cloneref(game:GetService("RunService"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local Players = cloneref(game:GetService("Players"))
local CoreGui = cloneref(game:GetService("CoreGui"))
local Workspace = cloneref(game:GetService("Workspace"))

local LocalPlayer = Players.LocalPlayer
local ProtectGui = protectgui or (syn and syn.protect_gui) or function() end
local GUIParent = gethui and gethui() or (CoreGui or (LocalPlayer and LocalPlayer:WaitForChild("PlayerGui")))

export type Dynamic3DOptions = {
	MaxTiltAngle: number?,
	Responsiveness: number?,
	Distance: number?,
}

local Dynamic3D = {}
Dynamic3D.__index = Dynamic3D

-- Active session registry: [GuiObject] -> Session
local activeSessions: { [GuiObject]: any } = {}

--[[
	Set(menuFrame, enabled, options)
	Enables or disables dynamic 3D cursor tilt on the specified GUI frame.
	Preserves full button clickability, hover states, and drag support.
]]
function Dynamic3D.Set(menuFrame: GuiObject, enabled: boolean, options: Dynamic3DOptions?)
	if not menuFrame or typeof(menuFrame) ~= "Instance" or not menuFrame:IsA("GuiObject") then
		warn("[WindUI:Dynamic3D] Invalid menuFrame provided. Expected GuiObject, got: " .. typeof(menuFrame))
		return
	end

	-- Disable 3D effect
	if not enabled then
		local session = activeSessions[menuFrame]
		if not session then
			return
		end

		if session.Connection then
			session.Connection:Disconnect()
			session.Connection = nil
		end

		if session.AncestryConnection then
			session.AncestryConnection:Disconnect()
			session.AncestryConnection = nil
		end

		-- Restore menuFrame to its original parent container
		if session.OriginalParent and session.OriginalParent.Parent then
			menuFrame.Parent = session.OriginalParent
		end

		if session.SurfaceGui then
			session.SurfaceGui:Destroy()
			session.SurfaceGui = nil
		end

		if session.Part then
			session.Part:Destroy()
			session.Part = nil
		end

		activeSessions[menuFrame] = nil
		return
	end

	-- Already active: return existing session
	if activeSessions[menuFrame] then
		return activeSessions[menuFrame]
	end

	options = options or {}
	local maxTiltDegrees = options.MaxTiltAngle or 8
	local maxTiltRad = math.rad(maxTiltDegrees)
	local responsiveness = options.Responsiveness or 12
	local distance = options.Distance or 2

	local originalParent = menuFrame.Parent
	local camera = Workspace.CurrentCamera

	-- Invisible Part anchored in front of the camera
	local part = Instance.new("Part")
	part.Name = "WindUI_3DPart"
	part.Transparency = 1
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = true -- CRITICAL: Must be true for raycasts to hit SurfaceGui elements
	part.CastShadow = false
	part.Anchored = true
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = camera

	-- SurfaceGui attached to the Part
	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Name = "WindUI_3DSurface"
	surfaceGui.Face = Enum.NormalId.Back -- Back face (+Z) looks directly at camera
	surfaceGui.AlwaysOnTop = true
	surfaceGui.LightInfluence = 0
	surfaceGui.Active = true
	surfaceGui.ClipsDescendants = false
	surfaceGui.ResetOnSpawn = false
	surfaceGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	surfaceGui.Adornee = part
	surfaceGui.Parent = GUIParent
	ProtectGui(surfaceGui)

	-- Reparent menuFrame inside SurfaceGui
	menuFrame.Parent = surfaceGui

	local currentRotX = 0
	local currentRotY = 0

	local connection
	connection = RunService.RenderStepped:Connect(function(dt: number)
		local currentCam = Workspace.CurrentCamera
		if not currentCam or not part or not part.Parent then
			return
		end

		if part.Parent ~= currentCam then
			part.Parent = currentCam
		end

		local vp = currentCam.ViewportSize
		if vp.X <= 0 or vp.Y <= 0 then
			return
		end

		-- Sync SurfaceGui CanvasSize to screen ViewportSize
		if surfaceGui.CanvasSize ~= vp then
			surfaceGui.CanvasSize = vp
		end

		-- Match Part dimensions to Camera frustum at current distance
		local fovRad = math.rad(currentCam.FieldOfView)
		local frustumHeight = 2 * distance * math.tan(fovRad / 2)
		local frustumWidth = frustumHeight * (vp.X / vp.Y)
		part.Size = Vector3.new(frustumWidth, frustumHeight, 0.001)

		-- Base CFrame directly in front of camera
		local baseCFrame = currentCam.CFrame * CFrame.new(0, 0, -distance)

		-- Cursor position relative to screen center [-1, 1]
		local mousePos = UserInputService:GetMouseLocation()
		local halfW = vp.X / 2
		local halfH = vp.Y / 2

		local normX = math.clamp((mousePos.X - halfW) / (halfW > 0 and halfW or 1), -1, 1)
		local normY = math.clamp((halfH - mousePos.Y) / (halfH > 0 and halfH or 1), -1, 1)

		-- Physical pressure / tilt physics:
		-- Cursor moving to the right pushes right edge into the screen (+Y rotation)
		-- Cursor moving to the top pushes top edge into the screen (-X rotation with inversion)
		local targetRotY = normX * maxTiltRad
		local targetRotX = -normY * maxTiltRad

		-- Smooth interpolation via dt
		local alpha = math.clamp(dt * responsiveness, 0, 1)
		currentRotX = currentRotX + (targetRotX - currentRotX) * alpha
		currentRotY = currentRotY + (targetRotY - currentRotY) * alpha

		-- Apply rotated CFrame to the invisible Part
		part.CFrame = baseCFrame * CFrame.Angles(currentRotX, currentRotY, 0)
	end)

	-- Auto-cleanup if menuFrame is destroyed or unparented
	local ancestryConn
	ancestryConn = menuFrame.AncestryChanged:Connect(function(_, newParent)
		if newParent == nil and activeSessions[menuFrame] then
			Dynamic3D.Set(menuFrame, false)
		end
	end)

	local session = {
		Part = part,
		SurfaceGui = surfaceGui,
		Connection = connection,
		AncestryConnection = ancestryConn,
		OriginalParent = originalParent,
	}
	activeSessions[menuFrame] = session

	return session
end

-- Allow calling Dynamic3D(menuFrame, enabled, options) directly as a function
setmetatable(Dynamic3D, {
	__call = function(_, menuFrame: GuiObject, enabled: boolean, options: Dynamic3DOptions?)
		return Dynamic3D.Set(menuFrame, enabled, options)
	end,
})

return Dynamic3D
