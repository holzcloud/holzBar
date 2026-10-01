# Updated by .github/workflows/release.yml for every release.
cask "holzice" do
  version "0.0.0"
  sha256 :no_check

  url "https://github.com/holzcloud/holzIce/releases/download/v#{version}/holzIce-#{version}.zip"
  name "holzIce"
  desc "Menu bar manager (fork of Ice with macOS 27 support)"
  homepage "https://github.com/holzcloud/holzIce"

  livecheck do
    url :url
    strategy :github_latest
  end

  conflicts_with cask: "jordanbaird-ice"
  depends_on macos: ">= :sonoma"

  app "Ice.app"

  # The app is signed ad hoc, not with a Developer ID, so Gatekeeper would
  # refuse to open it while it carries the quarantine attribute.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Ice.app"]
  end

  uninstall quit: "com.jordanbaird.Ice"

  zap trash: [
    "~/Library/Application Support/Ice",
    "~/Library/Caches/com.jordanbaird.Ice",
    "~/Library/HTTPStorages/com.jordanbaird.Ice",
    "~/Library/Preferences/com.jordanbaird.Ice.plist",
  ]
end
