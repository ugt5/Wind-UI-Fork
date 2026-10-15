-- /* src/modules/Dynamic3D.lua */
-- Dynamic 3D tilt perspective rendering for WindUI frames
-- Window-centric pivot with SDF falloff and click-accurate hitboxes

local cloneref = (cloneref or clonereference or function(instance)
	return instance
end)

local RunService = cloneref(game:GetService("RunService"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local TweenService = cloneref(game:GetService("TweenService"))
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
	ExitDuration: number?,
	FalloffDistance: number?,
}

local Dynamic3D = {}
Dynamic3D.__index = Dynamic3D

-- Active session registry: [GuiObject] -> Session
local activeSessions: { [GuiObject]: any } = {}

local function cleanupSession(session, menuFrame)
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

	if activeSessions[menuFrame] == session then
		activeSessions[menuFrame] = nil
	end
end

--[[
	Set(menuFrame, enabled, options, immediate)
	Enables or disables dynamic 3D cursor tilt on the specified GUI frame.
	Rotates strictly around the GUI frame's center (window-centric pivot),
	preserving pixel-accurate click hitboxes, toggle clicks, and drag functionality.
]]
function Dynamic3D.Set(menuFrame: GuiObject, enabled: boolean, options: Dynamic3DOptions?, immediate: boolean?)
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

		if immediate then
			cleanupSession(session, menuFrame)
			return
		end

		if session.Exiting then
			return
		end

		session.Exiting = true
		session.ExitElapsed = 0
		session.ExitDuration = (options and options.ExitDuration) or 0.35
		session.StartExitRotX = session.CurrentRotX or 0
		session.StartExitRotY = session.CurrentRotY or 0
		return
	end

	-- Already active: return existing session (or cancel smooth exit if currently exiting)
	local existingSession = activeSessions[menuFrame]
	if existingSession then
		if existingSession.Exiting then
			existingSession.Exiting = false
			existingSession.ExitElapsed = nil
			existingSession.StartExitRotX = nil
			existingSession.StartExitRotY = nil
		end
		return existingSession
	end

	options = options or {}
	local maxTiltDegrees = options.MaxTiltAngle or 5 -- 5 degrees optimal for Fluent UX without hitbox drift
	local maxTiltRad = math.rad(maxTiltDegrees)
	local responsiveness = options.Responsiveness or 18 -- Snappy 18 for zero-lag cursor tracking
	local distance = options.Distance or 2
	local maxFalloff = options.FalloffDistance or 120

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

	local session
	session = {
		Part = part,
		SurfaceGui = surfaceGui,
		Connection = nil,
		AncestryConnection = nil,
		OriginalParent = originalParent,
		CurrentRotX = 0,
		CurrentRotY = 0,
		Exiting = false,
	}
	activeSessions[menuFrame] = session

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

		local pixelSizeX = frustumWidth / vp.X
		local pixelSizeY = frustumHeight / vp.Y

		-- 1. Window-relative cursor calculation (relative to menuFrame)
		local framePos = menuFrame.AbsolutePosition
		local frameSize = menuFrame.AbsoluteSize
		local frameHalfW = frameSize.X / 2
		local frameHalfH = frameSize.Y / 2
		local frameCenterX = framePos.X + frameHalfW
		local frameCenterY = framePos.Y + frameHalfH

		-- Local 3D pivot of the window center on the frustum plane
		local offsetStudsX = (frameCenterX - vp.X / 2) * pixelSizeX
		local offsetStudsY = (vp.Y / 2 - frameCenterY) * pixelSizeY
		local pivotLocal = Vector3.new(offsetStudsX, offsetStudsY, -distance)
		local halfThickness = part.Size.Z / 2

		if session.Exiting then
			session.ExitElapsed = session.ExitElapsed + dt
			local progress = math.clamp(session.ExitElapsed / session.ExitDuration, 0, 1)
			local alpha = TweenService:GetValue(progress, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

			currentRotX = session.StartExitRotX * (1 - alpha)
			currentRotY = session.StartExitRotY * (1 - alpha)
			session.CurrentRotX = currentRotX
			session.CurrentRotY = currentRotY

			local rotCFrame = CFrame.Angles(currentRotX, currentRotY, 0)
			local partLocalCFrame = CFrame.new(pivotLocal) * rotCFrame * CFrame.new(-offsetStudsX, -offsetStudsY, -halfThickness)
			part.CFrame = currentCam.CFrame * partLocalCFrame

			if progress >= 1 then
				cleanupSession(session, menuFrame)
			end
			return
		end

		-- Screen cursor in viewport coordinates (matches SurfaceGui CanvasSize starting at (0, 0))
		local mousePos = UserInputService:GetMouseLocation()

		local relX = mousePos.X - frameCenterX
		local relY = frameCenterY - mousePos.Y

		-- Box SDF: distance from cursor to window bounding box
		local deltaX = math.max(0, math.abs(mousePos.X - frameCenterX) - frameHalfW)
		local deltaY = math.max(0, math.abs(mousePos.Y - frameCenterY) - frameHalfH)
		local distOutside = math.sqrt(deltaX * deltaX + deltaY * deltaY)

		-- Smoothstep falloff outside window
		local influence = 1
		if distOutside > 0 then
			local t = math.clamp(1 - (distOutside / maxFalloff), 0, 1)
			influence = t * t * (3 - 2 * t)
		end

		-- Lock tilt and level smoothly to 0 when mouse button is held down (clicks, sliders, dragging)
		if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
			influence = 0
		end

		local normX = 0
		local normY = 0
		if frameHalfW > 0 and frameHalfH > 0 then
			normX = math.clamp(relX / frameHalfW, -1, 1) * influence
			normY = math.clamp(relY / frameHalfH, -1, 1) * influence
		end

		-- Tilt physics:
		-- Cursor moving to the right pushes right edge into the screen (+Y rotation)
		-- Cursor moving to the top pushes top edge into the screen (-X rotation)
		local targetRotY = normX * maxTiltRad
		local targetRotX = -normY * maxTiltRad

		-- Smooth interpolation via dt
		local alpha = math.clamp(dt * responsiveness, 0, 1)
		currentRotX = currentRotX + (targetRotX - currentRotX) * alpha
		currentRotY = currentRotY + (targetRotY - currentRotY) * alpha
		session.CurrentRotX = currentRotX
		session.CurrentRotY = currentRotY

		-- Apply rotated CFrame around the window center pivot on the SurfaceGui face
		local rotCFrame = CFrame.Angles(currentRotX, currentRotY, 0)
		local partLocalCFrame = CFrame.new(pivotLocal) * rotCFrame * CFrame.new(-offsetStudsX, -offsetStudsY, -halfThickness)
		part.CFrame = currentCam.CFrame * partLocalCFrame
	end)

	session.Connection = connection

	-- Auto-cleanup if menuFrame is destroyed or unparented
	local ancestryConn
	ancestryConn = menuFrame.AncestryChanged:Connect(function(_, newParent)
		if newParent == nil and activeSessions[menuFrame] then
			Dynamic3D.Set(menuFrame, false, nil, true)
		end
	end)

	session.AncestryConnection = ancestryConn

	return session
end

-- Allow calling Dynamic3D(menuFrame, enabled, options, immediate) directly as a function
setmetatable(Dynamic3D, {
	__call = function(_, menuFrame: GuiObject, enabled: boolean, options: Dynamic3DOptions?, immediate: boolean?)
		return Dynamic3D.Set(menuFrame, enabled, options, immediate)
	end,
})

return Dynamic3D
