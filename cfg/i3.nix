{ base16, config, pkgs, lib, ... }: with lib; {
  services.i3gopher.enable = config.xsession.windowManager.i3.enable;
  xsession.windowManager.i3 = let
    run = pkgs.writeShellScriptBin "run" ''
      ARGS=(${term} +sb
        -name run -title run -g 80x8
        -bg rgba:8888/3333/6666/cccc
        -fg rgb:e0/98/e0
        -e "$SHELL" -i
      )

      ARC_PROMPT_RUN=y exec "''${ARGS[@]}"
    '';
    alt = "Mod1";
    mod = "Mod4";
    left = "h";
    down = "j";
    up = "k";
    right = "l";
    term = "${pkgs.rxvt-unicode-arc}/bin/urxvtc"; # urxvt
    #term = "${pkgs.xterm}/bin/xterm";
    i3-easyfocus = "${pkgs.i3-easyfocus}/bin/i3-easyfocus";
    #lock = "${pkgs.physlock}/bin/physlock -dms";
    lock = "${pkgs.i3lock}/bin/i3lock -e -u -c 111111";
    sleep = "${pkgs.coreutils}/bin/sleep";
    xset = "${pkgs.xorg.xset}/bin/xset";
    pactl = "${config.home.nixosConfig.hardware.pulseaudio.package or pkgs.pulseaudio}/bin/pactl";
    playerctl = "${config.services.playerctld.package}/bin/playerctl";
    pkill = "${pkgs.procps}/bin/pkill";
    mosh = "${pkgs.mosh-client}/bin/mosh";
    ssh = "${pkgs.openssh}/bin/ssh";
    browser = "${config.programs.firefox.package}/bin/firefox";
    bar-refresh = optionalString (!config.services.polybar.enable) "&& ${pkill} -USR1 i3status";
    bar-refresh-mic = if config.services.polybar.enable
      then "&& ${config.services.polybar.package}/bin/polybar-msg hook mic 1"
      else bar-refresh;
    bindWorkspace = key: workspace: {
      "${mod}+${key}" = "workspace number ${workspace}";
      "${mod}+shift+${key}" = "move container to workspace number ${workspace}";
      "${mod}+control+${key}" = "exec --no-startup-id ${pkgs.arc.packages.personal.i3workspaceoutput.exec} 'number ${workspace}' current";
    };
    bindsym = k: v: "bindsym ${k} ${v}";
    # NOTE/TODO: modes could be used for additional/uncommon workspace (and other) bindings
    workspaceBindings =
      map (v: bindWorkspace v "${v}:${v}") ["1" "2" "3" "4" "5" "6" "7" "8" "9"]
      ++ [(bindWorkspace "0" "10:10")]
      ++ imap1 (i: v: bindWorkspace v "${toString (10 + i)}:${v}") ["F1" "F2" "F3" "F4" "F5" "F6" "F7" "F8" "F9" "F10" "F11" "F12"];
    workspaceBindings' =
      map (mapAttrsToList bindsym) workspaceBindings;
    workspaceBindingsStr =
      concatStringsSep "\n" (flatten workspaceBindings');
    colours = base16.map.hash.rgb;
    #vm = "${pkgs.arc.vm.exec}";
  in {
    enable = true;
    extraConfig = ''
      ${workspaceBindingsStr}

    '';
    config = {
      #workspaceAutoBackAndForth = true;
      bars = optional (!config.services.polybar.enable) {
        workspaceNumbers = false;
        fonts = {
          names = [ "monospace" ];
          size = config.lib.gui.fontSize 8;
        };
        position = "top";
        colors = {
          statusline = "#ffffff";
          background = "#323232";
          inactiveWorkspace = {
            border = "#32323200";
            background = "#32323200";
            text = "#5c5c5c";
          };
        };
        statusCommand = "${pkgs.i3status}/bin/i3status";
      };
      colors = with colours; {
        background = background;
        unfocused = {
          background = background;
          text = comment;
          border = background_status;
          childBorder = background;
          indicator = background;
        };
        focusedInactive = {
          background = background_selection;
          text = foreground_alt;
          border = background_light;
          childBorder = comment;
          indicator = background_light;
        };
        focused = {
          background = background_selection;
          text = foreground;
          border = keyword;
          childBorder = keyword;
          indicator = heading;
        };
        urgent = {
          #background = link;
          background = background_light;
          text = foreground;
          border = link;
          childBorder = url;
          indicator = url;
        };
        placeholder = {
          background = background_light;
          text = foreground_status;
          border = caret;
          childBorder = caret;
          indicator = caret;
        };
      };
      fonts = {
        names = [ "monospace" ];
        size = config.lib.gui.fontSize 6;
      };
      modifier = mod;
      floating = {
        border = 1;
        modifier = mod;
        criteria = [
          { title = "^run$"; }
          { title = "^pinentry$"; }
          { title = "^streamlaunch: "; }
        ];
      };
      focus = {
        forceWrapping = true;
      };
      window = {
        hideEdgeBorders = "smart";
        border = 1;
      };
      modes.resize = {
        ${left} = "resize shrink width 4 px or 4 ppt";
        ${down} = "resize shrink height 4 px or 4 ppt";
        ${up} = "resize grow height 4 px or 4 ppt";
        ${right} = "resize grow width 4 px or 4 ppt";

        Return = ''mode "default"'';
        Escape = ''mode "default"'';
        "${mod}+z" = ''mode "default"'';
      };
      keybindings = {
        "${mod}+z" = ''mode "resize"'';

        "${mod}+Return" = "exec ${term}";
        "${mod}+control+Return" = mkDefault "exec ${term} -e ${ssh} shanghai";
        "${mod}+shift+Return" = mkDefault "exec ${term} -e ${mosh} shanghai";

        "${mod}+shift+c" = "kill";
        "${mod}+r" = "exec ${run.exec}";

        "${mod}+apostrophe" = "exec ${browser}";

        "${mod}+BackSpace" = mkIf config.services.dunst.enable
          "exec --no-startup-id ${config.services.dunst.package}/bin/dunstctl close";
        "${mod}+control+BackSpace" = mkIf config.services.dunst.enable
          "exec --no-startup-id ${config.services.dunst.package}/bin/dunstctl history-pop";
        "${mod}+shift+BackSpace" = mkIf config.services.dunst.enable
          "exec --no-startup-id ${config.services.dunst.package}/bin/dunstctl close-all";

        "${mod}+shift+r" = "reload";

        "XF86AudioLowerVolume" = "exec --no-startup-id ${pactl} set-sink-volume @DEFAULT_SINK@ -5% ${bar-refresh}";
        "XF86AudioRaiseVolume" = "exec --no-startup-id ${pactl} set-sink-volume @DEFAULT_SINK@ +5% ${bar-refresh}";
        "XF86AudioMute" = "exec --no-startup-id ${pactl} set-sink-mute @DEFAULT_SINK@ toggle ${bar-refresh}";
        "ctrl+XF86AudioMute" = "exec --no-startup-id ${pactl} set-source-mute @DEFAULT_SOURCE@ toggle ${bar-refresh-mic}";
        "shift+XF86AudioMute" = "exec --no-startup-id ${playerctl} stop ${bar-refresh}";
        "shift+XF86AudioLowerVolume" = "exec --no-startup-id ${playerctl} volume 0.05- ${bar-refresh}";
        "shift+XF86AudioRaiseVolume" = "exec --no-startup-id ${playerctl} volume 0.05+ ${bar-refresh}";
        "XF86AudioStop" = "exec --no-startup-id ${playerctl} stop ${bar-refresh}";
        "shift+XF86AudioStop" = "exec --no-startup-id ${playerctl} --player=mpd,%any,mpv play-pause ${bar-refresh}";
        "XF86AudioPlay" = "exec --no-startup-id ${playerctl} play-pause ${bar-refresh}";
        "shift+XF86AudioPlay" = "exec --no-startup-id ${playerctl} --player=mpd,%any,mpv play-pause ${bar-refresh}";
        "XF86AudioNext" = "exec --no-startup-id ${playerctl} next ${bar-refresh}";
        "ctrl+XF86AudioNext" = "exec --no-startup-id ${playerctl} seek 10+ ${bar-refresh}";
        "XF86AudioPrev" = "exec --no-startup-id ${playerctl} previous ${bar-refresh}";
        "ctrl+XF86AudioPrev" = "exec --no-startup-id ${playerctl} seek 10- ${bar-refresh}";

        "--release ${mod}+p" = "exec --no-startup-id ${sleep} 0.2 && ${xset} dpms force off";

        "--release ${mod}+bracketleft" = "exec --no-startup-id ${config.systemd.package}/bin/systemctl --user stop gpg-agent.service; exec --no-startup-id ${sleep} 0.2 && ${xset} dpms force off && ${lock}";

        "${mod}+shift+Escape" = "exit";

        "${mod}+grave" = "[urgent=latest] focus";
        "${mod}+Tab" = "exec --no-startup-id ${config.services.i3gopher.focus-last}";
        "${mod}+control+f" = "exec --no-startup-id ${i3-easyfocus} -a || ${i3-easyfocus} -c";
        "${mod}+control+shift+f" = "exec --no-startup-id ${i3-easyfocus} -ar || ${i3-easyfocus} -cr";
        "${mod}+a" = "focus parent";
        "${mod}+q" = "focus child";
        "${mod}+n" = "focus next";
        "${mod}+m" = "focus prev";

        "${mod}+control+${left}" = "focus output left";
        "${mod}+control+${down}" = "focus output down";
        "${mod}+control+${up}" = "focus output up";
        "${mod}+control+${right}" = "focus output right";

        "${mod}+${left}" = "focus left";
        "${mod}+${down}" = "focus down";
        "${mod}+${up}" = "focus up";
        "${mod}+${right}" = "focus right";

        "${mod}+Left" = "focus left";
        "${mod}+Down" = "focus down";
        "${mod}+Up" = "focus up";
        "${mod}+Right" = "focus right";

        "${mod}+comma" = "workspace back_and_forth";

        "${mod}+shift+control+${left}" = "move container to output left";
        "${mod}+shift+control+${down}" = "move container to output down";
        "${mod}+shift+control+${up}" = "move container to output up";
        "${mod}+shift+control+${right}" = "move container to output right";

        "${mod}+${alt}+shift+control+${left}" = "move workspace to output left";
        "${mod}+${alt}+shift+control+${down}" = "move workspace to output down";
        "${mod}+${alt}+shift+control+${up}" = "move workspace to output up";
        "${mod}+${alt}+shift+control+${right}" = "move workspace to output right";

        "${mod}+shift+a" = "move first";
        "${mod}+shift+n" = "move next";
        "${mod}+shift+m" = "move prev";

        "${mod}+shift+${left}" = "move left";
        "${mod}+shift+${down}" = "move down";
        "${mod}+shift+${up}" = "move up";
        "${mod}+shift+${right}" = "move right";

        "${mod}+shift+Left" = "move left";
        "${mod}+shift+Down" = "move down";
        "${mod}+shift+Up" = "move up";
        "${mod}+shift+Right" = "move right";

        "${mod}+b" = "splith";
        "${mod}+v" = "splitv";

        "${mod}+s" = "layout stacking";
        "${mod}+w" = "layout tabbed";
        "${mod}+e" = "layout toggle split";

        "${mod}+f" = "fullscreen";

        "${mod}+shift+space" = "floating toggle";

        "${mod}+space" = "focus mode_toggle";

        "${mod}+shift+minus" = "move scratchpad";
        "${mod}+minus" = "scratchpad show";
      };
    };
  };
}
