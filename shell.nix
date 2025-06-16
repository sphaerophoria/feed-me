let
  pkgs = import <nixpkgs> { };
in
pkgs.mkShell {
  nativeBuildInputs = with pkgs; [
    zls
    zig
    valgrind
    gdb
    python3
    linuxPackages_latest.perf
    kcov
    nodePackages.typescript-language-server
    vscode-langservers-extracted
    nodePackages.prettier
    nodePackages.jshint
    pyright
  ];
}
