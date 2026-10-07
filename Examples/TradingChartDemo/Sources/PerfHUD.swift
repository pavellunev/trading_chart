import SwiftUI

/// A one-line overlay with the frame statistics of the running `-perf` recording.
struct PerfHUD: View {
    let recorder: FrameRecorder

    var body: some View {
        Text(recorder.note.isEmpty ? recorder.summary : recorder.summary + "\n" + recorder.note)
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
            .padding(.top, 2)
            .padding(.leading, 4)
            .allowsHitTesting(false)
    }
}
