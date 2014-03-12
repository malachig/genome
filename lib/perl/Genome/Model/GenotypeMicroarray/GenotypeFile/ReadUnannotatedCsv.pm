package Genome::Model::GenotypeMicroarray::GenotypeFile::ReadUnannotatedCsv;

use strict;
use warnings;

use Genome;

use Genome::File::Vcf::Reader;

class Genome::Model::GenotypeMicroarray::GenotypeFile::ReadUnannotatedCsv { 
    is => 'UR::Object',
    has => {
        input => { is => 'Text', },
        variation_list_build => { is => 'Genome::Model::Build::ImportedVariationList', },
        snp_id_mapping => { is => 'Hash', },
        _vcf_reader => { is => 'Genome::File::Vcf::Reader', },
        _genotype_fh => { is => 'IO::File', },
        _headers => { is => 'Array', },
        _genotypes => { is => 'Hash', default_value => {}, },
        _entries => { is => 'Array', },
        _position => { is => 'Integer', default_value => 0, },
    },
};

sub header {
    my ($self, $header) = @_;

    if ( $header ) {
        $self->_vcf_reader->header($header);
    }

    return $self->_vcf_reader->header;
}

sub create {
    my $class = shift;

    my $self = $class->SUPER::create(@_);
    return if not $self;

    my $open_genotype_file = $self->_open_genotype_file;
    return if not $open_genotype_file;

    my $headers_ok = $self->_resolve_headers;
    return if not $headers_ok;

    my $open_vcf_reader = $self->_open_vcf_reader;
    return if not $open_vcf_reader;

    return $self;
}

BEGIN {
    *next = \&read;
}
sub read {
    my $self = shift;

    if ( $self->_position == 0 ) {
        my $load_genotypes = $self->_load_genotypes;
        die if not $load_genotypes;

        my $annotate_genotypes = $self->_annotate_genotypes;
        die if not $annotate_genotypes;
    }

    my $position = $self->_position;
    my $entry;
    do {
        $entry = $self->_entries->[$position++];
    } until not $entry or $self->_genotypes->{ $entry->{identifiers}->[0] }->{seen} == 1;
    $self->_position($position);

    return if not defined $entry;
    return $entry;
}

sub _open_vcf_reader {
    my $self = shift;

    my $variation_list_build = $self->variation_list_build;
    my $snvs_vcf = $variation_list_build->snvs_vcf;
    if ( not $snvs_vcf or not -s $snvs_vcf ) {
        $self->error_message('No SNVs VCF for variation list  build! '.$variation_list_build->__display_name__);
        return;
    }

    my $vcf_reader = eval{ Genome::File::Vcf::Reader->new($snvs_vcf); };
    if ( not $vcf_reader ) {
        $self->error_message("Failed to open SNVs VCF file! $snvs_vcf");
        return;
    }
    $self->_vcf_reader($vcf_reader);

    return 1;
}

sub _open_genotype_file {
    my $self = shift;

    my $genotype_file = $self->input;
    if ( not -s $genotype_file ) {
        $self->error_message('Genotype file file does not exist! '.$genotype_file);
        return;
    }

    my $genotype_fh = eval{ Genome::Sys->open_file_for_reading($genotype_file); };
    if ( not $genotype_fh ) {
        $self->error_message("Failed to open reader for genotype file: $genotype_file): $@");
        return;
    }

    $self->_genotype_fh($genotype_fh);

    return 1;
}

sub _resolve_headers {
    my $self = shift;

    my $header_line;
    my $genotype_fh = $self->_genotype_fh;
    do { $header_line = $genotype_fh->getline; } until not $header_line or $header_line =~ /,/;
    if ( not $header_line ) {
        $self->error_message('Failed to get header line for genotype file!');
        return;
    }

    chomp $header_line;
    my @headers = map { s/\s/_/g; s/_\-\_top$//i; lc } split(',', $header_line);
    $self->_headers(\@headers);

    return 1;
}

sub _load_genotype {
    my $self = shift;

    my $line = $self->_genotype_fh->getline;
    return if not $line;

    chomp $line;
    my %genotype;
    @genotype{@{$self->_headers}} = split(',', $line);

    # The id is from the snp mapping or the genotype's snp_name
    if ( $self->snp_id_mapping and exists $self->snp_id_mapping->{ $genotype{snp_name} }) {
        $genotype{id} = $self->snp_id_mapping->{ delete $genotype{snp_name} };
    } else {
        $genotype{id} = delete $genotype{snp_name};
        $genotype{id} =~ s/^(rs\d+)\D*$/$1/; #borrowed from GSC::Genotyping::normalize_to
    }

    if ( exists $self->_genotypes->{ $genotype{id} } ) {
        Carp::confess( $self->error_message('Already have a genotype for snp id: '.Data::Dumper::Dumper(\%genotype, $self->genotypes->{ $genotype{id} })) );
    }

    delete $genotype{'chr'};
    $genotype{alleles} = $genotype{allele1}.$genotype{allele2};

    $self->_genotypes->{ $genotype{id} } = \%genotype;

    return \%genotype;
}

sub _load_genotypes {
    my $self = shift;

    my $snp_id_mapping = $self->snp_id_mapping;

    my $genotype_fh = $self->_genotype_fh;
    my @headers = @{$self->_headers};
    my $genotypes = $self->_genotypes;

    my $genotype;
    do {
        $genotype = $self->_load_genotype;
    } while $genotype;

    if ( not %{$self->_genotypes} ) {
        $self->error_message("No genotypes found in genotype file! ".$self->get_original_input);
        return;
    }

    return 1;
}

sub _annotate_genotypes {
    my $self = shift;

    my $genotypes = $self->_genotypes;
    Carp::confess('No genotypes!') if not $genotypes or not %$genotypes;

    my @entries;
    my $vcf_reader = $self->_vcf_reader;
    while ( my $entry = $vcf_reader->next ) {
       # Skip INDELs
        if ( $entry->has_indel ) {
            $self->warning_message('Skipping INDEL: '.$entry->to_string);
            next;
        }

        my $variant_id = $entry->{identifiers}->[0];
        my $genotype = $genotypes->{$variant_id};

        # Skip if not in variation list
        next if not $genotype;

        # Add GT to genotype
        $genotype->{genotype} = $self->_gt_for_genotype($genotype, $entry);

        # Add genotype data to entry
        for my $field ( Genome::Model::GenotypeMicroarray->format_types ) {
            $entry->add_format_field($field->{id});
            $entry->set_sample_field(0, $field->{id}, $genotype->{ $field->{name} });
        }

        # Use entry for genotype
        $genotypes->{$variant_id}->{seen}++;

        # Push to entries to maintain order
        push @entries, $entry;
    }

    if ( not @entries ) {
        $self->error_message("All genotypes are duplicates in variant list! ".$vcf_reader->{name});
        return;
    }
    $self->_entries(\@entries);

    return 1;
}

sub _gt_for_genotype {
    my ($self, $genotype, $entry) = @_;

    my %alleles_idx = (
        '-' => '.',
        $entry->{reference_allele} => 0,
    );
    @alleles_idx{ @{$entry->{alternate_alleles}} } = ( 1..@{$entry->{alternate_alleles}} );

    my @gt_idx;
    for my $allele ( map { $genotype->{$_} } (qw/ allele1 allele2 /) ) { 
        if ( not exists $alleles_idx{$allele} ) {
            push @{$entry->{alternate_alleles}}, $allele;
            $alleles_idx{$allele} = scalar(@{$entry->{alternate_alleles}});
        }
        push @gt_idx, $alleles_idx{$allele};
    }

    return join('/', @gt_idx);
}

1;

