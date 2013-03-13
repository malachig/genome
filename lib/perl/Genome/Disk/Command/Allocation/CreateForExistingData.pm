package Genome::Disk::Command::Allocation::CreateForExistingData;

use strict;
use warnings;

use Genome;

class Genome::Disk::Command::Allocation::CreateForExistingData {
    is => 'Command::V2',
    has => [
        target_path => {
            is => 'DirectoryPath',
            doc => 'Path at which data exists, allocation will be made to point to this location',
        },
        owner_class_name => {
            is => 'Text',
            default_value => 'Genome::Sys::User',
            doc => 'Class name of entity that owns the allocations (eg, Genome::Sys::User for users, or Genome::Model::Build::* for builds.',
        },
        owner_id => {
            is => 'Text',
            default_value => $ENV{USER} . '@genome.wustl.edu',
            doc => 'The ID used to retrieve the owner (in conjunction with owner_class_name), ' .
                   'e.g. bdericks@genome.wustl.edu for Genome::Sys::User or build_id for Genome::Model::Build.',
        },
        allocation => {
            is => 'Genome::Disk::Allocation',
            is_transient => 1,
            doc => 'Transient argument, not settable via command line. Useful for programmatic access to created allocation',
        },
    ],
    has_optional => [
        volume_prefix => {
            is => 'Text',
            default_value => '/gscmnt',
            doc => 'Volume prefix to expect at start of target_path',
        },
    ],
    doc => 'Creates an allocation for data that already exists on disk',
};

sub help_brief {
    return 'Creates an allocation for data that already exists on disk';
}

sub help_synopsis {
    return help_brief();
}

sub help_detail {
    return <<EOS
This tool creates an allocation for data that already exists. The 'typical'
allocation create process assumes that data does not already exist at the
location specified and will fail if this is not true. This command
works around this issue.
EOS
}

sub execute {
    my $self = shift;

    my $kb = $self->_validate_and_get_size_of_path;
    my ($mount_path, $group_subdir, $allocation_path) = $self->_parse_path;
    my $volume = $self->_get_and_validate_volume($mount_path);
    my $group = $self->_get_and_validate_group($group_subdir, $volume->groups);

    my %params = (
        disk_group_name => $group->disk_group_name,
        allocation_path => sprintf("%s-temp_allocation_path_for_existing_data", $allocation_path),
        kilobytes_requested => $kb,
        owner_class_name => $self->owner_class_name,
        owner_id => $self->owner_id,
        mount_path => $mount_path,
    );

    my $allocation = Genome::Disk::Allocation->create(%params);
    unless ($allocation) {
        require Data::Dumper;
        die "Could not create allocation with these params:\n" . Data::Dumper::Dumper(\%params);
    }

    $self->status_message("Created allocation " . $allocation->id . ", moving to final location");

    $allocation->allocation_path($allocation_path);
    unless ($allocation->absolute_path eq $self->target_path) {
        die "Somehow, absolute path of new allocation does not match expected value " . $self->target_path;
    }

    $self->allocation($allocation);
    return 1;
}

sub _parse_path {
    my $self = shift;
    my $volume_prefix = $self->volume_prefix;
    my ($mount_path, $group_subdir, $allocation_path) =
        $self->target_path =~  /($volume_prefix\/\w+)\/(\w+)\/(.+)/;
    unless ($mount_path and $group_subdir and $allocation_path) {
        die "Could not determine mount path, group subdirectory, or allocation path from given path!";
    }
    return ($mount_path, $group_subdir, $allocation_path);
}

sub _get_and_validate_volume {
    my ($self, $mount_path) = @_;
    my $volume = Genome::Disk::Volume->get(
        mount_path => $mount_path,
        disk_status => 'active',
        can_allocate => 1,
    );
    unless ($volume) {
        die "Found no allocatable and active volume with mount path $mount_path";
    }
    return $volume;
}

sub _get_and_validate_group {
    my ($self, $group_subdir, @groups) = @_;
    my $group;
    for my $candidate_group (@groups) {
        if ($candidate_group->subdirectory eq $group_subdir) {
            $group = $candidate_group;
            last;
        }
    }
    unless ($group) {
        die "No groups found with subdirectory that matches $group_subdir";
    }
    return $group;
}

sub _validate_and_get_size_of_path {
    my $self = shift;
    unless (-d $self->target_path) {
        die "Path does not exist: " . $self->target_path;
    }
    my $kb = Genome::Sys->disk_usage_for_path($self->target_path);
    unless (defined $kb) {
        die "Could not determine size of " . $self->target_path;
    }
    return $kb;
}

1;
