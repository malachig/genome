#!/usr/bin/env genome-perl

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use strict;
use warnings;

use above "Genome";

use Data::Dumper 'Dumper';
use Test::More;

use_ok('Genome::Library') or die;

my $sample = Genome::Sample->create(name => '__TEST_SAMPLE__');
ok($sample, 'create sample');
my $library = Genome::Library->create(
    sample => $sample,
    name => $sample->name . "-extlibs",
    original_insert_size => '1kb',
    library_insert_size => '300-500',
    protocol => 'karate chop',
    transcript_strand => 'unstranded',
);
ok($library, 'create library');
isa_ok($library, 'Genome::Library');
isa_ok($library, 'Genome::Notable');
is($library->name, $sample->name . "-extlibs", "name is what is expected");

my $commit = eval{ UR::Context->commit; };
ok($commit, 'commit');

done_testing();
