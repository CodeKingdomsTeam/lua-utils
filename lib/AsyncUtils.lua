local TableUtils = require(script.Parent.TableUtils)
local Promise = require(script.Parent.Parent.Promise)
local AsyncUtils = {}

local baseRandomStream = Random.new()

--[[
    Given an array of objects, this function returns a promise which
    resolves once all of the array elements have resolved, or rejects
    if any of the array elements reject.

    Any objects in the array which aren't promises are considered
    resolved immediately.

    The promise resolves to an array mapping the input to resolved elements.
]]
function AsyncUtils.parallel(things)
	local promises =
		TableUtils.Map(
		things,
		function(thing)
			if Promise.is(thing) then
				return thing
			else
				return Promise.resolve(thing)
			end
		end
	)
	return Promise.all(promises)
end

--[[
    Given a table, this function returns a promise which
    resolves once all of the table values have resolved, or rejects
    if any of the array elements reject.

    Any values in the table which aren't promises are considered
    resolved immediately.

    The promise resolves to a table mapping the input table keys to resolved values.
]]
function AsyncUtils.props(things)
	local keys = TableUtils.Keys(things)
	local values =
		TableUtils.Map(
		keys,
		function(key)
			return things[key]
		end
	)
	return AsyncUtils.parallel(values):andThen(
		function(output)
			return TableUtils.KeyBy(
				output,
				function(value, i)
					return keys[i]
				end
			)
		end
	)
end

--[[
    Returns a promise which resolves after the given delayInSeconds.
]]
function AsyncUtils.delay(delayInSeconds)
	assert(type(delayInSeconds) == "number")
	return Promise.new(
		function(resolve)
			delay(
				delayInSeconds,
				function()
					resolve()
				end
			)
		end
	)
end

--[[
    Returns a promise for a function which may yield. wrapAsync calls the
    the function in a coroutine and resolves with the output of the function
    after any asynchronous actions, and rejects if the function throws an error.
]]
function AsyncUtils.wrapAsync(fn)
	assert(type(fn) == "function")
	return Promise.new(
		function(resolve, reject)
			coroutine.wrap(
				function()
					local ok, result = pcall(fn)
					if ok then
						resolve(result)
					else
						reject(result)
					end
				end
			)()
		end
	)
end

--[[
    Try running a function which returns a promise and retry if the function throws
    and error or the promise rejects. The retry behaviour can be adapted using
    backoffOptions, which can customize the maximum number of retries and the backoff
    timing of the form [0, x^attemptNumber] + y where x is an exponent that produces
    a random exponential delay and y is a constant delay.

    maxTries - how many tries (including the first one) the function should be called
    retryExponentInSeconds - customize the backoff exponent
	retryConstantInSeconds - customize the backoff constant
    randomStream - use a Roblox "Random" instance to control the backoff
	shouldRetry(response) - called if maxTries > 1 to determine whether a retry should occur
    onRetry(waitTime, errorMessage) - a hook for when a retry is triggered, with the delay before retry and error message which caused the failure
    onDone(response, durationMs) - a hook for when the promise resolves
    onFail(errorMessage) - a hook for when the promise has failed and no more retries are allowed
]]
function AsyncUtils.retryWithBackoff(getPromise, backoffOptions)
	assert(type(getPromise) == "function")
	local function backoffThenRetry(errorMessage)
		local waitTime =
			(backoffOptions.retryExponentInSeconds ^ backoffOptions.attemptNumber) * backoffOptions.randomStream:NextNumber() +
			backoffOptions.retryConstantInSeconds
		backoffOptions.onRetry(waitTime, errorMessage)
		return AsyncUtils.delay(waitTime):andThen(
			function()
				return AsyncUtils.retryWithBackoff(
					getPromise,
					TableUtils.Assign(
						{},
						backoffOptions,
						{
							maxTries = backoffOptions.maxTries - 1,
							attemptNumber = backoffOptions.attemptNumber + 1
						}
					)
				)
			end
		)
	end

	local function getDurationMs()
		return math.floor((tick() - backoffOptions.startTime) * 1000)
	end

	backoffOptions =
		TableUtils.Assign(
		{
			startTime = tick(),
			maxTries = 5,
			attemptNumber = 0,
			retryExponentInSeconds = 5,
			retryConstantInSeconds = 2,
			randomStream = baseRandomStream,
			onRetry = function()
			end,
			onDone = function()
			end,
			onFail = function()
			end,
			shouldRetry = function()
				return true
			end
		},
		backoffOptions
	)
	assert(backoffOptions.maxTries > 0, "You must try a function at least once")

	local function shouldRetry(response)
		return backoffOptions.maxTries > 1 and backoffOptions.shouldRetry(response)
	end

	local function retryIfShouldElseCallOnFailAndReturn(response, failHandler)
		if shouldRetry(response) then
			return backoffThenRetry(response)
		else
			backoffOptions.onFail(response)
			return failHandler(response)
		end
	end

	local function callOnDoneAndReturnPromise(response)
		backoffOptions.onDone(response, getDurationMs())
		return Promise.is(response) and response or Promise.resolve(response)
	end

	local ok, response =
		pcall(
		function()
			return getPromise()
		end
	)

	if ok then
		if Promise.is(response) then
			return response:catch(
				function(response)
					return retryIfShouldElseCallOnFailAndReturn(response, error)
				end
			):andThen(callOnDoneAndReturnPromise)
		else
			return callOnDoneAndReturnPromise(response)
		end
	else
		return retryIfShouldElseCallOnFailAndReturn(response, Promise.reject)
	end
end

return AsyncUtils
