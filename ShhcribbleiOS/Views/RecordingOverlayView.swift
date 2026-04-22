import SwiftUI

struct RecordingOverlayView: View {
    @ObservedObject var status: TranscriptionStatus
    @State private var pulse = false
    @State private var arrowBounce = false

    var body: some View {
        if status.isRecording {
            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: [Color.black, Color(red: 0.15, green: 0.02, blue: 0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "arrow.up.left")
                        .font(.system(size: 42, weight: .heavy))
                        .foregroundStyle(.white)
                        .offset(x: arrowBounce ? -3 : 3, y: arrowBounce ? -3 : 3)
                        .animation(
                            .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                            value: arrowBounce
                        )
                    Text("Tap the back pill\nup there to stop\n& return")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineSpacing(2)
                }
                .padding(.leading, 16)
                .padding(.top, 4)

                VStack(spacing: 28) {
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.18))
                            .frame(width: 180, height: 180)
                            .scaleEffect(pulse ? 1.15 : 0.9)
                            .opacity(pulse ? 0.4 : 0.9)
                        Circle()
                            .fill(Color.red.opacity(0.35))
                            .frame(width: 120, height: 120)
                        Image(systemName: "mic.fill")
                            .font(.system(size: 54, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .animation(
                        .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                        value: pulse
                    )

                    Text("Recording…")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(status.partialSnippet.isEmpty ? "Listening" : status.partialSnippet)
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 32)
                        .frame(minHeight: 40)

                    Text("Pause briefly before tapping back\nso the last word lands in the clipboard.")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .preferredColorScheme(.dark)
            .transition(.opacity)
            .onAppear {
                pulse = true
                arrowBounce = true
            }
            .onDisappear {
                pulse = false
                arrowBounce = false
            }
        }
    }
}
