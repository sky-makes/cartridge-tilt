#!/usr/bin/env lua

require("cli")
require("entities")
require("generator")
require("level")
require("random")
require("structures")
require("tileset")

-- Global variables
CHUNK_SIZE = 15
DIRECTORY = ""
FORMAT = "1.6"
RANDOM_SEED = "Cartridge Tilt"
VERBOSITY = 1

WORLDS = 8
LEVELS = 4

function main()
	-- Set up command line interface
	cli = Cli:new()
	cli.usage = 'lua ./main.lua [DIRECTORY] [OPTIONS]...'
	cli.summary = 'Randomly generates 32 glitchy-looking levels for Mari0 using a structure-based generation system.\nGenerated files are stored in the given DIRECTORY, overwriting existing levels there.'
	cli.defaultCallback = setDirectory

	-- Arguments
	cli:addOption('-d', '--directory', setDirectory,
		      'Set the directory to generate the files in (if not provided as the first argument)')
	cli:addOption('-s', '--seed', function(seed) RANDOM_SEED = seed end,
		      'Set the random seed used to generate levels (defaults to "Cartridge Tilt")')
	cli:addOption('-v', '--verbosity', setVerbosity,
		      'Set how in-depth the info printed to the console is (0-5, default 1)')

	-- Level format
	cli:setOptionGroup("Level format")
	cli:addOption(nil, '--1.6', function() FORMAT = "1.6" end,
		      "Generate levels in vanilla Mari0 1.6 format (default)")
	cli:addOption(nil, '--AE', function() FORMAT = "AE" end,
		      "Generate levels in Alesan's Entities format")
	-- cli:addOption(nil, '--SE', function() FORMAT = "SE" end,
	-- 	      "Generate levels in SE/CE format")

	-- Size and number of levels
	cli:setOptionGroup("Level parameters")
	cli:addOption('-w', '--worlds', setWorlds,
		      'Number of worlds to generate (default 8)')
	cli:addOption('-l', '--levels', setLevels,
		      'Number of levels to generate per world (default 4; other values not supported by 1.6)')
	cli:addOption(nil, '--height', setHeight,
		      'Height of levels to generate (experimental, not supported by 1.6)')

	-- Process command line arguments
	if cli:processArgs(arg) then return end

	-- Ensure the directory is set
	if DIRECTORY == "" then
		print("No directory specified.")
		cli:printHelp()
		return
	end

	-- Set the seed used to generate levels
	math.randomseed(table.concat({string.byte(RANDOM_SEED, 1, string.len(RANDOM_SEED))}))

	-- Prime the RNG
	math.random()
	math.random()
	math.random()
	math.random()

	-- Main loop, if you can call it that
	for world = 1, WORLDS do
		for level = 1, LEVELS do
			generateLevel(world, level)
		end
	end

	-- Always prints regardless of verbosity level
	print(string.format(
		"All %d levels generated in %f seconds.", WORLDS * LEVELS, os.clock()))
end

function generateLevel(world, level)
	if VERBOSITY >= 1 then
		print(string.format("Generating %d-%d...", world, level))
	end

	-- Open file for this level
	io.output(string.format("%s/%s-%s.txt", DIRECTORY, world, level))

	-- Create a blank level table
	local sections = math.random(8, 12)
	local levelTable = createLevelTable(CHUNK_SIZE, sections)
	local levelWidth = CHUNK_SIZE * sections
	local levelHeight = CHUNK_SIZE

	-- Set up cursors
	local topleft = Cursor:new({cell = levelTable[1]})
	local cursor = Cursor:new({cell = topleft.cell})

	-- Set default parameters for all generators used in the level
	Generator.width = CHUNK_SIZE
	Generator.height = CHUNK_SIZE
	Generator.groundPalette = math.random(PALETTES)
	Generator.blockPalette = math.random(PALETTES)
	Generator.plantPalette = math.random(PALETTES)
	Generator.pipePalette = math.random(PALETTES)
	Generator.weatherPalette = math.random(PALETTES)
	if VERBOSITY >= 2 then
		print("\tPalettes set:")
		print(string.format("\t| %-8s | %-8s | %-8s | %-8s | %-8s |",
		      "Ground", "Blocks", "Plants", "Pipes", "Weather"))
		print(string.format("\t| %-8d | %-8d | %-8d | %-8d | %-8d |",
		      Generator.groundPalette, Generator.blockPalette,
		      Generator.plantPalette, Generator.pipePalette,
		      Generator.weatherPalette))
	end

	Generator.groundTile = math.random(FIRST_GROUND_TILE, LAST_GROUND_TILE)
	Generator.blockTile = math.random(FIRST_BLOCK_TILE, LAST_BLOCK_TILE)
	Generator.altBrick = coinflip()
	Generator.altSkyBridge = coinflip()
	Generator.altTreetop = coinflip()
	Generator.altTreetopBase = coinflip()
	Generator.altBackgroundTree = coinflip()

	-- Add lava if this is a castle level
	if level == LEVELS then
		if VERBOSITY >= 2 then
			print("\tGenerating lava...")
		end
		local lavaGenerator = LavaGenerator:new({
			width = levelWidth,
			height = levelHeight
		})
		lavaGenerator:generate(cursor)
	end

	if VERBOSITY >= 2 then
		print("\tGenerating the level itself...")
	end

	-- Build the level
	for i = 1, sections do
		if VERBOSITY >= 3 then
			print(string.format("\t\tBuilding section %d...", i))
		end

		local baseLevel, distortions, enemies
		if i == sections then
			baseLevel = LevelEndGenerator:new() --level == 4 and CastleEndGenerator:new() or LevelEndGenerator:new()
			distortions = DistortionGenerator:new({
				world = world,
				level = level,
				cosmetic = true
			})
			enemies = Generator:new()
		else
			baseLevel = ChaosGenerator:new({
				world = world,
				level = level
			})
			distortions = DistortionGenerator:new({
				world = world,
				level = level
			})
			enemies = ChaosEnemyGenerator:new({
				width = CHUNK_SIZE,
				height = CHUNK_SIZE,
				world = world,
				level = level
			})
		end

		if VERBOSITY >= 4 then
			print("\t\t\tGenerating base level geometry...")
		end
		baseLevel:generate(cursor)

		if VERBOSITY >= 4 then
			print("\t\t\tGenerating enemies...")
		end
		enemies:generate(cursor)

		if VERBOSITY >= 4 then
			print("\t\t\tGenerating distortions...")
		end
		distortions:generate(cursor)

		cursor:move(CHUNK_SIZE, 0)
	end

	cursor.cell = topleft.cell
	local StartGenerator = StartGenerator:new({
		width = levelWidth,
		height = levelHeight
	})
	if VERBOSITY >= 2 then
		print("\tFinding start position...")
	end
	StartGenerator:generate(cursor)

	-- Write the level table to the file
	if VERBOSITY >= 2 then
		print("\tWriting to file...")
	end
	for i, v in ipairs(levelTable) do
		if i > 1 then
			io.write(",", tostring(v))
		else
			io.write(tostring(v))
		end
	end

	-- Set the height for AE mode
	if FORMAT == "AE" then
		io.write(";height=", levelHeight)
	end

	-- Generate the background
	local background = {math.random(0, 255), math.random(0, 255), math.random(0, 255)}

	-- AE combines the background colors into one element
	if FORMAT == "AE" then
		io.write(";background=", table.concat(background, ","))
	-- SE lists each color component as a separate element
	elseif FORMAT == "SE" then
		io.write(";backgroundr=", background[1],
			 ";backgroundg=", background[2],
			 ";backgroundb=", background[3])
	-- 1.6 only had three colors to choose from: Light Blue, Dark Blue, and Black
	else -- mode == "1.6", or there was some weird error
		local b
		if background[3] > 170 then
			b = 3
		elseif background[3] > 85 then
			b = 2
		else
			b = 1
		end
		io.write(";background=", b)
	end

	-- Finish the level
	io.write(";spriteset=", math.random(4))
	io.write(";music=", math.random(2, 6))
	io.write(";timelimit=0")
	io.write(";scrollfactor=0")

	-- Save and close file
	io.output():flush()
	io.output():close()

	if VERBOSITY >= 2 then
		print(string.format("%d-%d complete.", world, level))
	end
end

function setDirectory(d)
	if d and d ~= "" then
		DIRECTORY = d
		return false
	end

	return true
end

function setVerbosity(v)
	number = tonumber(v)
	if number then
		VERBOSITY = number
		return false
	end

	print("Verbosity option must be a number between 0 and 5.")
	return true
end

function setWorlds(w)
	number = tonumber(w)
	if number then
		WORLDS = number
		return false
	end

	print("Worlds option must be a number.")
	return true
end

function setLevels(l)
	number = tonumber(l)
	if number then
		LEVELS = number
		return false
	end

	print("Levels option must be a number.")
	return true
end

function setHeight(h)
	number = tonumber(h)
	if number then
		CHUNK_SIZE = number
		return false
	end

	print("Height must be a number.")
	return true
end

-- Run the script
main()
