--[[
=============================================================================
EPIC 34: Animation & Motion Design — Panel Animation Demo Script
=============================================================================

This script demonstrates the PanelAnimation module with various panel types.

RUN IN ROBLOX STUDIO:
1. Place this script in StarterPlayerScripts
2. Run the game to see demo panels opening/closing with animations

--]]

local PanelAnimation = require(script.Parent.PanelAnimation)

print("=== Panel Animation Demo ===")
print("Creating demo panels...")

-- Track all created panels for cleanup
local demoPanels = {}

-- Create a modal panel
local function createModalPanel(title, width, height)
  local modal = Instance.new("Frame")
  modal.Name = title .. " Modal"
  modal.Size = UDim2.new(0, width, 0, height)
  modal.Position = UDim2.new(0.5, -width/2, 0.5, -height/2)
  modal.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
  modal.BackgroundTransparency = 1
  modal.ZIndex = 1000
  
  local corner = Instance.new("UICorner")
  corner.CornerRadius = UDim.new(0, 8)
  corner.Parent = modal
  
  -- Title bar
  local titleBar = Instance.new("Frame")
  titleBar.Size = UDim2.new(1, -16, 0, 32)
  titleBar.Position = UDim2.new(0, 8, 0, 0)
  titleBar.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
  titleBar.Parent = modal
  
  local titleLabel = Instance.new("TextLabel")
  titleLabel.Size = UDim2.new(1, -16, 1, -8)
  titleLabel.Position = UDim2.new(0, 8, 0, 4)
  titleLabel.Text = title
  titleLabel.Font = Enum.Font.GothamBold
  titleLabel.TextSize = 16
  titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
  titleLabel.BackgroundTransparency = 1
  titleLabel.Parent = titleBar
  
  -- Close button
  local closeButton = Instance.new("TextButton")
  closeButton.Size = UDim2.new(0, 32, 0, 32)
  closeButton.Position = UDim2.new(1, -40, 0.5, -16)
  closeButton.Text = "✕"
  closeButton.Font = Enum.Font.GothamBold
  closeButton.TextSize = 20
  closeButton.TextColor3 = Color3.fromRGB(255, 100, 100)
  closeButton.BackgroundTransparency = 1
  closeButton.Parent = modal
  
  closeButton.MouseButton1Click:Connect(function()
    PanelAnimation:close(modal, {
      destroyOnComplete = true,
      onComplete = function()
        print("   Modal panel closed and destroyed")
      end
    })
  end)
  
  return modal
end

-- Create a settings panel
local function createSettingsPanel(width, height)
  local panel = Instance.new("Frame")
  panel.Name = "Settings Panel"
  panel.Size = UDim2.new(0, width, 0, height)
  panel.Position = UDim2.new(0.5, -width/2, 0.5, -height/2)
  panel.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
  panel.BackgroundTransparency = 1
  panel.ZIndex = 900
  
  local corner = Instance.new("UICorner")
  corner.CornerRadius = UDim.new(0, 12)
  corner.Parent = panel
  
  -- Header
  local header = Instance.new("Frame")
  header.Size = UDim2.new(1, -16, 0, 48)
  header.Position = UDim2.new(0, 8, 0, 0)
  header.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
  header.Parent = panel
  
  local headerLabel = Instance.new("TextLabel")
  headerLabel.Size = UDim2.new(1, -16, 1, -8)
  headerLabel.Position = UDim2.new(0, 8, 0, 4)
  headerLabel.Text = "⚙️ Settings"
  headerLabel.Font = Enum.Font.GothamBold
  headerLabel.TextSize = 18
  headerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
  headerLabel.BackgroundTransparency = 1
  headerLabel.Parent = header
  
  -- Content area
  local content = Instance.new("Frame")
  content.Size = UDim2.new(1, -16, 1, -64)
  content.Position = UDim2.new(0, 8, 0, 56)
  content.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
  content.BackgroundTransparency = 1
  content.Parent = panel
  
  local contentLabel = Instance.new("TextLabel")
  contentLabel.Size = UDim2.new(1, -16, 1, -8)
  contentLabel.Position = UDim2.new(0, 8, 0, 4)
  contentLabel.Text = "Settings content here..."
  contentLabel.Font = Enum.Font.GothamRegular
  contentLabel.TextSize = 14
  contentLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
  contentLabel.BackgroundTransparency = 1
  contentLabel.Parent = content
  
  -- Close button
  local closeButton = Instance.new("TextButton")
  closeButton.Size = UDim2.new(0, 48, 0, 48)
  closeButton.Position = UDim2.new(1, -56, 0.5, -24)
  closeButton.Text = "Close"
  closeButton.Font = Enum.Font.GothamRegular
  closeButton.TextSize = 14
  closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
  closeButton.BackgroundTransparency = 1
  closeButton.Parent = panel
  
  closeButton.MouseButton1Click:Connect(function()
    PanelAnimation:close(panel, {
      destroyOnComplete = true,
      onComplete = function()
        print("   Settings panel closed and destroyed")
      end
    })
  end)
  
  return panel
end

-- Create a toast notification
local function createToast(message, duration, toastType)
  local toast = Instance.new("Frame")
  toast.Name = "Toast Notification"
  toast.Size = UDim2.new(0, 350, 0, 64)
  toast.Position = UDim2.new(0.5, -175, 0.8, -32)
  toast.BackgroundColor3 = toastType == "error" and Color3.fromRGB(255, 92, 92) or
                          toastType == "success" and Color3.fromRGB(52, 199, 123) or
                          Color3.fromRGB(40, 40, 40)
  toast.BackgroundTransparency = 1
  toast.ZIndex = 2000
  
  local corner = Instance.new("UICorner")
  corner.CornerRadius = UDim.new(0, 8)
  corner.Parent = toast
  
  local messageLabel = Instance.new("TextLabel")
  messageLabel.Size = UDim2.new(1, -32, 1, -8)
  messageLabel.Position = UDim2.new(0, 16, 0, 4)
  messageLabel.Text = message or "Notification"
  messageLabel.Font = Enum.Font.GothamRegular
  messageLabel.TextSize = 14
  messageLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
  messageLabel.BackgroundTransparency = 1
  messageLabel.Parent = toast
  
  return toast
end

-- Demo sequence
print("\n=== Running Demo Sequence ===\n")

-- Get PlayerGui
local playerGui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")

-- Open modal panel
print("1. Opening Modal Panel...")
local modalPanel = createModalPanel("Welcome", 400, 300)
modalPanel.Parent = playerGui
PanelAnimation:open(modalPanel, {
  duration = 0.3,
  scaleStart = 0.8,
  onComplete = function()
    print("   Modal panel opened")
  end
})
demoPanels[modalPanel] = true

task.delay(2.0, function()
  print("   Closing Modal Panel...")
  PanelAnimation:close(modalPanel, {
    destroyOnComplete = true,
    onComplete = function()
      print("   Modal panel closed and destroyed")
    end
  })
  demoPanels[modalPanel] = nil
end)

-- Open settings panel
print("\n2. Opening Settings Panel...")
local settingsPanel = createSettingsPanel(500, 400)
settingsPanel.Parent = playerGui
PanelAnimation:open(settingsPanel, {
  duration = 0.35,
  scaleStart = 0.85,
  onComplete = function()
    print("   Settings panel opened")
  end
})
demoPanels[settingsPanel] = true

task.delay(3.0, function()
  print("   Closing Settings Panel...")
  PanelAnimation:close(settingsPanel, {
    destroyOnComplete = true,
    onComplete = function()
      print("   Settings panel closed and destroyed")
    end
  })
  demoPanels[settingsPanel] = nil
end)

-- Open toast notifications
print("\n3. Opening Toast Notifications...")
local toast1 = createToast("Settings saved successfully!", 2.0, "success")
toast1.Parent = playerGui
PanelAnimation:open(toast1, {duration = 0.25, scaleStart = 0.9})

local toast2 = createToast("An error occurred!", 2.0, "error")
toast2.Parent = playerGui
PanelAnimation:open(toast2, {duration = 0.25, scaleStart = 0.9})

local toast3 = createToast("Regular notification", 2.0)
toast3.Parent = playerGui
PanelAnimation:open(toast3, {duration = 0.25, scaleStart = 0.9})

-- Auto-close toasts after duration
task.delay(2.5, function()
  print("   Closing toast notifications...")
  PanelAnimation:close(toast1, {destroyOnComplete = true})
  PanelAnimation:close(toast2, {destroyOnComplete = true})
  PanelAnimation:close(toast3, {destroyOnComplete = true})
end)

-- Cleanup on game shutdown
game:BindToClose(function()
  print("\n4. Demo complete! Cleaning up...")
  for panel in pairs(demoPanels) do
    if panel.Parent then
      PanelAnimation:cancel(panel)
      panel:Destroy()
    end
  end
  print("   All panels destroyed.")
end)

print("\n=== Demo Started ===\n")
