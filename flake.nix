{
  description = "flake for packaging portable-nvim-config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?ref=nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    nixpkgs,
    flake-utils,
    ...
  }: let
    supportedSystems = let
      inherit (flake-utils.lib) system;
    in [
      system.aarch64-linux
      system.aarch64-darwin
      system.x86_64-linux
    ];
  in
    flake-utils.lib.eachSystem supportedSystems (system: let
      pkgs = import nixpkgs {inherit system;};
    in {
      devShell =
        pkgs.mkShell
        {
          packages = with pkgs; [
            zig_0_14
            neovim
            (pkgs.writeShellScriptBin "tvim" ''
                export XDG_CONFIG_HOME=$PWD/..
                export NVIM_APPNAME=$(${pkgs.coreutils}/bin/basename $PWD)
		export PATH=$PWD/zig-out/bin:$PATH
                nvim -u init.lua $@
            '')
            (pkgs.writeShellScriptBin "build" ''
	    	zig build -Dbuild_nvim -Dtarget=x86_64-linux-musl
            '')
          ];
        };
    });
}
