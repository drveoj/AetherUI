--[[--------------------------------------------------------------------------
	AetherUI :: IFEC route table  -  GENERATED, DO NOT EDIT

	Written by Tools/taxidata.py from the client's own DB2 export, build
	1.15.9.69109. Edit the generator, not this file.

	Seconds per SINGLE-HOP leg, keyed [from][to] on the names TaxiNodeName
	returns. A multi-hop journey is the sum of its legs - proved against
	measured flights, and the reason only legs are stored.

	Directional: the same two nodes take different times each way.
----------------------------------------------------------------------------]]

local ADDON, A = ...

A.IFEC_ROUTE_BUILD = "1.15.9.69109"
A.IFEC_TAXI_SPEED  = 30.122

A.IFEC_LEGS = {
	["Aerie Peak, The Hinterlands"] = {
		["Chillwind Camp, Western Plaguelands"] = 52.8,
		["Ironforge, Dun Morogh"] = 254.2,
		["Light's Hope Chapel, Eastern Plaguelands"] = 163.4,
		["Refuge Pointe, Arathi"] = 75.3,
		["Southshore, Hillsbrad"] = 67.7,
	},
	["Astranaar, Ashenvale"] = {
		["Auberdine, Darkshore"] = 146.9,
		["Stonetalon Peak, Stonetalon Mountains"] = 152.7,
		["Talrendis Point, Azshara"] = 147,
	},
	["Auberdine, Darkshore"] = {
		["Astranaar, Ashenvale"] = 175,
		["Feathermoon, Feralas"] = 470.4,
		["Moonglade"] = 150.2,
		["Nijel's Point, Desolace"] = 289.6,
		["Rut'theran Village, Teldrassil"] = 83.8,
		["Stonetalon Peak, Stonetalon Mountains"] = 180.3,
		["Talonbranch Glade, Felwood"] = 188.6,
		["Talrendis Point, Azshara"] = 298.1,
		["Theramore, Dustwallow Marsh"] = 672.2,
	},
	["Bloodvenom Post, Felwood"] = {
		["Crossroads, The Barrens"] = 239.9,
		["Everlook, Winterspring"] = 189.2,
		["Moonglade"] = 164.2,
		["Orgrimmar, Durotar"] = 257.2,
		["Valormok, Azshara"] = 239.7,
	},
	["Booty Bay, Stranglethorn"] = {
		["Darkshire, Duskwood"] = 174,
		["Grom'gol, Stranglethorn"] = 101.2,
		["Kargath, Badlands"] = 404.7,
		["Sentinel Hill, Westfall"] = 180.6,
		["Stonard, Swamp of Sorrows"] = 265.1,
		["Stormwind, Elwynn"] = 218.6,
	},
	["Brackenwall Village, Dustwallow Marsh"] = {
		["Crossroads, The Barrens"] = 160.9,
		["Gadgetzan, Tanaris"] = 221.1,
		["Orgrimmar, Durotar"] = 215.7,
		["Thunder Bluff, Mulgore"] = 223.4,
	},
	["Camp Mojache, Feralas"] = {
		["Cenarion Hold, Silithus"] = 129.4,
		["Crossroads, The Barrens"] = 262.8,
		["Freewind Post, Thousand Needles"] = 106.7,
		["Gadgetzan, Tanaris"] = 200,
		["Shadowprey Village, Desolace"] = 199.7,
		["Thunder Bluff, Mulgore"] = 258.2,
	},
	["Camp Taurajo, The Barrens"] = {
		["Crossroads, The Barrens"] = 79,
		["Freewind Post, Thousand Needles"] = 124.5,
		["Thunder Bluff, Mulgore"] = 113.2,
	},
	["Cenarion Hold, Silithus"] = {
		["Camp Mojache, Feralas"] = 129.3,
		["Feathermoon, Feralas"] = 173.9,
		["Gadgetzan, Tanaris"] = 213.7,
		["Marshal's Refuge, Un'Goro Crater"] = 93.6,
	},
	["Chillwind Camp, Western Plaguelands"] = {
		["Aerie Peak, The Hinterlands"] = 65,
		["Ironforge, Dun Morogh"] = 258.4,
		["Light's Hope Chapel, Eastern Plaguelands"] = 145.7,
		["Southshore, Hillsbrad"] = 85,
	},
	["Crossroads, The Barrens"] = {
		["Bloodvenom Post, Felwood"] = 252.4,
		["Brackenwall Village, Dustwallow Marsh"] = 161.9,
		["Camp Mojache, Feralas"] = 250.5,
		["Camp Taurajo, The Barrens"] = 89.8,
		["Freewind Post, Thousand Needles"] = 183.6,
		["Gadgetzan, Tanaris"] = 301.9,
		["Orgrimmar, Durotar"] = 141.2,
		["Ratchet, The Barrens"] = 51.3,
		["Splintertree Post, Ashenvale"] = 161.7,
		["Sun Rock Retreat, Stonetalon Mountains"] = 149.2,
		["Thunder Bluff, Mulgore"] = 181.3,
		["Valormok, Azshara"] = 167.7,
		["Zoram'gar Outpost, Ashenvale"] = 229.1,
	},
	["Darkshire, Duskwood"] = {
		["Booty Bay, Stranglethorn"] = 170.5,
		["Lakeshire, Redridge"] = 59.3,
		["Nethergarde Keep, Blasted Lands"] = 96.4,
		["Sentinel Hill, Westfall"] = 92.7,
		["Stormwind, Elwynn"] = 87.3,
	},
	["Dun Baldar, Alterac Valley"] = {
		["Ironforge, Dun Morogh"] = 276.6,
	},
	["Everlook, Winterspring"] = {
		["Bloodvenom Post, Felwood"] = 194.3,
		["Moonglade"] = 127.1,
		["Orgrimmar, Durotar"] = 302.6,
		["Talonbranch Glade, Felwood"] = 121.8,
		["Talrendis Point, Azshara"] = 174.8,
		["Valormok, Azshara"] = 134.2,
	},
	["Feathermoon, Feralas"] = {
		["Auberdine, Darkshore"] = 465.2,
		["Cenarion Hold, Silithus"] = 158.5,
		["Nijel's Point, Desolace"] = 225.7,
		["Thalanaar, Feralas"] = 153.9,
	},
	["Flame Crest, Burning Steppes"] = {
		["Kargath, Badlands"] = 99.4,
		["Stonard, Swamp of Sorrows"] = 211.7,
		["Thorium Point, Searing Gorge"] = 71.5,
	},
	["Freewind Post, Thousand Needles"] = {
		["Camp Mojache, Feralas"] = 122.3,
		["Camp Taurajo, The Barrens"] = 136.5,
		["Crossroads, The Barrens"] = 192.9,
		["Gadgetzan, Tanaris"] = 92.3,
		["Thunder Bluff, Mulgore"] = 224.6,
	},
	["Frostwolf Keep, Alterac Valley"] = {
		["Undercity, Tirisfal"] = 16,
	},
	["Gadgetzan, Tanaris"] = {
		["Brackenwall Village, Dustwallow Marsh"] = 220.7,
		["Camp Mojache, Feralas"] = 198.3,
		["Cenarion Hold, Silithus"] = 213.8,
		["Crossroads, The Barrens"] = 299.1,
		["Freewind Post, Thousand Needles"] = 86.4,
		["Marshal's Refuge, Un'Goro Crater"] = 105.1,
		["Orgrimmar, Durotar"] = 348.4,
		["Thalanaar, Feralas"] = 176.1,
		["Theramore, Dustwallow Marsh"] = 152.9,
		["Thunder Bluff, Mulgore"] = 302.3,
	},
	["Grom'gol, Stranglethorn"] = {
		["Booty Bay, Stranglethorn"] = 80.4,
		["Kargath, Badlands"] = 325.4,
		["Stonard, Swamp of Sorrows"] = 204.2,
	},
	["Hammerfall, Arathi"] = {
		["Kargath, Badlands"] = 257.6,
		["Revantusk Village, The Hinterlands"] = 89.8,
		["Tarren Mill, Hillsbrad"] = 116,
		["Undercity, Tirisfal"] = 257.7,
	},
	["Ironforge, Dun Morogh"] = {
		["Aerie Peak, The Hinterlands"] = 296.8,
		["Chillwind Camp, Western Plaguelands"] = 292.7,
		["Dun Baldar, Alterac Valley"] = 276.6,
		["Light's Hope Chapel, Eastern Plaguelands"] = 346.6,
		["Menethil Harbor, Wetlands"] = 128.2,
		["Refuge Pointe, Arathi"] = 251.8,
		["Southshore, Hillsbrad"] = 263.5,
		["Stormwind, Elwynn"] = 209.4,
		["Thelsamar, Loch Modan"] = 100.8,
		["Thorium Point, Searing Gorge"] = 86.1,
	},
	["Kargath, Badlands"] = {
		["Booty Bay, Stranglethorn"] = 414.7,
		["Flame Crest, Burning Steppes"] = 86.1,
		["Grom'gol, Stranglethorn"] = 311.3,
		["Hammerfall, Arathi"] = 261.6,
		["Stonard, Swamp of Sorrows"] = 279.7,
		["Thorium Point, Searing Gorge"] = 55.8,
		["Undercity, Tirisfal"] = 495.3,
	},
	["Lakeshire, Redridge"] = {
		["Darkshire, Duskwood"] = 60.2,
		["Morgan's Vigil, Burning Steppes"] = 60.6,
		["Sentinel Hill, Westfall"] = 132.9,
		["Stormwind, Elwynn"] = 112,
	},
	["Light's Hope Chapel, Eastern Plaguelands"] = {
		["Aerie Peak, The Hinterlands"] = 161.7,
		["Chillwind Camp, Western Plaguelands"] = 148.9,
		["Ironforge, Dun Morogh"] = 366,
		["Revantusk Village, The Hinterlands"] = 140.5,
		["Undercity, Tirisfal"] = 260.2,
	},
	["Marshal's Refuge, Un'Goro Crater"] = {
		["Cenarion Hold, Silithus"] = 96.7,
		["Gadgetzan, Tanaris"] = 107.8,
	},
	["Menethil Harbor, Wetlands"] = {
		["Ironforge, Dun Morogh"] = 88.3,
		["Refuge Pointe, Arathi"] = 112.5,
		["Southshore, Hillsbrad"] = 106.7,
		["Thelsamar, Loch Modan"] = 161.9,
	},
	["Moonglade"] = {
		["Auberdine, Darkshore"] = 141,
		["Bloodvenom Post, Felwood"] = 156.4,
		["Everlook, Winterspring"] = 135.4,
		["Talonbranch Glade, Felwood"] = 61.1,
	},
	["Morgan's Vigil, Burning Steppes"] = {
		["Lakeshire, Redridge"] = 62.6,
		["Nethergarde Keep, Blasted Lands"] = 208.8,
		["Stormwind, Elwynn"] = 150.3,
		["Thorium Point, Searing Gorge"] = 102.6,
	},
	["Nethergarde Keep, Blasted Lands"] = {
		["Darkshire, Duskwood"] = 91.2,
		["Morgan's Vigil, Burning Steppes"] = 207.5,
		["Stormwind, Elwynn"] = 188.3,
	},
	["Nighthaven, Moonglade"] = {
		["Rut'theran Village, Teldrassil"] = 151.3,
		["Thunder Bluff, Mulgore"] = 541.6,
	},
	["Nijel's Point, Desolace"] = {
		["Auberdine, Darkshore"] = 280.8,
		["Feathermoon, Feralas"] = 230.7,
		["Stonetalon Peak, Stonetalon Mountains"] = 118.9,
		["Theramore, Dustwallow Marsh"] = 306.1,
	},
	["Orgrimmar, Durotar"] = {
		["Bloodvenom Post, Felwood"] = 250.9,
		["Brackenwall Village, Dustwallow Marsh"] = 227.5,
		["Crossroads, The Barrens"] = 109.7,
		["Everlook, Winterspring"] = 318.1,
		["Gadgetzan, Tanaris"] = 415,
		["Splintertree Post, Ashenvale"] = 89,
		["Thunder Bluff, Mulgore"] = 223.9,
		["Valormok, Azshara"] = 98.4,
	},
	["Plaguewood Tower, Eastern Plaguelands"] = {
		["Crown Guard Tower, Eastern Plaguelands"] = 51.1,
		["Eastwall Tower, Eastern Plaguelands"] = 63,
		["Northpass Tower, Eastern Plaguelands"] = 49.1,
	},
	["Quest Path 9571: S03 - Runecarving - Shaman - Level 40 Quest - 6 - KJA"] = {
		["Quest Path 9571: S03 - Runecarving - Shaman - Level 40 Quest - 6 - KJA"] = 39.1,
	},
	["Quest Path 9574: S03 - Runecarving - Shaman - Level 40 Quest - 6 - Flight Back - KJA"] = {
		["Quest Path 9574: S03 - Runecarving - Shaman - Level 40 Quest - 6 - Flight Back - KJA"] = 10.1,
	},
	["Quest Path 9620: S03 - Runecarving - Shaman - Level 40 Rune - Corrupted Fire Totem - Tal Taxi Path - KJA"] = {
		["Quest Path 9620: S03 - Runecarving - Shaman - Level 40 Rune - Corrupted Fire Totem - Tal Taxi Path - KJA"] = 360.3,
	},
	["Ratchet, The Barrens"] = {
		["Crossroads, The Barrens"] = 67.8,
		["Talrendis Point, Azshara"] = 131.5,
		["Theramore, Dustwallow Marsh"] = 104.5,
	},
	["Refuge Pointe, Arathi"] = {
		["Aerie Peak, The Hinterlands"] = 71.4,
		["Ironforge, Dun Morogh"] = 269.2,
		["Menethil Harbor, Wetlands"] = 125.3,
		["Southshore, Hillsbrad"] = 86.2,
		["Thelsamar, Loch Modan"] = 169.7,
	},
	["Revantusk Village, The Hinterlands"] = {
		["Hammerfall, Arathi"] = 92.5,
		["Light's Hope Chapel, Eastern Plaguelands"] = 138.1,
		["Tarren Mill, Hillsbrad"] = 158.3,
		["Undercity, Tirisfal"] = 283.5,
	},
	["Rut'theran Village, Teldrassil"] = {
		["Auberdine, Darkshore"] = 84.7,
	},
	["Sentinel Hill, Westfall"] = {
		["Booty Bay, Stranglethorn"] = 184.6,
		["Darkshire, Duskwood"] = 96.2,
		["Lakeshire, Redridge"] = 129.1,
		["Stormwind, Elwynn"] = 85.2,
	},
	["Shadowprey Village, Desolace"] = {
		["Camp Mojache, Feralas"] = 195,
		["Sun Rock Retreat, Stonetalon Mountains"] = 198.1,
		["Thunder Bluff, Mulgore"] = 177.3,
	},
	["Southshore Ferry, Hillsbrad"] = {
		["Menethil Harbor, Wetlands"] = 207.5,
	},
	["Southshore, Hillsbrad"] = {
		["Aerie Peak, The Hinterlands"] = 71,
		["Chillwind Camp, Western Plaguelands"] = 80.3,
		["Ironforge, Dun Morogh"] = 205,
		["Menethil Harbor, Wetlands"] = 109.6,
		["Refuge Pointe, Arathi"] = 73.5,
	},
	["Splintertree Post, Ashenvale"] = {
		["Crossroads, The Barrens"] = 159.6,
		["Orgrimmar, Durotar"] = 95.2,
		["Valormok, Azshara"] = 95.3,
		["Zoram'gar Outpost, Ashenvale"] = 165.8,
	},
	["Stonard, Swamp of Sorrows"] = {
		["Booty Bay, Stranglethorn"] = 258.9,
		["Flame Crest, Burning Steppes"] = 196.4,
		["Grom'gol, Stranglethorn"] = 187.4,
		["Kargath, Badlands"] = 284,
	},
	["Stonetalon Peak, Stonetalon Mountains"] = {
		["Astranaar, Ashenvale"] = 153.2,
		["Auberdine, Darkshore"] = 176.1,
		["Nijel's Point, Desolace"] = 126.2,
	},
	["Stormwind, Elwynn"] = {
		["Booty Bay, Stranglethorn"] = 242.9,
		["Darkshire, Duskwood"] = 115.2,
		["Ironforge, Dun Morogh"] = 257.2,
		["Lakeshire, Redridge"] = 111.8,
		["Morgan's Vigil, Burning Steppes"] = 156,
		["Nethergarde Keep, Blasted Lands"] = 174.9,
		["Sentinel Hill, Westfall"] = 77,
	},
	["Sun Rock Retreat, Stonetalon Mountains"] = {
		["Crossroads, The Barrens"] = 148.6,
		["Shadowprey Village, Desolace"] = 142.7,
		["Thunder Bluff, Mulgore"] = 173.5,
	},
	["Talonbranch Glade, Felwood"] = {
		["Auberdine, Darkshore"] = 186.6,
		["Everlook, Winterspring"] = 119.5,
		["Moonglade"] = 66.6,
		["Talrendis Point, Azshara"] = 281,
	},
	["Talrendis Point, Azshara"] = {
		["Astranaar, Ashenvale"] = 152,
		["Auberdine, Darkshore"] = 300.1,
		["Everlook, Winterspring"] = 177.8,
		["Ratchet, The Barrens"] = 134.8,
		["Talonbranch Glade, Felwood"] = 282.3,
		["Theramore, Dustwallow Marsh"] = 240.4,
	},
	["Tarren Mill, Hillsbrad"] = {
		["Hammerfall, Arathi"] = 117.3,
		["Revantusk Village, The Hinterlands"] = 193.9,
		["The Sepulcher, Silverpine Forest"] = 98.6,
		["Undercity, Tirisfal"] = 138.5,
	},
	["Thalanaar, Feralas"] = {
		["Feathermoon, Feralas"] = 177.1,
		["Gadgetzan, Tanaris"] = 170,
		["Theramore, Dustwallow Marsh"] = 158.7,
	},
	["The Sepulcher, Silverpine Forest"] = {
		["Tarren Mill, Hillsbrad"] = 94.5,
		["Undercity, Tirisfal"] = 111,
	},
	["Thelsamar, Loch Modan"] = {
		["Ironforge, Dun Morogh"] = 108.4,
		["Menethil Harbor, Wetlands"] = 151.5,
		["Refuge Pointe, Arathi"] = 162.7,
	},
	["Theramore, Dustwallow Marsh"] = {
		["Auberdine, Darkshore"] = 617.5,
		["Gadgetzan, Tanaris"] = 155.8,
		["Nijel's Point, Desolace"] = 332.4,
		["Ratchet, The Barrens"] = 114.4,
		["Talrendis Point, Azshara"] = 234.1,
		["Thalanaar, Feralas"] = 162.2,
	},
	["Thorium Point, Searing Gorge"] = {
		["Flame Crest, Burning Steppes"] = 76.3,
		["Ironforge, Dun Morogh"] = 93,
		["Kargath, Badlands"] = 69.4,
		["Morgan's Vigil, Burning Steppes"] = 95.1,
	},
	["Thunder Bluff, Mulgore"] = {
		["Brackenwall Village, Dustwallow Marsh"] = 237.3,
		["Camp Mojache, Feralas"] = 251.1,
		["Camp Taurajo, The Barrens"] = 86.3,
		["Crossroads, The Barrens"] = 157.8,
		["Freewind Post, Thousand Needles"] = 202.9,
		["Gadgetzan, Tanaris"] = 288.6,
		["Orgrimmar, Durotar"] = 206.3,
		["Shadowprey Village, Desolace"] = 158.4,
		["Sun Rock Retreat, Stonetalon Mountains"] = 180.6,
		["Valormok, Azshara"] = 267.9,
	},
	["Undercity, Tirisfal"] = {
		["Frostwolf Keep, Alterac Valley"] = 16,
		["Hammerfall, Arathi"] = 299.2,
		["Kargath, Badlands"] = 485.7,
		["Light's Hope Chapel, Eastern Plaguelands"] = 260.6,
		["Revantusk Village, The Hinterlands"] = 283.2,
		["Tarren Mill, Hillsbrad"] = 140.2,
		["The Sepulcher, Silverpine Forest"] = 105.6,
	},
	["Valormok, Azshara"] = {
		["Bloodvenom Post, Felwood"] = 230.9,
		["Crossroads, The Barrens"] = 171.4,
		["Everlook, Winterspring"] = 129.6,
		["Orgrimmar, Durotar"] = 120.3,
		["Splintertree Post, Ashenvale"] = 92.8,
		["Thunder Bluff, Mulgore"] = 255.6,
	},
	["Zoram'gar Outpost, Ashenvale"] = {
		["Crossroads, The Barrens"] = 226.6,
		["Splintertree Post, Ashenvale"] = 166.4,
	},
}

--- Legs the client has two paths for, one per faction, differing by more
--  than a second. The stored value is their mean; a measured one beats it.
A.IFEC_LEGS_FUZZY = {
	["Cenarion Hold, Silithus"] = {
		["Gadgetzan, Tanaris"] = true,
		["Marshal's Refuge, Un'Goro Crater"] = true,
	},
	["Everlook, Winterspring"] = {
		["Moonglade"] = true,
	},
	["Gadgetzan, Tanaris"] = {
		["Cenarion Hold, Silithus"] = true,
		["Marshal's Refuge, Un'Goro Crater"] = true,
	},
	["Marshal's Refuge, Un'Goro Crater"] = {
		["Cenarion Hold, Silithus"] = true,
		["Gadgetzan, Tanaris"] = true,
	},
	["Moonglade"] = {
		["Everlook, Winterspring"] = true,
	},
}
