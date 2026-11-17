# WoW Forever market data

Auction-house prices and market research for the RP-PvP realm (Horde), taken from Auctionator's saved scans.

## Files

| File | What it is |
|---|---|
| `Market Research.md` | The written research: what to gather, craft and sell, supply gaps, and craft margins per character |
| `The Plan.html` | The plan and research as one page (open it in a browser) |
| `plan/PlanData.lua` | The plan itself, as loaded by the WFC_Plan addon: goals, character roles and per-item rules |
| `plan/characters.csv` | One row per character: level, gold, zone, professions, and how many items are in bags, bank and mail |
| `plan/inventory.csv` | Every item each character holds, by location (bags, bank, mail) |
| `plan/characters.json` | The full snapshots: the above plus equipped gear, active quests, known-recipe counts, ticked plan goals, and when each was taken |

Bank and mail are only as fresh as each character's last visit to a bank or mailbox (`bank_seen`, `mail_seen`).
| `data/prices.csv` | One row per item: latest scan, deepest scan and last-seen price |
| `data/price-history.json` | Every item's price and listing count for each scan date |
| `data/scans.json` | Which scan dates are in the data and how many items each saw |

## Reading the prices

- Prices are **minimum buyouts in copper** (1g = 10,000c). The CSV also has them formatted, like `12s 0c`.
- **Latest** is the newest scan date. **Deep scan** is the date with the most listings for that item, usually the most trustworthy price.
- **Listed** is how many were up. Under 20 listed, a single seller can set the price.

## Scans in this upload

| Date | Items with listings |
|---|---|
| 2026-11-13 | 1 |
| 2026-11-14 | 4,025 |
| 2026-11-15 | 4,565 |
| 2026-11-16 | 4,895 |

`Market Research.md`, `The Plan.html` and the files in `plan/` were refreshed from the 2026-11-16 17:54 scan.

To refresh: run a full Auctionator scan in game, `/reload`, and regenerate the files.
