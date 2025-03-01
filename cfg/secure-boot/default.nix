{ meta, tf, inputs, pkgs, config, lib, ... }: with lib; let
  inherit (tf) resources;
  secureboot_cert_config = tf.runners.pkgs.writeText "secureboot-openssl.cnf" ''
    subjectKeyIdentifier    = hash
    authorityKeyIdentifier  = keyid:always,issuer
    basicConstraints        = critical,CA:FALSE
    extendedKeyUsage        = codeSigning,1.3.6.1.4.1.311.10.3.6,1.3.6.1.4.1.2312.16.1.2
    nsComment               = "${meta.deploy.idTag} Secure Boot Certificate"
  '';
in {
  config = {
    boot.loader.secure-boot = mkIf tf.state.enable {
      enable = mkDefault true;
      keyPath = config.secrets.files.secureboot-key.path;
      certPath = "${pkgs.writeText "secureboot.pem" (resources.secureboot_cert_pem.getAttr "content")}";
    };
    secrets.files.secureboot-key.text = resources.secureboot_key.refAttr "private_key_pem";
    deploy.tf.resources = {
      secureboot_key = {
        provider = "tls";
        type = "private_key";
        inputs = {
          algorithm = "RSA";
          rsa_bits = 2048;
        };
      };
      secureboot_key_file = {
        provider = "local";
        type = "sensitive_file";
        inputs = {
          filename = toString tf.terraform.dataDir + "/secureboot-key.pem";
          content = resources.secureboot_key.refAttr "private_key_pem";
        };
      };
      secureboot_csr = {
        provider = "tls";
        type = "cert_request";
        inputs = {
          private_key_pem = resources.secureboot_key.refAttr "private_key_pem";

          subject = {
            common_name = "secureboot.${config.networking.hostName}.${config.networking.domain}";
            organization = "arcnmx";
            organizational_unit = "secureboot";
          };
        };
      };
      secureboot_csr_file = {
        provider = "local";
        type = "file";
        inputs = {
          filename = toString tf.terraform.dataDir + "/secureboot-csr.pem";
          content = resources.secureboot_csr.refAttr "cert_request_pem";
        };
      };
      secureboot_cert = {
        provider = "null";
        type = "resource";
        inputs.triggers = {
          csr = resources.secureboot_csr.refAttr "id";
          epoch = 0;
        };
        provisioners = singleton {
          local-exec.command = toString [
            "${tf.runners.pkgs.openssl}/bin/openssl x509"
            "-days 358000"
            "-extfile ${secureboot_cert_config}"
            "-signkey ${resources.secureboot_key_file.refAttr "filename"}"
            "-req -in ${resources.secureboot_csr_file.refAttr "filename"}"
            "-outform PEM -out ${resources.secureboot_cert_pem.inputs.filename}"
          ];
        };
      };
      secureboot_cert_pem = {
        provider = "local";
        type = "file";
        dataSource = true;
        inputs.filename = toString tf.terraform.dataDir + "/secureboot.pem";

        dependsOn = [
          resources.secureboot_cert.namedRef
        ];
      };
    };
  };
}
