#!/usr/bin/env genome-perl

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
};

use strict;
use warnings;

use above 'Genome';
use Test::More;

my $lims_class = 'Genome::Site::TGI::Synchronize::Classes::Genotyping';
use_ok($lims_class) or die;

my $entity_name = $lims_class->entity_name;
ok($entity_name, 'entity name');
is($entity_name, 'instrument data microarray', 'entity name');
my $expected_genome_class = 'Genome::InstrumentData::Imported';
is($lims_class->genome_class_for_comparison, $expected_genome_class, 'genome class for create');
is($lims_class->genome_class_for_create, $expected_genome_class, 'genome class for create');

my $sample = Genome::Sample->__define__(
    id => -3,
    name => '__TEST_SAMPLE__',
);

my @properties_to_copy = $lims_class->properties_to_copy;
my %properties = (
    'id' => Genome::InstrumentData->__meta__->autogenerate_new_object_id(),
    'chip_name' => 'HumanOmniExpress',
    'import_source_name' => 'wugc',
    'sequencing_platform' => 'infinium',
    'version' => '12v1_A',
);
ok(@properties_to_copy, 'properties to copy');
is_deeply([sort keys %properties], [sort @properties_to_copy], 'correct properties to copy');
my @properties_to_keep_updated = $lims_class->properties_to_keep_updated;
ok(@properties_to_keep_updated, 'properties to keep updated');
cmp_ok(@properties_to_copy, '>', @properties_to_keep_updated, 'more properties to copy than keep updated');

my $lims_object = $lims_class->__define__(%properties);
ok($lims_object, "define lims $entity_name object");

my $genotype_file = Genome::Config::get('test_inputs') . '/Genome-InstrumentData-Microarray/test_genotype_file1';
$lims_object->genotype_file($genotype_file);
$lims_object->sample_id($sample->id);
$lims_object->sample_name($sample->name);

my $genome_object = $lims_object->create_in_genome;
ok($genome_object, "create genome $entity_name object");
isa_ok($genome_object, $expected_genome_class);

is($genome_object->import_format, 'genotype file', 'import format');
ok($genome_object->library, 'library');
is($genome_object->library->name, $sample->name.'-microarraylib', 'library name');

my $genome_genotyp_file = $genome_object->genotype_file;
ok($genome_genotyp_file, 'got genotype file from genome object');
is($genome_genotyp_file, $genome_genotyp_file, 'genotype files mathce');
ok(-s $genotype_file, 'genome genotype file exists');

for my $property (qw/ id sequencing_platform import_source_name chip_name version /) {
    my $value = eval{ $genome_object->$property; };
    $value = eval{ $genome_object->attributes(attribute_label => $property)->attribute_value; } if not defined $value;
    $value = $genome_object->attributes(attribute_label => $property)->attribute_value if not defined $value;
    is($value, $properties{$property}, "genome and lims $property matches => $value");
}

done_testing();
