-- TurnHandler LocalScript in StarterPlayerScripts

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- RemoteEvents
local UnitTurnStartEvent = ReplicatedStorage:WaitForChild("UnitTurnStartEvent")
local EndTurnEvent = ReplicatedStorage:WaitForChild("EndTurnEvent")
local unitMovedEvent = ReplicatedStorage:WaitForChild("UnitMovedEvent")
local unitAttackedEvent = ReplicatedStorage:WaitForChild("UnitAttackedEvent")
local HighlightUnitEvent = ReplicatedStorage:WaitForChild("HighlightUnitEvent") -- New
local UpdateTurnOrderEvent = ReplicatedStorage:WaitForChild("UpdateTurnOrderEvent") -- New
local MoveConfirmationEvent = ReplicatedStorage:WaitForChild("MoveConfirmationEvent")
-- UI Elements (Assuming these are created manually or via UISetup script)
local playerGui = player:WaitForChild("PlayerGui")
local turnBasedUI = playerGui:FindFirstChild("TurnBasedUI")
if not turnBasedUI then
	-- Create TurnBasedUI if it doesn't exist
	turnBasedUI = Instance.new("ScreenGui")
	turnBasedUI.Name = "TurnBasedUI"
	turnBasedUI.Parent = playerGui
end

local turnIndicator = turnBasedUI:FindFirstChild("TurnIndicator")
if not turnIndicator then
	-- Create TurnIndicator if it doesn't exist
	turnIndicator = Instance.new("TextLabel")
	turnIndicator.Name = "TurnIndicator"
	turnIndicator.Size = UDim2.new(0, 300, 0, 50)
	turnIndicator.Position = UDim2.new(0.5, -150, 0, 10)
	turnIndicator.AnchorPoint = Vector2.new(0.5, 0)
	turnIndicator.BackgroundTransparency = 0.5
	turnIndicator.BackgroundColor3 = Color3.new(0, 0, 0)
	turnIndicator.TextColor3 = Color3.new(1, 1, 1)
	turnIndicator.Font = Enum.Font.GothamBold
	turnIndicator.TextScaled = true
	turnIndicator.Text = "Waiting for your unit's turn..."
	turnIndicator.Visible = false
	turnIndicator.Parent = turnBasedUI
end

local endTurnButton = turnBasedUI:FindFirstChild("EndTurnButton")
if not endTurnButton then
	-- Create EndTurnButton if it doesn't exist
	endTurnButton = Instance.new("TextButton")
	endTurnButton.Name = "EndTurnButton"
	endTurnButton.Size = UDim2.new(0, 150, 0, 50)
	endTurnButton.Position = UDim2.new(0.5, -75, 0, 70)
	endTurnButton.AnchorPoint = Vector2.new(0.5, 0)
	endTurnButton.BackgroundTransparency = 0.2
	endTurnButton.BackgroundColor3 = Color3.new(0, 0.5, 1)
	endTurnButton.TextColor3 = Color3.new(1, 1, 1)
	endTurnButton.Font = Enum.Font.GothamBold
	endTurnButton.TextScaled = true
	endTurnButton.Text = "End Turn"
	endTurnButton.Visible = false
	endTurnButton.Parent = turnBasedUI

	-- Add UICorner for rounded edges
	local uicorner = Instance.new("UICorner")
	uicorner.CornerRadius = UDim.new(0, 10)
	uicorner.Parent = endTurnButton

	-- Add UIStroke for borders
	local uistroke = Instance.new("UIStroke")
	uistroke.Color = Color3.new(1, 1, 1) -- White border
	uistroke.Thickness = 2
	uistroke.Parent = endTurnButton
end

local actionCounter = turnBasedUI:FindFirstChild("ActionCounter")
if not actionCounter then
	-- Create ActionCounter if it doesn't exist
	actionCounter = Instance.new("TextLabel")
	actionCounter.Name = "ActionCounter"
	actionCounter.Size = UDim2.new(0, 200, 0, 50)
	actionCounter.Position = UDim2.new(0.5, -100, 0, 130)
	actionCounter.AnchorPoint = Vector2.new(0.5, 0)
	actionCounter.BackgroundTransparency = 0.5
	actionCounter.BackgroundColor3 = Color3.new(0, 0, 0)
	actionCounter.TextColor3 = Color3.new(1, 1, 1)
	actionCounter.Font = Enum.Font.GothamBold
	actionCounter.TextScaled = true
	actionCounter.Text = "AP: 9 | Stamina: 100"
	actionCounter.Visible = false
	actionCounter.Parent = turnBasedUI

	-- Add UIStroke for borders
	local uistroke2 = Instance.new("UIStroke")
	uistroke2.Color = Color3.new(1, 1, 1) -- White border
	uistroke2.Thickness = 2
	uistroke2.Parent = actionCounter
end

-- Variables to keep track of the current unit
local currentUnit = nil
local highlightedUnit = nil -- Track the currently highlighted unit

-- Function to handle unit turn start
UnitTurnStartEvent.OnClientEvent:Connect(function(unit)
	currentUnit = unit
	local actionPoints = unit:GetAttribute("ActionPoints") or 9
	local stamina = unit:GetAttribute("Stamina") or 100
	turnIndicator.Text = "Your unit's turn: " .. unit.Name
	turnIndicator.Visible = true
	endTurnButton.Visible = true
	actionCounter.Text = "AP: " .. actionPoints .. " | Stamina: " .. stamina
	actionCounter.Visible = true
	print("It's your unit's turn: " .. unit.Name)
end)

-- Function to handle turn end
EndTurnEvent.OnClientEvent:Connect(function()
	turnIndicator.Visible = false
	endTurnButton.Visible = false
	actionCounter.Visible = false
	currentUnit = nil
	print("Your unit's turn has ended.")
end)

-- Function to handle End Turn button click
local function onEndTurnButtonClicked()
	turnIndicator.Visible = false
	endTurnButton.Visible = false
	actionCounter.Visible = false
	-- Notify the server that the unit's turn has ended
	EndTurnEvent:FireServer()
	print("You have ended your unit's turn.")
	currentUnit = nil
end

-- Connect the End Turn button
endTurnButton.MouseButton1Click:Connect(onEndTurnButtonClicked)

-- Listen for unit movement to update ActionCounter
MoveConfirmationEvent.OnClientEvent:Connect(function(success, unit, targetTile)
	if success and unit == currentUnit then
		local actionPoints = unit:GetAttribute("ActionPoints") or 0
		local stamina = unit:GetAttribute("Stamina") or 0
		actionCounter.Text = "AP: " .. actionPoints .. " | Stamina: " .. stamina
		print("Unit moved successfully to:", targetTile.Name)
		if actionPoints <= 0 then
			-- End unit's turn
			onEndTurnButtonClicked()
		end
	else
		print("Failed to move unit to:", targetTile.Name)
	end
end)

-- Listen for unit attacks to update ActionCounter
unitAttackedEvent.OnClientEvent:Connect(function(attacker, defender, damage)
	print(attacker.Name .. " attacked " .. defender.Name .. " for " .. damage .. " damage.")
	if attacker == currentUnit then
		local actionPoints = attacker:GetAttribute("ActionPoints") or 0
		local stamina = attacker:GetAttribute("Stamina") or 0
		actionCounter.Text = "AP: " .. actionPoints .. " | Stamina: " .. stamina
		if actionPoints <= 0 then
			onEndTurnButtonClicked()
		end
	end
end)

-- Listen for updating turn order
local turnOrderList = {} -- List to store the current turn order
UpdateTurnOrderEvent.OnClientEvent:Connect(function(updatedTurnOrder)
	turnOrderList = updatedTurnOrder
	print("Turn order updated:", table.concat(turnOrderList, ", "))
end)

-- Listen for highlighting the current unit
HighlightUnitEvent.OnClientEvent:Connect(function(unit)
	-- Remove highlight from previous unit
	if highlightedUnit and highlightedUnit ~= unit then
		local existingHighlight = highlightedUnit:FindFirstChild("Highlight")
		if existingHighlight then
			existingHighlight:Destroy()
		end
	end

	-- Highlight the new unit
	if unit then
		local unitModel = workspace.Units:FindFirstChild(unit.Name)
		if unitModel and unitModel.PrimaryPart then
			local highlight = Instance.new("Highlight")
			highlight.Name = "Highlight"
			highlight.Adornee = unitModel.PrimaryPart
			highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			highlight.FillColor = Color3.new(1, 1, 0) -- Yellow color
			highlight.FillTransparency = 0.5
			highlight.OutlineColor = Color3.new(1, 1, 0)
			highlight.OutlineTransparency = 0
			highlight.Parent = unitModel.PrimaryPart
			highlightedUnit = unitModel
		end
	else
		-- No unit to highlight
		highlightedUnit = nil
	end
end)

-- Notify the server when the player is ready (e.g., after spawning)
player.CharacterAdded:Connect(function(character)
	wait(1) -- Wait for the character to load
	ReplicatedStorage:WaitForChild("PlayerReadyEvent"):FireServer()
end)
