//
//  PlayerSpotlightProvider.swift
//  NWSLApp
//
//  ⚠️ TEMP / SCAFFOLDING — curated static seed for Home's Module 2 ("Get to know
//  your players"), per Reference/Design/spotlight-design-spec.md.
//
//  WHAT: One spotlight player per club (all 16, incl. the 2026 Denver Summit /
//  Boston Legacy expansion sides). Each carries a hand-written bio blurb, an
//  extended profile (nationality / age / career highlights / fun facts), and a
//  REAL, verified player-focused video — a "get to know"/feature/mic'd-up/
//  interview, every YouTube id confirmed to resolve to a video whose title names
//  the player. Where no good video exists (Nérilia Mondésir — hers lives only on
//  Facebook), `video:` is nil and the profile is written-only (the spec's
//  explicit fallback). Video sources are attributed honestly: some are on a
//  team's own channel (Houston Dash, Thorns FC, Racing Louisville, Bay FC, Utah
//  Royals, Washington Spirit), others on league/partner media (NWSL, Victory+,
//  Attacking Third, The Women's Game) — labeled as such, never as the team.
//
//  WHY: The spec makes Module 2 a core differentiator — learn your team's roster
//  one player a week. There's no player-content backend yet, so this seed lets
//  the module be real and functional for concept demos, mirroring the Feed /
//  Module-1 seeds.
//
//  ACCURACY: bios are durable facts (trophies, caps, draft position) gathered by
//  research; volatile current-season stats are deliberately omitted. Ages are a
//  2026 snapshot; nil where genuinely uncertain. Treat as curated demo content to
//  be editorially re-verified, not a live source of truth.
//
//  WHEN REMOVED: replace `spotlights()` with a real source (a curated editorial
//  feed or the planned proxy / AI-tagging layer — spec §"Content pipeline")
//  returning the same `[PlayerSpotlight]`, ideally with per-player content links,
//  real thumbnails + durations, and the club color for a team-colored badge. The
//  async signature is already shaped for it; the ViewModel/views don't change.
//

import Foundation

struct PlayerSpotlightProvider {
    func spotlights() async -> [PlayerSpotlight] { Self.seed }

    /// Build a spotlight. `videoID` is a YouTube watch id (nil → written-only).
    private static func spot(
        _ abbr: String, _ name: String, _ number: Int, _ position: String,
        bio: String,
        videoID: String? = nil, videoTitle: String? = nil, videoSource: String? = nil,
        nationality: String, age: Int? = nil,
        highlights: [String], funFacts: [String]
    ) -> PlayerSpotlight {
        PlayerSpotlight(
            id: abbr,
            teamAbbreviation: abbr,
            playerName: name,
            jerseyNumber: number,
            position: position,
            bioBlurb: bio,
            videoURL: videoID.flatMap { URL(string: "https://www.youtube.com/watch?v=\($0)") },
            videoTitle: videoTitle,
            videoSource: videoSource,
            nationality: nationality,
            age: age,
            careerHighlights: highlights,
            funFacts: funFacts,
            seasonForm: nil
        )
    }

    private static let seed: [PlayerSpotlight] = [
        spot(
            "LA", "Sveindís Jónsdóttir", 32, "Forward",
            bio: "An Icelandic winger with rare pace and power, signed from German champions Wolfsburg. She's the first Icelander to score four goals in a single Champions League match — and a 60-cap veteran who came up the hard way, from Keflavík to Europe's biggest stages.",
            videoID: "aiiQzwJFjF8", videoTitle: "From Iceland to LA: Sveindís Jónsdóttir", videoSource: "The Women's Game",
            nationality: "Iceland", age: 25,
            highlights: [
                "2022 Frauen-Bundesliga title with VfL Wolfsburg",
                "First Icelander to score 4 goals in a UEFA Women's Champions League match (2024)",
                "60+ caps for Iceland; debuted at 19",
                "Joined Angel City FC in 2025",
            ],
            funFacts: ["Born in Keflavík to an Icelandic father and Ghanaian mother"]
        ),
        spot(
            "BAY", "Racheal Kundananji", 9, "Forward",
            bio: "Bay FC made her the most expensive player in women's football history, paying a reported world-record fee in 2024. The Zambian striker scores at nearly a goal a game for her country — and got her start in the sport while working as a welder back home.",
            videoID: "l511H7bawXg", videoTitle: "Launching the Kundananji Legacy Foundation", videoSource: "Bay FC",
            nationality: "Zambia", age: 26,
            highlights: [
                "Reported world-record transfer fee to Bay FC (2024)",
                "First Zambian to play and score in the NWSL",
                "Two-time Olympian (Tokyo 2020, Paris 2024) and 2023 World Cup",
                "~30 goals for Zambia",
            ],
            funFacts: [
                "Worked as a welder before turning pro",
                "Founded the Racheal Kundananji Legacy Foundation",
            ]
        ),
        spot(
            "BOS", "Casey Murphy", 1, "Goalkeeper",
            bio: "A 6-foot-1 Olympic gold-medal goalkeeper who became one of the highest-paid keepers in NWSL history when expansion side Boston Legacy signed her. She spent four seasons as the wall for the North Carolina Courage — including a 2024 season where she played every single minute.",
            videoID: "4PnEzCPUy54", videoTitle: "The Mindset of a Champion: Casey Murphy", videoSource: "Victory+",
            nationality: "United States", age: 30,
            highlights: [
                "2024 Paris Olympic gold medalist with the USWNT",
                "20 USWNT caps; 2023 World Cup roster",
                "NC Courage all-time regular-season wins leader",
                "Played every minute of the 2024 NWSL season",
            ],
            funFacts: [
                "At 6'1\", one of the tallest keepers in the league",
                "Two-time Big Ten Goalkeeper of the Year at Rutgers",
            ]
        ),
        spot(
            "CHI", "Mallory Swanson", 9, "Forward",
            bio: "She scored the only goal in the 2024 Olympic final to win the USWNT gold — the signature moment of a career that began at 17. A World Cup champion and the face of the Chicago franchise, she returned in 2026 after injury and the birth of her daughter. She's also married to MLB shortstop Dansby Swanson.",
            videoID: "6TY1Nqe44hk", videoTitle: "Mallory Swanson: Embracing Motherhood", videoSource: "Victory+",
            nationality: "United States", age: 28,
            highlights: [
                "Scored the gold-winning goal in the 2024 Paris Olympic final",
                "2019 FIFA Women's World Cup champion",
                "100+ USWNT caps",
                "Debuted for the USWNT at 17",
            ],
            funFacts: [
                "Married to MLB shortstop Dansby Swanson",
                "Returned in 2026 after injury and welcoming daughter Josie",
            ]
        ),
        spot(
            "DEN", "Yazmeen Ryan", 9, "Forward",
            bio: "A polished, versatile forward and a foundational signing for expansion side Denver Summit, who paid a reported seven-figure fee to land her. A former sixth-overall draft pick, she's already won an NWSL Championship and brings USWNT pedigree to a brand-new club.",
            videoID: "0F9aOKvSVT4", videoTitle: "Yazmeen Ryan joins Denver Summit FC", videoSource: "CBS Sports Golazo",
            nationality: "United States", age: 27,
            highlights: [
                "6th overall pick, 2021 NWSL Draft",
                "2024 NWSL Champion with Gotham FC",
                "USWNT experience",
                "Marquee expansion signing for Denver Summit FC (2026)",
            ],
            funFacts: ["Has played for four NWSL clubs across her career"]
        ),
        spot(
            "GFC", "Esther González", 9, "Forward",
            bio: "A 2023 World Cup champion with Spain and a ruthless big-moment finisher. In her first NWSL season she scored the title-winning goal in Gotham's 2023 championship run, and she left Real Madrid as the club's all-time leading women's scorer.",
            videoID: "VMzzEoihfvo", videoTitle: "Esther González on the CONCACAF W Champions Cup", videoSource: "DeporMx",
            nationality: "Spain", age: 33,
            highlights: [
                "2023 FIFA Women's World Cup champion with Spain",
                "Scored the title-winning goal in the 2023 NWSL Championship",
                "Real Madrid's all-time leading women's goalscorer",
                "Fastest player to 10 goals in a Gotham FC season",
            ],
            funFacts: [
                "Born in Huéscar, a small town in Granada, Spain",
                "Reserved off the pitch — clinical in front of goal",
            ]
        ),
        spot(
            "HOU", "Messiah Bright", 6, "Forward",
            bio: "TCU's all-time leading scorer and a former NWSL Rookie of the Year finalist, this Dallas-bred forward has found her feet with the Houston Dash — quick, direct, and a natural goalscorer playing for a Texas club.",
            videoID: "_ZSqGw6ZIwQ", videoTitle: "Mic'd Up with Messiah Bright", videoSource: "Houston Dash",
            nationality: "United States", age: 26,
            highlights: [
                "TCU's all-time leading scorer (50 goals)",
                "2023 NWSL Rookie of the Year finalist",
                "Drafted by the Orlando Pride (2023)",
                "Appeared in all 26 matches for Houston in 2025",
            ],
            funFacts: [
                "Born in Dallas, Texas",
                "Three-time Dallas Girls Cup champion in club soccer",
            ]
        ),
        spot(
            "KC", "Temwa Chawinga", 6, "Forward",
            bio: "The first player in NWSL history to score 20 goals in a single season — and she did it in her debut year, winning the 2024 MVP and Golden Boot as the first African-born player named league MVP. The Malawi international plays with electric speed and pure joy.",
            videoID: "98TPQlXbaVU", videoTitle: "Temwa Chawinga: Playing With Joy", videoSource: "Victory+",
            nationality: "Malawi",
            highlights: [
                "2024 NWSL MVP — first in franchise history",
                "2024 NWSL Golden Boot",
                "First player to score 20 goals in a single NWSL season",
                "First African-born NWSL MVP",
            ],
            funFacts: [
                "Her sister Tabitha Chawinga is also a star striker",
                "Arrived in KC from the Chinese Super League",
            ]
        ),
        spot(
            "NC", "Manaka Matsukubo", 34, "Midfielder",
            bio: "At just 5'1\", she's among the smallest pros in the game — and one of the most electric. She arrived from Japan as a teenager on loan and was named NWSL Midfielder of the Year in only her second full season.",
            videoID: "DeKTqXQEOug", videoTitle: "Manaka Matsukubo on Midfielder of the Year", videoSource: "NWSL",
            nationality: "Japan", age: 21,
            highlights: [
                "NWSL Midfielder of the Year (2025)",
                "2023 NWSL Challenge Cup winner & tournament MVP (at 19)",
                "Youngest player to score an NWSL hat trick",
                "2024 FIFA U-20 World Cup Silver Ball",
            ],
            funFacts: [
                "Listed at 5'1\", among the shortest players in pro soccer",
                "Came up through JFA Academy Fukushima",
            ]
        ),
        spot(
            "ORL", "Marta", 10, "Forward",
            bio: "Widely regarded as the greatest women's footballer of all time — a six-time FIFA World Player of the Year and the all-time leading scorer at World Cups, men's or women's. After nearly a decade chasing it, she finally lifted the NWSL Championship with Orlando in 2024.",
            videoID: "_lNjPvnDZKQ", videoTitle: "Marta on the 2024 NWSL Championship", videoSource: "Attacking Third",
            nationality: "Brazil", age: 40,
            highlights: [
                "6× FIFA World Player of the Year",
                "All-time leading World Cup goalscorer (17)",
                "Scored at five consecutive Olympics (3 silver medals)",
                "2024 NWSL Champion with Orlando Pride",
            ],
            funFacts: [
                "Orlando Pride captain since 2022",
                "Speaks Portuguese, Spanish, Swedish, and English",
            ]
        ),
        spot(
            "POR", "Sophia Wilson", 9, "Forward",
            bio: "A 2022 NWSL MVP and Olympic gold medalist, and one of the most explosive forwards in the world — part of the USWNT's feared \"Triple Espresso\" front line with Swanson and Rodman. The former No. 1 overall pick returned to the Thorns in 2026 on a landmark contract.",
            videoID: "2ZesQfrEnkg", videoTitle: "Sophia Wilson Returns to Portland", videoSource: "Thorns FC",
            nationality: "United States", age: 25,
            highlights: [
                "2022 NWSL MVP and Champion (Championship MVP)",
                "Paris 2024 Olympic gold medalist",
                "No. 1 overall pick, 2020 NWSL Draft",
                "2023 NWSL Golden Boot",
            ],
            funFacts: [
                "Part of the USWNT's \"Triple Espresso\" front line",
                "Returned to Portland in 2026 after sitting out 2025",
            ]
        ),
        spot(
            "LOU", "Emma Sears", 13, "Forward",
            bio: "A breakout USWNT winger out of Ohio State who announced herself in style — scoring and assisting on her senior national-team debut, then bagging a hat trick against New Zealand. Racing Louisville locked her in through 2028 as the cornerstone of their attack.",
            videoID: "0kirYAvoG2I", videoTitle: "Emma Sears: A Consistent Scoring Threat", videoSource: "Racing Louisville FC",
            nationality: "United States", age: 25,
            highlights: [
                "Scored and assisted on her USWNT debut (2024)",
                "Hat trick for the USWNT vs. New Zealand (2025)",
                "Drafted out of Ohio State (2024)",
                "Signed with Racing Louisville through 2028",
            ],
            funFacts: ["Has a twin sister, Bronwen, who played college soccer"]
        ),
        spot(
            "SD", "Kenza Dali", 10, "Midfielder",
            bio: "A French international who reinvented herself as San Diego's midfield engine after a decorated career at Lyon and in England's WSL. A relentless, technical veteran, she chose the NWSL to make her mark — and has said she may never quit the game.",
            videoID: "0Ax0rwgN9Mk", videoTitle: "Why San Diego Was the Perfect Choice for Kenza Dali", videoSource: "Unlaced",
            nationality: "France", age: 34,
            highlights: [
                "75+ caps for France",
                "2019 & 2023 World Cups; UEFA Euro 2022",
                "Long spell at Olympique Lyonnais",
                "Played in the WSL with Everton and Aston Villa",
            ],
            funFacts: [
                "French-Algerian heritage",
                "Known for her durability and longevity",
            ]
        ),
        spot(
            "SEA", "Nérilia Mondésir", 30, "Forward",
            bio: "The captain of Haiti and the first Haitian-born player in NWSL history — a trailblazer who scored on her Reign debut and committed her future to Seattle. She carries the hopes of a national program that reached its first-ever World Cup in 2023.",
            // Written-only: her "get to know" feature lives on Facebook, not YouTube.
            nationality: "Haiti",
            highlights: [
                "Captain of the Haiti national team",
                "First Haitian-born player in NWSL history",
                "Part of Haiti's first-ever World Cup squad (2023)",
                "Scored on her Seattle Reign debut",
            ],
            funFacts: [
                "With Haiti's national setup since 2014",
                "Joined Seattle from Montpellier (France)",
            ]
        ),
        spot(
            "UTA", "Mina Tanaka", 11, "Forward",
            bio: "A prolific Japan international striker who was a top scorer in Japan's top flight for nearly a decade before bringing her finishing to Utah. Born in Thailand to a Japanese father and Thai mother, she's scored 40 goals for Japan and played at two Olympics and a World Cup.",
            videoID: "jQV0RaQOKXI", videoTitle: "Get to Know: Mina Tanaka", videoSource: "Utah Royals FC",
            nationality: "Japan", age: 32,
            highlights: [
                "40 goals for Japan (Nadeshiko)",
                "2018 AFC Women's Asian Cup champion",
                "Olympics: Tokyo 2020 & Paris 2024",
                "Two-time Nadeshiko League Best Player",
            ],
            funFacts: [
                "Born in Ubon Ratchathani, Thailand",
                "Spent nine seasons with Tokyo Verdy Beleza",
            ]
        ),
        spot(
            "WAS", "Trinity Rodman", 2, "Forward",
            bio: "The daughter of NBA Hall of Famer Dennis Rodman who became the youngest player ever drafted in NWSL history — then instantly won a championship and Rookie of the Year. An Olympic gold medalist and one of the most electric attackers in the world, she's built a legend all her own.",
            videoID: "9cGlhS59PlE", videoTitle: "Trinity Rodman Mic'd Up at Practice", videoSource: "Washington Spirit",
            nationality: "United States", age: 24,
            highlights: [
                "2nd overall pick (2021) — youngest draftee in NWSL history",
                "2021 NWSL Champion & Rookie of the Year",
                "Paris 2024 Olympic gold medalist (3 goals)",
                "Record contract extension with the Spirit",
            ],
            funFacts: [
                "Daughter of NBA Hall of Famer Dennis Rodman",
                "Full name: Trinity Rain Moyer-Rodman",
            ]
        ),
    ]
}
