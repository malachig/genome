#!/usr/bin/env genome-perl

#Written by Malachi Griffith

use strict;
use warnings;
use File::Basename;
use Cwd 'abs_path';

BEGIN {
  $ENV{UR_DBI_NO_COMMIT} = 1;
  $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
  $ENV{NO_LSF} = 1;
};

use above "Genome";
use Test::More tests=>9; #One per 'ok', 'is', etc. statement below
use Genome::Model::ClinSeq::Command::CreateMutationSpectrum;
use Data::Dumper;

use_ok('Genome::Model::ClinSeq::Command::AnnotateGenesByCategory') or die;

#Define the test where expected results are stored
my $expected_output_dir = $ENV{"GENOME_TEST_INPUTS"} . "Genome-Model-ClinSeq-Command-AnnotateGenesByCategory/2013-02-26/";
ok(-e $expected_output_dir, "Found test dir: $expected_output_dir") or die;

#Create a temp dir for results
my $temp_dir = Genome::Sys->create_temp_directory();
ok($temp_dir, "created temp directory: $temp_dir") or die;

#Make a copy of the expected input file in the temp dir
my $infile = $expected_output_dir . "example_input.tsv";
ok (-e $infile, "Found example input file: $infile") or die;
Genome::Sys->shellcmd(cmd => "cp $infile $temp_dir/");
my $temp_infile = $temp_dir . "/example_input.tsv";
ok (-e $temp_infile, "Found temp copy of example input file: $infile");

#Check for GeneSymbolLists dir
my $gene_symbol_lists_dir = "/gscmnt/sata132/techd/mgriffit/reference_annotations/GeneSymbolLists/";
ok (-e $gene_symbol_lists_dir && -d $gene_symbol_lists_dir, "Found gene symbol lists dir") or die;

#Create annotate-genes-by-category command and execute
#genome model clin-seq annotate-genes-by-category --infile=example_input.tsv --gene-symbol-lists-dir=/gscmnt/sata132/techd/mgriffit/reference_annotations/GeneSymbolLists/  --gene-name-column='mapped_gene_name'

my $annotate_genes_cmd = Genome::Model::ClinSeq::Command::AnnotateGenesByCategory->create(infile=>$temp_infile, gene_symbol_lists_dir=>$gene_symbol_lists_dir, gene_name_column=>'mapped_gene_name');
$annotate_genes_cmd->queue_status_messages(1);
my $r1 = $annotate_genes_cmd->execute();
is($r1, 1, 'Testing for successful execution.  Expecting 1.  Got: '.$r1);

#Dump the output to a log file
my @output1 = $annotate_genes_cmd->status_messages();
my $log_file = $temp_dir . "/AnnotateGenesByCategory.log.txt";
my $log = IO::File->new(">$log_file");
$log->print(join("\n", @output1));
ok(-e $log_file, "Wrote message file from annotate-genes-by-category to a log file: $log_file");

#The first time we run this we will need to save our initial result to diff against
#Genome::Sys->shellcmd(cmd => "cp -r -L $temp_dir/* $expected_output_dir");

#Perform a diff between the stored results and those generated by this test
my @diff = `diff -r -x '*.log.txt' -x '*.pdf' -x '*.stderr' -x '*.stdout' $expected_output_dir $temp_dir`;
ok(@diff == 0, "Found only expected number of differences between expected results and test results")
or do {
  diag("expected: $expected_output_dir\nactual: $temp_dir\n");
  diag("differences are:");
  diag(@diff);
  my $diff_line_count = scalar(@diff);
  print "\n\nFound $diff_line_count differing lines\n\n";
  Genome::Sys->shellcmd(cmd => "rm -fr /tmp/last-annotate-genes-by-category");
  Genome::Sys->shellcmd(cmd => "mv $temp_dir /tmp/last-annotate-genes-by-category");
};



