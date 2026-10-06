import Foundation

/// 单品状态流转规则。
///
/// 规则与 App 的 `WearService` 相同，本地 Web 服务端直接使用这里的函数。
/// App 的 `WearService` 目前仍保留自己的实现，改为调用这里需要在 Apple 工具链上验证（见迁移文档）。
public enum ItemLifecycle {
    /// 与流转相关的两个字段。
    public struct State: Equatable, Sendable {
        public var status: ItemStatus
        public var laundryEntryDate: Date?

        public init(status: ItemStatus, laundryEntryDate: Date?) {
            self.status = status
            self.laundryEntryDate = laundryEntryDate
        }
    }

    /// 脱下：勾选的单品进洗衣袋并记录入袋时间，其余回到衣橱并清空入袋时间（`WearService.takeOff`）。
    public static func takeOff(sentToLaundry: Bool, now: Date) -> State {
        sentToLaundry ? State(status: .inLaundry, laundryEntryDate: now) : State(status: .inWardrobe, laundryEntryDate: nil)
    }

    /// 洗净放回（`WearService.returnToWardrobe`）。
    public static func returnFromLaundry() -> State {
        State(status: .inWardrobe, laundryEntryDate: nil)
    }

    /// 装入行李箱：只改变状态，入袋时间保持原样（`WearService.packIntoLuggage`）。
    public static func pack(_ current: State) -> State {
        State(status: .inLuggage, laundryEntryDate: current.laundryEntryDate)
    }

    /// 结束差旅取出：只改变状态，入袋时间保持原样（`WearService.unpackAllLuggage`）。
    public static func unpack(_ current: State) -> State {
        State(status: .inWardrobe, laundryEntryDate: current.laundryEntryDate)
    }
}
