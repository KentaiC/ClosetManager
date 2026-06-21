# Closet Manager · 智能本地衣橱

一款**纯本地、完全离线**的 iOS 衣橱管理 App，用 SwiftUI + SwiftData 构建，所有智能能力均基于 Apple 原生框架（Vision、CoreImage、Swift Charts），不依赖任何联网服务。

## 主要功能
- **单品录入**：相册选图 → Vision 本地抠图去背 → CoreImage 主辅色提取与自动命名；支持批量录入向导。
- **穿搭引擎**：基于「保暖度求和匹配气温」的叠穿算法，含基础打底、同类排斥、场景纯净、雨雪天防水强关联等约束。
- **生命周期**：在衣橱 / 洗衣袋 / 行李箱 状态机；「目前正在穿」看板与一键脱下流转；洗衣滞留预警。
- **差旅打包**：按天数与温度生成打包清单，内裤携带量硬编码封顶。
- **数据看板**：Swift Charts 库存透视、色彩偏好、活跃度热力图、颜色树形图。
- **实用工具**：相似单品检测（Vision 特征指纹）、高级交叉筛选、外观自定义、本地冷备份导入导出。

## 技术栈
SwiftUI · SwiftData · Vision · CoreImage · Swift Charts · PhotosUI

## 运行
Xcode 26+ / iOS 17+。克隆后在 Xcode 打开，于 `Target → Signing & Capabilities` 选择你自己的 Team 即可在真机运行（仓库未包含开发者团队 ID）。Vision 抠图建议用真机测试（模拟器可能不支持）。
