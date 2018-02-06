#!/usr/bin/env perl

use strict;
use warnings;

BEGIN {
    use File::Basename qw(dirname);
    use File::Spec;
    my $d = dirname(File::Spec->rel2abs($0));
    require "$d/../setenv.pl";
}

use Open311::Endpoint::Integration::UK;
Open311::Endpoint::Integration::UK->run;
