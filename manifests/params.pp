#
class mysql::params {

  $mycnf = $::operatingsystem ? {
    /RedHat|Fedora|CentOS/ => '/etc/my.cnf',
    default => '/etc/mysql/my.cnf',
  }

  $mycnfctx = "/files/${mycnf}"

  $data_dir = $mysql::params::mysql_data_dir ? {
    ''      => '/var/lib/mysql',
    default => $mysql::params::mysql_data_dir,
  }

  $backup_dir = $mysql::params::mysql_backupdir ? {
    ''      => '/var/backups/mysql',
    default => $mysql::params::mysql_backupdir,
  }

  $replication_binlog_format = $mysql::params::replication_binlog_format ? {
    ''      => 'STATEMENT',
    default => $mysql::params::replication_binlog_format,
  }

}
