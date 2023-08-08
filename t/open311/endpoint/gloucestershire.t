use strict;
use warnings;

BEGIN { $ENV{TEST_MODE} = 1 };

use Open311::Endpoint::Integration::UK::Gloucestershire;
use Test::More;

my $class = Open311::Endpoint::Integration::UK::Gloucestershire->new(
    config_data => <<HERE,
default_site_code: 123456
HERE
);

subtest process_service_request_args => sub {
    my $args = {
        attributes => {
            description =>
                'Less deep than a golf ball, smaller than a dinner plate | Report title',
            fixmystreet_id => '2157',
            location       => 'Report detail',
            report_url => 'http://gloucestershire.localhost:3000/report/2157',
            title => 'Should ultimately populate description',
        },
        description  => 'Should be overridden by attributes description',
        service_code => 'pothole_road',
    };

    is_deeply $class->process_service_request_args($args), {
        attributes => { fixmystreet_id => '2157' },

        description =>
            'Less deep than a golf ball, smaller than a dinner plate | Report title',
        location     => 'Report detail',
        report_url   => 'http://gloucestershire.localhost:3000/report/2157',
        service_code => 'pothole_road',
        site_code    => '123456',
    };
};

done_testing();
