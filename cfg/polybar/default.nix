{ base16, nixosConfig, config, pkgs, lib, ... } @ args: with lib; {
  services.polybar = {
    enable = true;
    script = let
      xrandr = filter: "${pkgs.xorg.xrandr}/bin/xrandr -q | ${pkgs.gnugrep}/bin/grep -F ' ${filter}' | ${pkgs.coreutils}/bin/cut -d' ' -f1";
    in mkIf config.xsession.enable ''
      primary=$(${xrandr "connected primary"})
      for display in $(${xrandr "connected"}); do
        export POLYBAR_MONITOR=$display
        export POLYBAR_MONITOR_PRIMARY=$([[ $primary = $display ]] && echo true || echo false)
        export POLYBAR_TRAY_POSITION=$([[ $primary = $display ]] && echo right || echo none)
        polybar arc &
      done
    '';
    package = pkgs.polybarFull;
    config = {
      "bar/base" = {
        modules-left = mkIf config.xsession.windowManager.i3.enable (
          mkBefore [ "i3" ]
        );
        modules-center = mkMerge [
          (mkIf (nixosConfig.hardware.pulseaudio.enable or false || nixosConfig.services.pipewire.enable or false) (mkBefore [ "pulseaudio" "mic" ]))
          (mkIf config.services.playerctld.enable [ "sep" "mpris" ])
          (mkIf (config.programs.ncmpcpp.enable && !config.services.playerctld.enable) [ "sep" "mpd" ])
        ];
        modules-right = mkMerge [
          (mkBefore [ "fs-prefix" "fs-root" ])
          (mkOrder 990 [ "sep" ])
          (mkIf (nixosConfig.networking.wireless.enable or false || nixosConfig.networking.wireless.iwd.enable or false) [ "net-wlan" ])
          [ "net-ethb2b" ]
          (mkOrder 1240 [ "sep" ])
          (mkOrder 1250 [ "cpu" "temp" "ram" ])
          (mkOrder 1490 [ "sep" ])
          (mkAfter [ "utc" "date" ])
        ];
      };
    };
    settings = let
      colours = base16.map.hash.argb;
      warn-colour = colours.constant; # or deleted
    in with colours; {
      "bar/arc" = {
        "inherit" = "bar/base";
        monitor = {
          text = mkIf config.xsession.enable "\${env:POLYBAR_MONITOR:}";
        };
        enable-ipc = true;
        tray.position = "\${env:POLYBAR_TRAY_POSITION:right}";
        dpi = {
          x = 0;
          y = 0;
        };
        scroll = {
          up = "#i3.prev";
          down = "#i3.next";
        };
        font = [
          "monospace:size=${config.lib.gui.fontSizeStr 8}"
          "Noto Mono:size=${config.lib.gui.fontSizeStr 8}"
          "Symbola:size=${config.lib.gui.fontSizeStr 9}"
        ];
        padding = {
          right = 1;
        };
        separator = {
          text = " ";
          foreground = foreground_status;
        };
        background = background_status;
        foreground = foreground_alt;
        border = {
          bottom = {
            size = 1;
            color = background_light;
          };
        };
        module-margin = 0;
        #click-right = ""; menu of some sort?
      };
      "module/i3" = mkIf config.xsession.windowManager.i3.enable {
        type = "internal/i3";
        pin-workspaces = true;
        strip-wsnumbers = true;
        wrapping-scroll = false;
        enable-scroll = false; # handled by bar instead
        label = {
          mode = {
            padding = 2;
            foreground = constant;
            background = background_selection;
          };
          focused = {
            text = "%name%";
            padding = 1;
            foreground = attribute;
            background = background_light;
          };
          unfocused = {
            text = "%name%";
            padding = 1;
            foreground = comment;
            #background = background;
          };
          visible = {
            text = "%name%";
            padding = 1;
            foreground = foreground;
            #background = background;
          };
          urgent = {
            text = "%name%";
            padding = 1;
            foreground = foreground_status;
            background = link;
          };
          separator = {
            text = "|";
            foreground = foreground_status;
          };
        };
      };
      "module/sep" = {
        type = "custom/text";
        content = {
          text = "|";
          foreground = comment;
        };
      };
      "module/ram" = {
        type = "internal/memory";
        interval = 4;
        label = "%gb_used% %percentage_used%% ~ %gb_free%";
        warn-percentage = 90;
        format.warn.foreground = warn-colour;
      };
      "module/cpu" = {
        type = "internal/cpu";
        label = "🖥️ %percentage%%"; # 🧮
        interval = 2;
        warn-percentage = 90;
        format.warn.foreground = warn-colour;
      };
      "module/mpd" = let
        inherit (config.programs) mpc;
        default = mpc.servers.${mpc.defaultServer} or { enable = false; };
      in mkIf mpc.enable {
        type = "internal/mpd";

        host = mkIf default.enable default.connection.host;
        password = mkIf (default.enable && default.password != null) default.password;
        port = mkIf (default.enable && default.out.MPD_PORT != null) default.out.MPD_PORT;

        interval = 1;
        label-song = "♪ %artist% - %title%";
        format = {
          online = "<label-time> <label-song>";
          playing = "\${self.format-online}";
        };
      };
      "module/mpris" = mkIf config.services.playerctld.enable {
        # TODO consider: https://github.com/polybar/polybar-scripts/tree/master/polybar-scripts/player-mpris-tail
        type = "custom/script";
        format = "<label>";
        interval = 10;
        click-left = "${pkgs.playerctl}/bin/playerctl play-pause";
        exec = pkgs.writeShellScript "polybar-mpris" ''
          ${pkgs.playerctl}/bin/playerctl \
            metadata \
            --format "{{ emoji(status) }} ~{{ duration(mpris:length) }} ♪ {{ artist }} - {{ title }}"
        '';
        tail = false;
      };
      "module/net-ethb2b" = {
        type = "internal/network";
        interface = "ethb2b";
      };
      "module/pulseaudio" = {
        type = "internal/pulseaudio";
        use-ui-max = false;
        interval = 5;
        format.volume = "<ramp-volume> <label-volume>";
        ramp.volume = [ "🔈" "🔉" "🔊" ];
        label = {
          muted = {
            text = "🔇 muted";
            foreground = warn-colour;
          };
        };
      };
      "module/date" = {
        type = "internal/date";
        label = "%date%, %time%";
        format = "<label>";
        interval = 60;
        date = "%a %b %d";
        time = "%I:%M %p";
      };
      "module/utc" = {
        type = "custom/script";
        exec = "${pkgs.coreutils}/bin/date -u +%H:%M";
        format = "🕓 <label>Z";
        interval = 60;
      };
      "module/temp" = {
        type = "internal/temperature";

        interval = mkDefault 5;
        base-temperature = mkDefault 30;
        label = {
          text = "%temperature-c%";
          warn.foreground = warn-colour;
        };

        # $ for i in /sys/class/thermal/thermal_zone*; do echo "$i: $(<$i/type)"; done
        #thermal-zone = 0;

        # Full path of temperature sysfs path
        # Use `sensors` to find preferred temperature source, then run
        # $ for i in /sys/class/hwmon/hwmon*/temp*_input; do echo "$(<$(dirname $i)/name): $(cat ${i%_*}_label 2>/dev/null || echo $(basename ${i%_*})) $(readlink -f $i)"; done
        # Default reverts to thermal zone setting
        #hwmon-path = ?
      };
      "module/net-wlan" = {
        type = "internal/network";
        interface = mkIf (nixosConfig.networking.wireless.mainInterface.name or null != null) (mkDefault nixosConfig.networking.wireless.mainInterface.name);
        label = {
          connected = {
            text = "📶 %essid% %downspeed:9%";
            foreground = inserted;
          };
          disconnected = {
            text = "Disconnected.";
            foreground = warn-colour;
          };
        };
        format-packetloss = "<animation-packetloss> <label-connected>";
        animation-packetloss = [
          {
            text = "!"; # ⚠
            foreground = warn-colour;
          }
          {
            text = "📶";
            foreground = warn-colour;
          }
        ];
      };
      "module/net-wired" = {
        type = "internal/network";
        label = {
          connected = {
            text = "%ifname% %local_ip%";
            foreground = inserted;
          };
          disconnected = {
            text = "Unconnected.";
            foreground = warn-colour; # or deleted
          };
        };
        # TODO: formatting
      };
      "module/fs-prefix" = {
        type = "custom/text";
        content = {
          text = "💽";
        };
      };
      "module/fs-root" = {
        type = "internal/fs";
        mount = mkBefore [ "/" ];
        label-mounted = "%mountpoint% %free% %percentage_used%%";
        label-warn = "%mountpoint% %{F${warn-colour}}%free% %percentage_used%%%{F-}";
        label-unmounted = "";
        warn-percentage = 90;
        spacing = 1;
      };
      "module/mic" = {
        type = "custom/ipc";
        format = "🎤 <output>";
        initial = 1;
        click.left = "${nixosConfig.hardware.pulseaudio.package or pkgs.pulseaudio}/bin/pactl set-source-mute @DEFAULT_SOURCE@ toggle && ${config.services.polybar.package}/bin/polybar-msg hook mic 1";
        # check if pa default-source is muted, if so, show warning!
        # also we trigger an immediate refresh when hitting the keybind
        hook = let
          pamixer = "${pkgs.pamixer}/bin/pamixer --default-source";
          script = pkgs.writeShellScript "checkmute" ''
            set -eu

            MUTE=$(${pamixer} --get-mute || true)
            if [[ $MUTE = true ]]; then
              echo muted
            else
              echo "$(${pamixer} --get-volume)%"
            fi
          '';
        in singleton "${script}";
      };
    };
  };
}
