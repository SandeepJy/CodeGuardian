# danger-core

Core Bash Danger Repo

struct TruncatableText: View {
let text: String
let maxLines: Int
let alignment: TextAlignment
let font: Font?
let color: Color?

    @State private var isTruncated = false
    @State private var showingSheet = false

    init(
        _ text: String,
        maxLines: Int = 2,
        alignment: TextAlignment = .leading,
        font: Font? = nil,
        color: Color? = nil
    ) {
        self.text = text
        self.maxLines = maxLines
        self.alignment = alignment
        self.font = font
        self.color = color
    }

    var body: some View {
        VStack(alignment: alignment.horizontalAlignment, spacing: 4) {
            Text(text)
                .font(font)
                .foregroundColor(color)
                .lineLimit(maxLines)
                .truncationMode(.tail)
                .multilineTextAlignment(alignment)
                .background(
                    ViewThatFits(in: .vertical) {
                        Text(text)
                            .font(font)
                            .hidden()
                            .onAppear {
                                isTruncated = false
                            }

                        Color.clear
                            .onAppear {
                                isTruncated = true
                            }
                    }
                )

            if isTruncated {
                Button("More") {
                    showingSheet = true
                }
                .font(.footnote)
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showingSheet) {
            NavigationView {
                ScrollView {
                    Text(text)
                        .font(font)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .navigationTitle("Full Text")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            showingSheet = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

}





---------------------



import SwiftUI

// MARK: - Text Content Type
enum TextContentType {
    case plain(String)
    case attributed(AttributedString)
}

// MARK: - Text Protocol
protocol TextProtocol: View {
    var content: TextContentType { get set }
    var textStyle: Font? { get set }
    var lineLimit: Int? { get set }
    var characterLimit: Int? { get set }
    var showEllipsis: Bool { get set }
    var onTruncation: (() -> Void)? { get set }
}

// MARK: - Default Implementation
extension TextProtocol {
    var body: some View {
        TextProtocolDefaultView(
            content: content,
            textStyle: textStyle,
            lineLimit: lineLimit,
            characterLimit: characterLimit,
            showEllipsis: showEllipsis,
            onTruncation: onTruncation
        )
    }
}

// MARK: - Default View Implementation
struct TextProtocolDefaultView: View {
    let content: TextContentType
    let textStyle: Font?
    let lineLimit: Int?
    let characterLimit: Int?
    let showEllipsis: Bool
    let onTruncation: (() -> Void)?
    
    @State private var isTruncated = false
    @State private var fullTextHeight: CGFloat = 0
    @State private var truncatedTextHeight: CGFloat = 0
    
    var body: some View {
        let processedContent = processContent()
        
        ZStack {
            // Hidden full text to measure height
            createTextView(for: processedContent, isHidden: true)
                .background(
                    GeometryReader { geometry in
                        Color.clear.onAppear {
                            fullTextHeight = geometry.size.height
                            checkTruncation()
                        }
                    }
                )
                .hidden()
            
            // Visible text
            createTextView(for: processedContent, isHidden: false)
                .background(
                    GeometryReader { geometry in
                        Color.clear
                            .onAppear {
                                truncatedTextHeight = geometry.size.height
                                checkTruncation()
                            }
                            .onChange(of: geometry.size.height) { newHeight in
                                truncatedTextHeight = newHeight
                                checkTruncation()
                            }
                    }
                )
        }
    }
    
    private func processContent() -> TextContentType {
        guard let characterLimit = characterLimit else {
            return content
        }
        
        switch content {
        case .plain(let string):
            if string.count > characterLimit {
                let truncated = String(string.prefix(characterLimit))
                let processed = showEllipsis ? truncated + "..." : truncated
                return .plain(processed)
            }
            return .plain(string)
            
        case .attributed(let attributedString):
            let string = String(attributedString.characters)
            if string.count > characterLimit {
                let truncated = String(string.prefix(characterLimit))
                let processed = showEllipsis ? truncated + "..." : truncated
                return .attributed(AttributedString(processed))
            }
            return .attributed(attributedString)
        }
    }
    
    private func createTextView(for content: TextContentType, isHidden: Bool) -> some View {
        Group {
            switch content {
            case .plain(let string):
                Text(string)
                    .font(textStyle)
                    .lineLimit(isHidden ? nil : lineLimit)
                
            case .attributed(let attributedString):
                Text(attributedString)
                    .font(textStyle)
                    .lineLimit(isHidden ? nil : lineLimit)
            }
        }
    }
    
    private func checkTruncation() {
        let wasTruncated = isTruncated
        isTruncated = fullTextHeight > truncatedTextHeight && fullTextHeight > 0
        
        if isTruncated && !wasTruncated {
            onTruncation?()
        }
    }
}

// MARK: - Reusable Text View
struct ReusableTextView: TextProtocol {
    var content: TextContentType
    var textStyle: Font?
    var lineLimit: Int?
    var characterLimit: Int?
    var showEllipsis: Bool
    var onTruncation: (() -> Void)?
    
    // Plain text initializer
    init(
        _ text: String,
        textStyle: Font? = nil,
        lineLimit: Int? = nil,
        characterLimit: Int? = nil,
        showEllipsis: Bool = true,
        onTruncation: (() -> Void)? = nil
    ) {
        self.content = .plain(text)
        self.textStyle = textStyle
        self.lineLimit = lineLimit
        self.characterLimit = characterLimit
        self.showEllipsis = showEllipsis
        self.onTruncation = onTruncation
    }
    
    // Attributed text initializer
    init(
        _ attributedText: AttributedString,
        textStyle: Font? = nil,
        lineLimit: Int? = nil,
        characterLimit: Int? = nil,
        showEllipsis: Bool = true,
        onTruncation: (() -> Void)? = nil
    ) {
        self.content = .attributed(attributedText)
        self.textStyle = textStyle
        self.lineLimit = lineLimit
        self.characterLimit = characterLimit
        self.showEllipsis = showEllipsis
        self.onTruncation = onTruncation
    }
    
    // Uses the default implementation from protocol extension
    // No need to implement body unless you want custom behavior
}


// MARK: - View Modifier Extensions
extension ReusableTextView {
    func textStyle(_ style: Font) -> ReusableTextView {
        var copy = self
        copy.textStyle = style
        return copy
    }
    
    func lineLimit(_ limit: Int?) -> ReusableTextView {
        var copy = self
        copy.lineLimit = limit
        return copy
    }
    
    func characterLimit(_ limit: Int?, showEllipsis: Bool = true) -> ReusableTextView {
        var copy = self
        copy.characterLimit = limit
        copy.showEllipsis = showEllipsis
        return copy
    }
    
    func onTruncation(_ action: @escaping () -> Void) -> ReusableTextView {
        var copy = self
        copy.onTruncation = action
        return copy
    }
    
    func showEllipsis(_ show: Bool) -> ReusableTextView {
        var copy = self
        copy.showEllipsis = show
        return copy
    }
}

// MARK: - Custom Text View with Override
struct CustomStyledTextView: TextProtocol {
    var content: TextContentType
    var textStyle: Font?
    var lineLimit: Int?
    var characterLimit: Int?
    var showEllipsis: Bool
    var onTruncation: (() -> Void)?
    
    init(
        _ text: String,
        textStyle: Font? = nil,
        lineLimit: Int? = nil,
        characterLimit: Int? = nil,
        showEllipsis: Bool = true,
        onTruncation: (() -> Void)? = nil
    ) {
        self.content = .plain(text)
        self.textStyle = textStyle
        self.lineLimit = lineLimit
        self.characterLimit = characterLimit
        self.showEllipsis = showEllipsis
        self.onTruncation = onTruncation
    }
    
    // Custom body implementation overriding the default
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Use the default implementation
            TextProtocolDefaultView(
                content: content,
                textStyle: textStyle,
                lineLimit: lineLimit,
                characterLimit: characterLimit,
                showEllipsis: showEllipsis,
                onTruncation: onTruncation
            )
            
            // Add custom elements
            HStack {
                Image(systemName: "doc.text")
                    .foregroundColor(.blue)
                Text("Custom footer")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Another Custom Implementation with Different Styling
struct HighlightedTextView: TextProtocol {
    var content: TextContentType
    var textStyle: Font?
    var lineLimit: Int?
    var characterLimit: Int?
    var showEllipsis: Bool
    var onTruncation: (() -> Void)?
    
    var highlightColor: Color
    
    init(
        _ text: String,
        highlightColor: Color = .yellow.opacity(0.3),
        textStyle: Font? = nil,
        lineLimit: Int? = nil,
        characterLimit: Int? = nil,
        showEllipsis: Bool = true,
        onTruncation: (() -> Void)? = nil
    ) {
        self.content = .plain(text)
        self.highlightColor = highlightColor
        self.textStyle = textStyle
        self.lineLimit = lineLimit
        self.characterLimit = characterLimit
        self.showEllipsis = showEllipsis
        self.onTruncation = onTruncation
    }
    
    var body: some View {
        TextProtocolDefaultView(
            content: content,
            textStyle: textStyle,
            lineLimit: lineLimit,
            characterLimit: characterLimit,
            showEllipsis: showEllipsis,
            onTruncation: onTruncation
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(highlightColor)
        .cornerRadius(4)
    }
}

// MARK: - Demo View
struct ContentView: View {
    @State private var showBottomSheet = false
    @State private var fullText = ""
    @State private var isTruncated: Bool = false
    
    let longText = "This is a very long text that will definitely be truncated when we apply line limits or character limits to demonstrate the truncation detection functionality. It continues with more content to ensure truncation happens when we set limits."
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("TextProtocol Examples")
                    .font(.largeTitle.bold())
                    .padding(.bottom)
                
                // Basic usage
                GroupBox("1. Simple Text") {
                    ReusableTextView("Simple text with protocol implementation")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // With modifiers
                GroupBox("2. Styled with Modifiers") {
                    ReusableTextView("Text with chained modifiers")
                        .textStyle(.title3.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // Line limit with truncation
                GroupBox("3. Line Limit (2 lines)") {
                    ReusableTextView(longText)
                        .textStyle(.body)
                        .lineLimit(2)
                        .onTruncation {
                            print("Line limit truncation detected")
                            fullText = longText
                            isTruncated = true
                        }
                        .onTapGesture {
                            if isTruncated {
                                showBottomSheet = true
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // Character limit
                GroupBox("4. Character Limit (50)") {
                    ReusableTextView(longText)
                        .characterLimit(50)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // Without ellipsis
                GroupBox("5. Character Limit without Ellipsis") {
                    ReusableTextView(longText)
                        .characterLimit(40, showEllipsis: false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // Attributed text
                GroupBox("6. Attributed Text") {
                    ReusableTextView(createAttributedString())
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // Custom implementation
                GroupBox("7. Custom Styled Implementation") {
                    CustomStyledTextView(
                        "Custom implementation with footer",
                        textStyle: .headline,
                        lineLimit: 1
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // Highlighted text
                GroupBox("8. Highlighted Text") {
                    HighlightedTextView(
                        "This text has a highlight background",
                        highlightColor: .blue.opacity(0.2),
                        textStyle: .callout
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // Complex chaining
                GroupBox("9. Complex Chaining") {
                    ReusableTextView(longText)
                        .textStyle(.footnote)
                        .lineLimit(1)
                        .characterLimit(60)
                        .showEllipsis(true)
                        .onTruncation {
                            print("Complex chaining truncation")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                ModifiableTextExample()
            }
            .padding()
        }
        .sheet(isPresented: $showBottomSheet) {
            NavigationView {
                ScrollView {
                    Text(longText)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .navigationTitle("Full Text")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            showBottomSheet = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
    
    private func createAttributedString() -> AttributedString {
        var text = AttributedString("This text has ")
        var bold = AttributedString("bold")
        bold.font = .body.bold()
        bold.foregroundColor = .blue
        
        text.append(bold)
        text.append(AttributedString(" and "))
        
        var italic = AttributedString("italic")
        italic.font = .body.italic()
        italic.foregroundColor = .green
        
        text.append(italic)
        text.append(AttributedString(" styles applied."))
        
        return text
    }
}

// MARK: - Example showing direct property modification
struct ModifiableTextExample: View {
    @State private var textView = ReusableTextView("Modifiable text properties That will be a very long sting to test the auto layout")
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            textView
            
            HStack {
                Button("Toggle Line Limit") {
                    textView.lineLimit = textView.lineLimit == nil ? 1 : nil
                }
                .buttonStyle(.bordered)
                
                Button("Change Style") {
                    textView.textStyle = textView.textStyle == .body ? .title3.bold() : .body
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

