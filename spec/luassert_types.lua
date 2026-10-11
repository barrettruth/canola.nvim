---@meta

---@class luassert.internal
---@field equals fun(expected: any, ...: any)
---@field not_equals fun(expected: any, ...: any)
---@field not_nil fun(value: any)

---@class luassert.spy.assert
---@field was_called fun(times?: integer)
---@field was_not_called fun()
---@field was_called_with fun(...: any)

---@param name string
---@param block? fun()
function pending(name, block) end
