{ lib, stdenv, stdenvNoCC, fetchurl, coreutils, cacert, mercurial, nettools, java, scala_3, polyml, z3, veriT, cvc4, vampire, eprover-ho, naproche, rlwrap, perl, makeDesktopItem, isabelle-components, isabelle, symlinkJoin, fetchhg, unzip }:
# nettools needed for hostname

let
  sha1 = stdenv.mkDerivation {
    pname = "isabelle-sha1";
    version = "2021-1";

    src = fetchhg {
      url = "https://isabelle.sketis.net/repos/sha1";
      rev = "e0239faa6f42";
      sha256 = "sha256-4sxHzU/ixMAkSo67FiE6/ZqWJq9Nb9OMNhMoXH2bEy4=";
    };

    buildPhase = (if stdenv.isDarwin then ''
      LDFLAGS="-dynamic -undefined dynamic_lookup -lSystem"
    '' else ''
      LDFLAGS="-fPIC -shared"
    '') + ''
      CFLAGS="-fPIC -I."
      $CC $CFLAGS -c sha1.c -o sha1.o
      $LD $LDFLAGS sha1.o -o libsha1.so
    '';

    installPhase = ''
      mkdir -p $out/lib
      cp libsha1.so $out/lib/
    '';
  };
in stdenv.mkDerivation rec {
  pname = "isabelle";
  version = "2022-RC3";

  dirname = "Isabelle${version}";

  # can't use fetchhg here, because the Isabelle build requires the .hg directory
  src = stdenvNoCC.mkDerivation rec {
    name = "${dirname}-source";

    url = "https://isabelle.sketis.net/repos/isabelle";
    rev = dirname;
    sha256 = "sha256-X5VF1a50QkHkDokBWff34OhVHZ4Wi/X9dQvDLt4iOg4=";

    nativeBuildInputs = [ mercurial cacert ];
    phases = [ "buildPhase" ];
    buildPhase = ''
      hg clone -r "$rev" "$url" $out
    '';

    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
    outputHash = sha256;
  };

  nativeBuildInputs = [ mercurial unzip ];

  buildInputs = [ polyml z3 veriT vampire eprover-ho cvc4 nettools ]
    ++ lib.optionals (!stdenv.isDarwin) [ java ];

  buildPhase = ''
    cd ${src.name}
    export HOME=$(pwd)
    sed -i 's/\.isabelle\/contrib/contrib/' etc/settings

    # Set correct build
    sed -i 's/List(linux, windows, macos)/List(${if stdenv.isDarwin then "macos" else "linux"})/' src/Pure/System/platform.scala

    # Patch sources to use nix versions
    substituteInPlace src/Pure/General/sha1.ML \
      --replace '"$ML_HOME/" ^ (if ML_System.platform_is_windows then "sha1.dll" else "libsha1.so")' '"${sha1}/lib/libsha1.so"'

    # Set up bash_process
    bash_process_folder="contrib/$(grep bash_process < Admin/components/main)"
    mkdir -p "$bash_process_folder/etc"
    echo "ISABELLE_BASH_PROCESS_HOME=\"\$COMPONENT\"
    ISABELLE_BASH_PROCESS=\"\$ISABELLE_BASH_PROCESS_HOME/bash_process\"" > $bash_process_folder/etc/settings
    cc -Wall Admin/bash_process/bash_process.c -o "$bash_process_folder/bash_process"

    # Set up jdk
    jdk_folder="contrib/$(grep jdk < Admin/components/main)/etc"
    mkdir -p "$jdk_folder"
    echo 'ISABELLE_JAVA_PLATFORM=${stdenv.system}
    ISABELLE_JDK_HOME=${java}' > $jdk_folder/settings
    hg add contrib/jdk*

    mkdir -p contrib/polyml
    cp Admin/polyml/README contrib/polyml/
    hg add contrib/polyml/README

    sed -E -i '/^(polyml|cvc4|e|verit|z3|vampire)-/d' Admin/components/main

    settings='
    ML_SYSTEM_64=true
    ML_SYSTEM=${polyml.name}
    ML_PLATFORM=${stdenv.system}
    ML_HOME=${polyml}/bin
    ML_OPTIONS="--minheap 1000"
    POLYML_HOME="$ISABELLE_HOME/contrib/polyml"
    ML_SOURCES="${polyml.src}"

    CVC4_HOME="${cvc4}/bin"
    CVC4_VERSION="${cvc4.version}"
    CVC4_SOLVER="${cvc4}/bin/cvc4"
    CVC4_INSTALLED="yes"

    E_HOME="${eprover-ho}/bin"
    E_VERSION="${eprover-ho.version}"

    ISABELLE_VERIT="${veriT}/bin/veriT"

    Z3_HOME="${z3}"
    Z3_VERSION="${z3.version}"
    Z3_SOLVER="${z3}/bin/z3"
    Z3_INSTALLED="yes"

    VAMPIRE_HOME="${vampire}/bin"
    VAMPIRE_VERSION="${vampire.version}"
    VAMPIRE_EXTRA_OPTIONS="--mode casc"
    '

    echo "$settings" >> etc/settings
    echo "$settings" >> Admin/etc/settings

    # Save changes to source
    hg commit -m "Patches for nixpkgs" -u git@github.com

    $shell ./Admin/init

    setup_name=$(basename contrib/isabelle_setup*)

    #The following is adapted from https://isabelle.sketis.net/repos/isabelle/file/Isabelle2021-1/Admin/lib/Tools/build_setup
    TARGET_DIR="contrib/$setup_name/lib"
    rm -rf "$TARGET_DIR"
    mkdir -p "$TARGET_DIR/isabelle/setup"
    declare -a ARGS=("-Xlint:unchecked")
    SOURCES="$(${perl}/bin/perl -e 'while (<>) { if (m/(\S+\.java)/)  { print "$1 "; } }' "src/Tools/Setup/etc/build.props")"
    for SRC in $SOURCES
    do
      ARGS["''${#ARGS[@]}"]="src/Tools/Setup/$SRC"
    done
    echo "Building isabelle setup"
    ${java}/bin/javac -d "$TARGET_DIR" -classpath "${scala_3.bare}/lib/scala3-interfaces-${scala_3.version}.jar:${scala_3.bare}/lib/scala3-compiler_3-${scala_3.version}.jar" "''${ARGS[@]}"
    ${java}/bin/jar -c -f "$TARGET_DIR/isabelle_setup.jar" -e "isabelle.setup.Setup" -C "$TARGET_DIR" isabelle
    rm -rf "$TARGET_DIR/isabelle"

    #$shell ./Admin/build_release
  '';

  installPhase = ''
    tar -xzf dist-Isabelle*/Isabelle_*_*.tar.gz --directory $out
    mv $out/Isabelle_* $out/${dirname}
    contrib_dir=$out/${dirname}/contrib
    rm -r $contrib_dir/jdk-*
    rm -r $contrib_dir/bash_process-*
    rm $contrib_dir/*.tar.gz
    cp -r contrib/jdk-* $contrib_dir/
    cp -r contrib/bash_process-* $contrib_dir/
    cd $out/${dirname}

    export HOME=$TMP
    bin/isabelle build -v -o system_heaps -b HOL
  '';

  desktopItem = makeDesktopItem {
    name = "isabelle";
    exec = "isabelle jedit";
    icon = "isabelle";
    desktopName = "Isabelle";
    comment = meta.description;
    categories = [ "Education" "Science" "Math" ];
  };

  meta = with lib; {
    description = "A generic proof assistant";

    longDescription = ''
      Isabelle is a generic proof assistant.  It allows mathematical formulas
      to be expressed in a formal language and provides tools for proving those
      formulas in a logical calculus.
    '';
    homepage = "https://isabelle.in.tum.de/";
    sourceProvenance = with sourceTypes; [
      fromSource
      binaryNativeCode  # source bundles binary dependencies
    ];
    license = licenses.bsd3;
    maintainers = [ maintainers.jwiegley maintainers.jvanbruegge ];
    platforms = platforms.unix;
  };
} // {
  withComponents = f:
    let
      base = "$out/${isabelle.dirname}";
      components = f isabelle-components;
    in symlinkJoin {
      name = "isabelle-with-components-${isabelle.version}";
      paths = [ isabelle ] ++ components;

      postBuild = ''
        rm $out/bin/*

        cd ${base}
        rm bin/*
        cp ${isabelle}/${isabelle.dirname}/bin/* bin/
        rm etc/components
        cat ${isabelle}/${isabelle.dirname}/etc/components > etc/components

        export HOME=$TMP
        bin/isabelle install $out/bin
        patchShebangs $out/bin
      '' + lib.concatMapStringsSep "\n" (c: ''
        echo contrib/${c.pname}-${c.version} >> ${base}/etc/components
      '') components;
    };
}
