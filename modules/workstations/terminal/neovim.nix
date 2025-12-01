{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    neovim

    ripgrep # Needed for telescope grep
    # -- LSP (Language server protocols) --

    ## Lua
    lua-language-server
    stylua

    ## Nix
    nixd
    nixfmt-rfc-style

    ## HTML + Styling
    emmet-ls
    tailwindcss-language-server

    ## PHP
    nodePackages.intelephense

    ## Golang
    gopls

    ## Typescript
    typescript-language-server

    ## SQL
    sqls
  ];
}
