function onEventPushed(name, value1, value2, strumTime)
{
    if (name == 'Change Character' || name == 'ChangeCharacter')
    {
        var charName = (value2 != null && value2 != '') ? value2 : value1;
        if (charName == null || charName == '') return;

        funkin.gameplay.objects.character.Character.precacheCharacter(charName);

        Paths.image('icons/icon-' + charName);
    }
}

function onTrigger(v1, v2, time)
{
    if (game == null || v1 == null || v1 == '' || v2 == null || v2 == '')
        return false;

    var slotLow = v1.toLowerCase();
    var target  = null;

    if (slotLow == 'bf' || slotLow == 'boyfriend' || slotLow == 'player')
        target = game.boyfriend;
    else if (slotLow == 'dad' || slotLow == 'opponent')
        target = game.dad;
    else if (slotLow == 'gf' || slotLow == 'girlfriend')
        target = game.gf;

    if (target == null)
    {
        trace('ChangeCharacter: slot "' + v1 + '" no reconocido.');
        return false;
    }

    if (target.curCharacter == v2)
    {
        trace('ChangeCharacter: ' + v1 + ' ya es "' + v2 + '", skip.');
        return false;
    }

    funkin.gameplay.objects.character.Character.precacheCharacter(v2);

    target.reloadCharacter(v2);

    if (game.uiManager != null && game.boyfriend != null && game.dad != null)
        game.uiManager.setIcons(game.boyfriend.healthIcon, game.dad.healthIcon);

    trace('ChangeCharacter: ' + v1 + ' → ' + v2);
    return false;
}