{ config, lib, pkgs, ... }: with lib; let
  target = config.deploy.targets.${cfg.target};
  tconfig = target.tf;
  tlib = tconfig.lib.tf;
  cfg = config.deploy.repos;
  inherit (tconfig.lib.tf) tfTypes;
  gitString = value:
    if value == true then "true"
    else if value == false then "false"
    else toString value;
  gitConfigCommands = config:
    mapAttrsToList (k: v: [ "git" "config" k (gitString v) ]) config;
  gcryptType = types.submodule ({ config, name, ... }: {
    options = {
      enable = mkEnableOption "git-remote-gcrypt";
      participants = mkOption {
        type = types.listOf types.str;
      };
    };
  });
  annexEncryptionType = types.submodule ({ config, name, ... }: {
    options = {
      enable = mkEnableOption "git-annex encryption";
      mac = mkOption {
        type = types.enum [ "HMACSHA1" "HMACSHA256" "HMACSHA384" "HMACSHA512" ];
        default = "HMACSHA384";
      };
      type = mkOption {
        type = types.enum [ "hybrid" "shared" "pubkey" "sharedpubkey" ];
        default = "hybrid";
      };
      participants = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      embed = mkOption {
        type = types.bool;
        default = true;
      };
      out = {
        extraConfig = mkOption {
          type = types.attrs;
          default = { };
        };
        enableConfig = mkOption {
          type = types.attrs;
          default = { };
        };
        additionalKeys = mkOption {
          type = types.listOf types.unspecified;
          default = [ ];
        };
      };
    };
    config.out = {
      extraConfig = mkIf config.enable {
        mac = config.mac;
        encryption = config.type;
        keyid = mkIf (config.participants != []) (builtins.head config.participants);
        embedcreds = if config.embed then "yes" else "no";
      };
      enableConfig = { };
      additionalKeys = mkIf config.enable (builtins.tail config.participants);
    };
  });
  annexRemoteS3Type = types.submodule ({ config, name, ... }: {
    options = {
      bucket = mkOption {
        type = types.str;
      };
      prefix = mkOption {
        type = types.str;
        #default = "";
      };
      out = mkOption {
        type = types.attrsOf types.unspecified;
        default = { };
      };
    };
    config = {
      out = {
        extraConfig = {
          type = "S3";
          inherit (config) bucket;
          fileprefix = config.prefix;
          partsize = "1GiB";
        };
        enableConfig = { };
      };
    };
  });
  annexRemoteRsyncType = types.submodule ({ config, name, ... }: {
    options = {
      url = mkOption {
        type = types.str;
      };
      out = mkOption {
        type = types.attrsOf types.unspecified;
        default = { };
      };
    };
    config = {
      out = {
        extraConfig = {
          type = "rsync";
          rsyncurl = config.url;
        };
        enableConfig = {
          rsyncurl = config.url;
        };
      };
    };
  });
  annexRemoteB2Type = types.submodule ({ config, name, ... }: {
    options = {
      bucket = mkOption {
        type = types.str;
      };
      prefix = mkOption {
        type = types.str;
        #default = "";
      };
      out = mkOption {
        type = types.attrsOf types.unspecified;
        default = { };
      };
    };
    config = {
      out = {
        extraConfig = {
          type = "external";
          externaltype = "b2";
          inherit (config) bucket prefix;
        };
        enableConfig = { };
      };
    };
  });
  annexRemoteDirectoryType = types.submodule ({ config, name, ... }: {
    options = {
      path = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      out = {
        extraConfig = mkOption {
          type = types.attrsOf types.unspecified;
          default = { };
        };
        enableConfig = mkOption {
          type = types.attrsOf types.unspecified;
          default = { };
        };
      };
    };
    config = {
      out = {
        extraConfig = {
          type = "directory";
          directory = config.path;
        };
        enableConfig = {
          inherit (config.out.extraConfig) directory;
        };
      };
    };
  });
  annexRemoteGitType = types.submodule ({ config, name, ... }: {
    options = {
      out = mkOption {
        type = types.attrsOf types.unspecified;
        default = { };
      };
      # location=...? apparently it must be the same as existing git
    };
    config = {
      out = {
        extraConfig = {
          type = "git";
          # inherit config.location;
        };
        enableConfig = { };
      };
    };
  });
  annexRemoteType = { defaults, remote }: types.submoduleWith {
    modules = singleton ({ config, defaults, ... }: {
      options = {
        enable = mkOption {
          type = types.bool;
        };
        enableRemote = mkOption {
          type = types.bool;
          default = true;
        };
        name = mkOption {
          type = types.str;
          default = if config.uuid != null then config.uuid else remote.name;
        };
        uuid = mkOption {
          type = types.nullOr types.str;
          default = null;
        };
        chunkSize = mkOption {
          type = types.nullOr types.str;
          default = null;
          # example "5MiB"
        };
        trust = mkOption {
          type = types.nullOr (types.enum [ "trusted" "semitrusted" "untrusted" "dead" ]);
          default = null;
        };
        group = mkOption {
          type = types.listOf types.str;
          default = [ ];
        };
        wanted = mkOption {
          type = types.nullOr types.str;
          default = null;
        };
        extraConfig = mkOption {
          type = types.attrsOf types.unspecified;
          default = { };
        };
        enableConfig = mkOption {
          type = types.attrsOf types.unspecified;
          default = { };
        };
        chunkType = mkOption {
          type = types.enum [ "chunk" "chunksize" ];
          default = "chunk";
          # chunksize is a legacy option
        };
        encryption = mkOption {
          type = annexEncryptionType;
          default = { };
        };
        s3 = mkOption {
          type = types.nullOr annexRemoteS3Type;
          default = null;
        };
        b2 = mkOption {
          type = types.nullOr annexRemoteB2Type;
          default = null;
        };
        directory = mkOption {
          type = types.nullOr annexRemoteDirectoryType;
          default = null;
        };
        rsync = mkOption {
          type = types.nullOr annexRemoteRsyncType;
          default = null;
        };
        git = mkOption {
          type = types.nullOr annexRemoteGitType;
          default = null;
        };
        out = {
          specialRemote = mkOption {
            type = types.unspecified;
            default = { };
          };
          initremote = mkOption {
            type = types.listOf (types.listOf types.str);
            default = [ ];
          };
          enableremote = mkOption {
            type = types.listOf types.str;
            default = [ ];
          };
          enableCommands = mkOption {
            type = types.listOf (types.listOf types.str);
            default = [ ];
          };
        };
      };
      config = {
        enable = mkOptionDefault (config.uuid != null || config.extraConfig != {});
        encryption.participants = mkOptionDefault defaults.annex.participants;
        extraConfig = mkMerge [
          (mapAttrs (_: mkDefault) config.out.specialRemote.extraConfig)
          (mkIf (config.chunkSize != null) {
            ${config.chunkType} = mkDefault "${config.chunkSize}";
          })
          config.encryption.out.extraConfig
        ];
        enableConfig = mapAttrs (_: mkDefault) config.out.specialRemote.enableConfig
          // config.encryption.out.enableConfig;
        out = {
          specialRemote =
            if config.s3 != null then config.s3.out
            else if config.b2 != null then config.b2.out
            else if config.directory != null then config.directory.out
            else if config.rsync != null then config.rsync.out
            else if config.git != null then config.git.out
            else {
              extraConfig = { };
              enableConfig = { };
            };
          initremote = singleton (
            mapAttrsToList (k: v: "${k}=${gitString v}") config.extraConfig
          ) ++ map (key: config.out.enableremote ++ singleton "keyid+=${key}") config.encryption.out.additionalKeys;
          enableremote = mapAttrsToList (k: v: "${k}=${gitString v}") config.enableConfig;
          enableCommands = let
            trustCommand = {
              "trusted" = "trust";
              "semitrusted" = "semitrust";
              "untrusted" = "untrust";
              "dead" = "dead";
            }.${config.trust};
          in optionals (config.group != [ ]) (map (g: [ "git" "annex" "group" config.name g ]) config.group)
            ++ optional (config.wanted != null) [ "git" "annex" "wanted" config.name config.wanted ]
            ++ optional (config.trust != null) [ "git" "annex" trustCommand config.name ];
        };
      };
    });
    specialArgs = {
      inherit defaults;
    };
  };
  googleRemoteType = { defaults }: types.submoduleWith {
    modules = singleton ({ config, name, defaults, ... }: {
      options = {
        create = mkOption {
          type = types.bool;
          default = true;
        };
        repo = mkOption {
          type = types.str;
          default = defaults.name;
        };
        project = mkOption {
          type = types.nullOr types.str;
          default = null;
        };
        provider = mkOption {
          type = tfTypes.providerReferenceType;
          default = cfg.defaults.providers.google.set or "google";
        };
        out = {
          url = mkOption {
            type = types.unspecified;
          };
          sshCloneUrl = mkOption {
            type = types.unspecified;
          };
          repoResourceName = mkOption {
            type = types.str;
            default = tlib.terraformIdent "${config.repo}-google";
          };
          repoResource = mkOption {
            type = types.unspecified;
            default = tconfig.resources.${config.out.repoResourceName};
          };
          cloneUrl = mkOption {
            type = types.unspecified;
            default = { };
          };
          setRepoResources = mkOption {
            type = types.attrsOf types.unspecified;
            default = { };
          };
        };
      };
      config = mkMerge [ (cfg.defaults.remoteConfig.google or { }) {
        out = {
          url = config.out.repoResource.getAttr "url";
          sshCloneUrl = config.out.url;
          cloneUrl = {
            fetch = config.out.sshCloneUrl;
            push = config.out.sshCloneUrl;
          };
          setRepoResources = mkIf config.create {
            ${config.out.repoResourceName} = {
              provider = config.provider.reference;
              type = mkDefault "sourcerepo_repository";
              inputs = mkMerge [ {
                name = mkDefault config.repo;
                project = mkIf (config.project != null) (mkDefault config.project);
              } (cfg.defaults.providerConfig.google or { }) ];
            };
          };
        };
      } ];
    });
    specialArgs = {
      inherit defaults;
    };
  };
  s3RemoteType = { defaults }: types.submoduleWith {
    modules = singleton ({ config, name, defaults, ... }: {
      options = {
        bucket = mkOption {
          type = types.str;
        };
        prefix = mkOption {
          type = types.str;
          default = "git-remote-s3/" + defaults.name;
        };
        gpgRecipients = mkOption {
          type = types.listOf types.str;
          default = [ ];
        };
        accessKeyId = mkOption {
          type = types.nullOr types.str;
          default = null;
        };
        secretAccessKey = mkOption {
          type = types.nullOr types.str;
          default = null;
        };
        out = {
          s3CloneUrl = mkOption {
            type = types.unspecified;
            description = "git-remote-s3";
          };
          cloneUrl = mkOption {
            type = types.unspecified;
            default = { };
          };
          extraConfig = mkOption {
            type = types.attrsOf types.str;
            default = { };
          };
          gitConfig = mkOption {
            type = types.attrsOf types.str;
            default = { };
          };
          env = mkOption {
            type = types.attrsOf types.str;
            default = { };
          };
        };
      };
      config = mkMerge [ (cfg.defaults.remoteConfig.s3 or { }) {
        out = {
          s3CloneUrl = "s3://${config.bucket}/${config.prefix}";
          cloneUrl = {
            fetch = config.out.s3CloneUrl;
            push = config.out.s3CloneUrl;
          };
          env = {
            AWS_ACCESS_KEY_ID = mkIf (config.accessKeyId != null) config.accessKeyId;
            AWS_SECRET_ACCESS_KEY = mkIf (config.secretAccessKey != null) config.secretAccessKey;
          };
          extraConfig = {
            gpgRecipients = mkIf (config.gpgRecipients != [ ]) (mkDefault (concatStringsSep " " config.gpgRecipients));
            vcs = mkIf (config.out.env != { }) "s3-${config.bucket}";
          };
          gitConfig = mkIf (config.out.env != { }) {
            "alias.remote-s3-${config.bucket}" = mkIf (config.out.env != { }) "${pkgs.writeShellScript "git-remote-s3-${config.bucket}" ''
              ${concatStringsSep "\n" (mapAttrsToList (k: v: "export ${k}=${v}") config.out.env)}

              exec ${pkgs.gitAndTools.git-remote-s3}/bin/git-remote-s3 "$@"
            ''}";
          };
        };
      } ];
    });
    specialArgs = {
      inherit defaults;
    };
  };
  awsRemoteType = { defaults }: types.submoduleWith {
    modules = singleton ({ config, name, defaults, ... }: {
      options = {
        create = mkOption {
          type = types.bool;
          default = true;
        };
        repo = mkOption {
          type = types.str;
          default = defaults.name;
        };
        description = mkOption {
          type = types.nullOr types.str;
          default = null;
        };
        region = mkOption {
          type = types.str;
          default = config.provider.out.provider.inputs.region;
        };
        provider = mkOption {
          type = tfTypes.providerReferenceType;
          default = cfg.defaults.providers.aws.set or "aws";
        };
        out = {
          url = mkOption {
            type = types.unspecified;
          };
          httpsCloneUrl = mkOption {
            type = types.unspecified;
          };
          sshCloneUrl = mkOption {
            type = types.unspecified;
          };
          grcCloneUrl = mkOption {
            type = types.unspecified;
            description = "git-remote-codecommit";
          };
          arn = mkOption {
            type = types.unspecified;
          };
          repoResourceName = mkOption {
            type = types.str;
            default = tlib.terraformIdent "${config.repo}-aws";
          };
          repoResource = mkOption {
            type = types.unspecified;
            default = tconfig.resources.${config.out.repoResourceName};
          };
          cloneUrl = mkOption {
            type = types.unspecified;
            default = { };
          };
          setRepoResources = mkOption {
            type = types.attrsOf types.unspecified;
            default = { };
          };
        };
      };
      config = mkMerge [ (cfg.defaults.remoteConfig.aws or { }) {
        out = {
          url = "https://${config.region}.console.aws.amazon.com/codesuite/codecommit/repositories/${config.repo}/browse";
          httpsCloneUrl = "https://git-codecommit.${config.region}.amazonaws.com/v1/repos/${config.repo}";
          sshCloneUrl = "ssh://git-codecommit.${config.region}.amazonaws.com/v1/repos/${config.repo}";
          grcCloneUrl = "codecommit::${config.region}://${config.repo}";
          arn = "arn:aws:codecommit:${config.repo}:${config.accountNumber}:${config.repo}";
          cloneUrl = {
            # TODO: configure default protocol: ssh, https, grc
            fetch = config.out.sshCloneUrl;
            push = config.out.sshCloneUrl;
          };
          setRepoResources = mkIf config.create {
            ${config.out.repoResourceName} = {
              provider = config.provider.reference;
              type = mkDefault "codecommit_repository";
              inputs = mkMerge [ {
                repository_name = mkDefault config.repo;
                description = mkIf (config.description != null) (mkDefault config.description);
              } (cfg.defaults.providerConfig.aws or { }) ];
            };
          };
        };
      } ];
    });
    specialArgs = {
      inherit defaults;
    };
  };
  bitbucketRemoteType = { defaults }: types.submoduleWith {
    modules = singleton ({ config, name, defaults, ... }: {
      options = {
        create = mkOption {
          type = types.bool;
          default = true;
        };
        repo = mkOption {
          type = types.str;
          default = defaults.name;
        };
        description = mkOption {
          type = types.nullOr types.str;
          default = null;
        };
        provider = mkOption {
          type = tfTypes.providerReferenceType;
          default = cfg.defaults.providers.bitbucket.set or "bitbucket";
        };
        private = mkOption {
          type = types.bool;
          default = true;
        };
        projectKey = mkOption {
          type = types.nullOr types.str;
          default = null;
        };
        owner = mkOption {
          type = types.str;
        };
        out = {
          url = mkOption {
            type = types.unspecified;
          };
          httpsCloneUrl = mkOption {
            type = types.unspecified;
          };
          sshCloneUrl = mkOption {
            type = types.unspecified;
          };
          repoResourceName = mkOption {
            type = types.str;
            default = tlib.terraformIdent "${config.repo}-bitbucket";
          };
          repoResource = mkOption {
            type = types.unspecified;
            default = tconfig.resources.${config.out.repoResourceName};
          };
          cloneUrl = mkOption {
            type = types.unspecified;
            default = { };
          };
          setRepoResources = mkOption {
            type = types.attrsOf types.unspecified;
            default = { };
          };
        };
      };
      config = mkMerge [ (cfg.defaults.remoteConfig.bitbucket or { }) {
        owner = mkIf (config.provider.out.provider ? inputs.username) (mkOptionDefault config.provider.out.provider.inputs.username);
        out = {
          url = "https://bitbucket.org/${config.owner}/${config.repo}";
          sshCloneUrl = "ssh://git@bitbucket.org/${config.owner}/${config.repo}.git";
          httpsCloneUrl = config.out.url + ".git";
          cloneUrl = {
            fetch = if config.private then config.out.sshCloneUrl else config.out.httpsCloneUrl;
            push = config.out.sshCloneUrl;
          };
          setRepoResources = mkIf config.create {
            ${config.out.repoResourceName} = {
              provider = config.provider.reference;
              type = mkDefault "repository";
              inputs = mkMerge [ {
                owner = mkDefault config.owner;
                name = mkDefault config.repo;
                description = mkIf (config.description != null) (mkDefault config.description);
                project_key = mkIf (config.projectKey != null) (mkDefault config.projectKey);
                is_private = mkDefault config.private;
                pipelines_enabled = mkDefault true; # API broken and fails to create repo otherwise?
              } (cfg.defaults.providerConfig.bitbucket or { }) ];
            };
          };
        };
      } ];
    });
    specialArgs = {
      inherit defaults;
    };
  };
  githubRemoteType = { defaults }: types.submoduleWith {
    modules = singleton ({ config, name, defaults, ... }: {
      options = {
        create = mkOption {
          type = types.bool;
          default = true;
        };
        owner = mkOption {
          type = types.str;
        };
        provider = mkOption {
          type = tfTypes.providerReferenceType;
          default = cfg.defaults.providers.github.set or "github";
        };
        repo = mkOption {
          type = types.str;
          default = defaults.name;
        };
        private = mkOption {
          type = types.bool;
          default = false;
        };
        out = {
          url = mkOption {
            type = types.unspecified;
          };
          httpsCloneUrl = mkOption {
            type = types.unspecified;
          };
          sshCloneUrl = mkOption {
            type = types.unspecified;
          };
          cloneUrl = mkOption {
            type = types.unspecified;
            default = { };
          };
          repoResourceName = mkOption {
            type = types.str;
            default = tlib.terraformIdent "${config.repo}-github";
          };
          repoResource = mkOption {
            type = types.unspecified;
            default = tconfig.resources.${config.out.repoResourceName};
          };
          setRepoResources = mkOption {
            type = types.attrsOf types.unspecified;
            default = { };
          };
        };
      };
      config = mkMerge [ (cfg.defaults.remoteConfig.github or { }) {
        owner = mkIf (config.provider.out.provider ? inputs.owner) (mkOptionDefault config.provider.out.provider.inputs.owner);
        out = {
          url = "https://github.com/${config.owner}/${config.repo}";
          httpsCloneUrl = "https://github.com/${config.owner}/${config.repo}.git";
          sshCloneUrl = "ssh://git@github.com/${config.owner}/${config.repo}.git";
          cloneUrl = {
            fetch = if config.private then config.out.sshCloneUrl else config.out.httpsCloneUrl;
            push = config.out.sshCloneUrl;
          };
          setRepoResources = mkIf config.create {
            ${config.out.repoResourceName} = {
              provider = config.provider.reference;
              type = mkDefault "repository";
              inputs = mkMerge [ {
                name = mkDefault config.repo;
                #description = mkIf (config.description != null) (mkDefault config.description);
                visibility = if config.private then "private" else "public";
                # TODO: many other attrs could go here...
              } (cfg.defaults.providerConfig.github or { }) ];
            };
          };
        };
      } ];
    });
    specialArgs = {
      inherit defaults;
    };
  };
  repoRemoteType = { repo, defaults }: types.submoduleWith {
    modules = singleton ({ repo, config, name, defaults, ... }: {
      options = {
        enable = mkOption {
          type = types.bool;
          default = true;
        };
        name = mkOption {
          type = types.str;
          default = name;
        };
        mirror = mkOption {
          type = types.bool;
          default = false;
        };
        gcrypt = mkOption {
          type = gcryptType;
          default = { };
        };
        github = mkOption {
          type = types.nullOr (githubRemoteType {
            inherit defaults;
          });
          default = null;
        };
        aws = mkOption {
          type = types.nullOr (awsRemoteType {
            inherit defaults;
          });
          default = null;
        };
        s3 = mkOption {
          type = types.nullOr (s3RemoteType {
            inherit defaults;
          });
          default = null;
        };
        bitbucket = mkOption {
          type = types.nullOr (bitbucketRemoteType {
            inherit defaults;
          });
          default = null;
        };
        google = mkOption {
          type = types.nullOr (googleRemoteType {
            inherit defaults;
          });
          default = null;
        };
        annex = mkOption {
          type = annexRemoteType {
            inherit defaults;
            remote = config;
          };
          default = { };
        };
        cloneUrl = {
          fetch = mkOption {
            type = types.nullOr types.str;
          };
          push = mkOption {
            type = types.nullOr types.str;
            default = config.cloneUrl.fetch;
          };
        };
        extraConfig = mkOption {
          type = types.attrsOf types.unspecified;
          default = { };
        };
        gitConfig = mkOption {
          type = types.attrsOf types.unspecified;
          default = { };
        };
        out = {
          repoResources = mkOption {
            type = types.unspecified;
            default = mapAttrs (k: _: tconfig.resources.${k}) config.out.setRepoResources;
          };
          setRepoResources = mkOption {
            type = types.attrsOf types.unspecified;
            default = { };
          };
          cloneUrl = mkOption {
            type = types.unspecified;
            default = [ ];
          };
          add = mkOption {
            type = types.unspecified;
            default = [ ];
          };
          set = mkOption {
            type = types.unspecified;
            default = [ ];
          };
          init = mkOption {
            type = types.listOf (types.listOf types.str);
            default = [ ];
          };
        };
      };
      config = {
        gcrypt.participants = mkOptionDefault defaults.gcrypt.participants;
        cloneUrl = mkMerge [
          (mkIf (config.github != null) (mapAttrs (_: mkOptionDefault) {
            inherit (config.github.out.cloneUrl) fetch push;
          }))
          (mkIf (config.aws != null) (mapAttrs (_: mkOptionDefault) {
            inherit (config.aws.out.cloneUrl) fetch push;
          }))
          (mkIf (config.s3 != null) (mapAttrs (_: mkOptionDefault) {
            inherit (config.s3.out.cloneUrl) fetch push;
          }))
          (mkIf (config.bitbucket != null) (mapAttrs (_: mkOptionDefault) {
            inherit (config.bitbucket.out.cloneUrl) fetch push;
          }))
          (mkIf (config.google != null) (mapAttrs (_: mkOptionDefault) {
            inherit (config.google.out.cloneUrl) fetch push;
          }))
          (mkIf config.annex.enable {
            fetch = mkOptionDefault null;
            push = mkOptionDefault null;
          })
        ];
        extraConfig = mkMerge [
          (mkIf (repo.annex.enable && !config.annex.enable) {
            annex-ignore = mkDefault "true";
          })
          (mkIf (repo.annex.enable && config.mirror) {
            annex-sync = mkDefault "false";
          })
          (mkIf (config.s3 != null) (mapAttrs (_: mkDefault) config.s3.extraConfig))
        ];
        gitConfig = mkMerge [
          (mkIf (config.s3 != null) (mapAttrs (_: mkDefault) config.s3.gitConfig))
        ];
        out = let
          remoteConfig = gitConfigCommands (mapAttrs' (k: nameValuePair "remote.${name}.${k}") config.extraConfig);
        in {
          setRepoResources = mkMerge [
            (mkIf (config.github != null && config.github.create) config.github.out.setRepoResources)
            (mkIf (config.google != null && config.google.create) config.google.out.setRepoResources)
            (mkIf (config.bitbucket != null && config.bitbucket.create) config.bitbucket.out.setRepoResources)
            (mkIf (config.aws != null && config.aws.create) config.aws.out.setRepoResources)
          ];
          cloneUrl = if config.gcrypt.enable then {
            fetch = "gcrypt::${config.cloneUrl.fetch}";
            push = "gcrypt::${config.cloneUrl.push}";
          } else {
            inherit (config.cloneUrl) fetch push;
          };
          add =
            (if config.annex.enable then optional config.annex.enableRemote (
              [ "git" "annex" "enableremote" name ] ++ config.annex.out.enableremote
            ) ++ config.annex.out.enableCommands else [
              [ "git" "remote" "add" name config.out.cloneUrl.fetch ]
            ] ++ optionals (config.out.cloneUrl.push != config.out.cloneUrl.fetch) [
              [ "git" "remote" "set-url" "--push" name config.out.cloneUrl.push ]
            ]) ++ remoteConfig;
          set =
            []/*(if config.annex.enable then optional config.annex.enableRemote (
              [ "git" "annex" "enableremote" name ] ++ config.annex.out.enableremote
            ) ++ config.annex.out.enableCommands else [
              [ "git" "remote" "set-url" name config.out.cloneUrl.fetch ]
            ] ++ optionals (config.out.cloneUrl.push != config.out.cloneUrl.fetch) [
              [ "git" "remote" "set-url" "--push" name config.out.cloneUrl.push ]
            ]) ++ remoteConfig*/;
          init =
            (if config.annex.enable then [
              ([ "git" "annex" "initremote" name ] ++ builtins.head config.annex.out.initremote)
            ] ++ map (ir: [ "git" "annex" "enableremote" name ] ++ ir) (builtins.tail config.annex.out.initremote)
            ++ config.annex.out.enableCommands
            else [
              [ "git" "remote" "add" name config.out.cloneUrl.fetch ]
            ] ++ optionals (config.out.cloneUrl.push != config.out.cloneUrl.fetch) [
              [ "git" "remote" "set-url" "--push" name config.out.cloneUrl.push ]
            ]) ++ remoteConfig;
        };
      };
    });
    specialArgs = {
      inherit defaults repo;
    };
  };
  repoType = types.submodule ({ config, name, ... }: {
    options = {
      name = mkOption {
        type = types.str;
        default = name;
      };
      description = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      annex = {
        enable = mkOption {
          type = types.bool;
        };
        participants = mkOption {
          type = types.listOf types.str;
        };
        numCopies = mkOption {
          type = types.nullOr types.int;
          default = null;
        };
        groupWanted = mkOption {
          type = types.attrsOf types.str;
          default = { };
        };
        extraConfig = mkOption {
          type = with types; attrsOf (oneOf [ bool int float str ]);
          default = { };
        };
      };
      gcrypt = mkOption {
        type = gcryptType;
        default = { };
      };
      remotes = mkOption {
        type = types.attrsOf (repoRemoteType {
          repo = config;
          defaults = {
            inherit (config.out) name;
            inherit (config) annex gcrypt;
          };
        });
        default = { };
      };
      environment = {
        init = mkOption {
          type = types.attrsOf types.str;
          default = { };
        };
        fetch = mkOption {
          type = types.attrsOf types.str;
          default = { };
        };
      };
      extraConfig = mkOption {
        type = types.attrsOf types.unspecified;
        default = { };
      };
      out = {
        name = mkOption {
          type = types.str;
        };
        repoResources = mkOption {
          type = types.unspecified;
          default = mapAttrs (k: _: tconfig.resources.${k}) config.out.setRepoResources;
        };
        setRepoResources = mkOption {
          type = types.attrsOf types.unspecified;
          default = { };
        };
        origin = mkOption {
          type = types.unspecified;
        };
        clone = mkOption {
          type = types.listOf (types.listOf types.str);
        };
        init = mkOption {
          type = types.listOf (types.listOf types.str);
        };
        run = mkOption {
          type = types.attrsOf types.unspecified;
        };
      };
    };
    config = {
      annex.enable = mkOptionDefault (any (r: r.annex.enable) (attrValues config.remotes));
      gcrypt.participants = mkOptionDefault cfg.defaults.gcrypt.participants;
      annex.participants = mkOptionDefault cfg.defaults.annex.participants;
      extraConfig = mkMerge (mapAttrsToList (_: remote:
        (mapAttrs (_: mkDefault) remote.gitConfig)
      ) config.remotes);
      out = let
        annexInit = singleton [ "git" "annex" "init" ]
        ++ mapAttrsToList (group: wanted: [ "git" "annex" "groupwanted" group wanted ]) config.annex.groupWanted
        ++ mapAttrsToList (k: v: [ "git" "annex" "config" "--set" "annex.${k}" (gitString v) ]) config.annex.extraConfig
        ++ optional (config.annex.numCopies != null) [ "git" "annex" "numcopies" (toString config.annex.numCopies) ];
      in {
        name = config.name
          + optionalString config.annex.enable ".anx"
          + optionalString config.gcrypt.enable ".cry";
        setRepoResources = mkMerge (mapAttrsToList (_: r: r.out.setRepoResources) config.remotes);
        origin = findFirst (remote: remote.enable && !remote.annex.enable && !remote.mirror) null (
          optional (config.remotes ? origin) config.remotes.origin
          ++ attrValues config.remotes
        );
        clone = [
          ([ "git" "clone" config.out.origin.out.cloneUrl.fetch "." ]
            ++ optionals (config.out.origin.name != "origin") [ "-o" config.out.origin.name ]
          )
        ] ++ gitConfigCommands config.extraConfig
        ++ optionals config.annex.enable annexInit
        ++ config.out.origin.out.set
        ++ concatLists (mapAttrsToList (_: remote: remote.out.add) (filterAttrs (_: remote:
          remote.enable && remote.name != config.out.origin.name
        ) config.remotes));
        init = singleton [ "git" "init" ]
        ++ gitConfigCommands config.extraConfig
        ++ optionals config.annex.enable annexInit
        ++ concatLists (mapAttrsToList (_: remote: remote.out.init) (filterAttrs (_: remote:
          remote.enable
        ) config.remotes));
        run = let
          f = k: v: with pkgs; nixRunWrapper {
            package = writeShellScriptBin k (''
              set -eu
            '' + concatStringsSep "\n" (map escapeShellArgs v));
          };
        in mapAttrs f {
          inherit (config.out) clone init;
        };
      };
    };
  });
in {
  options.deploy = {
    repos = {
      target = mkOption {
        type = types.str;
        default = "archive";
      };
      defaults = {
        providers = mkOption {
          type = types.attrsOf tfTypes.providerReferenceType;
          default = { };
        };
        providerConfig = mkOption {
          type = types.attrsOf (types.attrsOf types.unspecified);
          default = { };
        };
        remoteConfig = mkOption {
          type = types.attrsOf (types.attrsOf types.unspecified);
          default = { };
        };
        gcrypt = {
          participants = mkOption {
            type = types.listOf types.str;
            default = [ ];
          };
        };
        annex = {
          participants = mkOption {
            type = types.listOf types.str;
            default = [ ];
          };
        };
      };
      repos = mkOption {
        type = types.attrsOf repoType;
        default = { };
      };
      setResources = mkOption {
        type = types.attrsOf types.unspecified;
        default = { };
        internal = true;
      };
    };
  };
  config.deploy = {
    targets.${cfg.target} = {
      tf = {
        resources = cfg.setResources;
        runners.run = let
          f = repo: k: v: nameValuePair "${repo.name}-${k}" {
            command = ''
              set -eu

            '' + concatStrings (mapAttrsToList (k: v: "${k}=${v}\nexport ${k}\n") (repo.environment.init // repo.environment.fetch))
            + concatMapStringsSep "\n" escapeShellArgs v;
          };
          f' = repo: mapAttrs' (f repo) {
            inherit (repo.out) clone init;
          };
        in mkMerge (map f' (attrValues cfg.repos));
      };
    };
    repos = {
      setResources = mkMerge (mapAttrsToList (_: repo: repo.out.setRepoResources) cfg.repos);
    };
  };
}
