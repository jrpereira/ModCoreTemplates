local M = {}

function M.text(value, where)
    assert(type(value) == 'string' and value:find('%S'), where .. ': expected nonempty string')
    return value
end

function M.array(value, where)
    assert(type(value) == 'table', where .. ': expected array')
    local count = 0
    for key in pairs(value) do
        assert(type(key) == 'number' and key >= 1 and key % 1 == 0,
            where .. ': expected dense array without named keys')
        count = count + 1
    end
    for i = 1, count do
        assert(rawget(value, i) ~= nil, where .. ': sparse array at [' .. i .. ']')
    end
    return count
end

function M.copy(value, seen)
    if type(value) ~= 'table' then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}; seen[value] = result
    for k, v in pairs(value) do result[M.copy(k, seen)] = M.copy(v, seen) end
    return result
end

return M
