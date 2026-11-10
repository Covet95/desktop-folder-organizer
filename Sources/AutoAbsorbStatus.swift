import Foundation

enum AutoAbsorbPhase: String, Equatable {
    case monitoring
    case processing
    case retrying
    case attention

    var title: String {
        switch self {
        case .monitoring: return "自动监控中"
        case .processing: return "正在收纳"
        case .retrying: return "等待重试"
        case .attention: return "需要处理"
        }
    }
}

struct AutoAbsorbStatus: Equatable {
    var phase: AutoAbsorbPhase = .monitoring
    var pendingCount: Int = 0
    var message: String = "正在监控桌面"
    var updatedAt: Date = Date()

    var detail: String {
        switch phase {
        case .monitoring:
            return message
        case .processing:
            return pendingCount > 0 ? "正在处理 \(pendingCount) 个项目" : message
        case .retrying:
            return pendingCount > 0 ? "\(pendingCount) 个项目将在稍后重试" : message
        case .attention:
            return message
        }
    }
}
