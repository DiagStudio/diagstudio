# COPY TO: DiagStudio/homebrew-tools/Formula/diagstudio.rb
# ONLY AFTER publishing the matching source tag and obtaining its real SHA-256.
class Diagstudio < Formula
  desc "macOS webcam and audio diagnostic utility"
  homepage "https://github.com/DiagStudio/diagstudio"
  url "https://github.com/DiagStudio/diagstudio/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "REPLACE_WITH_REAL_SHA256_FROM_RELEASE_ARCHIVE"
  license "MIT"
  depends_on :macos
  depends_on :xcode => ["15.0", :build]

  def install
    system "./scripts/build.sh"
    bin.install ".build/diagstudio"
  end

  test do
    assert_match "DiagStudio 0.1.0", shell_output("#{bin}/diagstudio --version")
  end
end
