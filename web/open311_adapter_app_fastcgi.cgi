#!/usr/bin/env perl

use strict;
use warnings;

BEGIN {
    use File::Basename qw(dirname);
    use File::Spec;
    my $d = dirname(File::Spec->rel2abs($0));
    require "$d/../setenv.pl";
}

# LWP::Protocol::https defaults to Mozilla::CA, which is out of date and
# doesn't include special intermediate certificates we've manually added
# to our server. So set LWP to look in the system store instead.
$ENV{PERL_LWP_SSL_CA_PATH} = '/etc/ssl/certs';

use Open311::Endpoint::Integration::UK;
Open311::Endpoint::Integration::UK->run;
