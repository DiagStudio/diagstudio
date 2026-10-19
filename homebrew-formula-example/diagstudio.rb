# TEMPLATE ONLY: publish after a tested GitHub release and real SHA-256.
class Diagstudio < Formula
  desc "Cross-platform camera and audio diagnostics"
  homepage "https://github.com/DiagStudio/diagstudio"
  url "https://github.com/DiagStudio/diagstudio/archive/refs/tags/v0.2.0.tar.gz"
  sha256 "REPLACE_WITH_REAL_RELEASE_SHA256"
  license "MIT" # Change if the release has a different license.

  depends_on "swift" => :build

  on_linux do
    depends_on "v4l-utils"
    depends_on "alsa-utils"
  end

  def install
    system "bash", "scripts/build.sh"
    bin.install ".build/diagstudio"
  end

  test do
    assert_match "DiagStudio", shell_output("#{bin}/diagstudio --version")
  end
end
