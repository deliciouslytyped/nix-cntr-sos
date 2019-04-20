#TODO debug vm? https://github.com/Mic92/nixos-shell
#NOTE huh this isnt bad if you have mouse mode stuff working (with nested tmux)
#TODO doesnt fail if no running cntr
#TODO only one cntr will work with this impl, cntr selector
{pkgs ? import (builtins.fetchTarball {
  name = "fresh";
  url = https://github.com/NixOS/nixpkgs-channels/archive/nixos-19.03.tar.gz;
  sha256 = "1d59i55qwqd76n2d0hr1si26q333ydizkd91h8lfczb00xnr5pqn"; }) {}}: 

with { inherit (pkgs) cntr socat mkShell breakpointHook stdenv jedit jdk11 runCommand tmuxinator tmux writeText bashInteractive writeShellScriptBin fetchFromGitHub rustPlatform; };

let
  #TODO Man how the hell does this rust stuff works, cant figure out the damn override
  cntr' = rustPlatform.buildRustPackage rec {
    name = "cntr-${version}";
    version = "socket-proxy";

    src = fetchFromGitHub {
      owner = "Mic92";
      repo = "cntr";
      rev = "99c6460471df041af6b1d551b2440f5afcddba80";
      sha256 = "0qcsqiqbpicmb78pp8rbjq91dy6vp2fs5rng2pza8jvwayfybgla";
      };

    cargoSha256 = "0wwza4lhdsq5yy4wz03zhgp592dwcxfiahixa4n32dd2yq0fgg4m";
    };

  jedit' = (jedit.override (a: { jdk = jdk11 // { jre = jdk11; }; })).overrideAttrs (a: { #haxxx
    installPhase = (builtins.replaceStrings ["/jre"] [""] a.installPhase) + ''
      set -x
      sed -i "s|\''${JAVA}\"|\''${JAVA}\" -Xrunjdwp:transport=dt_socket,address=9000,server=y,suspend=y|g" "$out"/bin/jedit
      set +x
      '';
    });

  toDebug = runCommand "java-debugme" { buildInputs = [ pkgs.procps jedit' breakpointHook ]; } ''
    jedit &
    exit 1
    ''; 
in

#TODO make a tmux workspace generator
#workspace
let
  tmuxSocket = "./tmuxsocket";

  defaultCommand = writeShellScriptBin "defaultCommand" ''exec nix-shell -E "(import ${builtins.toString ./test.nix} {}).shell {}"'';

  #TODO a new 0: session gets started for some reason and ive no idea why
  #TODO better layout? i wish you could specify more than one layout -_-
  tmuxinator-config = writeText "tmuxinator-config" ''
    name: socat-cntr
    socket_path: '${tmuxSocket}'

    pre: 'tmux -S "${tmuxSocket}" new-session -d -x 255 -y 75; tmux -S "${tmuxSocket}" set-option -g default-command "bash --rcfile ${defaultCommand}/bin/defaultCommand"'
    attach: false

    windows:
      - socatcntr:
          layout: even-vertical
          panes:
            - 'exec nix-shell -E "(import ${builtins.toString ./test.nix} {}).shell {command=\"failBuild\";}"'
            - 'exec nix-shell -E "(import ${builtins.toString ./test.nix} {}).shell {command=\"cntrTop\";}"'
            - 'exec nix-shell -E "(import ${builtins.toString ./test.nix} {}).shell {command=\"pcWatch\";}"'
            - 'exec nix-shell -E "(import ${builtins.toString ./test.nix} {}).shell {command=\"cntrGet\";}"'
    '';
in {
  inherit toDebug;

  shell = {command ? ""}: mkShell {
    name = "socat-cntr-tester";
    buildInputs = [ socat cntr' jdk11 tmux tmuxinator bashInteractive ]; #jdk provides jdb, a cli java debugger

    shellHook = ''
      export SHELL="${bashInteractive}"/bin/bash
      #export HISTFILE="$(mktemp --suffix=-socat-cntr)"
      export HISTFILE="${(builtins.toString ./.) + "/histfile"}"

      failBuild () {
        #nix-build $ {toDebug.drvPath} #TODO causes it to be evaled for some reason so we have to return an attrset and do the other thing instead
        nix-build -E "(import ${builtins.toString ./test.nix} {}).toDebug"
        }
 
      reloadShell () {
        exec nix-shell -E "(import ${builtins.toString ./test.nix} {}).shell {}"
        }

      cntrGet () { #TODO maybe this isn't the best way to do this
        #Check if file is empty in a loop https://stackoverflow.com/questions/46928291/bash-how-to-check-if-file-is-empty-in-a-loop
        rm ${(builtins.toString ./.)}/cntrpath
        echo Waiting for cntr...
        while ! [ -s ${(builtins.toString ./.)}/cntrpath ]; do 
          sleep 0.5;
          pgrep -a -f "cntr attach" | grep -Po "(?<=command ).*(?=')" > ${(builtins.toString ./.)}/cntrpath
        done
        echo have cntr!
        }

      _cntrRun () {
        cntrGet
        command="$1"
        set -x
        sudo cntr attach -t command $(cat ${(builtins.toString ./.)}/cntrpath) "$@"
        set +x
        }

      cntrRun () {
        _cntrRun -- "$@"
        }

      cntrSh (){ #TODO this doesnt really do much..
        cntrRun sh -c "$@"
        }

      cntrExec () {
        cntrRun cntr exec -- "$@"
        }

      cntrExecSh () {
        cntrRun cntr exec -- sh -c "$@"
        }

      test1 () {
        cntr --help
        }

      killAll () {
        true
        }

      #proc socat
      pso () {
        true
        }

      #proc cntr
      pc () { #TODO not necessarily reliable but it works
        #pgrep -a -f cntr | grep -Ev "nix-build|pgrep|tmux|sh -c echo"
        ps $(pgrep -f cntr) | grep -Ev "nix-build|pgrep|tmux|sh -c echo"
        }

      #TODO hide boring processes
      pcWatch () {
        (export -f pc; watch pc)
        }

      cntrTop () {
        cntrRun watch -n1 -c ps aux
        }

      seppuku () {
        tmux -S '${tmuxSocket}' kill-server
        }

      if [ -z ''${INENV} ]; then #If I'm not a tmux shell, start tmux
        export INENV=hi
        rm ${(builtins.toString ./.)}/cntrpath
        tmuxinator start -p ${tmuxinator-config}
        tmux -S '${tmuxSocket}' attach -t socat-cntr
        seppuku #TODO doesnt work when ^C
        exit 0
      fi
      ${command}
      '';
    };
  }
