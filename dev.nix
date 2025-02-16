{ pkgs ? import <nixpkgs> { } }:

let
  buildDerivation = name: version: sha256: lib:
    pkgs.stdenv.mkDerivation {
      name = "${name}-${version}";
      src = pkgs.fetchurl {
        url = "http://ftp.debian.org/debian/pool/main/${builtins.substring 0 1 name}/${name}/${name}_${version}_amd64.deb";
        sha256 = sha256;
      };

      buildInputs = [ pkgs.binutils pkgs.gnutar pkgs.pkg-config lib ];
      dontStrip = true; # in order to prevent `set` calls tampering with generated strip script 

      unpackPhase = ''
        #!/bin/bash
        set -euo pipefail

        mkdir -p tmp/
        ar x $src
        mv data.tar.xz tmp/
      '';

      installPhase = ''
        #!/bin/bash
        set -euo pipefail
        
        mkdir -p $out/bin $out/lib
        tar -xf ./tmp/data.tar.xz -C $out
        mv $out/usr/bin/${name} $out/bin/
        cp $(pkg-config --variable=libdir ${lib.pname})/* $out/lib/
        rm -rf $out/usr tmp/
      '';
    };

in
pkgs.mkShell {
  buildInputs = [
    pkgs.curl
    pkgs.git
    pkgs.lune
    (buildDerivation "unzip" "6.0-28" "s9lSnDQ4LMjS5syCmaGFNlBO28KEuRM/++UicEhlBo4=" pkgs.bzip2)
    (buildDerivation "zip" "3.0-14" "0vsh9c5wfbwsx1r1b5mkfxj5vy1xqv0wbj2i93jysyb7x1c3pq8n" pkgs.zlib)
  ];
}

