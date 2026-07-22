{ lib, stdenv, fetchurl, autoPatchelfHook }:
# rtk — "Rust Token Killer", the token-optimization proxy/hook for Claude Code
# (github.com/rtk-ai/rtk). NOT the `rtk` crate on crates.io: that name belongs to
# an unrelated "Rust Type Kit" (reachingforthejack/rtk), which is what the old
# `fetchCrate` here mistakenly installed — hence `rtk hook claude` failing with
# "unexpected argument 'hook'".
#
# Packaged from the official release tarballs rather than built from source:
# rtk isn't published to crates.io, and a source build would require a cargoHash
# that can't be pinned here. The release tarballs are content-addressed by the
# sha256 in the upstream checksums.txt.
let
  version = "0.43.0";

  # system -> { release asset, its sha256, whether it is a static musl build }.
  sources = {
    "x86_64-linux" = {
      asset = "rtk-x86_64-unknown-linux-musl.tar.gz"; # static: no ELF patching needed
      sha256 = "ff8a1e7766496e175291a85aeca1dc97c9ff6df33e51e5893d1fbc78fea2a609";
      static = true;
    };
    "aarch64-linux" = {
      asset = "rtk-aarch64-unknown-linux-gnu.tar.gz"; # glibc dynamic: needs autoPatchelf
      sha256 = "5519f7ca12e5c143a609f0d28a0a77b97413a8dce31c2681f1a41c24519a8731";
      static = false;
    };
  };

  source = sources.${stdenv.hostPlatform.system}
    or (throw "rtk: no prebuilt binary for ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation {
  pname = "rtk";
  inherit version;

  src = fetchurl {
    url = "https://github.com/rtk-ai/rtk/releases/download/v${version}/${source.asset}";
    inherit (source) sha256;
  };

  # goreleaser tarballs have no wrapping directory; unpack straight into cwd.
  sourceRoot = ".";

  nativeBuildInputs = lib.optionals (!source.static) [ autoPatchelfHook ];
  buildInputs = lib.optionals (!source.static) [ stdenv.cc.cc.lib ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 "$(find . -type f -name rtk | head -n1)" "$out/bin/rtk"
    runHook postInstall
  '';

  meta = {
    description = "Rust Token Killer - token-optimization proxy/hook for Claude Code";
    homepage = "https://www.rtk-ai.app/";
    downloadPage = "https://github.com/rtk-ai/rtk/releases";
    license = lib.licenses.asl20;
    mainProgram = "rtk";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = builtins.attrNames sources;
  };
}
