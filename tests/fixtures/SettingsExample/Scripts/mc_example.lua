-- Settings reference fixture: a variation, a branch group, field conditions and a loose field.
local template={
    id='ExampleCue',
    label='Example Cue',
    description='Exercise every row the settings reference describes.',
    category='npc.attacks',
    objects={hud={}},
    variations={
        style={description='Choose the arrangement.', values={[0]='Swap', [1]='Stack'}, default=0},
    },
    menu={
        {id='Bars', label='Bars', fields={
            {id='.A', label='Orientation', values={[7]='Horizontal', [5]='Vertical'}, default=7},
            {id='.KH', label='Key Indicators', values={[0]='Above', [1]='Below'}, default=0,
                conditions={visible={field='.A', values={7}}}},
            {id='.KV', label='Key Indicators', values={[0]='Left', [1]='Right'}, default=0,
                conditions={visible={field='.A', values={5}},
                    label={field='.A', values={[5]='Side Key Indicators'}}}},
        }},
        {id='Stack', label='Stacking', variation={style=1}, fields={
            {id='.Gap', label='Gap', values={min=0,max=40,step=4,suffix='px'}, default=8},
        }},
        {id='Opacity', label='Opacity', values='percent', default=100},
    },
}
function template.attach(objects, params, original) return original end
return template
