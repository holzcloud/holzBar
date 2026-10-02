# Updated by .github/workflows/release.yml for every release.
# holzBar was called holzIce; cask_renames.json moves holzice installs here.
cask "holzbar" do
  version "0.0.5"
  sha256 "ae6d4edf024babbfdbb0e0ceb954d68e62b662ffb8e6278fdd3c1315f68b515e"

  # Until the first holzBar release this installs holzIce 0.0.5; the release workflow then switches it to holzBar.
  url "https://github.com/holzcloud/holzIce/releases/download/v#{version}/holzIce-#{version}.zip"
  name "holzBar"
  desc "Menu bar manager forked from Ice"
  homepage "https://holzcloud.ch/holzbar"

  # Releases before 1.0 are pre-releases, which :github_latest skips.
  livecheck do
    url "https://github.com/holzcloud/holzBar.git"
    strategy :git
    regex(/^v?(\d+(?:\.\d+)+(?:-[\w.]+)?)$/i)
  end

  # No conflict with "holzice": Homebrew resolves that token through cask_renames.json
  # to this cask, so holzbar would conflict with itself. The rename already keeps the
  # two from being installed together, and the app offers to quit a running holzIce.
  conflicts_with cask: "jordanbaird-ice"
  depends_on macos: :sonoma

  app "holzIce.app"

  # The app is signed ad hoc, not with a Developer ID, so Gatekeeper would
  # refuse to open it while it carries the quarantine attribute.
  postflight_steps do
    run "/usr/bin/xattr",
        args:           ["-dr", "com.apple.quarantine", "{{appdir}}/holzIce.app"],
        must_succeed:   false,
        writable_paths: ["holzIce.app"],
        writable_base:  :appdir
  end

  uninstall quit: ["com.holzcloud.holzBar", "com.holzcloud.holzIce"]

  # The holzIce paths are what a user who came from holzIce leaves behind.
  zap trash: [
    "~/Library/Application Support/holzBar",
    "~/Library/Application Support/holzIce",
    "~/Library/Caches/com.holzcloud.holzBar",
    "~/Library/Caches/com.holzcloud.holzIce",
    "~/Library/HTTPStorages/com.holzcloud.holzBar",
    "~/Library/HTTPStorages/com.holzcloud.holzIce",
    "~/Library/Preferences/com.holzcloud.holzBar.plist",
    "~/Library/Preferences/com.holzcloud.holzIce.plist",
  ]
end
