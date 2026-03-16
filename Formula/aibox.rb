class Aibox < Formula
  desc "Run AI coding agents in isolated Docker containers"
  homepage "https://github.com/blitzdotdev/aibox"
  url "https://github.com/blitzdotdev/aibox/archive/refs/tags/v0.1.0.tar.gz"
  # sha256 will be filled after first release
  sha256 ""
  license "MIT"

  depends_on "docker" => :recommended
  depends_on "docker-compose" => :recommended

  def install
    bin.install "bin/aibox"
  end

  test do
    assert_match "aibox v", shell_output("#{bin}/aibox version")
  end
end
