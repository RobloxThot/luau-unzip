{ pkgs ? import <nixpkgs> { } }:

pkgs.mkShell {
  buildInputs = [
    pkgs.curl
    pkgs.git
    pkgs.lune
    (
      let version = "6.0-28"; in pkgs.stdenv.mkDerivation {
        name = "unzip-${version}";
        src = pkgs.fetchurl {
          url = "http://ftp.debian.org/debian/pool/main/u/unzip/unzip_${version}_amd64.deb";
          sha256 = "13h6cm4708p5zczi7fc4qbdlwl1nhnhrk0ncwv9chb1q6jf55ndk";
        };

        buildInputs = [ pkgs.binutils pkgs.gnutar pkgs.bzip2 pkgs.pkg-config ];

        unpackPhase = ''
          mkdir -p tmp/
          ar x $src
          mv data.tar.xz tmp/
        '';

        installPhase = ''
          mkdir -p $out/bin $out/lib
          tar -xf ./tmp/data.tar.xz -C $out
          mv $out/usr/bin/unzip $out/bin/
          cp $(pkg-config --variable=libdir bzip2)/libbz2.so.1.0.8 $out/lib/libbz2.so.1.0
          rm -rf $out/usr tmp/
        '';
      }
    )
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
  '';
}

