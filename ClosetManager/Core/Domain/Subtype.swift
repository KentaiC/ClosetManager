import Foundation

/// 二级子类（细分种类）。每个子类归属于唯一的顶层 `Category`。
///
/// 用于更精细的衣物描述，并作为「默认命名」的种类部分（如「绿色短裤」中的「短裤」）。
enum Subtype: String, Codable, CaseIterable, Identifiable {
    // 外套 Outerwear
    case jacket            // 夹克
    case trenchCoat        // 风衣
    case overcoat          // 大衣
    case downJacket        // 羽绒服
    case paddedJacket      // 棉服
    case leatherJacket     // 皮衣
    case blazer            // 西装外套
    case cardigan          // 针织开衫
    case vest              // 马甲

    // 上装 Top
    case tee               // T恤
    case polo              // Polo衫
    case shirt             // 衬衫
    case hoodie            // 卫衣
    case sweater           // 毛衣/针织衫
    case tankTop           // 背心/吊带
    case baseLayer         // 打底衫
    case suit              // 西装（西服上衣）

    // 下装 Bottom
    case jeans             // 牛仔裤
    case casualPants       // 休闲裤
    case dressPants        // 西裤
    case sweatpants        // 运动裤
    case shorts            // 短裤
    case skirt             // 半身裙

    // 鞋子 Shoes
    case sneakers          // 运动鞋
    case canvasShoes       // 板鞋/帆布鞋
    case leatherShoes      // 皮鞋
    case boots             // 靴子
    case sandals           // 凉鞋
    case slippers          // 拖鞋
    case heels             // 高跟鞋

    // 配饰 Accessory
    case hat               // 帽子
    case scarf             // 围巾
    case belt              // 腰带
    case bag               // 包袋
    case gloves            // 手套
    case glasses           // 眼镜
    case tie               // 领带
    case jewelry           // 首饰

    // 袜子 Socks
    case noShowSocks       // 船袜
    case ankleSocks        // 短袜
    case crewSocks         // 中筒袜
    case kneeSocks         // 长筒袜
    case athleticSocks     // 运动袜

    var id: String { rawValue }

    /// 所属顶层分类。
    var category: Category {
        switch self {
        case .jacket, .trenchCoat, .overcoat, .downJacket, .paddedJacket,
             .leatherJacket, .blazer, .cardigan, .vest:
            return .outerwear
        case .tee, .polo, .shirt, .hoodie, .sweater, .tankTop, .baseLayer, .suit:
            return .top
        case .jeans, .casualPants, .dressPants, .sweatpants, .shorts, .skirt:
            return .bottom
        case .sneakers, .canvasShoes, .leatherShoes, .boots, .sandals, .slippers, .heels:
            return .shoes
        case .hat, .scarf, .belt, .bag, .gloves, .glasses, .tie, .jewelry:
            return .accessory
        case .noShowSocks, .ankleSocks, .crewSocks, .kneeSocks, .athleticSocks:
            return .socks
        }
    }

    /// 中文名称（用于 UI 展示与默认命名）。
    var displayName: String {
        switch self {
        case .jacket:        return "夹克"
        case .trenchCoat:    return "风衣"
        case .overcoat:      return "大衣"
        case .downJacket:    return "羽绒服"
        case .paddedJacket:  return "棉服"
        case .leatherJacket: return "皮衣"
        case .blazer:        return "西装外套"
        case .cardigan:      return "针织开衫"
        case .vest:          return "马甲"

        case .tee:           return "T恤"
        case .polo:          return "Polo衫"
        case .shirt:         return "衬衫"
        case .hoodie:        return "卫衣"
        case .sweater:       return "毛衣"
        case .tankTop:       return "背心"
        case .baseLayer:     return "打底衫"
        case .suit:          return "西装"

        case .jeans:         return "牛仔裤"
        case .casualPants:   return "休闲裤"
        case .dressPants:    return "西裤"
        case .sweatpants:    return "运动裤"
        case .shorts:        return "短裤"
        case .skirt:         return "半身裙"

        case .sneakers:      return "运动鞋"
        case .canvasShoes:   return "板鞋"
        case .leatherShoes:  return "皮鞋"
        case .boots:         return "靴子"
        case .sandals:       return "凉鞋"
        case .slippers:      return "拖鞋"
        case .heels:         return "高跟鞋"

        case .hat:           return "帽子"
        case .scarf:         return "围巾"
        case .belt:          return "腰带"
        case .bag:           return "包袋"
        case .gloves:        return "手套"
        case .glasses:       return "眼镜"
        case .tie:           return "领带"
        case .jewelry:       return "首饰"

        case .noShowSocks:   return "船袜"
        case .ankleSocks:    return "短袜"
        case .crewSocks:     return "中筒袜"
        case .kneeSocks:     return "长筒袜"
        case .athleticSocks: return "运动袜"
        }
    }
}
