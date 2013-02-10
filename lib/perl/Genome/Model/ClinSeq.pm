package Genome::Model::ClinSeq;

use strict;
use warnings;
use Genome;

class Genome::Model::ClinSeq {
    is => 'Genome::Model',
    has_optional_input => [
        wgs_model           => { is => 'Genome::Model::SomaticVariation', doc => 'somatic variation model for wgs data' },
        exome_model         => { is => 'Genome::Model::SomaticVariation', doc => 'somatic variation model for exome data' },
        tumor_rnaseq_model  => { is => 'Genome::Model::RnaSeq', doc => 'rnaseq model for tumor rna-seq data' },
        normal_rnaseq_model => { is => 'Genome::Model::RnaSeq', doc => 'rnaseq model for normal rna-seq data' },
        de_model            => { is => 'Genome::Model::DifferentialExpression', doc => 'differential-expression for tumor vs normal rna-seq data' },
        force               => { is => 'Boolean', doc => 'skip sanity checks on input models' }, 
    ],
    has_optional_param => [
        #Processing profile parameters would go in here
        #someparam1 => { is => 'Number', doc => 'blah' },
        #someparam2 => { is => 'Boolean', doc => 'blah' },
        #someparam2 => { is => 'Text', valid_values => ['a','b','c'], doc => 'blah' },
    ],
    has_calculated => [
        expected_common_name => {
            is => 'Text',
            calculate_from => [qw /wgs_model exome_model tumor_rnaseq_model normal_rnaseq_model/],
            calculate => q|
              my ($wgs_common_name, $exome_common_name, $tumor_rnaseq_common_name, $normal_rnaseq_common_name, $wgs_name, $exome_name, $tumor_rnaseq_name, $normal_rnaseq_name);
              if ($wgs_model) {
                  $wgs_common_name = $wgs_model->subject->patient->common_name;
                  $wgs_name = $wgs_model->subject->patient->name;
              }
              if ($exome_model) {
                  $exome_common_name = $exome_model->subject->patient->common_name;
                  $exome_name = $exome_model->subject->patient->name;
              }
              if ($tumor_rnaseq_model) {
                  $tumor_rnaseq_common_name = $tumor_rnaseq_model->subject->patient->common_name;
                  $tumor_rnaseq_name = $tumor_rnaseq_model->subject->patient->name;
              }
              if ($normal_rnaseq_model) {
                  $normal_rnaseq_common_name = $normal_rnaseq_model->subject->patient->common_name;
                  $normal_rnaseq_name = $normal_rnaseq_model->subject->patient->name;
              }
              my @names = ($wgs_common_name, $exome_common_name, $tumor_rnaseq_common_name, $normal_rnaseq_common_name, $wgs_name, $exome_name, $tumor_rnaseq_name, $normal_rnaseq_name);
              my $final_name = "UnknownName";
              foreach my $name (@names){
                if ($name){
                  $final_name = $name;
                  last();
                }
              }
              return $final_name;
            |
        }
    ],
    doc => 'clinical and discovery sequencing data analysis and convergence of RNASeq, WGS and exome capture data',
};

#TODO: Fix this...
# temp fix until the output table is in place and we can readily 
# persist this per-build outside of the workflow
Genome::Model::Build::ClinSeq->class;
*Genome::Model::Build::ClinSeq::common_name = sub {
    my $self = shift;
    return $self->model->expected_common_name;
};
*Genome::Model::ClinSeq::common_name = sub {
    my $self = shift;
    return $self->expected_common_name;
};

sub define_by { 'Genome::Model::Command::Define::BaseMinimal' }

sub _help_synopsis {
    my $self = shift;
    return <<"EOS"

    genome processing-profile create clin-seq  --name 'November 2011 Clinical Sequencing' 

    genome model define clin-seq  --processing-profile='November 2011 Clinical Sequencing'  --wgs-model=2882504846 --exome-model=2882505032 --tumor-rnaseq-model=2880794613
    
    # Automatically builds if/when the models have a complete underlying build
EOS
}

sub _help_detail_for_profile_create {
    return <<EOS

The ClinSeq pipeline has no parameters.  Just use the default profile to run it.

EOS
}

sub _help_detail_for_model_define {
    return <<EOS

The ClinSeq pipeline takes four models, each of which is optional, and produces data sets potentially useful in a clinical or discovery project.

There are several primary goals:

1. Generate results that help to identify clinically actionable events (gain of function mutations, amplifications, etc.)

2. Converge results across data types for a single case (e.g. variant read counts from wgs + exome + rnaseq)

3. Automatically generate statistics, tables and figures to be used in manuscripts

4. Test novel analysis methods in a pipeline that runs faster and is more agile than say somatic-variation

EOS
}

sub _resolve_subject {
    my $self = shift;
    my @subjects = $self->_infer_candidate_subjects_from_input_models();
    if (@subjects > 1) {
      if ($self->force){
        @subjects = ($subjects[0]);
      }else{
        $self->error_message(
            "Conflicting subjects on input models!:\n\t"
            . join("\n\t", map { $_->__display_name__ } @subjects)
        );
        return;
      }
    }
    elsif (@subjects == 0) {
        $self->error_message("No subjects on input models?  Contact Informatics.");
        return;
    }
    return $subjects[0];
}

#TODO: As above, infer reference genome builds from input models and abort if they are missing or in conflict!

#TODO: As above, infer annotation builds from input models and abort if they are missing or in conflict!

#Implement specific error checking here, any error that is added to the @errors array will prevent the model from being commited to the database
#Could also implement a --force input above to allow over-riding of errors
sub __errors__ {
    my $self = shift;

    my @errors = $self->SUPER::__errors__;

#    unless(-e $self->input_fasta_file && -f $self->input_fasta_file) {
#        push @errors,UR::Object::Tag->create(
#            type => 'error',
#            properties => ['input_fasta_file'],
#            desc => 'input_fasta_file does not exist or is not a file'
#        );
#    }

    return @errors;
}

sub map_workflow_inputs {
    my $self = shift;
    my $build = shift;

    my $data_directory = $build->data_directory;

    my $wgs_build           = $build->wgs_build;
    my $exome_build         = $build->exome_build;
    my $tumor_rnaseq_build  = $build->tumor_rnaseq_build;
    my $normal_rnaseq_build = $build->normal_rnaseq_build;

    my $final_name = $self->common_name;

    # initial inputs are for the "Main" component which does all of the legacy/non-parellel tasks
    my @inputs = (
        build => $build,
        wgs_build => $wgs_build,
        exome_build => $exome_build,
        tumor_rnaseq_build => $tumor_rnaseq_build,
        normal_rnaseq_build => $normal_rnaseq_build,
        working_dir => $data_directory,
        common_name => $final_name,
        verbose => 1,
    );

    my $patient_dir = $data_directory . "/" . $final_name;
    my @dirs = ($patient_dir);

    # summarize builds
    my $input_summary_dir = $patient_dir . "/input";
    push @dirs, $input_summary_dir;
    push @inputs, summarize_builds_outdir => $input_summary_dir;
    push @inputs, summarize_builds_log_file => $input_summary_dir . "/SummarizeBuilds.log.tsv";

    if ($build->id > 0) {
      push @inputs, summarize_builds_skip_lims_reports => 0;
    }else {
      #Watch out for -ve build IDs which will occur when the ClinSeq.t test is run.  In that case, do not run the LIMS reports
      push @inputs, summarize_builds_skip_lims_reports => 1;
    }

    # dump igv xml
    my $igv_session_dir = $patient_dir . '/igv';
    push @dirs, $igv_session_dir;
    push @inputs, igv_session_dir => $igv_session_dir;

    # Create mutation diagrams (lolliplots) for all Tier1 SNVs/Indels and compare to COSMIC SNVs/Indels
    if ($build->wgs_build or $build->exome_build) {
      my $mutation_diagram_dir = $patient_dir . '/mutation_diagrams';
      push @dirs, $mutation_diagram_dir;
      push @inputs, (
          mutation_diagram_outdir => $mutation_diagram_dir,
          mutation_diagram_collapse_variants=>1, 
          mutation_diagram_max_snvs_per_file=>750, 
          mutation_diagram_max_indels_per_file=>750
      );
    }

    #rnaseq analysis steps according to what rna-seq builds are defined as inputs
    if ($build->normal_rnaseq_build or $build->tumor_rnaseq_build){
      my $rnaseq_dir = $patient_dir . '/rnaseq';
      push @dirs, $rnaseq_dir;
      
      push @inputs, cufflinks_percent_cutoff => 1;
      
      #cufflinks expression absolute
      if ($build->normal_rnaseq_build){
        my $normal_rnaseq_dir = $rnaseq_dir . '/normal';
        push @dirs, $normal_rnaseq_dir;
        my $normal_cufflinks_expression_absolute_dir = $normal_rnaseq_dir . '/cufflinks_expression_absolute';
        push @dirs, $normal_cufflinks_expression_absolute_dir;
        push @inputs, normal_cufflinks_expression_absolute_dir => $normal_cufflinks_expression_absolute_dir;
      }
      if ($build->tumor_rnaseq_build){
        my $tumor_rnaseq_dir = $rnaseq_dir . '/tumor';
        push @dirs, $tumor_rnaseq_dir;
        my $tumor_cufflinks_expression_absolute_dir = $tumor_rnaseq_dir . '/cufflinks_expression_absolute';
        push @dirs, $tumor_cufflinks_expression_absolute_dir;
        push @inputs, tumor_cufflinks_expression_absolute_dir => $tumor_cufflinks_expression_absolute_dir;
      }

      #cufflink differential expression
      if ($build->normal_rnaseq_build and $build->tumor_rnaseq_build){
        my $cufflinks_differential_expression_dir = $rnaseq_dir . '/cufflinks_differential_expression';
        push @dirs, $cufflinks_differential_expression_dir;
        push @inputs, cufflinks_differential_expression_dir => $cufflinks_differential_expression_dir;
      }
    }

    #Perform clonality analysis and generate clonality plots
    if ($build->wgs_build){
      my $clonality_dir = $patient_dir . "/clonality/";
      push @dirs, $clonality_dir;
      push @inputs, clonality_dir => $clonality_dir;      
    }

    #Run cn-vew analysis
    if ($build->wgs_build){
      my $cnv_dir = $patient_dir . "/cnv/";
      push @dirs, $cnv_dir;
      push @inputs, cnv_dir => $cnv_dir;
    }

    #Summarize SV results
    if ($build->wgs_build){
      my $sv_dir = $patient_dir . "/sv/";
      push @dirs, $sv_dir;
      push @inputs, sv_dir => $sv_dir;
    }

    #Create mutation-spectrum results from WGS and exome results
    if ($build->wgs_build) {
        push @inputs, 'wgs_mutation_spectrum_outdir' => $patient_dir . '/mutation-spectrum';
        push @inputs, 'wgs_mutation_spectrum_datatype' => 'wgs';
    }
    if ($build->exome_build) {
        push @inputs, 'exome_mutation_spectrum_outdir' => $patient_dir . '/mutation-spectrum';
        push @inputs, 'exome_mutation_spectrum_datatype' => 'exome';
    }

    # For now it works to create directories here because the data_directory
    # has been allocated.  It is possible that this would not happen until
    # later, which would mess up assigning inputs to many of the commands.
    for my $dir (@dirs) {
        Genome::Sys->create_directory($dir);
    }

    return @inputs;
}

sub _resolve_workflow_for_build {
    # This is called by Genome::Model::Build::start()
    # Returns a Workflow::Operation
    my $self = shift;
    my $build = shift;
    my $lsf_queue = shift;   # TODO: the workflow shouldn't need this yet
    my $lsf_project = shift;

    if (!defined $lsf_queue || $lsf_queue eq '' || $lsf_queue eq 'inline') {
        $lsf_queue = 'apipe';
    }
    if (!defined $lsf_project || $lsf_project eq '') {
        $lsf_project = 'build' . $build->id;
    }

    # The wf system will call this method after we finish
    # but it consolidates logic to make a workflow which will
    # automatically take all inputs that method will assign.
    my %inputs = $self->map_workflow_inputs($build);
    my @input_properties = sort keys %inputs;
   
    # This must be updated for each new tool added which is "terminal" in the workflow!
    # (too bad it can't just be inferred from a dynamically expanding output connector)
    my @output_properties = qw(
        main_result
        summarize_builds_result
        igv_session_result
    );

    if ($build->wgs_build) {
        push @output_properties, qw( 
            summarize_wgs_tier1_snv_support_result
            summarize_svs_result
            summarize_cnvs_result
            wgs_mutation_spectrum_result
            clonality_result
            run_cn_view_result
        );
    }

    if ($build->exome_build) {
        push @output_properties, qw(
            summarize_exome_tier1_snv_support_result
            exome_mutation_spectrum_result
        );
    }

    if ($build->wgs_build and $build->exome_build) {
        push @output_properties, 'summarize_wgs_exome_tier1_snv_support_result';
    }

    if ($build->wgs_build or $build->exome_build) {
        push @output_properties, 'mutation_diagram_result';
    }

    if ($build->normal_rnaseq_build){
        push @output_properties, 'normal_cufflinks_expression_absolute_result';
    }

    if ($build->tumor_rnaseq_build){
        push @output_properties, 'tumor_cufflinks_expression_absolute_result';
    }

    if ($build->normal_rnaseq_build and $build->tumor_rnaseq_build){
        push @output_properties, 'cufflinks_differential_expression_result';
    }


    # Make the workflow and some convenience wrappers for adding steps and links

    my $workflow = Workflow::Model->create(
        name => $build->workflow_name,
        input_properties => \@input_properties, 
        output_properties => \@output_properties,
    );

    my $log_directory = $build->log_directory;
    $workflow->log_dir($log_directory);

    my $input_connector = $workflow->get_input_connector;
    my $output_connector = $workflow->get_output_connector;

    my %steps_by_name; 
    my $step = 0;
    my $add_step = sub {
        my ($name, $cmd) = @_;

        if (substr($cmd,0,2) eq '::') {
            $cmd = 'Genome::Model::ClinSeq::Command' . $cmd;
        }
        
        unless ($cmd->can("execute")) {
            die "bad command $cmd!";
        }

        die "$name already used!" if $steps_by_name{$name};

        my $op = $workflow->add_operation(
            name => $name,
            operation_type => Workflow::OperationType::Command->create(
                command_class_name => $cmd,
            )
        );
        $op->operation_type->lsf_queue($lsf_queue);
        $op->operation_type->lsf_project($lsf_project);
        $steps_by_name{$name} = $op;
        return $op;
    };

    my $converge;

    my $add_link = sub {
        my ($from_op, $from_p, $to_op, $to_p) = @_;
        $to_p = $from_p if not defined $to_p;
        
        if (ref($to_p) eq 'ARRAY') {
            Carp::confess("the 'to' property in a link cannot be a list!");
        }

        my $link;
        if (ref($from_p) eq 'ARRAY') {
            my $cname = "(combine @$from_p for \"" . $to_op->name . "$to_p\")";
            my $converge_op = $converge->($cname,$from_op,$from_p);
            $link = $workflow->add_link(
                left_operation => $converge_op,
                left_property => 'outputs',
                right_operation => $to_op,
                right_property => $to_p
            );
        }
        else {
            $link = $workflow->add_link(
                left_operation => $from_op,
                left_property => $from_p,
                right_operation => $to_op,
                right_property => $to_p
            );
        }
        $link or die "Failed to make link from $link from $from_p to $to_p!";
        return $link;
    };

    my $combo_cnt = 0;
    $converge = sub {
        my $cname = shift;
        my @params1 = @_;
        my @params2 = @_;

        # make a friendly name
        my $name = '';
        my $combo_cnt++;
        my $input_count = 0;
        while (@params1) {
            my $from_op = shift @params1;
            my $from_props = shift @params1;
            unless ($from_props) {
                die "expected \$op2,['p1','p2',...],\$op2,['p3','p4'],...";
            }
            unless (ref($from_props) eq 'ARRAY') {
                die "expected the second param (and every even param) in converge to be an arrayref of property names"; 
            }
            $input_count += scalar(@$from_props);
            if ($name) {
                $name .= " and ";
            }
            else {
                $name = "combine ($combo_cnt): ";
            }
            if ($from_op->name eq 'input_conector') {
                $name = "($combo_cnt)";
            }
            else {
                $name .= $from_op->name . "(";
            }
            for my $p (@$from_props) {
                $name .= $p;
                $name .= "," unless $p eq $from_props->[-1];
            }
            $name .= ")";
        }
        my $op = $workflow->add_operation(
            name => $cname,
            operation_type => Workflow::OperationType::Converge->create(
                input_properties => [ map { "i$_" } (1..$input_count) ],
                output_properties => ['outputs'],
            )
        );
        
        # create links
        my $input_n = 0;
        while (@params2) {
            my $from_op = shift @params2;
            my $from_props = shift @params2;
            for my $from_prop (@$from_props) {
                $input_n++;
                $add_link->(
                    $from_op,
                    $from_prop,
                    $op,
                    "i$input_n"
                );
            }
        }

        # return the op which will have a single "output"
        return $op;
    };
  
    #
    # Add steps which go in parallel with the Main step before setting up Main.
    # This will ensure testing goes more quickly because these will happen first.
    #
    

    #Summarize build inputs using SummarizeBuilds.pm
    my $msg = "Creating a summary of input builds using summarize-builds";
    my $summarize_builds_op = $add_step->($msg, "Genome::Model::ClinSeq::Command::SummarizeBuilds");
    $add_link->($input_connector, 'build', $summarize_builds_op, 'builds');
    $add_link->($input_connector, 'summarize_builds_outdir', $summarize_builds_op, 'outdir');
    $add_link->($input_connector, 'summarize_builds_skip_lims_reports', $summarize_builds_op, 'skip_lims_reports');
    $add_link->($input_connector, 'summarize_builds_log_file', $summarize_builds_op, 'log_file');
    $add_link->($summarize_builds_op, 'result', $output_connector, 'summarize_builds_result');

    #Create mutation spectrum results for wgs data
    if ($build->wgs_build) {
        $msg = "Creating mutation spectrum results for wgs snvs using create-mutation-spectrum";
        my $create_mutation_spectrum_wgs_op = $add_step->($msg, 'Genome::Model::ClinSeq::Command::CreateMutationSpectrum');
        $add_link->($input_connector, 'wgs_build', $create_mutation_spectrum_wgs_op, 'build');
        $add_link->($input_connector, 'wgs_mutation_spectrum_outdir', $create_mutation_spectrum_wgs_op, 'outdir');
        $add_link->($input_connector, 'wgs_mutation_spectrum_datatype', $create_mutation_spectrum_wgs_op, 'datatype');
        $add_link->($create_mutation_spectrum_wgs_op, 'result', $output_connector, 'wgs_mutation_spectrum_result')
    }

    #Create mutation spectrum results for exome data
    if ($build->exome_build) {
        $msg = "Creating mutation spectrum results for exome snvs using create-mutation-spectrum";
        my $create_mutation_spectrum_exome_op = $add_step->($msg, 'Genome::Model::ClinSeq::Command::CreateMutationSpectrum');
        $add_link->($input_connector, 'exome_build', $create_mutation_spectrum_exome_op, 'build');
        $add_link->($input_connector, 'exome_mutation_spectrum_outdir', $create_mutation_spectrum_exome_op, 'outdir');
        $add_link->($input_connector, 'exome_mutation_spectrum_datatype', $create_mutation_spectrum_exome_op, 'datatype');
        $add_link->($create_mutation_spectrum_exome_op, 'result', $output_connector, 'exome_mutation_spectrum_result')
    }

    #Create mutation diagrams (lolliplots) for all Tier1 SNVs/Indels and compare to COSMIC SNVs/Indels
    if ($build->wgs_build or $build->exome_build) {
        my $msg = "Creating mutation-diagram plots";
        my $mutation_diagram_op = $add_step->($msg, "Genome::Model::ClinSeq::Command::CreateMutationDiagrams");
        $DB::single = 1;
        if ($build->wgs_build and $build->exome_build) {
            $add_link->($input_connector,['wgs_build','exome_build'], $mutation_diagram_op, 'builds');
        }
        elsif ($build->wgs_build) {
            $add_link->($input_connector,'wgs_build',$mutation_diagram_op,'builds');
        }
        elsif ($build->exome_build) {
            $add_link->($input_connector,'exome_build',$mutation_diagram_op,'builds');
        }
        else {
            die "impossible!";
        }
        $add_link->($mutation_diagram_op,'result',$output_connector,'mutation_diagram_result');
        
        for my $p (qw/outdir collapse_variants max_snvs_per_file max_indels_per_file/) {
            my $input_name = 'mutation_diagram_' . $p;
            $add_link->($input_connector,$input_name,$mutation_diagram_op,$p);
        }
    }


    #Run cufflinks expression absolute analysis on normal
    my $normal_cufflinks_expression_absolute_op;
    if ($build->normal_rnaseq_build){
      my $msg = "Performing cufflinks expression absolute analysis for normal sample";
      $normal_cufflinks_expression_absolute_op = $add_step->($msg, 'Genome::Model::ClinSeq::Command::CufflinksExpressionAbsolute');
      $add_link->($input_connector, 'normal_rnaseq_build', $normal_cufflinks_expression_absolute_op, 'build');
      $add_link->($input_connector, 'normal_cufflinks_expression_absolute_dir', $normal_cufflinks_expression_absolute_op, 'outdir');
      $add_link->($input_connector, 'cufflinks_percent_cutoff', $normal_cufflinks_expression_absolute_op, 'percent_cutoff');
      $add_link->($normal_cufflinks_expression_absolute_op, 'result', $output_connector, 'normal_cufflinks_expression_absolute_result'); 
    }

    #Run cufflinks expression absolute analysis on tumor
    my $tumor_cufflinks_expression_absolute_op;
    if ($build->tumor_rnaseq_build){
      my $msg = "Performing cufflinks expression absolute analysis for tumor sample";
      $tumor_cufflinks_expression_absolute_op = $add_step->($msg, 'Genome::Model::ClinSeq::Command::CufflinksExpressionAbsolute');
      $add_link->($input_connector, 'tumor_rnaseq_build', $tumor_cufflinks_expression_absolute_op, 'build');
      $add_link->($input_connector, 'tumor_cufflinks_expression_absolute_dir', $tumor_cufflinks_expression_absolute_op, 'outdir');
      $add_link->($input_connector, 'cufflinks_percent_cutoff', $tumor_cufflinks_expression_absolute_op, 'percent_cutoff');
      $add_link->($tumor_cufflinks_expression_absolute_op, 'result', $output_connector, 'tumor_cufflinks_expression_absolute_result');
    }

    #Run cufflinks differential expression
    if ($build->normal_rnaseq_build and $build->tumor_rnaseq_build){
      my $msg = "Performing cufflinks differential expression analysis for case vs. control (e.g. tumor vs. normal)";
      my $cufflinks_differential_expression_op = $add_step->($msg, 'Genome::Model::ClinSeq::Command::CufflinksDifferentialExpression');
      $add_link->($input_connector, 'normal_rnaseq_build', $cufflinks_differential_expression_op, 'control_build');
      $add_link->($input_connector, 'tumor_rnaseq_build', $cufflinks_differential_expression_op, 'case_build');
      $add_link->($input_connector, 'cufflinks_differential_expression_dir', $cufflinks_differential_expression_op, 'outdir');
      $add_link->($cufflinks_differential_expression_op, 'result', $output_connector, 'cufflinks_differential_expression_result');
    }

    #Create IGV xml session files with increasing numbers of tracks and store in a single (WGS and Exome BAM files, RNA-seq BAM files, junctions.bed, SNV bed files, etc.)
    #genome model clin-seq dump-igv-xml --outdir=/gscuser/mgriffit/ --builds=119971814
    $msg = "Create IGV XML session files for varying levels of detail using the input builds";
    my $igv_session_op = $add_step->($msg, "Genome::Model::ClinSeq::Command::DumpIgvXml");
    $add_link->($input_connector, 'build', $igv_session_op, 'builds');
    $add_link->($input_connector, 'igv_session_dir', $igv_session_op, 'outdir');
    $add_link->($igv_session_op, 'result', $output_connector, 'igv_session_result'); 

    #Run clonality analysis and produce clonality plots
    $msg = "Run clonality analysis and produce clonality plots";
    my $clonality_op;
    if ($build->wgs_build){
      $clonality_op = $add_step->($msg, "Genome::Model::ClinSeq::Command::GenerateClonalityPlots");
      $add_link->($input_connector, 'wgs_build', $clonality_op, 'somatic_var_build');
      $add_link->($input_connector, 'clonality_dir', $clonality_op, 'output_dir');
      $add_link->($input_connector, 'common_name', $clonality_op, 'common_name');
      $add_link->($clonality_op, 'result', $output_connector, 'clonality_result'); 
    }

    #Produce copy number results with run-cn-view.  Relies on clonality step already having been run
    my $run_cn_view_op;
    if ($build->wgs_build){
      $msg = "Use gmt copy-number cn-view to produce copy number tables and images";
      $run_cn_view_op = $add_step->($msg, "Genome::Model::ClinSeq::Command::RunCnView");
      $add_link->($input_connector, 'wgs_build', $run_cn_view_op, 'build');
      $add_link->($input_connector, 'cnv_dir', $run_cn_view_op, 'outdir');
      $add_link->($clonality_op, 'cnv_hmm_file', $run_cn_view_op);
      $add_link->($run_cn_view_op, 'result', $output_connector, 'run_cn_view_result');
    }
   
    #Generate a summary of CNV results, copy cnvs.hq, cnvs.png, single-bam copy number plot PDF, etc. to the cnv directory
    #This step relies on the generate-clonality-plots step already having been run 
    #It also relies on run-cn-view step having been run already
    if ($build->wgs_build){
        my $msg = "Summarize CNV results from WGS somatic variation";
        my $summarize_cnvs_op = $add_step->($msg, "Genome::Model::ClinSeq::Command::SummarizeCnvs");
        $add_link->($input_connector, 'cnv_dir', $summarize_cnvs_op, 'outdir');
        $add_link->($input_connector, 'wgs_build', $summarize_cnvs_op, 'build');
        $add_link->($clonality_op, 'cnv_hmm_file', $summarize_cnvs_op);
        $add_link->($run_cn_view_op, 'gene_amp_file', $summarize_cnvs_op);
        $add_link->($run_cn_view_op, 'gene_del_file', $summarize_cnvs_op);
        $add_link->($summarize_cnvs_op, 'result', $output_connector, 'summarize_cnvs_result');
    }

    #Generate a summary of SV results from the WGS SV results
    if ($build->wgs_build){
        my $msg = "Summarize SV results from WGS somatic variation";
        my $summarize_svs_op = $add_step->($msg, "Genome::Model::ClinSeq::Command::SummarizeSvs");
        $add_link->($input_connector, 'wgs_build', $summarize_svs_op, 'builds');
        $add_link->($input_connector, 'sv_dir', $summarize_svs_op, 'outdir');
        $add_link->($summarize_svs_op, 'result', $output_connector, 'summarize_svs_result');
    }


    #
    # Main contains all of the original clinseq non-parallel code.
    # Re-factor out pieces which are completely independent, or which are at the end first.
    #

    my $main_op = $add_step->("ClinSeq Main", "Genome::Model::ClinSeq::Command::Main");
    for my $in (qw/ 
        build
        wgs_build
        exome_build
        tumor_rnaseq_build
        normal_rnaseq_build
        working_dir
        common_name
        verbose
    /) {
        $add_link->($input_connector, $in, $main_op, $in);
    }
    $add_link->($main_op, 'result', $output_connector, 'main_result');



    #
    # Add steps which follow the main step...
    # As we refactor start with things which do not feed into anything else down-stream,
    # or which only feed into things which have already been broken-out.
    #

    #For each of the following: WGS SNVs, Exome SNVs, and WGS+Exome SNVs, do the following:
    #Get BAM readcounts for WGS (tumor/normal), Exome (tumor/normal), RNAseq (tumor), RNAseq (normal) - as available of course
    #TODO: Break this down to do direct calls to GetBamReadCounts instead of wrapping it.
    for my $run (qw/wgs exome wgs_exome/) {
        if ($run eq 'wgs' and not $build->wgs_build) {
            next;
        }
        if ($run eq 'exome' and not $build->exome_build) {
            next;
        }
        if ($run eq 'wgs_exome' and not ($build->wgs_build and $build->exome_build)) {
            next;
        }
        my $txt_name = $run;
        $txt_name =~ s/_/ plus /g;
        $txt_name =~ s/wgs/WGS/;
        $txt_name =~ s/exome/Exome/;
        $msg = "$txt_name Summarize Tier 1 SNV Support (BAM read counts)";
        my $summarize_tier1_snv_support_op = $add_step->($msg, "Genome::Model::ClinSeq::Command::SummarizeTier1SnvSupport");
        $add_link->($main_op, $run . "_positions_file", $summarize_tier1_snv_support_op);
        $add_link->($main_op, 'wgs_build', $summarize_tier1_snv_support_op);
        $add_link->($main_op, 'exome_build', $summarize_tier1_snv_support_op);
        $add_link->($main_op, 'tumor_rnaseq_build', $summarize_tier1_snv_support_op);
        $add_link->($main_op, 'normal_rnaseq_build', $summarize_tier1_snv_support_op);
        if ($build->tumor_rnaseq_build){
          $add_link->($tumor_cufflinks_expression_absolute_op, 'tumor_fpkm_file', $summarize_tier1_snv_support_op);
        }
        $add_link->($main_op, 'verbose', $summarize_tier1_snv_support_op);
        $add_link->($summarize_tier1_snv_support_op, 'result', $output_connector, "summarize_${run}_tier1_snv_support_result");
    }

    # REMINDER:
    # For new steps be sure to add their result to the output connector if they do not feed into another step.
    # When you do that, expand the list of output properties at line 182 above. 

    my @errors = $workflow->validate();
    if (@errors) {
        for my $error (@errors) {
            $self->error_message($error);
        }
        die "Invalid workflow!";
    }

    return $workflow;
}

sub _infer_candidate_subjects_from_input_models {
    my $self = shift;
    my %subjects;
    for my $input_model (
        $self->wgs_model,
        $self->exome_model,
        $self->tumor_rnaseq_model,
        $self->normal_rnaseq_model,
    ) {
        next unless $input_model;
        my $patient;
        if ($input_model->subject->isa("Genome::Individual")) {
            $patient = $input_model->subject;
        }
        else {
            $patient = $input_model->subject->patient;
        }
        $subjects{ $patient->id } = $patient;

        # this will only work when the subject is an original tissue
        next;

        my $tumor_model;
        if ($input_model->can("tumor_model")) {
            $tumor_model = $input_model->tumor_model;
        }
        else {
            $tumor_model = $input_model;
        }
        $subjects{ $tumor_model->subject_id } = $tumor_model->subject;
    }
    my @subjects = sort { $a->id cmp $b->id } values %subjects;
    return @subjects;
}

sub _resolve_resource_requirements_for_build {
  #Set LSF parameters for the ClinSeq job
  my $lsf_resource_string = "-R 'select[model!=Opteron250 && type==LINUX64] rusage[tmp=10000:mem=4000]' -M 4000000";
  return($lsf_resource_string);
}

# This is implemented here until refactoring is done on the model/build API
# It ensures that when the CI server compares two clinseq builds it ignores the correct files.
# Keep it in sync with the diff conditions in ClinSeq.t.
sub files_ignored_by_build_diff {
    return qw(
        build.xml
        reports/Build_Initialized/report.xml
        reports/Build_Succeeded/report.xml
        logs/.*
        .*.R$
        .*.pdf$
        .*.jpg$
        .*.jpeg$
        .*.png$
        .*/summary/rc_summary.stderr$
        .*._COSMIC.svg$
        .*.clustered.data.tsv$
        .*.SummarizeBuilds.log.tsv$
        .*.DumpIgvXml.log.txt
        .*/mutation_diagrams/cosmic.mutation-diagram.stderr
        .*/mutation_diagrams/somatic.mutation-diagram.stderr
        .*.sequence-context.stderr
        .*.annotate.stderr
        .*/mutation-spectrum/exome/summarize_mutation_spectrum/summarize-mutation-spectrum.stderr
        .*/mutation-spectrum/wgs/summarize_mutation_spectrum/summarize-mutation-spectrum.stderr
        .*LIMS_Sample_Sequence_QC_library.tsv
    );
};

1;

