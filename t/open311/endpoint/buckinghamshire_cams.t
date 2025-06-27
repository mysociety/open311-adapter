package Integrations::Rest::Dummy;

use Moo;

extends 'Integrations::Rest';

sub _build_config_file { path(__FILE__)->sibling("buckinghamshire_cams.yml")->stringify };

package Open311::Endpoint::Integration::Cams::Dummy;

use Moo;

extends 'Open311::Endpoint::Integration::Cams';

has integration_class => (
    is => 'ro',
    default => 'Integrations::Rest::Dummy',
);

package main;

use strict; use warnings;

use utf8;

use Test::More;

use Path::Tiny;
use Open311::Endpoint::Service::UKCouncil;

BEGIN { $ENV{TEST_MODE} = 1; }

my $bucks_endpoint = Open311::Endpoint::Integration::Cams::Dummy->new(
    jurisdiction_id => 'buckinghamshire_cams',
    config_file => path(__FILE__)->sibling("buckinghamshire_cams.yml")->stringify,
    );

subtest "GET Service List" => sub {
    my $res = $bucks_endpoint->run_test_request( GET => '/services.xml' );
    ok $res->is_success, 'xml success';
};

subtest "Check services structure" => sub {
    my @services = $bucks_endpoint->services;
    ok scalar @services == 3, 'Three services received';
    for my $test (
        {
            service_code => '9',
            service_name => 'Alignment/Path Off Line',
        },
        {
            service_code => 'I273',
            service_name => 'Bridge/Missing',
        },
        {
            service_code => 'I274',
            service_name => 'Damaged Bridge',
        },
    ) {
        my $contact = shift @services;
        ok $contact->{service_code} eq $test->{service_code}, 'Correct service code';
        ok $contact->{service_name} eq $test->{service_name}, 'Correct service name';
        ok $contact->{group} eq 'Public Rights of Way', 'Correct group';
        my @hidden_fields = ('AdminArea', 'LinkCode', 'LinkType');
        for my $attribute (grep { $_->{automated} eq 'hidden_field' } @{$contact->{attributes}}) {
            ok $attribute->code eq shift @hidden_fields;
        };
    };
};

done_testing;
