#!/usr/bin/perl -w

use English;
use warnings;
use strict;
use Carp qw(carp cluck croak confess);
use Getopt::Long qw( :config posix_default bundling no_ignore_case );
use POSIX qw(ceil floor);
use List::Util qw[min max];
use Cwd 'abs_path';
use Cwd;

use cworld::dekker;

sub check_options {
    my $opts = shift;

    my ($inputMatrix,$verbose,$output,$loessObjectFile,$excludeCis,$excludeTrans,$cisAlpha,$cisApproximateFactor,$disableIQRFilter,$minDistance,$maxDistance,$excludeZero);
    
    if( exists($opts->{ inputMatrix }) ) {
        $inputMatrix = $opts->{ inputMatrix };
    } else {
        print STDERR "\nERROR: Option inputMatrix|i is required.\n";
        help();
    }
    
    if( exists($opts->{ verbose }) ) {
        $verbose = 1;
    } else {
        $verbose = 0;
    }
    
    if( exists($opts->{ output }) ) {
        $output = $opts->{ output };
    } else {
        $output = "";
    }
    
    if( exists($opts->{ loessObjectFile }) ) {
        $loessObjectFile = $opts->{ loessObjectFile };
    } else {
        $loessObjectFile="";
    }
    
    if( exists($opts->{ excludeCis }) ) {
        $excludeCis=1;
    } else {
        $excludeCis=0;
    }
    
    if( exists($opts->{ excludeTrans }) ) {
        $excludeTrans=1;
    } else {
        $excludeTrans=0;
    }
    
    if( exists($opts->{ cisAlpha }) ) {
        $cisAlpha = $opts->{ cisAlpha };
    } else {        
        $cisAlpha=0.01;
    }    
    
    if( exists($opts->{ cisApproximateFactor }) ) {
        $cisApproximateFactor = $opts->{ cisApproximateFactor };
    } else {
        $cisApproximateFactor=1000;
    }
    
    
    if( exists($opts->{ disableIQRFilter }) ) {
        $disableIQRFilter = 1;
    } else {
        $disableIQRFilter=0;
    }
     
    if( exists($opts->{ minDistance }) ) {
        $minDistance = $opts->{ minDistance };
    } else {
        $minDistance=undef;
    }
    
    if( exists($opts->{ maxDistance }) ) {
        $maxDistance = $opts->{ maxDistance };
    } else {
        $maxDistance = undef;
    }
    
    if( exists($opts->{ excludeZero }) ) {
        $excludeZero = 1;
    } else {
        $excludeZero = 0;
    }
    
    return($inputMatrix,$verbose,$output,$loessObjectFile,$excludeCis,$excludeTrans,$cisAlpha,$cisApproximateFactor,$disableIQRFilter,$minDistance,$maxDistance,$excludeZero);
}

sub intro() {
    print STDERR "\n";
    
    print STDERR "Tool:\t\tfillMissingData.pl\n";
    print STDERR "Version:\t".$cworld::dekker::VERSION."\n";
    print STDERR "Summary:\treplace NAs with expected signals\n";
    
    print STDERR "\n";
}

sub help() {
    intro();
    
    print STDERR "Usage: perl fillMissingData.pl [OPTIONS] -i <inputMatrix>\n";
    
    print STDERR "\n";
    
    print STDERR "Required:\n";
    printf STDERR ("\t%-10s %-10s %-10s\n", "-i", "[]", "input matrix file");
    
    print STDERR "\n";
    print STDERR "Options:\n";
    printf STDERR ("\t%-10s %-10s %-10s\n", "-v", "[]", "FLAG, verbose mode");
    printf STDERR ("\t%-10s %-10s %-10s\n", "-o", "[]", "prefix for output file(s)");
    printf STDERR ("\t%-10s %-10s %-10s\n", "--lof", "[]", "optional loess object file (pre-calculated loess)");   
    printf STDERR ("\t%-10s %-10s %-10s\n", "--ec", "[]", "FLAG, exclude CIS data");
    printf STDERR ("\t%-10s %-10s %-10s\n", "--et", "[]", "FLAG, exclude TRANS data");
    printf STDERR ("\t%-10s %-10s %-10s\n", "--ca", "[0.01]", "lowess alpha value, fraction of datapoints to smooth over");
    printf STDERR ("\t%-10s %-10s %-10s\n", "--dif", "[]", "FLAG, disable loess IQR (outlier) filter");
    printf STDERR ("\t%-10s %-10s %-10s\n", "--caf", "[1000]", "cis approximate factor to speed up loess, genomic distance / -caffs");
    printf STDERR ("\t%-10s %-10s %-10s\n", "--minDist", "[]", "minimum allowed interaction distance, exclude < N distance (in BP)");
    printf STDERR ("\t%-10s %-10s %-10s\n", "--maxDist", "[]", "maximum allowed interaction distance, exclude > N distance (in BP)");
    printf STDERR ("\t%-10s %-10s %-10s\n", "--ez", "[]", "FLAG, ignore 0s in all calculations");
    print STDERR "\n";
    
    print STDERR "Notes:";
    print STDERR "
    This script can fill NAs with the lowess expected.
    Matrix can be TXT or gzipped TXT.
    See website for matrix format details.\n";
    
    print STDERR "\n";
    
    print STDERR "Contact:
    Bryan R. Lajoie
    Dekker Lab 2015
    https://github.com/blajoie/cworld-dekker
    http://my5C.umassmed.edu";
    
    print STDERR "\n";
    print STDERR "\n";
    
    exit;
}

sub fillMissingData($$$;$) {
    #required
    my $matrixObject=shift;
    my $matrix=shift;
    my $loess=shift;
    #optional
    my $cisApproximateFactor=1;
    $cisApproximateFactor=shift if @_;
    
    my $inc2header=$matrixObject->{ inc2header };
    my $numYHeaders=$matrixObject->{ numYHeaders };
    my $numXHeaders=$matrixObject->{ numXHeaders };
    my $missingValue=$matrixObject->{ missingValue };
    my $symmetrical=$matrixObject->{ symmetrical };

    my $filledMatrix={};
    
    my ($y,$x);
    for(my $y=0;$y<$numYHeaders;$y++) {
        my $yHeader=$inc2header->{ y }->{$y};
        my $yHeaderObject=getHeaderObject($yHeader);
        for(my $x=0;$x<$numXHeaders;$x++) {
            my $xHeader=$inc2header->{ x }->{$x};    
            my $xHeaderObject=getHeaderObject($xHeader);
            
            next if(($symmetrical) and ($y > $x));
            
            my $interactionDistance=getInteractionDistance($matrixObject,$yHeaderObject,$xHeaderObject,$cisApproximateFactor);
        
            my $cScore=$matrixObject->{ missingValue };
            $cScore=$matrix->{$y}->{$x} if(defined($matrix->{$y}->{$x}));
                
            $cScore = "NA" if($cScore eq ""); 
            $cScore = "NA" if(($cScore =~ /^NULL$/i) or ($cScore =~ /^NA$/i) or ($cScore =~ /inf$/i) or ($cScore =~ /^nan$/i));
            
            
            if( ( ($cScore eq $missingValue) or (($cScore ne "NA") and ($missingValue ne "NA") and ($cScore == 0))) and (exists($loess->{$interactionDistance}->{ loess })) ) {
                
                my $loessValue=$loess->{$interactionDistance}->{ loess };
                my $loessStdev=$loess->{$interactionDistance}->{ stdev };
                
                my $stdevRange=($loessStdev*2);
                $cScore=$loessValue+rand($stdevRange)-$loessStdev;
            }
            
            $filledMatrix->{$y}->{$x}=$cScore;
            $filledMatrix->{$x}->{$y}=$cScore if($symmetrical);

        }
    }
    
    return($filledMatrix);

}

my %options;
my $results = GetOptions( \%options,'inputMatrix|i=s','verbose|v','output|o=s','loessObjectFile|lof=s','excludeCis|ec','excludeTrans|et','cisAlpha|ca=f','cisApproximateFactor|caf=i','disableIQRFilter|dif','minDistance|minDist=i','maxDistance|maxDist=i','excludeZero|ez') or croak help();

my ($inputMatrix,$verbose,$output,$loessObjectFile,$excludeCis,$excludeTrans,$cisAlpha,$cisApproximateFactor,$disableIQRFilter,$minDistance,$maxDistance,$excludeZero)=check_options( \%options );

intro() if($verbose);

#get the absolute path of the script being used
my $cwd = getcwd();
my $fullScriptPath=abs_path($0);
my @fullScriptPathArr=split(/\//,$fullScriptPath);
@fullScriptPathArr=@fullScriptPathArr[0..@fullScriptPathArr-3];
my $scriptPath=join("/",@fullScriptPathArr);

croak "inputMatrix [$inputMatrix] does not exist" if(!(-e $inputMatrix));

# get matrix information
my $matrixObject=getMatrixObject($inputMatrix,$output,$verbose);
my $inc2header=$matrixObject->{ inc2header };
my $header2inc=$matrixObject->{ header2inc };
my $numYHeaders=$matrixObject->{ numYHeaders };
my $numXHeaders=$matrixObject->{ numXHeaders };
my $missingValue=$matrixObject->{ missingValue };
my $symmetrical=$matrixObject->{ symmetrical };
my $inputMatrixName=$matrixObject->{ inputMatrixName };
$output=$matrixObject->{ output };

my $includeCis=flipBool($excludeCis);
my $includeTrans=flipBool($excludeTrans);

# get matrix data
my ($matrix)=getData($inputMatrix,$matrixObject,$verbose,$minDistance,$maxDistance,$excludeCis,$excludeTrans);

print STDERR "\n" if($verbose);

# calculate LOWESS smoothing for cis data

croak "loessObjectFile [$loessObjectFile] does not exist" if( ($loessObjectFile ne "") and (!(-e $loessObjectFile)) );

my $loessMeta="";
$loessMeta .= "--ic" if($includeCis);
$loessMeta .= "--it" if($includeTrans);
$loessMeta .= "--maxDist".$maxDistance if(defined($maxDistance));
$loessMeta .= "--ez" if($excludeZero);
$loessMeta .= "--caf".$cisApproximateFactor;
$loessMeta .= "--ca".$cisAlpha;
$loessMeta .= "--dif" if($disableIQRFilter);
my $loessFile=$output.$loessMeta.".loess.gz";
$loessObjectFile=$output.$loessMeta.".loess.object.gz" if($loessObjectFile eq "");

my $inputDataCis=[];
my $inputDataTrans=[];
if(!validateLoessObject($loessObjectFile)) {
    # dump matrix data into input lists (CIS + TRANS)
    print STDERR "seperating cis/trans data...\n" if($verbose);
    ($inputDataCis,$inputDataTrans)=matrix2inputlist($matrixObject,$matrix,$includeCis,$includeTrans,$minDistance,$maxDistance,$excludeZero,$cisApproximateFactor);
    croak "$inputMatrixName - no avaible CIS data" if((scalar @{ $inputDataCis } <= 0) and ($includeCis) and ($includeTrans == 0));
    croak "$inputMatrixName - no avaible TRANS data" if((scalar @{ $inputDataTrans } <= 0) and ($includeTrans) and ($includeCis == 0));
    print STDERR "\n" if($verbose);
}

# init loess object [hash]
my $loess={};

# calculate cis-expected
$loess=calculateLoess($matrixObject,$inputDataCis,$loessFile,$loessObjectFile,$cisAlpha,$disableIQRFilter,$excludeZero);

# plot cis-expected
system("Rscript '".$scriptPath."/R/plotLoess.R' '".$cwd."' '".$loessFile."' > /dev/null") if(scalar @{ $inputDataCis } > 0);

# calculate cis-expected
$loess=calculateTransExpected($inputDataTrans,$excludeZero,$loess,$loessObjectFile,$verbose);

# fill matrix
print STDERR "filling NAs ...\n" if($verbose);
my $filledMatrix=fillMissingData($matrixObject,$matrix,$loess,$cisApproximateFactor);
my $filledFile=$output.".filled.matrix.gz";
writeMatrix($filledMatrix,$inc2header,$filledFile,$missingValue);
$filledMatrix={};
print STDERR "\tdone\n" if($verbose);

print STDERR "\n" if($verbose);