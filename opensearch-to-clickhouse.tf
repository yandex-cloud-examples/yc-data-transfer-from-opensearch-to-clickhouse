# Infrastructure for Managed Service for OpenSearch cluster, Managed Service for ClickHouse cluster, and Data Transfer.

# RU: https://cloud.yandex.ru/ru/docs/data-transfer/tutorials/opensearch-to-clickhouse
# EN: https://cloud.yandex.com/en/docs/data-transfer/tutorials/opensearch-to-clickhouse

# Specify the following settings:
locals {
  # Settings for the Managed Service for OpenSearch cluster:
  source_admin_password = "password" # Password of user in Managed Service for OpenSearch

  # Settings for the Managed Service for ClickHouse cluster:
  mch_db_name       = "db1"      # Name of the Managed Service for ClickHouse database
  mch_username      = "user1"    # Name of the Managed Service for ClickHouse user
  mch_user_password = "password" # Password of the Managed Service for ClickHouse user

  # Specify these settings ONLY AFTER the clusters are created. Then run "terraform apply" command again.
  # You should set up endpoints using the GUI to obtain their IDs
  source_endpoint_id = "" # Source endpoint ID

  # The following settings are predefined. Change them only if necessary.
  opensearch_port      = 9200                  # Managed Service for OpenSearch port for Internet connection  
  mch_https_port       = 8443                  # Managed Service for ClickHouse HTTPS port
  mch_client_port      = 9440                  # Managed Service for ClickHouse client port
  network_name         = "mynet"               # Name of the network for Managed Service for OpenSearch cluster and Managed Service for ClickHouse cluster
  subnet_name          = "mysubnet"            # Name of the subnet for Managed Service for OpenSearch cluster and Managed Service for ClickHouse cluster
  sg_name              = "mos-mch-sg"          # Name of the security group for Managed Service for OpenSearch cluster and Managed Service for ClickHouse cluster
  mos_cluster_name     = "mos-cluster"         # Name of the Managed Service for OpenSearch cluster
  mos_version          = "2.8"                 # Version of the Managed Service for OpenSearch cluster   
  node_group_name      = "mos-group"           # Node group name in the Managed Service for OpenSearch cluster
  dashboards_name      = "dashboards"          # Name of the dashboards node group in the Managed Service for OpenSearch cluster
  mch_cluster_name     = "mch-cluster"         # Name of the Managed Service for ClickHouse cluster
  target_endpoint_name = "mch-target"          # Name of the target endpoint
  transfer_name        = "mos-to-mch-transfer" # Name of the Data Transfer
}

resource "yandex_vpc_network" "mynet" {
  description = "Network for Managed Service for OpenSearch cluster and Managed Service for ClickHouse cluster"
  name        = local.network_name
}

resource "yandex_vpc_subnet" "mysubnet" {
  description    = "Subnet for for Managed Service for OpenSearch cluster and Managed Service for ClickHouse cluster"
  name           = local.subnet_name
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.mynet.id
  v4_cidr_blocks = ["10.1.0.0/16"]
}

resource "yandex_vpc_security_group" "mos-mch-sg" {
  description = "Security group for Managed Service for OpenSearch cluster and Managed Service for ClickHouse cluster"
  name        = local.sg_name
  network_id  = yandex_vpc_network.mynet.id

  ingress {
    description    = "Allow connections to the Managed Service for OpenSearch cluster from the Internet"
    protocol       = "TCP"
    port           = local.opensearch_port
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description    = "Allow connections to the Managed Service for ClickHouse via HTTPS"
    port           = local.mch_https_port
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description    = "Allow connections to the Managed Service for ClickHouse via Clickhouse-client"
    port           = local.mch_client_port
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description    = "The rule allows all outgoing traffic"
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }
}

resource "yandex_mdb_opensearch_cluster" "my-os-clstr" {
  description        = "Managed Service for OpenSearch cluster"
  name               = local.mos_cluster_name
  environment        = "PRODUCTION"
  network_id         = yandex_vpc_network.mynet.id
  security_group_ids = [yandex_vpc_security_group.mos-mch-sg.id]

  config {

    version        = local.mos_version
    admin_password = local.source_admin_password

    opensearch {
      node_groups {
        name             = local.node_group_name
        assign_public_ip = true
        hosts_count      = 1
        zone_ids         = ["ru-central1-a"]
        subnet_ids       = [yandex_vpc_subnet.mysubnet.id]
        roles            = ["DATA", "MANAGER"]
        resources {
          resource_preset_id = "s2.micro"  # 2 vCPU, 8 GB RAM
          disk_size          = 10737418240 # Bytes
          disk_type_id       = "network-ssd"
        }
      }
    }

    dashboards {
      node_groups {
        name        = local.dashboards_name
        hosts_count = 1
        zone_ids    = ["ru-central1-a"]
        subnet_ids  = [yandex_vpc_subnet.mysubnet.id]
        resources {
          resource_preset_id = "s2.micro"  # 2 vCPU, 8 GB RAM
          disk_size          = 10737418240 # Bytes
          disk_type_id       = "network-ssd"
        }
      }
    }
  }

  maintenance_window {
    type = "ANYTIME"
  }
}

resource "yandex_mdb_clickhouse_cluster" "mych" {
  description        = "Managed Service for ClickHouse cluster"
  name               = local.mch_cluster_name
  environment        = "PRESTABLE"
  network_id         = yandex_vpc_network.mynet.id
  security_group_ids = [yandex_vpc_security_group.mos-mch-sg.id]

  clickhouse {
    resources {
      resource_preset_id = "s2.micro"
      disk_type_id       = "network-ssd"
      disk_size          = 32
    }
  }

  host {
    type      = "CLICKHOUSE"
    zone      = "ru-central1-a"
    subnet_id = yandex_vpc_subnet.mysubnet.id
  }

  database {
    name = local.mch_db_name
  }

  user {
    name     = local.mch_username
    password = local.mch_user_password
    permission {
      database_name = local.mch_db_name
    }
  }
}

resource "yandex_datatransfer_endpoint" "managed-clickhouse-target" {
  description = "Target endpoint for the Managed Service for ClickHouse cluster"
  name        = local.target_endpoint_name
  settings {
    clickhouse_target {
      connection {
        connection_options {
          mdb_cluster_id = yandex_mdb_clickhouse_cluster.mych.id
          database       = local.mch_db_name
          user           = local.mch_username
          password {
            raw = local.mch_user_password
          }
        }
      }
    }
  }
}

# Uncomment this block ONLY AFTER creating source endpoint and setting source ID variable.
# After uncommenting run `terraform apply` again.
# resource "yandex_datatransfer_transfer" "mos-to-mch-transfer" {
#  description = "Transfer from the Managed Service for OpenSearch cluster to the Managed Service for ClickHouse cluster"
#  name        = local.transfer_name
#  source_id   = local.source_endpoint_id
#  target_id   = yandex_datatransfer_endpoint.managed-clickhouse-target.id
#  type        = "SNAPSHOT_ONLY" # Copy all data from the source server
#}
