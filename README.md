# PortalPro

A WoW Forever addon for mages who sell portals. It automates as much of the job as the game's API allows.

## What it does

- **Finds buyers** in Trade, General, LFG, say, yell and whispers ("WTB port to UC", "inv org").
- **Invites** buyers and replies to them.
- **Opens trade** when a buyer in your group is in range.
- **Checks payment** in the trade window and shows PAID or how much is missing.
- **Cast button** that always holds the portal the group needs.
- **Kicks** buyers once they went through the portal.
- **Ledger:** income, tips, short or unpaid buyers, and rune cost, with net profit for today, 7 days and all time.
- **Party thank-you** after each trade, so everyone can see what was paid.
- **Templates:** the ad and the thank-you are editable in the Messages window.
- **Windows:** all of them are resizable with the bottom-right grip.

The addon loads only on mages.

## What still needs your click or key

The game reserves these actions for the player:

- casting the portal
- accepting the trade
- posting in public chat

On live Forever realms, addons can't send chat lines at all. The ad and the thank-you go into your chat box, and you press Enter to send them.

## Install

```
cd "World of Warcraft/_forever_/Interface/AddOns"
git clone https://github.com/WoozChucky/PortalPro.git
```

To update, run `git pull` in that folder, then `/reload` in game.

## Use

Type `/pp` to show or hide the panel and `/pp help` for all commands. Key bindings are in Game Menu > Key Bindings > PortalPro.

## Tests

The tests run offline against a fake WoW API, using Lua 5.1 through [lupa](https://pypi.org/project/lupa/):

```
pip install lupa
python tests/run_tests.py
```
