--[[
	SkillService.lua
	Function: Handles all skill logic and hitbox interactions server-side.
	Libraries: Knit Framework
	Last Updated: 31/10/2025
	Author: coolguy3338/isaquinhoo
	Notes:
	-- Each skill is registered in SkillService.Skills
	-- Uses HitboxService to handle hitbox logic
	-- Uses VFXService to send VFX to the client
	-- I've already sent this code to application once and they said that it was too nested and indented
	-- I dont know how to handle physics T-T
]]

-- OK SO WTH, i sent this code again for application AND IT GOT REJECTED!!! FOR "Not having enough commentary"
-- BRO I COMMENTED THIS ENTIRE CODE, WHAT DO YOU WANT ME TO DO, YOU WANT ME TO COMMENT EACH SINGLE LINE?????
-- OK, i'm going to comment more, ALSO that was the only complain from the response so NEXT TIME YOU GUYS ARE GOING
-- TO ACCEPT RIGHT?????

--// Service Setup -------------------------------------------------------------
local Knit = require(game.ReplicatedStorage:WaitForChild("Packages").Knit)
local SkillService = Knit.CreateService {
	Name = "SkillService",
	Client = {}
}

-- Dependancies
local HitboxService = nil
local ClientManager = nil
local VFXService = nil
local ClientManager = nil
local runservice = game:GetService("RunService")


--// Helper functions ----------------------------------------------------------
-- General functions -------------------------

-- Applys impulse to a part in the center of mass
function ApplyImpulse(part : Part, impulse : Vector3)
	part:ApplyImpulseAtPosition(impulse * part.AssemblyMass, part.AssemblyCenterOfMass)
end

-- Used for translating body part names to Motor6D names for ragdolling
function TranslateToMotor6D(name : string)
	if name == "Left Arm" then
		return "Left Shoulder"
	elseif name == "Right Arm" then
		return "Right Shoulder"
	elseif name == "Left Leg" then
		return "Left Hip"
	elseif name == "Right Leg" then
		return "Right Hip"
	elseif name == "Head" then
		return "Neck"
	end
end

-- Used for detaching body parts for gore effects
function DetachBodyPart(character : Model, bodypartname : string) 
	local torso:Part = character:FindFirstChild("Torso")
	local bodypart:Part = character:FindFirstChild(bodypartname)
	local bloodemitter = bodypart:FindFirstChild("BloodEmitter")
	local translated = TranslateToMotor6D(bodypartname)
	
	-- Checking the variables
	if not bodypart or not bloodemitter or not translated then return end
	
	-- Makes it so that the part doesnt phase through the ground
	bodypart.CanCollide  = true

	-- Goes through every single constraint in the torso and deletes them to detach the body part
	for _, constraint:BallSocketConstraint in torso:GetChildren() do
		if not constraint:IsA("BallSocketConstraint") then continue end
		if constraint.Name ~= "RagdollConstraint" .. translated then continue end -- The constraints are called RagdollConstraint
		
		constraint:Destroy()
	end
	
	-- Goes through all the blood particle emitters and enables them
	for _, particle in bloodemitter:GetChildren() do
		if not particle:IsA("ParticleEmitter") then continue end
		
		particle.Enabled = true
	end
	
	
end

-- Welds one part to ther other using WeldConstraint
function Weld(part0:Part, part1:Part)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = part0
	weld.Part1 = part1
	weld.Parent = part0
end

-- Checks for the nearest character to a certain part and ignores another specified part
function FindNearestCharacterAroundPart(part : Part, parttoignore : Part?) : Part
	local listofparts = {}
	local numblist = {}
	
	-- Looks through the workspace for characters and puts their rootpart and distance in a table
	for _, character in workspace:GetChildren() do
		if character:IsA("Model") and character:FindFirstChildOfClass("Humanoid") then
			if character == part.Parent or character == parttoignore.Parent or game:GetService("CollectionService"):HasTag(character, "Ignore") then continue end
			
			listofparts[character:FindFirstChild("HumanoidRootPart")] = (character:FindFirstChild("HumanoidRootPart").Position - part.Position).Magnitude
			table.insert(numblist, (character:FindFirstChild("HumanoidRootPart").Position - part.Position).Magnitude)
		end
	end
	
	-- Does the same but with the NPCS folder which contains non-playable characters
	for _, character in workspace.NPCS:GetChildren() do
		if character:IsA("Model") and character:FindFirstChildOfClass("Humanoid") then
			if character == part.Parent or character == parttoignore.Parent or game:GetService("CollectionService"):HasTag(character, "Ignore") or not part
			or not character:FindFirstChild("HumanoidRootPart") then continue end

			listofparts[character:FindFirstChild("HumanoidRootPart")] = (character:FindFirstChild("HumanoidRootPart").Position - part.Position).Magnitude
			table.insert(numblist, (character:FindFirstChild("HumanoidRootPart").Position - part.Position).Magnitude)
		end
	end
	
	-- Sorts the table and returns the part that is closest to the part that it is checking
	local lowest = math.min(table.unpack(numblist)) -- Returns the lowest value of the numblist
	local nearest -- Will be assigned a value later
	
	-- Sorting process
	for part, distance in listofparts do
		if distance == lowest then -- If distance is the lowest then return it and the distance
			nearest = part
			return nearest, distance
		end
	end
	
	
end

-- Used later to convert the player's backpack to a table
function convertBackpackToTable(backpack : {Tool})
	local converted = {}

	for _, tool in backpack do -- Goes through the backpack and inserts every tool into a table
		table.insert(converted, tool.Name)
	end

	return converted
end

-- Checks if the player isnt trying to use the skill while dead or stunned
function CanUseSkill(character:Model) 
	local hum = character:FindFirstChildOfClass("Humanoid")
	return hum.Health > 0 and not character:GetAttribute("IsRagdoll") -- If the player is dead or ragdolled then return false
end

-- Ragdolls the player for a certain time
function Ragdoll(character, duration)
	task.spawn(function() -- Creates a thread
		character:SetAttribute("IsRagdoll", true)
		task.wait(duration)
		character:SetAttribute("IsRagdoll", false)
	end)
end

-- Flips a "coin" and gets 1 or 2.
function FlipCoin()
	local coinside = math.random(1, 2) -- Randomizes a value between 1 and 2 to represent each side
	return coinside
end

-- Used for sills like AnnoyingBugs
function Countdown(duration)
	for i = duration, 1, -1 do -- For every second it decreases 1 from duration
		print(i)
		task.wait(1)
	end
end

-- Ok, so for some reason game.Debris wasnt working so i made my own
-- Schedules the item to be destroyed later
function DebrisAddItem(instance, lifetime)
	task.spawn(function()
		task.wait(lifetime)
		instance:Destroy()
	end)
end
-- Specific functions -----------------------


function BonesHitboxLogic(humrootpart, characterhit)
	task.spawn(function() -- Creates a thread
		local enemyhum = characterhit:FindFirstChildOfClass("Humanoid")
		local enemytorso = characterhit:FindFirstChild("Torso")

	
		if characterhit:GetAttribute("State") == "Ragdoll" and enemyhum.Health > 10 then
			ApplyImpulse(enemytorso, (humrootpart.CFrame.LookVector * 75) + Vector3.new(0, 300, 0)) -- Applies an impulse
			VFXService:CastVFXToAllClients("Ragdoll", characterhit) -- Casts the FX
		elseif enemyhum.Health <= 10 then
			Ragdoll(characterhit, 999)
			task.wait(0.2)

			ApplyImpulse(enemytorso, (humrootpart.CFrame.LookVector * 50) + Vector3.new(0, 500, 0))
			VFXService:CastVFXToAllClients("Ragdoll", characterhit)
		end

		enemyhum:TakeDamage(10)
	end)
	
	
end

function DismantleHitboxLogic(humrootpart, characterhit, hitboxresult)
	-- Ok, so i used a task.spawn here, cuz some times the attack hits multiple targets
	task.spawn(function()

		local enemyhum = characterhit:FindFirstChildOfClass("Humanoid")
		local enemytorso = characterhit:FindFirstChild("Torso")
		local enemyhumrootpart = characterhit:FindFirstChild("HumanoidRootPart")

		-- Creates a slash sound in the enemy torso
		local hitslashsfx = game.SoundService.VFX.Slash:Clone()
		hitslashsfx.Parent = enemytorso
		hitslashsfx:Play()

		task.defer(function() -- Creates a thread that will be runned later
			task.wait(2)
			hitslashsfx:Destroy()
		end)

		-- This is used for a finisher that slices the player in half
		-- Gojo reference
		if table.find(hitboxresult.partsHit, enemytorso or enemyhumrootpart) and enemyhum.Health <= 30 then
			enemyhum.Health = 0
			Ragdoll(characterhit, 999)
			task.wait(0.1)
			DetachBodyPart(characterhit, "Left Leg")
			DetachBodyPart(characterhit, "Right Leg")

			enemytorso:ApplyImpulse((humrootpart.CFrame.LookVector * 500) + Vector3.new(0, 500, 0)) -- Applies an impulse

			-- Goes through every single blood particle and enables them
			for _, particle in enemytorso:FindFirstChild("BloodEmitter"):GetChildren() do
				if not particle:IsA("ParticleEmitter") then continue end

				particle.Enabled = true
			end



		else -- If the hit wasn't a finisher
			enemyhum:TakeDamage(30)
			Ragdoll(characterhit, 1)
			task.wait(0.1)
			enemytorso:ApplyImpulse(humrootpart.CFrame.LookVector * 500)
			task.wait(1)
			characterhit:SetAttribute("IsRagdoll", false)
		end



	end)
end

function BasicHitboxLogic(characterhit, damage)
	task.spawn(function() -- Creates another thread
		local enemyhum = characterhit:FindFirstChildOfClass("Humanoid")
		enemyhum:TakeDamage(damage)
	end)
end

--// Skills Dictionary --------------------------------------------------------------

-- Each skill has a function that is called when the skill is used
-- Some functions/skills need extra parameters like mouse position and that is handled in SkillUse()
-- I'll explain what each skills does in case you haven't played the game
SkillService.Skills = {
	--[[
		Description: It explodes the character, by detaching every body part and emitting blood.
		Duration: 0.1
		Brief note: To this moment it does not apply damage
	]]
	["SelfExplosion"] = function(player:Player)
		local character = player.Character
		local hum = character:FindFirstChildOfClass("Humanoid")
		local torso = character:FindFirstChild("Torso")
		local rightleg = character:FindFirstChild("Right Leg")
		local leftleg = character:FindFirstChild("Left Leg")
		
		if not CanUseSkill(character) then return end
		
		Ragdoll(character, 999)
		
		task.wait(0.1)
		
		DetachBodyPart(character, "Right Arm")
		DetachBodyPart(character, "Left Arm")
		DetachBodyPart(character, "Left Leg")
		DetachBodyPart(character, "Right Leg")
		DetachBodyPart(character, "Head")
		
		torso:ApplyImpulse(Vector3.new(0, 25, 0))
		
		hum.Health = 0
	end,
	
	--[[
		Description: This skill creates a warning VFX and then it creates a hitbox 
		that damages the player if they touch it
		Duration: 0.8
	]]
	["Bones"] = function(player:Player, cframe : CFrame)
		local MAX_DISTANCE = 50
		local character = player.Character
		local humrootpart:Part = character:FindFirstChild("HumanoidRootPart")
		local hum = character:FindFirstChildOfClass("Humanoid")
		
		-- Checks if there isnt a CFrame, if the distance of the target isnt too far, and if the character isnt dead or ragdolled
		if not cframe then return end
		if (humrootpart.CFrame.Position - cframe.Position).Magnitude > MAX_DISTANCE then return end
		if not CanUseSkill(character) then return end
		
		
		-- Sets the hitbox parameters
		local overlapparams = OverlapParams.new()
		overlapparams.FilterType = Enum.RaycastFilterType.Exclude
		overlapparams.FilterDescendantsInstances = {player.Character}
		
		local hitboxparams = {
			Size = Vector3.new(12, 7.299, 12),
			CFrame = cframe * CFrame.new(0, -(6.9 / 2), 0),
			OverlapParams = overlapparams,
			hitsRagdolls = true
		}
		
		-- Casts the VFX to all Players
		VFXService:CastVFXToAllClients("Bones", player, cframe)
		
		-- Waits for 0.8 seconds so that the warning vfx can happen
		task.wait(0.8)
		
		-- Hitbox Logic
		local hitboxresult = HitboxService.newstatichitbox(hitboxparams)
		if not hitboxresult.hitSomething then -- If it didnt hit anyone
			return
		else
			-- Goes through every single character and applies hitbox logic to them
			for _, characterhit:Model in hitboxresult.charactersHit do
				BonesHitboxLogic(humrootpart, characterhit)
			end
		end
	end,
	
	--[[
		Description: Creates a slash that goes forward and slices players with low health
		Duration: 0.8
		Brief note: Based on Dismantle from Sukuna JJK
	]]
	["Dismantle"] = function(player:Player, cframe:CFrame, randomtilt : number)
		local character = player.Character
		local humrootpart = character:FindFirstChild("HumanoidRootPart")
		local hum = character:FindFirstChildOfClass("Humanoid")
		
		-- Checks if the player is dead or stunned
		if CanUseSkill(character) then return end
		
		-- Sets the hitbox parameters
		local overlapparams = OverlapParams.new()
		overlapparams.FilterType = Enum.RaycastFilterType.Exclude
		overlapparams.FilterDescendantsInstances = {character}

		local hitboxparams = {
			Size = Vector3.new(22.864, 5, 52.286),
			CFrame = cframe * CFrame.new(0, 0, -25) * CFrame.Angles(0, 0, randomtilt),
			OverlapParams = overlapparams,
			hitsRagdolls = true
		}

		-- Creates the hitbox
		local hitboxresult = HitboxService.newstatichitbox(hitboxparams)

		-- Checks if the hitbox hit something
		if hitboxresult.hitSomething == false then
			return
		else
			-- Goes through every single character that was hit from the hitbox
			for _, characterhit:Model in hitboxresult.charactersHit do
				if characterhit == character then continue end -- Makes sure to not hit the player that used the attack
				DismantleHitboxLogic(humrootpart, characterhit, hitboxresult)
			end
		end
		
	end,
	
	--[[
		Description: Summons a bug that runs after the nearest enemy and explodes itself after some time
		similar to a time bomb.
		Duration: 2.5
		Brief note: Uses c00lkid as the bug
	]]
	["AnnoyingBugs"] = function(player:Player)
		local character = player.Character
		local humrootpart = character:FindFirstChild("HumanoidRootPart")
		local hum = character:FindFirstChildOfClass("Humanoid")

		if not CanUseSkill(character) then return end
		
		local annoyingbug = game.ReplicatedStorage.VFX.BugSummon.annoyingbug:Clone()
		local bombfuse = game.SoundService.VFX.BombFuse:Clone()
		local laterexplosion = Instance.new("Explosion")
		local classicexplosionsfx = game.SoundService.VFX.ClassicExplosion:Clone()
		laterexplosion.BlastRadius = 0
		laterexplosion.BlastPressure = 0
		laterexplosion.DestroyJointRadiusPercent = 0
		local infinitejumpConnect = annoyingbug.AttributeChanged:Connect(function(attribute) -- Its used later to make the creature jump when close to the enemy
			if attribute == "InfiniteJump" then
				task.spawn(function()
					while annoyingbug:GetAttribute("InfiniteJump") == true do
						annoyingbug.Humanoid.Jump = true
						task.wait(0.2)
					end
				end)
			end
		end)
		bombfuse.Parent = annoyingbug.Head
		bombfuse.Looped = true
		annoyingbug.Parent = workspace.NPCS
		annoyingbug.HumanoidRootPart.Anchored = false
		classicexplosionsfx.Parent = annoyingbug.HumanoidRootPart
		
		-- Used to randomize which side the creature is coming from
		local flipcoin = FlipCoin()
		if FlipCoin() == 1 then
			annoyingbug:PivotTo(humrootpart.CFrame * CFrame.new(-math.random(5, 10), 0, 0)) -- Pivots the character to his left side
		else
			annoyingbug:PivotTo(humrootpart.CFrame * CFrame.new(math.random(5, 10), 0, 0)) -- Pivots the character to his right side
		end
		
		-- Creates a red smoke similar to Naruto Shadow Clone Jutsu
		VFXService:CastVFXToAllClients("Summon", annoyingbug.HumanoidRootPart.CFrame, 
			annoyingbug.HumanoidRootPart, ColorSequence.new(Color3.fromRGB(255, 0, 0)))
		bombfuse:Play()
		
		local starttime = tick() -- Starts the time
		task.spawn(function() -- Makes the creature run towards the nearest enemy
			while (tick() - starttime) < 3 do -- While there has not been 3 seconds
				local nearestpart, distance = FindNearestCharacterAroundPart(annoyingbug.HumanoidRootPart, humrootpart)

				if distance < 20 then
					annoyingbug:SetAttribute("InfiniteJump", true)
					if annoyingbug.Humanoid.FloorMaterial ~= Enum.Material.Air then -- If the creature is already jumping
						annoyingbug.Humanoid:ChangeState(Enum.HumanoidStateType.Jumping) -- Changes the state to stop the MoveTo from interfering
					end
				else
					annoyingbug:SetAttribute("InfiniteJump", false)
					annoyingbug.Humanoid:ChangeState(Enum.HumanoidStateType.Running) -- Goes back to running
				end

				annoyingbug.Humanoid:MoveTo(nearestpart.Position + Vector3.new(0, 0, -2)) -- Goes to the enemy's front
				task.wait(0.2)
			end
		end)

		Countdown(3) -- Counts to three
		annoyingbug.Humanoid.Health = 0
		bombfuse:Destroy()
		annoyingbug.Head.Fuse.Fire.Fire.Enabled = false

		-- Hitbox logic
		local overlapparams = OverlapParams.new()
		overlapparams.FilterType = Enum.RaycastFilterType.Exclude
		overlapparams.FilterDescendantsInstances = {character}
		local hitboxparams = {
			Size = Vector3.new(20, 20, 20),
			CFrame = annoyingbug.HumanoidRootPart.CFrame,
			OverlapParams = overlapparams,
			hitsRagdolls = true
		}
		local hitboxresult = HitboxService.newstatichitbox(hitboxparams)
		if hitboxresult.hitSomething == false then return end -- Checks if the hitbox hit something
		for _, characterhit:Model in hitboxresult.charactersHit do -- Goes through every character that was hit
			print(characterhit)
			BasicHitboxLogic(characterhit, 40) -- Applies damage to them
		end
		
		-- Makes the explosion effect
		laterexplosion.Position = annoyingbug.HumanoidRootPart.Position
		laterexplosion.Parent = workspace
		infinitejumpConnect:Disconnect()
		annoyingbug:Destroy()
		
		-- Schedules the explosion instance to be destroyed
		DebrisAddItem(laterexplosion, 2)
		
	end,
	
	--[[
		Description: Casts a Fireball that targets the player's mouse position and explodes on impact,
		dealing damage
		Duration: Variable
		Brief note: Uses a Quadratic Bezier to make a curve effect on the Fireball's path,
		anticipates the positions for performance and approximates the curve lenght to avoid lag,
		vizualizeRay is meant for debugging reasons
	]]
	["Fireball"] = function(player:Player, mousepos:Vector3)
		local character = player.Character
		local humrootpart:Part = character:FindFirstChild("HumanoidRootPart")
		local hum = character:FindFirstChildOfClass("Humanoid")

		if not CanUseSkill(character) then return end

		-- Quadratic Bezier function
		local function bezier(p0, p1, p2, t) -- Dont expect me to explain this
			return (1 - t)^2 * p0 + 2 * (1 - t) * t * p1 + t^2 * p2 -- LOTS OF MATH
		end

		-- Approximates the curve's length
		local function approximateLength(p0, p1, p2, steps) -- Ok this is used to avoid when the player uses the fireball too near of themselves
			local length = 0
			local prev = p0
			for i = 1, steps do
				local t = i / steps
				local pos = bezier(p0, p1, p2, t)
				length += (pos - prev).Magnitude
				prev = pos
			end
			return length
		end
		-- Curve points
		local start = (humrootpart.CFrame * CFrame.new(0, 0, 2)).Position -- The player's front
		local endpoint = mousepos -- The mouse's position
		-- In the middle but with a randomized offset
		local middle = (humrootpart.CFrame * CFrame.new(0, math.random(-10, 10), 0)) * CFrame.new(math.random(-(endpoint - start).Magnitude / 2, (endpoint - start).Magnitude / 2), 0, 0).Position
		local finish -- To be assigned later in the code
		-- Effects to the client
		VFXService:CastVFXToAllClients("FireballCast", player)
		VFXService:CastVFXToAllClients("Fireball", player, mousepos, middle)

		-- Defining the curve
		local curveLength = approximateLength(start, middle, endpoint, 15) -- This value derermines the smoothness
		local spacing = 1
		local segments = math.floor(curveLength / spacing)
		
		-- This is used later
		local raycastHit = false
		local raycastparams = RaycastParams.new()
		raycastparams.RespectCanCollide = true
		local resultCFrame:CFrame
		local partHit = false
		
		-- This pre-assigns every step of the curve and puts them onto a table
		local positions = {}
		for i = 0, segments do
			local t = i / segments
			table.insert(positions, bezier(start, middle, endpoint, t))
		end
		
		-- Creates the curve
		for i = 2, #positions - 1 do
			-- Defining the direction which t he fireball must be headed to
			local origin = positions[i]
			local target = positions[i + 1]
			local direction = target - origin
			
			-- Raycasts the fireball to see if there's any obstacle
			-- This is useful so that the fireball cant phase throug objects
			local raycastResult = workspace:Raycast(origin, direction, raycastparams)
			if raycastResult and raycastResult.Instance and raycastResult.Instance.Parent ~= character then
				finish = raycastResult.Position
				resultCFrame = CFrame.new(raycastResult.Position, raycastResult.Position + raycastResult.Normal) * CFrame.Angles(math.rad(90), 0, 0)
				raycastHit = true
				break
			end
			if raycastHit == true or partHit == true then break end
			
			task.wait(0.01) -- adjust for speed
		end
		
		if finish == nil then finish = endpoint end
		
		-- Creates a part to vizualize the next raycast
		local function visualizeRay(origin, direction, duration, color) -- Only used for debugging
			duration = duration or 0.1 -- seconds to stay in the world
			color = color or Color3.fromRGB(255, 0, 0)

			-- Create a thin Part to represent the ray
			local rayPart = Instance.new("Part")
			rayPart.Anchored = true
			rayPart.CanCollide = false
			rayPart.Material = Enum.Material.Neon
			rayPart.Color = color

			local length = direction.Magnitude
			rayPart.Size = Vector3.new(0.1, 0.1, length) -- very thin part
			rayPart.CFrame = CFrame.new(origin + direction/2, origin + direction) -- center and point along direction
			rayPart.Parent = workspace

			-- Remove it after 'duration'
			DebrisAddItem(rayPart, duration)
		end
		
		
		-- Raycasts to see if the fireball is near or hit the ground
		local raycastResult = workspace:Raycast(finish + Vector3.new(0, 5, 0), Vector3.new(0, -10, 0), raycastparams)
		if raycastResult ~= nil then -- Creates a FireArea on the ground
			VFXService:CastVFXToAllClients("FireArea", player, raycastResult.Position)
		end
		
		if not resultCFrame then
			VFXService:CastVFXToAllClients("FireballExplosion", player, resultCFrame or CFrame.new(finish.X, finish.Y, finish.Z), Vector3.new(math.random(45, 180), math.random(45, 180), math.random(45, 180)))
		else -- If the fieball hit some obstacle, then the explosion should match the collision area
			VFXService:CastVFXToAllClients("FireballExplosion", player, resultCFrame or CFrame.new(finish.X, finish.Y, finish.Z))
		end
		
		-- Hitbox logic
		local overlapparams = OverlapParams.new()
		overlapparams.FilterType = Enum.RaycastFilterType.Exclude
		overlapparams.FilterDescendantsInstances = {character}

		local hitboxparams = {
			Size = Vector3.new(20, 20, 20),
			CFrame = resultCFrame or CFrame.new(finish.X, finish.Y, finish.Z),
			OverlapParams = overlapparams,
			hitsRagdolls = true
		}

		local hitbox = HitboxService.newstatichitbox(hitboxparams)

		for _, characterhit in hitbox.charactersHit do -- Goes through every single character hit
			BasicHitboxLogic(characterhit, 20)
		end
	end,
	
	----[[
	--	Description: Was meant for a cutscene, but right now its useless.
	--]]
	--["UltimateShowcase"] = function(player:Player)
	--	local character = player.Character
	--	local humrootpart:Part = character:FindFirstChild("HumanoidRootPart")
	--	local hum = character:FindFirstChildOfClass("Humanoid")
		
	--	if hum.Health <= 0 or character:GetAttribute("IsRagdoll") == true then return end

	--	local HitboxService = Knit.GetService("HitboxService")
	--	local ClientManager = Knit.GetService("ClientManager")
	--	local VFXService = Knit.GetService("VFXService")
		
	--	VFXService:CastVFXToAllClients("UltimateShowcase", player)
		
		
	--end,
}

--[[
	This function is called when Knit starts.
]]
function SkillService:KnitStart()
	HitboxService = Knit.GetService("HitboxService")
	ClientManager = Knit.GetService("ClientManager")
	VFXService = Knit.GetService("VFXService")
	print("SkillService started!")
end

--[[
	This functions is called from the client,
	and the client will send the skill name, and the parameters needed for the skill.
	For example, the player wants to use the "Fireball" skill, the client will send the skill name, 
	and the position of the mouse.
	Then the server will check if the player has the skill, and if the player is in range of the skill.
	Then the server will execute the skill, and the server will send the vfx to all clients.
]]
function SkillService:UseSkill(player : Player, skill : string, ...)
	local character = player.Character
	local hum = character:FindFirstChildOfClass("Humanoid")
	local clientdata = ClientManager:getClient(player) -- Trusting source of the player's moveset, comes from the server.
	local clientmoveset = convertBackpackToTable(clientdata.Moveset)

	if not CanUseSkill(character) then return end -- Checks if the player is dead or ragdolled
	if not table.find(clientmoveset, skill) then  -- Checks if there is the skill's name in the table
		print("player dont got the move neccessary!")
		return 
	end
	
	-- Goes through the SkillService.Skills and executes the function assigned
	local skill = self.Skills[skill]
	if skill then skill(player, ...) end
end

--[[
	This is the client side of the skill service.
	The client will send the skill name, and the parameters needed for the skill.
]]
function SkillService.Client:UseSkill(player : Player, skill : string, ...)
	local char = player.Character
	local hum = char:FindFirstChildOfClass("Humanoid")

	self.Server:UseSkill(player, skill, ...) -- Calls the functions before
end

return SkillService
