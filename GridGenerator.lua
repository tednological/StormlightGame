-- GridGenerator Script in ServerScriptService

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Require Terrain Definitions
local TerrainDefinitions = require(ReplicatedStorage:WaitForChild("TerrainDefinitions"))

-- Variables
local tileTemplate = ReplicatedStorage:WaitForChild("HexTile") -- Tile model with HexTile and HexOutline
local gridRadius = 5 
local tileSize = 14 
local tileMap = {} -- Table to store references to tiles
local tilesFolder = Workspace:FindFirstChild("Tiles") or Instance.new("Folder", Workspace)
tilesFolder.Name = "Tiles"

-- Function to create a tile at given axial coordinates (q, r)
local function createTile(q, r)
	local s = -q - r
	if math.abs(s) > gridRadius then
		return -- Skip tiles outside the grid radius
	end

	-- Calculate position for pointy-topped hexes
	local x = tileSize * math.sqrt(3) * (q + r/2)
	local z = tileSize * 3/2 * r

	-- Clone the tile template
	local tile = tileTemplate:Clone()
	tile.Parent = tilesFolder -- Parent tile to the Tiles folder

	-- Set the position of the model using SetPrimaryPartCFrame
	tile:SetPrimaryPartCFrame(CFrame.new(x, 0, z))

	-- Set tile attributes for identification
	tile:SetAttribute("q", q)
	tile:SetAttribute("r", r)
	tile:SetAttribute("Occupied", false) 

	-- Assign a terrain type
	local terrainTypeNames = {}
	for name, _ in pairs(TerrainDefinitions.Types) do
		table.insert(terrainTypeNames, name)
	end
	local terrainType = terrainTypeNames[math.random(#terrainTypeNames)]
	tile:SetAttribute("TerrainType", terrainType)

	-- Configure HexOutline based on terrain type
	local hexOutline = tile:FindFirstChild("HexOutline", true)
	if hexOutline then
		hexOutline.Color = TerrainDefinitions.Types[terrainType].Color or Color3.new(1, 1, 1)
		hexOutline.Material = TerrainDefinitions.Types[terrainType].Material or Enum.Material.Plastic
	else
		warn("HexOutline not found in tile at position:", q, r)
	end

	-- Configure HexTile's main color and material
	local hexTile = tile:FindFirstChild("HexTile", true)
	if hexTile then
		hexTile.Color = TerrainDefinitions.Types[terrainType].Color or Color3.new(1, 1, 1)
		hexTile.Material = TerrainDefinitions.Types[terrainType].Material or Enum.Material.Plastic
	else
		warn("HexTile part not found in tile at position:", q, r)
	end

	-- Store tile in the tileMap for easy access
	if not tileMap[q] then
		tileMap[q] = {}
	end
	tileMap[q][r] = tile
end

-- Main loop to generate the grid
for q = -gridRadius, gridRadius do
	for r = -gridRadius, gridRadius do
		createTile(q, r)
	end
end

-- At the end of the GridGenerator script, assign tileMap to a global variable
_G.tileMap = tileMap
print("tileMap has been set in _G") -- Debugging statement
