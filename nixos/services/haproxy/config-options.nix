{ lib, ... }:
with lib; with types; let

globalOptions = {
  daemon = mkOption {
    default = true;
    type = bool;
    description = ''
      # `daemon`
      Makes the process fork into background. This is the recommended mode of
      operation. It is equivalent to the command line "-D" argument. It can be
      disabled by the command line "-db" argument. This option is ignored in
      systemd mode.
    '';
    example = false;
  };
  chroot = mkOption {
    default = "/var/empty";
    type = str;
    description = ''
      # `chroot <jail dir>`
      Changes current directory to <jail dir> and performs a chroot() there before
      dropping privileges. This increases the security level in case an unknown
      vulnerability would be exploited, since it would make it very hard for the
      attacker to exploit the system. This only works when the process is started
      with superuser privileges. It is important to ensure that <jail_dir> is both
      empty and non-writable to anyone.
    '';
    example = "/var/lib/haproxy";
  };
  user = mkOption {
    default = "haproxy";
    type = str;
    description = ''
      # `user <user name>`
      Changes the process's user ID to UID of user name <user name> from /etc/passwd.
      It is recommended that the user ID is dedicated to HAProxy or to a small set
      of similar daemons. HAProxy must be started with superuser privileges in order
      to be able to switch to another one.
    '';
    example = "hapuser";
  };
  group = mkOption {
    default = "haproxy";
    type = str;
    description = ''
      # `group <group name>`
      Changes the process's group ID to the GID of group name <group name> from
      /etc/group. It is recommended that the group ID is dedicated to HAProxy
      or to a small set of similar daemons. HAProxy must be started with a user
      belonging to this group, or with superuser privileges. Note that if haproxy
      is started from a user having supplementary groups, it will only be able to
      drop these groups if started with superuser privileges.

    '';
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
  extraOptions = mkOption {
    default = "";
    type = lines;
  };
}