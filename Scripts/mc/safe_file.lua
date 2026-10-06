-- Crash-safe file replacement. The content is written to <path>.new, the current
-- file is moved to <path>.old, which is kept as a backup, and <path>.new then
-- becomes <path>. A crash leaves either the old or the new file in place.
local M = {}

local function exists(path)
    local file = io.open(path, 'rb')
    if not file then return false end
    file:close()
    return true
end

-- Finish a replacement interrupted after the current file was moved out, and
-- discard a replacement that was never published. A missing file with only a
-- backup is left alone: that file was removed on purpose.
function M.recover(path)
    local new, old = path .. '.new', path .. '.old'
    if not exists(new) then return end
    if not exists(path) and exists(old) then
        -- The current file is moved out only after the replacement is complete.
        assert(os.rename(new, path), 'could not publish interrupted replacement: ' .. new)
        return
    end
    assert(os.remove(new), 'could not clear unpublished replacement: ' .. new)
end

function M.read(path)
    M.recover(path)
    local file = io.open(path, 'rb')
    if not file then return nil end
    local content = file:read('a')
    file:close()
    return content
end

function M.write(path, content)
    M.recover(path)
    local new, old = path .. '.new', path .. '.old'
    local file = assert(io.open(new, 'wb'))
    local written, why = file:write(content)
    local closed, closeWhy = file:close()
    if not written or not closed then
        os.remove(new)
        error(tostring(why or closeWhy), 0)
    end
    local moved = false
    if exists(path) then
        if exists(old) then
            local removed, removeWhy = os.remove(old)
            if not removed then os.remove(new); error(tostring(removeWhy), 0) end
        end
        local renamed, renameWhy = os.rename(path, old)
        if not renamed then os.remove(new); error(tostring(renameWhy), 0) end
        moved = true
    end
    local published, publishWhy = os.rename(new, path)
    if not published then
        if moved then os.rename(old, path) end
        os.remove(new)
        error(tostring(publishWhy), 0)
    end
    return true
end

return M
