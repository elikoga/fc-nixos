{ config, pkgs, lib, ... }:

with builtins;

let

  fclib = config.fclib;
  cfg = config.flyingcircus.roles.jitsi;

  generatedTurnSecret = readFile
      (pkgs.runCommand "jitsi-turn-secret" {}
      "${pkgs.apg}/bin/apg -a 1 -M lnc -n 1 -m 32 > $out");
  turnSecret = lib.removeSuffix "\n" (fclib.configFromFile /etc/local/jitsi/turn-secret generatedTurnSecret);
  turnHostName = if cfg.coturn.enable then cfg.coturn.hostName else cfg.turnHostName;

  # Does the same on the backend side but UI buttons can be turned on/off seperately.
  enableJibriIntegration = cfg.enableRecording || cfg.enableLivestreaming;

in {

  options = with lib; {
    flyingcircus.roles.jitsi = {

      enable = mkEnableOption "Enable a Jitsi Meet server with all needed services.";

      coturn = mkOption {
        default = {};
        type = types.submodule {
          options = {
            enable = mkEnableOption ''
              Enable a local coturn preconfigured for Jitsi
              Machines with Jitsi and a local coturn need two public IP addresses.
            '';

            listenAddress = mkOption {
              type = with types; string;
              description = ''
                Specify here which IPv4 address to use for coturn.";
              '';
            };

            listenAddress6 = mkOption {
              type = with types; string;
              description = ''
                Specify here which IPv6 address to use for coturn.";
              '';
            };

            hostName = mkOption {
              type = types.string;
            };
          };
        };
      };

      enablePublicUDP = mkOption {
        description =  "Allow public access to the videobridge via UDP 10000";
        type = types.bool;
        default = true;
      };

      enableRecording = mkOption {
        description =  ''
          Enable integration for recording and show the recording button in the UI.
          Needs a separate Jibri installation which is not part of this role.
        '';
        type = types.bool;
        default = false;
      };

      enableLivestreaming = mkOption {
        description =  ''
          Enable integration for recording and show the livestream button in the UI.
          Needs a separate Jibri installation which is not part of this role.
        '';
        type = types.bool;
        default = false;
      };

      enableRoomAuthentication = mkOption {
        description =  ''
          Require a username and password to create new rooms.
          Guests can join after the room is created
        '';
        type = types.bool;
        default = false;
      };

      listenAddress = mkOption {
        type = with types; string;
        description = ''
          IPv4 address to use for Jitsi.
        '';
      };

      listenAddress6 = mkOption {
        type = with types; string;
        description = ''
          IPv6 address to use for Jitsi.
        '';
      };

      hostName = mkOption {
        type = types.string;
      };

      turnHostName = mkOption {
        type = with types; nullOr string;
        default = null;
        description = ''
          Only needed for an external TURN server.
        '';
      };

      resolution = mkOption {
        type = types.int;
        default = 480;
      };

      defaultLanguage = mkOption {
        type = types.string;
        default = "de";
      };

    };

  };

  config = lib.mkMerge [

    (lib.mkIf cfg.enable {

      environment.etc."local/jitsi/README.txt".text = ''
        To customize the content on the welcome page, add a file called welcomePageAdditionalContent.html here.

        You can set a static auth secret for TURN in a file called turn-secret.
        If the file is missing, a random secret is generated on rebuild.
      '';

      environment.systemPackages = with pkgs; [
        (writeScriptBin "jitsi-jvb-show-config" ''
          cat $(systemctl cat jitsi-videobridge | grep JAVA_SYS_PROPS | cut -d= -f4 | cut -d" " -f1)
        '')

        (writeScriptBin "jitsi-jicofo-show-config" ''
          cat /etc/jitsi/jicofo/sip-communicator.properties
        '')

        (writeScriptBin "jitsi-prosody-show-config" ''
          cat /etc/prosody/prosody.cfg.lua
        '')
      ];

      flyingcircus.localConfigDirs.jitsi = {
        dir = "/etc/local/jitsi";
      };

      flyingcircus.roles.nginx.enable = true;

      flyingcircus.services.telegraf.inputs.http = [{
          urls = [ "http://127.0.0.1:8080/colibri/stats" ];
          tagexclude = [ "url" ];
          name_override = "jitsi_jvb";
          data_format = "json";
          fielddrop = [ "p2p_conferences" "version" ];
          json_time_key = "current_timestamp";
          json_time_format = "2006-01-02 15:04:05.000";
          json_timezone = "UTC";
        }];

      flyingcircus.services.sensu-client.checks = {
        jitsi-videobridge-alive = {
          notification = "Jitsi videobridge alive";
          command = "check_http -v -j HEAD -H localhost -p 8080 -u /about/health";
        };
      };

      networking.firewall.allowedUDPPorts = lib.optional cfg.enablePublicUDP 10000;
      networking.firewall.allowedTCPPorts = [ 3478 ];

      services.jicofo.config =
        lib.optionalAttrs cfg.enableRoomAuthentication {
          "org.jitsi.jicofo.auth.URL" = "XMPP:${cfg.hostName}";
        } //
        lib.optionalAttrs enableJibriIntegration {
          "org.jitsi.jicofo.jibri.BREWERY" = "jibribrewery@internal.${cfg.hostName}";
          "org.jitsi.jicofo.jibri.PENDING_TIMEOUT"= "90";
        };

      services.jitsi-meet = {
        enable = true;
        nginx.enable = true;
        jicofo.enable = true;
        videobridge.enable = true;
        prosody.enable = true;

        config = {
          channelLastN = 8;
          constraints = {
            video = {
              height = {
                ideal = cfg.resolution;
                max = cfg.resolution;
                min = cfg.resolution;
              };
            };
          };
          defaultLanguage = cfg.defaultLanguage;
          enableLipSync = false;
          enableAutomaticUrlCopy = true;
          useStunTurn = true;
          p2p.enabled = false;
          inherit (cfg) resolution;
          startVideoMuted = 8;
          stunServers = [];
          fileRecordingsEnabled = cfg.enableRecording;
          liveStreamingEnabled = cfg.enableLivestreaming;
        } //
        lib.optionalAttrs cfg.enableRoomAuthentication {
          hosts.anonymousdomain = "guest.${cfg.hostName}";
        } //
        lib.optionalAttrs enableJibriIntegration {
          hiddenDomain = "recorder.${cfg.hostName}";
        };

        hostName = cfg.hostName;

        interfaceConfig = {
          DISABLE_VIDEO_BACKGROUND = true;
          MOBILE_APP_PROMO = false;
          SHOW_JITSI_WATERMARK = false;
          SHOW_WATERMARK_FOR_GUESTS = false;
        };

      };

      services.nginx.virtualHosts = {
        "${cfg.hostName}" = {
          listenAddress = cfg.listenAddress;
          listenAddress6 = fclib.quoteIPv6Address cfg.listenAddress6;
        } //
        lib.optionalAttrs (pathExists /etc/local/jitsi/welcomePageAdditionalContent.html) {
          locations."=/static/welcomePageAdditionalContent.html" = {
            alias = "${/etc/local/jitsi/welcomePageAdditionalContent.html}";
          };
        };
      };

      services.prosody = {

        extraModules = [
          "ping"
          "turncredentials"
        ];

        extraConfig = ''
          turncredentials_secret = "${turnSecret}";
          turncredentials = {
            { type = "turn",
              host = "${turnHostName}",
              port = "3478",
              transport = "tcp"
            },
            { type = "turn",
              host = "${turnHostName}",
              port = "443",
              transport = "tcp"
            },
            { type = "turns",
              host = "${turnHostName}",
              port = "443",
              transport = "tcp"
            }
          }
        '';

        extraPluginPaths = [
          ./prosody-plugins
        ];

        virtualHosts =
          lib.optionalAttrs cfg.enableRoomAuthentication {

            # Force authentication on default vhost which is used for room creation.
            "${cfg.hostName}" = {
              extraConfig = lib.mkForce ''
                authentication = "internal_hashed"
                c2s_require_encryption = false
                admins = { "focus@auth.${cfg.hostName}" }
              '';
            };

            # Define new vhost for anonymous guests in rooms.
            "guest.${cfg.hostName}" = {
              domain = "guest.${cfg.hostName}";
              enabled = true;
              extraConfig = ''
                authentication = "anonymous"
                c2s_require_encryption = false
              '';
            };
          } //
          lib.optionalAttrs enableJibriIntegration {
            # Jibri gets special rights and needs its own vhost for that.
            # c2s encryption doesn't work for unknown reasons but both are on the
            # same host, so it's ok.
            "recorder.${cfg.hostName}" = {
              domain = "recorder.${cfg.hostName}";
              enabled = true;
              extraConfig = ''
                authentication = "internal_plain"
                c2s_require_encryption = false
              '';
            };
          };

      };

      services.jitsi-videobridge.extraProperties =
        lib.optionalAttrs (!cfg.enablePublicUDP) {
          "org.ice4j.ice.harvest.ALLOWED_ADDRESSES" =
            lib.concatStringsSep ";" (fclib.listenAddresses "ethsrv");
        };

    })

    (lib.mkIf (cfg.enable && cfg.coturn.enable) {

      flyingcircus.roles.coturn = {
        enable = true;
        hostName = cfg.coturn.hostName;
      };

      services.coturn = {
        listening-ips = [ cfg.coturn.listenAddress cfg.coturn.listenAddress6 ];
        no-tcp = false;
        static-auth-secret = turnSecret;
        tls-listening-port = 443;
        extraConfig = ''
          no-stun
        '';
      };

    })

  ];
}
