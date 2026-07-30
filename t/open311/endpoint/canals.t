package Open311::Endpoint::Integration::Sugar::Dummy;
use Moo;

extends 'Open311::Endpoint::Integration::Sugar';

package main;

use strict; use warnings;

use utf8;

use Test::More;
use Path::Tiny;
use Open311::Endpoint::Service::UKCouncil;
BEGIN { $ENV{TEST_MODE} = 1; }

my $canals_endpoint = Open311::Endpoint::Integration::Sugar::Dummy->new(
    jurisdiction_id => 'canals_sugar',
    config_file => path(__FILE__)->sibling("canals.yml")->stringify,
    );

subtest "GET Service List" => sub {
    my $res = $canals_endpoint->run_test_request( GET => '/services.xml' );
    ok $res->is_success, 'xml success';
};


done_testing;
