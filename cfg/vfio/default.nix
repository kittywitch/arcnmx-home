{ config, lib, pkgs, ... }: with lib; {
  imports = [
    ./qemu
    ./io.nix
    ./scripts
  ];

  options = {
    hardware.vfio = {
      acsOverride = mkEnableOption "ACS IOMMU Override";
      i915arbiter = mkEnableOption "i915 VGA Arbiter";
    };
  };

  config = {
    home-manager.users.arc.imports = [ ./home.nix ];
    boot = {
      initrd.kernelModules = ["vfio" "vfio_iommu_type1" "vfio_pci" "vfio_virqfd"];
      modprobe.modules = {
        kvm.options = {
          ignore_msrs = mkDefault true;
          report_ignored_msrs = mkDefault false;
        };
        vfio-pci.options = {
          disable_vga = mkDefault false;
        };
        kvmfr.options = {
          static_size_mb = "64";
        };
        xpad.blacklist = true;
      };
      extraModulePackages = with config.boot.kernelPackages; [ forcefully-remove-bootfb kvmfr ];
      kernel.extraPatches = with pkgs.kernelPatches; [
        (mkIf config.hardware.vfio.i915arbiter i915-vga-arbiter)
        (mkIf config.hardware.vfio.acsOverride acs-override)
      ];
    };
    environment.etc."qemu/bridge.conf".text = "allow br";
    security.pam.loginLimits = [
      {
        domain = "@kvm";
        type = "-";
        item = "memlock";
        value = "unlimited";
      }
    ];
    security.wrappers = {
      # TODO: remove this, keep the VM network config entirely within the system nixos config instead?
      qemu-bridge-helper = {
        source = "${pkgs.qemu-vfio or pkgs.qemu}/libexec/qemu-bridge-helper";
        capabilities = "cap_net_admin+ep";
        owner = "root";
        group = "root";
      };
    };
  };
}
