{ stdenv, lib, fetchFromGitHub, isabelle }:

stdenv.mkDerivation rec {
  pname = "isabelle-linter";
  version = "2023-RC1";

  src = fetchFromGitHub {
    owner = "isabelle-prover";
    repo = "isabelle-linter";
    rev = "43464c9c440a7ba608a8cb1d31f47ca95602acde";
    sha256 = "sha256-q9+qN94NaTzvhbcNQj7yH/VVfs1QgCH8OU8HW+5+s9U=";
  };

  nativeBuildInputs = [ isabelle ];

  buildPhase = ''
    export HOME=$TMP
    isabelle components -u $(pwd)
    isabelle scala_build
  '';

  installPhase = ''
    dir=$out/Isabelle${isabelle.version}/contrib/${pname}-${version}
    mkdir -p $dir
    cp -r * $dir/
  '';

  meta = with lib; {
    description = "Linter component for Isabelle.";
    homepage = "https://github.com/isabelle-prover/isabelle-linter";
    maintainers = with maintainers; [ jvanbruegge ];
    license = licenses.mit;
    platforms = platforms.all;
  };
}
