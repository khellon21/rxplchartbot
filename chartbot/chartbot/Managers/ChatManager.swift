import Foundation
import SwiftUI

class ChatManager: ObservableObject {
    @Published private(set) var chats: [Chat] = []
    @Published var selectedChatId: UUID?
    
    private let userDefaults = UserDefaults.standard
    private let chatsKey = "saved_chats"
    
    var selectedChat: Chat? {
        guard let selectedChatId else { return nil }
        return chats.first { $0.id == selectedChatId }
    }
    
    init() {
        loadChats()
        ensureActiveChat()
    }
    
    private func ensureActiveChat() {
        if chats.isEmpty {
            createNewChat()
        } else if selectedChatId == nil {
            selectedChatId = chats.first?.id
        }
    }
    
    func loadChats() {
        guard let data = userDefaults.data(forKey: chatsKey),
              let decodedChats = try? JSONDecoder().decode([Chat].self, from: data) else {
            // Create initial chat if none exists
            createNewChat()
            return
        }
        
        chats = decodedChats.sorted(by: { $0.createdAt > $1.createdAt })
        selectedChatId = chats.first?.id
    }
    
    private func saveChats() {
        guard let encoded = try? JSONEncoder().encode(chats) else { return }
        userDefaults.set(encoded, forKey: chatsKey)
    }
    
    func createNewChat() {
        let newChat = Chat(title: "New Chat \(chats.count + 1)")
        chats.insert(newChat, at: 0)
        selectedChatId = newChat.id
        saveChats()
    }
    
    func deleteChat(_ chat: Chat) {
        chats.removeAll { $0.id == chat.id }
        
        // If we deleted the selected chat, select another one
        if selectedChatId == chat.id {
            selectedChatId = chats.first?.id
        }
        
        // If all chats were deleted, create a new one
        ensureActiveChat()
        saveChats()
    }
    
    func updateChatTitle(_ chatId: UUID, newTitle: String) {
        guard let index = chats.firstIndex(where: { $0.id == chatId }) else { return }
        let trimmedTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        chats[index].title = trimmedTitle.isEmpty ? "New Chat" : trimmedTitle
        saveChats()
    }
    
    func addMessage(_ message: Message, to chatId: UUID) {
        guard let index = chats.firstIndex(where: { $0.id == chatId }) else { return }
        chats[index].messages.append(message)
        saveChats()
    }
} 