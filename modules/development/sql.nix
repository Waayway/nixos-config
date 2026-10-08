{
  pkgs,
  lib,
  hostPlatform,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    sql-studio
  ];
}
// lib.optionalAttrs hostPlatform.isDarwin {
  # Local Postgres for development (brew services keeps it running).
  homebrew.brews = [
    "postgresql@16"
    "pgvector"
  ];
}
