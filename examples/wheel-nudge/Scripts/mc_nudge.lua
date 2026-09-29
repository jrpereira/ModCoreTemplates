local MC=require('mc')
local Widget=MC('widget')

-- Declare only the wheel this template changes. The category resolves its
-- switcher dependency and already knows how to save the wheel's position.
local template={
    name='Wheel Nudge',
    category='player.quickslots',
    objects={abilities={}},
    settings={HorizontalPercent=0,VerticalPercent=0},
    menu={{id='Position',label='Position',fields={
        {id='HorizontalPercent',label='Horizontal offset',
            values={min=-25,max=25,step=1,suffix='%'},default=0},
        {id='VerticalPercent',label='Vertical offset',
            values={min=-25,max=25,step=1,suffix='%'},default=0},
    }}},
}

function template.attach(objects,params,original)
    local x=params.screen.width*params.settings.HorizontalPercent/100
    local y=params.screen.height*params.settings.VerticalPercent/100
    local position=original.abilities.position
    Widget.setTranslation(objects.abilities,position.X+x,position.Y+y)
    return original
end

return template
