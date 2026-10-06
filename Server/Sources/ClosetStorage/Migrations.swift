import Foundation

/// 一次 schema 迁移。已发布的迁移不可修改，结构变化只能追加新的迁移。
struct Migration: Sendable {
    let version: Int
    let name: String
    let sql: String
}

/// 服务端数据库的全部迁移。
///
/// 时间字段统一存为 Unix 秒（REAL）。
///
/// 迁移中的取值列表是字面量快照，不在运行时从枚举生成，保证同一迁移在任何版本下执行结果相同。
/// `StorageSchemaTests` 校验这些列表与 ClosetCore 中的枚举一致：枚举新增取值时测试会失败，
/// 提醒追加一个放宽约束的新迁移。
enum Migrations {
    static let categoryValues = ["outerwear", "top", "bottom", "shoes", "accessory", "socks"]
    static let statusValues = ["inWardrobe", "inLaundry", "inLuggage"]
    static let scenarioValues = ["work", "casual", "sport", "formal"]
    static let warmthLevelValues = ["frigid", "cold", "cool", "mild", "warm", "hot"]
    static let seasonValues = ["spring", "summer", "autumn", "winter"]
    static let sourceValues = ["generated", "manual"]
    static let colorCategoryValues = ["black", "white", "gray", "beige", "brown", "red", "orange", "yellow",
                                      "green", "cyan", "blue", "purple", "pink", "multicolor"]
    static let slotValues = ["outerwear", "midLayer", "top", "bottom", "socks", "shoes", "accessory"]
    /// 子类与所属分类的对照表快照。
    static let subtypeCategories: [(String, String)] = [
        ("jacket", "outerwear"), ("trenchCoat", "outerwear"), ("overcoat", "outerwear"), ("downJacket", "outerwear"),
        ("paddedJacket", "outerwear"), ("leatherJacket", "outerwear"), ("blazer", "outerwear"), ("cardigan", "outerwear"),
        ("vest", "outerwear"),
        ("tee", "top"), ("polo", "top"), ("shirt", "top"), ("hoodie", "top"), ("sweater", "top"), ("tankTop", "top"),
        ("baseLayer", "top"), ("suit", "top"),
        ("jeans", "bottom"), ("casualPants", "bottom"), ("dressPants", "bottom"), ("sweatpants", "bottom"),
        ("shorts", "bottom"), ("skirt", "bottom"),
        ("sneakers", "shoes"), ("canvasShoes", "shoes"), ("leatherShoes", "shoes"), ("boots", "shoes"),
        ("sandals", "shoes"), ("slippers", "shoes"), ("heels", "shoes"),
        ("hat", "accessory"), ("scarf", "accessory"), ("belt", "accessory"), ("bag", "accessory"),
        ("gloves", "accessory"), ("glasses", "accessory"), ("tie", "accessory"), ("jewelry", "accessory"),
        ("noShowSocks", "socks"), ("ankleSocks", "socks"), ("crewSocks", "socks"), ("kneeSocks", "socks"),
        ("athleticSocks", "socks"),
    ]

    private static func list(_ values: [String]) -> String {
        values.map { "'\($0)'" }.joined(separator: ", ")
    }

    private static func jsonArrayCheck(_ column: String) -> String {
        "CHECK (json_valid(\(column)) AND json_type(\(column)) = 'array')"
    }

    static let all: [Migration] = [
        Migration(version: 1, name: "initial schema", sql: """
        CREATE TABLE subtypes (
            subtype TEXT PRIMARY KEY,
            category TEXT NOT NULL CHECK (category IN (\(list(categoryValues)))),
            UNIQUE (subtype, category)
        );
        INSERT INTO subtypes (subtype, category) VALUES
            \(subtypeCategories.map { "('\($0.0)', '\($0.1)')" }.joined(separator: ",\n    "));

        CREATE TABLE media (
            sha256 TEXT PRIMARY KEY CHECK (length(sha256) = 64),
            format TEXT NOT NULL,
            byte_count INTEGER NOT NULL CHECK (byte_count >= 0),
            created_at REAL NOT NULL
        );

        CREATE TABLE items (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            category TEXT NOT NULL CHECK (category IN (\(list(categoryValues)))),
            subtype TEXT,
            scenarios TEXT NOT NULL DEFAULT '[]' \(jsonArrayCheck("scenarios")),
            status TEXT NOT NULL CHECK (status IN (\(list(statusValues)))),
            is_waterproof INTEGER NOT NULL DEFAULT 0 CHECK (is_waterproof IN (0, 1)),
            laundry_entry_at REAL,
            processed_media TEXT REFERENCES media(sha256),
            original_media TEXT REFERENCES media(sha256),
            dominant_red REAL NOT NULL,
            dominant_green REAL NOT NULL,
            dominant_blue REAL NOT NULL,
            dominant_alpha REAL NOT NULL,
            secondary_red REAL,
            secondary_green REAL,
            secondary_blue REAL,
            secondary_alpha REAL,
            dominant_color_category TEXT NOT NULL CHECK (dominant_color_category IN (\(list(colorCategoryValues)))),
            warmth_score INTEGER NOT NULL CHECK (warmth_score BETWEEN 1 AND 100),
            warmth_levels TEXT NOT NULL \(jsonArrayCheck("warmth_levels")),
            seasons TEXT NOT NULL \(jsonArrayCheck("seasons")),
            brand TEXT,
            notes TEXT,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            FOREIGN KEY (subtype, category) REFERENCES subtypes (subtype, category)
        );
        CREATE INDEX items_status_category ON items (status, category);
        CREATE INDEX items_created_at ON items (created_at);
        CREATE INDEX items_color_category ON items (dominant_color_category);

        CREATE TABLE outfits (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            is_favorite INTEGER NOT NULL CHECK (is_favorite IN (0, 1)),
            source TEXT NOT NULL CHECK (source IN (\(list(sourceValues)))),
            target_scenario TEXT CHECK (target_scenario IS NULL OR target_scenario IN (\(list(scenarioValues)))),
            target_warmth_level TEXT CHECK (target_warmth_level IS NULL OR target_warmth_level IN (\(list(warmthLevelValues)))),
            canvas_layout BLOB,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        CREATE INDEX outfits_favorite_created ON outfits (is_favorite, created_at);

        CREATE TABLE outfit_items (
            outfit_id TEXT NOT NULL REFERENCES outfits (id) ON DELETE CASCADE,
            item_id TEXT NOT NULL REFERENCES items (id) ON DELETE CASCADE,
            position INTEGER NOT NULL,
            slot TEXT CHECK (slot IS NULL OR slot IN (\(list(slotValues)))),
            PRIMARY KEY (outfit_id, item_id)
        );
        CREATE INDEX outfit_items_item ON outfit_items (item_id);

        CREATE TABLE wear_records (
            id TEXT PRIMARY KEY,
            date REAL NOT NULL,
            is_active INTEGER NOT NULL DEFAULT 0 CHECK (is_active IN (0, 1)),
            outfit_id TEXT REFERENCES outfits (id) ON DELETE SET NULL,
            notes TEXT,
            created_at REAL NOT NULL
        );
        CREATE INDEX wear_records_date ON wear_records (date);
        CREATE UNIQUE INDEX wear_records_single_active ON wear_records (is_active) WHERE is_active = 1;

        CREATE TABLE wear_record_items (
            wear_record_id TEXT NOT NULL REFERENCES wear_records (id) ON DELETE CASCADE,
            item_id TEXT NOT NULL REFERENCES items (id) ON DELETE CASCADE,
            position INTEGER NOT NULL,
            slot TEXT CHECK (slot IS NULL OR slot IN (\(list(slotValues)))),
            PRIMARY KEY (wear_record_id, item_id)
        );
        CREATE INDEX wear_record_items_item ON wear_record_items (item_id);

        CREATE TABLE settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL CHECK (json_valid(value)),
            updated_at REAL NOT NULL
        );
        """),
    ]
}

/// 迁移执行器。
enum MigrationRunner {
    /// 当前数据库的 schema 版本，空库为 0。
    static func currentVersion(_ db: SQLiteDatabase) throws -> Int {
        try db.execute("CREATE TABLE IF NOT EXISTS schema_migrations (version INTEGER PRIMARY KEY, name TEXT NOT NULL, applied_at REAL NOT NULL);")
        return try db.query("SELECT COALESCE(MAX(version), 0) AS v FROM schema_migrations;").first?.int("v") ?? 0
    }

    /// 执行全部待执行迁移。
    ///
    /// - Parameter backupBeforeUpgrade: 已有数据且需要升级时，先把数据库完整复制到该目录。
    /// - Returns: 本次执行的迁移版本号。
    @discardableResult
    static func migrate(
        _ db: SQLiteDatabase,
        backupBeforeUpgrade backupDirectory: URL?,
        migrations: [Migration] = Migrations.all
    ) throws -> [Int] {
        let current = try currentVersion(db)
        let pending = migrations.filter { $0.version > current }
        if let latest = migrations.last?.version, current > latest {
            throw StorageError.schemaTooNew(found: current, supported: latest)
        }
        guard !pending.isEmpty else { return [] }
        if current > 0, let backupDirectory {
            try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
            let stamp = Int(Date().timeIntervalSince1970)
            let target = backupDirectory.appendingPathComponent("closet-v\(current)-\(stamp).sqlite")
            try db.run("VACUUM INTO ?;", [.text(target.path)])
        }
        for migration in pending {
            try db.transaction {
                try db.execute(migration.sql)
                try db.run("INSERT INTO schema_migrations (version, name, applied_at) VALUES (?, ?, ?);",
                           [.integer(Int64(migration.version)), .text(migration.name), .real(Date().timeIntervalSince1970)])
            }
        }
        return pending.map(\.version)
    }
}
