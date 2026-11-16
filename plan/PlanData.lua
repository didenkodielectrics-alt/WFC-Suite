local _, ns = ...

-- PlanData: "the plan", written by Claude after talking it through with you.
-- Claude edits this file; you /reload to load a new plan. Everything here overrides Logic.lua.
--
--   main        = lead character (name or "Name-Realm"); /plan main <name> overrides it in-game
--   summary     = one paragraph: what the plan is right now
--   goals       = ordered list of { id, section, who, text, why } shown as a checklist in /plan
--                 section = groups goals into numbered stages; who = the character doing it;
--                 text = one short action; why = one short reason; steps = sub-steps;
--                 trainer = profession name: that trainer gets a map/nameplate marker
--                 (ticks are saved per account; "id" must stay stable when a goal is reworded)
--   characters  = per-character role notes, keyed by name: { role = "...", notes = "..." }
--   items       = per-item overrides, keyed by itemId:
--                 { action = "MAIL"|"AUCTION"|"VENDOR"|"BANK"|"KEEP"|"USE"|"DISENCHANT", to = "Name"|"main", note = "..." }
--   updated     = date this plan was written

ns.PlanData = {
    updated = "2026-11-15 (plan 6, L27 + 22:08 market rescan)",
    main = "Gnomestomper",
    summary = "Gnomestomper is level 27 in Stonetalon Mountains with 3g 0s 57c (account liquid: 3g 45s 25c), Fishing 198/225, Cooking 168/225, and Skinning 186/225. "
        .. "Cen reached Leatherworking 110/150 and Ophelia is Tailoring 93/150 (2 points from Red Woolen Boots). "
        .. "New Auctionator scan shows big gold waiting in mail/bags: 84 Firefin Snapper (1.45g), Plans: Iridescent Hammer (82s), Recipe: Lesser Mender's Potion (50s), "
        .. "72 Wool Cloth (1.15g), 23 Coarse Stone (66s), Meadow Ring (30s), 3 Mystic kits (26.7s), 2 Sharpening Wheels (20s), and vendor weapons (Outlaw Sabre 65.2s, Wingblade 28.8s). "
        .. "Priority now: Bitores clears mail and auctions Firefin/plans/recipes; Ophelia clears mail, hits Tailoring 95, and auctions BoEs/kits/surplus Wool; "
        .. "Gnomestomper hits Cooking 175 (3 recipes waiting) and First Aid 85, and Cen opens the bank once.",

    goals = {
        -- Stage 1: finish remaining snapshot & mail pickups
        { id = "cen-bank", section = "Get the data & clear mail", who = "Cen",
          text = "Open the bank once (and refresh Cen's bag scan)",
          why = "The plan still has never seen Cen's bank, and Cen's bag snapshot didn't load this session" },
        { id = "bitores-mail", section = "Get the data & clear mail", who = "Bitores",
          text = "Collect mail (84 Firefin Snapper ~1.45g, 12 Oily Blackmouth ~8.3s, 11 Coarse Stone ~31.8s, 5 Stranglekelp, 2 Pyrite)",
          why = "84 Firefin Snapper alone are worth 1g 45s 32c at 1s 73c each on the AH" },
        { id = "ophelia-mail", section = "Get the data & clear mail", who = "Ophelia",
          text = "Collect mail (78 Linen, 57 Wool, 8 Silk, 3 Mystic kits, Meadow Ring 30s, Pathfinder Bracers 14s, Hulking Leggings 19s, Spider's Silk)",
          why = "Over 1.5g in cloth, kits, and BoEs is sitting in Ophelia's mailbox" },

        -- Stage 2: bags & crafters feed the lead
        { id = "ophelia-bags", section = "Crafters", who = "Ophelia",
          text = "Make Linen Bags / Red Linen Bags for Cen and alts",
          why = "78 Linen Cloth is in Ophelia's mail plus 2 Bolts in bags; Red Linen Bag (Tailoring 75, she's 93) is 8 slots" },
        { id = "ophelia-boots", section = "Crafters", who = "Ophelia",
          text = "Reach Tailoring 95 (at 93), then learn Pattern: Red Woolen Boots",
          why = "The pattern is in her bank and she has 57 Wool Cloth in mail (sell the surplus Wool at 1s 60c ea)" },
        { id = "leather-to-cen", section = "Crafters", who = "Gnomestomper",
          text = "Mail all leather and hides to Cen after skinning",
          why = "Cen is Leatherworking 110/150 and turns them into skill-ups and armor" },
        { id = "cen-gear-gnome", section = "Crafters", who = "Cen",
          text = "Craft leather armor upgrades for Gnomestomper: Bind on Equip pieces only",
          why = "Hunters wear leather until 40. Check 'Binds when equipped' on the pattern first: the Pristine Leather sets (Trapper's, Brawler's...) are Bind on Pickup, so they can only be worn by the crafter" },
        { id = "cen-quiver", trainer = "Leatherworking", section = "Crafters", who = "Cen",
          text = "Learn Light Leather Quiver and make one for Gnomestomper",
          why = "A Hunter's quiver speeds up ranged attacks; Cen can learn it now (Leatherworking 110/150)",
          steps = {
              "Visit a Leatherworking trainer (Thunder Bluff is right there)",
              "Learn Light Leather Quiver (and Small Leather Ammo Pouch if offered)",
              "Craft it from Light Leather; it also gives skill-ups",
              "Mail it to Gnomestomper Greybeard",
          } },
        { id = "ench-mats", section = "Crafters", who = "Bitores",
          text = "Mail Greater Magic Essence (1 on Bitores) to Ophelia",
          why = "Ophelia is the enchanter (Enchanting 112) and already holds 15 Lesser Magic Essence" },
        { id = "gnome-cooking", section = "Crafters", who = "Gnomestomper",
          text = "Push Cooking 168 -> 175 (cook Raw Rockscale Cod x76 / Yellowtail x16) to learn 3 recipes",
          why = "Recipe: Sagefish Delight (69s), Rockscale Cod (53.5s), and Mithril Head Trout (44s) are waiting in bags" },

        -- Stage 3: gold for the mount (fresh 11/15 22:08 AH prices)
        { id = "sell-mender", section = "Gold for the mount (100g at 40)", who = "Bitores",
          text = "Auction Plans: Iridescent Hammer (82s) and Recipe: Lesser Mender's Potion (50s)",
          why = "Both spiked in value on the new scan (1.32g combined vs 4.5s vendor)" },
        { id = "ah-high-value", section = "Gold for the mount (100g at 40)", who = "All",
          text = "Auction 84 Firefin (1.45g), surplus Wool (~1g), 23 Coarse Stone (66s), Bronze/Tin/Silver bars (~73s), 3 Mystic kits (26.7s), 2 Murloc Eyes (19.5s), Copper Chain Boots (18s), 2 Moss Agate (16s), Minor Wizard Oil (11.9s), Tomahawk (8s)",
          why = "Fresh Auctionator scan puts these far above vendor even after 5% AH cut + 1s deposit" },
        { id = "vendor-traps", section = "Gold for the mount (100g at 40)", who = "All",
          text = "Vendor items where AH <= vendor or non-AH BoEs (Outlaw Sabre 65.2s, Wingblade 28.8s, 2 Lesser Moonstone 12s, 57 Blood Shards 14.3s, 10 Light Armor Kits 1.5s, Seaforium 2s)",
          why = "AH 5% cut + 1s deposit loses money compared to vendoring directly" },
        { id = "pristine-check", section = "Gold for the mount (100g at 40)", who = "Cen / Gnomestomper",
          text = "Keep the Pristine Leather for Cen's own Pristine pieces, or sell if the price jumps",
          why = "Dropped to ~8s 32c each on AH now; Pristine sets are Bind on Pickup, so they only help Cen unless prices spike over 1g" },
        { id = "gnome-gather", section = "Gold for the mount (100g at 40)", who = "Gnomestomper",
          text = "Skin, mine, and fish while questing; sell ore, bars, Firefin/Blackmouth, and extra hides",
          why = "Leather goes to Cen; everything else becomes mount money" },
        { id = "mount-fund", section = "Gold for the mount (100g at 40)", who = "Gnomestomper",
          text = "Save 100g by level 40 (90g if Honored with Orgrimmar)",
          why = "Account has 3g 45s 25c liquid right now; don't spend on AH upgrades, park spare gold on Ophelia" },

        -- Stage 3b: supply gaps (thin or empty on the AH; see "Supply gaps" in Market Research.md)
        { id = "gap-list-owned", section = "Supply gaps (thin or empty AH)", who = "Ophelia / Gnomestomper",
          text = "Auction Meadow Ring (~30s), Hulking Leggings (~19s) and Pathfinder Bracers (~14s); vendor Dervish Boots unless someone wears them",
          why = "22:02 rescan: each has under 10 listed and beats vendor after the 5% cut; Dervish Boots (15s on AH vs 14s 37c vendor) doesn't" },
        { id = "gap-murloc-scales", section = "Supply gaps (thin or empty AH)", who = "Cen",
          text = "Low priority: Murloc Scale Belt / Breastplate, only if you pass Andrew Hilbert (Silverpine) for the patterns",
          why = "Prices fell on 2026-11-15: Belt 48s -> 29s, Breastplate 65s -> 32s, so about +13s and +8s per craft before pattern cost" },
        { id = "gap-bitores-wheel", section = "Supply gaps (thin or empty AH)", who = "Bitores",
          text = "Auction the 2 Sharpening Wheels at ~9s",
          why = "None on the deep scan, one seller at 10s on the latest; mats are ~1s 54c and he knows the recipe" },
        { id = "gap-gnome-farm", section = "Supply gaps (thin or empty AH)", who = "Gnomestomper",
          text = "Skin Red Whelps if you pass them (Red Whelp Scale ~11s)",
          why = "22:02 rescan: Red Whelp Scale fell from 20s to 11s; Small Egg (~3s) and Slimy Murloc Scale (~2s) are no longer worth a detour" },
        { id = "gap-vendor-stock", section = "Supply gaps (thin or empty AH)", who = "Any",
          text = "At an engineering supplier, compare Heavy Stock (AH ~44s, 32 listed) and Wooden Stock (AH ~8s) with the vendor price",
          why = "Classic vendor prices were ~20s and ~2s; Forever's may differ, so read the price before buying" },
        { id = "gap-soon", section = "Supply gaps (thin or empty AH)", who = "Ophelia / Cen",
          text = "Ophelia: buy Pattern: Colorful Kilt (~15s on AH) and post Kilts one at a time; Cen: aim for Leatherworking ~125 for Green Leather Armor",
          why = "22:02 rescan: Colorful Kilt ~80s (14 listed, ~+45s). Green Leather Armor ~80s (7 listed, ~+40s); its pattern is sold by George Candarte, Hillsbrad" },

        -- Stage 4: the lead's kit (PvP ruleset)
        { id = "gnome-firstaid", trainer = "First Aid", section = "Gnomestomper's kit", who = "Gnomestomper",
          text = "Train Wool Bandage now, Lesser Healing Potion at First Aid 85 (using Wool Cloth in bags)",
          why = "First Aid is 80 and you have 13 Wool Cloth in bags; Forever moved healing potions into First Aid",
          steps = {
              "Visit a First Aid trainer and learn Wool Bandage (and Anti-Venom)",
              "Make Wool Bandages until First Aid 85 using Wool Cloth in bags",
              "Return to the trainer at 85 and learn Lesser Healing Potion",
          } },
        { id = "gnome-potions", section = "Gnomestomper's kit", who = "Gnomestomper",
          text = "Keep 8 or more healing potions (currently 2 Healing in bags; 1 Lesser + 6 Minor in bank)",
          why = "Grab the bank potions or craft Lesser Healing Potions once First Aid hits 85" },
    },

    characters = {
        Gnomestomper = { role = "Lead · gatherer",
            notes = "Level 27 in Stonetalon Mountains (3g 0s 57c). Skinning 186, Fishing 198, Cooking 168 (push to 175 for 3 recipes), Mining 124, First Aid 80. Vendor Outlaw Sabre (65s) + Wingblade (28.8s) if unused; auction bank ores/bars/Moss Agate/Murloc Eyes." },
        Cen = { role = "Leatherworker",
            notes = "Level 10 in Thunder Bluff, Leatherworking 110/150, Herbalism 27/75. Needs to open bank once and refresh bag scan; crafts Gnomestomper's quiver and armor upgrades." },
        Ophelia = { role = "Tailor · enchanter · bank alt",
            notes = "Tailoring 93/150, Enchanting 112/150 (in The Barrens). Collects 78 Linen + 57 Wool + 3 Mystic kits + Meadow Ring (30s) from mail, hits Tailoring 95, and auctions BoEs/kits/surplus Wool." },
        Bitores = { role = "Herb holder · alchemist · seller",
            notes = "Blacksmithing 48/75 + Alchemy 33/75 in Undercity (41s 1c). Collects mail (84 Firefin Snapper ~1.45g, 12 Blackmouth, 11 Coarse Stone), auctions Plans: Iridescent Hammer (82s) + Mender's recipe (50s), and vendors AH-loss items." },
    },

    items = {
        -- Linen & Wool: bags / First Aid / Tailoring 95 first, then AH surplus Wool (1s 60c ea)
        [2589]   = { action = "MAIL", to = "Ophelia", note = "the plan: bags first (78 in Ophelia's mail)" },
        [2592]   = { action = "AUCTION", note = "the plan: ~1s 60c ea after Gnomestomper hits FA 85 & Ophelia hits Tailoring 95" },
        -- Leather & hides -> Cen (leatherworker)
        [2318]   = { action = "MAIL", to = "Cen", note = "the plan: Cen's leatherworking" },
        [2319]   = { action = "MAIL", to = "Cen", note = "the plan: Cen's leatherworking" },
        [4234]   = { action = "MAIL", to = "Cen", note = "the plan: Heavy Leather for Cen (3 in Ophelia's mail)" },
        [783]    = { action = "MAIL", to = "Cen", note = "the plan: Cen cures hides" },
        [4231]   = { action = "MAIL", to = "Cen", note = "the plan: Cen's leatherworking" },
        [4232]   = { action = "MAIL", to = "Cen", note = "the plan: Cen cures hides" },
        [5082]   = { action = "MAIL", to = "Cen", note = "the plan: Cen's leatherworking" },
        [6470]   = { action = "MAIL", to = "Cen", note = "the plan: Cen's leatherworking" },
        [249427] = { action = "KEEP", note = "the plan: AH dropped to ~8s 32c; hold for LW 270 unless >1g" },
        -- Herbs -> Bitores (Alchemy 33)
        [765]    = { action = "MAIL", to = "Bitores", note = "the plan: Bitores' Alchemy" },
        [2447]   = { action = "MAIL", to = "Bitores", note = "the plan: Bitores' Alchemy" },
        [2449]   = { action = "MAIL", to = "Bitores", note = "the plan: Bitores' Alchemy" },
        [785]    = { action = "MAIL", to = "Bitores", note = "the plan: Bitores' Alchemy" },
        -- Enchanting materials -> Ophelia
        [10938]  = { action = "MAIL", to = "Ophelia", note = "the plan: Ophelia's enchanting (15 in bags)" },
        [10939]  = { action = "MAIL", to = "Ophelia", note = "the plan: 1 on Bitores -> Ophelia" },
        [10940]  = { action = "MAIL", to = "Ophelia", note = "the plan: Ophelia's enchanting" },
        -- High-value AH items (verified by 11/15 22:08 Auctionator scan)
        [6359]   = { action = "AUCTION", note = "the plan: Firefin Snapper 1s 73c ea (~1.45g for 84 in Bitores's mail)" },
        [6358]   = { action = "AUCTION", note = "the plan: Oily Blackmouth ~69c ea (stack of 12 in Bitores's mail)" },
        [5543]   = { action = "AUCTION", note = "the plan: Plans: Iridescent Hammer jumped to 82s on AH!" },
        [250989] = { action = "AUCTION", note = "the plan: Recipe: Lesser Mender's Potion ~50s on AH" },
        [252436] = { action = "AUCTION", note = "the plan: Mystic Medium Armor Kit ~8s 90c ea (~26.7s in Ophelia's mail)" },
        [3469]   = { action = "AUCTION", note = "the plan: Copper Chain Boots 18s on AH (vendor 49c)" },
        [730]    = { action = "AUCTION", note = "the plan: Murloc Eye 9s 75c ea (2 in bank)" },
        [1206]   = { action = "AUCTION", note = "the plan: Moss Agate 8s ea (2 in bank)" },
        [4561]   = { action = "AUCTION", note = "the plan: Scalping Tomahawk jumped to 7s 99c on AH (vendor 3s 9c)" },
        [211855] = { action = "AUCTION", note = "the plan: Scroll: STHENIC LUNATE 8s 80c on AH" },
        [3182]   = { action = "AUCTION", note = "the plan: Spider's Silk 7s 10c on AH (vendor 3s 87c)" },
        [9766]   = { action = "AUCTION", note = "the plan: Greenweave Sash 6s on AH (vendor 3s 61c)" },
        [2836]   = { action = "AUCTION", note = "the plan: Coarse Stone ~2s 89c ea (~66s for 23)" },
        [2841]   = { action = "AUCTION", note = "the plan: Bronze Bar ~1s 70c ea (16 in bank)" },
        [2842]   = { action = "AUCTION", note = "the plan: Silver Bar ~3s 45c ea on AH" },
        [2771]   = { action = "AUCTION", note = "the plan: Tin Ore ~1s 13c ea (12 in bank)" },
        [3576]   = { action = "AUCTION", note = "the plan: Tin Bar ~1s 10c ea (17 total)" },
        [20744]  = { action = "AUCTION", note = "the plan: Minor Wizard Oil ~2s 97c ea on AH" },
        -- Supply gaps: thin on the AH (Market Research.md, "Supply gaps")
        [12006]  = { action = "AUCTION", note = "the plan: Meadow Ring ~30s, 9 listed (vendor 10s 64c)" },
        [15348]  = { action = "AUCTION", note = "the plan: Pathfinder Bracers ~14s, 5 listed (vendor 7s 92c)" },
        [6601]   = { action = "VENDOR", note = "the plan: Dervish Boots AH ~15s vs vendor 14s 37c (cut loses gold)" },
        [264040] = { action = "AUCTION", note = "the plan: Craftsman's Writ ~30s and falling (was 99s); sell soon" },
        [279944] = { action = "AUCTION", note = "the plan: Sharpening Wheel ~10s, almost none listed" },
        [5784]   = { action = "MAIL", to = "Cen", note = "the plan: Slimy Murloc Scale for Murloc Scale Belt/Breastplate" },
        [7287]   = { action = "AUCTION", note = "the plan: Red Whelp Scale ~11s, 131 listed" },
        [6889]   = { action = "AUCTION", note = "the plan: Small Egg ~3s, 163 listed" },
        -- Vendor where AH <= vendor or non-AH BoEs
        [16886]  = { action = "VENDOR", note = "the plan: Outlaw Sabre 65s 22c vendor" },
        [6504]   = { action = "VENDOR", note = "the plan: Wingblade 28s 83c vendor" },
        [4409]   = { action = "VENDOR", note = "the plan: AH 2s == vendor 2s (cut+deposit loses gold)" },
        [1705]   = { action = "VENDOR", note = "the plan: AH 5s 99c < vendor 6s (cut loses gold)" },
        [2304]   = { action = "VENDOR", note = "the plan: AH 15c == vendor 15c" },
        [5075]   = { action = "VENDOR", note = "the plan: AH 25c == vendor 25c" },
        -- Recipes / keep
        [4345]   = { action = "USE", note = "the plan: Ophelia learns it at Tailoring 95" },
        [21219]  = { action = "KEEP", note = "the plan: Gnomestomper learns at Cooking 175 (69s AH)" },
        [6369]   = { action = "KEEP", note = "the plan: Gnomestomper learns at Cooking 175 (53.5s AH)" },
        [17062]  = { action = "KEEP", note = "the plan: Gnomestomper learns at Cooking 175 (44s AH)" },
        -- Lead's kit
        [929]    = { action = "KEEP", note = "the plan: Healing Potions for Gnomestomper" },
        [858]    = { action = "MAIL", to = "main", note = "the plan: healing potions for Gnomestomper" },
        [118]    = { action = "MAIL", to = "main", note = "the plan: healing potions for Gnomestomper" },
        [2581]   = { action = "KEEP", note = "the plan: Gnomestomper's bandages" },
    },
}
