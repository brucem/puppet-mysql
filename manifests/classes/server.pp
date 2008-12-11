class mysql::server {
  $user     = "root"
  $password = generate("/usr/bin/pwgen", 8, 1)

  $mycnf = $operatingsystem ? {
    RedHat => "/etc/my.cnf",
    default => "/etc/mysql/my.cnf",
  }

  $mycnfctx = "/files/${mycnf}"

  user { "mysql":
    ensure => present,
    require => Package["mysql-server"],
  }

  package { "mysql-server":
    ensure => installed,
  }

  file { "/etc/mysql/my.cnf":
    ensure => present,
    path => $mycnf,
    owner => root,
    group => root,
    mode => 644,
    seltype => "mysqld_etc_t",
    require => Package["mysql-server"],
  }

  augeas { "my.cnf/mysqld":
    context => "$mycnfctx/mysqld/",
    changes => [
      "set pid-file /var/run/mysqld/mysqld.pid",
      "set old_passwords 0",
      "set character-set-server utf8",
      "set log-warnings 1",
      $operatingsystem ? {
        RedHat => "set log-error /var/log/mysqld.log",
        default => "set log-error /var/log/mysql.err",
      },
      $operatingsystem ? {
        RedHat => "set log-slow-queries /var/log/mysql-slow-queries.log",
        default => "set set log-slow-queries /var/log/mysql/mysql-slow.log",
      },
      #"ins log-slow-admin-statements after log-slow-queries", # not implemented in puppet yet
      $operatingsystem ? {
        RedHat => "set socket /var/lib/mysql/mysql.sock",
        default => "set socket /var/run/mysqld/mysqld.sock",
      }
    ],
    #require => File["/etc/mysql/my.cnf"], BUG: augeas changes file ownership
  }

  # by default, replication is disabled
  augeas { "my.cnf/replication":
    context => "$mycnfctx/mysqld/",
    changes => [
      "rm log-bin",
      "rm server-id",
      "rm master-host",
      "rm master-user",
      "rm master-password",
      "rm report-host"
    ],
    #require => File["/etc/mysql/my.cnf"], BUG: augeas changes file ownership
  }

  augeas { "my.cnf/mysqld_safe":
    context => "$mycnfctx/mysqld_safe/",
    changes => [
      "set pid-file /var/run/mysqld/mysqld.pid",
      $operatingsystem ? {
        RedHat => "set socket /var/lib/mysql/mysql.sock",
        default => "set socket /var/run/mysqld/mysqld.sock",
      }
    ],
    #require => File["/etc/mysql/my.cnf"], BUG: augeas changes file ownership
  }

  # force use of system defaults
  augeas { "my.cnf/performance":
    context => "$mycnfctx/",
    changes => [
     "rm mysqld/key_buffer",
     "rm mysqld/max_allowed_packet",
     "rm mysqld/table_cache",
     "rm mysqld/sort_buffer_size",
     "rm mysqld/read_buffer_size",
     "rm mysqld/read_rnd_buffer_size",
     "rm mysqld/net_buffer_length",
     "rm mysqld/myisam_sort_buffer_size",
     "rm mysqld/thread_cache_size",
     "rm mysqld/query_cache_size",
     "rm mysqld/thread_concurrency",
     "rm mysqld/thread_stack",
     "rm mysqldump/max_allowed_packet",
     "rm isamchk/key_buffer",
     "rm isamchk/sort_buffer_size",
     "rm isamchk/read_buffer",
     "rm isamchk/write_buffer",
     "rm myisamchk/key_buffer",
     "rm myisamchk/sort_buffer_size",
     "rm myisamchk/read_buffer",
     "rm myisamchk/write_buffer"
    ],
    #require => File["/etc/mysql/my.cnf"], BUG: augeas changes file ownership
  }

  augeas { "my.cnf/client":
    context => "$mycnfctx/client/",
    changes => [
      $operatingsystem ? {
        RedHat => "set socket /var/lib/mysql/mysql.sock",
        default => "set socket /var/run/mysqld/mysqld.sock",
      }
    ],
    #require => File["/etc/mysql/my.cnf"], BUG: augeas changes file ownership
  }

  service { "mysql":
    ensure      => running,
    name        => $operatingsystem ? {
      RedHat => "mysqld",
      default => "mysql",
    },
    require   => Package["mysql-server"],
    subscribe   => File["/etc/mysql/my.cnf"],
    # don't subscribe to augeas until this bug is fixed:
    # http://thread.gmane.org/gmane.comp.sysutils.augeas.devel/985/focus=9718
    #subscribe   => [File["/etc/mysql/my.cnf"], Augeas["my.cnf/mysqld"]],
  }

  exec { "Set MySQL server root password":
    unless      => "test -f /root/.my.cnf",
    command     => "mysqladmin -u${user} password ${password}",
    notify      => Exec["Generate my.cnf"],
    require     => [Package["mysql-server"], Service["mysql"]]
  }

  exec { "Generate my.cnf":
    command     => "echo -e \"[mysql]\nuser=${user}\npassword=${password}\n[mysqladmin]\nuser=${user}\npassword=${password}\n[mysqldump]\nuser=${user}\npassword=${password}\n\" > /root/.my.cnf",
    refreshonly => true,
    creates     => "/root/.my.cnf",
  }

  file { "/root/.my.cnf":
    owner => root,
    group => root,
    mode  => 600,
  }

  file { "/var/backups":
    ensure  => directory,
    owner   => "root",
    group   => "root",
    mode    => 755,
  }

  file { "/var/backups/mysql":
    ensure  => directory,
    owner   => "root",
    group   => "root",
    mode    => 750,
    require => File["/var/backups"]
  }

  file { "/usr/local/bin/mysql-backup.sh":
    ensure => present,
    source => "puppet:///mysql/mysql-backup.sh",
    owner => "root",
    group => "root",
    mode  => 555,
  }

  cron { "mysql-backup":
    command => "/usr/local/bin/mysql-backup.sh week",
    user    => "root",
    hour    => 2,
    minute  => 0,
    require => [File["/var/backups/mysql"], File["/usr/local/bin/mysql-backup.sh"]],
  }

  file { "/etc/logrotate.d/mysql-server":
    ensure => present,
    source => $operatingsystem ? {
      RedHat => "puppet:///mysql/logrotate.redhat",
      default => undef,
    }
  }

  define rights($database, $user, $password, $ensure=true) {
    case $ensure {
      present:{
        exec {"Set rigths for db ${database}":
          command => "mysql -e \"GRANT ALL PRIVILEGES on ${database}.* TO ${user}@localhost IDENTIFIED BY '${password}';\"",
          unless  => "mysql --database=${database} --user=${user} --password=${password} -A -e 'exit'",
          require => Exec["Set MySQL server root password"],
        }
      }

      absent:{
        exec {"unsert rights for db ${database}":
          command => "mysql -e \"REVOKE ALL PRIVILEGES on ${database}.* FROM ${user}@localhost;\"",
          onlyif  => "mysql --database=${database} --user=${user} --password=${password} -A -e 'exit'",
          require => Exec["Set MySQL server root password"],
        }
      }
    }
  }
}
