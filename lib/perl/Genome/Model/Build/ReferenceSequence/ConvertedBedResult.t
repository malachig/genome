#!/usr/bin/perl

BEGIN { 
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use strict;
use warnings;

use above "Genome";
use Test::More;
use Sub::Install;
use Genome::Utility::Test qw(compare_ok);
use File::Slurp qw(write_file);
my $class = 'Genome::Model::Build::ReferenceSequence::ConvertedBedResult';

Sub::Install::reinstall_sub({
    into => 'Genome::Model::Build::ReferenceSequence::Converter',
    as => 'convert_bed',
    code => sub { my ($class, $source_bed, $source_reference, $destination_bed, $destination_reference) = @_;
                  Genome::Sys->copy_file($source_bed, $destination_bed);
                  return $destination_bed;
                },
});

my $reference_build = Genome::Model::Build::ReferenceSequence->__define__;
my $bed_path = Genome::Sys->create_temp_file_path;
write_file($bed_path, "Some content!\n");
note("Wrote some content to bed at ($bed_path)");

my $result = $class->get_or_create(
    source_reference => $reference_build,
    target_reference => $reference_build,
    source_bed => $bed_path,
    source_md5 => Genome::Sys->md5sum($bed_path),
);

ok($result, "Got a software result");

my $kilo = $result->_staging_kilobytes_requested;
ok(defined $kilo, "staging kilobytes requested returns something ($kilo)");

my $target_bed = $result->target_bed;
ok(defined $target_bed, "Got a target_bed ($target_bed)");

compare_ok($bed_path, $target_bed, "Target bed contains what we expect");

done_testing();
