--!strict

local FunctionButCloned: <T>(T) -> T = clonefunction or function<T>(f: T): T return f end

local GetService: (Instance, string) -> Instance = FunctionButCloned(game.GetService)
local Reference: (Instance) -> Instance = cloneref or function(X: Instance): Instance return X end
local SType: (any) -> string = FunctionButCloned(type)
local SPcall: ((...any) -> ...any, ...any) -> (boolean, ...any) = FunctionButCloned(pcall)
local SPairs: <K, V>({[K]: V}) -> ((any, any) -> (any, any), any, any) = FunctionButCloned(pairs)
local SWarn: (...any) -> () = FunctionButCloned(warn)
local SToString: (any) -> string = FunctionButCloned(tostring)
local SLower: (string) -> string = FunctionButCloned(string.lower)
local SFind: (string, string, number?, boolean?) -> (number?, number?) = FunctionButCloned(string.find)

local Services: {[string]: Instance} = setmetatable({}, {
	__index = function(S: any, N: string): Instance
		S[N] = Reference(GetService(game, N))
		return S[N]
	end
})

type HookOptions = {
	ScriptName: string?,
	FunctionName: string?,
	FunctionAddress: string?,
	FunctionHash: string?,
	ScriptHash: string?,
	Constants: {any}?,
	Upvalues: {string}?
}

type HookEntry = {
	Original: (...any) -> any,
	Active: boolean
}

local Bynew = {
	Hooks = {} :: {[(...any) -> any]: HookEntry}
}

local function GetExecutorName(): string
	local ok: boolean, Name: any = SPcall(identifyexecutor)
	return ok and Name or "idk this executor"
end

local function GetScriptFromFunction(Func: (...any) -> any): LuaSourceContainer?
	if not getscripts then return nil end
	
	local ok: boolean, Info: any = SPcall(debug.getinfo, Func)
	if not ok or not Info or not Info.source then return nil end
	
	local Source: string = Info.source
	if Source:sub(1, 1) == "@" then
		Source = Source:sub(2)
	end
	
	local AllScripts: {LuaSourceContainer} = getscripts()
	for i: number = 1, #AllScripts do
		local Scr: LuaSourceContainer = AllScripts[i]
		if Scr:GetFullName() == Source or Scr.Name == Source then
			return Scr
		end
	end
	
	return nil
end

local function GetFunctionAddress(Func: (...any) -> any): string?
	local Addr: string = SToString(Func)
	local Start: number?, End: number? = SFind(Addr, "0x", 1, true)
	if Start then
		return Addr:sub(Start)
	end
	return nil
end

local function MatchesConstant(A: any, B: any): boolean
	if SType(A) == "string" and SType(B) == "string" then
		return SLower(A) == SLower(B)
	end
	return A == B
end

local function CheckConstants(Func: (...any) -> any, TargetConstants: {any}): boolean
	if not debug.getconstants then return false end
	
	local ok: boolean, Constants: any = SPcall(debug.getconstants, Func)
	if not ok or not Constants then return false end
	
	local Matches: number = 0
	for i: number = 1, #Constants do
		local Const: any = Constants[i]
		for j: number = 1, #TargetConstants do
			if MatchesConstant(Const, TargetConstants[j]) then
				Matches += 1
				break
			end
		end
	end
	
	return Matches == #TargetConstants
end

local function CheckUpvalues(Func: (...any) -> any, TargetUpvalues: {string}): boolean
	if not debug.getupvalues then return false end
	
	local ok: boolean, Upvalues: any = SPcall(debug.getupvalues, Func)
	if not ok or not Upvalues then return false end
	
	local Matches: number = 0
	for Name: any, Value: any in SPairs(Upvalues) do
		if SType(Name) == "string" then
			local LowerName: string = SLower(Name)
			for i: number = 1, #TargetUpvalues do
				if LowerName == SLower(TargetUpvalues[i]) then
					Matches += 1
					break
				end
			end
		end
	end
	
	return Matches == #TargetUpvalues
end

local function CheckScriptName(Info: any, SearchName: string): boolean
	if not Info.source then return false end
	local Source: string = SLower(SToString(Info.source))
	local Search: string = SLower(SearchName)
	return SFind(Source, Search, 1, true) ~= nil
end

local function CheckFunctionName(Info: any, SearchName: string): boolean
	if not Info.name then return false end
	return SLower(Info.name) == SLower(SearchName)
end

local function CheckFunctionAddress(Func: (...any) -> any, TargetAddress: string): boolean
	local Addr: string? = GetFunctionAddress(Func)
	return Addr ~= nil and SLower(Addr) == SLower(TargetAddress)
end

local function CheckFunctionHash(Func: (...any) -> any, TargetHash: string): boolean
	if not getfunctionhash then return false end
	
	local ok: boolean, Hash: any = SPcall(getfunctionhash, Func)
	return ok and Hash == TargetHash
end

local function CheckScriptHash(Func: (...any) -> any, TargetHash: string): boolean
	if not getscripthash then return false end
	
	local Scr: LuaSourceContainer? = GetScriptFromFunction(Func)
	if not Scr then return false end
	
	local ok: boolean, Hash: any = SPcall(getscripthash, Scr)
	return ok and Hash == TargetHash
end

local function ShouldHook(Func: (...any) -> any, Options: HookOptions): boolean
	if not islclosure or not islclosure(Func) then return false end
	
	local ok: boolean, Info: any = SPcall(debug.getinfo, Func)
	if not ok or not Info then return false end
	
	if Options.ScriptName and not CheckScriptName(Info, Options.ScriptName) then
		return false
	end
	
	if Options.FunctionName and not CheckFunctionName(Info, Options.FunctionName) then
		return false
	end
	
	if Options.FunctionAddress and not CheckFunctionAddress(Func, Options.FunctionAddress) then
		return false
	end
	
	if Options.FunctionHash and not CheckFunctionHash(Func, Options.FunctionHash) then
		return false
	end
	
	if Options.ScriptHash and not CheckScriptHash(Func, Options.ScriptHash) then
		return false
	end
	
	if Options.Constants and not CheckConstants(Func, Options.Constants) then
		return false
	end
	
	if Options.Upvalues and not CheckUpvalues(Func, Options.Upvalues) then
		return false
	end
	
	return true
end

local function DisableFunction(Func: (...any) -> any): ()
	if debug.getconstants and debug.setconstant then
		local ok: boolean, Constants: any = SPcall(debug.getconstants, Func)
		if ok and Constants then
			for i: number = 1, #Constants do
				local Const: any = Constants[i]
				local ConstType: string = SType(Const)
				
				if ConstType == "string" then
					SPcall(debug.setconstant, Func, i, "")
				elseif ConstType == "number" then
					SPcall(debug.setconstant, Func, i, 0)
				elseif ConstType == "boolean" then
					SPcall(debug.setconstant, Func, i, false)
				end
			end
		end
	end
	
	if debug.getupvalues and debug.setupvalue then
		local ok: boolean, Upvalues: any = SPcall(debug.getupvalues, Func)
		if ok and Upvalues then
			for Name: any, Value: any in SPairs(Upvalues) do
				SPcall(debug.setupvalue, Func, Name, nil)
			end
		end
	end
	
	if debug.getprotos then
		local ok: boolean, Protos: any = SPcall(debug.getprotos, Func)
		if ok and Protos then
			for i: number = 1, #Protos do
				local Proto: any = Protos[i]
				if SType(Proto) == "function" then
					DisableFunction(Proto)
				end
			end
		end
	end
end

local function GetAllFunctions(): {any}
	if filtergc then
		local ok: boolean, Result: any = SPcall(filtergc, "function")
		if ok and Result then
			return SType(Result) == "table" and Result or {Result}
		end
	end
	
	if getgc then
		return getgc(false)
	end
	
	return {}
end

local function ScanGarbageCollector(): {string}
	local Found: {string} = {}
	local FoundSet: {[string]: boolean} = {}
	
	local Funcs: {any} = getgc and getgc(false) or {}
	local Tables: {any} = getgc and getgc(true) or {}
	
	for i: number = 1, #Funcs do
		local f: any = Funcs[i]
		if SType(f) == "function" then
			if isexecutorclosure and isexecutorclosure(f) then
				continue
			end
			
			if islclosure and not islclosure(f) then
				continue
			end
			
			local ok: boolean, Info: any = SPcall(debug.getinfo, f)
			if ok and Info and Info.source then
				local Source: string = Info.source
				if Source:sub(1, 1) == "@" then
					Source = Source:sub(2)
				end
				
				if not FoundSet[Source] then
					FoundSet[Source] = true
					Found[#Found + 1] = `GC-Function: {Source}`
				end
			end
		end
	end
	
	for i: number = 1, #Tables do
		local t: any = Tables[i]
		if SType(t) == "table" then
			local mt: any = getmetatable(t)
			if mt and SType(mt) == "table" then
				local src: any = rawget(mt, "__source")
				if src and SType(src) == "string" then
					if not FoundSet[src] then
						FoundSet[src] = true
						Found[#Found + 1] = `GC-Table: {src}`
					end
				end
			end
		end
	end
	
	return Found
end

local function ScanRegistry(): {string}
	local Found: {string} = {}
	local FoundSet: {[string]: boolean} = {}
	
	local Reg: {any}? = nil
	
	if getreg then
		SPcall(function(): ()
			Reg = getreg()
		end)
	end
	
	if not Reg and getregistry then
		SPcall(function(): ()
			Reg = getregistry()
		end)
	end
	
	if not Reg then
		return Found
	end
	
	for Idx: number = 1, #Reg do
		local Obj: any = Reg[Idx]
		
		if SType(Obj) == "function" then
			if isexecutorclosure and isexecutorclosure(Obj) then
				continue
			end
			
			if islclosure and not islclosure(Obj) then
				continue
			end
			
			local ok: boolean, Info: any = SPcall(debug.getinfo, Obj)
			if ok and Info and Info.source then
				local Source: string = Info.source
				if Source:sub(1, 1) == "@" then
					Source = Source:sub(2)
				end
				
				if not FoundSet[Source] then
					FoundSet[Source] = true
					Found[#Found + 1] = `Registry-Function: {Source}`
				end
			end
		end
		
		if typeof(Obj) == "thread" and getscriptfromthread then
			SPcall(function(): ()
				local Scr: LuaSourceContainer = getscriptfromthread(Obj)
				if Scr then
					local Path: string = Scr:GetFullName()
					if not FoundSet[Path] then
						FoundSet[Path] = true
						Found[#Found + 1] = `Registry-Thread: {Path}`
					end
				end
			end)
		end
	end
	
	return Found
end

local function ScanNilInstances(): {string}
	local Found: {string} = {}
	
	if not getnilinstances then
		return Found
	end
	
	SPcall(function(): ()
		local NilInst: {Instance} = getnilinstances()
		for Idx: number = 1, #NilInst do
			SPcall(function(): ()
				local Inst: Instance = NilInst[Idx]
				if Inst and (Inst:IsA("LocalScript") or Inst:IsA("ModuleScript")) then
					Found[#Found + 1] = `Nil: {Inst.Name}`
				end
			end)
		end
	end)
	
	return Found
end

local function ScanActors(): {string}
	local Found: {string} = {}
	
	if not getactors then
		return Found
	end
	
	SPcall(function(): ()
		local Actors: {Actor} = getactors()
		for Idx: number = 1, #Actors do
			SPcall(function(): ()
				local Act: Actor = Actors[Idx]
				for DescIdx: number, Desc: Instance in Act:GetDescendants() do
					if Desc:IsA("LocalScript") or Desc:IsA("ModuleScript") then
						Found[#Found + 1] = `Actor: {Desc:GetFullName()}`
					end
				end
			end)
		end
	end)
	
	return Found
end

function Bynew.Find(PossibleAC: string?): {string}
	local Found: {string} = {}
	local FoundSet: {[string]: boolean} = {}
	
	if PossibleAC then
		local Functions: {any} = GetAllFunctions()
		for i: number = 1, #Functions do
			local Func: any = Functions[i]
			if SType(Func) == "function" then
				local ok: boolean, Info: any = SPcall(debug.getinfo, Func)
				if ok and Info and Info.source then
					local Source: string = SLower(SToString(Info.source))
					if SFind(Source, SLower(PossibleAC), 1, true) then
						if not FoundSet[Info.source] then
							FoundSet[Info.source] = true
							Found[#Found + 1] = Info.source
						end
					end
				end
			end
		end
	else
		local GCResults: {string} = ScanGarbageCollector()
		for i: number = 1, #GCResults do
			if not FoundSet[GCResults[i]] then
				FoundSet[GCResults[i]] = true
				Found[#Found + 1] = GCResults[i]
			end
		end
		
		local RegResults: {string} = ScanRegistry()
		for i: number = 1, #RegResults do
			if not FoundSet[RegResults[i]] then
				FoundSet[RegResults[i]] = true
				Found[#Found + 1] = RegResults[i]
			end
		end
		
		local NilResults: {string} = ScanNilInstances()
		for i: number = 1, #NilResults do
			if not FoundSet[NilResults[i]] then
				FoundSet[NilResults[i]] = true
				Found[#Found + 1] = NilResults[i]
			end
		end
		
		local ActorResults: {string} = ScanActors()
		for i: number = 1, #ActorResults do
			if not FoundSet[ActorResults[i]] then
				FoundSet[ActorResults[i]] = true
				Found[#Found + 1] = ActorResults[i]
			end
		end
		
		local ok: boolean, RepFirst: any = SPcall(function(): Instance
			return Services.ReplicatedFirst
		end)
		
		if ok and RepFirst then
			for idx: number, Child: Instance in RepFirst:GetDescendants() do
				if Child:IsA("LocalScript") or Child:IsA("ModuleScript") then
					local Path: string = `ReplicatedFirst: {Child:GetFullName()}`
					if not FoundSet[Path] then
						FoundSet[Path] = true
						Found[#Found + 1] = Path
					end
				end
			end
		end
	end
	
	if #Found > 0 then
		for i: number = 1, #Found do
			SWarn(Found[i])
		end
	end
	
	if setclipboard then
		setclipboard(table.concat(Found, "\n"))
	elseif toclipboard then
		toclipboard(table.concat(Found, "\n"))
	end
	
	return Found
end

function Bynew.Hook(Options: string | HookOptions, Callback: ((fn: (...any) -> any) -> ())?): number
	if not (getgc or filtergc) then
		SWarn(`[{GetExecutorName()}] doesn't support: getgc or filtergc`)
		return 0
	end
	
	local HookOpts: HookOptions = SType(Options) == "string" and {ScriptName = Options} or Options
	local Functions: {any} = GetAllFunctions()
	local Hooked: number = 0
	
	for i: number = 1, #Functions do
		local Func: any = Functions[i]
		
		if SType(Func) == "function" and ShouldHook(Func, HookOpts) then
			if not Bynew.Hooks[Func] or not Bynew.Hooks[Func].Active then
				local Original: (...any) -> any = FunctionButCloned(Func)
				
				if Callback then
					Callback(Func)
				else
					DisableFunction(Func)
				end
				
				Bynew.Hooks[Func] = {
					Original = Original,
					Active = true
				}
				
				Hooked += 1
			end
		end
	end
	
	return Hooked
end

function Bynew.Replace(Options: string | HookOptions, Replacement: (...any) -> any): number
	if not hookfunction then
		SWarn(`[{GetExecutorName()}] doesn't support: hookfunction`)
		return 0
	end
	
	local HookOpts: HookOptions = SType(Options) == "string" and {ScriptName = Options} or Options
	local Functions: {any} = GetAllFunctions()
	local Replaced: number = 0
	
	for i: number = 1, #Functions do
		local Func: any = Functions[i]
		
		if SType(Func) == "function" and ShouldHook(Func, HookOpts) then
			if not Bynew.Hooks[Func] or not Bynew.Hooks[Func].Active then
				local Original: (...any) -> any = hookfunction(Func, Replacement)
				
				Bynew.Hooks[Func] = {
					Original = Original,
					Active = true
				}
				
				Replaced += 1
			end
		end
	end
	
	return Replaced
end

function Bynew.Restore(Options: string | HookOptions?): number
	if not restorefunction then
		SWarn(`[{GetExecutorName()}] doesn't support: restorefunction`)
		return 0
	end
	
	if not Options then
		local Restored: number = 0
		for Func: any, Entry: any in SPairs(Bynew.Hooks) do
			if Entry.Active then
				SPcall(restorefunction, Func)
				Entry.Active = false
				Restored += 1
			end
		end
		return Restored
	end
	
	local HookOpts: HookOptions = SType(Options) == "string" and {ScriptName = Options} or Options
	local Restored: number = 0
	
	for Func: any, Entry: any in SPairs(Bynew.Hooks) do
		if Entry.Active and ShouldHook(Func, HookOpts) then
			SPcall(restorefunction, Func)
			Entry.Active = false
			Restored += 1
		end
	end
	
	return Restored
end

return Bynew
