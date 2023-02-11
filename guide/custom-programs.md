# Custom Programs

This file lists some of the customizations of bot programs found on the internet. Often these emerged from answering developers' questions.
The list serves as an additional way to find customizations again, besides the general [catalog](https://catalog.botlab.org).
If you think a change should be merged into the main branch, you can post on the [forum](https://forum.botlab.org) or create an issue on the [bots GitHub page](https://github.com/Viir/bots/issues).
The main branch of the example programs develops by evolution: The more popular a change with users, the more likely it will be merged into the main branch. You can see the popularity displayed at `Total running time in hours` on the program's catalog entry.
To find a program on the catalog, you can also enter the commit as a search term, or use the `botlab  describe` command.

## 2020-03-19 - goondola - EVE Online - print the list of pilots in local

+ Original discussion: https://forum.botlab.org/t/learning-be-and-elm/3160
+ Program code: https://github.com/Viir/bots/commit/0dcadd5b6d1de84d12be96af32148d618e4fee78 and parent commits.

## 2020-04-21 - Caleb Tribal Wars 2 - Support Multiple Instances

https://github.com/Viir/bots/tree/9b623a9cc678de660e3aa57b3e1b131da3ad54f9/implement/applications/tribal-wars-2/tribal-wars-2-farmbot

> Support scenario shared by Caleb at https://forum.botlab.org/t/farm-manager-tribal-wars-2-farmbot/3038/62?u=viir

2020-07-06 From the catalog entry at https://catalog.botlab.org/fd575d579bc77305a45495b862f060206e93bc26f3ed39cec87c5f05c74e4928

> Total running time in hours: 162

## 2020-06-30 - Cam lastelement - EVE Online - local watch

Origin and discussion: https://forum.botlab.org/t/local-intel-bot/3413/6?u=viir

https://github.com/Viir/bots/commit/d01478b69a9e71ac7bffc34c25585723d3abf28e

## 2020-07-01 - Cameron Urnes - EVE Online - local watch

Origin and discussion: https://github.com/Viir/bots/pull/15

> Uses whitelist instead of blacklist for determining the trigger list. Allows selection of character during launch, still supports auto-picking top window. Beep a bit more.

https://github.com/Viir/bots/commit/acf8c8c34dfe910f19bd838236e845d51bafb7e2

## 2020-07-30 - TheRealManiac - EVE Online - hiding when neutral or hostile appears in local chat

On 2020-07-30, the catalog entry at https://catalog.botlab.org/782844bb5667da19d2dec276b3afd9d0a2e381c7e5011f837752c4a0d523e110 shows:

> Total running time in hours: 4

Program code change at https://github.com/Viir/bots/commit/42819720f12f34658d88e29ff0e55d158869568d

> Support hiding when neutral or hostile appears in local chat
> 
> Add a setting to enable this behavior.
> If conditions are met for hiding, do not undock anymore. If conditions are met for hiding, return drones to bay and dock to station or structure.
> 
> Original discussion at https://forum.botlab.org/t/mining-bot-master-branch/3463?u=viir

On 2020-08-07, the catalog entry at https://catalog.botlab.org/782844bb5667da19d2dec276b3afd9d0a2e381c7e5011f837752c4a0d523e110 shows:

> Total running time in hours: 119

Therefore integrate these into the recommendation on the main branch.

## 2020-08-20 - Dante - EVE Online - priority-rat

https://github.com/Viir/bots/tree/95178b9233710d335eedcaf7bd2ac31fffce280f/implement/applications/eve-online/eve-online-combat-anomaly-bot

Original discussion: https://forum.botlab.org/t/let-me-know-how-to-make-my-app/3514

2020-08-20 the catalog entry for [App 8e7e916263...](https://catalog.botlab.org/8e7e916263f4cf75eb2fa7e68fc995fe9932324c2c90c37dcaf2206202117351) shows:

> Total running time in hours: 76

## 2020-10-12 - Mactastic08 & annar_731 - EVE Online - Orca Mining

https://github.com/Viir/bots/tree/02027201fd8c506c6d88d160b1a80763f8bdabbd/implement/applications/eve-online/eve-online-mactastic08-orca-mining

Original discussion: https://forum.botlab.org/t/orca-targeting-mining/3591

2020-10-12 the catalog entry for [App 81395744f5...](https://catalog.botlab.org/81395744f5857f15f5cf22cf091a71b440b42a81dddd0e992a0d9db1fce92da2) shows:

> Total running time in hours: 33

2022-04-15 the catalog entry for [Bot 81395744f5...](https://catalog.botlab.org/81395744f5857f15f5cf22cf091a71b440b42a81dddd0e992a0d9db1fce92da2) shows:

> Total running time in hours: 175

## 2020-10-31 - Stephan Fuchs - EVE Online - Merged Mining Scripts

https://github.com/Viir/bots/commit/f6246764ac106894e74669815c0e675c48ab9262

Original discussion: https://forum.botlab.org/t/eve-online-request-suggestion/3663

```
Would it be possible to merge both mining scripts?
So that the normal mining script would use mining drones as well?
Currently the drones willl be activated, but they don’t mine (I guess because most people are using them as fighting drones)
Thanks for your help and your great tools
```

2020-11-06 the catalog entry for [App dbbec0a31d...](https://catalog.botlab.org/dbbec0a31dfe05b39cf37bb4f329c1fe5e4eb5ed85ceadac37f04ccff4a14c0b) shows:

> Total running time in hours: 116

2022-04-15 the catalog entry for [Bot dbbec0a31d...](https://catalog.botlab.org/dbbec0a31dfe05b39cf37bb4f329c1fe5e4eb5ed85ceadac37f04ccff4a14c0b) shows:

> Total running time in hours: 292

## 2021-09-22 - Drklord and opticcanadian - Tribal Wars 2 - avoid targets based on outgoing commands

https://github.com/Viir/bots/commit/828e5b23a892b050f34680e006543af4df823221

Original discussion:

+ <https://forum.botlab.org/t/farm-manager-tribal-wars-2-farmbot/3038/222>
+ <https://forum.botlab.org/t/farm-manager-tribal-wars-2-farmbot/3038/314>

2021-09-22 the catalog entry for [d5a06db64f](https://botcatalog.org/d5a06db64fd579fbcf695ef99162cd1cd069b7c9eddc19e6e5abee5d7be21c43) shows:

> Total running time in hours: 71

2022-04-15 the catalog entry for [d5a06db64fd579fb](https://botcatalog.org/d5a06db64fd579fbcf695ef99162cd1cd069b7c9eddc19e6e5abee5d7be21c43) shows:

> Total running time in hours: 1343

## 2021-10-05 - qmail - EVE Online Intel Bot - Local Watch Script

Original discussion:

+ <https://forum.botlab.org/t/bot-not-working-with-new-engine/4142>

> EVE Online Intel Bot - Local Watch Script - 2021-09-21
> This bot watches local and plays an alarm sound when a pilot with bad standing appears.

+ <https://github.com/Viir/bots/tree/0bce0d7f3cd6e560d5a625e9f8a8068610950901/implement/applications/eve-online/eve-online-local-watch>
+ <https://reactor.botlab.org/catalog/b590279a1fbac9b39a76512df2d5dae3ef92ece4863f307ad4faea03a193ce4d>

2021-10-05 the catalog entry shows:

> Total running time in hours: 91

2022-04-15 the catalog entry shows:

> Total running time in hours: 1442


## 2022-09-01 - Maunzinator - EVE Online Intel Bot - Local Watch Bot

Discussion:

+ <https://forum.botlab.org/t/local-watch-bot/4112/3>

+ <https://catalog.botlab.org/413d1319fc4d45a8>
+ <https://github.com/Viir/bots/tree/1067c27ab4e56a91f6d7b00c2f45926dd76b8a3a/implement/applications/eve-online/eve-online-local-watch>


## 2022-09-19 - opticcanadian and Drklord - Tribal Wars 2 - avoid targets based on outgoing commands

+ <https://github.com/Viir/bots/commit/96b22107183d708ec1c44f6e0d2bd6d322d33ba4>
+ <https://catalog.botlab.org/ab0771677670681c>

Original discussion:

+ <https://forum.botlab.org/t/update-upgrade-to-recent-tribal-wars-2-bot/4443>

2022-10-17 the catalog entry <https://catalog.botlab.org/ab0771677670681c> shows:

> Total running time in hours: 1293

