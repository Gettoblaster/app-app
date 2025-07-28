//
//  Homepage.swift
//  YourAppName
//
//  Created by You on YYYY/MM/DD.
//

import SwiftUI
import AVFoundation

// MARK: – PreviewView for camera feed
class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

// MARK: – CameraView: simple live camera feed
struct CameraView: UIViewRepresentable {
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        let session = AVCaptureSession()
        session.sessionPreset = .high

        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        }

        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        session.startRunning()
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

// MARK: – ScannerView: camera + QR scanning
struct ScannerView: UIViewRepresentable {
    var onDetect: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDetect: onDetect)
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        let session = AVCaptureSession()
        session.sessionPreset = .high

        // camera input
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        }

        // metadata output
        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(context.coordinator, queue: .main)
            output.metadataObjectTypes = [.qr]
            let side: CGFloat = 0.6
            let x = (1 - side)/2
            let y = (1 - side)/2
            output.rectOfInterest = CGRect(x: y, y: x, width: side, height: side)
        }

        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        session.startRunning()
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onDetect: (Int) -> Void
        init(onDetect: @escaping (Int) -> Void) { self.onDetect = onDetect }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            for obj in metadataObjects {
                guard let qr = obj as? AVMetadataMachineReadableCodeObject,
                      qr.type == .qr,
                      let s = qr.stringValue,
                      let id = Int(s) else { continue }
                onDetect(id)
                break
            }
        }
    }
}

// MARK: – ScannerOverlay: mask + frame
struct ScannerOverlay: View {
    var isScanning: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            if isScanning {
                let side = size.width * 0.6
                let x = (size.width - side)/2
                let y = (size.height - side)/2
                Path { p in
                    p.addRect(CGRect(origin: .zero, size: size))
                    p.addRoundedRect(in: CGRect(x: x, y: y, width: side, height: side),
                                     cornerSize: CGSize(width: 16, height: 16))
                }
                .fill(Color.black.opacity(0.6), style: FillStyle(eoFill: true))

                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: side, height: side)
                    .position(x: size.width/2, y: size.height/2)
            } else {
                Color.black.opacity(0.8)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: – Location model matching backend JSON
struct Location: Identifiable, Codable {
    let id: Int
    let name: String
}


// MARK: – Homepage View
struct Homepage: View {
    @Binding var selectedTab: Int

    // scan + picker state
    @State private var isCheckedIn = false
    @State private var selectedLocation = "Abwesend"
    @State private var locationOptions: [String] = []
    @State private var locationList: [Location] = []
    @State private var showAlert = false
    @State private var alertMessage = ""
    // internal flag so updates from backend don't trigger onChange logic
    @State private var ignoreSelectionChange = false

    // debug / backend test
    @State private var backendMessage: String = ""

    private var isScanning: Bool {
        !isCheckedIn && selectedLocation == "Abwesend"
    }

    var body: some View {
        ZStack {
            if isScanning {
                ScannerView(onDetect: handleDetect)
                    .ignoresSafeArea()
            } else {
                CameraView()
                    .ignoresSafeArea()
            }

            ScannerOverlay(isScanning: isScanning)

            VStack {
                HStack {
                    Image(systemName: "list.bullet")
                        .foregroundStyle(.white)
                        .padding(.leading, 40)
                        .onTapGesture { selectedTab = 1 }
                    Spacer()
                    Picker("Standort", selection: $selectedLocation) {
                        ForEach(locationOptions, id: \.self) {
                            Text($0)
                        }
                    }
                    .pickerStyle(.menu)
                    .overlay(RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray, lineWidth: 1))
                    .background(RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white.opacity(0.3)))
                    .onChange(of: selectedLocation) { old, new in
                        if ignoreSelectionChange {
                            ignoreSelectionChange = false
                            return
                        }

                        if new == "Abwesend" {
                            if isCheckedIn {
                                SessionService.clockOut { _ in }
                                isCheckedIn = false
                            }
                        } else if let loc = locationList.first(where: { $0.name == new }) {
                            if isCheckedIn {
                                SessionService.clockOut { _ in
                                    SessionService.clockIn(locationId: loc.id) { _ in }
                                }
                            } else {
                                SessionService.clockIn(locationId: loc.id) { _ in }
                            }
                            alertMessage = "Eingecheckt in \(loc.name)"
                            isCheckedIn = true
                            showAlert = true
                        }
                    }
                    Spacer()
                    Image(systemName: "person")
                        .foregroundStyle(.white)
                        .padding(.trailing, 40)
                        .onTapGesture { selectedTab = 2 }
                }
                .padding(.top, 20)

                Spacer()

                Button(isCheckedIn ? "Auschecken" : "Abwesend melden") {
                    if isCheckedIn {
                        // Wenn Du eingecheckt bist, schicke den Clock‑Out‑Request ab
                        SessionService.clockOut { result in
                            switch result {
                            case .success:
                                print("✅ ClockOut erfolgreich")
                            case .failure(let err):
                                print("❌ ClockOut‑Fehler:", err)
                            }
                        }
                    }
                    // Danach immer zurück auf Abwesend
                    ignoreSelectionChange = true

                    let previous = selectedLocation

                    selectedLocation = "Abwesend"
                    if previous == selectedLocation {
                        // reset flag when value hasn't actually changed
                        ignoreSelectionChange = false
                    }
                    isCheckedIn = false
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(selectedLocation == "Abwesend")
                .padding(.bottom, 20)

            }
        }
        .onAppear {
            fetchCurrentLocation()
            loadLocations()
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Status"),
                  message: Text(alertMessage),
                  dismissButton: .default(Text("OK")))
        }
    }
    // MARK: – handle QR detection
    private func handleDetect(_ id: Int) {
        guard let loc = locationList.first(where: { $0.id == id }) else { return }
        if isCheckedIn {
            SessionService.clockOut { _ in
                SessionService.clockIn(locationId: loc.id) { _ in }
            }
        } else {
            SessionService.clockIn(locationId: loc.id) { _ in }

        }
        alertMessage = "Eingecheckt in \(loc.name)"
        ignoreSelectionChange = true
        let previous = selectedLocation
        selectedLocation = loc.name
        if previous == selectedLocation {
            ignoreSelectionChange = false
        }
        isCheckedIn = true
        showAlert = true
    }

    // MARK: – fetch current user location
    private func fetchCurrentLocation() {
        guard let url = URL(string: "http://172.16.42.23:3000/location/me") else {
            print("🔴 Ungültige URL für location/me")
            return
        }
        APIClient.shared.getJSON(url) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let data):
                    if let arr = data as? [[String: Any]],
                       let first = arr.first,
                       let name = first["name"] as? String {
                        ignoreSelectionChange = true

                        let previous = selectedLocation
                        selectedLocation = name
                        if previous == selectedLocation {
                            ignoreSelectionChange = false
                        }
                        isCheckedIn = true
                    } else {
                        ignoreSelectionChange = true
                        let previous = selectedLocation
                        selectedLocation = "Abwesend"
                        if previous == selectedLocation {
                            ignoreSelectionChange = false
                        }

                        isCheckedIn = false
                    }
                case .failure(let err):
                    print("🔴 Fehler beim Laden der aktuellen Position: \(err.localizedDescription)")
                }
            }
        }
    }

    // MARK: – load locations from backend
    private func loadLocations() {
        locationOptions = ["Abwesend"]
        locationList = []

        guard let url = URL(string: "http://172.16.42.23:3000/web/allLocations") else {
            print("🔴 Ungültige URL für Locations")
            return
        }

        APIClient.shared.getJSON(url) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let json):
                    guard let arr = json as? [[String: Any]] else {
                        print("🔴 Ungültiges JSON‑Format")
                        return
                    }
                    self.locationList = arr.compactMap { dict in
                        guard let id = dict["id"] as? Int,
                              let name = dict["name"] as? String
                        else { return nil }
                        return Location(id: id, name: name)
                    }
                    self.locationOptions += self.locationList.map { $0.name }
                case .failure(let err):
                    print("🔴 Fehler beim Laden der Locations:", err.localizedDescription)
                }
            }
        }
    }
}

// MARK: – SwipeContainerView
struct SwipeContainerView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            WorkersListView().tag(1)
            Homepage(selectedTab: $selectedTab).tag(0)
            ProfilView().tag(2)
        }
        .ignoresSafeArea()
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
    }
}

// MARK: – Preview
struct Homepage_Previews: PreviewProvider {
    static var previews: some View {
        SwipeContainerView()
    }
}
