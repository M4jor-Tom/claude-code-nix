{ rustPlatform, fetchCrate, lib }:
rustPlatform.buildRustPackage rec {
  pname = "rtk";
  version = "0.1.0";

  src = fetchCrate {
    inherit pname version;
    hash = "sha256-oXJmayUviPqikKClCrPM4aD8FYbxDRF7F6N/7n7z8ek=";
  };

  cargoHash = "sha256-j9fC28tIjjBNjzJiUsGThA5TedC82b/NKggGCaRJ7Gc=";

  meta = {
    description = "Rust Token Killer - token optimization hook for Claude Code";
    homepage = "https://www.rtk-ai.app/";
    mainProgram = "rtk";
  };
}
