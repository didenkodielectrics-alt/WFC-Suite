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
    updated = "2026-11-16 (plan 7, 17:54 AH scan)",
    main = "Gnomestomper",
    summary = "Gnomestomper is level 27 in Orgrimmar with 4g 1s 98c; the account has 6g 38s 22c liquid. "
        .. "Today's scan (17:54) lowered several earlier estimates: Firefin Snapper is ~59c (the 84 in Bitores' mail are worth ~50s, not 1.45g), "
        .. "Red Woolen Boots now only break even, and the Murloc Scale crafts lose money. "
        .. "New best earners: Bitores' Sharpening Wheels (~24s for ~2s of mats, already known), Ophelia's Colorful Kilt (~68s, ~+32s; pattern ~7s on the AH), "
        .. "and later Cen's Pilferer's Gloves and Green Leather Armor. "
        .. "Priority now: Bitores and Ophelia clear mail and post the sellables; Bitores crafts Wheels; Ophelia buys the Kilt pattern; Cen opens his bank once.",

    goals = {
        -- Stage 1: finish remaining snapshot & mail pickups
        { id = "cen-bank", section = "Get the data & clear mail", who = "Cen",
          text = "Open the bank once",
          why = "Cen's bags are scanned again (29 items, 39s 61c), but the plan has never seen his bank" },
        { id = "bitores-mail", section = "Get the data & clear mail", who = "Bitores",
          text = "Collect mail (84 Firefin Snapper, 12 Oily Blackmouth, 11 Coarse Stone, 14 Rough Stone, 5 Stranglekelp, 2 Pyrite)",
          why = "About 80s of goods. Firefin fell to ~59c each with 5,084 listed, so sell it rather than wait. Keep the Rough Stone for Sharpening Wheels" },
        { id = "ophelia-mail", section = "Get the data & clear mail", who = "Ophelia",
          text = "Collect mail (78 Linen, 57 Wool, 8 Silk, Meadow Ring, Pathfinder Bracers, Hulking Leggings, Spider's Silk)",
          why = "Over 2g of cloth and BoEs is sitting in Ophelia's mailbox; the Wool alone is ~1g 11s at 1s 95c each" },

        -- Stage 2: bags & crafters feed the lead
        { id = "ophelia-bags", section = "Crafters", who = "Ophelia",
          text = "Make Linen Bags / Red Linen Bags for Cen and alts",
          why = "78 Linen Cloth is in her mail. Bags barely beat their mats on the AH (Red Linen Bag ~4s), so make them to use, not to sell" },
        { id = "ophelia-kilt", section = "Crafters", who = "Ophelia",
          text = "Buy Pattern: Colorful Kilt (~7s on the AH, 16 listed) and make Kilts",
          why = "Kilt sells ~68s (22 listed) for ~32s of mats (5 Bolts of Woolen Cloth + 3 Red Dye + Fine Thread), about +32s each. She's Tailoring 93; it's orange until 95. Post one or two at a time",
          steps = {
              "Buy Pattern: Colorful Kilt on the AH",
              "Turn the 57 Wool from her mail into Bolts of Woolen Cloth; Gnomestomper mails his 8 Bolts",
              "Buy Red Dye and Fine Thread from a trade supplies vendor",
              "Craft and post 1-2 Kilts at a time; make more as they sell",
          } },
        { id = "ophelia-boots", section = "Crafters", who = "Ophelia",
          text = "Reach Tailoring 95 (at 93), then learn Red Woolen Boots for skill-ups",
          why = "The pattern is in her bank. The Boots now sell for ~28s against ~27s of mats (31 listed), so they're for skill, not profit" },
        { id = "gap-bitores-wheel", section = "Crafters", who = "Bitores",
          text = "Post the 2 Sharpening Wheels (~24s) and craft more: 1 Rough Stone + 1 Copper Bar each",
          why = "Wheels sell ~24s with 99 listed, for ~2s of mats, and he already knows the recipe. He holds 37 Rough Stone; Gnomestomper's 7 Copper Ore make 7 bars. Post 5 at a time" },
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
              "Craft it from Light Leather (he has 41); it also gives skill-ups",
              "Mail it to Gnomestomper Greybeard",
          } },
        { id = "ench-mats", section = "Crafters", who = "Bitores / Cen",
          text = "Mail Greater Magic Essence (1 on Bitores) and Strange Dust (13 on Cen) to Ophelia",
          why = "Ophelia is the enchanter (Enchanting 112) and already holds 15 Lesser Magic Essence" },
        { id = "gnome-cooking", section = "Crafters", who = "Gnomestomper",
          text = "Push Cooking 168 -> 175 (cook the 76 Raw Rockscale Cod / 31 Yellowtail) to learn 3 recipes",
          why = "Cooking the raw fish costs nothing (Rockscale Cod sells for 5c). The 3 recipes are worth ~1g 10s on the AH (Sagefish Delight ~46s, Mithril Head Trout ~34s, Rockscale Cod ~30s), so sell them instead if you don't care about Cooking" },

        -- Stage 3: gold for the mount (11/16 17:54 AH prices)
        { id = "sell-mender", section = "Gold for the mount (100g at 40)", who = "Bitores",
          text = "Auction Plans: Iridescent Hammer (~50s) and Recipe: Lesser Mender's Potion (~44s)",
          why = "About 94s combined vs 4s 50c vendor. 15 of each are listed now and both are slipping, so sell soon" },
        { id = "ah-high-value", section = "Gold for the mount (100g at 40)", who = "All",
          text = "Auction surplus Wool (~1s 95c ea), 40 Sweet Nectar (~70s), 2 Lesser Moonstone (~24s ea), 16 Bronze Bars (~39s), 17 Tin Bars (~29s), 23 Coarse Stone (~22s), 4 Silver Bars (~20s), Murloc Eyes, Moss Agate, Minor Wizard Oil, Spider's Silk",
          why = "11/16 17:54 scan: all clear vendor comfortably after the 5% cut. Lesser Moonstone jumped from vendor-only to ~24s with 571 listed" },
        { id = "gnome-hogshank", section = "Gold for the mount (100g at 40)", who = "Gnomestomper",
          text = "List a few of the 20 Wild Hog Shank at ~4s 99c",
          why = "Only 26 are listed and it was 50c yesterday, so it's a spike: test 3-5, not the whole stack" },
        { id = "vendor-traps", section = "Gold for the mount (100g at 40)", who = "All",
          text = "Vendor items where AH <= vendor (Battering Hammer 27s 41c, Dervish Boots 14s 37c, Scalping Tomahawk 3s 9c, 57 Blood Shards, 20 Light Armor Kits, Seaforium schematic, Long Tail Feathers)",
          why = "AH 5% cut + 1s deposit loses money compared to vendoring directly" },
        { id = "pristine-check", section = "Gold for the mount (100g at 40)", who = "Cen / Gnomestomper",
          text = "Keep the Pristine Leather for Cen's own Pristine pieces, or sell if the price jumps",
          why = "~7s each on the AH now (1,270 listed); Pristine sets are Bind on Pickup, so they only help Cen unless prices spike" },
        { id = "gnome-gather", section = "Gold for the mount (100g at 40)", who = "Gnomestomper",
          text = "Skin, mine, and fish while questing; sell ore, bars and extra hides",
          why = "Today: Heavy Hide ~12s 70c, Gold Ore ~10s, Mithril Ore ~8s, Thick Leather ~6s 44c, Silver Ore ~6s, Iron Ore ~3s 25c, Pyrite ~3s. Leather goes to Cen" },
        { id = "mount-fund", section = "Gold for the mount (100g at 40)", who = "Gnomestomper",
          text = "Save 100g by level 40 (90g if Honored with Orgrimmar)",
          why = "Account has 6g 38s 22c liquid right now; don't spend on AH upgrades, park spare gold on Ophelia" },

        -- Stage 3b: supply gaps (thin or empty on the AH; see "Supply gaps" in Market Research.md)
        { id = "gap-list-owned", section = "Supply gaps (thin or empty AH)", who = "Ophelia / Cen",
          text = "Auction Meadow Ring (~51s), Craftsman's Writ (~35s), Pathfinder Bracers (~14s) and Hulking Leggings",
          why = "Thin markets: 6-11 listed each. Hulking Leggings has a single listing at 1g 86s; yesterday's market was ~19s, so price it in between and lower it if it doesn't sell" },
        { id = "gap-gnome-farm", section = "Supply gaps (thin or empty AH)", who = "Gnomestomper",
          text = "Skin Red Whelps if you pass them (Red Whelp Scale ~12s)",
          why = "Only 62 listed today. Small Egg (~1s 80c) and Slimy Murloc Scale (~1s 55c) aren't worth a detour" },
        { id = "gap-vendor-stock", section = "Supply gaps (thin or empty AH)", who = "Any",
          text = "At an engineering supplier, compare Wooden Stock (AH ~7s 87c, 24 listed) with the vendor price",
          why = "The Classic vendor price was ~2s; Forever's may differ, so read the price before buying. Heavy Stock fell to ~23s, too close to its ~20s vendor price" },
        { id = "gap-soon", section = "Supply gaps (thin or empty AH)", who = "Cen",
          text = "Aim Leatherworking at ~115-125 for Pilferer's Gloves and Green Leather Armor",
          why = "Pilferer's Gloves sell ~1g 25s (5 listed) for ~42s of mats incl. 2 Lucky Charms; its pattern is ~8s on the AH (1 listed). Green Leather Armor ~75s (14 listed) for ~24s; its pattern is sold by George Candarte, Hillsbrad" },

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
            notes = "Level 27 in Orgrimmar (4g 1s 98c). Skinning 186, Fishing 198, Cooking 168 (175 unlocks 3 recipes), Mining 124, First Aid 80. Mails 8 Bolts of Woolen Cloth to Ophelia and 7 Copper Ore (as bars) to Bitores; auctions bank bars, Murloc Eyes and Moss Agate." },
        Cen = { role = "Leatherworker",
            notes = "Level 10 in Thunder Bluff (39s 61c), Leatherworking 110/150, Herbalism 27/75. Holds 41 Light + 37 Medium Leather, 15 Pristine Leather, and the Herbalist's Gloves writ (~35s). Opens his bank once; crafts Gnomestomper's quiver and armor." },
        Ophelia = { role = "Tailor · enchanter · bank alt",
            notes = "Tailoring 93/150, Enchanting 112/150 (The Crossroads, 3s 37c). Clears ~2g of mail, makes Colorful Kilts (~+32s each), reaches Tailoring 95, and auctions BoEs and surplus Wool." },
        Bitores = { role = "Herb holder · alchemist · seller",
            notes = "Blacksmithing 48/75 + Alchemy 33/75 in Undercity (1g 93s 26c). Clears mail (84 Firefin ~50s), crafts Sharpening Wheels (~+20s each), auctions Plans: Iridescent Hammer (~50s) + Mender's recipe (~44s). Sulfuric Acid now loses money, so his Alchemy isn't a priority." },
    },

    items = {
        -- Linen & Wool: bags / First Aid / Kilts first, then AH surplus Wool (~1s 95c ea)
        [2589]   = { action = "MAIL", to = "Ophelia", note = "the plan: bags first (78 in Ophelia's mail)" },
        [2592]   = { action = "AUCTION", note = "the plan: ~1s 95c ea after Gnomestomper hits FA 85 & Ophelia has Kilt bolts" },
        [2997]   = { action = "MAIL", to = "Ophelia", note = "the plan: Bolts of Woolen Cloth for Colorful Kilts (5 per Kilt)" },
        [4306]   = { action = "KEEP", note = "the plan: Silk Cloth AH ~90c is below vendor 1s 50c; keep for Ophelia's tailoring" },
        -- Leather & hides -> Cen (leatherworker)
        [2318]   = { action = "MAIL", to = "Cen", note = "the plan: Cen's leatherworking" },
        [2319]   = { action = "MAIL", to = "Cen", note = "the plan: Cen's leatherworking" },
        [4234]   = { action = "MAIL", to = "Cen", note = "the plan: Heavy Leather for Cen (Green Leather Armor later)" },
        [783]    = { action = "MAIL", to = "Cen", note = "the plan: Cen cures hides" },
        [4231]   = { action = "MAIL", to = "Cen", note = "the plan: Cen's leatherworking" },
        [4232]   = { action = "MAIL", to = "Cen", note = "the plan: Cen cures hides" },
        [5082]   = { action = "MAIL", to = "Cen", note = "the plan: Cen's leatherworking" },
        [6470]   = { action = "MAIL", to = "Cen", note = "the plan: Cen's leatherworking" },
        [249427] = { action = "KEEP", note = "the plan: AH ~7s; hold for Cen's Pristine pieces unless it spikes" },
        -- Herbs -> Bitores (Alchemy 33)
        [765]    = { action = "MAIL", to = "Bitores", note = "the plan: Bitores' Alchemy" },
        [2447]   = { action = "MAIL", to = "Bitores", note = "the plan: Bitores' Alchemy" },
        [2449]   = { action = "MAIL", to = "Bitores", note = "the plan: Bitores' Alchemy" },
        [785]    = { action = "MAIL", to = "Bitores", note = "the plan: Bitores' Alchemy" },
        -- Sharpening Wheel mats -> Bitores
        [2835]   = { action = "MAIL", to = "Bitores", note = "the plan: Rough Stone for Sharpening Wheels (~24s each)" },
        [2770]   = { action = "MAIL", to = "Bitores", note = "the plan: Copper Ore -> bars for Sharpening Wheels" },
        [2840]   = { action = "MAIL", to = "Bitores", note = "the plan: Copper Bar for Sharpening Wheels" },
        -- Enchanting materials -> Ophelia
        [10938]  = { action = "MAIL", to = "Ophelia", note = "the plan: Ophelia's enchanting (15 in bags)" },
        [10939]  = { action = "MAIL", to = "Ophelia", note = "the plan: 1 on Bitores -> Ophelia" },
        [10940]  = { action = "MAIL", to = "Ophelia", note = "the plan: 13 Strange Dust on Cen -> Ophelia" },
        -- High-value AH items (11/16 17:54 Auctionator scan)
        [6359]   = { action = "AUCTION", note = "the plan: Firefin Snapper ~59c ea, 5,084 listed (~50s for 84)" },
        [6358]   = { action = "AUCTION", note = "the plan: Oily Blackmouth ~1s 28c ea" },
        [5543]   = { action = "AUCTION", note = "the plan: Plans: Iridescent Hammer ~50s (15 listed, slipping)" },
        [250989] = { action = "AUCTION", note = "the plan: Recipe: Lesser Mender's Potion ~44s (15 listed)" },
        [279944] = { action = "AUCTION", note = "the plan: Sharpening Wheel ~24s, 99 listed; post 5 at a time" },
        [1705]   = { action = "AUCTION", note = "the plan: Lesser Moonstone ~24s 50c, 571 listed (vendor 6s)" },
        [1708]   = { action = "AUCTION", note = "the plan: Sweet Nectar ~1s 75c ea, 80 listed" },
        [3771]   = { action = "AUCTION", note = "the plan: Wild Hog Shank ~4s 99c but 26 listed and 50c yesterday; test a few" },
        [6363]   = { action = "AUCTION", note = "the plan: 26 Pound Catfish ~30s, 2 listed" },
        [3469]   = { action = "AUCTION", note = "the plan: Copper Chain Boots ~3s on AH (vendor 49c)" },
        [730]    = { action = "AUCTION", note = "the plan: Murloc Eye ~7s 50c ea (2 in bank)" },
        [1206]   = { action = "AUCTION", note = "the plan: Moss Agate ~7s ea (2 in bank)" },
        [211855] = { action = "AUCTION", note = "the plan: Scroll: STHENIC LUNATE ~5s on AH" },
        [3182]   = { action = "AUCTION", note = "the plan: Spider's Silk ~8s on AH (vendor 3s 87c)" },
        [9766]   = { action = "AUCTION", note = "the plan: Greenweave Sash ~5s 76c on AH (vendor 3s 61c)" },
        [2836]   = { action = "AUCTION", note = "the plan: Coarse Stone ~95c ea (~22s for 23)" },
        [2841]   = { action = "AUCTION", note = "the plan: Bronze Bar ~2s 47c ea (16 in bank)" },
        [2842]   = { action = "AUCTION", note = "the plan: Silver Bar ~4s 99c ea" },
        [2771]   = { action = "AUCTION", note = "the plan: Tin Ore ~1s 77c ea (12 in bank)" },
        [3576]   = { action = "AUCTION", note = "the plan: Tin Bar ~1s 72c ea (17 total)" },
        [20744]  = { action = "AUCTION", note = "the plan: Minor Wizard Oil ~3s 99c ea" },
        -- Supply gaps: thin on the AH (Market Research.md, "Supply gaps")
        [12006]  = { action = "AUCTION", note = "the plan: Meadow Ring ~51s, 6 listed (vendor 10s 64c)" },
        [15348]  = { action = "AUCTION", note = "the plan: Pathfinder Bracers ~14s, 7 listed (vendor 7s 92c)" },
        [14748]  = { action = "AUCTION", note = "the plan: Hulking Leggings: 1 listed at 1g 86s, ~19s yesterday; price in between" },
        [264040] = { action = "AUCTION", note = "the plan: Craftsman's Writ ~35s, 11 listed" },
        [7287]   = { action = "AUCTION", note = "the plan: Red Whelp Scale ~12s, 62 listed" },
        [6889]   = { action = "AUCTION", note = "the plan: Small Egg ~1s 80c, 164 listed" },
        -- Vendor where AH <= vendor
        [6601]   = { action = "VENDOR", note = "the plan: Dervish Boots AH ~15s vs vendor 14s 37c (cut loses gold)" },
        [3198]   = { action = "VENDOR", note = "the plan: Battering Hammer AH ~27s 49c vs vendor 27s 41c" },
        [4561]   = { action = "VENDOR", note = "the plan: Scalping Tomahawk AH ~3s 99c vs vendor 3s 9c (cut+deposit)" },
        [5116]   = { action = "VENDOR", note = "the plan: Long Tail Feather AH 3s 2c == vendor 3s 3c" },
        [4409]   = { action = "VENDOR", note = "the plan: AH 2s == vendor 2s (cut+deposit loses gold)" },
        [2304]   = { action = "VENDOR", note = "the plan: AH 24c vs vendor 15c (deposit eats it)" },
        [5075]   = { action = "VENDOR", note = "the plan: AH 25c == vendor 25c" },
        -- Recipes / keep
        [4345]   = { action = "USE", note = "the plan: Ophelia learns it at Tailoring 95 (skill-ups; pattern only ~3s on AH)" },
        [21219]  = { action = "KEEP", note = "the plan: learn at Cooking 175, or sell (~46s on AH)" },
        [6369]   = { action = "KEEP", note = "the plan: learn at Cooking 175, or sell (~30s on AH)" },
        [17062]  = { action = "KEEP", note = "the plan: learn at Cooking 175, or sell (~34s on AH)" },
        -- Lead's kit
        [929]    = { action = "KEEP", note = "the plan: Healing Potions for Gnomestomper" },
        [858]    = { action = "MAIL", to = "main", note = "the plan: healing potions for Gnomestomper" },
        [118]    = { action = "MAIL", to = "main", note = "the plan: healing potions for Gnomestomper" },
        [2581]   = { action = "KEEP", note = "the plan: Gnomestomper's bandages" },
    },
}
