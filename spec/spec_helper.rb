# -*- mode: ruby; tab-width: 2; indent-tabs-mode: nil -*-
$LOAD_PATH.push(File.expand_path('../lib/zfs'))

require 'zfs'

shared_context "scratch-filesystem" do
  before(:all) do
    ZFS['/tank'].create("fs1")
    ZFS['/tank'].create("fs2")
  end

  after(:all) do
    ZFS['/tank/fs1'].destroy!
    ZFS['/tank/fs2'].destroy!
  end
end
