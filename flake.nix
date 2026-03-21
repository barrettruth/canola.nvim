{
  description = "canola.nvim — refined fork of oil.nvim";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    systems.url = "github:nix-systems/default";
    vimdoc-language-server.url = "github:barrettruth/vimdoc-language-server";
  };

  outputs =
    {
      nixpkgs,
      systems,
      vimdoc-language-server,
      ...
    }:
    let
      forEachSystem =
        f: nixpkgs.lib.genAttrs (import systems) (system: f nixpkgs.legacyPackages.${system});
    in
    {
      formatter = forEachSystem (pkgs: pkgs.nixfmt-tree);

      devShells = forEachSystem (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.prettier
            pkgs.stylua
            pkgs.selene
            vimdoc-language-server.packages.${pkgs.system}.default
            (pkgs.luajit.withPackages (ps: [
              ps.busted
              ps.nlua
            ]))
          ];
        };

        ci = pkgs.mkShell {
          packages = [
            pkgs.prettier
            pkgs.neovim
            pkgs.stylua
            pkgs.selene
            vimdoc-language-server.packages.${pkgs.system}.default
            (pkgs.luajit.withPackages (ps: [
              ps.busted
              ps.nlua
            ]))
          ];
        };
      });
    };
}
