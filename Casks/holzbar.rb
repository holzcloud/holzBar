# The stable channel: the newest plain release (no -alpha or -beta suffix). Updated by
# .github/workflows/release.yml for every plain release.
cask "holzbar" do
  version "0.0.11"
  sha256 "6415929bab5a657973c4051b8e52ce7d593f35271a3a136a2469bd5abf81b85a"

  url "https://github.com/holzcloud/holzBar/releases/download/v#{version}/holzBar-#{version}.zip"
  name "holzBar"
  desc "Menu bar manager: hide, reveal and style menu bar items (fork of Ice)"
  homepage "https://holzcloud.ch/holzbar"

  # Releases before 1.0 are pre-releases, which :github_latest skips. Plain versions only.
  livecheck do
    url "https://github.com/holzcloud/holzBar.git"
    strategy :git
    regex(/^v?(\d+(?:\.\d+)+)$/i)
  end

  conflicts_with cask: [
    "holzbar@beta",
    "jordanbaird-ice",
  ]
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
