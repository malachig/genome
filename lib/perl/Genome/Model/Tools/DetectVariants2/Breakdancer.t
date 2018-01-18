#!/usr/bin/env genome-perl

use strict;
use warnings;

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
};

use above 'Genome';
use Genome::SoftwareResult;
use Genome::Test::Factory::SoftwareResult::User;

use Test::More;
use File::Compare qw(compare);
use File::Spec;

my $archos = `uname -a`;
if ($archos !~ /64/) {
    plan skip_all => "Must run from 64-bit machine";
}

use_ok('Genome::Model::Tools::DetectVariants2::Breakdancer');

my $refbuild_id = 101947881;
my $ref_seq_build = Genome::Model::Build::ImportedReferenceSequence->get($refbuild_id);
ok($ref_seq_build, 'human36 reference sequence build') or die;

my $result_users = Genome::Test::Factory::SoftwareResult::User->setup_user_hash(
    reference_sequence_build => $ref_seq_build,
);

my $test_dir = File::Spec->join(Genome::Config::get('test_inputs'), 'Genome-Model-Tools-DetectVariants2-Breakdancer');
my $test_base_dir = File::Temp::tempdir(CLEANUP => 1);
my $test_working_dir = File::Spec->join($test_base_dir, 'output');

my $normal_bam = File::Spec->join($test_dir, '/normal.bam');
my $tumor_bam  = File::Spec->join($test_dir, '/tumor.bam');
my $cfg_file   = processed_cfg_file($test_dir, 'breakdancer_config');

my $chromosome = 22;
my $test_out   = File::Spec->join($test_working_dir, $chromosome, 'svs.hq.'.$chromosome);

my $version = '1.2';
note("use breakdancer version: $version");

SKIP: {
    skip "No WGS test BAMs available.", 6;

my $command = Genome::Model::Tools::DetectVariants2::Breakdancer->create(
    reference_build_id => $refbuild_id,
    aligned_reads_input => $tumor_bam,
    control_aligned_reads_input => $normal_bam,
    version => $version,
    params  => '-g -h:-a -q 10 -o',  #breakdancer 1.2 and beyond need turn on "-a" flag to output lib info
    chromosome => $chromosome,
    output_directory => $test_working_dir,
    config_file => $cfg_file,
    result_users => $result_users,
);
ok($command, 'Created `gmt detect-variants2 breakdancer` command');
$command->dump_status_messages(1);
ok($command->execute, 'Executed `gmt detect-variants2 breakdancer` command');

my $expected_output = File::Spec->join($test_dir, "svs.hq.$chromosome".'_current');
system("diff -u $expected_output $test_out");
my $diff = sub {
    my ($line1, $line2) = @_;
    $line1 =~ s/^#Command:.*//;
    $line2 =~ s/^#Command:.*//;
    $line1 =~ s/^#\S+((?:tumor|normal).bam)/$1/;
    $line2 =~ s/^#\S+((?:tumor|normal).bam)/$1/;
    return $line1 ne $line2;
};
is(compare($expected_output, $test_out, $diff), 0, "svs.hq output as expected");

# Test fastq QC
my $good_fastq_dir = $command->_temp_staging_directory($test_base_dir.'/good');
Genome::Sys->create_directory($good_fastq_dir);
for my $cnt (1..2) {
    my $good_fastq_file = $command->_sv_staging_output.'.good.'.$cnt.'.fastq';
    my $good_fastq_fh = Genome::Sys->open_file_for_writing($good_fastq_file);
    $good_fastq_fh->print( join("\n", '@read1', join('', map { 'A' } (1..$cnt+3)), '+', join('', (1..$cnt+3)), '') );
    $good_fastq_fh->close;
}
ok($command->_validate_ctx_fastqs, 'validate ctx fastqs');
my $good_md5 = Genome::Sys->read_file($command->_sv_staging_output.'.fastqs.md5');
is($good_md5, "d14cc59113d6baa186496776b55e6ebe\tsvs.hq.22.good.1.fastq\nf2768207c9cd0a01b6aaf5a6f044526c\tsvs.hq.22.good.2.fastq\n", 'MD5 for good fastq matches');

my $bad_fastq_file = $command->_sv_staging_output.'.bad.1.fastq';
my $bad_fastq_fh = Genome::Sys->open_file_for_writing($bad_fastq_file);
$bad_fastq_fh->print( join("\n", '@read1', 'ATCG', '+', 'BLAH!', '') );
$bad_fastq_fh->close;
ok(!$command->_validate_ctx_fastqs, 'validate ctx fastqs failed b/c of bad fastq');
#print $command->_sv_staging_output."\n";<STDIN>;

}; #SKIP

my $no_ctx_working_dir = File::Spec->join($test_base_dir, 'output2');

my $no_ctx_normal_bam = File::Spec->join($test_dir, '/noctx.chr22.tst1_bl.bam');
my $no_ctx_tumor_bam  = File::Spec->join($test_dir, '/noctx.chr22.tst1.bam');
my $no_ctx_cfg_file   = processed_cfg_file($test_dir, 'no_ctx_bam_cfg');
my $command1 = Genome::Model::Tools::DetectVariants2::Breakdancer->create(
    reference_build_id => $refbuild_id,
    aligned_reads_input => $no_ctx_tumor_bam,
    control_aligned_reads_input => $no_ctx_normal_bam,
    version => $version,
    params  => '-g -h:-a -q 10 -t -d',  #breakdancer 1.2 and beyond need turn on "-a" flag to output lib info
    chromosome => $chromosome,
    output_directory => $no_ctx_working_dir,
    config_file => $no_ctx_cfg_file,
    result_users => $result_users,
);
ok($command1, 'Created `gmt detect-variants2 breakdancer` command for ctx');
$command1->dump_status_messages(1);
ok($command1->execute, 'Executed `gmt detect-variants2 breakdancer` command for ctx');

done_testing();

sub processed_cfg_file {
    my $test_dir = shift;
    my $cfg_name = shift;

    my @cfg = Genome::Sys->read_file(File::Spec->join($test_dir, $cfg_name));

    my $processed_cfg_path = Genome::Sys->create_temp_file_path;
    Genome::Sys->write_file(
        $processed_cfg_path,
        map { _process_cfg_line($test_dir, $_) } @cfg
    );

    return $processed_cfg_path;
}

sub _process_cfg_line {
    my $test_dir = shift;
    my $line = shift;

    $line =~ s/^#\S*((?:tumor|normal).bam)/#$test_dir\/$1/;
    return $line;
}
