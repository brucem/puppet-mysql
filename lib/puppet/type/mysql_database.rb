# -*- tab-width: 4; ruby-indent-level: 4; indent-tabs-mode: t -*-
# This has to be a separate type to enable collecting
Puppet::Type.newtype(:mysql_database) do
	@doc = "Manage a database."
	ensurable
	newparam(:name) do
		desc "The name of the database."

		# TODO: only [[:alnum:]_] allowed
	end

	autorequire(:service) do
		["mysql"]
	end
	autorequire(:mysql_user) do
		["mysql root"]
	end
end

