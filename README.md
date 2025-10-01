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
