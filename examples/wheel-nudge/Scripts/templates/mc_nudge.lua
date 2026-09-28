-- Declare only the wheel this template changes. The category resolves its
-- switcher dependency and already knows how to save the wheel's position.
return {
    name='Wheel Nudge',
    category='player.quickslots',
    objects={abilities={}},
    settings={HorizontalPercent=0,VerticalPercent=0},
    menu={
        enabled=true,
        groups={{id='Position',label='Position'}},
        fields={
            {id='HorizontalPercent',group='Position',label='Horizontal offset',
                type='integer',min=-25,max=25,step=1,default=0,suffix='%'},
            {id='VerticalPercent',group='Position',label='Vertical offset',
                type='integer',min=-25,max=25,step=1,default=0,suffix='%'},
        },
    },
}
