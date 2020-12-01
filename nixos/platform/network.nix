{ config, lib, pkgs, ... }:

with builtins;

let
  cfg = config.flyingcircus;

  fclib = config.fclib;

  interfaces = lib.attrByPath [ "parameters" "interfaces" ] {} cfg.enc;
  location = lib.attrByPath [ "parameters" "location" ] "" cfg.enc;

  # generally use DHCP in the current location?
  allowDHCP = location:
    if hasAttr location cfg.static.allowDHCP
    then cfg.static.allowDHCP.${location}
    else false;

  udev_rename_rules = pkgs.writeTextFile {
    name = "persistent-net-rules";
    destination = "/etc/udev/rules.d/61-fc-persistent-net.rules";
    text = if (interfaces != {}) then
        lib.concatMapStrings
          (vlan:
            let
              fallback = "02:00:00:${fclib.byteToHex (lib.toInt n)}:??:??";
              mac = lib.toLower
                (lib.attrByPath [ vlan "mac" ] fallback interfaces);
            in ''
              KERNEL=="eth*", ATTR{address}=="${mac}", NAME="eth${vlan}"
            '')
          (attrNames interfaces)
      else ''
        # static fallback rules for VMs
        KERNEL=="eth*", ATTR{address}=="02:00:00:02:??:??", NAME="ethfe"
        KERNEL=="eth*", ATTR{address}=="02:00:00:03:??:??", NAME="ethsrv"
      '';
  };

  # Policy routing
  rt_tables = ''
    # reserved values
    #
    255 local
    254 main
    253 default
    0 unspec
    #
    # local
    #
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (n : vlan : "${n} ${vlan}")
      cfg.static.vlans
    )}
    '';

  # add srv addresses from my own resource group to /etc/hosts
  hostsFromEncAddresses = encAddresses:
    let
      recordToEtcHostsLine = r:
      let hostName =
        if config.networking.domain != null
        then "${r.name}.${config.networking.domain} ${r.name}"
        else "${r.name}";
      in
        "${fclib.stripNetmask r.ip} ${hostName}";
    in
      # always mention IPv6 addresses first to get predictable behaviour
      lib.concatMapStringsSep "\n" recordToEtcHostsLine
        ((filter (a: fclib.isIp6 a.ip) encAddresses) ++
         (filter (a: fclib.isIp4 a.ip) encAddresses));

in
{
  options = {
    flyingcircus.network.policyRouting = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Enable policy routing? Automatically deselected for external network
          gateways.
        '';
      };

      extraRoutes = lib.mkOption {
        description = ''
          Add the given routes to every routing table. List items should be
          "ip route" command fragments without a "ip -[46] route {add,del}"
          prefix and a "table" suffix.
        '';
        default = [ ];
        type = with lib.types; listOf str;
        example = [
          "10.107.36.0/24 via 10.107.36.2 dev tun0"
        ];
      };

      requires = lib.mkOption {
        description = ''
          List of systemd services which are required to run before policy
          routing is started (e.g., because they define additional network
          interfaces).

          Note that the policy routing services will go down if one of the
          required services goes down.
        '';
        default = [ ];
        type = with lib.types; listOf str;
        example = [ "openvpn.service" ];
      };

    };
  };

  config = rec {
    environment.etc."iproute2/rt_tables".text = rt_tables;
    environment.etc."host.conf".text = ''
      order hosts, bind
      multi on
    '';

    networking = {
      nameservers =
        if (hasAttr location cfg.static.nameservers)
        then cfg.static.nameservers.${location}
        else [];

      # data structure for all configured interfaces with their IP addresses:
      # { ethfe = { ... }; ethsrv = { }; ... }
      interfaces =
        lib.mapAttrs'
          (vlan: iface:
            lib.nameValuePair
              "eth${vlan}"
              (fclib.interfaceConfig iface.networks))
          interfaces;

      resolvconf.extraOptions = [ "ndots:1" "timeout:1" "attempts:6" ];

      search = lib.optionals
        (location != "" && config.networking.domain != null)
        [ "${location}.${config.networking.domain}"
          config.networking.domain
        ];

      useDHCP = (interfaces == {});

      # DHCP settings: never do IPv4ll and don't use DHCP if there is explicit
      # network configuration present
      dhcpcd.extraConfig = ''
        # IPv4ll gets in the way if we really do not want
        # an IPv4 address on some interfaces.
        noipv4ll
      '';

      extraHosts = lib.optionalString
        (cfg.encAddresses != [])
        (hostsFromEncAddresses cfg.encAddresses);
    };

    systemd.network.links."30-vm-fallback-fe" = {
        matchConfig = {
            "OriginalName" = "*";
            "MACAddress" = "52:54:00:12:02:01";
        };
        linkConfig = {
            "NamePolicy" = "";
            "Name" = "ethfe";
        };
    };

    systemd.network.links."30-vm-fallback-srv" = {
        matchConfig = {
            "OriginalName" = "*";
            "MACAddress" = "52:54:00:12:01:01";
        };
        linkConfig = {
            "NamePolicy" = "";
            "Name" = "ethsrv";
        };
    };

    boot.initrd.extraUdevRulesCommands = ''
      cp ${udev_rename_rules}/etc/udev/rules.d/* $out/
    '';
    services.udev.packages = [ udev_rename_rules ];

    systemd.services =
      let startStopScript = if cfg.network.policyRouting.enable
        then fclib.policyRouting
        else fclib.simpleRouting;
      in
      { nscd.restartTriggers = [
          config.environment.etc."host.conf".source
        ];
      } //
      (listToAttrs
        (map
          (vlan: lib.nameValuePair
            "network-routing-eth${vlan}"
            rec {
              description = "Custom IP routing for eth${vlan}";
              after = [ "network-addresses-eth${vlan}.service" ];
              before = [ "network-local-commands.service" ];
              wantedBy = after;
              bindsTo = [ "sys-subsystem-net-devices-eth${vlan}.device" ] ++ after;
              path = [ fclib.relaxedIp ];
              script = startStopScript {
                vlan = "${vlan}";
                encInterface = interfaces.${vlan};
              };
              preStop = startStopScript {
                vlan = "${vlan}";
                encInterface = interfaces.${vlan};
                action = "stop";
              };
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
              };
            })
          (attrNames interfaces))) //
      (listToAttrs
        (map (vlan:
          let
            mac = lib.toLower interfaces.${vlan}.mac;
          in
          lib.nameValuePair
            "network-no-autoconf-eth${vlan}"
            rec {
              description = "Disable IPv6 SLAAC (autconf) on eth${vlan}";
              wantedBy = [ "network-addresses-eth${vlan}.service" ];
              before = wantedBy;
              path = [ pkgs.nettools pkgs.procps ];
              script = ''
                sysctl net.ipv6.conf.eth${vlan}.accept_ra=0
                sysctl net.ipv6.conf.eth${vlan}.autoconf=0
              '';
              preStop = ''
                sysctl net.ipv6.conf.eth${vlan}.accept_ra=1
                sysctl net.ipv6.conf.eth${vlan}.autoconf=1
              '';
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
              };
            })
          (attrNames interfaces)));

    boot.kernel.sysctl = {
      "net.ipv4.ip_nonlocal_bind" = "1";
      "net.ipv6.ip_nonlocal_bind" = "1";
      "net.ipv4.ip_local_port_range" = "32768 60999";
      "net.ipv4.ip_local_reserved_ports" = "61000-61999";
      "net.core.rmem_max" = 8388608;
    };
  };
}
