import Foundation

enum GroupIconResolver {
    private static let fluentBase =
        "https://cdn.jsdelivr.net/gh/microsoft/fluentui-emoji@1ffb34c752ecf5d402f04cfb4b392c77f57c54bc/assets/"
    private static let twemojiFlagBase =
        "https://cdn.jsdelivr.net/gh/jdecked/twemoji@15.1.0/assets/72x72/"

    private static let fluentPaths: [String: String] = [
        "🍃": "Leaf%20fluttering%20in%20wind/3D/leaf_fluttering_in_wind_3d.png",
        "🛑": "Stop%20sign/3D/stop_sign_3d.png",
        "🐟": "Fish/3D/fish_3d.png",
        "🛡": "Shield/3D/shield_3d.png",
        "🌏": "Globe%20showing%20asia-australia/3D/globe_showing_asia-australia_3d.png",
        "🌍": "Globe%20showing%20europe-africa/3D/globe_showing_europe-africa_3d.png",
        "🏠": "House/3D/house_3d.png",
        "🌐": "Globe%20with%20meridians/3D/globe_with_meridians_3d.png",
        "📶": "Antenna%20bars/3D/antenna_bars_3d.png",
        "🔀": "Shuffle%20tracks%20button/3D/shuffle_tracks_button_3d.png",
        "📢": "Loudspeaker/3D/loudspeaker_3d.png",
        "📹": "Video%20camera/3D/video_camera_3d.png",
        "🎥": "Movie%20camera/3D/movie_camera_3d.png",
        "🧸": "Teddy%20bear/3D/teddy_bear_3d.png",
        "🎬": "Clapper%20board/3D/clapper_board_3d.png",
        "🍿": "Popcorn/3D/popcorn_3d.png",
        "⚽": "Soccer%20ball/3D/soccer_ball_3d.png",
        "📺": "Television/3D/television_3d.png",
        "🎵": "Musical%20note/3D/musical_note_3d.png",
        "🎧": "Headphone/3D/headphone_3d.png",
        "🎶": "Musical%20notes/3D/musical_notes_3d.png",
        "📲": "Mobile%20phone%20with%20arrow/3D/mobile_phone_with_arrow_3d.png",
        "🤖": "Robot/3D/robot_3d.png",
        "🔷": "Large%20blue%20diamond/3D/large_blue_diamond_3d.png",
        "🐦": "Bird/3D/bird_3d.png",
        "♾": "Infinity/3D/infinity_3d.png",
        "📣": "Megaphone/3D/megaphone_3d.png",
        "🎙": "Studio%20microphone/3D/studio_microphone_3d.png",
        "👽": "Alien/3D/alien_3d.png",
        "📕": "Closed%20book/3D/closed_book_3d.png",
        "💬": "Speech%20balloon/3D/speech_balloon_3d.png",
        "📞": "Telephone%20receiver/3D/telephone_receiver_3d.png",
        "🐙": "Octopus/3D/octopus_3d.png",
        "🐳": "Spouting%20whale/3D/spouting_whale_3d.png",
        "📝": "Memo/3D/memo_3d.png",
        "📱": "Mobile%20phone/3D/mobile_phone_3d.png",
        "🔞": "No%20one%20under%20eighteen/3D/no_one_under_eighteen_3d.png",
        "🎨": "Artist%20palette/3D/artist_palette_3d.png",
        "💳": "Credit%20card/3D/credit_card_3d.png",
        "🪙": "Coin/3D/coin_3d.png",
        "🛒": "Shopping%20cart/3D/shopping_cart_3d.png",
        "☁": "Cloud/3D/cloud_3d.png",
        "Ⓜ": "Circled%20m/3D/circled_m_3d.png",
        "🍎": "Red%20apple/3D/red_apple_3d.png",
        "🔍": "Magnifying%20glass%20tilted%20left/3D/magnifying_glass_tilted_left_3d.png",
        "🎮": "Video%20game/3D/video_game_3d.png",
        "🎓": "Graduation%20cap/3D/graduation_cap_3d.png",
        "📰": "Newspaper/3D/newspaper_3d.png",
        "📧": "E-mail/3D/e-mail_3d.png",
        "🏦": "Bank/3D/bank_3d.png",
        "👥": "Busts%20in%20silhouette/3D/busts_in_silhouette_3d.png",
        "📥": "Inbox%20tray/3D/inbox_tray_3d.png",
        "🎯": "Bullseye/3D/bullseye_3d.png",
        "🔁": "Repeat%20button/3D/repeat_button_3d.png",
        "⚖": "Balance%20scale/3D/balance_scale_3d.png",
        "♻": "Recycling%20symbol/3D/recycling_symbol_3d.png",
        "🎛": "Control%20knobs/3D/control_knobs_3d.png",
        "🏡": "House%20with%20garden/3D/house_with_garden_3d.png",
        "💰": "Money%20bag/3D/money_bag_3d.png",
        "⭐": "Star/3D/star_3d.png",
        "🛠": "Hammer%20and%20wrench/3D/hammer_and_wrench_3d.png",
        "🗺": "World%20map/3D/world_map_3d.png",
        "🚀": "Rocket/3D/rocket_3d.png",
        "⚡": "High%20voltage/3D/high_voltage_3d.png",
    ]

    private static let phraseRules: [(emoji: String, keywords: [String])] = [
        ("🛑", ["reject", "adblock", "广告拦截", "全球拦截", "去广告", "拦截"]),
        ("🐟", ["final", "match", "漏网之鱼", "兜底", "剩余流量"]),
        ("🛡️", ["privacy", "tracking", "隐私", "追踪"]),
        ("📹", ["youtube", "油管"]),
        ("🎥", ["netflix", "奈飞", "网飞"]),
        ("🧸", ["disney", "迪士尼"]),
        ("📺", ["bilibili", "bahamut", "iqiyi", "youku", "twitch", "哔哩", "巴哈", "爱奇艺", "动漫"]),
        ("🎵", ["tiktok", "douyin", "抖音"]),
        ("🎧", ["spotify", "apple music"]),
        ("📲", ["telegram", "电报"]),
        ("🤖", ["openai", "chatgpt", "claude", "anthropic", "deepseek", "copilot", "perplexity", "grok", "ai平台", "人工智能"]),
        ("🔷", ["gemini", "bard"]),
        ("🐦", ["twitter", "推特"]),
        ("💬", ["wechat", "line", "discord", "whatsapp", "微信"]),
        ("🐙", ["github", "gitlab"]),
        ("🍎", ["apple", "icloud", "appstore", "testflight", "苹果"]),
        ("🔍", ["google", "gmail", "谷歌"]),
        ("Ⓜ️", ["microsoft", "onedrive", "bing", "微软"]),
        ("🎮", ["game", "steam", "epic", "playstation", "xbox", "nintendo", "游戏"]),
        ("🎯", ["direct", "全球直连", "直连", "国内", "大陆"]),
        ("🌍", ["global media", "streaming", "国外媒体", "国际媒体", "流媒体"]),
        ("🌏", ["china media", "asia media", "国内媒体", "港台媒体"]),
        ("♻️", ["auto", "url-test", "自动", "优选", "低延迟"]),
        ("🔁", ["fallback", "failover", "故障转移", "备用"]),
        ("🚀", ["proxy", "node", "节点选择", "默认", "代理"]),
    ]

    static func resolveEmoji(name: String, strategy: GroupStrategy?, members: [GroupMemberItem]) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let first = trimmed.unicodeScalars.first, first.properties.isEmojiPresentation || first.value >= 0x1F1E6 {
            let firstChar = String(trimmed.prefix(1))
            if firstChar != "#" && firstChar != "*" && !firstChar.allSatisfy(\.isNumber) {
                return firstChar
            }
        }

        let lowered = trimmed.lowercased()
        for rule in phraseRules where rule.keywords.contains(where: { lowered.contains($0) }) {
            return rule.emoji
        }

        for (code, meta) in RegionCatalog.presets where code != "OTHER" {
            if lowered.contains(meta.shortName) || lowered.contains(code.lowercased()) {
                return meta.flag
            }
        }

        let regionCodes = Set(members.compactMap { member -> String? in
            if case .region(let code) = member { return code }
            return nil
        })
        if regionCodes.count == 1, let only = regionCodes.first {
            return RegionCatalog.flagEmoji(of: only)
        }

        switch strategy {
        case .urlTest: return "⚡"
        case .fallback: return "🔁"
        default: return "🌐"
        }
    }

    static func iconURL(for emoji: String) -> URL? {
        let stripped = emoji.replacingOccurrences(of: "\u{FE0F}", with: "")
            .replacingOccurrences(of: "\u{FE0E}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let scalars = Array(stripped.unicodeScalars)
        if scalars.count == 2 && scalars.allSatisfy({ $0.value >= 0x1F1E6 && $0.value <= 0x1F1FF }) {
            let hex = scalars.map { String($0.value, radix: 16) }.joined(separator: "-")
            return URL(string: "\(twemojiFlagBase)\(hex).png")
        }

        if let path = fluentPaths[stripped] {
            return URL(string: "\(fluentBase)\(path)")
        }
        return nil
    }
}
