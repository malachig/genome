#!/usr/bin/env genome-perl

#Written by Malachi Griffith

use strict;
use warnings;
use File::Basename;
use Cwd 'abs_path';
use File::Spec qw();
use List::MoreUtils qw(uniq);
use Genome::Utility::Test qw(compare_ok capture_ok run_ok);

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
    $ENV{NO_LSF} = 1;
};

use Data::Dumper;
use above "Genome";
use Test::More tests => 61;

#The following tests are expressed as system calls of what you would actually type at the command-line because that is the output we specifically wish to test

#This test performs a series of tests that cover common analysis use cases for command line usage of Genome listers, etc.
#If this test breaks it will most likely be because of one of the following.  Figure out which is the case and update appropriately:
#1.) If a code change is pushed that breaks one of these examples because of a desired improvement to the UI, please update the appropriate command below
#2.) Since many of these involve querying the database, if this test breaks it may simply require updating the test results 

#Create a temp dir for results
#my $temp_dir = "/tmp/TestGenomeCommands/";
my $temp_dir = Genome::Sys->create_temp_directory();
ok($temp_dir, "created temp directory: $temp_dir");

#Define the test where expected results are stored
my $expected_output_dir = $ENV{"GENOME_TEST_INPUTS"} . "Genome-Model-ClinSeq-Command-TestGenomeCommands/2014-04-23/";
ok(-e $expected_output_dir, "Found test dir: $expected_output_dir") or die;

#CLIN-SEQ UPDATE-ANALYSIS
#Test clin-seq update-analysis - make sure the following command correctly obtains three expected samples (this has been broken in the past)
my $cmd = "genome model clin-seq update-analysis --individual='H_KA-306905' --samples='id in [2878747496,2878747497,2879495575]' --display-samples";
$cmd .= " 2>$temp_dir/genome-model-clinseq-update-analysis.out";
run_ok($cmd, "tested genome model clin-seq update-analysis") or diag $cmd;

#GENOME SAMPLE LIST
$cmd = "genome sample list --filter \'name like \"H_NJ-HCC1395-HCC1395%\"\' --show id,name,common_name,tissue_desc,extraction_type,extraction_label";
$cmd .= " 1>$temp_dir/genome-sample-list1.out 2>$temp_dir/genome-sample-list1.err";
run_ok($cmd, "tested genome sample list1") or diag $cmd;

#GENOME MODEL CLIN-SEQ LIST
$cmd = "genome model clin-seq list --filter model_groups.id=66909 --show wgs_model.last_succeeded_build.id,wgs_model.last_succeeded_build.data_directory";
$cmd .= " 1>$temp_dir/genome-model-clinseq-list1.out 2>$temp_dir/genome-model-clinseq-list1.err";
run_ok($cmd, "tested genome model clin-seq list1") or diag $cmd;

$cmd = "genome model clin-seq list --filter model_groups.id=66909 --style=tsv --show id,name,wgs_model,tumor_rnaseq_model,subject.common_name";
$cmd .= " 1>$temp_dir/genome-model-clinseq-list2.out 2>$temp_dir/genome-model-clinseq-list2.err";
run_ok($cmd, "tested genome model clin-seq list2") or diag $cmd;

$cmd = "genome model clin-seq list --style csv --filter model_groups.id=66909 --show wgs_model.last_succeeded_build.normal_build.subject.name,wgs_model.last_succeeded_build.normal_build.whole_rmdup_bam_file";
$cmd .= " 1>$temp_dir/genome-model-clinseq-list3.out 2>$temp_dir/genome-model-clinseq-list3.err";
run_ok($cmd, "tested genome model clin-seq list3") or diag $cmd;

#GENOME MODEL SOMATIC-VARIATION LIST
$cmd = "genome model somatic-variation list --filter group_ids=50569 --show subject.patient_common_name,subject.name,id";
$cmd .= " 1>$temp_dir/genome-model-somatic-variation-list1.out 2>$temp_dir/genome-model-somatic-variation-list1.err";
run_ok($cmd, "tested genome model somatic-variation list1") or diag $cmd;

#genome model somatic-variation list --filter group_ids=50569 --show subject.name,last_succeeded_build_directory  --noheaders
$cmd = "genome model somatic-variation list --filter group_ids=50569 --show subject.name,last_succeeded_build_directory  --noheaders";
$cmd .= " 1>$temp_dir/genome-model-somatic-variation-list2.out 2>$temp_dir/genome-model-somatic-variation-list2.err";
run_ok($cmd, "tested genome model somatic-variation list2") or diag $cmd;

#genome model somatic-variation list 'model_groups.id=50569' --show 'tumor_model.subject.name,tumor_model.subject.common_name' --style=csv
$cmd = "genome model somatic-variation list 'model_groups.id=50569' --show 'tumor_model.subject.name,tumor_model.subject.common_name' --style=csv";
$cmd .= " 1>$temp_dir/genome-model-somatic-variation-list3.out 2>$temp_dir/genome-model-somatic-variation-list3.err";
run_ok($cmd, "tested genome model somatic-variation list3") or diag $cmd;

#GENOME MODEL RNA-SEQ LIST
$cmd = "genome model rna-seq list --filter 'genome_model_id=2888673504'";
$cmd .= " 1>$temp_dir/genome-model-rnaseq-list1.out 2>$temp_dir/genome-model-rnaseq-list1.err";
run_ok($cmd, "tested genome model rna-seq list1") or diag $cmd;

$cmd = "genome model rna-seq list group_ids=50554 --show id,name,processing_profile,last_succeeded_build.id,last_succeeded_build.alignment_result.bam_file --style tsv";
$cmd .= " 1>$temp_dir/genome-model-rnaseq-list2.out 2>$temp_dir/genome-model-rnaseq-list2.err";
run_ok($cmd, "tested genome model rna-seq list2") or diag $cmd;

#GENOME INSTRUMENT-DATA LIST SOLEXA
$cmd = "genome instrument-data list solexa --show id,flow_cell_id,lane,index_sequence,sample_name,library_name,clusters,read_length,bam_path --filter flow_cell_id=D1VCPACXX";
$cmd .= " 1>$temp_dir/genome-instrument-data-list1.out 2>$temp_dir/genome-instrument-data-list1.err";
run_ok($cmd, "tested genome instrument-data list1") or diag $cmd;

$cmd = "genome instrument-data list solexa --filter sample_name=\'H_NE-00264-264-03-A5-D1\'";
$cmd .= " 1>$temp_dir/genome-instrument-data-list2.out 2>$temp_dir/genome-instrument-data-list2.err";
run_ok($cmd, "tested genome instrument-data list2") or diag $cmd;

#GENOME MODEL-GROUP MEMBER LIST
$cmd = "genome model-group member list --filter 'model_group_id=66909' --show model.wgs_model.id,model.wgs_model.subject.patient_common_name,model.last_succeeded_build,model.last_succeeded_build.data_directory";
$cmd .= " 1>$temp_dir/genome-model-group-member-list1.out 2>$temp_dir/genome-model-group-member-list1.err";
run_ok($cmd, "tested genome model-group member list1") or diag $cmd;

#GENOME MODEL SOMATIC-VALIDATION LIST
#genome model somatic-validation list --filter model_groups.id=72096 --show tumor_sample.patient_common_name,tumor_sample.name,last_complete_build.tumor_bam
$cmd = "genome model somatic-validation list --filter model_groups.id=72096 --show tumor_sample.patient_common_name,tumor_sample.name,last_complete_build.tumor_bam";
$cmd .= " 1>$temp_dir/genome-model-somatic-validation-list1.out 2>$temp_dir/genome-model-somatic-validation-list1.err";
run_ok($cmd, "tested genome somatic-validation list1") or diag $cmd;


my @expected_files = map { (/^$expected_output_dir\/?(.*)/)[0] } capture_ok(qq(find $expected_output_dir -type f ! -name '*.err'));
my @temp_files = map { (/^$temp_dir\/?(.*)/)[0] } capture_ok(qq(find $temp_dir -type f ! -name '*.err'));
my @files = uniq (@expected_files, @temp_files);
chomp @files;
is(scalar(@files), 14, 'found expected number of files');
for my $file (@files) {
    next if $file =~ m/^\..*\.swp$/;  # skip vim temp files
    my $temp_file = File::Spec->join($temp_dir, $file);
    ok(-f $temp_file, "file exists in temp_dir: $file");
    my $expected_file = File::Spec->join($expected_output_dir, $file);
    ok(-f $expected_file, "file exists in expected_output_dir: $file");
    compare_ok($temp_file, $expected_file,
        filters => [
            '^\*\*\*\*\* GENOME_DEV_MODE.*',
            '^Subroutine Genome::SoftwareResult::_resolve_lock_name redefined.*',
            "^WARNING: Ignoring ineffective commit because AutoCommit is on\n",
        ],
        name => "compared $file",
    );
}



