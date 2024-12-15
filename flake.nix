{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, uv2nix, pyproject-nix, pyproject-build-systems, flake-utils }: flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = import nixpkgs {
        inherit system;
      };
      workspace = uv2nix.lib.workspace.loadWorkspace {
        workspaceRoot = ./.;
      };
      overlay = workspace.mkPyprojectOverlay {
        sourcePreference = "wheel";
      };

      pyprojectOverrides = _final: prev: {
        pyqt6 = prev.pyqt6.overrideAttrs (old: {
          dontWrapQtApps = true;
          buildInputs = (old.buildInputs or [ ]) ++ [
            pkgs.kdePackages.qtbase
            pkgs.kdePackages.qttools
            pkgs.kdePackages.qtsvg
            pkgs.kdePackages.qt3d
            pkgs.kdePackages.qtwebview
            pkgs.kdePackages.qtconnectivity
            pkgs.kdePackages.qtsensors
            pkgs.kdePackages.qtremoteobjects
            pkgs.kdePackages.qtwayland
            pkgs.xorg.libxcb
            pkgs.xorg.libXcursor
          ];
        });
        pyqt6-qt6 = prev.pyqt6-qt6.overrideAttrs (old: {
          dontWrapQtApps = true;
          autoPatchelfIgnoreMissingDeps = [
            "libmimerapi.so"
            "libmysqlclient.so.21"
            "libQt63DQuickScene3D.so.6"
            "libQt6EglFsKmsGbmSupport.so.6"
          ];
          buildInputs = (old.buildInputs or [ ]) ++ [
            pkgs.kdePackages.qtbase
            pkgs.kdePackages.qttools
            pkgs.kdePackages.qtsvg
            pkgs.kdePackages.qt3d
            pkgs.kdePackages.qtwebview
            pkgs.kdePackages.qtconnectivity
            pkgs.kdePackages.qtsensors
            pkgs.kdePackages.qtremoteobjects
            pkgs.cairo
            pkgs.pcsclite
            pkgs.gtk3
            pkgs.speechd
            pkgs.kdePackages.qtquick3d
            pkgs.kdePackages.qtquicktimeline
            pkgs.kdePackages.qtwayland
          ];
        });
        pyqt6-webengine = prev.pyqt6-webengine.overrideAttrs (old: {
          dontWrapQtApps = true;
          buildInputs = (old.buildInputs or [ ]) ++ [
            pkgs.kdePackages.qtwebengine
          ];
        });
        pyqt6-webengine-qt6 = prev.pyqt6-webengine-qt6.overrideAttrs (old: {
          dontWrapQtApps = true;
          buildInputs = (old.buildInputs or [ ]) ++ [
            pkgs.kdePackages.qtwebengine
          ];
        });
      };

      python = pkgs.python312;

      pythonSet = (pkgs.callPackage pyproject-nix.build.packages {
        inherit python;
      }).overrideScope (
        nixpkgs.lib.composeManyExtensions [
          pyproject-build-systems.overlays.default
          overlay
          pyprojectOverrides
        ]
      );
    in
    {
      packages.default =
        let
          virtualEnv = pythonSet.mkVirtualEnv "openconnect-sso" workspace.deps.default;
        in
        pkgs.stdenv.mkDerivation {
          name = "openconnect-sso";
          inherit (pythonSet.openconnect-sso) src;

          dontConfigure = true;
          dontBuild = true;

          buildInputs = [
            pkgs.kdePackages.qtbase
          ];

          nativeBuildInputs = [
            virtualEnv
            pkgs.kdePackages.wrapQtAppsHook
          ];

          installPhase = ''
            mkdir -p $out/bin
            cat <<- BASH > $out/bin/openconnect-sso
            #!/usr/bin/env bash
            export PYTHONPATH=${virtualEnv}/lib/python3.12/site-packages
            ${pythonSet.openconnect-sso}/bin/openconnect-sso "$@"
            BASH
            chmod a+x $out/bin/openconnect-sso
          '';
        };

      devShell =
        let
          # Create an overlay enabling editable mode for all local dependencies.
          editableOverlay = workspace.mkEditablePyprojectOverlay {
            # Use environment variable
            root = "$REPO_ROOT";
            # Optional: Only enable editable for these packages
            # members = [ "hello-world" ];
          };

          # Override previous set with our overrideable overlay.
          editablePythonSet = pythonSet.overrideScope editableOverlay;

          # Build virtual environment, with local packages being editable.
          #
          # Enable all optional dependencies for development.
          virtualenv = editablePythonSet.mkVirtualEnv "openconnect-sso-dev-env" workspace.deps.all;

        in
        pkgs.mkShell {
          packages = [
            pkgs.python3
            pkgs.uv
            virtualenv
            pkgs.openconnect
          ];
          shellHook = ''
            # Undo dependency propagation by nixpkgs.
            unset PYTHONPATH

            # Don't create venv using uv
            export UV_NO_SYNC=1

            # Prevent uv from downloading managed Python's
            export UV_PYTHON_DOWNLOADS=never

            # Get repository root using git. This is expanded at runtime by the editable `.pth` machinery.
            export REPO_ROOT=$(git rev-parse --show-toplevel)
          '';
        };

    });
}
