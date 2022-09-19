{ lib, fetchFromGitHub, haskellPackages, makeWrapper, eprover }:

with haskellPackages; mkDerivation {
  pname = "Naproche-SAD";
  version = "2022-09-19";

  src = fetchFromGitHub {
    owner = "naproche";
    repo = "naproche";
    rev = "64ec081b936a2bd3cce75b4a40013ce2206f2a1d";
    sha256 = "1adwlgm6w7vjc86i6pvgrj6msl7dbajvq4k7yw51p60ka1w683f7";
  };

  isExecutable = true;

  buildTools = [ hpack makeWrapper ];
  executableHaskellDepends = [
    base array bytestring containers ghc-prim megaparsec mtl network process
    split temporary text threads time transformers uuid
  ];

  prePatch = "hpack";

  checkPhase = ''
    export NAPROCHE_EPROVER=${eprover}/bin/eprover
    dist/build/Naproche-SAD/Naproche-SAD examples/cantor.ftl.tex -t 60 --tex=on
  '';

  postInstall = ''
    wrapProgram $out/bin/Naproche-SAD \
      --set-default NAPROCHE_EPROVER ${eprover}/bin/eprover
  '';

  homepage = "https://github.com/naproche/naproche#readme";
  description = "Write formal proofs in natural language and LaTeX";
  maintainers = with lib.maintainers; [ jvanbruegge ];
  license = lib.licenses.gpl3Only;
}
