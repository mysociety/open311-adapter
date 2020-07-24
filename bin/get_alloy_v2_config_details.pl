#!/usr/bin/env perl

BEGIN {
    use File::Basename qw(dirname);
    use File::Spec;
    my $d = dirname(File::Spec->rel2abs($0));
    require "$d/../setenv.pl";
}

use Try::Tiny;

use Integrations::AlloyV2;
use feature qw/say/;

my $config = shift;

die "Please provide a config name\n" unless $config;

my $i = Integrations::AlloyV2->new(config_filename => $config);

die "Please add an API key to the config\n" unless $i->config->{api_key};

unless ( $i->config->{rfs_design} ) {
    my $inspections = $i->api_call(
        call => 'design',
        params => { query => 'inspection' }
    );

    #TODO page results
    say "possible inspection designs:";
    for my $inspection ( @{ $inspections->{results} } ) {
        say sprintf('%s: %s',
            $inspection->{design}->{name},
            $inspection->{design}->{code}
        )
    }

    exit;
}

my $inspection = $i->get_designs;

my $inspection_attrib = $i->design_attributes_to_hash($inspection);

say "inspection attributes";
say $_ . ': ' . $inspection_attrib->{$_}->{code}
    for keys %$inspection_attrib;

if ( $inspection_attrib->{'Status'}->{linked_code} ) {
    my $code = $inspection_attrib->{Status}->{linked_code};

    my $query = {
        properties =>  {
            dodiCode => $code,
        },
    };

    my $results = $i->search( $query, 1 );

    say "";
    say "inspection statuses";

    for my $status ( @$results ) {
        say sprintf('%s: %s', $status->{title}, $status->{itemId});
    }
} else {
    say "Can't work out what the status design is to get status details";
}

if ( $inspection_attrib->{'Reason for Closure'}->{linked_code} ) {
    my $code = $inspection_attrib->{'Reason for Closure'}->{linked_code};

    my $query = {
        properties =>  {
            dodiCode => $code,
        },
    };

    my $results = $i->search( $query, 1 );

    say "";
    say "reasons for closure";

    for my $status ( @$results ) {
        say sprintf('%s: %s', $status->{title}, $status->{itemId});
    }
} else {
    say "Can't work out what the reason for closure design is to get reason for closure details";
}

if ( $inspection_attrib->{'FMS Contact'}->{linked_code} ) {
    say "";
    say "contact design is " . $inspection_attrib->{'FMS Contact'}->{linked_code};

    my $contact = $i->api_call(call => 'design/' . $inspection_attrib->{'FMS Contact'}->{linked_code});
    my $contact_attrib = $i->design_attributes_to_hash($contact);

    say "";
    say "contact attributes";
    say $_ . ': ' . $contact_attrib->{$_}->{code}
        for keys %$contact_attrib;
} else {
    say "Can't work out what the contact design is to get contact details";
}

if ( $inspection_attrib->{Category}->{linked_code} ) {
    $query = {
        properties =>  {
            dodiCode => $inspection_attrib->{Category}->{linked_code},
        },
    };

    say "";
    say "Category design: " . $inspection_attrib->{Category}->{linked_code};

    $results = $i->search( $query, 1 );

    say "";
    say "category codes";
    for my $cat ( @$results ) {
        say sprintf('%s: %s', $cat->{title}, $cat->{itemId});
    }
} else {
    say "Can't work out what the category design is to get categories";
}
