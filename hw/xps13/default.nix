{ config, pkgs, lib, ... }: with lib; let
  cfg = config.home.hw.xps13;
in {
  key = "Dell XPS 13 (9343)";
  imports = [
    ../intel
    ../../cfg/laptop
  ];

  config = {
    home.profileSettings.intel.graphics.enable = true;

    home-manager.users.arc = { ... }: {
      imports = [ ./home.nix ];
    };

    boot = {
      kernel = {
        arch = "broadwell";
      };
      initrd.availableKernelModules = [
        "xhci_pci" "ehci_pci" "ahci" "sd_mod" "rtsx_pci_sdmmc"
      ];
    };

    # boot.kernelParams = ["i915.enable_execlists=0"]; # try if getting freezes
    # boot.kernelParams = ["i915.enable_psr=1"]; # try for powersaving
    # boot.kernelParams = ["intel_idle.max_cstate=1"]; # try to fix baytrail freeze?

    hardware.display = {
      enable = true;
      monitors = {
        internal = {
          output = "eDP1";
          xserver.sectionName = "Monitor[0]";
          primary = true;
          width = 1920;
          height = 1080;
          size = {
            diagonal = 13.3;
            width = 292;
            height = 165;
          };
        };
      };
      dpi = config.hardware.display.monitors.internal.dpi.out.dpi;
    };

    services.xserver = {
      xrandrHeads = [{
        output = "eDP1";
        primary = true;
        monitorConfig = ''
          DisplaySize ${toString (292 * config.hardware.display.dpiScale)} ${toString (165 * config.hardware.display.dpiScale)} # millimeters
        '';
      }];
      videoDrivers = ["intel"];
      deviceSection = ''
        Option "TearFree" "true"
        #Option "AccelMethod" "uxa"
      '';
      #videoDrivers = ["modesetting"]; # TODO: modern suggestion is to use this instead?
      #useGlamor = true; # TODO: good idea or no? alternative 2d accel to uxa/sna/etc

      synaptics = {
        enable = true;
        accelFactor = "0.275";
        minSpeed = "0.30";
        maxSpeed = "1.30";
        palmDetect = true; # seems to work on ps/2 but not i2c
        palmMinWidth = 8;
        palmMinZ = 100;
        twoFingerScroll = true;
        scrollDelta = -40;
        tapButtons = true;
        fingersMap = [1 3 2];

        # Sets up soft buttons at the bottom
        # First 40% - Left Button
        # Middle 20% - Middle Button
        # Right 40% - Right Button
        additionalOptions = ''
          Option "ClickPad" "true"
          Option "SoftButtonAreas" "60% 0 82% 0 40% 59% 82% 0"
        '';
      };
    };

    sound.extraConfig = ''
      defaults.ctl.!card PCH
      defaults.pcm.!card PCH
    '';
  };
}
