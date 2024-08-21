let deps = {
      "haskell.nix" = builtins.fetchTarball {
        url = "https://github.com/input-output-hk/haskell.nix/archive/d8c50dcaf3d3d589829ee9be9d5dba8279b8cc59.tar.gz";
        sha256 = "0a5hgryz6nszmy67yf1aks399h2aw0nj845518c4prs5c6ns1z7p";
      };
      patch = pkgs.fetchFromGitHub {
        owner = "ymeister";
        repo = "patch";
        rev = "2170c364450d5827a21dbcd817131d5def6e4767";
        sha256 = "0cnk89h3z0xkfa7jyz9ihycvpa0ak8kyslfl7labkwf6qi3qh80s";
      };
      reflex = pkgs.fetchFromGitHub {
        owner = "ymeister";
        repo = "reflex";
        rev = "844d88d10cbf0db8ad8677a9c72f6a10e811c0f4";
        sha256 = "013iaa4b9d18d8cbszrmp7h153yljsg05b28fblkpyra5ss010qh";
      };
      reflex-dom = pkgs.fetchFromGitHub {
        owner = "ymeister";
        repo = "reflex-dom";
        rev = "546989b6368efd6ecc4f88bcab500b6b6361be28";
        sha256 = "1w6lp9vr1axpdy51ms58av578bqyyz6v64rapi9w5d6pxr1l9kr3";
      };
    };

    haskellNix = import deps."haskell.nix" {};

    # Import nixpkgs and pass the haskell.nix provided nixpkgsArgs
    pkgs = import
      # haskell.nix provides access to the nixpkgs pins which are used by our CI,
      # hence you will be more likely to get cache hits when using these.
      # But you can also just use your own, e.g. '<nixpkgs>'.
      haskellNix.sources.nixpkgs-2405
      # These arguments passed to nixpkgs, include some patches and also
      # the haskell.nix functionality itself as an overlay.
      haskellNix.nixpkgsArgs;

    source-repository-packages = packages:
      builtins.zipAttrsWith
        (k: vs:
          if k == "cabalProjectLocal" then pkgs.lib.strings.concatStringsSep "\n" vs
          else builtins.zipAttrsWith (_: pkgs.lib.lists.last) vs
        )
        (pkgs.lib.lists.forEach packages (p:
          let input = builtins.unsafeDiscardStringContext p;
          in {
            inputMap."${input}" = { name = builtins.baseNameOf p; outPath = p; rev = "HEAD"; };
            cabalProjectLocal = ''
              source-repository-package
                type: git
                location: ${input}
                tag: HEAD
            '';
          }
        ));

    import-cabal-project = dir: file:
      let path = dir + "/${file}";
          content = ''
            -- ${path}
            ${builtins.readFile path}
          '';
          lines = pkgs.lib.strings.splitString "\n" content;
      in pkgs.lib.strings.concatStringsSep "\n" (
          pkgs.lib.lists.forEach lines (line:
            if pkgs.lib.strings.hasPrefix "if !arch(javascript)" line
              then "if false"
              else
                if pkgs.lib.strings.hasPrefix "import: " line
                then import-cabal-project dir (pkgs.lib.strings.removePrefix "import: " line)
                else line
          )
      );

    haskellDeps = source-repository-packages [
      (deps.reflex-dom + "/reflex-dom")
      (deps.reflex-dom + "/reflex-dom-core")
      deps.reflex
      deps.patch
    ];

    project = pkgs: pkgs.haskell-nix.project {
      src = ./.;

      inherit (haskellDeps) inputMap;
      cabalProject = import-cabal-project ./. "cabal.project";
      cabalProjectLocal = ''
        ${import-cabal-project deps.reflex-dom "cabal.dependencies.project"}

        ${haskellDeps.cabalProjectLocal}

        if arch(javascript)
          extra-packages: ghci
      '';

      shell.withHaddock = if pkgs.stdenv.hostPlatform.isGhcjs then false else true;

      modules = [({ pkgs, lib, ... }: {
        packages.reflex-dom-core.components.tests = {
          gc.buildable = lib.mkForce false;
          hydration.buildable = lib.mkForce false;
          #gc.build-tools = [ pkgs.chromium ];
          #hydration.build-tools = [ pkgs.chromium ];
        };
      })];

      compiler-nix-name = "ghc910";
    };

in {
  ghc = project pkgs;
  ghc-js = project pkgs.pkgsCross.ghcjs;
}
