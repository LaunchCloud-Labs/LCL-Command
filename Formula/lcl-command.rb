class LclCommand < Formula
  desc "LaunchCloud Labs installable Mission Control client"
  homepage "https://www.launchcloudlabs.com/"
  url "https://registry.npmjs.org/lcl-command/-/lcl-command-0.4.0.tgz"
  sha256 "335bc414720271bf5797de8b8bd45d807a4b658e5bfc906e52846c6303249058"
  license "UNLICENSED"

  depends_on "node"

  def install
    system "npm", "install", *std_npm_args
  end

  test do
    assert_match "LCL Command", shell_output("#{bin}/lcl-command help")
  end
end
