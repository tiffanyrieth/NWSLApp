//
//  TriviaQuestionProvider.swift
//  NWSLApp
//
//  ⚠️ TEMP / SCAFFOLDING — curated static seed for Home's Module 3 "Play",
//  game 1 (Daily Trivia), per Reference/Design/games-design-spec.md.
//
//  WHAT: 55 hand-written NWSL trivia questions covering all 16 clubs (incl. the
//  2026 Denver Summit / Boston Legacy expansion sides) at mixed difficulty, in a
//  mix of categories — league history, player facts, stadiums, rules, records,
//  team history. `questions()` returns the whole pool; the ViewModel
//  deterministically serves 5 per day from it (a seeded daily shuffle), so the
//  same 5 show all day and the pool rotates as days pass.
//
//  WHY: The spec wants Daily Trivia real and playable for a concept demo without
//  a backend. This seed is the question bank; the daily/streak/score state lives
//  in TriviaStore (UserDefaults), the session flow in TriviaViewModel.
//
//  ACCURACY: questions lean deliberately on DURABLE facts — league/championship
//  history, records, club founding, stadiums, and laws of the game — and avoid
//  volatile "who currently leads in goals" trivia, because a wrong answer in a
//  quiz is worse than a thin category. Facts are a 2026 snapshot gathered by
//  research; treat as curated demo content to be editorially re-verified, not a
//  live source of truth.
//
//  WHEN REMOVED: replace `questions()` with a real question backend (an editorial
//  feed or the planned proxy) returning the same `[TriviaQuestion]`. The async
//  signature is already shaped for it; the Store / ViewModel / View don't change.
//

import Foundation

struct TriviaQuestionProvider {
    func questions() async -> [TriviaQuestion] { Self.seed }

    /// Build a question. `correct` is the index (0–3) of the right option.
    private static func q(
        _ id: String,
        _ question: String,
        _ options: [String],
        correct: Int,
        _ category: TriviaQuestion.Category,
        _ difficulty: TriviaQuestion.Difficulty
    ) -> TriviaQuestion {
        TriviaQuestion(
            id: id,
            question: question,
            options: options,
            correctIndex: correct,
            category: category,
            difficulty: difficulty
        )
    }

    private static let seed: [TriviaQuestion] = [
        // MARK: League history
        q("q01", "In what year did the NWSL play its inaugural season?",
          ["2009", "2013", "2016", "2019"], correct: 1, .leagueHistory, .easy),
        q("q02", "The NWSL is the top division of women's professional soccer in which country?",
          ["Canada", "England", "United States", "Australia"], correct: 2, .leagueHistory, .easy),
        q("q03", "Which club has won the most NWSL Championships?",
          ["Orlando Pride", "Portland Thorns FC", "Kansas City Current", "Houston Dash"],
          correct: 1, .leagueHistory, .medium),
        q("q04", "How many clubs compete in the NWSL in the 2026 season?",
          ["12", "14", "16", "18"], correct: 2, .leagueHistory, .medium),
        q("q05", "Which club won the 2023 NWSL Championship?",
          ["NJ/NY Gotham FC", "Portland Thorns FC", "San Diego Wave FC", "Seattle Reign FC"],
          correct: 0, .leagueHistory, .medium),
        q("q06", "Which club won back-to-back NWSL Championships in 2018 and 2019?",
          ["Portland Thorns FC", "North Carolina Courage", "Chicago Red Stars", "Washington Spirit"],
          correct: 1, .leagueHistory, .medium),
        q("q07", "Which club won its first NWSL Championship in 2024?",
          ["Washington Spirit", "Kansas City Current", "Orlando Pride", "Bay FC"],
          correct: 2, .leagueHistory, .medium),
        q("q08", "Which club won the 2021 NWSL Championship?",
          ["Washington Spirit", "Chicago Red Stars", "Portland Thorns FC", "OL Reign"],
          correct: 0, .leagueHistory, .medium),
        q("q09", "Which club won the 2020 NWSL Challenge Cup, the league's tournament held during the pandemic?",
          ["Portland Thorns FC", "Houston Dash", "Chicago Red Stars", "North Carolina Courage"],
          correct: 1, .leagueHistory, .hard),
        q("q10", "Which club finished atop the regular season to win the 2023 NWSL Shield?",
          ["Portland Thorns FC", "NJ/NY Gotham FC", "San Diego Wave FC", "North Carolina Courage"],
          correct: 2, .leagueHistory, .hard),
        q("q11", "Which trophy is awarded to the NWSL club with the best regular-season record?",
          ["The Golden Boot", "The NWSL Shield", "The Challenge Cup", "The Supporters' Plate"],
          correct: 1, .leagueHistory, .medium),

        // MARK: Team history
        q("q12", "Which Hollywood actor was a founding investor in Angel City FC?",
          ["Reese Witherspoon", "Natalie Portman", "Margot Robbie", "Jennifer Lawrence"],
          correct: 1, .teamHistory, .medium),
        q("q13", "Angel City FC, which began play in 2022, is based in which city?",
          ["San Diego", "San Francisco", "Los Angeles", "Sacramento"],
          correct: 2, .teamHistory, .easy),
        q("q14", "Which two clubs joined the NWSL as expansion sides for the 2026 season?",
          ["Denver Summit and Boston Legacy", "Bay FC and Utah Royals",
           "Tampa Bay and Cincinnati", "Austin and Phoenix"],
          correct: 0, .teamHistory, .medium),
        q("q15", "Boston Legacy FC joined the NWSL as an expansion club in which year?",
          ["2022", "2024", "2025", "2026"], correct: 3, .teamHistory, .easy),
        q("q16", "The Denver Summit joined the NWSL as an expansion club for which season?",
          ["2024", "2025", "2026", "2027"], correct: 2, .teamHistory, .easy),
        q("q17", "Racing Louisville FC joined the NWSL as an expansion side in which year?",
          ["2019", "2021", "2023", "2024"], correct: 1, .teamHistory, .medium),
        q("q18", "The current Kansas City franchise was formed in 2021 when which club relocated to Kansas City?",
          ["Utah Royals FC", "Boston Breakers", "Sky Blue FC", "Western New York Flash"],
          correct: 0, .teamHistory, .hard),
        q("q19", "In 2024 the Utah Royals returned to the NWSL alongside which other new club?",
          ["Bay FC", "Angel City FC", "San Diego Wave FC", "Racing Louisville FC"],
          correct: 0, .teamHistory, .medium),
        q("q20", "The Chicago NWSL club rebranded for the 2025 season from the Red Stars to what name?",
          ["Chicago Fire FC", "Chicago Stars FC", "Chicago Surge", "Chicago Stockyards FC"],
          correct: 1, .teamHistory, .hard),

        // MARK: Stadiums
        q("q21", "Which NWSL club plays its home games at Providence Park?",
          ["Seattle Reign FC", "Portland Thorns FC", "Bay FC", "Angel City FC"],
          correct: 1, .venues, .easy),
        q("q22", "The Kansas City Current play at CPKC Stadium, the first stadium purpose-built for what?",
          ["A women's professional sports team", "An NWSL expansion club",
           "A college soccer program", "A minor-league baseball team"],
          correct: 0, .venues, .medium),
        q("q23", "The San Diego Wave play their home matches at which stadium?",
          ["Snapdragon Stadium", "Petco Park", "Torero Stadium", "SDCCU Stadium"],
          correct: 0, .venues, .medium),
        q("q24", "Angel City FC shares which downtown Los Angeles stadium with MLS side LAFC?",
          ["SoFi Stadium", "BMO Stadium", "Dignity Health Sports Park", "Rose Bowl"],
          correct: 1, .venues, .medium),
        q("q25", "The Washington Spirit play many of their home matches at which D.C. stadium?",
          ["Audi Field", "FedExField", "RFK Stadium", "Nationals Park"],
          correct: 0, .venues, .medium),
        q("q26", "The Houston Dash play their home matches at which stadium?",
          ["NRG Stadium", "Shell Energy Stadium", "Minute Maid Park", "TDECU Stadium"],
          correct: 1, .venues, .hard),
        q("q27", "Which club is known for drawing the NWSL's largest crowds at its riverside stadium in the Pacific Northwest?",
          ["Seattle Reign FC", "Portland Thorns FC", "Bay FC", "Utah Royals FC"],
          correct: 1, .venues, .medium),

        // MARK: Player facts
        q("q28", "Brazilian legend Marta plays for which NWSL club?",
          ["Orlando Pride", "Houston Dash", "Gotham FC", "NC Courage"],
          correct: 0, .playerFacts, .easy),
        q("q29", "Trinity Rodman, the youngest player ever drafted in NWSL history, plays for which club?",
          ["Portland Thorns FC", "Washington Spirit", "Chicago Stars FC", "Bay FC"],
          correct: 1, .playerFacts, .medium),
        q("q30", "Trinity Rodman is the daughter of which NBA Hall of Famer?",
          ["Scottie Pippen", "Dennis Rodman", "Charles Barkley", "Gary Payton"],
          correct: 1, .playerFacts, .easy),
        q("q31", "Mallory Swanson, who scored the gold-winning goal at the 2024 Olympics, plays club soccer for which NWSL team?",
          ["Portland Thorns FC", "Washington Spirit", "Chicago Stars FC", "Orlando Pride"],
          correct: 2, .playerFacts, .medium),
        q("q32", "Sophia Wilson (formerly Sophia Smith) won the 2022 NWSL MVP award with which club?",
          ["Portland Thorns FC", "San Diego Wave FC", "Kansas City Current", "Houston Dash"],
          correct: 0, .playerFacts, .medium),
        q("q33", "Striker Racheal Kundananji, signed by Bay FC for a reported world-record fee, plays for which national team?",
          ["Nigeria", "Zambia", "South Africa", "Ghana"],
          correct: 1, .playerFacts, .medium),
        q("q34", "Which goalkeeper, a 2024 Olympic gold medalist, spent four seasons with the North Carolina Courage before joining Boston Legacy?",
          ["Alyssa Naeher", "Casey Murphy", "Adrianna Franch", "Aubrey Kingsbury"],
          correct: 1, .playerFacts, .hard),
        q("q35", "Megan Rapinoe spent the bulk of her NWSL career with which club?",
          ["Portland Thorns FC", "Seattle Reign / OL Reign", "Chicago Red Stars", "Washington Spirit"],
          correct: 1, .playerFacts, .medium),
        q("q36", "Temwa Chawinga, the 2024 NWSL MVP, represents which national team?",
          ["Nigeria", "Malawi", "Cameroon", "Jamaica"],
          correct: 1, .playerFacts, .hard),
        q("q37", "Marta has been named FIFA World Player of the Year a record how many times?",
          ["Four", "Five", "Six", "Eight"], correct: 2, .playerFacts, .medium),

        // MARK: Records
        q("q38", "Who became the first player to score 20 goals in a single NWSL regular season, in 2024?",
          ["Sophia Smith", "Temwa Chawinga", "Sam Kerr", "Lynn Williams"],
          correct: 1, .records, .medium),
        q("q39", "Who won the 2024 NWSL MVP award, the first MVP in her franchise's history?",
          ["Marta", "Temwa Chawinga", "Barbra Banda", "Mallory Swanson"],
          correct: 1, .records, .medium),
        q("q40", "Before 2024, who held the NWSL single-season scoring record with 18 goals in 2019?",
          ["Sam Kerr", "Christen Press", "Alex Morgan", "Lynn Williams"],
          correct: 0, .records, .hard),
        q("q41", "Who is the NWSL's all-time regular-season leading goalscorer?",
          ["Sam Kerr", "Lynn Williams", "Christen Press", "Alex Morgan"],
          correct: 1, .records, .hard),
        q("q42", "The NWSL Golden Boot is awarded to the player with the most of what in a season?",
          ["Assists", "Clean sheets", "Goals", "Appearances"],
          correct: 2, .records, .easy),
        q("q43", "Bay FC made which striker the most expensive player in women's football history in 2024?",
          ["Racheal Kundananji", "Asisat Oshoala", "Barbra Banda", "Bunny Shaw"],
          correct: 0, .records, .medium),

        // MARK: Rules / laws of the game
        q("q44", "How many players from each team are on the field at kickoff?",
          ["9", "10", "11", "12"], correct: 2, .rules, .easy),
        q("q45", "How many substitutions is each NWSL team typically allowed during a match?",
          ["3", "4", "5", "6"], correct: 2, .rules, .medium),
        q("q46", "A standard soccer match is made up of two halves of how many minutes each?",
          ["40", "45", "50", "60"], correct: 1, .rules, .easy),
        q("q47", "What is shown to a player who commits a second cautionable offense in the same match?",
          ["A penalty kick", "A red card and sending-off", "A second yellow only", "A throw-in"],
          correct: 1, .rules, .easy),
        q("q48", "In the standings, what does the abbreviation 'GD' stand for?",
          ["Games Drawn", "Goal Difference", "Goal Defense", "Games Decided"],
          correct: 1, .rules, .easy),
        q("q49", "How many points does a team earn for a win in the NWSL regular season?",
          ["1", "2", "3", "4"], correct: 2, .rules, .easy),
        q("q50", "What is the official length of a regulation soccer match, before stoppage time?",
          ["80 minutes", "90 minutes", "100 minutes", "120 minutes"],
          correct: 1, .rules, .easy),

        // MARK: A few more club anchors / mixed
        q("q51", "Which NWSL club is nicknamed the Wave and is based in Southern California?",
          ["Angel City FC", "San Diego Wave FC", "Bay FC", "Utah Royals FC"],
          correct: 1, .teamHistory, .easy),
        q("q52", "The Houston-based NWSL club goes by which nickname?",
          ["the Dash", "the Stars", "the Current", "the Pride"],
          correct: 0, .teamHistory, .easy),
        q("q53", "Which club is based in the San Francisco Bay Area and debuted in the NWSL in 2024?",
          ["Angel City FC", "Bay FC", "San Diego Wave FC", "Seattle Reign FC"],
          correct: 1, .teamHistory, .easy),
        q("q54", "Esther González, a 2023 World Cup winner with Spain, plays for which NWSL club?",
          ["Orlando Pride", "NJ/NY Gotham FC", "Racing Louisville FC", "Chicago Stars FC"],
          correct: 1, .playerFacts, .hard),
        q("q55", "The Orlando Pride share their home venue and ownership group with which MLS club?",
          ["Inter Miami CF", "Orlando City SC", "Atlanta United FC", "Nashville SC"],
          correct: 1, .teamHistory, .medium),
    ]
}
