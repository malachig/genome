#!/usr/bin/env genome-perl

BEGIN { 
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use strict;
use warnings;

use above "Genome";
use Test::More;

my $pkg = 'Genome::Process::WithVcf';
use_ok($pkg) || die;
my $code_test_dir = __FILE__ . '.d';

{
    package TestProcess;

    use strict;
    use warnings FATAL => 'all';
    use Genome;

    class TestProcess {
        is => [$pkg],
    };
}
my $p = TestProcess->create();
ok($p, "Created TestProcess object");

my %tests = (
    filedate_diff  => {
        test_name  => 'Only filedate diffs',
        diff_count => 0,
    },
    other_diff => {
        test_name => 'Real vcf diff',
        diff_count => 1,
        diff_message => 'files are not the same',
    },
);

while (my ($subdir, $test_info) = each %tests) {
    subtest $test_info->{test_name} => sub {
        my $original_dir = File::Spec->join($code_test_dir, 'original');
        my $other_dir    = File::Spec->join($code_test_dir, $subdir);
        my %diffs = $p->_compare_output_directories($original_dir, $other_dir, $p);
        is(scalar(keys %diffs), $test_info->{diff_count}, 'Number of differences as expected');
        if (scalar(keys %diffs) > 0) {
            like((values %diffs)[0], qr/$test_info->{diff_message}/, 'Diff message as expected');
        }
    };
}
done_testing;
