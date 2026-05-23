import SwiftUI

struct RecordButton: View {

    let isRecording: Bool
    let isDisabled: Bool
    let action: () -> Void

    @State private var isPulsing = false

    var body: some View {
        Button(action: action) {
            ZStack {
                // Pulse ring (visible only while recording)
                if isRecording {
                    Circle()
                        .stroke(Color.red.opacity(0.35), lineWidth: 3)
                        .scaleEffect(isPulsing ? 1.55 : 1.0)
                        .opacity(isPulsing ? 0 : 1)
                        .animation(
                            .easeOut(duration: 1.1).repeatForever(autoreverses: false),
                            value: isPulsing
                        )
                }

                // Main circle
                Circle()
                    .fill(isRecording ? Color.red : Color.accentColor)
                    .frame(width: 72, height: 72)
                    .shadow(color: (isRecording ? Color.red : Color.accentColor).opacity(0.45), radius: 12, y: 4)

                // Icon
                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(.white)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .onChange(of: isRecording) { _, recording in
            isPulsing = recording
        }
        .onAppear {
            isPulsing = isRecording
        }
    }
}
