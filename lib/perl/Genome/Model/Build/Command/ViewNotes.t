#!/usr/bin/env genome-perl

use strict;
use warnings;

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
};

use above "Genome";
use Test::More tests => 10;

use_ok('Genome::Model::Build::Command::ViewNotes');

class Genome::Model::Tester { is => 'Genome::ModelDeprecated', };

my $s = Genome::Sample->create(name => 'TEST-' . __FILE__ . "-$$");
ok($s, "made a test sample");

my $p = Genome::ProcessingProfile::Tester->create(
    name => 'Tester Test for Testing',
);
ok($p, "made a test processing profile");

my $m = Genome::Model::Tester->create(
    processing_profile_id => $p->id,
    subject_class_name => ref($s),
    subject_id => $s->id,
);
ok($m, "made a test model");
my $model_id = $m->id;

my $b = Genome::Model::Build::Tester->create(
    model_id => $m->id,
);
ok($b, "made a test build");

$b->add_note(header_text => 'test_note1', body_text => 'test body 1');
$b->add_note(header_text => 'test_note2', body_text => 'test body two');

my $cmd1 = Genome::Model::Build::Command::ViewNotes->create(
    notables => [$b],
);

isa_ok($cmd1, 'Genome::Model::Build::Command::ViewNotes', 'created view-notes command');
my $file1 = run_command($cmd1);
diag(Genome::Sys->read_file($file1));

my $cmd2 = Genome::Model::Build::Command::ViewNotes->create(
    notables => [$b],
    note_type => 'test_note2',
);

isa_ok($cmd2, 'Genome::Model::Build::Command::ViewNotes', 'created view-notes command');
my $file2 = run_command($cmd2);
my $text = Genome::Sys->read_file($file2);
diag($text);
my $c = $text =~ m/>/g; #If the output format changes, this will need to be changed, too
is($c,1, 'returned expected number of notes');

sub run_command {
    my $cmd = shift;
    my ($fh, $file) = Genome::Sys->create_temp_file();
    my $rv;
    {
        local *STDOUT = $fh;
        $rv = $cmd->execute;
        close *STDOUT;
    }

    ok($rv, "executed command");
    return $file;
}
