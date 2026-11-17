# Homebrew cask for Manita. Copy to Casks/manita.rb in the github.com/gzimbron/homebrew-tap repo.
# Users install with: brew install --cask gzimbron/tap/manita
cask "manita" do
  version "1.0.0" # x-release-please-version
  sha256 "fa740be46fe37228b5c7b2fa264ae562b0a91279ac56fa4896153fce63b997ee"

  url "https://github.com/gzimbron/manita/releases/download/v#{version}/Manita-#{version}.zip"
  name "Manita"
  desc "Cartoon hand pointer with click effects and presentation mode"
  homepage "https://github.com/gzimbron/manita"

  depends_on macos: :tahoe

  app "Manita.app"

  uninstall quit: "dev.gzimbron.manita"

  zap trash: [
    "~/Library/Application Support/Manita",
    "~/Library/Preferences/dev.gzimbron.manita.plist",
  ]
end
