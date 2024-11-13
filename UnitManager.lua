-- UnitManager Script in ServerScriptService

--[[
    UnitManager Script
    Handles the creation, placement, equipping, movement, and combat interactions of units.
    Integrates with the hex grid system and manages unit attributes.
    Implements Turn-Based System with unit initiative, action points, stamina, and unit highlighting.
]]

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

-- Require Terrain Definitions
local TerrainDefinitions = require(ReplicatedStorage:WaitForChild("TerrainDefinitions"))

-- References to Folders
local tilesFolder = Workspace:WaitForChild("Tiles")
local unitsFolder = Workspace:FindFirstChild("Units") or Instance.new("Folder", Workspace)
unitsFolder.Name = "Units"

-- Reference to Items Folder
local itemsFolder = ReplicatedStorage:WaitForChild("Items")

-- RemoteEvents
local moveUnitEvent = ReplicatedStorage:WaitForChild("MoveUnitEvent")
local attackUnitEvent = ReplicatedStorage:WaitForChild("AttackUnitEvent")
local unitInitEvent = ReplicatedStorage:WaitForChild("UnitInitEvent")
local moveConfirmationEvent = ReplicatedStorage:WaitForChild("MoveConfirmationEvent")
local TurnStartEvent = ReplicatedStorage:WaitForChild("TurnStartEvent")
local EndTurnEvent = ReplicatedStorage:WaitForChild("EndTurnEvent")
local PlayerReadyEvent = ReplicatedStorage:WaitForChild("PlayerReadyEvent")
local UnitTurnStartEvent = ReplicatedStorage:WaitForChild("UnitTurnStartEvent")
local unitMovedEvent = ReplicatedStorage:WaitForChild("UnitMovedEvent")
local unitAttackedEvent = ReplicatedStorage:WaitForChild("UnitAttackedEvent")
local HighlightUnitEvent = ReplicatedStorage:WaitForChild("HighlightUnitEvent") -- New
local UpdateTurnOrderEvent = ReplicatedStorage:WaitForChild("UpdateTurnOrderEvent") -- New

local startTurnForCurrentUnit
-- Shared tileMap (Assuming GridGenerator populates this as a global variable)
local tileMap = _G.tileMap 

-- Utility Functions

-- Function to calculate distance between two tiles using axial coordinates
local function hexDistance(q1, r1, q2, r2)
	return (math.abs(q1 - q2) + math.abs(q1 + r1 - q2 - r2) + math.abs(r1 - r2)) / 2
end

-- Function to equip an item to a unit
local function equipItem(unit, itemName, slot)
	-- Validate slot
	local validSlots = {"MainHand", "OffHand", "Accessory", "BodyArmor", "Helmet"}
	if not table.find(validSlots, slot) then
		warn("Invalid equipment slot:", slot)
		return false
	end

	-- Find the item in ReplicatedStorage
	local itemTemplate = itemsFolder:FindFirstChild(itemName)
	if not itemTemplate then
		warn("Item not found:", itemName)
		return false
	end

	-- Clone the item and parent it to the unit's Equipment folder
	local equipmentFolder = unit:FindFirstChild("Equipment") or Instance.new("Folder", unit)
	equipmentFolder.Name = "Equipment"

	local item = itemTemplate:Clone()
	item.Parent = equipmentFolder

	-- Update the equipment slot
	local slotValue = equipmentFolder:FindFirstChild(slot)
	if slotValue then
		-- Unequip previous item if any
		if slotValue.Value then
			slotValue.Value:Destroy()
		end
		slotValue.Value = item
	else
		-- Create slot if it doesn't exist
		slotValue = Instance.new("ObjectValue")
		slotValue.Name = slot
		slotValue.Value = item
		slotValue.Parent = equipmentFolder
	end

	-- Update unit stats based on the item
	if slot == "BodyArmor" then
		local durability = item:GetAttribute("Durability") or 0
		unit:SetAttribute("BodyArmorHP", durability)
		unit:SetAttribute("MaxBodyArmorHP", durability)
	elseif slot == "Helmet" then
		local durability = item:GetAttribute("Durability") or 0
		unit:SetAttribute("HelmetHP", durability)
		unit:SetAttribute("MaxHelmetHP", durability)
	elseif slot == "MainHand" or slot == "OffHand" then
		-- Additional attributes like Damage can be handled here
		local damage = item:GetAttribute("Damage") or 0
		unit:SetAttribute(slot .. "Damage", damage)
		local staminaCost = item:GetAttribute("StaminaCost") or 0
		unit:SetAttribute(slot .. "StaminaCost", staminaCost)
	end

	-- Optional: Add visual representation (e.g., attaching the item model to the character)
	

	print("Equipped", itemName, "to slot", slot, "of unit", unit.Name)
	return true
end

-- Function to unequip an item from a unit
local function unequipItem(unit, slot)
	local validSlots = {"MainHand", "OffHand", "Accessory", "BodyArmor", "Helmet"}
	if not table.find(validSlots, slot) then
		warn("Invalid equipment slot for unequip:", slot)
		return false
	end

	local equipmentFolder = unit:FindFirstChild("Equipment")
	if not equipmentFolder then
		warn("Equipment folder not found for unit:", unit.Name)
		return false
	end

	local slotValue = equipmentFolder:FindFirstChild(slot)
	if slotValue and slotValue.Value then
		slotValue.Value:Destroy()
		slotValue.Value = nil

		-- Reset unit stats if necessary
		if slot == "BodyArmor" then
			unit:SetAttribute("BodyArmorHP", 0)
			unit:SetAttribute("MaxBodyArmorHP", 0)
		elseif slot == "Helmet" then
			unit:SetAttribute("HelmetHP", 0)
			unit:SetAttribute("MaxHelmetHP", 0)
		elseif slot == "MainHand" or slot == "OffHand" then
			unit:SetAttribute(slot .. "Damage", 0)
			unit:SetAttribute(slot .. "StaminaCost", 0)
		end

		print("Unequipped slot", slot, "from unit", unit.Name)
		return true
	else
		warn("No item to unequip in slot:", slot)
		return false
	end
end

-- Function to place a unit on a specific tile
local function placeUnitOnTile(unitModelName, tile, player)
	print("Placing unit:", unitModelName, "on tile for player:", player.Name) -- Debugging statement

	if not tile then
		warn("Tile is nil in placeUnitOnTile")
		return nil
	end

	if tile:GetAttribute("Occupied") then
		warn("Tile is already occupied.")
		return nil
	end

	-- Clone the unit model
	local unitTemplate = ReplicatedStorage.Units:FindFirstChild(unitModelName)
	if not unitTemplate then
		warn("Unit model not found:", unitModelName)
		return nil
	end

	local unit = unitTemplate:Clone()
	unit.Parent = unitsFolder

	-- Ensure the unit has a PrimaryPart set
	if not unit.PrimaryPart then
		warn("Unit model does not have a PrimaryPart set.")
		unit:SetPrimaryPartCFrame(tile.PrimaryPart.CFrame) -- Temporarily set to tile's CFrame
	end

	-- Calculate the correct Y-position
	local tilePosition = tile.PrimaryPart.Position
	local tileHeight = tile.PrimaryPart.Size.Y
	local unitHeight = unit:GetExtentsSize().Y / 2
	local padding = 1 -- Adjust this value as needed

	local targetCFrame = CFrame.new(
		tilePosition.X,
		tilePosition.Y + (tileHeight / 2) + unitHeight + padding,
		tilePosition.Z
	)

	unit:SetPrimaryPartCFrame(targetCFrame)

	-- Set initial attributes
	unit:SetAttribute("HP", unit:GetAttribute("MaxHP") or 100)
	unit:SetAttribute("BodyArmorHP", unit:GetAttribute("MaxBodyArmorHP") or 0)
	unit:SetAttribute("HelmetHP", unit:GetAttribute("MaxHelmetHP") or 0)
	unit:SetAttribute("Stamina", unit:GetAttribute("MaxStamina") or 100)
	unit:SetAttribute("MaxStamina", unit:GetAttribute("MaxStamina") or 100)
	unit:SetAttribute("StaminaRecovery", unit:GetAttribute("StaminaRecovery") or 10)
	unit:SetAttribute("MovementRange", unit:GetAttribute("MovementRange") or 3)
	unit:SetAttribute("Owner", player.UserId)
	unit:SetAttribute("Initiative", unit:GetAttribute("Initiative") or math.random(1, 20))
	unit:SetAttribute("ActionPoints", 9) -- Initialize with 9 AP

	-- Update tile occupancy using ObjectValues
	local occupantValue = tile:FindFirstChild("Occupant")
	if occupantValue then
		occupantValue.Value = unit
	else
		-- Create Occupant ObjectValue if it doesn't exist
		occupantValue = Instance.new("ObjectValue")
		occupantValue.Name = "Occupant"
		occupantValue.Value = unit
		occupantValue.Parent = tile
	end

	-- Create an ObjectValue to store the current tile reference
	local currentTileValue = Instance.new("ObjectValue")
	currentTileValue.Name = "CurrentTile"
	currentTileValue.Value = tile
	currentTileValue.Parent = unit

	print("Placed unit", unit.Name, "on tile at position:", tile:GetAttribute("q"), tile:GetAttribute("r"))
	return unit
end

-- Function to move a unit to a target tile
local function moveUnitToTile(player, unit, targetTile)
	print("Attempting to move unit:", unit.Name, "to target tile at position:", targetTile:GetAttribute("q"), targetTile:GetAttribute("r")) -- Debugging statement

	-- Get the unit's current tile from the ObjectValue
	local currentTileValue = unit:FindFirstChild("CurrentTile")
	local currentTile = currentTileValue and currentTileValue.Value

	if not currentTile then
		warn("Unit does not have a current tile.")
		moveConfirmationEvent:FireClient(player, false, unit, targetTile) -- Notify client of failure
		return
	end

	-- Get coordinates of current and target tiles
	local q1 = currentTile:GetAttribute("q")
	local r1 = currentTile:GetAttribute("r")
	local q2 = targetTile:GetAttribute("q")
	local r2 = targetTile:GetAttribute("r")

	-- Validate that both tiles have valid coordinates
	if not (q1 and r1 and q2 and r2) then
		warn("One or both tiles do not have valid coordinates.")
		moveConfirmationEvent:FireClient(player, false, unit, targetTile) -- Notify client of failure
		return
	end

	-- Calculate distance using hex distance formula
	local distance = hexDistance(q1, r1, q2, r2)
	local movementRange = unit:GetAttribute("MovementRange") or 3 -- Default movement range

	if distance > movementRange then
		warn("Target tile is out of movement range.")
		moveConfirmationEvent:FireClient(player, false, unit, targetTile) -- Notify client of failure
		return
	end

	-- Check if target tile is occupied using ObjectValue
	local targetOccupantValue = targetTile:FindFirstChild("Occupant")
	if targetOccupantValue and targetOccupantValue.Value then
		warn("Target tile is occupied.")
		moveConfirmationEvent:FireClient(player, false, unit, targetTile) -- Notify client of failure
		return
	end

	-- Check if unit has enough action points
	local actionPoints = unit:GetAttribute("ActionPoints") or 0
	local moveCostAP = 2
	if actionPoints < moveCostAP then
		warn("Unit does not have enough action points to move.")
		moveConfirmationEvent:FireClient(player, false, unit, targetTile) -- Notify client of failure
		return
	end

	-- Check if unit has enough stamina
	local staminaCostPerMove = 5 -- Adjust as needed
	local currentStamina = unit:GetAttribute("Stamina") or 100
	if currentStamina < staminaCostPerMove then
		warn("Unit does not have enough stamina to move.")
		moveConfirmationEvent:FireClient(player, false, unit, targetTile) -- Notify client of failure
		return
	end

	-- Deduct action points and stamina
	unit:SetAttribute("ActionPoints", actionPoints - moveCostAP)
	unit:SetAttribute("Stamina", currentStamina - staminaCostPerMove)
	print("Deducted action points and stamina. New AP:", unit:GetAttribute("ActionPoints"), "New Stamina:", unit:GetAttribute("Stamina"))

	-- Update tile occupancy using ObjectValues
	-- Clear current tile's Occupant
	local currentOccupantValue = currentTile:FindFirstChild("Occupant")
	if currentOccupantValue then
		currentOccupantValue.Value = nil
		print("Cleared current tile's occupant.")
	else
		-- If Occupant ObjectValue doesn't exist, create it
		currentOccupantValue = Instance.new("ObjectValue")
		currentOccupantValue.Name = "Occupant"
		currentOccupantValue.Value = nil
		currentOccupantValue.Parent = currentTile
		print("Created Occupant ObjectValue on current tile.")
	end

	-- Set target tile's Occupant to the unit
	if targetOccupantValue then
		targetOccupantValue.Value = unit
		print("Set target tile's occupant to unit.")
	else
		-- If Occupant ObjectValue doesn't exist, create it
		targetOccupantValue = Instance.new("ObjectValue")
		targetOccupantValue.Name = "Occupant"
		targetOccupantValue.Value = unit
		targetOccupantValue.Parent = targetTile
		print("Created Occupant ObjectValue on target tile and set to unit.")
	end

	-- Calculate target position for tween
	local tilePosition = targetTile.PrimaryPart.Position
	local tileHeight = targetTile.PrimaryPart.Size.Y
	local unitHeight = unit:GetExtentsSize().Y / 2
	local padding = 1 -- Adjust this value as needed

	local targetCFrame = CFrame.new(
		tilePosition.X,
		tilePosition.Y + (tileHeight / 2) + unitHeight + padding,
		tilePosition.Z
	)

	-- Tween the unit's movement for smooth transition
	local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(unit.PrimaryPart, tweenInfo, {CFrame = targetCFrame})
	tween:Play()
	print("Tweening unit to new position.")

	-- Update the unit's current tile reference after the tween completes
	tween.Completed:Connect(function()
		if currentTileValue then
			currentTileValue.Value = targetTile
			print("Moved unit", unit.Name, "to tile at position:", q2, r2) -- Debugging statement
			moveConfirmationEvent:FireClient(player, true, unit, targetTile) -- Notify client of success
			-- Broadcast movement to all clients
			unitMovedEvent:FireAllClients(unit, targetTile)
			-- Check if action points are depleted
			if unit:GetAttribute("ActionPoints") <= 0 then
				endTurnForCurrentUnit()
			end
		else
			warn("CurrentTile ObjectValue not found for unit:", unit.Name)
			moveConfirmationEvent:FireClient(player, false, unit, targetTile) -- Notify client of failure
		end
	end)
end

-- Function to attack a defender unit
local function attackUnit(attacker, defender)
	-- Get attacker's weapon damage
	local weapon = attacker.Equipment.MainHand.Value
	local damage = weapon and weapon:GetAttribute("Damage") or 10 -- Default damage

	-- Check if attacker has enough action points
	local actionPoints = attacker:GetAttribute("ActionPoints") or 0
	local attackCostAP = 4
	if actionPoints < attackCostAP then
		warn("Unit does not have enough action points to attack.")
		return
	end

	-- Check if attacker has enough stamina
	local staminaCost = weapon and weapon:GetAttribute("StaminaCost") or 10
	local currentStamina = attacker:GetAttribute("Stamina") or 100
	if currentStamina < staminaCost then
		warn("Unit does not have enough stamina to attack.")
		return
	end

	-- Deduct action points and stamina
	attacker:SetAttribute("ActionPoints", actionPoints - attackCostAP)
	attacker:SetAttribute("Stamina", currentStamina - staminaCost)
	print("Deducted action points and stamina for attack. New AP:", attacker:GetAttribute("ActionPoints"), "New Stamina:", attacker:GetAttribute("Stamina"))

	-- Apply damage to defender's armor first
	local bodyArmorHP = defender:GetAttribute("BodyArmorHP") or 0
	if bodyArmorHP > 0 then
		local damageToArmor = math.min(damage, bodyArmorHP)
		defender:SetAttribute("BodyArmorHP", bodyArmorHP - damageToArmor)
		damage = damage - damageToArmor
	end

	-- Apply damage to defender's helmet if any
	if damage > 0 then
		local helmetHP = defender:GetAttribute("HelmetHP") or 0
		if helmetHP > 0 then
			local damageToHelmet = math.min(damage, helmetHP)
			defender:SetAttribute("HelmetHP", helmetHP - damageToHelmet)
			damage = damage - damageToHelmet
		end
	end

	-- Apply remaining damage to defender's HP
	if damage > 0 then
		local defenderHP = defender:GetAttribute("HP") or 100
		defender:SetAttribute("HP", math.max(defenderHP - damage, 0))
	end

	print(attacker.Name, "attacked", defender.Name, "for", damage, "damage.")

	-- Broadcast attack to all clients
	unitAttackedEvent:FireAllClients(attacker, defender, damage)

	-- Check if defender is dead
	if (defender:GetAttribute("HP") or 100) <= 0 then
		-- Handle defender's death
		local defenderTile = defender:FindFirstChild("CurrentTile") and defender.CurrentTile.Value
		if defenderTile then
			defenderTile:SetAttribute("Occupied", false)
			local occupantValue = defenderTile:FindFirstChild("Occupant")
			if occupantValue then
				occupantValue.Value = nil
			end
		end
		defender:Destroy()
		print(defender.Name, "has been defeated!")
	end

	-- Check if action points are depleted
	if attacker:GetAttribute("ActionPoints") <= 0 then
		endTurnForCurrentUnit()
	end
end

-- Turn-Based System Variables
local unitsInGame = {} -- List of units participating in the game, sorted by initiative
local currentUnitIndex = 1 -- Index of the unit whose turn it is
local turnInProgress = false
local actionPointsPerUnit = 9 -- Maximum action points per unit per turn
local turnTimeLimit = 60 -- Seconds per unit's turn (optional)
local turnTimer = nil -- Reference to the turn timer

-- Function to replenish stamina for all units at the end of a round
local function replenishStamina()
	for _, unit in pairs(unitsInGame) do
		local maxStamina = unit:GetAttribute("MaxStamina") or 100
		local currentStamina = unit:GetAttribute("Stamina") or 100
		local staminaRecovery = unit:GetAttribute("StaminaRecovery") or 10
		local newStamina = math.min(currentStamina + staminaRecovery, maxStamina)
		unit:SetAttribute("Stamina", newStamina)
		print("Unit", unit.Name, "recovered stamina. New Stamina:", newStamina)
	end
end

-- Function to initialize the turn order at the start of a round
local function initializeTurnOrder()
	-- Collect all units
	unitsInGame = {}
	for _, unit in pairs(unitsFolder:GetChildren()) do
		table.insert(unitsInGame, unit)
	end

	-- Sort units by initiative
	table.sort(unitsInGame, function(a, b)
		local initiativeA = a:GetAttribute("Initiative") or 0
		local initiativeB = b:GetAttribute("Initiative") or 0
		return initiativeA > initiativeB
	end)

	currentUnitIndex = 1
	startTurnForCurrentUnit()

	-- Update turn order for clients
	local turnOrderList = {}
	for i, unit in ipairs(unitsInGame) do
		table.insert(turnOrderList, unit.Name) -- Assuming unit names are unique identifiers
	end
	UpdateTurnOrderEvent:FireAllClients(turnOrderList)
end

-- Function to start a turn for the current unit
local function startTurnForCurrentUnit()
	local currentUnit = unitsInGame[currentUnitIndex]
	if not currentUnit then
		-- All units have acted, start new round
		-- Before starting new round, replenish stamina
		replenishStamina()
		initializeTurnOrder()
		return
	end

	turnInProgress = true
	print("It's now " .. currentUnit.Name .. "'s turn.")

	-- Set the unit's action points to maximum
	currentUnit:SetAttribute("ActionPoints", actionPointsPerUnit)

	-- Notify the owner of the unit about the turn start
	local ownerUserId = currentUnit:GetAttribute("Owner")
	local ownerPlayer = Players:GetPlayerByUserId(ownerUserId)
	if ownerPlayer then
		UnitTurnStartEvent:FireClient(ownerPlayer, currentUnit)
	end

	-- Highlight the current unit by broadcasting to all clients
	HighlightUnitEvent:FireAllClients(currentUnit)

end

-- Function to end the turn for the current unit
function endTurnForCurrentUnit()
	turnInProgress = false
	local currentUnit = unitsInGame[currentUnitIndex]
	print(currentUnit.Name .. "'s turn has ended.")

	-- Cancel the turn timer if it exists
	if turnTimer then
		task.cancel(turnTimer)
		turnTimer = nil
	end

	-- Notify the owner that the unit's turn has ended
	local ownerUserId = currentUnit:GetAttribute("Owner")
	local ownerPlayer = Players:GetPlayerByUserId(ownerUserId)
	if ownerPlayer then
		EndTurnEvent:FireClient(ownerPlayer)
	end

	-- Remove highlight from the current unit by broadcasting to all clients
	HighlightUnitEvent:FireAllClients(nil)

	-- Move to the next unit
	currentUnitIndex = currentUnitIndex + 1
	if currentUnitIndex > #unitsInGame then
		-- All units have acted, start new round
		-- Before starting new round, replenish stamina
		replenishStamina()
		-- Re-initialize turn order
		initializeTurnOrder()
	else
		startTurnForCurrentUnit()
	end

	-- Update turn order for clients
	local turnOrderList = {}
	for i, unit in ipairs(unitsInGame) do
		table.insert(turnOrderList, unit.Name) -- Assuming unit names are unique identifiers
	end
	UpdateTurnOrderEvent:FireAllClients(turnOrderList)
end

-- Server-Side Event Handlers

-- Handler for moving units
moveUnitEvent.OnServerEvent:Connect(function(player, unit, targetTile)
	print("MoveUnitEvent received from player:", player.Name, "for unit:", unit.Name, "to tile:", targetTile.Name) -- Debugging statement
	-- Validate that the unit belongs to the player
	local ownerUserId = unit:GetAttribute("Owner")
	if ownerUserId ~= player.UserId then
		warn("Player does not own this unit.")
		moveConfirmationEvent:FireClient(player, false, unit, targetTile) -- Notify client of failure
		return
	end

	-- Validate turn
	if not turnInProgress or unitsInGame[currentUnitIndex] ~= unit then
		warn("It's not this unit's turn.")
		moveConfirmationEvent:FireClient(player, false, unit, targetTile) -- Notify client of failure
		return
	end

	-- Perform movement
	moveUnitToTile(player, unit, targetTile)
	-- Check if action points are depleted within moveUnitToTile
end)

-- Handler for attacking units
attackUnitEvent.OnServerEvent:Connect(function(player, attacker, defender)
	print("AttackUnitEvent received from player:", player.Name, "attacking unit:", attacker.Name, "defender:", defender.Name) -- Debugging statement
	-- Validate ownership
	local ownerUserId = attacker:GetAttribute("Owner")
	if ownerUserId ~= player.UserId then
		warn("Player does not own the attacking unit.")
		return
	end

	-- Validate turn
	if not turnInProgress or unitsInGame[currentUnitIndex] ~= attacker then
		warn("It's not this unit's turn.")
		return
	end

	-- Perform attack
	attackUnit(attacker, defender)
	-- Check if action points are depleted within attackUnit
end)

-- Function to initialize a unit (can be triggered by a command or game event)
local function initializeUnit(player, q, r, unitModelName)
	print("Initializing unit for player:", player.Name, "at position:", q, r) -- Debugging statement
	local tile = tileMap[q] and tileMap[q][r]
	if not tile then
		warn("Tile does not exist at position:", q, r)
		return
	end

	local unit = placeUnitOnTile(unitModelName, tile, player)
	if unit then
		-- Optionally equip default items
		equipItem(unit, "IronSword", "MainHand")
		equipItem(unit, "WoodenShield", "OffHand")
		equipItem(unit, "LeatherArmor", "BodyArmor")
		equipItem(unit, "IronHelmet", "Helmet")
		-- Add more equipment as needed
	end
end

-- Handler for unit initialization
unitInitEvent.OnServerEvent:Connect(function(player, q, r, unitModelName)
	print("UnitInitEvent received from player:", player.Name, "for unit:", unitModelName, "at position:", q, r) -- Debugging statement
	-- Optional: Implement permission checks (e.g., only admins can spawn units)
	-- For testing purposes, you might disable security checks

	-- Initialize the unit at the specified position
	initializeUnit(player, q, r, unitModelName)
end)

-- Handler for player readiness
PlayerReadyEvent.OnServerEvent:Connect(function(player)
	print(player.Name .. " is ready.")
	-- Optionally, ensure the player is in the playersInGame list
	-- In this system, turn order is based on units' initiative, not players

	-- If starting the turn system upon all players being ready, implement here
	-- For simplicity, we start the turn order after a delay to allow unit initialization
	-- Adjust as needed based on your game flow
end)

-- Handler for ending turns via client
EndTurnEvent.OnServerEvent:Connect(function(player)
	local currentUnit = unitsInGame[currentUnitIndex]
	-- Validate that it's the unit's owner
	local ownerUserId = currentUnit:GetAttribute("Owner")
	if ownerUserId ~= player.UserId then
		warn(player.Name .. " tried to end a turn but it's not their unit's turn.")
		return
	end
	endTurnForCurrentUnit()
end)

-- Start the turn system after a delay to allow all units to be initialized
-- Adjust the delay as necessary
delay(5, function()
	initializeTurnOrder()
end)

-- For testing purposes, initialize units when the server starts
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		wait(1) -- Wait for the character to load
		-- Place units at different positions for testing
		initializeUnit(player, 0, 0, "HumanoidUnit")
		initializeUnit(player, 1, -1, "HumanoidUnit")
		initializeUnit(player, -1, 1, "HumanoidUnit")
	end)
end)
