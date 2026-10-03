# Updated by .github/workflows/release.yml for every release.
cask "holzbar" do
  version "0.0.6-beta1"
  sha256 "bd432a166fad5e5102cca933e09f58da767f003e61d9008e08afb520db52f7b0"

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
