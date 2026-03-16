class LclCommand < Formula
  desc "LaunchCloud Labs installable Mission Control client"
  homepage "https://www.launchcloudlabs.com/"
  url "https://registry.npmjs.org/lcl-command/-/lcl-command-0.3.0.tgz"
  sha256 "580ddf1c492fd3e9a9451fd45fc91fa2e917868b17007f60fca98470b837ae25"
  license "UNLICENSED"

  depends_on "node"

  def install
    system "npm", "install", *std_npm_args
  end

  test do
    assert_match "LCL Command", shell_output("#{bin}/lcl-command help")
  end
end
