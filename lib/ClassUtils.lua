local tea = require(script.Parent.Parent.tea)
local TableUtils = require(script.Parent.TableUtils)
local ClassUtils = {}

local function generateMetatable(Class)
	return {
		__index = Class,
		__tostring = Class.toString,
		__eq = Class.equals,
		__add = Class.__add,
		__sub = Class.__sub,
		__mul = Class.__mul,
		__div = Class.__div,
		__mod = Class.__mod,
		__pow = Class.__pow,
		__unm = Class.__unm,
		__concat = Class.__concat,
		__len = Class.__len,
		__lt = Class.__lt,
		__le = Class.__le
	}
end

function ClassUtils.makeClass(name, constructor, include)
	if type(constructor) == "table" then
		include = constructor
		constructor = nil
	end
	constructor = constructor or function()
			return {}
		end
	local Class = {
		name = name
	}
	setmetatable(
		Class,
		{
			__tostring = function()
				return string.format("Class<%s>", name)
			end
		}
	)
	function Class.new(...)
		local instance = constructor(...)
		assert(type(instance) == "table", "Constructor must return a table")
		setmetatable(instance, generateMetatable(Class))
		instance.Class = Class
		if instance._init then
			instance:_init(...)
		end
		return instance
	end
	function Class.isInstance(value)
		local ok = ClassUtils.isA(value, Class)
		return ok, not ok and string.format("Not a %s instance", name) or nil
	end
	function Class:extend(name, subConstructor)
		local SubClass = ClassUtils.makeClass(name, subConstructor or Class.new)
		setmetatable(SubClass, {__index = self})
		return SubClass
	end
	function Class:extendWithInterface(name, interface)
		local function getComposableInterface(input)
			if input == nil then
				return function()
					return {}
				end
			elseif type(input) == "function" then
				return input
			else
				return function()
					return input
				end
			end
		end
		local inheritedInterface = self.interface
		-- NOTE: Sub interfaces can at present override super interfaces, so this should be avoided
		-- to provide better validation detection / true field type inheritence.
		local compositeInterface = function(Class)
			return TableUtils.assign(
				{},
				getComposableInterface(interface)(Class),
				getComposableInterface(inheritedInterface)(Class)
			)
		end
		local SubClass = ClassUtils.makeClassWithInterface(name, compositeInterface)
		setmetatable(SubClass, {__index = self})
		return SubClass
	end
	if include and include.equals then
		function Class:equals(other)
			assert(ClassUtils.isA(other, Class))
			return TableUtils.shallowMatch(self, other)
		end
	end
	if include and include.toString then
		function Class:toString()
			local string = Class.name .. "("
			local first = true
			local keys = TableUtils.keys(self)
			table.sort(keys)
			for _, key in ipairs(keys) do
				local value = self[key]
				if not first then
					string = string .. ", "
				end
				string = string .. key .. " = " .. tostring(value)
				first = false
			end
			return string .. ")"
		end
	end
	return Class
end

function ClassUtils.makeClassWithInterface(name, interface)
	local function getImplementsInterface(currentInterface)
		local ok, problem = tea.values(tea.callback)(currentInterface)
		assert(ok, string.format([[Class %s does not have a valid interface
%s]], name, tostring(problem)))
		return tea.strictInterface(currentInterface)
	end
	local implementsInterface
	local Class =
		ClassUtils.makeClass(
		name,
		function(data)
			data = data or {}
			local ok, problem = implementsInterface(data)
			assert(ok, string.format([[Class %s cannot be instantiated
%s]], name, tostring(problem)))
			return TableUtils.mapKeys(
				data,
				function(_, key)
					return "_" .. key
				end
			)
		end
	)
	implementsInterface =
		type(interface) == "function" and getImplementsInterface(interface(Class)) or getImplementsInterface(interface)
	Class.interface = interface
	return Class
end

function ClassUtils.makeEnum(keys)
	local enum =
		TableUtils.keyBy(
		keys,
		function(key)
			assert(key:match("^[A-Z_]+$"), "Enum keys must be defined as upper snake case")
			return key
		end
	)

	setmetatable(
		enum,
		{
			__index = function(t, key)
				error(string.format("Attempt to access key %s which is not a valid key of the enum", key))
			end,
			__newindex = function(t, key)
				error(string.format("Attempt to set key %s on enum", key))
			end
		}
	)

	return enum
end

function ClassUtils.applySwitchStrategyForEnum(enum, enumValue, strategies, ...)
	assert(ClassUtils.isA(enumValue, enum), "enumValue must be an instance of enum")
	assert(
		TableUtils.deepEquals(TableUtils.sort(TableUtils.values(enum)), TableUtils.sort(TableUtils.keys(strategies))),
		"keys for strategies must match values for enum"
	)
	assert(tea.values(tea.callback)(strategies), "strategies values must be functions")

	return strategies[enumValue](...)
end

function ClassUtils.makeFinal(object)
	local backend = getmetatable(object)
	local proxy = {
		__index = function(t, key)
			error(string.format("Attempt to access key %s which is missing in final object", key))
		end,
		__newindex = function(t, key)
			error(string.format("Attempt to set key %s on final object", key))
		end
	}
	if backend then
		setmetatable(proxy, backend)
	end

	setmetatable(object, proxy)

	return object
end

function ClassUtils.isA(instance, classOrEnum)
	local isEnum = type(instance) == "string"
	if isEnum then
		local isEnumKeyDefined = type(classOrEnum[instance]) == "string"
		return isEnumKeyDefined
	elseif type(instance) == "table" then
		if instance.__symbol and classOrEnum[instance.__symbol] == instance then
			return true
		end
		local metatable = getmetatable(instance)
		while metatable do
			if metatable.__index == classOrEnum then
				return true
			end
			metatable = getmetatable(metatable.__index)
		end
	end
	return false
end

ClassUtils.Symbol =
	ClassUtils.makeClass(
	"Symbol",
	function(name)
		return {
			__symbol = name
		}
	end,
	{}
)

function ClassUtils.Symbol:toString()
	return self.__symbol
end

function ClassUtils.parseEnumValue(value, ENUM)
	local textValue = tostring(value):upper():gsub("-", "_")
	return ENUM[textValue]
end

return ClassUtils
