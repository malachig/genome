package Genome::Model::Tools::EpitopePrediction::FrameShift;

use strict;
use warnings;

use Genome;
use Workflow;
use Carp;

class Genome::Model::Tools::EpitopePrediction::FrameShift {
    is  => ['Genome::Model::Tools::EpitopePrediction::Base'],
    doc => '',
    has => [
        bed_file => {
            is  => 'Text',
            doc => '',
        },
        vcf_file => {
            is  => 'Text',
            doc => '',
        },
        database_directory => {
            is  => 'Text',
            doc => '',
        },
        output_directory => {
            is  => 'Text',
            doc => '',
        },
    ],
};

sub execute {
    my $self = shift;

    my $filename = $self->bed_file;
    my $dir = $self->database_directory;
    my $filename_vcf_somatic = $self->vcf_file;

    my $out_dir = $self->output_directory;
    Genome::Sys->create_directory($out_dir);

    my %mapping = (
        "TTT" => "F",
        "TTC" => "F",
        "TTA" => "L",
        "TTG" => "L",
        "CTT" => "L",
        "CTC" => "L",
        "CTA" => "L",
        "CTG" => "L",
        "ATT" => "I",
        "ATC" => "I",
        "ATA" => "I",
        "ATG" => "M",
        "GTT" => "V",
        "GTC" => "V",
        "GTA" => "V",
        "GTG" => "V",

        "TCT" => "S",
        "TCC" => "S",
        "TCA" => "S",
        "TCG" => "S",
        "CCT" => "P",
        "CCC" => "P",
        "CCA" => "P",
        "CCG" => "P",
        "ACT" => "T",
        "ACC" => "T",
        "ACA" => "T",
        "ACG" => "T",
        "GCT" => "A",
        "GCC" => "A",
        "GCA" => "A",
        "GCG" => "A",

        "TAT" => "Y",
        "TAC" => "Y",
        "TAA" => "*",
        "TAG" => "*",
        "CAT" => "H",
        "CAC" => "H",
        "CAA" => "Q",
        "CAG" => "Q",
        "AAT" => "N",
        "AAC" => "N",
        "AAA" => "K",
        "AAG" => "K",
        "GAT" => "D",
        "GAC" => "D",
        "GAA" => "E",
        "GAG" => "E",

        "TGT" => "C",
        "TGC" => "C",
        "TGA" => "*",
        "TGG" => "W",
        "CGT" => "R",
        "CGC" => "R",
        "CGA" => "R",
        "CGG" => "R",
        "AGT" => "S",
        "AGC" => "S",
        "AGA" => "R",
        "AGG" => "R",
        "GGT" => "G",
        "GGC" => "G",
        "GGA" => "G",
        "GGG" => "G"
    );

    open( OUT,     ">$out_dir/proteome-indel.fasta" );
    open( OUT_MOD, ">$out_dir/proteome-indel-mod.fasta" );

    open( LOG,     ">$out_dir/proteome-indel.log" );
    open( LOG_MOD, ">$out_dir/proteome-mod-indel.log" );
    open( STAT,    ">$out_dir/proteome-mod-indel.stat" );

    my (%chr, %bed);
    my $ifh = Genome::Sys->open_file_for_reading($filename);
    while (my $line = $ifh->getline) {
        chomp $line;
        my @fields = split("\t", $line);
        my $chr  = $fields[0];
        my $name = $fields[3];
        $bed{$name} = $line;
        $chr{$chr} .= "#$name#";
    }
    $ifh->close;

    my (%vcf_old, %vcf_new, %vcf_type, %vcf_anno);
    my $vcf_ifh = Genome::Sys->open_file_for_reading($filename_vcf_somatic);
    while (my $line = $vcf_ifh->getline ) {
        chomp($line);
        print $line, "\n";
        my @fields = split("\t", $line);
        my $chr  = "chr" . $fields[0];
        my $pos  = $fields[1];
        my $id   = $fields[2];
        my $old  = $fields[3];
        my $new  = $fields[4];
        my $qaul = $fields[5];
        my $anno = $fields[6];
        my $type = $fields[7];
        $pos--;
        $new =~ s/\,.*$//;    #####
        print "pos=$pos", "\t", "id=$id", "\t", "old=$old", "\t",
        "new=$new", "\t", "qaul=$qaul", "\t", "anno=$anno", "\t",
        "type=$type", "\n";

        $vcf_old{"$chr#$pos"} = $old;
        $vcf_new{"$chr#$pos"} = $new;
        if ( $type eq "SOMATIC" ) { $vcf_type{"$chr#$pos"} = "S"; }
        else                      { $vcf_type{"$chr#$pos"} = "G"; }

        $vcf_anno{"$chr#$pos"} = $anno;
    }
    $vcf_ifh->close;

    foreach my $chr ( sort keys %chr ) {

        print qq!$chr\n!;
        my $database_fh = Genome::Sys->open_file_for_reading("$dir/$chr.fa");
        print qq!opened $chr\n!;
        my $sequence = "";
        my $line = $database_fh->getline;
        chomp($line);
        my $chr_ = $chr;
        $chr_ =~ s/^chr//i;
        if ( $line =~ /^>$chr\s*/ or $line =~ /^>$chr_\s*/ ) {
            while ( $line = $database_fh->getline ) {
                chomp($line);
                if ( $line =~ /^>/ ) {
                    print LOG qq!Error: > not expected: $line\n!;
                }
                else {
                    $line =~ s/\s+//g;
                    if ( $line !~ /^[atcgATCGnN]+$/ ) {
                        print LOG
                        qq!Error: unexpected character: $line\n!;
                    }
                    else {
                        $sequence .= "\U$line";
                    }
                }
            }
            my $temp = $chr{$chr};
            my %seq_chr_pos;

            while ( $temp =~ s/^#([^#]+)#// ) {
                my $name     = $1;
                my $modified = 0;

                if ( $bed{$name} =~
                    /^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$/
                )
                {
                    my $start                    = $2;
                    my $end                      = $3;
                    my $strand                   = $6;
                    my $num                      = $10;
                    my $segment_lengths          = "$11,";
                    my $segment_starts           = "$12,";
                    my $segment_lengths_extended = "$11,";
                    my $segment_starts_extended  = "$12,";

                    my $seq_original     = "";
                    my $segment_starts_  = $segment_starts;
                    my $segment_lengths_ = $segment_lengths;
                    my $accu_c           = 0;
                    while ( $segment_starts_ =~ s/^([0-9\-]+)\,// ) {
                        my $segment_start = $1;
                        if ( $segment_lengths_ =~ s/^([0-9]+)\,// ) {
                            my $segment_length = $1;

                            my $seq_ = substr $sequence,
                            $start + $segment_start, $segment_length;
                            for (
                                my $pos = 1 ;
                                $pos <= $segment_length ;
                                $pos++
                            )
                            {
                                $seq_chr_pos{$accu_c} =
                                $start + $segment_start + $pos - 1;
                                $accu_c++;
                            }
                            $seq_original .= $seq_;

                        }
                        else {
                            print LOG qq!Error parsing $bed{$name}\n!;
                        }
                    }

                    my $seq             = $seq_original;
                    my $seq_original_rc = reverse $seq_original;
                    $seq_original_rc =~ tr/ATCG/TAGC/;

                    my $description_        = "";
                    my %variants            = ();
                    my %variants_           = ();
                    my %variants2           = ();
                    my %variants2_          = ();
                    my $variant_loc         = "";
                    my $seqment_lengths_sum = 0;
                    my $seqment_count       = 0;
                    my $num_indel           = 0;
                    my $segment_start_first = 0;

                    $segment_start_first = 0;

                    for (
                        my $i = length($seq_original) - 1 ;
                        $i >= 0 ;
                        $i--
                    )
                    {
                        my $var_pos = $seq_chr_pos{$i};

                        if ( defined $vcf_old{"$chr#$var_pos"} ) {

                            print $name,    "\n";
                            print $var_pos, "\n";
                            print $vcf_old{"$chr#$var_pos"}, "\n";
                            print $vcf_new{"$chr#$var_pos"}, "\n";

                            my $leno;
                            my $lenn;
                            if ( $vcf_old{"$chr#$var_pos"} eq "-" ) {
                                $leno = 0;
                            }
                            else {
                                $leno =
                                length( $vcf_old{"$chr#$var_pos"} );
                            }
                            if ( $vcf_new{"$chr#$var_pos"} eq "-" ) {
                                $lenn = 0;
                            }
                            else {
                                $lenn =
                                length( $vcf_new{"$chr#$var_pos"} );
                            }
                            $num_indel++;
                            my $inframe;
                            if ( abs( $leno - $lenn ) % 3 == 0 ) {
                                $inframe = 1;
                            }
                            else { $inframe = 0; }
                            if ( $strand =~ /\-/ ) {

                                if ( $vcf_new{"$chr#$var_pos"} eq "-" )
                                {
                                    my $rev_pos =
                                    length($seq_original) -
                                    $i -
                                    $leno;
                                    my $left_3 = ( $rev_pos + 1 ) % 3;
                                    my $int_3s =
                                    int( ( $rev_pos + 1 ) / 3 ) + 1;
                                    my $int_3e = int(
                                        ( $rev_pos + $leno + 1 ) / 3 ) +
                                    1;
                                    if ( $inframe == 1 ) {
                                        $description_ .=
                                        "(DEL:" 
                                        . $chr . "-"
                                        . $var_pos . "-"
                                        . $leno . "-"
                                        . $vcf_type{"$chr#$var_pos"}
                                        . ":"
                                        . $int_3s
                                        . "in_frame_del";
                                    }
                                    else {
                                        $description_ .=
                                        "(DEL:" 
                                        . $chr . "-"
                                        . $var_pos . "-"
                                        . $leno . "-"
                                        . $vcf_type{"$chr#$var_pos"}
                                        . ":"
                                        . $int_3s . "fs";
                                    }
                                }

                                else {
                                    my $rev_pos =
                                    length($seq_original) -
                                    $i -
                                    $leno;
                                    my $left_3 = ( $rev_pos + 1 ) % 3;
                                    my $int_3s =
                                    int( ( $rev_pos + 1 ) / 3 ) + 1;
                                    my $int_3e = int(
                                        ( $rev_pos + $lenn + 1 ) / 3 ) +
                                    1;
                                    if ( $inframe == 1 ) {
                                        $description_ .=
                                        "(INS:" 
                                        . $chr . "-"
                                        . $var_pos . "-"
                                        . $lenn . "-"
                                        . $vcf_type{"$chr#$var_pos"}
                                        . ":"
                                        . $int_3s . "-"
                                        . $int_3e
                                        . "in_frame_ins";
                                    }
                                    else {
                                        $description_ .=
                                        "(INS:" 
                                        . $chr . "-"
                                        . $var_pos . "-"
                                        . $lenn . "-"
                                        . $vcf_type{"$chr#$var_pos"}
                                        . ":"
                                        . $int_3s . "fs";
                                    }
                                }

                            }

                            else {
                                if ( $vcf_new{"$chr#$var_pos"} eq "-" )
                                {
                                    my $left_3 = ( $i + 1 ) % 3;

                                    my $int_3s =
                                    int( ( $i + 1 ) / 3 ) + 1;

                                    my $int_3e =
                                    int( ( $i + $leno + 1 ) / 3 ) + 1;
                                    if ( $inframe == 1 ) {
                                        $description_ .=
                                        "(DEL:" 
                                        . $chr . "-"
                                        . $var_pos . "-"
                                        . $leno . "-"
                                        . $vcf_type{"$chr#$var_pos"}
                                        . ":"
                                        . $int_3s
                                        . "in_frame_del";
                                    }
                                    else {
                                        $description_ .=
                                        "(DEL:" 
                                        . $chr . "-"
                                        . $var_pos . "-"
                                        . $leno . "-"
                                        . $vcf_type{"$chr#$var_pos"}
                                        . ":"
                                        . $int_3s . "fs";
                                    }
                                }
                                else {
                                    my $left_3 = ( $i + 1 ) % 3;
                                    my $int_3s =
                                    int( ( $i + 1 ) / 3 ) + 1;
                                    my $int_3e =
                                    int( ( $i + $lenn + 1 ) / 3 ) + 1;
                                    if ( $inframe == 1 ) {
                                        $description_ .=
                                        "(INS:" 
                                        . $chr . "-"
                                        . $var_pos . "-"
                                        . $lenn . "-"
                                        . $vcf_type{"$chr#$var_pos"}
                                        . ":"
                                        . $int_3s . "-"
                                        . $int_3e
                                        . "in_frame_ins";
                                    }
                                    else {
                                        $description_ .=
                                        "(INS:" 
                                        . $chr . "-"
                                        . $var_pos . "-"
                                        . $lenn . "-"
                                        . $vcf_type{"$chr#$var_pos"}
                                        . ":"
                                        . $int_3s . "fs";
                                    }
                                }
                            }


                            my $seql = substr( $seq, 0, $i );
                            print $seql, "\n";
                            my $seqr =
                            substr( $seq, $i + $leno,
                                length($seq) - length($seql) - $leno );

                            if ( $lenn >= 1 ) {
                                $seq =
                                $seql
                                . $vcf_new{"$chr#$var_pos"}
                                . $seqr;
                            }
                            else { $seq = $seql . $seqr; }
                        }
                    }

                    my $name_ = $name;
                    $name_ =~ s/\-[^\-]+$//;

                    my $protein          = "";
                    my $protein_original = "";

                    if ( $strand =~ /\-/ ) {
                        my $seq_ = reverse $seq;
                        $seq = $seq_;
                        $seq =~ tr/ATCG/TAGC/;
                        $seq_         = reverse $seq_original;
                        $seq_original = $seq_;
                        $seq_original =~ tr/ATCG/TAGC/;
                    }

                    for (
                        my $n = 0 ;
                        $n < length($seq_original) ;
                        $n = $n + 3
                    )
                    {
                        my $triplet = substr( $seq_original, $n, 3 );
                        if ( length($triplet) == 3 ) {
                            if ( $mapping{$triplet} !~ /[\w\*]/ ) {
                                $mapping{$triplet} = "X";
                            }
                            $protein_original .= $mapping{$triplet};
                        }
                    }

                    my $stop_found    = 0;
                    my $triplet_count = 0;

                    for (
                        my $n = 0 ;
                        $n < length($seq) and $stop_found == 0 ;
                        $n = $n + 3
                    )
                    {
                        my $n_ = $n + 2;

                        my $triplet = substr( $seq, $n, 3 );
                        if ( length($triplet) == 3 ) {

                            if ( $mapping{$triplet} !~ /[\w\*]/ ) {
                                $mapping{$triplet} = "X";
                            }

                            if ( $mapping{$triplet} =~ /\*/ ) {
                                $stop_found = 1;
                            }
                            $protein .= $mapping{$triplet};
                        }

                        $triplet_count++;
                    }

                    $protein_original =~ s/\*$//;

                    if ( $protein_original =~ /^([^\*]+)\*.*$/ ) {
                        print LOG
                        qq!Error: Stop codon found in middle of sequence:$name \n$protein_original\n!;
                        $protein_original = "";
                    }

                    $protein =~ s/\*$//;
                    $protein =~ s/^([^\*]+)\*.*$//;

                    if (   ( $protein ne $protein_original )
                        && ( $num_indel == 1 ) )
                    {

                        print "original protein\n";
                        print $protein_original, "\n";
                        print "modified protein\n";
                        print $protein, "\n";

                        if ( length($protein) > 6
                                and $protein !~ /^\*/ )
                        {
                            print OUT
                            qq!>$name (MAP:$chr:$start$strand $segment_lengths $segment_starts)\n$protein_original\n!;
                            $description_ .= ")";

                            print OUT_MOD
                            qq!>$name-indel (MAP:$chr:$start$strand $segment_lengths $segment_starts) $description_\n$protein\n!;
                        }

                    }

                }
                else { print LOG qq!Error parsing $bed{$name}\n!; }
            }
        }
        else { print LOG qq!Error in name $chr: $line\n!; }

        $database_fh->close;
    }
    print STAT qq!
    done; 
    !;
    print STAT
    qq!\nnumber of modifications\tnumber of proteins\tnumber of proteins (somatic variants)\n!;

    close(OUT);
    close(OUT_MOD);

    close(LOG);
    close(LOG_MOD);
    close(STAT);
}
