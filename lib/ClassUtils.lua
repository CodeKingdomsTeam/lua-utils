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
	constructor = constructor or function()
			return {}
		end
	local Class = {
		name = name,
		constructor = constructor
	}
	function Class.new(...)
		local instance = constructor(...)
		assert(type(instance) == "table", "Constructor must return a table")
		setmetatable(instance, generateMetatable(Class))
		return instance
	end
	function Class:extend(name, constructor)
		local SubClass = ClassUtils.makeClass(name, constructor or self.constructor)
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
			local keys = TableUtils.Keys(self)
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

function ClassUtils.makeConstructedClass(name, constructor)
	constructor = constructor or function()
		end
	local Class
	Class =
		ClassUtils.makeClass(
		name,
		function(data)
			local instance = TableUtils.clone(data)
			if constructor then
				setmetatable(instance, generateMetatable(Class))
				constructor(instance)
			end
			return instance
		end
	)
	Class.constructor = constructor
	function Class:extend(name, constructor)
		local SubClass = ClassUtils.makeConstructedClass(name, constructor)
		setmetatable(SubClass, {__index = self})
		return SubClass
	end
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
				error("Attempt to access key " .. key .. " which is not a valid key of the enum")
			end,
			__newindex = function(t, key)
				error("Attempt to set key " .. key .. " on enum")
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

function ClassUtils.makeSymbolEnum(keys)
	return TableUtils.map(
		ClassUtils.makeEnum(keys),
		function(key)
			return ClassUtils.Symbol.new(key)
		end
	)
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
	end
)

function ClassUtils.Symbol:toString()
	return self.__symbol
end

function ClassUtils.parseEnumValue(value, ENUM)
	local textValue = tostring(value):upper():gsub("-", "_")
	return ENUM[textValue]
end

return ClassUtils
