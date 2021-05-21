{ lib, ... }:
with lib; with types; let

globalOptions = {
  daemon = mkOption {
    default = true;
    type = bool;
  };
  chroot = mkOption {
    default = "/var/empty";
    type = str;
  };
  user = mkOption {
    default = "haproxy";
    type = str;
  };
  group = mkOption {
    default = "haproxy";
    type = str;
  };
  maxconn = mkOption {
    default = 4096;
    type = int;
  };
  extraOptions = mkOption {
    default = ''
      log localhost local2
      # Increase buffers for large URLs
      tune.bufsize 131072
      tune.maxrewrite 65536
    '';
    type = lines;
  };
};

defaultsOptions = {
  mode = mkOption {
    default = "http";
    type = enum [ "tcp" "http" "health" ];
  };
  options = mkOption {
    default = [
      "httplog"
      "dontlognull"
      "http-server-close"
    ];
    type = listOf str;
  };
  timeout = mkOption {
    default = {
      connect = "5s";
      client = "30s";
      server = "30s";
      queue = "25s";
    };
    type = submodule {
      options = timeoutOptions;
    };
  };
  extraOptions = mkOption {
    default = ''
      log global
    '';
    type = lines;
  };
};

timeoutOptions = let
    timeoutOption = mkOption { default = null; type = nullOr str; };
  in {
    check = timeoutOption;
    client = timeoutOption;
    client-fin = timeoutOption;
    connect = timeoutOption;
    http-keep-alive = timeoutOption;
    http-request = timeoutOption;
    queue = timeoutOption;
    server = timeoutOption;
    server-fin = timeoutOption;
    tarpit = timeoutOption;
    tunnel = timeoutOption;
  };

listenOptions = frontendOptions // backendOptions;

frontendOptions = {
  binds = mkOption {
    default = [];
    type = listOf str;
  };
  default_backend = mkOption {
    default = null;
    type = nullOr str;
  };
  extraOptions = mkOption {
    default = "";
    type = lines;
  };
};

backendOptions = {
  servers = mkOption {
    default = [];
    type = listOf str;
  };
  extraOptions = mkOption {
    default = "";
    type = lines;
  };
};

in {
  global = mkOption {
    default = {};
    type = submodule {
      options = globalOptions;
    };
  };
  defaults = mkOption {
    default = {};
    type = submodule {
      options = defaultsOptions;
    };
  };
  listens = mkOption {
    default = {
      http-in = {
        binds = [
          "127.0.0.1:8002"
          "::1:8002"
        ];
        default_backend = "be";
      };
    };
    type = attrsOf (submodule {
      options = listenOptions;
    });
  };
  frontends = mkOption {
    default = {};
    type = attrsOf (submodule {
      options = frontendOptions;
    });
  };
  backends = mkOption {
    default = {
      be = {
        servers = [
          "localhost localhost:8080"
        ];
      };
    };
    type = attrsOf (submodule {
      options = backendOptions;
    });
  };
}