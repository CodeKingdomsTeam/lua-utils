local tea = require(script.Parent.Parent.tea)
local TableUtils = require(script.Parent.TableUtils)
local ClassUtils = require(script.Parent.ClassUtils)

local function connectToStore(Class, mapStateToProps)
	local ConnectedClass =
		Class:extendWithInterface(
		"Connected(" .. Class.name .. ")",
		{
			store = tea.interface(
				{
					changed = tea.Signal
				}
			)
		}
	)

	function ConnectedClass:mount()
		self._connection =
			self._store.changed:connect(
			function(state)
				local nextProps = ClassUtils.makeFinal(mapStateToProps(state))
				if self:shouldUpdate(nextProps) then
					self:willUpdate(nextProps)
				end
				self._props = nextProps
			end
		)
		if Class.mount then
			Class.mount(self)
		end
		local nextProps = ClassUtils.makeFinal(mapStateToProps(self._store:getState()))
		self._props = nextProps
		if Class.didMount then
			Class.didMount(self)
		end
	end

	function ConnectedClass:shouldUpdate(nextProps)
		if Class.shouldUpdate then
			return Class.shouldUpdate(self, nextProps)
		end
		return not TableUtils.shallowEqual(self._props, nextProps)
	end

	function ConnectedClass:didMount()
		if Class.didMount then
			Class.didMount(self)
		end
	end

	function ConnectedClass:willUpdate(nextProps)
		if Class.willUpdate then
			Class.willUpdate(self, nextProps)
		end
	end

	function ConnectedClass:destroy()
		if self._connection then
			self._connection:disconnect()
		end
		if Class.destroy then
			Class.destroy(self)
		end
	end

	return ConnectedClass
end

return connectToStore
