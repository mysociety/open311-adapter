#!/usr/bin/env perl

use JSON::MaybeXS;
use Path::Tiny;

use feature qw/say/;

my $file = shift;
my $resource_id = shift;

my @lines = path($file)->lines;

my @resources;
foreach my $line (@lines) {
    if ($line =~ /results":\[/) {
        chomp($line);
        $line =~ s/(\[[^\]]*\]) [^{\[]*([{\[])/$2/;
        my $json = decode_json($line);
        for my $result ( @{ $json->{results} } ) {
            if ( $result->{resourceId} eq $resource_id ) {
                push @resources, encode_json($result);
            }
        }
    }
}

say '[' . join( ",\n", @resources ) . ']';
