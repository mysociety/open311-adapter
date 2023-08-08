use strict;
use warnings;

BEGIN { $ENV{TEST_MODE} = 1 };

use Open311::Endpoint::Integration::UK::Gloucestershire;
use Test::More;

my $class = Open311::Endpoint::Integration::UK::Gloucestershire->new;

subtest process_service_request_args => sub {
    my $args = {
        attributes => {
            description => 'Ash Tree located on private land

Report details',
            fixmystreet_id => '2157',
            report_url => 'http://gloucestershire.localhost:3000/report/2157',
            title      => 'Report title',
        },
        description => 'title: Report title

detail: Report details

url: http://gloucestershire.localhost:3000/report/2157

Submitted via FixMyStreet
',
    };

    is_deeply $class->process_service_request_args($args), {
        attributes => {
            fixmystreet_id => '2157',
        },

        description => 'Report title',
        location => 'Ash Tree located on private land

Report details',
        report_url => 'http://gloucestershire.localhost:3000/report/2157',
        site_code => '99999999',
    };
};

done_testing();
