import Foundation

struct Chat: Identifiable, Codable {
    let id: UUID
    var title: String
    var messages: [Message]
    let createdAt: Date
    
    init(id: UUID = UUID(), title: String = "New Chat", messages: [Message] = [], createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
    }
} 