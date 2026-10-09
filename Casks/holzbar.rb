# Updated by .github/workflows/release.yml for every release.
cask "holzbar" do
  version "0.0.7"
  sha256 "9a9f38382d00e767a404f2277cfc5cb4e54c6fe7e90a63be9ce687221fe6d769"

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

  # The app is signed with its own certificate, not a Developer ID, so Gatekeeper would
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
