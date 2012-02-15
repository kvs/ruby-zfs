# -*- mode: ruby; tab-width: 2; indent-tabs-mode: nil -*-

require 'spec_helper'

# Basic list
describe ZFS do
  # Initially, the test-system has only 'tank', so this is what we're assuming here

  describe ".filesystems" do
    subject { ZFS.filesystems }
    it { should be_an_instance_of Enumerator }
    it "should list all filesystems" do
      subject.to_a.length.should eq 1
      subject.first.name.should eq "tank"
    end
  end

  describe ".mountpoints" do
    subject { ZFS.mountpoints }
    it { should be_an_instance_of Enumerator }
    it "should list all mountpoints" do
      subject.to_a.length.should eq 1
      subject.first[0].should eq "/tank"
      subject.first[1].should eq ZFS.filesystems.first
    end
  end

  it "should be able to fetch filesystems by zpool-path" do
    ZFS['tank'].should be_an_instance_of ZFS::Filesystem
  end

  it "should be able to fetch filesystems by mountpoint" do
    ZFS['/tank'].should eq ZFS['tank']
  end
end

# Basic create/destroy
describe ZFS do
  it "should be able to create filesystems" do
    ZFS.filesystems.to_a.length.should eq 1
    fs = ZFS.create("tank/fs1")
    ZFS.filesystems.to_a.length.should eq 2
    fs.destroy!
    ZFS.filesystems.to_a.length.should eq 1
  end
end

describe ZFS::Filesystem do
  it "should be valid across destroy/re-create" do
    fs = ZFS.create('tank/fs1')
    fs.should be_an_instance_of ZFS::Filesystem
    fs.should be_valid
    fs.destroy!
    fs.should_not be_valid

    fs2 = ZFS.create('tank/fs1')
    fs.should be_valid
    fs.should eq fs2
    fs.object_id.should eq fs2.object_id
    fs.destroy!
    fs.should_not be_valid
  end
end

# Tests with more filesystems
describe ZFS::Filesystem do
  include_context "scratch-filesystem"

  it "should be able to find specific filesystems" do
    ZFS['/tank'].to_s.should eq '#<ZFS:tank>'
    ZFS['/tank'].should eq ZFS['tank']

    ZFS['/tank/fs1'].to_s.should eq '#<ZFS:tank/fs1>'
    ZFS['/tank/fs1'].should eq ZFS['tank/fs1']
    ZFS['/tank/fs1'].should_not eq ZFS['/tank/fs2']

    # Find parent
    ZFS['/tank/fs1/dir1', true].should eq ZFS['/tank/fs1']
    ZFS['/tank/fs1/dir1', false].should be_nil
  end
end

describe ZFS::Filesystem do
  subject { ZFS['tank/fs1'] }

  include_context "scratch-filesystem"

  it "should support snapshots" do
    subject.snapshots.should eq []
    snapshot = subject.snapshot!('snap1')
    snapshots = subject.snapshots
    snapshot.should be_valid
    snapshot.destroy!
    snapshots.first.name.should eq 'tank/fs1@snap1'
    snapshot.should_not be_valid

    subject.snapshot!('snap1')
    subject.snapshot!('snap2')
    subject.snapshots.size.should eq 2
    subject.snapshots.each do |snap|
      snap.should be_an_instance_of ZFS::Snapshot
      snap.destroy!
    end
  end

  it "should support clones" do
    snapshot = subject.snapshot!('test')
    clone = snapshot.clone!('tank/clonefs')
    clone.should be_an_instance_of ZFS::Filesystem
    clone.should eq ZFS['/tank/clonefs']
    clone['origin'].should eq snapshot.name

    clone.destroy!
    ZFS['/tank/clonefs'].should be_nil

    snapshot.destroy!
    subject.snapshots.should eq []
  end
end
