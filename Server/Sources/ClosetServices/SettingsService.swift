import Foundation
import ClosetCore
import ClosetStorage

/// 用户画像，对应 App 设置页中保存在 `@AppStorage` 的四项。默认值与 App 相同。
public struct Profile: Codable, Sendable, Equatable {
    public var heightCm: Double = 0
    public var weightKg: Double = 0
    public var age: Int = 0
    /// `Gender` 的原始值，与 App 的 `@AppStorage("profile.gender")` 相同。
    public var gender: String = Gender.unspecified.rawValue

    public init(heightCm: Double = 0, weightKg: Double = 0, age: Int = 0, gender: String = Gender.unspecified.rawValue) {
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.age = age
        self.gender = gender
    }
}

/// 设置的读写。画像保存在本机数据库中，后续可纳入备份。
public struct SettingsService: Sendable {
    static let profileKey = "profile"
    let store: ClosetStore
    let now: @Sendable () -> Date

    public init(store: ClosetStore, now: @escaping @Sendable () -> Date = Date.init) {
        self.store = store
        self.now = now
    }

    public func profile() async throws -> Profile {
        guard let json = try await store.read({ try $0.setting(Self.profileKey) }) else { return Profile() }
        return (try? JSONDecoder().decode(Profile.self, from: Data(json.utf8))) ?? Profile()
    }

    /// 年龄范围与 App 的步进器相同（0 到 120）；身高体重必须是非负数。
    public func updateProfile(_ profile: Profile) async throws -> Profile {
        guard (0...120).contains(profile.age) else { throw ServiceError.invalid("年龄必须在 0 到 120 之间。") }
        let _: Gender = try parseEnum(profile.gender, field: "gender")
        for value in [profile.heightCm, profile.weightKg] where !(value.isFinite && value >= 0 && value < 1000) {
            throw ServiceError.invalid("身高与体重必须是 0 到 1000 之间的数字。")
        }
        let json = String(decoding: try JSONEncoder().encode(profile), as: UTF8.self)
        let timestamp = now()
        try await store.transaction { try $0.putSetting(Self.profileKey, json: json, updatedAt: timestamp) }
        return profile
    }
}
