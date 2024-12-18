//
//  ContentView.swift
//  chartbot
//
//  Created by khellon patel on 12/13/24.
//

import SwiftUI
import AVFoundation

// MARK: - Message Model
struct Message: Identifiable, Equatable, Codable {
    let id: UUID
    let content: String
    let isUser: Bool
    
    static func == (lhs: Message, rhs: Message) -> Bool {
        lhs.id == rhs.id && lhs.content == rhs.content && lhs.isUser == rhs.isUser
    }
    
    struct CodeBlock: Codable {
        let language: String
        let code: String
        let explanation: String
    }
    
    var containsCode: Bool {
        !codeBlocks.isEmpty
    }
    
    var codeBlocks: [CodeBlock] {
        // First try to match multiple language format
        let multiPattern = "\\[([^\\]]+)\\]\\s*```([a-zA-Z]*)\\n([\\s\\S]*?)```"
        let multiRegex = try? NSRegularExpression(pattern: multiPattern, options: [])
        let nsRange = NSRange(content.startIndex..<content.endIndex, in: content)
        var blocks: [CodeBlock] = []
        
        if let matches = multiRegex?.matches(in: content, options: [], range: nsRange),
           !matches.isEmpty {
            // Handle multiple language format
            for match in matches {
                if match.numberOfRanges == 4,
                   let languageRange = Range(match.range(at: 1), in: content),
                   let _ = Range(match.range(at: 2), in: content),
                   let codeRange = Range(match.range(at: 3), in: content) {
                    let language = String(content[languageRange]).trimmingCharacters(in: .whitespaces)
                    let code = String(content[codeRange])
                    
                    // Get explanation before this code block
                    let fullLanguageMarker = "[" + language + "]"
                    if let markerRange = content.range(of: fullLanguageMarker) {
                        let explanationText = String(content[..<markerRange.lowerBound])
                        let explanation = explanationText
                            .components(separatedBy: "```")
                            .last?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        
                        blocks.append(CodeBlock(
                            language: language,
                            code: code.trimmingCharacters(in: .whitespacesAndNewlines),
                            explanation: explanation
                        ))
                    }
                }
            }
        } else {
            // Handle single language format
            let singlePattern = "```([a-zA-Z]*)\\n([\\s\\S]*?)```"
            let singleRegex = try? NSRegularExpression(pattern: singlePattern, options: [])
            
            if let matches = singleRegex?.matches(in: content, options: [], range: nsRange) {
                for match in matches {
                    if match.numberOfRanges == 3,
                       let languageRange = Range(match.range(at: 1), in: content),
                       let codeRange = Range(match.range(at: 2), in: content) {
                        let language = String(content[languageRange]).trimmingCharacters(in: .whitespaces)
                        let code = String(content[codeRange])
                        
                        // Get explanation before code block
                        if let beforeCode = content.components(separatedBy: "```").first {
                            blocks.append(CodeBlock(
                                language: language.isEmpty ? "code" : language,
                                code: code.trimmingCharacters(in: .whitespacesAndNewlines),
                                explanation: beforeCode.trimmingCharacters(in: .whitespacesAndNewlines)
                            ))
                        }
                    }
                }
            }
        }
        return blocks
    }
    
    var textContent: String {
        let parts = content.components(separatedBy: "[")
        return parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, content, isUser
    }
}

// Add this enum after the Message struct
enum QueryType {
    case code
    case informative
    
    static func categorize(_ query: String) -> QueryType {
        // Keywords that suggest code-related queries
        let codeKeywords = [
            "code", "program", "function", "implement", "algorithm",
            "javascript", "python", "swift", "java", "html", "css",
            "api", "database", "loop", "array", "class", "struct",
            "variable", "const", "let", "var", "func", "method"
        ]
        
        let lowercaseQuery = query.lowercased()
        
        // Check for explicit code indicators
        if codeKeywords.contains(where: { lowercaseQuery.contains($0) }) {
            return .code
        }
        
        // Check for code syntax patterns
        let codeSyntaxPatterns = [
            "how (do|can|to) (i|we|you) (make|create|build|implement)",
            "show me (how|an example)",
            "write (a|the|some)",
            "syntax for",
            "example of"
        ]
        
        if codeSyntaxPatterns.contains(where: { 
            lowercaseQuery.range(of: $0, options: .regularExpression) != nil 
        }) {
            return .code
        }
        
        // Default to informative for general questions
        return .informative
    }
}

// MARK: - Mistral Service
class MistralService {
    private let apiKey = "7dzLKfcHrpYSlvzYt0pHQFmlZokZMrR8"
    private let model = "mistral-large-latest"
    private let endpoint = "https://api.mistral.ai/v1/chat/completions"
    
    func sendMessage(_ message: String) async throws -> String {
        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }
        
        let queryType = QueryType.categorize(message)
        let systemPrompt = getSystemPrompt(for: queryType)
        
        let messageData: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": message]
            ]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: messageData)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        if let choices = json?["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let message = firstChoice["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }
        
        throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse response"])
    }
    
    private func getSystemPrompt(for queryType: QueryType) -> String {
        switch queryType {
        case .code:
            return """
            You are a helpful and friendly AI assistant specialized in providing clear, well-structured code examples.
            
            When providing code examples:
            1. Always wrap code blocks with triple backticks and specify the language
            2. Include brief comments explaining key parts
            3. Ensure consistent indentation
            4. Add a brief explanation before each code block
            5. For multiple programming languages:
               - Use [Language Name] before each code block
               - Maintain consistent formatting across examples
            
            Example format:
            Here's how to do X...
            
            [Swift]
            ```swift
            // Code example
            ```
            
            [Python]
            ```python
            # Code example
            ```
            """
            
        case .informative:
            return """
            You are a helpful and friendly AI assistant providing clear, informative responses.
            
            When answering questions:
            1. Provide concise, accurate information
            2. Use clear explanations without technical jargon unless necessary
            3. Structure responses with proper paragraphs and bullet points when appropriate
            4. Include relevant examples or analogies when helpful
            5. Avoid using code blocks unless specifically asked
            
            Focus on delivering information in a conversational, easy-to-understand manner.
            """
        }
    }
}

// MARK: - Code Block View
struct CodeBlockView: View {
    let code: String
    let language: String
    @State private var isCopied = false
    @State private var isExpanded = false
    
    private var cleanCode: String {
        code.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(language)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                Spacer()
                HStack(spacing: 12) {
                    Button(action: {
                        isExpanded.toggle()
                    }) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .foregroundColor(.gray)
                    }
                    Button(action: {
                        UIPasteboard.general.string = cleanCode
                        isCopied = true
                        
                        // Haptic feedback
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            isCopied = false
                        }
                    }) {
                        HStack {
                            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            Text(isCopied ? "Copied!" : "Copy")
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.neonBlue.opacity(0.1))
                        .foregroundColor(Theme.neonBlue)
                        .cornerRadius(8)
                    }
                }
            }
            
            if isExpanded {
                ScrollView {
                    Text(cleanCode)
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 400)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(cleanCode.components(separatedBy: .newlines).prefix(3).joined(separator: "\n"))
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
                .frame(height: 100)
                
                if cleanCode.components(separatedBy: .newlines).count > 3 {
                    Button(action: { isExpanded.toggle() }) {
                        Text("Show more...")
                            .font(.caption)
                            .foregroundColor(Theme.neonBlue)
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
        .padding(8)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 1)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Theme
struct Theme {
    enum Style: String, CaseIterable {
        case classic = "Classic"
        case animeParadise = "Anime Warrior"
        case neubrutalism = "Neubrutalism"
    }
    
    @AppStorage("selectedTheme") static var currentStyle: Style = .classic
    
    static var primary: Color {
        switch currentStyle {
        case .classic: return Color("AccentColor")
        case .animeParadise: return Color(hex: "003366")
        case .neubrutalism: return Color(hex: "FF3366") // Vibrant pink for primary elements
        }
    }
    
    static var background: LinearGradient {
        switch currentStyle {
        case .classic:
            return LinearGradient(
                gradient: Gradient(colors: [
                    Color(hex: "0A0A0A"),
                    Color(hex: "1A1A1A"),
                    Color(hex: "2A2A2A")
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .animeParadise:
            return LinearGradient(
                gradient: Gradient(colors: [
                    Color(hex: "1A1A2E"),  // Dark navy
                    Color(hex: "16213E"),  // Deep blue
                    Color(hex: "0F3460")   // Rich blue
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .neubrutalism:
            return LinearGradient(
                gradient: Gradient(colors: [
                    Color(hex: "FFFFFF"),  // Clean white
                    Color(hex: "F0F0F0"),  // Light gray
                    Color(hex: "FFECB3").opacity(0.3)  // Subtle warm accent
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    static var neonBlue: Color {
        switch currentStyle {
        case .classic: return Color(hex: "00f2fe")
        case .animeParadise: return Color(hex: "FFD700")
        case .neubrutalism: return Color(hex: "2196F3") // Bright blue for accents
        }
    }
    
    static var neonPurple: Color {
        switch currentStyle {
        case .classic: return Color(hex: "4facfe")
        case .animeParadise: return Color(hex: "4B0082")
        case .neubrutalism: return Color(hex: "9C27B0") // Rich purple for variety
        }
    }
    
    static var textPrimary: Color {
        switch currentStyle {
        case .classic, .animeParadise: return .white
        case .neubrutalism: return .black // High contrast text
        }
    }
    
    static var textSecondary: Color {
        switch currentStyle {
        case .classic: return .white.opacity(0.7)
        case .animeParadise: return .white.opacity(0.8)
        case .neubrutalism: return Color(hex: "333333") // Dark gray for secondary text
        }
    }
    
    static var cardBackground: Color {
        switch currentStyle {
        case .classic: return Color(hex: "1A1A1A").opacity(0.7)
        case .animeParadise: return Color(hex: "1E3A5F").opacity(0.9)
        case .neubrutalism: return Color(hex: "4CAF50") // Vibrant green for cards
        }
    }
    
    static var shadowColor: Color {
        switch currentStyle {
        case .classic, .animeParadise: return .black.opacity(0.2)
        case .neubrutalism: return .black
        }
    }
    
    static var shadowOffset: CGFloat {
        switch currentStyle {
        case .classic, .animeParadise: return 1
        case .neubrutalism: return 4 // Strong shadow offset
        }
    }
    
    static var buttonStyle: AnyButtonStyle {
        switch currentStyle {
        case .classic:
            return AnyButtonStyle(ClassicButtonStyle())
        case .animeParadise:
            return AnyButtonStyle(AnimeWarriorButtonStyle())
        case .neubrutalism:
            return AnyButtonStyle(ColorfulNeubrutalistButtonStyle())
        }
    }
    
    static var inputFieldBackground: Color {
        switch currentStyle {
        case .classic:
            return Color.white.opacity(0.1)
        case .animeParadise:
            return Color(hex: "FF69B4").opacity(0.1)
        case .neubrutalism:
            return .white
        }
    }
    
    static var cornerRadius: CGFloat {
        switch currentStyle {
        case .classic:
            return 16
        case .animeParadise:
            return 25
        case .neubrutalism:
            return 0 // Sharp corners
        }
    }
    
    static var symbolEffect: Animation {
        switch currentStyle {
        case .classic:
            return .spring(duration: 0.3)
        case .animeParadise:
            return .spring(duration: 0.5, bounce: 0.4)
        case .neubrutalism:
            return .spring(duration: 0.2)
        }
    }
}

// MARK: - Extensions
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Animated Background
struct AnimatedBackgroundView: View {
    @State private var animation = false
    
    var body: some View {
        ZStack {
            Theme.background
            
            ForEach(0..<3) { index in
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Theme.neonBlue, Theme.neonPurple]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 200, height: 200)
                    .blur(radius: 50)
                    .offset(
                        x: animation ? CGFloat.random(in: -200...200) : CGFloat.random(in: -200...200),
                        y: animation ? CGFloat.random(in: -200...200) : CGFloat.random(in: -200...200)
                    )
                    .opacity(0.3)
            }
        }
        .onAppear {
            withAnimation(
                Animation
                    .easeInOut(duration: 10)
                    .repeatForever(autoreverses: true)
            ) {
                animation.toggle()
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Message Input View
struct MessageInputView: View {
    @Binding var messageText: String
    let onSend: () -> Void
    @FocusState private var isFocused: Bool
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            messageInputField
            sendButton
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(
            Theme.currentStyle == .neubrutalism ? 
            Color.white : 
            Color(uiColor: .systemBackground).opacity(0.8)
        )
        .overlay(
            Theme.currentStyle == .neubrutalism ?
            Rectangle()
                .stroke(.black, lineWidth: 3)
                .offset(x: 4, y: 4) :
            nil
        )
    }
    
    private var messageInputField: some View {
        HStack {
            TextField("Type a message...", text: $messageText)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Theme.textPrimary)
                .focused($isFocused)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    Group {
                        if Theme.currentStyle == .neubrutalism {
                            Color(hex: "F5F5F5")
                                .overlay(
                                    Rectangle()
                                        .stroke(.black, lineWidth: 3)
                                )
                                .shadow(color: .black, radius: 0, x: 4, y: 4)
                        } else {
                            Theme.inputFieldBackground
                                .cornerRadius(Theme.cornerRadius)
                        }
                    }
                )
                .scaleEffect(isHovered ? 1.01 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
                .onHover { hovering in
                    isHovered = hovering
                }
        }
    }
    
    private var sendButton: some View {
        Button(action: {
            HapticManager.shared.feedback(.light)
            onSend()
        }) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 32))
                .foregroundColor(Theme.currentStyle == .neubrutalism ? .black : Theme.neonBlue)
                .background(
                    Theme.currentStyle == .neubrutalism ?
                    Color(hex: "FFE082") : // Warm yellow
                    Color.clear
                )
                .cornerRadius(Theme.currentStyle == .neubrutalism ? 0 : 16)
        }
        .buttonStyle(Theme.buttonStyle)
    }
}

// MARK: - Typing Indicator
struct TypingIndicator: View {
    @State private var animationOffset = 0.0
    @State private var showIndicator = false
    
    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Theme.neonBlue)
                        .frame(width: 8, height: 8)
                        .offset(y: animationOffset)
                        .animation(
                            Animation
                                .easeInOut(duration: 0.5)
                                .repeatForever()
                                .delay(0.2 * Double(index)),
                            value: animationOffset
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [Color.white.opacity(0.1), Color.white.opacity(0.05)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            Spacer()
        }
        .padding(.horizontal)
        .opacity(showIndicator ? 1 : 0)
        .offset(x: showIndicator ? 0 : -50)
        .onAppear {
            animationOffset = -5
            withAnimation(.easeOut(duration: 0.3)) {
                showIndicator = true
            }
        }
    }
}

// MARK: - Chat Bubble
struct ChatBubble: View {
    let message: Message
    @State private var isAnimated = false
    @State private var showContent = false
    
    var body: some View {
        HStack {
            if message.isUser { Spacer() }
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
                if !message.textContent.isEmpty {
                    Text(message.textContent)
                        .padding()
                        .background(
                            Group {
                                switch Theme.currentStyle {
                                case .neubrutalism:
                                    Color.white
                                        .shadow(color: Theme.shadowColor, radius: 0, x: Theme.shadowOffset, y: Theme.shadowOffset)
                                default:
                                    message.isUser ?
                                    LinearGradient(
                                        gradient: Gradient(colors: [Theme.neonBlue, Theme.neonPurple]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ) :
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.white.opacity(0.1), Color.white.opacity(0.05)]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                }
                            }
                        )
                        .foregroundColor(Theme.currentStyle == .neubrutalism ? .black : Theme.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.currentStyle == .neubrutalism ? 0 : 16))
                        .overlay(
                            Theme.currentStyle == .neubrutalism ?
                            RoundedRectangle(cornerRadius: 0)
                                .stroke(Color.black, lineWidth: 2) :
                            nil
                        )
                }
                
                // Code blocks
                if message.containsCode && showContent {
                    ForEach(message.codeBlocks, id: \.language) { block in
                        VStack(alignment: .leading, spacing: 8) {
                            if !block.explanation.isEmpty {
                                Text(block.explanation)
                                    .padding()
                                    .background(
                                        LinearGradient(
                                            gradient: Gradient(colors: [Color.white.opacity(0.1), Color.white.opacity(0.05)]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .foregroundColor(Theme.textPrimary)
                            }
                            
                            CodeBlockView(code: block.code, language: block.language)
                                .transition(.asymmetric(
                                    insertion: .scale.combined(with: .offset(x: message.isUser ? 50 : -50)),
                                    removal: .scale.combined(with: .opacity)
                                ))
                        }
                    }
                }
            }
            .opacity(isAnimated ? 1 : 0)
            if !message.isUser { Spacer() }
        }
        .padding(.horizontal)
        .onAppear {
            withAnimation(.spring(duration: 0.5)) {
                isAnimated = true
            }
            
            if !message.isUser {
                withAnimation(.spring(duration: 0.6).delay(0.3)) {
                    showContent = true
                }
            } else {
                withAnimation(.spring(duration: 0.5)) {
                    showContent = true
                }
            }
        }
    }
}

// MARK: - Splash Screen
struct SplashScreen: View {
    var body: some View {
        ZStack {
            Theme.background
            
            VStack(spacing: 20) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 100))
                    .foregroundColor(Theme.neonBlue)
                    .symbolEffect(.bounce)
                
                Text("Rxple Bot")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.textPrimary)
                
                Text("Your AI Assistant")
                    .font(.title2)
                    .foregroundColor(Theme.textSecondary)
            }
            .padding()
        }
    }
}

// MARK: - Content View
struct ContentView: View {
    @StateObject private var chatManager = ChatManager()
    @State private var messageText = ""
    @State private var isLoading = false
    @State private var showingOnboarding = !UserDefaults.standard.bool(forKey: "hasSeenOnboarding")
    @State private var showingSplash = true
    @State private var showingSettings = false
    @AppStorage("enableTextToSpeech") private var enableTextToSpeech = false
    private let mistralService = MistralService()
    private let speechSynthesizer = AVSpeechSynthesizer()
    
    var body: some View {
        ZStack {
            if showingSplash {
                SplashScreen()
            } else {
                mainView
            }
        }
        .preferredColorScheme(.dark)
        .environmentObject(chatManager)
        .sheet(isPresented: $showingOnboarding) {
            OnboardingView(isPresented: $showingOnboarding)
                .onDisappear {
                    UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
                }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(chatManager)
        }
        .onAppear {
            // Hide splash screen after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    showingSplash = false
                }
            }
        }
    }
    
    private var mainView: some View {
        ZStack {
            AnimatedBackgroundView()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gear")
                            .font(.system(size: 20))
                            .foregroundColor(Theme.textPrimary)
                    }
                    
                    Spacer()
                    
                    Text("Rxple Bot")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.textPrimary)
                }
                .padding()
                .background(.ultraThinMaterial)
                
                // Chat Area
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(chatManager.selectedChat?.messages ?? []) { message in
                            ChatBubble(message: message)
                        }
                        if isLoading {
                            TypingIndicator()
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .offset(x: -50)),
                                    removal: .opacity.combined(with: .offset(x: -20))
                                ))
                        }
                    }
                    .padding(.vertical)
                }
                .animation(.spring(duration: 0.5), value: chatManager.selectedChat?.messages)
                
                // Input Area
                MessageInputView(
                    messageText: $messageText,
                    onSend: {
                        Task {
                            await sendMessage()
                        }
                    }
                )
            }
        }
    }
    
    private func sendMessage() async {
        let trimmedMessage = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty, let chatId = chatManager.selectedChatId else { return }
        
        HapticManager.shared.feedback(.medium)
        
        let userMessage = Message(id: UUID(), content: trimmedMessage, isUser: true)
        chatManager.addMessage(userMessage, to: chatId)
        messageText = ""
        isLoading = true
        
        do {
            let response = try await mistralService.sendMessage(trimmedMessage)
            let aiMessage = Message(id: UUID(), content: response, isUser: false)
            chatManager.addMessage(aiMessage, to: chatId)
            
            HapticManager.shared.notification(.success)
            
            if enableTextToSpeech {
                let utterance = AVSpeechUtterance(string: response)
                utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
                utterance.rate = 0.5
                speechSynthesizer.speak(utterance)
            }
            
        } catch {
            let errorMessage = Message(id: UUID(), content: "Sorry, I encountered an error: \(error.localizedDescription)", isUser: false)
            chatManager.addMessage(errorMessage, to: chatId)
            HapticManager.shared.notification(.error)
        }
        
        isLoading = false
    }
}

// MARK: - Onboarding View
struct OnboardingView: View {
    @Binding var isPresented: Bool
    
    var body: some View {
        ZStack {
            Theme.background
                .ignoresSafeArea()
            
            TabView {
                ForEach(0..<3) { index in
                    VStack(spacing: 20) {
                        Image(systemName: ["wand.and.stars", "brain.head.profile", "sparkles"][index])
                            .font(.system(size: 80))
                            .foregroundColor(Theme.neonBlue)
                            .symbolEffect(.bounce)
                        
                        Text(["Welcome to Rxple Bot", "AI-Powered Assistant", "Let's Get Started"][index])
                            .font(.title)
                            .bold()
                            .foregroundColor(Theme.textPrimary)
                        
                        Text(["Your personal AI assistant", "Powered by advanced AI", "Ask me anything!"][index])
                            .multilineTextAlignment(.center)
                            .foregroundColor(Theme.textSecondary)
                    }
                    .padding()
                    .background(
                        Theme.cardBackground
                            .cornerRadius(20)
                            .padding()
                    )
                }
            }
            .tabViewStyle(PageTabViewStyle())
            
            VStack {
                Spacer()
                Button("Get Started") {
                    isPresented = false
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Theme.neonBlue, Theme.neonPurple]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
                .padding(.bottom, 40)
                .shadow(color: Theme.neonBlue.opacity(0.5), radius: 10)
            }
        }
    }
}

// Add this after other struct declarations
struct SettingsView: View {
    @EnvironmentObject private var chatManager: ChatManager
    @AppStorage("enableTextToSpeech") private var enableTextToSpeech = false
    @AppStorage("enableHaptics") private var enableHaptics = false
    @AppStorage("selectedTheme") private var selectedTheme = Theme.Style.classic
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var editingChat: Chat?
    @State private var showingTitleAlert = false
    @State private var showingDeleteAlert = false
    @State private var chatToDelete: Chat?
    @State private var showingThemePicker = false
    @State private var newTitle = ""
    private let privacyPolicyURL = URL(string: "https://khellon.netlify.app")!
    private let termsOfUseURL = URL(string: "https://khellon1.netlify.app")!
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Chats")) {
                    ForEach(chatManager.chats) { chat in
                        HStack {
                            Text(chat.title)
                                .foregroundColor(chat.id == chatManager.selectedChatId ? .accentColor : .primary)
                            
                            Spacer()
                            
                            if chat.id == chatManager.selectedChatId {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            chatManager.selectedChatId = chat.id
                            dismiss()
                        }
                        .contextMenu {
                            Button {
                                editingChat = chat
                                newTitle = chat.title
                                showingTitleAlert = true
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            
                            Button(role: .destructive) {
                                chatToDelete = chat
                                showingDeleteAlert = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    
                    Button {
                        chatManager.createNewChat()
                        dismiss()
                    } label: {
                        Label("New Chat", systemImage: "plus.circle.fill")
                    }
                }
                
                Section(header: Text("Appearance")) {
                    Button {
                        showingThemePicker = true
                    } label: {
                        HStack {
                            Label("Theme", systemImage: "paintpalette")
                            Spacer()
                            Text(selectedTheme.rawValue)
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section(header: Text("Settings")) {
                    Toggle("Enable Text-to-Speech", isOn: $enableTextToSpeech)
                    Toggle("Enable Haptic Feedback", isOn: $enableHaptics)
                }
                
                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    Link(destination: privacyPolicyURL) {
                        HStack {
                            Label("Privacy Policy", systemImage: "lock.shield")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)
                    
                    Link(destination: termsOfUseURL) {
                        HStack {
                            Label("Terms of Use", systemImage: "doc.text")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingThemePicker) {
                ThemePickerView(selectedTheme: $selectedTheme)
            }
            .alert("Rename Chat", isPresented: $showingTitleAlert) {
                TextField("Chat Title", text: $newTitle)
                Button("Cancel", role: .cancel) { }
                Button("Save") {
                    if let chat = editingChat {
                        chatManager.updateChatTitle(chat.id, newTitle: newTitle)
                    }
                }
            }
            .alert("Delete Chat", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if let chat = chatToDelete {
                        chatManager.deleteChat(chat)
                    }
                }
            } message: {
                Text("Are you sure you want to delete this chat? This action cannot be undone.")
            }
        }
    }
}

// Add ThemePickerView
struct ThemePickerView: View {
    @Binding var selectedTheme: Theme.Style
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List(Theme.Style.allCases, id: \.self) { theme in
                Button {
                    selectedTheme = theme
                    dismiss()
                } label: {
                    HStack {
                        ThemePreviewIcon(theme: theme)
                            .frame(width: 40, height: 40)
                            .cornerRadius(8)
                        
                        Text(theme.rawValue)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        if theme == selectedTheme {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
            }
            .navigationTitle("Select Theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// Add ThemePreviewIcon
struct ThemePreviewIcon: View {
    let theme: Theme.Style
    
    var body: some View {
        ZStack {
            switch theme {
            case .classic:
                LinearGradient(
                    colors: [Color(hex: "0A0A0A"), Color(hex: "2A2A2A")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .animeParadise:
                LinearGradient(
                    colors: [Color(hex: "FF69B4"), Color(hex: "9C27B0")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .neubrutalism:
                Color.white
                    .overlay(
                        Rectangle()
                            .stroke(.black, lineWidth: 2)
                            .offset(x: 2, y: 2)
                    )
            }
        }
    }
}

// Add after other struct declarations
class HapticManager {
    static let shared = HapticManager()
    @AppStorage("enableHaptics") private var enableHaptics = false
    
    private init() {}
    
    func feedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard enableHaptics else { return }
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
    
    func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard enableHaptics else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }
}

// Add custom button styles
struct ClassicButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

struct AnimeWarriorButtonStyle: ButtonStyle {
    @State private var isHovered = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(hex: "003366"),  // Deep blue
                        Color(hex: "004080")   // Rich blue
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(hex: "FFD700"), lineWidth: 2) // Gold border
            )
            .shadow(color: Color(hex: "FFD700").opacity(0.3), radius: 8, x: 0, y: 4)
            .scaleEffect(configuration.isPressed ? 0.98 : isHovered ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.2), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

struct ColorfulNeubrutalistButtonStyle: ButtonStyle {
    @State private var isHovered = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(hex: "FFE082")) // Warm yellow background
            .foregroundColor(.black)
            .overlay(
                Rectangle()
                    .stroke(.black, lineWidth: 3)
            )
            .shadow(color: .black, radius: 0, x: 4, y: 4)
            .offset(x: configuration.isPressed ? 4 : 0, y: configuration.isPressed ? 4 : 0)
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.2), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

// Add AnyButtonStyle struct
struct AnyButtonStyle: ButtonStyle {
    private let makeBody: (ButtonStyle.Configuration) -> AnyView
    
    init<S: ButtonStyle>(_ style: S) {
        makeBody = { configuration in
            AnyView(style.makeBody(configuration: configuration))
        }
    }
    
    func makeBody(configuration: Configuration) -> some View {
        makeBody(configuration)
    }
}

#Preview {
    ContentView()
}
