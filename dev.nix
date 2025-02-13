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

  shellHook = ''
    export SHELL=${pkgs.fish}/bin/fish
    exec ${pkgs.fish}/bin/fish

    # Use a default fish config if not already setup
    if [ ! -f ~/.config/fish/config.fish ]; then
      ## FISH INIT START ##
      # Don't do anything if not running interactively
      if not status --is-interactive
          return
      end

      # Set history options
      set -g fish_history_ignore_dups 1  # Don't put duplicate lines in history
      set -g fish_history_ignore_space 1 # Don't put lines starting with space in history
      set -g fish_history_size 2000      # Set history size
      set -g fish_save_history 1         # Append to the history file

      # Set the terminal title if in xterm or rxvt
      if test "$TERM" = "xterm" -o "$TERM" = "rxvt"
          function fish_title
              echo -ne "\033]0;$USER@$HOSTNAME: $PWD\007"
          end
      end

      # Enable color support for ls and set aliases
      if test -x /usr/bin/dircolors
          if test -r ~/.dircolors
              set -l dircolors_output (dircolors -b ~/.dircolors)
          else
              set -l dircolors_output (dircolors -b)
          end
          # Now, set the environment variables based on the output
          for line in $dircolors_output
              set -gx $line
          end
      end
      ## FISH INIT END ##
    fi

    set PATH "$PATH:$HOME/.pesde/bin"
  '';
}

