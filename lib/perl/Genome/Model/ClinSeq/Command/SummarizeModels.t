#!/usr/bin/env genome-perl

#Written by Malachi Griffith

use strict;
use warnings;
use File::Basename;
use Cwd 'abs_path';

BEGIN {
    $ENV{UR_DBI_NO_COMMIT}               = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use above "Genome";
use Test::More tests => 6;  #One per 'ok', 'is', etc. statement below
use Genome::Model::ClinSeq::Command::SummarizeModels;
use Data::Dumper;

use_ok('Genome::Model::ClinSeq::Command::SummarizeModels') or die;

#Define the test where expected results are stored
my $expected_output_dir =
    Genome::Config::get('test_inputs') . "/Genome-Model-ClinSeq-Command-SummarizeModels/2014-09-29/";
ok(-e $expected_output_dir, "Found test dir: $expected_output_dir") or die;

#Create a temp dir for results
my $temp_dir = Genome::Sys->create_temp_directory();
ok($temp_dir, "created temp directory: $temp_dir");

#Get a clin-seq build
my $clinseq_model_id1 = 2882726707;
my $clinseq_model1    = Genome::Model->get($clinseq_model_id1);

#Create summarize-models command and execute
#genome model clin-seq summarize-models --outdir=/tmp/ --skip-lims-reports=1 2882726707

my $summarize_models_cmd = Genome::Model::ClinSeq::Command::SummarizeModels->create(
    outdir => $temp_dir,
    models => [$clinseq_model1]
);
$summarize_models_cmd->queue_status_messages(1);
my $r1 = $summarize_models_cmd->execute();
is($r1, 1, 'Testing for successful execution.  Expecting 1.  Got: ' . $r1);

#Dump the output of summarize-models to a log file
my @output1  = $summarize_models_cmd->status_messages();
my $log_file = $temp_dir . "/SummarizeModels.log.txt";
my $log      = IO::File->new(">$log_file");
$log->print(join("\n", @output1));
ok(-e $log_file, "Wrote message file from summarize-models to a log file: $log_file");

#The first time we run this we will need to save our initial result to diff against
#Genome::Sys->shellcmd(cmd => "cp -r -L $temp_dir/* $expected_output_dir");

#Perform a diff between the stored results and those generated by this test
my @diff = `diff -r $expected_output_dir $temp_dir`;
ok(@diff == 0, "Found only expected number of differences between expected results and test results")
    or do {
    diag("expected: $expected_output_dir\nactual: $temp_dir\n");
    diag("differences are:");
    diag(@diff);
    my $diff_line_count = scalar(@diff);
    print "\n\nFound $diff_line_count differing lines\n\n";
    Genome::Sys->shellcmd(cmd => "rm -fr /tmp/last-summarize-models-result/");
    Genome::Sys->shellcmd(cmd => "mv $temp_dir /tmp/last-summarize-models-result");
    };
chdir("/");
