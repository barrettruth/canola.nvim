local M = {}

---Store entries as a list-like table for maximum space efficiency and retrieval speed.
---We use the constants below to index into the table.
---@alias canola.InternalEntry {[1]: integer, [2]: string, [3]: canola.EntryType, [4]: nil|table}

-- Indexes into canola.InternalEntry
M.FIELD_ID = 1
M.FIELD_NAME = 2
M.FIELD_TYPE = 3
M.FIELD_META = 4

return M
