# 2020-05-20 Read Battle Reports in Tribal Wars 2

## Motivation

From the conversation at https://forum.botengine.org/t/farm-manager-tribal-wars-2-farmbot/3038/87?u=viir

> I was wondering if there is a way to make sure the bot doesn’t send a farm to a specific village? Some barbarian villages of players who stopped playing still have walls, so everytime a farm is sent there some troops die.

> [...]
> At the moment, there is no quick way to avoid a specific village.
> I could expand the bot to support these scenarios: It could read the battle reports and avoid villages where troops died in the last 24 hours.
> [...]

## Exploring Implementation

Found this way to read a list of battle reports:

```javacript
reportService = angular.element(document.body).injector().get('reportService');

reportService.requestReportList('battle', 0, 100, null, { "BATTLE_RESULTS": { "1": false, "2": false, "3": false }, "BATTLE_TYPES": { "attack": true, "defense": true, "support": true, "scouting": true }, "OTHERS_TYPES": { "trade": true, "system": true, "misc": true }, "MISC": { "favourite": false, "full_haul": false, "forwarded": false, "character": false } }, function (data) {
    console.log(JSON.stringify(data));
});
```

What values does `requestReportList` support for the `filters` parameter? I used `JSON.stringify` on a value for `filters` coming from the `ReportListController` (`$scope.activeFilters` in the calling site) and got this:

```
"{"BATTLE_RESULTS":{"1":false,"2":false,"3":false},"BATTLE_TYPES":{"attack":true,"defense":true,"support":true,"scouting":true},"OTHERS_TYPES":{"trade":true,"system":true,"misc":true},"MISC":{"favourite":false,"full_haul":false,"forwarded":false,"character":false}}"
```

The above `filters` variant was with all visible; at least that was the intention. Let's see what `filters` we find when using the filters in the UI:

Victory with casualties:

```
"{"BATTLE_RESULTS":{"1":false,"2":true,"3":false},"BATTLE_TYPES":{"attack":true,"defense":true,"support":true,"scouting":true},"OTHERS_TYPES":{"trade":true,"system":true,"misc":true},"MISC":{"favourite":false,"full_haul":false,"forwarded":false,"character":false}}"
```

Defeat:

```
"{"BATTLE_RESULTS":{"1":false,"2":false,"3":true},"BATTLE_TYPES":{"attack":true,"defense":true,"support":true,"scouting":true},"OTHERS_TYPES":{"trade":true,"system":true,"misc":true},"MISC":{"favourite":false,"full_haul":false,"forwarded":false,"character":false}}"
```

Here is a result returned 2020-05-20:

```json
{
    "offset": 0,
    "total": 2,
    "reports": [
        {
            "id": 1137257,
            "time_created": 1589744135,
            "type": "attack",
            "title": "Segundo pueblo de John ataca  (ESTRELLA DEL NORTE )",
            "favourite": 0,
            "haul": "partial",
            "result": 2,
            "token": "1137257.123456.714e8dfb9617327f1",
            "read": 0
        },
        {
            "id": 1093285,
            "time_created": 1589698147,
            "type": "attack",
            "title": "Segundo pueblo de John ataca  (ESTRELLA DEL NORTE )",
            "favourite": 0,
            "haul": "full",
            "result": 2,
            "token": "1093285.123456.8468d4f2a7ca81afa",
            "read": 0
        }
    ]
}
```

Now lets get details for a report:

```javascript
reportService.getReport(1137257, function (data) {
    console.log(JSON.stringify(data));
});
```

This gets us:

```json
{
    "id": 1137257,
    "time_created": 1589744135,
    "title": "Segundo pueblo de John ataca  (ESTRELLA DEL NORTE )",
    "favourite": 0,
    "haul": "partial",
    "result": 2,
    "token": "1137257.229172.714e8dfb9617327f1",
    "type": "ReportAttack",
    "ReportAttack": {
        "outcome": 17,
        "attUnits": {
            "spear": 12,
            "sword": 0,
            "axe": 0,
            "archer": 0,
            "light_cavalry": 0,
            "heavy_cavalry": 0,
            "mounted_archer": 0,
            "ram": 0,
            "catapult": 0,
            "knight": 0,
            "snob": 0,
            "trebuchet": 0,
            "doppelsoldner": 0
        },
        "attLosses": {
            "spear": 4,
            "sword": 0,
            "axe": 0,
            "archer": 0,
            "light_cavalry": 0,
            "heavy_cavalry": 0,
            "mounted_archer": 0,
            "ram": 0,
            "catapult": 0,
            "knight": 0,
            "snob": 0,
            "trebuchet": 0,
            "doppelsoldner": 0
        },
        "attRevived": [],
        "attFaith": 0.5,
        "attModifier": 0.5650000000000001,
        "attEffects": [],
        "attWon": true,
        "defUnits": {
            "spear": 0,
            "sword": 0,
            "axe": 0,
            "archer": 0,
            "light_cavalry": 0,
            "heavy_cavalry": 0,
            "mounted_archer": 0,
            "ram": 0,
            "catapult": 0,
            "knight": 0,
            "snob": 0,
            "trebuchet": 0,
            "doppelsoldner": 0
        },
        "defLosses": {
            "spear": 0,
            "sword": 0,
            "axe": 0,
            "archer": 0,
            "light_cavalry": 0,
            "heavy_cavalry": 0,
            "mounted_archer": 0,
            "ram": 0,
            "catapult": 0,
            "knight": 0,
            "snob": 0,
            "trebuchet": 0,
            "doppelsoldner": 0
        },
        "defRevived": null,
        "defFaith": 0.5,
        "defModifier": 0.5,
        "defEffects": [],
        "officers": {
            "leader": false,
            "loot_master": false,
            "medic": false,
            "scout": false,
            "supporter": false,
            "bastard": false
        },
        "loyaltyBefore": null,
        "loyaltyAfter": null,
        "luck": 1.1300000000000001,
        "morale": 1,
        "leader": 1,
        "wallBonus": 0.1499999999999999,
        "night": false,
        "farmRule": 1,
        "wallBefore": null,
        "wallAfter": null,
        "building": null,
        "buildingBefore": null,
        "buildingAfter": null,
        "haul": {
            "wood": 25,
            "clay": 28,
            "iron": 28,
            "food": 0
        },
        "capacity": 200,
        "storage": null,
        "buildings": {
            "timber_camp": 9,
            "clay_pit": 10,
            "iron_mine": 10
        },
        "attCharacterIcon": 0,
        "defCharacterIcon": null,
        "attVillageId": 1617,
        "attVillageName": "Segundo pueblo de John",
        "attVillageX": 511,
        "attVillageY": 488,
        "attCharacterId": 123456,
        "attCharacterName": "John",
        "defVillageId": 2170,
        "defVillageName": "ESTRELLA DEL NORTE",
        "defVillageX": 499,
        "defVillageY": 459,
        "defCharacterId": 0,
        "defCharacterName": null
    }
}
```



tags:tribal-wars-2,explore,botengine