require "language/node"

class Lanraragi < Formula
  desc "Web application for archival and reading of manga/doujinshi"
  homepage "https://github.com/Difegue/LANraragi"
  # url "https://github.com/Difegue/LANraragi/archive/v.0.7.6.tar.gz"
  # sha256 "2c498cc6a18b9fbb77c52ca41ba329c503aa5d4ec648075c3ebb72bfa7102099"
  url "https://github.com/Difegue/LANraragi.git",
      revision: "COMMIT_HASH"
  version "0.1994-dev"
  license "MIT"
  revision 1
  head "https://github.com/Difegue/LANraragi.git"

  depends_on "pkg-config" => :build
  depends_on "cpanminus"
  depends_on "ghostscript"
  depends_on "giflib"
  depends_on "imagemagick"
  depends_on "jpeg"
  depends_on "libpng"
  depends_on "node"
  depends_on "openssl@1.1"
  depends_on "perl"
  depends_on "redis"
  uses_from_macos "libarchive"

  resource "Image::Magick" do
    url "https://cpan.metacpan.org/authors/id/J/JC/JCRISTY/PerlMagick-7.0.10.tar.gz"
    sha256 "1d5272d71b5cb44c30cd84b09b4dc5735b850de164a192ba191a9b35568305f4"
  end

  resource "libarchive-headers" do
    url "https://opensource.apple.com/tarballs/libarchive/libarchive-83.40.4.tar.gz"
    sha256 "20ad61b1301138bc7445e204dd9e9e49145987b6655bbac39f6cad3c75b10369"
  end

  resource "Archive::Peek::Libarchive" do
    url "https://cpan.metacpan.org/authors/id/R/RE/REHSACK/Archive-Peek-Libarchive-0.38.tar.gz"
    sha256 "332159603c5cd560da27fd80759da84dad7d8c5b3d96fbf7586de2b264f11b70"
  end

  def install
    ENV.prepend_create_path "PERL5LIB", "#{libexec}/lib/perl5"
    ENV.prepend_path "PERL5LIB", "#{libexec}/lib"
    ENV["CFLAGS"] = "-I#{libexec}/include"
    # https://stackoverflow.com/questions/60521205/how-can-i-install-netssleay-with-perlbrew-in-macos-catalina
    ENV["OPENSSL_PREFIX"] = "#{Formula["openssl@1.1"]}/1.1.1g"

    imagemagick = Formula["imagemagick"]
    resource("Image::Magick").stage do
      inreplace "Makefile.PL" do |s|
        s.gsub! "/usr/local/include/ImageMagick-#{imagemagick.version.major}",
                "#{imagemagick.opt_include}/ImageMagick-#{imagemagick.version.major}"
      end

      system "perl", "Makefile.PL", "INSTALL_BASE=#{libexec}"
      system "make"
      system "make", "install"
    end

    resource("libarchive-headers").stage do
      cd "libarchive/libarchive" do
        (libexec/"include").install "archive.h", "archive_entry.h"
      end
    end

    resource("Archive::Peek::Libarchive").stage do
      inreplace "Makefile.PL" do |s|
        s.gsub! "$autoconf->_get_extra_compiler_flags", "$autoconf->_get_extra_compiler_flags .$ENV{CFLAGS}"
      end

      system "cpanm", "Config::AutoConf", "--notest", "-l", libexec
      system "perl", "Makefile.PL", "INSTALL_BASE=#{libexec}"
      system "make"
      system "make", "install"
    end

    system "npm", "install", *Language::Node.local_npm_install_args
    system "perl", "./tools/install.pl", "install-full"

    prefix.install "README.md"
    (libexec/"lib").install Dir["lib/*"]
    libexec.install "script", "package.json", "public", "templates", "tests", "lrr.conf"
    cd "tools/build/homebrew" do
      bin.install "lanraragi"
      libexec.install "redis.conf"
    end
  end

  def caveats
    <<~EOS
      Automatic thumbnail generation will not work properly on macOS < 10.15 due to the bundled Libarchive being too old.
      Opening archives for reading will generate thumbnails normally.
    EOS
  end

  test do
    # brew-core uses this to test user-facing functionality by checking for the redis table flip.
    # As this is used for CI here, it's more logical to run the test suite instead.
    ENV["PERL5LIB"] = libexec/"lib/perl5"
    ENV["LRR_LOG_DIRECTORY"] = testpath/"log"

    system "npm", "--prefix", libexec, "test"
  end
end
