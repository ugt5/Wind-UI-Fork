local cloneref = (cloneref or clonereference or function(instance)
	return instance
end)

local UserInputService = cloneref(game:GetService("UserInputService"))
local RunService = cloneref(game:GetService("RunService"))
local ContextActionService = cloneref(game:GetService("ContextActionService"))
local HttpService = cloneref(game:GetService("HttpService"))

local Creator = require("../modules/Creator")
local New = Creator.New

local Element = {}

type ConfigType = {
	Object: Instance,
	Camera: Instance?,
	Interactive: boolean?,
	Height: number?,
	Focused: boolean,

	Window: any, -- later
	WindUI: any, -- later
	Tab: any, -- later
	Parent: Instance,
}

function Element:New(Config: ConfigType)
	local Viewport = {
		__type = "Viewport",
		Object = Config.Object,
		Camera = Config.Camera or Instance.new("Camera"),
		Interactive = Config.Interactive or false,
		Height = Config.Height or 200,
		Focused = Config.Focused ~= false,
	}

	local Dragging = false
	local Pinching = false
	local isHovered = false
	local LastMousePos, LastPinchDist = nil, 0
	local isWheelSinkBound = false
	local ZoomTweenConnection = nil

	local CurrentDistance = 10
	local TargetDistance = 10
	local MinDistance = 0.5
	local MaxDistance = 50
	local ZoomStep = 1.15
	local ZoomDecay = 16

	local ActionName = "WindUI_ViewportWheel_"
		.. (Config.WindUI and Config.WindUI.GenerateGUID and Config.WindUI.GenerateGUID() or HttpService:GenerateGUID(false))
	local CurInput = Config.WindUI and Config.WindUI.GenerateGUID and Config.WindUI.GenerateGUID()
		or HttpService:GenerateGUID(false)

	local Main = Creator.NewRoundFrame(Config.Window.ElementConfig.UICorner, "Squircle", {
		Size = UDim2.new(1, 0, 0, Viewport.Height),
		Parent = Config.Parent,
		ThemeTag = {
			ImageColor3 = "ViewportBackground",
			ImageTransparency = "ViewportBackgroundTransparency",
		},
	}, {
		New("CanvasGroup", {
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
		}, {
			New("UICorner", {
				CornerRadius = UDim.new(0, Config.Window.ElementConfig.UICorner),
			}),
			New("ViewportFrame", {
				Name = "Viewport",
				Size = UDim2.new(1, 0, 1, 0),
				BackgroundTransparency = 1,
				CurrentCamera = Viewport.Camera,
				Active = Viewport.Interactive,
			}, {
				Viewport.Object,
				Viewport.Camera,
			}),
		}),
	})

	local function IsPositionInsideViewport(Position)
		local AbsPos = Main.CanvasGroup.Viewport.AbsolutePosition
		local Size = Main.CanvasGroup.Viewport.AbsoluteSize

		return Position.X >= AbsPos.X
			and Position.X <= AbsPos.X + Size.X
			and Position.Y >= AbsPos.Y
			and Position.Y <= AbsPos.Y + Size.Y
	end

	local function BindWheelSink()
		if isWheelSinkBound then
			return
		end
		isWheelSinkBound = true
		ContextActionService:BindActionAtPriority(
			ActionName,
			function()
				return Enum.ContextActionResult.Sink
			end,
			false,
			Enum.ContextActionPriority.High.Value,
			Enum.UserInputType.MouseWheel
		)
	end

	local function UnbindWheelSink()
		if not isWheelSinkBound then
			return
		end
		isWheelSinkBound = false
		pcall(function()
			ContextActionService:UnbindAction(ActionName)
		end)
	end

	local function GetScrollingFrame()
		if Config.Tab and Config.Tab.UIElements and Config.Tab.UIElements.ContainerFrame then
			return Config.Tab.UIElements.ContainerFrame
		end
		return Main:FindFirstAncestorWhichIsA("ScrollingFrame")
	end

	local function UpdateScrollLock()
		local shouldLock = Viewport.Interactive and (isHovered or Dragging or Pinching)
		local scrollingFrame = GetScrollingFrame()

		if shouldLock then
			if scrollingFrame then
				scrollingFrame.ScrollingEnabled = false
			end
			BindWheelSink()
		else
			if scrollingFrame then
				scrollingFrame.ScrollingEnabled = true
			end
			UnbindWheelSink()
		end
	end

	local function GetModelBounds()
		if not Viewport.Object then
			return Vector3.new(2, 2, 2), 2
		end
		local ModelSize = (Viewport.Object:IsA("BasePart") and Viewport.Object.Size)
			or (Viewport.Object:IsA("Model") and select(2, Viewport.Object:GetBoundingBox()))
			or Vector3.new(2, 2, 2)
		local MaxExtent = math.max(0.1, ModelSize.X, ModelSize.Y, ModelSize.Z)
		return ModelSize, MaxExtent
	end

	local function UpdateDistanceLimits()
		local _, MaxExtent = GetModelBounds()
		MinDistance = math.max(MaxExtent * 0.35, 0.4)
		MaxDistance = math.max(MaxExtent * 8, 10)
	end

	local function StartZoomAnimation()
		if ZoomTweenConnection then
			return
		end

		ZoomTweenConnection = RunService.RenderStepped:Connect(function(dt)
			if not Viewport.Object or not Viewport.Camera then
				if ZoomTweenConnection then
					ZoomTweenConnection:Disconnect()
					ZoomTweenConnection = nil
				end
				return
			end

			local factor = 1 - math.exp(-ZoomDecay * dt)
			CurrentDistance = CurrentDistance + (TargetDistance - CurrentDistance) * factor

			if math.abs(CurrentDistance - TargetDistance) < 0.005 then
				CurrentDistance = TargetDistance
				if ZoomTweenConnection then
					ZoomTweenConnection:Disconnect()
					ZoomTweenConnection = nil
				end
			end

			local pivot = Viewport.Object:GetPivot().Position
			local camPos = Viewport.Camera.CFrame.Position
			local offset = camPos - pivot
			local dist = offset.Magnitude
			local dir = if dist > 0.0001 then (offset / dist) else (-Viewport.Camera.CFrame.LookVector)

			local newPos = pivot + dir * CurrentDistance
			Viewport.Camera.CFrame = CFrame.new(newPos) * Viewport.Camera.CFrame.Rotation
		end)
	end

	local function ApplyZoom(delta)
		if not Viewport.Interactive or not Viewport.Object then
			return
		end

		UpdateDistanceLimits()

		if not ZoomTweenConnection then
			local pivot = Viewport.Object:GetPivot().Position
			local actualDist = (Viewport.Camera.CFrame.Position - pivot).Magnitude
			if actualDist > 0.001 then
				CurrentDistance = actualDist
				TargetDistance = actualDist
			end
		end

		local multiplier = (ZoomStep) ^ (-delta)
		TargetDistance = math.clamp(TargetDistance * multiplier, MinDistance, MaxDistance)

		StartZoomAnimation()
	end

	local function FocusCamera()
		if not Viewport.Object then
			return
		end
		local _, MaxExtent = GetModelBounds()
		local CameraDistance = MaxExtent * 2
		local ModelPosition = Viewport.Object:GetPivot().Position

		Viewport.Camera.CFrame =
			CFrame.new(ModelPosition + Vector3.new(0, MaxExtent / 2, CameraDistance), ModelPosition)

		UpdateDistanceLimits()
		CurrentDistance = (Viewport.Camera.CFrame.Position - ModelPosition).Magnitude
		TargetDistance = CurrentDistance

		if ZoomTweenConnection then
			ZoomTweenConnection:Disconnect()
			ZoomTweenConnection = nil
		end
	end

	if Viewport.Focused and Viewport.Object then
		FocusCamera()
	else
		UpdateDistanceLimits()
	end

	-- Hover & Scroll Lock Handling
	Creator.AddSignal(Main.CanvasGroup.Viewport.MouseEnter, function()
		if Viewport.Interactive then
			isHovered = true
			UpdateScrollLock()
		end
	end)

	Creator.AddSignal(Main.CanvasGroup.Viewport.MouseLeave, function()
		isHovered = false
		UpdateScrollLock()
	end)

	-- Drag Rotation Handling
	Creator.AddSignal(Main.CanvasGroup.Viewport.InputBegan, function(Input)
		if Viewport.Interactive then
			if
				(Input.UserInputType == Enum.UserInputType.MouseButton1)
				or (Input.UserInputType == Enum.UserInputType.Touch and not Pinching)
			then
				if Config.WindUI.CurrentInput and Config.WindUI.CurrentInput ~= CurInput then
					return
				end

				Config.WindUI.CurrentInput = CurInput

				Dragging = true
				LastMousePos = Input.Position
				UpdateScrollLock()
			end
		end
	end)

	Creator.AddSignal(UserInputService.InputEnded, function(Input)
		if Viewport.Interactive then
			if
				Input.UserInputType == Enum.UserInputType.MouseButton1
				or Input.UserInputType == Enum.UserInputType.Touch
			then
				if Config.WindUI.CurrentInput and Config.WindUI.CurrentInput ~= CurInput then
					return
				end

				Config.WindUI.CurrentInput = nil

				Dragging = false
				if Input.UserInputType == Enum.UserInputType.MouseButton1 then
					isHovered = IsPositionInsideViewport(Input.Position)
				else
					isHovered = false
				end
				UpdateScrollLock()
			end
		end
	end)

	Creator.AddSignal(UserInputService.InputChanged, function(Input)
		if Input.UserInputType == Enum.UserInputType.MouseMovement then
			-- Safety: If engine missed MouseLeave during fast mouse flick
			if isHovered and not Dragging and not IsPositionInsideViewport(Input.Position) then
				isHovered = false
				UpdateScrollLock()
			end
		end

		if Viewport.Interactive and Dragging and not Pinching then
			if
				Input.UserInputType == Enum.UserInputType.MouseMovement
				or Input.UserInputType == Enum.UserInputType.Touch
			then
				local MouseDelta = Input.Position - LastMousePos
				LastMousePos = Input.Position

				local Position = Viewport.Object:GetPivot().Position
				local Camera = Viewport.Camera

				local RotationY = CFrame.fromAxisAngle(Vector3.new(0, 1, 0), -MouseDelta.X * 0.02)
				Camera.CFrame = CFrame.new(Position) * RotationY * CFrame.new(-Position) * Camera.CFrame

				local RotationX = CFrame.fromAxisAngle(Camera.CFrame.RightVector, -MouseDelta.Y * 0.02)
				local PitchedCFrame = CFrame.new(Position) * RotationX * CFrame.new(-Position) * Camera.CFrame

				if PitchedCFrame.UpVector.Y > 0.1 then
					Camera.CFrame = PitchedCFrame
				end
			end
		end
	end)

	-- Smooth MouseWheel Zoom Handling
	Creator.AddSignal(Main.CanvasGroup.Viewport.InputChanged, function(Input)
		if Viewport.Interactive and Input.UserInputType == Enum.UserInputType.MouseWheel then
			ApplyZoom(Input.Position.Z)
		end
	end)

	-- Touch Pinch Handling
	Creator.AddSignal(UserInputService.TouchPinch, function(touchPositions, scale, velocity, state)
		if not IsPositionInsideViewport(touchPositions[1]) or not IsPositionInsideViewport(touchPositions[2]) then
			return
		end
		if Viewport.Interactive then
			if state == Enum.UserInputState.Begin then
				Pinching = true
				Dragging = false
				UpdateScrollLock()
				LastPinchDist = (touchPositions[1] - touchPositions[2]).Magnitude
			elseif state == Enum.UserInputState.Change then
				if Pinching and LastPinchDist > 0 then
					local currentDist = (touchPositions[1] - touchPositions[2]).Magnitude
					local ratio = currentDist / math.max(LastPinchDist, 0.001)
					LastPinchDist = currentDist

					if ratio > 0 then
						TargetDistance = math.clamp(TargetDistance / ratio, MinDistance, MaxDistance)
						StartZoomAnimation()
					end
				end
			elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
				Pinching = false
				UpdateScrollLock()
			end
		end
	end)

	-- Window Focus & Cleanup Signals
	Creator.AddSignal(UserInputService.WindowFocusReleased, function()
		if isHovered or Dragging then
			isHovered = false
			Dragging = false
			UpdateScrollLock()
		end
	end)

	Creator.AddSignal(Main.Destroying, function()
		isHovered = false
		Dragging = false
		Pinching = false
		UpdateScrollLock()

		if ZoomTweenConnection then
			ZoomTweenConnection:Disconnect()
			ZoomTweenConnection = nil
		end
	end)

	function Viewport:SetObject(Object, IsClone)
		if IsClone then
			Object = Object:Clone()
		end
		if Viewport.Object then
			Viewport.Object:Destroy()
		end

		Viewport.Object = Object
		Viewport.Object.Parent = Main.CanvasGroup.Viewport

		if Viewport.Focused and Viewport.Object then
			FocusCamera()
		else
			UpdateDistanceLimits()
		end
	end

	function Viewport:SetHeight(Height)
		Main.Size = UDim2.new(1, 0, 0, Height)
	end

	function Viewport:Focus()
		if Viewport.Object then
			FocusCamera()
		end
	end

	function Viewport:SetCamera(Camera)
		Viewport.Camera = Camera
		Main.CanvasGroup.Viewport.CurrentCamera = Camera
		if Viewport.Object then
			local pivot = Viewport.Object:GetPivot().Position
			CurrentDistance = (Camera.CFrame.Position - pivot).Magnitude
			TargetDistance = CurrentDistance
		end
	end

	function Viewport:SetInteractive(Interactive)
		Viewport.Interactive = Interactive
		Main.CanvasGroup.Viewport.Active = Interactive
		if not Interactive then
			isHovered = false
			Dragging = false
			Pinching = false
			if ZoomTweenConnection then
				ZoomTweenConnection:Disconnect()
				ZoomTweenConnection = nil
			end
		end
		UpdateScrollLock()
	end

	function Viewport:Destroy()
		isHovered = false
		Dragging = false
		Pinching = false
		UpdateScrollLock()

		if ZoomTweenConnection then
			ZoomTweenConnection:Disconnect()
			ZoomTweenConnection = nil
		end

		if Viewport.Object then
			Viewport.Object:Destroy()
		end

		Main:Destroy()
	end

	Viewport.Main = Main
	Viewport.ElementFrame = Main
	Viewport.UIElements = { Main = Main }

	return Viewport.__type, Viewport
end

return Element
