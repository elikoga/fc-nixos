{ lib, ... }:
with lib; with types; let

in {
  global = mkOption {
    default = {
      daemon = true;
      chroot = "/var/empty";
      maxconn = "4096";
      log = "localhost local2";
    };
    type = attrsOf (oneOf [
      bool
      str
    ]);
  };
  defaults = mkOption {
    default = {
      mode = "http";
      log = "global";
      option = [
        "httplog"
        "dontlognull"
        "http-server-close"
      ];
      timeout = [
        "connect 5s"
        "client 10m"
        "server 10m"
        "queue 25s"
      ];
    };
    type = attrsOf (oneOf [
      str
      (listOf str)
    ]);
  };
  proxies = mkOption {
    default = {
      "http-in" = {
        section = "listen";
        bind = [
          "127.0.0.1:8002"
          "::1:8002"
        ];
        default_backend = "be";
      };
      "be" = {
        section = "backend";
        server = "localhost localhost:8080";
      };
    };
    type = attrsOf (
      addCheck (
        attrsOf (oneOf [
          str
          (listOf str)
        ])
      ) (proxy: builtins.typeOf proxy.section == "string")
    );
  };
}