{ modulesPath, ... }: {
  imports = [
    ./deploy-switch.nix
    ./deploy-personal.nix
    ./deploy-tf.nix
    ./deploy-domains.nix
    ./matrix-synapse-bridges.nix
    ./secure-boot.nix
    ./nixbld.nix
    ./home.nix
  ];
}
