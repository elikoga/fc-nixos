{ config, lib, ... }:

{
  config = lib.mkIf (config.flyingcircus.infrastructureModule == "container") {

    networking.firewall.allowedTCPPorts = [ 80 ];
    networking.firewall.allowPing = true;

    boot.isContainer = true;

    # boot.loader.grub.enable = false
    # networking.useHostResolvConf = true;
    # networking.hostName = "ct-dir-dev";
    # fileSystems."/" = lib.mkOverride 90 {
    #    fsType = "xfs";
    #    device = "/dev/null";
    # };

    services.telegraf.enable = false;
    flyingcircus.agent.enable = false;

    services.timesyncd.servers = [ "pool.ntp.org" ];

    users.users.root.password = "";

    systemd.services."network-addresses-ethsrv" = {
      wantedBy = [ "multi-user.target" ];
      script = ''
        echo "Ready."
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };

    environment.shellInit = ''
      export NIX_REMOTE=daemon
    '';

    networking.hostName = "ct-dir-dev";

    services.postgresql.settings.listen_addresses = lib.mkOverride 20 "0.0.0.0,::";

    services.mysql.extraOptions= ''
      [mysqld]
      # We don't really care about the data and this speeds up things.
      innodb_flush_method = nosync

      innodb_buffer_pool_size         = 200M
      innodb_log_buffer_size          = 64M
      innodb_file_per_table           = 1
      innodb_read_io_threads          = 1
      innodb_write_io_threads         = 1
      # Percentage. Probably needs local tuning depending on the workload.
      innodb_change_buffer_max_size   = 50
      innodb_doublewrite              = 1
      innodb_log_file_size            = 64M
      innodb_log_files_in_group       = 2
    '';

    services.postgresql.settings.fsync = "off";
    services.postgresql.settings.full_page_writes = "off";
    services.postgresql.settings.synchronous_commit = "off";

    services.redis.bind = lib.mkForce "0.0.0.0 ::";

    services.consul.enable = true;
    services.consul.extraConfig = {
      acl_master_token = "4369DAF2-6D0B-4AC8-BB32-94DE29B7FE1E";
      encrypt = "wrzotzhclj233L4twI/qNrHT+jhGOuXt6UcAQYsfHEY=";
      server = true;
      bootstrap = true;
      datacenter = "services";
      acl_default_policy = "deny";
    };
    # services.consul.interface.bind = "ethsrv";

  networking.extraHosts = ''
    127.0.0.1 consul-ext.service.services.vgr.consul.local
    ::1 consul-ext.service.services.vgr.consul.local
  '';

  };
}
