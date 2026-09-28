local M = {}

local function markLinks(manifest, choices)
    local links, section = {}, nil
    for line in (manifest .. '\n'):gmatch('([^\n]*)\n') do
        local heading = line:match('^%[([^%]]+)%]$')
        if heading then
            section = heading:match('^Setting%.(.+)$')
        elseif section then
            local target = line:match('^mcLinkProvider=(.+)$')
            if target then links[section] = target end
        end
    end
    for _, choice in ipairs(choices) do
        if links[choice.id] then choice.mcLinkProvider = links[choice.id] end
    end
    return choices
end

local function installLinks(page, providers, hostApi)
    if type(page) ~= 'table' or type(page.controls) ~= 'table' then return page end
    local controls, pending = page.controls, nil
    local show, tick = controls.show, controls.tick
    if type(show) ~= 'function' or type(tick) ~= 'function' then return page end
    function controls:show(index)
        local result = show(self, index)
        local model = self.model
        if model and not model._mctProviderLinks then
            local set = model.set
            function model:set(settingIndex, value)
                local choice = providers[index].choices[settingIndex]
                if choice and choice.mcLinkProvider then
                    pending = choice.mcLinkProvider
                    return
                end
                return set(self, settingIndex, value)
            end
            model._mctProviderLinks = true
        end
        return result
    end
    local function status(message)
        if hostApi.setText and page.controlStatus then
            hostApi.setText(page.controlStatus, message)
        end
    end
    function controls:tick(...)
        local result = tick(self, ...)
        local target = pending
        pending = nil
        if not target then return result end
        if self.model:dirty() then
            status('Apply or discard changes before opening ModCore Controls.')
            return true
        end
        for index, provider in ipairs(providers) do
            if provider.id == target and not provider.noSettings then
                for rowIndex, row in ipairs(page.rows) do
                    if row.providerIndex == index then
                        page:showDetail(rowIndex)
                        return true
                    end
                end
            end
        end
        status('ModCore Controls page is unavailable.')
        return true
    end
    return page
end

function M.new(root, menu)
local getMenu = type(menu) == 'function' and menu or function() return menu end

return {
    id = 'ModCoreTemplates.CategoryPages',
    apiVersion = 1,
    install = function(api)
        assert(type(api) == 'table' and type(api.pages) == 'table'
            and type(api.pages.build) == 'function', 'DMM pages API unavailable')
        assert(type(api.choices) == 'table' and type(api.choices.parse) == 'function',
            'DMM choices API unavailable')
        if api.pages._mctCategoryPagesInstalled then return false end
        api.pages._mctCategoryPagesInstalled = true
        local build = api.pages.build
        api.pages.build = function(tree, providers, status, hostApi)
            local current = getMenu()
            local definitions = {pages=current and current.pages or {}}
            assert(type(definitions.pages) == 'table', 'invalid MCT menu page definitions')
            local previousPositions = {}
            for index = #providers, 1, -1 do
                local id = tostring(providers[index].id or '')
                if id:sub(1, #'ModCoreTemplates.') == 'ModCoreTemplates.'
                    or (not current and id == 'ModCoreTemplates') then
                    previousPositions[providers[index].id] = index
                    table.remove(providers, index)
                end
            end
            if not current then return build(tree, providers, status, hostApi) end
            local aggregateChoices = current.aggregate and current.aggregate.manifest
                and api.choices.parse(current.aggregate.manifest) or {}
            local showAggregate = #aggregateChoices > 0
            for _, page in ipairs(definitions.pages) do
                if page.category then showAggregate = true end
            end
            local ids = {}
            for _, provider in ipairs(providers) do ids[provider.id] = true end
            local aggregate
            for index = #providers, 1, -1 do
                local provider = providers[index]
                if provider.id == 'ModCoreTemplates' then
                    local ownsPages = true
                    for _, page in ipairs(definitions.pages) do
                        ownsPages = ownsPages and type(page.id) == 'string'
                            and page.id:sub(1, #provider.id + 1) == provider.id .. '.'
                            and ((type(page.category) == 'string') ~= (type(page.module) == 'string'))
                    end
                    if ownsPages then
                        assert(aggregate == nil, 'duplicate MCT aggregate provider')
                        if showAggregate then aggregate = provider
                        else table.remove(providers, index); ids[provider.id] = nil end
                    end
                end
            end
            if showAggregate and current.aggregate and current.aggregate.manifest then
                local choices = aggregateChoices
                if not aggregate then
                    aggregate = {id='ModCoreTemplates', name='ModCore Templates',
                        author='ModCoreTemplates', version='0.0.20', testOnly=false,
                        path=root .. '/mod_settings.ini', logoFile='', logoAsset=''}
                    providers[#providers + 1] = aggregate
                end
                aggregate.choices, aggregate.settingsCount, aggregate.noSettings = choices, #choices, nil
                ids[aggregate.id] = true
            end
            assert(not showAggregate or aggregate ~= nil, 'MCT aggregate provider unavailable')
            local categoryProviders, moduleProviders = {}, {}
            for _, page in ipairs(definitions.pages) do
                assert(type(page.id) == 'string' and not ids[page.id], 'duplicate MCT category provider')
                local choices = markLinks(page.manifest, api.choices.parse(page.manifest))
                local generated = {
                    id = page.id,
                    name = page.name,
                    author = page.author or 'ModCoreTemplates',
                    version = page.version or '0.0.20',
                    description = page.description or ('Templates and settings for ' .. page.name .. '.'),
                    choices = choices,
                    settingsCount = #choices,
                    path = root .. '/mod_settings.ini',
                    testOnly = false,
                    logoFile = '',
                    logoAsset = '',
                }
                if page.category then
                    generated.mcBrowserLevel, generated.mcBrowserIndent = 4, 20
                    categoryProviders[#categoryProviders + 1] = generated
                else
                    generated._mctModule = assert(page.module, 'generated page needs category or module')
                    moduleProviders[#moduleProviders + 1] = generated
                end
                ids[page.id] = true
            end
            table.sort(providers, function(a, b)
                if a.testOnly ~= b.testOnly then return not a.testOnly end
                local an, bn = a.name:lower(), b.name:lower()
                if an ~= bn then return an < bn end
                return a.id < b.id
            end)
            local aggregateIndex
            for index, provider in ipairs(providers) do
                if provider == aggregate then aggregateIndex = index; break end
            end
            assert(not showAggregate or aggregateIndex ~= nil, 'MCT aggregate provider lost during ordering')
            for index, provider in ipairs(categoryProviders) do
                table.insert(providers, aggregateIndex + index, provider)
            end
            for _, generated in ipairs(moduleProviders) do
                local wanted, match = generated._mctModule:lower(), nil
                generated._mctModule = nil
                for index, provider in ipairs(providers) do
                    local id, name = tostring(provider.id or ''):lower(), tostring(provider.name or ''):lower()
                    if name == wanted or id == wanted or id == 'detected:ue4ss:' .. wanted then
                        assert(match == nil, 'duplicate module provider: ' .. generated.name)
                        match = index
                    end
                end
                if match and providers[match].noSettings then
                    table.remove(providers, match)
                    table.insert(providers, match, generated)
                elseif match then
                    generated.mcBrowserLevel, generated.mcBrowserIndent = 4, 20
                    table.insert(providers, match + 1, generated)
                elseif previousPositions[generated.id] then
                    table.insert(providers, math.min(previousPositions[generated.id], #providers + 1), generated)
                else
                    providers[#providers + 1] = generated
                end
            end
            return installLinks(build(tree, providers, status, hostApi), providers, hostApi)
        end
    end,
}

end

return M
