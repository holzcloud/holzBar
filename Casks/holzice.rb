# Updated by .github/workflows/release.yml for every release.
cask "holzice" do
  version "0.0.0"
  sha256 :no_check

  url "https://github.com/holzcloud/holzIce/releases/download/v#{version}/holzIce-#{version}.zip"
  name "holzIce"
  desc "Menu bar manager (fork of Ice with macOS 27 support)"
  homepage "https://github.com/holzcloud/holzIce"

  # Releases before 1.0 are pre-releases, which :github_latest skips.
  livecheck do
    url "https://github.com/holzcloud/holzIce.git"
    strategy :git
    regex(/^v?(\d+(?:\.\d+)+(?:-[\w.]+)?)$/i)
  end

  conflicts_with cask: "jordanbaird-ice"
  depends_on macos: ">= :sonoma"

  app "holzIce.app"

  # The app is signed ad hoc, not with a Developer ID, so Gatekeeper would
  # refuse to open it while it carries the quarantine attribute.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/holzIce.app"]
  end

  uninstall quit: "com.holzcloud.holzIce"

  zap trash: [
    "~/Library/Application Support/holzIce",
    "~/Library/Caches/com.holzcloud.holzIce",
    "~/Library/HTTPStorages/com.holzcloud.holzIce",
    "~/Library/Preferences/com.holzcloud.holzIce.plist",
  ]
end
