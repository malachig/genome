#!/usr/bin/env genome-perl

BEGIN { 
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use strict;
use warnings;

use above "Genome";
use Test::Exception;
use Test::More;
use Genome::VariantReporting::Plan::TestHelpers;

my $pkg = "Genome::VariantReporting::Reporter::WithHeader";
use_ok($pkg);

{
    package Test::BadReporter;

    class Test::BadReporter {
        is => 'Genome::VariantReporting::Reporter::WithHeader',
    };

    sub name {
        "bad_reporter";
    }

    sub requires_interpreters {
        return qw(interpreter_y);
    }

    sub headers {
        return qw(different_field);
    }
    1;
}

{
    package Genome::VariantReporting::DuplicateInterpreter;

    class Genome::VariantReporting::DuplicateInterpreter {
        is => 'Genome::VariantReporting::Framework::Component::Interpreter',
    };
    sub name {
        'duplicate';
    }
    sub available_fields {
        return qw(chrom);
    }
}

{
    package Test::BadReporter2;

    class Test::BadReporter2 {
        is => 'Genome::VariantReporting::Reporter::WithHeader',
    };

    sub name {
        "bad_reporter2";
    }

    sub requires_interpreters {
        return qw(interpreter_y duplicate);
    }

    sub headers {
        return qw(chrom);
    }
    1;
}

my $reporter = Test::BadReporter->create(file_name => 'bad');
ok($reporter, 'Reporter created successfully');
dies_ok(sub {$reporter->validate;}, "Reporter does not validate");

my $reporter2 = Test::BadReporter2->create(file_name => 'bad');
ok($reporter2, 'Reporter created successfully');
dies_ok(sub {$reporter2->validate;}, "Reporter does not validate");

done_testing;

