{ lib, config, pkgs, ... }: with lib; let
  cfg = config.hardware.vfio;
  nixosConfig = config;
  systemdUnits =
    mapAttrsToList (_: dev: dev.systemd) cfg.devices
    ++ mapAttrsToList (_: disk: disk.systemd) cfg.disks.mapped
    ++ mapAttrsToList (_: disk: disk.systemd) cfg.disks.cow
    ++ mapAttrsToList (_: machine: machine.scream.systemd) (filterAttrs (_: m: m.scream.systemd.enable) cfg.qemu.machines)
    ++ mapAttrsToList (_: machine: machine.systemd) (filterAttrs (_: m: m.enable && m.systemd.enable) cfg.qemu.machines);
  applyPermission = { permission, path }: let
    owner = optionalString (permission.owner != null) permission.owner;
    group = optionalString (permission.group != null) permission.group;
    chown = ''chown ${owner}:${group} ${path}'';
    chmod = ''chmod ${permission.mode} ${path}'';
    cmds = optional (permission.owner != null || permission.group != null) chown
    ++ optional (permission.mode != null) chmod;
  in concatStringsSep "\n" cmds;
  polkitPermissions = systemd: mkIf systemd.enable {
    ${systemd.polkit.user} = {
      systemd.units = [ systemd.id ];
    };
  };
  systemdService = systemd: {
    ${systemd.name} = unmerged.merge systemd.unit;
  };
  udevPermission = permission: let
    assignments = optional (permission.owner != null) ''OWNER="${permission.owner}"''
    ++ optional (permission.group != null) ''GROUP="${permission.group}"''
    ++ optional (permission.mode != null) ''MODE="${permission.mode}"'';
  in concatStringsSep ", " assignments;
  permissionType = types.submodule ({ config, ... }: {
    options = {
      owner = mkOption {
        type = with types; nullOr str;
        default = null;
      };
      group = mkOption {
        type = with types; nullOr str;
        default = null;
      };
      mode = mkOption {
        type = with types; nullOr str;
        default = null;
      };
    };
  });
  systemdModule = { config, ... }: {
    options = {
      enable = mkEnableOption "systemd service" // {
        default = true;
      };
      name = mkOption {
        type = types.str;
      };
      id = mkOption {
        type = types.str;
        default = config.name + ".service";
      };
      depends = mkOption {
        type = with types; listOf str;
        default = [ ];
      };
      wants = mkOption {
        type = with types; listOf str;
        default = [ ];
      };
      user = mkOption {
        type = with types; nullOr str;
        default = null;
      };
      polkit.user = mkOption {
        type = with types; nullOr str;
        default = config.user;
      };
      type = mkOption {
        type = types.str;
        default = "oneshot";
      };
      script = mkOption {
        type = types.lines;
        default = "";
      };
      unit = mkOption {
        type = unmerged.type;
      };
    };
    config = {
      unit = {
        inherit (config) enable;
        path = [ pkgs.coreutils ];
        after = mkIf (config.depends != [ ] || config.wants != [ ]) (config.depends ++ config.wants);
        requires = mkIf (config.depends != [ ]) config.depends;
        wants = mkIf (config.wants != [ ]) config.wants;
        script = mkIf (config.script != "") config.script;
        restartIfChanged = mkDefault false;
        serviceConfig = {
          User = mkIf (config.user != null) (mkDefault config.user);
          Type = mkDefault config.type;
          RemainAfterExit = mkIf (config.type == "oneshot") (mkDefault true);
        };
      };
    };
  };
  mapDiskModule = { name, config, ... }: {
    options = {
      name = mkOption {
        type = types.str;
        default = name;
      };
      path = mkOption {
        type = types.path;
      };
      source = mkOption {
        type = types.path;
      };
      permission = mkOption {
        type = permissionType;
        default = { };
      };
      mbr = {
        id = mkOption {
          type = types.strMatching "[0-9a-f]{8}";
          default = substring 8 8 (builtins.hashString "sha256" config.name);
        };
        partType = mkOption {
          type = types.int;
          default = 7; # NTFS
        };
      };
      systemd = mkOption {
        type = types.submodule systemdModule;
        default = { };
      };
    };
    config = {
      path = "/dev/mapper/${config.name}";
      systemd = {
        name = "vfio-mapdisk-${config.name}";
        polkit.user = config.permission.owner;
        script = ''
          ${nixosConfig.lib.arc-vfio.map-disk}/bin/map-disk ${config.source} ${config.name} ${config.mbr.id} ${toString config.mbr.partType}
          ${applyPermission {
            inherit (config) permission path;
          }}
        '';
        unit.serviceConfig = {
          RuntimeDirectory = config.systemd.name;
          ExecStop = "${nixosConfig.lib.arc-vfio.map-disk}/bin/map-disk STOP";
        };
      };
    };
  };
  snapshotDiskModule = { name, config, ... }: {
    options = {
      name = mkOption {
        type = types.str;
        default = name;
      };
      path = mkOption {
        type = types.path;
      };
      source = mkOption {
        type = types.path;
      };
      permission = mkOption {
        type = permissionType;
        default = { };
      };
      mode = mkOption {
        type = types.enum [ "P" "N" ];
        default = "N";
        description = "(P)ersistent snapshot?";
      };
      storage = mkOption {
        type = types.path;
      };
      sizeMB = mkOption {
        type = types.int;
        default = 1024 * 8;
      };
      systemd = mkOption {
        type = types.submodule systemdModule;
        default = { };
      };
    };
    config = {
      path = "/dev/mapper/${config.name}";
      storage = mkIf (config.mode == "N") (mkOptionDefault "/tmp/qemu-cow-${config.name}");
      systemd = {
        name = "vfio-cowdisk-${config.name}";
        polkit.user = config.permission.owner;
        script = ''
          ${nixosConfig.lib.arc-vfio.cow-disk}/bin/cow-disk ${config.source} ${config.name} ${config.mode} ${config.storage} ${toString config.sizeMB}
          ${applyPermission {
            inherit (config) permission path;
          }}
        '';
        unit.serviceConfig = {
          RuntimeDirectory = config.systemd.name;
          ExecStop = "${nixosConfig.lib.arc-vfio.cow-disk}/bin/cow-disk STOP";
        };
      };
    };
  };
  vfioDeviceModule = { config, name, ... }: {
    options = {
      enable = mkEnableOption "VFIO device";
      vendor = mkOption {
        type = types.strMatching "[0-9a-f]{4}";
      };
      product = mkOption {
        type = types.strMatching "[0-9a-f]{4}";
      };
      unbindVts = mkEnableOption "unbind-vts";
      host = mkOption {
        type = with types; nullOr str;
        default = null;
        example = "02:00.0";
      };
      systemd = mkOption {
        type = types.submodule systemdModule;
        default = { };
      };
    };
    config = {
      systemd = {
        name = "vfio-reserve-${name}";
        script = mkMerge (
          optional config.unbindVts "${nixosConfig.lib.arc-vfio.unbind-vts}/bin/unbind-vts"
          ++ singleton "${nixosConfig.lib.arc-vfio.reserve-pci}/bin/reserve-pci ${config.vendor}:${config.product}"
        );
        unit.serviceConfig = {
          RuntimeDirectory = config.systemd.name;
          ExecStop = "${nixosConfig.lib.arc-vfio.reserve-pci}/bin/reserve-pci STOP";
        };
      };
    };
  };
  usbDeviceModule = { config, name, ... }: {
    options = {
      enable = mkEnableOption "USB device" // {
        default = true;
      };
      name = mkOption {
        type = types.str;
        default = name;
      };
      vendor = mkOption {
        type = types.strMatching "[0-9a-f]{4}";
      };
      product = mkOption {
        type = types.strMatching "[0-9a-f]{4}";
      };
      permission = mkOption {
        type = permissionType;
        default = { };
      };
      udev.conditions = mkOption {
        type = with types; listOf str;
      };
      out = {
        udevRule = mkOption {
          type = types.str;
        };
      };
    };
    config = {
      permission.group = mkDefault "plugdev";
      udev.conditions = mkBefore [
        ''SUBSYSTEM=="usb"''
        ''ATTR{idVendor}=="${config.vendor}"''
        ''ATTR{idProduct}=="${config.product}"''
      ];
      out.udevRule = let
        assignments = udevPermission config.permission;
      in optionalString (assignments != "")
        ''${concatStringsSep ", " config.udev.conditions}, ${assignments}'';
    };
  };
  machineModule = { config, name, ... }: {
    options = {
      systemd = mkOption {
        type = types.submodule systemdModule;
        default = { };
      };
      scream = {
        playback = {
          user = mkOption {
            type = with types; nullOr str;
            default = null;
          };
          pulse = {
            server = mkOption {
              type = with types; nullOr str;
              default = null;
            };
          };
        };
        systemd = mkOption {
          type = types.submodule systemdModule;
          default = { };
        };
      };
    };
    config = let
      otherMachines = filterAttrs (n: _: n != name) cfg.qemu.machines;
      sameMachines = filterAttrs (_: machine: machine.systemd.enable && machine.name == config.name) otherMachines;
    in {
      systemd = {
        name = "vm-${name}";
        user = mkDefault config.state.owner;
        script = getExe config.exec.package;
        type = "exec";
        unit = {
          conflicts = mapAttrsToList (_: machine: machine.systemd.id) sameMachines;
          serviceConfig = {
            PIDFile = mkIf (config.exec.pidfile != null) config.exec.pidfile;
            StateDirectory = mkIf (hasPrefix "/var/lib/" config.state.path) (removePrefix "/var/lib/" config.state.path);
            RuntimeDirectory = mkIf (hasPrefix "/run/" config.state.runtimePath) (removePrefix "/run/" config.state.runtimePath);
            OOMScoreAdjust = -150;
          };
        };
      };
      scream = {
        playback.pulse.server = mkIf (config.scream.playback.user != null)
          (mkDefault "unix:/run/user/${toString nixosConfig.users.users.${config.scream.playback.user}.uid}/pulse/native");
        systemd = {
          name = "vm-${name}-scream";
          enable = config.scream.enable;
          type = "exec";
          polkit.user = mkDefault config.systemd.polkit.user;
          unit = {
            wantedBy = mkIf (config.scream.mode == "ivshmem") [ config.systemd.id ];
            conflicts = mapAttrsToList (_: machine: machine.scream.systemd.id) (filterAttrs (_: machine: machine.scream.systemd.enable) sameMachines);
            unitConfig = {
              ConditionPathExists = mkIf (
                config.scream.playback.backend == "pulse"
                && config.scream.playback.pulse.server != null
                && hasPrefix "unix:" config.scream.playback.pulse.server
              ) [
                (removePrefix "unix:" config.scream.playback.pulse.server)
              ];
            };
            serviceConfig = {
              Environment = mkMerge [
                (mkIf (config.scream.playback.backend == "pulse" && config.scream.playback.pulse.server != null) [
                  "PULSE_SERVER=${config.scream.playback.pulse.server}"
                ])
                (mkIf (config.scream.playback.backend == "pulse" && config.scream.playback.user != null) [
                  "PULSE_COOKIE=${nixosConfig.users.users.${config.scream.playback.user}.home}/.config/pulse/cookie"
                ])
              ];
              ExecStart = config.scream.playback.cli.command;
            };
          };
        };
      };
      exec = {
        preExec = mkMerge [
          (mkIf (config.systemd.depends != [ ]) ''
            systemctl start ${toString config.systemd.depends}
          '')
          (mkIf (config.systemd.wants != [ ]) ''
            systemctl start ${toString config.systemd.wants} || true
          '')
        ];
      };
    };
  };
in {
  options.hardware.vfio = {
    devices = mkOption {
      type = with types; attrsOf (submodule vfioDeviceModule);
      default = { };
    };
    usb = {
      devices = mkOption {
        type = with types; attrsOf (submodule usbDeviceModule);
        default = { };
      };
    };
    disks = {
      mapped = mkOption {
        type = with types; attrsOf (submodule mapDiskModule);
        default = { };
      };
      cow = mkOption {
        type = with types; attrsOf (submodule snapshotDiskModule);
        default = { };
      };
    };
    qemu.machines = mkOption {
      type = with types; attrsOf (submoduleWith {
        modules = [ machineModule ];
      });
    };
  };
  config = {
    systemd.services = mkMerge (map systemdService systemdUnits);
    security.polkit.users = mkMerge (map polkitPermissions systemdUnits);
    systemd.tmpfiles.rules = mkMerge (mapAttrsToList (_: machine: [
      "d ${machine.state.path} 0750 ${machine.state.owner} kvm -"
      "d ${machine.state.runtimePath} 0750 ${machine.state.owner} kvm -"
    ]) (filterAttrs (_: m: m.enable) cfg.qemu.machines));
    services.udev.extraRules = mkMerge (mapAttrsToList (_: usb: usb.out.udevRule) (filterAttrs (_: usb: usb.enable) cfg.usb.devices));
    boot.modprobe.modules = {
      vfio-pci = let
        vfio-pci-ids = mapAttrsToList (_: dev:
          "${dev.vendor}:${dev.product}"
        ) (filterAttrs (_: dev: dev.enable) cfg.devices);
      in mkIf (vfio-pci-ids != [ ]) {
        options.ids = concatStringsSep "," vfio-pci-ids;
      };
    };
  };
}
