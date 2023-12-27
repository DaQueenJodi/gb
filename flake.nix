{
  inputs = rec {
    nixpkgs.url = "github:NixOS/nixpkgs/release-23.05";
    zig-overlay.url = "github:mitchellh/zig-overlay";
    zls-overlay.url = "github:zigtools/zls/5c0bebe";
  };
  outputs = inputs @ {
    self,
    nixpkgs,
    ...
  }:
  let
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
    zig = inputs.zig-overlay.packages.x86_64-linux.master-2023-12-24;
    zls = inputs.zls-overlay.packages.x86_64-linux.zls.overrideAttrs (old: {
            nativeBuildInputs = [ zig ];
          });
  in
  {
    devShells.x86_64-linux.default = pkgs.mkShell {
      packages = with pkgs; with xorg; [
        zls
        zig
        raylib
        gdb
      ];
    };
  };
}
