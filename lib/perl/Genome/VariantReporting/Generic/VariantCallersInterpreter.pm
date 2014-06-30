package Genome::VariantReporting::Generic::VariantCallersInterpreter;

use strict;
use warnings;
use Genome;
use List::MoreUtils qw/uniq/;

class Genome::VariantReporting::Generic::VariantCallersInterpreter {
    is => ['Genome::VariantReporting::Framework::Component::Interpreter', 'Genome::VariantReporting::Framework::Component::WithSampleName'],
};

sub name {
    return 'variant-callers';
}

sub requires_experts {
    return ();
}

sub available_fields {
    return qw /
        variant_callers
    /
}

sub interpret_entry {
    my $self = shift;
    my $entry = shift;

    my %return_values;
    my %callers;
    for my $alt_allele (@{$entry->{alternate_alleles}}) {
        $return_values{$alt_allele} = { variant_callers => "" };
        $callers{$alt_allele} = [];
    }

    for my $caller_name ($self->get_callers($entry->{header})) {
        my $sample_name = $self->sample_name_with_suffix($caller_name);
        my $sample_index = eval{ $entry->{header}->index_for_sample_name($sample_name) };
        my $error = $@;
        if ($error =~ /^Sample name $sample_name not found in header/) {
            next;
        }
        my @sample_alt_alleles = eval{ $entry->alt_bases_for_sample($sample_index)};
        for my $sample_alt_allele (uniq @sample_alt_alleles) {
            push(@{$callers{$sample_alt_allele}}, $caller_name);
        }
    }

    for my $alt_allele (keys %return_values) {
        $return_values{$alt_allele} = {
            variant_callers => $callers{$alt_allele}
        };
    }

    return %return_values;
}
1;

