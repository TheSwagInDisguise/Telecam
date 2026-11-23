import SwiftUI

struct ContentView: View {
    @StateObject private var camera = CameraModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Text(camera.status)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(.top, 8)

                Spacer()

                VStack(spacing: 14) {
                    Picker("Lens", selection: $camera.lens) {
                        ForEach(LensChoice.allCases) { lens in
                            Text(lens.label).tag(lens)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(camera.isCapturing)

                    Toggle("2x add-on lens attached", isOn: $camera.addOnAttached)
                        .foregroundStyle(.white)

                    Stepper("Burst: \(camera.burstCount) RAW frames",
                            value: $camera.burstCount, in: 1...16)
                        .foregroundStyle(.white)
                        .disabled(camera.isCapturing)

                    Button {
                        camera.captureBurst()
                    } label: {
                        Circle()
                            .strokeBorder(.white, lineWidth: 4)
                            .background(Circle().fill(camera.isCapturing ? Color.red : Color.white.opacity(0.9)).padding(8))
                            .frame(width: 76, height: 76)
                    }
                    .disabled(camera.isCapturing || !camera.isReady)
                }
                .padding()
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .onAppear { camera.start() }
        .onChange(of: camera.lens) { _, _ in camera.configure() }
    }
}
