# -*- tab-width: 4; ruby-indent-level: 4; indent-tabs-mode: t -*-
require 'puppet/provider/package'
Puppet::Type.type(:mysql_user).provide :mysql, :parent => Puppet::Provider::Package  do

	desc "Use mysql as database."
	# this is a bit of a hack.
	# Since puppet evaluates what provider to use at start time rather than run time
	# we can't specify that commands will exist. Instead we call manually.
	# I would make these call execute directly, but execpipe needs the path
	def self.mysqladmin
		'/usr/bin/mysqladmin'
	end
	def self.mysql
		'/usr/bin/mysql'
	end
	def mysqladmin
		self.class.mysqladmin
	end
	def mysql
		self.class.mysql
	end

	# retrieve the current set of mysql users
	def self.instances
		users = []

		cmd = "#{mysql} mysql -NBe 'select concat(user, \"@\", host), password from user'"
		execpipe(cmd) do |process|
			process.each do |line|
				users << new( query_line_to_hash(line) )
			end
		end
		return users
	end

	def self.query_line_to_hash(line)
		fields = line.chomp.split(/\t/)
		{
			:name => fields[0],
			:password_hash => fields[1],
			:ensure => :present
		}
	end

	def mysql_flush 
		execute([mysqladmin, "flush-privileges"])
	end

	def query
		result = {}

		cmd = "#{mysql} -NBe 'select concat(user, \"@\", host), password from user where concat(user, \"@\", host) = \"%s\"'" % @resource[:name]
		execpipe(cmd) do |process|
			process.each do |line|
				unless result.empty?
					raise Puppet::Error,
						"Got multiple results for user '%s'" % @resource[:name]
				end
				result = query_line_to_hash(line)
			end
		end
		result
	end

	def create
		# There is a longstanding MySQL bug where a user that does not appear to exist (previously deleted, etc) still cannot be created.
		# http://bugs.mysql.com/bug.php?id=28331
		# A workaround is to unconditionally drop the user and ignore the return value
		execute([mysql, "mysql", "-e", "drop user '%s'" % [ @resource[:name].sub("@", "'@'") ]],
				{:failonfail => false})
		execute [mysql, "mysql", "-e", "create user '%s' identified by PASSWORD '%s'" % [ @resource[:name].sub("@", "'@'"), @resource.should(:password_hash) ]]
		mysql_flush
	end

	def destroy
		execute [mysql, "mysql", "-e", "drop user '%s'" % @resource[:name].sub("@", "'@'")]
		mysql_flush
	end

	def exists?
		not execute([mysql, "mysql", "-NBe", "select '1' from user where CONCAT(user, '@', host) = '%s'" % @resource[:name]]).empty?
	end

	def password_hash
		@property_hash[:password_hash]
	end

	def password_hash=(string)
		execute [mysql, "mysql", "-e", "SET PASSWORD FOR '%s' = '%s'" % [ @resource[:name].sub("@", "'@'"), string ]]
		mysql_flush
	end
end

