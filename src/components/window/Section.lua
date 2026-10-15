local Section = {}


local Creator = require("../../modules/Creator")
local New = Creator.New
local Tween = Creator.Tween

local TabModule = require("./Tab")

function Section.New(SectionConfig, Parent, Folder, UIScale, Window)
    local SectionModule = {
        Title = SectionConfig.Title or "Section",
        Icon = SectionConfig.Icon,
        IconThemed = SectionConfig.IconThemed,
        Opened = SectionConfig.Opened or false,
        
        HeaderSize = 42,
        IconSize = 18,
        
        Expandable = false,
    }
    
    local CurrentTween = nil
    local CloseTweenConn = nil
    
    local IconFrame
    if SectionModule.Icon then
        IconFrame = Creator.Image(
            SectionModule.Icon,
            SectionModule.Icon,
            0,
            Folder,
            "Section",
            true,
            SectionModule.IconThemed,
            "TabSectionIcon"
        )
        
        IconFrame.Size = UDim2.new(0,SectionModule.IconSize,0,SectionModule.IconSize)
        IconFrame.ImageLabel.ImageTransparency = .25
    end
    
    local ChevronIconData = Creator.Icon("chevron-down")
    local ChevronIconFrame = New("Frame", {
        Size = UDim2.new(0,SectionModule.IconSize,0,SectionModule.IconSize),
        BackgroundTransparency = 1,
        Visible = false
    }, {
        New("ImageLabel", {
            Size = UDim2.new(1,0,1,0),
            BackgroundTransparency = 1,
            Image = ChevronIconData and ChevronIconData[1],
            ImageRectSize = ChevronIconData and ChevronIconData[2] and ChevronIconData[2].ImageRectSize,
            ImageRectOffset = ChevronIconData and ChevronIconData[2] and ChevronIconData[2].ImageRectPosition,
            ThemeTag = {
                ImageColor3 = "Icon",
            },
            ImageTransparency = .7,
        })
    })
    
    local SectionFrame = New("Frame", {
        Size = UDim2.new(1,0,0,SectionModule.HeaderSize),
        BackgroundTransparency = 1,
        Parent = Parent,
        ClipsDescendants = true,
    }, {
        New("TextButton", {
            Size = UDim2.new(1,0,0,SectionModule.HeaderSize),
            BackgroundTransparency = 1,
            Text = "",
        }, {
            IconFrame,
            New("TextLabel", {
                Text = SectionModule.Title,
                TextXAlignment = "Left",
                Size = UDim2.new(
                    1, 
                    IconFrame and (-SectionModule.IconSize-10)*2
                        or (-SectionModule.IconSize-10),
                        
                    1,
                    0
                ),
                ThemeTag = {
                    TextColor3 = "Text",
                },
                FontFace = Font.new(Creator.Font, Enum.FontWeight.SemiBold),
                TextSize = 14,
                BackgroundTransparency = 1,
                TextTransparency = .7,
                --TextTruncate = "AtEnd",
                TextWrapped = true
            }),
            New("UIListLayout", {
                FillDirection = "Horizontal",
                VerticalAlignment = "Center",
                Padding = UDim.new(0,10)
            }),
            ChevronIconFrame,
            New("UIPadding", {
                PaddingLeft = UDim.new(0,11),
                PaddingRight = UDim.new(0,11),
            })
        }),
        New("Frame", {
            BackgroundTransparency = 1,
            Size = UDim2.new(1,0,0,0),
            AutomaticSize = "Y",
            Name = "Content",
            Visible = SectionModule.Opened,
            ClipsDescendants = true,
            Position = UDim2.new(0,0,0,SectionModule.HeaderSize)
        }, {
            New("UIListLayout", {
                FillDirection = "Vertical",
                Padding = UDim.new(0,Window.Gap),
                VerticalAlignment = "Top",
            }),
        })
    })
    
    
    function SectionModule:Tab(TabConfig)
        if not SectionModule.Expandable then
            SectionModule.Expandable = true
            ChevronIconFrame.Visible = true
        end
        TabConfig.Parent = SectionFrame.Content
        return TabModule.New(TabConfig, UIScale)
    end
    
    function SectionModule:Open()
        if SectionModule.Expandable then
            SectionModule.Opened = true
            SectionFrame.Content.Visible = true

            if CloseTweenConn then
                CloseTweenConn:Disconnect()
                CloseTweenConn = nil
            end
            if CurrentTween then
                CurrentTween:Cancel()
                CurrentTween = nil
            end

            local contentHeight = SectionFrame.Content.UIListLayout.AbsoluteContentSize.Y
            if contentHeight == 0 then
                contentHeight = SectionFrame.Content.AbsoluteSize.Y
            end

            CurrentTween = Tween(SectionFrame, 0.33, {
                Size = UDim2.new(1,0,0, SectionModule.HeaderSize + (contentHeight/UIScale))
            }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
            CurrentTween:Play()
            
            Tween(ChevronIconFrame.ImageLabel, 0.1, {Rotation = 180}, Enum.EasingStyle.Quint, Enum.EasingDirection.Out):Play()
        end
    end
    function SectionModule:Close()
        if SectionModule.Expandable then
            SectionModule.Opened = false

            if CloseTweenConn then
                CloseTweenConn:Disconnect()
                CloseTweenConn = nil
            end
            if CurrentTween then
                CurrentTween:Cancel()
                CurrentTween = nil
            end

            CurrentTween = Tween(SectionFrame, 0.26, {
                Size = UDim2.new(1,0,0, SectionModule.HeaderSize)
            }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

            CloseTweenConn = CurrentTween.Completed:Connect(function(playbackState)
                if CloseTweenConn then
                    CloseTweenConn:Disconnect()
                    CloseTweenConn = nil
                end
                if playbackState == Enum.PlaybackState.Completed and not SectionModule.Opened then
                    SectionFrame.Content.Visible = false
                end
            end)

            CurrentTween:Play()
            Tween(ChevronIconFrame.ImageLabel, 0.1, {Rotation = 0}, Enum.EasingStyle.Quint, Enum.EasingDirection.Out):Play()
        end
    end
    
    Creator.AddSignal(SectionFrame.TextButton.MouseButton1Click, function()
        if SectionModule.Expandable then
            if SectionModule.Opened then
                SectionModule:Close()
            else
                SectionModule:Open()
            end
        end
    end)
    
    Creator.AddSignal(SectionFrame.Content.UIListLayout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
        if SectionModule.Opened then
            SectionModule:Open()
        end
    end)
    
    if SectionModule.Opened then
        task.spawn(function()
            task.wait()
            SectionModule:Open()
        end)
    end

    
    
    return SectionModule
end


return Section