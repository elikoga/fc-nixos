{ config, lib, pkgs, ... }:

with builtins;

let
  cfg = lib.debug.traceValSeq config.flyingcircus.services.haproxy;
  fclib = config.fclib;

  # indentWith prepends a list fo strings with the first parameter
  # indentWith :: String -> [String] -> [String]
  # ```haskell
  # indentWith spaces = map (spaces ++)
  # ```
  indentWith = spaces: map (x: spaces + x);

  # separates a string into list of lines
  # lines :: String -> [String]
  lines = str: lib.trivial.pipe str [
    (split "\n") # :: String -> [String | [String]]
    (filter (elem: typeOf elem != "list")) # :: [String | [String]] -> [String]
  ];

  # concats strings in list with newlines
  # unlines :: [String] -> String
  unlines = concatStringsSep "\n";

  # flattens list one layer
  # join :: [[a]] -> [a]
  join = foldl' (x: y: x ++ y) [];

  generatedConfig' = with lib; with cfg; (x: trivial.pipe x [ join unlines ]) [
    (with global; join [
      ["global"]
      (indentWith "  " (join [
        (if global.daemon then ["daemon"] else []) # daemon is already set and won't be shadowed
        ["chroot ${chroot}"]
        ["user ${user}"]
        ["group ${group}"]
        ["maxconn ${toString maxconn}"]
        (lines extraOptions)
      ]))
    ])
    (with defaults; join [
      ["defaults"]
      (indentWith "  " (join [
        ["mode ${mode}"]
        (map (option: "option ${option}" ) options)
        (join (mapAttrsToList (key: value: if value != null then ["timeout ${key} ${value}"] else []) timeout))
        (lines extraOptions)
      ]))
    ])
    (join (mapAttrsToList (name: data: ((join [
      ["listen ${name}"]
      (indentWith "  " (with data; join [
        (map (bind: "bind ${bind}" ) binds)
        ["default_backend ${default_backend}"]
        (map (server: "server ${server}") servers)
        (lines extraOptions)
      ]))
    ]))) listens))
    (join (mapAttrsToList (name: data: ((join [
      ["frontend ${name}"]
      (indentWith "  " (with data; join [
        (map (bind: "bind ${bind}" ) binds)
        ["default_backend ${default_backend}"]
        (lines extraOptions)
      ]))
    ]))) frontends))
    (join (mapAttrsToList (name: data: ((join [
      ["backend ${name}"]
      (indentWith "  " (with data; join [
        (map (server: "server ${server}") servers)
        (lines extraOptions)
      ]))
    ]))) backends))
  ];

  generatedConfig = lib.debug.traceValSeq generatedConfig';

  haproxyCfg = pkgs.writeText "haproxy.conf" config.services.haproxy.config;

  configFiles = filter (lib.hasSuffix ".cfg") (fclib.files /etc/local/haproxy);

  # This was included in our old example config. Breaks on 20.09 because HAProxy
  # isn't allowed to write to /run/ anymore and is unneeded because a stats socket
  # is added by the NixOS module automatically.
  oldStatsLine = "stats socket /run/haproxy_admin.sock mode 660 group nogroup level operator";

  importedCfgContent = concatStringsSep "\n" (map readFile configFiles);
  modifiedCfgContent =
    replaceStrings
      [ oldStatsLine ]
      [ ("# XXX: you can remove this after upgrading to 20.09: " + oldStatsLine) ]
      importedCfgContent;

  haproxyCfgContent = (
    if importedCfgContent != modifiedCfgContent
    then lib.info
      ("HAProxy: you can remove the 'stats socket' line from your config."
      + " It's ignored on NixOS 20.09.")
    else lib.id
    ) (generatedConfig + "\n" + modifiedCfgContent);

  example = ''
    # haproxy configuration example - copy to haproxy.cfg and adapt.

    global
        daemon
        chroot /var/empty
        maxconn 4096
        log localhost local2

    defaults
        mode http
        log global
        option httplog
        option dontlognull
        option http-server-close
        timeout connect 5s
        timeout client 30s    # should be equal to server timeout
        timeout server 30s    # should be equal to client timeout
        timeout queue 25s     # discard requests sitting too long in the queue

    listen http-in
        bind 127.0.0.1:8002
        bind ::1:8002
        default_backend be

    backend be
        server localhost localhost:8080
  '';

  daemon = "${pkgs.haproxy}/bin/haproxy";
  kill = "${pkgs.coreutils}/bin/kill";

in
{
  options = with lib; with types; {
    flyingcircus.services.haproxy = {
      enable = mkEnableOption "FC-customized HAproxy";
    } // (import ./config-options.nix { inherit lib; });
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {

      environment.etc = {
        "local/haproxy/README.txt".text = ''
          HAProxy is enabled on this machine.

          Put your main haproxy configuration here as e.g. `haproxy.cfg`.
          There is also an example configuration here.

          If you need more than just one centralized configuration file,
          add more files named `*.cfg` here. They will get merged along
          in alphabetical order and used as `haproxy.cfg`.
        '';
        "local/haproxy/haproxy.cfg.example".text = example;
      };

      environment.systemPackages = [
        (pkgs.writeScriptBin
          "haproxy-show-config"
          "cat /etc/haproxy.cfg")
      ];

      flyingcircus.services = {
        sensu-client.checks.haproxy_config = {
          notification = "HAProxy configuration check problems";
          command = "${daemon} -f /etc/haproxy.cfg -c || exit 2";
          interval = 300;
        };

        telegraf.inputs = {
          prometheus  = [ { urls = [ "http://localhost:9127/metrics" ]; } ];
        };
      };

      flyingcircus.syslog.separateFacilities = {
        local2 = "/var/log/haproxy.log";
      };

      services.haproxy.enable = true;
      services.haproxy.config = haproxyCfgContent;

      systemd.services.haproxy = {
        reloadIfChanged = true;
        serviceConfig = {
          AmbientCapabilities = lib.mkOverride 90 [
            "CAP_NET_BIND_SERVICE"
            "CAP_SYS_CHROOT"
          ];
          CapabilityBoundingSet = [
            "CAP_NET_BIND_SERVICE"
            "CAP_SYS_CHROOT"
          ];
        };
      };

      flyingcircus.localConfigDirs.haproxy = {
        dir = "/etc/local/haproxy";
        user = "haproxy";
      };

      flyingcircus.services.sensu-client.checkEnvPackages = [
        pkgs.fc.check-haproxy
      ];

      # Upstream reload code hangs for a long time when the socket is missing.
      systemd.services.haproxy.serviceConfig.ExecReload = lib.mkOverride 90 [
        (pkgs.writeScript "haproxy-reload" ''
          #!${pkgs.runtimeShell} -e

          if [[ -S /run/haproxy/haproxy.sock ]]; then
            ${pkgs.haproxy}/sbin/haproxy -c -f /etc/haproxy.cfg
            ${pkgs.coreutils}/bin/ln -sf ${pkgs.haproxy}/sbin/haproxy /run/haproxy/haproxy
            ${pkgs.coreutils}/bin/kill -USR2 $MAINPID
          else
            echo Socket not present which is needed for reloading, restarting instead...
            ${pkgs.coreutils}/bin/kill $MAINPID
          fi
        '')
      ];

      systemd.services.prometheus-haproxy-exporter = {
        description = "Prometheus exporter for haproxy metrics";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        path = [ pkgs.haproxy ];
        script = ''
          exec ${pkgs.prometheus-haproxy-exporter}/bin/haproxy_exporter \
            --web.listen-address localhost:9127 \
            --haproxy.scrape-uri=unix:/run/haproxy/haproxy.sock
        '';
        serviceConfig = {
          User = "haproxy";
          Restart = "always";
          PrivateTmp = true;
          WorkingDirectory = "/tmp";
          ExecReload = "${kill} -HUP $MAINPID";
        };
      };

    })
  ];
}
