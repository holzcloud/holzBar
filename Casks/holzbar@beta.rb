# The beta channel: the newest alpha, beta or plain release. Updated by
# .github/workflows/release.yml for every release.
cask "holzbar@beta" do
  version "0.0.13-beta1"
  sha256 "7c07dc3312aa4678ce3f49bd78a060d559ddc32b4efd7a1ed545249d8d23354e"

  url "https://github.com/holzcloud/holzBar/releases/download/v#{version}/holzBar-#{version}.zip"
  name "holzBar"
  desc "Menu bar manager: hide, reveal and style menu bar items (fork of Ice)"
  homepage "https://holzcloud.ch/holzbar"

  # Releases before 1.0 are pre-releases, which :github_latest skips. Suffixes -alphaN and
  # -betaN count.
  livecheck do
    url "https://github.com/holzcloud/holzBar.git"
    strategy :git
    regex(/^v?(\d+(?:\.\d+)+(?:-(?:alpha|beta)\d+)?)$/i)
  end

  conflicts_with cask: [
    "holzbar",
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
