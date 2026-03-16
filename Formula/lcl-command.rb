class LclCommand < Formula
  desc "LaunchCloud Labs installable Mission Control client"
  homepage "https://www.launchcloudlabs.com/"
  url "https://github.com/LaunchCloud-Labs/LCL-Command/releases/download/v0.2.0/lcl-command-0.2.0.tgz"
  sha256 "c3f828a214286168aa96c5f99b24a2801c2ce6bc37e5a857aeeb5ec3e897bea1"
  license "UNLICENSED"

  depends_on "node"

  def install
    system "npm", "install", *std_npm_args
  end

  test do
    assert_match "LCL Command", shell_output("#{bin}/lcl-command help")
  end
end
