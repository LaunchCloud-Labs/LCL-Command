class LclCommand < Formula
  desc "LaunchCloud Labs installable Mission Control client"
  homepage "https://www.launchcloudlabs.com/"
  url "https://registry.npmjs.org/lcl-command/-/lcl-command-0.2.0.tgz"
  sha256 "f2c044b5113fdc1f5e2b8d12708d8dc022d64b7b82695a60b837b8247c530d25"
  license "UNLICENSED"

  depends_on "node"

  def install
    system "npm", "install", *std_npm_args
  end

  test do
    assert_match "LCL Command", shell_output("#{bin}/lcl-command help")
  end
end
