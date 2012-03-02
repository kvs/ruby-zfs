# -*- mode: ruby; tab-width: 4; indent-tabs-mode: t -*-
$LOAD_PATH.push(File.expand_path('../lib/zfs'))

require 'zfs'
require 'open4'

shared_context "vagrant" do
	before(:all) do
		ZFS.zfs_path   = %w(ssh vagrant-zfs sudo zfs)
		ZFS.zpool_path = %w(ssh vagrant-zfs sudo zpool)
	end

	after(:all) do
		Open4::spawn([*ZFS.zfs_path]+['destroy -r tank/foo'], ignore_exit_failure: true)
		Open4::spawn([*ZFS.zfs_path]+['destroy -r tank/bar'], ignore_exit_failure: true)

		ZFS.zfs_path   = 'zfs'
		ZFS.zpool_path = 'zpool'
	end
end
