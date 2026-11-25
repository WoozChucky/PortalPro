# PortalPro

A WoW Forever addon for mages who sell portals. It automates as much of the job as the game's API allows.

## What it does

- **Finds buyers** in Trade, General, LFG, say, yell and whispers ("WTB port to UC", "inv org").
- **Invites** buyers and replies to them.
- **Opens trade** when a buyer in your group is in range.
- **Trade dock:** a panel beside the trade window shows the city, the payment against the price, and a Cast button that glows once they've paid.
- **Cast button** that always holds the portal the group needs.
- **Kicks** buyers once they went through the portal.
- **Ledger:** today, 7 days and all time at a glance, a 7-day chart of income and tips, your best cities, who still owes you, and the full history.
- **Party thank-you** after each trade, so everyone can see what was paid.
- **Templates:** the ad and the thank-you are editable on the Messages tab.
- **One window** with Buyers / Messages / Ledger tabs, resizable with the bottom-right grip. Buyers show in their class colour with the portal's icon.

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

- `/pp` shows or hides the window; `/pp help` lists all commands.
- The **minimap button** shows how many buyers are waiting. Click it for the window, right-click to post the ad, drag it to move it. `/pp minimap` hides or shows it.
- `/pp compact` folds the window to one line (buyers waiting, in group, Post ad); again, or `+`, brings it back.
- A short **pop-up** with a sound tells you when a new buyer shows up.
- Key bindings are in Game Menu > Key Bindings > PortalPro.

The window and the dock hold the Cast button, which the game locks in combat: showing, hiding or folding them waits until combat ends.

## Tests

The tests run offline against a fake WoW API, using Lua 5.1 through [lupa](https://pypi.org/project/lupa/):

```
pip install lupa
python tests/run_tests.py
```
