# Updated by .github/workflows/release.yml for every release.
cask "holzbar" do
  version "0.0.5"
  sha256 "ae6d4edf024babbfdbb0e0ceb954d68e62b662ffb8e6278fdd3c1315f68b515e"

  url "https://github.com/holzcloud/holzBar/releases/download/v#{version}/holzBar-#{version}.zip"
  name "holzBar"
  desc "Menu bar manager forked from Ice"
  homepage "https://holzcloud.ch/holzbar"

  # Releases before 1.0 are pre-releases, which :github_latest skips.
  livecheck do
    url "https://github.com/holzcloud/holzBar.git"
    strategy :git
    regex(/^v?(\d+(?:\.\d+)+(?:-[\w.]+)?)$/i)
  end

  conflicts_with cask: "jordanbaird-ice"
  depends_on macos: :sonoma

  app "holzBar.app"

  # The app is signed ad hoc, not with a Developer ID, so Gatekeeper would
  # refuse to open it while it carries the quarantine attribute.
  postflight_steps do
    run "/usr/bin/xattr",
        args:           ["-dr", "com.apple.quarantine", "{{appdir}}/holzBar.app"],
        must_succeed:   false,
        writable_paths: ["holzBar.app"],
        writable_base:  :appdir
  end

  uninstall quit: "com.holzcloud.holzBar"

  zap trash: [
    "~/Library/Application Support/holzBar",
    "~/Library/Caches/com.holzcloud.holzBar",
    "~/Library/HTTPStorages/com.holzcloud.holzBar",
    "~/Library/Preferences/com.holzcloud.holzBar.plist",
  ]
end
