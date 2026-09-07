cask "voza" do
  version "0.2.0"
  sha256 :no_check  # replace with the real DMG SHA-256 on each release

  url "https://github.com/jerotherey/voza/releases/download/v#{version}/Voza-#{version}.dmg"
  name "Voza"
  desc "Local, offline, AI-powered push-to-talk dictation for macOS"
  homepage "https://github.com/jerotherey/voza"

  livecheck do
    url :homepage
    regex(%r{/releases/download/v?(\d+(?:\.\d+)+)/}i)
  end

  depends_on macos: ">= :sonoma"

  app "Voza.app"

  zap trash: [
    "~/.config/voza",
    "~/Library/Preferences/com.jerotherey.voza.plist",
  ]
end
