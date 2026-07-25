import Defaults
import KeyboardShortcuts
import Settings
import SwiftUI

struct ScreenshotSettingsPane: View {
    @Default(.screenshotEnabled) private var screenshotEnabled

    var body: some View {
        Settings.Container(contentWidth: 450) {
            Settings.Section(title: "", bottomDivider: true) {
                Toggle(isOn: $screenshotEnabled) {
                    Text("EnableScreenshot", tableName: "ScreenshotSettings")
                }
                .help(Text("EnableScreenshotTooltip", tableName: "ScreenshotSettings"))

                Text("EnableScreenshotDescription", tableName: "ScreenshotSettings")
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.gray)
                    .controlSize(.small)
            }

            Settings.Section(
                bottomDivider: true,
                label: { Text("ScreenshotShortcut", tableName: "ScreenshotSettings") }
            ) {
                KeyboardShortcuts.Recorder(for: .screenshot)
                    .help(Text("ScreenshotShortcutTooltip", tableName: "ScreenshotSettings"))
            }

            Settings.Section(title: "") {
                Text("ScreenshotUsage", tableName: "ScreenshotSettings")
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.gray)
                    .controlSize(.small)
            }
        }
    }
}

#Preview {
    ScreenshotSettingsPane()
        .environment(\.locale, .init(identifier: "en"))
}
